class_name Hud
extends CanvasLayer
## Интерфейс поверх 3D-стола: верхняя панель, боковая панель (рука, союзы стихий, карта, журнал),
## нижняя панель (золото, кнопки, магазин), рука магии, подсказки, всплывающие сообщения, оверлеи.
## Сам ничего не решает: шлёт act(name, arg) в контроллер игры.

signal act(name: String, arg: Variant)

const SIDE_W := 300
const BOTTOM_H := 186
const TOP_H := 50

var root: Control
var top: PanelContainer
var side: PanelContainer
var bottom: PanelContainer
var lbl_round: Label
var bar_me: ProgressBar
var bar_foe: ProgressBar
var lbl_me: Label
var lbl_foe: Label
var lbl_foe_name: Label
var chips_box: HBoxContainer
var btn_sound: Button
# боковая панель
var hand_name: Label
var hand_bonus: Label
var hand_cards: HFlowContainer
var traits_grid: GridContainer
var info_box: VBoxContainer
var info_tex: TextureRect
var info_title: Label
var info_text: Label
var log_box: RichTextLabel
# нижняя панель
var lbl_gold: Label
var lbl_income: Label
var lbl_level: Label
var bar_xp: ProgressBar
var lbl_xp: Label
var lbl_odds: RichTextLabel
var btns := {}
var shop_box: HBoxContainer
var magic_box: HBoxContainer
var shop_buttons: Array = []
var magic_buttons: Array = []
var shop_grid: GridContainer
var speed_grid: GridContainer
# рука магии
var hand_box: HBoxContainer
var hand_title: Label
var hand_buttons: Array = []
# прочее
var hint: PanelContainer
var hint_lbl: Label
var toasts: VBoxContainer
var overlay: Control
var overlay_panel: PanelContainer
var banner: Label
var step_lbl: Label

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(root)
	_build_top()
	_build_side()
	_build_bottom()
	_build_hand()
	_build_misc()

# ---------- построение ----------
func _btn(text: String, action: String, variation := "", arg: Variant = null) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): act.emit(action, arg))
	return b

