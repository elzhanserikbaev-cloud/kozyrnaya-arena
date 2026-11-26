class_name Ai
extends RefCounted
## Соперник — aiArrange / aiTurn / aiMagic / aiCast из web/index.html v1.4.0, те же решения и тот же порядок случайных чисел.

const D = preload("res://scripts/core/data.gd")

## Целевой уровень по раунду (aiTurn).
const LEVEL_TARGET: Array = [0, 1, 2, 3, 3, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 8]

## Сочетания из arr по k в лексикографическом порядке (генератор combos в JS).
static func combos(arr: Array, k: int) -> Array:
	var out: Array = []
	_combos_rec(arr, k, 0, [], out)
	return out

static func _combos_rec(arr: Array, k: int, start: int, acc: Array, out: Array) -> void:
	if acc.size() == k:
		out.append(acc.duplicate())
		return
	for i in range(start, arr.size()):
		acc.append(arr[i])
		_combos_rec(arr, k, i + 1, acc, out)
		acc.pop_back()

static func _uid_in(u: Dictionary, lst: Array) -> bool:
	for x: Dictionary in lst:
		if int(x["uid"]) == int(u["uid"]):
			return true
	return false

## Расставить стол: лучший набор по силе × бонус руки × союзы, танки в центр, лишнее на скамью/продажу, кормление ★★.
static func arrange(side: Dictionary) -> void:
	var all: Array = Rules.ssort(Rules.all_units(side), func(a: Dictionary, b: Dictionary) -> float: return Rules.power(b) - Rules.power(a))
	var cap: int = Rules.cap_of(int(side["level"]))
	var k: int = mini(cap, all.size())
	var cand: Array = all.slice(0, mini(all.size(), cap + 3))
	var best: Array = all.slice(0, k)
	if Rules.legend_count(best) > Rules.LEGEND_BOARD_MAX:
		# дополнения: на поле не больше одной легенды — по умолчанию берём сильнейших без лишних легенд
		best = []
		for u: Dictionary in all:
			if best.size() < k and (not Rules.is_legend(u) or Rules.legend_count(best) < Rules.LEGEND_BOARD_MAX):
				best.append(u)
	var best_score: float = -1.0
	for st: Array in combos(cand, k):
		if Rules.legend_count(st) > Rules.LEGEND_BOARD_MAX:
			continue
		var ti: Dictionary = Rules.team_info(st)
		var H: Dictionary = D.HANDS[ti["hand"]]
		var sum: float = 0.0
		for u: Dictionary in st:
			sum += Rules.power(u)
		var sc: float = sum * (1.0 + (float(H["atk"]) + float(H["hp"])) / 2.0 + float(H["mana"]) * 0.15)
		var lv: Dictionary = ti["tl"]["lv"]
		for s: String in lv:
			sc *= 1.0 + float(lv[s]) * 0.06
		if sc > best_score:
			best_score = sc
			best = st
	var rest: Array = []
	for u: Dictionary in all:
		if not _uid_in(u, best):
			rest.append(u)
	var board: Array = []
	board.resize(5)
	var bench: Array = []
	bench.resize(6)
	side["board"] = board
	side["bench"] = bench
	var tanky: Array = Rules.ssort(best, func(a: Dictionary, b: Dictionary) -> float: return float(int(Rules.stats(b)["hp"]) - int(Rules.stats(a)["hp"])))
	var lanes: Array = [2, 1, 3, 0, 4]
	for i in tanky.size():
		board[lanes[i]] = tanky[i]
	for i in rest.size():
		if i < 6:
			bench[i] = rest[i]
		else:
			side["gold"] = int(side["gold"]) + Rules.sell_value(rest[i])
	for i in 6:
		var food: Variant = bench[i]
		if food == null or int(food["star"]) < 2:
			continue
		var fs: String = D.HEROES[food["id"]]["s"]
		var fp: float = Rules.power(food)
		var cands: Array = []
		for u: Variant in board:
			if u != null and D.HEROES[u["id"]]["s"] == fs and int(Rules.fed_of(u).get("n", 0)) < D.FEED_MAX and Rules.power(u) > fp * 1.2:
				cands.append(u)
		cands = Rules.ssort(cands, func(a: Dictionary, b: Dictionary) -> float: return Rules.power(b) - Rules.power(a))
		if cands.is_empty():
			continue
		var tgt: Dictionary = cands[0]
		var b: Dictionary = Rules.stats({"id": food["id"], "star": food["star"]})
		if not Rules.has_fed(tgt):
			tgt["fed"] = {"atk": 0, "hp": 0, "n": 0}
		var fd: Dictionary = tgt["fed"]
		fd["atk"] = int(fd["atk"]) + D.r(float(b["atk"]) * D.FEED_PCT)
		fd["hp"] = int(fd["hp"]) + D.r(float(b["hp"]) * D.FEED_PCT)
		fd["n"] = int(fd["n"]) + 1
		bench[i] = null

static func _shop_once(side: Dictionary, rng: Rng) -> void:
	for id: String in Rules.roll_shop(int(side["level"]), side, rng):
		var d: Dictionary = D.HEROES[id]
		var cost: int = d["c"]
		if int(side["gold"]) < cost:
			continue
		var all: Array = Rules.all_units(side)
		var owned: int = 0
		for u: Dictionary in all:
			if u["id"] == id and int(u["star"]) < 3:
				owned += 1
		var want: bool = owned > 0 or all.size() < Rules.cap_of(int(side["level"])) + 2 or cost >= mini(5, int(side["level"]) - 1)
		if not want:
			continue
		var res: Dictionary = Rules.gain_unit(side, Rules.new_unit(id))
		if not res["ok"]:
			var bench: Array = side["bench"]
			var w: int = -1
			for i in bench.size():
				var u: Variant = bench[i]
				if u != null and (w < 0 or Rules.power(u) < Rules.power(bench[w])):
					w = i
			if w < 0 or Rules.power(bench[w]) >= Rules.power({"id": id, "star": 1}):
				continue
			side["gold"] = int(side["gold"]) + Rules.sell_value(bench[w])
			bench[w] = null
			res = Rules.gain_unit(side, Rules.new_unit(id))
		if res["ok"]:
			side["gold"] = int(side["gold"]) - cost

