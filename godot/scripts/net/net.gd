extends Node
## Автозагрузка Net — транспорт мультиплеера «Козырной Арены».
##
## После успешного подключения игра пользуется обычным API Godot: `multiplayer`, `@rpc`,
## multiplayer.get_unique_id() (хост всегда = 1). Net только поднимает/опускает MultiplayerPeer.
##
## Режимы:
##   LAN    — ENetMultiplayerPeer, порт 8777; поиск игр — UDP-рассылка на 8778 (lan_discovery.gd).
##   online — WebRTCMultiplayerPeer, звезда (хост = 1), сигналинг через облачный PeerJS (peerjs_signaling.gd).
##
## Сигналы:
##   connected               — клиент: подключён к хосту; хост: сервер/комната поднят(а) (online: сразу после room_ready).
##   connection_failed(text) — понятная причина по-русски; состояние уже сброшено (mode == "").
##   peer_joined(id) / peer_left(id) — из multiplayer.peer_connected / peer_disconnected.
##   disconnected            — связь с хостом потеряна после подключения (у клиента); состояние сброшено.
##   room_ready(code)        — online-хост: код комнаты (6 символов) готов, его можно показывать.
##   lan_games_changed(list) — список LAN-игр: [{id, ip, port, name, players, max, version, compatible, open, own}]
##
## ── Как клиенту онлайн назначается id мультиплеера (подробно — в конце файла) ──
## Клиент сначала шлёт хосту через PeerJS «заявку» — OFFER с SDP-заглушкой и metadata.kozyr="join".
## Хост выдаёт ему следующий свободный id (2, 3, …) ответом ANSWER{metadata:{kozyr:"welcome", mp_id}}
## (или metadata.kozyr="reject" с причиной). Только после этого клиент делает create_client(mp_id), add_peer(conn, 1)
## и отправляет обычный PeerJS OFFER с SDP; хост делает add_peer(conn, mp_id) и отвечает ANSWER с SDP.

signal connected
signal connection_failed(reason: String)
signal peer_joined(id: int)
signal peer_left(id: int)
signal disconnected
signal room_ready(code: String)
signal lan_games_changed(list: Array)
## Быстрая игра: одинокий ведущий нашёл стол с людьми на «младшем» месте и пересаживается туда
## (Net уже сам начал новое подключение; игре надо сбросить своё лобби).
signal quick_switch

const LAN_PORT := 8777
const DISCOVERY_PORT := 8778
const MAX_CLIENTS := 7                       # 8 игроков в лобби
const NET_PROTOCOL := 3                      # меняется при несовместимых изменениях сетевых сообщений
const ROOM_PREFIX := "kozyr-godot-v1-"
const CLIENT_PREFIX := "kozyr-godot-c-"
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # без 0/O, 1/I
const CODE_LEN := 6
## Быстрая игра: QUICK_SLOTS «общих столов» с постоянными PeerJS-id. Кто занял стол — ведущий.
## Ищущий опрашивает все столы разом (заявка kozyr:"status"); пустой стол сервер отмечает EXPIRE.
const QUICK_SLOTS := 12
const QUICK_PREFIX := "kozyr-godot-q3-"      # цифра = NET_PROTOCOL: разные версии не смешиваются
const QUICK_PROBE_MS := 8000                 # EXPIRE от облачного PeerJS приходит через ~5–6 с
const QUICK_MERGE_MS := 7000                 # одинокий ведущий проверяет младшие столы
const QUICK_TRIES := 3
## Облачный PeerJS проверяет форму сообщений: OFFER/ANSWER без правдоподобного SDP (и без label/
## reliable/serialization у OFFER) он не пересылает, а закрывает сокет отправителя. Поэтому служебные
## сообщения (заявка/выдача id/отказ) — это OFFER/ANSWER с такой SDP-заглушкой и полем metadata.kozyr.
const CTL_SDP := "v=0
o=- 0 0 IN IP4 0.0.0.0
s=kozyr-control
t=0 0
"
const ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]},
]

# тайминги (мс)
const LAN_CONNECT_TIMEOUT := 7000
const LAN_ATTEMPTS := 2
const ONLINE_TOTAL_TIMEOUT := 45000          # от join_online до connected
const JOIN_RESEND_MS := 3000                 # заявка без ответа — повторить
const JOIN_MAX_SENDS := 5
const EXPIRE_RETRIES := 3                    # «хост не в сети» — столько раз переспросить (как в старом JS)
const EXPIRE_RETRY_DELAY := 2000
const OFFER_RESEND_MS := 5000
const RTC_ATTEMPT_TIMEOUT := 18000           # одна попытка ICE/DTLS; потом новая заявка
const RTC_ATTEMPTS := 2
const HOST_PENDING_TIMEOUT := 30000          # хост забывает не подключившегося клиента
const HOST_ID_RETRIES := 5                   # код занят — новый код
const HOST_RECONNECT_MS := 3000              # обрыв связи хоста с PeerJS — переподключение

