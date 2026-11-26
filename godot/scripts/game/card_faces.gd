extends Node
## Запекает лица карт (рамка + портрет + надписи) в текстуры через SubViewport.
## Одна и та же текстура идёт и на 3D-карту, и в интерфейс (магазин, рука, подсказки).
## face()/magic_face() сразу возвращают текстуру-заглушку нужного размера, а затем подменяют
## её содержимое, когда запекание готово (ImageTexture.update), так что ссылки остаются верными.

const TW := 512
const TH := 716
# Области на рамке (см. отчёт ассетов / DESIGN.md)
# Раскладка каменной рамки (assets/cards/card_layout.json)
const PORTRAIT := Rect2(50, 58, 412, 298)
const CORNER_C := Vector2(66, 74)          # медальон в углу: ранг+стихия (герой) / цена (магия)
const GEM_C := Vector2(256, 350)           # октагон на ленте: цена героя
const NAME_RECT := Rect2(72, 362, 368, 46)
const TEXT_RECT := Rect2(80, 436, 352, 172)
const ATK_C := Vector2(112, 662)
const MANA_C := Vector2(256, 668)
const HP_C := Vector2(400, 662)
const MAGIC_ICON_C := Vector2(256, 207)

const ELEM := {"S": "ice", "H": "fire", "D": "light", "C": "nature"}

var _cache := {}          # ключ → ImageTexture
var _queue: Array = []    # [{key, build:Callable}]
var _busy := false
var _vp: SubViewport
var f_title: Font
var f_body: Font
var f_bold: Font

func _ready() -> void:
	f_title = _font("res://assets/fonts/Philosopher-Bold.ttf", true)
	f_body = _font("res://assets/fonts/Rubik-Regular.ttf", false)
	f_bold = _font("res://assets/fonts/Rubik-Bold.ttf", true)
	_vp = SubViewport.new()
	_vp.size = Vector2i(TW, TH)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.disable_3d = true
	add_child(_vp)

func _font(path: String, bold: bool) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	# запасной вариант: Rubik может лежать как вариативный шрифт
	for alt in ["res://assets/fonts/Rubik[wght].ttf", "res://assets/fonts/Rubik-VariableFont_wght.ttf"]:
		if ResourceLoader.exists(alt):
			var fv := FontVariation.new()
			fv.base_font = load(alt)
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700 if bold else 400}
			return fv
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Georgia" if bold else "Segoe UI", "DejaVu Sans"])
	return sf

static func tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

func fed_key(fed) -> String:
	return "" if fed == null or int(fed.get("n", 0)) == 0 else "f%d_%d_%d" % [fed.n, fed.atk, fed.hp]

## Лицо героя. items — ключи магии, fed — {atk,hp,n} или null.
func face(id: String, star: int, items: Array = [], fed = null) -> Texture2D:
	var key := "h|%s|%d|%s|%s" % [id, star, ",".join(items), fed_key(fed)]
	return _job(key, func(root: Control): _build_hero(root, id, star, items, fed))

func magic_face(k: String, power_round: int = 1) -> Texture2D:
	var key := "m|%s|%d" % [k, power_round if Data.MAGIC[k].k == "spell" else 0]
	return _job(key, func(root: Control): _build_magic(root, k, power_round))

func back() -> Texture2D:
	var t := tex("res://assets/cards/back.png")
	if t: return t
	return _job("back", func(root: Control):
		var r := ColorRect.new(); r.color = Color("3b2a1a"); r.size = Vector2(TW, TH); root.add_child(r))

func _job(key: String, build: Callable) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(TW, TH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.18, 0.12, 0.09, 1))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	_queue.append({"tex": t, "build": build})
	if not _busy:
		_pump()
	return t

func _pump() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		for c in _vp.get_children():
			c.free()
		var root := Control.new()
		root.size = Vector2(TW, TH)
		_vp.add_child(root)
		job.build.call(root)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		if img:
			img.generate_mipmaps()
			(job.tex as ImageTexture).set_image(img)
	_busy = false

# ---------- сборка ----------
func _rect_tex(root: Control, t: Texture2D, r: Rect2, fallback: Color = Color(0, 0, 0, 0)) -> void:
	if t:
		var tr := TextureRect.new()
		tr.texture = t
		tr.position = r.position
		tr.size = r.size
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		root.add_child(tr)
	elif fallback.a > 0:
		var cr := ColorRect.new()
		cr.color = fallback
		cr.position = r.position
		cr.size = r.size
		root.add_child(cr)

func _label(root: Control, text: String, r: Rect2, font: Font, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_CENTER, outline := 0, ocol := Color(0, 0, 0, 0.85), shrink := true, lines := 1) -> Label:
	var l := Label.new()
	l.text = text
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", ocol)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 2)
	if lines > 1:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.max_lines_visible = lines
	if shrink and lines == 1:
		# ужимаем шрифт, пока текст не влезет
		var fs := size
		while fs > 14 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x:
			fs -= 2
		l.add_theme_font_size_override("font_size", fs)
	root.add_child(l)
	# после добавления Label может растянуться под текст — возвращаем ширину, чтобы перенос строк работал
	l.custom_minimum_size = Vector2(r.size.x, 0)
	l.size = r.size
	l.clip_text = lines > 1
	return l

