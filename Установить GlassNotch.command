#!/bin/bash
cd "$(dirname "$0")/GlassNotch" || { echo "Папка GlassNotch не найдена рядом со скриптом"; read -n 1 -s -r -p "Нажми любую клавишу..."; exit 1; }

echo "== Установка GlassNotch =="

# Нужны Command Line Tools
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Не найдены Command Line Tools. Запускаю их установку."
  echo "Когда она закончится, открой этот файл ещё раз."
  xcode-select --install
  read -n 1 -s -r -p "Нажми любую клавишу..."
  exit 1
fi

if bash build.sh; then
  pkill -x GlassNotch 2>/dev/null
  rm -rf /Applications/GlassNotch.app
  cp -R build/GlassNotch.app /Applications/
  xattr -cr /Applications/GlassNotch.app 2>/dev/null
  open /Applications/GlassNotch.app
  echo
  echo "Готово! GlassNotch установлен в /Applications и запущен."
  echo "Иконка появится в строке меню. Музыка: разреши доступ, когда macOS спросит."
else
  echo
  echo "Сборка не удалась. Скопируй текст ошибки выше и отправь Claude."
fi
echo
read -n 1 -s -r -p "Нажми любую клавишу, чтобы закрыть..."
