extends SceneTree
## Тесты дополнений (легенды, Страж арены, награды) — headless:
##   Godot --headless --path godot --script res://tests/test_extras.gd [-- --games=200]
## Базовый баланс проверяет test_core.gd (там extras выключены).

const D = preload("res://scripts/core/data.gd")

var checks: int = 0
var fails: int = 0
var sim_games: int = 200

func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			sim_games = int(a.substr(8))
	var t0: int = Time.get_ticks_msec()
	test_data()
	test_shop_never_legends()
	test_hands_and_legend_limit()
	test_frostbreath()
	test_phoenix()
	test_aegis()
	test_grove()
	test_jest()
	test_monster_rounds()
	test_rewards()
	test_monster_damage()
	test_ai_rewards()
	test_save_load()
	test_determinism()
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

func U(id: String, star: int = 1, items: Array = []) -> Dictionary:
	var u: Dictionary = Rules.new_unit(id, star)
	u["items"] = items.duplicate()
	return u

func board(ids: Array, base: int) -> Array:
	var out: Array = []
	for lane in 5:
		var id: Variant = ids[lane] if lane < ids.size() else null
		out.append(null if id == null else {"uid": base + lane, "id": id, "star": 1, "items": [], "fed": null})
	return out

func types(ev: Array) -> Array:
	return ev.map(func(e: Dictionary) -> String: return e["t"])

## Боец slot копит полную ману и ходит первым в линии; возвращает события первого хода.
func cast_now(b: Battle, slot: int) -> Array:
	var c: Dictionary = b.unit(slot)
	c["mana"] = c["mm"]
	return b.step()

func find_ev(ev: Array, f: Callable) -> Array:
	return ev.filter(f)

# ---------------------------------------------------------------

func test_data() -> void:
	section("данные: легенды, монстры, тексты, ранги")
	eq(D.LEGENDS.size(), 5, "5 легенд")
	for id: String in D.LEGENDS:
		var d: Dictionary = D.HEROES[id]
		eq(int(d["c"]), 6, "легенда %s стоит 6" % id)
		ok(D.ab_desc(id, 1) != "", "текст способности %s" % id)
		ok(not D.BASE_HEROES.has(id), "%s не в BASE_HEROES" % id)
		ok(FileAccess.file_exists("res://assets/portraits/hero_%s.png" % id), "портрет %s" % id)
	var elems: Dictionary = {}
	for id: String in D.LEGENDS:
		elems[D.LEGENDS[id]["s"]] = true
	eq(elems.size(), 4, "легенды покрывают все 4 стихии")
	for id: String in D.MONSTERS:
		ok(D.HEROES.has(id) and D.ab_desc(id, 1) != "", "монстр %s в справочнике и с текстом" % id)
		ok(FileAccess.file_exists("res://assets/portraits/hero_%s.png" % id), "портрет %s" % id)
	eq(D.HEROES.size(), D.BASE_HEROES.size() + D.LEGENDS.size() + D.MONSTERS.size(), "HEROES = база + легенды + монстры")
	eq(D.HEROES.keys().slice(0, D.BASE_HEROES.size()), D.BASE_HEROES.keys(), "порядок базовых героев не изменился")
	# правило рангов: обычных ≤ 3 на ранг; с учётом «одна легенда на поле» ≤ 3 на ранг на поле
	var per: Dictionary = {}
	for id: String in D.BASE_HEROES:
		per[int(D.BASE_HEROES[id]["r"])] = int(per.get(int(D.BASE_HEROES[id]["r"]), 0)) + 1
	var worst: int = 0
	for r: int in per:
		var legs: int = 0
		for id: String in D.LEGENDS:
			if int(D.LEGENDS[id]["r"]) == r and not D.LEGENDS[id].has("wild"):
				legs += 1
		worst = maxi(worst, int(per[r]) + mini(legs, Rules.LEGEND_BOARD_MAX))
	ok(worst <= 3, "на поле не больше 3 карт одного ранга без Джокера (макс. %d)" % worst)
	# автозагрузка Data (экземпляр узла) видит тот же справочник
	var inst: Node = load("res://scripts/core/data.gd").new()
	ok(inst.HEROES.has("phoenix") and inst.HEROES.has("m_golem"), "Data.HEROES через экземпляр видит легенды и монстров")
	inst.free()
	eq(Rules.rank_label(0), "★", "ранг Шута")

