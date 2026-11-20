-- English Online Language
-- Finds the "Preferred Online Language" setting in Blizzard's Settings panel
-- (Options > System > Languages and Social) and sets it to English when it
-- is set to anything else. Writes what it finds to SavedVariables so the
-- result can be checked outside the game.

local ADDON = ...
local PREFIX = "|cff33ff99EnglishOnlineLanguage|r: "

local SETTING_NAME_PATTERNS = { "online language", "preferred.*language" }
local ENGLISH_VALUES = { enUS = true, enGB = true, en = true, English = true, ENGLISH = true }

local db
local busy = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

local function Log(msg)
    if db then
        db.log = db.log or {}
        table.insert(db.log, date("%Y-%m-%d %H:%M:%S") .. "  " .. tostring(msg))
        while #db.log > 200 do table.remove(db.log, 1) end
    end
end

local function Call(obj, method, ...)
    if type(obj) == "table" and type(obj[method]) == "function" then
        local ok, a, b = pcall(obj[method], obj, ...)
        if ok then return a, b end
    end
end

---------------------------------------------------------------------------
-- Settings panel discovery
---------------------------------------------------------------------------

local function AllCategories()
    local result, seen = {}, {}
    local function add(cat)
        if type(cat) ~= "table" or seen[cat] then return end
        seen[cat] = true
        table.insert(result, cat)
        local subs = Call(cat, "GetSubcategories")
        if type(subs) == "table" then
            for _, sub in ipairs(subs) do add(sub) end
        end
    end
    local cats = SettingsPanel and Call(SettingsPanel, "GetAllCategories")
    if type(cats) == "table" then
        for _, cat in ipairs(cats) do add(cat) end
    end
    return result
end

local function InitializersOf(category)
    local layout = SettingsPanel and Call(SettingsPanel, "GetLayout", category)
    local inits = layout and Call(layout, "GetInitializers")
    return type(inits) == "table" and inits or {}
end

local function SettingOf(init)
    local setting = Call(init, "GetSetting")
    if not setting and type(init.data) == "table" then
        setting = init.data.setting
    end
    return setting
end

local function NameOf(init, setting)
    return Call(setting, "GetName")
        or (type(init.data) == "table" and init.data.name)
        or Call(init, "GetName")
end

