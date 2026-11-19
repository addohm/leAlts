-- Nothing Wasted: reminders for the leveling buffs, below max level.
--
-- Well Fed (+5% kill XP from cooked food), the Cozy Sleeping Bag's Well-Rested (up to +3% XP) and
-- the Camp Tent (rested XP; Boosted Rest marks one used, so missing it means you can use another). A missing buff is mentioned as a chat line when you leave an inn or city, and when it
-- wears off while you're out in the world. At logout, a ready sleeping bag is pointed out: resting
-- in it first carries the buff into the next session.
local _, ns = ...
local L = ns.L

local Buffs = {}
ns.Buffs = Buffs

local function HasAura(spellID)
    return C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil
end

local function WellFedName()
    return C_Spell.GetSpellName(ns.Data.wellFedSpellID) or L["Well Fed"]
end

-- The player's Well Fed buff, or nil. Foods use different Well Fed spells, so this goes by the
-- name. Returns nil when the names are secret (in combat).
local function WellFedAura()
    local name = WellFedName()
    for i = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura or (issecretvalue and issecretvalue(aura.name)) then return nil end
        if aura.name == name then return aura end
    end
end

local function WellFedSpell()
    local aura = WellFedAura()
    return aura and aura.spellId
end

-- Where the sleeping bag is: count in bags, count in the bank, and whether it's a toy.
local function BagWhere()
    local itemID = ns.Data.sleepingBag.itemID
    local carried = C_Item.GetItemCount(itemID) or 0
    local total = C_Item.GetItemCount(itemID, true) or 0
    local toy = PlayerHasToy and PlayerHasToy(itemID) or false
    return carried, total - carried, toy
end

-- Seconds until the bag is off cooldown (0 when ready).
local function BagCooldown()
    local start, duration = C_Container.GetItemCooldown(ns.Data.sleepingBag.itemID)
    if not start or start == 0 or not duration or duration == 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- What clicking the sleeping bag icon does: use the bag from your bags, or the toy. nil if neither.
function Buffs.BagAction()
    local carried, _, toy = BagWhere()
    local itemID = ns.Data.sleepingBag.itemID
    if carried > 0 then return { type = "item", item = "item:" .. itemID } end
    if toy then return { type = "toy", toy = itemID } end
end

-- Food in your bags that gives Well Fed: a consumable whose tooltip mentions Well Fed by name.
local FOOD_BAGS = { 0, 1, 2, 3, 4 }
local CONSUMABLE = 0       -- Enum.ItemClass.Consumable
local foodCache = {}       -- [itemID] = whether it gives Well Fed
local lastFoodID, lastFoodName

local function GivesWellFed(bag, slot, itemID)
    if foodCache[itemID] ~= nil then return foodCache[itemID] end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    if classID ~= CONSUMABLE then
        foodCache[itemID] = false
        return false
    end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    local lines = data and data.lines
    if not lines or #lines == 0 then return false end -- not loaded yet; try again next time
    local name = WellFedName()
    local lower = name:lower()
    local yes = false
    for _, line in ipairs(lines) do
        local text = line.leftText
        if type(text) == "string" and not (issecretvalue and issecretvalue(text))
            and (text:find(name, 1, true) or text:lower():find(lower, 1, true)) then
            yes = true
            break
        end
    end
    foodCache[itemID] = yes
    return yes
end

-- The item ID and name of a food in your bags that gives Well Fed, or nil. In combat, the last answer.
function Buffs.WellFedFood()
    if InCombatLockdown() then return lastFoodID, lastFoodName end
    lastFoodID, lastFoodName = nil, nil
    for _, bag in ipairs(FOOD_BAGS) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and GivesWellFed(bag, slot, info.itemID) then
                lastFoodID, lastFoodName = info.itemID, info.itemName
                return lastFoodID, lastFoodName
            end
        end
    end
end

-- True if the bag can be used now: in your bags (or a toy) and off cooldown. A bag in the bank
-- can't be used.
function Buffs.BagReady()
    local carried, _, toy = BagWhere()
    return (carried > 0 or toy) and BagCooldown() == 0
end

local YELLOW = "|cffffd100"

-- Shows buff reminders on the reminder card (kinds: "wellFed", "bag", "bagLogout"), with one sound
-- and one screen-edge flash for the batch, and optionally as yellow chat lines, large text and a
-- flash of the game's taskbar icon too.
local CHAT = {
    wellFed = "Not Well Fed: eat cooked food for +5% XP from kills.",
    bag = "Your Cozy Sleeping Bag is ready: rest in it for up to +3% XP.",
    bagLogout = "Your Cozy Sleeping Bag is ready: rest in it before logging out to keep up to +3% XP for your next session.",
    tent = "No Boosted Rest: find a Camp Tent by a campfire for rested XP.",
}
local function Remind(kinds)
    if #kinds == 0 then return end
    local settings = ns.db.settings.alerts
    ns.Reminder.Show(kinds)
    if settings.buffChat then
        for _, k in ipairs(kinds) do ns.Print(YELLOW .. L[CHAT[k]] .. "|r") end
    end
    if settings.buffSound then ns.Alerts.PlaySound("buff") end
    if settings.buffGlow then ns.Glow.Pulse() end
    if settings.buffBigText then ns.Reminder.BigText(kinds) end
    if settings.buffFlash and FlashClientIcon then FlashClientIcon() end
