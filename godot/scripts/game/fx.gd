class_name Fx
extends Node
## Боевые эффекты в «рисованном» стиле: мягкие короткие частицы без неона и свечения.
## Работает в GL Compatibility: только CPUParticles3D + анимированные квады (Tween), всё из пула,
## текстуры — крошечные белые спрайты из res://assets/fx/ (подкрашиваются цветом стихии).
## Обычное смешивание (alpha), аддитивное — только тусклое и редко (вспышка света).
##
## ---------------- Подключение ----------------
##   var fx := Fx.new(); table.add_child(fx)        # один раз (узел не 3D — дети стоят в мировых координатах)
##   fx.time_scale = speed / 2.0                       # 1.0 = обычная скорость боя (speed 2); 2.0 — ускоренная
##
## ---------------- Координаты ----------------
## Все функции принимают ТОЧКУ ОСНОВАНИЯ КАРТЫ на столе: card.global_position (y ≈ 0).
## Высоту центра лица и сдвиг к камере (чтобы эффект не прятался за картой) Fx добавляет сам.
##
## ---------------- API ----------------
##   hit(at: Vector3, element: String, crit := false, kind := "attack") -> void
##        element: "S" лёд | "H" огонь | "D" свет | "C" природа | "" нейтральный | любой ключ PAL ("poison", "dark", …)
##        kind: "attack" | "ability" | "spell" | "poison" (зелёные капли) | "thorns" (мелкий нейтральный)
##        crit=true — крупнее, полумесяц удара и лёгкая тряска камеры (если shake_on_crit)
##   projectile(from: Vector3, to: Vector3, element: String, dur := 0.3) -> Signal   # await fx.projectile(...)
##   cast(at: Vector3, element: String) -> void                # руна под картой + поднимающиеся искры
##   spell(key: String, targets: Array, side_center: Vector3) -> Signal   # 13 ключей Data.MAGIC с t:"spell"; await — до «прилёта»
##   heal(at) / shield(at, col := Color()) / poison(at) / revive(at) -> void
##   death(at: Vector3, element := "") -> void                # пыль + уходящая душа
##   buff(at: Vector3, up: bool) -> void
##   stun(at: Vector3, frost := false) -> void                # звёздочки над картой / иней (заморозка)
##   victory(center: Vector3) / defeat(center: Vector3) -> void   # center — центр линии победившей/проигравшей стороны
##   camera_shake(camera: Camera3D = null, strength := 0.06, dur := 0.2) -> void   # null → камера вьюпорта
## Вспомогательное: Fx.elem_of_hero(id) -> String, Fx.SPELL_ELEM[key], Fx.RANGED_AB (способности со снарядом).

const SPELL_ELEM := {"fireball": "H", "heal": "C", "bless": "D", "rage": "H", "freeze": "S", "meteor": "D",
	"surge": "mana", "pact": "blood", "curse": "dark", "chain": "S", "revive": "D", "venom": "poison", "guillotine": ""}
## Способности героев, которые летят снарядом от заклинателя к цели (остальные — только cast()).
const RANGED_AB := ["strike", "drain", "poison", "stun", "execute", "volley", "plague", "sunburst"]

## Палитры: a — светлый, b — основной, c — тёмный. Приглушённые, «акварельные».
const PAL := {
	"S": [Color("dcf0f7"), Color("8cc2de"), Color("46769f")],
	"H": [Color("ffd9a0"), Color("ec8044"), Color("8a3a24")],
	"D": [Color("fff1c8"), Color("e9c060"), Color("9c7838")],
	"C": [Color("d6eca8"), Color("78b456"), Color("3f6e36")],
	"": [Color("efe6d6"), Color("bba98f"), Color("6e6050")],
	"poison": [Color("cfe89a"), Color("86b850"), Color("4c6e2e")],
	"dark": [Color("cdb4dc"), Color("80588f"), Color("3e2848")],
	"blood": [Color("eab0a2"), Color("b04444"), Color("5c2024")],
	"mana": [Color("d6e4ff"), Color("78a2e2"), Color("3a5690")],
}

const FACE_Y := 0.62        # высота центра лица стоящей карты над столом
const PUSH := 0.5           # сдвиг к камере
const P_SCALE := 2.0        # общий множитель размера частиц (стол виден издалека: ~80 px на единицу)

var time_scale := 1.0
var shake_on_crit := true
var _tex_cache := {}
var _mesh_cache := {}
var _free_em: Array[CPUParticles3D] = []
var _free_q: Array[MeshInstance3D] = []
var _quad1: QuadMesh
var _curve_pop: Curve
var _curve_shrink: Curve
var _shaking := {}           # camera → [base_h, base_v, tween]

