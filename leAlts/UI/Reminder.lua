-- leAlts: the buff reminder. When you leave an inn or city with a leveling buff missing, the
-- missing buffs' icons appear, large, with a pulsing yellow glow and a small label under each. They
-- sit where the bars window is until you move them (Options → Alerts → Move). Hover one for the details; left-click to eat or use the sleeping bag;
-- right-click to dismiss. An icon goes away when you get that buff; they all go when none are left
-- or when you're back in a rested area. It can also show the reminder in large text near the top
-- of the screen.
local _, ns = ...
local L = ns.L

local Reminder = {}
ns.Reminder = Reminder

local SIZE = 38       -- icon size
local GAP = 14        -- space between one icon's label and the next
local LABEL_SPACE = 16 -- room under the icons for their labels
local YELLOW = { 1, 0.82, 0 }
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border" -- the game's yellow button highlight

local frame, mover
local moving = false -- showing sample icons to drag
local SAMPLE = { "wellFed", "bag", "tent" }
local buttons = {}
local shown = {} -- the kinds currently shown
local shownAt    -- GetTime() when the icons last came up

local function SpellIcon(spellID)
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.iconID or "Interface\\Icons\\INV_Misc_Food_15"
end

local function ItemIcon(itemID)
    return C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or "Interface\\Icons\\INV_Misc_Bag_08"
end

-- The kinds of reminder: icon, short label, and the details shown on hover.
local KINDS = {
    wellFed = function()
        local def = { icon = SpellIcon(ns.Data.wellFedSpellID), label = L["Well Fed"],
            title = L["Not Well Fed"], hint = L["Eat cooked food: Well Fed gives +5% XP from kills."] }
        local missed = ns.Buffs.MissedXP("wellFed")
        if ns.db.settings.alerts.buffMissedXP and missed >= 1 then
            local n = ns.FormatNumber(missed)
            def.label = format(L["Well Fed (-%s XP)"], n)
            def.extra = format(L["Missed so far: about %s XP."], n)
        end
        if ns.db.settings.alerts.buffClick then
            local foodID, foodName = ns.Buffs.WellFedFood()
            if foodID then
                def.action = { type = "item", item = "item:" .. foodID }
                def.click = format(L["Left-click to eat %s."], foodName or ("item " .. foodID))
            else
                def.click = L["No food that gives Well Fed in your bags."]
            end
        end
        return def
    end,
    bag = function()
        local def = { icon = ItemIcon(ns.Data.sleepingBag.itemID), label = L["Sleeping bag"],
            title = L["Sleeping bag ready"], hint = L["Rest in your Cozy Sleeping Bag for up to +3% XP."] }
        local missed = ns.Buffs.MissedXP("bag")
        if ns.db.settings.alerts.buffMissedXP and missed >= 1 then
            local n = ns.FormatNumber(missed)
            def.label = format(L["Sleeping bag (-%s XP)"], n)
            def.extra = format(L["Missed so far: about %s XP."], n)
        end
        return Reminder.AddBagAction(def)
    end,
    tent = function()
        return { icon = SpellIcon(ns.Data.campTent.spellID), label = L["Camp Tent"],
            title = L["No Boosted Rest"], hint = L["Find a Camp Tent by a campfire and sit by it: it tops up your rested XP."] }
    end,
    bagLogout = function()
        local def = { icon = ItemIcon(ns.Data.sleepingBag.itemID), label = L["Sleeping bag"],
            title = L["Use your sleeping bag"], hint = L["Rest in your Cozy Sleeping Bag before logging out to keep up to +3% XP for your next session."] }
        return Reminder.AddBagAction(def)
    end,
}

function Reminder.AddBagAction(def)
    if ns.db.settings.alerts.buffClick then
        def.action = ns.Buffs.BagAction()
        if def.action then def.click = L["Left-click to use your sleeping bag."] end
    end
    return def
end

local Place

