-- Shinri server browser for the Garry's Mod menu realm.
local translations = {
    ["Лобби"] = "Lobbies", ["Игровые"] = "Game servers", ["Быстрые игры"] = "Quick games", ["Тестовые"] = "Test servers", ["Быстрые"] = "Quick",
    ["Серверы Shinri"] = "Shinri servers", ["Серверы Shinri   →"] = "Shinri servers   →",
    ["Обновить статус"] = "Refresh status", ["Полное обновление"] = "Full refresh", ["Остановить"] = "Stop", ["Подключиться"] = "Connect",
    ["Сохранённые серверы. Полное обновление ищет оба региона."] = "Saved servers. Full refresh scans both regions.",
    ["Не распознано: "] = "Unrecognized: ", [" — показать имена"] = " — show names",
    ["Поиск продолжается. Серверы появятся по мере ответов."] = "Searching. Servers appear as they respond.",
    ["Серверов этого типа пока нет. Нажмите «Полное обновление»."] = "No servers of this type yet. Select Full refresh.",
    ["СЕРВЕР"] = "SERVER", ["ИГРОКИ"] = "PLAYERS", ["КАРТА"] = "MAP", ["ПИНГ"] = "PING", ["АДРЕС"] = "ADDRESS", ["СТАТУС"] = "STATUS",
    ["Сохранён"] = "Saved", ["Нет ответа"] = "No response", ["Ответил"] = "Responded", ["Запрос..."] = "Querying...",
    ["\nПоследний ответ: "] = "\nLast response: ", ["Нераспознанные серверы — "] = "Unrecognized servers — ", ["Название"] = "Name", ["Адрес"] = "Address",
    ["получение узлов"] = "fetching nodes", ["; ответили "] = "; responded ", ["; узлов "] = "; nodes ", [" (кэш "] = " (cached ", [", ответили "] = ", responded ",
    ["Поиск остановлен. Подтверждённые находки сохранены."] = "Search stopped. Confirmed discoveries saved.",
    ["Поиск остановлен. Старый кэш сохранён без изменений."] = "Search stopped. The old cache was left unchanged.",
    ["\nНет ответа не означает, что сервер выключен."] = "\nNo response does not mean the server is offline.",
    ["Слишком большой ответ /nodes"] = "Node response is too large", ["Некорректный или пустой список узлов"] = "Invalid or empty node list", ["Недопустимый IP узла"] = "Invalid node IP address",
    ["Кэш слишком большой"] = "Cache is too large", ["Кэш повреждён"] = "Cache is corrupted", ["Неизвестная версия кэша"] = "Unknown cache version", ["Повтор адреса в кэше"] = "Duplicate address in cache", ["Кэш узлов повреждён"] = "Node cache is corrupted", ["Кэш поиска повреждён"] = "Scan cache is corrupted",
    ["Не удалось подготовить кэш"] = "Could not prepare cache", ["Не удалось сохранить список"] = "Could not save server list", ["Узлы недоступны"] = "Nodes unavailable", ["Тайм-аут /nodes"] = "Node request timed out", ["Ошибка сети /nodes"] = "Node network request failed", ["Запрос /nodes не принят"] = "Node request rejected", ["Достигнут лимит сохранённых адресов"] = "Saved address limit reached",
}
local function currentLanguage()
    local ok, value = pcall(GetConVarString, "gmod_language")
    value = ok and isstring(value) and string.lower(value) or ""
    return (value == "ru" or value:match("^ru[-_]")) and "ru" or "en"
end
local function tr(text, lang)
    if (lang or currentLanguage()) == "ru" then return text end
    return translations[text] or text
end
local regions = {
    { key = "cis", label = "CIS", urls = { "https://api.shinri.red/nodes", "https://api-fb1.shinri.red/nodes" }, first = 28015, last = 28215 },
    { key = "eu", label = "EU", urls = { "https://api.shinri-trial.com/nodes" }, first = 27015, last = 27215 },
}
local categories = {
    { key = "lobby", label = "Лобби" }, { key = "game", label = "Игровые" },
    { key = "quick", label = "Быстрые игры" }, { key = "test", label = "Тестовые" },
}
local regionByKey, categoryByKey = {}, { unknown = true }
for _, region in ipairs(regions) do regionByKey[region.key] = region end
for _, category in ipairs(categories) do categoryByKey[category.key] = category end
local TIMEOUT, MAX_NODES, MAX_RECORDS = 8, 32, 12864
local cachePath = "shinri_server_browser.json"
local records, nodeCache, scans = {}, {}, {}
local dirty, cacheError, cacheProtected = false, nil, false

