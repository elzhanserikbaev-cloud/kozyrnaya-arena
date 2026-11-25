class_name Table3D
extends Node3D
## 3D-сцена: деревянный стол с сукном-картой арены, мягкий тёплый свет с тенями (без свечения),
## места для карт (линии врага и игрока, скамья, продажа), камера и выбор мышью.
## Координаты повторяют web-версию: Babylon (x, y, z) → Godot (x, y, -z).

signal card_pressed(card: Card3D, button: int)
signal slot_pressed(zone: String, index: int, button: int)
signal empty_pressed(button: int)
signal hover_changed(card: Card3D)

const BOARD_N := 5
const BENCH_N := 6

var camera: Camera3D
var cam_target := Vector3(0, 0, 1.3)
var cam_yaw := 0.0
var cam_pitch := 0.6          # от вертикали, как beta в Babylon
var cam_dist := 10.2
var key_light: DirectionalLight3D
var fill_light: OmniLight3D
var env: Environment
var slots := {}                # "board:i" / "bench:i" / "sell" → MeshInstance3D
var slot_mats := {}
var hovered: Card3D
var side_px := 360.0
var top_px := 76.0
var bottom_px := 210.0

static func pos_board(i: int) -> Vector3: return Vector3((i - 2) * 1.55, 0, 1.95)
static func pos_enemy(i: int) -> Vector3: return Vector3((i - 2) * 1.55, 0, -2.1)
static func pos_bench(i: int) -> Vector3: return Vector3(-4.55 + i * 1.32, 0, 4.4)
static func pos_sell() -> Vector3: return Vector3(4.15, 0, 4.4)

func _ready() -> void:
	_build_env()
	_build_table()
	_build_slots()
	_build_camera()

func _tex(p: String) -> Texture2D:
	return load(p) if ResourceLoader.exists(p) else null

func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("141a22")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f2dcc0")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = false            # без неона
	env.fog_enabled = true
	env.fog_light_color = Color("141a22")
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	we.environment = env
	add_child(we)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-62, -28, 0)
	key_light.light_color = Color("fff0d8")
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	key_light.shadow_blur = 1.6
	key_light.directional_shadow_max_distance = 30.0
	key_light.shadow_opacity = 0.55
	add_child(key_light)
	fill_light = OmniLight3D.new()
	fill_light.position = Vector3(0, 5.5, 6)
	fill_light.light_color = Color("ffd9b0")
	fill_light.light_energy = 0.6
	fill_light.omni_range = 18
	add_child(fill_light)

