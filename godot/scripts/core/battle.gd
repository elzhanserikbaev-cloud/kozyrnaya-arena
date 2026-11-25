class_name Battle
extends RefCounted
## Симуляция боя — та же логика, что simulate()/act()/hit()/cast()/castSpell()/endStep() в web/index.html v1.4.0.
## Детерминирована: случайны только криты, и они берутся из Rng(seed) в том же порядке, что S.rng в сетевом JS-бою.
##
## Стороны: "home" и "away". «Домашняя» ходит первой в нечётные ходы (как S.home в JS; в соло-игре home = игрок).
## Бой длится не больше 30 ходов; если оба отряда живы после 30-го — ничья.
##
## ---------------- Ссылки на бойцов ----------------
## Каждый боец адресуется СЛОТОМ: slot = lane для home (0..4), 5 + lane для away (5..9).
## (uid карт двух игроков в сети могут совпадать, слот однозначен.) Связь слот → uid/сторона/линия — в units().
##
## ---------------- События step() ----------------
## step() возвращает Array[Dictionary], каждое событие — {"t": тип, ...}. Порядок = порядок применения в логике.
##   {t:"step", n}                                  начало хода n (1..30)
##   {t:"spell", side, key, tgt}                    заклинание key разыгрывает сторона side; tgt — слот цели или -1
##   {t:"fizzle", side, key}                        заклинание из очереди не нашло цель (сгорает, как в JS)
##   {t:"skip", u}                                  боец оглушён/заморожен и пропускает ход (stun уменьшен)
##   {t:"attack", u, tgt}                           обычная атака (выпад) u → tgt; дальше идёт "hit"
##   {t:"cast", u, tgt, ab, name}                   способность героя (ab — тип из HEROES[].ab.t, name — название); мана u обнулена
##   {t:"hit", src, tgt, amount, dmg, absorbed, crit, kind, hp, shield, mana}
##        src — слот атакующего или -1 (заклинание, яд, шипы); amount — урон до щита (после крита и округления);
##        absorbed — съедено щитом; dmg — снято ОЗ; hp/shield/mana — новые значения цели;
##        kind: "attack" | "ability" | "spell" | "poison" | "thorns"
##   {t:"death", u}                                 боец пал
##   {t:"heal", u, amount, hp, kind}                лечение (amount > 0); kind: "ability"|"spell"|"lifesteal"|"regen"|"drain"
##   {t:"shield", u, amount, shield, kind}          получен щит; kind: "ability"|"spell"
##   {t:"mana", u, mana, kind}                      мана изменилась: kind "attack" (+20 после атаки), "spell" (Зелье маны — полная)
##   {t:"stun", u, turns, kind}                     оглушение (kind "ability") или заморозка (kind "spell")
##   {t:"poison", u, dmg, turns, kind}              наложен яд (dmg за ход, turns ходов); kind "ability"|"spell"
##   {t:"poison_tick", u, amount}                   конец хода: суммарный яд; дальше идёт "hit" с kind "poison"
##   {t:"buff", u, stat:"atk", pct, atk, kind}      изменение АТК (pct: +20, +25, +60, -35 …); atk — новое значение
##   {t:"hp_set", u, hp}                            ОЗ выставлены напрямую (Кровавый пакт: −25% текущих ОЗ)
##   {t:"revive", u, hp, kind}                      боец восстал (kind "ability" — Поднять мёртвых 40%, "spell" — 50%)
##   {t:"end", outcome, steps}                      бой окончен (последнее событие последнего хода); outcome "home"|"away"|"draw"
## Попадание (hit) для мана-бара: цель всегда получает +8 маны (до максимума), даже если пала.
##
## ---------------- Прочее API ----------------
## Battle.new(home_board, away_board, home_info, away_info, seed, round)
##   board — 5 элементов Unit|null; info — {name?, ai?:bool, hand?:[ключи магии], allin?}
##   ai=true: сторона сама разыгрывает заклинания из hand на 2-м и 5-м ходу (aiCast в JS).
## queue_spell(side_tag, key, target_uid) -> bool — применится в начале следующего хода; не больше 2 заклинаний на сторону за бой.
##   (заклинания ИИ из hand в этот лимит не входят — в JS у ИИ своё ограничение: не больше 2 заклинаний в руке.)
## over(), result(), units(), unit(slot), team_hand(side), team_traits(side), spent_spells(side).