local function publicIP(value)
    if not isstring(value) or #value > 15 then return end
    local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return end
    for _, octet in ipairs({ a, b, c, d }) do
        if #octet > 3 or tonumber(octet) > 255 then return end
    end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if a == 0 or a == 10 or a == 127 or a >= 224
        or (a == 169 and b == 254) or (a == 172 and b >= 16 and b <= 31)
        or (a == 192 and b == 168) or (a == 100 and b >= 64 and b <= 127)
        or (a == 192 and b == 0 and (c == 0 or c == 2))
        or (a == 198 and (b == 18 or b == 19 or (b == 51 and c == 100)))
        or (a == 203 and b == 0 and c == 113) then return end
    return a .. "." .. b .. "." .. c .. "." .. d
end
local function validAddress(value, regionKey)
    if not isstring(value) or #value > 21 then return end
    local ip, port = value:match("^([%d%.]+):(%d+)$")
    ip, port = publicIP(ip), tonumber(port)
    if not ip or not port or port < 1 or port > 65535 then return end
    local region = regionByKey[regionKey]
    if region and (port < region.first or port > region.last) then return end
    return ip .. ":" .. port
end
local function recordKey(region, address) return region .. "/" .. address end
local function compareRecords(a, b)
    return recordKey(a.region, a.address) < recordKey(b.region, b.address)
end
local function denseArray(value, limit, allowEmpty)
    if not istable(value) or #value > limit or (not allowEmpty and #value == 0) then return false end
    local count = 0
    for key in pairs(value) do
        if not isnumber(key) or key % 1 ~= 0 or key < 1 or key > #value then return false end
        count = count + 1
    end
    return count == #value
