class_name Match
extends RefCounted
## Одиночная партия против ИИ без интерфейса: newGame/beginRound/buy/sell/…/fight/resolve из web/index.html v1.4.0.
## Игрок — сторона "home" в бою (ходит первой в нечётные ходы, как в соло-JS), соперник — "away".
##
## Отличие от JS только в источнике случайности: вместо Math.random — один Rng партии (можно задать seed),
## а криты в бою считаются от зерна боя (как в сетевом JS). Сохраняется состояние Rng — после загрузки игра продолжается тем же потоком.
##
## Действия возвращают Dictionary {ok:bool, reason?:String, ...} — интерфейс показывает reason тостом.
##
## ---------------- Дополнения (Match.new(seed, true)) ----------------
## Без extras всё работает ровно как раньше (паритет с JS). С extras:
## • Страж арены: каждый 5-й раунд (is_monster_round()) игрок бьётся с отрядом монстров (monster_info()),
##   а соперник «за кадром» — со своим таким же отрядом (бой досчитывается в start_battle()).
##   Ва-банк в этот раунд недоступен, серии не меняются, урона между игроками нет.
##   Поражение (и ничья) — половина обычного урона раунда (мин. 1). Победа — выбор награды.
## • Награды: pending_reward — 3 оффера после победы над Стражем, а также после победы, которая делает серию ровно 3 или 5
##   (за серию — скромные: немного золота, магия или одна копия героя ★, без ★★ и легенд).
##   Оффер: {type:"legend"|"hero"|"magic"|"gold", id?, star?, keys?, amount?, title, desc}.
##   choose_reward(i) применяет оффер; пока награда не выбрана, next_round() возвращает false.
##   Соперник (и auto_player) выбирают сами (Ai.choose_reward).
## • Легенды: на поле не больше одной (move() отказывает), в магазине не выпадают.

const D = preload("res://scripts/core/data.gd")

var diff: String = "normal"
var round_n: int = 1
var phase: String = "shop"          ## "shop" | "battle" | "result" | "over"
var p: Dictionary = {}               ## игрок (Side)
var ai: Dictionary = {}              ## соперник (Side)
var shop: Array = []                 ## 5 id героев или null (куплено)
var magic_shop: Array = []           ## 2 ключа магии или null
var locked: bool = false
var free_roll: int = 0               ## 1 — первое обновление бесплатно (после поражения)
var income: Dictionary = {}          ## последний доход игрока {interest, sb, gold}
var level_up: bool = false           ## в begin_round игрок поднял уровень
var rng: Rng
var battle: Battle = null
var last_result: Dictionary = {}
var over_result: String = ""         ## "" | "win" | "lose" | "draw"
## Режим автоигрока (для симуляций): перед боем за игрока ходит тот же ИИ (без бонуса сложности),
## он же сам решает ва-банк и сам разыгрывает заклинания в бою.
var auto_player: bool = false
## --- дополнения ---
var extras: bool = false
var pending_reward: Array = []       ## офферы награды игрока (пусто — нет)
var reward_source: String = ""       ## "monster" | "streak" — за что награда
var monster: Dictionary = {}         ## Страж текущего раунда: {name, title, theme, tier, board}
var ai_monster_result: Dictionary = {}   ## result() боя соперника со своим Стражем
var _ai_monster_spent: Array = []
var reward_log: Array = []           ## [{side:"p"|"ai", round, source, type, id}] — что выбрано (статистика/UI)

func _init(seed_value: int = -1, extras_on: bool = false) -> void:
	extras = extras_on
	if seed_value < 0:
		seed_value = (Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system() * 1000.0)) & 0x7FFFFFFF
	rng = Rng.new(seed_value)

# ---------- ход партии ----------

func new_game(difficulty: String = "normal") -> void:
	Rules.next_uid_value = 1
	diff = difficulty
	round_n = 1
	p = Rules.new_side("Вы")
	ai = Rules.new_side("Соперник")
	locked = false
	battle = null
	last_result = {}
	over_result = ""
	pending_reward = []
	reward_source = ""
	monster = {}
	ai_monster_result = {}
	reward_log = []
	begin_round(true)

func begin_round(first: bool = false) -> void:
	level_up = false
	for pair: Array in [[p, false], [ai, true]]:
		var side: Dictionary = pair[0]
		var is_ai: bool = pair[1]
		if first:
			side["gold"] = 6
			continue
		var inc: Dictionary = Rules.income(side, int(D.AIBONUS[diff]) if is_ai else 0)
		var lv: int = side["level"]
		side["gold"] = int(side["gold"]) + int(inc["gold"])
		Rules.add_xp(side, 2)
		if not is_ai:
			income = inc
			if int(side["level"]) > lv:
				level_up = true
	free_roll = 1 if (not first and int(p["streak"]) < 0) else 0
	if first or not locked:
		shop = Rules.roll_shop(int(p["level"]), p, rng)
		magic_shop = [Rules.roll_magic(rng), Rules.roll_magic(rng)]
	locked = false
	phase = "shop"
	battle = null
	p["allin"] = false
	ai["allin"] = false

