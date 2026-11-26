extends Node
## Обучение для новичка: подсказки по шагам с золотой рамкой вокруг нужного места.
## Шаг завершается действием игрока (купил, поставил, начал бой) или кнопкой «Дальше».

signal finished

var game: Node
var step := -1
var coach: PanelContainer
var coach_text: Label
var btn_next: Button
var frame: Panel
var _pulse: Tween
var _battle_round := -1

const STEPS := [
	{"text": "Добро пожаловать на Козырную Арену! Цель — остаться последним, у кого есть ОЗ (здоровье). За минуту покажу главное.", "next": true},
	{"text": "Купите героя: нажмите на любую карту в магазине внизу. Цена — золотая цифра в правом верхнем углу карты.", "target": "shop", "done": "bought"},
	{"text": "Перетащите героя со скамьи (нижний ряд) на линию боя — светлые места в центре стола. Сражаются только герои на линии.", "target": "board", "done": "placed"},
	{"text": "Линия боя — это ваша покерная рука. Ранг героя — цифра или буква в углу карты. Два разных героя одного ранга — «Пара», три — «Тройка», пять подряд — «Стрит». Чем сильнее рука, тем сильнее весь отряд. Ваша рука — вверху и на табличке справа от линии.", "target": "hand", "next": true},
	{"text": "Стихии — союзы. 2 разных героя одной стихии (Лёд, Огонь, Свет, Природа) дают бонус, 4 — сильный бонус. Наведите на значок стихии вверху — увидите, какой.", "target": "traits", "next": true},
	{"text": "Нажмите «В бой!». Бой идёт сам; во время боя можно разыграть заклинания из руки магии (левый верхний угол).", "target": "fight", "done": "battle"},
	{"text": "Каждый раунд приносит 5 золота. «Новые карты» обновляют магазин, «Опыт +4» поднимает уровень — на линию помещается больше героев. Три одинаковых героя сами сливаются в ★★, три ★★ — в ★★★. Удачи на арене!", "target": "eco", "next": true, "last": true},
]

func setup(g: Node) -> void:
	game = g
	var root: Control = game.hud.root
	frame = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.85, 0.4, 0.06)
	sb.border_color = Color("f2c457")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	root.add_child(frame)
	coach = PanelContainer.new()
	coach.theme_type_variation = "TooltipPanel"
	coach.anchor_left = 0.5; coach.anchor_right = 0.5
	coach.offset_top = 64
	coach.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "ОБУЧЕНИЕ"
	title.theme_type_variation = "HeaderLabel"
	coach_text = Label.new()
	coach_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coach_text.custom_minimum_size.x = 560
	coach_text.add_theme_font_size_override("font_size", 17)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_theme_constant_override("separation", 8)
	var skip := Button.new()
	skip.text = "Пропустить обучение"
	skip.theme_type_variation = "GhostButton"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func(): Sfx.play("stone_soft"); finish())
	btn_next = Button.new()
	btn_next.text = "Дальше"
	btn_next.theme_type_variation = "GoldButton"
	btn_next.custom_minimum_size = Vector2(140, 40)
	btn_next.focus_mode = Control.FOCUS_NONE
	btn_next.pressed.connect(func(): Sfx.play("stone"); advance())
	h.add_child(skip); h.add_child(btn_next)
	v.add_child(title); v.add_child(coach_text); v.add_child(h)
	coach.add_child(v)
	root.add_child(coach)
	step = -1
	advance()

func advance() -> void:
	step += 1
	if step >= STEPS.size():
		finish()
		return
	var s: Dictionary = STEPS[step]
	coach_text.text = s.text
	btn_next.visible = s.get("next", false)
	btn_next.text = "Готово" if s.get("last", false) else "Дальше"
	game.hud.set_hint("")
	coach.modulate.a = 0
	coach.create_tween().tween_property(coach, "modulate:a", 1.0, 0.25)
	_place_frame()
	if String(s.get("done", "")) == "battle":
		_battle_round = game.m.round_n

func finish() -> void:
	frame.visible = false
	for n in game.table.slots:
		game.table.highlight_slot(n, 1.0)
	coach.queue_free()
	frame.queue_free()
	finished.emit()
	queue_free()

func _rect_of(ctrls: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for c in ctrls:
		if c == null or not (c as Control).is_visible_in_tree():
			continue
		var cr: Rect2 = (c as Control).get_global_rect()
		r = cr if first else r.merge(cr)
		first = false
	return r.grow(8)

func _target_rect() -> Rect2:
	var hud = game.hud
	match String(STEPS[step].get("target", "")):
		"shop": return _rect_of(hud.shop_buttons)
		"hand": return _rect_of([hud.hand_chip.get_parent()])
		"traits": return _rect_of([hud.trait_chips])
		"fight": return _rect_of([hud.btns["fight"], hud.btns["allin"]])
		"eco": return _rect_of([hud.btns["reroll"], hud.btns["xp"]])
		"board":
			var pts: Array = []
			for i in 5:
				pts.append(game.table.screen_pos(Table3D.pos_board(i)))
			var r := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				r = r.expand(p)
			return r.grow(90)
	return Rect2()

func _place_frame() -> void:
	var r := _target_rect()
	frame.visible = r.size != Vector2.ZERO
	if not frame.visible:
		return
	frame.position = r.position
	frame.size = r.size
	if _pulse:
		_pulse.kill()
	_pulse = frame.create_tween().set_loops()
	_pulse.tween_property(frame, "modulate:a", 0.35, 0.6)
	_pulse.tween_property(frame, "modulate:a", 1.0, 0.6)

func _process(_dt: float) -> void:
	if step < 0 or step >= STEPS.size():
		return
	var s: Dictionary = STEPS[step]
	if frame.visible:
		var r := _target_rect()
		if r.size != Vector2.ZERO:
			frame.position = r.position; frame.size = r.size
	# на шаге «поставьте на линию» мигают места линии
	if String(s.get("target", "")) == "board":
		var lv := 1.0 + 0.8 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0))
		for i in 5:
			game.table.highlight_slot("board:%d" % i, lv)
	var m: Match = game.m
	match String(s.get("done", "")):
		"bought":
			if not Rules.all_units(m.p).is_empty():
				advance()
		"placed":
			if Rules.board_count(m.p) > 0:
				for i in 5:
					game.table.highlight_slot("board:%d" % i, 1.0)
				advance()
		"battle":
			# во время боя и итога подсказка спрятана; новый раунд — следующий шаг
			var busy: bool = game.in_battle or m.phase != "shop"
			coach.visible = not busy
			frame.visible = not busy and frame.size != Vector2.ZERO
			if m.round_n > _battle_round and m.phase == "shop":
				coach.visible = true
				advance()