end
local function parseNodes(body)
    if not isstring(body) or #body > 65536 then return nil, "Слишком большой ответ /nodes" end
    local data = util.JSONToTable(body)
    if not istable(data) or data.success ~= true or not istable(data.result)
        or not denseArray(data.result.nodes, MAX_NODES, false) then return nil, "Некорректный или пустой список узлов" end
    local ips, seen = {}, {}
    for _, node in ipairs(data.result.nodes) do
        local ip = istable(node) and publicIP(node.ipAddress)
        if not ip then return nil, "Недопустимый IP узла" end
        if not seen[ip] then ips[#ips + 1], seen[ip] = ip, true end
    end
    return ips
end
local uppercase = { "А", "Б", "В", "Г", "Д", "Е", "Ё", "Ж", "З", "И", "Й", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т", "У", "Ф", "Х", "Ц", "Ч", "Ш", "Щ", "Ъ", "Ы", "Ь", "Э", "Ю", "Я" }
local lowercase = { "а", "б", "в", "г", "д", "е", "ё", "ж", "з", "и", "й", "к", "л", "м", "н", "о", "п", "р", "с", "т", "у", "ф", "х", "ц", "ч", "ш", "щ", "ъ", "ы", "ь", "э", "ю", "я" }
local function lowerName(value)
    value = string.lower(value):gsub("^%s+", ""):gsub("%s+$", "")
    for index, letter in ipairs(uppercase) do value = value:gsub(letter, lowercase[index]) end
    return value
end
local function classifyServer(name)
    if not isstring(name) or #name > 512 then return "unknown", "Не распознано" end
    local text = lowerName(name)
    -- A session title cannot turn ST #N into a test or quick-game server.
    local number = text:match("^st%s+#(%d+)%s*%-")
    if number then return "game", "Игровой " .. number, tonumber(number) end
    local prefix = text:gsub("^st%s*%-%s*", "")
    if prefix:match("^тест%s+%d+%s*$") or prefix:match("^тестовый сервер") or prefix:match("^тестовый%s")
        or prefix:match("^test server") or prefix:match("^testing server") then
        return "test", "Тестовый", tonumber(prefix:match("#?(%d+)"))
    end
    if prefix:match("^быстрая игра") or prefix:match("^quick game") or prefix:match("^quick match") then
        return "quick", "Быстрая игра", tonumber(prefix:match("#?(%d+)"))
    end
    number = text:match("общее лобби%s*#?(%d+)")
        or prefix:match("^public lobby%s*#?(%d+)") or prefix:match("^lobby%s*#?(%d+)")
    if number then return "lobby", "Лобби " .. number, tonumber(number) end
    number = prefix:match("^игровой%s+(%d+)") or prefix:match("^game server%s*#?(%d+)")
    if number then return "game", "Игровой " .. number, tonumber(number) end
    return "unknown", "Не распознано"
end
local function timestamp(value)
    return isnumber(value) and value >= 0 and value <= os.time() + 86400 and value % 1 == 0
end
local function countsFor(regionKey)
    local counts = { lobby = 0, game = 0, quick = 0, test = 0, unknown = 0, total = 0 }
    for _, record in pairs(records) do
        if record.region == regionKey then
            counts[record.category] = counts[record.category] + 1
            if record.category ~= "unknown" then counts.total = counts.total + 1 end
        end
    end
    return counts
end
local function loadCache()
    local raw = file.Read(cachePath, "DATA")
    if not raw then return end
    cacheProtected = true
    if #raw > 16777216 then cacheError = "Кэш слишком большой" return end
    local data = util.JSONToTable(raw)
    if not istable(data) or not denseArray(data.servers, MAX_RECORDS, true) then cacheError = "Кэш повреждён" return end
    local loaded, loadedNodes, loadedScans, seen = {}, {}, {}, {}
    local dropped = false
    if data.version ~= 2 then cacheError = "Неизвестная версия кэша" return end
    for _, item in ipairs(data.servers) do
        if not istable(item) then cacheError = "Кэш повреждён" return end
        local region, category = item.region, item.category
        local address = regionByKey[region] and validAddress(item.address, region)
        local label, name, lastSeen = item.label, item.name, item.lastSeen
        if not address or not categoryByKey[category] or not isstring(label) or #label > 128
            or not isstring(name) or #name > 512 or not timestamp(lastSeen) then cacheError = "Кэш повреждён" return end
        local key = recordKey(region, address)
        if seen[key] then cacheError = "Повтор адреса в кэше" return end
        seen[key] = true
        if lastSeen == 0 then
            dropped = true
        else
            if name ~= "" then
                local recognized, newLabel = classifyServer(name)
                if recognized ~= "unknown" then category, label = recognized, newLabel end
            end
            loaded[key] = { region = region, address = address, category = category, label = label, name = name,
                lastSeen = lastSeen, number = tonumber(label:match("(%d+)$")), status = "Сохранён" }
        end
    end
    if data.version == 2 then
        if not istable(data.nodes) or not istable(data.scans) then cacheError = "Кэш узлов повреждён" return end
        for _, region in ipairs(regions) do
            local snapshot, scan = data.nodes[region.key], data.scans[region.key]
            if snapshot then
                if not istable(snapshot) or not timestamp(snapshot.fetchedAt)
                    or not denseArray(snapshot.ips, MAX_NODES, false) then cacheError = "Кэш узлов повреждён" return end
                local ips, seen = {}, {}
                for _, value in ipairs(snapshot.ips) do
                    local ip = publicIP(value)
                    if not ip or seen[ip] then cacheError = "Кэш узлов повреждён" return end
                    ips[#ips + 1], seen[ip] = ip, true
                end
                loadedNodes[region.key] = { ips = ips, fetchedAt = snapshot.fetchedAt }
            end
            if scan then
                if not istable(scan) or not timestamp(scan.attemptedAt) or (scan.scannedAt and not timestamp(scan.scannedAt))
                    or not isbool(scan.complete) then cacheError = "Кэш поиска повреждён" return end
                loadedScans[region.key] = { attemptedAt = scan.attemptedAt, scannedAt = scan.scannedAt, complete = scan.complete }
            end
        end
    end
    records, nodeCache, scans = loaded, loadedNodes, dropped and {} or loadedScans
    cacheProtected = false
    if dropped then dirty = true end
end
local function saveCache()
    if cacheProtected then return false end
    local entries = {}
    for _, record in pairs(records) do
        entries[#entries + 1] = { region = record.region, category = record.category, address = record.address,
            label = record.label, name = record.name, lastSeen = record.lastSeen }
    end
    table.sort(entries, compareRecords)
    local json = util.TableToJSON({ version = 2, servers = entries, nodes = nodeCache, scans = scans,
        counts = { cis = countsFor("cis"), eu = countsFor("eu") } })
    if not json then cacheError = "Не удалось подготовить кэш" return false end
    local ok = pcall(file.Write, cachePath, json)
    if not ok or file.Read(cachePath, "DATA") ~= json then cacheError = "Не удалось сохранить список" return false end
    dirty, cacheError = false, nil
    return true
end
loadCache()

local function requestNodes(region, alive, callback)
    local function attempt(index)
        if not alive() then return end
        local done = false
        local function finish(ips, problem)
            if done or not alive() then return end
            done = true
            if ips then
                nodeCache[region.key] = { ips = ips, fetchedAt = os.time() }
                dirty = true
                callback(ips, nil, false)
            elseif index < #region.urls then
                attempt(index + 1)
            else
                local cached = nodeCache[region.key]
                callback(cached and cached.ips or nil, problem or "Узлы недоступны", cached ~= nil)
            end
        end
        timer.Simple(TIMEOUT, function() finish(nil, "Тайм-аут /nodes") end)
        local ok, accepted = pcall(HTTP, {
            url = region.urls[index], method = "get", timeout = TIMEOUT,
            success = function(code, body)
                if done or not alive() then return end
                if code ~= 200 then finish(nil, "HTTP " .. tostring(code)) return end
                finish(parseNodes(body))
            end,
            failed = function() finish(nil, "Ошибка сети /nodes") end,
        })
        if not ok or accepted == false then finish(nil, "Запрос /nodes не принят") end
    end
    attempt(1)
end
local function pingAddress(address, alive, callback)
    local done = false
    local function finish(...)
        if done or not alive() then return end
        done = true
        callback(...)
    end
    timer.Simple(TIMEOUT, function() finish() end)
    local ok = pcall(serverlist.PingServer, address, finish)
    if not ok then finish() end
end
local function buildTargets(nodes)
    local queues, indexes, result = {}, {}, {}
    for index, region in ipairs(regions) do
        queues[index], indexes[index] = {}, 1
        for _, ip in ipairs(nodes[region.key] or {}) do
            for port = region.first, region.last do
                queues[index][#queues[index] + 1] = { region = region.key, address = ip .. ":" .. port }
            end
        end
    end
    local added = true
    while added do
        added = false
        for index, queue in ipairs(queues) do
            local target = queue[indexes[index]]
            if target then result[#result + 1], indexes[index], added = target, indexes[index] + 1, true end
        end
    end
    return result
end

surface.CreateFont("ShinriTitle", { font = "Arial", size = 23, weight = 700, extended = true })
surface.CreateFont("ShinriBody", { font = "Arial", size = 16, weight = 500, extended = true })
surface.CreateFont("ShinriSmall", { font = "Arial", size = 14, weight = 500, extended = true })
local colors = {
    background = Color(18, 20, 27), panel = Color(26, 29, 38), row = Color(30, 34, 44),
    hover = Color(42, 47, 60), selected = Color(47, 58, 77), accent = Color(122, 161, 236),
    text = Color(230, 234, 243), muted = Color(155, 165, 182), warning = Color(233, 192, 122),
}
local function styleButton(button, primary)
    button:SetFont("ShinriBody")
    button:SetTextColor(colors.text)
    button.Paint = function(self, w, h)
        local bg = self:IsEnabled() and (self:IsHovered() and colors.hover or colors.row) or colors.panel
        if primary and self:IsEnabled() then bg = self:IsHovered() and Color(106, 144, 218) or colors.accent end
        draw.RoundedBox(6, 0, 0, w, h, bg)
        self:SetTextColor(not self:IsEnabled() and colors.muted or (primary and colors.background or colors.text))
    end
end
local frame, operationSerial
operationSerial = 0
local function openBrowser()
    if IsValid(frame) then frame:MakePopup() return end
    local windowLanguage = currentLanguage()
    local browser = vgui.Create("DFrame")
    frame = browser
    browser:SetTitle("")
    browser:ShowCloseButton(false)
    browser:SetSize(math.max(320, math.min(1120, ScrW() - 40)), math.max(420, math.min(760, ScrH() - 40)))
    browser:Center()
    browser:MakePopup()
    browser:DockPadding(16, 52, 16, 16)
    browser.Paint = function(_, w, h)
        draw.RoundedBox(10, 0, 0, w, h, colors.background)
        draw.SimpleText(tr("Серверы Shinri", windowLanguage), "ShinriTitle", 18, 15, colors.text)
    end
    local close = vgui.Create("DButton", browser)
    close:SetSize(32, 30)
    close:SetText("×")
    styleButton(close, false)
    close.Think = function(self) self:SetPos(browser:GetWide() - 48, 12) end
    close.DoClick = function() browser:Close() end

    local activeRegion, activeCategory = "cis", "lobby"
    local regionButtons, categoryButtons, lists, rows = {}, {}, {}, {}
    local selectedKey, operation, sortDirty = nil, nil, false
    local recordCount = 0
    for _ in pairs(records) do recordCount = recordCount + 1 end
    local statusText = tr("Сохранённые серверы. Полное обновление ищет оба региона.", windowLanguage)
    local regionBar = vgui.Create("DPanel", browser)
    regionBar:Dock(TOP)
    regionBar:SetTall(38)
    regionBar.Paint = nil
    local categoryBar = vgui.Create("DPanel", browser)
    categoryBar:Dock(TOP)
    categoryBar:DockMargin(0, 4, 0, 0)
    categoryBar:SetTall(34)
    categoryBar.Paint = nil
    local notes = vgui.Create("DPanel", browser)
    notes:Dock(TOP)
    notes:DockMargin(0, 6, 0, 6)
    notes:SetTall(86)
    notes.Paint = nil
    local note = vgui.Create("DLabel", notes)
    note:Dock(TOP)
    note:SetTall(60)
    note:SetFont("ShinriSmall")
    note:SetTextColor(colors.muted)
    note:SetWrap(true)
    local diagnostics = vgui.Create("DButton", notes)
    diagnostics:Dock(TOP)
    diagnostics:SetTall(22)
    diagnostics:SetFont("ShinriSmall")
    diagnostics:SetTextColor(colors.warning)
    diagnostics:SetContentAlignment(4)
    diagnostics.Paint = nil
    local actions = vgui.Create("DPanel", browser)
    actions:Dock(BOTTOM)
    actions:SetTall(46)
    actions.Paint = nil
    local refresh = vgui.Create("DButton", actions)
    refresh:SetText(tr("Обновить статус", windowLanguage))
    local fullRefresh = vgui.Create("DButton", actions)
    fullRefresh:SetText(tr("Полное обновление", windowLanguage))
    local stop = vgui.Create("DButton", actions)
    stop:SetText(tr("Остановить", windowLanguage))
    stop:SetEnabled(false)
    local connect = vgui.Create("DButton", actions)
    connect:SetText(tr("Подключиться", windowLanguage))
    connect:SetEnabled(false)
    for _, button in ipairs({ refresh, fullRefresh, stop }) do styleButton(button, false) end
    styleButton(connect, true)
    actions.PerformLayout = function(self, w)
        local columns = w >= 780 and 4 or (w >= 370 and 2 or 1)
        local width = math.floor((w - (columns - 1) * 8) / columns)
        self:SetTall(math.ceil(4 / columns) * 42 + 4)
        for index, button in ipairs({ refresh, fullRefresh, stop, connect }) do
            button:SetSize(width, 34)
            button:SetPos(((index - 1) % columns) * (width + 8), math.floor((index - 1) / columns) * 42 + 8)
        end
    end
    local content = vgui.Create("DPanel", browser)
    content:Dock(FILL)
    content.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, colors.panel) end
    local empty = vgui.Create("DLabel", content)
    empty:SetFont("ShinriBody")
    empty:SetTextColor(colors.muted)
    empty:SetContentAlignment(5)
    empty:SetWrap(true)
    empty:SetZPos(10)
    content.PerformLayout = function(_, w, h) empty:SetPos(12, 12) empty:SetSize(w - 24, math.max(40, h - 24)) end

    local function updateConnect()
        local record = selectedKey and records[selectedKey]
        connect:SetEnabled(record ~= nil and record.region == activeRegion and record.category == activeCategory
            and validAddress(record.address, record.region) ~= nil)
    end
    local function join(record)
        if record and record.region == activeRegion and record.category == activeCategory then
            local address = validAddress(record.address, record.region)
            if address then JoinServer(address) end
        end
    end
    connect.DoClick = function() join(selectedKey and records[selectedKey]) end
    local function updateNavigation()
        local activeCounts
        for _, region in ipairs(regions) do
            local counts = countsFor(region.key)
            if region.key == activeRegion then activeCounts = counts end
            regionButtons[region.key]:SetText(region.label .. "  /  " .. counts.total)
        end
        local counts = activeCounts
        for _, category in ipairs(categories) do
            local label = tr(category.label, windowLanguage)
            if categoryBar:GetWide() < 520 and category.key == "quick" then label = tr("Быстрые", windowLanguage) end
            categoryButtons[category.key]:SetText(label .. "  " .. counts[category.key])
        end
        diagnostics:SetText(tr("Не распознано: ", windowLanguage) .. counts.unknown .. tr(" — показать имена", windowLanguage))
        diagnostics:SetEnabled(counts.unknown > 0)
        empty:SetVisible(counts[activeCategory] == 0)
        empty:SetText(operation and tr("Поиск продолжается. Серверы появятся по мере ответов.", windowLanguage)
            or tr("Серверов этого типа пока нет. Нажмите «Полное обновление».", windowLanguage))
        updateConnect()
    end
    local function selectView(region, category)
        selectedKey = nil
        activeRegion, activeCategory = region, category
        for regionKey, regionLists in pairs(lists) do
            for categoryKey, list in pairs(regionLists) do
                list:ClearSelection()
                list:SetVisible(regionKey == region and categoryKey == category)
            end
        end
        updateNavigation()
    end
    local function styleTab(button, selected, large)
        button:SetFont(large and "ShinriBody" or "ShinriSmall")
        button:SetTextColor(colors.text)
        button.Paint = function(self, w, h)
            if selected() or self:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, selected() and colors.selected or colors.row) end
            if selected() then surface.SetDrawColor(colors.accent) surface.DrawRect(6, h - 2, w - 12, 2) end
        end
    end
    for _, region in ipairs(regions) do
        local key = region.key
        local button = vgui.Create("DButton", regionBar)
        styleTab(button, function() return activeRegion == key end, true)
        button.DoClick = function() selectView(key, activeCategory) end
        regionButtons[key] = button
    end
    regionBar.PerformLayout = function(_, w, h)
        local width = math.floor((w - 8) / 2)
        for index, region in ipairs(regions) do
            regionButtons[region.key]:SetPos((index - 1) * (width + 8), 0)
            regionButtons[region.key]:SetSize(width, h)
        end
    end
    for _, category in ipairs(categories) do
        local key = category.key
        local button = vgui.Create("DButton", categoryBar)
        styleTab(button, function() return activeCategory == key end, false)
        button.DoClick = function() selectView(activeRegion, key) end
        categoryButtons[key] = button
    end
    categoryBar.PerformLayout = function(_, w, h)
        local width = math.floor((w - 12) / 4)
        for index, category in ipairs(categories) do
            categoryButtons[category.key]:SetPos((index - 1) * (width + 4), 0)
            categoryButtons[category.key]:SetSize(width, h)
        end
    end
    for _, region in ipairs(regions) do
        lists[region.key] = {}
        for _, category in ipairs(categories) do
            local list = vgui.Create("DListView", content)
            list:Dock(FILL)
            list:SetVisible(region.key == activeRegion and category.key == activeCategory)
            list:SetMultiSelect(false)
            list:SetDataHeight(30)
            list.Paint = nil
            local specs = { { tr("СЕРВЕР", windowLanguage), nil }, { tr("ИГРОКИ", windowLanguage), 70 }, { tr("КАРТА", windowLanguage), nil },
                { tr("ПИНГ", windowLanguage), 50 }, { tr("АДРЕС", windowLanguage), 160 }, { tr("СТАТУС", windowLanguage), 95 } }
            for _, spec in ipairs(specs) do
                local column = list:AddColumn(spec[1])
                if spec[2] then column:SetFixedWidth(spec[2]) end
                column.Header:SetFont("ShinriSmall")
                column.Header:SetTextColor(colors.muted)
                column.Header.Paint = function(_, w, h) surface.SetDrawColor(colors.panel) surface.DrawRect(0, 0, w, h) end
            end
            list.OnRowSelected = function(_, _, line)
                selectedKey = IsValid(line) and line.shinriKey or nil
                updateConnect()
            end
            list.DoDoubleClick = function(_, _, line) if IsValid(line) then join(records[line.shinriKey]) end end
            lists[region.key][category.key] = list
        end
    end
    local lastWidth
    local function fitColumns()
        local w = content:GetWide()
        if w == lastWidth then return end
        lastWidth = w
        for _, regionLists in pairs(lists) do
            for _, list in pairs(regionLists) do
                list.Columns[3]:SetFixedWidth(w < 760 and 0 or 170)
                list.Columns[5]:SetFixedWidth(w < 620 and 0 or 160)
                list.Columns[2]:SetFixedWidth(w < 400 and 52 or 70)
                list.Columns[4]:SetFixedWidth(w < 400 and 36 or 50)
                list.Columns[6]:SetFixedWidth(w < 400 and 74 or 95)
            end
        end
        updateNavigation()
    end
    local function updateRow(key, navigationChanged)
        local record, line = records[key], rows[key]
        local destination = record.category ~= "unknown" and lists[record.region][record.category] or nil
        if IsValid(line) and line:GetListView() ~= destination then
            line:GetListView():RemoveLine(line:GetID())
            rows[key], line = nil, nil
            if selectedKey == key then selectedKey = nil end
        end
        if not destination then
            if navigationChanged then updateNavigation() end
            return
        end
        if not IsValid(line) then
            line = destination:AddLine("", "", "", "", "", "")
            line.shinriKey = key
            line.Paint = function(self, w, h)
                local bg = self:IsLineSelected() and colors.selected or (self:IsHovered() and colors.hover or colors.row)
                surface.SetDrawColor(bg) surface.DrawRect(0, 1, w, h - 2)
            end
            for _, column in ipairs(line.Columns) do column:SetFont("ShinriSmall") column:SetTextColor(colors.text) end
            rows[key] = line
        end
        line:SetColumnText(1, record.name ~= "" and record.name or ((record.category == "lobby" and tr("Лобби", windowLanguage) or tr("Игровые", windowLanguage)) .. (record.number and (" " .. record.number) or "")))
        line:SetColumnText(2, record.info and (record.info.players .. "/" .. record.info.maxplayers) or "—")
        line:SetColumnText(3, record.info and record.info.map or "—")
        line:SetColumnText(4, record.info and record.info.ping or "—")
        line:SetColumnText(5, record.address)
        line:SetColumnText(6, tr(record.status or "Сохранён", windowLanguage))
        line:SetSortValue(1, record.number or 999999)
        line:SetTooltip(record.address .. tr("\nПоследний ответ: ", windowLanguage) .. os.date("%d.%m.%Y %H:%M", record.lastSeen))
        sortDirty = true
        if navigationChanged then updateNavigation() end
    end
    for key in pairs(records) do updateRow(key) end
    diagnostics.DoClick = function()
        local popup = vgui.Create("DFrame", browser)
        popup:SetTitle(tr("Нераспознанные серверы — ", windowLanguage) .. regionByKey[activeRegion].label)
        popup:SetSize(math.min(900, ScrW() - 40), math.min(430, ScrH() - 40))
        popup:Center()
        popup:MakePopup()
        local list = vgui.Create("DListView", popup)
        list:Dock(FILL)
        list:AddColumn(tr("Название", windowLanguage))
        list:AddColumn(tr("Адрес", windowLanguage)):SetFixedWidth(170)
        for _, record in pairs(records) do
            if record.region == activeRegion and record.category == "unknown" then list:AddLine(record.name, record.address) end
        end
    end
    local function setBusy(value)
        refresh:SetEnabled(not value)
        fullRefresh:SetEnabled(not value)
        stop:SetEnabled(value)
        updateNavigation()
    end
    local function renderProgress()
        if not operation then note:SetText(statusText .. (cacheError and ("\n" .. tr(cacheError, windowLanguage)) or "")) return end
        local parts = {}
        for _, region in ipairs(regions) do
            local state = operation.stats[region.key]
            local text = region.label .. ": "
            if state.loading then text = text .. tr("получение узлов", windowLanguage)
            elseif state.error and state.total == 0 then text = text .. tr(state.error, windowLanguage)
            else text = text .. state.completed .. "/" .. state.total .. tr("; ответили ", windowLanguage) .. state.replied
                .. tr("; узлов ", windowLanguage) .. (state.nodes or 0) end
            if state.cached then text = text .. tr(" (кэш ", windowLanguage) .. os.date("%d.%m %H:%M", nodeCache[region.key].fetchedAt) .. ")" end
            parts[#parts + 1] = text
        end
        note:SetText(table.concat(parts, "\n") .. (cacheError and ("\n" .. tr(cacheError, windowLanguage)) or ""))
    end
    local function alive(op) return IsValid(browser) and operation == op end
    local function flushCache() if dirty then saveCache() end end
    local function cancel(closing)
        local op = operation
        if op then
            operation = nil
            timer.Remove(op.timer)
            statusText = tr(cacheProtected and "Поиск остановлен. Старый кэш сохранён без изменений."
                or "Поиск остановлен. Подтверждённые находки сохранены.", windowLanguage)
            if not closing then
                for key, record in pairs(records) do
                    if record.status == "Запрос..." then
                        record.status = "Сохранён"
                        updateRow(key)
                    end
                end
            end
        end
        flushCache()
        if not closing then setBusy(false) renderProgress() end
    end
    stop.DoClick = function() cancel(false) end
    browser.OnRemove = function() cancel(true) end
    local function beginOperation(kind)
        if operation then cancel(false) end
        operationSerial = operationSerial + 1
        local op = { kind = kind, timer = "ShinriServerBrowserQueue_" .. operationSerial, stats = {} }
        for _, region in ipairs(regions) do
            op.stats[region.key] = { total = 0, completed = 0, replied = 0, loading = kind == "full" }
            if kind == "full" then
                local previous = scans[region.key]
                scans[region.key] = { attemptedAt = os.time(), scannedAt = previous and previous.scannedAt, complete = false }
                dirty = true
            end
        end
        operation = op
        for key, record in pairs(records) do
            record.status = "Сохранён"
            updateRow(key)
        end
        setBusy(true)
        renderProgress()
        return op
    end
    local function acceptReply(target, ping, name, map, players, maxplayers)
        local key = recordKey(target.region, target.address)
        local record = records[key]
        if not isstring(name) then
            if record then record.status = "Нет ответа" updateRow(key) end
            return false
        end
        local category, label, number = classifyServer(name)
        local navigationChanged = not record or record.category ~= category
        if not record then
            if recordCount >= MAX_RECORDS then cacheError = "Достигнут лимит сохранённых адресов" return true end
            record = { region = target.region, address = target.address }
            records[key] = record
            recordCount = recordCount + 1
        end
        record.name, record.label, record.number, record.category = name:sub(1, 512), label, number, category
        cacheProtected = false
        record.lastSeen, record.status = os.time(), "Ответил"
        record.info = { players = tostring(players or 0), maxplayers = tostring(maxplayers or 0),
            map = tostring(map or "—"), ping = tostring(ping or "—") }
        dirty = true
        updateRow(key, navigationChanged)
        return true
    end
    local function finishOperation(op)
        if not alive(op) then return end
        timer.Remove(op.timer)
        local summaries = {}
        for _, region in ipairs(regions) do
            local state = op.stats[region.key]
            if op.kind == "full" and state.total > 0 then
                scans[region.key].complete = not state.cached and not state.error
                if scans[region.key].complete then scans[region.key].scannedAt = os.time() end
                dirty = true
            end
            summaries[#summaries + 1] = region.label .. ": " .. state.completed .. "/" .. state.total .. tr(", ответили ", windowLanguage) .. state.replied
                .. (state.error and ("; " .. tr(state.error, windowLanguage)) or "")
        end
        operation = nil
        flushCache()
        statusText = table.concat(summaries, "\n") .. tr("\nНет ответа не означает, что сервер выключен.", windowLanguage)
        setBusy(false)
        renderProgress()
    end
    local function runTargets(op, targets)
        if not alive(op) then return end
        for _, target in ipairs(targets) do op.stats[target.region].total = op.stats[target.region].total + 1 end
        local nextIndex, active, completed = 1, 0, 0
        if #targets == 0 then finishOperation(op) return end
        local function pump()
            if not alive(op) then timer.Remove(op.timer) return end
            if active >= 16 or nextIndex > #targets then return end
            local target = targets[nextIndex]
            nextIndex, active = nextIndex + 1, active + 1
            local key = recordKey(target.region, target.address)
            if records[key] then records[key].status = "Запрос..." updateRow(key) end
            pingAddress(target.address, function() return alive(op) end, function(ping, name, desc, map, players, maxplayers)
                if not alive(op) then return end
                local replied = acceptReply(target, ping, name, map, players, maxplayers)
                local state = op.stats[target.region]
                state.completed = state.completed + 1
                state.replied = state.replied + (replied and 1 or 0)
                active, completed = active - 1, completed + 1
                renderProgress()
                if completed == #targets then finishOperation(op) end
            end)
        end
        renderProgress()
        timer.Create(op.timer, 0.1, 0, pump)
        pump()
    end
    local function fullUpdate()
        local op = beginOperation("full")
        local nodes, remaining = {}, #regions
        for _, region in ipairs(regions) do
            requestNodes(region, function() return alive(op) end, function(ips, problem, cached)
                if not alive(op) then return end
                nodes[region.key] = ips
                local state = op.stats[region.key]
                state.loading, state.error, state.cached, state.nodes = false, problem, cached, ips and #ips or 0
                remaining = remaining - 1
                renderProgress()
                if remaining == 0 then runTargets(op, buildTargets(nodes)) end
            end)
        end
    end
    local function updateStatus()
        local op, targets = beginOperation("status"), {}
        for _, record in pairs(records) do targets[#targets + 1] = { region = record.region, address = record.address } end
        table.sort(targets, compareRecords)
        runTargets(op, targets)
    end
    fullRefresh.DoClick, refresh.DoClick = fullUpdate, updateStatus
    local nextSave, nextSort = SysTime() + 5, SysTime() + 1
    local frameThink = browser.Think
    browser.Think = function(self)
        if frameThink then frameThink(self) end
        fitColumns()
        local now = SysTime()
        if now >= nextSave then flushCache() nextSave = now + 5 end
        if sortDirty and now >= nextSort then
            for _, regionLists in pairs(lists) do for _, list in pairs(regionLists) do list:SortByColumn(1) end end
            sortDirty, nextSort = false, now + 1
        end
    end
    updateNavigation()
    renderProgress()
    local scanned = scans.cis and scans.cis.scannedAt and scans.eu and scans.eu.scannedAt
    if scanned then updateStatus() else fullUpdate() end
end

local function installButton()
    if not IsValid(pnlMainMenu) or IsValid(pnlMainMenu.ShinriServerButton) then return end
    local button = vgui.Create("DButton", pnlMainMenu)
    button:SetText(tr("Серверы Shinri   →"))
    button:SetSize(180, 36)
    -- Leave room for the standard lower-right menu buttons.
    local function positionButton(self, parent)
        local x = math.max(16, parent:GetWide() - self:GetWide() - 345)
        local y = math.max(0, parent:GetTall() - self:GetTall() - 7)
        self:SetPos(x, y)
    end
    positionButton(button, pnlMainMenu)
    button:SetZPos(1000)
    button.Think = function(self)
        self:SetText(tr("Серверы Shinri   →"))
        local parent = self:GetParent()
        if IsValid(parent) then positionButton(self, parent) end
    end
    styleButton(button, false)
    button.DoClick = openBrowser
    pnlMainMenu.ShinriServerButton = button
end

timer.Create("ShinriServerBrowserInstall", 1, 0, installButton)
installButton()