func next_round() -> bool:
	if phase != "result" or not pending_reward.is_empty():
		return false
	round_n += 1
	begin_round(false)
	return true

# ---------- магазин ----------

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func buy(i: int) -> Dictionary:
	if phase != "shop" or i < 0 or i >= shop.size() or shop[i] == null:
		return _fail("")
	var id: String = shop[i]
	var cost: int = D.HEROES[id]["c"]
	if int(p["gold"]) < cost:
		return _fail("Не хватает золота")
	var u: Dictionary = Rules.new_unit(id)
	var res: Dictionary = Rules.gain_unit(p, u)
	if not res["ok"]:
		return _fail("Скамья заполнена. Продайте карту или выставьте её на поле.")
	p["gold"] = int(p["gold"]) - cost
	shop[i] = null
	return {"ok": true, "unit": u, "merged": res["merged"]}

func buy_magic(i: int) -> Dictionary:
	if phase != "shop" or i < 0 or i >= magic_shop.size() or magic_shop[i] == null:
		return _fail("")
	var k: String = magic_shop[i]
	var c: int = D.MAGIC[k]["c"]
	if int(p["gold"]) < c:
		return _fail("Не хватает золота")
	if (p["hand"] as Array).size() >= D.HAND_MAX:
		return _fail("В руке магии помещается 5 карт")
	p["gold"] = int(p["gold"]) - c
	(p["hand"] as Array).append(k)
	magic_shop[i] = null
	return {"ok": true, "key": k}

func can_reroll() -> bool:
	return phase == "shop" and (free_roll > 0 or int(p["gold"]) >= D.REROLL_COST)

func reroll() -> Dictionary:
	if not can_reroll():
		return _fail("Не хватает золота")
	if free_roll > 0:
		free_roll = 0
	else:
		p["gold"] = int(p["gold"]) - D.REROLL_COST
	shop = Rules.roll_shop(int(p["level"]), p, rng)
	magic_shop = [Rules.roll_magic(rng), Rules.roll_magic(rng)]
	locked = false
	return {"ok": true}

func buy_xp() -> Dictionary:
	if phase != "shop" or int(p["gold"]) < D.XP_COST or int(p["level"]) >= 8:
		return _fail("")
	var l: int = p["level"]
	p["gold"] = int(p["gold"]) - D.XP_COST
	Rules.add_xp(p, 4)
	return {"ok": true, "level_up": int(p["level"]) > l}

func toggle_lock() -> Dictionary:
	if phase != "shop":
		return _fail("")
	locked = not locked
	return {"ok": true, "locked": locked}

func get_at(zone: String, i: int) -> Variant:
	if zone != "board" and zone != "bench":
		return null
	var arr: Array = p[zone]
	return arr[i] if i >= 0 and i < arr.size() else null

## Переставить/поменять местами (moveUnit). zone: "board" | "bench".
func move(from_zone: String, from_i: int, to_zone: String, to_i: int) -> Dictionary:
	if phase != "shop":
		return _fail("")
	var a: Variant = get_at(from_zone, from_i)
	if to_zone != "board" and to_zone != "bench" or to_i < 0 or to_i >= (p[to_zone] as Array).size():
		return _fail("")
	var b: Variant = get_at(to_zone, to_i)
	if a == null or (from_zone == to_zone and from_i == to_i):
		return _fail("")
	if to_zone == "board" and from_zone == "bench" and b == null and Rules.board_count(p) >= Rules.cap_of(int(p["level"])):
		return _fail("На поле сейчас помещается %d карт. Поднимите уровень, чтобы ставить больше." % Rules.cap_of(int(p["level"])))
	if from_zone != to_zone:
		var incoming: Variant = a if to_zone == "board" else b
		var outgoing: Variant = b if to_zone == "board" else a
		if Rules.is_legend(incoming) and not Rules.is_legend(outgoing) and Rules.legend_count(Rules.board_units(p)) >= Rules.LEGEND_BOARD_MAX:
			return _fail("На поле может стоять только одна легенда.")
	p[from_zone][from_i] = b
	p[to_zone][to_i] = a
	return {"ok": true}

## «Поставить на место»: то же, что move.
func place(from_zone: String, from_i: int, to_zone: String, to_i: int) -> Dictionary:
	return move(from_zone, from_i, to_zone, to_i)

func sell(zone: String, i: int) -> Dictionary:
	if phase != "shop":
		return _fail("")
	var u: Variant = get_at(zone, i)
	if u == null:
		return _fail("")
	var v: int = Rules.sell_value(u)
	p["gold"] = int(p["gold"]) + v
	p[zone][i] = null
	for k: String in Rules.items_of(u):
		Rules.return_item(p, k)
	return {"ok": true, "gold": v, "unit": u}