local function Build()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(SIZE, SIZE + LABEL_SPACE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- While moving: a tinted cover over the sample icons that takes the drag.
    mover = CreateFrame("Button", nil, frame)
    mover:SetPoint("TOPLEFT", -8, 22)
    mover:SetPoint("BOTTOMRIGHT", 8, -4)
    mover:SetFrameLevel(frame:GetFrameLevel() + 20)
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.5, 1, 0.3)
    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOP", 0, -4)
    text:SetText(L["Reminder icons: drag to move"])
    mover:RegisterForDrag("LeftButton")
    mover:RegisterForClicks("RightButtonUp")
    mover:SetScript("OnDragStart", function() frame:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        -- Saved by the centre, so any number of icons stays centred on the spot.
        local x, y = frame:GetCenter()
        ns.db.settings.alerts.reminderPos = { x, y }
        Place()
    end)
    mover:SetScript("OnClick", function() Reminder.SetMoving(false) end)
    mover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Drag to move."])
        GameTooltip:AddLine(L["Right-click when done."], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", GameTooltip_Hide)
    mover:Hide()
end

-- Centers the icons (with their labels) on their saved spot, or on the bars window until they've
-- been moved.
function Place()
    frame:ClearAllPoints()
    local pos = ns.db.settings.alerts.reminderPos
    if pos then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else
        frame:SetPoint("CENTER", ns.Meter.GetFrame(), "CENTER", 0, 0)
    end
end

local function CreateButton(i)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("RightButtonUp")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- The glow sits on its own frame so it can pulse.
    b.glow = CreateFrame("Frame", nil, b)
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(SIZE * 1.8, SIZE * 1.8)
    local tex = b.glow:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(GLOW)
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(YELLOW[1], YELLOW[2], YELLOW[3])
    b.pulse = b.glow:CreateAnimationGroup()
    local a = b.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.6)
    b.pulse:SetLooping("BOUNCE")

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)

    b:SetScript("OnEnter", function(self)
        if not self.def then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.def.title, YELLOW[1], YELLOW[2], YELLOW[3])
        GameTooltip:AddLine(self.def.hint, 1, 1, 1, true)
        if self.def.extra then GameTooltip:AddLine(self.def.extra, 1, 0.4, 0.4, true) end
        if self.def.click then GameTooltip:AddLine(self.def.click, 0.4, 1, 0.4, true) end
        GameTooltip:AddLine(L["Right-click to dismiss."], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", function() Reminder.Hide() end)
    return b
end

-- Lays out the icons; `keepPulse` leaves the glows pulsing as they are (a label update).
local function Layout(keepPulse)
    local kinds = moving and SAMPLE or shown
    local x = 0
    for i, kind in ipairs(kinds) do
        local b = buttons[i] or CreateButton(i)
        buttons[i] = b
        b.buffKind = kind
        b.def = KINDS[kind]()
        b.icon:SetTexture(b.def.icon)
        b.label:SetText(b.def.label)
        -- Each icon gets a slot as wide as its label (or the icon, if wider), so labels never overlap.
        local slot = math.max(SIZE, math.ceil(b.label:GetStringWidth() or SIZE))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x + (slot - SIZE) / 2, 0)
        x = x + slot + GAP
        b:Show()
        -- Restart every glow together, so they pulse in step.
        if not keepPulse then
            b.pulse:Stop()
            b.pulse:Play()
        end
    end
    for i = #kinds + 1, #buttons do
        buttons[i].buffKind = nil
        buttons[i].pulse:Stop()
        buttons[i]:Hide()
    end
    frame:SetWidth(math.max(SIZE, x - GAP))
    Reminder.SyncActions()
end

