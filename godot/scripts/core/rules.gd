class_name Rules
extends RefCounted
## Правила игры — статические функции, 1:1 с блоком «ПРАВИЛА» в web/index.html v1.4.0.
## Unit: {uid:int, id:String, star:int, items:Array[String], fed:{atk,hp,n}|null}
## Side: {hp, gold, level, xp, board:[5 Unit|null], bench:[6 Unit|null], streak, hand:[магия], allin:bool, allin_cd:int, name}
## Случайность — только через переданный Rng (в JS здесь был Math.random), порядок вызовов тот же.

const D = preload("res://scripts/core/data.gd")

## Счётчик uid карт (uidc в JS). Match сохраняет/восстанавливает его.
static var next_uid_value: int = 1

static func r(x: float) -> int:
	return D.r(x)

static func rank_label(rank: int) -> String:
	match rank:
		11: return "J"
		12: return "Q"
		13: return "K"
		14: return "A"
	return str(rank)

static func cap_of(level: int) -> int:
	return mini(5, level + 1)

# ---------- карты и стороны ----------

static func new_unit(id: String, star: int = 1) -> Dictionary:
	var u: Dictionary = {"uid": next_uid_value, "id": id, "star": star, "items": [], "fed": null}
	next_uid_value += 1
	return u

static func new_side(name: String = "") -> Dictionary:
	var board: Array = []
	board.resize(D.BOARD_SIZE)
	var bench: Array = []
	bench.resize(D.BENCH_SIZE)
	return {"hp": D.START_HP, "gold": 0, "level": 1, "xp": 0, "board": board, "bench": bench,
		"streak": 0, "hand": [], "allin": false, "allin_cd": 0, "name": name}

static func items_of(u: Dictionary) -> Array:
	var it: Variant = u.get("items")
	return it if it is Array else []

static func fed_of(u: Dictionary) -> Dictionary:
	var f: Variant = u.get("fed")
	return f if f is Dictionary else {}

static func has_fed(u: Dictionary) -> bool:
	return u.get("fed") is Dictionary

static func all_units(side: Dictionary) -> Array:
	var out: Array = []
	for u: Variant in side["board"]:
		if u != null: out.append(u)
	for u: Variant in side["bench"]:
		if u != null: out.append(u)
	return out

static func board_units(side: Dictionary) -> Array:
	var out: Array = []
	for u: Variant in side["board"]:
		if u != null: out.append(u)
	return out

static func board_count(side: Dictionary) -> int:
	return board_units(side).size()

## {zone:"board"|"bench", i} или {} если нет.
static func loc_of_uid(side: Dictionary, uid: int) -> Dictionary:
	for z: String in ["board", "bench"]:
		var arr: Array = side[z]
		for i in arr.size():
			if arr[i] != null and int(arr[i]["uid"]) == uid:
				return {"zone": z, "i": i}
	return {}

static func unit_by_uid(side: Dictionary, uid: int) -> Variant:
	var l: Dictionary = loc_of_uid(side, uid)
	return side[l["zone"]][l["i"]] if not l.is_empty() else null

# ---------- характеристики ----------

## {hp, atk} героя с учётом звезды и съеденных карт. Принимает u без uid/items, fed может отсутствовать.
static func stats(u: Dictionary) -> Dictionary:
	var d: Dictionary = D.HEROES[u["id"]]
	var fd: Dictionary = fed_of(u)
	var sm: float = D.STARM[int(u["star"])]
	return {"hp": r(float(d["hp"]) * sm) + int(fd.get("hp", 0)), "atk": r(float(d["atk"]) * sm) + int(fd.get("atk", 0))}

static func sell_value(u: Dictionary) -> int:
	return int(D.HEROES[u["id"]]["c"]) * int(pow(3, int(u["star"]) - 1))

static func power(u: Dictionary) -> float:
	var d: Dictionary = D.HEROES[u["id"]]
	var fd: Dictionary = fed_of(u)
	var extra: float = 0.0
	if has_fed(u):
		extra = float(fd.get("hp", 0)) / 8.0 + float(fd.get("atk", 0)) * 2.0
	return (float(d["hp"]) / 8.0 + float(d["atk"]) * 2.0 + float(d["c"]) * 45.0) * float(D.STARM[int(u["star"])]) + extra