const D = preload("res://scripts/core/data.gd")

var round_n: int = 1
var step_n: int = 0
var rng: Rng
var teams: Dictionary = {"home": [], "away": []}
var infos: Dictionary = {"home": {}, "away": {}}
var team_infos: Dictionary = {"home": {}, "away": {}}
var ai_hands: Dictionary = {"home": [], "away": []}
var spent: Dictionary = {"home": [], "away": []}
var spells_used: Dictionary = {"home": 0, "away": 0}
var queued: Array = []
var _ev: Array = []
var _ended: bool = false

func _init(home_board: Array = [], away_board: Array = [], home_info: Dictionary = {}, away_info: Dictionary = {}, seed_value: int = 0, round_number: int = 1) -> void:
	round_n = round_number
	rng = Rng.new(seed_value)
	infos = {"home": home_info, "away": away_info}
	teams["home"] = _build_team(home_board, "home")
	teams["away"] = _build_team(away_board, "away")
	for tag: String in ["home", "away"]:
		var h: Variant = infos[tag].get("hand", [])
		ai_hands[tag] = (h as Array).duplicate() if h is Array else []

static func other(tag: String) -> String:
	return "away" if tag == "home" else "home"

static func slot_of(tag: String, lane: int) -> int:
	return lane + (0 if tag == "home" else 5)

# ---------- сборка отряда (buildTeam) ----------

func _build_team(board: Array, tag: String) -> Array:
	var units: Array = []
	for u: Variant in board:
		if u != null:
			units.append(u)
	var ti: Dictionary = Rules.team_info(units)
	team_infos[tag] = ti
	var H: Dictionary = D.HANDS[ti["hand"]]
	var lv: Dictionary = ti["tl"]["lv"]
	var out: Array = []
	out.resize(5)
	for lane in 5:
		var u: Variant = board[lane] if lane < board.size() else null
		if u == null:
			continue
		var d: Dictionary = D.HEROES[u["id"]]
		var st: Dictionary = Rules.stats(u)
		var it: Array = Rules.items_of(u)
		var lv_c: int = lv["C"]
		var lv_d: int = lv["D"]
		var lv_s: int = lv["S"]
		var lv_h: int = lv["H"]
		var max_hp: int = D.r(float(st["hp"]) * (1.0 + float(H["hp"]) + (0.28 if lv_c == 2 else (0.12 if lv_c == 1 else 0.0)) + 0.3 * it.count("armor")))
		var atk: int = D.r(float(st["atk"]) * (1.0 + float(H["atk"]) + (0.10 if lv_c == 2 else 0.0) + 0.25 * it.count("sword")))
		var mm: int = d["mm"]
		out[lane] = {
			"slot": slot_of(tag, lane), "uid": int(u.get("uid", 0)), "id": u["id"], "star": int(u["star"]), "side": tag, "lane": lane,
			"d": d, "max_hp": max_hp, "hp": max_hp, "atk": atk, "base_atk": atk, "mm": mm,
			"mana": D.r(float(mm) * minf(1.0, float(H["mana"]) + 0.4 * it.count("orb"))),
			"lifesteal": 0.25 * it.count("fang"), "thorns": 0.25 * it.count("thorns"),
			"shield": D.r(float(max_hp) * (0.28 if lv_d == 2 else (0.12 if lv_d == 1 else 0.0))),
			"crit": 0.1 + (0.30 if lv_s == 2 else (0.15 if lv_s == 1 else 0.0)) + 0.2 * it.count("feather"),
			"regen": 0.045 if lv_h == 2 else (0.02 if lv_h == 1 else 0.0),
			"stun": 0, "poison": [], "alive": true,
		}
	return out

# ---------- запросы ----------

func _alive(team: Array) -> bool:
	for c: Variant in team:
		if c != null and c["alive"]:
			return true
	return false

func _live(team: Array) -> Array:
	var out: Array = []
	for c: Variant in team:
		if c != null and c["alive"]:
			out.append(c)
	return out

func _adj(team: Array, lane: int) -> Array:
	var out: Array = []
	for c: Variant in team:
		if c != null and c["alive"] and absi(int(c["lane"]) - lane) <= 1:
			out.append(c)
	return out