## Надеть усиление из руки (hand_i) на героя (applyItem).
func use_item(hand_i: int, zone: String, i: int) -> Dictionary:
	if phase != "shop":
		return _fail("")
	var hand: Array = p["hand"]
	var u: Variant = get_at(zone, i)
	if u == null or hand_i < 0 or hand_i >= hand.size():
		return _fail("")
	var k: String = hand[hand_i]
	if D.MAGIC[k]["k"] != "item":
		return _fail("Заклинание разыгрывается во время боя")
	if not u.get("items") is Array:
		u["items"] = []
	if (u["items"] as Array).size() >= 2:
		return _fail("У героя уже 2 усиления")
	(u["items"] as Array).append(k)
	hand.remove_at(hand_i)
	return {"ok": true, "unit": u, "key": k}

## Кого можно скормить герою recv_uid (uid карт ★★+ той же стихии); пусто — нельзя.
func feed_targets(recv_uid: int) -> Array:
	var recv: Variant = Rules.unit_by_uid(p, recv_uid)
	if recv == null or int(Rules.fed_of(recv).get("n", 0)) >= D.FEED_MAX:
		return []
	var out: Array = []
	for u: Dictionary in Rules.feed_targets(p, recv):
		out.append(u["uid"])
	return out

## Почему нельзя кормить (текст для тоста) или "".
func feed_reason(recv_uid: int) -> String:
	var recv: Variant = Rules.unit_by_uid(p, recv_uid)
	if recv == null:
		return ""
	var d: Dictionary = D.HEROES[recv["id"]]
	if int(Rules.fed_of(recv).get("n", 0)) >= D.FEED_MAX:
		return "%s сыт: уже съел %d карты" % [d["n"], D.FEED_MAX]
	if Rules.feed_targets(p, recv).is_empty():
		return "Нечем накормить «%s»: нужна другая карта ★★ или ★★★ стихии %s" % [d["n"], D.SUITS[d["s"]]["name"]]
	return ""

func feed(recv_uid: int, food_uid: int) -> Dictionary:
	if phase != "shop":
		return _fail("")
	var res: Dictionary = Rules.do_feed(p, recv_uid, food_uid)
	if not res["ok"]:
		return _fail(feed_reason(recv_uid))
	return res

# ---------- ва-банк ----------

func top_rival_hp() -> int:
	return int(ai["hp"])

func can_allin() -> bool:
	return phase == "shop" and not is_monster_round() and int(p["allin_cd"]) <= round_n and int(p["hp"]) < top_rival_hp()

func allin_reason() -> String:
	if is_monster_round():
		return "Против Стража арены ва-банк не играют."
	if int(p["allin_cd"]) > round_n:
		return "Ва-банк снова будет доступен с раунда %d." % int(p["allin_cd"])
	return "Ва-банк доступен, только когда у вас меньше ОЗ, чем у лидера."

func toggle_allin() -> Dictionary:
	if phase != "shop":
		return _fail("")
	if p["allin"]:
		p["allin"] = false
		return {"ok": true, "allin": false}
	if can_allin():
		p["allin"] = true
		return {"ok": true, "allin": true}
	return _fail(allin_reason())

## Награда за голову: строка для HUD или "".
func bounty_text() -> String:
	if int(ai["streak"]) >= 3:
		return "Награда за голову соперника: %d золота" % int(ai["streak"])
	if int(p["streak"]) >= 3:
		return "За вашу голову награда: %d" % int(p["streak"])
	return ""

# ---------- бой ----------

## fight(): ход ИИ, решение ИИ о ва-банке, создание боя. Дальше: battle.step() до battle.over(), потом finish_battle().
func start_battle() -> Battle:
	if phase != "shop":
		return battle
	if is_monster_round():
		return _start_monster_battle()
	phase = "battle"
	if auto_player:
		Ai.take_turn(p, round_n, "normal", rng)
	Ai.take_turn(ai, round_n, diff, rng)
	if Ai.wants_allin(ai, int(p["hp"]), round_n, rng):
		ai["allin"] = true
		ai["allin_cd"] = round_n + 3
	if auto_player and not p["allin"] and Ai.wants_allin(p, int(ai["hp"]), round_n, rng):
		p["allin"] = true
	var sd: int = rng.next_seed()
	var p_spells: Array = (p["hand"] as Array).filter(func(k: String) -> bool: return D.MAGIC[k]["k"] == "spell") if auto_player else []
	battle = Battle.new(p["board"], ai["board"],
		{"name": p["name"], "ai": auto_player, "hand": p_spells, "allin": p["allin"]},
		{"name": ai["name"], "ai": true, "hand": (ai["hand"] as Array).duplicate(), "allin": ai["allin"]},
		sd, round_n)
	return battle

