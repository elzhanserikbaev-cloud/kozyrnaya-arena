extends Node
## Данные игры (автозагрузка Data). Все числа — 1:1 из web/index.html v1.4.0 (баланс не меняем).
## Масти теперь стихии: ♠ Лёд, ♥ Огонь, ♦ Свет, ♣ Природа. Механика союзов та же:
## Лёд — криты, Огонь — регенерация отряда, Свет — щит на старте, Природа — +ОЗ отряду.
## Все функции статические: ядро (rules/battle/ai) обращается к ним через preload(), без экземпляра узла.

const SUIT_KEYS: Array = ["S", "H", "D", "C"]

## s → {key, sym, name, trait, color, ink, desc1, desc2}; desc1 — союз из 2 разных героев, desc2 — из 4.
const SUITS: Dictionary = {
	"S": {"key": "ice", "sym": "♠", "name": "Лёд", "trait": "Ледяные клинки",
		"color": Color(0.357, 0.561, 0.839), "ink": Color(0.10, 0.18, 0.40),
		"desc1": "+15% к шансу крита", "desc2": "+30% к шансу крита"},
	"H": {"key": "fire", "sym": "♥", "name": "Огонь", "trait": "Живое пламя",
		"color": Color(0.824, 0.271, 0.184), "ink": Color(0.45, 0.07, 0.05),
		"desc1": "отряд лечит 2% ОЗ за ход", "desc2": "отряд лечит 4,5% ОЗ за ход"},
	"D": {"key": "light", "sym": "♦", "name": "Свет", "trait": "Сияющий щит",
		"color": Color(0.878, 0.698, 0.227), "ink": Color(0.42, 0.28, 0.03),
		"desc1": "щит 12% ОЗ на старте", "desc2": "щит 28% ОЗ на старте"},
	"C": {"key": "nature", "sym": "♣", "name": "Природа", "trait": "Сила леса",
		"color": Color(0.310, 0.604, 0.290), "ink": Color(0.07, 0.27, 0.08),
		"desc1": "+12% ОЗ отряду", "desc2": "+28% ОЗ и +10% АТК"},
}

