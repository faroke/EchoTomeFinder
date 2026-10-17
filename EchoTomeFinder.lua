-- EchoTomeFinder
--
-- Spots Echo Tomes in your bags and in loot rolls, and checks them against the
-- saved builds of ALL your characters:
--   * server builds (Echo Journal slots, Loadouts tab)
--   * local library (ProjectEbonholdDB.echoLoadouts)
--
-- Each character records its builds when it logs in (EchoTomeFinderDB.chars),
-- and the other characters see them afterwards. Every character has a color
-- (class color by default, changed with /etf color).
--
-- Ebonhold convention: tome itemId == echoSpellId + 100000.
-- A build echo matches the tome when its spellId is the same, or when its name
-- is (same echo, another quality = another spellId).

local _, ns = ...

local ID_OFFSET = 100000
local PREFIX = "|cffb048f8EchoTomeFinder|r: "

local defaults = {
    sound = true,       -- play a sound when a wanted tome shows up
    allClasses = false, -- include local builds of other classes
    alts = true,        -- take other characters' builds into account
}

local db
local tomesInBags = {}   -- [itemId] = { echoId, link, name, count, wanters }
local alerted = {}       -- [itemId] = true, already announced this session
local firstScanDone = false
local requestedSlots = false

-- Translation lookup; falls back to the English key
local function L(s)
    local t = db and ns.Locales[db.lang]
    return (t and t[s]) or s
end

-- Same key as ProjectEbonhold (echoDiscovery), so we can read what the other
-- characters have already learned
local function CharKey()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or "Unknown"
    return realm .. "\t" .. (UnitName("player") or "Unknown")
end
local myKey

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function Perks()
    return ProjectEbonhold and ProjectEbonhold.PerkService
end

-- echoId + data when the item is an echo tome, nil otherwise
local function GetEchoForItem(itemId)
    if not itemId then return nil end
    local echoId = itemId - ID_OFFSET
    if echoId <= 0 then return nil end
    local data = ProjectEbonhold and ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[echoId]
    if not data or not data.requiredSpell or data.requiredSpell == 0 then return nil end
    return echoId, data
end

local function ItemIdFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- ── Colors ───────────────────────────────────────────────────────────────────

local function CharColor(key)
    local c = db.colors[key]
    if c then return c end
    local char = db.chars[key]
    local cc = char and RAID_CLASS_COLORS[char.class]
    if cc then return { r = cc.r, g = cc.g, b = cc.b } end
    return { r = 1, g = 1, b = 1 }
end

local function Colorize(key, text)
    local c = CharColor(key)
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), text)
end

-- ── Build index of the logged-in character ───────────────────────────────────
-- index[spellId] / index[name] = { "Build A", "Build B", ... }

local function AddToIndex(index, spellId, label)
    local name = GetSpellInfo(spellId)
    for _, key in ipairs({ spellId, name }) do
        if key then
            local list = index[key]
            if not list then
                list = {}
                index[key] = list
            end
            local present = false
            for _, l in ipairs(list) do
                if l == label then present = true break end
            end
            if not present then table.insert(list, label) end
        end
    end
end

local function BuildProfileIndex()
    local index, count = {}, 0
    local svc = Perks()
    if not svc then return index, count end

    local slots = svc.GetServerBuildSlots and svc.GetServerBuildSlots()
    if slots then
        for slot, build in pairs(slots) do
            count = count + 1
            local label = (build.name ~= "" and build.name) or string.format(L("Slot %d"), slot)
            for _, e in ipairs(build.echoes or {}) do
                AddToIndex(index, e.spellId, label)
            end
        end
    end

    local _, myClass = UnitClass("player")
    local library = svc.GetEchoLoadouts and svc.GetEchoLoadouts()
    for _, loadout in ipairs(library or {}) do
        if db.allClasses or not loadout.class or loadout.class == myClass then
            count = count + 1
            local label = loadout.name or "?"
            if loadout.class and loadout.class ~= myClass then
                label = label .. " (" .. loadout.class .. ")"
            end
            for _, e in ipairs(loadout.echoes or {}) do
                AddToIndex(index, e.spellId, label)
            end
        end
    end
    return index, count
end

-- Memo for WhoWants, cleared whenever builds or learned echoes may have changed
local wantCache = {}
local function InvalidateIndex()
    wantCache = {}
end