func _ready() -> void:
	_quad1 = QuadMesh.new()
	_quad1.size = Vector2.ONE
	_curve_pop = Curve.new()
	_curve_pop.add_point(Vector2(0.0, 0.5))
	_curve_pop.add_point(Vector2(0.15, 1.0))
	_curve_pop.add_point(Vector2(1.0, 0.35))
	_curve_shrink = Curve.new()
	_curve_shrink.add_point(Vector2(0.0, 1.0))
	_curve_shrink.add_point(Vector2(1.0, 0.1))
	for n in ["soft", "dot", "ring", "rune", "shard", "leaf", "star", "drop", "puff", "ray", "slash"]:
		_tex(n)

static func elem_of_hero(id: String) -> String:
	var h = Data.HEROES.get(id)
	return String(h.s) if h else ""

# =================== эффекты ===================

func hit(at: Vector3, element: String, crit := false, kind := "attack") -> void:
	var p := _front(at)
	var k := 1.6 if crit else 1.0
	if kind == "poison":
		_drops(p, 12, "poison")
		return
	if kind == "thorns":
		element = ""
		k = 0.6
	var c: Array = _pal(element)
	match element:
		"S":
			_burst(p, {"tex": "shard", "n": 14 * k, "life": 0.55, "vel": [2.4, 4.4], "grav": Vector3(0, -7, 0),
				"damp": [2, 4], "size": [0.14 * k, 0.26 * k], "cols": [c[0], c[1]], "spin": 540.0, "curve": _curve_shrink})
			_burst(p, {"tex": "puff", "n": 5, "life": 0.55, "vel": [0.5, 1.1], "size": [0.3, 0.45], "cols": [c[0], c[1]],
				"alpha": 0.3, "damp": [1, 2]})
			_sprite(p, "ring", 0.35, 1.3 * k, c[0], 0.3, {"alpha": 0.55})
		"H":
			_burst(p, {"tex": "dot", "n": 18 * k, "life": 0.5, "vel": [2.0, 4.2], "grav": Vector3(0, -5, 0),
				"damp": [2, 4], "size": [0.06, 0.11 * k], "cols": [c[0], c[1]], "curve": _curve_shrink})
			_burst(p, {"tex": "soft", "n": 8, "life": 0.9, "vel": [0.4, 1.2], "dir": Vector3.UP, "spread": 40.0,
				"grav": Vector3(0, 0.8, 0), "size": [0.08, 0.14], "cols": [c[1], c[2]], "r": 0.25, "alpha": 0.85})
			_burst(p, {"tex": "puff", "n": 5, "life": 0.8, "vel": [0.3, 0.8], "dir": Vector3.UP, "spread": 60.0,
				"size": [0.4, 0.7 * k], "cols": [Color("5a4a40"), Color("3a302a")], "alpha": 0.35, "r": 0.2})
			_sprite(p, "soft", 0.5, 1.2 * k, c[1], 0.22, {"alpha": 0.6})
		"D":
			_sprite(p, "star", 0.5, 1.5 * k, c[0], 0.3, {"alpha": 0.55, "add": true})
			_sprite(p, "ring", 0.3, 1.6 * k, c[1], 0.35, {"alpha": 0.6})
			_burst(p, {"tex": "dot", "n": 14 * k, "life": 0.6, "vel": [1.4, 3.0], "damp": [3, 5],
				"size": [0.05, 0.1], "cols": [c[0], c[1]], "curve": _curve_shrink})
		"C":
			_burst(p, {"tex": "leaf", "n": 12 * k, "life": 0.75, "vel": [1.6, 3.0], "grav": Vector3(0, -2.5, 0),
				"damp": [2, 3], "size": [0.14, 0.24 * k], "cols": [c[0], c[2]], "spin": 360.0})
			_burst(p, {"tex": "puff", "n": 4, "life": 0.55, "vel": [0.4, 0.9], "size": [0.35, 0.55],
				"cols": [Color("8a9a6a"), Color("6a7a50")], "alpha": 0.35})
		_:
			_burst(p, {"tex": "dot", "n": 10 * k, "life": 0.45, "vel": [1.6, 3.2], "grav": Vector3(0, -5, 0),
				"damp": [2, 4], "size": [0.05, 0.09], "cols": [c[0], c[1]], "curve": _curve_shrink})
			_burst(p, {"tex": "puff", "n": 5, "life": 0.5, "vel": [0.4, 0.9], "size": [0.35, 0.55 * k],
				"cols": [c[1], c[2]], "alpha": 0.35})
	if crit:
		_sprite(p + Vector3(0, 0.05, 0), "slash", 0.9, 1.9, Color("fff4e0"), 0.28, {"alpha": 0.8, "a_in": 0.15})
		if shake_on_crit:
			camera_shake(null, 0.05, 0.18)

