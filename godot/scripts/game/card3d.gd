class_name Card3D
extends Node3D
## 3D-карта на столе: лицо (запечённая текстура), рубашка, полоски ОЗ/маны/щита в бою,
## подсветка выбора (золотая подложка, без свечения), всплывающие числа, анимации.

const W := 1.25
const H := 1.75
const TILT := 0.55             # наклон к камере (рад), карта «стоит» на подставке
const BAR_W := 1.15

var uid: int = -1
var kind := "hero"             # hero | magic
var key := ""                  # id героя или ключ магии
var side := "p"                # p | e
var face_mi: MeshInstance3D
var back_mi: MeshInstance3D
var plate: MeshInstance3D      # подложка выделения
var body: StaticBody3D
var pivot: Node3D              # всё, что наклоняется
var bars: Node3D
var hp_fill: MeshInstance3D
var hp_lag: MeshInstance3D
var mana_fill: MeshInstance3D
var shield_fill: MeshInstance3D
var hp_label: Label3D
var _face_mat: StandardMaterial3D
var _plate_mat: StandardMaterial3D
var _dim := 1.0
var _hp_ratio := 1.0
var _move_tw: Tween

static var _quad: QuadMesh

func _init() -> void:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(W, H)

func setup(p_kind: String, p_key: String, tex: Texture2D, p_uid: int = -1, p_side := "p") -> Card3D:
	kind = p_kind; key = p_key; uid = p_uid; side = p_side
	pivot = Node3D.new()
	add_child(pivot)
	# лицо
	face_mi = MeshInstance3D.new()
	face_mi.mesh = _quad
	_face_mat = StandardMaterial3D.new()
	_face_mat.albedo_texture = tex
	_face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_face_mat.alpha_scissor_threshold = 0.5
	_face_mat.roughness = 0.62
	_face_mat.metallic_specular = 0.35
	_face_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	face_mi.material_override = _face_mat
	pivot.add_child(face_mi)
	# рубашка
	back_mi = MeshInstance3D.new()
	back_mi.mesh = _quad
	back_mi.rotation.y = PI
	var bm := StandardMaterial3D.new()
	bm.albedo_texture = CardFaces.back()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	bm.roughness = 0.6
	back_mi.material_override = bm
	back_mi.position.z = -0.004
	pivot.add_child(back_mi)
	# подложка выделения (матовое золото, не светится)
	plate = MeshInstance3D.new()
	var pq := QuadMesh.new(); pq.size = Vector2(W + 0.12, H + 0.12)
	plate.mesh = pq
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_color = Color("d8a640")
	_plate_mat.metallic = 0.6
	_plate_mat.roughness = 0.35
	_plate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plate.material_override = _plate_mat
	plate.position.z = -0.008
	plate.visible = false
	pivot.add_child(plate)
	# коллайдер для выбора мышью
	body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(W, H, 0.06)
	cs.shape = bs
	body.add_child(cs)
	body.set_meta("card", self)
	pivot.add_child(body)
	_build_bars()
	set_tilt(true)
	return self

## Карта «стоит» с наклоном к камере (на столе) или лежит плашмя (в полёте/руке).
func set_tilt(standing: bool) -> void:
	# лицом вверх: поворот -90° по X, затем приподнимаем верх к камере
	pivot.rotation = Vector3(-PI / 2 + (TILT if standing else 0.0), 0, 0)
	pivot.position = Vector3(0, (sin(TILT) * H * 0.5 + 0.03) if standing else 0.03, 0)

func set_face(tex: Texture2D) -> void:
	_face_mat.albedo_texture = tex

func set_selected(on: bool, col := Color("d8a640")) -> void:
	plate.visible = on
	_plate_mat.albedo_color = col

func set_dim(a: float) -> void:
	_dim = a
	var c := Color(a, a, a, 1)
	_face_mat.albedo_color = c

func show_bars(on: bool) -> void:
	bars.visible = on