const LanDiscovery := preload("res://scripts/net/lan_discovery.gd")
const PeerJSSignaling := preload("res://scripts/net/peerjs_signaling.gd")

## true у ведущего (хоста) — у него multiplayer.get_unique_id() == 1.
var is_host := false
## "lan" | "online" | ""
var mode := ""
## Код комнаты (online): у хоста — после room_ready, у клиента — тот, к которому подключается.
var room_code := ""
## Имя игры/хоста для LAN-объявления (можно менять до/после host_lan()).
var player_name := "Игрок"
## Принимает ли хост новых игроков (выключить при старте партии: LAN-объявление пометит open=false,
## онлайн-заявки получат отказ «Игра уже началась»).
var accepting_players := true:
	set(v):
		accepting_players = v
		_refresh_advert()
		if not v and quick and is_host and _sig:
			_sig.close()  # партия началась — освобождаем общий стол для других
			_host_reconnect_at = 0
## Быстрая игра (подбор игроков), а не комната по коду.
var quick := false
## Номер общего стола (у ведущего — свой, у игрока — к которому подключается).
var quick_slot := 0

var _q_phase := ""          # "" | "probe" | "join" | "claim"
var _q_res := {}            # slot -> {"st": "open"|"closed"|"empty", "humans": n}
var _q_probe_until := 0
var _q_tries := 0
var _q_claim: Array = []    # свободные столы, которые пробуем занять
var _q_merge_next := 0
var _q_merge_cids := {}     # cid -> slot (проверка младших столов одиноким ведущим)

var _phase := ""            # "" | "connecting" | "ready"
var _deadline := 0          # ticks_msec общего таймаута подключения (0 = нет)
var _lan: Node
var _sig: Node
var _rtc: WebRTCMultiplayerPeer

# LAN-клиент
var _lan_ip := ""
var _lan_port := LAN_PORT
var _lan_attempt := 0

# online-хост
var _host_id_attempt := 0
var _next_mp_id := 2
var _pending := {}          # connectionId -> {src, mp_id, conn, t, connected}
var _host_reconnect_at := 0

# online-клиент
var _host_peer := ""
var _cid := ""              # connectionId текущей заявки
var _my_mp_id := 0
var _join_sends := 0
var _join_next := 0
var _expire_count := 0
var _rtc_attempt := 0
var _rtc_started := 0
var _conn: WebRTCPeerConnection
var _offer: Dictionary = {}
var _offer_next := 0
var _offer_sends := 0
var _have_answer := false
var _pending_cands: Array = []
var _retry_at := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lan = LanDiscovery.new()
	_lan.name = "LanDiscovery"
	_lan.discovery_port = DISCOVERY_PORT
	add_child(_lan)
	_lan.games_changed.connect(func(l): lan_games_changed.emit(l))
	var mp := multiplayer
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected_to_server)
	mp.connection_failed.connect(_on_mp_connection_failed)
	mp.server_disconnected.connect(_on_server_disconnected)


# ═════════════════════════ публичное API ═════════════════════════

## LAN доступен везде, кроме веба (в браузере нет UDP/ENet).
func lan_supported() -> bool:
	return LanDiscovery.supported()


## Онлайн доступен, если есть реализация WebRTC (на вебе встроена, на ПК/Android — аддон webrtc_native).
func online_supported() -> bool:
	if OS.has_feature("web"):
		return true
	# Класс из аддона webrtc_native. Без его библиотеки (например, exe скопирован без DLL)
	# WebRTCPeerConnection.new() создаёт пустую заглушку, которая «успешно» ничего не делает.
	return ClassDB.class_exists(&"WebRTCLibPeerConnection")


func is_active() -> bool:
	return mode != ""


func is_connected_ready() -> bool:
	return _phase == "ready"


func version_string() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


func host_lan(port := LAN_PORT) -> void:
	leave()
	if not lan_supported():
		_fail("Игра по локальной сети недоступна в браузере")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		_fail("Не удалось открыть порт %d — возможно, игра уже запущена или порт занят" % port)
		return
	mode = "lan"
	is_host = true
	multiplayer.multiplayer_peer = peer
	_phase = "ready"
	_lan_port = port
	_lan.start_advertising(_advert_info(), NET_PROTOCOL)
	connected.emit()


func join_lan(ip: String, port := LAN_PORT) -> void:
	leave()
	if not lan_supported():
		_fail("Игра по локальной сети недоступна в браузере")
		return
	ip = ip.strip_edges()
	if ip == "":
		_fail("Не указан адрес хоста")
		return
	mode = "lan"
	is_host = false
	_lan_ip = ip
	_lan_port = port
	_lan_attempt = 0
	_phase = "connecting"
	_lan_try_connect()


func start_lan_browse() -> bool:
	if not lan_supported():
		return false
	var err: Error = _lan.start_browsing(NET_PROTOCOL)
	if err != OK:
		push_warning("Net: не удалось слушать UDP %d (%s)" % [DISCOVERY_PORT, error_string(err)])
	return err == OK