func projectile(from: Vector3, to: Vector3, element: String, dur := 0.3) -> Signal:
	var a := _front(from, FACE_Y + 0.15, 0.35)
	var b := _front(to, FACE_Y, PUSH)
	var c: Array = _pal(element)
	var trail := {"tex": "soft", "n": 22, "life": 0.35, "vel": [0.05, 0.3], "size": [0.08, 0.16], "cols": [c[0], c[1]],
		"stream": true, "curve": _curve_shrink, "alpha": 0.8}
	match element:
		"S": trail.merge({"tex": "shard", "size": [0.1, 0.18], "spin": 360.0, "cols": [c[0], c[1]], "n": 18}, true)
		"H": trail.merge({"tex": "dot", "cols": [c[0], c[2]], "grav": Vector3(0, 1.2, 0), "n": 26}, true)
		"D": trail.merge({"tex": "star", "size": [0.12, 0.22], "n": 16}, true)
		"C": trail.merge({"tex": "leaf", "size": [0.1, 0.16], "spin": 360.0, "cols": [c[0], c[2]], "n": 16}, true)
	var em := _burst(a, trail)
	_sprite(a, "soft", 0.95, 0.95, c[1], dur, {"alpha": 0.55, "a_in": 0.1, "fade": 0.0, "move": b, "arc": 0.5, "follow": em})
	var tw := _sprite(a, "dot", 0.45, 0.45, c[0], dur, {"alpha": 0.95, "a_in": 0.1, "fade": 0.0, "move": b, "arc": 0.5})
	return tw.finished

func cast(at: Vector3, element: String) -> void:
	var c: Array = _pal(element)
	var g := Vector3(at.x, 0.035, at.z)
	_sprite(g, "rune", 1.4, 2.3, c[1], 0.95, {"flat": true, "alpha": 0.75, "a_in": 0.25, "spin": 1.4})
	_burst(g + Vector3(0, 0.05, 0), {"tex": "soft", "n": 22, "life": 0.9, "expl": 0.55, "ring": [1.0, 0.75],
		"dir": Vector3.UP, "spread": 12.0, "vel": [0.8, 1.7], "size": [0.07, 0.13], "cols": [c[0], c[1]], "alpha": 0.9,
		"tang": [0.6, 1.2]})

func heal(at: Vector3) -> void:
	var c: Array = _pal("C")
	var p := _front(at, 0.25, PUSH)
	_burst(p, {"tex": "soft", "n": 16, "life": 1.0, "expl": 0.6, "r": 0.5, "dir": Vector3.UP, "spread": 15.0,
		"vel": [0.6, 1.3], "size": [0.08, 0.15], "cols": [Color("e8f3b0"), c[1]], "alpha": 0.9})
	_burst(p, {"tex": "star", "n": 6, "life": 0.9, "expl": 0.4, "r": 0.5, "dir": Vector3.UP, "spread": 10.0,
		"vel": [0.7, 1.2], "size": [0.14, 0.22], "cols": [Color("fff4c8"), Color("e2efb0")], "alpha": 0.8})
	_sprite(Vector3(at.x, 0.035, at.z), "ring", 0.8, 2.0, c[0], 0.7, {"flat": true, "alpha": 0.4})

func shield(at: Vector3, col := Color(0, 0, 0, 0)) -> void:
	var tint := col if col.a > 0.0 else Color("dfe8f2")
	var p := _front(at)
	_sprite(p, "ring", 0.7, 1.75, tint, 0.6, {"alpha": 0.6, "a_in": 0.3, "ease": Tween.EASE_OUT})
	_sprite(p, "soft", 1.2, 1.7, tint, 0.5, {"alpha": 0.22})
	_burst(p, {"tex": "dot", "n": 14, "life": 0.6, "surface": 0.85, "vel": [0.1, 0.4], "size": [0.05, 0.09],
		"cols": [Color.WHITE, tint], "alpha": 0.9, "curve": _curve_shrink})

func poison(at: Vector3) -> void:
	_drops(_front(at, FACE_Y + 0.9, PUSH), 10, "poison", true)
	var c: Array = _pal("poison")
	_burst(_front(at, 0.3, PUSH), {"tex": "dot", "n": 10, "life": 0.9, "expl": 0.3, "r": 0.4, "dir": Vector3.UP,
		"spread": 20.0, "vel": [0.3, 0.8], "size": [0.05, 0.1], "cols": [c[0], c[1]], "alpha": 0.8})

func death(at: Vector3, element := "") -> void:
	var c: Array = _pal(element)
	var g := Vector3(at.x, 0.12, at.z)
	_burst(g, {"tex": "puff", "n": 10, "life": 0.8, "ring": [0.7, 0.4], "dir": Vector3.UP, "spread": 70.0,
		"vel": [0.6, 1.2], "damp": [1.5, 2.5], "size": [0.45, 0.8], "cols": [Color("9c8a74"), Color("6e604f")], "alpha": 0.45})
	var p := _front(at, FACE_Y, PUSH)
	var em := _burst(p, {"tex": "soft", "n": 14, "life": 0.6, "vel": [0.05, 0.2], "size": [0.06, 0.12],
		"cols": [c[0], Color("f2eee6")], "stream": true, "alpha": 0.7, "curve": _curve_shrink})
	_sprite(p, "soft", 0.55, 0.4, Color("f4f0e8"), 1.1, {"alpha": 0.55, "a_in": 0.15, "move": p + Vector3(0.15, 1.5, 0),
		"sway": 0.12, "follow": em})