# ---------- полоски боя ----------
func _bar_quad(col: Color, h: float, z: float, unshaded := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(BAR_W, h)
	q.center_offset = Vector3(BAR_W / 2, 0, 0)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 1 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.material_override = m
	mi.position = Vector3(-BAR_W / 2, 0, z)
	return mi

func _build_bars() -> void:
	bars = Node3D.new()
	bars.position = Vector3(0, H / 2 + 0.22, 0.0)
	pivot.add_child(bars)
	var bg := _bar_quad(Color(0.08, 0.05, 0.04, 0.85), 0.2, 0.0)
	bars.add_child(bg)
	hp_lag = _bar_quad(Color("f0d9a0"), 0.15, 0.002)
	bars.add_child(hp_lag)
	hp_fill = _bar_quad(Color("4cb874") if side == "p" else Color("d9485c"), 0.15, 0.004)
	bars.add_child(hp_fill)
	shield_fill = _bar_quad(Color(0.93, 0.95, 1.0, 0.85), 0.07, 0.006)
	shield_fill.position.y = 0.04
	shield_fill.scale.x = 0.0
	bars.add_child(shield_fill)
	var mbg := _bar_quad(Color(0.08, 0.05, 0.04, 0.85), 0.08, 0.0)
	mbg.position.y = -0.15
	bars.add_child(mbg)
	mana_fill = _bar_quad(Color("5c9be6"), 0.05, 0.004)
	mana_fill.position.y = -0.15
	bars.add_child(mana_fill)
	hp_label = Label3D.new()
	hp_label.font = CardFaces.f_bold
	hp_label.font_size = 64
	hp_label.pixel_size = 0.0028
	hp_label.outline_size = 14
	hp_label.outline_modulate = Color(0.08, 0.05, 0.03, 1)
	hp_label.position = Vector3(0, 0, 0.01)
	hp_label.no_depth_test = false
	bars.add_child(hp_label)
	bars.visible = false

func set_bars(hp: int, max_hp: int, mana: int, mm: int, shield: int) -> void:
	var r := clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	hp_fill.scale.x = maxf(0.001, r)
	if r < _hp_ratio:
		var tw := create_tween()
		tw.tween_interval(0.25)
		tw.tween_property(hp_lag, "scale:x", maxf(0.001, r), 0.45)
	else:
		hp_lag.scale.x = maxf(0.001, r)
	_hp_ratio = r
	mana_fill.scale.x = maxf(0.001, clampf(float(mana) / maxf(1.0, float(mm)), 0.0, 1.0))
	shield_fill.scale.x = clampf(float(shield) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	hp_label.text = str(max(hp, 0))

# ---------- анимации ----------
func move_to(pos: Vector3, dur := 0.35, rot_y := 0.0) -> Tween:
	if _move_tw and _move_tw.is_running():
		_move_tw.kill()
	_move_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tw.tween_property(self, "position", pos, dur)
	_move_tw.tween_property(self, "rotation:y", rot_y, dur)
	return _move_tw

## Взлёт и посадка по дуге (покупка, перенос).
func arc_to(pos: Vector3, dur := 0.45, height := 1.2) -> Tween:
	var from := position
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := from.lerp(pos, t)
		p.y += sin(t * PI) * height
		position = p, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tw

func lunge(target: Vector3, dur := 0.32) -> Tween:
	var home := position
	var dir := (target - home)
	dir.y = 0
	var hit := home + dir.normalized() * minf(dir.length() * 0.55, 1.6) + Vector3(0, 0.25, 0)
	var tw := create_tween()
	tw.tween_property(self, "position", hit, dur * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position", home, dur * 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw

func shake(strength := 0.08) -> void:
	var home := pivot.position
	var tw := create_tween()
	for i in 4:
		tw.tween_property(pivot, "position", home + Vector3(randf_range(-strength, strength), 0, randf_range(-strength, strength) * 0.5), 0.04)
	tw.tween_property(pivot, "position", home, 0.05)

func pop(scale_to := 1.12) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * scale_to, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.18)

func die() -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(pivot, "rotation:x", -PI / 2, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(pivot, "position:y", 0.02, 0.35)
	tw.tween_method(set_dim, _dim, 0.35, 0.4)
	bars.visible = false
	return tw

func revive() -> void:
	set_tilt(true)
	set_dim(1.0)
	pop(1.15)

## Всплывающее число/текст над картой.
func float_text(text: String, col: Color, big := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = CardFaces.f_title
	l.font_size = 120 if big else 84
	l.pixel_size = 0.003
	l.modulate = col
	l.outline_size = 22
	l.outline_modulate = Color(0.1, 0.05, 0.03, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.position = position + Vector3(randf_range(-0.25, 0.25), 1.9, 0.2)
	get_parent().add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.9, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)