func stop_lan_browse() -> void:
	_lan.stop_browsing()


## Совместимость с DESIGN.md: find_lan_games() = start_lan_browse().
func find_lan_games() -> bool:
	return start_lan_browse()


func get_lan_games() -> Array:
	return _lan.get_games()


## Создать онлайн-комнату. Код придёт сигналом room_ready(code), затем connected.
func host_online() -> void:
	leave()
	if not online_supported():
		_fail("Онлайн-игра недоступна: нет модуля WebRTC")
		return
	mode = "online"
	is_host = true
	_phase = "connecting"
	_host_id_attempt = 0
	_next_mp_id = 2
	_pending.clear()
	_deadline = Time.get_ticks_msec() + 20000
	_host_open_signaling(false)


func join_online(code: String) -> void:
	leave()
	code = normalize_code(code)
	if not is_valid_code(code):
		_fail("Неверный код комнаты: нужно %d символов (буквы и цифры)" % CODE_LEN)
		return
	if not online_supported():
		_fail("Онлайн-игра недоступна: нет модуля WebRTC")
		return
	mode = "online"
	is_host = false
	room_code = code
	_host_peer = ROOM_PREFIX + code
	_phase = "connecting"
	_expire_count = 0
	_rtc_attempt = 0
	_deadline = Time.get_ticks_msec() + ONLINE_TOTAL_TIMEOUT
	_ensure_sig()
	var err: Error = _sig.open(CLIENT_PREFIX + PeerJSSignaling.random_token(16))
	if err != OK:
		_fail("Нет соединения с сервером комнат")


## Быстрая игра: найти открытый стол с людьми или самому стать ведущим свободного стола.
func quick_match() -> void:
	var tries := _q_tries
	leave()
	if not online_supported():
		_fail("Онлайн-игра недоступна: нет модуля WebRTC")
		return
	mode = "online"
	is_host = false
	quick = true
	_q_tries = tries + 1
	_phase = "connecting"
	_deadline = Time.get_ticks_msec() + ONLINE_TOTAL_TIMEOUT + QUICK_PROBE_MS
	_q_phase = "probe"
	_q_res.clear()
	_q_probe_until = 0
	_expire_count = 0
	_rtc_attempt = 0
	_ensure_sig()
	if _sig.open(CLIENT_PREFIX + PeerJSSignaling.random_token(16)) != OK:
		_fail("Нет соединения с сервером комнат")


static func quick_peer(slot: int) -> String:
	return QUICK_PREFIX + str(slot)


func _q_send_probes() -> void:
	_q_probe_until = Time.get_ticks_msec() + QUICK_PROBE_MS
	for slot in range(1, QUICK_SLOTS + 1):
		var cid := "kq_%d_%s" % [slot, PeerJSSignaling.random_token(6)]
		_sig.send("OFFER", quick_peer(slot), _ctl_payload("offer", cid, {"kozyr": "status", "proto": NET_PROTOCOL}))


func _q_slot_of(peer: String) -> int:
	if not peer.begins_with(QUICK_PREFIX):
		return 0
	return int(peer.substr(QUICK_PREFIX.length()))


## Ответы на опрос столов (у ищущего).
func _q_on_probe_message(type: String, src: String, payload: Dictionary) -> void:
	var slot := _q_slot_of(src)
	if slot < 1:
		return
	if type == "EXPIRE":
		_q_res[slot] = {"st": "empty", "humans": 0}
	elif type == "ANSWER" and _ctl_kind(payload) == "status":
		var m: Dictionary = payload.metadata
		var ok := bool(m.get("open", false)) and int(m.get("proto", 0)) == NET_PROTOCOL
		_q_res[slot] = {"st": "open" if ok else "closed", "humans": int(m.get("humans", 0))}
	else:
		return
	if _q_res.size() >= QUICK_SLOTS:
		_q_decide()


func _q_decide() -> void:
	if _q_phase != "probe":
		return
	var best := 0
	var best_h := 0
	for slot in range(1, QUICK_SLOTS + 1):
		var r = _q_res.get(slot)
		if r and r.st == "open" and int(r.humans) > best_h:
			best = slot
			best_h = int(r.humans)
	if best > 0:
		_q_join(best)
		return
	_q_claim.clear()
	for slot in range(1, QUICK_SLOTS + 1):
		var r = _q_res.get(slot)
		if r == null or r.st == "empty":
			_q_claim.append(slot)
	_q_claim_next()


func _q_join(slot: int) -> void:
	_q_phase = "join"
	quick_slot = slot
	_host_peer = quick_peer(slot)
	_expire_count = 0
	_client_send_join(true)


func _q_claim_next() -> void:
	if _q_claim.is_empty():
		if _q_tries < QUICK_TRIES:
			quick_match()
		else:
			_fail("Все столы быстрой игры заняты. Попробуйте позже или создайте комнату по коду")
		return
	_q_phase = "claim"
	quick_slot = int(_q_claim.pop_front())
	is_host = true
	_next_mp_id = 2
	_pending.clear()
	_deadline = Time.get_ticks_msec() + 20000
	_ensure_sig()
	if _sig.open(quick_peer(quick_slot)) != OK:
		_fail("Нет соединения с сервером комнат")