func test_shop_never_legends() -> void:
	section("легенды и монстры не выпадают в магазине (20 000+ бросков)")
	var rng: Rng = Rng.new(2024)
	var bad: int = 0
	var n: int = 0
	for i in 20000:
		var id: String = Rules.roll_id(1 + i % 8, rng)
		n += 1
		if not D.BASE_HEROES.has(id):
			bad += 1
	# подсказки («Козырь в рукаве») при легендах на поле и на скамье
	var side: Dictionary = Rules.new_side()
	side["board"][0] = U("frostdragon")
	side["board"][1] = U("archangel")
	side["bench"][0] = U("phoenix")
	side["bench"][1] = U("madjester")
	side["bench"][2] = U("m_golem")
	side["hp"] = 30
	side["streak"] = -5
	for i in 4000:
		for id: String in Rules.roll_shop(1 + i % 8, side, rng):
			n += 1
			if not D.BASE_HEROES.has(id):
				bad += 1
		var h: String = Rules.help_id(1 + i % 8, side, rng)
		if h != "" and not D.BASE_HEROES.has(h):
			bad += 1
	eq(bad, 0, "ни одной легенды/монстра из %d бросков" % n)

func test_hands_and_legend_limit() -> void:
	section("покерные руки с легендами, лимит одной легенды")
	eq(Rules.eval_units([U("madjester"), U("cutpurse"), U("leech")]), "three", "Шут = Джокер: пара → тройка")
	eq(Rules.eval_units([U("madjester"), U("cutpurse"), U("leech"), U("spider")]), "four", "каре с Шутом-Джокером")
	eq(Rules.eval_units([U("tyrant"), U("plaguelord"), U("archangel")]), "three", "K: 2 обычных + легенда = тройка")
	eq(Rules.eval_units([U("guildkiller"), U("guildmaster"), U("spadequeen"), U("frostdragon"), U("reaper")]), "flush", "Лёд 10-J-Q-A-A не роял")
	# Match.move: вторая легенда на поле запрещена, замена легенды на легенду — можно
	var m: Match = Match.new(3, true)
	m.new_game("normal")
	m.p["level"] = 5
	m.p["board"] = [U("frostdragon"), U("cutpurse"), null, null, null]
	m.p["bench"] = [U("phoenix"), U("leech"), null, null, null, null]
	ok(not m.move("bench", 0, "board", 2)["ok"], "вторая легенда на пустое место — нельзя")
	ok(not m.move("bench", 0, "board", 1)["ok"], "вторая легенда вместо обычного героя — нельзя")
	ok(m.move("bench", 0, "board", 0)["ok"] and m.p["board"][0]["id"] == "phoenix", "легенда вместо легенды — можно")
	ok(m.move("bench", 1, "board", 3)["ok"], "обычный герой — как раньше")
	# ИИ не ставит двух легенд
	var s: Dictionary = Rules.new_side()
	s["level"] = 8
	s["bench"] = [U("frostdragon"), U("phoenix"), U("archangel"), U("cutpurse"), U("leech"), U("spider")]
	Ai.arrange(s)
	eq(Rules.legend_count(Rules.board_units(s)), 1, "Ai.arrange: одна легенда на поле")
	eq(Rules.board_count(s), 4, "остальные места заняты обычными героями")

func test_frostbreath() -> void:
	section("Ледяной дракон: Ледяное дыхание")
	var b: Battle = Battle.new(board([null, null, "frostdragon"], 1), board(["cutpurse", "leech", "spider", "sellsword"], 101), {}, {}, 7, 5)
	for sl in [5, 6, 7, 8]:
		b.unit(sl)["mana"] = 40
	var ev: Array = cast_now(b, 2)
	ok(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "cast" and e["ab"] == "frostbreath").size() == 1, "событие cast frostbreath")
	eq(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "hit" and e["src"] == 2 and e["kind"] == "ability").size(), 4, "бьёт всех 4 врагов")
	eq(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "stun" and e["kind"] == "ability").size(), 4, "замораживает всех")
	var mana_ev: Array = find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "mana" and e["kind"] == "ability")
	var halves: bool = mana_ev.size() == 4
	for me: Dictionary in mana_ev:
		var hits: Array = find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "hit" and e["src"] == 2 and e["tgt"] == me["u"])
		halves = halves and hits.size() == 1 and int(me["mana"]) == floori(int(hits[0]["mana"]) / 2.0)
	ok(halves, "сжигает половину маны после удара")
	var skips: int = 0
	for e: Dictionary in ev + b.step():
		if e["t"] == "skip":
			skips += 1
	eq(skips, 4, "все замороженные пропускают ход")