## Разыграть заклинание из руки игрока в бою (playSpell): сработает в начале следующего хода. target_uid — uid цели.
func play_spell(hand_i: int, target_uid: int = -1) -> Dictionary:
	if phase != "battle" or battle == null or battle.over():
		return _fail("")
	var hand: Array = p["hand"]
	if hand_i < 0 or hand_i >= hand.size():
		return _fail("")
	var k: String = hand[hand_i]
	if D.MAGIC[k]["k"] != "spell":
		return _fail("Усиления выдаются героям между боями")
	if battle.spells_left("home") <= 0:
		return _fail("За один бой можно разыграть 2 заклинания")
	if D.MAGIC[k]["t"] != null and target_uid < 0:
		return _fail("Выберите цель")
	if not battle.queue_spell("home", k, target_uid):
		return _fail("")
	hand.remove_at(hand_i)
	return {"ok": true, "key": k}

func _remove_spent(side: Dictionary, tag: String) -> void:
	if battle == null:
		return
	for k: String in battle.spent_spells(tag):
		var hand: Array = side["hand"]
		var i: int = hand.find(k)
		if i >= 0:
			hand.remove_at(i)

## resolve(): урон, ва-банк, награда за голову, серии, конец игры.
## result — battle.result() (если пусто — берётся из текущего боя; незаконченный бой досчитывается).
## Возвращает {outcome:"win"|"lose"|"draw", dmg_p, dmg_e, over:""|"win"|"lose"|"draw", notes:[String], bounty_card:String}
func finish_battle(result: Dictionary = {}) -> Dictionary:
	if phase != "battle":
		return last_result
	if result.is_empty():
		if battle != null and not battle.over():
			battle.run_to_end()
		result = battle.result() if battle != null else {"outcome": "draw", "survivors_home": [], "survivors_away": []}
	if is_monster_round():
		return _finish_monster_battle(result)
	_remove_spent(ai, "away")
	if auto_player:
		_remove_spent(p, "home")
	var base: int = Rules.base_damage(round_n)
	var my_allin: bool = p["allin"]
	var opp_allin: bool = ai["allin"]
	var opp_streak: int = ai["streak"]
	var my_streak: int = p["streak"]
	var outcome: String = "draw"
	var dmg_p: int = 0
	var dmg_e: int = 0
	var notes: Array = []
	match str(result.get("outcome", "draw")):
		"home":
			outcome = "win"
			dmg_e = Rules.round_damage(base, Rules.survivor_score(result.get("survivors_home", [])))
			if my_allin: dmg_e *= 2
			if opp_allin: dmg_e = D.r(float(dmg_e) * 1.5)
		"away":
			outcome = "lose"
			dmg_p = Rules.round_damage(base, Rules.survivor_score(result.get("survivors_away", [])))
			if opp_allin: dmg_p *= 2
			if my_allin: dmg_p = D.r(float(dmg_p) * 1.5)
		_:
			dmg_p = Rules.round_damage(base, 0)
			dmg_e = dmg_p
	if my_allin:
		notes.append("Ва-банк сыграл: соперник теряет вдвое больше." if outcome == "win" else ("Ва-банк не сыграл: вы теряете в 1,5 раза больше." if outcome == "lose" else "Ва-банк: ничья, без последствий."))
	if opp_allin:
		notes.append("Соперник шёл ва-банк: %s." % ("он теряет в 1,5 раза больше" if outcome == "win" else ("вы теряете вдвое больше" if outcome == "lose" else "ничья")))
	if my_allin:
		p["allin_cd"] = round_n + 3
	var card: String = ""
	if outcome == "win" and opp_streak >= 3:
		p["gold"] = int(p["gold"]) + opp_streak
		if (p["hand"] as Array).size() < D.HAND_MAX:
			card = Rules.roll_magic(rng)
			(p["hand"] as Array).append(card)
		notes.append("Награда за голову: +%d золота%s." % [opp_streak, (" и карту «%s»" % D.MAGIC[card]["n"]) if card != "" else ""])
	if outcome == "lose" and my_streak >= 3:
		ai["gold"] = int(ai["gold"]) + my_streak
	p["hp"] = maxi(0, int(p["hp"]) - dmg_p)
	ai["hp"] = maxi(0, int(ai["hp"]) - dmg_e)
	if outcome == "win":
		Rules.update_streak(p, true)
		Rules.update_streak(ai, false)
	elif outcome == "lose":
		Rules.update_streak(ai, true)
		Rules.update_streak(p, false)
	else:
		p["streak"] = 0
		ai["streak"] = 0
	var over: String = ""
	if int(p["hp"]) <= 0 or int(ai["hp"]) <= 0:
		over = "win" if int(p["hp"]) > int(ai["hp"]) else ("lose" if int(p["hp"]) < int(ai["hp"]) else "draw")
	over_result = over
	phase = "over" if over != "" else "result"
	last_result = {"outcome": outcome, "dmg_p": dmg_p, "dmg_e": dmg_e, "over": over, "notes": notes, "bounty_card": card, "round": round_n}
	if extras:
		# награда за серию ровно 3 или 5 побед (у проигравшего серия ≤ 0, так что награда только у победителя)
		last_result["monster"] = false
		last_result["ai_reward"] = {}
		if over == "":
			if outcome == "win" and (int(p["streak"]) == 3 or int(p["streak"]) == 5):
				notes.append("Серия из %d побед: выберите награду." % int(p["streak"]))
				_offer_player(_gen_offers(p, false, int(p["streak"])), "streak")
			elif outcome == "lose" and (int(ai["streak"]) == 3 or int(ai["streak"]) == 5):
				last_result["ai_reward"] = _ai_take_reward(_gen_offers(ai, false, int(ai["streak"])), "streak")
		last_result["reward"] = pending_reward.size() > 0
	return last_result

