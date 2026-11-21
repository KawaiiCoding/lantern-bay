extends SceneTree
## Lantern Bay QA runner.
##
##   godot --headless --path /Users/hm/Desktop/files/dev/lantern-bay -s res://tests/test_runner.gd
##   godot --headless --path . -s res://tests/test_runner.gd -- only=core,data      (name filter)
##   godot --headless --path . -s res://tests/test_runner.gd -- fast=1              (skip slow tests)
##   godot --headless --path . -s res://tests/test_runner.gd -- list=1              (list tests only)
##
## Suites live in res://tests/suites/*.gd (extend res://tests/suite.gd). Every method named t_<name>
## is a test (may be a coroutine). The runner never references game parts statically, so a part with
## a parse error fails only the tests that need it. Engine errors (SCRIPT ERROR, push_error, ...) raised
## while a test runs are captured through a Logger and fail that test. Exit code 1 on any failure.
## The player's real save is backed up at start and restored at the end.

const MAIN_SCENE := "res://main.tscn"
const SUITE_DIR := "res://tests/suites/"
const SUITE_ORDER := ["core", "data", "eco", "int", "selftest"]
const TEST_TIMEOUT_MS := 150000
const SAVE_FILES := ["save.json", "save.bak.json", "save.json.tmp"]

class QALogger extends Logger:
	var mutex := Mutex.new()
	var errors: Array = []      # strings
	var warnings: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		var msg := code
		if rationale != "" and rationale != code: msg = ("%s - %s" % [code, rationale]) if code != "" else rationale
		var where := file.replace("res://", "") + ":" + str(line)
		if error_type == Logger.ERROR_TYPE_WARNING:
			mutex.lock(); warnings.append("%s (%s)" % [msg, where]); mutex.unlock()
			return
		var tag := "SCRIPT ERROR" if error_type == Logger.ERROR_TYPE_SCRIPT else "ERROR"
		mutex.lock(); errors.append("%s: %s (%s in %s)" % [tag, msg, where, function]); mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func take_errors() -> Array:
		mutex.lock(); var out := errors.duplicate(); errors.clear(); mutex.unlock()
		return out
	func take_warnings() -> Array:
		mutex.lock(); var out := warnings.duplicate(); warnings.clear(); mutex.unlock()
		return out

var gs: Node                  # GameState autoload
var dt: Node                  # Data autoload
var ib: Node                  # InputBridge autoload
var main: Node = null         # the loaded main.tscn instance (see ensure_main)
var args := {}
var logger := QALogger.new()

# per-test state (suites write through suite.gd helpers)
var cur_name := ""
var cur_fails: Array = []
var cur_warns: Array = []
var cur_notes: Array = []
var cur_skip := ""
var allow_errors: Array = []  # substrings of engine errors the current test expects (dropped, not failed)

var _tests: Array = []
var _results: Array = []
var _test_t0 := 0
var _run_t0 := 0
var _done := false
var _saved_files := {}
var _had_save := false
var _boot_warnings: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() == 2 else "1"
	# Other godot processes (teammates running the game) write the same user:// save files, which would race with
	# the save tests. Re-run ourselves under a private HOME so user:// is ours alone.
	if OS.get_environment("LB_QA_ISOLATED") != "1" and not args.has("noisolate") and OS.get_name() in ["macOS", "Linux"]:
		_relaunch_isolated()
		return
	gs = root.get_node_or_null("GameState")
	dt = root.get_node_or_null("Data")
	ib = root.get_node_or_null("InputBridge")
	if gs == null or dt == null or ib == null:
		print("FAIL  runner: autoloads missing (GameState/Data/InputBridge); check project.godot and the scripts for parse errors")
		quit(1)
		return
	OS.add_logger(logger)
	_run_t0 = Time.get_ticks_msec()
	_run()

func _relaunch_isolated() -> void:
	var home := OS.get_temp_dir().path_join("lantern_bay_qa_home")
	DirAccess.make_dir_recursive_absolute(home)
	var cmd: Array = ["HOME=" + home, "LB_QA_ISOLATED=1", OS.get_executable_path(), "--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/test_runner.gd", "--"]
	for a in OS.get_cmdline_user_args(): cmd.append(a)
	var out: Array = []
	var code := OS.execute("/usr/bin/env", cmd, out, true)
	for o in out: print(str(o).strip_edges(false, true))
	quit(code)

