-- rakbot updater v3.1
-- Safe cleanup: backup fayllarini yashirmaydi, o'chirishdan oldin inventarizatsiya qiladi.
local requests = require("requests")
local json = require("cjson")

local BASE_URL = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/"
local MANIFEST_URL = BASE_URL .. "version.json"
local STATE_FILE = "settings\\update_state.json"
local INVENTORY_FILE = "settings\\backup_inventory.json"
local BACKUP_DIR = "settings\\backups"
local MAX_RETRIES = 3
local BACKUP_RETENTION_DAYS = 7
local MAX_BACKUPS_PER_FILE = 3

local function log(msg)
    print("[UPDATER] " .. tostring(msg))
end

local function now()
    return os.time()
end

local function get(url)
    for attempt = 1, MAX_RETRIES do
        local full = url .. (url:find("?", 1, true) and "&" or "?") ..
            "nocache=" .. tostring(now()) .. "_" .. tostring(attempt)
        local ok, res = pcall(function()
            return requests.get(full, {
                timeout = 15,
                headers = { ["Cache-Control"] = "no-cache", ["Pragma"] = "no-cache" }
            })
        end)
        if ok and res and res.status_code == 200 and type(res.text) == "string" and res.text ~= "" then
            return res.text
        end
        if attempt < MAX_RETRIES and wait then wait(1000) end
    end
    return nil
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function writeAll(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    local ok = pcall(function() f:write(data) end)
    f:close()
    return ok
end

local function parseJSON(text)
    local ok, data = pcall(json.decode, text or "")
    if ok and type(data) == "table" then return data end
    return nil
end

local function loadTable(path, fallback)
    return parseJSON(readAll(path) or "") or fallback
end

local function saveTable(path, value)
    local encoded = json.encode(value)
    if not encoded then return false end
    return writeAll(path, encoded)
end

local function ensureDir(path)
    -- Windows/RakSAMP: md mavjud bo'lmasa ham yangilanish davom etadi.
    -- Backup papkasini oldindan yaratish uchun updater ishga tushirilgan katalogdan foydalanadi.
    local ok = os.execute('if not exist "' .. path .. '" mkdir "' .. path .. '"')
    return ok == true or ok == 0
end

local function fileSize(path)
    local data = readAll(path)
    return data and #data or 0
end

local function safeName(path)
    return tostring(path):gsub("[^%w%._%-]", "_")
end

local function backupPath(target, version)
    return BACKUP_DIR .. "\\" .. safeName(target) .. ".v" .. tostring(version):gsub("%.", "_") .. ".backup"
end

local function addInventory(inventory, entry)
    table.insert(inventory.items, entry)
    inventory.updated_at = now()
end

local function inventoryBackup(inventory, path, target, version, reason)
    local data = readAll(path)
    if not data then return nil end
    ensureDir(BACKUP_DIR)
    local dest = backupPath(target, version)
    if not writeAll(dest, data) then return nil end
    local item = {
        path = dest,
        target = target,
        version = tonumber(version) or 0,
        size = #data,
        created_at = now(),
        reason = reason or "update"
    }
    addInventory(inventory, item)
    return dest
end

local function cleanupBackups(inventory)
    local kept = {}
    local grouped = {}
    local cutoff = now() - (BACKUP_RETENTION_DAYS * 86400)

    for _, item in ipairs(inventory.items or {}) do
        if item.path and readAll(item.path) then
            grouped[item.target or item.path] = grouped[item.target or item.path] or {}
            table.insert(grouped[item.target or item.path], item)
        end
    end

    for target, items in pairs(grouped) do
        table.sort(items, function(a, b)
            return (tonumber(a.created_at) or 0) > (tonumber(b.created_at) or 0)
        end)
        for index, item in ipairs(items) do
            local ageExpired = (tonumber(item.created_at) or 0) < cutoff
            local overLimit = index > MAX_BACKUPS_PER_FILE
            if ageExpired or overLimit then
                -- Faqat inventorydagi, backup papkasidagi fayl o'chiriladi.
                local normalized = tostring(item.path):gsub("/", "\\")
                if normalized:lower():find(BACKUP_DIR:lower(), 1, true) == 1 then
                    os.remove(item.path)
                    log("cleanup: " .. item.path)
                end
            else
                table.insert(kept, item)
            end
        end
    end
    inventory.items = kept
    inventory.updated_at = now()
end

local function validate(body, entry)
    if type(body) ~= "string" or body == "" then return false, "bo'sh fayl" end
    if entry.min_size and #body < tonumber(entry.min_size) then return false, "fayl juda kichik" end
    if entry.type == "lua" then
        if body:match("^%s*<") then return false, "HTML keldi, Lua emas" end
        if loadstring then
            local chunk, err = loadstring(body, entry.path)
            if not chunk then return false, "Lua sintaksis xatosi: " .. tostring(err) end
        end
    elseif entry.type == "json" and not parseJSON(body) then
        return false, "JSON yaroqsiz"
    end
    return true
end

local function updateOne(entry, state, inventory)
    local path = assert(entry.path, "manifest path yo'q")
    local target = assert(entry.target, "manifest target yo'q")
    local remoteVersion = tonumber(entry.version) or 0
    local localVersion = tonumber(state.files[path] and state.files[path].version) or 0
    if remoteVersion <= localVersion then return nil end

    local body = get(BASE_URL .. path)
    if not body then return "[UPDATE] " .. path .. ": yuklab bo'lmadi" end
    local valid, reason = validate(body, entry)
    if not valid then return "[UPDATE] " .. path .. ": " .. reason end

    local old = readAll(target)
    if old and old == body then
        state.files[path] = { version = remoteVersion, updated_at = now() }
        return nil
    end

    if old and entry.backup ~= false then
        local saved = inventoryBackup(inventory, target, target, localVersion > 0 and localVersion or "old", "before_update")
        if not saved then return "[UPDATE] " .. path .. ": backup yaratilmadi" end
    end

    if not writeAll(target, body) then
        if old then writeAll(target, old) end
        return "[UPDATE] " .. path .. ": yozilmadi" end
    if readAll(target) ~= body then
        if old then writeAll(target, old) end
        return "[UPDATE] " .. path .. ": tekshiruv yiqildi" end

    state.files[path] = { version = remoteVersion, updated_at = now() }
    return "[UPDATE] " .. path .. ": v" .. remoteVersion .. " o'rnatildi"
end

function checkAndUpdate(current_admin_version)
    local manifest = parseJSON(get(MANIFEST_URL))
    if not manifest or type(manifest.files) ~= "table" then
        return "[UPDATE] version.json manifesti o'qilmadi"
    end

    local state = loadTable(STATE_FILE, { files = {} })
    state.files = state.files or {}
    local inventory = loadTable(INVENTORY_FILE, { items = {}, updated_at = 0 })
    inventory.items = inventory.items or {}
    local messages = {}
    local changed = false

    -- Har bir ishga tushishda avval inventarizatsiya tozalanadi.
    cleanupBackups(inventory)
    for _, entry in ipairs(manifest.files) do
        local msg = updateOne(entry, state, inventory)
        if msg then
            table.insert(messages, msg)
            if msg:find("o'rnatildi", 1, true) then changed = true end
        end
    end
    cleanupBackups(inventory)
    saveTable(state and STATE_FILE, state)
    saveTable(INVENTORY_FILE, inventory)

    if changed then table.insert(messages, "[UPDATE] Yangilanish tugadi. Backup inventari saqlandi.") end
    if #messages == 0 then return nil end
    return table.concat(messages, "\n")
end

return { checkAndUpdate = checkAndUpdate }