func revive(at: Vector3) -> void:
	var c: Array = _pal("D")
	for i in 3:
		var x := (i - 1) * 0.45
		_sprite(_front(at, 1.0, PUSH - 0.1) + Vector3(x, 0, 0), "ray", Vector2(0.45, 0.4), Vector2(0.45, 2.6), c[0],
			0.95, {"alpha": 0.5 - absf(i - 1) * 0.15, "a_in": 0.3, "billboard": BaseMaterial3D.BILLBOARD_FIXED_Y, "delay": i * 0.05})
	_burst(_front(at, 0.2, PUSH), {"tex": "dot", "n": 20, "life": 1.0, "expl": 0.5, "r": 0.55, "dir": Vector3.UP,
		"spread": 8.0, "vel": [1.0, 2.0], "size": [0.05, 0.1], "cols": [c[0], c[1]], "alpha": 0.9})
	_sprite(Vector3(at.x, 0.035, at.z), "rune", 2.4, 1.9, c[1], 1.0, {"flat": true, "alpha": 0.6, "spin": -1.0, "a_in": 0.2})

func buff(at: Vector3, up: bool) -> void:
	if up:
		var c: Array = _pal("H")
		_burst(_front(at, 0.2, PUSH), {"tex": "dot", "n": 16, "life": 0.8, "expl": 0.7, "ring": [0.6, 0.45],
			"dir": Vector3.UP, "spread": 6.0, "vel": [1.4, 2.4], "damp": [1, 2], "size": [0.06, 0.11], "cols": [Color("ffe2a0"), c[1]]})
		_sprite(Vector3(at.x, 0.035, at.z), "ring", 0.5, 2.3, c[1], 0.5, {"flat": true, "alpha": 0.4})
	else:
		var d: Array = _pal("dark")
		var p := _front(at, FACE_Y + 0.7, PUSH)
		_burst(p, {"tex": "puff", "n": 8, "life": 0.9, "r": 0.4, "dir": Vector3.DOWN, "spread": 30.0, "vel": [0.4, 0.9],
			"size": [0.35, 0.6], "cols": [d[1], d[2]], "alpha": 0.4})
		_burst(p, {"tex": "dot", "n": 12, "life": 0.8, "r": 0.5, "dir": Vector3.DOWN, "spread": 15.0, "vel": [0.8, 1.6],
			"size": [0.05, 0.09], "cols": [d[0], d[1]], "alpha": 0.85})

func stun(at: Vector3, frost := false) -> void:
	if frost:
		var c: Array = _pal("S")
		var p := _front(at)
		_burst(p, {"tex": "shard", "n": 10, "life": 0.7, "r": 0.6, "vel": [0.2, 0.8], "grav": Vector3(0, -1.0, 0),
			"size": [0.14, 0.24], "cols": [c[0], c[1]], "spin": 180.0, "alpha": 0.9})
		_burst(p, {"tex": "puff", "n": 6, "life": 0.9, "r": 0.5, "vel": [0.1, 0.4], "size": [0.5, 0.8],
			"cols": [c[0], Color.WHITE], "alpha": 0.35})
		_sprite(Vector3(at.x, 0.035, at.z), "ring", 1.2, 2.1, c[0], 0.9, {"flat": true, "alpha": 0.5, "a_in": 0.25})
	else:
		var top := _front(at, 1.45, 0.2)
		for i in 3:
			_sprite(top, "star", 0.24, 0.24, Color("fff0c0"), 1.0, {"alpha": 0.9, "a_in": 0.15,
				"orbit": [0.42, 5.0, TAU * i / 3.0]})