## Подключение к найденному столу не вышло (отказ/стол пропал) — ищем заново.
func _q_retry_or_fail(reason: String) -> void:
	if quick and _q_tries < QUICK_TRIES:
		quick_match()
	else:
		_fail(reason)


## Одинокий ведущий: есть ли люди за младшими столами? Если да — пересаживаемся.
func _q_merge_tick(now: int) -> void:
	if not quick or quick_slot <= 1 or not accepting_players or _sig == null or not _sig.is_open:
		return
	if not multiplayer.get_peers().is_empty() or not _pending.is_empty():
		return
	if now < _q_merge_next:
		return
	_q_merge_next = now + QUICK_MERGE_MS
	_q_merge_cids.clear()
	for slot in range(1, quick_slot):
		var cid := "km_%d_%s" % [slot, PeerJSSignaling.random_token(6)]
		_q_merge_cids[cid] = slot
		_sig.send("OFFER", quick_peer(slot), _ctl_payload("offer", cid, {"kozyr": "status", "proto": NET_PROTOCOL}))


## Выйти из игры/комнаты (без сигналов). Безопасно вызывать в любом состоянии.
func leave() -> void:
	_q_tries = 0
	# LEAVE облачный сервер не пересылает (закрывает наш сокет), так что не шлём: хост уберёт
	# незавершённую заявку по таймауту, а подключённые узнают об уходе по WebRTC.
	_teardown()


static func normalize_code(code: String) -> String:
	return code.strip_edges().to_upper().replace(" ", "").replace("-", "")


static func is_valid_code(code: String) -> bool:
	if code.length() != CODE_LEN:
		return false
	for ch in code:
		if not CODE_ALPHABET.contains(ch):
			return false
	return true


static func make_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in CODE_LEN:
		s += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return s


# ═════════════════════════ внутреннее: общее ═════════════════════════

func _teardown() -> void:
	_lan.stop_advertising()
	if _sig:
		_sig.close()
	if _conn:
		_conn.close()
		_conn = null
	for p in _pending.values():
		if p.get("conn"):
			p.conn.close()
	_pending.clear()
	if _rtc:
		_rtc.close()
		_rtc = null
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = ""
	is_host = false
	room_code = ""
	_phase = ""
	_deadline = 0
	_host_peer = ""
	_cid = ""
	_my_mp_id = 0
	_offer = {}
	_have_answer = false
	_pending_cands.clear()
	_retry_at = 0
	_host_reconnect_at = 0
	accepting_players = true
	quick = false
	quick_slot = 0
	_q_phase = ""
	_q_res.clear()
	_q_claim.clear()
	_q_merge_cids.clear()
	_q_merge_next = 0


func _fail(reason: String) -> void:
	push_warning("Net: " + reason)
	_teardown()
	connection_failed.emit(reason)


func _ensure_sig() -> void:
	if _sig == null:
		_sig = PeerJSSignaling.new()
		_sig.name = "PeerJS"
		add_child(_sig)
		_sig.opened.connect(_on_sig_opened)
		_sig.failed.connect(_on_sig_failed)
		_sig.message_received.connect(_on_sig_message)


func _new_conn() -> WebRTCPeerConnection:
	var c := WebRTCPeerConnection.new()
	var err := c.initialize({"iceServers": ICE_SERVERS})
	if err != OK:
		return null
	return c


func _advert_info() -> Dictionary:
	return {
		"name": player_name,
		"players": 1 + (multiplayer.get_peers().size() if multiplayer.has_multiplayer_peer() else 0),
		"max": MAX_CLIENTS + 1,
		"port": _lan_port,
		"version": version_string(),
		"open": accepting_players,
	}


func _refresh_advert() -> void:
	if _lan and _lan.is_advertising():
		_lan.update_advert(_advert_info())


func _process(_delta: float) -> void:
	if mode == "":
		return
	var now := Time.get_ticks_msec()
	if _phase == "connecting" and _deadline > 0 and now > _deadline:
		_on_timeout()
		return
	if mode == "lan" and not is_host and _phase == "connecting" and _retry_at > 0 and now > _retry_at:
		# ENet ещё не ответил — попытка не удалась
		_lan_attempt_failed()
	elif mode == "online":
		if is_host:
			_host_tick(now)
		else:
			_client_tick(now)


func _on_timeout() -> void:
	if mode == "lan":
		_fail("Хост %s не отвечает. Проверьте адрес и что вы в одной сети" % _lan_ip)
	elif is_host:
		_fail("Нет соединения с сервером комнат. Проверьте интернет")
	elif _sig == null or not _sig.is_open:
		_fail("Нет соединения с сервером комнат. Проверьте интернет")
	elif _my_mp_id == 0:
		_fail("Комната не отвечает. Проверьте код и что хост не закрыл игру")
	else:
		_fail("Не удалось установить прямое соединение с хостом (сеть блокирует WebRTC)")


