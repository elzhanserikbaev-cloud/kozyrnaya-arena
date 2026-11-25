extends SceneTree
## Сетевые тесты в одном процессе (без интернета):
##   godot --headless --path godot --script res://tests/test_net_lan.gd
## 1) коды комнат; 2) LAN-обнаружение (наше же объявление видно поиску); 3) ENet-петля 127.0.0.1:
##    Net — хост на основном multiplayer, клиент — отдельный SceneMultiplayer на поддереве /root/Client,
##    RPC ping/pong; 4) leave() и повторный host; 5) join_lan на закрытый порт -> connection_failed.

const ProbeNode := preload("res://tests/net_probe_node.gd")

var net: Node
var fails := 0
var events: Array = []


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	net = root.get_node_or_null("Net")
	if net == null:
		net = load("res://scripts/net/net.gd").new()
		net.name = "Net"
		root.add_child(net)
	_run.call_deferred()


func wait_until(cond: Callable, sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
		OS.delay_msec(10)
	return cond.call()


func _run() -> void:
	var NetScript = net.get_script()
	print("[коды комнат]")
	var seen := {}
	for i in 200:
		var c: String = NetScript.make_code()
		if i < 3: check(NetScript.is_valid_code(c), "код %s допустим" % c)
		if not NetScript.is_valid_code(c):
			fails += 1
		seen[c] = true
	check(seen.size() > 195, "коды случайны (%d уникальных из 200)" % seen.size())
	check(NetScript.normalize_code(" ab-c2 34 ") == "ABC234", "normalize_code")
	check(not NetScript.is_valid_code("ABC0O1"), "0/O/1 отвергаются")
	check(net.lan_supported(), "lan_supported() на ПК")
	print("  online_supported() = ", net.online_supported())

	net.connected.connect(func(): events.append("connected"))
	net.connection_failed.connect(func(r): events.append("failed:" + r))
	net.peer_joined.connect(func(id): events.append("joined:%d" % id))
	net.peer_left.connect(func(id): events.append("left:%d" % id))

	print("[LAN-хост + обнаружение]")
	var port := 19777 + randi() % 500
	net.player_name = "Тест-хост"
	var lists: Array = []
	net.lan_games_changed.connect(func(l): lists.append(l))
	check(net.start_lan_browse(), "start_lan_browse()")
	net.host_lan(port)
	check(net.is_host and net.mode == "lan" and events.has("connected"), "host_lan: is_host, mode=lan, connected")
	var found := await wait_until(func():
		for g in net.get_lan_games():
			if g.port == port:
				return true
		return false, 4.0)
	check(found, "своя игра найдена через UDP 8778")
	var g0 := {}
	for g in net.get_lan_games():
		if g.port == port:
			g0 = g
	check(g0.get("name") == "Тест-хост" and g0.get("compatible") == true and g0.get("own") == true, "поля объявления: %s" % str(g0))

	print("[ENet-петля + RPC]")
	var host_probe := ProbeNode.new()
	host_probe.name = "Probe"
	root.add_child(host_probe)
	var client_root := Node.new()
	client_root.name = "Client"
	root.add_child(client_root)
	var cmp := SceneMultiplayer.new()
	set_multiplayer(cmp, ^"/root/Client")
	var cli_probe := ProbeNode.new()
	cli_probe.name = "Probe"
	client_root.add_child(cli_probe)
	var cpeer := ENetMultiplayerPeer.new()
	check(cpeer.create_client("127.0.0.1", port) == OK, "клиент ENet создан")
	cmp.multiplayer_peer = cpeer
	var cli_connected := [false]  # лямбды захватывают по значению — нужен контейнер
	cmp.connected_to_server.connect(func(): cli_connected[0] = true)
	check(await wait_until(func(): return cli_connected[0], 5.0), "клиент подключился")
	check(await wait_until(func(): return events.any(func(e): return str(e).begins_with("joined:")), 3.0), "peer_joined у хоста")
	var rtt := [-1]
	cli_probe.got_pong.connect(func(r, _h): rtt[0] = r)
	cli_probe.ping.rpc_id(1, Time.get_ticks_msec())
	check(await wait_until(func(): return rtt[0] >= 0, 3.0), "ping/pong (rtt %d мс)" % rtt[0])
	check(await wait_until(func():
		for g in net.get_lan_games():
			if g.port == port and g.players == 2:
				return true
		return false, 3.0), "объявление: players=2")
	net.accepting_players = false
	check(await wait_until(func():
		for g in net.get_lan_games():
			if g.port == port and g.open == false:
				return true
		return false, 3.0), "accepting_players=false -> open=false")
	cpeer.close()
	check(await wait_until(func(): return events.any(func(e): return str(e).begins_with("left:")), 5.0), "peer_left у хоста")
	cmp.multiplayer_peer = null

	print("[leave и повторный хост]")
	net.leave()
	check(net.mode == "" and not net.is_host and not get_multiplayer().has_multiplayer_peer(), "leave() сбросил состояние")
	check(await wait_until(func(): return net.get_lan_games().all(func(g): return g.port != port), 5.0), "объявление пропало из списка")
	events.clear()
	net.host_lan(port)
	check(events.has("connected"), "повторный host_lan на том же порту")
	net.leave()
	net.stop_lan_browse()

	print("[join_lan на закрытый порт]")
	events.clear()
	net.join_lan("127.0.0.1", port + 1)
	check(await wait_until(func(): return events.any(func(e): return str(e).begins_with("failed:")), 20.0), "connection_failed: %s" % str(events))
	check(net.mode == "", "состояние сброшено после ошибки")

	print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