# ---------- Страж арены (дополнения) ----------

func is_monster_round(r: int = -1) -> bool:
	var rn: int = round_n if r < 0 else r
	return extras and rn > 0 and rn % D.MONSTER_EVERY == 0

## Отряд Стража для раунда r: {name, title, theme, tier, board:[5 Unit|null]}.
## Детерминирован (без случайности): тема по кругу, размер 3/4/5, сила растёт с тиром (тир = раунд / 5).
## uid монстров фиксированные (90001 + линия) — счётчик uid партии не трогается.
static func monster_info(r: int) -> Dictionary:
	var tier: int = maxi(1, floori(float(r) / float(D.MONSTER_EVERY)))
	var th: Dictionary = D.MONSTER_THEMES[(tier - 1) % D.MONSTER_THEMES.size()]
	var n: int = mini(5, 2 + tier)                      # 3, 4, 5, 5 …
	var mult: float = monster_mult(tier)
	var star: int = 3 if mult >= Rules.star_mult(th["boss"], 3) else (2 if mult >= Rules.star_mult(th["boss"], 2) else 1)   # рамка ★ по силе, остаток — в fed (n=0)
	var board: Array = []
	board.resize(D.BOARD_SIZE)
	var ids: Array = [th["boss"]]
	ids.append_array((th["minions"] as Array).slice(0, n - 1))
	var lanes: Array = [2, 1, 3, 0, 4]
	for i in ids.size():
		var id: String = ids[i]
		var d: Dictionary = D.HEROES[id]
		var fed: Variant = null
		var extra_hp: int = D.r(float(d["hp"]) * (mult - Rules.star_mult(id, star)))
		var extra_atk: int = D.r(float(d["atk"]) * (mult - Rules.star_mult(id, star)))
		if extra_hp > 0 or extra_atk > 0:
			fed = {"atk": extra_atk, "hp": extra_hp, "n": 0}
		board[lanes[i]] = {"uid": 90001 + int(lanes[i]), "id": id, "star": star, "items": [], "fed": fed}
		if i == 0:
			board[lanes[i]]["boss"] = true
	return {"name": th["name"], "title": "Страж арены: %s" % th["name"], "theme": th["key"], "tier": tier, "board": board}

## Множитель статов монстров по тиру (Data.MONSTER_MULT, дальше +MONSTER_MULT_STEP за тир).
static func monster_mult(tier: int) -> float:
	var last: int = D.MONSTER_MULT.size() - 1
	var k: float = 1.0 if Rules.classic else Rules.MONSTER_SCALE
	if tier <= last:
		return float(D.MONSTER_MULT[maxi(1, tier)]) * k
	return (float(D.MONSTER_MULT[last]) + D.MONSTER_MULT_STEP * float(tier - last)) * k

func _start_monster_battle() -> Battle:
	phase = "battle"
	if auto_player:
		Ai.take_turn(p, round_n, "normal", rng)
	Ai.take_turn(ai, round_n, diff, rng)
	p["allin"] = false
	ai["allin"] = false
	monster = monster_info(round_n)
	var sd: int = rng.next_seed()
	var sd_ai: int = rng.next_seed()
	# соперник бьётся со своим Стражем сразу (игрок этот бой не видит)
	var ab: Battle = Battle.new(ai["board"], (monster["board"] as Array).duplicate(true),
		{"name": ai["name"], "ai": true, "hand": (ai["hand"] as Array).duplicate(), "allin": false},
		{"name": monster["title"], "ai": false, "hand": [], "monster": true}, sd_ai, round_n)
	ab.run_to_end()
	ai_monster_result = ab.result()
	_ai_monster_spent = ab.spent_spells("home").duplicate()
	var p_spells: Array = (p["hand"] as Array).filter(func(k: String) -> bool: return D.MAGIC[k]["k"] == "spell") if auto_player else []
	battle = Battle.new(p["board"], (monster["board"] as Array).duplicate(true),
		{"name": p["name"], "ai": auto_player, "hand": p_spells, "allin": false},
		{"name": monster["title"], "ai": false, "hand": [], "monster": true}, sd, round_n)
	return battle

