class_name UiTheme
extends RefCounted
## Тема интерфейса из запечённых ассетов (assets/ui + ui_manifest.json).
## Варианты кнопок: theme_type_variation = "GoldButton" | "RedButton" | "BlueButton" | "WoodButton" (по умолчанию).
## Панели: "Panel" (дерево + пергамент), "DarkPanel" (тёмное дерево), "Chip", "Tooltip".

const UI := "res://assets/ui/"
const INK := Color("3a2614")          # текст на пергаменте
const CREAM := Color("fbf0d8")        # текст на дереве
const GOLD := Color("f3cf73")
const MUTED := Color("d9c6a5")

static var _manifest := {}
static var theme: Theme
static var f_title: Font
static var f_body: Font
static var f_bold: Font
static var f_medium: Font

static func _margins(file: String, def: Array) -> Array:
	if _manifest.is_empty() and FileAccess.file_exists(UI + "ui_manifest.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string(UI + "ui_manifest.json"))
		if j is Dictionary:
			for k in j:
				var v = j[k]
				if v is Dictionary and v.has("margins"):
					_manifest[String(v.get("file", k)).get_file()] = v.margins
			if j.has("items") and j.items is Array:
				for v in j.items:
					_manifest[String(v.file).get_file()] = v.margins
		elif j is Array:
			for v in j:
				_manifest[String(v.file).get_file()] = v.margins
	return _manifest.get(file, def)

static func box(file: String, def_margins := [24, 24, 24, 24], content := Vector4(14, 10, 14, 10), fallback := Color("5a3a22")) -> StyleBox:
	var path := UI + file
	if ResourceLoader.exists(path):
		var sb := StyleBoxTexture.new()
		sb.texture = load(path)
		var m: Array = _margins(file, def_margins)
		sb.texture_margin_left = m[0]; sb.texture_margin_top = m[1]
		sb.texture_margin_right = m[2]; sb.texture_margin_bottom = m[3]
		sb.content_margin_left = content.x; sb.content_margin_top = content.y
		sb.content_margin_right = content.z; sb.content_margin_bottom = content.w
		return sb
	var f := StyleBoxFlat.new()
	f.bg_color = fallback
	f.set_corner_radius_all(12)
	f.border_color = Color("c9973f")
	f.set_border_width_all(2)
	f.content_margin_left = content.x; f.content_margin_top = content.y
	f.content_margin_right = content.z; f.content_margin_bottom = content.w
	f.shadow_color = Color(0, 0, 0, 0.35); f.shadow_size = 6; f.shadow_offset = Vector2(0, 3)
	return f

static func icon(name: String) -> Texture2D:
	var p := UI + name + ".png"
	return load(p) if ResourceLoader.exists(p) else null

static func build() -> Theme:
	if theme:
		return theme
	f_title = CardFaces.f_title
	f_body = CardFaces.f_body
	f_bold = CardFaces.f_bold
	f_medium = CardFaces.f_body
	if ResourceLoader.exists("res://assets/fonts/Rubik-Medium.ttf"):
		f_medium = load("res://assets/fonts/Rubik-Medium.ttf")
	theme = Theme.new()
	theme.default_font = f_body
	theme.default_font_size = 17
	# Label
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_constant("shadow_offset_x", "Label", 0)
	for v in ["TitleLabel", "HeaderLabel"]:
		theme.set_type_variation(v, "Label")
		theme.set_font("font", v, f_title)
		theme.set_color("font_color", v, GOLD)
	theme.set_font_size("font_size", "TitleLabel", 40)
	theme.set_font_size("font_size", "HeaderLabel", 21)
	theme.set_type_variation("InkLabel", "Label")
	theme.set_color("font_color", "InkLabel", INK)
	theme.set_color("font_shadow_color", "InkLabel", Color(0, 0, 0, 0))
	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", MUTED)
	theme.set_font_size("font_size", "MutedLabel", 15)
	# Кнопки
	_button("Button", "wood", CREAM)
	_button("WoodButton", "wood", CREAM)
	_button("GoldButton", "gold", Color("3a1e08"))
	_button("RedButton", "red", Color("fff0e0"))
	_button("BlueButton", "blue", Color("f2f7ff"))
	theme.set_font_size("font_size", "GoldButton", 24)
	# Панели
	theme.set_stylebox("panel", "PanelContainer", box("panel_dark.png", [38, 38, 38, 38], Vector4(30, 24, 30, 24), Color("3b2418")))
	theme.set_type_variation("ParchmentPanel", "PanelContainer")
	theme.set_stylebox("panel", "ParchmentPanel", box("panel.png", [48, 48, 48, 48], Vector4(52, 46, 52, 46), Color("e9d6ad")))
	theme.set_type_variation("ChipPanel", "PanelContainer")
	theme.set_stylebox("panel", "ChipPanel", box("chip.png", [20, 18, 20, 18], Vector4(14, 8, 14, 8), Color("2d1b12")))
	theme.set_type_variation("TooltipPanel", "PanelContainer")
	theme.set_stylebox("panel", "TooltipPanel", box("tooltip.png", [22, 22, 22, 22], Vector4(20, 14, 20, 14), Color("2a1a12")))
	theme.set_type_variation("RibbonPanel", "PanelContainer")
	theme.set_stylebox("panel", "RibbonPanel", box("ribbon.png", [90, 10, 90, 10], Vector4(70, 8, 70, 12), Color("8a2a22")))
	# Поля ввода
	var le := StyleBoxFlat.new()
	le.bg_color = Color("f3e3bf"); le.set_corner_radius_all(10); le.border_color = Color("8a6232"); le.set_border_width_all(2)
	le.content_margin_left = 12; le.content_margin_right = 12; le.content_margin_top = 8; le.content_margin_bottom = 8
	theme.set_stylebox("normal", "LineEdit", le)
	var lf := le.duplicate(); lf.border_color = Color("d8a640")
	theme.set_stylebox("focus", "LineEdit", lf)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(0.23, 0.15, 0.08, 0.5))
	theme.set_color("caret_color", "LineEdit", INK)
	theme.set_font("font", "LineEdit", f_medium)
	# Прокрутка и подсказки
	var tip := box("tooltip.png", [20, 20, 20, 20], Vector4(12, 8, 12, 8), Color("2a1a12"))
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", CREAM)
	var sg := StyleBoxFlat.new(); sg.bg_color = Color(0.85, 0.65, 0.3, 0.6); sg.set_corner_radius_all(4)
	theme.set_stylebox("grabber", "VScrollBar", sg)
	theme.set_stylebox("grabber_highlight", "VScrollBar", sg)
	theme.set_stylebox("grabber_pressed", "VScrollBar", sg)
	var sc := StyleBoxFlat.new(); sc.bg_color = Color(0, 0, 0, 0.2); sc.set_corner_radius_all(4); sc.content_margin_left = 5; sc.content_margin_right = 5
	theme.set_stylebox("scroll", "VScrollBar", sc)
	# Полоски
	theme.set_stylebox("background", "ProgressBar", box("bar_frame.png", [14, 10, 14, 10], Vector4(4, 4, 4, 4), Color("1e130d")))
	theme.set_stylebox("fill", "ProgressBar", box("bar_fill_hp.png", [10, 6, 10, 6], Vector4.ZERO, Color("4cb874")))
	for pair in [["FoeBar", "bar_fill_foe.png", Color("d9485c")], ["XpBar", "bar_fill_xp.png", Color("8a6ad8")], ["ManaBar", "bar_fill_mana.png", Color("5c9be6")]]:
		theme.set_type_variation(pair[0], "ProgressBar")
		theme.set_stylebox("fill", pair[0], box(pair[1], [10, 6, 10, 6], Vector4.ZERO, pair[2]))
	theme.set_font_size("font_size", "ProgressBar", 1)
	theme.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
	return theme

