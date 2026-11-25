extends Node
## Сетевая партия поверх Net (ENet по локалке или WebRTC по коду комнаты).
## Ведущий (id 1) — авторитет: держит лобби и ОЗ всех игроков, ботов, пары, считает бои и урон.
## У каждого игрока своя экономика (магазин, золото, уровень) — локальный Match, как в web-версии.
## Раунд: все закупаются → «В бой!» шлёт ведущему снимок поля → ведущий ставит пары и шагает бои,
## дожидаясь, пока оба участника досмотрят ход (ack) → итог раунда каждому → следующий раунд.

const PROTO := 1
const MAX_PLAYERS := 8
const ACK_TIMEOUT := 8.0
const SUBMIT_TIMEOUT := 120.0

var game: Node                      # game.gd
var view := ""                      # "" | "menu" | "lobby" | "play"
var menu_kind := "online"
var my_name := ""
# ---- общее (у всех) ----
var players: Array = []             # [{id, name, hp, alive, place, bot, streak}] — от ведущего
var started := false
var round_n := 1
var opp := {}                       # {id, name, hp, streak} — соперник текущего/прошлого боя
var waiting := false                # снимок отправлен, ждём боя
var rb: RemoteBattle = null
var _pending_ack := -1
# ---- только у ведущего ----
var H := {}                         # id → {id, name, hp, streak, allin_cd, alive, place, bot, side, snap, submitted}
var _next_bot := -1
var _rng: Rng
var _battles: Array = []            # [{b, home, away, ghost_of, acks:{}, t, done}]
var _submit_deadline := 0.0
var _resolving := false
var h_round := 1                    # номер раунда у ведущего (для боёв и урона)

func setup(g: Node) -> void:
	game = g
	name = "NetGame"
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.disconnected.connect(_on_disconnected)
	Net.room_ready.connect(func(_c): _show_lobby())
	if Net.has_signal("lan_games_changed"):
		Net.lan_games_changed.connect(func(_l): if view == "menu" and menu_kind == "lan": show_menu("lan"))
	my_name = _load_name()

# =================== меню и лобби ===================
func _load_name() -> String:
	if FileAccess.file_exists("user://name.txt"):
		return FileAccess.get_file_as_string("user://name.txt").strip_edges().left(16)
	return ""

func _save_name(n: String) -> void:
	var f := FileAccess.open("user://name.txt", FileAccess.WRITE)
	if f: f.store_string(n)

func _name_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(game._ink("Ваше имя", 18))
	h.get_child(0).custom_minimum_size.x = 130
	var le := LineEdit.new()
	le.text = my_name
	le.placeholder_text = "Как вас зовут"
	le.max_length = 16
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(t): my_name = t.strip_edges(); _save_name(my_name))
	h.add_child(le)
	return h

func _nm() -> String:
	return my_name if my_name != "" else ("Игрок %d" % (randi() % 90 + 10))

