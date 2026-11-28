extends SceneTree
## Слушает объявления LAN 8 секунд и считает, сколько раз менялся список (каждое изменение = перерисовка меню).
var lan
var changes := 0
var t := 0.0
func _initialize() -> void:
	lan = load("res://scripts/net/lan_discovery.gd").new()
	lan.discovery_port = 8778
	root.add_child(lan)
	lan.games_changed.connect(func(l): changes += 1; print("changed: ", l.map(func(g): return g.ip)))
	pass
func _process(d: float) -> bool:
	if t == 0.0: print("browse: ", lan.start_browsing(3))
	t += d
	if t > 8.0:
		print("TOTAL changes in 8s: ", changes)
		return true
	return false
