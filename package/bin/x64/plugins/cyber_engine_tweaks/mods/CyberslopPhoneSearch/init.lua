-- Cyberslop Phone Search 1.0.0 (2026-11-21), Cyberpunk 2077 2.5 + CET + redscript
--
-- CET window "Phone Search": every phone contact and message thread in one list, with a search box.
-- Text = the vanilla phone opens straight on that thread (read threads too).
-- Call = the same call the phone's dialer starts.
-- Mod contacts that use the NightlyNow Holo framework (Drug Dealer's Yukmouth / Shanice, NC Cab, Trauma Team,
-- GigCore, NCPD Duty ...) are listed and open like vanilla ones.
--
-- How to use: open the CET overlay, type a few letters, press Enter (or click Text / Call), close the overlay.
-- The action runs right after the overlay closes, so the phone gets the keyboard and mouse.
-- Enter acts on the top result: Text if it has messages, otherwise Call.
--
-- Needs r6\scripts\CyberslopPhoneSearch\CyberslopPhoneSearch.reds (the system this window calls).
-- Window shows with the CET overlay; CET hotkey "Show / hide window" (unbound). Settings: settings.json.

local SETTINGS_FILE = "settings.json"
local SYSTEM_NAME = "CyberslopPhoneSearchSystem"
local RUN_DELAY = 0.35         -- seconds after the overlay closes before the queued action runs
local MESSAGE_TIME = 6.0       -- seconds a status line stays in the window

local OPEN_RESULT = {
    [0] = nil,
    [1] = "Phone not ready yet (load a save first)",
    [2] = "Phone is blocked right now (combat, scene or quest)",
    [3] = "Phone is already open",
    [4] = "That thread is gone",
}
local CALL_RESULT = {
    [0] = nil,
    [1] = "Phone not ready yet (load a save first)",
    [2] = "Calling is blocked right now (combat, call running, scene or quest)",
    [5] = "That contact can't be called",
}

local state = {
    overlay = false,
    show = true,
    filter = "all",        -- all / call / text / unread
    sort = "name",         -- name / recent
    priorityFirst = true,  -- quest and unread first
    query = "",
    focusSearch = false,
    groups = {},           -- built by refresh()
    expanded = {},         -- contact key -> true when its threads are listed
    pending = nil,         -- { kind = "text" | "call", hash = n, id = s, label = s }
    runAt = nil,
    message = "",
    messageTime = -100,
    clock = 0,
}

------------------------------------------------------------------ settings
local function loadSettings()
    local f = io.open(SETTINGS_FILE, "r")
    if not f then return end
    local ok, data = pcall(function() return json.decode(f:read("*a")) end)
    f:close()
    if ok and type(data) == "table" then
        if type(data.show) == "boolean" then state.show = data.show end
        if data.filter == "all" or data.filter == "call" or data.filter == "text" or data.filter == "unread" then
            state.filter = data.filter
        end
        if data.sort == "name" or data.sort == "recent" then state.sort = data.sort end
        if type(data.priorityFirst) == "boolean" then state.priorityFirst = data.priorityFirst end
    end
end

local function saveSettings()
    local f = io.open(SETTINGS_FILE, "w")
    if not f then return end
    f:write(json.encode({ show = state.show, filter = state.filter, sort = state.sort,
                          priorityFirst = state.priorityFirst }))
    f:close()
end

local function say(msg)
    state.message = msg or ""
    state.messageTime = state.clock
    if msg and msg ~= "" then print("[PhoneSearch] " .. msg) end
end

------------------------------------------------------------------ game access
local function getSystem()
    if Game.GetPlayer() == nil then return nil end
    local ok, sys = pcall(function() return Game.GetScriptableSystemsContainer():Get(SYSTEM_NAME) end)
    if ok then return sys end
    return nil
end

local function str(v)
    if v == nil then return "" end
    return tostring(v)
end

local function lower(s)
    return string.lower(s or "")
end