func show_menu(kind: String) -> void:
	menu_kind = kind
	view = "menu"
	var v: VBoxContainer = game._vbox(12)
	v.add_child(game._ink("Онлайн по коду комнаты" if kind == "online" else "Игра по локальной сети", 34, "TitleLabel"))
	v.add_child(_name_row())
	if kind == "online":
		v.add_child(game._ink("Один создаёт комнату и сообщает друзьям код из 6 знаков. Можно играть и с ботами.", 16))
		var b: Button = game._button("Создать комнату", "net_host", null, "GoldButton")
		v.add_child(b)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var code := LineEdit.new()
		code.placeholder_text = "КОД КОМНАТЫ"
		code.max_length = 8
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code.name = "Code"
		h.add_child(code)
		var j := Button.new()
		j.text = "Войти"
		j.theme_type_variation = "BlueButton"
		j.custom_minimum_size = Vector2(150, 54)
		j.pressed.connect(func(): _join_online(code.text))
		code.text_submitted.connect(func(t): _join_online(t))
		h.add_child(j)
		v.add_child(h)
	else:
		v.add_child(game._ink("Все должны быть в одной сети Wi-Fi. Игры в сети находятся сами.", 16))
		v.add_child(game._button("Создать игру в сети", "net_host", null, "GoldButton"))
		var games: Array = Net.get_lan_games() if Net.has_method("get_lan_games") else []
		Net.start_lan_browse()
		var any := false
		for g in games:
			if g.get("own", false):
				continue
			any = true
			var gb := Button.new()
			gb.text = "Войти: %s (%d/%d)%s" % [g.name, g.players, g.max, "" if g.get("open", true) else " — идёт игра"]
			gb.theme_type_variation = "BlueButton"
			gb.disabled = not g.get("open", true) or not g.get("compatible", true)
			gb.custom_minimum_size.y = 50
			gb.pressed.connect(func(): _join_lan(g.ip, int(g.port)))
			v.add_child(gb)
		if not any:
			v.add_child(game._ink("Ищем игры в сети…", 16, "InkLabel"))
		var h := HBoxContainer.new()
		var ip := LineEdit.new()
		ip.placeholder_text = "IP ведущего, например 192.168.1.5"
		ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(ip)
		var j := Button.new()
		j.text = "Войти по IP"
		j.custom_minimum_size = Vector2(170, 50)
		j.pressed.connect(func(): _join_lan(ip.text.strip_edges(), 8777))
		h.add_child(j)
		v.add_child(h)
	v.add_child(game._button("Назад", "net_back"))
	game.hud.show_overlay(v)

func on_act(name_: String, arg: Variant) -> void:
	match name_:
		"net_host":
			_host()
		"net_back":
			Net.leave()
			Net.stop_lan_browse()
			view = ""
			game._show_start()
		"net_bot_add":
			_host_add_bot()
		"net_bot_remove":
			_host_remove_bot()
		"net_start":
			_host_start()
		"net_leave":
			_leave_to_menu()
		"net_next":
			game.hud.show_overlay(null)
			next_round()

func _host() -> void:
	Net.player_name = _nm()
	if menu_kind == "online":
		game.hud.show_overlay(game._ink("Создаём комнату…", 22))
		Net.host_online()
	else:
		Net.stop_lan_browse()
		Net.host_lan()

func _join_online(code: String) -> void:
	if code.strip_edges() == "":
		game.hud.toast("Введите код комнаты", "bad"); return
	game.hud.show_overlay(game._ink("Подключаемся к комнате %s…" % code.to_upper(), 22))
	Net.join_online(code)

func _join_lan(ip: String, port: int) -> void:
	if ip == "":
		game.hud.toast("Введите IP ведущего", "bad"); return
	Net.stop_lan_browse()
	game.hud.show_overlay(game._ink("Подключаемся к %s…" % ip, 22))
	Net.join_lan(ip, port)

func _on_connected() -> void:
	if Net.is_host:
		_rng = Rng.new(int(Time.get_unix_time_from_system()) & 0x7fffffff)
		H.clear()
		H[1] = _new_player(1, _nm(), false)
		_broadcast_lobby()
		_show_lobby()
	else:
		_to_host("hello", [_nm(), PROTO])
		game.hud.show_overlay(game._ink("Подключено. Ждём ведущего…", 22))

func _on_failed(reason: String) -> void:
	game.hud.toast(reason, "bad")
	show_menu(menu_kind)

func _on_disconnected() -> void:
	game.hud.toast("Связь с ведущим потеряна", "bad")
	_leave_to_menu()

func _leave_to_menu() -> void:
	Net.leave()
	started = false
	view = ""
	H.clear()
	players.clear()
	game.net_game = null
	game.in_battle = false
	queue_free()
	game._show_start()