# ═════════════════════════ multiplayer ═════════════════════════

func _on_peer_connected(id: int) -> void:
	if is_host and mode == "online":
		for p in _pending.values():
			if p.mp_id == id:
				p.connected = true
	_refresh_advert()
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if is_host and mode == "online":
		for cid in _pending.keys():
			if _pending[cid].mp_id == id:
				_pending.erase(cid)
				break
	_refresh_advert()
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	if _phase != "connecting":
		return
	_phase = "ready"
	_deadline = 0
	_retry_at = 0
	if mode == "online" and _sig:
		_sig.close()  # клиенту сигналинг больше не нужен
	connected.emit()


func _on_mp_connection_failed() -> void:
	if mode == "lan" and not is_host and _phase == "connecting":
		_lan_attempt_failed()


func _on_server_disconnected() -> void:
	if mode == "" or is_host:
		return
	var was_ready := _phase == "ready"
	if was_ready:
		_teardown()
		disconnected.emit()
	elif mode == "online":
		_client_rtc_failed()


# ═════════════════════════ LAN-клиент ═════════════════════════

func _lan_try_connect() -> void:
	_lan_attempt += 1
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_lan_ip, _lan_port)
	if err != OK:
		_fail("Неверный адрес хоста: %s" % _lan_ip)
		return
	multiplayer.multiplayer_peer = peer
	_retry_at = Time.get_ticks_msec() + LAN_CONNECT_TIMEOUT
	_deadline = 0


func _lan_attempt_failed() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_retry_at = 0
	if _lan_attempt < LAN_ATTEMPTS:
		_lan_try_connect()
	else:
		_fail("Не удалось подключиться к %s:%d. Проверьте адрес, что хост создал игру и что брандмауэр не блокирует игру" % [_lan_ip, _lan_port])


# ═════════════════════════ online: сигналинг ═════════════════════════

func _host_open_signaling(reconnect: bool) -> void:
	_ensure_sig()
	if not reconnect:
		room_code = make_code()
	var err: Error = _sig.open(quick_peer(quick_slot) if quick else ROOM_PREFIX + room_code, reconnect)
	if err != OK and not reconnect:
		_fail("Нет соединения с сервером комнат")


func _on_sig_opened(_id: String) -> void:
	if mode != "online":
		return
	if is_host:
		_host_reconnect_at = 0
		if _rtc == null:
			_rtc = WebRTCMultiplayerPeer.new()
			_rtc.create_server()
			multiplayer.multiplayer_peer = _rtc
			_phase = "ready"
			_deadline = 0
			_q_phase = ""
			_q_merge_next = Time.get_ticks_msec() + QUICK_MERGE_MS
			room_ready.emit(room_code)
			connected.emit()
	elif quick and _q_phase == "probe":
		_q_send_probes()
	else:
		_client_send_join(true)


func _on_sig_failed(kind: String, detail: String) -> void:
	if mode != "online":
		return
	if is_host:
		if quick and _q_phase == "claim":
			# Стол только что занял кто-то другой. Облачный PeerJS в этом случае часто просто
			# закрывает сокет, не успев прислать ID-TAKEN, — поэтому любой обрыв до OPEN = «занят».
			# Перебор ограничен: столы кончатся → новый поиск (до QUICK_TRIES) → понятная ошибка.
			_q_claim_next()
			return
		if kind == "id_taken" and _phase == "connecting":
			_host_id_attempt += 1
			if _host_id_attempt < HOST_ID_RETRIES:
				_host_open_signaling(false)
			else:
				_fail("Не удалось создать комнату: сервер комнат занят, попробуйте позже")
			return
		if _phase == "ready":
			# Уже играющие клиенты живут по WebRTC без сервера; переподключаемся ради новых.
			push_warning("Net: связь с сервером комнат потеряна (%s: %s), переподключение" % [kind, detail])
			_host_reconnect_at = Time.get_ticks_msec() + HOST_RECONNECT_MS
			return
		if kind == "id_taken":
			return
		_fail("Нет соединения с сервером комнат (%s)" % detail)
	else:
		if _phase == "ready":
			return
		push_warning("Net: сигналинг клиента: %s %s" % [kind, detail])
		if kind == "error" and detail.to_lower().contains("id"):
			_fail("Сервер комнат отклонил подключение: %s" % detail)
		else:
			_fail("Нет соединения с сервером комнат. Проверьте интернет")


func _on_sig_message(type: String, src: String, payload: Dictionary) -> void:
	if mode != "online":
		return
	if is_host:
		_host_on_message(type, src, payload)
	else:
		_client_on_message(type, src, payload)


# ═════════════════════════ online: хост ═════════════════════════