func _label(text := "", variation := "", size := 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l

func _build_top() -> void:
	top = PanelContainer.new()
	top.theme_type_variation = "BarPanel"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = TOP_H
	root.add_child(top)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	top.add_child(h)
	var brand := _label("КОЗЫРНАЯ АРЕНА", "TitleLabel", 18)
	brand.add_theme_color_override("font_color", UiTheme.GOLD)
	h.add_child(brand)
	var rp := PanelContainer.new()
	rp.theme_type_variation = "ChipPanel"
	rp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl_round = _label("Раунд 1", "TitleLabel", 15)
	rp.add_child(lbl_round)
	h.add_child(rp)
	h.add_child(_hp_block(true))
	h.add_child(_hp_block(false))
	chips_box = HBoxContainer.new()
	chips_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips_box.add_theme_constant_override("separation", 8)
	h.add_child(chips_box)
	btn_sound = _btn("Звук вкл.", "sound", "GhostButton")
	h.add_child(btn_sound)
	h.add_child(_btn("Правила", "rules", "GhostButton"))
	h.add_child(_btn("Меню", "menu", "GhostButton"))

func _hp_block(me: bool) -> Control:
	var v := HBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var ic := TextureRect.new()
	ic.texture = UiTheme.icon("heart")
	ic.custom_minimum_size = Vector2(22, 22)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var name_l := _label("Вы" if me else "Соперник", "MutedLabel", 15)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(170, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = Data.START_HP
	bar.value = Data.START_HP
	bar.show_percentage = false
	if not me:
		bar.theme_type_variation = "FoeBar"
	var val := _label("100", "TitleLabel", 18)
	v.add_child(ic); v.add_child(name_l); v.add_child(bar); v.add_child(val)
	if me:
		bar_me = bar; lbl_me = val
	else:
		bar_foe = bar; lbl_foe = val; lbl_foe_name = name_l
	return v

func _section(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_label(title.to_upper(), "HeaderLabel"))
	return v

func _build_side() -> void:
	side = PanelContainer.new()
	side.anchor_left = 1; side.anchor_right = 1; side.anchor_top = 0; side.anchor_bottom = 1
	side.offset_left = -SIDE_W - 10; side.offset_right = -10; side.offset_top = TOP_H + 10; side.offset_bottom = -BOTTOM_H - 20
	root.add_child(side)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	# рука
	var hs := _section("Ваша рука")
	hand_name = _label("Старшая карта", "TitleLabel", 24)
	hand_bonus = _label("без бонуса", "MutedLabel")
	hand_cards = HFlowContainer.new()
	hand_cards.add_theme_constant_override("h_separation", 4)
	hs.add_child(hand_name); hs.add_child(hand_cards); hs.add_child(hand_bonus)
	v.add_child(hs)
	v.add_child(HSeparator.new())
	# союзы
	var ts := _section("Союзы стихий")
	traits_grid = GridContainer.new()
	traits_grid.columns = 2
	traits_grid.add_theme_constant_override("h_separation", 6)
	traits_grid.add_theme_constant_override("v_separation", 6)
	ts.add_child(traits_grid)
	v.add_child(ts)
	v.add_child(HSeparator.new())
	# карта
	var cs := _section("Карта")
	info_box = VBoxContainer.new()
	var ih := HBoxContainer.new()
	info_tex = TextureRect.new()
	info_tex.custom_minimum_size = Vector2(96, 134)
	info_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	info_title = _label("", "TitleLabel", 17)
	info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(info_tex); ih.add_child(info_title)
	info_text = _label("Наведите на карту, чтобы увидеть способность.", "", 15)
	info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_text.custom_minimum_size.x = SIDE_W - 50
	info_box.add_child(ih); info_box.add_child(info_text)
	cs.add_child(info_box)
	v.add_child(cs)
	v.add_child(HSeparator.new())
	# журнал
	var ls := _section("Журнал боя")
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.fit_content = true
	log_box.scroll_active = false
	log_box.custom_minimum_size = Vector2(SIDE_W - 50, 60)
	log_box.add_theme_font_size_override("normal_font_size", 14)
	log_box.add_theme_color_override("default_color", UiTheme.MUTED)
	ls.add_child(log_box)
	v.add_child(ls)

func _build_bottom() -> void:
	bottom = PanelContainer.new()
	bottom.anchor_left = 0; bottom.anchor_right = 1; bottom.anchor_top = 1; bottom.anchor_bottom = 1
	bottom.offset_top = -BOTTOM_H - 10; bottom.offset_bottom = -10; bottom.offset_left = 10; bottom.offset_right = -10
	root.add_child(bottom)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	bottom.add_child(h)
	# экономика
	var econ := VBoxContainer.new()
	econ.custom_minimum_size.x = 180
	econ.add_theme_constant_override("separation", 4)
	var gh := HBoxContainer.new()
	var coin := TextureRect.new()
	coin.texture = UiTheme.icon("coin")
	coin.custom_minimum_size = Vector2(28, 28)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lbl_gold = _label("0", "TitleLabel", 30)
	lbl_income = _label("", "MutedLabel")
	gh.add_child(coin); gh.add_child(lbl_gold); gh.add_child(lbl_income)
	lbl_level = _label("Уровень 1 · поле до 2 карт", "", 15)
	bar_xp = ProgressBar.new()
	bar_xp.theme_type_variation = "XpBar"
	bar_xp.custom_minimum_size = Vector2(180, 8)
	bar_xp.show_percentage = false
	lbl_xp = _label("", "MutedLabel")
	lbl_odds = RichTextLabel.new()
	lbl_odds.bbcode_enabled = true
	lbl_odds.fit_content = true
	lbl_odds.scroll_active = false
	lbl_odds.custom_minimum_size = Vector2(200, 22)
	lbl_odds.add_theme_font_size_override("normal_font_size", 13)
	lbl_odds.custom_minimum_size = Vector2(200, 22)
	econ.add_child(gh); econ.add_child(lbl_level); econ.add_child(bar_xp); econ.add_child(lbl_xp); econ.add_child(lbl_odds)
	h.add_child(econ)
	# кнопки магазина
	shop_grid = GridContainer.new()
	shop_grid.columns = 2
	shop_grid.add_theme_constant_override("h_separation", 8)
	shop_grid.add_theme_constant_override("v_separation", 8)
	for spec in [["reroll", "Обновить  2", "BlueButton"], ["xp", "Опыт +4  4", "BlueButton"], ["lock", "Закрепить", ""],
			["sell", "Продать", ""], ["allin", "Ва-банк", "RedButton"], ["fight", "В бой!", "GoldButton"]]:
		var b := _btn(spec[1], spec[0], spec[2])
		b.custom_minimum_size = Vector2(128, 40)
		btns[spec[0]] = b
		shop_grid.add_child(b)
	h.add_child(shop_grid)
	# кнопки боя (скорость)
	speed_grid = GridContainer.new()
	speed_grid.columns = 2
	speed_grid.add_theme_constant_override("h_separation", 8)
	speed_grid.add_theme_constant_override("v_separation", 8)
	for spec in [["speed", "Скорость ×1", 1], ["speed", "Скорость ×2", 2], ["speed", "Скорость ×4", 4], ["skip", "Пропустить", null]]:
		var b := _btn(spec[1], spec[0], "", spec[2])
		b.custom_minimum_size = Vector2(128, 40)
		btns["%s%s" % [spec[0], str(spec[2]) if spec[2] != null else ""]] = b
		speed_grid.add_child(b)
	speed_grid.visible = false
	h.add_child(speed_grid)
	# витрина
	shop_box = HBoxContainer.new()
	shop_box.add_theme_constant_override("separation", 8)
	shop_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_box.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 5:
		var tb := _card_button("buy", i, 112)
		shop_buttons.append(tb)
		shop_box.add_child(tb)
	var sep := VSeparator.new()
	shop_box.add_child(sep)
	for i in 2:
		var tb := _card_button("buy_magic", i, 112)
		magic_buttons.append(tb)
		shop_box.add_child(tb)
	h.add_child(shop_box)

func _card_button(action: String, i: int, w := 120) -> TextureButton:
	var tb := TextureButton.new()
	tb.ignore_texture_size = true
	tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	tb.custom_minimum_size = Vector2(w, w * 1.4)
	tb.focus_mode = Control.FOCUS_NONE
	tb.pressed.connect(func(): act.emit(action, i))
	var big := w >= 100
	for spec in [["st", Vector2(0.5, 0), HORIZONTAL_ALIGNMENT_CENTER], ["tl", Vector2(0, 0), HORIZONTAL_ALIGNMENT_LEFT], ["tr", Vector2(1, 0), HORIZONTAL_ALIGNMENT_RIGHT],
			["bl", Vector2(0, 1), HORIZONTAL_ALIGNMENT_LEFT], ["br", Vector2(1, 1), HORIZONTAL_ALIGNMENT_RIGHT]]:
		var l := Label.new()
		l.name = spec[0]
		l.theme_type_variation = "TitleLabel"
		l.add_theme_font_size_override("font_size", 17 if big else 15)
		l.add_theme_constant_override("outline_size", 7)
		l.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.05, 0.95))
		l.horizontal_alignment = spec[2]
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.anchor_left = spec[1].x; l.anchor_right = spec[1].x
		l.anchor_top = spec[1].y; l.anchor_bottom = spec[1].y
		var lw := 60.0
		l.offset_left = 4.0 if spec[1].x == 0 else (-lw - 4.0 if spec[1].x == 1 else -lw)
		l.offset_right = lw + 4.0 if spec[1].x == 0 else (-4.0 if spec[1].x == 1 else lw)
		l.offset_top = 0.0 if spec[1].y == 0 else -24.0
		l.offset_bottom = 24.0 if spec[1].y == 0 else 0.0
		tb.add_child(l)
	tb.mouse_entered.connect(func():
		act.emit("hover_" + action, i)
		var tw := tb.create_tween()
		tw.tween_property(tb, "position:y", -10.0, 0.12).as_relative())
	tb.mouse_exited.connect(func():
		act.emit("hover_none", null)
		var tw := tb.create_tween()
		tw.tween_property(tb, "position:y", 10.0, 0.12).as_relative())
	return tb