## Устойчивая сортировка (как Array.prototype.sort в JS): cmp(a,b) > 0 — a после b.
static func ssort(arr: Array, cmp: Callable) -> Array:
	var out: Array = arr.duplicate()
	for i in range(1, out.size()):
		var x: Variant = out[i]
		var j: int = i - 1
		while j >= 0 and float(cmp.call(out[j], x)) > 0.0:
			out[j + 1] = out[j]
			j -= 1
		out[j + 1] = x
	return out

# ---------- покерные руки и союзы ----------

## cards: [{r:int, s:String}] → ключ руки из HANDS.
static func eval_hand(cards: Array) -> String:
	var n: int = cards.size()
	if n == 0:
		return "high"
	var cnt: Dictionary = {}
	for c: Dictionary in cards:
		cnt[c["r"]] = int(cnt.get(c["r"], 0)) + 1
	var v: Array = cnt.values()
	v.sort()
	v.reverse()
	var v0: int = v[0]
	var v1: int = v[1] if v.size() > 1 else 0
	var flush: bool = false
	if n == 5:
		flush = true
		for c: Dictionary in cards:
			if c["s"] != cards[0]["s"]:
				flush = false
	var straight: bool = false
	if n == 5 and v0 == 1:
		var rs: Array = []
		for c: Dictionary in cards:
			rs.append(int(c["r"]))
		rs.sort()
		straight = int(rs[4]) - int(rs[0]) == 4 or rs == [2, 3, 4, 5, 14]
		if straight and flush:
			return "royal" if int(rs[0]) == 10 else "sflush"
	if v0 == 4: return "four"
	if v0 == 3 and v1 == 2: return "full"
	if flush: return "flush"
	if straight: return "straight"
	if v0 == 3: return "three"
	if v0 == 2 and v1 == 2: return "two"
	if v0 == 2: return "pair"
	return "high"