func _show_lobby() -> void:
	if started:
		return
	view = "lobby"
	var v: VBoxContainer = game._vbox(12)
	v.add_child(game._ink("Лобби", 34, "TitleLabel"))
	if Net.mode == "online" and Net.room_code != "":
		var c: Label = game._ink("Код комнаты: %s" % Net.room_code, 30, "TitleLabel")
		c.add_theme_color_override("font_color", Color("8a2a1a"))
		v.add_child(c)
		v.add_child(game._ink("Скажите этот код друзьям: «Онлайн по коду» → ввести код → «Войти».", 16))
	elif Net.mode == "lan":
		v.add_child(game._ink("Друзья увидят вашу игру в разделе «По локальной сети».", 16))
	for p in players:
		var row: Label = game._ink("%s%s%s" % [p.name, " · бот" if p.bot else "", " · ведущий" if int(p.id) == 1 else ""], 20)
		v.add_child(row)
	if Net.is_host:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var a: Button = game._button("Добавить бота", "net_bot_add")
		var r: Button = game._button("Убрать бота", "net_bot_remove")
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a); h.add_child(r)
		v.add_child(h)
		var s: Button = game._button("Начать игру (%d)" % players.size(), "net_start", null, "GoldButton")
		s.disabled = players.size() < 2
		v.add_child(s)
	else:
		v.add_child(game._ink("Ждём, когда ведущий начнёт игру…", 18))
	v.add_child(game._button("Выйти", "net_leave"))
	game.hud.show_overlay(v)

# =================== транспорт ===================
func _to_host(method: String, args: Array) -> void:
	if Net.is_host:
		callv("_h_" + method, [1] + args)
	else:
		rpc_id(1, "_rpc_host", method, args)

func _to_peer(id: int, method: String, args: Array) -> void:
	if id < 0:
		return  # бот
	if id == 1:
		callv("_c_" + method, args)
	elif multiplayer.get_peers().has(id):
		rpc_id(id, "_rpc_client", method, args)

func _to_all(method: String, args: Array) -> void:
	for id in H:
		_to_peer(int(id), method, args)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_host(method: String, args: Array) -> void:
	if not Net.is_host or not has_method("_h_" + method):
		return
	callv("_h_" + method, [multiplayer.get_remote_sender_id()] + args)

@rpc("authority", "call_remote", "reliable")
func _rpc_client(method: String, args: Array) -> void:
	if has_method("_c_" + method):
		callv("_c_" + method, args)

# =================== ведущий: лобби ===================
func _new_player(id: int, nm: String, bot: bool) -> Dictionary:
	return {"id": id, "name": nm, "hp": Data.START_HP, "streak": 0, "allin_cd": 0, "alive": true, "place": 0,
		"bot": bot, "side": Rules.new_side(nm) if bot else {}, "snap": {}, "submitted": false}

func _public() -> Array:
	var out: Array = []
	for id in H:
		var p: Dictionary = H[id]
		out.append({"id": p.id, "name": p.name, "hp": p.hp, "alive": p.alive, "place": p.place, "bot": p.bot, "streak": p.streak})
	return out

func _broadcast_lobby() -> void:
	_to_all("lobby", [_public(), started, h_round])

func _h_hello(from: int, nm: String, proto: int) -> void:
	if proto != PROTO:
		return
	if started:
		# переподключение посреди игры не поддерживаем: зритель не нужен
		return
	H[from] = _new_player(from, String(nm).left(16), false)
	_broadcast_lobby()

func _on_peer_joined(_id: int) -> void:
	pass

func _on_peer_left(id: int) -> void:
	if not Net.is_host or not H.has(id):
		return
	if not started:
		H.erase(id)
	else:
		# игрок ушёл посреди партии — его место занимает бот с его последним полем
		var p: Dictionary = H[id]
		p.bot = true
		var side := Rules.new_side(p.name)
		side.hp = p.hp
		if not p.snap.is_empty():
			side.board = Rules.clean_board(p.snap.board)
		side.level = int(p.snap.get("level", 3))
		side.gold = 10
		p.side = side
		p.name += " (ушёл)"
		for bt in _battles:
			bt.acks[id] = true
		_check_all_submitted()
	_broadcast_lobby()

