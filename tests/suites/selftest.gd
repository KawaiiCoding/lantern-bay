extends "res://tests/suite.gd"
## Every system's own `-- test=<name>` self-test, run as a separate headless process (fixed 60 fps so it is fast).
## A self-test fails when it exits non-zero, times out, prints FAIL, or logs SCRIPT ERROR / Parse Error / ERROR.
## Methods are named t_slow_* so `fast=1` skips them.

const TIMEOUT_S := 90
const FRAMES := 4000
const IGNORE := ["resources still in use at exit", "ObjectDB instances were leaked", "Pages in use exist at exit", "were leaked at exit"]

func _run_one(args: Array, needs: Array) -> void:
	for path in needs:
		if not ResourceLoader.exists(path):
			skip("needs %s (not written yet)" % path.get_file()); return
	var cmd: Array = ["-e", "alarm shift; exec @ARGV", str(TIMEOUT_S), OS.get_executable_path(), "--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--quit-after", str(FRAMES), "--", "fresh=1"]
	cmd.append_array(args)
	var out: Array = []
	var code := OS.execute("/usr/bin/perl", cmd, out, true)
	var text := "\n".join(out)
	var bad: Array = []
	for line in text.split("\n"):
		var l := str(line)
		var ignored := false
		for ig in IGNORE:
			if l.contains(ig): ignored = true
		if ignored: continue
		if l.contains("SCRIPT ERROR") or l.contains("Parse Error") or l.begins_with("ERROR:") or (l.contains("FAIL") and not l.contains("failures: 0")) or l.contains("Invalid call") or l.contains("Invalid get index") or l.contains("Invalid set index"):
			bad.append(l.strip_edges().left(160))
	if code != 0 and code != 142: bad.append("exit code %d" % code)
	if code == 142: bad.append("timed out after %d s (no quit)" % TIMEOUT_S)
	var sig := " ".join(args)
	ok(bad.is_empty(), "self-test [%s]: %s" % [sig, " | ".join(bad.slice(0, 5))])
	if bad.is_empty(): note("self-test [%s] clean, %d lines of output" % [sig, text.split("\n").size()])

func t_slow_player() -> void: _run_one(["test=player"], ["res://scripts/player/player.gd"])
func t_slow_cats_logic() -> void: _run_one(["test=cats_logic"], ["res://scripts/systems/cats.gd"])
func t_slow_cats_scare() -> void: _run_one(["test=cats_scare"], ["res://scripts/systems/cats.gd"])
func t_slow_fishing_catch() -> void: _run_one(["test=fishing", "result=catch"], ["res://scripts/systems/fishing.gd"])
func t_slow_fishing_miss() -> void: _run_one(["test=fishing", "result=miss"], ["res://scripts/systems/fishing.gd"])
func t_slow_fishing_snap() -> void: _run_one(["test=fishing", "result=snap"], ["res://scripts/systems/fishing.gd"])
func t_slow_fishing_cancel() -> void: _run_one(["test=fishing", "result=cancel"], ["res://scripts/systems/fishing.gd"])
func t_slow_fishing_eager() -> void: _run_one(["test=fishing", "result=eager"], ["res://scripts/systems/fishing.gd"])
func t_slow_shore() -> void: _run_one(["test=shore"], ["res://scripts/systems/shore.gd"])
func t_slow_town() -> void: _run_one(["test=town"], ["res://scripts/systems/town.gd"])
func t_slow_town_buy_panel() -> void: _run_one(["test=town", "panel=buy"], ["res://scripts/systems/town.gd"])
func t_slow_town_board_panel() -> void: _run_one(["test=town", "panel=board"], ["res://scripts/systems/town.gd"])
func t_slow_lantern() -> void: _run_one(["test=lantern"], ["res://scripts/systems/lanterns.gd"])
func t_slow_ui() -> void: _run_one(["test=ui"], ["res://scripts/ui/hud.gd"])
func t_slow_people() -> void: _run_one(["test=people"], ["res://scripts/systems/people.gd"])
func t_slow_island() -> void: _run_one(["test=island"], ["res://scripts/world/island.gd"])
func t_slow_sky() -> void: _run_one(["test=sky"], ["res://scripts/world/sky_cycle.gd"])

## Any other `test=<name>` the sources understand but this list does not run: reported so nothing is silently untested.
func t_selftests_are_all_listed() -> void:
	var known := ["player", "cats", "cats_logic", "cats_scare", "fishing", "shore", "town", "shop", "board", "lantern", "ui", "icons", "people", "island", "sky"]
	var found := {}
	var rx := RegEx.create_from_string("test=([a-z_]+)")
	var rx2 := RegEx.create_from_string("get\\(\\s*\"test\"[^)]*\\)\\s*(?:==|in)\\s*\\[?\\s*\"([a-z_]+)\"")
	for path in r.sources(false).keys():
		var p := str(path)
		if p.begins_with("res://tests/") or p.begins_with("res://tools/"): continue
		var text: String = r.sources(false)[path]
		for m in rx.search_all(text): found[m.get_string(1)] = p
		for m in rx2.search_all(text): found[m.get_string(1)] = p
	var extra: Array = []
	for k in found.keys():
		if not (k in known): extra.append("%s (%s)" % [k, str(found[k]).replace("res://", "")])
	if not extra.is_empty(): warn("self-test names found in source but not run by tests/suites/selftest.gd: " + ", ".join(extra))