-- Records the logged-in character's builds and learned echoes.
-- Nothing is written until the server has sent the builds, so a valid record
-- is never overwritten by an empty list.
local function SaveSnapshot()
    local svc = Perks()
    if not (db and svc) then return end
    if svc.GetServerBuildSlots and svc.GetServerBuildSlots() == nil then return end

    local index, count = BuildProfileIndex()
    local learned = {}
    for id in pairs((svc.GetDiscoveredEchoes and svc.GetDiscoveredEchoes()) or {}) do
        learned[id] = true
    end
    local _, class = UnitClass("player")
    db.chars[myKey] = {
        name = UnitName("player"),
        class = class,
        index = index,
        builds = count,
        learned = learned,
        updated = time(),
    }
    InvalidateIndex()
end

local function GetCharLearned(key)
    if key == myKey then
        local svc = Perks()
        return (svc and svc.GetDiscoveredEchoes and svc.GetDiscoveredEchoes()) or {}
    end
    -- ProjectEbonhold's own cache (refreshed every time that character logs in)
    local pe = ProjectEbonholdDB and ProjectEbonholdDB.echoDiscovery and ProjectEbonholdDB.echoDiscovery[key]
    if pe and next(pe) then return pe end
    local char = db.chars[key]
    return (char and char.learned) or {}
end

local function ProfilesIn(index, echoId)
    local result, seen = {}, {}
    local name = GetSpellInfo(echoId)
    for _, key in ipairs({ echoId, name }) do
        for _, label in ipairs((index and key and index[key]) or {}) do
            if not seen[label] then
                seen[label] = true
                table.insert(result, label)
            end
        end
    end
    return result
end

-- Characters that want this echo and have not learned it yet:
-- { { key, name, profiles }, ... }, logged-in character first.
local function WhoWants(echoId)
    local cached = wantCache[echoId]
    if cached then return cached end

    local list = {}
    for key, char in pairs(db.chars) do
        if key == myKey or db.alts then
            local profiles = ProfilesIn(char.index, echoId)
            if #profiles > 0 and not GetCharLearned(key)[echoId] then
                table.insert(list, { key = key, name = char.name or key, profiles = profiles })
            end
        end
    end
    table.sort(list, function(a, b)
        if (a.key == myKey) ~= (b.key == myKey) then return a.key == myKey end
        return a.name < b.name
    end)
    wantCache[echoId] = list
    return list
end

local function WantersForItem(itemId)
    local echoId = GetEchoForItem(itemId)
    if not echoId then return nil end
    return WhoWants(echoId), echoId
end

local function DescribeWanters(wanters)
    local parts = {}
    for _, w in ipairs(wanters) do
        table.insert(parts, Colorize(w.key, w.name .. " (" .. table.concat(w.profiles, ", ") .. ")"))
    end
    return table.concat(parts, ", ")
end

-- ── Highlight ────────────────────────────────────────────────────────────────
-- Border in the color of the first interested character; a number shows how
-- many characters want the tome when there is more than one.
--   * wanted by the logged-in character: bright pulsing border + star icon
--   * wanted only by other characters: faint, still border

