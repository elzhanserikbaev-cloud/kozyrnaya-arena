extends SceneTree
## Тесты ядра (headless):
##   Godot --headless --path godot --script res://tests/test_core.gd [-- --games=200]
## Сверка с JS: сначала `node godot/tests/js_parity.js` (пишет tests/parity_js.json), затем этот тест сравнит бои и партии.

const D = preload("res://scripts/core/data.gd")

var checks: int = 0
var fails: int = 0
var sim_games: int = 200

func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			sim_games = int(a.substr(8))
	var t0: int = Time.get_ticks_msec()
	test_rng()
	test_hands()
	test_merges()
	test_feeding()
	test_damage_and_gold()
	test_match_flow()
	test_help_chance()
	test_battle_basics()
	test_determinism()
	test_save_load()
	test_parity()
	test_simulation()
	print("\n%d проверок, ошибок: %d (%.1f с)" % [checks, fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if fails > 0 else 0)

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  ОШИБКА: ", msg)

func eq(a: Variant, b: Variant, msg: String) -> void:
	ok(a == b, "%s: получено %s, ожидалось %s" % [msg, str(a), str(b)])

func section(name: String) -> void:
	print("— ", name)

func U(id: String, star: int = 1, items: Array = [], fed: Variant = null) -> Dictionary:
	var u: Dictionary = Rules.new_unit(id, star)
	u["items"] = items.duplicate()
	u["fed"] = fed
	return u

# ---------------------------------------------------------------

func test_rng() -> void:
	section("mulberry32")
	var ref: Dictionary = {1: [2693262067, 11749833, 2265367787, 4213581821],
		123456789: [1107202814, 4169434471, 3372958138, 885470128],
		2147483646: [4267670024, 1636768646, 1630072450, 4289807666]}
	for s: int in ref:
		var r: Rng = Rng.new(s)
		var got: Array = []
		for i in 4:
			got.append(int(r.next() * 4294967296.0))
		eq(got, ref[s], "mulberry32(%d)" % s)

func test_hands() -> void:
	section("покерные руки, Джокер, копии")
	eq(Rules.eval_units([]), "high", "пусто")
	eq(Rules.eval_units([U("cutpurse"), U("leech")]), "pair", "пара")
	eq(Rules.eval_units([U("cutpurse"), U("cutpurse")]), "high", "копии = одна карта")
	eq(Rules.eval_units([U("cutpurse"), U("cutpurse", 2), U("leech")]), "pair", "копии не дают тройку")
	eq(Rules.eval_units([U("cutpurse"), U("leech"), U("sellsword"), U("cardsharp")]), "two", "две пары")
	eq(Rules.eval_units([U("cutpurse"), U("leech"), U("spider")]), "three", "тройка")
	eq(Rules.eval_units([U("cutpurse"), U("leech"), U("spider"), U("sellsword"), U("cardsharp")]), "full", "фулл-хаус")
	eq(Rules.eval_units([U("cutpurse"), U("sellsword"), U("gravedigger"), U("vampire"), U("nighthunter")]), "straight", "стрит 2-6")
	eq(Rules.eval_units([U("reaper"), U("leech"), U("sellsword"), U("gravedigger"), U("vampire")]), "straight", "стрит A-5")
	eq(Rules.eval_units([U("cutpurse"), U("cardsharp"), U("duelist"), U("nighthunter"), U("shadowmaster")]), "flush", "флеш (Лёд)")
	eq(Rules.eval_units([U("cutpurse"), U("cardsharp"), U("duelist"), U("vampire"), U("nighthunter")]), "straight", "стрит без Джокера")
	eq(Rules.eval_units([U("cutpurse"), U("cardsharp"), U("duelist"), U("vampire", 1, ["joker"]), U("nighthunter")]), "sflush", "Джокер → стрит-флеш")
	eq(Rules.eval_units([U("cutpurse"), U("leech"), U("spider"), U("sellsword", 1, ["joker"])]), "four", "Джокер → каре")
	eq(Rules.eval_units([U("guildkiller"), U("guildmaster"), U("spadequeen"), U("reaper"), U("cutpurse", 1, ["joker"])]), "royal", "Джокер → роял-флеш")
	eq(Rules.eval_units([U("guildkiller"), U("guildmaster"), U("spadequeen", 1, ["joker"]), U("cutpurse", 1, ["joker"])]), "three", "2 Джокера, 4 карты → тройка (каре нужно 4 одного ранга)")
	eq(Rules.eval_units([U("leech"), U("spider"), U("guildmaster", 1, ["joker"]), U("guildkiller", 1, ["joker"])]), "four", "2 Джокера → каре")
	# герой с Джокером идёт первым, копия без Джокера его не вытесняет
	eq(Rules.eval_units([U("sellsword"), U("sellsword", 1, ["joker"]), U("leech"), U("spider")]), "three", "копия с Джокером важнее копии без")
	eq(Rules.eval_units([U("sellsword"), U("leech"), U("spider")]), "pair", "без Джокера — пара")
	var tl: Dictionary = Rules.trait_levels([U("cutpurse"), U("cardsharp"), U("duelist"), U("nighthunter"), U("leech"), U("vampire"), U("cutpurse")])
	eq(tl["n"]["S"], 4, "союз Льда считает разных героев")
	eq(tl["lv"]["S"], 2, "союз Льда ур. 2")
	eq(tl["lv"]["H"], 1, "союз Огня ур. 1")
	eq(tl["lv"]["D"], 0, "союз Света 0")

func test_merges() -> void:
	section("слияния ★★/★★★, сумма кормления, лишние предметы")
	var s: Dictionary = Rules.new_side()
	s["bench"][0] = U("cutpurse", 1, ["sword"], {"atk": 5, "hp": 10, "n": 1})
	s["bench"][1] = U("cutpurse", 1, ["armor"], {"atk": 3, "hp": 6, "n": 2})
	var r: Dictionary = Rules.gain_unit(s, U("cutpurse", 1, ["orb"]))
	ok(r["ok"], "покупка третьей копии")
	var m: Dictionary = r["merged"]
	eq(m["star"], 2, "★★")
	eq(m["items"], ["sword", "armor"], "предметы: первые два")
	eq(s["hand"], ["orb"], "третий предмет в руку")
	eq(m["fed"], {"atk": 8, "hp": 16, "n": 2}, "кормление суммируется, n ≤ 2")
	eq(Rules.all_units(s).size(), 1, "осталась одна карта")
	# лишний предмет при полной руке → золото
	var s2: Dictionary = Rules.new_side()
	s2["hand"] = ["heal", "heal", "heal", "heal", "heal"]
	s2["gold"] = 0
	s2["bench"][0] = U("leech", 1, ["sword", "fang"])
	s2["bench"][1] = U("leech", 1, ["joker"])
	Rules.gain_unit(s2, U("leech"))
	eq(s2["gold"], 5, "Джокер при полной руке продан за 5")
	# ★★★: две ★★ на поле + две ★ на скамье + покупка
	var s3: Dictionary = Rules.new_side()
	s3["board"][0] = U("duelist", 2)
	s3["board"][2] = U("duelist", 2)
	s3["bench"][3] = U("duelist")
	s3["bench"][4] = U("duelist")
	var r3: Dictionary = Rules.gain_unit(s3, U("duelist"))
	eq(r3["merged"]["star"], 3, "★★★")
	eq(s3["board"][0]["star"], 3, "★★★ остаётся на месте первой копии (поле)")
	eq(Rules.all_units(s3).size(), 1, "после ★★★ одна карта")
	# полная скамья: третья копия всё равно сливается
	var s4: Dictionary = Rules.new_side()
	for i in 6:
		s4["bench"][i] = U(["spider", "spider", "nun", "crossbow", "leech", "sellsword"][i])
	var r4: Dictionary = Rules.gain_unit(s4, U("spider"))
	ok(r4["ok"] and r4["merged"] != null and int(r4["merged"]["star"]) == 2, "полная скамья + 2 копии → слияние")
	eq((s4["bench"] as Array).size(), 6, "скамья снова 6 мест")
	ok(not Rules.gain_unit(s4, U("vampire"))["ok"] or Rules.all_units(s4).size() == 6, "")
	var s5: Dictionary = Rules.new_side()
	for i in 6:
		s5["bench"][i] = U("nun")
	s5["bench"][0] = U("crossbow")
	ok(not Rules.gain_unit(s5, U("gravedigger"))["ok"], "полная скамья без копий — нельзя")

func test_feeding() -> void:
	section("жертвоприношение")
	var s: Dictionary = Rules.new_side()
	var recv: Dictionary = U("nighthunter")
	s["board"][0] = recv
	var food1: Dictionary = U("cutpurse", 2, ["sword"])
	var food2: Dictionary = U("duelist", 2)
	var food3: Dictionary = U("cardsharp", 3)
	s["bench"][0] = food1
	s["bench"][1] = U("leech", 2)        # другая стихия
	s["bench"][2] = U("cardsharp", 1)    # ★
	s["bench"][3] = food2
	s["bench"][4] = food3
	var tg: Array = Rules.feed_targets(s, recv).map(func(u: Dictionary) -> int: return u["uid"])
	eq(tg, [food1["uid"], food2["uid"], food3["uid"]], "цели: ★★+ той же стихии")
	var r: Dictionary = Rules.do_feed(s, recv["uid"], s["bench"][1]["uid"])
	ok(not r["ok"], "чужая стихия запрещена")
	r = Rules.do_feed(s, recv["uid"], food1["uid"])
	ok(r["ok"], "кормление ★★")
	# Карманник ★★: ОЗ R(440*1.8)=792, АТК R(58*1.8)=104 → +16 АТК, +119 ОЗ
	eq([r["atk"], r["hp"]], [16, 119], "15% базовых АТК/ОЗ еды")
	eq(s["hand"], ["sword"], "предмет еды вернулся в руку")
	eq(Rules.stats(recv), {"hp": 580 + 119, "atk": 70 + 16}, "статы с кормлением")
	r = Rules.do_feed(s, recv["uid"], food2["uid"])
	ok(r["ok"] and int(r["n"]) == 2, "второе кормление")
	r = Rules.do_feed(s, recv["uid"], food3["uid"])
	ok(not r["ok"], "больше 2 нельзя")
	ok(not Rules.can_feed(s, recv), "сыт")
	eq(Rules.stats({"id": "cutpurse", "star": 2}), {"hp": 792, "atk": 104}, "stats без uid/items/fed")
	eq(Rules.rank_label(12), "Q", "rank_label")
	eq(Rules.sell_value(U("reaper", 2)), 15, "цена продажи ★★")

func test_damage_and_gold() -> void:
	section("урон, серии, доход")
	eq(Rules.round_damage(1, 0), 2, "минимальный урон")
	eq(Rules.round_damage(2, 7), 14, "R((2+7)*1.5)")
	eq(Rules.round_damage(5, 10), 18, "кап 18")
	eq(Rules.base_damage(1), 1, "база раунд 1")
	eq(Rules.base_damage(9), 4, "база раунд 9")
	var sg: Array = []
	for st in range(-5, 6):
		sg.append(Rules.streak_gold(st))
	eq(sg, [3, 3, 2, 1, 0, 0, 0, 1, 1, 2, 2], "streak_gold -5..5")
	var side: Dictionary = Rules.new_side()
	side["gold"] = 37
	side["streak"] = -3
	eq(Rules.income(side), {"interest": 3, "sb": 2, "gold": 10}, "доход")
	side["gold"] = 80
	eq(Rules.income(side, -1)["interest"], 5, "проценты не больше 5")
	eq(Data_spell(300, 1), 300, "spellPow раунд 1")
	eq(Data_spell(300, 5), 444, "spellPow раунд 5")
	eq(D.magic_desc("fireball", 5), "Наносит 444 урона выбранному врагу.", "magic_desc")
	eq(D.ab_desc("cutpurse", 2), "Бьёт цель на 250.", "ab_desc ★★")

func Data_spell(b: int, rn: int) -> int:
	return D.spell_pow(b, rn)

func _match_for_resolve() -> Match:
	var m: Match = Match.new(5)
	m.new_game("normal")
	m.round_n = 4
	m.phase = "battle"
	return m

func test_match_flow() -> void:
	section("Match: ва-банк, награда, серии, бесплатное обновление")
	var surv: Array = [{"id": "reaper", "star": 2}, {"id": "cutpurse", "star": 1}]   # очки: 2+1 + 1 = 4
	# победа, оба ва-банк: R(min(18,R((2+4)*1.5))=9 ×2 =18 ×1.5 = 27)
	var m: Match = _match_for_resolve()
	m.p["allin"] = true
	m.ai["allin"] = true
	var r: Dictionary = m.finish_battle({"outcome": "home", "survivors_home": surv, "survivors_away": []})
	eq(r["dmg_e"], 27, "победа: ва-банк ×2, ва-банк соперника ×1.5")
	eq(m.ai["hp"], 73, "ОЗ соперника")
	eq(m.p["allin_cd"], 7, "ва-банк снова через 3 раунда")
	# поражение со своим ва-банком
	m = _match_for_resolve()
	m.p["allin"] = true
	r = m.finish_battle({"outcome": "away", "survivors_home": [], "survivors_away": surv})
	eq(r["dmg_p"], 14, "поражение с ва-банком: R(9*1.5)=14")
	eq(m.p["streak"], -1, "серия поражений")
	# поражение от ва-банка соперника
	m = _match_for_resolve()
	m.ai["allin"] = true
	r = m.finish_battle({"outcome": "away", "survivors_home": [], "survivors_away": surv})
	eq(r["dmg_p"], 18, "ва-банк соперника ×2 (может превысить кап)")
	# ничья
	m = _match_for_resolve()
	r = m.finish_battle({"outcome": "draw", "survivors_home": surv, "survivors_away": surv})
	eq([r["dmg_p"], r["dmg_e"]], [3, 3], "ничья: обе стороны R((2+0)*1.5)=3")
	# награда за голову
	m = _match_for_resolve()
	m.ai["streak"] = 4
	m.p["gold"] = 0
	r = m.finish_battle({"outcome": "home", "survivors_home": surv, "survivors_away": []})
	eq(m.p["gold"], 4, "награда: золото = длина серии")
	eq((m.p["hand"] as Array).size(), 1, "награда: карта магии")
	eq(m.ai["streak"], -1, "серия соперника прервана")
	m = _match_for_resolve()
	m.p["streak"] = 3
	m.ai["gold"] = 0
	m.finish_battle({"outcome": "away", "survivors_home": [], "survivors_away": surv})
	eq(m.ai["gold"], 3, "ИИ получает награду за голову игрока")
	eq(m.ai["streak"], 1, "серия ИИ")
	# бесплатное обновление после поражения
	ok(m.next_round(), "следующий раунд")
	eq(m.free_roll, 1, "после поражения обновление даром")
	var g: int = m.p["gold"]
	m.reroll()
	eq(m.p["gold"], g, "бесплатное обновление")
	m.reroll()
	eq(m.p["gold"], g - 2, "второе — за 2")
	# конец игры
	m = _match_for_resolve()
	m.p["hp"] = 5
	r = m.finish_battle({"outcome": "away", "survivors_home": [], "survivors_away": surv})
	eq(r["over"], "lose", "игра окончена")
	eq(m.phase, "over", "фаза over")
	# ва-банк доступен только отстающему
	m = Match.new(9)
	m.new_game("normal")
	ok(not m.toggle_allin()["ok"], "ва-банк при равных ОЗ запрещён")
	m.p["hp"] = 50
	ok(m.toggle_allin()["ok"] and m.p["allin"], "ва-банк при отставании")
	# магазин: покупка, перестановка, лимит поля
	m = Match.new(11)
	m.new_game("normal")
	eq(m.p["gold"], 6, "старт 6 золота")
	eq(m.shop.size(), 5, "5 карт в витрине")
	var b: Dictionary = m.buy(0)
	ok(b["ok"], "покупка")
	var bi: int = (m.p["bench"] as Array).find(b["unit"])
	ok(m.move("bench", bi, "board", 2)["ok"], "на поле")
	m.p["bench"][0] = U("nun")
	m.p["bench"][1] = U("crossbow")
	ok(m.move("bench", 0, "board", 0)["ok"], "вторая карта на поле (уровень 1 → 2 места)")
	ok(not m.move("bench", 1, "board", 1)["ok"], "третья — нет места")
	ok(m.move("bench", 1, "board", 0)["ok"], "замена занятого места разрешена")
	var sl: Dictionary = m.sell("bench", 1)
	eq(sl["gold"], 1, "продажа")
	# магия: усиление на героя, заклинание в бою, кормление через Match
	m.p["gold"] = 50
	m.magic_shop = ["sword", "fireball"]
	ok(m.buy_magic(0)["ok"] and m.buy_magic(1)["ok"], "покупка магии")
	ok(not m.use_item(1, "board", 0)["ok"], "заклинание не надевается")
	ok(m.use_item(0, "board", 0)["ok"] and Rules.items_of(m.p["board"][0]).has("sword"), "усиление надето")
	var food: Dictionary = U("cardsharp", 2)
	var eater: Dictionary = U("duelist")
	m.p["bench"][4] = food
	m.p["bench"][5] = eater
	eq(m.feed_targets(eater["uid"]), [food["uid"]], "Match.feed_targets")
	ok(m.feed(eater["uid"], food["uid"])["ok"] and m.p["bench"][4] == null, "Match.feed")
	m.p["board"] = [U("crossbow"), null, null, null, null]
	m.ai["board"] = [U("spider"), null, null, null, null]
	m.ai["hand"] = []
	var bt: Battle = m.start_battle()
	m.ai["board"] = [U("spider"), null, null, null, null]
	ok(bt != null and m.phase == "battle", "бой начат")
	var foe_uid: int = int(bt.units().filter(func(c: Dictionary) -> bool: return c["side"] == "away")[0]["uid"])
	ok(m.play_spell(0, foe_uid)["ok"] and (m.p["hand"] as Array).is_empty(), "заклинание в бою")
	var ev1: Array = bt.step()
	ok(ev1.any(func(e: Dictionary) -> bool: return e["t"] == "spell" and e["key"] == "fireball"), "Адское пламя сработало в начале хода")
	var fr: Dictionary = m.finish_battle()
	ok(m.phase == "result" or m.phase == "over", "раунд завершён (%s)" % fr["outcome"])

func test_help_chance() -> void:
	section("«Козырь в рукаве»")
	var s: Dictionary = Rules.new_side()
	eq(Rules.help_chance(s), 0.2, "база 20%")
	s["streak"] = -2
	ok(absf(Rules.help_chance(s) - 0.4) < 1e-9, "−2 серия → 40%")
	s["hp"] = 40
	eq(Rules.help_chance(s), 0.5, "кап 50%")
	s["streak"] = 0
	ok(absf(Rules.help_chance(s) - 0.3) < 1e-9, "мало ОЗ → 30%")
	eq(Rules.help_chance(null), 0.0, "без стороны 0")
	# подсказки: копии своих героев или те же ранги
	var side: Dictionary = Rules.new_side()
	side["board"][0] = U("cutpurse")
	side["bench"][0] = U("sellsword")
	var rng: Rng = Rng.new(77)
	var good: int = 0
	for i in 300:
		var id: String = Rules.help_id(1, side, rng)
		if id in ["cutpurse", "sellsword", "leech", "spider"]:
			good += 1
	eq(good, 300, "help_id даёт копии или героев того же ранга")
	# частота подсказок в витрине: при шансе 20% и уровне 1 ~20% + случайные совпадения
	var hits: int = 0
	var total: int = 0
	for i in 400:
		for id: String in Rules.roll_shop(1, side, rng):
			total += 1
			if id == "cutpurse" or id == "sellsword" or id == "leech" or id == "spider":
				hits += 1
	var frac: float = float(hits) / float(total)
	print("   доля подходящих карт в витрине: %.1f%% (без подсказок было бы ~44%%)" % (frac * 100.0))
	ok(frac > 0.5 and frac < 0.62, "доля подходящих карт ≈ 0.2 + 0.8·4/9")

func _board(arr: Array, base: int) -> Array:
	var out: Array = []
	for lane in 5:
		var u: Variant = arr[lane] if lane < arr.size() else null
		if u == null:
			out.append(null)
		else:
			var it: Array = []
			for k: Variant in u.get("items", []):
				it.append(str(k))
			var fed: Variant = null
			if u.get("fed") is Dictionary:
				fed = {"atk": int(u["fed"]["atk"]), "hp": int(u["fed"]["hp"]), "n": int(u["fed"]["n"])}
			out.append({"uid": base + lane, "id": str(u["id"]), "star": int(u["star"]), "items": it, "fed": fed})
	return out

func test_battle_basics() -> void:
	section("бой: события, снимок, очередь заклинаний")
	var home: Array = _board([{"id": "cutpurse", "star": 2}, {"id": "nun", "star": 1}, null, {"id": "sellsword", "star": 1}, null], 1)
	var away: Array = _board([{"id": "leech", "star": 1}, null, {"id": "spider", "star": 1}, null, null], 101)
	var b: Battle = Battle.new(home, away, {}, {}, 1, 1)
	eq(b.units().size(), 5, "5 бойцов в снимке")
	var keys: Array = b.units()[0].keys()
	for k: String in ["uid", "side", "lane", "hp", "max_hp", "mana", "mm", "shield", "atk", "alive", "stunned", "poison"]:
		ok(keys.has(k), "снимок содержит " + k)
	ok(b.queue_spell("home", "fireball", 101), "заклинание 1")
	ok(b.queue_spell("home", "bless", -1), "заклинание 2")
	ok(not b.queue_spell("home", "rage", -1), "третье за бой нельзя")
	ok(not b.queue_spell("home", "sword", -1), "усиление — не заклинание")
	var ev: Array = b.step()
	eq(ev[0]["t"], "step", "первое событие — step")
	var types: Array = ev.map(func(e: Dictionary) -> String: return e["t"])
	ok(types.has("spell") and types.has("shield") and types.has("attack") and types.has("hit"), "заклинания применяются в начале хода")
	eq(ev[1]["key"], "fireball", "порядок очереди")
	var all: Array = ev.duplicate()
	all.append_array(b.run_to_end())
	ok(b.over(), "бой закончен")
	eq(all[all.size() - 1]["t"], "end", "последнее событие — end")
	var seen: Dictionary = {}
	for e: Dictionary in all:
		seen[e["t"]] = true
	ok(seen.has("death"), "есть гибели")
	# все типы способностей и заклинаний отрабатывают без ошибок
	var ab_ids: Array = ["cutpurse", "leech", "spider", "sellsword", "cardsharp", "nun", "gravedigger", "cultist", "necro", "bloodpriest", "cardinal", "deathlord", "tyrant", "reaper", "blooddemon", "plaguelord", "executioner"]
	var n: int = 0
	for i in range(0, ab_ids.size(), 5):
		var hb: Array = []
		for j in 5:
			hb.append({"id": ab_ids[(i + j) % ab_ids.size()], "star": 2, "items": ["orb", "thorns"]})
		var ab_b: Battle = Battle.new(_board(hb, 1), _board([{"id": "gargoyle", "star": 3}, {"id": "vampirecount", "star": 2, "items": ["fang"]}, {"id": "tyrant", "star": 2}, {"id": "reaper", "star": 2}, {"id": "deathlord", "star": 2}], 101), {"ai": true, "hand": ["venom", "guillotine"]}, {"ai": true, "hand": ["revive", "surge"]}, 1000 + i, 10)
		for e: Dictionary in ab_b.run_to_end():
			if e["t"] == "cast" or e["t"] == "spell":
				n += 1
	ok(n > 10, "способности и заклинания ИИ разыгрываются (%d)" % n)

func _event_log(seed_value: int) -> String:
	var home: Array = _board([{"id": "nighthunter", "star": 2, "items": ["sword"]}, {"id": "blackknight", "star": 1, "items": ["armor", "joker"]}, {"id": "werewolf", "star": 1}, {"id": "crimsonwitch", "star": 1, "items": ["fang"]}, {"id": "guildmaster", "star": 1, "items": ["feather"]}], 1)
	var away: Array = _board([{"id": "sellsword", "star": 2, "items": ["thorns"]}, {"id": "shadowmaster", "star": 1}, {"id": "deathlord", "star": 1}, {"id": "necro", "star": 1}, {"id": "plaguedoc", "star": 1}], 101)
	var b: Battle = Battle.new(home, away, {}, {"ai": true, "hand": ["freeze", "meteor"]}, seed_value, 6)
	return JSON.stringify(b.run_to_end())

func test_determinism() -> void:
	section("детерминизм")
	var a: String = _event_log(424242)
	var b: String = _event_log(424242)
	ok(a == b, "одинаковое зерно → одинаковый журнал событий (%d байт)" % a.length())
	var c: String = _event_log(424243)
	ok(a != c, "другое зерно → другой бой")

func test_save_load() -> void:
	section("сохранение/загрузка")
	var m: Match = Match.new(31)
	m.auto_player = true
	m.new_game("hard")
	for i in 3:
		m.start_battle()
		m.finish_battle()
		m.next_round()
	var js: String = JSON.stringify(m.save_state())
	var m2: Match = Match.new(1)
	m2.auto_player = true
	ok(m2.load_state(JSON.parse_string(js)), "загрузка")
	eq(JSON.stringify(m2.save_state()), js, "состояние совпадает после JSON")
	var uid_before: int = Rules.next_uid_value
	m.start_battle()
	var r1: Dictionary = m.finish_battle()
	var s1: String = JSON.stringify(m.save_state())
	Rules.next_uid_value = uid_before
	m2.start_battle()
	var r2: Dictionary = m2.finish_battle()
	eq(JSON.stringify(m2.save_state()), s1, "загруженная партия продолжается так же")
	eq(r1["outcome"], r2["outcome"], "исход раунда")

# ---------------------------------------------------------------

## Партия ИИ против ИИ (Match.auto_player), тот же порядок случайностей, что simGame() в js_parity.js.
func sim_game(seed_value: int) -> Dictionary:
	var m: Match = Match.new(seed_value)
	m.auto_player = true
	m.new_game("normal")
	var trace: Array = []
	var battles: Array = []
	var min_p: int = 0
	var min_e: int = 0
	while true:
		var b: Battle = m.start_battle()
		var hp_i: int = D.HAND_ORDER.find(b.team_hand("home"))
		var he_i: int = D.HAND_ORDER.find(b.team_hand("away"))
		while not b.over():
			b.step()
		var r: Dictionary = m.finish_battle(b.result())
		battles.append({"hp": hp_i, "he": he_i, "outcome": r["outcome"]})
		trace.append("%d-%d" % [int(m.p["hp"]), int(m.ai["hp"])])
		min_p = mini(min_p, int(m.p["hp"]) - int(m.ai["hp"]))
		min_e = mini(min_e, int(m.ai["hp"]) - int(m.p["hp"]))
		if m.phase == "over" or m.round_n >= 60:
			break
		m.next_round()
	var winner: String = "p" if int(m.p["hp"]) > int(m.ai["hp"]) else ("e" if int(m.p["hp"]) < int(m.ai["hp"]) else "draw")
	return {"seed": seed_value, "rounds": m.round_n, "hp_p": int(m.p["hp"]), "hp_ai": int(m.ai["hp"]), "winner": winner,
		"trace": " ".join(trace), "battles": battles, "min_p": min_p, "min_e": min_e}

func _battle_case(cs: Dictionary) -> Dictionary:
	var b: Battle = Battle.new(_board(cs["home"], 1), _board(cs["away"], 101), {}, {"ai": true, "hand": cs["away_hand"]}, int(cs["seed"]), int(cs["round"]))
	var sched: Dictionary = {}
	for sp: Dictionary in cs["spells"]:
		var k: int = int(sp["after"])
		if not sched.has(k):
			sched[k] = []
		(sched[k] as Array).append(sp)
	var done: int = 0
	while not b.over():
		for sp: Dictionary in sched.get(done, []):
			var side: String = sp["side"]
			var tt: Variant = D.MAGIC[sp["key"]]["t"]
			var uid: int = -1
			if tt != null:
				var tside: String = side if tt == "ally" else Battle.other(side)
				uid = (1 if tside == "home" else 101) + int(sp["lane"])
			b.queue_spell(side, sp["key"], uid)
		b.step()
		done += 1
	var parts: Array = []
	for c: Dictionary in b.units():
		parts.append("%d:%d/%d/%d/%d/%d" % [c["slot"], c["hp"], c["shield"], c["atk"], c["mana"], 1 if c["alive"] else 0])
	return {"name": cs["name"], "outcome": b.result()["outcome"], "steps": b.step_n, "units": " ".join(parts)}

func test_parity() -> void:
	section("сверка с JS (web/index.html)")
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/parity_cases.json"))
	if not cases is Dictionary:
		ok(false, "нет tests/parity_cases.json")
		return
	var js: Variant = null
	if FileAccess.file_exists("res://tests/parity_js.json"):
		js = JSON.parse_string(FileAccess.get_file_as_string("res://tests/parity_js.json"))
	else:
		print("   (нет tests/parity_js.json — запустите node godot/tests/js_parity.js; печатаю только свои результаты)")
	var i: int = 0
	for cs: Dictionary in cases["battles"]:
		var g: Dictionary = _battle_case(cs)
		print("   бой %s: %s, ходов %d" % [g["name"], g["outcome"], g["steps"]])
		if js is Dictionary:
			var j: Dictionary = js["battles"][i]
			eq(g["outcome"], j["outcome"], "исход боя " + g["name"])
			eq(g["steps"], int(j["steps"]), "ходов в бою " + g["name"])
			eq(g["units"], j["units"], "итоговые ОЗ/щиты/АТК/мана " + g["name"])
		i += 1
	i = 0
	var same: int = 0
	for sd: Variant in cases["game_seeds"]:
		var g: Dictionary = sim_game(int(sd))
		if js is Dictionary:
			var j: Dictionary = js["games"][i]
			var match_ok: bool = g["rounds"] == int(j["rounds"]) and g["trace"] == j["trace"]
			ok(match_ok, "партия seed=%d: GD %d раундов %d-%d | JS %d раундов %d-%d" % [int(sd), g["rounds"], g["hp_p"], g["hp_ai"], int(j["rounds"]), int(j["hp_p"]), int(j["hp_ai"])])
			if match_ok:
				same += 1
		i += 1
	if js is Dictionary:
		print("   партий ИИ-против-ИИ, совпавших с JS раунд в раунд: %d из %d" % [same, (cases["game_seeds"] as Array).size()])

func test_simulation() -> void:
	section("симуляция %d партий ИИ против ИИ" % sim_games)
	var rounds: int = 0
	var stronger: int = 0
	var decided: int = 0
	var behind: int = 0
	var comebacks: int = 0
	for sd in range(1, sim_games + 1):
		var g: Dictionary = sim_game(sd)
		rounds += int(g["rounds"])
		for bt: Dictionary in g["battles"]:
			if bt["hp"] != bt["he"] and bt["outcome"] != "draw":
				decided += 1
				if (int(bt["hp"]) > int(bt["he"])) == (bt["outcome"] == "win"):
					stronger += 1
		if int(g["min_p"]) <= -20 or int(g["min_e"]) <= -20:
			behind += 1
		if (g["winner"] == "p" and int(g["min_p"]) <= -20) or (g["winner"] == "e" and int(g["min_e"]) <= -20):
			comebacks += 1
	var avg: float = float(rounds) / sim_games
	var sw: float = 100.0 * stronger / maxi(1, decided)
	var cb: float = 100.0 * comebacks / maxi(1, behind)
	print("   средняя длина партии: %.2f раунда" % avg)
	print("   более сильная рука побеждает: %.1f%% из %d решённых боёв с разными руками" % [sw, decided])
	print("   камбэки (победитель отставал на 20+ ОЗ): %d из %d партий с таким отставанием (%.1f%%)" % [comebacks, behind, cb])
	if FileAccess.file_exists("res://tests/parity_js.json"):
		var js: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/parity_js.json"))
		if js is Dictionary and int(js["stats"]["games"]) == sim_games:
			var st: Dictionary = js["stats"]
			print("   JS: %.2f раунда, сильная рука %.1f%%, камбэки %.1f%%" % [float(st["avg_rounds"]), float(st["stronger_hand_win_pct"]), float(st["comeback_pct_of_deficit_games"])])
			ok(absf(avg - float(st["avg_rounds"])) < 1e-9 and absf(sw - float(st["stronger_hand_win_pct"])) < 1e-9 and absf(cb - float(st["comeback_pct_of_deficit_games"])) < 1e-9, "статистика совпадает с JS")
	ok(avg > 9.0 and avg < 13.5, "средняя длина ~11 раундов")
	ok(sw > 52.0 and sw < 65.0, "сильная рука выигрывает ~55-62%")
	ok(cb > 30.0 and cb < 65.0, "камбэки примерно в половине партий")
