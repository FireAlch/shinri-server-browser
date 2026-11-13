# Shinri Server Browser for Garry's Mod

[Русский](#русский) · [English](#english)

## Русский

**Полное обновление** проверяет доступные сервера и сохраняет их в кэш. Работает долго, запускать часто не нужно.
**Обновить статус** опрашивает сохранённые в кэше адреса. Отсутствие ответа не обязательно означает, что сервер выключен.

### Установка

Это изменение главного меню, а не обычный аддон Workshop. Понадобится файл `shinri_server_browser.lua` из проекта.

1. В Steam откройте **Garry's Mod → Свойства → Установленные файлы → Обзор**.
2. Скопируйте `shinri_server_browser.lua` в `garrysmod/lua/menu/`; при необходимости создайте папку.
3. В той же папке `garrysmod/lua/menu/` откройте файл `menu.lua`.
4. Добавьте в конец `menu.lua`:

   ```lua
   -- Shinri server browser
   local shinriOk, shinriError = pcall( include, "menu/shinri_server_browser.lua" )
   if not shinriOk then
       ErrorNoHalt( "Shinri browser: " .. tostring( shinriError ) .. "\n" )
   end
   ```
   
Или распакуйте содержимое архива последнего релиза в папку `GarrysMod`. Это перезапишет файл меню на стандартный + нужный блок кода.

### Удаление

1. Удалите добавленный блок из `garrysmod/lua/includes/menu.lua`.
2. Удалите `garrysmod/lua/menu/shinri_server_browser.lua`.
3. При желании удалите локальный кэш `garrysmod/data/shinri_server_browser.json`.
4. Перезапустите игру.

### Источники и декомпиляция

Никакие файлы Shinri Trial **не были декомпилированы** использовалась только информация из открытых источников, включая доступные API и документацию Garry's Mod.

> Проект не является официальным продуктом и не связан с разработчиками Garry's Mod или Shinri.

---

## English

**Full refresh** checks available servers and saves them to the cache. It takes a while and does not need to be run often.
**Refresh status** queries the addresses saved in the cache. No response does not necessarily mean a server is offline.

### Installation

This modifies the main menu; it is not a regular Workshop addon. You will need the `shinri_server_browser.lua` file from the project.

1. In Steam, open **Garry's Mod → Properties → Installed Files → Browse**.
2. Copy `shinri_server_browser.lua` to `garrysmod/lua/menu/`; create the directory if needed.
3. In the same `garrysmod/lua/menu/` directory, open `menu.lua`.
4. Add the following to the end of `menu.lua`:

   ```lua
   -- Shinri server browser
   local shinriOk, shinriError = pcall( include, "menu/shinri_server_browser.lua" )
   if not shinriOk then
       ErrorNoHalt( "Shinri browser: " .. tostring( shinriError ) .. "\n" )
   end
 
   ```
Or unzip the contents of the archive of the latest release to the `GarrysMod' folder. This will overwrite the menu file to the standard + required code block.

### Uninstallation

1. Remove the added block from `garrysmod/lua/includes/menu.lua`.
2. Delete `garrysmod/lua/menu/shinri_server_browser.lua`.
3. Optionally delete the local cache at `garrysmod/data/shinri_server_browser.json`.
4. Restart the game.

### Sources and decompilation

No Shinri Trial files were **decompiled**. Only information from publicly available sources was used, including accessible APIs and the Garry's Mod documentation.

> This is an unofficial project and is not affiliated with the developers of Garry's Mod or Shinri.