static func _button(type: String, skin: String, col: Color) -> void:
	if type != "Button":
		theme.set_type_variation(type, "Button")
	var content := Vector4(28, 14, 28, 16)
	var fb: Color = {"wood": Color("6b4426"), "gold": Color("d9a63e"), "red": Color("a8312c"), "blue": Color("35618f")}[skin]
	theme.set_stylebox("normal", type, box("btn_%s_normal.png" % skin, [26, 22, 26, 26], content, fb))
	theme.set_stylebox("hover", type, box("btn_%s_hover.png" % skin, [26, 22, 26, 26], content, fb.lightened(0.12)))
	theme.set_stylebox("pressed", type, box("btn_%s_pressed.png" % skin, [26, 22, 26, 26], Vector4(content.x, content.y + 3, content.z, content.w - 3), fb.darkened(0.15)))
	theme.set_stylebox("disabled", type, box("btn_%s_disabled.png" % skin, [26, 22, 26, 26], content, Color("4a3d33")))
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	theme.set_font("font", type, f_title)
	theme.set_font_size("font_size", type, 19)
	theme.set_color("font_color", type, col)
	theme.set_color("font_hover_color", type, col)
	theme.set_color("font_pressed_color", type, col)
	theme.set_color("font_focus_color", type, col)
	theme.set_color("font_disabled_color", type, Color(col.r, col.g, col.b, 0.45))
	theme.set_constant("outline_size", type, 0 if skin == "gold" else 5)
	theme.set_color("font_outline_color", type, Color(0.1, 0.05, 0.02, 0.7))