func test_phoenix() -> void:
	section("Феникс: Пламя возрождения и восстание из пепла")
	var b: Battle = Battle.new(board([null, null, "phoenix"], 1), board([null, "cutpurse", "leech", "spider"], 101), {}, {}, 9, 5)
	var ev: Array = cast_now(b, 2)
	ok(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "cast" and e["ab"] == "phoenix").size() == 1, "событие cast phoenix")
	eq(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "poison" and e["kind"] == "ability").size(), 3, "поджигает цель и соседей")
	# восстание: ставим 1 ОЗ, следующий удар убивает
	var ph: Dictionary = b.unit(2)
	ph["hp"] = 1
	ph["shield"] = 0
	var all: Array = []
	for i in 3:
		all.append_array(b.step())
	var death_i: int = -1
	var reb_i: int = -1
	for i in all.size():
		var e: Dictionary = all[i]
		if e["t"] == "death" and e["u"] == 2 and death_i < 0:
			death_i = i
		if e["t"] == "revive" and e["u"] == 2 and e["kind"] == "rebirth":
			reb_i = i
	ok(death_i >= 0 and reb_i == death_i + 1, "revive kind=rebirth сразу после death")
	ok(int(ph.get("rebirth", 1)) == 0, "возрождение израсходовано")
	ph["hp"] = 1
	ph["shield"] = 0
	var ev2: Array = b.run_to_end()
	ok(find_ev(ev2, func(e: Dictionary) -> bool: return e["t"] == "revive" and e["u"] == 2).is_empty(), "второй раз не восстаёт")

func test_aegis() -> void:
	section("Архангел: Небесный покров")
	var b: Battle = Battle.new(board(["cutpurse", null, "archangel", "leech"], 1), board(["spider", null, "nun"], 101), {}, {}, 11, 5)
	b.unit(0)["poison"] = [{"d": 30, "n": 3}]
	b.unit(0)["hp"] = 100
	b.unit(3)["stun"] = 1
	b.unit(3)["hp"] = 100
	var ev: Array = cast_now(b, 2)
	ok(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "cast" and e["ab"] == "aegis").size() == 1, "событие cast aegis")
	eq(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "shield" and e["kind"] == "ability").size(), 3, "щит всем союзникам")
	ok(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "heal" and e["kind"] == "ability").size() >= 2, "лечение раненых")
	var cl: Array = find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "cleanse")
	ok(cl.size() == 2 and (b.unit(0)["poison"] as Array).is_empty(), "снят яд и оглушение")