## id → {id, n, ic, s, r, c, hp, atk, mm, ab:{t, v, n}}. Порядок ключей = порядок RAW в JS (важен для пулов магазина).
## На каждом ранге не больше 3 разных героев: каре собирается только с Джокером.
const HEROES: Dictionary = {
	"cutpurse": {"id": "cutpurse", "n": "Карманник", "ic": "robber", "s": "S", "r": 2, "c": 1, "hp": 440, "atk": 58, "mm": 50, "ab": {"t": "strike", "v": 2.4, "n": "Удар исподтишка"}},
	"leech": {"id": "leech", "n": "Кровопийца", "ic": "bat", "s": "H", "r": 2, "c": 1, "hp": 500, "atk": 46, "mm": 60, "ab": {"t": "drain", "v": 1.8, "n": "Укус"}},
	"spider": {"id": "spider", "n": "Могильный паук", "ic": "hanging-spider", "s": "C", "r": 2, "c": 1, "hp": 480, "atk": 44, "mm": 60, "ab": {"t": "poison", "v": 0.55, "n": "Трупный яд"}},
	"sellsword": {"id": "sellsword", "n": "Наёмник", "ic": "brutal-helm", "s": "D", "r": 3, "c": 1, "hp": 680, "atk": 44, "mm": 60, "ab": {"t": "shield", "v": 2.5, "n": "Сомкнуть щиты"}},
	"cardsharp": {"id": "cardsharp", "n": "Шулер", "ic": "carnival-mask", "s": "S", "r": 3, "c": 1, "hp": 460, "atk": 50, "mm": 70, "ab": {"t": "stun", "v": 1.5, "n": "Краплёная карта"}},
	"nun": {"id": "nun", "n": "Сестра милосердия", "ic": "nun-face", "s": "H", "r": 3, "c": 1, "hp": 470, "atk": 38, "mm": 60, "ab": {"t": "heal", "v": 3.0, "n": "Последнее причастие"}},
	"gravedigger": {"id": "gravedigger", "n": "Могильщик", "ic": "hasty-grave", "s": "C", "r": 4, "c": 1, "hp": 600, "atk": 48, "mm": 60, "ab": {"t": "cleave", "v": 1.2, "n": "Удар лопатой"}},
	"crossbow": {"id": "crossbow", "n": "Арбалетчик", "ic": "crossbow", "s": "D", "r": 4, "c": 1, "hp": 450, "atk": 60, "mm": 60, "ab": {"t": "strike", "v": 2.2, "n": "Бронебойный болт"}},
	"duelist": {"id": "duelist", "n": "Бретёр", "ic": "duel", "s": "S", "r": 4, "c": 1, "hp": 500, "atk": 54, "mm": 60, "ab": {"t": "cleave", "v": 1.3, "n": "Вихрь клинков"}},
	"vampire": {"id": "vampire", "n": "Вампир", "ic": "vampire-dracula", "s": "H", "r": 5, "c": 2, "hp": 640, "atk": 62, "mm": 70, "ab": {"t": "drain", "v": 2.2, "n": "Кровавый поцелуй"}},
	"halberdier": {"id": "halberdier", "n": "Алебардщик", "ic": "pikeman", "s": "D", "r": 5, "c": 2, "hp": 820, "atk": 52, "mm": 70, "ab": {"t": "shield", "v": 3.0, "n": "Стена алебард"}},
	"bogwitch": {"id": "bogwitch", "n": "Болотная ведьма", "ic": "witch-face", "s": "C", "r": 5, "c": 2, "hp": 600, "atk": 52, "mm": 70, "ab": {"t": "poison", "v": 0.75, "n": "Гнилое зелье"}},
	"nighthunter": {"id": "nighthunter", "n": "Ночной охотник", "ic": "hooded-figure", "s": "S", "r": 6, "c": 2, "hp": 580, "atk": 70, "mm": 60, "ab": {"t": "execute", "v": 2.2, "n": "Охота на раненых"}},
	"inquisitor": {"id": "inquisitor", "n": "Инквизитор", "ic": "templar-eye", "s": "D", "r": 6, "c": 2, "hp": 700, "atk": 58, "mm": 80, "ab": {"t": "stun", "v": 1.8, "n": "Допрос с пристрастием"}},
	"cultist": {"id": "cultist", "n": "Культистка", "ic": "cultist", "s": "H", "r": 6, "c": 2, "hp": 580, "atk": 50, "mm": 70, "ab": {"t": "healall", "v": 1.1, "n": "Кровавый обряд"}},
	"necro": {"id": "necro", "n": "Некромант", "ic": "raise-zombie", "s": "C", "r": 7, "c": 2, "hp": 620, "atk": 56, "mm": 80, "ab": {"t": "volley", "v": 1.0, "n": "Костяной дождь"}},
	"poisoner": {"id": "poisoner", "n": "Отравительница", "ic": "poison-bottle", "s": "S", "r": 7, "c": 2, "hp": 560, "atk": 60, "mm": 60, "ab": {"t": "poison", "v": 0.85, "n": "Яд в бокале"}},
	"executioner": {"id": "executioner", "n": "Палач", "ic": "executioner-hood", "s": "D", "r": 7, "c": 2, "hp": 760, "atk": 64, "mm": 70, "ab": {"t": "execute", "v": 2.0, "n": "Казнь"}},
	"bloodpriest": {"id": "bloodpriest", "n": "Кровавый жрец", "ic": "chalice-drops", "s": "H", "r": 8, "c": 3, "hp": 780, "atk": 62, "mm": 80, "ab": {"t": "rally", "v": 0.2, "n": "Причастие кровью"}},
	"shadowmaster": {"id": "shadowmaster", "n": "Мастер теней", "ic": "hooded-assassin", "s": "S", "r": 8, "c": 3, "hp": 700, "atk": 92, "mm": 60, "ab": {"t": "execute", "v": 2.4, "n": "Удар из тени"}},
	"werewolf": {"id": "werewolf", "n": "Оборотень", "ic": "werewolf", "s": "C", "r": 8, "c": 3, "hp": 920, "atk": 78, "mm": 70, "ab": {"t": "drain", "v": 2.0, "n": "Растерзать"}},
	"blackknight": {"id": "blackknight", "n": "Чёрный рыцарь", "ic": "black-knight-helm", "s": "D", "r": 9, "c": 3, "hp": 1080, "atk": 66, "mm": 80, "ab": {"t": "shield", "v": 3.5, "n": "Клятва стали"}},
	"plaguedoc": {"id": "plaguedoc", "n": "Чумной доктор", "ic": "plague-doctor-profile", "s": "C", "r": 9, "c": 3, "hp": 760, "atk": 64, "mm": 90, "ab": {"t": "plague", "v": 0.45, "n": "Мор"}},
	"crimsonwitch": {"id": "crimsonwitch", "n": "Багровая колдунья", "ic": "warlock-hood", "s": "H", "r": 9, "c": 3, "hp": 700, "atk": 76, "mm": 90, "ab": {"t": "volley", "v": 1.35, "n": "Кровавый дождь"}},
	"guildkiller": {"id": "guildkiller", "n": "Убийца гильдии", "ic": "cloak-dagger", "s": "S", "r": 10, "c": 3, "hp": 720, "atk": 96, "mm": 70, "ab": {"t": "strike", "v": 3.0, "n": "Смертельный удар"}},
	"cardinal": {"id": "cardinal", "n": "Кардинал", "ic": "pope-crown", "s": "D", "r": 10, "c": 3, "hp": 820, "atk": 60, "mm": 90, "ab": {"t": "shieldall", "v": 1.8, "n": "Отпущение грехов"}},
	"gargoyle": {"id": "gargoyle", "n": "Горгулья", "ic": "gargoyle", "s": "C", "r": 10, "c": 3, "hp": 1250, "atk": 58, "mm": 80, "ab": {"t": "shield", "v": 4.0, "n": "Каменная кожа"}},
	"guildmaster": {"id": "guildmaster", "n": "Глава гильдии", "ic": "daggers", "s": "S", "r": 11, "c": 4, "hp": 920, "atk": 108, "mm": 70, "ab": {"t": "cleave", "v": 2.0, "n": "Танец клинков"}},
	"vampirecount": {"id": "vampirecount", "n": "Граф-вампир", "ic": "vampire-cape", "s": "H", "r": 11, "c": 4, "hp": 1000, "atk": 92, "mm": 80, "ab": {"t": "drain", "v": 2.6, "n": "Пир"}},
	"deathlord": {"id": "deathlord", "n": "Повелитель мертвецов", "ic": "skull-staff", "s": "C", "r": 11, "c": 4, "hp": 960, "atk": 84, "mm": 90, "ab": {"t": "raise", "v": 2.5, "n": "Поднять мёртвых"}},
	"mercqueen": {"id": "mercqueen", "n": "Королева наёмников", "ic": "queen-crown", "s": "D", "r": 12, "c": 4, "hp": 1150, "atk": 86, "mm": 90, "ab": {"t": "rally", "v": 0.28, "n": "Плата вперёд"}},
	"countess": {"id": "countess", "n": "Кровавая графиня", "ic": "dagger-rose", "s": "H", "r": 12, "c": 4, "hp": 980, "atk": 90, "mm": 90, "ab": {"t": "healall", "v": 1.6, "n": "Ванна из крови"}},
	"spadequeen": {"id": "spadequeen", "n": "Пиковая дама", "ic": "ceremonial-mask", "s": "S", "r": 12, "c": 4, "hp": 900, "atk": 100, "mm": 80, "ab": {"t": "volley", "v": 1.5, "n": "Проклятие дамы"}},
	"tyrant": {"id": "tyrant", "n": "Король-тиран", "ic": "throne-king", "s": "D", "r": 13, "c": 5, "hp": 1500, "atk": 98, "mm": 120, "ab": {"t": "stunall", "v": 1.1, "n": "Приговор"}},
	"plaguelord": {"id": "plaguelord", "n": "Чумной владыка", "ic": "dread-skull", "s": "C", "r": 13, "c": 5, "hp": 1600, "atk": 92, "mm": 110, "ab": {"t": "plague", "v": 0.7, "n": "Чёрная смерть"}},
	"reaper": {"id": "reaper", "n": "Жнец", "ic": "grim-reaper", "s": "S", "r": 14, "c": 5, "hp": 1150, "atk": 138, "mm": 80, "ab": {"t": "reap", "v": 1.55, "n": "Жатва"}},
	"blooddemon": {"id": "blooddemon", "n": "Демон крови", "ic": "devil-mask", "s": "H", "r": 14, "c": 5, "hp": 1350, "atk": 118, "mm": 100, "ab": {"t": "sunburst", "v": 1.7, "n": "Кровавая буря"}},
}

