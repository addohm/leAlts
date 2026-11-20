-- leAlts: slash commands. /lealts, and the short /nw from when it was Nothing Wasted.
local _, ns = ...
local L = ns.L

local function Help()
    local version = ns.version .. (ns.build and (" build " .. ns.build) or "")
    ns.Print(format(L["v%s commands:"], version))
    ns.Print(L["  /lealts - show or hide the window"])
    ns.Print(L["  /lealts bars - show or hide the small bars window"])
    ns.Print(L["  /lealts [item] - find an item on all your characters"])
    ns.Print(L["  /lealts options - open the options"])
    ns.Print(L["  /lealts minimap - show or hide the minimap button"])
    ns.Print(L["  /lealts chars - list every saved character"])
    ns.Print(L["  /lealts rate - measure the rested XP rate (/lealts rate reset starts over)"])
    ns.Print(L["  /lealts buffs - what the leveling buff reminders see right now"])
    ns.Print(L["  /lealts reset - forget every character"])
    ns.Print(L["  /nw works too, for short."])
end

-- Lists every saved character and what its bar shows: /lealts chars
local function ListCharacters()
    local now = ns.Now()
    local keys = {}
    for key in pairs(ns.db.chars) do keys[#keys + 1] = key end
    table.sort(keys)
    -- Where the data came from: if the game didn't write it at the last logout, alts are missing.
    local save = ns.loadedSave
    if ns.firstRun then
        ns.Print(L["No saved data was found when this character logged in. If you've played other characters with leAlts, the game didn't write their data: log out to the character screen or type /reload before closing the game."])
    elseif save and save.at then
        ns.Print(format(L["Data loaded at login was saved by %s %s ago."], save.by or "?", ns.FormatDuration(now - save.at)))
    end
    ns.Print(format(L["%d saved character(s):"], #keys))
    for _, key in ipairs(keys) do
        local c = ns.db.chars[key]
        local status
        if c.untracked then
            status = L["not tracked"]
        elseif c.isMax then
            status = ns.db.settings.bars.showMax and L["max level"] or L["max level (hidden by the option)"]
        elseif ns.Rested.IsIdle(c) then
            status = c.xpDisabled and L["XP turned off"] or L["no XP data yet"]
        else
            local _, _, toCap = ns.Rested.Estimate(c, now)
            status = toCap <= 0 and L["at the rested cap"] or format(L["caps in %s"], ns.FormatDuration(toCap))
        end
        ns.Print(format("  %s  %s %d, %s, %s", c.name and (ns.FullName(c) .. "-" .. (c.realm or "?")) or key, L["level"], c.level or 0,
            c.savedAt and format(L["saved %s ago"], ns.FormatDuration(now - c.savedAt)) or L["never saved"], status))
    end
end

-- The internal names (SLASH_NOTHINGWASTED, NOTHINGWASTED_* popups) are from the old name.
SLASH_NOTHINGWASTED1 = "/lealts"
SLASH_NOTHINGWASTED2 = "/nw"
SlashCmdList.NOTHINGWASTED = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd = msg:lower()
    if cmd == "" then
        ns.Window.Toggle()
    elseif cmd == "bars" then
        ns.Meter.Toggle()
    elseif cmd == "options" or cmd == "config" then
        ns.Window.Show("options")
    elseif cmd == "minimap" then
        local hidden = ns.db.settings.minimap.hide
        ns.Minimap.SetShown(hidden)
        ns.Print(hidden and L["minimap button shown."] or L["minimap button hidden. Type /lealts minimap to bring it back."])
    elseif cmd == "reset" then
        StaticPopup_Show("NOTHINGWASTED_FORGET_ALL")
    elseif cmd == "chars" then
        ListCharacters()
    elseif cmd == "rate" or cmd == "rate reset" then
        ns.RateCheck.Run(cmd == "rate reset" and "reset" or nil)
    elseif cmd == "buffs" then
        ns.Buffs.Report()
    elseif cmd == "perks" then
        ns.Legacy.DumpPerks()
    elseif cmd == "help" or cmd == "?" then
        Help()
    else
        -- Anything else is an item search: an item link or part of a name.
        ns.Window.Show("items")
        ns.Inventory.ShowSearch(msg)
    end
end

StaticPopupDialogs["NOTHINGWASTED_FORGET"] = {
    text = L["Forget %s?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, key) ns.Character.Forget(key) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["NOTHINGWASTED_FORGET_ALL"] = {
    text = L["Forget every character? The one you're playing is added back."],
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        wipe(ns.db.chars)
        ns.Character.Save()
        ns.Fire("NW_REFRESH")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
