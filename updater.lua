-- rakbot multi-file updater v3
-- GitHub version.json manifest asosida fayllarni tekshiradi va xavfsiz yangilaydi.
local requests = require("requests")
local json = require("cjson")

local BASE_URL = "https://raw.githubusercontent.com/azimdca33-ship/farm/main/"
local MANIFEST_URL = BASE_URL .. "version.json"
local STATE_FILE = "settings\\update_state.json"
local CACHE_BUSTER = true
local MAX_RETRIES = 3

local function log(msg)
    print("[UPDATER] " .. tostring(msg))
end

local function get(url)
    for attempt = 1, MAX_RETRIES do
        local full = url
        if CACHE_BUSTER then
            full = url .. (url:find("?", 1, true) and "&" or "?") .. "nocache=" .. os.time() .. "_" .. attempt
        end
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

local function digest(data)
    for _, module_name in ipairs({ "sha256", "sha2", "crypto.sha256" }) do
        local ok, mod = pcall(require, module_name)
        if ok and mod then
            if type(mod) == "function" then
                local ok2, out = pcall(mod, data)
                if ok2 and type(out) == "string" then return out:lower() end
            elseif type(mod) == "table" then
                for _, fn in ipairs({ "digest", "sha256", "hash", "sum" }) do
                    if type(mod[fn]) == "function" then
                        local ok2, out = pcall(mod[fn], data)
                        if ok2 and type(out) == "string" then return out:lower() end
                    end
                end
            end
        end
    end
    return nil
end

local function parseJSON(text)
    local ok, data = pcall(json.decode, text or "")
    if ok and type(data) == "table" then return data end
    return nil
end

local function localVersion(state, path)
    if state and state.files and state.files[path] then
        return tonumber(state.files[path].version) or 0
    end
    return 0
end

local function saveState(state)
    pcall(function() writeAll(STATE_FILE, json.encode(state)) end)
end

local function validFile(body, entry)
    if type(body) ~= "string" or body == "" then return false, "bo'sh fayl" end
    if entry.min_size and #body < tonumber(entry.min_size) then
        return false, "fayl juda kichik"
    end
    if entry.type == "lua" then
        if body:match("^%s*<") then return false, "HTML keldi, Lua emas" end
        if loadstring then
            local chunk, err = loadstring(body, entry.path)
            if not chunk then return false, "Lua sintaksis xatosi: " .. tostring(err) end
        end
    elseif entry.type == "json" then
        if not parseJSON(body) then return false, "JSON yaroqsiz" end
    end
    return true
end

local function updateOne(entry, state)
    local path = assert(entry.path, "manifest path yo'q")
    local target = assert(entry.target, "manifest target yo'q")
    local remote_version = tonumber(entry.version) or 0
    if remote_version <= localVersion(state, path) then return nil end

    local body = get(BASE_URL .. path)
    if not body then return "[UPDATE] " .. path .. ": yuklab bo'lmadi" end
    local ok, why = validFile(body, entry)
    if not ok then return "[UPDATE] " .. path .. ": " .. why end

    local expected = tostring(entry.sha256 or ""):match("%x%x%x%x%x%x%x%x+")
    local actual = digest(body)
    if expected and actual and expected:lower() ~= actual:lower() then
        return "[UPDATE] " .. path .. ": SHA-256 mos kelmadi"
    end
    if expected and not actual then log(path .. ": sha256 moduli yo'q, sintaksis tekshiruvi ishladi") end

    local old = readAll(target)
    if old and old == body then
        state.files[path] = { version = remote_version, updated_at = os.time() }
        return nil
    end
    if old and entry.backup ~= false then
        if not writeAll(target .. ".backup", old) then return "[UPDATE] " .. path .. ": backup yaratilmadi" end
    end
    if not writeAll(target, body) then
        if old then writeAll(target, old) end
        return "[UPDATE] " .. path .. ": yozilmadi"
    end
    if readAll(target) ~= body then
        if old then writeAll(target, old) end
        return "[UPDATE] " .. path .. ": qayta o'qish tekshiruvi yiqildi"
    end
    state.files[path] = { version = remote_version, updated_at = os.time() }
    return "[UPDATE] " .. path .. ": v" .. remote_version .. " o'rnatildi"
end

function checkAndUpdate(current_admin_version)
    local manifest = parseJSON(get(MANIFEST_URL))
    if not manifest or type(manifest.files) ~= "table" then
        return "[UPDATE] version.json manifesti o'qilmadi"
    end

    local state = parseJSON(readAll(STATE_FILE) or "{}") or {}
    state.files = state.files or {}
    local messages = {}
    local changed = false

    for _, entry in ipairs(manifest.files) do
        local msg = updateOne(entry, state)
        if msg then
            table.insert(messages, msg)
            if msg:find("o'rnatildi", 1, true) then changed = true end
        end
    end
    saveState(state)

    if changed then
        table.insert(messages, "[UPDATE] Yangilanish tugadi. Botni restart qiling.")
    end
    if #messages == 0 then return nil end
    return table.concat(messages, "\n")
end

return { checkAndUpdate = checkAndUpdate }