# Watchdog: a hung test (an await that never resolves) fails the run instead of hanging it.
func _process(_delta: float) -> bool:
	if _done or cur_name == "": return false
	if Time.get_ticks_msec() - _test_t0 > TEST_TIMEOUT_MS:
		_done = true
		print("FAIL  %s  (timed out after %d s; a coroutine never finished)" % [cur_name, TEST_TIMEOUT_MS / 1000])
		_results.append({"name": cur_name, "status": "FAIL", "msgs": ["timed out"]})
		_restore_save()
		_print_summary()
		quit(1)
	return false

# ------------------------------------------------------------------ main flow
func _run() -> void:
	_backup_save()
	_boot_warnings = logger.take_warnings()
	_collect_tests()
	if args.has("list"):
		for t in _tests: print(t.label)
		_finish(0)
		return
	print("Lantern Bay tests: %d tests, Godot %s, renderer %s" % [_tests.size(), Engine.get_version_info().string, str(RenderingServer.get_current_rendering_method())])
	gs.reset()
	for t in _tests:
		await _run_one(t)
	await free_main()
	_print_summary()
	_finish(1 if _count("FAIL") > 0 else 0)

func _finish(code: int) -> void:
	_done = true
	_restore_save()
	OS.remove_logger(logger)
	quit(code)

func _run_one(t: Dictionary) -> void:
	var label: String = t.label
	if not _selected(label, str(t.method)):
		return
	cur_name = label; cur_fails = []; cur_warns = []; cur_notes = []; cur_skip = ""; allow_errors = []
	logger.take_errors()
	_test_t0 = Time.get_ticks_msec()
	await t.suite.call(t.method)
	var ms := Time.get_ticks_msec() - _test_t0
	await _cleanup()
	var errs := _filter_errors(logger.take_errors())
	logger.take_warnings()
	for e in errs: cur_fails.append("engine: " + e)
	var status := "PASS"
	if cur_fails.size() > 0: status = "FAIL"
	elif cur_skip != "": status = "SKIP"
	var msgs: Array = []
	msgs.append_array(cur_fails)
	_results.append({"name": label, "status": status, "msgs": msgs, "warns": cur_warns.duplicate()})
	match status:
		"PASS": print("PASS  %s  (%d ms)" % [label, ms])
		"SKIP": print("SKIP  %s  (%s)" % [label, cur_skip])
		"FAIL": print("FAIL  %s  (%d ms)" % [label, ms])
	for m in cur_fails: print("        - " + m)
	for w in cur_warns: print("        warn: " + w)
	for n in cur_notes: print("        " + n)
	cur_name = ""

func _selected(label: String, method: String) -> bool:
	if args.has("fast") and method.contains("_slow"): return false
	if args.has("only"):
		var hit := false
		for s in str(args.only).split(",", false):
			if label.contains(s): hit = true
		if not hit: return false
	if args.has("skip"):
		for s in str(args.skip).split(",", false):
			if label.contains(s): return false
	return true

func _filter_errors(errs: Array) -> Array:
	var out: Array = []
	var seen := {}
	for e in errs:
		var s := str(e)
		var allowed := false
		for a in allow_errors:
			if s.contains(str(a)): allowed = true
		if allowed: continue
		if seen.has(s): continue
		seen[s] = true
		out.append(s)
		if out.size() >= 8: break
	return out

func _cleanup() -> void:
	ib.touch_move = Vector2.ZERO
	if ib.action_held: ib.release()
	Engine.time_scale = 1.0
	gs.set_paused(false)
	await process_frame

func _count(status: String) -> int:
	var n := 0
	for r in _results:
		if r.status == status: n += 1
	return n

func _print_summary() -> void:
	var warns := 0
	for r in _results: warns += int(r.get("warns", []).size())
	print("")
	print("SUMMARY: %d passed, %d failed, %d skipped, %d warnings  (%.1f s)" % [_count("PASS"), _count("FAIL"), _count("SKIP"), warns, (Time.get_ticks_msec() - _run_t0) / 1000.0])
	for r in _results:
		if r.status == "FAIL":
			print("  FAILED  %s" % r.name)
			for m in r.msgs: print("          " + str(m))
	if warns > 0:
		print("  WARNINGS (non-blocking)")
		for r in _results:
			for w in r.get("warns", []): print("          %s: %s" % [r.name, w])

