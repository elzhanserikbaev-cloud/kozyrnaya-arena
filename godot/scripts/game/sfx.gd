extends Node
## Простые синтезированные звуки (без внешних файлов): мягкие «деревянные» щелчки, звон монет, удары.

var enabled := true
var _cache := {}
var _players: Array = []
const RATE := 22050

func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8
		add_child(p)
		_players.append(p)

func _tone(parts: Array) -> AudioStreamWAV:
	# parts: [[freq_from, freq_to, dur, vol, noise]]
	var data := PackedByteArray()
	var phase := 0.0
	for pt in parts:
		var n := int(RATE * float(pt[2]))
		for i in n:
			var t := float(i) / n
			var f: float = lerpf(pt[0], pt[1], t)
			phase += TAU * f / RATE
			var env := minf(1.0, t * 30.0) * pow(1.0 - t, 2.2)
			var s: float = sin(phase) * (1.0 - pt[4]) + randf_range(-1, 1) * pt[4]
			var v: int = int(clampf(s * env * pt[3], -1, 1) * 32000)
			data.append(v & 0xFF); data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w

## Тяжёлый каменный «бум»: низкий удар с затуханием, глухой грохот (сглаженный шум) и короткий щелчок камня.
func _stone(dur: float, f0: float, f1: float, vol: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var n := int(RATE * dur)
	var phase := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(f0, f1, minf(1.0, t / dur))
		phase += TAU * f / RATE
		var thud := sin(phase) * exp(-t * 14.0)
		var wn := randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.06
		lp2 += (lp - lp2) * 0.25
		var rumble := lp2 * 3.2 * exp(-t * 9.0)
		var click := wn * exp(-t * 160.0) * 0.35
		var env := minf(1.0, t * 400.0)
		var s: float = (thud * 0.85 + rumble + click) * env * vol
		var v: int = int(clampf(s, -1.0, 1.0) * 32000)
		data.append(v & 0xFF); data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w

func _stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	if name == "stone" or name == "stone_soft":
		var st := _stone(0.42, 82.0, 46.0, 0.78) if name == "stone" else _stone(0.26, 120.0, 70.0, 0.6)
		_cache[name] = st
		return st
	var parts: Array = {
		"buy": [[880, 1320, 0.09, 0.5, 0.0], [1320, 1760, 0.12, 0.4, 0.0]],
		"sell": [[700, 500, 0.12, 0.5, 0.0]],
		"place": [[220, 160, 0.08, 0.6, 0.35]],
		"reroll": [[400, 900, 0.16, 0.25, 0.6]],
		"level": [[523, 523, 0.1, 0.5, 0], [659, 659, 0.1, 0.5, 0], [784, 784, 0.18, 0.5, 0]],
		"cast": [[300, 900, 0.25, 0.35, 0.1]],
		"hit": [[180, 90, 0.09, 0.7, 0.5]],
		"death": [[200, 60, 0.35, 0.6, 0.3]],
		"feed": [[160, 80, 0.3, 0.6, 0.2], [500, 700, 0.15, 0.3, 0]],
		"win": [[523, 523, 0.12, 0.5, 0], [659, 659, 0.12, 0.5, 0], [784, 784, 0.12, 0.5, 0], [1046, 1046, 0.3, 0.5, 0]],
		"lose": [[392, 370, 0.2, 0.5, 0], [311, 290, 0.2, 0.5, 0], [262, 240, 0.4, 0.5, 0]],
		"draw": [[440, 440, 0.2, 0.4, 0], [440, 415, 0.25, 0.4, 0]],
	}.get(name, [[440, 440, 0.1, 0.3, 0]])
	var s := _tone(parts)
	_cache[name] = s
	return s

func play(name: String) -> void:
	if not enabled or DisplayServer.get_name() == "headless":
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = _stream(name)
			p.play()
			return