func _mat(tex: Texture2D, col := Color.WHITE, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if tex:
		m.albedo_texture = tex
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _build_table() -> void:
	var sx := 1.3   # стол овальный, как в web-версии
	# сукно
	var felt := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 7.1; fm.bottom_radius = 7.1; fm.height = 0.04; fm.radial_segments = 128
	felt.mesh = fm
	felt.scale = Vector3(sx, 1, 1)
	felt.position.y = -0.02
	var felt_tex := _tex("res://assets/table/felt.png")
	var feltm := _mat(felt_tex, Color.WHITE if felt_tex else Color("1f5a5a"), 0.92)
	feltm.uv1_triplanar = false
	felt.material_override = feltm
	felt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(felt)
	# у цилиндра верх развёрнут не по кругу — кладём текстуру отдельным диском-плоскостью
	if felt_tex:
		var top := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(14.2, 14.2)
		top.mesh = pm
		top.scale = Vector3(sx, 1, 1)
		top.position.y = 0.002
		var tm := _mat(felt_tex, Color.WHITE, 0.92)
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		top.material_override = tm
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(top)
	# деревянный борт
	var wood := _tex("res://assets/table/stone_rim.png")
	var wm := _mat(wood, Color.WHITE if wood else Color("4a5566"), 0.7)
	wm.uv1_scale = Vector3(8, 1, 1)
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 6.97; tor.outer_radius = 7.62; tor.rings = 128; tor.ring_segments = 24
	rim.mesh = tor
	rim.scale = Vector3(sx, 1, 1)
	rim.position.y = 0.05
	rim.material_override = wm
	add_child(rim)
	# латунная вставка
	var inlay := MeshInstance3D.new()
	var t2 := TorusMesh.new(); t2.inner_radius = 6.98; t2.outer_radius = 7.08; t2.rings = 128; t2.ring_segments = 8
	inlay.mesh = t2
	inlay.scale = Vector3(sx, 1, 1)
	inlay.position.y = 0.09
	inlay.material_override = _mat(null, Color("b89350"), 0.35, 0.8)
	add_child(inlay)
	# основание и ножка
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new(); bc.top_radius = 7.3; bc.bottom_radius = 7.1; bc.height = 0.7; bc.radial_segments = 96
	base.mesh = bc; base.scale = Vector3(sx, 1, 1); base.position.y = -0.38
	base.material_override = wm
	add_child(base)
	var ped := MeshInstance3D.new()
	var pc := CylinderMesh.new(); pc.top_radius = 2.5; pc.bottom_radius = 3.5; pc.height = 4.0
	ped.mesh = pc; ped.position.y = -2.7
	ped.material_override = _mat(null, Color("2a3038"), 0.8)
	add_child(ped)
	# пол
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new(); fp.size = Vector2(80, 80)
	floor_mi.mesh = fp
	floor_mi.position.y = -4.7
	var flt := _tex("res://assets/table/floor.png")
	var flm := _mat(flt, Color.WHITE if flt else Color("2a1d16"), 0.9)
	flm.uv1_scale = Vector3(10, 10, 1)
	floor_mi.material_override = flm
	add_child(floor_mi)

func _build_slots() -> void:
	var st := _tex("res://assets/ui/slot.png")
	var sb := _tex("res://assets/ui/slot_bench.png")
	for i in BOARD_N:
		_slot("board:%d" % i, pos_board(i), st, Color(1, 0.93, 0.78, 0.55))
		_slot("eboard:%d" % i, pos_enemy(i), st, Color(1, 0.8, 0.8, 0.28))
	for i in BENCH_N:
		_slot("bench:%d" % i, pos_bench(i), sb if sb else st, Color(1, 0.93, 0.78, 0.4))
	var sell := _tex("res://assets/ui/sell.png")
	_slot("sell", pos_sell(), sell if sell else st, Color(1, 0.75, 0.7, 0.45))

func _slot(name_: String, p: Vector3, tex: Texture2D, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new(); q.size = Vector2(Card3D.W + 0.08, Card3D.H + 0.08)
	mi.mesh = q
	mi.position = p + Vector3(0, 0.006, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if tex:
		m.albedo_texture = tex
	else:
		m.albedo_color = Color(col.r, col.g, col.b, col.a * 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(Card3D.W + 0.1, 0.05, Card3D.H + 0.1)
	cs.shape = bs
	body.add_child(cs)
	body.set_meta("slot", name_)
	mi.add_child(body)
	add_child(mi)
	slots[name_] = mi
	slot_mats[name_] = {"mat": m, "base": m.albedo_color}

## Подсветка мест: alpha 0..1 (1 = обычная видимость, >1 — выделено).
func highlight_slot(name_: String, level: float) -> void:
	if not slot_mats.has(name_):
		return
	var s: Dictionary = slot_mats[name_]
	var c: Color = s.base
	if level > 1.0:
		s.mat.albedo_color = Color(1.0, 0.86, 0.5, minf(1.0, c.a * 1.8))
	else:
		s.mat.albedo_color = Color(c.r, c.g, c.b, c.a * level)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 200
	add_child(camera)
	_update_camera()
	get_viewport().size_changed.connect(_frame)
	_frame()

func _frame() -> void:
	var vs := get_viewport().get_visible_rect().size
	var a := vs.x / maxf(1.0, vs.y)
	# интерфейс закрывает правую колонку и низ: сдвигаем кадр, чтобы стол оказался в свободной части
	var free_w := vs.x - side_px
	var free_h := vs.y - top_px - bottom_px
	var fa := free_w / maxf(1.0, free_h)
	cam_dist = 14.8 * pow(maxf(1.0, 1.9 / fa), 0.8) * clampf(900.0 / maxf(1.0, vs.y), 0.85, 1.25) ** 0.0
	_update_camera()
	# смещение проекции: центр свободной области относительно центра экрана, в долях
	var cx := (free_w * 0.5) / vs.x - 0.5
	var cy := (top_px + free_h * 0.5) / vs.y - 0.5
	var half_h := tan(deg_to_rad(camera.fov * 0.5)) * cam_dist
	camera.h_offset = -cx * 2.0 * half_h * a
	camera.v_offset = cy * 2.0 * half_h

func _update_camera() -> void:
	var off := Vector3(sin(cam_yaw) * sin(cam_pitch), cos(cam_pitch), cos(cam_yaw) * sin(cam_pitch)) * cam_dist
	camera.position = cam_target + off
	camera.look_at(cam_target, Vector3.UP)

# ---------- ввод ----------
var _rot_drag := false

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_dist = clampf(cam_dist * 0.94, 8.0, 20.0); _update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_dist = clampf(cam_dist * 1.06, 8.0, 20.0); _update_camera()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rot_drag = mb.pressed
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _rot_drag:
			cam_yaw = clampf(cam_yaw - mm.relative.x * 0.005, -0.7, 0.7)
			cam_pitch = clampf(cam_pitch - mm.relative.y * 0.004, 0.25, 1.1)
			_update_camera()
		else:
			var c := pick_card(mm.position)
			if c != hovered:
				hovered = c
				hover_changed.emit(c)

## Луч из точки экрана: возвращает {card} или {slot} или {} и точку на столе.
func pick(screen: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var res := {}
	if hit:
		var col: Object = hit.collider
		if col.has_meta("card"):
			res.card = col.get_meta("card")
		elif col.has_meta("slot"):
			res.slot = col.get_meta("slot")
		res.point = hit.position
	var t := -from.y / dir.y if absf(dir.y) > 0.0001 else 0.0
	res.table_point = from + dir * t
	return res

func pick_card(screen: Vector2) -> Card3D:
	var r := pick(screen)
	return r.get("card")

## Ближайшее место к точке на столе (для перетаскивания).
func nearest_slot(p: Vector3, prefixes: Array) -> String:
	var best := ""
	var bd := 1.2
	for n in slots:
		var ok := false
		for pre in prefixes:
			if String(n).begins_with(pre):
				ok = true
		if not ok:
			continue
		var d := Vector2(p.x - slots[n].position.x, p.z - slots[n].position.z).length()
		if d < bd:
			bd = d; best = n
	return best

## Затемнение сцены (режим жертвоприношения).
func set_dark(on: bool) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(key_light, "light_energy", 0.45 if on else 1.25, 0.3)
	tw.tween_property(fill_light, "light_energy", 0.2 if on else 0.6, 0.3)
	tw.tween_property(env, "ambient_light_energy", 0.22 if on else 0.55, 0.3)

func screen_pos(p: Vector3) -> Vector2:
	return camera.unproject_position(p)
