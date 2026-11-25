extends Node
## Клиент сигнального протокола PeerJS поверх WebSocketPeer.
##
## Сервер: wss://0.peerjs.com/peerjs?key=peerjs&id=<id>&token=<token>
## Протокол (peerjs-server):
##   сервер -> {type:"OPEN"}                      — id зарегистрирован
##   сервер -> {type:"ID-TAKEN", payload:{msg}}   — id занят другим токеном
##   сервер -> {type:"ERROR", payload:{msg}}
##   сервер -> {type:"EXPIRE", src}               — адресат src не в сети (сообщение не доставлено)
##   клиент -> {type:"HEARTBEAT"} каждые 5 с      — иначе сервер выкинет через ~60 с
##   OFFER / ANSWER / CANDIDATE / LEAVE {type, dst, payload} пересылаются адресату как {type, src, dst, payload}.
## Узел сам опрашивает сокет в _process; создаётся и удаляется модулем Net.

signal opened(id: String)
## Пересланное сообщение от другого пира (OFFER/ANSWER/CANDIDATE/LEAVE/EXPIRE).
signal message_received(type: String, src: String, payload: Dictionary)
## kind: "id_taken" | "error" | "closed" | "timeout"
signal failed(kind: String, detail: String)

const HEARTBEAT_SEC := 5.0
const OPEN_TIMEOUT_SEC := 12.0

var server_host := "0.peerjs.com"
var server_port := 443
var server_path := "/peerjs"
var api_key := "peerjs"
var secure := true

var peer_id := ""
var token := ""
var is_open := false

var _ws: WebSocketPeer
var _hb := 0.0
var _open_timer := 0.0
var _active := false
var debug := OS.get_environment("KOZYR_NET_DEBUG") != ""


static func random_token(n := 12) -> String:
	const A := "abcdefghijklmnopqrstuvwxyz0123456789"
	var s := ""
	for i in n:
		s += A[randi() % A.length()]
	return s


func url() -> String:
	return "%s://%s:%d%s?key=%s&id=%s&token=%s&version=1.5.4" % [
		"wss" if secure else "ws", server_host, server_port, server_path,
		api_key.uri_encode(), peer_id.uri_encode(), token.uri_encode()]


## Подключиться под id. Повторный вызов с тем же id и токеном (после обрыва) возвращает id себе.
func open(id: String, keep_token := false) -> Error:
	close()
	peer_id = id
	if not keep_token or token == "":
		token = random_token()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 18
	_ws.max_queued_packets = 512
	var err := _ws.connect_to_url(url(), TLSOptions.client() if secure else null)
	if err != OK:
		_ws = null
		return err
	_active = true
	is_open = false
	_hb = 0.0
	_open_timer = 0.0
	set_process(true)
	return OK


func send(type: String, dst: String, payload: Dictionary) -> bool:
	return _send_raw({"type": type, "dst": dst, "payload": payload})


func close() -> void:
	_active = false
	is_open = false
	if _ws:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN or _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
			_ws.close(1000, "bye")
		_ws = null
	set_process(false)


func _ready() -> void:
	set_process(_active)


func _exit_tree() -> void:
	close()


func _send_raw(msg: Dictionary) -> bool:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var txt := JSON.stringify(msg)
	if debug:
		print("[peerjs ->] ", txt.left(300))
	return _ws.send_text(txt) == OK


func _fail(kind: String, detail: String) -> void:
	close()
	failed.emit(kind, detail)


func _process(delta: float) -> void:
	if not _active or _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED:
		_fail("closed", "код %d %s" % [_ws.get_close_code(), _ws.get_close_reason()])
		return
	if not is_open:
		_open_timer += delta
		if _open_timer > OPEN_TIMEOUT_SEC:
			_fail("timeout", "сервер не ответил за %d с" % int(OPEN_TIMEOUT_SEC))
			return
	if st != WebSocketPeer.STATE_OPEN:
		return
	while _ws != null and _ws.get_available_packet_count() > 0:
		var txt := _ws.get_packet().get_string_from_utf8()
		if debug:
			print("[peerjs <-] ", txt.left(300))
		var msg = JSON.parse_string(txt)
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		_handle(msg)
		if not _active:
			return
	_hb += delta
	if is_open and _hb >= HEARTBEAT_SEC:
		_hb = 0.0
		_send_raw({"type": "HEARTBEAT"})


func _handle(msg: Dictionary) -> void:
	var type := str(msg.get("type", ""))
	var payload = msg.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		payload = {"value": payload}
	match type:
		"OPEN":
			is_open = true
			_hb = 0.0
			opened.emit(peer_id)
		"ID-TAKEN":
			_fail("id_taken", str(payload.get("msg", "ID is taken")))
		"ERROR":
			_fail("error", str(payload.get("msg", "error")))
		"HEARTBEAT":
			pass
		"OFFER", "ANSWER", "CANDIDATE", "LEAVE", "EXPIRE":
			message_received.emit(type, str(msg.get("src", "")), payload)
		_:
			pass
