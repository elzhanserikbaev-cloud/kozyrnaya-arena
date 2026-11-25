class_name Rng
extends RefCounted
## mulberry32 — побитово тот же генератор, что в web/index.html:
##   a|=0; a=a+0x6D2B79F5|0; t=imul(a^a>>>15,1|a); t=t+imul(t^t>>>7,61|t)^t; return ((t^t>>>14)>>>0)/2^32
## Целые GDScript 64-битные, поэтому всё держим как беззнаковые 32 бита и маскируем после каждой операции.

const M32: int = 0xFFFFFFFF

## Внутреннее состояние (беззнаковое 32-битное). Можно сохранять/восстанавливать.
var state: int = 0

func _init(seed_value: int = 0) -> void:
	state = seed_value & M32

## 32-битное умножение как Math.imul (результат беззнаковый), без переполнения 64 бит.
static func imul(x: int, y: int) -> int:
	x &= M32
	y &= M32
	var lo: int = (x & 0xFFFF) * y
	var hi: int = ((x >> 16) * y) & 0xFFFF
	return (lo + (hi << 16)) & M32

## Следующее число 0 ≤ x < 1 (как вызов функции mulberry32 в JS).
func next() -> float:
	state = (state + 0x6D2B79F5) & M32
	var a: int = state
	var t: int = imul(a ^ (a >> 15), 1 | a)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) & M32) ^ t
	return float((t ^ (t >> 14)) & M32) / 4294967296.0

## Целое 0..n-1 (Math.floor(rnd()*n)).
func next_int(n: int) -> int:
	return int(floorf(next() * float(n)))

## Целое from..to включительно.
func randi_range(from: int, to: int) -> int:
	return from + next_int(to - from + 1)

## Случайное зерно для боя (Math.floor(rnd()*2147483647), как у хоста в JS).
func next_seed() -> int:
	return next_int(2147483647)