## Копии одного героя в руке считаются одной картой; бонусы растут с редкостью руки.
const HANDS: Dictionary = {
	"high": {"n": "Старшая карта", "atk": 0.0, "hp": 0.0, "mana": 0.0, "ex": "ничего не совпало"},
	"pair": {"n": "Пара", "atk": 0.06, "hp": 0.0, "mana": 0.0, "ex": "2 разных героя одного ранга"},
	"two": {"n": "Две пары", "atk": 0.08, "hp": 0.06, "mana": 0.0, "ex": "2 + 2 разных героя одного ранга"},
	"three": {"n": "Тройка", "atk": 0.12, "hp": 0.08, "mana": 0.0, "ex": "3 разных героя одного ранга"},
	"straight": {"n": "Стрит", "atk": 0.12, "hp": 0.08, "mana": 0.3, "ex": "5 рангов подряд"},
	"flush": {"n": "Флеш", "atk": 0.15, "hp": 0.15, "mana": 0.0, "ex": "5 разных героев одной стихии"},
	"full": {"n": "Фулл-хаус", "atk": 0.18, "hp": 0.18, "mana": 0.0, "ex": "тройка + пара"},
	"four": {"n": "Каре", "atk": 0.22, "hp": 0.15, "mana": 0.0, "ex": "4 одного ранга (только с Джокером)"},
	"sflush": {"n": "Стрит-флеш", "atk": 0.30, "hp": 0.30, "mana": 0.4, "ex": "стрит одной стихии"},
	"royal": {"n": "Роял-флеш", "atk": 0.50, "hp": 0.50, "mana": 1.0, "ex": "10-J-Q-K-A одной стихии"},
}
const HAND_ORDER: Array = ["high", "pair", "two", "three", "straight", "flush", "full", "four", "sflush", "royal"]

