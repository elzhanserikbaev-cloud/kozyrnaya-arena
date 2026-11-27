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
var fx: Fx
var _last_spell := ""

func _ready() -> void:
	table = Table3D.new()
	add_child(table)
	fx = Fx.new()
	table.add_child(fx)
	hud = Hud.new()
	add_child(hud)
	hud.act.connect(_on_act)
	table.hover_changed.connect(_on_hover)
	m = Match.new(-1, true)
	m.new_game("normal")
	_sync_all(false)
	if DisplayServer.is_touchscreen_available() and not FileAccess.file_exists("user://settings.json"):
		settings.big_ui = true   # телефон/планшет: крупнее по умолчанию
	_load_settings()
	_apply_settings()
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
		elif m.phase == "result" and hud.overlay.visible and not m.pending_reward.is_empty():
			var ch := m.choose_reward(Ai.choose_reward(m.p, m.pending_reward))
			_log_line("REWARD round=%d %s legends=%s" % [m.round_n, String(ch.get("offer", {}).get("title", "")), JSON.stringify(Rules.all_units(m.p).filter(func(u): return Data.is_legend(u.id)).map(func(u): return [u.id, u.star]))])
			_sync_all(false)
			hud.show_overlay(null)
			net_game.next_round()
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

## Автотест обучения: проходит все шаги действиями игрока.
func _tuttest() -> void:
	_on_act("tutorial", null)
	await get_tree().create_timer(0.5).timeout
	var log := []
	log.append(tutorial.step)
	tutorial.advance()                       # приветствие → купить
	await get_tree().create_timer(0.3).timeout
	_on_act("buy", 0)
	await get_tree().create_timer(0.5).timeout
	log.append(tutorial.step)
	m.move("bench", 0, "board", 2)
	_sync_all(false)
	await get_tree().create_timer(0.5).timeout
	log.append(tutorial.step)
	tutorial.advance(); tutorial.advance()   # рука, стихии → бой
	log.append(tutorial.step)
	_fight()
	await get_tree().create_timer(0.8).timeout
	skip_battle = true
	await get_tree().create_timer(3.0).timeout
	hud.show_overlay(null)
	_next_round()
	await get_tree().create_timer(0.8).timeout
	log.append([tutorial.step if tutorial else "done", m.round_n, m.phase, tutorial._battle_round if tutorial else -9, in_battle])
	tutorial.advance()
	await get_tree().create_timer(0.3).timeout
	print("tutorial steps: ", log, " finished=", tutorial == null, " saved=", settings.tutorial_done)
	get_tree().quit()

## Автотест: раунд Стража (5-й), победа, окно награды, выбор легенды.
func _monstertest(args: PackedStringArray) -> void:
	hud.show_overlay(null)
	m = Match.new(777, true)
	m.new_game("normal")
	m.round_n = 5; m.p.level = 6; m.p.gold = 30
	m.p.board = [Rules.new_unit("reaper", 2), Rules.new_unit("blooddemon", 2), Rules.new_unit("tyrant", 2), Rules.new_unit("plaguelord", 2), Rules.new_unit("guildmaster", 2)]
	for k in cards: cards[k].queue_free()
	cards.clear()
	_sync_all(false)
	print("monster round: ", m.is_monster_round(), " ", Match.monster_info(5).title, " enemy cards: ", cards.keys().filter(func(k): return k.begins_with("e:")).size())
	var shot := ""
	for a in args:
		if a.begins_with("--mshot="): shot = a.substr(8)
	await get_tree().create_timer(1.5).timeout
	if shot != "": get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_pre.png"))
	_fight()
	await get_tree().create_timer(1.0).timeout
	skip_battle = true
	await get_tree().create_timer(3.0).timeout
	print("result: ", m.last_result.get("outcome"), " monster=", m.last_result.get("monster"), " pending=", m.pending_reward.map(func(o): return o.type))
	if shot != "": get_viewport().get_texture().get_image().save_png(shot)
	if not m.pending_reward.is_empty():
		var r := m.choose_reward(0)
		print("chose: ", r.get("ok"), " ", r.get("offer", {}).get("title", ""))
		hud.show_overlay(null)
		_next_round()
		await get_tree().create_timer(1.0).timeout
		print("round now ", m.round_n, " legends owned: ", Rules.all_units(m.p).filter(func(u): return Data.is_legend(u.id)).map(func(u): return u.id))
		if shot != "": get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_after.png"))
	get_tree().quit()

## Автотест Стража и легенды: раунд 10 (костяной дракон), на линии Ледяной дракон; ярость, приём легенды, пробуждение.
func _bosstest(args: PackedStringArray) -> void:
	hud.show_overlay(null)
	m = Match.new(4242, true)
	m.new_game("normal")
	m.round_n = 10; m.p.level = 6; m.p.gold = 30
	m.p.board = [Rules.new_unit("reaper", 2), Rules.new_unit("blooddemon", 2), Rules.new_unit("frostdragon", 1), Rules.new_unit("plaguelord", 2), Rules.new_unit("guildmaster", 2)]
	for k in cards: cards[k].queue_free()
	cards.clear()
	_sync_all(false)
	var shot := ""
	for a in args:
		if a.begins_with("--bshot="): shot = a.substr(8)
	var boss_card: Card3D = null
	for k in cards:
		if cards[k].rare == "boss": boss_card = cards[k]
	print("boss card: ", boss_card != null, " scale ", boss_card.base_scale if boss_card else 0.0, " legend rare: ", cards.values().filter(func(c): return c.rare == "legend").size())
	print("round chip: ", hud.lbl_round.text)
	await get_tree().create_timer(1.5).timeout
	if shot != "": get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_pre.png"))
	_ev_count.clear()
	_fight()
	var t0 := Time.get_ticks_msec()
	var shot_rage := false
	var shot_bar := false
	while in_battle or m.phase == "battle":
		await get_tree().process_frame
		if not shot_bar and hud.boss_box.visible and Time.get_ticks_msec() - t0 > 4000:
			shot_bar = true
			if shot != "": get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_bar.png"))
		if not shot_rage and int(_ev_count.get("enrage", 0)) > 0:
			shot_rage = true
			await get_tree().create_timer(0.5).timeout
			if shot != "": get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_rage.png"))
		if Time.get_ticks_msec() - t0 > 90000:
			print("TIMEOUT"); break
	await get_tree().create_timer(1.2).timeout
	print("events: ", _ev_count)
	print("result: ", m.last_result.get("outcome"), " awakened=", m.last_result.get("awakened"), " boss bar hidden=", not hud.boss_box.visible)
	print("legend star now: ", Rules.all_units(m.p).filter(func(u): return Data.is_legend(u.id)).map(func(u): return [u.id, u.star]))
	if shot != "": get_viewport().get_texture().get_image().save_png(shot)
	hud.show_overlay(null)
	_show_codex()
	await get_tree().create_timer(0.6).timeout
	if shot != "": get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_codex.png"))
	get_tree().quit()

