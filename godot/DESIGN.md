# Козырная Арена 2.0 (Godot 4.7) — общий план

Порт веб-игры `../web/index.html` (Babylon.js, единственный источник правил) на Godot 4.7.2, GDScript, рендер **GL Compatibility** (ПК, Android, веб для iOS).
Редактор: `C:\Users\user\Downloads\Kozyrnaya Arena\tools\godot\Godot_v4.7.2-stable_win64_console.exe` (`--headless --path godot --import`, `--headless --path godot --script res://tests/xxx.gd`).

## Что меняется
- **Масти = стихии.** ♠ Лёд (синий/серебро), ♥ Огонь (красный/медь), ♦ Свет (золото/слоновая кость), ♣ Природа (зелёный/дерево). Покерные правила те же (ранги, масти, руки).
  Союзы стихий — механика та же, меняются только названия: Лёд = криты (+15%/+30%), Огонь = регенерация отряда, Свет = щит на старте, Природа = +ОЗ отряду.
- **Баланс НЕ меняем** (пользователь явно просил): числа HANDS, героев, магии, урон, золото, ва-банк, награда, жертвоприношение (★★+, та же масть, 15%, максимум 2), 100 ОЗ, «Козырь в рукаве», бесплатное обновление после поражения — всё как в web/index.html v1.4.0.
- **Без неона.** Никаких светящихся контуров, bloom/glow, кислотных цветов. Свет мягкий, «рисованный»: насыщенные, но тёплые цвета, тени, фактуры (металл, дерево, камень, пергамент).
- **Ассеты как у приложения**: запечённые PNG (резные рамки, самоцветы, ленты, кнопки, панели), шрифты TTF внутри проекта. Никакого HTML.

## Стиль (ориентир — «набор карт заклинаний: природа, лёд, огонь, свет, UI для игр»)
Фэнтези-карты в стиле мобильных ККИ: толстая резная рамка из материала стихии, самоцвет сверху, лента с именем, круглые медальоны статов.
- Лёд: посеребрённая сталь + ледяные кристаллы по углам, сапфир; фон портрета — холодное небо, снежинки.
- Огонь: медь/бронза + языки пламени в орнаменте, рубин; фон — закат, угли, дым.
- Свет: золото + слоновая кость, лучи солнца, топаз; фон — тёплые солнечные лучи.
- Природа: тёмное дерево + лоза и листья, изумруд; фон — лес, листва.
- Звёзды: ★1 — базовая рамка, ★2 — серебряная окантовка + 2 звезды, ★3 — золотая окантовка + 3 звезды.
- Магия: «Усиление» — сталь/бирюза; «Заклинание» — фиолетовый пергамент с рунами (без свечения).
- UI: панели из тёмного дерева с золотой окантовкой и пергаментными вставками; кнопки-«камни» с фаской (золотая — главная «В бой!», красная — «Ва-банк», синяя/дерево — обычные); иконки монеты, сердца, меча, маны.
- Стол (3D): деревянный круглый стол с резным бортом, сукно-«карта арены» насыщенного сине-зелёного цвета с золотой вышивкой и четырьмя знаками стихий.

## Шрифты (OFL, лежат в assets/fonts)
- Заголовки: **Philosopher Bold** (кириллица). Текст: **Rubik** (Regular/Medium/Bold).

## Структура
```
godot/
  project.godot           (автозагрузки: Data, Net)
  assets/cards/           рамки карт: frame_{ice,fire,light,nature}_{1,2,3}.png, frame_item.png, frame_spell.png, back.png  (512x716)
  assets/portraits/       hero_<id>.png (запечённые портреты 432x312), magic_<key>.png (300x300)
  assets/ui/              panel.png, panel_dark.png, btn_{gold,red,blue,wood}_{normal,hover,pressed,disabled}.png, ribbon.png, gem_*.png, medal_{atk,hp,mana,cost}.png, star.png, coin.png, bar_frame.png, bar_fill_{hp,foe,mana}.png, element_{ice,fire,light,nature}.png ...  (+ assets/ui/ui_manifest.json с 9-patch отступами)
  assets/table/           felt.png (2048), wood.png, rim_normal?.png
  assets/fonts/           Philosopher-Bold.ttf, Rubik-*.ttf
  scripts/core/           data.gd (автозагрузка Data), rules.gd, battle.gd, ai.gd, rng.gd   — чистая логика, без узлов сцены
  scripts/game/           game.gd (ход партии, соло и сеть), table3d.gd, card3d.gd, fx.gd
  scripts/ui/             hud.gd, shop.gd, menus.gd, theme.tres
  scripts/net/            net.gd (автозагрузка Net), peerjs_signaling.gd, lan_discovery.gd
  tests/                  headless-тесты (*.gd, extends SceneTree)
  tools/asset-studio/     HTML+canvas «студия», которая запекает PNG через headless Chrome
```

