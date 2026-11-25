extends Node3D
## Контроллер партии: связывает Match (правила) с 3D-столом и интерфейсом.
## Соло-игра против ИИ; сетевая игра подменяет источник соперника и боя (см. net_game.gd).

const SAVE_PATH := "user://save.json"

var table: Table3D
var hud: Hud
var m: Match
var cards := {}                 # "p:uid" / "e:uid" → Card3D
var net_game: Node = null       # NetGame, когда идёт сетевая игра
var speed := 2
var skip_battle := false
var sel_uid := -1
var drag: Dictionary = {}       # {card, from:{z,i}, start:Vector2, moved:bool}
var feed_state: Dictionary = {} # {recv, food:[uids]}
var hand_sel := -1              # выбранная карта магии (усиление в магазине / заклинание в бою)
var targeting := false
var in_battle := false
var sound_on := true
var _slot_map := {}             # slot боя → ключ карты
var _pending_toasts: Array = []
var _lp_id := 0
var _lp_pos := Vector2.ZERO
var _lp_fired := false

func _ready() -> void:
	table = Table3D.new()
	add_child(table)
	hud = Hud.new()
	add_child(hud)
	hud.act.connect(_on_act)
	table.hover_changed.connect(_on_hover)
	m = Match.new()
	m.new_game("normal")
	_sync_all(false)
	_show_start()
	_dev_args()

## Автотест сети: процесс сам закупается (ИИ за игрока), жмёт «В бой!» и «Следующий раунд», пишет журнал.
func _nettest(role: String, ip: String, args: PackedStringArray) -> void:
	auto_fast = true
	for a in args:
		if a.begins_with("--log="): _auto_log = a.substr(6)
	var online := ip.begins_with("online")
	_on_act("net", "online" if online else "lan")
	net_game.my_name = "Ведущий" if role == "host" else "Клиент"
	if role == "host":
		net_game._host()
		if not Net.is_active() or online:
			await Net.connected
		if online:
			var f := FileAccess.open(_auto_log + ".code", FileAccess.WRITE)
			f.store_string(Net.room_code); f.close()
			print("nettest: room ", Net.room_code)
		print("nettest: host up, waiting for client")
		while net_game.players.size() < 2 or net_game.H.size() < 2:
			await get_tree().create_timer(0.5).timeout
		net_game._host_add_bot()
		await get_tree().create_timer(1.0).timeout
		net_game._host_start()
		print("nettest: started")
	elif online:
		var cf := ip.substr(7)
		while not FileAccess.file_exists(cf):
			await get_tree().create_timer(0.5).timeout
		net_game._join_online(FileAccess.get_file_as_string(cf).strip_edges())
	else:
		net_game._join_lan(ip, 8777)
	var rng := Rng.new(777 if role == "host" else 999)
	var last_round := -1
	var last_state := ""
	while true:
		await get_tree().create_timer(0.3).timeout
		var st := "%s r%d phase=%s ov=%s started=%s wait=%s view=%s" % [role, m.round_n, m.phase, hud.overlay.visible, net_game.started if net_game else null, net_game.waiting if net_game else null, net_game.view if net_game else null]
		if st != last_state:
			print(st); last_state = st
		if net_game == null or not is_instance_valid(net_game):
			break
		if m.phase == "shop" and net_game.started and not net_game.waiting and last_round != m.round_n:
			last_round = m.round_n
			Ai.take_turn(m.p, m.round_n, "normal", rng)
			_sync_all(false)
			net_game.ready_for_battle()
		elif m.phase == "result" and hud.overlay.visible:
			_log_line("round=%d hp=%d streak=%d opp=%s opp_hp=%d players=%s" % [m.round_n, m.p.hp, m.p.streak, net_game.opp_name(), net_game.opp_hp(), JSON.stringify(net_game.players.map(func(p): return [p.name, p.hp]))])
			hud.show_overlay(null)
			net_game.next_round()
		if hud.overlay.visible and net_game.view == "play" and m.phase != "result" and not net_game.started:
			_log_line("GAME OVER " + JSON.stringify(net_game.players.map(func(p): return [p.name, p.hp, p.place])))
			break
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _log_line(t: String) -> void:
	print(t)
	if _auto_log != "":
		var f := FileAccess.open(_auto_log, FileAccess.READ_WRITE if FileAccess.file_exists(_auto_log) else FileAccess.WRITE)
		if f:
			f.seek_end(); f.store_line(t)

## Автотест перетаскивания: настоящие события мыши через Input.
func _dragtest() -> void:
	hud.show_overlay(null)
	await get_tree().create_timer(1.0).timeout
	m.p.gold = 20
	_on_act("buy", 0)
	_on_act("buy", 1)
	await get_tree().create_timer(1.0).timeout
	print("bench before: ", m.p.bench.map(func(u): return u.id if u else null), " board: ", m.p.board.map(func(u): return u.id if u else null))
	var u = null
	for x in m.p.bench:
		if x: u = x; break
	var c: Card3D = cards["p:%d" % u.uid]
	var from := table.screen_pos(c.global_position + Vector3(0, 0.6, 0))
	var to := table.screen_pos(Table3D.pos_board(2) + Vector3(0, 0.3, 0))
	print("from ", from, " to ", to, " pick at from: ", table.pick(from))
	var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true; ev.position = from; ev.global_position = from
	Input.parse_input_event(ev)
	await get_tree().process_frame
	for i in 12:
		var mm := InputEventMouseMotion.new(); mm.position = from.lerp(to, (i + 1) / 12.0); mm.global_position = mm.position; mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)
		await get_tree().process_frame
	print("drag state: ", drag.keys(), " moved=", drag.get("moved"))
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = to; up.global_position = to
	Input.parse_input_event(up)
	await get_tree().create_timer(0.5).timeout
	print("table point at to: ", table.pick(to).table_point, " nearest: ", table.nearest_slot(table.pick(to).table_point, ["board:", "bench:", "sell"]))
	print("bench after: ", m.p.bench.map(func(u): return u.id if u else null), " board: ", m.p.board.map(func(u): return u.id if u else null))
	get_tree().quit()