## Автотест: после боя (с «Пропустить») ни одна карта не лежит и не затемнена.
func _battletest() -> void:
	await get_tree().create_timer(1.5).timeout
	_on_act("speed", 4)
	_fight()
	await get_tree().create_timer(0.6).timeout
	skip_battle = true
	await get_tree().create_timer(4.0).timeout
	var bad := []
	for k in cards:
		var c: Card3D = cards[k]
		var standing := absf(c.pivot.rotation.x - (-PI / 2 + Card3D.TILT)) < 0.01
		if not standing or c._dim < 0.99 or c.scale.distance_to(Vector3.ONE) > 0.01:
			bad.append([k, snappedf(c.pivot.rotation.x, 0.01), c._dim])
	print("after battle: phase=", m.phase, " cards=", cards.size(), " not standing: ", bad, " overlay=", hud.overlay.visible)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			get_viewport().get_texture().get_image().save_png(arg.substr(7))
	get_tree().quit()

## Автотест: карты магазина не съезжают при быстром наведении; правая кнопка с движением вращает арену, щелчок — жертва.
func _uitest() -> void:
	hud.show_overlay(null)
	await get_tree().create_timer(1.0).timeout
	var before: Array = hud.shop_buttons.map(func(b): return b.global_position)
	for k in 30:
		for b in hud.shop_buttons:
			b.mouse_entered.emit()
			await get_tree().process_frame
			b.mouse_exited.emit()
	await get_tree().create_timer(0.5).timeout
	var after: Array = hud.shop_buttons.map(func(b): return b.global_position)
	print("shop drift: ", before == after, " ", before[0], " -> ", after[0])
	var yaw0 := table.cam_yaw
	var p := Vector2(800, 420)
	var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_RIGHT; ev.pressed = true; ev.position = p
	Input.parse_input_event(ev)
	await get_tree().process_frame
	for i in 10:
		var mm := InputEventMouseMotion.new(); mm.position = p + Vector2(i * 12, 0); mm.relative = Vector2(12, 0); mm.button_mask = MOUSE_BUTTON_MASK_RIGHT
		Input.parse_input_event(mm)
		await get_tree().process_frame
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_RIGHT; up.pressed = false; up.position = p + Vector2(120, 0)
	Input.parse_input_event(up)
	await get_tree().create_timer(0.3).timeout
	print("rotate: yaw ", yaw0, " -> ", table.cam_yaw, " feed_mode=", not feed_state.is_empty())
	var w: AudioStreamWAV = Sfx._stream("stone")
	print("stone sound: ", w.get_length(), " s, ", w.data.size(), " bytes")
	var mp: AudioStreamPlayer = Sfx._music[Sfx._music_cur]
	var p0 := mp.get_playback_position()
	await get_tree().create_timer(1.0).timeout
	print("music: ", Sfx._music_name, " playing=", mp.playing, " pos ", snappedf(p0, 0.01), " -> ", snappedf(mp.get_playback_position(), 0.01), " len ", snappedf(mp.stream.get_length(), 0.1), " vol ", snappedf(mp.volume_db, 0.1), " loop=", (mp.stream as AudioStreamOggVorbis).loop)
	Sfx.music("game")
	await get_tree().create_timer(2.0).timeout
	var g: AudioStreamPlayer = Sfx._music[Sfx._music_cur]
	print("music after switch: ", Sfx._music_name, " playing=", g.playing, " vol ", snappedf(g.volume_db, 0.1), " other playing=", (Sfx._music[1 - Sfx._music_cur] as AudioStreamPlayer).playing)
	w.save_to_wav(OS.get_user_data_dir() + "/stone.wav")
	get_tree().quit()

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
		elif a == "--uitest": _uitest()
		elif a == "--battletest": _battletest()
		elif a == "--continue": _on_act("continue", null)
		elif a == "--tutorial": _on_act("tutorial", null)
		elif a == "--tuttest": _tuttest()
		elif a == "--monstertest": _monstertest(args)
		elif a == "--bosstest": _bosstest(args)
		elif a == "--settings": _show_settings()
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

## Кого показывать на линии соперника: обычно поле ИИ (или соперника в сети), в раунд Стража — отряд Стража.
func _enemy_board() -> Array:
	if m.extras and m.is_monster_round() and m.phase in ["shop", "wait", "battle", "result"]:
		return Match.monster_info(m.round_n).board
	return m.ai.board

func _enemy_name() -> String:
	if m.extras and m.is_monster_round():
		return String(Match.monster_info(m.round_n).title)
	return "Соперник" if net_game == null else net_game.opp_name()