func _host_add_bot() -> void:
	if H.size() >= MAX_PLAYERS:
		game.hud.toast("Мест больше нет (до %d игроков)" % MAX_PLAYERS, "bad"); return
	var names := ["Шулер Вельт", "Мадам Ворона", "Граф Тень", "Сестра Пепла", "Барон Лёд", "Лиса Злата", "Старый Корень"]
	var id := _next_bot
	_next_bot -= 1
	H[id] = _new_player(id, names[(-id - 1) % names.size()] + " (бот)", true)
	H[id].side.gold = 6
	_broadcast_lobby()

func _host_remove_bot() -> void:
	for id in H.keys():
		if H[id].bot:
			H.erase(id)
			_broadcast_lobby()
			return

func _host_start() -> void:
	if H.size() < 2:
		game.hud.toast("Нужно хотя бы 2 игрока: позовите друга или добавьте бота", "bad"); return
	started = true
	Net.accepting_players = false
	h_round = 1
	_to_all("start", [])
	_broadcast_lobby()

# =================== клиент: лобби и старт ===================
func _c_lobby(list: Array, st: bool, _rn: int) -> void:
	players = list
	if not st and view != "play":
		_show_lobby()
	if view == "play":
		game._refresh_hud()

func _c_start() -> void:
	started = true
	round_n = 1
	view = "play"
	game.hud.show_overlay(null)
	for k in game.cards:
		game.cards[k].queue_free()
	game.cards.clear()
	var m := Match.new()
	m.new_game("normal")
	m.p.name = _nm()
	game.m = m
	game.hud.clear_log()
	game.hud.add_log("Сетевая игра: %d игроков." % players.size(), "#f3cf73")
	_sync_rivals()
	game._sync_all()

## Соперники для ва-банка и награды: «лидер» — самый живучий из остальных.
func _sync_rivals() -> void:
	var top := 0
	var best_streak := 0
	for p in players:
		if int(p.id) != _my_id() and p.alive:
			top = maxi(top, int(p.hp))
			best_streak = maxi(best_streak, int(p.streak))
		if int(p.id) == _my_id():
			game.m.p.hp = int(p.hp)
			game.m.p.streak = int(p.streak)
	game.m.ai.hp = top
	game.m.ai.streak = best_streak
	game.m.ai.board = Rules.clean_board(opp.get("board", []))

func _my_id() -> int:
	return multiplayer.get_unique_id()

func opp_name() -> String:
	return String(opp.get("name", "Соперники"))

func opp_hp() -> int:
	return int(opp.get("hp", game.m.ai.hp))

# =================== клиент: бой ===================
func ready_for_battle() -> void:
	var m: Match = game.m
	if waiting or m.phase != "shop":
		return
	if Rules.board_count(m.p) == 0:
		game.hud.toast("Поставьте хотя бы одного героя на линию", "bad"); return
	if not game.feed_state.is_empty():
		game._end_feed()
	waiting = true
	m.phase = "wait"
	var spells: Array = (m.p.hand as Array).filter(func(k): return Data.MAGIC[k].k == "spell")
	_to_host("submit", [{"board": m.p.board.duplicate(true), "spells": spells, "allin": m.p.allin, "level": m.p.level}])
	game.hud.set_hint("Ждём остальных игроков…")
	game._refresh_hud()
	game.hud.set_hint("Ждём остальных игроков…")

