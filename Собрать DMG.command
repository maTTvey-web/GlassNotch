#!/bin/bash
cd "$(dirname "$0")/GlassNotch" || exit 1
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Не найдены Command Line Tools. Запускаю установку. Когда закончится, открой этот файл ещё раз."
  xcode-select --install
  read -n 1 -s -r -p "Нажми любую клавишу..."
  exit 1
fi
if bash make-dmg.sh; then
  open ..
  echo "Готово! Рядом лежит GlassNotch.dmg"
else
  echo "Сборка не удалась. Скопируй текст ошибки выше и отправь Claude."
fi
read -n 1 -s -r -p "Нажми любую клавишу, чтобы закрыть..."
