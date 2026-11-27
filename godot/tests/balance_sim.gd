extends SceneTree
## Замер баланса (не тест, просто цифры): партии ИИ против ИИ с дополнениями (Стражи, легенды, награды).
##   Godot --headless --path godot -s tests/balance_sim.gd [-- --games=300 --classic]
## --classic — старые числа (web v1.4), чтобы сравнить «до» и «после».
## Что смотрим:
##   • снежный ком: как часто выигрывает тот, кто вёл по ОЗ после 6-го раунда / первым собрал серию из 3;
##   • камбэки: победитель отставал на 20+ ОЗ;
##   • редкость: дуэли равных по золоту отрядов (дешёвые ★★/★★★ против дорогих ★).

const D = preload("res://scripts/core/data.gd")

func _init() -> void:
	var games: int = 300
	var only_duels: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
		if a == "--classic":
			Rules.classic = true
		if a.begins_with("--starm="):
			var v: PackedStringArray = a.substr(8).split(",")
			Rules.STARM_V2 = [0.0, 1.0, float(v[0]), float(v[1])]
		if a.begins_with("--lstar="):
			var v: PackedStringArray = a.substr(8).split(",")
			Rules.LEGEND_STARM = [0.0, 1.0, float(v[0]), float(v[1])]
		if a.begins_with("--rarity="):
			var v: PackedStringArray = a.substr(9).split(",")
			Rules.RARITY = [1.0, 1.0, float(v[0]), float(v[1]), float(v[2]), float(v[3])]
		if a.begins_with("--lscale="):
			Rules.LEGEND_SCALE = float(a.substr(9))
		if a.begins_with("--mscale="):
			Rules.MONSTER_SCALE = float(a.substr(9))
		if a == "--duels":
			only_duels = true
	print("Баланс: %s, партий %d, звёзды %s, редкость %s, легенды %s ×%.2f, Стражи ×%.2f" % ["классика (v1.4)" if Rules.classic else "новый", games, Rules.STARM_V2, Rules.RARITY, Rules.LEGEND_STARM, Rules.LEGEND_SCALE, Rules.MONSTER_SCALE])
	if not only_duels:
		_games(games)
	_duels()
	quit(0)

func _games(n: int) -> void:
	var rounds: int = 0
	var lead6: int = 0
	var lead6_won: int = 0
	var str3: int = 0
	var str3_won: int = 0
	var behind: int = 0
	var comebacks: int = 0
	var mon_win: Dictionary = {}
	var mon_all: Dictionary = {}
	var legend_win: int = 0
	var legend_games: int = 0
	var draws: int = 0
	for sd in range(1, n + 1):
		var m: Match = Match.new(sd * 7919 + 13, true)
		m.auto_player = true
		m.new_game("normal")
		var min_p: int = 0
		var min_e: int = 0
		var leader6: String = ""
		var first3: String = ""
		while true:
			var b: Battle = m.start_battle()
			b.run_to_end()
			var mon: bool = m.is_monster_round()
			var r: Dictionary = m.finish_battle(b.result())
			if mon:
				var t: int = int(m.monster.get("tier", 0))
				mon_all[t] = int(mon_all.get(t, 0)) + 2
				mon_win[t] = int(mon_win.get(t, 0)) + (1 if r["outcome"] == "win" else 0) + (1 if r.get("ai_monster", "") == "win" else 0)
			if not m.pending_reward.is_empty():
				m.choose_reward(Ai.choose_reward(m.p, m.pending_reward))
			min_p = mini(min_p, int(m.p["hp"]) - int(m.ai["hp"]))
			min_e = mini(min_e, int(m.ai["hp"]) - int(m.p["hp"]))
			if m.round_n == 6:
				leader6 = "p" if int(m.p["hp"]) > int(m.ai["hp"]) else ("e" if int(m.p["hp"]) < int(m.ai["hp"]) else "")
			if first3 == "":
				if int(m.p["streak"]) >= 3: first3 = "p"
				elif int(m.ai["streak"]) >= 3: first3 = "e"
			if m.phase == "over" or m.round_n >= 60:
				break
			m.next_round()
		rounds += m.round_n
		var w: String = "p" if int(m.p["hp"]) > int(m.ai["hp"]) else ("e" if int(m.p["hp"]) < int(m.ai["hp"]) else "")
		if w == "":
			draws += 1
			continue
		if leader6 != "":
			lead6 += 1
			lead6_won += 1 if leader6 == w else 0
		if first3 != "":
			str3 += 1
			str3_won += 1 if first3 == w else 0
		if min_p <= -20 or min_e <= -20:
			behind += 1
			if (w == "p" and min_p <= -20) or (w == "e" and min_e <= -20):
				comebacks += 1
		var wl: bool = Rules.legend_count(Rules.all_units(m.p if w == "p" else m.ai)) > 0
		var ll: bool = Rules.legend_count(Rules.all_units(m.ai if w == "p" else m.p)) > 0
		if wl != ll:
			legend_games += 1
			legend_win += 1 if wl else 0
	print("  средняя длина: %.1f раунда, ничьих %d" % [float(rounds) / n, draws])
	print("  лидер после 6-го раунда выигрывает: %.0f%% (%d партий)" % [100.0 * lead6_won / maxi(1, lead6), lead6])
	print("  первым собрал серию из 3 — выигрывает: %.0f%% (%d)" % [100.0 * str3_won / maxi(1, str3), str3])
	print("  камбэки (отставал на 20+ ОЗ и выиграл): %.0f%% из %d" % [100.0 * comebacks / maxi(1, behind), behind])
	print("  легенда только у одного — он выигрывает: %.0f%% (%d)" % [100.0 * legend_win / maxi(1, legend_games), legend_games])
	var ks: Array = mon_all.keys()
	ks.sort()
	for t: int in ks:
		print("  Страж тир %d: побед %.0f%% из %d боёв" % [t, 100.0 * mon_win[t] / maxi(1, mon_all[t]), mon_all[t]])