func _c_battle_begin(info: Dictionary) -> void:
	waiting = false
	var m: Match = game.m
	m.phase = "battle"
	opp = info.opp
	m.ai.board = Rules.clean_board(info.opp.board)
	m.ai.hp = int(info.opp.hp)
	rb = RemoteBattle.new(info.units, info.hands, info.tag)
	game.hud.add_log("Раунд %d: против %s%s" % [round_n, opp.name, " (призрак)" if info.get("ghost", false) else ""], "#f3cf73")
	if bool(info.opp.get("allin", false)):
		game.hud.show_banner("%s: ва-банк!" % opp.name, Color("e06a5a"))
	_pending_ack = -1
	await game._play_battle(rb, info.tag, _next_batch)
	_send_ack()
	game.hud.set_hint("Ждём, когда закончатся остальные бои…")

func _next_batch() -> Array:
	_send_ack()
	if rb == null:
		return []
	var evs: Array = rb.take()
	if not evs.is_empty():
		for e in evs:
			if e.get("t", "") == "step":
				_pending_ack = int(e.n)
	return evs

func _send_ack() -> void:
	if _pending_ack >= 0:
		_to_host("ack", [_pending_ack])
		_pending_ack = -1

func _c_battle_events(evs: Array, units: Array) -> void:
	if rb:
		rb.push(evs, units)

func play_spell(hand_i: int, target_uid: int) -> Dictionary:
	var m: Match = game.m
	if rb == null or rb.over():
		return {"ok": false}
	var hand: Array = m.p.hand
	if hand_i < 0 or hand_i >= hand.size():
		return {"ok": false}
	var k: String = hand[hand_i]
	if Data.MAGIC[k].k != "spell":
		return {"ok": false, "reason": "Усиления выдаются героям между боями"}
	if rb.spells_left(rb.my_tag) <= 0:
		return {"ok": false, "reason": "За один бой можно разыграть 2 заклинания"}
	rb.used_spell(rb.my_tag)
	hand.remove_at(hand_i)
	_to_host("cast", [k, target_uid])
	return {"ok": true, "key": k}

func _c_round_result(r: Dictionary) -> void:
	var m: Match = game.m
	m.p.hp = int(r.hp)
	m.p.streak = int(r.streak)
	m.p.gold = int(m.p.gold) + int(r.get("gold", 0))
	if String(r.get("card", "")) != "" and (m.p.hand as Array).size() < Data.HAND_MAX:
		m.p.hand.append(r.card)
	if m.p.allin:
		m.p.allin_cd = round_n + 3
	opp.hp = int(r.get("opp_hp", opp.get("hp", 0)))
	m.phase = "result"
	if rb:
		rb.force_end()
	rb = null
	game.in_battle = false
	game._after_battle_net(r)

func next_round() -> void:
	var m: Match = game.m
	if m.phase != "result":
		return
	round_n += 1
	m.round_n = round_n
	m.begin_round(false)
	_sync_rivals()
	game._sync_all()
	if m.free_roll > 0:
		game.hud.toast("После поражения: первое обновление магазина бесплатно", "good")
	if not m.income.is_empty():
		game.hud.toast("+%d золота за раунд" % int(m.income.gold))

func _c_game_over(place: int, list: Array) -> void:
	players = list
	started = false
	var v: VBoxContainer = game._vbox(10)
	v.add_child(game._ink("Вы забрали банк!" if place == 1 else "Ваше место: %d" % place, 44, "TitleLabel"))
	var sorted := list.duplicate()
	sorted.sort_custom(func(a, b): return (int(a.place) if int(a.place) > 0 else 99) < (int(b.place) if int(b.place) > 0 else 99))
	for p in sorted:
		v.add_child(game._ink("%d. %s — %d ОЗ%s" % [int(p.place), p.name, int(p.hp), " · бот" if p.bot else ""], 19))
	v.add_child(game._button("В главное меню", "net_leave", null, "GoldButton"))
	game.hud.show_overlay(v)