end

-- While the icons are up: the steady screen border and the repeated sound. With "build up" on,
-- both wait until the icons have been up a while; the repeated sound then plays at once.
local nextSoundAt
local function UpdateAttention()
    local s = ns.db.settings.alerts
    local since = ns.Reminder.ShownSince()
    if not since then
        ns.Glow.SetSteady(false)
        return
    end
    local now = GetTime()
    local wait = s.buffEscalate and s.buffEscalateMinutes * 60 or 0
    local ready = now - since >= wait
    ns.Glow.SetSteady(s.buffBorder and ready, s.buffBorderColor, s.buffBorderStrength)
    if s.buffRepeat and ready then
        nextSoundAt = nextSoundAt or (since + (wait > 0 and wait or s.buffRepeatMinutes * 60))
        if now >= nextSoundAt then
            ns.Alerts.PlaySound("buff")
            nextSoundAt = now + s.buffRepeatMinutes * 60
        end
    end
end
ns.On("NW_REMINDER", function()
    nextSoundAt = nil
    UpdateAttention()
end)
ns.On("NW_REFRESH", function()
    UpdateAttention()
    ns.Reminder.Refresh()
end)
ns.On("NW_INIT", function()
    C_Timer.NewTicker(5, function()
        UpdateAttention()
        ns.Reminder.SyncActions() -- the icons follow the bars window until they're moved
    end)
end)
ns.On("BAG_UPDATE_DELAYED", function() ns.Reminder.Refresh() end)

-- The Test button: everything that's turned on, with the border for a few seconds.
function Buffs.Preview()
    local s = ns.db.settings.alerts
    ns.Alerts.PlaySound("buff")
    if s.buffGlow then ns.Glow.Pulse() end
    if s.buffBigText then ns.Reminder.BigText({ "wellFed" }) end
    if s.buffFlash and FlashClientIcon then FlashClientIcon() end
    if s.buffBorder then
        ns.Glow.SetSteady(true, s.buffBorderColor, s.buffBorderStrength)
        C_Timer.After(5, UpdateAttention)
    end
end

local function BelowMax()
    local c = ns.Me()
    return ns.IsTracked(c) and not c.isMax and not c.xpDisabled
end

-- State between checks. nil until the first check after login or a reload: that one reminds only
-- if you're out in the world (and that's turned on), then sets the baseline.
local wasResting, hadWellFed, hadBagBuff, hadTent