func test_grove() -> void:
	section("Древний энт: Зов леса (призыв / +ОЗ)")
	var b: Battle = Battle.new(board([null, null, "ancientent"], 1), board(["cutpurse", "leech", "spider"], 101), {}, {}, 13, 5)
	var ev: Array = cast_now(b, 2)
	var sm: Array = find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "summon")
	ok(sm.size() == 1 and sm[0]["id"] == "m_sapling" and (int(sm[0]["lane"]) == 1 or int(sm[0]["lane"]) == 3) and not sm[0]["replaced"], "Росток в соседней пустой линии")
	var sl: int = int(sm[0]["u"])
	ok(b.units().any(func(c: Dictionary) -> bool: return c["slot"] == sl and c["id"] == "m_sapling" and c["alive"]), "Росток в units()")
	var acted: bool = false
	for e: Dictionary in b.step():
		if (e["t"] == "attack" or e["t"] == "cast") and e["u"] == sl:
			acted = true
	ok(acted, "Росток ходит со следующего хода")
	var res: Dictionary = b.result()
	var score_ok: bool = true
	for s: Dictionary in res["survivors_home"]:
		if s["id"] == "m_sapling" and not s.get("summoned", false):
			score_ok = false
	ok(score_ok and Rules.survivor_score([{"id": "m_sapling", "star": 1, "summoned": true}]) == 0, "призванные не дают очков урона")
	# полный стол — +ОЗ всем
	var b2: Battle = Battle.new(board(["cutpurse", "leech", "ancientent", "spider", "nun"], 1), board(["sellsword"], 101), {}, {}, 13, 5)
	var hp0: int = int(b2.unit(0)["max_hp"])
	var gain: int = D.r(float(b2.unit(2)["atk"]) * 2.5)
	var ev2: Array = cast_now(b2, 2)
	var bf: Array = find_ev(ev2, func(e: Dictionary) -> bool: return e["t"] == "buff" and e["stat"] == "hp")
	eq(bf.size(), 5, "+ОЗ всем 5 союзникам")
	eq(int(b2.unit(0)["max_hp"]), hp0 + gain, "макс. ОЗ выросли на АТК×2.5")

func test_jest() -> void:
	section("Безумный шут: Смертельная шутка")
	var b: Battle = Battle.new(board([null, null, "madjester"], 1), board(["cutpurse", "leech", "spider", "sellsword", "nun"], 101), {}, {}, 17, 5)
	var ev: Array = cast_now(b, 2)
	ok(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "cast" and e["ab"] == "jest").size() == 1, "событие cast jest")
	eq(find_ev(ev, func(e: Dictionary) -> bool: return e["t"] == "hit" and e["src"] == 2 and e["kind"] == "ability").size(), 3, "три удара")
	var stuns: int = 0
	for sd in range(100, 140):
		var bb: Battle = Battle.new(board([null, null, "madjester"], 1), board(["gargoyle", "blackknight", "tyrant"], 101), {}, {}, sd, 5)
		for e: Dictionary in cast_now(bb, 2):
			if e["t"] == "stun" and e["kind"] == "ability":
				stuns += 1
	ok(stuns > 30 and stuns < 90, "оглушение примерно в половине ударов (%d из 120)" % stuns)

func _monster_match(seed_value: int) -> Match:
	var m: Match = Match.new(seed_value, true)
	m.new_game("normal")
	return m

func test_monster_rounds() -> void:
	section("Страж арены: раунды 5/10/15")
	var m: Match = _monster_match(21)
	ok(not m.is_monster_round(), "раунд 1 — обычный")
	ok(m.is_monster_round(5) and m.is_monster_round(10) and m.is_monster_round(15) and not m.is_monster_round(4) and not m.is_monster_round(11), "каждый 5-й раунд")
	var off: Match = Match.new(21)
	off.new_game("normal")
	ok(not off.is_monster_round(5), "без extras Стража нет")
	var sizes: Array = []
	for r: int in [5, 10, 15, 20]:
		var mi: Dictionary = Match.monster_info(r)
		var n: int = 0
		for u: Variant in mi["board"]:
			if u != null:
				n += 1
				ok(D.MONSTERS.has(u["id"]), "в отряде только монстры")
		sizes.append(n)
		ok(str(mi["title"]).begins_with("Страж арены: "), "название Стража (%s)" % mi["title"])
	eq(sizes, [3, 4, 5, 5], "размер отряда растёт")
	ok(Rules.stats(Match.monster_info(20)["board"][2])["hp"] > Rules.stats(Match.monster_info(5)["board"][2])["hp"], "сила растёт с раундом (голем 20 > голем 5)")
	m.round_n = 5
	m.p["board"] = [U("cutpurse"), U("leech"), null, null, null]
	m.p["hp"] = 50
	ok(not m.can_allin() and not m.toggle_allin()["ok"], "ва-банк против Стража недоступен")
	var b: Battle = m.start_battle()
	ok(b != null and m.phase == "battle", "бой со Стражем начат")
	var away: Array = b.units().filter(func(c: Dictionary) -> bool: return c["side"] == "away")
	ok(away.size() == 3 and away.all(func(c: Dictionary) -> bool: return D.MONSTERS.has(c["id"])), "противник — монстры")
	eq(str(b.infos["away"]["name"]), "Страж арены: Каменный голем", "имя противника")
	ok(not m.ai_monster_result.is_empty(), "соперник сразился со своим Стражем")
	var r: Dictionary = m.finish_battle()
	ok(r["monster"] and r.has("ai_monster"), "результат помечен как бой со Стражем")
	eq(int(m.ai["streak"]), 0, "серия соперника не изменилась")