local function MatchesName(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    for _, pattern in ipairs(SETTING_NAME_PATTERNS) do
        if lower:find(pattern) then return true end
    end
    return false
end

local function OptionsOf(init)
    local data = type(init.data) == "table" and init.data
    local options = data and data.options
    if type(options) == "function" then
        local ok, res = pcall(options)
        options = ok and res or nil
    end
    if type(options) == "table" and type(options.GetData) == "function" then
        options = Call(options, "GetData")
    end
    local list = {}
    if type(options) == "table" then
        for _, opt in ipairs(options) do
            if type(opt) == "table" then
                table.insert(list, { value = opt.value, label = opt.label or opt.text or opt.name })
            end
        end
    end
    return list
end

local function FindSetting()
    for _, category in ipairs(AllCategories()) do
        for _, init in ipairs(InitializersOf(category)) do
            local setting = SettingOf(init)
            local name = NameOf(init, setting)
            if setting and MatchesName(name) then
                return setting, init, name, Call(category, "GetName")
            end
        end
    end
end

local function IsEnglish(value, options)
    if ENGLISH_VALUES[value] then return true end
    for _, opt in ipairs(options) do
        if opt.value == value and type(opt.label) == "string" and opt.label:lower():find("english") then
            return true
        end
    end
    return false
end

local function EnglishOption(options)
    for _, opt in ipairs(options) do
        if ENGLISH_VALUES[opt.value] then return opt end
    end
    for _, opt in ipairs(options) do
        if type(opt.label) == "string" and opt.label:lower():find("english") then return opt end
    end
end

local function LabelFor(value, options)
    for _, opt in ipairs(options) do
        if opt.value == value then return opt.label end
    end
    return tostring(value)
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

local function Commit(setting)
    -- Settings with the "Apply" commit flag stay pending until committed,
    -- which is what the Apply button in the Options window does.
    local needsApply = Settings and Settings.CommitFlag and Settings.CommitFlag.Apply
        and Call(setting, "HasCommitFlag", Settings.CommitFlag.Apply)
    if needsApply and SettingsPanel and type(SettingsPanel.Commit) == "function" then
        local ok, err = pcall(SettingsPanel.Commit, SettingsPanel, true)
        Log("Commit (Apply) called: " .. (ok and "ok" or ("error: " .. tostring(err))))
    end
end

local function Run(reason, verbose)
    if busy then return end
    busy = true

    local setting, init, name, categoryName = FindSetting()
    if not setting then
        busy = false
        Log(reason .. ": setting not found")
        if verbose then Print("Could not find 'Preferred Online Language' in the Options window. Try /eol scan.") end
        return false
    end

    local options = OptionsOf(init)
    local current = Call(setting, "GetValue")
    db.found = {
        name = name,
        category = categoryName,
        variable = Call(setting, "GetVariable"),
        value = tostring(current),
        options = options,
    }

    if IsEnglish(current, options) then
        busy = false
        Log(reason .. ": already English (" .. tostring(current) .. ")")
        if verbose then Print("Preferred Online Language is already English.") end
        return true
    end

    local target = EnglishOption(options)
    if not target then
        busy = false
        Log(reason .. ": no English option found; current=" .. tostring(current))
        Print("Found the setting, but no English option. Try /eol scan.")
        return false
    end

    local ok, err = pcall(setting.SetValue, setting, target.value)
    if ok then Commit(setting) end
    local after = Call(setting, "GetValue")
    busy = false

    if ok and after == target.value then
        Log(reason .. ": changed " .. tostring(current) .. " -> " .. tostring(target.value))
        Print(("Preferred Online Language: %s -> %s"):format(LabelFor(current, options), tostring(target.label or target.value)))
        return true
    end
    Log(reason .. ": change failed; ok=" .. tostring(ok) .. " err=" .. tostring(err) .. " now=" .. tostring(after))
    Print("Could not change the setting (24h cooldown?). Current: " .. LabelFor(after, options))
    return false
end

---------------------------------------------------------------------------
-- Diagnostics: /eol scan
---------------------------------------------------------------------------

local function Scan()
    local out = {}
    local function add(s) table.insert(out, s); Print(s) end

    local setting, init, name, categoryName = FindSetting()
    if setting then
        add(("Setting: '%s' in '%s', variable=%s, value=%s"):format(
            tostring(name), tostring(categoryName), tostring(Call(setting, "GetVariable")), tostring(Call(setting, "GetValue"))))
        for _, opt in ipairs(OptionsOf(init)) do
            add(("  option value=%s label=%s"):format(tostring(opt.value), tostring(opt.label)))
        end
    else
        add("Setting not found by name. Settings with 'language' in their name:")
        for _, category in ipairs(AllCategories()) do
            for _, i in ipairs(InitializersOf(category)) do
                local s = SettingOf(i)
                local n = NameOf(i, s)
                if type(n) == "string" and n:lower():find("lang") then
                    add(("  '%s' in '%s' variable=%s"):format(n, tostring(Call(category, "GetName")), tostring(s and Call(s, "GetVariable"))))
                end
            end
        end
    end

    -- API functions with language/locale in their name
    for key, ns in pairs(_G) do
        if type(key) == "string" and key:sub(1, 2) == "C_" and type(ns) == "table" then
            for fname, fn in pairs(ns) do
                if type(fn) == "function" and type(fname) == "string"
                    and (fname:lower():find("language") or fname:lower():find("locale")) then
                    add("  API: " .. key .. "." .. fname)
                end
            end
        end
    end

    -- CVars with language/locale in their name
    if C_Console and C_Console.GetAllCommands then
        local ok, cmds = pcall(C_Console.GetAllCommands)
        if ok and type(cmds) == "table" then
            for _, c in ipairs(cmds) do
                local cmd = c.command
                if type(cmd) == "string" and (cmd:lower():find("lang") or cmd:lower():find("locale")) then
                    local v = GetCVar and GetCVar(cmd)
                    add("  CVar: " .. cmd .. " = " .. tostring(v))
                end
            end
        end
    end

    db.scan = { time = date("%Y-%m-%d %H:%M:%S"), lines = out }
    Print("Scan saved; it is written to disk on logout or /reload.")
end

---------------------------------------------------------------------------
-- Events and slash command
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        EnglishOnlineLanguageDB = EnglishOnlineLanguageDB or {}
        db = EnglishOnlineLanguageDB
        if db.enabled == nil then db.enabled = true end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
        if not (isLogin or isReload) or not db or not db.enabled then return end
        -- The value can arrive from the server a little after login, so check twice.
        C_Timer.After(5, function() Run("login") end)
        C_Timer.After(20, function() Run("login+20s") end)
        if SettingsPanel and not self.hooked then
            self.hooked = true
            SettingsPanel:HookScript("OnShow", function() C_Timer.After(0.5, function() Run("options opened") end) end)
        end
    end
end)

SLASH_ENGLISHONLINELANGUAGE1 = "/eol"
SlashCmdList.ENGLISHONLINELANGUAGE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "scan" then
        Scan()
    elseif msg == "on" then
        db.enabled = true; Print("Automatic fixing enabled.")
    elseif msg == "off" then
        db.enabled = false; Print("Automatic fixing disabled.")
    elseif msg == "" or msg == "fix" then
        Run("manual", true)
    else
        Print("/eol - set to English now | /eol scan - diagnostics | /eol on|off - toggle automatic fixing")
    end
end