func spell(key: String, targets: Array, side_center: Vector3) -> Signal:
	var el: String = SPELL_ELEM.get(key, "")
	var c: Array = _pal(el)
	var t_hit := 0.35
	match key:
		"fireball":
			for t: Vector3 in targets:
				projectile(side_center, t, "H", 0.38)
				_later(0.38, func(): hit(t, "H", true, "spell"))
			t_hit = 0.4
		"meteor":       # «Звездопад»: падающие звёзды на всех врагов
			var i := 0
			for t: Vector3 in targets:
				var d := i * 0.09
				var src := t + Vector3(randf_range(-1.5, 1.5), 7.0, -2.0)
				_later(d, func(): projectile(src - Vector3(0, FACE_Y + 0.15, 0), t, "D", 0.36))
				_later(d + 0.36, func():
					hit(t, "D", false, "spell")
					_dust(t))
				i += 1
			t_hit = 0.4 + 0.09 * maxf(0, targets.size() - 1)
		"chain":
			var pts: Array = [_front(side_center, 3.5, 0.0)]
			for t: Vector3 in targets:
				pts.append(_front(t, FACE_Y, PUSH))
			_bolt(pts, Color("e2ebff"), 0.35)
			for t: Vector3 in targets:
				hit(t, "S", false, "spell")
			t_hit = 0.2
		"guillotine":
			for t: Vector3 in targets:
				var p := _front(t, FACE_Y, PUSH)
				_sprite(p + Vector3(0, 1.6, 0), "slash", 1.3, 1.5, Color("d9dde2"), 0.45,
					{"alpha": 0.85, "a_in": 0.1, "fade": 0.4, "move": p - Vector3(0, 0.3, 0)})
				_later(0.25, func():
					_burst(p, {"tex": "dot", "n": 14, "life": 0.5, "vel": [1.5, 3.0], "grav": Vector3(0, -6, 0),
						"size": [0.05, 0.1], "cols": [Color("b04444"), Color("6a2228")], "curve": _curve_shrink})
					_dust(t)
					camera_shake(null, 0.04, 0.15))
			t_hit = 0.3
		"freeze":
			for t: Vector3 in targets:
				var p := _front(t, FACE_Y + 1.2, PUSH)
				_burst(p, {"tex": "shard", "n": 14, "life": 0.6, "r": 0.5, "dir": Vector3.DOWN, "spread": 20.0,
					"vel": [2.0, 3.0], "grav": Vector3(0, -4, 0), "size": [0.14, 0.24], "cols": [c[0], c[1]], "spin": 200.0})
				_sprite(Vector3(t.x, 0.035, t.z), "rune", 0.8, 2.0, c[0], 0.8, {"flat": true, "alpha": 0.55, "spin": 0.8})
		"heal":
			for t: Vector3 in targets:
				heal(t)
			_leaf_swirl(targets)
		"bless":
			for t: Vector3 in targets:
				shield(t, Color("f2dea0"))
				_burst(_front(t, FACE_Y + 1.3, PUSH), {"tex": "dot", "n": 10, "life": 0.8, "r": 0.5, "dir": Vector3.DOWN,
					"spread": 10.0, "vel": [0.8, 1.4], "size": [0.05, 0.09], "cols": [c[0], c[1]]})
		"rage":
			_sprite(Vector3(side_center.x, 0.04, side_center.z), "ring", 1.0, 9.0, c[1], 0.7, {"flat": true, "alpha": 0.3})
			for t: Vector3 in targets:
				buff(t, true)
		"surge":
			for t: Vector3 in targets:
				_burst(_front(t, 0.1, PUSH), {"tex": "soft", "n": 20, "life": 1.0, "expl": 0.4, "ring": [0.6, 0.3],
					"dir": Vector3.UP, "spread": 6.0, "vel": [0.9, 1.8], "tang": [2.0, 3.0], "size": [0.07, 0.13],
					"cols": [c[0], c[1]], "alpha": 0.9})
				_sprite(Vector3(t.x, 0.035, t.z), "rune", 1.0, 2.0, c[1], 0.9, {"flat": true, "alpha": 0.55, "spin": 2.0})
		"pact":
			for t: Vector3 in targets:
				_sprite(Vector3(t.x, 0.035, t.z), "rune", 1.6, 2.1, c[1], 1.0, {"flat": true, "alpha": 0.6, "spin": -1.2})
				_drops(_front(t), 14, "blood")
		"curse":
			for t: Vector3 in targets:
				_sprite(Vector3(t.x, 0.035, t.z), "rune", 2.2, 1.7, c[1], 1.0, {"flat": true, "alpha": 0.55, "spin": -0.8})
				buff(t, false)
		"revive":
			var g := Vector3(side_center.x, 1.6, side_center.z)
			_burst(g, {"tex": "soft", "n": 40, "life": 1.3, "expl": 0.5, "box": Vector3(3.8, 0.3, 0.6),
				"dir": Vector3.DOWN, "spread": 10.0, "vel": [0.5, 1.0], "size": [0.08, 0.15], "cols": [c[0], c[1]], "alpha": 0.95})
			_burst(g, {"tex": "star", "n": 12, "life": 1.1, "expl": 0.4, "box": Vector3(3.8, 0.3, 0.6),
				"dir": Vector3.DOWN, "spread": 10.0, "vel": [0.4, 0.8], "size": [0.1, 0.16], "cols": [Color.WHITE, c[0]], "alpha": 0.8})
		"venom":
			for t: Vector3 in targets:
				_drops(_front(t, FACE_Y + 1.2, PUSH), 12, "poison", true)
		_:
			for t: Vector3 in targets:
				cast(t, el)
	return get_tree().create_timer(t_hit / time_scale).timeout

func victory(center: Vector3) -> void:
	var c: Array = _pal("D")
	_burst(Vector3(center.x, 0.3, center.z), {"tex": "soft", "n": 48, "life": 2.0, "expl": 0.25, "box": Vector3(4.0, 0.1, 0.9),
		"dir": Vector3.UP, "spread": 15.0, "vel": [0.6, 1.3], "tang": [0.3, 0.6], "size": [0.09, 0.16],
		"cols": [c[0], c[1]], "alpha": 0.95, "lrand": 0.4})
	_burst(Vector3(center.x, 0.6, center.z), {"tex": "star", "n": 12, "life": 1.6, "expl": 0.2, "box": Vector3(4.0, 0.4, 0.9),
		"dir": Vector3.UP, "spread": 20.0, "vel": [0.4, 0.9], "size": [0.12, 0.2], "cols": [Color.WHITE, c[0]], "alpha": 0.8})
	_sprite(Vector3(center.x, 0.03, center.z), "ring", 2.0, 8.5, c[1], 1.2, {"flat": true, "alpha": 0.3, "a_in": 0.3})