func _find_target(c: Dictionary, foes: Array) -> Variant:
	var lane: int = c["lane"]
	if foes[lane] != null and foes[lane]["alive"]:
		return foes[lane]
	var best: Variant = null
	var bd: int = 9
	for f: Variant in foes:
		if f != null and f["alive"]:
			var dd: int = absi(int(f["lane"]) - lane)
			if dd < bd:
				bd = dd
				best = f
	return best

func over() -> bool:
	return step_n >= D.MAX_STEPS or not _alive(teams["home"]) or not _alive(teams["away"])

func outcome() -> String:
	var pa: bool = _alive(teams["home"])
	var ea: bool = _alive(teams["away"])
	if pa and not ea:
		return "home"
	if ea and not pa:
		return "away"
	return "draw"

func _survivors(tag: String) -> Array:
	var out: Array = []
	for c: Dictionary in _live(teams[tag]):
		out.append({"uid": c["uid"], "id": c["id"], "star": c["star"], "lane": c["lane"], "slot": c["slot"], "hp": c["hp"], "max_hp": c["max_hp"]})
	return out

## {outcome:"home"|"away"|"draw", survivors_home, survivors_away, score_home, score_away, steps}
## score_* — очки выживших для урона (звезда + 1 за героя стоимостью 4+), как surv() в resolve().
func result() -> Dictionary:
	var sh: Array = _survivors("home")
	var sa: Array = _survivors("away")
	return {"outcome": outcome(), "survivors_home": sh, "survivors_away": sa,
		"score_home": Rules.survivor_score(sh), "score_away": Rules.survivor_score(sa), "steps": step_n}

## Снимок для полосок: [{slot, uid, id, star, side, lane, hp, max_hp, mana, mm, shield, atk, alive, stunned, stun, poison, poison_turns}]
func units() -> Array:
	var out: Array = []
	for tag: String in ["home", "away"]:
		for c: Variant in teams[tag]:
			if c == null:
				continue
			var ps: int = 0
			var pt: int = 0
			for p: Dictionary in c["poison"]:
				ps += int(p["d"])
				pt = maxi(pt, int(p["n"]))
			out.append({"slot": c["slot"], "uid": c["uid"], "id": c["id"], "star": c["star"], "side": tag, "lane": c["lane"],
				"hp": c["hp"], "max_hp": c["max_hp"], "mana": c["mana"], "mm": c["mm"], "shield": c["shield"], "atk": c["atk"],
				"alive": c["alive"], "stunned": int(c["stun"]) > 0, "stun": c["stun"], "poison": ps, "poison_turns": pt})
	return out

func unit(slot: int) -> Variant:
	var tag: String = "home" if slot < 5 else "away"
	return teams[tag][slot % 5]

func team_hand(tag: String) -> String:
	return team_infos[tag]["hand"]

func team_traits(tag: String) -> Dictionary:
	return team_infos[tag]["tl"]

## Заклинания, которые ИИ-сторона потратила из своей руки (Match убирает их из side.hand).
func spent_spells(tag: String) -> Array:
	return spent[tag]

func spells_left(tag: String) -> int:
	return D.MAX_SPELLS_PER_BATTLE - int(spells_used[tag])

# ---------- заклинания из очереди ----------

## Заклинание применится в начале следующего хода (как в сетевом JS). target_uid — uid карты-цели
## (своей для t="ally", вражеской для t="foe"); для заклинаний без цели игнорируется.
func queue_spell(side_tag: String, key: String, target_uid: int = -1) -> bool:
	if not D.MAGIC.has(key) or D.MAGIC[key]["k"] != "spell" or over():
		return false
	if side_tag != "home" and side_tag != "away":
		return false
	if int(spells_used[side_tag]) >= D.MAX_SPELLS_PER_BATTLE:
		return false
	spells_used[side_tag] = int(spells_used[side_tag]) + 1
	queued.append({"side": side_tag, "key": key, "target": target_uid})
	return true

func _apply_queued() -> void:
	var q: Array = queued
	queued = []
	# сначала заклинания «домашней» стороны, потом гостевой (S.queued в JS)
	var ordered: Array = []
	for sp: Dictionary in q:
		if sp["side"] == "home": ordered.append(sp)
	for sp: Dictionary in q:
		if sp["side"] == "away": ordered.append(sp)
	for sp: Dictionary in ordered:
		var tag: String = sp["side"]
		var key: String = sp["key"]
		var tt: Variant = D.MAGIC[key]["t"]
		var t: Variant = null
		if tt != null:
			var team: Array = teams[tag] if tt == "ally" else teams[other(tag)]
			for c: Variant in team:
				if c != null and int(c["uid"]) == int(sp["target"]):
					t = c
			if t == null:
				_emit({"t": "fizzle", "side": tag, "key": key})
				continue
		_cast_spell(tag, key, t)

