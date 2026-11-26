extends Node
## Простые синтезированные звуки (без внешних файлов): мягкие «деревянные» щелчки, звон монет, удары.

var enabled := true
var music_on := true
var _music: Array = []          # два плеера для плавного перехода
var _music_cur := -1
var _music_name := ""
const MUSIC_DB_BASE := -11.0
var music_vol := 0.8
var sfx_vol := 0.9
var _cache := {}
var _players: Array = []
const RATE := 22050

func _ready() -> void:
	for i in 2:
		var mp := AudioStreamPlayer.new()
		mp.volume_db = -80
		add_child(mp)
		_music.append(mp)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8
		add_child(p)
		_players.append(p)
	_prewarm_fx.call_deferred()

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
	if FX_SOUNDS.has(name) or name.begins_with("spell_"):
		var fx := _fx_sound(name)
		if fx:
			_cache[name] = fx
			return fx
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

## Фоновая музыка: "menu" (главное меню) или "game" (партия). Плавный переход 1,6 с.
func music(name: String) -> void:
	if name == _music_name:
		return
	_music_name = name
	if DisplayServer.get_name() == "headless":
		return
	var path := "res://assets/music/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	var nxt := 0 if _music_cur != 0 else 1
	var p_new: AudioStreamPlayer = _music[nxt]
	var st: AudioStream = load(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	p_new.stream = st
	p_new.volume_db = -60
	p_new.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p_new, "volume_db", _music_db() if (music_on and enabled) else -80.0, 1.6)
	if _music_cur >= 0:
		var p_old: AudioStreamPlayer = _music[_music_cur]
		tw.tween_property(p_old, "volume_db", -60.0, 1.6)
		tw.chain().tween_callback(p_old.stop)
	_music_cur = nxt

func _music_db() -> float:
	return MUSIC_DB_BASE + linear_to_db(maxf(0.001, music_vol / 0.8))

## Громкость из настроек: 0..1 (музыка, звуки).
func set_volumes(mv: float, sv: float) -> void:
	music_vol = mv
	sfx_vol = sv
	for pl in _players:
		(pl as AudioStreamPlayer).volume_db = -8.0 + linear_to_db(maxf(0.001, sv / 0.9))
	if _music_cur >= 0:
		var p: AudioStreamPlayer = _music[_music_cur]
		p.volume_db = _music_db() if (music_on and enabled and mv > 0.01) else -80.0

func set_music_enabled(on: bool) -> void:
	music_on = on
	if _music_cur >= 0:
		var p: AudioStreamPlayer = _music[_music_cur]
		create_tween().tween_property(p, "volume_db", _music_db() if (music_on and enabled) else -80.0, 0.5)

func play(name: String) -> void:
	if not enabled or DisplayServer.get_name() == "headless":
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = _stream(name)
			p.play()
			return

# =================== звуки боевых эффектов (Fx) ===================
## Мягкие процедурные звуки стихий. Всё через фильтрованный шум и синусы с огибающими,
## без резкого «шипения» (шум всегда пропущен через ФНЧ), пик нормирован ≤ 0.72.
##   hit_ice hit_fire hit_light hit_nature hit_neutral crit heal shield freeze stun poison
##   buff_up buff_down revive soul whoosh victory_sting defeat_sting
##   spell_<ключ Data.MAGIC>: fireball heal bless rage freeze meteor surge pact curse chain revive venom guillotine
const FX_SOUNDS := ["hit_ice", "hit_fire", "hit_light", "hit_nature", "hit_neutral", "crit", "heal", "shield",
	"freeze", "stun", "poison", "buff_up", "buff_down", "revive", "soul", "whoosh", "victory_sting", "defeat_sting"]
const SPELL_SOUNDS := ["fireball", "heal", "bless", "rage", "freeze", "meteor", "surge", "pact", "curse",
	"chain", "revive", "venom", "guillotine"]