func _sync_cards(animate := true, spawn_from := Vector3.INF) -> void:
	var want := {}
	for e in _side_units(m.p):
		want["p:%d" % e.u.uid] = {"u": e.u, "pos": _pos_for(e.z, e.i, false), "side": "p"}
	var eb := _enemy_board()
	for i in eb.size():
		var u = eb[i]
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
		var tex := CardFaces.face(u.id, int(u.star), u.get("items", []), u.get("fed"), false)
		var c: Card3D = cards.get(k)
		if c == null:
			c = Card3D.new()
			table.add_child(c)
			c.setup("hero", u.id, tex, int(u.uid), w.side)
			c.set_rare(_rare_of(u))
			cards[k] = c
			if animate and spawn_from != Vector3.INF and w.side == "p":
				c.position = spawn_from
				c.arc_to(w.pos, 0.5, 1.6)
			else:
				c.position = w.pos
				if animate:
					c.scale = Vector3.ONE * 0.2
					c.create_tween().tween_property(c, "scale", Vector3.ONE * c.base_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					if c.rare == "boss":
						Sfx.play("roar")
		else:
			c.set_face(tex)
			if c != drag.get("card"):
				if animate:
					c.move_to(w.pos, 0.3)
				else:
					c.position = w.pos
		c.set_meta("u", u)
		c.home_pos = w.pos
		var st := Rules.stats(u)
		var hd: Dictionary = Data.HEROES[u.id]
		c.set_stats(int(st.atk), int(st.hp), Rules.rank_label(int(hd.r)) + Data.SUITS[hd.s].sym, Data.SUITS[hd.s].color.lightened(0.55), int(u.star), String(hd.n))

## Пробуждение легенд: золотой столб над картой, звук, надпись.
func _show_awakened(list: Array) -> void:
	for a in list:
		var c: Card3D = cards.get("p:%d" % int(a.uid))
		if c == null:
			continue
		fx.awaken(c.global_position)
		c.pop(1.2)
		c.float_text("Пробуждение %s" % "★".repeat(int(a.star)), Color("ffd66a"), true)
		Sfx.play("awaken")
		hud.toast("Легенда пробудилась: %s %s" % [String(a.name), "★".repeat(int(a.star))], "good")

func _rare_of(u: Dictionary) -> String:
	if Data.is_legend(String(u.id)):
		return "legend"
	if bool(u.get("boss", false)):
		return "boss"
	return ""

func _sync_all(animate := true, spawn_from := Vector3.INF) -> void:
	_sync_cards(animate, spawn_from)
	_refresh_hud()

func _refresh_hud() -> void:
	var p: Dictionary = m.p
	var foe_name: String = _enemy_name()
	var foe_hp: int = int(m.ai.hp) if net_game == null else net_game.opp_hp()
	if m.extras and m.is_monster_round() and net_game != null:
		foe_hp = 0
	hud.set_hp(int(p.hp), foe_hp, foe_name)
	hud.lbl_round.text = "Раунд %d" % m.round_n
	if m.extras:
		var left: int = Data.MONSTER_EVERY - m.round_n % Data.MONSTER_EVERY
		if m.round_n % Data.MONSTER_EVERY == 0:
			hud.lbl_round.text += " · Страж!"
			hud.lbl_round.get_parent().tooltip_text = "%s. Победа — награда на выбор, в том числе легенда." % Match.monster_info(m.round_n).title
		else:
			if left <= 2:
				hud.lbl_round.text += " · Страж через %d" % left
			hud.lbl_round.get_parent().tooltip_text = "Следующий Страж арены — раунд %d: %s." % [m.round_n + left, Match.monster_info(m.round_n + left).name]
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
		"reroll": {"on": shop_phase and (m.free_roll > 0 or int(p.gold) >= 2)},
		"xp": {"on": shop_phase and int(p.gold) >= 4 and int(p.level) < 8},
		"lock": {"on": shop_phase, "text": "Витрина сохранена" if m.locked else "Сохранить витрину"},
		"sell": {"on": shop_phase and sel_uid >= 0},
		"allin": {"on": shop_phase and (m.can_allin() or bool(p.allin)), "text": "Ва-банк!" if p.allin else "Ва-банк"},
		"fight": {"on": shop_phase},
	})
	hud.set_price("reroll", "0" if m.free_roll > 0 else "2")
	var chips := []
	if p.allin: chips.append("Ва-банк!")
	var bt := m.bounty_text()
	if bt != "": chips.append(bt)
	if int(p.streak) >= 2: chips.append("Побед подряд: %d" % p.streak)
	elif int(p.streak) <= -2: chips.append("Поражений подряд: %d" % -int(p.streak))
	hud.set_chips(chips)
	hud.set_hint(_step_hint())
	_update_slots()
	_update_hand_view(board, info.hand)

## Какие герои составляют покерную комбинацию (uid). Копии одного героя считаются одной картой.
func _hand_members(units: Array, hand_key: String) -> Array:
	var uniq := Rules.unique_units(units)
	var out: Array = []
	if hand_key == "high" or uniq.is_empty():
		return out
	if hand_key in ["straight", "flush", "sflush", "royal"]:
		for u in uniq:
			out.append(int(u.uid))
		return out
	var cnt := {}
	for u in uniq:
		var r := int(Data.HEROES[u.id].r)
		cnt[r] = int(cnt.get(r, 0)) + 1
	for u in uniq:
		var joker: bool = (u.get("items", []) as Array).has("joker")
		if int(cnt[int(Data.HEROES[u.id].r)]) >= 2 or joker:
			out.append(int(u.uid))
	return out

## Подсветка карт комбинации, таблички рук у разделительной полосы, подсказки «→ рука» в магазине.
func _update_hand_view(board: Array, my_hand: String) -> void:
	var mine := _hand_members(board, my_hand)
	var eunits: Array = _enemy_board().filter(func(u): return u != null)
	var ehand: String = Rules.team_info(eunits).hand if not eunits.is_empty() else "high"
	var theirs := _hand_members(eunits, ehand)
	for k in cards:
		var c: Card3D = cards[k]
		var on_board := _is_on_board(k)
		c.set_in_hand(on_board and ((c.side == "p" and mine.has(c.uid)) or (c.side == "e" and theirs.has(c.uid))))
	var who: String = "Страж арены" if _enemy_name().begins_with("Страж") else _enemy_name()
	var eb: String = Data.hand_text(ehand)
	var mb: String = Data.hand_text(my_hand)
	table.set_hands(who, Data.HANDS[ehand].n if not eunits.is_empty() else "—", "" if eb == "без бонуса" else eb,
		Data.HANDS[my_hand].n, "" if mb == "без бонуса" else mb)
	# магазин: какая рука получится, если купить и поставить этого героя
	var badges: Array = []
	var cap := Rules.cap_of(int(m.p.level))
	var cur := Data.HAND_ORDER.find(my_hand)
	for id in m.shop:
		var txt := ""
		if id != null and board.size() < cap and not board.any(func(u): return u.id == id):
			var test := board.duplicate()
			test.append({"uid": -1, "id": id, "star": 1, "items": [], "fed": null})
			var h: String = Rules.eval_units(test)
			if Data.HAND_ORDER.find(h) > cur:
				txt = "→ " + String(Data.HANDS[h].n)
		badges.append(txt)
	hud.set_shop_badges(badges)