## aiCast: первое заклинание из руки, цель выбирает Ai.battle_spell_choice.
func _ai_cast(tag: String) -> void:
	var hand: Array = ai_hands[tag]
	var i: int = -1
	for j in hand.size():
		if D.MAGIC[hand[j]]["k"] == "spell":
			i = j
			break
	if i < 0:
		return
	var k: String = hand[i]
	var t: Variant = Ai.battle_spell_choice(k, _live(teams[tag]), _live(teams[other(tag)]))
	if D.MAGIC[k]["t"] != null and t == null:
		return
	hand.remove_at(i)
	(spent[tag] as Array).append(k)
	_cast_spell(tag, k, t)

# ---------- ход ----------

func _emit(e: Dictionary) -> void:
	_ev.append(e)

func step() -> Array:
	if over():
		if not _ended:
			_ended = true
			return [{"t": "end", "outcome": outcome(), "steps": step_n}]
		return []
	_ev = []
	step_n += 1
	_emit({"t": "step", "n": step_n})
	_apply_queued()
	if step_n == 2 or step_n == 5:
		for tag: String in ["home", "away"]:
			if infos[tag].get("ai", false) and (ai_hands[tag] as Array).size() > 0:
				_ai_cast(tag)
	var H: Array = teams["home"]
	var W: Array = teams["away"]
	var order: Array = []
	for l in 5:
		var a: Variant = H[l]
		var b: Variant = W[l]
		if step_n % 2 == 1:
			if a != null: order.append(a)
			if b != null: order.append(b)
		else:
			if b != null: order.append(b)
			if a != null: order.append(a)
	for c: Dictionary in order:
		if not _alive(H) or not _alive(W):
			break
		if c["alive"]:
			_act(c)
	_end_step(H)
	_end_step(W)
	if over():
		_ended = true
		_emit({"t": "end", "outcome": outcome(), "steps": step_n})
	var out: Array = _ev
	_ev = []
	return out

## Досчитать бой до конца; возвращает все события.
func run_to_end() -> Array:
	var all: Array = []
	while not _ended:
		all.append_array(step())
	return all

func _act(c: Dictionary) -> void:
	var allies: Array = teams[c["side"]]
	var foes: Array = teams[other(c["side"])]
	if int(c["stun"]) > 0:
		c["stun"] = int(c["stun"]) - 1
		_emit({"t": "skip", "u": c["slot"]})
		return
	var t: Variant = _find_target(c, foes)
	if t == null:
		return
	if int(c["mana"]) >= int(c["mm"]):
		c["mana"] = 0
		_emit({"t": "cast", "u": c["slot"], "tgt": t["slot"], "ab": c["d"]["ab"]["t"], "name": c["d"]["ab"]["n"]})
		_cast(c, t, allies, foes)
	else:
		_emit({"t": "attack", "u": c["slot"], "tgt": t["slot"]})
		_hit(c, t, float(c["atk"]), true, "attack")
		c["mana"] = mini(int(c["mm"]), int(c["mana"]) + 20)
		_emit({"t": "mana", "u": c["slot"], "mana": c["mana"], "kind": "attack"})

func _hit(src: Variant, t: Variant, amt: float, can_crit: bool, kind: String) -> int:
	if t == null or not t["alive"]:
		return 0
	var crit: bool = false
	if can_crit and src != null and rng.next() < float(src["crit"]):
		amt *= 1.75
		crit = true
	var a: int = D.r(amt)
	var dmg: int = a
	var absorbed: int = 0
	if int(t["shield"]) > 0:
		absorbed = mini(int(t["shield"]), dmg)
		t["shield"] = int(t["shield"]) - absorbed
		dmg -= absorbed
	t["hp"] = int(t["hp"]) - dmg
	t["mana"] = mini(int(t["mm"]), int(t["mana"]) + 8)
	var died: bool = int(t["hp"]) <= 0
	if died:
		t["hp"] = 0
		t["alive"] = false
	_emit({"t": "hit", "src": src["slot"] if src != null else -1, "tgt": t["slot"], "amount": a, "dmg": dmg, "absorbed": absorbed,
		"crit": crit, "kind": kind, "hp": t["hp"], "shield": t["shield"], "mana": t["mana"]})
	if died:
		_emit({"t": "death", "u": t["slot"]})
	if src != null and src["alive"] and float(src["lifesteal"]) > 0.0:
		_heal(src, a * float(src["lifesteal"]), "lifesteal")
	if src != null and src["alive"] and float(t["thorns"]) > 0.0:
		_hit(null, src, a * float(t["thorns"]), false, "thorns")
	return a