func _prewarm_fx() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# по одному звуку с паузами, чтобы синтез (~20–60 мс на звук) не давал заметных рывков в меню
	await get_tree().create_timer(1.5).timeout
	for n in FX_SOUNDS + SPELL_SOUNDS.map(func(k): return "spell_" + k):
		_stream(n)
		await get_tree().create_timer(0.08).timeout

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * dur))
	return b

## Синус с гармониками и огибающей: атака att (с), экспоненциальное затухание dec (1/с).
## harm — веса гармоник [1, h2, h3, …]; vib — глубина вибрато (доля), 5,5 Гц.
func _sine(b: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, vol: float,
		att := 0.005, dec := 8.0, harm: Array = [1.0], vib := 0.0) -> void:
	var i0 := int(t0 * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, float(i) / maxf(1.0, n)) * (1.0 + vib * sin(TAU * 5.5 * t))
		ph += TAU * f / RATE
		var s := 0.0
		for h in harm.size():
			s += sin(ph * (h + 1)) * float(harm[h])
		var env := minf(1.0, t / att) * exp(-t * dec) * minf(1.0, float(n - i) / (RATE * 0.01))
		b[i0 + i] += s * env * vol

## Шум через два ФНЧ (lp1 — «яркость» 0..1, чем меньше, тем глуше); bp=true — полоса (lp1 − lp2).
## sweep — множитель коэффициента к концу звука (свист «вжух»); grain — доля «зёрен» (потрескивание).
func _noise(b: PackedFloat32Array, t0: float, dur: float, vol: float, lp1: float,
		att := 0.005, dec := 8.0, bp := false, sweep := 1.0, grain := 0.0) -> void:
	var i0 := int(t0 * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	var a := 0.0
	var c := 0.0
	var d := 0.0
	var g := 1.0
	for i in n:
		var t := float(i) / RATE
		var k := clampf(lp1 * lerpf(1.0, sweep, float(i) / maxf(1.0, n)), 0.001, 0.95)
		a += (randf_range(-1.0, 1.0) - a) * k
		c += (a - c) * k
		d += (c - d) * k * 0.35
		var s := (c - d) * 2.2 if bp else c
		if grain > 0.0 and i % 220 == 0:
			g = 1.0 if randf() < grain else 0.15
		var env := minf(1.0, t / att) * exp(-t * dec) * minf(1.0, float(n - i) / (RATE * 0.01))
		b[i0 + i] += s * env * vol * g * 2.0

## Мягкий «колокольчик»: негармонические частичные с быстрым затуханием верхних.
func _bell(b: PackedFloat32Array, t0: float, f: float, vol: float, dec := 6.0, dur := 0.6) -> void:
	_sine(b, t0, dur, f, f, vol, 0.002, dec)
	_sine(b, t0, dur, f * 2.76, f * 2.76, vol * 0.22, 0.002, dec * 2.2)
	_sine(b, t0, dur, f * 5.40, f * 5.40, vol * 0.06, 0.002, dec * 3.5)

func _thud(b: PackedFloat32Array, t0: float, f: float, vol: float, dec := 16.0) -> void:
	# гармоники нужны, чтобы удар был слышен и на динамиках ноутбука (они не играют ниже ~150 Гц)
	_sine(b, t0, 0.3, f, f * 0.6, vol, 0.002, dec, [1.0, 0.6, 0.35, 0.15])
	_noise(b, t0, 0.12, vol * 0.5, 0.1, 0.002, 30.0)

func _wav(b: PackedFloat32Array, rms_target := 0.15, peak_max := 0.72) -> AudioStreamWAV:
	# мягкий общий ФНЧ (срезает остатки «песка») + нормировка по RMS с ограничением пика
	var lp := 0.0
	var pk := 0.0
	var acc := 0.0
	for i in b.size():
		lp += (b[i] - lp) * 0.55
		b[i] = lp
		pk = maxf(pk, absf(lp))
		acc += lp * lp
	var rms := sqrt(acc / maxf(1.0, b.size()))
	var g := minf(peak_max / maxf(pk, 1e-6), rms_target / maxf(rms, 1e-6))
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		data.encode_s16(i * 2, int(clampf(b[i] * g, -1.0, 1.0) * 32000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w

func _fx_sound(name: String) -> AudioStreamWAV:
	var b: PackedFloat32Array
	var rms := 0.15
	match name:
		"hit_ice":       # хрусткий ледяной скол + стеклянный звон
			b = _buf(0.45)
			_thud(b, 0.0, 150.0, 0.6, 18.0)
			_noise(b, 0.0, 0.18, 0.5, 0.35, 0.002, 26.0, true)
			_bell(b, 0.005, 1568.0, 0.18, 9.0, 0.44)
			_bell(b, 0.03, 2093.0, 0.12, 11.0, 0.4)
		"hit_fire":      # глухой «вуф» пламени + потрескивание
			b = _buf(0.5)
			_thud(b, 0.0, 110.0, 0.7, 14.0)
			_noise(b, 0.0, 0.45, 0.6, 0.06, 0.02, 7.0, false, 2.5)
			_noise(b, 0.04, 0.4, 0.3, 0.3, 0.005, 9.0, true, 1.0, 0.35)
		"hit_light":     # мягкий удар + светлый звон (квинта)
			b = _buf(0.55)
			_thud(b, 0.0, 130.0, 0.55, 18.0)
			_bell(b, 0.0, 880.0, 0.22, 7.0, 0.55)
			_bell(b, 0.02, 1318.5, 0.14, 8.0, 0.5)
		"hit_nature":    # деревянный «ток» + шелест
			b = _buf(0.42)
			_sine(b, 0.0, 0.25, 260.0, 170.0, 0.5, 0.002, 22.0, [1.0, 0.35, 0.12])
			_thud(b, 0.0, 120.0, 0.4, 20.0)
			_noise(b, 0.02, 0.38, 0.35, 0.16, 0.03, 9.0, true, 1.0, 0.5)
		"hit_neutral":
			b = _buf(0.35)
			_thud(b, 0.0, 120.0, 0.7, 16.0)
			_noise(b, 0.0, 0.2, 0.3, 0.12, 0.002, 20.0, true)
		"crit":          # тяжёлый удар + металлический отзвук
			b = _buf(0.75)
			_thud(b, 0.0, 100.0, 0.9, 9.0)
			_noise(b, 0.0, 0.3, 0.5, 0.1, 0.002, 12.0)
			_bell(b, 0.01, 523.0, 0.16, 5.0, 0.7)
			_bell(b, 0.01, 784.0, 0.1, 6.0, 0.7)
			rms = 0.17
		"heal":          # тёплое восходящее арпеджио
			b = _buf(0.85)
			var notes := [523.25, 659.25, 783.99, 1046.5]
			for i in notes.size():
				_sine(b, i * 0.07, 0.6, notes[i], notes[i], 0.22, 0.015, 5.0, [1.0, 0.2])
			_noise(b, 0.0, 0.7, 0.08, 0.08, 0.15, 4.0, true)
			rms = 0.12
		"shield":        # плотный колокол + «шшух» щита
			b = _buf(0.8)
			_noise(b, 0.0, 0.3, 0.25, 0.08, 0.06, 10.0, true, 1.6)
			_bell(b, 0.04, 392.0, 0.3, 4.5, 0.76)
			_bell(b, 0.04, 587.3, 0.16, 5.0, 0.76)
			rms = 0.13
		"freeze":        # хрустальная россыпь
			b = _buf(0.9)
			_noise(b, 0.0, 0.8, 0.22, 0.12, 0.05, 4.5, true, 1.8)
			for i in 9:
				_bell(b, 0.03 + i * 0.065 + randf() * 0.02, randf_range(1500.0, 2600.0), 0.1, 10.0, 0.3)
			_sine(b, 0.0, 0.8, 330.0, 290.0, 0.12, 0.05, 3.0)
			rms = 0.11
		"stun":          # «звёзды в глазах»: качающийся тон
			b = _buf(0.6)
			_thud(b, 0.0, 140.0, 0.45, 18.0)
			_sine(b, 0.02, 0.55, 740.0, 620.0, 0.22, 0.01, 4.5, [1.0, 0.15], 0.06)
			_sine(b, 0.06, 0.5, 990.0, 830.0, 0.12, 0.01, 5.0, [1.0], 0.06)
			rms = 0.12
		"poison":        # бульканье
			b = _buf(0.6)
			for i in 6:
				var f := randf_range(260.0, 420.0)
				_sine(b, i * 0.08 + randf() * 0.03, 0.09, f, f * 1.8, 0.3, 0.004, 30.0)
			_noise(b, 0.0, 0.5, 0.12, 0.05, 0.05, 5.0)
			rms = 0.12
		"buff_up":       # бодрый подъём (мягкая «медь»)
			b = _buf(0.6)
			_sine(b, 0.0, 0.25, 392.0, 392.0, 0.3, 0.02, 6.0, [1.0, 0.4, 0.2, 0.08])
			_sine(b, 0.12, 0.45, 587.3, 587.3, 0.3, 0.02, 4.5, [1.0, 0.4, 0.2, 0.08])
			rms = 0.13
		"buff_down":     # спад с биениями
			b = _buf(0.7)
			_sine(b, 0.0, 0.65, 330.0, 220.0, 0.28, 0.02, 3.5, [1.0, 0.3])
			_sine(b, 0.0, 0.65, 334.0, 223.0, 0.2, 0.02, 3.5, [1.0])
			rms = 0.12
		"revive":        # восходящий свист + аккорд
			b = _buf(1.2)
			_noise(b, 0.0, 0.7, 0.2, 0.05, 0.3, 2.5, true, 3.0)
			for f in [392.0, 493.9, 587.3, 784.0]:
				_sine(b, 0.3, 0.85, f, f, 0.15, 0.08, 3.0, [1.0, 0.15])
			_bell(b, 0.3, 1568.0, 0.08, 4.0, 0.8)
			rms = 0.12
		"soul":          # тихий уходящий выдох (для гибели)
			b = _buf(0.8)
			_noise(b, 0.0, 0.75, 0.3, 0.05, 0.08, 3.5, true, 0.5)
			_sine(b, 0.0, 0.75, 440.0, 300.0, 0.08, 0.1, 3.5, [1.0], 0.02)
			rms = 0.08
		"whoosh":        # пролёт снаряда
			b = _buf(0.4)
			_noise(b, 0.0, 0.38, 0.6, 0.04, 0.18, 6.0, true, 3.0)
			rms = 0.1
		"victory_sting": # мажорное арпеджио колокольчиками + подушка
			b = _buf(1.7)
			var vn := [523.25, 659.25, 783.99, 1046.5]
			for i in vn.size():
				_bell(b, i * 0.11, vn[i], 0.25, 3.2, 1.3)
			for f in [261.6, 329.6, 392.0]:
				_sine(b, 0.3, 1.35, f, f, 0.12, 0.25, 2.2, [1.0, 0.2])
			rms = 0.13
		"defeat_sting":  # мягкий минорный спуск
			b = _buf(1.7)
			var dn := [440.0, 349.2, 293.7]
			for i in dn.size():
				_sine(b, i * 0.2, 0.9, dn[i], dn[i] * 0.99, 0.22, 0.02, 3.0, [1.0, 0.25, 0.08])
			for f in [146.8, 174.6, 220.0]:
				_sine(b, 0.4, 1.25, f, f, 0.1, 0.3, 2.0, [1.0, 0.2])
			rms = 0.12
		"spell_fireball":  # нарастающий рёв пламени и хлопок
			b = _buf(0.9)
			_noise(b, 0.0, 0.5, 0.5, 0.06, 0.3, 2.0, true, 3.0)
			_thud(b, 0.42, 120.0, 0.8, 9.0)
			_noise(b, 0.42, 0.45, 0.45, 0.12, 0.003, 7.0, true, 0.6, 0.4)
		"spell_heal":
			return _fx_sound("heal")
		"spell_bless":     # хорал-аккорд
			b = _buf(1.1)
			for f in [392.0, 493.9, 587.3, 784.0]:
				_sine(b, 0.0, 1.05, f, f, 0.15, 0.12, 2.6, [1.0, 0.25, 0.1], 0.004)
			_bell(b, 0.05, 1174.7, 0.08, 3.5, 1.0)
			rms = 0.12
		"spell_rage":      # боевой рог
			b = _buf(0.95)
			_sine(b, 0.0, 0.9, 196.0, 220.0, 0.35, 0.08, 2.8, [1.0, 0.55, 0.35, 0.2, 0.1], 0.01)
			_sine(b, 0.0, 0.9, 293.7, 329.6, 0.18, 0.1, 3.0, [1.0, 0.4, 0.2], 0.01)
		"spell_freeze":
			return _fx_sound("freeze")
		"spell_meteor":    # гул падения + раскаты
			b = _buf(1.1)
			_noise(b, 0.0, 0.55, 0.4, 0.04, 0.4, 1.5, true, 0.5)
			_sine(b, 0.0, 0.55, 700.0, 250.0, 0.08, 0.3, 2.0)
			_thud(b, 0.5, 100.0, 0.9, 6.0)
			_thud(b, 0.62, 140.0, 0.5, 9.0)
		"spell_surge":     # восходящая волна маны
			b = _buf(0.8)
			_sine(b, 0.0, 0.75, 300.0, 900.0, 0.22, 0.15, 3.0, [1.0, 0.3], 0.01)
			_noise(b, 0.0, 0.7, 0.18, 0.05, 0.2, 3.0, true, 3.0)
			rms = 0.12
		"spell_pact":      # тёмный удар сердца
			b = _buf(0.9)
			_thud(b, 0.0, 90.0, 0.8, 10.0)
			_thud(b, 0.22, 82.0, 0.6, 10.0)
			_sine(b, 0.0, 0.85, 110.0, 104.0, 0.2, 0.1, 2.5, [1.0, 0.5, 0.25])
			_sine(b, 0.0, 0.85, 113.0, 107.0, 0.15, 0.1, 2.5, [1.0, 0.4])
		"spell_curse":     # шёпот + диссонанс
			b = _buf(1.0)
			_noise(b, 0.0, 0.9, 0.3, 0.06, 0.25, 2.5, true, 0.6)
			_sine(b, 0.05, 0.9, 233.1, 220.0, 0.16, 0.15, 2.5, [1.0, 0.3], 0.02)
			_sine(b, 0.05, 0.9, 247.0, 233.1, 0.12, 0.15, 2.5, [1.0, 0.3], 0.02)
			rms = 0.12
		"spell_chain":     # приглушённый электрический треск (без высоких частот)
			b = _buf(0.7)
			_noise(b, 0.0, 0.6, 0.55, 0.22, 0.003, 5.0, true, 1.0, 0.55)
			_sine(b, 0.0, 0.6, 95.0, 85.0, 0.3, 0.005, 5.0, [1.0, 0.6, 0.45, 0.3, 0.2], 0.0)
			_thud(b, 0.0, 120.0, 0.4, 18.0)
			rms = 0.14
		"spell_revive":
			return _fx_sound("revive")
		"spell_venom":     # густое бульканье
			b = _buf(0.9)
			for i in 9:
				var f := randf_range(200.0, 360.0)
				_sine(b, i * 0.085 + randf() * 0.03, 0.1, f, f * 1.7, 0.3, 0.004, 28.0)
			_noise(b, 0.0, 0.85, 0.16, 0.04, 0.1, 2.5)
			rms = 0.12
		"spell_guillotine": # свист лезвия и глухой стук
			b = _buf(0.8)
			_noise(b, 0.0, 0.35, 0.4, 0.06, 0.25, 2.0, true, 3.5)
			_thud(b, 0.32, 120.0, 0.9, 12.0)
			_bell(b, 0.32, 330.0, 0.12, 8.0, 0.45)
		_:
			if name.begins_with("spell_"):
				return _stream("cast")
			return null
	return _wav(b, rms)