func _build_hand() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(16, TOP_H + 10)
	root.add_child(v)
	hand_title = _label("Рука магии 0/5", "HeaderLabel", 16)
	v.add_child(hand_title)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 6)
	v.add_child(hand_box)
	for i in Data.HAND_MAX:
		var tb := _card_button("hand", i, 74)
		hand_buttons.append(tb)
		hand_box.add_child(tb)

func _build_misc() -> void:
	hint = PanelContainer.new()
	hint.theme_type_variation = "TooltipPanel"
	hint.anchor_left = 0.5; hint.anchor_right = 0.5
	hint.offset_top = TOP_H + 12
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_lbl = _label("", "", 16)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.custom_minimum_size.x = 520
	hint.add_child(hint_lbl)
	root.add_child(hint)
	step_lbl = _label("", "TitleLabel", 24)
	step_lbl.anchor_left = 0.5; step_lbl.anchor_right = 0.5
	step_lbl.offset_top = TOP_H + 70
	step_lbl.offset_left = -200; step_lbl.offset_right = 200 - SIDE_W
	step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_lbl.add_theme_constant_override("outline_size", 10)
	step_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.03))
	root.add_child(step_lbl)
	banner = _label("", "TitleLabel", 52)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 18)
	banner.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.03))
	banner.modulate.a = 0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)
	toasts = VBoxContainer.new()
	toasts.anchor_left = 0.5; toasts.anchor_right = 0.5
	toasts.offset_top = TOP_H + 130
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.05, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	overlay_panel = PanelContainer.new()
	overlay_panel.theme_type_variation = "ParchmentPanel"
	cc.add_child(overlay_panel)
	root.add_child(overlay)