func _step_hint() -> String:
	if in_battle:
		if targeting: return "Выберите цель для заклинания."
		return "Бой идёт сам. Можно разыграть до 2 заклинаний из руки магии."
	if not feed_state.is_empty():
		return "Жертвоприношение: выберите карту, которую скормить. Esc или правый клик — отмена."
	if hand_sel >= 0:
		return "Выберите героя, которому отдать усиление."
	var p: Dictionary = m.p
	if m.extras and m.is_monster_round() and m.phase == "shop":
		return "%s! Победите — выберете награду, в том числе легендарного героя. Поражение отнимет вдвое меньше ОЗ." % Match.monster_info(m.round_n).title
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
			m.toggle_lock()
			hud.toast("Витрина сохранена: в следующем раунде магазин не обновится" if m.locked else "Витрина обновится в следующем раунде", "good" if m.locked else "")
			_refresh_hud()
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
			fx.time_scale = speed / 2.0
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
			# по кругу: звук и музыка → без музыки → без звука
			if sound_on and Sfx.music_on:
				Sfx.set_music_enabled(false)
				hud.btn_sound.text = "Без музыки"
			elif sound_on:
				sound_on = false
				Sfx.enabled = false
				Sfx.set_music_enabled(false)
				hud.btn_sound.text = "Без звука"
			else:
				sound_on = true
				Sfx.enabled = true
				Sfx.set_music_enabled(true)
				hud.btn_sound.text = "Звук"
			_save_settings()
		"rules":
			_show_rules()
		"codex":
			_show_codex()
		"side":
			hud.toggle_side()
		"tutorial":
			hud.show_overlay(null)
			_start_tutorial()
		"settings":
			_show_settings()
		"set_speed":
			settings.speed = arg
			_save_settings(); _apply_settings(); _show_settings()
		"toggle_fs":
			settings.fullscreen = not settings.fullscreen
			_save_settings(); _apply_settings(); _show_settings()
		"toggle_big":
			settings.big_ui = not settings.big_ui
			_save_settings(); _apply_settings(); _show_settings()
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

var _hover_id := 0

func _on_hover(c: Card3D) -> void:
	_hover_id += 1
	hud.hide_zoom()
	if c == null or not c.has_meta("u") or not drag.is_empty():
		return
	var u: Dictionary = c.get_meta("u")
	var my := _hover_id
	get_tree().create_timer(0.45).timeout.connect(func():
		if my == _hover_id and drag.is_empty() and is_instance_valid(c) and table.hovered == c 				and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			hud.show_zoom_hero(u, table.screen_pos(c.global_position)))
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
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			# правая кнопка: перетаскивание вращает арену, короткий щелчок — жертвоприношение
			if not table.rotated:
				_right(mb.position)
	elif ev is InputEventMouseMotion and not drag.is_empty():
		var mm := ev as InputEventMouseMotion
		if (mm.position - drag.start).length() > 6:
			drag.moved = true
		if drag.moved:
			var p: Vector3 = table.pick(mm.position).table_point
			var c: Card3D = drag.card
			c.position = Vector3(p.x, 0.15, p.z)
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
	_hover_id += 1
	hud.hide_zoom()
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
	fx.time_scale = speed / 2.0
	hud.clear_log()
	var my_hand: String = Data.HANDS[b.team_hand(my_tag)].n
	var their_hand: String = Data.HANDS[b.team_hand(Battle.other(my_tag))].n
	hud.add_log("Раунд %d: %s против %s" % [m.round_n, my_hand, their_hand], "#f3cf73")
	_boss_slot = -1
	for u in (b.units() if b else []):
		if u.side != my_tag and Data.is_boss(String(u.id)):
			_boss_slot = int(u.slot)
			hud.show_boss_bar("Страж: %s" % Data.HEROES[u.id].n, int(u.hp), int(u.max_hp))
	if _boss_slot >= 0:
		var bc := _card_at_slot(_boss_slot)
		if bc and not skip_battle:
			bc.pop(1.15)
			fx.enrage(bc.global_position)
		Sfx.play("roar")
		hud.show_banner(_enemy_name(), Color("e8b86a")); await _wait(1.4)
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
	_boss_slot = -1
	hud.hide_boss_bar()
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

## Слот главаря Стража (у отряда Стража — линия 2), -1 — бой не со Стражем.
var _boss_slot := -1
var _ev_count := {}   # счётчик показанных событий боя (для автотестов)

func _boss_track(b, e: Dictionary) -> void:
	if _boss_slot < 0:
		return
	var u_ = e.get("tgt", e.get("u", -99))
	if int(u_) != _boss_slot:
		return
	# состояние боя уже на конец хода — берём ОЗ из самого события, макс. ОЗ — из снимка
	var bu = b.unit(_boss_slot)
	if bu and e.has("hp"):
		hud.set_boss_hp(int(e.hp), int(e.get("max_hp", bu.max_hp)))