func test_rewards() -> void:
	section("награды: Страж, серии 3/5, выбор")
	var m: Match = _monster_match(33)
	m.round_n = 5
	m.p["board"] = [U("cutpurse"), null, null, null, null]
	m.start_battle()
	m.ai_monster_result = {"outcome": "away", "survivors_home": [], "survivors_away": []}
	var hp_ai: int = int(m.ai["hp"])
	var r: Dictionary = m.finish_battle({"outcome": "home", "survivors_home": [{"id": "cutpurse", "star": 1}], "survivors_away": []})
	eq(r["outcome"], "win", "победа над Стражем")
	eq(r["dmg_p"], 0, "без урона")
	ok(r["reward"] and m.pending_reward.size() == 3, "3 оффера")
	eq(m.pending_reward[0]["type"], "legend", "первый оффер — легенда")
	var tps: Dictionary = {}
	for o: Dictionary in m.pending_reward:
		tps[o["type"]] = int(tps.get(o["type"], 0)) + 1
		ok(str(o.get("title", "")) != "" and str(o.get("desc", "")) != "", "у оффера есть title/desc")
	eq(int(tps.get("legend", 0)), 1, "легенда ровно одна")
	eq(tps.size(), 3, "типы офферов разные")
	eq(int(m.ai["hp"]), hp_ai - Match.monster_damage(5, m.ai_monster_result), "соперник проиграл своему Стражу: половина урона")
	ok(not m.next_round(), "next_round ждёт выбора награды")
	var lid: String = m.pending_reward[0]["id"]
	var c: Dictionary = m.choose_reward(0)
	ok(c["ok"] and Rules.owns_id(m.p, lid), "легенда %s получена" % lid)
	ok(m.pending_reward.is_empty() and not m.choose_reward(0)["ok"], "повторно выбрать нельзя")
	ok(m.next_round(), "после выбора — следующий раунд")
	# легенда, которая уже есть, не предлагается
	var seen_dup: bool = false
	for i in 30:
		for o: Dictionary in m._gen_offers(m.p, true):
			if o["type"] == "legend" and o["id"] == lid:
				seen_dup = true
	ok(not seen_dup, "свою легенду повторно не предлагают")
	# серия: 3-я победа подряд
	m = _monster_match(34)
	m.round_n = 3
	m.phase = "battle"
	m.p["streak"] = 2
	r = m.finish_battle({"outcome": "home", "survivors_home": [], "survivors_away": []})
	ok(r["reward"] and m.pending_reward.size() == 3, "серия 3 → награда")
	ok(m.pending_reward.all(func(o: Dictionary) -> bool: return o["type"] != "legend"), "за серию легенд нет")
	var g: int = int(m.p["gold"])
	var gi: int = -1
	for i in 3:
		if m.pending_reward[i]["type"] == "gold":
			gi = i
	ok(m.choose_reward(gi)["ok"] and int(m.p["gold"]) == g + 6, "золото +6")
	m.phase = "battle"
	r = m.finish_battle({"outcome": "home", "survivors_home": [], "survivors_away": []})
	ok(not r["reward"], "серия 4 → без награды")
	m.phase = "battle"
	r = m.finish_battle({"outcome": "home", "survivors_home": [], "survivors_away": []})
	ok(r["reward"], "серия 5 → награда")
	var hi: int = -1
	var mi: int = -1
	for i in 3:
		if m.pending_reward[i]["type"] == "hero": hi = i
		if m.pending_reward[i]["type"] == "magic": mi = i
	var hid: String = m.pending_reward[hi]["id"]
	ok(int(D.HEROES[hid]["c"]) >= 3 and int(D.HEROES[hid]["c"]) <= 4, "герой стоимостью 3–4")
	var hres: Dictionary = m.choose_reward(hi)
	ok(hres["ok"] and int(hres["unit"]["star"]) >= 2, "герой ★★ получен")
	# магия: 2 карты в руку
	m.phase = "battle"
	m.p["streak"] = 2
	m.p["hand"] = []
	m.finish_battle({"outcome": "home", "survivors_home": [], "survivors_away": []})
	for i in 3:
		if m.pending_reward[i]["type"] == "magic": mi = i
	var keys: Array = m.pending_reward[mi]["keys"]
	m.choose_reward(mi)
	eq(m.p["hand"], keys, "2 карты магии в руке")
	# без extras наград нет
	var off: Match = Match.new(34)
	off.new_game("normal")
	off.phase = "battle"
	off.p["streak"] = 2
	var ro: Dictionary = off.finish_battle({"outcome": "home", "survivors_home": [], "survivors_away": []})
	ok(not ro.has("reward") and off.pending_reward.is_empty(), "extras=false: наград нет, результат прежний")