## Магия: усиления (k="item", до 2 на героя) и заклинания (k="spell", до 2 за бой).
## t — цель заклинания: "foe" / "ally" / null. w — вес выпадения в магазине.
## d — текст; "{p}" заменяется на spell_pow(pb, раунд) (сила растёт на 12% за раунд, как spellPow в JS).
## Порядок ключей важен: rollMagic перебирает их по порядку.
const MAGIC: Dictionary = {
	"sword": {"k": "item", "n": "Зазубренный клинок", "i": "bloody-sword", "c": 3, "w": 1.0, "t": null, "d": "Герой получает +25% АТК."},
	"armor": {"k": "item", "n": "Шипастые латы", "i": "spiked-armor", "c": 3, "w": 1.0, "t": null, "d": "Герой получает +30% ОЗ."},
	"orb": {"k": "item", "n": "Камень душ", "i": "crystal-ball", "c": 3, "w": 1.0, "t": null, "d": "Герой начинает бой с 40% маны."},
	"fang": {"k": "item", "n": "Клыки вампира", "i": "fangs", "c": 4, "w": 1.0, "t": null, "d": "Герой лечится на 25% нанесённого урона."},
	"feather": {"k": "item", "n": "Монета удачи", "i": "coinflip", "c": 3, "w": 1.0, "t": null, "d": "+20% к шансу крита героя."},
	"thorns": {"k": "item", "n": "Шипастый щит", "i": "spiked-shield", "c": 4, "w": 1.0, "t": null, "d": "Возвращает атакующему 25% полученного урона."},
	"joker": {"k": "item", "n": "Джокер", "i": "jester-hat", "c": 5, "w": 0.35, "t": null, "d": "Карта героя считается любой картой, нужной для лучшей покерной руки."},
	"fireball": {"k": "spell", "n": "Адское пламя", "i": "fireball", "c": 3, "w": 1.0, "t": "foe", "pb": 300, "d": "Наносит {p} урона выбранному врагу."},
	"heal": {"k": "spell", "n": "Эликсир", "i": "health-potion", "c": 2, "w": 1.0, "t": "ally", "d": "Лечит выбранного союзника на 40% ОЗ."},
	"bless": {"k": "spell", "n": "Святой щит", "i": "holy-symbol", "c": 3, "w": 1.0, "t": null, "pb": 170, "d": "Все союзники получают щит {p}."},
	"rage": {"k": "spell", "n": "Боевой рог", "i": "mighty-horn", "c": 3, "w": 1.0, "t": null, "d": "Все союзники получают +25% АТК до конца боя."},
	"freeze": {"k": "spell", "n": "Ледяная хватка", "i": "snowflake-1", "c": 4, "w": 0.8, "t": null, "d": "Замораживает всех врагов на 1 ход."},
	"meteor": {"k": "spell", "n": "Звездопад", "i": "meteor-impact", "c": 4, "w": 0.8, "t": null, "pb": 140, "d": "Наносит {p} урона всем врагам."},
	"surge": {"k": "spell", "n": "Зелье маны", "i": "magic-potion", "c": 2, "w": 1.0, "t": "ally", "d": "Выбранный союзник сразу получает полную ману."},
	"pact": {"k": "spell", "n": "Кровавый пакт", "i": "blood", "c": 2, "w": 1.0, "t": "ally", "d": "Союзник получает +60% АТК до конца боя, но теряет 25% текущих ОЗ."},
	"curse": {"k": "spell", "n": "Проклятие", "i": "evil-hand", "c": 3, "w": 1.0, "t": "foe", "d": "Выбранный враг теряет 35% АТК до конца боя."},
	"chain": {"k": "spell", "n": "Цепная молния", "i": "chain-lightning", "c": 3, "w": 1.0, "t": "foe", "pb": 180, "d": "Наносит {p} урона врагу и его соседям по линиям."},
	"revive": {"k": "spell", "n": "Восстание из гроба", "i": "coffin", "c": 4, "w": 0.7, "t": null, "d": "Первый павший союзник возвращается в бой с 50% ОЗ."},
	"venom": {"k": "spell", "n": "Отравленное вино", "i": "pouring-chalice", "c": 3, "w": 1.0, "t": null, "pb": 55, "d": "Все враги отравлены: {p} урона за ход, 4 хода."},
	"guillotine": {"k": "spell", "n": "Гильотина", "i": "guillotine", "c": 4, "w": 0.8, "t": "foe", "pb": 160, "d": "Казнит врага с ОЗ ниже 30%. Иначе наносит {p} урона."},
}