func _heal(c: Variant, amt: float, kind: String) -> int:
	if c == null or not c["alive"]:
		return 0
	var real: int = mini(D.r(amt), int(c["max_hp"]) - int(c["hp"]))
	if real > 0:
		c["hp"] = int(c["hp"]) + real
		_emit({"t": "heal", "u": c["slot"], "amount": real, "hp": c["hp"], "kind": kind})
	return real

func _add_shield(c: Dictionary, amt: float, kind: String) -> void:
	if not c["alive"]:
		return
	var s: int = D.r(amt)
	c["shield"] = int(c["shield"]) + s
	_emit({"t": "shield", "u": c["slot"], "amount": s, "shield": c["shield"], "kind": kind})

func _buff_atk(x: Dictionary, new_atk: int, pct: int, kind: String) -> void:
	x["atk"] = new_atk
	_emit({"t": "buff", "u": x["slot"], "stat": "atk", "pct": pct, "atk": new_atk, "kind": kind})

func _poison(x: Dictionary, d: int, n: int, kind: String) -> void:
	(x["poison"] as Array).append({"d": d, "n": n})
	_emit({"t": "poison", "u": x["slot"], "dmg": d, "turns": n, "kind": kind})

func _stun(x: Dictionary, turns: int, kind: String) -> void:
	x["stun"] = turns
	_emit({"t": "stun", "u": x["slot"], "turns": turns, "kind": kind})

func _ratio(x: Dictionary) -> float:
	return float(x["hp"]) / float(x["max_hp"])

func _cast(c: Dictionary, t: Dictionary, allies: Array, foes: Array) -> void:
	var type: String = c["d"]["ab"]["t"]
	var v: float = float(c["d"]["ab"]["v"])
	var P: float = float(c["atk"]) * v
	match type:
		"strike":
			_hit(c, t, P, true, "ability")
		"stun":
			_hit(c, t, P, true, "ability")
			if t["alive"]:
				_stun(t, 1, "ability")
		"cleave":
			for x: Dictionary in _adj(foes, t["lane"]):
				_hit(c, x, P, true, "ability")
		"volley":
			for x: Dictionary in _live(foes):
				_hit(c, x, P, false, "ability")
		"heal":
			var lst: Array = Rules.ssort(_live(allies), func(a: Dictionary, b: Dictionary) -> float: return _ratio(a) - _ratio(b))
			_heal(lst[0] if lst.size() > 0 else null, P, "ability")
		"healall":
			for x: Dictionary in _live(allies):
				_heal(x, P, "ability")
		"shield":
			for x: Dictionary in _adj(allies, c["lane"]):
				_add_shield(x, P, "ability")
		"shieldall":
			for x: Dictionary in _live(allies):
				_add_shield(x, P, "ability")
		"rally":
			for x: Dictionary in _live(allies):
				_buff_atk(x, D.r(float(x["atk"]) + float(x["base_atk"]) * v), D.r(v * 100.0), "ability")
		"drain":
			var dd: int = _hit(c, t, P, true, "ability")
			_heal(c, float(dd), "drain")
		"execute":
			_hit(c, t, P * 2.0 if _ratio(t) < 0.4 else P, true, "ability")
		"poison":
			for x: Dictionary in _adj(foes, t["lane"]):
				if x["alive"]:
					_poison(x, D.r(P), 3, "ability")
		"stunall":
			for x: Dictionary in _live(foes):
				_hit(c, x, P, false, "ability")
				if x["alive"]:
					_stun(x, 1, "ability")
		"reap":
			for x: Dictionary in _live(foes):
				_hit(c, x, P * 2.0 if _ratio(x) < 0.4 else P, false, "ability")
		"sunburst":
			for x: Dictionary in _live(foes):
				_hit(c, x, P, false, "ability")
			for x: Dictionary in _live(allies):
				_heal(x, float(c["atk"]), "ability")
		"plague":
			for x: Dictionary in _live(foes):
				_poison(x, D.r(P), 3, "ability")
		"raise":
			var f: Variant = null
			for x: Variant in allies:
				if x != null and not x["alive"]:
					f = x
					break
			if f != null:
				_revive(f, 0.4, "ability")
			else:
				_heal(c, P, "ability")