func defeat(center: Vector3) -> void:
	_burst(Vector3(center.x, 2.6, center.z), {"tex": "puff", "n": 30, "life": 2.0, "expl": 0.2, "box": Vector3(4.0, 0.2, 0.9),
		"dir": Vector3.DOWN, "spread": 15.0, "vel": [0.5, 0.9], "size": [0.12, 0.22], "spin": 90.0,
		"cols": [Color("a9adb5"), Color("6c6e78")], "alpha": 0.5, "lrand": 0.4})

func camera_shake(camera: Camera3D = null, strength := 0.06, dur := 0.2) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	var base: Array
	if _shaking.has(camera):
		base = _shaking[camera]
		if base[2] and (base[2] as Tween).is_valid():
			(base[2] as Tween).kill()
	else:
		base = [camera.h_offset, camera.v_offset, null]
	var tw := create_tween()
	base[2] = tw
	_shaking[camera] = base
	var steps := 5
	for i in steps:
		var s := strength * (1.0 - float(i) / steps)
		tw.tween_property(camera, "h_offset", base[0] + randf_range(-s, s), dur / (steps + 1))
		tw.parallel().tween_property(camera, "v_offset", base[1] + randf_range(-s, s) * 0.6, dur / (steps + 1))
	tw.tween_property(camera, "h_offset", base[0], dur / (steps + 1))
	tw.parallel().tween_property(camera, "v_offset", base[1], dur / (steps + 1))
	tw.tween_callback(func(): _shaking.erase(camera))

# =================== составные куски ===================

func _drops(p: Vector3, n: int, pal: String, falling := false) -> void:
	var c: Array = _pal(pal)
	if falling:
		_burst(p, {"tex": "drop", "n": n, "life": 0.6, "r": 0.5, "dir": Vector3.DOWN, "spread": 10.0, "vel": [0.6, 1.2],
			"grav": Vector3(0, -6, 0), "size": [0.12, 0.2], "cols": [c[0], c[1]], "alpha": 0.9})
	else:
		_burst(p, {"tex": "drop", "n": n, "life": 0.6, "vel": [1.6, 3.0], "dir": Vector3.UP, "spread": 70.0,
			"grav": Vector3(0, -7, 0), "size": [0.1, 0.18], "cols": [c[0], c[1]], "alpha": 0.9})

func _dust(at: Vector3) -> void:
	_burst(Vector3(at.x, 0.1, at.z), {"tex": "puff", "n": 8, "life": 0.7, "ring": [0.6, 0.3], "dir": Vector3.UP, "spread": 75.0,
		"vel": [0.8, 1.4], "damp": [2, 3], "size": [0.4, 0.7], "cols": [Color("a8957a"), Color("756654")], "alpha": 0.4})

func _leaf_swirl(targets: Array) -> void:
	var c: Array = _pal("C")
	for t: Vector3 in targets:
		_burst(_front(t, 0.1, PUSH), {"tex": "leaf", "n": 8, "life": 1.0, "expl": 0.5, "ring": [0.7, 0.5], "dir": Vector3.UP,
			"spread": 10.0, "vel": [0.8, 1.4], "tang": [1.5, 2.5], "size": [0.12, 0.18], "cols": [c[0], c[1]], "spin": 200.0})

## Ломаная молния через точки pts (мягкая, без свечения), мерцает 2–3 раза.
func _bolt(pts: Array, col: Color, life: float) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var cam := get_viewport().get_camera_3d()
	var rng := RandomNumberGenerator.new()
	var build := func(a: float):
		im.clear_surfaces()
		for pass_i in 2:
			var w := 0.16 if pass_i == 0 else 0.05
			var cc := Color(col.r, col.g, col.b, (0.22 if pass_i == 0 else 0.9) * a)
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for s in pts.size() - 1:
				var p0: Vector3 = pts[s]
				var p1: Vector3 = pts[s + 1]
				var segs := 7
				var prev := p0
				rng.seed = hash([s, pass_i, Time.get_ticks_msec() / 60])
				for j in range(1, segs + 1):
					var q := p0.lerp(p1, float(j) / segs)
					if j < segs:
						q += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.18
					var to_cam := (cam.global_position - prev).normalized() if cam else Vector3.UP
					var side := (q - prev).cross(to_cam).normalized() * w
					im.surface_set_color(cc); im.surface_add_vertex(prev - side)
					im.surface_set_color(cc); im.surface_add_vertex(prev + side)
					im.surface_set_color(cc); im.surface_add_vertex(q + side)
					im.surface_set_color(cc); im.surface_add_vertex(prev - side)
					im.surface_set_color(cc); im.surface_add_vertex(q + side)
					im.surface_set_color(cc); im.surface_add_vertex(q - side)
					prev = q
			im.surface_end()
	var tw := create_tween().set_speed_scale(time_scale)
	tw.tween_method(func(t: float):
		build.call((1.0 - t) * (0.6 + 0.4 * float(int(t * 9.0) % 2))), 0.0, 1.0, life)
	tw.tween_callback(mi.queue_free)