const STARM: Array = [0.0, 1.0, 1.8, 3.2]
const XPNEED: Array = [0, 2, 4, 8, 14, 22, 34, 50, 0]
const ODDS: Array = [null, [100, 0, 0, 0, 0], [75, 25, 0, 0, 0], [55, 35, 10, 0, 0], [40, 35, 20, 5, 0], [25, 35, 30, 10, 0], [18, 27, 35, 17, 3], [12, 20, 33, 27, 8], [5, 15, 30, 35, 15]]
const AIBONUS: Dictionary = {"easy": -1, "normal": 0, "hard": 2}
const DIFFN: Dictionary = {"easy": "Лёгкий", "normal": "Обычный", "hard": "Тяжёлый"}
const START_HP: int = 100
const FEED_PCT: float = 0.15
const FEED_MAX: int = 2
const DMG_CAP: int = 18
const MAX_STEPS: int = 30
const HAND_MAX: int = 5
const BOARD_SIZE: int = 5
const BENCH_SIZE: int = 6
const REROLL_COST: int = 2
const XP_COST: int = 4
const MAX_SPELLS_PER_BATTLE: int = 2

## Math.round из JS (половина — вверх, к +∞).
static func r(x: float) -> int:
	var f: float = floorf(x)
	if x - f >= 0.5:
		f += 1.0
	return int(f)

