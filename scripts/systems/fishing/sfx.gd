extends Node
## Tiny procedural sound kit for fishing (no audio files needed).
## Sounds: plip, plop, splash, plunge, tick, snap, catch, whoosh, warn, sparkle, miss.

const RATE := 22050
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build()

func play(id: String, pitch := 1.0, db := 0.0) -> void:
	if not _streams.has(id) or _players.is_empty(): return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[id]; p.pitch_scale = clampf(pitch, 0.3, 3.0); p.volume_db = db
	p.play()

func _build() -> void:
	_streams["plip"] = _wav(_sweep(0.09, 760.0, 1500.0, 0.45))
	_streams["plop"] = _wav(_mix([_sweep(0.14, 380.0, 900.0, 0.45), _noise(0.12, 0.22, 30.0, 0.35)]))
	_streams["splash"] = _wav(_noise(0.5, 0.55, 6.5, 0.14))
	_streams["plunge"] = _wav(_mix([_sweep(0.28, 190.0, 55.0, 0.8), _noise(0.32, 0.45, 9.0, 0.22)]))
	_streams["tick"] = _wav(_mix([_sweep(0.03, 2600.0, 2100.0, 0.22), _noise(0.02, 0.2, 200.0, 0.9)]))
	_streams["snap"] = _wav(_mix([_sweep(0.32, 1400.0, 150.0, 0.45), _noise(0.08, 0.6, 40.0, 0.9)]))
	_streams["whoosh"] = _wav(_whoosh(0.35))
	_streams["warn"] = _wav(_sweep(0.12, 540.0, 380.0, 0.3))
	_streams["catch"] = _wav(_chime([523.25, 659.25, 783.99, 1046.5], 0.085, 0.55, 0.3))
	_streams["sparkle"] = _wav(_chime([1568.0, 2093.0, 2637.0, 3136.0], 0.06, 0.35, 0.18))
	_streams["miss"] = _wav(_chime([392.0, 329.63], 0.13, 0.35, 0.25))

func _sweep(dur: float, f0: float, f1: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array(); out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f0 * pow(f1 / f0, t / dur)
		ph += TAU * f / RATE
		var env := minf(1.0, t * 500.0) * pow(1.0 - t / dur, 2.0)
		out[i] = sin(ph) * env * amp
	return out

func _noise(dur: float, amp: float, decay: float, bright: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array(); out.resize(n)
	var y := 0.0
	var rng := RandomNumberGenerator.new(); rng.seed = int(dur * 1000.0 + decay)
	for i in n:
		var t := float(i) / RATE
		y += bright * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * exp(-t * decay) * minf(1.0, t * 300.0) * amp * 2.0
	return out

func _whoosh(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array(); out.resize(n)
	var y := 0.0
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for i in n:
		var t := float(i) / dur / RATE
		var a := lerpf(0.04, 0.3, sin(PI * t))
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * sin(PI * t) * 0.9
	return out

func _chime(freqs: Array, step: float, dur: float, amp: float) -> PackedFloat32Array:
	var total := step * freqs.size() + dur
	var n := int(total * RATE)
	var out := PackedFloat32Array(); out.resize(n)
	for k in freqs.size():
		var f: float = freqs[k]
		var start := int(k * step * RATE)
		for i in range(start, mini(n, start + int(dur * RATE))):
			var t := float(i - start) / RATE
			var env := minf(1.0, t * 400.0) * exp(-t * 7.0)
			out[i] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * amp
	return out

func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts: n = maxi(n, p.size())
	var out := PackedFloat32Array(); out.resize(n)
	for p in parts:
		for i in p.size(): out[i] += p[i]
	return out

func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray(); data.resize(s.size() * 2)
	for i in s.size(): data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = RATE; w.stereo = false; w.data = data
	return w