## Для проверки без участия человека: -- --demo / --demofight / --shot=путь.png / --menu
func _dev_args() -> void:
	var args := OS.get_cmdline_user_args()
	var shot := ""
	var demo := false
	var demofight := false
	var menu := false
	for a in args:
		if a.begins_with("--shot="): shot = a.substr(7)
		elif a == "--demo": demo = true
		elif a == "--demofight": demo = true; demofight = true
		elif a == "--menu": menu = true
		elif a == "--dragtest": _dragtest()
		elif a == "--nettest-host-online": _nettest("host", "online", args)
		elif a.begins_with("--nettest-join-online="): _nettest("join", "online:" + a.substr(22), args)
		elif a.begins_with("--nettest-host"): _nettest("host", "", args)
		elif a.begins_with("--nettest-join="): _nettest("join", a.substr(15), args)
	if demo:
		hud.show_overlay(null)
		m = Match.new(12345)
		m.new_game("normal")
		m.round_n = 6; m.p.level = 4; m.ai.level = 4; m.p.gold = 24
		m.p.board = [null, null, null, null, null]
		var ids := [["nighthunter", 2], ["blackknight", 1], ["werewolf", 1], ["crimsonwitch", 1], ["guildmaster", 1]]
		for i in ids.size():
			m.p.board[i] = Rules.new_unit(ids[i][0], ids[i][1])
		m.p.board[1].items = ["sword", "joker"]
		m.p.bench[0] = Rules.new_unit("cutpurse"); m.p.bench[1] = Rules.new_unit("vampire"); m.p.bench[3] = Rules.new_unit("sellsword", 2)
		m.p.hand = ["fireball", "bless", "feather"]
		var eids := ["sellsword", "shadowmaster", "deathlord", "necro", "plaguedoc"]
		for i in 5:
			m.ai.board[i] = Rules.new_unit(eids[i])
		_sync_all(false)
	if demo and args.has("--hover"):
		await get_tree().create_timer(1.5).timeout
		_on_hover(cards["p:%d" % m.p.board[0].uid])
	if demofight:
		await get_tree().create_timer(2.0).timeout
		_fight()
	if shot != "":
		await get_tree().create_timer(9.0 if demofight else 4.0).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		get_tree().quit()

# =================== отрисовка состояния ===================
func _side_units(side: Dictionary) -> Array:
	var out: Array = []
	for i in side.board.size():
		if side.board[i] != null:
			out.append({"u": side.board[i], "z": "board", "i": i})
	for i in side.bench.size():
		if side.bench[i] != null:
			out.append({"u": side.bench[i], "z": "bench", "i": i})
	return out

func _pos_for(z: String, i: int, enemy: bool) -> Vector3:
	if enemy:
		return Table3D.pos_enemy(i)
	return Table3D.pos_board(i) if z == "board" else Table3D.pos_bench(i)