# ------------------------------------------------------------------ suites
func _collect_tests() -> void:
	var files: Array = []
	for f in DirAccess.get_files_at(SUITE_DIR):
		if f.ends_with(".gd"): files.append(f.get_basename())
	var ordered: Array = []
	for s in SUITE_ORDER:
		if s in files: ordered.append(s)
	for f in files:
		if not (f in ordered): ordered.append(f)
	for sname in ordered:
		var path: String = SUITE_DIR + sname + ".gd"
		var scr = load(path)
		if scr == null or not scr.can_instantiate():
			_tests.append({"label": sname + "/_load", "method": "t__load_failed", "suite": _LoadFailed.new(sname)})
			continue
		var suite = scr.new()
		suite.setup(self)
		for m in scr.get_script_method_list():
			var mn: String = m.name
			if mn.begins_with("t_"):
				_tests.append({"label": sname + "/" + mn.substr(2), "method": mn, "suite": suite})

class _LoadFailed extends RefCounted:
	var sname := ""
	func _init(n: String) -> void: sname = n
	func t__load_failed() -> void:
		var r = Engine.get_main_loop()
		r.cur_fails.append("suite %s failed to load (parse error in tests/suites/%s.gd?)" % [sname, sname])

# ------------------------------------------------------------------ helpers for suites
func wait_frames(n: int) -> void:
	for i in n: await process_frame

func wait_sec(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < int(s * 1000.0): await process_frame

## Wait until cond.call() is true or timeout seconds pass; returns whether it became true.
func wait_until(cond: Callable, timeout: float = 3.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - t0) > int(timeout * 1000.0): return false
		await process_frame
	return true

## Load main.tscn once and reuse it. Returns null (and records a failure) if it cannot boot.
func ensure_main() -> Node:
	if is_instance_valid(main): return main
	return await fresh_main()

func fresh_main() -> Node:
	await free_main()
	var scn = load(MAIN_SCENE)
	if scn == null:
		cur_fails.append("cannot load " + MAIN_SCENE)
		return null
	main = scn.instantiate()
	root.add_child(main)
	await wait_frames(4)
	return main

func free_main() -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
		await process_frame
	main = null

## A part of main: "sky", "island", "player", "hud" or a system id ("cats", "fishing", ...). null when absent.
func part(id: String) -> Node:
	if not is_instance_valid(main): return null
	var v = null
	if id in ["sky", "island", "player", "hud"]:
		v = main.get(id)
	else:
		var sys = main.get("systems")
		if typeof(sys) == TYPE_DICTIONARY: v = sys.get(id, null)
	return v if (v != null and is_instance_valid(v)) else null

var _src_cache := {}
## Source text of every .gd (and .tscn when with_scenes) under res://, keyed by res:// path. Cached.
func sources(with_scenes := false) -> Dictionary:
	var key := "scn" if with_scenes else "gd"
	if _src_cache.has(key): return _src_cache[key]
	var files: Array = []
	_list_files("res://", [".gd", ".tscn"] if with_scenes else [".gd"], files)
	var out := {}
	for p in files: out[p] = FileAccess.get_file_as_string(p)
	_src_cache[key] = out
	return out

func _list_files(dir: String, exts: Array, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		for e in exts:
			if f.ends_with(e): out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d in ["build", "shots", "addons"]: continue
		_list_files(dir.path_join(d), exts, out)

func const_of(script_path: String, key: String, default = null):
	if not ResourceLoader.exists(script_path): return default
	var s = load(script_path)
	if s == null: return default
	return s.get_script_constant_map().get(key, default)

# ------------------------------------------------------------------ save backup
func _backup_save() -> void:
	for f in SAVE_FILES:
		var p: String = "user://" + f
		if FileAccess.file_exists(p):
			_saved_files[f] = FileAccess.get_file_as_bytes(p)
	_had_save = _saved_files.has("save.json")

func _restore_save() -> void:
	for f in SAVE_FILES:
		var p: String = "user://" + f
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for f in _saved_files.keys():
		var fa := FileAccess.open("user://" + str(f), FileAccess.WRITE)
		if fa != null:
			fa.store_buffer(_saved_files[f]); fa.close()
	# GameState saves itself on exit: make that write the player's own data back, not test data
	if _had_save: gs.load_game()
	else: gs.reset()
