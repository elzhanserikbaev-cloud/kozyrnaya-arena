class_name RemoteBattle
extends RefCounted
## Бой, который считает ведущий: у клиента — та же «поверхность», что у Battle (units, unit, team_hand, over),
## а события ходов приходят по сети пачками.

var _units: Array = []
var _hands := {"home": "high", "away": "high"}
var _batches: Array = []        # очередь пачек событий
var _ended := false             # событие "end" уже отдано на показ
var _spells_left := {"home": 2, "away": 2}
var my_tag := "home"

func _init(units_: Array, hands: Dictionary, tag: String) -> void:
	_units = units_
	_hands = hands
	my_tag = tag

func push(evs: Array, units_: Array) -> void:
	_batches.append({"evs": evs, "units": units_})

## Следующая пачка событий или [] (ещё не пришла).
func take() -> Array:
	if _batches.is_empty():
		return []
	var b: Dictionary = _batches.pop_front()
	_units = b.units
	for e in b.evs:
		if e.get("t", "") == "end":
			_ended = true
	return b.evs

func units() -> Array: return _units

func unit(slot: int) -> Variant:
	for u in _units:
		if int(u.slot) == slot:
			return u
	return null

func team_hand(tag: String) -> String: return _hands.get(tag, "high")
func over() -> bool: return _ended
func spells_left(tag: String) -> int: return _spells_left.get(tag, 0)
func used_spell(tag: String) -> void: _spells_left[tag] = maxi(0, int(_spells_left[tag]) - 1)

func force_end() -> void:
	_ended = true
