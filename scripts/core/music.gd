extends Node
## Music (autoload): the owner's jazz, by time of day, with slow crossfades.
## Morning + afternoon: day_coffee_jazz. Evening + night: evening_relax_jazz.
## Settings live in GameState.flags: "music_on" (bool), "music_volume" (0..1).
## On the web, sound starts after the first tap (browser rule); Godot resumes audio automatically.

const TRACKS := {
	"day": "res://assets/music/day_coffee_jazz.mp3",
	"evening": "res://assets/music/evening_relax_jazz.mp3",
}
const FADE := 3.0
const BASE_DB := -8.0

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _current := ""
var _streams := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_a = AudioStreamPlayer.new(); _b = AudioStreamPlayer.new()
	for p in [_a, _b]:
		p.volume_db = -80.0
		add_child(p)
	for k in TRACKS:
		if ResourceLoader.exists(TRACKS[k]):
			var s = load(TRACKS[k])
			if s is AudioStreamMP3: s.loop = true
			_streams[k] = s
	GameState.time_changed.connect(_on_time)
	_pick()

func _on_time(_d: int, _m: float) -> void: _pick()

func enabled() -> bool: return bool(GameState.flags.get("music_on", true))
func volume() -> float: return clampf(float(GameState.flags.get("music_volume", 0.7)), 0.0, 1.0)

func set_enabled(on: bool) -> void:
	GameState.flags["music_on"] = on; GameState.save_soon()
	_apply_volume()
func set_volume(v: float) -> void:
	GameState.flags["music_volume"] = clampf(v, 0.0, 1.0); GameState.save_soon()
	_apply_volume()

func _target_db() -> float:
	if not enabled() or volume() <= 0.001: return -80.0
	return BASE_DB + linear_to_db(volume())

func _apply_volume() -> void:
	var live := _a if _a.playing and _a.volume_db > -60.0 else _b
	if live.playing: live.volume_db = _target_db()

func _pick() -> void:
	var slot := GameState.time_slot()
	var want := "day" if slot == "morning" or slot == "afternoon" else "evening"
	if want == _current or not _streams.has(want): return
	_current = want
	# crossfade: the quiet player takes the new track
	var incoming := _b if _a.playing and _a.volume_db > -60.0 else _a
	var outgoing := _a if incoming == _b else _b
	incoming.stream = _streams[want]
	incoming.volume_db = -60.0
	incoming.play()
	var t := create_tween().set_parallel(true)
	t.tween_property(incoming, "volume_db", _target_db(), FADE)
	if outgoing.playing:
		t.tween_property(outgoing, "volume_db", -80.0, FADE)
		t.chain().tween_callback(outgoing.stop)

func _exit_tree() -> void:
	for p in [_a, _b]:
		if is_instance_valid(p):
			p.stop(); p.stream = null
	_streams.clear()
