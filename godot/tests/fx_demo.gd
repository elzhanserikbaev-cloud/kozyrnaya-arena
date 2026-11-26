extends Node3D
## Витрина боевых эффектов (Fx): стол, 5 + 5 карт, по очереди все эффекты и заклинания, скриншоты.
##   Godot --path godot --position -3000,-3000 --resolution 1600x900 res://tests/fx_demo.tscn -- --out=<папка> [--only=hit,spell_meteor]
## Без --out просто проигрывает показ (удобно смотреть вживую).

var table: Table3D
var fx: Fx
var mine: Array[Card3D] = []
var foes: Array[Card3D] = []
var out := ""
var only: PackedStringArray = []
var shot_n := 0
var nocards := false

const MY_IDS := ["cutpurse", "leech", "sellsword", "spider", "nun"]
const FOE_IDS := ["gravedigger", "crossbow", "cardsharp", "vampire", "bogwitch"]

func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--nocards":
			nocards = true
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	# сторожевой таймер: окно не должно остаться висеть, даже если показ упал с ошибкой
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
	table = Table3D.new()
	add_child(table)
	for i in 5:
		mine.append(_card(MY_IDS[i], Table3D.pos_board(i), "p", i))
		foes.append(_card(FOE_IDS[i], Table3D.pos_enemy(i), "e", 10 + i))
	fx = Fx.new()
	table.add_child(fx)
	await _sec(1.2)          # запекание лиц карт
	await _run()
	get_tree().quit()

func _card(id: String, pos: Vector3, side: String, uid: int) -> Card3D:
	var c := Card3D.new()
	table.add_child(c)
	c.setup("hero", id, CardFaces.face(id, 1), uid, side)
	c.position = pos
	c.home_pos = pos
	var d: Dictionary = Data.HEROES[id]
	c.set_stats(int(d.atk), int(d.hp), "", Color.WHITE, 1, String(d.n))
	c.show_bars(true)
	if nocards:
		c.pivot.visible = false
	c.set_bars(int(d.hp) * (3 + uid % 4) / 6, int(d.hp), 30, 100, 0)
	return c

func _sec(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _want(name: String) -> bool:
	if only.is_empty():
		return true
	for o in only:
		if name.begins_with(o):
			return true
	return false

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	if out == "":
		return
	var img := get_viewport().get_texture().get_image()
	shot_n += 1
	var p := out.path_join("%02d_%s.png" % [shot_n, name])
	img.save_png(p)
	print("shot ", p)

func _pos(cs: Array[Card3D]) -> Array:
	return cs.map(func(c: Card3D): return c.global_position)

func _el(c: Card3D) -> String:
	return Fx.elem_of_hero(c.key)

func _run() -> void:
	await _shot("00_table")
	if _want("hit"):
		# удары по всем врагам: лёд, огонь, свет, природа и крит
		for i in 5:
			var src := mine[i]
			src.lunge(foes[i].position)
		await _sec(0.15)
		for i in 4:
			fx.hit(foes[i].global_position, _el(mine[i]), false, "attack")
			foes[i].shake(0.06)
			Sfx.play("hit_" + {"S": "ice", "H": "fire", "D": "light", "C": "nature"}[_el(mine[i])])
		fx.hit(foes[4].global_position, "H", true, "attack")
		foes[4].shake(0.12)
		foes[4].float_text("-120!", Color("ffcf5a"), true)
		await _sec(0.08)
		await _shot("hit_early")
		await _sec(0.14)
		await _shot("hit_mid")
		await _sec(0.5)
	if _want("poisonhit"):
		fx.hit(foes[2].global_position, "C", false, "poison")
		fx.hit(foes[3].global_position, "", false, "thorns")
		await _sec(0.18)
		await _shot("poisonhit_thorns")
		await _sec(0.6)
	if _want("projectile"):
		for i in 4:
			fx.projectile(mine[i].global_position, foes[i].global_position, _el(mine[i]))
		await _sec(0.16)
		await _shot("projectile_mid")
		await _sec(0.8)
	if _want("cast"):
		for i in 4:
			fx.cast(mine[i].global_position, _el(mine[i]))
			mine[i].pop(1.15)
		await _sec(0.4)
		await _shot("cast")
		await _sec(0.8)
	if _want("support"):
		fx.heal(mine[0].global_position)
		fx.shield(mine[1].global_position)
		fx.poison(mine[2].global_position)
		fx.buff(mine[3].global_position, true)
		fx.buff(mine[4].global_position, false)
		await _sec(0.3)
		await _shot("support_heal_shield_poison_buffup_buffdown")
		await _sec(1.0)
	if _want("status"):
		fx.stun(foes[0].global_position)
		fx.stun(foes[1].global_position, true)
		foes[2].die()
		fx.death(foes[2].global_position, _el(foes[2]))
		fx.revive(foes[3].global_position)
		await _sec(0.4)
		await _shot("status_stun_frost_death_revive")
		await _sec(1.0)
		foes[2].revive()
	for key in ["fireball", "heal", "bless", "rage", "freeze", "meteor", "surge", "pact", "curse", "chain", "revive", "venom", "guillotine"]:
		if not _want("spell_" + key):
			continue
		var t: String = str(Data.MAGIC[key].get("t", ""))
		var targets: Array
		match key:
			"fireball", "curse", "guillotine":
				targets = [foes[2].global_position]
			"chain":
				targets = [foes[2].global_position, foes[1].global_position, foes[3].global_position]
			"freeze", "meteor", "venom":
				targets = _pos(foes)
			"heal", "surge", "pact":
				targets = [mine[2].global_position]
			_:
				targets = _pos(mine) if t != "foe" else _pos(foes)
		Sfx.play("spell_" + key)
		fx.spell(key, targets, Vector3(0, 0, 3.2))
		var peak: float = {"fireball": 0.2, "meteor": 0.45, "chain": 0.08, "guillotine": 0.34, "revive": 0.5}.get(key, 0.35)
		await _sec(peak)
		await _shot("spell_" + key)
		await _sec(0.4)  # сигнал ждут сразу; здесь он уже мог пройти
		await _sec(0.9)
	if _want("victory"):
		fx.victory(Vector3(0, 0, 1.95))
		Sfx.play("victory_sting")
		await _sec(0.9)
		await _shot("victory")
		await _sec(1.4)
	if _want("defeat"):
		fx.defeat(Vector3(0, 0, -2.1))
		await _sec(1.0)
		await _shot("defeat")
		await _sec(1.2)
	if _want("crit"):
		fx.hit(foes[1].global_position, "S", true)
		fx.hit(foes[3].global_position, "D", true)
		await _sec(0.1)
		await _shot("crit_ice_light")
		await _sec(0.6)
	# нагрузка: все удары разом + пул (сколько узлов создано)
	print("pool: emitters=", fx._free_em.size(), " quads=", fx._free_q.size(), " children=", fx.get_child_count())
