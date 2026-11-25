extends SceneTree
## Двухпроцессные сетевые тесты: запускает два headless-процесса Godot с tests/net_probe.gd.
##   godot --headless --path godot --script res://tests/test_net_online.gd [-- online notfound lan2p]
## online   — хост создаёт комнату в облачном PeerJS, клиент входит по коду, RPC ping/pong по WebRTC.
## notfound — вход в несуществующую комнату должен закончиться «Комната … не найдена».
## lan2p    — ENet по 127.0.0.1 между двумя процессами + ping/pong.
## Нужен интернет (для online/notfound). Код выхода 0 — все выбранные сценарии прошли.

var scenarios: Array = []
var results := {}
var tmp_dir := ""


func _initialize() -> void:
	scenarios = Array(OS.get_cmdline_user_args())
	if scenarios.is_empty():
		scenarios = ["online", "notfound", "lan2p"]
	tmp_dir = OS.get_user_data_dir().path_join("net_test")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	_run.call_deferred()


func _spawn(role_args: Array, out_name: String, timeout: int) -> Dictionary:
	var out := tmp_dir.path_join(out_name)
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/net_probe.gd", "--"]
	args.append_array(role_args)
	args.append_array(["--out", out, "--timeout", str(timeout)])
	var pid := OS.create_process(OS.get_executable_path(), args)
	return {"pid": pid, "out": out}


func _lines(p: Dictionary) -> PackedStringArray:
	if not FileAccess.file_exists(p.out):
		return []
	return FileAccess.get_file_as_string(p.out).strip_edges().split("\n", false)


func _find(p: Dictionary, prefix: String) -> String:
	for l in _lines(p):
		if l.begins_with(prefix):
			return l
	return ""


func _wait(cond: Callable, sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
		OS.delay_msec(50)
	return false


func _exit_code(p: Dictionary) -> int:
	if OS.is_process_running(p.pid):
		return -999
	return OS.get_process_exit_code(p.pid)


func _done(p: Dictionary) -> bool:
	return not OS.is_process_running(p.pid)


func _kill(p: Dictionary) -> void:
	if OS.is_process_running(p.pid):
		OS.kill(p.pid)


func _run() -> void:
	for s in scenarios:
		print("=== ", s, " ===")
		var t0 := Time.get_ticks_msec()
		var ok: bool = await call("_sc_" + s)
		results[s] = ok
		print("=== %s: %s (%.1f с) ===" % [s, "OK" if ok else "FAIL", (Time.get_ticks_msec() - t0) / 1000.0])
	var all_ok := true
	for s in results:
		all_ok = all_ok and results[s]
	print("RESULT ", "PASS" if all_ok else "FAIL", " ", results)
	quit(0 if all_ok else 1)


func _sc_online() -> bool:
	var host := _spawn(["host"], "host.txt", 90)
	var got_room := await _wait(func(): return _find(host, "ROOM ") != "" or _done(host), 25)
	var room := _find(host, "ROOM ")
	if not got_room or room == "":
		print("  хост не создал комнату: ", _lines(host))
		_kill(host)
		return false
	var code := room.split(" ")[1]
	print("  комната ", code)
	var cli := _spawn(["join", code], "client.txt", 60)
	await _wait(func(): return _done(cli), 65)
	await _wait(func(): return _done(host), 8)
	print("  host:   ", " | ".join(_lines(host)))
	print("  client: ", " | ".join(_lines(cli)))
	var ok := _exit_code(cli) == 0 and _find(cli, "PONG") != "" and _find(host, "PING") != ""
	_kill(host)
	_kill(cli)
	return ok


func _sc_notfound() -> bool:
	# Код из допустимых символов, которого почти наверняка нет.
	var code: String = load("res://scripts/net/net.gd").make_code()
	var cli := _spawn(["join", code], "nf.txt", 60)
	await _wait(func(): return _done(cli), 65)
	print("  client: ", " | ".join(_lines(cli)))
	var f := _find(cli, "FAILED")
	_kill(cli)
	return f.contains("не найдена")


func _sc_lan2p() -> bool:
	var port := 18777 + randi() % 1000
	var host := _spawn(["lan-host", "--port", str(port)], "lanhost.txt", 40)
	if not await _wait(func(): return _find(host, "READY") != "" or _done(host), 15):
		_kill(host)
		return false
	var cli := _spawn(["lan-join", "127.0.0.1", "--port", str(port)], "lanclient.txt", 30)
	await _wait(func(): return _done(cli), 35)
	await _wait(func(): return _done(host), 8)
	print("  host:   ", " | ".join(_lines(host)))
	print("  client: ", " | ".join(_lines(cli)))
	var ok := _exit_code(cli) == 0 and _find(cli, "PONG") != ""
	_kill(host)
	_kill(cli)
	return ok
