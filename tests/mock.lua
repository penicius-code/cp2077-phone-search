-- Mock test for Cyberslop Phone Search init.lua (LuaJIT). Stubs CET (events, ImGui, Game, json) and the
-- redscript system, then drives overlay open / typing / Enter / buttons / overlay close / onUpdate.
-- Usage: luajit ps_mock.lua <path to init.lua>   (run from a scratch folder: writes settings.json there)

local INIT = arg[1]
local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

-- ---------------------------------------------------------------- CET stubs
local events, hotkeys = {}, {}
function registerForEvent(name, fn) events[name] = fn end
function registerHotkey(id, label, fn) hotkeys[id] = fn end
json = {
    encode = function(t)
        local parts = {}
        for k, v in pairs(t) do
            local val = type(v) == "string" and ('"' .. v .. '"') or tostring(v)
            parts[#parts + 1] = '"' .. k .. '":' .. val
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end,
    decode = function(s)
        local t = {}
        for k, v in string.gmatch(s, '"([%w_]+)":("?[%w_]+"?)') do
            if v == "true" then t[k] = true elseif v == "false" then t[k] = false
            else t[k] = (v:gsub('"', '')) end
        end
        return t
    end,
}
ImGuiCond = { FirstUseEver = 4 }
ImGuiInputTextFlags = { EnterReturnsTrue = 32 }

-- ImGui recorder: texts drawn this frame, buttons to click (by "<id path>/<label>"), query input
local ui = { texts = {}, ids = {}, clicks = {}, query = nil, enter = false, focusCalls = 0, checkbox = nil }
local function idpath() return table.concat(ui.ids, "/") end
local function rec(s) ui.texts[#ui.texts + 1] = s end
ImGui = {
    SetNextWindowSize = function() end,
    Begin = function() return true end,
    End = function() end,
    Text = function(s) rec(s) end,
    TextDisabled = function(s) rec(s) end,
    TextWrapped = function(s) rec(s) end,
    TextColored = function(r, g, b, a, s) rec(s) end,
    SameLine = function() end,
    Separator = function() end,
    Indent = function() end,
    Unindent = function() end,
    PushItemWidth = function() end,
    PopItemWidth = function() end,
    PushID = function(id) ui.ids[#ui.ids + 1] = tostring(id) end,
    PopID = function() ui.ids[#ui.ids] = nil end,
    SetKeyboardFocusHere = function() ui.focusCalls = ui.focusCalls + 1 end,
    InputTextWithHint = function(label, hint, text, size, flags)
        assert(flags == ImGuiInputTextFlags.EnterReturnsTrue)
        local t = ui.query or text
        ui.query = nil
        local e = ui.enter
        ui.enter = false
        return t, e
    end,
    Button = function(label) local k = idpath() .. "/" .. label; local hit = ui.clicks[k]; ui.clicks[k] = nil; return hit == true end,
    SmallButton = function(label) local k = idpath() .. "/" .. label; local hit = ui.clicks[k]; ui.clicks[k] = nil; return hit == true end,
    RadioButton = function(label, active) local k = "radio/" .. label; local hit = ui.clicks[k]; ui.clicks[k] = nil; return hit == true end,
    Checkbox = function(label, v) if ui.checkbox ~= nil then local n = ui.checkbox; ui.checkbox = nil; return n, true end return v, false end,
    BeginChild = function() return true end,
    EndChild = function() end,
}

-- ---------------------------------------------------------------- game + redscript system stubs
local function E(t) return t end
local snapshot = {
    -- Judy: callable, two threads (multi-thread contact)
    E{ name = "Judy Alvarez", contactId = "judy", contactHash = 100, openHash = 100, isThread = false, callable = true, unread = 0, questRelated = false, canReply = false, timeSeconds = 0 },
    E{ name = "Judy Alvarez", title = "Dream On", contactId = "judy", contactHash = 100, openHash = 101, isThread = true, callable = true, unread = 0, questRelated = false, canReply = false, timeSeconds = 5000 },
    E{ name = "Judy Alvarez", title = "Pisces", contactId = "judy", contactHash = 100, openHash = 102, isThread = true, callable = true, unread = 2, questRelated = false, canReply = true, timeSeconds = 9000 },
    -- Yukmouth (Holo): not callable, one thread
    E{ name = "Yukmouth", contactId = "Yukmouth", contactHash = 29184223, openHash = 29184223, isThread = false, callable = false, unread = 1, questRelated = false, canReply = true, timeSeconds = 0 },
    E{ name = "Yukmouth", title = "", contactId = "Yukmouth", contactHash = 29184223, openHash = 29184223, isThread = true, callable = false, unread = 0, questRelated = false, canReply = true, timeSeconds = 7000 },
    -- Panam: callable, no messages
    E{ name = "Panam Palmer", contactId = "panam", contactHash = 300, openHash = 300, isThread = false, callable = true, unread = 0, questRelated = false, canReply = false, timeSeconds = 0 },
    -- quest contact
    E{ name = "Rogue", contactId = "rogue", contactHash = 400, openHash = 400, isThread = false, callable = true, unread = 0, questRelated = true, canReply = false, timeSeconds = 0 },
    -- unknown sender: thread only, no contact row
    E{ name = "", title = "Spam", contactId = "", contactHash = 999, openHash = 999, isThread = true, callable = false, unread = 0, questRelated = false, canReply = false, timeSeconds = 100 },
}
local calls = { open = {}, call = {}, warn = {} }
local sysResult = { open = 0, call = 0 }
local system = {
    Snapshot = function(self) return snapshot end,
    OpenThread = function(self, h) calls.open[#calls.open + 1] = h; return sysResult.open end,
    Call = function(self, id) calls.call[#calls.call + 1] = id; return sysResult.call end,
}
local hasPlayer, hasSystem = true, true
local player = { SetWarningMessage = function(self, m) calls.warn[#calls.warn + 1] = m end }
Game = {
    GetPlayer = function() if hasPlayer then return player end return nil end,
    GetScriptableSystemsContainer = function()
        return { Get = function(self, name)
            assert(name == "CyberslopPhoneSearchSystem", name)
            if hasSystem then return system end
            return nil
        end }
    end,
}

-- ---------------------------------------------------------------- run
local printed = {}
local realPrint = print
print = function(s) printed[#printed + 1] = s end
dofile(INIT)
print = realPrint

local function frame() ui.texts = {}; events.onDraw() end
local function drawn(s) for _, t in ipairs(ui.texts) do if t == s then return true end end return false end
local function drawnLike(p) for _, t in ipairs(ui.texts) do if string.find(t, p, 1, true) then return true end end return false end
local function update(dt) events.onUpdate(dt) end

events.onInit()
check("hotkey registered", hotkeys.toggle_window ~= nil)

-- overlay open: refresh + focus
events.onOverlayOpen()
frame()
check("focus requested once", ui.focusCalls == 1)
frame()
check("focus not repeated", ui.focusCalls == 1)
check("all 5 groups shown", drawnLike("5 of 5 contacts"))
check("quest first: Rogue drawn", drawn("Rogue"))
check("unknown sender named", drawn("(unknown)"))
-- order: Rogue (quest) first, then unread groups (Judy 2, Yukmouth 0 thread unread but contact unread not counted) ...
local order = {}
for _, t in ipairs(ui.texts) do
    if t == "Rogue" or t == "Judy Alvarez" or t == "Yukmouth" or t == "Panam Palmer" or t == "(unknown)" then order[#order + 1] = t end
end
check("order quest, unread, then names", table.concat(order, ",") == "Rogue,Judy Alvarez,(unknown),Panam Palmer,Yukmouth")
check("Judy badge", drawnLike("2 unread, 2 threads"))

-- search "yuk" + Enter -> text pending, runs after overlay close
ui.query = "yuk"; frame()
check("search filters to 1", drawnLike("1 of 5 contacts"))
ui.enter = true; frame()
check("pending text Yukmouth", drawnLike("Opens Yukmouth when you close the overlay"))
check("nothing ran while overlay open", #calls.open == 0)
events.onOverlayClose()
update(0.1)
check("not before delay", #calls.open == 0)
update(0.3)
check("OpenThread ran once", #calls.open == 1 and calls.open[1] == 29184223)
update(1.0)
check("ran only once", #calls.open == 1)

-- search "pan" + Enter -> call (no threads)
events.onOverlayOpen()
ui.query = "pan"; frame()
ui.enter = true; frame()
check("pending call Panam", drawnLike("Calls Panam Palmer when you close the overlay"))
events.onOverlayClose(); update(0.5)
check("Call ran", #calls.call == 1 and calls.call[1] == "panam")

-- multi-token search across thread titles: "judy pisc" -> Judy, Enter opens newest unread thread (Pisces, 102)
events.onOverlayOpen()
ui.query = "judy pisc"; frame()
check("multi-token match", drawnLike("1 of 5 contacts"))
ui.enter = true; frame()
events.onOverlayClose(); update(0.5)
check("Judy opens unread thread first", calls.open[#calls.open] == 102)

-- expand Judy's threads, open the other one by button
events.onOverlayOpen()
ui.query = "judy"; frame()
ui.clicks["100/+"] = true; frame(); frame()
check("threads listed", drawn("Dream On") and drawnLike("Pisces"))
ui.clicks["100/t2/Open"] = true; frame(); frame()
check("pending names thread", drawnLike("Opens Judy Alvarez - Dream On"))
events.onOverlayClose(); update(0.5)
check("thread 101 opened", calls.open[#calls.open] == 101)

-- Call button on Judy
events.onOverlayOpen()
ui.query = "judy"; frame()
ui.clicks["100/Call"] = true; frame()
events.onOverlayClose(); update(0.5)
check("Judy called", calls.call[#calls.call] == "judy")

-- no Call button for Yukmouth (not callable): clicking a non-existent button does nothing
events.onOverlayOpen()
ui.query = "yuk"; frame()
ui.clicks["29184223/Call"] = true; frame()
check("no call pending for Yukmouth", not drawnLike("Calls Yukmouth"))
ui.clicks["29184223/Call"] = nil

-- cancel
ui.clicks["29184223/Text"] = true; frame(); frame()
check("pending via Text button", drawnLike("Opens Yukmouth"))
ui.clicks["/Cancel"] = true; frame(); frame()
check("cancelled", not drawnLike("Opens Yukmouth") and drawn("Cancelled"))
local opensBefore = #calls.open
events.onOverlayClose(); update(0.5)
check("cancel ran nothing", #calls.open == opensBefore)

-- blocked phone -> message + warning
sysResult.open = 2
events.onOverlayOpen()
ui.query = "yuk"; frame(); ui.enter = true; frame()
events.onOverlayClose(); update(0.5)
check("warning shown", calls.warn[#calls.warn] == "Yukmouth: Phone is blocked right now (combat, scene or quest)")
events.onOverlayOpen(); frame()
check("message in window", drawnLike("Phone is blocked right now"))
sysResult.open = 7
ui.enter = true; frame()
events.onOverlayClose(); update(0.5)
check("unknown code reported", calls.warn[#calls.warn] == "Yukmouth: unexpected result 7")
sysResult.open = 0

-- filters
events.onOverlayOpen()
ui.query = ""; frame()
ui.clicks["radio/Callable"] = true; frame(); frame()
check("callable filter = Judy, Panam, Rogue", drawnLike("3 of 5 contacts"))
ui.clicks["radio/Messages"] = true; frame(); frame()
check("messages filter = Judy, Yukmouth, unknown", drawnLike("3 of 5 contacts"))
ui.clicks["radio/Unread"] = true; frame(); frame()
check("unread filter = Judy", drawnLike("1 of 5 contacts"))
ui.clicks["radio/All"] = true; frame()

-- sort recent without priority
ui.checkbox = false; frame()
ui.clicks["radio/Recent"] = true; frame(); frame()
order = {}
for _, t in ipairs(ui.texts) do
    if t == "Rogue" or t == "Judy Alvarez" or t == "Yukmouth" or t == "Panam Palmer" or t == "(unknown)" then order[#order + 1] = t end
end
check("recent order", table.concat(order, ",") == "Judy Alvarez,Yukmouth,(unknown),Panam Palmer,Rogue")

-- settings saved and reloaded
local f = io.open("settings.json", "r"); local s = f and f:read("*a") or ""; if f then f:close() end
check("settings saved", string.find(s, '"sort":"recent"', 1, true) ~= nil and string.find(s, '"priorityFirst":false', 1, true) ~= nil)

-- no player / no system
hasPlayer = false
events.onOverlayOpen(); frame()
check("no player text", drawn("Load a save first."))
hasPlayer = true; hasSystem = false
events.onOverlayOpen(); frame()
check("missing system text", drawnLike("redscript part is missing"))
-- pending action with system gone -> message, no crash
hasSystem = true
events.onOverlayOpen(); ui.query = "pan"; frame(); ui.enter = true; frame()
hasSystem = false
events.onOverlayClose(); update(0.5)
check("missing system at run time handled", true)
hasSystem = true

-- window hidden by hotkey
hotkeys.toggle_window()
events.onOverlayOpen(); frame()
check("hidden window draws nothing", #ui.texts == 0)
hotkeys.toggle_window()

-- snapshot error
system.Snapshot = function() error("boom") end
events.onOverlayOpen(); frame()
check("snapshot error shown", drawnLike("Could not read the phone"))

print(string.format("mock: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
