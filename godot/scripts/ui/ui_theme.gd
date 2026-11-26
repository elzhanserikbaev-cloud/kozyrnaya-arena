class_name UiTheme
extends RefCounted
## Тема интерфейса из запечённых ассетов (assets/ui + ui_manifest.json).
## Варианты кнопок: theme_type_variation = "GoldButton" | "RedButton" | "BlueButton" | "WoodButton" (по умолчанию).
## Панели: "Panel" (дерево + пергамент), "DarkPanel" (тёмное дерево), "Chip", "Tooltip".

const UI := "res://assets/ui/"
const INK := Color("3a2614")          # текст на пергаменте (карты)
const CREAM := Color("fbf0d8")
const TEXT := Color("eef1f5")         # основной текст интерфейса
const GOLD := Color("f0b94a")
const MUTED := Color("9aa6b5")

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

static func flat(bg: Color, radius := 14, border := Color(1, 1, 1, 0.08), bw := 1, pad := Vector4(16, 12, 16, 12), shadow := 10) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = bg
	f.set_corner_radius_all(radius)
	f.border_color = border
	f.set_border_width_all(bw)
	f.content_margin_left = pad.x; f.content_margin_top = pad.y
	f.content_margin_right = pad.z; f.content_margin_bottom = pad.w
	if shadow > 0:
		f.shadow_color = Color(0, 0, 0, 0.35); f.shadow_size = shadow; f.shadow_offset = Vector2(0, 4)
	f.anti_aliasing = true
	return f

## Современная плоская тема: тёмные полупрозрачные панели, скругления, крупный Rubik, без свечения.
static func build() -> Theme:
	if theme:
		return theme
	f_title = CardFaces.f_title
	f_body = CardFaces.f_body
	f_bold = CardFaces.f_bold
	f_medium = CardFaces._font("res://assets/fonts/Rubik-Medium.ttf", false)
	if f_medium is FontVariation:
		(f_medium as FontVariation).variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	theme = Theme.new()
	theme.default_font = f_body
	theme.default_font_size = 17
	# Label
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))
	for v in ["TitleLabel", "HeaderLabel"]:
		theme.set_type_variation(v, "Label")
		theme.set_font("font", v, f_bold)
		theme.set_color("font_color", v, Color.WHITE)
	theme.set_font_size("font_size", "TitleLabel", 28)
	theme.set_font_size("font_size", "HeaderLabel", 12)
	theme.set_color("font_color", "HeaderLabel", MUTED)
	theme.set_type_variation("InkLabel", "Label")
	theme.set_color("font_color", "InkLabel", TEXT)
	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", MUTED)
	theme.set_font_size("font_size", "MutedLabel", 15)
	# Кнопки — каменные, как рамки карт и борт арены
	_stone_button("Button", "slate", TEXT)
	_stone_button("WoodButton", "slate", TEXT)
	_stone_button("GoldButton", "gold", Color("2a1804"))
	_stone_button("RedButton", "red", Color.WHITE)
	_stone_button("BlueButton", "blue", Color.WHITE)
	theme.set_font_size("font_size", "GoldButton", 20)
	# Прозрачные кнопки для верхней панели
	_stone_button("GhostButton", "slate", TEXT)
	theme.set_font_size("font_size", "GhostButton", 15)
	# Разделитель
	theme.set_stylebox("separator", "HSeparator", flat(Color(1, 1, 1, 0.08), 0, Color(0, 0, 0, 0), 0, Vector4.ZERO, 0))
	theme.set_constant("separation", "HSeparator", 14)
	# Панели
	theme.set_stylebox("panel", "PanelContainer", tex_box("panel_slate.png", [26, 26, 26, 26], Vector4(18, 16, 18, 16)))
	theme.set_type_variation("ParchmentPanel", "PanelContainer")
	theme.set_stylebox("panel", "ParchmentPanel", tex_box("panel_slate.png", [26, 26, 26, 26], Vector4(34, 30, 34, 30)))
	theme.set_type_variation("ChipPanel", "PanelContainer")
	theme.set_stylebox("panel", "ChipPanel", tex_box("chip_slate.png", [14, 14, 14, 14], Vector4(10, 5, 10, 5)))
	theme.set_type_variation("TooltipPanel", "PanelContainer")
	theme.set_stylebox("panel", "TooltipPanel", tex_box("panel_slate.png", [26, 26, 26, 26], Vector4(18, 10, 18, 10)))
	theme.set_type_variation("BarPanel", "PanelContainer")
	var bar := tex_box("bar_slate.png", [0, 2, 0, 4], Vector4(18, 6, 18, 9))
	bar.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	theme.set_stylebox("panel", "BarPanel", bar)
	# Поля ввода
	var le := flat(Color(1, 1, 1, 0.08), 12, Color(1, 1, 1, 0.14), 1, Vector4(14, 10, 14, 10), 0)
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_stylebox("focus", "LineEdit", flat(Color(1, 1, 1, 0.1), 12, GOLD, 2, Vector4(14, 10, 14, 10), 0))
	theme.set_color("font_color", "LineEdit", Color.WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.4))
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_font("font", "LineEdit", f_medium)
	theme.set_font_size("font_size", "LineEdit", 17)
	# Прокрутка
	var sg := flat(Color(1, 1, 1, 0.25), 4, Color(0, 0, 0, 0), 0, Vector4.ZERO, 0)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(st, "VScrollBar", sg)
	theme.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0.15), 4, Color(0, 0, 0, 0), 0, Vector4(4, 0, 4, 0), 0))
	# Полоски
	theme.set_stylebox("background", "ProgressBar", flat(Color(0, 0, 0, 0.45), 8, Color(1, 1, 1, 0.08), 1, Vector4.ZERO, 0))
	theme.set_stylebox("fill", "ProgressBar", flat(Color("49c27a"), 8, Color(0, 0, 0, 0), 0, Vector4.ZERO, 0))
	for pair in [["FoeBar", Color("e0565f")], ["XpBar", Color("9b7be0")], ["ManaBar", Color("4f9be8")]]:
		theme.set_type_variation(pair[0], "ProgressBar")
		theme.set_stylebox("fill", pair[0], flat(pair[1], 8, Color(0, 0, 0, 0), 0, Vector4.ZERO, 0))
	theme.set_font_size("font_size", "ProgressBar", 1)
	theme.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
	var track := flat(Color(0, 0, 0, 0.45), 6, Color(1, 1, 1, 0.12), 1, Vector4(0, 5, 0, 5), 0)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", flat(GOLD.darkened(0.15), 6, Color(0, 0, 0, 0), 0, Vector4(0, 5, 0, 5), 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", flat(GOLD, 6, Color(0, 0, 0, 0), 0, Vector4(0, 5, 0, 5), 0))
	theme.set_stylebox("separator", "VSeparator", flat(Color(1, 1, 1, 0.1), 0, Color(0, 0, 0, 0), 0, Vector4.ZERO, 0))
	theme.set_constant("separation", "VSeparator", 18)
	return theme

