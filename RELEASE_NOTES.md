## Козырная Арена

3D карточный автобаттлер: нанимайте героев-карты, собирайте из них покерную руку, выдавайте усиления и разыгрывайте заклинания прямо в бою.

**Играть в браузере без установки:** https://elzhanserikbaev-cloud.github.io/kozyrnaya-arena/

### Скачать

| Система | Файл |
|---|---|
| Windows | `KozyrnayaArena-…-Windows-Setup.exe` (установщик) или `…-Windows-Portable.exe` (без установки) |
| macOS (M1/M2/M3/M4) | `KozyrnayaArena-…-macOS-arm64.dmg` |
| macOS (Intel) | `KozyrnayaArena-…-macOS-x64.dmg` |
| Ubuntu / Linux | `KozyrnayaArena-…-Linux-x86_64.AppImage` или `…-Linux-amd64.deb` |

### Режимы
- **Одиночная игра** против ИИ (три уровня сложности).
- **Онлайн по коду комнаты** — с друзьями через интернет, до 8 участников, можно добавить ботов.
- **По локальной сети** — по IP-адресу хоста.

### Первый запуск
Приложение не подписано платным сертификатом, поэтому система спросит подтверждение:
- **Windows:** «Windows защитила ваш компьютер» → «Подробнее» → «Выполнить в любом случае».
- **macOS:** перетащите игру в «Программы», затем правый клик по ней → «Открыть» → «Открыть». Если пишет «повреждено», выполните в Терминале:
  `xattr -cr "/Applications/Kozyrnaya Arena.app"`
- **Ubuntu (AppImage):** правый клик → Свойства → «Разрешить запуск как программы», или `chmod +x KozyrnayaArena-*.AppImage`. Если AppImage не стартует: `sudo apt install libfuse2`. Либо поставьте `.deb`: `sudo apt install ./KozyrnayaArena-*.deb`.