## Половина обычного урона раунда (мин. 1). result — с точки зрения стороны (home), Страж — away.
static func monster_damage(round_number: int, result: Dictionary) -> int:
	var base: int = Rules.base_damage(round_number)
	var full: int
	if str(result.get("outcome", "draw")) == "away":
		full = Rules.round_damage(base, Rules.survivor_score(result.get("survivors_away", [])))
	else:
		full = Rules.round_damage(base, 0)
	return maxi(1, D.r(float(full) / 2.0))

func _finish_monster_battle(result: Dictionary) -> Dictionary:
	if auto_player:
		_remove_spent(p, "home")
	for k: String in _ai_monster_spent:
		var i: int = (ai["hand"] as Array).find(k)
		if i >= 0:
			(ai["hand"] as Array).remove_at(i)
	_ai_monster_spent = []
	var notes: Array = []
	var res_p: String = str(result.get("outcome", "draw"))
	var res_ai: String = str(ai_monster_result.get("outcome", "draw"))
	var outcome: String = "win" if res_p == "home" else ("lose" if res_p == "away" else "draw")
	var ai_out: String = "win" if res_ai == "home" else ("lose" if res_ai == "away" else "draw")
	var dmg_p: int = 0 if outcome == "win" else monster_damage(round_n, result)
	var dmg_e: int = 0 if ai_out == "win" else monster_damage(round_n, ai_monster_result)
	p["hp"] = maxi(0, int(p["hp"]) - dmg_p)
	ai["hp"] = maxi(0, int(ai["hp"]) - dmg_e)
	var awakened: Array = []
	if outcome == "win":
		notes.append("%s повержен! Выберите награду." % monster["name"])
		awakened = awaken_legends(p)
		for a: Dictionary in awakened:
			notes.append("Легенда пробудилась: %s %s" % [a["name"], "★".repeat(int(a["star"]))])
	else:
		notes.append("%s устоял: вы теряете %d ОЗ (половину урона раунда)." % [monster["name"], dmg_p])
	if ai_out == "win":
		awaken_legends(ai)
	notes.append("Соперник тоже одолел своего Стража." if ai_out == "win" else ("Соперник не справился со Стражем: −%d ОЗ." % dmg_e))
	var over: String = ""
	if int(p["hp"]) <= 0 or int(ai["hp"]) <= 0:
		over = "win" if int(p["hp"]) > int(ai["hp"]) else ("lose" if int(p["hp"]) < int(ai["hp"]) else "draw")
	over_result = over
	phase = "over" if over != "" else "result"
	var ai_reward: Dictionary = {}
	if over == "":
		if ai_out == "win":
			ai_reward = _ai_take_reward(_gen_offers(ai, true), "monster")
		if outcome == "win":
			_offer_player(_gen_offers(p, true), "monster")
	last_result = {"outcome": outcome, "dmg_p": dmg_p, "dmg_e": dmg_e, "over": over, "notes": notes, "bounty_card": "", "round": round_n,
		"monster": true, "monster_name": monster["name"], "ai_monster": ai_out, "ai_reward": ai_reward, "reward": pending_reward.size() > 0,
		"awakened": awakened}
	return last_result

## Пробуждение легенд: каждая легенда, что стояла на линии в победном бою со Стражем, получает +1 ★ (до ★★★).
## Легенды не сливаются (копия у стороны одна), так они растут вместе с партией. [{uid, id, name, star}]
static func awaken_legends(side: Dictionary) -> Array:
	var out: Array = []
	for u: Variant in side["board"]:
		if u != null and Rules.is_legend(u) and int(u["star"]) < 3:
			u["star"] = int(u["star"]) + 1
			out.append({"uid": int(u["uid"]), "id": str(u["id"]), "name": str(D.HEROES[u["id"]]["n"]), "star": int(u["star"])})
	return out

# ---------- награды (дополнения) ----------