func _centered(root: Control, text: String, c: Vector2, font: Font, size: int, col: Color, outline := 8) -> void:
	_label(root, text, Rect2(c - Vector2(70, 40), Vector2(140, 80)), font, size, col, HORIZONTAL_ALIGNMENT_CENTER, outline)

func _build_hero(root: Control, id: String, star: int, items: Array, fed) -> void:
	var d: Dictionary = Data.HEROES[id]
	var el: String = ELEM[d.s]
	var su: Dictionary = Data.SUITS[d.s]
	_rect_tex(root, tex("res://assets/portraits/hero_%s.png" % id), PORTRAIT, su.color.darkened(0.4))
	var frame_path := "res://assets/cards/frame_legend.png" if Data.is_legend(id) else "res://assets/cards/frame_%s_%d.png" % [el, star]
	_rect_tex(root, tex(frame_path), Rect2(0, 0, TW, TH), Color(0, 0, 0, 0))
	# угловой медальон: ранг и стихия
	# ранг, АТК и ОЗ рисуются чёткими подписями поверх карты (3D: Label3D, интерфейс: Label)
	# цена в октагоне
	_centered(root, str(d.c), GEM_C, f_bold, 40, Color("fff6dc"), 10)
	# усиления — значки справа на портрете
	for i in items.size():
		var c := Vector2(PORTRAIT.end.x - 42, PORTRAIT.position.y + 44 + i * 80)
		var disc := TextureRect.new()
		disc.texture = tex("res://assets/portraits/magic_%s.png" % items[i])
		disc.position = c - Vector2(36, 36)
		disc.size = Vector2(72, 72)
		disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		root.add_child(disc)
	# съеденные карты — красные метки
	if fed != null and int(fed.get("n", 0)) > 0:
		for i in Data.FEED_MAX:
			var pip := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("c8303f") if i < int(fed.n) else Color(0.95, 0.9, 0.78, 0.35)
			sb.set_corner_radius_all(13)
			sb.border_color = Color("2a160c"); sb.set_border_width_all(3)
			pip.add_theme_stylebox_override("panel", sb)
			pip.position = Vector2(PORTRAIT.position.x + 98 + i * 34, PORTRAIT.position.y + 8)
			pip.size = Vector2(26, 26)
			root.add_child(pip)
	_label(root, String(d.n).to_upper(), NAME_RECT, f_bold, 36, Color("fff1c4"), HORIZONTAL_ALIGNMENT_CENTER, 10, Color(0.14, 0.07, 0.03, 0.95))
	# пергамент: название способности и её действие
	var t := TEXT_RECT
	_label(root, d.ab.n, Rect2(t.position, Vector2(t.size.x, 40)), f_title, 30, Color("5a1f12"), HORIZONTAL_ALIGNMENT_CENTER, 0)
	var desc := _label(root, Data.ab_desc(id, star, fed), Rect2(t.position + Vector2(6, 42), t.size - Vector2(12, 46)), f_body, 26,
		Color("3a2614"), HORIZONTAL_ALIGNMENT_CENTER, 0, Color(0, 0, 0, 0), false, 4)
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.remove_theme_color_override("font_shadow_color")
	_centered(root, str(d.mm), MANA_C, f_bold, 36, Color("eef4ff"), 12)

func _build_magic(root: Control, k: String, power_round: int) -> void:
	var m: Dictionary = Data.MAGIC[k]
	var item: bool = m.k == "item"
	_rect_tex(root, tex("res://assets/portraits/magic_%s.png" % k), Rect2(MAGIC_ICON_C - Vector2(150, 150), Vector2(300, 300)), Color("3a2a4a"))
	_rect_tex(root, tex("res://assets/cards/frame_%s.png" % ("item" if item else "spell")), Rect2(0, 0, TW, TH))
	_label(root, str(m.c), Rect2(CORNER_C - Vector2(40, 30), Vector2(80, 60)), f_title, 40, Color("fff1c9"), HORIZONTAL_ALIGNMENT_CENTER, 8, Color(0.06, 0.04, 0.03, 0.95))
	_label(root, String(m.n).to_upper(), NAME_RECT, f_title, 34, Color("fff1c4"), HORIZONTAL_ALIGNMENT_CENTER, 9, Color(0.14, 0.07, 0.03, 0.95))
	var t := TEXT_RECT
	_label(root, "Усиление" if item else "Заклинание", Rect2(t.position, Vector2(t.size.x, 38)), f_title, 28, Color("2f5a66") if item else Color("5a2a72"), HORIZONTAL_ALIGNMENT_CENTER, 0)
	var desc := _label(root, Data.magic_desc(k, power_round), Rect2(t.position + Vector2(0, 42), t.size - Vector2(0, 46)), f_body, 27,
		Color("3a2614"), HORIZONTAL_ALIGNMENT_CENTER, 0, Color(0, 0, 0, 0), false, 4)
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.remove_theme_color_override("font_shadow_color")
