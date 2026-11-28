extends SceneTree
## Открывает меню «По локальной сети», ждёт найденную игру и жмёт «Войти» настоящим кликом мыши.
var game
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()
func _btns(n: Node, out: Array) -> Array:
	if n is Button and n.is_visible_in_tree(): out.append(n)
	for c in n.get_children(): _btns(c, out)
	return out
func _click(b: Button) -> void:
	var p: Vector2 = b.get_global_rect().get_center()
	var vp := b.get_viewport()
	var tr: Transform2D = vp.get_final_transform() if vp.has_method("get_final_transform") else Transform2D()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed
		e.position = tr * p; e.global_position = e.position
		root.push_input(e)
		await process_frame
func _run() -> void:
	for i in 30: await process_frame
	game = current_scene
	print("scene: ", game.name)
	game._on_act("net", "lan")
	for i in 40:
		await create_timer(0.25).timeout
	var list := _btns(root, []).filter(func(b): return b.text.begins_with("Войти"))
	print("buttons: ", list.map(func(b): return [b.text, b.disabled, b.get_global_rect()]))
	var target = list.filter(func(b): return b.text.begins_with("Войти:"))
	if target.is_empty(): print("NO GAME BUTTON"); quit(); return
	var hit = root.gui_find_control(target[0].get_global_rect().get_center()) if root.has_method("gui_find_control") else null
	print("control under button center: ", hit, " ", hit.get_path() if hit else "")
	await _click(target[0])
	for i in 8: await create_timer(0.25).timeout
	var Net = root.get_node("Net")
	print("after click: Net.mode=", Net.mode, " phase=", Net._phase, " view=", game.net_game.view if game.net_game else null)
	quit()