## 3 оффера. from_monster — первым идёт легенда (которой у стороны ещё нет), затем 2 из {магия, золото, герой ★★};
## иначе (награда за серию streak = 3 или 5) все три в случайном порядке, но скромнее:
##   серия 3 — 3 золота / 1 карта магии / герой ★ за 2–3 золота;
##   серия 5 — 5 золота / 2 карты магии / герой ★ за 3–4 золота.
func _gen_offers(side: Dictionary, from_monster: bool, streak: int = 3) -> Array:
	var kinds: Array = ["magic", "gold", "hero"]
	for i in range(kinds.size() - 1, 0, -1):   # перемешать (Фишер — Йетс)
		var j: int = rng.next_int(i + 1)
		var t: Variant = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	var out: Array = []
	if from_monster:
		var free: Array = []
		for id: String in D.LEGENDS:
			if not Rules.owns_id(side, id):
				free.append(id)
		if free.size() > 0:
			out.append(_offer_legend(free[rng.next_int(free.size())], side))
	var small: bool = not from_monster and not Rules.classic
	var big: bool = streak >= 5
	for k: String in kinds:
		if out.size() >= 3:
			break
		match k:
			"magic":
				if small and not big:
					var k1: String = Rules.roll_magic(rng)
					out.append({"type": "magic", "keys": [k1], "title": "Карта магии",
						"desc": "«%s» в руку (если рука полна — продаётся за свою цену)." % D.MAGIC[k1]["n"]})
					continue
				var keys: Array = [Rules.roll_magic(rng), Rules.roll_magic(rng)]
				out.append({"type": "magic", "keys": keys, "title": "Две карты магии",
					"desc": "«%s» и «%s» в руку (если рука полна — продаются за свою цену)." % [D.MAGIC[keys[0]]["n"], D.MAGIC[keys[1]]["n"]]})
			"gold":
				var amt: int = D.REWARD_GOLD if not small else (5 if big else 3)
				out.append({"type": "gold", "amount": amt, "title": "Кошель золота", "desc": "+%d золота сразу." % amt})
			"hero":
				# за серию — одна копия ★ (помогает собрать ★★, но не даёт готовую сильную карту)
				var lo: int = 3
				var hi: int = 4
				var hstar: int = 2
				if small:
					hstar = 1
					lo = 3 if big else 2
					hi = 4 if big else 3
				var pool: Array = []
				for id: String in D.BASE_HEROES:
					var c: int = int(D.BASE_HEROES[id]["c"])
					if c >= lo and c <= hi:
						pool.append(id)
				var hid: String = pool[rng.next_int(pool.size())]
				var hd: Dictionary = D.HEROES[hid]
				out.append({"type": "hero", "id": hid, "star": hstar, "title": "%s %s" % [hd["n"], "★".repeat(hstar)],
					"desc": "%s%s, %s. %s: %s%s" % [Rules.rank_label(int(hd["r"])), D.SUITS[hd["s"]]["sym"], D.SUITS[hd["s"]]["name"], hd["ab"]["n"], D.ab_desc(hid, hstar), _space_note(side, hid, hstar)]})
	return out

func _offer_legend(id: String, side: Dictionary) -> Dictionary:
	var d: Dictionary = D.HEROES[id]
	var rank: String = "Джокер в покерной руке" if d.has("wild") else "%s%s" % [Rules.rank_label(int(d["r"])), D.SUITS[d["s"]]["sym"]]
	return {"type": "legend", "id": id, "star": 1, "title": "Легенда: %s" % d["n"],
		"desc": "%s, %s. %s: %s На поле — только одна легенда.%s" % [rank, D.SUITS[d["s"]]["name"], d["ab"]["n"], D.ab_desc(id, 1), _space_note(side, id)]}

func _space_note(side: Dictionary, id: String, star: int = 2) -> String:
	if (side["bench"] as Array).has(null):
		return ""
	var same: int = 0
	for u: Dictionary in Rules.all_units(side):
		if u["id"] == id and int(u["star"]) == star:
			same += 1
	return "" if same >= 2 else " Скамья полна — карта будет продана."

func _offer_player(offers: Array, source: String) -> void:
	pending_reward = offers
	reward_source = source
	if auto_player and not offers.is_empty():
		choose_reward(Ai.choose_reward(p, offers))

func _ai_take_reward(offers: Array, source: String) -> Dictionary:
	if offers.is_empty():
		return {}
	var o: Dictionary = offers[Ai.choose_reward(ai, offers)]
	_apply_offer(ai, o)
	reward_log.append({"side": "ai", "round": round_n, "source": source, "type": o["type"], "id": o.get("id", "")})
	return o

## Выбрать награду i из pending_reward. {ok, offer, unit?, merged?, gold?, keys?, sold?}
func choose_reward(i: int) -> Dictionary:
	if pending_reward.is_empty() or i < 0 or i >= pending_reward.size():
		return _fail("")
	var o: Dictionary = pending_reward[i]
	var res: Dictionary = _apply_offer(p, o)
	reward_log.append({"side": "p", "round": round_n, "source": reward_source, "type": o["type"], "id": o.get("id", "")})
	pending_reward = []
	reward_source = ""
	res["ok"] = true
	res["offer"] = o
	return res

