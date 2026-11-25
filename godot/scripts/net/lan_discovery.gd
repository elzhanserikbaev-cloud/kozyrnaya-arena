extends Node
## Поиск игр в локальной сети: хост раз в секунду рассылает UDP-объявление на порт 8778,
## клиенты слушают этот порт и собирают список.
## Объявление (JSON): {g:"kozyrnaya-arena", proto, hid, name, players, max, port, version, open}

signal games_changed(list: Array)

const MAGIC := "kozyrnaya-arena"
const ADVERT_INTERVAL := 1.0
const GAME_TTL_MSEC := 3500

var discovery_port := 8778

var _adv_udp: PacketPeerUDP
var _adv_info := {}
var _adv_timer := 0.0
var _adv_targets: PackedStringArray = []
var _hid := ""

var _listen: PacketPeerUDP
var _games := {}  # hid -> entry
var _proto := 1


func _ready() -> void:
	_hid = "%08x%08x" % [randi(), randi()]
	set_process(false)


static func supported() -> bool:
	return not OS.has_feature("web")


# ---------------- объявление (хост) ----------------

func start_advertising(info: Dictionary, proto: int) -> Error:
	if not supported():
		return ERR_UNAVAILABLE
	_proto = proto
	_adv_info = info.duplicate()
	if _adv_udp == null:
		_adv_udp = PacketPeerUDP.new()
		_adv_udp.set_broadcast_enabled(true)
	_adv_targets = _broadcast_targets()
	_adv_timer = ADVERT_INTERVAL  # отправить сразу
	set_process(true)
	return OK


func update_advert(info: Dictionary) -> void:
	_adv_info.merge(info, true)


func stop_advertising() -> void:
	if _adv_udp:
		_adv_udp.close()
		_adv_udp = null
	_adv_info = {}
	_update_process()


func is_advertising() -> bool:
	return _adv_udp != null


func _broadcast_targets() -> PackedStringArray:
	var t: PackedStringArray = ["255.255.255.255", "127.0.0.1"]
	for a in IP.get_local_addresses():
		var parts := String(a).split(".")
		if parts.size() != 4 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]  # предполагаем /24 (домашние сети)
		if not t.has(b):
			t.append(b)
	return t


func _send_advert() -> void:
	var msg := _adv_info.duplicate()
	msg["g"] = MAGIC
	msg["proto"] = _proto
	msg["hid"] = _hid
	var data := JSON.stringify(msg).to_utf8_buffer()
	for addr in _adv_targets:
		_adv_udp.set_dest_address(addr, discovery_port)
		_adv_udp.put_packet(data)  # ошибки (нет сети на интерфейсе) игнорируем


# ---------------- поиск (клиент) ----------------

func start_browsing() -> Error:
	if not supported():
		return ERR_UNAVAILABLE
	if _listen:
		return OK
	_listen = PacketPeerUDP.new()
	var err := _listen.bind(discovery_port, "*")
	if err != OK:
		# IPv6-сокет недоступен/запрещён — пробуем чистый IPv4
		err = _listen.bind(discovery_port, "0.0.0.0")
	if err != OK:
		_listen = null
		return err
	_games.clear()
	set_process(true)
	return OK


func stop_browsing() -> void:
	if _listen:
		_listen.close()
		_listen = null
	if not _games.is_empty():
		_games.clear()
		games_changed.emit([])
	_update_process()


func is_browsing() -> bool:
	return _listen != null


func get_games() -> Array:
	var out := []
	for g in _games.values():
		var e: Dictionary = g.duplicate()
		e.erase("seen")
		out.append(e)
	out.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return out


func _update_process() -> void:
	set_process(_adv_udp != null or _listen != null)


func _process(delta: float) -> void:
	if _adv_udp:
		_adv_timer += delta
		if _adv_timer >= ADVERT_INTERVAL:
			_adv_timer = 0.0
			_send_advert()
	if _listen:
		_poll_listen()


func _poll_listen() -> void:
	var changed := false
	var now := Time.get_ticks_msec()
	while _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		if pkt.size() > 2048:
			continue
		var m = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(m) != TYPE_DICTIONARY or m.get("g") != MAGIC:
			continue
		var hid := str(m.get("hid", ip))
		var entry := {
			"id": hid,
			"ip": ip,
			"port": int(m.get("port", 8777)),
			"name": str(m.get("name", "Игра")).left(40),
			"players": int(m.get("players", 1)),
			"max": int(m.get("max", 8)),
			"version": str(m.get("version", "")),
			"compatible": int(m.get("proto", 0)) == _proto,
			"open": bool(m.get("open", true)),
			"own": hid == _hid,  # наша же игра (хост и поиск в одном процессе)
		}
		var old = _games.get(hid)
		if old != null:
			# Один и тот же хост приходит и через 127.0.0.1, и через адрес в сети — берём сетевой.
			if ip.begins_with("127.") and not str(old.ip).begins_with("127."):
				entry.ip = old.ip
			for k in ["ip", "port", "name", "players", "max", "version", "compatible", "open"]:
				if old.get(k) != entry[k]:
					changed = true
					break
		else:
			changed = true
		entry["seen"] = now
		_games[hid] = entry
	for hid in _games.keys():
		if now - int(_games[hid].seen) > GAME_TTL_MSEC:
			_games.erase(hid)
			changed = true
	if changed:
		games_changed.emit(get_games())
