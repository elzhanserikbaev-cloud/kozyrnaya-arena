Козырная Арена — Linux (x86_64)

Запуск:
  chmod +x KozyrnayaArena.x86_64
  ./KozyrnayaArena.x86_64

Файл libwebrtc_native.*.so должен лежать рядом с программой — без него не работает онлайн-игра по коду комнаты.

Значок в меню приложений (по желанию):
  mkdir -p ~/.local/share/applications ~/.local/share/icons
  cp kozyrnaya-arena.png ~/.local/share/icons/
  sed "s|^Exec=.*|Exec=$PWD/KozyrnayaArena.x86_64|; s|^Icon=.*|Icon=$HOME/.local/share/icons/kozyrnaya-arena.png|" \
      kozyrnaya-arena.desktop > ~/.local/share/applications/kozyrnaya-arena.desktop

Игра по локальной сети: порт 8777 (TCP/UDP) и 8778 (UDP, поиск игр) должны быть открыты в брандмауэре.