-- Shows the icons for these kinds ("wellFed", "bag", "tent", "bagLogout").
function Reminder.Show(kinds)
    if #kinds == 0 then return end
    if not frame then Build() end
    shown = {}
    for _, k in ipairs(kinds) do shown[#shown + 1] = k end
    shownAt = GetTime()
    -- While moving, the sample stays up; these show when moving is done.
    if not moving then
        Place()
        frame:Show()
        Layout()
    end
    ns.Fire("NW_REMINDER")
end

-- Keeps only the icons still missing; hides when none are left.
function Reminder.Keep(stillMissing)
    if not shownAt then return end
    local keep = {}
    for _, k in ipairs(shown) do
        if stillMissing[k] then keep[#keep + 1] = k end
    end
    if #keep == 0 then
        Reminder.Hide()
    elseif #keep ~= #shown then
        shown = keep
        if not moving then Layout() end
    end
end

function Reminder.Hide()
    shown = {}
    local was = shownAt ~= nil
    shownAt = nil
    if frame and not moving then
        for _, b in ipairs(buttons) do b.pulse:Stop() end
        frame:Hide()
    end
    Reminder.SyncActions()
    if was then ns.Fire("NW_REMINDER") end
end

-- Click to use: a secure button over each icon that has something to use (food, the sleeping
-- bag). The game lets these change only out of combat, and locks whatever they're anchored to,
-- so they sit on UIParent and are placed over the icons whenever those change outside combat. A
-- change during combat waits for the fight to end.
local actionButtons = {}
local syncWanted = false

local function ActionButton(i)
    if actionButtons[i] then return actionButtons[i] end
    local a = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    a:SetSize(SIZE, SIZE)
    a:SetFrameStrata("MEDIUM")
    a:SetFrameLevel(frame:GetFrameLevel() + 10)
    a:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    a:HookScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then Reminder.Hide() end
    end)
    a:SetScript("OnEnter", function(self)
        local icon = self.icon
        if icon and icon:IsVisible() then icon:GetScript("OnEnter")(icon) end
    end)
    a:SetScript("OnLeave", GameTooltip_Hide)
    a:Hide()
    actionButtons[i] = a
    return a
end

function Reminder.SyncActions()
    if InCombatLockdown() then
        syncWanted = true
        return
    end
    syncWanted = false
    for _, a in ipairs(actionButtons) do
        a.icon = nil
        a:Hide()
    end
    if not frame or not frame:IsShown() or moving then return end
    for i in ipairs(shown) do
        local b = buttons[i]
        local action = b and b.def and b.def.action
        local x, y = b and b:GetCenter()
        if action and x then
            local a = ActionButton(i)
            a:ClearAllPoints()
            a:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            a:SetAttribute("type1", action.type)
            a:SetAttribute("item", action.item)
            a:SetAttribute("toy", action.toy)
            a.icon = b
            a:Show()
        end
    end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if syncWanted then Reminder.SyncActions() end
end)

-- Updates the labels of the icons that are up (the XP missed changes as you kill).
function Reminder.Refresh()
    if frame and frame:IsShown() and (moving or #shown > 0) then Layout(true) end
end

-- Moving: sample icons under a cover you drag; right-click it, or click Done, to finish. Real
-- reminders that come up meanwhile show when it's done. Not in combat, since the click-to-use
-- buttons can't be moved then.
function Reminder.SetMoving(on)
    on = on and true or false
    if on == moving then return end
    if on and InCombatLockdown() then
        ns.Print(L["The reminder icons can't be moved in combat."])
        return
    end
    if not frame then Build() end
    moving = on
    if moving then
        Place()
        frame:Show()
        mover:Show()
        Layout()
    else
        mover:Hide()
        if shownAt then
            Layout()
        else
            for _, b in ipairs(buttons) do b.pulse:Stop() end
            frame:Hide()
        end
    end
    Reminder.SyncActions()
    ns.Fire("NW_REFRESH")
end

function Reminder.IsMoving()
    return moving
end

-- Back to the middle of the screen.
function Reminder.ResetPosition()
    local x, y = UIParent:GetCenter()
    ns.db.settings.alerts.reminderPos = { x, y }
    if frame then Place() end
end

-- Closing the options ends moving.
ns.On("NW_WINDOW_HIDDEN", function() Reminder.SetMoving(false) end)

-- For the tests.
function Reminder.Mover() return mover end

-- GetTime() when the icons came up, or nil while they're not up.
function Reminder.ShownSince()
    return shownAt
end

function Reminder.IsShown()
    return shownAt ~= nil
end

-- The kinds currently shown (for the tests).
function Reminder.Kinds()
    return shown
end

-- The reminder in large text near the top of the screen, fading out after a few seconds.
local notice
local function BuildNotice()
    notice = CreateFrame("Frame", nil, UIParent)
    notice:SetSize(800, 120)
    notice:SetPoint("TOP", UIParent, "TOP", 0, -160)
    notice:SetFrameStrata("HIGH")
    notice:EnableMouse(false)
    notice.text = notice:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge3")
    notice.text:SetPoint("TOP")
    notice.text:SetJustifyH("CENTER")
    notice.fade = notice:CreateAnimationGroup()
    local a = notice.fade:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    a:SetStartDelay(4)
    a:SetDuration(1)
    notice.fade:SetScript("OnFinished", function() notice:Hide() end)
    notice:Hide()
end

function Reminder.BigText(kinds)
    if #kinds == 0 then return end
    if not notice then BuildNotice() end
    local lines = {}
    for _, k in ipairs(kinds) do lines[#lines + 1] = KINDS[k]().title end
    notice.text:SetText(table.concat(lines, "\n"))
    notice.fade:Stop()
    notice:Show()
    notice.fade:Play()
end

-- The big text shown now, or nil (for the tests).
function Reminder.BigTextShown()
    return notice and notice:IsShown() and notice.text:GetText() or nil
end