## Отряд из 5 героев данной стоимости и звезды (разные герои, без рук — ранги перемешаны).
func _team(cost: int, star: int, off: int, uid0: int) -> Array:
	var ids: Array = []
	for id: String in D.BASE_HEROES:
		if int(D.BASE_HEROES[id]["c"]) == cost:
			ids.append(id)
	var b: Array = []
	b.resize(D.BOARD_SIZE)
	for i in 5:
		b[i] = {"uid": uid0 + i, "id": ids[(i + off) % ids.size()], "star": star, "items": [], "fed": null}
	return b

func _duel(ca: int, sa: int, cb: int, sb: int) -> float:
	var won: float = 0.0
	var n: int = 0
	for off in 6:
		for sd in 8:
			var b: Battle = Battle.new(_team(ca, sa, off, 1), _team(cb, sb, off + 1, 101), {}, {}, 1000 + sd * 31 + off, 6)
			b.run_to_end()
			var o: String = b.result()["outcome"]
			won += 1.0 if o == "home" else (0.5 if o == "draw" else 0.0)
			n += 1
	return 100.0 * won / n

func _duels() -> void:
	print("  дуэли 5 на 5 (победы левого отряда):")
	for c: Array in [[1, 2, 3, 1, "★★ за 3 зол. против ★ за 3 зол."], [1, 3, 5, 1, "★★★ из 1-зол. (9) против ★ за 5 зол."], [2, 2, 5, 1, "★★ из 2-зол. (6) против ★ за 5 зол."],
			[3, 2, 5, 1, "★★ из 3-зол. (9) против ★ за 5 зол."], [1, 1, 2, 1, "★ 1 зол. против ★ 2 зол."], [3, 1, 4, 1, "★ 3 зол. против ★ 4 зол."], [4, 1, 5, 1, "★ 4 зол. против ★ 5 зол."],
			[3, 2, 3, 1, "★★ против ★ той же цены (3)"], [4, 2, 5, 2, "★★ 4 зол. против ★★ 5 зол."], [3, 3, 3, 2, "★★★ против ★★ той же цены (3)"]]:
		print("    %s: %.0f%%" % [c[4], _duel(c[0], c[1], c[2], c[3])])

	for cs: Array in [[2, 1, 1], [2, 2, 1], [3, 2, 2], [4, 2, 3]]:
		var st: int = cs[2]
		var won: float = 0.0
		var n: int = 0
		for lid: String in D.LEGENDS:
			for sd in 6:
				var a: Array = _team(cs[0], cs[1], sd, 1)
				a[2] = {"uid": 3, "id": lid, "star": st, "items": [], "fed": null}
				var b: Battle = Battle.new(a, _team(cs[0], cs[1], sd + 1, 101), {}, {}, 500 + sd, 8)
				b.run_to_end()
				var o: String = b.result()["outcome"]
				won += 1.0 if o == "home" else (0.5 if o == "draw" else 0.0)
				n += 1
		print("    легенда %s вместо одного в отряде %s за %d зол.: %.0f%%" % ["★".repeat(st), "★".repeat(cs[1]), cs[0], 100.0 * won / n])