-- XP missed without the buffs. Each XP gain is split into quest XP (QUEST_TURNED_IN's reward),
-- exploration (a gain that comes with MAP_EXPLORATION_UPDATED) and kill XP (the rest, less the
-- rested bonus, which shows as the rested pool going down). Well Fed's share is 5% of the kill XP;
-- the sleeping bag's is 1% per missing stack of kill and quest XP, if you have the bag. Both are
-- worked out from the XP before any bonus.
local KILL_NUDGE_SECONDS = 300 -- a kill brings the icons back at most this often
local EXPLORE_SECONDS = 2      -- a gain this close to an exploration counts as exploration XP
local missed = { wellFed = 0, bag = 0 } -- since each buff was last on, this session
local killedSinceCheck = false
local lastKillNudge
local lastXP, lastXPMax, lastLevel
local restedSeen = 0           -- the rested pool, as last seen
local batch                    -- gains within a second of each other: { xp, quest, rested }
local exploredAt
local CheckSoon

-- The buffs as last seen out of combat (auras can be secret in combat): when Well Fed and the
-- bag's Well-Rested run out (0 for never), and the bag's stacks. nil until first read.
local fedUntil, bagUntil, bagStacks
local function ReadBuffs()
    local fed = WellFedAura()
    fedUntil = fed and (fed.expirationTime or 0) or false
    local bag = C_UnitAuras.GetPlayerAuraBySpellID(ns.Data.sleepingBag.buffSpellID)
    bagUntil = bag and (bag.expirationTime or 0) or false
    bagStacks = bag and math.max(1, bag.applications or 0) or 0
end

local function Active(untilTime)
    return untilTime and (untilTime == 0 or GetTime() < untilTime) or false
end

-- About how much XP each buff would have added since it was last on (this session):
-- kind "wellFed" or "bag".
function Buffs.MissedXP(kind)
    return missed[kind or "wellFed"]
end

local function AddMissed(kind, xp)
    if xp <= 0 then return end
    missed[kind] = missed[kind] + xp
    local c = ns.Me()
    if c then
        c.missedXP = c.missedXP or {}
        c.missedXP[kind] = (c.missedXP[kind] or 0) + xp
    end
end

local function HasBag()
    local carried, banked, toy = BagWhere()
    return carried + banked > 0 or toy
end

local function FlushXP()
    local b = batch
    batch = nil
    if not BelowMax() then return end
    if not InCombatLockdown() then ReadBuffs() end
    if fedUntil == nil then return end -- the buffs haven't been read yet
    local fed = Active(fedUntil)
    local stacks = Active(bagUntil) and bagStacks or 0
    local bonus = (fed and ns.Data.wellFedXPBonus or 0) + stacks * ns.Data.sleepingBag.xpPerStack
    local explored = exploredAt and GetTime() - exploredAt <= EXPLORE_SECONDS
    local kill = explored and 0 or math.max(0, b.xp - b.quest - b.rested)
    local killBase = kill / (1 + bonus)
    -- The reward QUEST_TURNED_IN gives is taken to include the bag's bonus.
    local questBase = b.quest / (1 + stacks * ns.Data.sleepingBag.xpPerStack)
    if not fed then AddMissed("wellFed", killBase * ns.Data.wellFedXPBonus) end
    local missingStacks = ns.Data.sleepingBag.maxStacks - stacks
    if missingStacks > 0 and HasBag() then
        AddMissed("bag", (killBase + questBase) * missingStacks * ns.Data.sleepingBag.xpPerStack)
    end
    if kill > 0 then
        killedSinceCheck = true
        CheckSoon()
    end
    ns.Reminder.Refresh()
end

local function Batch()
    if not batch then
        batch = { xp = 0, quest = 0, rested = 0 }
        C_Timer.After(1, FlushXP)
    end
    return batch
end

-- A drop in the rested pool is the rested bonus on a kill.
local function SeeRested()
    local now = GetXPExhaustion() or 0
    if issecretvalue and issecretvalue(now) then return end
    if now < restedSeen then
        local b = Batch()
        b.rested = b.rested + restedSeen - now
    end
    restedSeen = now
end

ns.On("PLAYER_XP_UPDATE", function(unit)
    if unit and unit ~= "player" then return end
    local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if issecretvalue and (issecretvalue(xp) or issecretvalue(xpMax)) then return end
    if lastXP then
        local gained
        if level == lastLevel then
            gained = xp - lastXP
        elseif level > lastLevel then
            gained = (lastXPMax - lastXP) + xp
        end
        if gained and gained > 0 then
            local b = Batch()
            b.xp = b.xp + gained
        end
    end
    lastXP, lastXPMax, lastLevel = xp, xpMax, level
    SeeRested()
end)
ns.On("UPDATE_EXHAUSTION", SeeRested)
ns.On("QUEST_TURNED_IN", function(_, xpReward)
    if type(xpReward) == "number" and xpReward > 0 then
        local b = Batch()
        b.quest = b.quest + xpReward
    end
end)
ns.On("MAP_EXPLORATION_UPDATED", function() exploredAt = GetTime() end)

function Buffs.Check()
    -- Auras can be secret in combat; the check runs again when combat ends, transitions intact.
    if InCombatLockdown() or not BelowMax() then return end
    local settings = ns.db.settings.alerts
    local resting = IsResting() and true or false
    local leftRest = wasResting == true and not resting
    -- The first check after logging in or a reload, out in the world, counts as leaving rest.
    local firstOut = wasResting == nil and not resting and settings.buffAtLogin
    local wellFed = WellFedSpell() ~= nil
    local bagBuff = HasAura(ns.Data.sleepingBag.buffSpellID)
    local tent = HasAura(ns.Data.campTent.debuffSpellID)
    local killed = killedSinceCheck
    killedSinceCheck = false

    ReadBuffs()

    -- A buff back on: say what going without cost, and start counting again. The bag's count goes
    -- on while it has fewer than 3 stacks.
    if wellFed and hadWellFed ~= true then
        if hadWellFed == false and missed.wellFed >= 1 and settings.buffMissedXP then
            ns.Print(YELLOW .. format(L["Well Fed again. Without it you missed about %s XP."], ns.FormatNumber(missed.wellFed)) .. "|r")
        end
        missed.wellFed = 0
    end
    if bagBuff and hadBagBuff ~= true then
        if hadBagBuff == false and missed.bag >= 1 and settings.buffMissedXP then
            ns.Print(YELLOW .. format(L["Sleeping bag buff back on. Without it you missed about %s XP."], ns.FormatNumber(missed.bag)) .. "|r")
        end
        missed.bag = 0
    end

    -- What's missing right now, and what just became worth a reminder.
    local missing = {
        wellFed = not resting and settings.wellFed and not wellFed,
        bag = not resting and settings.bagBuff and not bagBuff and Buffs.BagReady(),
    }
    missing.tent = not resting and settings.tent and not tent
    missing.bagLogout = missing.bag
    if resting then
        ns.Reminder.Hide()
    else
        ns.Reminder.Keep(missing)
        -- Leaving rest, or a buff wearing off, brings up the card with everything that's missing.
        local trigger = (missing.wellFed and (leftRest or firstOut or hadWellFed))
            or (missing.bag and (leftRest or firstOut or hadBagBuff))
            or (missing.tent and (leftRest or firstOut or hadTent))
        -- A kill without a buff brings the icons back if they were dismissed, now and then.
        if not trigger and killed and settings.buffOnKill and (missing.wellFed or missing.bag or missing.tent)
            and not ns.Reminder.IsShown()
            and (not lastKillNudge or GetTime() - lastKillNudge >= KILL_NUDGE_SECONDS) then
            trigger = true
            lastKillNudge = GetTime()
        end
        if trigger then
            local kinds = {}
            if missing.wellFed then kinds[#kinds + 1] = "wellFed" end
            if missing.bag then kinds[#kinds + 1] = "bag" end
            if missing.tent then kinds[#kinds + 1] = "tent" end
            Remind(kinds)
        end
    end
    wasResting, hadWellFed, hadBagBuff, hadTent = resting, wellFed, bagBuff, tent
end

local pending
function CheckSoon()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        Buffs.Check()
    end)
end

ns.On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    if isInitialLogin or isReload then
        wasResting, hadWellFed, hadBagBuff, hadTent = nil, nil, nil, nil
    end
    lastXP, lastXPMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    restedSeen = GetXPExhaustion() or 0
    C_Timer.After(5, Buffs.Check)
end)
ns.On("UNIT_AURA", function(unit) if unit == "player" then CheckSoon() end end)
ns.On("PLAYER_REGEN_ENABLED", CheckSoon)
-- Leaving rest is checked right away, so the reminder appears as the bars window closes.
ns.On("PLAYER_UPDATE_RESTING", function() Buffs.Check() end)

-- Logging out with a ready sleeping bag and no Well-Rested buff.
ns.On("PLAYER_CAMPING", function()
    if not ns.db.settings.alerts.bagLogout or not BelowMax() or IsResting() then return end
    if Buffs.BagReady() and not HasAura(ns.Data.sleepingBag.buffSpellID) then
        Remind({ "bagLogout" })
    end
end)

-- What the reminders see right now: /nw buffs
function Buffs.Report()
    local function YesNo(v) return v and L["yes"] or L["no"] end
    local carried, banked, toy = BagWhere()
    local cd = BagCooldown()
    ns.Print(format(L["Below max level: %s. Resting: %s. In combat: %s."], YesNo(BelowMax()),
        YesNo(IsResting()), YesNo(InCombatLockdown())))
    local wellFedSpell = WellFedSpell()
    ns.Print(wellFedSpell and format(L["Well Fed: yes (spell %d)."], wellFedSpell) or L["Well Fed: no."])
    ns.Print(format(L["Cozy Sleeping Bag (%d): %d in bags, %d in the bank, toy: %s, cooldown: %s."],
        ns.Data.sleepingBag.itemID, carried, banked, YesNo(toy), cd > 0 and ns.FormatDuration(cd) or L["ready"]))
    ns.Print(format(L["Well-Rested buff (%d): %s. Bag reminder possible now: %s."], ns.Data.sleepingBag.buffSpellID,
        YesNo(HasAura(ns.Data.sleepingBag.buffSpellID)),
        YesNo(Buffs.BagReady() and not IsResting() and not HasAura(ns.Data.sleepingBag.buffSpellID))))
    ns.Print(format(L["Boosted Rest from a Camp Tent (%d): %s."], ns.Data.campTent.debuffSpellID,
        YesNo(HasAura(ns.Data.campTent.debuffSpellID))))
    local _, food = Buffs.WellFedFood()
    ns.Print(food and format(L["Food that gives Well Fed in your bags: %s."], food) or L["Food that gives Well Fed in your bags: none found."])
    local total = ns.Me() and ns.Me().missedXP or {}
    ns.Print(format(L["XP missed without Well Fed: about %s since it was last on, %s in all. Without the sleeping bag: about %s, %s in all."],
        ns.FormatNumber(missed.wellFed), ns.FormatNumber(total.wellFed or 0), ns.FormatNumber(missed.bag), ns.FormatNumber(total.bag or 0)))
end