## Копии одного героя считаются одной картой: оставляем первое вхождение каждого id.
static func unique_units(units: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for u: Dictionary in units:
		if not seen.has(u["id"]):
			seen[u["id"]] = true
			out.append(u)
	return out

static func has_joker(u: Dictionary) -> bool:
	return items_of(u).has("joker")

## Рука с учётом Джокера: перебираем ранги и стихии для карт с Джокером (до 2) и берём лучшую.
static func eval_units(units: Array) -> String:
	var ord: Array = ssort(units, func(a: Dictionary, b: Dictionary) -> float:
		return float((1 if has_joker(b) else 0) - (1 if has_joker(a) else 0)))
	var cards: Array = []
	for u: Dictionary in unique_units(ord):
		var d: Dictionary = D.HEROES[u["id"]]
		cards.append({"r": int(d["r"]), "s": d["s"], "j": has_joker(u)})
	var js: Array = []
	for c: Dictionary in cards:
		if c["j"] and js.size() < 2:
			js.append(c)
	if js.is_empty():
		return eval_hand(cards)
	var best: Array = ["high"]
	_joker_rec(cards, js, 0, best)
	return best[0]

static func _joker_rec(cards: Array, js: Array, i: int, best: Array) -> void:
	if best[0] == "royal":
		return  # лучше не бывает — результат тот же, перебор короче
	if i == js.size():
		var h: String = eval_hand(cards)
		if D.HAND_ORDER.find(h) > D.HAND_ORDER.find(best[0]):
			best[0] = h
		return
	for rank in range(2, 15):
		for s: String in D.SUIT_KEYS:
			js[i]["r"] = rank
			js[i]["s"] = s
			_joker_rec(cards, js, i + 1, best)

## {n:{S,H,D,C}, lv:{S,H,D,C}}: 2 разных героя стихии — уровень 1, 4 — уровень 2.
static func trait_levels(units: Array) -> Dictionary:
	var n: Dictionary = {"S": 0, "H": 0, "D": 0, "C": 0}
	for u: Dictionary in unique_units(units):
		var s: String = D.HEROES[u["id"]]["s"]
		n[s] = int(n[s]) + 1
	var lv: Dictionary = {}
	for k: String in n:
		lv[k] = 2 if int(n[k]) >= 4 else (1 if int(n[k]) >= 2 else 0)
	return {"n": n, "lv": lv}

static func team_info(units: Array) -> Dictionary:
	return {"hand": eval_units(units), "tl": trait_levels(units)}

# ---------- опыт, магазин ----------

static func add_xp(side: Dictionary, n: int) -> void:
	side["xp"] = int(side["xp"]) + n
	while int(side["level"]) < 8 and int(side["xp"]) >= int(D.XPNEED[int(side["level"])]):
		side["xp"] = int(side["xp"]) - int(D.XPNEED[int(side["level"])])
		side["level"] = int(side["level"]) + 1
	if int(side["level"]) >= 8:
		side["xp"] = 0

static func roll_id(level: int, rng: Rng) -> String:
	var o: Array = D.ODDS[level]
	var x: float = rng.next() * 100.0
	var c: int = 0
	while c < 5:
		x -= float(o[c])
		if x < 0.0:
			break
		c += 1
	var cost: int = mini(c, 4) + 1
	var pool: Array = []
	for id: String in D.HEROES:
		if int(D.HEROES[id]["c"]) == cost:
			pool.append(id)
	return pool[int(floorf(rng.next() * float(pool.size())))]

## «Козырь в рукаве»: шанс подсказки в витрине. Отстающим больше.
static func help_chance(side: Variant) -> float:
	if not side is Dictionary:
		return 0.0
	var sd: Dictionary = side
	return minf(0.5, 0.2 + 0.1 * float(maxi(0, -int(sd.get("streak", 0)))) + (0.1 if int(sd["hp"]) < 50 else 0.0))

static func help_id(level: int, side: Dictionary, rng: Rng) -> String:
	var odds: Array = D.ODDS[level]
	var mine: Array = all_units(side)
	var copies: Array = []
	for u: Dictionary in mine:
		if int(u["star"]) < 3 and not copies.has(u["id"]):
			copies.append(u["id"])
	copies = copies.filter(func(id: String) -> bool: return int(odds[mini(int(D.HEROES[id]["c"]), 5) - 1]) > 0)
	var ranks: Dictionary = {}
	for u: Dictionary in board_units(side):
		ranks[int(D.HEROES[u["id"]]["r"])] = true
	var have: Dictionary = {}
	for u: Dictionary in mine:
		have[u["id"]] = true
	var mates: Array = []
	for id: String in D.HEROES:
		var d: Dictionary = D.HEROES[id]
		if ranks.has(int(d["r"])) and not have.has(id) and int(odds[mini(int(d["c"]), 5) - 1]) > 0:
			mates.append(id)
	var pool: Array
	if rng.next() < 0.5 and mates.size() > 0:
		pool = mates
	elif copies.size() > 0:
		pool = copies
	else:
		pool = mates
	if pool.is_empty():
		return ""
	return pool[int(floorf(rng.next() * float(pool.size())))]

static func roll_shop(level: int, side: Variant, rng: Rng) -> Array:
	var hc: float = help_chance(side)
	var out: Array = []
	for i in 5:
		var id: String = ""
		if rng.next() < hc:
			id = help_id(level, side, rng)
		if id == "":
			id = roll_id(level, rng)
		out.append(id)
	return out

static func roll_magic(rng: Rng) -> String:
	var tot: float = 0.0
	for k: String in D.MAGIC:
		tot += float(D.MAGIC[k]["w"])
	var x: float = rng.next() * tot
	for k: String in D.MAGIC:
		x -= float(D.MAGIC[k]["w"])
		if x < 0.0:
			return k
	return D.MAGIC.keys()[0]

# ---------- слияние, покупка, кормление ----------

## Предмет уходит в руку (до 5) или продаётся за свою цену.
static func return_item(side: Dictionary, k: String) -> void:
	if side.has("hand") and (side["hand"] as Array).size() < D.HAND_MAX:
		(side["hand"] as Array).append(k)
	else:
		side["gold"] = int(side["gold"]) + int(D.MAGIC[k]["c"])

## Три одинаковые ★ → ★★, три ★★ → ★★★ (повторяет mergeAll). Возвращает последнюю слитую карту или null.
static func merge_all(side: Dictionary) -> Variant:
	var merged: Variant = null
	var changed: bool = true
	while changed:
		changed = false
		for star: int in [1, 2]:
			var g: Dictionary = {}
			for z: String in ["board", "bench"]:
				var arr: Array = side[z]
				for i in arr.size():
					var u: Variant = arr[i]
					if u != null and int(u["star"]) == star:
						if not g.has(u["id"]):
							g[u["id"]] = []
						(g[u["id"]] as Array).append({"z": z, "i": i, "u": u})
			for id: String in g:
				var lst: Array = g[id]
				if lst.size() >= 3:
					var keep: Dictionary = lst[0]
					var a: Dictionary = lst[1]
					var b: Dictionary = lst[2]
					var ku: Dictionary = keep["u"]
					var its: Array = []
					its.append_array(items_of(ku))
					its.append_array(items_of(a["u"]))
					its.append_array(items_of(b["u"]))
					ku["items"] = its.slice(0, 2)
					var fds: Array = []
					for x: Dictionary in [ku, a["u"], b["u"]]:
						if has_fed(x):
							fds.append(x["fed"])
					if fds.size() > 0:
						var fa: int = 0
						var fh: int = 0
						var fn: int = 0
						for f: Dictionary in fds:
							fa += int(f["atk"])
							fh += int(f["hp"])
							fn += int(f["n"])
						ku["fed"] = {"atk": fa, "hp": fh, "n": mini(D.FEED_MAX, fn)}
					for k: String in its.slice(2):
						return_item(side, k)
					ku["star"] = int(ku["star"]) + 1
					side[a["z"]][a["i"]] = null
					side[b["z"]][b["i"]] = null
					merged = ku
					changed = true
					break
			if changed:
				break
	var bench: Array = side["bench"]
	if bench.size() > D.BENCH_SIZE:
		var extra: Array = bench.slice(D.BENCH_SIZE)
		bench.resize(D.BENCH_SIZE)
		for u: Variant in extra:
			if u != null:
				var k: int = bench.find(null)
				if k >= 0:
					bench[k] = u
	return merged

## Положить карту на скамью (или слить с двумя копиями при полной скамье). {ok, merged}
static func gain_unit(side: Dictionary, unit: Dictionary) -> Dictionary:
	var bench: Array = side["bench"]
	var k: int = bench.find(null)
	if k >= 0:
		bench[k] = unit
		return {"ok": true, "merged": merge_all(side)}
	var same: int = 0
	for u: Dictionary in all_units(side):
		if u["id"] == unit["id"] and int(u["star"]) == 1:
			same += 1
	if same >= 2:
		bench.append(unit)
		return {"ok": true, "merged": merge_all(side)}
	return {"ok": false, "merged": null}

## Кого можно скормить герою recv: ★★+ той же стихии, кроме него самого.
static func feed_targets(side: Dictionary, recv: Dictionary) -> Array:
	var su: String = D.HEROES[recv["id"]]["s"]
	var out: Array = []
	for u: Dictionary in all_units(side):
		if int(u["uid"]) != int(recv["uid"]) and int(u["star"]) >= 2 and D.HEROES[u["id"]]["s"] == su:
			out.append(u)
	return out

static func can_feed(side: Dictionary, recv: Dictionary) -> bool:
	return int(fed_of(recv).get("n", 0)) < D.FEED_MAX and feed_targets(side, recv).size() > 0

## Жертвоприношение: food исчезает, recv навсегда получает 15% её базовых АТК и ОЗ (её предметы — в руку/золото).
## {ok, atk, hp, n, reason}
static func do_feed(side: Dictionary, recv_uid: int, food_uid: int) -> Dictionary:
	var recv: Variant = unit_by_uid(side, recv_uid)
	var loc: Dictionary = loc_of_uid(side, food_uid)
	if recv == null or loc.is_empty():
		return {"ok": false, "reason": "нет карты"}
	var food: Dictionary = side[loc["zone"]][loc["i"]]
	if int(fed_of(recv).get("n", 0)) >= D.FEED_MAX:
		return {"ok": false, "reason": "сыт"}
	var ok: bool = false
	for u: Dictionary in feed_targets(side, recv):
		if int(u["uid"]) == food_uid:
			ok = true
	if not ok:
		return {"ok": false, "reason": "нельзя скормить"}
	var b: Dictionary = stats({"id": food["id"], "star": food["star"]})
	var add_atk: int = r(float(b["atk"]) * D.FEED_PCT)
	var add_hp: int = r(float(b["hp"]) * D.FEED_PCT)
	if not has_fed(recv):
		recv["fed"] = {"atk": 0, "hp": 0, "n": 0}
	var fd: Dictionary = recv["fed"]
	fd["atk"] = int(fd["atk"]) + add_atk
	fd["hp"] = int(fd["hp"]) + add_hp
	fd["n"] = int(fd["n"]) + 1
	side[loc["zone"]][loc["i"]] = null
	for k: String in items_of(food):
		return_item(side, k)
	return {"ok": true, "atk": add_atk, "hp": add_hp, "n": int(fd["n"])}

# ---------- золото и урон ----------

## Урон за проигранный раунд: ×1,5 к старому (под 100 ОЗ), не больше DMG_CAP.
static func round_damage(base: int, surv: int) -> int:
	return mini(D.DMG_CAP, r(float(base + surv) * 1.5))

static func base_damage(round_n: int) -> int:
	return 1 + floori(round_n / 3.0)

## Золото за серию: поражения дают больше, чем победы.
static func streak_gold(st: int) -> int:
	if st < 0:
		return 3 if st <= -4 else (2 if st <= -3 else (1 if st <= -2 else 0))
	return 2 if st >= 4 else (1 if st >= 2 else 0)

## Доход начала раунда (без изменения стороны): {interest, sb, gold}. bonus — AIBONUS для соперника.
static func income(side: Dictionary, bonus: int = 0) -> Dictionary:
	var interest: int = mini(5, floori(int(side["gold"]) / 10.0))
	var sb: int = streak_gold(int(side["streak"]))
	return {"interest": interest, "sb": sb, "gold": maxi(0, 5 + interest + sb + bonus)}

## Очки выживших для урона: звезда + 1 за героя стоимостью 4+. units — карты (Unit) выживших.
static func survivor_score(units: Array) -> int:
	var s: int = 0
	for u: Dictionary in units:
		s += int(u["star"]) + (1 if int(D.HEROES[u["id"]]["c"]) >= 4 else 0)
	return s

static func update_streak(side: Dictionary, won: bool) -> void:
	var st: int = int(side["streak"])
	side["streak"] = (st + 1 if st > 0 else 1) if won else (st - 1 if st < 0 else -1)

# ---------- сеть ----------

## Проверка стола, присланного по сети (cleanBoard в JS).
static func clean_board(b: Variant) -> Array:
	var out: Array = []
	out.resize(D.BOARD_SIZE)
	if not b is Array:
		return out
	var arr: Array = b
	for i in mini(D.BOARD_SIZE, arr.size()):
		var u: Variant = arr[i]
		if not u is Dictionary or not D.HEROES.has(str(u.get("id", ""))):
			continue
		var items: Array = []
		var src_items: Variant = u.get("items")
		if src_items is Array:
			for k: Variant in src_items:
				if D.MAGIC.has(str(k)) and D.MAGIC[str(k)]["k"] == "item" and items.size() < 2:
					items.append(str(k))
		var cu: Dictionary = {"uid": int(u.get("uid", 0)), "id": str(u["id"]), "star": clampi(int(u.get("star", 1)), 1, 3), "items": items, "fed": null}
		var f: Variant = u.get("fed")
		if f is Dictionary:
			var fd: Dictionary = {"n": clampi(int(f.get("n", 0)), 0, D.FEED_MAX), "atk": clampi(int(f.get("atk", 0)), 0, 140), "hp": clampi(int(f.get("hp", 0)), 0, 1600)}
			if int(fd["n"]) > 0:
				cu["fed"] = fd
		out[i] = cu
	return out