local function SetGlow(button, wanters)
    local glow = button.EchoTomeFinderGlow
    if not wanters or #wanters == 0 then
        if glow then
            glow.anim:Stop()
            glow:Hide()
            glow.badge:Hide()
        end
        return
    end
    if not glow then
        glow = CreateFrame("Frame", nil, button)
        glow:SetFrameLevel(button:GetFrameLevel() + 5)
        glow:SetPoint("CENTER")
        local w = button:GetWidth()
        glow:SetWidth(w * 1.8)
        glow:SetHeight(w * 1.8)
        glow.tex = glow:CreateTexture(nil, "OVERLAY")
        glow.tex:SetAllPoints()
        glow.tex:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
        glow.tex:SetBlendMode("ADD")
        glow.anim = glow:CreateAnimationGroup()
        local fade = glow.anim:CreateAnimation("Alpha")
        fade:SetChange(-0.7)
        fade:SetDuration(0.6)
        glow.anim:SetLooping("BOUNCE")

        -- The number must not blink: separate frame
        local badge = CreateFrame("Frame", nil, button)
        badge:SetFrameLevel(button:GetFrameLevel() + 6)
        badge:SetAllPoints(button)
        badge.text = badge:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        badge.text:SetPoint("TOPLEFT", 2, -2)
        badge.star = badge:CreateTexture(nil, "OVERLAY")
        badge.star:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcon_1]])
        badge.star:SetWidth(14)
        badge.star:SetHeight(14)
        badge.star:SetPoint("TOPRIGHT", 2, 2)
        glow.badge = badge
        button.EchoTomeFinderGlow = glow
    end
    local c = CharColor(wanters[1].key)
    glow.tex:SetVertexColor(c.r, c.g, c.b)
    glow:Show()
    -- WhoWants puts the logged-in character first
    local mine = wanters[1].key == myKey
    if mine then
        glow:SetAlpha(1)
        if not glow.anim:IsPlaying() then glow.anim:Play() end
        glow.badge.star:Show()
    else
        glow.anim:Stop()
        glow:SetAlpha(0.35)
        glow.badge.star:Hide()
    end
    glow.badge:Show()
    if #wanters > 1 then
        glow.badge.text:SetText(#wanters)
    else
        glow.badge.text:SetText("")
    end
end

local function UpdateButtonFromLink(button, link)
    if not (button and db) then return end
    SetGlow(button, WantersForItem(ItemIdFromLink(link)))
end

local function UpdateButton(button, bag, slot)
    if not button then return end
    UpdateButtonFromLink(button, GetContainerItemLink(bag, slot))
end

-- ── Bags (ElvUI and Blizzard) ────────────────────────────────────────────────

local function GetElvModule(name)
    if not ElvUI then return nil end
    local E = unpack(ElvUI)
    local ok, mod = pcall(E.GetModule, E, name)
    if ok then return mod end
end

local function RefreshHighlights()
    if not (db and ProjectEbonhold and ProjectEbonhold.PerkDatabase) then return end

    local B = GetElvModule("Bags")
    if B and B.Initialized and B.BagFrames then
        for _, frame in pairs(B.BagFrames) do
            for bagID, bag in pairs(frame.Bags or {}) do
                for slotID = 1, (bag.numSlots or 0) do
                    UpdateButton(bag[slotID], bagID, slotID)
                end
            end
        end
    end

    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            local bag = frame:GetID()
            for j = 1, (frame.size or 0) do
                local button = _G[frame:GetName() .. "Item" .. j]
                UpdateButton(button, bag, button:GetID())
            end
        end
    end
end

local function HookBagAddons()
    local B = GetElvModule("Bags")
    if B and B.Initialized and B.UpdateSlot and not B.EchoTomeFinderHooked then
        B.EchoTomeFinderHooked = true
        hooksecurefunc(B, "UpdateSlot", function(_, frame, bagID, slotID)
            local bag = frame and frame.Bags and frame.Bags[bagID]
            UpdateButton(bag and bag[slotID], bagID, slotID)
        end)
    end
end

hooksecurefunc("ContainerFrame_Update", function(frame)
    local bag = frame:GetID()
    for j = 1, (frame.size or 0) do
        local button = _G[frame:GetName() .. "Item" .. j]
        UpdateButton(button, bag, button:GetID())
    end
end)

-- ── Alerts ───────────────────────────────────────────────────────────────────

-- Sound and on-screen warning only when the logged-in character wants the
-- tome; for other characters a chat line is enough.
local function Alert(title, link, echoId, wanters)
    Print("|cff20ff20" .. title .. "|r " .. link .. " -> " .. DescribeWanters(wanters))
    if wanters[1].key ~= myKey then return end
    if firstScanDone then
        local names = {}
        for _, w in ipairs(wanters) do table.insert(names, Colorize(w.key, w.name)) end
        RaidNotice_AddMessage(RaidWarningFrame,
            title .. " " .. (GetSpellInfo(echoId) or "") .. " (" .. table.concat(names, ", ") .. ")",
            ChatTypeInfo["RAID_WARNING"])
    end
    if db.sound then PlaySound("RaidWarning") end
end

-- ── Loot rolls (Need / Greed) ────────────────────────────────────────────────
-- Handles ElvUI roll bars and Blizzard GroupLootFrames.

local function ForEachRollFrame(fn)
    local M = GetElvModule("Misc")
    if M and M.RollBars then
        for _, frame in ipairs(M.RollBars) do
            fn(frame, frame.itemButton)
        end
    end
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local frame = _G["GroupLootFrame" .. i]
        if frame then fn(frame, _G["GroupLootFrame" .. i .. "IconFrame"]) end
    end
end

local function RefreshRollGlows()
    if not db then return end
    ForEachRollFrame(function(frame, icon)
        if not icon then return end
        if frame:IsShown() and frame.rollID then
            UpdateButtonFromLink(icon, GetLootRollItemLink(frame.rollID))
        else
            SetGlow(icon, nil)
        end
    end)
end

-- Roll frames are filled during the same event: wait a moment before
-- placing the border.
local rollTimer = CreateFrame("Frame")
rollTimer:Hide()
rollTimer:SetScript("OnUpdate", function(self, elapsed)
    self.wait = self.wait - elapsed
    if self.wait <= 0 then
        self:Hide()
        RefreshRollGlows()
    end
end)

local function QueueRollRefresh()
    rollTimer.wait = 0.1
    rollTimer:Show()
end

local function OnLootRoll(rollID)
    local link = GetLootRollItemLink(rollID)
    local wanters, echoId = WantersForItem(ItemIdFromLink(link))
    if wanters and #wanters > 0 then
        Alert(L("Wanted tome in a loot roll!"), link, echoId, wanters)
    end
    QueueRollRefresh()
end

-- ── Bag scan ─────────────────────────────────────────────────────────────────

local function DescribeTome(t)
    local line = t.link or t.name
    if t.count > 1 then line = line .. " x" .. t.count end
    if #t.wanters > 0 then
        line = line .. " -> " .. DescribeWanters(t.wanters)
    else
        line = line .. " -> |cff999999" .. L("no character") .. "|r"
    end
    return line
end

local function ScanBags()
    if not (db and ProjectEbonhold and ProjectEbonhold.PerkDatabase) then return end
    -- Using a tome changes the learned echoes: start from an empty memo
    InvalidateIndex()

    local found = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            local itemId = ItemIdFromLink(link)
            local wanters, echoId = WantersForItem(itemId)
            if wanters then
                local _, count = GetContainerItemInfo(bag, slot)
                local t = found[itemId]
                if t then
                    t.count = t.count + (count or 1)
                else
                    found[itemId] = {
                        echoId = echoId,
                        link = link,
                        name = GetSpellInfo(echoId) or ("Echo " .. echoId),
                        count = count or 1,
                        wanters = wanters,
                    }
                end
            end
        end
    end

    -- Announce every wanted tome that just appeared in the bags
    local newMatches = {}
    for itemId, t in pairs(found) do
        if #t.wanters > 0 and not alerted[itemId] then
            alerted[itemId] = true
            table.insert(newMatches, t)
        end
    end
    -- A tome that leaves the bags can trigger an alert again later
    for itemId in pairs(alerted) do
        if not found[itemId] then alerted[itemId] = nil end
    end

    tomesInBags = found
    RefreshHighlights()

    for i, t in ipairs(newMatches) do
        -- One sound / on-screen alert, but every tome gets a chat line
        if i == 1 then
            Alert(L("Wanted tome!"), t.link, t.echoId, t.wanters)
        else
            Print("|cff20ff20" .. L("Wanted tome!") .. "|r " .. DescribeTome(t))
        end
    end
    firstScanDone = true
end

-- Bag events come in bursts: scan once at the end
local throttle = CreateFrame("Frame")
throttle:Hide()
throttle:SetScript("OnUpdate", function(self, elapsed)
    self.wait = self.wait - elapsed
    if self.wait <= 0 then
        self:Hide()
        ScanBags()
    end
end)

local function QueueScan(delay)
    throttle.wait = delay or 0.3
    throttle:Show()
end

local function RefreshAll()
    InvalidateIndex()
    ScanBags()
    RefreshRollGlows()
end

-- ── Tooltip ──────────────────────────────────────────────────────────────────

local function AddTooltipLines(tooltip)
    if not (db and tooltip and tooltip.GetItem) then return end
    local _, link = tooltip:GetItem()
    local wanters = WantersForItem(ItemIdFromLink(link))
    if not wanters then return end

    if #wanters > 0 then
        tooltip:AddLine(L("Wanted by:"), 1, 0.82, 0)
        for _, w in ipairs(wanters) do
            local c = CharColor(w.key)
            tooltip:AddDoubleLine("  " .. w.name, table.concat(w.profiles, ", "), c.r, c.g, c.b, c.r, c.g, c.b)
        end
    else
        tooltip:AddLine(L("Wanted by no character"), 0.6, 0.6, 0.6)
    end
    tooltip:Show()
end

-- ── Commands ─────────────────────────────────────────────────────────────────

local function FindChar(name)
    name = (name or ""):lower()
    for key, char in pairs(db.chars) do
        if (char.name or ""):lower() == name then return key, char end
    end
end

local function ParseColor(arg)
    local hex = (arg or ""):match("^#?(%x%x%x%x%x%x)$")
    if not hex then return nil end
    return {
        r = tonumber(hex:sub(1, 2), 16) / 255,
        g = tonumber(hex:sub(3, 4), 16) / 255,
        b = tonumber(hex:sub(5, 6), 16) / 255,
    }
end

local function ListTomes()
    ScanBags()
    local list = {}
    for _, t in pairs(tomesInBags) do table.insert(list, t) end
    if #list == 0 then
        Print(L("no Echo Tome in your bags."))
        return
    end
    table.sort(list, function(a, b)
        if (#a.wanters > 0) ~= (#b.wanters > 0) then return #a.wanters > 0 end
        return a.name < b.name
    end)
    Print(string.format(L("%d Echo Tome(s) in your bags:"), #list))
    for _, t in ipairs(list) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. DescribeTome(t))
    end
end

local function ListBuilds()
    local svc = Perks()
    if not svc then
        Print(L("ProjectEbonhold not found."))
        return
    end
    local n = 0
    local slots = svc.GetServerBuildSlots and svc.GetServerBuildSlots()
    if slots then
        for slot, build in pairs(slots) do
            n = n + 1
            Print(string.format(L("server #%d %s (%d echoes)"), slot,
                build.name ~= "" and build.name or L("unnamed"), #(build.echoes or {})))
        end
    else
        Print(L("server builds not received yet, request sent again."))
        if svc.RequestServerBuildSlots then svc.RequestServerBuildSlots() end
    end
    for _, l in ipairs((svc.GetEchoLoadouts and svc.GetEchoLoadouts()) or {}) do
        n = n + 1
        Print(string.format(L("local %s [%s] (%d echoes)"), l.name or "?", l.class or "?", #(l.echoes or {})))
    end
    if n == 0 then Print(L("no saved build.")) end
end

local function ListChars()
    local list = {}
    for key, char in pairs(db.chars) do table.insert(list, { key = key, char = char }) end
    if #list == 0 then
        Print(L("no character recorded yet."))
        return
    end
    table.sort(list, function(a, b) return (a.char.name or "") < (b.char.name or "") end)
    Print(db.alts and L("recorded characters:")
        or L("recorded characters (other characters ignored, see /etf alts):"))
    for _, e in ipairs(list) do
        local c = e.char
        DEFAULT_CHAT_FRAME:AddMessage(string.format(L("  %s - %s, %d build(s), updated %s%s"),
            Colorize(e.key, c.name or "?"), c.class or "?", c.builds or 0,
            c.updated and date("%d/%m %H:%M", c.updated) or "?",
            e.key == myKey and ("|cff999999" .. L(" (logged in)") .. "|r") or ""))
    end
end

local function PrintHelp()
    Print(L("/etf: list tomes in your bags and who wants them"))
    Print(L("/etf chars: list recorded characters and their color"))
    Print(L("/etf color <Name> <rrggbb|reset>: change a character's color"))
    Print(L("/etf forget <Name>: remove a character"))
    Print(L("/etf alts: include or ignore other characters"))
    Print(L("/etf builds: list the logged-in character's builds"))
    Print(L("/etf sound: toggle the alert sound"))
    Print(L("/etf classes: include local builds of other classes"))
    Print(L("/etf lang <en|fr>: change the language"))
end

-- French aliases for the commands
local ALIASES = {
    liste = "list", persos = "chars", couleur = "color",
    oublier = "forget", son = "sound", langue = "lang",
}

SLASH_ECHOTOMEFINDER1 = "/etf"
SLASH_ECHOTOMEFINDER2 = "/tomes"
SlashCmdList["ECHOTOMEFINDER"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    cmd = ALIASES[cmd] or cmd

    if cmd == "" or cmd == "list" then
        ListTomes()
    elseif cmd == "builds" then
        ListBuilds()
    elseif cmd == "chars" then
        ListChars()
    elseif cmd == "color" then
        local name, value = rest:match("^(%S+)%s*(%S*)$")
        local key, char = FindChar(name)
        if not key then
            Print(L("unknown character. Usage: /etf color <Name> <rrggbb|reset>"))
            return
        end
        if value:lower() == "reset" or value == "" then
            db.colors[key] = nil
        else
            local c = ParseColor(value)
            if not c then
                Print(string.format(L("invalid color, example: /etf color %s ff8800"), char.name))
                return
            end
            db.colors[key] = c
        end
        Print(string.format(L("color of %s updated."), Colorize(key, char.name)))
        RefreshAll()
    elseif cmd == "forget" then
        local key, char = FindChar(rest)
        if not key then
            Print(L("unknown character. Usage: /etf forget <Name>"))
            return
        end
        db.chars[key] = nil
        db.colors[key] = nil
        Print(string.format(key == myKey and L("%s forgotten (recorded again on the next build update).")
            or L("%s forgotten."), char.name))
        RefreshAll()
    elseif cmd == "alts" then
        db.alts = not db.alts
        Print(db.alts and L("other characters' builds included.") or L("other characters' builds ignored."))
        RefreshAll()
    elseif cmd == "sound" then
        db.sound = not db.sound
        Print(db.sound and L("alert sound enabled.") or L("alert sound disabled."))
    elseif cmd == "classes" then
        db.allClasses = not db.allClasses
        Print(db.allClasses and L("local builds of other classes included.")
            or L("local builds of other classes excluded."))
        SaveSnapshot()
        RefreshAll()
    elseif cmd == "lang" and (rest == "en" or rest == "fr") then
        db.lang = rest
        Print(rest == "fr" and L("language: French.") or L("language: English."))
    else
        PrintHelp()
    end
end

-- ── Initialization ───────────────────────────────────────────────────────────

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("BAG_UPDATE")
f:RegisterEvent("START_LOOT_ROLL")
f:RegisterEvent("CANCEL_LOOT_ROLL")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "EchoTomeFinder" then
        EchoTomeFinderDB = EchoTomeFinderDB or {}
        db = EchoTomeFinderDB
        -- Language: French client -> French. Data from 1.x (French-only
        -- versions) also means French, so existing users keep their language.
        if db.lang == nil then
            db.lang = (GetLocale() == "frFR" or db.chars ~= nil or db.sound ~= nil) and "fr" or "en"
        end
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        db.chars = db.chars or {}
        db.colors = db.colors or {}
        myKey = CharKey()

        GameTooltip:HookScript("OnTooltipSetItem", AddTooltipLines)
        ItemRefTooltip:HookScript("OnTooltipSetItem", AddTooltipLines)

        -- Server builds received or changed: record them and rescan
        if ProjectEbonhold and ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.RefreshLoadoutHighlights then
            hooksecurefunc(ProjectEbonhold.PerkUI, "RefreshLoadoutHighlights", function()
                SaveSnapshot()
                InvalidateIndex()
                QueueScan(0.5)
            end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local svc = Perks()
        if not svc then
            Print(L("ProjectEbonhold not found, addon disabled."))
            return
        end
        -- ProjectEbonhold only requests the builds after the "active slot"
        -- event; if they are still missing, ask once.
        if not requestedSlots then
            requestedSlots = true
            local timer = CreateFrame("Frame")
            timer.t = 5
            timer:SetScript("OnUpdate", function(tf, elapsed)
                tf.t = tf.t - elapsed
                if tf.t > 0 then return end
                tf:SetScript("OnUpdate", nil)
                if svc.GetServerBuildSlots and svc.GetServerBuildSlots() == nil and svc.RequestServerBuildSlots then
                    svc.RequestServerBuildSlots()
                end
                SaveSnapshot()
                QueueScan(1)
            end)
        end
        HookBagAddons()
        QueueScan(2)
    elseif event == "PLAYER_LOGOUT" then
        SaveSnapshot()
    elseif event == "BAG_UPDATE" then
        if db then QueueScan() end
    elseif event == "START_LOOT_ROLL" then
        if db then OnLootRoll(arg1) end
    elseif event == "CANCEL_LOOT_ROLL" then
        QueueRollRefresh()
    end
end)