func _animate(evs: Array, b, my_tag: String) -> void:
	var anim := not skip_battle
	for e in evs:
		_ev_count[String(e.t)] = int(_ev_count.get(String(e.t), 0)) + 1
		if String(e.t) in ["hit", "heal", "revive", "buff"]:
			_boss_track(b, e)
		var c := _card_at_slot(int(e.get("u", -99)))
		match String(e.t):
			"step":
				hud.set_step("Ход %d" % e.n)
			"spell":
				_last_spell = String(e.key)
				var mine: bool = e.side == my_tag
				hud.show_banner(Data.MAGIC[e.key].n, Color("f3cf73") if mine else Color("e88a7a"))
				hud.add_log("%s разыгрывает «%s»" % ["Вы" if mine else "Соперник", Data.MAGIC[e.key].n], "#9fd0ff" if mine else "#ffb0a0")
				Sfx.play("spell_" + String(e.key))
				if anim:
					var my_center := Vector3(0, 0, 3.2) if mine else Vector3(0, 0, -3.8)
					var tg: Array = []
					if int(e.tgt) >= 0:
						var tc := _card_at_slot(int(e.tgt))
						if tc: tg.append(tc.global_position)
					else:
						var foe_side: bool = String(e.key) in ["freeze", "meteor", "venom"]
						for u in b.units():
							if (u.side == e.side) != foe_side and int(u.hp) > 0:
								var uc := _card_at_slot(int(u.slot))
								if uc: tg.append(uc.global_position)
					await fx.spell(String(e.key), tg, my_center)
			"attack":
				var t := _card_at_slot(int(e.tgt))
				if c and t and anim:
					c.lunge(t.position)
					await _wait(0.16)
			"cast":
				if c and Data.is_legend(c.key):
					c.pop(1.2)
					c.float_text(String(e.name), Color("ffd66a"), true)
					hud.show_banner(String(e.name), Color("f3cf73"))
					Sfx.play("legend")
					if anim:
						var mine_c: bool = c.side == "p"
						var foes: Array = []
						var allies: Array = []
						for u in b.units():
							if int(u.hp) <= 0:
								continue
							var uc := _card_at_slot(int(u.slot))
							if uc == null:
								continue
							if (uc.side == "p") == mine_c:
								allies.append(uc.global_position)
							else:
								foes.append(uc.global_position)
						var tcard := _card_at_slot(int(e.get("tgt", -99)))
						await fx.legend_cast(c.key, c.global_position, foes, allies, tcard.global_position if tcard else Vector3.INF)
					else:
						await _wait(0.2)
				elif c:
					c.pop(1.15)
					c.float_text(String(e.name), Color("ffe6a8"))
					var el := Fx.elem_of_hero(c.key)
					Sfx.play("cast")
					if anim:
						fx.cast(c.global_position, el)
						var t := _card_at_slot(int(e.tgt))
						if t and t != c and String(e.ab) in Fx.RANGED_AB:
							Sfx.play("whoosh")
							await fx.projectile(c.global_position, t.global_position, el)
						else:
							await _wait(0.3)
			"hit":
				var t := _card_at_slot(int(e.tgt))
				if t:
					var src := _card_at_slot(int(e.src))
					var el: String = Fx.elem_of_hero(src.key) if src else String(Fx.SPELL_ELEM.get(_last_spell, ""))
					if anim:
						t.shake(0.06 if not e.crit else 0.12)
						fx.hit(t.global_position, el, bool(e.crit), String(e.kind))
					var snd: String = "crit" if e.crit else ("poison" if e.kind == "poison" else "hit_" + String({"S": "ice", "H": "fire", "D": "light", "C": "nature"}.get(el, "neutral")))
					Sfx.play(snd)
					var txt := "-%d" % int(e.dmg) if int(e.dmg) > 0 else ("щит" if int(e.absorbed) > 0 else "0")
					var col := Color("ffffff") if not e.crit else Color("ffcf5a")
					if e.kind == "poison": col = Color("a6e26a")
					t.float_text(txt + ("!" if e.crit else ""), col, e.crit)
					t.set_bars(int(e.hp), int(_max_hp(b, int(e.tgt))), int(e.mana), _mm(b, int(e.tgt)), int(e.shield))
					await _wait(0.12)
			"death":
				if c:
					c.die()
					Sfx.play("soul")
					if anim:
						fx.death(c.global_position, Fx.elem_of_hero(c.key))
					await _wait(0.25)
			"heal":
				if c and int(e.amount) > 0:
					c.float_text("+%d" % int(e.amount), Color("7fe0a0"))
					if anim and e.kind != "regen":
						fx.heal(c.global_position); Sfx.play("heal")
			"shield":
				if c:
					c.float_text("щит +%d" % int(e.amount), Color("e8f0ff"))
					if anim:
						fx.shield(c.global_position, Color("f2dea0") if e.kind == "spell" else Color(0, 0, 0, 0)); Sfx.play("shield")
			"stun":
				if c:
					c.float_text("заморожен" if e.kind == "spell" else "оглушён", Color("bfe3ff"))
					if anim:
						fx.stun(c.global_position, e.kind == "spell"); Sfx.play("freeze" if e.kind == "spell" else "stun")
			"poison":
				if c:
					c.float_text("яд", Color("a6e26a"))
					if anim:
						fx.poison(c.global_position); Sfx.play("poison")
			"buff":
				if c and String(e.get("stat", "atk")) == "hp":
					c.float_text("+%d ОЗ" % int(e.get("amount", 0)), Color("8fe0a6"))
					if anim: fx.buff(c.global_position, true)
				elif c:
					c.float_text("%+d%% АТК" % int(e.pct), Color("ffd39a") if int(e.pct) > 0 else Color("c9b0ff"))
					if anim:
						fx.buff(c.global_position, int(e.pct) > 0); Sfx.play("buff_up" if int(e.pct) > 0 else "buff_down")
			"mana":
				if c and String(e.get("kind", "")) == "ability":
					c.float_text("мана сгорела", Color("9fc4ff"))
			"revive":
				if c:
					c.revive(); c.show_bars(true)
					c.float_text("возродился из пепла!" if String(e.get("kind", "")) == "rebirth" else "восстал", Color("ffc070") if String(e.get("kind", "")) == "rebirth" else Color("ffe6a8"))
					if anim:
						fx.revive(c.global_position); Sfx.play("revive")
					await _wait(0.3)
			"summon":
				var key := ("p:%d" if e.side == my_tag else "e:%d") % int(e.uid)
				var lane := int(e.lane)
				var pos := Table3D.pos_board(lane) if e.side == my_tag else Table3D.pos_enemy(lane)
				var old := _card_at_slot(int(e.u))
				if old and bool(e.get("replaced", false)):
					for k in cards.keys():
						if cards[k] == old:
							cards.erase(k)
					old.queue_free()
				var su := {"uid": int(e.uid), "id": String(e.id), "star": int(e.star), "items": [], "fed": null}
				var nc := Card3D.new()
				table.add_child(nc)
				nc.setup("hero", su.id, CardFaces.face(su.id, su.star, [], null, false), su.uid, "p" if e.side == my_tag else "e")
				nc.position = pos
				nc.home_pos = pos
				nc.set_meta("u", su)
				var st := Rules.stats(su)
				var hd: Dictionary = Data.HEROES[su.id]
				nc.set_stats(int(st.atk), int(st.hp), Rules.rank_label(int(hd.r)) + Data.SUITS[hd.s].sym, Data.SUITS[hd.s].color.lightened(0.55), su.star, String(hd.n))
				nc.show_bars(true)
				nc.set_bars(int(e.hp), int(e.max_hp), int(e.mana), int(e.mm), 0)
				cards[key] = nc
				_slot_map[int(e.u)] = key
				nc.pop(1.2)
				nc.float_text("Росток!", Color("9fe08a"))
				if anim: fx.revive(pos)
				Sfx.play("heal")
				await _wait(0.3)
			"enrage":
				if c:
					c.set_enraged(true)
					c.pop(1.18)
					c.float_text("ЯРОСТЬ!", Color("ff9a6a"), true)
					hud.show_banner("%s: %s" % [Data.HEROES[c.key].n, String(e.name)], Color("ff9a6a"))
					hud.boss_enraged("%s — %s" % [Data.HEROES[c.key].n, String(e.name)])
					Sfx.play("roar")
					if anim:
						fx.enrage(c.global_position)
					await _wait(0.8)
			"cleanse":
				if c:
					c.float_text("очищен", Color("f2e6b0"))
					if anim: fx.heal(c.global_position)
			"end":
				var won: bool = e.outcome == my_tag
				if e.outcome != "draw":
					if won:
						fx.victory(Vector3(0, 0, 1.95))
					else:
						fx.defeat(Vector3(0, 0, -2.1))
					Sfx.play("victory_sting" if won else "defeat_sting")

