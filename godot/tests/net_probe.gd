extends SceneTree
## Сетевой зонд: один участник теста в отдельном процессе Godot.
##   godot --headless --path godot --script res://tests/net_probe.gd -- host [--out FILE] [--timeout SEC]
##   godot --headless --path godot --script res://tests/net_probe.gd -- join CODE [--out FILE]
##   ... -- lan-host [--port 8777]          ... -- lan-join IP [--port 8777]
## Хост ждёт ping от клиента, отвечает pong и выходит после ухода клиента.
## Клиент подключается, шлёт ping хосту (id 1), ждёт pong и выходит с кодом 0.
## Строки статуса печатаются в stdout и (если задан --out) дописываются в файл:
##   ROOM <code> | READY | CONNECTED <my_id> | PEER_JOINED <id> | PING <from> | PONG <rtt_ms> <host_id> | PEER_LEFT <id> | FAILED <reason> | TIMEOUT | DONE

const ProbeNode := preload("res://tests/net_probe_node.gd")

var net: Node
var probe: Node
var role := ""
var arg := ""
var out_path := ""
var port := 8777
var deadline := 0
var quit_at := 0
var exit_code := 1
var pinged := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	var timeout := 60
	while i < a.size():
		match a[i]:
			"--out":
				i += 1; out_path = a[i]
			"--timeout":
				i += 1; timeout = int(a[i])
			"--port":
				i += 1; port = int(a[i])
			_:
				if role == "":
					role = a[i]
				elif arg == "":
					arg = a[i]
		i += 1
	deadline = Time.get_ticks_msec() + timeout * 1000
	probe = ProbeNode.new()
	probe.name = "NetProbe"
	root.add_child(probe)
	probe.got_ping.connect(func(f): emit_line("PING %d" % f))
	probe.got_pong.connect(func(rtt, hid):
		emit_line("PONG %d %d" % [rtt, hid])
		finish(0))
	net = root.get_node_or_null("Net")
	if net == null:
		net = load("res://scripts/net/net.gd").new()
		net.name = "Net"
		root.add_child(net)
	net.connection_failed.connect(func(r): emit_line("FAILED " + r); finish(2))
	net.room_ready.connect(func(c): emit_line("ROOM " + c))
	net.connected.connect(_on_connected)
	net.peer_joined.connect(func(id): emit_line("PEER_JOINED %d" % id))
	net.peer_left.connect(func(id):
		emit_line("PEER_LEFT %d" % id)
		if net.is_host and pinged:
			finish(0))
	net.disconnected.connect(func(): emit_line("DISCONNECTED"); finish(3 if not pinged else 0))
	probe.got_ping.connect(func(_f): pinged = true)
	emit_line("START %s %s lan=%s online=%s" % [role, arg, net.lan_supported(), net.online_supported()])
	# Net._ready ещё не вызван до первого кадра — стартуем отложенно
	_start.call_deferred()


func _start() -> void:
	match role:
		"host":
			net.host_online()
		"join":
			net.join_online(arg)
		"lan-host":
			net.host_lan(port)
		"lan-join":
			net.join_lan(arg if arg != "" else "127.0.0.1", port)
		_:
			emit_line("FAILED неизвестная роль '%s'" % role)
			finish(4)


func _on_connected() -> void:
	if net.is_host:
		emit_line("READY")
		return
	emit_line("CONNECTED %d" % probe.multiplayer.get_unique_id())
	probe.ping.rpc_id(1, Time.get_ticks_msec())


func emit_line(s: String) -> void:
	var line := "[%s %.1fs] %s" % [role, Time.get_ticks_msec() / 1000.0, s]
	print(line)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		if f:
			f.seek_end()
			f.store_line(s)
			f.close()


func finish(code: int) -> void:
	if quit_at > 0:
		return
	exit_code = code
	# у клиента — даём хосту увидеть уход; у хоста — сразу
	quit_at = Time.get_ticks_msec() + (300 if role.ends_with("join") else 100)


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if quit_at > 0 and now >= quit_at:
		if exit_code == 0:
			emit_line("DONE")
		net.leave()
		quit(exit_code)
		return true
	if quit_at == 0 and now > deadline:
		emit_line("TIMEOUT")
		finish(5)
	return false