func _sync_cards(animate := true, spawn_from := Vector3.INF) -> void:
	var want := {}
	for e in _side_units(m.p):
		want["p:%d" % e.u.uid] = {"u": e.u, "pos": _pos_for(e.z, e.i, false), "side": "p"}
	for i in m.ai.board.size():
		var u = m.ai.board[i]
		if u != null:
			want["e:%d" % u.uid] = {"u": u, "pos": Table3D.pos_enemy(i), "side": "e"}
	for k in cards.keys():
		if not want.has(k):
			var c: Card3D = cards[k]
			cards.erase(k)
			var tw := c.create_tween()
			tw.tween_property(c, "scale", Vector3.ONE * 0.01, 0.2)
			tw.tween_callback(c.queue_free)
	for k in want:
		var w: Dictionary = want[k]
		var u: Dictionary = w.u
		var tex := CardFaces.face(u.id, int(u.star), u.get("items", []), u.get("fed"))
		var c: Card3D = cards.get(k)
		if c == null:
			c = Card3D.new()
			table.add_child(c)
			c.setup("hero", u.id, tex, int(u.uid), w.side)
			cards[k] = c
			if animate and spawn_from != Vector3.INF and w.side == "p":
				c.position = spawn_from
				c.arc_to(w.pos, 0.5, 1.6)
			else:
				c.position = w.pos
				if animate:
					c.scale = Vector3.ONE * 0.2
					c.create_tween().tween_property(c, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			c.set_face(tex)
			if c != drag.get("card"):
				if animate:
					c.move_to(w.pos, 0.3)
				else:
					c.position = w.pos
		c.set_meta("u", u)
		var st := Rules.stats(u)
		var hd: Dictionary = Data.HEROES[u.id]
		c.set_stats(int(st.atk), int(st.hp), Rules.rank_label(int(hd.r)) + Data.SUITS[hd.s].sym, Data.SUITS[hd.s].color.lightened(0.55), int(u.star), String(hd.n))

func _sync_all(animate := true, spawn_from := Vector3.INF) -> void:
	_sync_cards(animate, spawn_from)
	_refresh_hud()

func _refresh_hud() -> void:
	var p: Dictionary = m.p
	var foe_name: String = "Соперник · %s" % Data.DIFFN[m.diff].to_lower() if net_game == null else net_game.opp_name()
	hud.set_hp(int(p.hp), int(m.ai.hp) if net_game == null else net_game.opp_hp(), foe_name)
	hud.lbl_round.text = "Раунд %d" % m.round_n
	var board := Rules.board_units(p)
	var info := Rules.team_info(board)
	hud.set_hand_info(info.hand, Rules.unique_units(board), info.tl)
	var need: int = Data.XPNEED[p.level] if int(p.level) < 8 else 0
	var inc_text := ""
	if not m.income.is_empty():
		inc_text = "+%d проц." % int(m.income.interest) if int(m.income.interest) > 0 else ""
	hud.set_econ(int(p.gold), inc_text, int(p.level), int(p.xp), need, Rules.cap_of(int(p.level)))
	hud.set_shop(m.shop, int(p.gold))
	hud.set_magic_shop(m.magic_shop, int(p.gold), m.round_n)
	hud.set_hand(p.hand, m.round_n, hand_sel, in_battle)
	var shop_phase := m.phase == "shop" and not in_battle
	hud.set_buttons({
		"reroll": {"on": shop_phase and (m.free_roll > 0 or int(p.gold) >= 2), "text": "Обновить  даром" if m.free_roll > 0 else "Обновить  2"},
		"xp": {"on": shop_phase and int(p.gold) >= 4 and int(p.level) < 8},
		"lock": {"on": shop_phase, "text": "Закреплён" if m.locked else "Закрепить"},
		"sell": {"on": shop_phase and sel_uid >= 0},
		"allin": {"on": shop_phase and (m.can_allin() or bool(p.allin)), "text": "Ва-банк!" if p.allin else "Ва-банк"},
		"fight": {"on": shop_phase},
	})
	var chips := []
	if p.allin: chips.append("Ва-банк!")
	var bt := m.bounty_text()
	if bt != "": chips.append(bt)
	if int(p.streak) >= 2: chips.append("Серия побед: %d" % p.streak)
	elif int(p.streak) <= -2: chips.append("Серия поражений: %d" % -int(p.streak))
	hud.set_chips(chips)
	hud.set_hint(_step_hint())
	_update_slots()

func _step_hint() -> String:
	if in_battle:
		if targeting: return "Выберите цель для заклинания."
		return "Бой идёт сам. Можно разыграть до 2 заклинаний из руки магии."
	if not feed_state.is_empty():
		return "Жертвоприношение: выберите карту, которую скормить. Esc или правый клик — отмена."
	if hand_sel >= 0:
		return "Выберите героя, которому отдать усиление."
	var p: Dictionary = m.p
	if Rules.all_units(p).is_empty():
		return "Купите героя в магазине внизу: клик по карте."
	if Rules.board_count(p) == 0:
		return "Перетащите героя со скамьи на линию боя."
	if m.can_allin():
		return "Вы отстаёте: доступен «Ва-банк». Победа — соперник теряет вдвое больше, поражение — вы в 1,5 раза больше."
	for e in _side_units(p):
		if int(e.u.star) >= 2 and not m.feed_targets(int(e.u.uid)).is_empty():
			return "Можно принести жертву: правый клик по герою, затем карта ★★ той же стихии — герой получит 15% её силы."
	if Rules.board_count(p) < Rules.cap_of(int(p.level)) and _side_units(p).size() > Rules.board_count(p):
		return "На поле есть место: поставьте ещё героя со скамьи."
	return ""

func _update_slots() -> void:
	var cap := Rules.cap_of(int(m.p.level))
	for i in 5:
		var on: bool = i < cap or m.p.board[i] != null
		table.highlight_slot("board:%d" % i, 1.0 if on else 0.25)
		table.highlight_slot("eboard:%d" % i, 1.0)
	for i in 6:
		table.highlight_slot("bench:%d" % i, 1.0)
	table.highlight_slot("sell", 1.0 if not in_battle else 0.3)

# =================== действия интерфейса ===================
func _res(r: Dictionary) -> bool:
	if not r.get("ok", false):
		var reason: String = r.get("reason", "")
		if reason != "":
			hud.toast(reason, "bad")
		return false
	return true

func _on_act(name: String, arg: Variant) -> void:
	match name:
		"buy":
			if m.phase != "shop" or in_battle: return
			var id = m.shop[arg]
			if _res(m.buy(arg)):
				Sfx.play("buy")
				var from := table.camera.project_position(hud.shop_buttons[arg].get_global_rect().get_center(), 6.0)
				_sync_all(true, from)
				if id != null:
					hud.show_info(CardFaces.face(id, 1), Data.HEROES[id].n, Data.ab_desc(id, 1))
		"buy_magic":
			if m.phase != "shop" or in_battle: return
			if _res(m.buy_magic(arg)):
				Sfx.play("buy")
				_refresh_hud()
		"reroll":
			if _res(m.reroll()):
				Sfx.play("reroll")
				_refresh_hud()
		"xp":
			var lv := int(m.p.level)
			if _res(m.buy_xp()):
				Sfx.play("level" if int(m.p.level) > lv else "buy")
				if int(m.p.level) > lv:
					hud.toast("Уровень %d: на поле до %d карт" % [m.p.level, Rules.cap_of(int(m.p.level))], "good")
				_refresh_hud()
		"lock":
			m.toggle_lock(); _refresh_hud()
		"sell":
			if sel_uid >= 0:
				var loc = Rules.loc_of_uid(m.p, sel_uid)
				if not loc.is_empty() and _res(m.sell(loc.zone, loc.i)):
					Sfx.play("sell")
					sel_uid = -1
					_sync_all()
		"allin":
			var was: bool = m.p.allin
			if _res(m.toggle_allin()):
				if not was and m.p.allin:
					hud.toast("Ва-банк! Победа: соперник теряет вдвое больше ОЗ. Поражение: вы теряете в 1,5 раза больше.", "good")
				_refresh_hud()
			elif not was:
				hud.toast(m.allin_reason(), "bad")
		"fight":
			if net_game:
				net_game.ready_for_battle()
			else:
				_fight()
		"speed":
			speed = arg
			hud.set_battle_mode(true, speed)
		"skip":
			skip_battle = true
		"hand":
			_on_hand(arg)
		"hover_buy":
			var id = m.shop[arg]
			if id != null:
				hud.show_info(CardFaces.face(id, 1), "%s · %s%s" % [Data.HEROES[id].n, Rules.rank_label(int(Data.HEROES[id].r)), Data.SUITS[Data.HEROES[id].s].sym], _hero_text(id, 1, null))
		"hover_buy_magic":
			var k = m.magic_shop[arg]
			if k != null:
				hud.show_info(CardFaces.magic_face(k, m.round_n), Data.MAGIC[k].n, Data.magic_desc(k, m.round_n))
		"hover_hand":
			if arg < m.p.hand.size():
				var k: String = m.p.hand[arg]
				hud.show_info(CardFaces.magic_face(k, m.round_n), Data.MAGIC[k].n, Data.magic_desc(k, m.round_n))
		"sound":
			sound_on = not sound_on
			Sfx.enabled = sound_on
			hud.btn_sound.text = "Звук вкл." if sound_on else "Звук выкл."
		"rules":
			_show_rules()
		"menu":
			_show_start()
		"start":
			hud.show_overlay(null)
			_new_game(arg)
		"continue":
			hud.show_overlay(null)
			_load_game()
		"close":
			hud.show_overlay(null)
		"next":
			hud.show_overlay(null)
			_next_round()
		"net":
			if net_game == null:
				net_game = preload("res://scripts/net/net_game.gd").new()
				add_child(net_game)
				net_game.setup(self)
			net_game.show_menu(arg)
		_:
			if net_game and net_game.has_method("on_act"):
				net_game.on_act(name, arg)

func _hero_text(id: String, star: int, fed) -> String:
	var d: Dictionary = Data.HEROES[id]
	var su: Dictionary = Data.SUITS[d.s]
	var st := Rules.stats({"id": id, "star": star, "fed": fed})
	var t := "%s · стихия «%s» · стоимость %d\nАТК %d · ОЗ %d · мана %d\n%s: %s" % [
		"★".repeat(star), su.name, d.c, st.atk, st.hp, d.mm, d.ab.n, Data.ab_desc(id, star, fed)]
	if fed != null and int(fed.get("n", 0)) > 0:
		t += "\nСъедено карт: %d из %d (+%d АТК, +%d ОЗ)." % [fed.n, Data.FEED_MAX, fed.atk, fed.hp]
	return t

func _on_hover(c: Card3D) -> void:
	if c == null or not c.has_meta("u") or not drag.is_empty():
		hud.hide_zoom()
		return
	var u: Dictionary = c.get_meta("u")
	hud.show_zoom_hero(u, table.screen_pos(c.global_position))
	var d: Dictionary = Data.HEROES[u.id]
	hud.show_info(CardFaces.face(u.id, int(u.star), u.get("items", []), u.get("fed")),
		"%s %s · %s%s" % [d.n, "★".repeat(int(u.star)), Rules.rank_label(int(d.r)), Data.SUITS[d.s].sym], _hero_text(u.id, int(u.star), u.get("fed")))

# =================== рука магии ===================
func _on_hand(i: int) -> void:
	if i >= m.p.hand.size():
		return
	var k: String = m.p.hand[i]
	var spell: bool = Data.MAGIC[k].k == "spell"
	if in_battle:
		if not spell:
			hud.toast("Усиления выдаются героям между боями", "bad"); return
		if Data.MAGIC[k].t == null:
			_cast(i, -1)
		else:
			hand_sel = i; targeting = true
			_refresh_hud()
	else:
		if spell:
			hud.toast("Заклинания разыгрываются в бою", "bad"); return
		hand_sel = -1 if hand_sel == i else i
		_refresh_hud()

func _cast(i: int, target_uid: int) -> void:
	var r: Dictionary
	if net_game:
		r = net_game.play_spell(i, target_uid)
	else:
		r = m.play_spell(i, target_uid)
	if _res(r):
		Sfx.play("cast")
		hud.toast("«%s» сработает в начале следующего хода" % Data.MAGIC[r.key].n, "good")
	hand_sel = -1; targeting = false
	_refresh_hud()

# =================== мышь на столе ===================
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		if not feed_state.is_empty(): _end_feed()
		elif hand_sel >= 0: hand_sel = -1; targeting = false; _refresh_hud()
		return
	# телефон: долгое нажатие = правый клик (жертвоприношение)
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_lp_pos = st.position
			_lp_id += 1
			var my_id := _lp_id
			get_tree().create_timer(0.55).timeout.connect(func():
				if my_id == _lp_id and (drag.is_empty() or not drag.moved):
					if not drag.is_empty():
						var c: Card3D = drag.card
						drag = {}
						c.set_tilt(true)
						_sync_cards(true)
					_lp_fired = true
					_right(_lp_pos))
		else:
			_lp_id += 1
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed: _press(mb.position)
			elif _lp_fired: _lp_fired = false
			else: _release(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_right(mb.position)
	elif ev is InputEventMouseMotion and not drag.is_empty():
		var mm := ev as InputEventMouseMotion
		if (mm.position - drag.start).length() > 6:
			drag.moved = true
		if drag.moved:
			var p: Vector3 = table.pick(mm.position).table_point
			var c: Card3D = drag.card
			c.position = Vector3(p.x, 0.5, p.z)
			var s := table.nearest_slot(p, ["board:", "bench:", "sell"])
			for n in table.slots:
				if String(n).begins_with("eboard"): continue
				table.highlight_slot(n, 1.6 if n == s else 1.0)

func _card_key(c: Card3D) -> String:
	for k in cards:
		if cards[k] == c:
			return k
	return ""

func _press(pos: Vector2) -> void:
	var hit := table.pick(pos)
	var c: Card3D = hit.get("card")
	# бой: выбор цели заклинания
	if in_battle:
		if targeting and c:
			var k: String = m.p.hand[hand_sel]
			var want_foe: bool = Data.MAGIC[k].t == "foe"
			if (c.side == "e") == want_foe:
				_cast(hand_sel, c.uid)
			else:
				hud.toast("Выберите %s" % ("врага" if want_foe else "союзника"), "bad")
		return
	if m.phase != "shop":
		return
	# жертвоприношение
	if not feed_state.is_empty():
		if c and c.side == "p" and feed_state.food.has(c.uid):
			_do_feed(c.uid)
		else:
			_end_feed()
		return
	# усиление на героя
	if hand_sel >= 0:
		if c and c.side == "p":
			var loc = Rules.loc_of_uid(m.p, c.uid)
			if not loc.is_empty() and _res(m.use_item(hand_sel, loc.zone, loc.i)):
				Sfx.play("cast"); c.pop()
				hand_sel = -1
				_sync_all()
		else:
			hand_sel = -1; _refresh_hud()
		return
	if c and c.side == "p":
		var loc = Rules.loc_of_uid(m.p, c.uid)
		if not loc.is_empty():
			drag = {"card": c, "from": loc, "start": pos, "moved": false}
			c.set_tilt(false)

func _release(pos: Vector2) -> void:
	if drag.is_empty():
		return
	var c: Card3D = drag.card
	var from: Dictionary = drag.from
	var moved: bool = drag.moved
	drag = {}
	c.set_tilt(true)
	if not moved:
		_select(c.uid)
		_sync_cards(true)
		return
	var p: Vector3 = table.pick(pos).table_point
	var s := table.nearest_slot(p, ["board:", "bench:", "sell"])
	if s == "sell":
		if _res(m.sell(from.zone, from.i)):
			Sfx.play("sell")
			if sel_uid == c.uid: sel_uid = -1
	elif s != "":
		var parts := s.split(":")
		var r := m.move(from.zone, from.i, parts[0], int(parts[1]))
		if _res(r):
			Sfx.play("place")
	_sync_all()

func _select(uid: int) -> void:
	sel_uid = -1 if sel_uid == uid else uid
	for k in cards:
		var cc: Card3D = cards[k]
		cc.set_selected(cc.side == "p" and cc.uid == sel_uid)
	_refresh_hud()

func _right(pos: Vector2) -> void:
	if in_battle or m.phase != "shop":
		return
	if not feed_state.is_empty():
		_end_feed(); return
	var c: Card3D = table.pick_card(pos)
	if c and c.side == "p":
		_start_feed(c.uid)

# =================== жертвоприношение ===================
func _start_feed(uid: int) -> void:
	var food := m.feed_targets(uid)
	if food.is_empty():
		var why := m.feed_reason(uid)
		hud.toast(why if why != "" else "Нечем накормить", "bad")
		return
	feed_state = {"recv": uid, "food": food}
	table.set_dark(true)
	hud.feeding(true)
	for k in cards:
		var c: Card3D = cards[k]
		if c.side == "p" and c.uid == uid:
			c.set_dim(1.0); c.set_selected(true, Color("b83a3a"))
		elif c.side == "p" and food.has(c.uid):
			c.set_dim(1.0); c.set_selected(true, Color("e0b04a"))
		else:
			c.set_dim(0.18); c.set_selected(false)
	for n in table.slots:
		table.highlight_slot(n, 0.1)
	_refresh_hud()

func _end_feed() -> void:
	feed_state = {}
	table.set_dark(false)
	hud.feeding(false)
	for k in cards:
		var c: Card3D = cards[k]
		c.set_dim(1.0)
		c.set_selected(c.side == "p" and c.uid == sel_uid)
	_refresh_hud()

func _do_feed(food_uid: int) -> void:
	var recv: int = feed_state.recv
	var r := m.feed(recv, food_uid)
	if not _res(r):
		return
	var fc: Card3D = cards.get("p:%d" % food_uid)
	var rc: Card3D = cards.get("p:%d" % recv)
	if fc and rc:
		cards.erase("p:%d" % food_uid)
		var tw := fc.arc_to(rc.position + Vector3(0, 0.3, 0), 0.4, 0.8)
		tw.tween_property(fc, "scale", Vector3.ONE * 0.05, 0.15)
		tw.tween_callback(fc.queue_free)
		tw.tween_callback(func(): rc.pop(1.18); rc.float_text("+%d АТК  +%d ОЗ" % [r.atk, r.hp], Color("ffd39a")))
	Sfx.play("feed")
	hud.toast("Жертва принята: +%d АТК, +%d ОЗ (%d из %d)" % [r.atk, r.hp, r.n, Data.FEED_MAX], "good")
	var more := m.feed_targets(recv)
	_end_feed()
	_sync_all()
	if not more.is_empty():
		_start_feed(recv)

# =================== бой ===================
var auto_fast := false
var _auto_log := ""

func _wait(t: float) -> void:
	if skip_battle or auto_fast:
		return
	await get_tree().create_timer(t / speed).timeout

func _fight() -> void:
	if m.phase != "shop" or in_battle:
		return
	if Rules.board_count(m.p) == 0:
		hud.toast("Поставьте хотя бы одного героя на линию", "bad")
		return
	if not feed_state.is_empty():
		_end_feed()
	var b := m.start_battle()
	await _play_battle(b, "home")
	var res := m.finish_battle()
	_after_battle(res)

## Проигрывает бой Battle на столе. my_tag — за какую сторону игрок ("home"/"away").
## step_source — Callable, возвращающий массив событий следующего хода (для сети); по умолчанию b.step().
func _play_battle(b, my_tag: String, step_source: Callable = Callable()) -> void:
	in_battle = true
	skip_battle = false
	sel_uid = -1
	hand_sel = -1
	targeting = false
	_sync_cards(true)
	await get_tree().create_timer(0.35).timeout
	_slot_map.clear()
	for u in (b.units() if b else []):
		var mine: bool = u.side == my_tag
		_slot_map[int(u.slot)] = ("p:%d" if mine else "e:%d") % int(u.uid)
	for k in cards:
		var c: Card3D = cards[k]
		c.set_selected(false)
		c.show_bars(c.position.distance_to(Table3D.pos_bench(0)) > 0.1 and _is_on_board(k))
	_update_bars(b)
	hud.set_battle_mode(true, speed)
	hud.clear_log()
	var my_hand: String = Data.HANDS[b.team_hand(my_tag)].n
	var their_hand: String = Data.HANDS[b.team_hand(Battle.other(my_tag))].n
	hud.add_log("Раунд %d: %s против %s" % [m.round_n, my_hand, their_hand], "#f3cf73")
	if m.p.allin:
		hud.show_banner("Вы идёте ва-банк!", Color("e06a5a")); await _wait(1.2)
	_refresh_hud()
	while not b.over():
		var evs: Array = step_source.call() if step_source.is_valid() else b.step()
		if evs.is_empty() and step_source.is_valid():
			await get_tree().process_frame
			continue
		if not in_battle:
			break
		await _animate(evs, b, my_tag)
		_update_bars(b)
		await _wait(0.25)
	in_battle = false
	targeting = false
	hud.set_battle_mode(false)
	hud.set_step("")

func _is_on_board(k: String) -> bool:
	if k.begins_with("e:"):
		return true
	var uid := int(k.split(":")[1])
	for u in m.p.board:
		if u != null and int(u.uid) == uid:
			return true
	return false

func _card_at_slot(slot: int) -> Card3D:
	return cards.get(_slot_map.get(slot, ""))

func _update_bars(b) -> void:
	for u in b.units():
		var c := _card_at_slot(int(u.slot))
		if c:
			c.set_bars(int(u.hp), int(u.max_hp), int(u.mana), int(u.mm), int(u.shield))

func _animate(evs: Array, b, my_tag: String) -> void:
	for e in evs:
		var c := _card_at_slot(int(e.get("u", -99)))
		match String(e.t):
			"step":
				hud.set_step("Ход %d" % e.n)
			"spell":
				var mine: bool = e.side == my_tag
				hud.show_banner(Data.MAGIC[e.key].n, Color("f3cf73") if mine else Color("e88a7a"))
				hud.add_log("%s разыгрывает «%s»" % ["Вы" if mine else "Соперник", Data.MAGIC[e.key].n], "#9fd0ff" if mine else "#ffb0a0")
				Sfx.play("cast")
				await _wait(0.6)
			"attack":
				var t := _card_at_slot(int(e.tgt))
				if c and t:
					c.lunge(t.position)
					Sfx.play("hit")
					await _wait(0.16)
			"cast":
				if c:
					c.pop(1.15)
					c.float_text(String(e.name), Color("ffe6a8"))
					Sfx.play("cast")
					await _wait(0.3)
			"hit":
				var t := _card_at_slot(int(e.tgt))
				if t:
					t.shake(0.06 if not e.crit else 0.12)
					var txt := "-%d" % int(e.dmg) if int(e.dmg) > 0 else ("щит" if int(e.absorbed) > 0 else "0")
					var col := Color("ffffff") if not e.crit else Color("ffcf5a")
					if e.kind == "poison": col = Color("a6e26a")
					t.float_text(txt + ("!" if e.crit else ""), col, e.crit)
					t.set_bars(int(e.hp), int(_max_hp(b, int(e.tgt))), int(e.mana), _mm(b, int(e.tgt)), int(e.shield))
					await _wait(0.12)
			"death":
				if c:
					c.die()
					Sfx.play("death")
					await _wait(0.25)
			"heal":
				if c and int(e.amount) > 0:
					c.float_text("+%d" % int(e.amount), Color("7fe0a0"))
			"shield":
				if c: c.float_text("щит +%d" % int(e.amount), Color("e8f0ff"))
			"stun":
				if c: c.float_text("заморожен" if e.kind == "spell" else "оглушён", Color("bfe3ff"))
			"poison":
				if c: c.float_text("яд", Color("a6e26a"))
			"buff":
				if c: c.float_text("%+d%% АТК" % int(e.pct), Color("ffd39a") if int(e.pct) > 0 else Color("c9b0ff"))
			"revive":
				if c:
					c.revive(); c.show_bars(true)
					c.float_text("восстал", Color("ffe6a8"))
					await _wait(0.3)
			"end":
				pass

func _max_hp(b, slot: int) -> int:
	var u = b.unit(slot)
	return int(u.max_hp) if u else 1

func _mm(b, slot: int) -> int:
	var u = b.unit(slot)
	return int(u.mm) if u else 100

func _after_battle(res: Dictionary) -> void:
	for k in cards:
		var c: Card3D = cards[k]
		c.show_bars(false)
		c.set_dim(1.0)
		c.set_tilt(true)
	var o: String = res.outcome
	Sfx.play("win" if o == "win" else ("lose" if o == "lose" else "draw"))
	_refresh_hud()
	if res.get("over", "") != "":
		_show_game_over(res)
	else:
		_show_result(res)

## Итог раунда в сетевой игре (данные от ведущего).
func _after_battle_net(r: Dictionary) -> void:
	for k in cards:
		var c: Card3D = cards[k]
		c.show_bars(false); c.set_dim(1.0); c.set_tilt(true)
	var o: String = r.outcome
	Sfx.play("win" if o == "win" else ("lose" if o == "lose" else "draw"))
	_refresh_hud()
	var v := _vbox(8)
	var title: String = {"win": "Победа в раунде!", "lose": "Поражение", "draw": "Ничья"}[o]
	var t := _ink(title, 38, "TitleLabel")
	t.add_theme_color_override("font_color", Color("2f7a3a") if o == "win" else (Color("9a2b22") if o == "lose" else Color("6a5338")))
	v.add_child(t)
	v.add_child(_ink("Соперник: %s. Вы потеряли %d ОЗ, он — %d ОЗ." % [r.opp_name, r.dmg_p, r.dmg_e], 19))
	for n in r.get("notes", []):
		v.add_child(_ink(String(n), 16))
	var rows: Array = r.get("standings", []).duplicate()
	rows.sort_custom(func(a, b): return int(a.hp) > int(b.hp))
	for p in rows:
		v.add_child(_ink("%s%s — %d ОЗ%s" % ["✝ " if not p.alive else "", p.name, int(p.hp), " · бот" if p.bot else ""], 16))
	if not bool(r.alive):
		v.add_child(_ink("Вы выбыли. Место: %d. Можно досмотреть игру или выйти в меню." % int(r.place), 18))
		v.add_child(_button("Выйти в меню", "net_leave", null, "GoldButton"))
	else:
		v.add_child(_button("Следующий раунд", "net_next", null, "GoldButton"))
	hud.show_overlay(v, false)

func _next_round() -> void:
	if net_game:
		net_game.next_round()
		return
	m.next_round()
	sel_uid = -1
	_sync_all()
	if not m.income.is_empty():
		var inc: Dictionary = m.income
		var parts := ["5 за раунд"]
		if int(inc.interest) > 0: parts.append("%d процентов" % inc.interest)
		if int(inc.sb) > 0: parts.append("%d за серию" % inc.sb)
		hud.toast("+%d золота: %s" % [inc.gold, ", ".join(parts)])
	if m.free_roll > 0:
		hud.toast("После поражения: первое обновление магазина бесплатно", "good")
	if m.level_up:
		hud.toast("Уровень %d: на поле до %d карт" % [m.p.level, Rules.cap_of(int(m.p.level))], "good")
	_save()

# =================== партия, сохранение ===================
func _new_game(diff: String) -> void:
	for k in cards:
		cards[k].queue_free()
	cards.clear()
	m = Match.new()
	m.new_game(diff)
	sel_uid = -1; hand_sel = -1
	hud.clear_log()
	_sync_all()
	_save()

func _save() -> void:
	if net_game:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(m.save_state()))

func _has_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return j if j is Dictionary and j.get("phase", "") == "shop" else {}

func _load_game() -> void:
	var d := _has_save()
	for k in cards:
		cards[k].queue_free()
	cards.clear()
	m = Match.new()
	if d.is_empty() or not m.load_state(d):
		m.new_game("normal")
	_sync_all()

# =================== оверлеи ===================
func _vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func _ink(text: String, size := 18, variation := "InkLabel") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 560
	return l

func _button(text: String, action: String, arg: Variant = null, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, 50)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _on_act(action, arg))
	return b