## Сила заклинания растёт на 12% за раунд (spellPow).
static func spell_pow(base: float, round_n: int) -> int:
	return r(base * (1.0 + 0.12 * float(round_n - 1)))

static func magic_desc(k: String, round_n: int = 1) -> String:
	var m: Dictionary = MAGIC[k]
	var d: String = m["d"]
	if m.has("pb"):
		d = d.replace("{p}", str(spell_pow(float(m["pb"]), round_n)))
	return d

## Текст способности (AB в JS): v — сила способности, a — АТК героя.
static func ab_text(t: String, v: float, a: int) -> String:
	var p: int = r(v * a)
	match t:
		"strike": return "Бьёт цель на %d." % p
		"stun": return "Бьёт цель на %d и оглушает на 1 ход." % p
		"cleave": return "Бьёт цель и соседние линии на %d." % p
		"volley": return "Бьёт всех врагов на %d." % p
		"heal": return "Лечит самого раненого союзника на %d." % p
		"healall": return "Лечит всех союзников на %d." % p
		"shield": return "Даёт себе и соседям щит %d." % p
		"shieldall": return "Даёт всем союзникам щит %d." % p
		"rally": return "Все союзники получают +%d%% АТК до конца боя." % r(v * 100.0)
		"drain": return "Бьёт цель на %d и лечится на столько же." % p
		"execute": return "Бьёт цель на %d, вдвое сильнее по цели ниже 40%% ОЗ." % p
		"poison": return "Травит цель и соседей: %d урона за ход, 3 хода." % p
		"stunall": return "Бьёт всех врагов на %d и оглушает их." % p
		"reap": return "Бьёт всех врагов на %d, вдвое по целям ниже 40%% ОЗ." % p
		"sunburst": return "Бьёт всех врагов на %d и лечит союзников на %d." % [p, a]
		"plague": return "Травит всех врагов: %d урона за ход, 3 хода." % p
		"raise": return "Поднимает первого павшего союзника с 40%% ОЗ. Если павших нет, лечится на %d." % p
	return ""

## Описание способности героя с числами для указанной звезды (и съеденных карт, если переданы).
static func ab_desc(id: String, star: int = 1, fed: Variant = null) -> String:
	var d: Dictionary = HEROES[id]
	var atk: int = r(float(d["atk"]) * float(STARM[star]))
	if fed is Dictionary and not (fed as Dictionary).is_empty():
		atk += int((fed as Dictionary).get("atk", 0))
	return ab_text(d["ab"]["t"], float(d["ab"]["v"]), atk)

## Подпись бонуса руки (handText в JS).
static func hand_text(k: String) -> String:
	var h: Dictionary = HANDS[k]
	var p: Array = []
	if float(h["atk"]) > 0.0:
		p.append("+%d%% АТК" % r(float(h["atk"]) * 100.0))
	if float(h["hp"]) > 0.0:
		p.append("+%d%% ОЗ" % r(float(h["hp"]) * 100.0))
	if float(h["mana"]) > 0.0:
		p.append("полная мана на старте" if float(h["mana"]) >= 1.0 else "старт с %d%% маны" % r(float(h["mana"]) * 100.0))
	return ", ".join(p) if p.size() > 0 else "без бонуса"

## Текст союза стихии для уровня 1/2.
static func trait_text(s: String, lv: int) -> String:
	if lv <= 0:
		return ""
	return SUITS[s]["desc2"] if lv >= 2 else SUITS[s]["desc1"]