func _max_hp(b, slot: int) -> int:
	var u = b.unit(slot)
	return int(u.max_hp) if u else 1

func _mm(b, slot: int) -> int:
	var u = b.unit(slot)
	return int(u.mm) if u else 100

func _after_battle(res: Dictionary) -> void:
	for k in cards:
		(cards[k] as Card3D).reset_pose()
	_sync_cards(true)
	_show_awakened(res.get("awakened", []))
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
		c.reset_pose()
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
	_sync_cards(true)
	_show_awakened(r.get("awakened", []))
	var rows: Array = r.get("standings", []).duplicate()
	rows.sort_custom(func(a, b): return int(a.hp) > int(b.hp))
	for p in rows:
		v.add_child(_ink("%s%s — %d ОЗ%s" % ["✝ " if not p.alive else "", p.name, int(p.hp), " · бот" if p.bot else ""], 16))
	if not bool(r.alive):
		v.add_child(_ink("Вы выбыли. Место: %d. Можно досмотреть игру или выйти в меню." % int(r.place), 18))
		v.add_child(_button("Выйти в меню", "net_leave", null, "GoldButton"))
	elif not m.pending_reward.is_empty():
		v.add_child(_ink("Выберите награду" if m.reward_source == "monster" else "Награда за серию побед — выберите одну", 24, "TitleLabel"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		for i in m.pending_reward.size():
			row.add_child(_reward_card(i, m.pending_reward[i]))
		v.add_child(row)
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
var settings := {"music_vol": 0.8, "sfx_vol": 0.9, "fullscreen": false, "speed": 2, "big_ui": false, "tutorial_done": false}
var tutorial: Node = null

func _save_settings() -> void:
	settings.sound = sound_on
	settings.music = Sfx.music_on
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))

func _apply_settings() -> void:
	if Sfx.has_method("set_volumes"):
		Sfx.set_volumes(float(settings.music_vol), float(settings.sfx_vol))
	var fs: bool = settings.fullscreen
	if DisplayServer.get_name() != "headless" and OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"]:
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and not OS.get_cmdline_user_args().has("--demo"):
			DisplayServer.window_set_mode(want)
	speed = int(settings.speed)
	get_tree().root.content_scale_factor = 1.22 if settings.big_ui else 1.0
	table._frame()

func _load_settings() -> void:
	if not FileAccess.file_exists("user://settings.json"):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	if j is Dictionary:
		for k in settings:
			if j.has(k):
				settings[k] = j[k]
		sound_on = bool(j.get("sound", true))
		Sfx.enabled = sound_on
		Sfx.music_on = bool(j.get("music", true)) and sound_on
		hud.btn_sound.text = "Без звука" if not sound_on else ("Звук" if Sfx.music_on else "Без музыки")

func _new_game(diff: String) -> void:
	Sfx.music("game")
	for k in cards:
		cards[k].queue_free()
	cards.clear()
	m = Match.new(-1, true)
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
	Sfx.music("game")
	var d := _has_save()
	for k in cards:
		cards[k].queue_free()
	cards.clear()
	m = Match.new(-1, true)
	if d.is_empty() or not m.load_state(d):
		m.new_game("normal")
	m.extras = true
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
	b.pressed.connect(func():
		Sfx.play("stone")
		_on_act(action, arg))
	return b

func _show_start() -> void:
	Sfx.music("menu")
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
	if not bool(settings.tutorial_done):
		v.add_child(_button("Обучение для новичков — 1 минута", "tutorial", null, "GoldButton"))
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
	var misc := HBoxContainer.new()
	misc.add_theme_constant_override("separation", 10)
	for spec in [["Как играть", "rules"], ["Легенды и Стражи", "codex"], ["Обучение", "tutorial"], ["Настройки", "settings"]]:
		var mb := _button(spec[0], spec[1])
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		misc.add_child(mb)
	v.add_child(misc)
	hud.show_overlay(v)