func _show_start() -> void:
	var v := _vbox(14)
	var logo := TextureRect.new()
	logo.texture = UiTheme.icon("title_logo")
	if logo.texture:
		logo.custom_minimum_size = Vector2(560, 160)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(logo)
	else:
		var t := _ink("Козырная Арена", 52, "TitleLabel")
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
	var fan := HBoxContainer.new()
	fan.alignment = BoxContainer.ALIGNMENT_CENTER
	fan.add_theme_constant_override("separation", -38)
	var fan_cards := [["spadequeen", 2], ["countess", 2], ["reaper", 3], ["blooddemon", 3], ["mercqueen", 2]]
	for i in fan_cards.size():
		var tr := TextureRect.new()
		tr.texture = CardFaces.face(fan_cards[i][0], fan_cards[i][1])
		tr.custom_minimum_size = Vector2(116, 162)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.pivot_offset = Vector2(58, 220)
		tr.rotation = deg_to_rad((i - 2) * 9)
		fan.add_child(tr)
	v.add_child(fan)
	var tag := _ink("Подпольный турнир стихий: собирайте из героев покерную руку, кормите сильных слабыми и выбивайте соперников из игры.", 18)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	var sv := _has_save()
	if not sv.is_empty():
		v.add_child(_button("Продолжить: раунд %d, %s соперник" % [sv.round, Data.DIFFN[sv.diff].to_lower()], "continue", null, "GoldButton"))
	var diffs := HBoxContainer.new()
	diffs.add_theme_constant_override("separation", 10)
	for d in ["easy", "normal", "hard"]:
		var b := _button(Data.DIFFN[d], "start", d, "BlueButton" if d == "normal" else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		diffs.add_child(b)
	v.add_child(_ink("Одиночная игра против ИИ", 20, "InkLabel"))
	v.add_child(diffs)
	v.add_child(_ink("С друзьями", 20, "InkLabel"))
	var nets := HBoxContainer.new()
	nets.add_theme_constant_override("separation", 10)
	var b1 := _button("Онлайн по коду", "net", "online", "WoodButton")
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nets.add_child(b1)
	if Net.has_method("lan_supported") and Net.lan_supported():
		var b2 := _button("По локальной сети", "net", "lan", "WoodButton")
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nets.add_child(b2)
	v.add_child(nets)
	v.add_child(_button("Как играть", "rules"))
	hud.show_overlay(v)

const RULES_TEXT := """Магазин. Каждый раунд приносит 5 золота и проценты с накоплений (1 за каждые 10, до 5). Купите героя кликом по карте внизу. Три одинаковые карты сливаются в ★★, три ★★ — в ★★★.

Поле — это ваша рука. До 5 героев на линиях. Пара, две пары, тройка, стрит, флеш, фулл-хаус, каре (только с Джокером) и стрит-флеш усиливают весь отряд. Комбинацию собирают только разные герои: копии одного считаются одной картой.

Стихии — союзы. 2 или 4 разных героя одной стихии: Лёд — криты, Огонь — отряд лечится каждый ход, Свет — щит на старте боя, Природа — больше ОЗ.

Магия. Усиления отдаются героям между боями (клик по карте в руке, затем по герою). Заклинания разыгрываются в бою, не больше 2 за бой.

Жертвоприношение. Правый клик по герою (на телефоне — долгое нажатие): скормите ему карту ★★ или ★★★ той же стихии — герой навсегда получит 15% её АТК и ОЗ. Не больше 2 карт на героя.

Камбэк. Ва-банк — когда вы отстаёте: победа отнимает у соперника вдвое больше, поражение — у вас в 1,5 раза больше. Раз в 3 раунда. Награда за голову: прервите серию из 3+ побед и получите золото и карту магии. За обычное поражение — не больше 18 ОЗ. После поражения первое обновление магазина бесплатно, а витрина чаще подбрасывает нужные карты.

Бой идёт сам. Урон после поражения зависит от раунда и выживших врагов. У каждого 100 ОЗ: кто остался последним — забирает банк.

Иконки героев и магии: game-icons.net (CC BY 3.0). Шрифты: Philosopher, Rubik (OFL)."""

func _show_rules() -> void:
	var v := _vbox(12)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var l := _ink(RULES_TEXT, 17)
	l.custom_minimum_size.x = 600
	sc.add_child(l)
	v.add_child(_ink("Правила", 34, "TitleLabel"))
	v.add_child(sc)
	v.add_child(_button("Понятно", "close", null, "GoldButton"))
	hud.show_overlay(v)

func _show_result(res: Dictionary) -> void:
	var v := _vbox(10)
	var o: String = res.outcome
	var title: String = {"win": "Победа в раунде!", "lose": "Поражение", "draw": "Ничья"}[o]
	var t := _ink(title, 40, "TitleLabel")
	t.add_theme_color_override("font_color", Color("2f7a3a") if o == "win" else (Color("9a2b22") if o == "lose" else Color("6a5338")))
	v.add_child(t)
	v.add_child(_ink("Вы потеряли %d ОЗ · соперник потерял %d ОЗ" % [res.dmg_p, res.dmg_e], 20))
	for n in res.get("notes", []):
		v.add_child(_ink(String(n), 17))
	v.add_child(_button("Следующий раунд", "next", null, "GoldButton"))
	hud.show_overlay(v, false)

func _show_game_over(res: Dictionary) -> void:
	var v := _vbox(12)
	var o: String = res.over
	v.add_child(_ink({"win": "Вы забрали банк!", "lose": "Игра окончена", "draw": "Ничья"}[o], 46, "TitleLabel"))
	v.add_child(_ink("Раунд %d. Ваш уровень %d, рука «%s»." % [m.round_n, m.p.level, Data.HANDS[Rules.team_info(Rules.board_units(m.p)).hand].n], 19))
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	v.add_child(_button("Новая игра", "menu", null, "GoldButton"))
	hud.show_overlay(v)