# =================== ведущий: раунд ===================
func _h_submit(from: int, snap: Dictionary) -> void:
	if not H.has(from) or not H[from].alive:
		return
	var p: Dictionary = H[from]
	snap.board = Rules.clean_board(snap.get("board", []))
	var spells: Array = []
	for k in snap.get("spells", []):
		if Data.MAGIC.has(k) and Data.MAGIC[k].k == "spell" and spells.size() < Data.HAND_MAX:
			spells.append(k)
	snap.spells = spells
	snap.allin = bool(snap.get("allin", false)) and int(p.allin_cd) <= h_round
	p.snap = snap
	p.submitted = true
	if _submit_deadline == 0.0:
		_submit_deadline = Time.get_ticks_msec() / 1000.0 + SUBMIT_TIMEOUT
	_check_all_submitted()

func _check_all_submitted() -> void:
	if not Net.is_host or not started or not _battles.is_empty() or _resolving:
		return
	for id in H:
		var p: Dictionary = H[id]
		if p.alive and not p.bot and not p.submitted:
			return
	_start_round_battles()

func _bot_turn(p: Dictionary) -> void:
	var s: Dictionary = p.side
	s.hp = p.hp
	s.streak = p.streak
	if h_round > 1:
		var inc := Rules.income(s, 0)
		s.gold = int(s.gold) + int(inc.gold)
		Rules.add_xp(s, 2)
	Ai.take_turn(s, h_round, "normal", _rng)
	Ai.magic(s, h_round, "normal", _rng)
	var spells: Array = (s.hand as Array).filter(func(k): return Data.MAGIC[k].k == "spell")
	p.snap = {"board": Rules.clean_board(s.board), "spells": spells, "allin": false, "level": s.level}
	var top := 0
	for id in H:
		if H[id] != p and H[id].alive:
			top = maxi(top, int(H[id].hp))
	if Ai.wants_allin(s, top, h_round, _rng):
		p.snap.allin = true

func _start_round_battles() -> void:
	_submit_deadline = 0.0
	var alive: Array = []
	for id in H:
		if H[id].alive:
			if H[id].bot:
				_bot_turn(H[id])
			alive.append(id)
	# перемешиваем и ставим пары; нечётному достаётся «призрак» — копия поля случайного соперника
	for i in range(alive.size() - 1, 0, -1):
		var j := _rng.next_int(i + 1)
		var t = alive[i]; alive[i] = alive[j]; alive[j] = t
	var pairs: Array = []
	var i := 0
	while i + 1 < alive.size():
		pairs.append([alive[i], alive[i + 1], -1])
		i += 2
	if i < alive.size():
		var ghost_src = alive[_rng.next_int(alive.size() - 1)]
		pairs.append([alive[i], ghost_src, ghost_src])
	_battles.clear()
	for pr in pairs:
		var hp_: Dictionary = H[pr[0]]
		var ap: Dictionary = H[pr[1]]
		var ghost: bool = int(pr[2]) >= 0
		var ai_home: bool = hp_.bot
		var ai_away: bool = ap.bot or ghost
		var b := Battle.new(hp_.snap.board, ap.snap.board,
			{"name": hp_.name, "ai": ai_home, "hand": hp_.snap.spells if ai_home else [], "allin": hp_.snap.allin},
			{"name": ap.name, "ai": ai_away, "hand": (ap.snap.spells if ai_away else []).duplicate(), "allin": false if ghost else ap.snap.allin},
			_rng.next_seed(), h_round)
		var bt := {"b": b, "home": pr[0], "away": pr[1], "ghost": ghost, "acks": {}, "t": 0.0, "done": false, "step": 0}
		_battles.append(bt)
		for tag in ["home", "away"]:
			var me_id = bt[tag]
			if tag == "away" and ghost:
				continue
			var other_id = bt[Battle.other(tag)]
			var o: Dictionary = H[other_id]
			_to_peer(int(me_id), "battle_begin", [{"tag": tag, "units": b.units(), "ghost": ghost and tag == "home",
				"hands": {"home": b.team_hand("home"), "away": b.team_hand("away")},
				"opp": {"id": o.id, "name": o.name + (" (призрак)" if ghost and tag == "home" else ""), "hp": o.hp, "streak": o.streak,
					"board": o.snap.board, "allin": o.snap.allin and not ghost}}])
		_reset_acks(bt)
		for id in bt.acks:
			bt.acks[id] = true   # первый ход — сразу