# ---------- обновление ----------
func set_hp(me: int, foe: int, foe_name := "Соперник") -> void:
	bar_me.value = me; lbl_me.text = str(me)
	bar_foe.value = foe; lbl_foe.text = str(foe)
	lbl_foe_name.text = foe_name

func set_chips(items: Array) -> void:
	for c in chips_box.get_children():
		c.queue_free()
	for t in items:
		var p := PanelContainer.new()
		p.theme_type_variation = "ChipPanel"
		var l := _label(t, "", 15)
		p.add_child(l)
		chips_box.add_child(p)

func set_hand_info(hand_key: String, cards: Array, traits: Dictionary) -> void:
	hand_name.text = Data.HANDS[hand_key].n
	hand_bonus.text = Data.hand_text(hand_key)
	for c in hand_cards.get_children():
		c.queue_free()
	for u in cards:
		var d: Dictionary = Data.HEROES[u.id]
		var p := PanelContainer.new()
		p.theme_type_variation = "ChipPanel"
		var l := _label(Rules.rank_label(int(d.r)) + Data.SUITS[d.s].sym, "TitleLabel", 17)
		l.add_theme_color_override("font_color", Data.SUITS[d.s].color.lightened(0.35))
		p.add_child(l)
		hand_cards.add_child(p)
	for c in traits_grid.get_children():
		c.queue_free()
	for s in ["S", "H", "D", "C"]:
		var su: Dictionary = Data.SUITS[s]
		var n: int = traits.n[s]
		var lv: int = traits.lv[s]
		var cell := PanelContainer.new()
		cell.theme_type_variation = "ChipPanel"
		cell.custom_minimum_size = Vector2(126, 62)
		cell.modulate = Color.WHITE if lv > 0 else Color(1, 1, 1, 0.6)
		var hb := HBoxContainer.new()
		var em := TextureRect.new()
		em.texture = UiTheme.icon("element_" + String(su.key))
		em.custom_minimum_size = Vector2(26, 26)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		em.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		var t := _label("%s %d/%d" % [su.name, n, 2 if n < 2 else 4], "TitleLabel", 15)
		t.add_theme_color_override("font_color", su.color.lightened(0.4))
		var dsc := _label(Data.trait_text(s, max(lv, 1)), "MutedLabel", 13)
		dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dsc.custom_minimum_size.x = 82
		vb.add_child(t); vb.add_child(dsc)
		hb.add_child(em); hb.add_child(vb)
		cell.add_child(hb)
		traits_grid.add_child(cell)

func show_info(tex: Texture2D, title: String, text: String) -> void:
	info_tex.texture = tex
	info_title.text = title
	info_text.text = text