static func tex_box(file: String, m: Array, pad: Vector4) -> StyleBox:
	var p := UI + file
	if not ResourceLoader.exists(p):
		return flat(Color(0.075, 0.09, 0.12, 0.92), 16, Color(1, 1, 1, 0.07), 1, pad)
	var sb := StyleBoxTexture.new()
	sb.texture = load(p)
	sb.texture_margin_left = m[0]; sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]; sb.texture_margin_bottom = m[3]
	sb.content_margin_left = pad.x; sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z; sb.content_margin_bottom = pad.w
	return sb

static func _stone_button(type: String, skin: String, col: Color) -> void:
	if type != "Button":
		theme.set_type_variation(type, "Button")
	var pad := Vector4(18, 8, 18, 9)
	var m := [18, 17, 18, 17]
	theme.set_stylebox("normal", type, tex_box("sbtn_%s_normal.png" % skin, m, pad))
	theme.set_stylebox("hover", type, tex_box("sbtn_%s_hover.png" % skin, m, pad))
	theme.set_stylebox("pressed", type, tex_box("sbtn_%s_pressed.png" % skin, m, Vector4(pad.x, pad.y + 2, pad.z, pad.w - 2)))
	theme.set_stylebox("disabled", type, tex_box("sbtn_%s_disabled.png" % skin, m, pad))
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	theme.set_font("font", type, f_bold)
	theme.set_font_size("font_size", type, 16)
	theme.set_constant("outline_size", type, 0 if skin == "gold" else 4)
	theme.set_color("font_outline_color", type, Color(0.03, 0.04, 0.06, 0.8))
	theme.set_color("font_color", type, col)
	theme.set_color("font_hover_color", type, col)
	theme.set_color("font_pressed_color", type, col)
	theme.set_color("font_focus_color", type, col)
	theme.set_color("font_disabled_color", type, Color(1, 1, 1, 0.38))

static func _button(type: String, bg: Color, col: Color) -> void:
	if type != "Button":
		theme.set_type_variation(type, "Button")
	var pad := Vector4(16, 9, 16, 9)
	theme.set_stylebox("normal", type, flat(bg, 12, bg.lightened(0.12), 1, pad, 6))
	theme.set_stylebox("hover", type, flat(bg.lightened(0.1), 12, bg.lightened(0.25), 1, pad, 8))
	theme.set_stylebox("pressed", type, flat(bg.darkened(0.15), 12, bg.darkened(0.1), 1, Vector4(pad.x, pad.y + 2, pad.z, pad.w - 2), 2))
	theme.set_stylebox("disabled", type, flat(Color(0.2, 0.22, 0.26, 0.6), 12, Color(1, 1, 1, 0.04), 1, pad, 0))
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	theme.set_font("font", type, f_bold)
	theme.set_font_size("font_size", type, 16)
	theme.set_color("font_color", type, col)
	theme.set_color("font_hover_color", type, col)
	theme.set_color("font_pressed_color", type, col)
	theme.set_color("font_focus_color", type, col)
	theme.set_color("font_disabled_color", type, Color(1, 1, 1, 0.35))