func _revive(c: Dictionary, frac: float, kind: String) -> void:
	c["alive"] = true
	c["hp"] = maxi(1, D.r(float(c["max_hp"]) * frac))
	c["stun"] = 0
	c["poison"] = []
	c["mana"] = 0
	_emit({"t": "revive", "u": c["slot"], "hp": c["hp"], "kind": kind})

func _cast_spell(tag: String, k: String, t: Variant) -> void:
	var allies: Array = teams[tag]
	var foes: Array = teams[other(tag)]
	if not _alive(allies) or not _alive(foes):
		return
	_emit({"t": "spell", "side": tag, "key": k, "tgt": t["slot"] if t != null else -1})
	match k:
		"fireball":
			if t == null or not t["alive"]:
				return
			_hit(null, t, float(D.spell_pow(300, round_n)), false, "spell")
		"heal":
			if t != null and t["alive"]:
				_heal(t, float(t["max_hp"]) * 0.40, "spell")
		"bless":
			for x: Dictionary in _live(allies):
				_add_shield(x, float(D.spell_pow(170, round_n)), "spell")
		"rage":
			for x: Dictionary in _live(allies):
				_buff_atk(x, D.r(float(x["atk"]) + float(x["base_atk"]) * 0.25), 25, "spell")
		"freeze":
			for x: Dictionary in _live(foes):
				_stun(x, maxi(int(x["stun"]), 1), "spell")
		"meteor":
			for x: Dictionary in _live(foes):
				_hit(null, x, float(D.spell_pow(140, round_n)), false, "spell")
		"pact":
			if t != null and t["alive"]:
				_buff_atk(t, D.r(float(t["atk"]) + float(t["base_atk"]) * 0.6), 60, "spell")
				t["hp"] = maxi(1, D.r(float(t["hp"]) * 0.75))
				_emit({"t": "hp_set", "u": t["slot"], "hp": t["hp"]})
		"curse":
			if t != null and t["alive"]:
				_buff_atk(t, maxi(1, D.r(float(t["atk"]) - float(t["base_atk"]) * 0.35)), -35, "spell")
		"chain":
			if t == null or not t["alive"]:
				return
			for x: Dictionary in _adj(foes, t["lane"]):
				_hit(null, x, float(D.spell_pow(180, round_n)), false, "spell")
		"revive":
			for x: Variant in allies:
				if x != null and not x["alive"]:
					_revive(x, 0.5, "spell")
					break
		"venom":
			for x: Dictionary in _live(foes):
				_poison(x, D.spell_pow(55, round_n), 4, "spell")
		"guillotine":
			if t == null or not t["alive"]:
				return
			if _ratio(t) < 0.3:
				_hit(null, t, float(int(t["hp"]) + int(t["shield"])), false, "spell")
			else:
				_hit(null, t, float(D.spell_pow(160, round_n)), false, "spell")
		"surge":
			if t != null and t["alive"]:
				t["mana"] = t["mm"]
				_emit({"t": "mana", "u": t["slot"], "mana": t["mana"], "kind": "spell"})

func _end_step(team: Array) -> void:
	for c: Variant in team:
		if c == null or not c["alive"]:
			continue
		var pl: Array = c["poison"]
		if pl.size() > 0:
			var sum: int = 0
			for p: Dictionary in pl:
				sum += int(p["d"])
			var keep: Array = []
			for p: Dictionary in pl:
				p["n"] = int(p["n"]) - 1
				if int(p["n"]) > 0:
					keep.append(p)
			c["poison"] = keep
			_emit({"t": "poison_tick", "u": c["slot"], "amount": sum})
			_hit(null, c, float(sum), false, "poison")
		if c["alive"] and float(c["regen"]) > 0.0:
			_heal(c, float(c["max_hp"]) * float(c["regen"]), "regen")
