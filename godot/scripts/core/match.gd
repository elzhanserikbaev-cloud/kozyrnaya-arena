class_name Match
extends RefCounted
## Одиночная партия против ИИ без интерфейса: newGame/beginRound/buy/sell/…/fight/resolve из web/index.html v1.4.0.
## Игрок — сторона "home" в бою (ходит первой в нечётные ходы, как в соло-JS), соперник — "away".
##
## Отличие от JS только в источнике случайности: вместо Math.random — один Rng партии (можно задать seed),
## а криты в бою считаются от зерна боя (как в сетевом JS). Сохраняется состояние Rng — после загрузки игра продолжается тем же потоком.
##
## Действия возвращают Dictionary {ok:bool, reason?:String, ...} — интерфейс показывает reason тостом.

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

func _init(seed_value: int = -1) -> void:
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
	if phase != "result":
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
	return phase == "shop" and int(p["allin_cd"]) <= round_n and int(p["hp"]) < top_rival_hp()

func allin_reason() -> String:
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
	return last_result

# ---------- сохранение ----------

## Состояние для JSON (сохраняется только фаза магазина, как в JS).
func save_state() -> Dictionary:
	return {"v": 1, "diff": diff, "round": round_n, "phase": phase, "p": p.duplicate(true), "ai": ai.duplicate(true),
		"shop": shop.duplicate(), "magic_shop": magic_shop.duplicate(), "locked": locked, "free_roll": free_roll,
		"rng": rng.state, "uidc": Rules.next_uid_value, "over_result": over_result}

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
	return true

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