func test_monster_damage() -> void:
	section("поражение от Стража: половина урона, серия не меняется")
	var m: Match = _monster_match(41)
	m.round_n = 10
	m.p["streak"] = -2
	m.p["board"] = [U("cutpurse"), null, null, null, null]
	m.start_battle()
	var surv: Array = [{"id": "m_bonedragon", "star": 2}, {"id": "m_spectre", "star": 2}]   # 2+1 + 2 = 5
	var hp0: int = int(m.p["hp"])
	var r: Dictionary = m.finish_battle({"outcome": "away", "survivors_home": [], "survivors_away": surv})
	var full: int = Rules.round_damage(Rules.base_damage(10), 5)   # min(18, R((4+5)*1.5)=14) = 14
	eq(r["dmg_p"], D.r(full / 2.0), "половина урона (%d из %d)" % [r["dmg_p"], full])
	eq(int(m.p["hp"]), hp0 - int(r["dmg_p"]), "ОЗ игрока")
	eq(int(m.p["streak"]), -2, "серия не изменилась")
	ok(m.pending_reward.is_empty(), "награды нет")
	ok(m.next_round() and m.free_roll == 1, "дальше как обычно")

func test_ai_rewards() -> void:
	section("ИИ выбирает награду сам")
	var m: Match = _monster_match(51)
	m.round_n = 5
	m.start_battle()
	m.ai_monster_result = {"outcome": "home", "survivors_home": [], "survivors_away": []}
	var r: Dictionary = m.finish_battle({"outcome": "away", "survivors_home": [], "survivors_away": []})
	ok(not (r["ai_reward"] as Dictionary).is_empty(), "соперник получил награду")
	eq(r["ai_reward"]["type"], "legend", "без легенды ИИ берёт легенду")
	ok(Rules.owns_id(m.ai, r["ai_reward"]["id"]), "легенда у соперника")
	eq(m.reward_log.size(), 1, "запись в reward_log")
	eq(int(m.ai["hp"]), 100, "победивший Стража соперник без урона")
	# Ai.choose_reward: с легендой на руках предпочитает другое
	var s: Dictionary = Rules.new_side()
	s["bench"][0] = U("phoenix")
	var offers: Array = [{"type": "legend", "id": "archangel"}, {"type": "gold", "amount": 6}, {"type": "magic", "keys": ["heal", "bless"]}]
	ok(Ai.choose_reward(s, offers) != 0, "вторая легенда не в приоритете")
	# auto_player выбирает сам
	var m2: Match = _monster_match(52)
	m2.auto_player = true
	m2.phase = "battle"
	m2.p["streak"] = 2
	m2.finish_battle({"outcome": "home", "survivors_home": [], "survivors_away": []})
	ok(m2.pending_reward.is_empty() and m2.reward_log.size() == 1 and m2.next_round(), "auto_player выбрал награду сам")

func test_save_load() -> void:
	section("сохранение с наградой")
	var m: Match = _monster_match(61)
	m.phase = "battle"
	m.p["streak"] = 2
	m.finish_battle({"outcome": "home", "survivors_home": [], "survivors_away": []})
	var js: String = JSON.stringify(m.save_state())
	var m2: Match = Match.new(1)
	ok(m2.load_state(JSON.parse_string(js)), "загрузка")
	ok(m2.extras and m2.pending_reward.size() == 3, "extras и офферы восстановлены")
	eq(JSON.stringify(m2.save_state()), js, "состояние совпадает")