const RULES_TEXT := """Магазин. Каждый раунд приносит 5 золота и проценты с накоплений (1 за каждые 10, до 5). Купите героя кликом по карте внизу. Три одинаковые карты сливаются в ★★, три ★★ — в ★★★. «Новые карты» — обновить витрину за 2 золота. «Опыт +4» — поднять уровень (больше героев на поле). «Сохранить витрину» — магазин не обновится в следующем раунде. Наведите на любую кнопку — появится подсказка.

Поле — это ваша рука. До 5 героев на линиях. Пара, две пары, тройка, стрит, флеш, фулл-хаус, каре (только с Джокером) и стрит-флеш усиливают весь отряд. Комбинацию собирают только разные герои: копии одного считаются одной картой.

Стихии — союзы. 2 или 4 разных героя одной стихии: Лёд — криты, Огонь — отряд лечится каждый ход, Свет — щит на старте боя, Природа — больше ОЗ.

Магия. Усиления отдаются героям между боями (клик по карте в руке, затем по герою). Заклинания разыгрываются в бою, не больше 2 за бой.

Жертвоприношение. Правый клик по герою (на телефоне — долгое нажатие): скормите ему карту ★★ или ★★★ той же стихии — герой навсегда получит 15% её АТК и ОЗ. Не больше 2 карт на героя.

Камбэк. Ва-банк — когда вы отстаёте: победа отнимает у соперника вдвое больше, поражение — у вас в 1,5 раза больше. Раз в 3 раунда. Награда за голову: прервите серию из 3+ побед и получите золото и карту магии. За обычное поражение — не больше 18 ОЗ. После поражения первое обновление магазина бесплатно, а витрина чаще подбрасывает нужные карты (тому, кто идёт на серии побед, — не подбрасывает).

Баланс. ★★ сильнее ★ в 1,75 раза, ★★★ — в 3 раза; дорогие герои чуть сильнее своей цены. За серию из 3 и 5 побед — скромная награда: немного золота, карта магии или одна копия героя ★.

Бой идёт сам. Урон после поражения зависит от раунда и выживших врагов. У каждого 100 ОЗ: кто остался последним — забирает банк.

Стражи арены. Каждый 5-й раунд вместо соперника выходит Страж со свитой. Когда у главаря остаётся меньше половины ОЗ, он впадает в ярость: голем закрывает отряд каменной кожей, костяной дракон поднимает павших слуг, Владыка бездны распаляется и сразу бьёт. Победа — награда на выбор, поражение отнимает вдвое меньше ОЗ.

Легенды. Пять уникальных героев в золотых рамках — только в награду за Стража. На линии может стоять одна легенда. Каждая победа над Стражем, в которой легенда сражалась, пробуждает её: ★ → ★★ (×1,5) → ★★★ (×2). Все легенды и Стражи — в меню «Легенды и Стражи».

Иконки героев и магии: game-icons.net (CC BY 3.0). Шрифты: Philosopher, Rubik (OFL). Музыка написана для игры."""

func _start_tutorial() -> void:
	_new_game("easy")
	if tutorial and is_instance_valid(tutorial):
		tutorial.queue_free()
	tutorial = preload("res://scripts/game/tutorial.gd").new()
	add_child(tutorial)
	tutorial.setup(self)
	tutorial.finished.connect(func():
		settings.tutorial_done = true
		_save_settings()
		tutorial = null
		_refresh_hud())