# =================== основа: частицы и квады ===================

func _pal(el: String) -> Array:
	return PAL.get(el, PAL[""])

## Точка над основанием карты, сдвинутая к камере.
func _front(at: Vector3, h := FACE_Y, push := PUSH) -> Vector3:
	var p := at + Vector3(0, h, 0)
	var cam := get_viewport().get_camera_3d()
	if cam and push != 0.0:
		p += (cam.global_position - p).normalized() * push
	return p

func _tex(n: String) -> Texture2D:
	if not _tex_cache.has(n):
		var path := "res://assets/fx/%s.png" % n
		_tex_cache[n] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[n]

## Эффекты рисуются поверх карт (no_depth_test): карта стоит под углом и иначе закрывает вспышку.
## Плоские руны/кольца на столе — с проверкой глубины, чтобы карта стояла «на» них.
func _mat(tex: String, add: bool, billboard := BaseMaterial3D.BILLBOARD_PARTICLES, on_top := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _tex(tex)
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	m.disable_receive_shadows = true
	m.no_depth_test = on_top
	m.render_priority = 2 if on_top else 0
	return m

func _pmesh(tex: String, add: bool) -> QuadMesh:
	var key := tex + ("+" if add else "")
	if not _mesh_cache.has(key):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		q.material = _mat(tex, add)
		_mesh_cache[key] = q
	return _mesh_cache[key]

func _get_em() -> CPUParticles3D:
	var e: CPUParticles3D
	if _free_em.is_empty():
		e = CPUParticles3D.new()
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.local_coords = false
		e.emitting = false
		add_child(e)
	else:
		e = _free_em.pop_back()
	e.visible = true
	return e

func _release_em(e: CPUParticles3D) -> void:
	if not is_instance_valid(e):
		return
	e.emitting = false
	e.visible = false
	if _free_em.size() < 40:
		_free_em.append(e)
	else:
		e.queue_free()

## Вспышка частиц. o: tex, n, life, expl, lrand, vel[min,max], dir, spread, grav, damp[], size[], cols[a,b] (случайный
## цвет между a и b), alpha, spin (град/с), tang[], curve, add, delay, r (сфера) | surface (оболочка) | ring [r, r_in] | box,
## stream=true — непрерывный поток (для шлейфа; позицией управляет _sprite.follow, остановка — там же).
func _burst(p: Vector3, o: Dictionary) -> CPUParticles3D:
	var e := _get_em()
	e.position = p
	e.mesh = _pmesh(o.get("tex", "soft"), o.get("add", false))
	var stream: bool = o.get("stream", false)
	e.one_shot = not stream
	e.amount = clampi(int(o.get("n", 12)), 1, 60)
	e.lifetime = float(o.get("life", 0.6))
	e.explosiveness = 0.0 if stream else float(o.get("expl", 1.0))
	e.randomness = 0.3
	e.lifetime_randomness = float(o.get("lrand", 0.3))
	e.speed_scale = time_scale
	e.direction = o.get("dir", Vector3.UP)
	e.spread = float(o.get("spread", 180.0))
	e.gravity = o.get("grav", Vector3.ZERO)
	var v: Array = o.get("vel", [0.5, 1.0])
	e.initial_velocity_min = v[0]; e.initial_velocity_max = v[1]
	var dm: Array = o.get("damp", [0.0, 0.0])
	e.damping_min = dm[0]; e.damping_max = dm[1]
	var sz: Array = o.get("size", [0.1, 0.15])
	e.scale_amount_min = sz[0] * P_SCALE; e.scale_amount_max = sz[1] * P_SCALE
	e.scale_amount_curve = o.get("curve", _curve_pop)
	var spin: float = o.get("spin", 0.0)
	e.angle_min = 0.0; e.angle_max = 360.0 if spin > 0.0 or o.get("tex", "") in ["shard", "leaf", "puff"] else 0.0
	e.angular_velocity_min = -spin; e.angular_velocity_max = spin
	var tg: Array = o.get("tang", [0.0, 0.0])
	e.tangential_accel_min = tg[0]; e.tangential_accel_max = tg[1]
	# форма излучения
	if o.has("box"):
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		e.emission_box_extents = o.box
	elif o.has("ring"):
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		e.emission_ring_axis = Vector3.UP
		e.emission_ring_height = 0.0
		e.emission_ring_radius = o.ring[0]
		e.emission_ring_inner_radius = o.ring[1]
	elif o.has("surface"):
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
		e.emission_sphere_radius = o.surface
	elif o.has("r"):
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		e.emission_sphere_radius = o.r
	else:
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	# цвета: начальный — случайный между a и b; по жизни — появление и угасание
	var cols: Array = o.get("cols", [Color.WHITE, Color.WHITE])
	var gi := Gradient.new()
	gi.set_color(0, cols[0]); gi.set_color(1, cols[1])
	e.color_initial_ramp = gi
	var a: float = o.get("alpha", 1.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.0))
	gr.set_color(1, Color(1, 1, 1, 0.0))
	gr.add_point(0.1, Color(1, 1, 1, a))
	gr.add_point(0.55, Color(1, 1, 1, a * 0.85))
	e.color_ramp = gr
	e.color = Color.WHITE
	var delay: float = o.get("delay", 0.0)
	var start := func():
		if is_instance_valid(e):
			e.restart()
			e.emitting = true
	if delay > 0.0:
		e.emitting = false
		_later(delay, start)
	else:
		start.call()
	if not stream:
		_later(delay + e.lifetime + 0.15, _release_em.bind(e))
	return e