-- Groups rows by contact: one group per contact hash, threads under it.
-- Threads whose contact is not in the Contacts tab (unknown senders) get a group of their own.
local function buildGroups(entries)
    local groups, byHash = {}, {}
    local function group(hash, name)
        local g = byHash[hash]
        if g == nil then
            g = { key = tostring(hash), hash = hash, name = name, id = "", callable = false, threads = {},
                  unread = 0, quest = false, time = 0, haystack = "" }
            byHash[hash] = g
            groups[#groups + 1] = g
        end
        if (g.name == nil or g.name == "") and name ~= "" then g.name = name end
        return g
    end
    for _, e in ipairs(entries) do
        local hash = tonumber(e.contactHash) or 0
        local g = group(hash, str(e.name))
        if e.isThread then
            g.threads[#g.threads + 1] = {
                title = str(e.title), openHash = tonumber(e.openHash) or 0,
                unread = tonumber(e.unread) or 0, quest = e.questRelated == true,
                canReply = e.canReply == true, time = tonumber(e.timeSeconds) or 0,
            }
        else
            if str(e.contactId) ~= "" then g.id = str(e.contactId) end
            if e.callable then g.callable = true end
        end
        if e.questRelated then g.quest = true end
    end
    for _, g in ipairs(groups) do
        local unread, time, titles = 0, 0, {}
        for _, t in ipairs(g.threads) do
            unread = unread + t.unread
            if t.time > time then time = t.time end
            if t.quest then g.quest = true end
            titles[#titles + 1] = t.title
        end
        table.sort(g.threads, function(a, b)
            if (a.unread > 0) ~= (b.unread > 0) then return a.unread > 0 end
            return a.time > b.time
        end)
        g.unread, g.time = unread, time
        if g.name == "" then g.name = "(unknown)" end
        g.haystack = lower(g.name .. " " .. table.concat(titles, " "))
    end
    return groups
end

local function refresh()
    local sys = getSystem()
    if sys == nil then
        state.groups = {}
        return false
    end
    local ok, entries = pcall(function() return sys:Snapshot() end)
    if not ok or type(entries) ~= "table" then
        state.groups = {}
        say("Could not read the phone: " .. tostring(entries))
        return false
    end
    state.groups = buildGroups(entries)
    return true
end

------------------------------------------------------------------ search / sort
local function matches(g, tokens)
    if state.filter == "call" and not g.callable then return false end
    if state.filter == "text" and #g.threads == 0 then return false end
    if state.filter == "unread" and g.unread == 0 then return false end
    for _, tok in ipairs(tokens) do
        if not string.find(g.haystack, tok, 1, true) then return false end
    end
    return true
end

local function visibleGroups()
    local tokens = {}
    for tok in string.gmatch(lower(state.query), "%S+") do tokens[#tokens + 1] = tok end
    local out = {}
    for _, g in ipairs(state.groups) do
        if matches(g, tokens) then out[#out + 1] = g end
    end
    table.sort(out, function(a, b)
        if state.priorityFirst then
            if a.quest ~= b.quest then return a.quest end
            if (a.unread > 0) ~= (b.unread > 0) then return a.unread > 0 end
        end
        if state.sort == "recent" and a.time ~= b.time then return a.time > b.time end
        local an, bn = lower(a.name), lower(b.name)
        if an ~= bn then return an < bn end
        return a.key < b.key
    end)
    return out
end

------------------------------------------------------------------ actions
local function queue(kind, g, thread)
    if kind == "text" then
        local t = thread or g.threads[1]
        if t == nil then return end
        local label = g.name
        if t.title ~= "" and #g.threads > 1 then label = label .. " - " .. t.title end
        state.pending = { kind = "text", hash = t.openHash, label = label }
    else
        if not g.callable or g.id == "" then return end
        state.pending = { kind = "call", id = g.id, label = g.name }
    end
    state.runAt = nil
    state.message = ""
    if not state.overlay then state.runAt = state.clock end
end

local function primary(g)
    if #g.threads > 0 then queue("text", g) elseif g.callable then queue("call", g) end
end

local function runPending()
    local p = state.pending
    state.pending, state.runAt = nil, nil
    if p == nil then return end
    local sys = getSystem()
    if sys == nil then
        say("Phone Search: redscript part not loaded (r6\\scripts\\CyberslopPhoneSearch)")
        return
    end
    local ok, res, texts
    if p.kind == "text" then
        ok, res = pcall(function() return sys:OpenThread(p.hash) end)
        texts = OPEN_RESULT
    else
        ok, res = pcall(function() return sys:Call(p.id) end)
        texts = CALL_RESULT
    end
    local code = nil
    if not ok then
        code = "error: " .. tostring(res)
    elseif tonumber(res) ~= 0 then
        code = texts[tonumber(res) or -1] or ("unexpected result " .. tostring(res))
    end
    if code then
        say(p.label .. ": " .. code)
        local player = Game.GetPlayer()
        if player then pcall(function() player:SetWarningMessage(p.label .. ": " .. code) end) end
    else
        say("")
    end
end

------------------------------------------------------------------ window
local function badge(g)
    local parts = {}
    if g.quest then parts[#parts + 1] = "quest" end
    if g.unread > 0 then parts[#parts + 1] = tostring(g.unread) .. " unread" end
    if #g.threads > 1 then parts[#parts + 1] = tostring(#g.threads) .. " threads" end
    return table.concat(parts, ", ")
end

local function drawGroup(g, index)
    ImGui.PushID(g.key)
    if #g.threads > 0 then
        if ImGui.SmallButton("Text") then queue("text", g) end
    else
        ImGui.TextDisabled("    ")
    end
    ImGui.SameLine()
    if g.callable then
        if ImGui.SmallButton("Call") then queue("call", g) end
    else
        ImGui.TextDisabled("    ")
    end
    ImGui.SameLine()
    if g.quest then
        ImGui.TextColored(1.0, 0.8, 0.3, 1.0, g.name)
    elseif g.unread > 0 then
        ImGui.TextColored(0.5, 0.9, 1.0, 1.0, g.name)
    else
        ImGui.Text(g.name)
    end
    if index == 1 and state.query ~= "" then
        ImGui.SameLine()
        ImGui.TextDisabled("[Enter]")
    end
    local b = badge(g)
    if b ~= "" then
        ImGui.SameLine()
        ImGui.TextDisabled("(" .. b .. ")")
    end
    if #g.threads > 1 then
        ImGui.SameLine()
        local open = state.expanded[g.key] == true
        if ImGui.SmallButton(open and "-" or "+") then state.expanded[g.key] = not open end
        if open then
            for i, t in ipairs(g.threads) do
                ImGui.PushID("t" .. tostring(i))
                ImGui.Indent(24)
                if ImGui.SmallButton("Open") then queue("text", g, t) end
                ImGui.SameLine()
                local title = t.title ~= "" and t.title or "(thread " .. i .. ")"
                if t.unread > 0 then
                    ImGui.TextColored(0.5, 0.9, 1.0, 1.0, title .. "  (" .. t.unread .. " unread)")
                else
                    ImGui.Text(title)
                end
                ImGui.Unindent(24)
                ImGui.PopID()
            end
        end
    end
    ImGui.PopID()
end

local function drawWindow()
    local sys = getSystem()
    if Game.GetPlayer() == nil then
        ImGui.Text("Load a save first.")
        return
    end
    if sys == nil then
        ImGui.TextWrapped("The redscript part is missing or failed to compile: r6\\scripts\\CyberslopPhoneSearch.")
        return
    end

    if state.focusSearch then
        ImGui.SetKeyboardFocusHere()
        state.focusSearch = false
    end
    ImGui.PushItemWidth(-70)
    local text, enter = ImGui.InputTextWithHint("##query", "Search name or thread...", state.query, 128,
                                                 ImGuiInputTextFlags.EnterReturnsTrue)
    ImGui.PopItemWidth()
    if type(text) == "string" then state.query = text end
    ImGui.SameLine()
    if ImGui.Button("Refresh") then refresh() end

    local function radio(label, field, value)
        if ImGui.RadioButton(label, state[field] == value) then
            state[field] = value
            saveSettings()
        end
    end
    radio("All", "filter", "all") ImGui.SameLine()
    radio("Callable", "filter", "call") ImGui.SameLine()
    radio("Messages", "filter", "text") ImGui.SameLine()
    radio("Unread", "filter", "unread")
    ImGui.Text("Sort:") ImGui.SameLine()
    radio("Name", "sort", "name") ImGui.SameLine()
    radio("Recent", "sort", "recent") ImGui.SameLine()
    local v, pressed = ImGui.Checkbox("Quest / unread first", state.priorityFirst)
    if pressed then
        state.priorityFirst = v
        saveSettings()
    end
    ImGui.Separator()

    local list = visibleGroups()
    if enter and list[1] then primary(list[1]) end

    if state.pending then
        ImGui.TextColored(0.6, 0.9, 0.6, 1.0, (state.pending.kind == "text" and "Opens " or "Calls ")
            .. state.pending.label .. " when you close the overlay")
        ImGui.SameLine()
        if ImGui.SmallButton("Cancel") then
            state.pending = nil
            say("Cancelled")
        end
    elseif state.message ~= "" and state.clock - state.messageTime < MESSAGE_TIME then
        ImGui.TextColored(1.0, 0.7, 0.4, 1.0, state.message)
    end
    ImGui.TextDisabled(tostring(#list) .. " of " .. tostring(#state.groups) .. " contacts")

    if ImGui.BeginChild("##list", 0, 0, false) then
        for i, g in ipairs(list) do drawGroup(g, i) end
    end
    ImGui.EndChild()
end

------------------------------------------------------------------ events
registerForEvent("onInit", function()
    loadSettings()
end)

registerHotkey("toggle_window", "Show / hide window", function()
    state.show = not state.show
    saveSettings()
end)

registerForEvent("onOverlayOpen", function()
    state.overlay = true
    state.focusSearch = true
    state.runAt = nil
    pcall(refresh)
end)

registerForEvent("onOverlayClose", function()
    state.overlay = false
    if state.pending then state.runAt = state.clock + RUN_DELAY end
end)

registerForEvent("onUpdate", function(dt)
    state.clock = state.clock + (dt or 0)
    if state.pending and state.runAt and not state.overlay and state.clock >= state.runAt then
        local ok, err = pcall(runPending)
        if not ok then
            state.pending, state.runAt = nil, nil
            say("Phone Search failed: " .. tostring(err))
        end
    end
end)

registerForEvent("onDraw", function()
    if not state.overlay or not state.show then return end
    ImGui.SetNextWindowSize(440, 520, ImGuiCond.FirstUseEver)
    if ImGui.Begin("Phone Search") then
        local ok, err = pcall(drawWindow)
        if not ok then
            ImGui.TextWrapped("Error: " .. tostring(err))
        end
    end
    ImGui.End()
end)

return {}