func _host_tick(now: int) -> void:
	_q_merge_tick(now)
	if _host_reconnect_at > 0 and now > _host_reconnect_at:
		_host_reconnect_at = now + HOST_RECONNECT_MS * 3
		_host_open_signaling(true)
	for cid in _pending.keys():
		var p: Dictionary = _pending[cid]
		if not p.connected and now - int(p.t) > HOST_PENDING_TIMEOUT:
			if p.get("conn") and _rtc and _rtc.has_peer(p.mp_id):
				_rtc.remove_peer(p.mp_id)
			_pending.erase(cid)


func _host_on_message(type: String, src: String, payload: Dictionary) -> void:
	var cid := str(payload.get("connectionId", ""))
	match type:
		"ANSWER":
			if _q_merge_cids.has(cid) and _ctl_kind(payload) == "status":
				var m: Dictionary = payload.metadata
				if bool(m.get("open", false)) and int(m.get("humans", 0)) > 0 \
						and multiplayer.get_peers().is_empty() and _pending.is_empty():
					quick_match()
					quick_switch.emit()
		"OFFER":
			if _ctl_kind(payload) == "status":
				var humans := 1 + multiplayer.get_peers().size()
				var is_open := accepting_players and humans < MAX_CLIENTS + 1
				_sig.send("ANSWER", src, _ctl_payload("answer", cid, {"kozyr": "status", "open": is_open, "humans": humans, "proto": NET_PROTOCOL}))
			elif _ctl_kind(payload) == "join":
				_host_on_join(src, cid, payload)
			elif _ctl_kind(payload) == "" and payload.has("sdp"):
				_host_on_offer(src, cid, payload)
		"CANDIDATE":
			var p = _pending.get(cid)
			if p and p.src == src and p.get("conn"):
				_add_candidate(p.conn, payload.get("candidate", {}))
		"LEAVE":
			for k in _pending.keys():
				var p: Dictionary = _pending[k]
				if p.src == src and not p.connected:
					if _rtc and _rtc.has_peer(p.mp_id):
						_rtc.remove_peer(p.mp_id)
					_pending.erase(k)


func _host_reject(src: String, cid: String, reason: String) -> void:
	_sig.send("ANSWER", src, _ctl_payload("answer", cid, {"kozyr": "reject", "reason": reason}))


func _host_on_join(src: String, cid: String, payload: Dictionary) -> void:
	if cid == "":
		return
	var meta: Dictionary = payload.metadata
	if int(meta.get("proto", 0)) != NET_PROTOCOL:
		_host_reject(src, cid, "Версии игры не совпадают (у хоста %s). Обновите игру" % version_string())
		return
	var p = _pending.get(cid)
	if p == null:
		if not accepting_players:
			_host_reject(src, cid, "Игра в этой комнате уже началась")
			return
		var used := 0
		for q in _pending.values():
			if not q.connected:
				used += 1
		if multiplayer.get_peers().size() + used >= MAX_CLIENTS:
			_host_reject(src, cid, "Комната заполнена")
			return
		p = {"src": src, "cid": cid, "mp_id": _next_mp_id, "conn": null, "t": Time.get_ticks_msec(), "connected": false}
		_next_mp_id += 1
		_pending[cid] = p
	elif p.src != src:
		return
	# Повторная заявка с тем же connectionId получает тот же id (ответ мог потеряться).
	_sig.send("ANSWER", src, _ctl_payload("answer", cid, {"kozyr": "welcome", "mp_id": p.mp_id, "proto": NET_PROTOCOL}))


func _host_on_offer(src: String, cid: String, payload: Dictionary) -> void:
	var p = _pending.get(cid)
	if p == null or p.src != src:
		_host_reject(src, cid, "Заявка устарела, подключитесь заново")
		return
	var sdp = payload.get("sdp", {})
	if typeof(sdp) != TYPE_DICTIONARY or str(sdp.get("type")) != "offer":
		return
	if p.get("conn"):
		if p.get("offer_sdp") == str(sdp.get("sdp")):
			if p.has("answer"):  # повтор того же OFFER — ответ потерялся, шлём ещё раз
				_sig.send("ANSWER", src, p.answer)
			return
		if _rtc.has_peer(p.mp_id):
			_rtc.remove_peer(p.mp_id)
		p.conn.close()
		p.erase("answer")
	var conn := _new_conn()
	if conn == null:
		_host_reject(src, cid, "У хоста не работает WebRTC")
		return
	p.conn = conn
	p.offer_sdp = str(sdp.get("sdp"))
	p.t = Time.get_ticks_msec()
	conn.session_description_created.connect(func(t: String, s: String):
		if _pending.get(cid) != p:
			return
		conn.set_local_description(t, s)
		var ans := {"sdp": {"type": t, "sdp": s}, "type": "data", "connectionId": cid}
		p.answer = ans
		_sig.send("ANSWER", src, ans))
	conn.ice_candidate_created.connect(func(media: String, index: int, cand: String):
		if _pending.get(cid) == p:
			_sig.send("CANDIDATE", src, {"candidate": {"candidate": cand, "sdpMid": media, "sdpMLineIndex": index}, "type": "data", "connectionId": cid}))
	var err := _rtc.add_peer(conn, p.mp_id)  # каналы данных создаёт сам WebRTCMultiplayerPeer (negotiated)
	if err != OK:
		_host_reject(src, cid, "Хост не смог принять игрока")
		_pending.erase(cid)
		return
	conn.set_remote_description("offer", p.offer_sdp)  # ответ придёт в session_description_created