# ---------------------------------------------------------------

func sim_game(seed_value: int) -> Dictionary:
	var m: Match = Match.new(seed_value, true)
	m.auto_player = true
	m.new_game("normal")
	var trace: Array = []
	var mon: Array = []   # [tier, p_win, ai_win]
	while true:
		var b: Battle = m.start_battle()
		while not b.over():
			b.step()
		var r: Dictionary = m.finish_battle(b.result())
		trace.append("%d-%d" % [int(m.p["hp"]), int(m.ai["hp"])])
		if r.get("monster", false):
			mon.append([floori(m.round_n / 5.0), r["outcome"] == "win", r["ai_monster"] == "win"])
		if m.phase == "over" or m.round_n >= 60:
			break
		if not m.pending_reward.is_empty():
			ok(false, "auto_player не выбрал награду (seed %d, раунд %d)" % [seed_value, m.round_n])
			m.choose_reward(0)
		m.next_round()
	return {"rounds": m.round_n, "trace": " ".join(trace), "log": m.reward_log.duplicate(true), "mon": mon}

func test_determinism() -> void:
	section("детерминизм с extras")
	var a: Dictionary = sim_game(777)
	var b: Dictionary = sim_game(777)
	ok(a["trace"] == b["trace"] and JSON.stringify(a["log"]) == JSON.stringify(b["log"]), "одинаковое зерно → одинаковая партия (%d раундов)" % a["rounds"])
	ok(sim_game(778)["trace"] != a["trace"], "другое зерно → другая партия")

func test_simulation() -> void:
	section("симуляция %d партий ИИ против ИИ с дополнениями" % sim_games)
	var rounds: int = 0
	var lens: Dictionary = {}
	var leg_offered: int = 0
	var leg_picked: int = 0
	var picks: Dictionary = {}
	var by_id: Dictionary = {}
	var games_with_legend: int = 0
	var mon_n: Dictionary = {}
	var mon_w: Dictionary = {}
	for sd in range(1, sim_games + 1):
		var g: Dictionary = sim_game(sd)
		rounds += int(g["rounds"])
		lens[g["rounds"]] = int(lens.get(g["rounds"], 0)) + 1
		var had: bool = false
		for e: Dictionary in g["log"]:
			picks[e["type"]] = int(picks.get(e["type"], 0)) + 1
			if e["source"] == "monster":
				leg_offered += 1
			if e["type"] == "legend":
				leg_picked += 1
				had = true
				by_id[e["id"]] = int(by_id.get(e["id"], 0)) + 1
		if had:
			games_with_legend += 1
		for x: Array in g["mon"]:
			var t: int = x[0]
			mon_n[t] = int(mon_n.get(t, 0)) + 2
			mon_w[t] = int(mon_w.get(t, 0)) + (1 if x[1] else 0) + (1 if x[2] else 0)
	var avg: float = float(rounds) / sim_games
	print("   средняя длина партии: %.2f раунда" % avg)
	var ks: Array = lens.keys()
	ks.sort()
	print("   распределение длины: ", ", ".join(ks.map(func(k: int) -> String: return "%d:%d" % [k, lens[k]])))
	for t: int in [1, 2, 3, 4]:
		if mon_n.has(t):
			print("   Страж тира %d (раунд %d): побед %.0f%% из %d боёв" % [t, t * 5, 100.0 * mon_w[t] / mon_n[t], mon_n[t]])
	print("   выбрано наград: ", picks)
	print("   легенд взято: %d из %d наград за Стража (%.0f%%); партий, где кто-то взял легенду: %d из %d" % [leg_picked, leg_offered, 100.0 * leg_picked / maxi(1, leg_offered), games_with_legend, sim_games])
	print("   по легендам: ", by_id)
	ok(avg >= 10.0 and avg <= 14.0, "средняя длина в пределах 10–14 раундов (%.2f)" % avg)
	ok(leg_picked > 0, "легенды берут")