## Ход соперника в магазине: опыт до целевого уровня, покупки, обновления, расстановка, магия.
static func take_turn(side: Dictionary, round_n: int, diff: String, rng: Rng) -> void:
	var target: int = LEVEL_TARGET[mini(round_n, 16)]
	while int(side["level"]) < target and int(side["level"]) < 8 and int(side["gold"]) >= 4:
		side["gold"] = int(side["gold"]) - 4
		Rules.add_xp(side, 4)
	_shop_once(side, rng)
	var keep: int = 14 if diff == "hard" else (20 if round_n >= 10 else 30)
	var rolls: int = 0
	if diff != "easy":
		while int(side["gold"]) >= keep + 2 and rolls < 8:
			side["gold"] = int(side["gold"]) - 2
			rolls += 1
			_shop_once(side, rng)
	arrange(side)
	magic(side, round_n, diff, rng)

## Покупка магии: усиление сильнейшему герою или заклинание в руку (до 2).
static func magic(side: Dictionary, round_n: int, diff: String, rng: Rng) -> void:
	if round_n < 2 or (diff == "easy" and round_n % 2 == 1):
		return
	var picks: Array = [Rules.roll_magic(rng), Rules.roll_magic(rng)]
	for k: String in picks:
		var M: Dictionary = D.MAGIC[k]
		if int(side["gold"]) < int(M["c"]) + (0 if round_n < 6 else 8):
			continue
		var hand: Array = side["hand"]
		if M["k"] == "spell" and hand.size() >= 2:
			continue
		if M["k"] == "item":
			var cands: Array = []
			for u: Variant in side["board"]:
				if u != null and Rules.items_of(u).size() < 2:
					cands.append(u)
			cands = Rules.ssort(cands, func(a: Dictionary, b: Dictionary) -> float: return Rules.power(b) - Rules.power(a))
			if cands.is_empty():
				continue
			var tgt: Dictionary = cands[0]
			if not tgt.get("items") is Array:
				tgt["items"] = []
			(tgt["items"] as Array).append(k)
		else:
			hand.append(k)
		side["gold"] = int(side["gold"]) - int(M["c"])
		break

## Дополнения: какую из наград (Match.pending_reward) взять. Возвращает индекс оффера.
## Легенда — если на поле ещё нет легенды; герой ★★ — если есть место (или он сольётся); иначе золото/магия.
static func choose_reward(side: Dictionary, offers: Array) -> int:
	var best: int = 0
	var best_sc: float = -1.0
	var bench_free: bool = (side["bench"] as Array).has(null)
	var hand_n: int = (side["hand"] as Array).size()
	for i in offers.size():
		var o: Dictionary = offers[i]
		var sc: float = 0.0
		match str(o.get("type", "")):
			"legend":
				sc = (100.0 if Rules.legend_count(Rules.all_units(side)) == 0 else 15.0) if bench_free else 5.0
			"hero":
				var same: int = 0
				for u: Dictionary in Rules.all_units(side):
					if u["id"] == o["id"] and int(u["star"]) == 2:
						same += 1
				sc = (60.0 + 25.0 * same) if (bench_free or same >= 2) else 8.0
			"gold":
				sc = 45.0 if int(side["gold"]) < 20 else 30.0
			"magic":
				sc = 40.0 if hand_n <= 3 else 12.0
		if sc > best_sc:
			best_sc = sc
			best = i
	return best

## Идёт ли соперник ва-банк (fight() в JS): когда отстаёт больше чем на 15 ОЗ, с шансом 60%, раз в 3 раунда.
## Случайное число берётся только если остальные условия выполнены (как && в JS).
static func wants_allin(side: Dictionary, opp_hp: int, round_n: int, rng: Rng) -> bool:
	return int(side.get("allin_cd", 0)) <= round_n and int(side["hp"]) + 15 < opp_hp and rng.next() < 0.6

## Цель для заклинания ИИ в бою (aiCast): allies/foes — живые бойцы Battle. null — цель не нужна или её нет.
static func battle_spell_choice(key: String, allies: Array, foes: Array) -> Variant:
	var M: Dictionary = D.MAGIC[key]
	var by_ratio: Callable = func(a: Dictionary, b: Dictionary) -> float:
		return float(a["hp"]) / float(a["max_hp"]) - float(b["hp"]) / float(b["max_hp"])
	var by_atk: Callable = func(a: Dictionary, b: Dictionary) -> float: return float(int(b["atk"]) - int(a["atk"]))
	var lst: Array = []
	if key == "guillotine":
		lst = Rules.ssort(foes, by_ratio)
	elif M["t"] == "foe":
		lst = Rules.ssort(foes, by_atk)
	elif M["t"] == "ally":
		if key == "surge":
			lst = Rules.ssort(allies.filter(func(c: Dictionary) -> bool: return int(c["mana"]) < int(c["mm"])), by_atk)
		else:
			lst = Rules.ssort(allies, by_ratio)
	else:
		return null
	return lst[0] if lst.size() > 0 else null