func _get_q() -> MeshInstance3D:
	var q: MeshInstance3D
	if _free_q.is_empty():
		q = MeshInstance3D.new()
		q.mesh = _quad1
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
	else:
		q = _free_q.pop_back()
	q.visible = true
	return q

func _release_q(q: MeshInstance3D) -> void:
	if not is_instance_valid(q):
		return
	q.visible = false
	if _free_q.size() < 40:
		_free_q.append(q)
	else:
		q.queue_free()

## Анимированный спрайт: масштаб s0 → s1 (число или Vector2), появление a_in (доля жизни) и угасание fade (доля).
## o: alpha, add, flat (лежит на столе), billboard (режим), spin (рад/с, только flat), move (куда лететь), arc (высота дуги),
## sway (покачивание), orbit [r, рад/с, фаза], follow (CPUParticles3D, едет за спрайтом и гаснет в конце), delay, ease.
func _sprite(p: Vector3, tex: String, s0, s1, col: Color, life: float, o := {}) -> Tween:
	var q := _get_q()
	var flat: bool = o.get("flat", false)
	var m := _mat(tex, o.get("add", false), BaseMaterial3D.BILLBOARD_DISABLED if flat else o.get("billboard", BaseMaterial3D.BILLBOARD_ENABLED), not flat)
	m.vertex_color_use_as_albedo = false
	q.material_override = m
	q.position = p
	q.rotation = Vector3(-PI / 2, 0, 0) if flat else Vector3.ZERO
	var v0: Vector2 = s0 if s0 is Vector2 else Vector2(s0, s0)
	var v1: Vector2 = s1 if s1 is Vector2 else Vector2(s1, s1)
	var alpha: float = o.get("alpha", 1.0)
	var a_in: float = o.get("a_in", 0.0)
	var fade: float = o.get("fade", 0.6)
	var spin: float = o.get("spin", 0.0)
	var to: Vector3 = o.get("move", p)
	var arc: float = o.get("arc", 0.0)
	var sway: float = o.get("sway", 0.0)
	var orbit: Array = o.get("orbit", [])
	var follow: CPUParticles3D = o.get("follow", null)
	var ease_out := int(o.get("ease", Tween.EASE_OUT))
	var upd := func(t: float):
		var k := ease(t, 0.4) if ease_out == Tween.EASE_OUT else t
		var s := v0.lerp(v1, k)
		q.scale = Vector3(s.x, s.y, 1.0)
		var pos := p.lerp(to, t) + Vector3(0, sin(t * PI) * arc, 0)
		if sway > 0.0:
			pos.x += sin(t * TAU * 1.5) * sway
		if not orbit.is_empty():
			var ang: float = orbit[2] + t * life * orbit[1]
			pos += Vector3(cos(ang), 0.0, sin(ang)) * float(orbit[0]) + Vector3(0, sin(ang * 2.0) * 0.05, 0)
		q.position = pos
		if follow:
			follow.position = pos
		if spin != 0.0:
			q.rotation.y = t * life * spin
		var a := 1.0
		if a_in > 0.0 and t < a_in:
			a = t / a_in
		elif fade > 0.0 and t > 1.0 - fade:
			a = (1.0 - t) / fade
		m.albedo_color = Color(col.r, col.g, col.b, col.a * alpha * a)
	upd.call(0.0)
	var delay: float = o.get("delay", 0.0)
	if delay > 0.0:
		q.visible = false
	var tw := create_tween().set_speed_scale(time_scale)
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func(): q.visible = true)
	tw.tween_method(upd, 0.0, 1.0, life)
	tw.tween_callback(func():
		_release_q(q)
		if follow:
			follow.emitting = false
			_later(follow.lifetime + 0.1, _release_em.bind(follow)))
	return tw

func _later(d: float, f: Callable) -> void:
	if d <= 0.0:
		f.call()
		return
	get_tree().create_timer(d / time_scale).timeout.connect(f)