# ═════════════════════════ online: клиент ═════════════════════════

func _client_send_join(new_request: bool) -> void:
	if new_request:
		_cid = "kz_" + PeerJSSignaling.random_token(12)
		_join_sends = 0
		_my_mp_id = 0
	_join_sends += 1
	_join_next = Time.get_ticks_msec() + JOIN_RESEND_MS
	_sig.send("OFFER", _host_peer, _ctl_payload("offer", _cid, {"kozyr": "join", "proto": NET_PROTOCOL, "version": version_string()}))


func _client_tick(now: int) -> void:
	if _phase != "connecting" or _sig == null:
		return
	if quick and _q_phase == "probe":
		if _q_probe_until > 0 and now > _q_probe_until:
			_q_decide()  # кто не ответил и не «истёк» — считаем свободным
		return
	if _retry_at > 0:
		if now > _retry_at:
			_retry_at = 0
			if _sig.is_open:
				_client_send_join(true)
		return
	if not _sig.is_open:
		return
	if _my_mp_id == 0:
		if now > _join_next:
			if _join_sends >= JOIN_MAX_SENDS:
				if quick:
					_q_retry_or_fail("Стол быстрой игры не отвечает")
				else:
					_fail("Комната не отвечает. Проверьте код и что хост не закрыл игру")
			else:
				_client_send_join(false)
		return
	if not _have_answer and not _offer.is_empty() and now > _offer_next and _offer_sends < 3:
		_offer_sends += 1
		_offer_next = now + OFFER_RESEND_MS
		_sig.send("OFFER", _host_peer, _offer)
	if _conn:
		var st := _conn.get_connection_state()
		if st == WebRTCPeerConnection.STATE_FAILED or now - _rtc_started > RTC_ATTEMPT_TIMEOUT:
			_client_rtc_failed()


func _client_on_message(type: String, src: String, payload: Dictionary) -> void:
	if quick and _q_phase == "probe":
		_q_on_probe_message(type, src, payload)
		return
	if quick and type == "EXPIRE" and src == _host_peer and _my_mp_id == 0 and _phase == "connecting":
		_q_retry_or_fail("Стол быстрой игры пропал")
		return
	if type == "EXPIRE":
		if src != _host_peer or _my_mp_id != 0 or _phase != "connecting":
			return
		# Хоста нет на сервере (или ещё не зарегистрировался) — переспросить пару раз.
		_expire_count += 1
		if _expire_count > EXPIRE_RETRIES:
			_fail("Комната %s не найдена. Проверьте код" % room_code)
		else:
			_retry_at = Time.get_ticks_msec() + EXPIRE_RETRY_DELAY
		return
	if src != _host_peer:
		return
	var cid := str(payload.get("connectionId", ""))
	match type:
		"ANSWER":
			if cid != _cid:
				return
			match _ctl_kind(payload):
				"reject":
					var why := str(payload.metadata.get("reason", "Хост отклонил подключение"))
					if quick:
						_q_retry_or_fail(why)
					else:
						_fail(why)
				"welcome":
					if _my_mp_id == 0:
						_client_start_rtc(int(payload.metadata.get("mp_id", 0)))
				_:
					var sdp = payload.get("sdp", {})
					if typeof(sdp) == TYPE_DICTIONARY and sdp.get("type") == "answer" and _conn and not _have_answer:
						_have_answer = true
						_conn.set_remote_description("answer", str(sdp.get("sdp")))
						for c in _pending_cands:
							_add_candidate(_conn, c)
						_pending_cands.clear()
		"CANDIDATE":
			if cid != _cid or _conn == null:
				return
			if _have_answer:
				_add_candidate(_conn, payload.get("candidate", {}))
			else:
				_pending_cands.append(payload.get("candidate", {}))
		"LEAVE":
			if _phase == "connecting":
				_fail("Хост закрыл комнату")