func add_log(text: String, col := "") -> void:
	if col != "":
		log_box.append_text("[color=%s]%s[/color]\n" % [col, text])
	else:
		log_box.append_text(text + "\n")
	var lines := log_box.get_parsed_text().split("\n")
	if lines.size() > 40:
		log_box.clear()
		log_box.append_text("\n".join(lines.slice(lines.size() - 30)))

func clear_log() -> void:
	log_box.clear()

func set_econ(gold: int, income_text: String, level: int, xp: int, xp_need: int, cap: int) -> void:
	lbl_gold.text = str(gold)
	lbl_income.text = income_text
	lbl_level.text = "Уровень %d · поле до %d карт" % [level, cap]
	bar_xp.max_value = maxi(1, xp_need)
	bar_xp.value = xp if xp_need > 0 else xp_need
	lbl_xp.text = ("%d/%d опыта" % [xp, xp_need]) if xp_need > 0 else "Максимальный уровень"
	var o: Array = Data.ODDS[level]
	var cols := ["#c9bfae", "#7fc77a", "#6fa3e8", "#c07ad8", "#f0c24f"]
	var parts := []
	for i in 5:
		parts.append("[color=%s]%d%%[/color]" % [cols[i], o[i]])
	lbl_odds.text = "Шансы: " + "  ".join(parts)

func set_shop(ids: Array, gold: int) -> void:
	for i in shop_buttons.size():
		var tb: TextureButton = shop_buttons[i]
		var id = ids[i] if i < ids.size() else null
		tb.visible = true
		if id == null:
			tb.texture_normal = null
			_corner(tb, "", "", "", "", Color.WHITE)
			tb.disabled = true
			tb.modulate = Color(1, 1, 1, 0)
		else:
			tb.texture_normal = CardFaces.face(id, 1)
			tb.disabled = false
			var d: Dictionary = Data.HEROES[id]
			var st: Dictionary = Rules.stats({"id": id, "star": 1})
			_corner(tb, Rules.rank_label(int(d.r)) + Data.SUITS[d.s].sym, str(d.c), str(st.atk), str(st.hp), Data.SUITS[d.s].color.lightened(0.45))
			tb.modulate = Color.WHITE if gold >= int(Data.HEROES[id].c) else Color(0.55, 0.5, 0.5, 1)

func set_magic_shop(keys: Array, gold: int, round_n: int) -> void:
	for i in magic_buttons.size():
		var tb: TextureButton = magic_buttons[i]
		var k = keys[i] if i < keys.size() else null
		if k == null:
			tb.texture_normal = null
			_corner(tb, "", "", "", "", Color.WHITE)
			tb.modulate = Color(1, 1, 1, 0)
		else:
			tb.texture_normal = CardFaces.magic_face(k, round_n)
			_corner(tb, str(Data.MAGIC[k].c), "", "", "", UiTheme.GOLD)
			tb.modulate = Color.WHITE if gold >= int(Data.MAGIC[k].c) else Color(0.55, 0.5, 0.5, 1)

## Подписи на карточной кнопке: ранг (tl), цена (tr), АТК (bl), ОЗ (br).
func _corner(tb: TextureButton, tl: String, tr: String, bl: String, br: String, tl_col: Color) -> void:
	var a: Label = tb.get_node("tl"); a.text = tl; a.add_theme_color_override("font_color", tl_col)
	(tb.get_node("st") as Label).text = ""
	var b: Label = tb.get_node("tr"); b.text = tr; b.add_theme_color_override("font_color", UiTheme.GOLD)
	var c: Label = tb.get_node("bl"); c.text = bl; c.add_theme_color_override("font_color", Color("ff9b8f"))
	var d: Label = tb.get_node("br"); d.text = br; d.add_theme_color_override("font_color", Color("8ff0b0"))

var zoom: TextureButton
var zoom_box: Control

func _build_zoom() -> void:
	zoom_box = Control.new()
	zoom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_box.visible = false
	root.add_child(zoom_box)
	zoom = _card_button("zoom", 0, 250)
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l in zoom.get_children():
		(l as Label).add_theme_font_size_override("font_size", 30)
		(l as Label).add_theme_constant_override("outline_size", 10)
		(l as Label).offset_top *= 1.4; (l as Label).offset_bottom *= 1.4
	zoom_box.add_child(zoom)