func _slider(title: String, value: float, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := _ink(title, 18)
	l.custom_minimum_size.x = 170
	var s := HSlider.new()
	s.min_value = 0; s.max_value = 100; s.step = 1
	s.value = value * 100.0
	s.custom_minimum_size = Vector2(300, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := _ink("%d%%" % int(value * 100), 17)
	val.custom_minimum_size.x = 60
	s.value_changed.connect(func(x):
		val.text = "%d%%" % int(x)
		on_change.call(x / 100.0))
	s.drag_ended.connect(func(_c): Sfx.play("stone_soft"); _save_settings())
	h.add_child(l); h.add_child(s); h.add_child(val)
	return h

func _show_settings() -> void:
	var v := _vbox(14)
	v.add_child(_ink("Настройки", 34, "TitleLabel"))
	v.add_child(_slider("Музыка", float(settings.music_vol), func(x):
		settings.music_vol = x
		_apply_settings()))
	v.add_child(_slider("Звуки", float(settings.sfx_vol), func(x):
		settings.sfx_vol = x
		_apply_settings()))
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 10)
	var sl := _ink("Скорость боя", 18)
	sl.custom_minimum_size.x = 170
	sp.add_child(sl)
	for s in [1, 2, 4]:
		var b := _button("×%d" % s, "set_speed", s, "GoldButton" if int(settings.speed) == s else "")
		b.custom_minimum_size.x = 90
		sp.add_child(b)
	v.add_child(sp)
	if OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"]:
		v.add_child(_button("Полный экран: %s" % ("вкл." if settings.fullscreen else "выкл."), "toggle_fs", null, "BlueButton" if settings.fullscreen else ""))
	v.add_child(_button("Крупный интерфейс (телефон, планшет): %s" % ("вкл." if settings.big_ui else "выкл."), "toggle_big", null, "BlueButton" if settings.big_ui else ""))
	v.add_child(_button("Готово", "menu", null, "GoldButton"))
	hud.show_overlay(v)

## Справочник: все легенды (способности по ★) и Стражи арены (раунды, свита, ярость).
func _show_codex() -> void:
	var v := _vbox(10)
	v.add_child(_ink("Легенды и Стражи", 34, "TitleLabel"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(820, 540)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := _vbox(12)
	sc.add_child(list)
	list.add_child(_ink("ЛЕГЕНДЫ — награда за победу над Стражем. На линии — одна. Пробуждаются (+★) после каждой победы над Стражем, в которой сражались.", 16, "MutedLabel"))
	for id in Data.LEGENDS:
		var d: Dictionary = Data.HEROES[id]
		var rank: String = "Джокер в покерной руке" if d.has("wild") else "%s%s" % [Rules.rank_label(int(d.r)), Data.SUITS[d.s].sym]
		var body := "%s · %s · ОЗ %d · АТК %d\n%s: %s\n★★★: %s" % [rank, Data.SUITS[d.s].name, int(Rules.stats({"id": id, "star": 1}).hp), int(Rules.stats({"id": id, "star": 1}).atk), d.ab.n, Data.ab_desc(id, 1), Data.ab_desc(id, 3)]
		list.add_child(_codex_row(CardFaces.face(id, 1), String(d.n), body, Color("b8862a")))
	list.add_child(HSeparator.new())
	list.add_child(_ink("СТРАЖИ АРЕНЫ — каждый 5-й раунд. Сила растёт с каждым кругом, свита — от 2 до 4 слуг.", 16, "MutedLabel"))
	var rage := {"m_golem": "Каменная кожа: весь отряд получает щит (14% ОЗ голема).",
		"m_bonedragon": "Восставшие кости: павшие слуги встают с 40% ОЗ, а если никто не пал — отряд злеет (+25% АТК).",
		"m_abyss": "Пламя ярости: +40% АТК и полная мана — «Пламя бездны» сразу следующим ходом."}
	for ti in Data.MONSTER_THEMES.size():
		var th: Dictionary = Data.MONSTER_THEMES[ti]
		var bd: Dictionary = Data.HEROES[th.boss]
		var rounds: Array = []
		for k in 3:
			rounds.append(str((ti + 1 + k * Data.MONSTER_THEMES.size()) * Data.MONSTER_EVERY))
		var minions: Array = (th.minions as Array).map(func(x): return String(Data.HEROES[x].n))
		var body := "Раунды %s… · свита: %s\n%s: %s\nЯрость (меньше половины ОЗ) — %s" % [", ".join(rounds), ", ".join(minions), bd.ab.n, Data.ab_desc(th.boss, 1), rage.get(th.boss, "")]
		list.add_child(_codex_row(CardFaces.face(th.boss, 1), String(th.name), body, Color("7a2e22")))
	v.add_child(sc)
	v.add_child(_button("Назад", "menu" if not in_battle and m.round_n <= 1 and m.phase == "shop" and Rules.all_units(m.p).is_empty() else "close", null, "GoldButton"))
	hud.show_overlay(v)

func _codex_row(tex: Texture2D, title: String, body: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(112, 157)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var vb := _vbox(4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := _ink(title, 22, "TitleLabel")
	t.add_theme_color_override("font_color", col)
	t.custom_minimum_size.x = 600
	var b := _ink(body, 15)
	b.custom_minimum_size.x = 600
	vb.add_child(t); vb.add_child(b)
	h.add_child(tr); h.add_child(vb)
	return h

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
	if bool(res.get("monster", false)):
		var mt := _ink(String(res.get("monster_name", "Страж арены")), 18, "HeaderLabel")
		v.add_child(mt)
	var title: String = {"win": "Победа в раунде!", "lose": "Поражение", "draw": "Ничья"}[o]
	var t := _ink(title, 40, "TitleLabel")
	t.add_theme_color_override("font_color", Color("2f7a3a") if o == "win" else (Color("9a2b22") if o == "lose" else Color("6a5338")))
	v.add_child(t)
	v.add_child(_ink("Вы потеряли %d ОЗ · соперник потерял %d ОЗ" % [res.dmg_p, res.dmg_e], 20))
	for n in res.get("notes", []):
		v.add_child(_ink(String(n), 17))
	if bool(res.get("monster", false)) and String(res.get("ai_monster", "")) != "":
		v.add_child(_ink("Соперник против своего Стража: %s." % {"win": "победа", "lose": "поражение", "draw": "ничья"}.get(String(res.ai_monster), "—"), 16, "MutedLabel"))
	if not m.pending_reward.is_empty():
		v.add_child(_ink("Выберите награду" if m.reward_source == "monster" else "Награда за серию побед — выберите одну", 24, "TitleLabel"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		for i in m.pending_reward.size():
			row.add_child(_reward_card(i, m.pending_reward[i]))
		v.add_child(row)
	else:
		v.add_child(_button("Следующий раунд", "next", null, "GoldButton"))
	hud.show_overlay(v, false)

func _reward_card(i: int, o: Dictionary) -> Control:
	var b := Button.new()
	b.theme_type_variation = "GoldButton" if o.type == "legend" else ""
	b.custom_minimum_size = Vector2(230, 330)
	b.focus_mode = Control.FOCUS_NONE
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12; vb.offset_right = -12; vb.offset_top = 10; vb.offset_bottom = -10
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var tex: Texture2D = null
	match String(o.type):
		"legend", "hero": tex = CardFaces.face(String(o.id), int(o.get("star", 1)))
		"magic": tex = CardFaces.magic_face(String(o["keys"][0]), m.round_n)
		_: tex = UiTheme.icon("coin")
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(0, 130)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Label.new()
	t.text = String(o.title)
	t.theme_type_variation = "TitleLabel"
	t.add_theme_font_size_override("font_size", 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := Label.new()
	d.text = String(o.desc)
	d.add_theme_font_size_override("font_size", 13)
	d.max_lines_visible = 7
	d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = String(o.desc)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tr); vb.add_child(t); vb.add_child(d)
	b.add_child(vb)
	b.pressed.connect(func():
		Sfx.play("stone")
		var r := m.choose_reward(i)
		if r.get("ok", false):
			hud.toast("Награда: %s" % String(o.title), "good")
			_sync_all(true)
		hud.show_overlay(null)
		_next_round())
	return b

func _show_game_over(res: Dictionary) -> void:
	var v := _vbox(12)
	var o: String = res.over
	v.add_child(_ink({"win": "Вы забрали банк!", "lose": "Игра окончена", "draw": "Ничья"}[o], 46, "TitleLabel"))
	v.add_child(_ink("Раунд %d. Ваш уровень %d, рука «%s»." % [m.round_n, m.p.level, Data.HANDS[Rules.team_info(Rules.board_units(m.p)).hand].n], 19))
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	v.add_child(_button("Новая игра", "menu", null, "GoldButton"))
	hud.show_overlay(v)