func _client_start_rtc(mp_id: int) -> void:
	if mp_id < 2:
		_fail("Хост прислал неверные данные подключения")
		return
	_my_mp_id = mp_id
	_rtc_attempt += 1
	_rtc_started = Time.get_ticks_msec()
	_have_answer = false
	_pending_cands.clear()
	_offer = {}
	_offer_sends = 0
	_rtc = WebRTCMultiplayerPeer.new()
	_rtc.create_client(mp_id)
	_conn = _new_conn()
	if _conn == null:
		_fail("Онлайн-игра недоступна: нет модуля WebRTC")
		return
	var conn := _conn
	var cid := _cid
	conn.session_description_created.connect(func(t: String, s: String):
		if _conn != conn:
			return
		conn.set_local_description(t, s)
		_offer = {"sdp": {"type": t, "sdp": s}, "type": "data", "connectionId": cid,
			"label": "kozyr", "reliable": true, "serialization": "none",
			"browser": "godot", "metadata": {"mp_id": _my_mp_id}}
		_offer_sends = 1
		_offer_next = Time.get_ticks_msec() + OFFER_RESEND_MS
		_sig.send("OFFER", _host_peer, _offer))
	conn.ice_candidate_created.connect(func(media: String, index: int, cand: String):
		if _conn == conn and _sig.is_open:
			_sig.send("CANDIDATE", _host_peer, {"candidate": {"candidate": cand, "sdpMid": media, "sdpMLineIndex": index}, "type": "data", "connectionId": cid}))
	_rtc.add_peer(conn, 1)  # до create_offer: так WebRTCMultiplayerPeer заранее создаёт свои каналы
	multiplayer.multiplayer_peer = _rtc
	conn.create_offer()


## Попытка WebRTC не удалась (ICE failed/таймаут) — новая заявка и новый id, пока есть попытки.
func _client_rtc_failed() -> void:
	if _rtc_attempt >= RTC_ATTEMPTS:
		_fail("Не удалось установить прямое соединение с хостом (сеть блокирует WebRTC)")
		return
	if _conn:
		_conn.close()
		_conn = null
	multiplayer.multiplayer_peer = null
	if _rtc:
		_rtc.close()
		_rtc = null
	_my_mp_id = 0
	_offer = {}
	_have_answer = false
	_client_send_join(true)


func _ctl_payload(sdp_type: String, cid: String, meta: Dictionary) -> Dictionary:
	return {"sdp": {"type": sdp_type, "sdp": CTL_SDP}, "type": "data", "connectionId": cid,
		"label": "kozyr-control", "reliable": true, "serialization": "none", "metadata": meta}


## Вид служебного сообщения ("join" | "welcome" | "reject") или "" для настоящего SDP.
func _ctl_kind(payload: Dictionary) -> String:
	var m = payload.get("metadata")
	if typeof(m) == TYPE_DICTIONARY and m.has("kozyr"):
		return str(m.kozyr)
	return ""


func _add_candidate(conn: WebRTCPeerConnection, c) -> void:
	if typeof(c) != TYPE_DICTIONARY:
		return
	var cand := str(c.get("candidate", ""))
	if cand == "":
		return  # end-of-candidates
	conn.add_ice_candidate(str(c.get("sdpMid", "0")), int(c.get("sdpMLineIndex", 0)), cand)


# ═════════════════════════ протокол (документация) ═════════════════════════
# PeerJS-id: хост  = "kozyr-godot-v1-<КОД>" (КОД — 6 символов из CODE_ALPHABET);
#            клиент = "kozyr-godot-c-<16 случайных>".
# Все сообщения идут через PeerJS-сервер как {type, dst, payload}; payload.connectionId (cid) —
# id одной попытки подключения клиента, по нему хост различает заявки.
#
#  клиент                                         хост
#  OFFER  {sdp:CTL_SDP, cid, metadata:{kozyr:"join", proto}}   ─▶   выдаёт mp_id = следующий свободный
#                                                 (2,3,…), запоминает pending[cid] = {src, mp_id}
#         ◀─  ANSWER {sdp:CTL_SDP, cid, metadata:{kozyr:"welcome", mp_id}}
#           | ANSWER {sdp:CTL_SDP, cid, metadata:{kozyr:"reject", reason}}
#  create_client(mp_id); add_peer(conn, 1); create_offer()
#  OFFER  {sdp:{type:"offer",sdp}, type:"data", cid, label, reliable, serialization:"none",
#          metadata:{mp_id}}                ─▶   add_peer(conn, mp_id); set_remote_description(offer)
#         ◀─  ANSWER {sdp:{type:"answer",sdp}, type:"data", cid}
#  CANDIDATE {candidate:{candidate,sdpMid,sdpMLineIndex}, type:"data", cid}  ◀─▶ (в обе стороны)
#  … ICE/DTLS … multiplayer: peer_connected(1) у клиента / peer_connected(mp_id) у хоста,
#  клиент закрывает сигналинг; хост остаётся на сервере для новых игроков.
#
# Почему так: WebRTCMultiplayerPeer.create_client(id) требует id ДО создания соединения и оффера,
# а id должен быть уникален в комнате. Выдаёт его только хост, последовательно, поэтому коллизий нет
# (в отличие от случайных id). Повторы: заявка переотправляется каждые 3 с (тот же cid → тот же
# mp_id), OFFER — каждые 5 с (хост на тот же SDP повторяет сохранённый ANSWER). Если сервер вернул
# EXPIRE (хост не в сети) — до 3 повторов через 2 с, потом «Комната не найдена». Если ICE не сошёлся
# за 18 с — вторая попытка с новым cid/mp_id; хост забывает неподключившиеся заявки через 30 с.