func _apply_offer(side: Dictionary, o: Dictionary) -> Dictionary:
	match str(o["type"]):
		"gold":
			side["gold"] = int(side["gold"]) + int(o["amount"])
			return {"gold": int(o["amount"])}
		"magic":
			for k: String in o["keys"]:
				Rules.return_item(side, k)
			return {"keys": o["keys"]}
		"hero", "legend":
			var u: Dictionary = Rules.new_unit(str(o["id"]), int(o.get("star", 1)))
			var r: Dictionary = Rules.gain_unit(side, u)
			if not r["ok"]:
				var v: int = Rules.sell_value(u)
				side["gold"] = int(side["gold"]) + v
				return {"sold": true, "gold": v}
			return {"unit": u, "merged": r["merged"]}
	return {}

# ---------- сохранение ----------

## Состояние для JSON (сохраняется только фаза магазина, как в JS).
func save_state() -> Dictionary:
	var st: Dictionary = {"v": 1, "diff": diff, "round": round_n, "phase": phase, "p": p.duplicate(true), "ai": ai.duplicate(true),
		"shop": shop.duplicate(), "magic_shop": magic_shop.duplicate(), "locked": locked, "free_roll": free_roll,
		"rng": rng.state, "uidc": Rules.next_uid_value, "over_result": over_result}
	if extras:
		st["extras"] = true
		st["pending_reward"] = pending_reward.duplicate(true)
		st["reward_source"] = reward_source
	return st

func load_state(d: Dictionary) -> bool:
	if not d.has("p") or not d.has("ai"):
		return false
	diff = str(d.get("diff", "normal"))
	if not D.AIBONUS.has(diff):
		diff = "normal"
	round_n = int(d.get("round", 1))
	phase = str(d.get("phase", "shop"))
	if phase == "battle":
		phase = "shop"
	p = _clean_side(d["p"])
	ai = _clean_side(d["ai"])
	shop = []
	for x: Variant in d.get("shop", []):
		shop.append(str(x) if x != null and D.HEROES.has(str(x)) else null)
	magic_shop = []
	for x: Variant in d.get("magic_shop", []):
		magic_shop.append(str(x) if x != null and D.MAGIC.has(str(x)) else null)
	locked = bool(d.get("locked", false))
	free_roll = int(d.get("free_roll", 0))
	rng.state = int(d.get("rng", 0)) & Rng.M32
	Rules.next_uid_value = int(d.get("uidc", 1))
	over_result = str(d.get("over_result", ""))
	battle = null
	extras = bool(d.get("extras", extras))
	pending_reward = []
	reward_source = ""
	if extras:
		var pr: Variant = d.get("pending_reward", [])
		if pr is Array:
			for o: Variant in pr:
				if o is Dictionary and _offer_ok(o):
					var co: Dictionary = (o as Dictionary).duplicate(true)
					for k: String in ["amount", "star"]:
						if co.has(k):
							co[k] = int(co[k])   # JSON отдаёт числа как float
					pending_reward.append(co)
		reward_source = str(d.get("reward_source", ""))
	return true

static func _offer_ok(o: Dictionary) -> bool:
	match str(o.get("type", "")):
		"gold": return o.has("amount")
		"magic":
			if not o.get("keys") is Array:
				return false
			for k: Variant in o["keys"]:
				if not D.MAGIC.has(str(k)):
					return false
			return true
		"hero", "legend": return D.HEROES.has(str(o.get("id", "")))
	return false

static func _clean_unit(u: Variant) -> Variant:
	if not u is Dictionary or not D.HEROES.has(str(u.get("id", ""))):
		return null
	var items: Array = []
	var it: Variant = u.get("items")
	if it is Array:
		for k: Variant in it:
			items.append(str(k))
	var fed: Variant = null
	var f: Variant = u.get("fed")
	if f is Dictionary:
		fed = {"atk": int(f.get("atk", 0)), "hp": int(f.get("hp", 0)), "n": int(f.get("n", 0))}
	return {"uid": int(u.get("uid", 0)), "id": str(u["id"]), "star": int(u.get("star", 1)), "items": items, "fed": fed}

static func _clean_side(s: Dictionary) -> Dictionary:
	var side: Dictionary = Rules.new_side(str(s.get("name", "")))
	for k: String in ["hp", "gold", "level", "xp", "streak", "allin_cd"]:
		side[k] = int(s.get(k, side[k]))
	side["allin"] = bool(s.get("allin", false))
	for z: String in ["board", "bench"]:
		var src: Variant = s.get(z, [])
		var arr: Array = side[z]
		for i in arr.size():
			arr[i] = _clean_unit(src[i]) if src is Array and i < (src as Array).size() else null
	var hand: Array = []
	for k: Variant in s.get("hand", []):
		if D.MAGIC.has(str(k)):
			hand.append(str(k))
	side["hand"] = hand
	return side