## Контракт ядра (scripts/core)
Данные — словари (удобно передавать по сети и сохранять JSON).
- Unit: `{uid:int, id:String, star:int, items:Array[String], fed:{atk,hp,n}|null}`
- Side: `{hp, gold, level, xp, board:[5 Unit|null], bench:[6 Unit|null], streak, hand:[magic keys], allin:bool, allin_cd:int, name}`
- `Data`: HEROES (id → {id,n,ic,s,r,c,hp,atk,mm,ab:{t,v,n}}), MAGIC, HANDS, HAND_ORDER, STARM, XPNEED, ODDS, START_HP=100, FEED_PCT, FEED_MAX, DMG_CAP, SUITS (S/H/D/C → имя стихии, цвет, символ).
- `Rules` (class_name Rules, static): eval_hand, eval_units, unique_units, trait_levels, stats, power, sell_value, cap_of, add_xp, roll_id, roll_shop(level, side, rng), help_chance, merge_all(side) → merged unit|null, gain_unit, feed_targets, do_feed, round_damage, streak_gold, income(side) …
- `Rng` (class_name Rng): mulberry32 как в JS (`next()` 0..1, `randi_range`).
- `Battle` (class_name Battle, RefCounted): `Battle.new(home_board, away_board, home_info, away_info, seed, round)`; `step() -> Array[Dictionary]` события хода (атака, способность, урон, лечение, щит, смерть, оглушение, яд, заклинание…); `queue_spell(side_tag, key, target_uid)` — применяется в начале следующего хода; `over() -> bool`; `result() -> {outcome:"home"|"away"|"draw", survivors_home:[…], survivors_away:[…]}`. Детерминирован при одинаковом seed (повторяет JS-логику боя).
- `Ai` (class_name Ai, static): take_turn(side, round, diff, rng), arrange(side), magic(side, …), battle_spell_choice(…).

## Сеть
Ведущий (хост) — авторитетный: держит лобби, пары, симулирует ВСЕ бои у себя и рассылает события ходов; клиенты только показывают и шлют действия (покупки делаются локально у клиента и присылаются снимком стола в конце фазы магазина, как в web-версии; заклинания в бою — RPC хосту, применяются в начале следующего хода).
Транспорт — высокоуровневый multiplayer Godot (RPC) поверх:
- **LAN**: ENetMultiplayerPeer (порт 8777) + поиск игр по UDP-рассылке (порт 8778).
- **Онлайн по коду комнаты**: WebRTCMultiplayerPeer (аддон webrtc_native 1.2.2, на вебе — встроенный), сигналинг через бесплатный PeerJS-сервер `wss://0.peerjs.com/peerjs?key=peerjs&id=<id>&token=<rand>` (протокол PeerJS: OPEN/OFFER/ANSWER/CANDIDATE/HEARTBEAT/LEAVE/EXPIRE). ID хоста = `kozyr-godot-v1-<КОД6>`.
API `Net`: `host_lan()`, `join_lan(ip)`, `find_lan_games()` (сигнал), `host_online() -> code` (сигнал room_ready), `join_online(code)`, `leave()`, сигналы `connected`, `connection_failed(reason)`, `peer_joined(id)`, `peer_left(id)`; после подключения игра пользуется `multiplayer` и `@rpc`.

## Сборка (CI)
`.github/workflows/release.yml` по тегу `v*`: скачать Godot 4.7.2 + шаблоны экспорта + webrtc_native → экспорт Windows (exe), Linux (x86_64), macOS (universal zip, ad-hoc подпись встроенным codesign Godot), Android (APK, временный ключ или секреты ANDROID_KEYSTORE_B64/PASS), Web (на GitHub Pages — для iPhone «На экран Домой»).