## Увеличенная карта героя рядом с курсором/картой (всё читается).
func show_zoom_hero(u: Dictionary, near: Vector2) -> void:
	if zoom == null:
		_build_zoom()
	var d: Dictionary = Data.HEROES[u.id]
	var st: Dictionary = Rules.stats(u)
	zoom.texture_normal = CardFaces.face(u.id, int(u.star), u.get("items", []), u.get("fed"))
	_corner(zoom, Rules.rank_label(int(d.r)) + Data.SUITS[d.s].sym, str(d.c), str(st.atk), str(st.hp), Data.SUITS[d.s].color.lightened(0.45))
	var sl: Label = zoom.get_node("st")
	sl.text = "★".repeat(int(u.star)) if int(u.star) > 1 else ""
	sl.add_theme_color_override("font_color", Color("ffd45a") if int(u.star) >= 3 else Color("eef3ff"))
	var vs := root.get_viewport_rect().size
	var sz := zoom.custom_minimum_size
	var pos := near + Vector2(110, -sz.y * 0.6)
	if pos.x + sz.x > vs.x - SIDE_W - 20:
		pos.x = near.x - 110 - sz.x
	pos.y = clampf(pos.y, TOP_H + 8, vs.y - BOTTOM_H - sz.y - 24)
	zoom_box.position = pos
	zoom_box.visible = true

func hide_zoom() -> void:
	if zoom_box:
		zoom_box.visible = false

func set_hand(keys: Array, round_n: int, selected := -1, battle := false) -> void:
	hand_title.text = ("Рука магии · заклинаний за бой" if battle else "Рука магии %d/%d") % ([] if battle else [keys.size(), Data.HAND_MAX])
	for i in hand_buttons.size():
		var tb: TextureButton = hand_buttons[i]
		if i < keys.size():
			tb.visible = true
			tb.texture_normal = CardFaces.magic_face(keys[i], round_n)
			_corner(tb, "", "", "", "", Color.WHITE)
			var usable: bool = (Data.MAGIC[keys[i]].k == "spell") == battle
			tb.modulate = Color(1.15, 1.08, 0.9) if i == selected else (Color.WHITE if usable else Color(0.6, 0.6, 0.6, 0.85))
		else:
			tb.visible = false

func set_buttons(state: Dictionary) -> void:
	for k in state:
		if btns.has(k):
			var b: Button = btns[k]
			var s = state[k]
			if s is bool:
				b.disabled = not s
			elif s is Dictionary:
				if s.has("text"): b.text = s.text
				if s.has("on"): b.disabled = not s.on
				if s.has("visible"): b.visible = s.visible

func set_battle_mode(on: bool, speed := 2) -> void:
	shop_grid.visible = not on
	speed_grid.visible = on
	for s in [1, 2, 4]:
		var b: Button = btns["speed%d" % s]
		b.theme_type_variation = "GoldButton" if s == speed else ""

func set_hint(text: String) -> void:
	hint.visible = text != ""
	hint_lbl.text = text

func set_step(text: String) -> void:
	step_lbl.text = text

func toast(text: String, kind := "") -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "TooltipPanel"
	var l := _label(text, "", 16)
	if kind == "bad":
		l.add_theme_color_override("font_color", Color("ffb3a8"))
	elif kind == "good":
		l.add_theme_color_override("font_color", Color("ffe2a0"))
	p.add_child(l)
	toasts.add_child(p)
	p.modulate.a = 0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()

func show_banner(text: String, col := Color("f3cf73")) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	banner.pivot_offset = banner.size / 2
	var tw := banner.create_tween()
	banner.scale = Vector2(0.7, 0.7)
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.18)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.9)
	tw.chain().tween_property(banner, "modulate:a", 0.0, 0.3)

## Оверлей с произвольным содержимым (Control). null — скрыть.
func show_overlay(content: Control, dim := true) -> void:
	for c in overlay_panel.get_children():
		c.queue_free()
	overlay.visible = content != null
	(overlay.get_child(0) as ColorRect).visible = dim
	if content:
		overlay_panel.add_child(content)

func feeding(on: bool) -> void:
	for n in [top, side, bottom, hand_box]:
		n.modulate = Color(0.45, 0.42, 0.42) if on else Color.WHITE