func _humans_in(bt: Dictionary) -> Array:
	var out: Array = []
	if not H[bt.home].bot: out.append(bt.home)
	if not bt.ghost and not H[bt.away].bot: out.append(bt.away)
	return out

func _reset_acks(bt: Dictionary) -> void:
	bt.acks = {}
	bt.t = Time.get_ticks_msec() / 1000.0
	for id in _humans_in(bt):
		bt.acks[id] = false

func _h_ack(from: int, _step: int) -> void:
	for bt in _battles:
		if bt.acks.has(from):
			bt.acks[from] = true

func _h_cast(from: int, key: String, target_uid: int) -> void:
	for bt in _battles:
		if bt.done:
			continue
		var tag := ""
		if bt.home == from: tag = "home"
		elif bt.away == from and not bt.ghost: tag = "away"
		if tag != "":
			var b: Battle = bt.b
			if (H[from].snap.spells as Array).has(key) and b.queue_spell(tag, key, target_uid):
				H[from].snap.spells.erase(key)

func _process(_dt: float) -> void:
	if not Net.is_host or not started:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _battles.is_empty():
		if _submit_deadline > 0.0 and now > _submit_deadline:
			# кто не успел — играет прошлым полем
			for id in H:
				var p: Dictionary = H[id]
				if p.alive and not p.bot and not p.submitted:
					p.submitted = true
					if p.snap.is_empty():
						p.snap = {"board": Rules.clean_board([]), "spells": [], "allin": false, "level": 1}
			_check_all_submitted()
		return
	var all_done := true
	for bt in _battles:
		if bt.done:
			continue
		all_done = false
		var b: Battle = bt.b
		var humans := _humans_in(bt)
		if humans.is_empty():
			b.run_to_end()
			bt.done = true
			continue
		var ready := true
		for id in bt.acks:
			if not bt.acks[id]:
				ready = false
		if not ready and now - float(bt.t) < ACK_TIMEOUT:
			continue
		if b.over():
			bt.done = true
			continue
		var evs := b.step()
		var units := b.units()
		for id in humans:
			_to_peer(int(id), "battle_events", [evs, units])
		_reset_acks(bt)
		if b.over():
			# ждём, пока досмотрят последний ход
			bt.step = -1
	if all_done and not _resolving:
		_resolve_round()
	elif not _resolving:
		# последний ход досмотрен — бой закрыт
		for bt in _battles:
			if not bt.done and bt.b.over():
				var ok := true
				for id in bt.acks:
					if not bt.acks[id]: ok = false
				if ok or now - float(bt.t) > ACK_TIMEOUT:
					bt.done = true

func _resolve_round() -> void:
	_resolving = true
	var base := Rules.base_damage(h_round)
	var results := {}     # id → {outcome, dmg_p, dmg_e, notes, gold, card, opp_hp}
	for id in H:
		H[id].pre_streak = int(H[id].streak)
	for bt in _battles:
		var res: Dictionary = bt.b.result()
		var home: Dictionary = H[bt.home]
		var away: Dictionary = H[bt.away]
		var ghost: bool = bt.ghost
		var o: String = res.outcome
		var h_all: bool = home.snap.allin
		var a_all: bool = away.snap.allin and not ghost
		var dmg_h := 0
		var dmg_a := 0
		if o == "home":
			dmg_a = Rules.round_damage(base, Rules.survivor_score(res.get("survivors_home", [])))
			if h_all: dmg_a *= 2
			if a_all: dmg_a = Data.r(float(dmg_a) * 1.5)
		elif o == "away":
			dmg_h = Rules.round_damage(base, Rules.survivor_score(res.get("survivors_away", [])))
			if a_all: dmg_h *= 2
			if h_all: dmg_h = Data.r(float(dmg_h) * 1.5)
		else:
			dmg_h = Rules.round_damage(base, 0); dmg_a = dmg_h
		_apply(home, away, "win" if o == "home" else ("lose" if o == "away" else "draw"), dmg_h, dmg_a, h_all, a_all, results, ghost)
		if not ghost:
			_apply(away, home, "win" if o == "away" else ("lose" if o == "home" else "draw"), dmg_a, dmg_h, a_all, h_all, results, false)
	# выбывшие и места
	var alive_after: Array = []
	for id in H:
		if H[id].alive and int(H[id].hp) <= 0:
			H[id].alive = false
	for id in H:
		if H[id].alive: alive_after.append(id)
	var dead_now: Array = []
	for id in H:
		if not H[id].alive and int(H[id].place) == 0:
			dead_now.append(id)
	dead_now.sort_custom(func(a, b): return int(H[a].hp) > int(H[b].hp))
	# места выбывших в этом раунде: после всех живых, лучшие ОЗ — выше
	var k := alive_after.size() + 1
	for id in dead_now:
		H[id].place = k
		k += 1
	var over := alive_after.size() <= 1
	if over and alive_after.size() == 1:
		H[alive_after[0]].place = 1
	_broadcast_lobby()
	for id in results:
		var r: Dictionary = results[id]
		var p: Dictionary = H[id]
		r.hp = p.hp
		r.streak = p.streak
		r.round = h_round
		r.alive = p.alive
		r.place = p.place
		r.standings = _public()
		r.opp_hp = int(H[r.opp_id].hp) if H.has(r.opp_id) else 0
		_to_peer(int(id), "round_result", [r])
	for id in H:
		H[id].submitted = false
		H[id].snap.allin = false
	_battles.clear()
	if over:
		for id in H:
			_to_peer(int(id), "game_over", [int(H[id].place), _public()])
		started = false
	else:
		h_round += 1
	_resolving = false

func _apply(me: Dictionary, them: Dictionary, outcome: String, dmg_me: int, dmg_them: int, my_all: bool, their_all: bool, results: Dictionary, _ghost: bool) -> void:
	var notes: Array = []
	if my_all:
		notes.append("Ва-банк сыграл: соперник теряет вдвое больше." if outcome == "win" else ("Ва-банк не сыграл: вы теряете в 1,5 раза больше." if outcome == "lose" else "Ва-банк: ничья, без последствий."))
		me.allin_cd = h_round + 3
	if their_all:
		notes.append("%s шёл ва-банк: %s." % [them.name, "он теряет в 1,5 раза больше" if outcome == "win" else ("вы теряете вдвое больше" if outcome == "lose" else "ничья")])
	var gold := 0
	var card := ""
	if outcome == "win" and int(them.get("pre_streak", 0)) >= 3:
		gold = int(them.pre_streak)
		card = Rules.roll_magic(_rng)
		notes.append("Награда за голову: +%d золота и карту «%s»." % [gold, Data.MAGIC[card].n])
		if me.bot:
			me.side.gold = int(me.side.gold) + gold
	me.hp = maxi(0, int(me.hp) - dmg_me)
	if outcome == "win":
		me.streak = int(me.streak) + 1 if int(me.streak) > 0 else 1
	elif outcome == "lose":
		me.streak = int(me.streak) - 1 if int(me.streak) < 0 else -1
	else:
		me.streak = 0
	if me.bot:
		me.side.hp = me.hp
		me.side.streak = me.streak
	results[me.id] = {"outcome": outcome, "dmg_p": dmg_me, "dmg_e": dmg_them, "notes": notes, "gold": gold, "card": card,
		"opp_name": them.name, "opp_id": them.id}
