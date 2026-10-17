-- EchoTomeFinder window and minimap button
--
-- Minimap button (drag it around the minimap):
--   left click  = open / close the window
--   right click = open the Options tab
-- Window tabs: Tomes (bag content), Characters (colors, forget), Options.

local _, ns = ...
local L = function(s) return ns.L(s) end
local Core

local WIDTH, HEIGHT = 470, 420
local ROW_H = 26

local BACKDROP = {
    bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
    edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local window

-- Region:SetShown does not exist on 3.3.5
local function SetShown(region, show)
    if show then region:Show() else region:Hide() end
end
local tabs = {}
local pages = {}
local currentTab = 1

-- ── Small widgets ────────────────────────────────────────────────────────────

local function CreateScrollList(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(WIDTH - 60)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    scroll.content = content
    scroll.rows = {}
    scroll.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    scroll.empty:SetPoint("TOP", 0, -20)
    return scroll
end

local function RowBackground(row, index)
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetTexture(1, 1, 1)
    end
    row.bg:SetAlpha(index % 2 == 0 and 0.05 or 0)
end

local function CreateCheck(parent, y, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb:SetWidth(26)
    cb:SetHeight(26)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label = label
    cb.get = get
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    return cb
end

-- ── Tomes tab ────────────────────────────────────────────────────────────────

local function TomeRow(scroll, i)
    local row = scroll.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, scroll.content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", scroll.content, "RIGHT")
    row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(ROW_H - 4)
    row.icon:SetHeight(ROW_H - 4)
    row.icon:SetPoint("LEFT", 2, 0)
    row.star = row:CreateTexture(nil, "OVERLAY")
    row.star:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcon_1]])
    row.star:SetWidth(12)
    row.star:SetHeight(12)
    row.star:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 4, 4)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)

    row.who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.who:SetPoint("LEFT", row, "LEFT", 190, 0)
    row.who:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.who:SetJustifyH("LEFT")
    row.who:SetHeight(ROW_H)

    row:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-click links the tome in chat, ctrl-click previews it
    row:SetScript("OnClick", function(self)
        if self.link then HandleModifiedItemClick(self.link) end
    end)
    scroll.rows[i] = row
    return row
end

local function RefreshTomes()
    local scroll = pages[1].scroll
    local tomes = Core.GetTomes()
    local myKey = Core.GetMyKey()
    for i, t in ipairs(tomes) do
        local row = TomeRow(scroll, i)
        RowBackground(row, i)
        row.link = t.link
        -- The echo's own icon says more than the generic tome book
        local _, _, echoIcon = GetSpellInfo(t.echoId)
        row.icon:SetTexture(echoIcon or t.texture or [[Interface\Icons\INV_Misc_QuestionMark]])
        row.name:SetText(t.name)
        row.count:SetText(t.count > 1 and ("x" .. t.count) or "")
        local mine = #t.wanters > 0 and t.wanters[1].key == myKey
        SetShown(row.star, mine)
        row.icon:SetAlpha(#t.wanters > 0 and 1 or 0.4)
        if #t.wanters > 0 then
            local parts = {}
            for _, w in ipairs(t.wanters) do
                table.insert(parts, Core.Colorize(w.key, w.name) .. " |cff999999(" .. table.concat(w.profiles, ", ") .. ")|r")
            end
            row.who:SetText(table.concat(parts, ", "))
        else
            row.who:SetText("|cff999999" .. L("no character") .. "|r")
        end
        row:Show()
    end
    for i = #tomes + 1, #scroll.rows do scroll.rows[i]:Hide() end
    scroll.content:SetHeight(math.max(1, #tomes * ROW_H))
    scroll.empty:SetText(#tomes == 0 and L("no Echo Tome in your bags.") or "")
end

-- ── Characters tab ───────────────────────────────────────────────────────────

local function OpenColorPicker(key)
    local db = Core.GetDB()
    local c = Core.CharColor(key)
    local function apply(color)
        db.colors[key] = color
        Core.RefreshAll()
    end
    ColorPickerFrame:Hide()
    -- No callbacks while setting the start color, or it would be saved at once
    ColorPickerFrame.func = nil
    ColorPickerFrame.cancelFunc = nil
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
    ColorPickerFrame.previousValues = { r = c.r, g = c.g, b = c.b, custom = db.colors[key] ~= nil }
    ColorPickerFrame.func = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        apply({ r = r, g = g, b = b })
    end
    ColorPickerFrame.cancelFunc = function(prev)
        apply(prev.custom and { r = prev.r, g = prev.g, b = prev.b } or nil)
    end
    ShowUIPanel(ColorPickerFrame)
end

StaticPopupDialogs["ECHOTOMEFINDER_FORGET"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, key)
        local db = Core.GetDB()
        db.chars[key] = nil
        db.colors[key] = nil
        Core.RefreshAll()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function CharRow(scroll, i)
    local row = scroll.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, scroll.content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", scroll.content, "RIGHT")

    row.swatch = CreateFrame("Button", nil, row)
    row.swatch:SetWidth(18)
    row.swatch:SetHeight(18)
    row.swatch:SetPoint("LEFT", 4, 0)
    row.swatch.tex = row.swatch:CreateTexture(nil, "ARTWORK")
    row.swatch.tex:SetAllPoints()
    row.swatch.tex:SetTexture(1, 1, 1)
    row.swatch:SetBackdrop({ edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
    row.swatch:SetBackdropBorderColor(0, 0, 0)
    row.swatch:SetScript("OnClick", function(self) OpenColorPicker(self:GetParent().key) end)
    row.swatch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("Click to change the color"))
        GameTooltip:Show()
    end)
    row.swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
    row.name:SetWidth(170)
    row.name:SetJustifyH("LEFT")
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.info:SetJustifyH("LEFT")

    row.reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.reset:SetWidth(22)
    row.reset:SetHeight(20)
    row.reset:SetText("R")
    row.reset:SetScript("OnClick", function(self)
        Core.GetDB().colors[self:GetParent().key] = nil
        Core.RefreshAll()
    end)
    row.reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("Reset to class color"))
        GameTooltip:Show()
    end)
    row.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.forget = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.forget:SetWidth(24)
    row.forget:SetHeight(24)
    row.forget:SetPoint("RIGHT", -2, 0)
    row.forget:SetScript("OnClick", function(self)
        local r = self:GetParent()
        local dialog = StaticPopup_Show("ECHOTOMEFINDER_FORGET", string.format(L("Forget %s?"), r.charName))
        if dialog then dialog.data = r.key end
    end)
    row.reset:SetPoint("RIGHT", row.forget, "LEFT", -2, 0)
    scroll.rows[i] = row
    return row
end

local function RefreshChars()
    local scroll = pages[2].scroll
    local db = Core.GetDB()
    local myKey = Core.GetMyKey()
    local list = {}
    for key, char in pairs(db.chars) do table.insert(list, { key = key, char = char }) end
    table.sort(list, function(a, b) return (a.char.name or "") < (b.char.name or "") end)

    for i, e in ipairs(list) do
        local row = CharRow(scroll, i)
        RowBackground(row, i)
        row.key = e.key
        row.charName = e.char.name or "?"
        local c = Core.CharColor(e.key)
        row.swatch.tex:SetVertexColor(c.r, c.g, c.b)
        row.name:SetText(Core.Colorize(e.key, row.charName)
            .. (e.key == myKey and (" |cff999999" .. L(" (logged in)") .. "|r") or ""))
        row.info:SetText(string.format(L("%d build(s), %s"), e.char.builds or 0,
            e.char.updated and date("%d/%m %H:%M", e.char.updated) or "?"))
        SetShown(row.reset, db.colors[e.key] ~= nil)
        row:Show()
    end
    for i = #list + 1, #scroll.rows do scroll.rows[i]:Hide() end
    scroll.content:SetHeight(math.max(1, #list * ROW_H))
    scroll.empty:SetText(#list == 0 and L("no character recorded yet.") or "")
end

-- ── Options tab ──────────────────────────────────────────────────────────────

local function RefreshOptions()
    local page = pages[3]
    for _, cb in ipairs(page.checks) do
        cb.text:SetText(L(cb.label))
        cb:SetChecked(cb.get())
    end
    page.langLabel:SetText(L("Language"))
    page.legend:SetText(L("legend"))
end

local function BuildOptions(page)
    local function db() return Core.GetDB() end
    page.checks = {
        CreateCheck(page, -12, "Alert sound",
            function() return db().sound end,
            function(v) db().sound = v end),
        CreateCheck(page, -40, "Chat messages",
            function() return db().chat end,
            function(v) db().chat = v end),
        CreateCheck(page, -68, "Include my other characters",
            function() return db().alts end,
            function(v) db().alts = v Core.RefreshAll() end),
        CreateCheck(page, -96, "Include Echo Wishlists",
            function() return db().wishlists end,
            function(v) db().wishlists = v Core.RefreshAll() end),
        CreateCheck(page, -124, "Include local loadouts of other classes",
            function() return db().allClasses end,
            function(v) db().allClasses = v Core.SaveSnapshot() Core.RefreshAll() end),
        CreateCheck(page, -152, "Show minimap button",
            function() return not db().minimap.hide end,
            function(v) db().minimap.hide = not v ns.UpdateMinimapButton() end),
    }

    page.langLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    page.langLabel:SetPoint("TOPLEFT", 20, -190)
    local x = 120
    for _, lang in ipairs({ { "en", "English" }, { "fr", "Français" } }) do
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetWidth(90)
        b:SetHeight(22)
        b:SetPoint("LEFT", page.langLabel, "LEFT", x, 0)
        b:SetText(lang[2])
        b:SetScript("OnClick", function()
            db().lang = lang[1]
            ns.RefreshWindow()
        end)
        x = x + 96
    end

    page.legend = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.legend:SetPoint("TOPLEFT", 20, -228)
    page.legend:SetPoint("RIGHT", page, "RIGHT", -20, 0)
    page.legend:SetJustifyH("LEFT")
    page.legend:SetSpacing(4)
end

-- ── Window ───────────────────────────────────────────────────────────────────

local TAB_LABELS = { "Tomes", "Characters", "Options" }

local function SelectTab(index)
    currentTab = index
    for i, page in ipairs(pages) do
        SetShown(page, i == index)
        if i == index then tabs[i]:LockHighlight() else tabs[i]:UnlockHighlight() end
    end
    ns.RefreshWindow()
end

local function CreateWindow()
    window = CreateFrame("Frame", "EchoTomeFinderWindow", UIParent)
    window:SetWidth(WIDTH)
    window:SetHeight(HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetBackdrop(BACKDROP)
    window:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    -- Escape closes it
    table.insert(UISpecialFrames, "EchoTomeFinderWindow")

    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    window.title:SetPoint("TOPLEFT", 14, -12)
    window.title:SetText("|cffb048f8EchoTomeFinder|r")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    for i = 1, #TAB_LABELS do
        local tab = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        tab:SetWidth(110)
        tab:SetHeight(22)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 114, -38)
        tab:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = tab

        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 10, -66)
        page:SetPoint("BOTTOMRIGHT", -10, 10)
        page:SetBackdrop(BACKDROP)
        page:SetBackdropColor(0, 0, 0, 0.4)
        page:Hide()
        pages[i] = page
    end

    pages[1].scroll = CreateScrollList(pages[1], "EchoTomeFinderTomeList")
    pages[2].scroll = CreateScrollList(pages[2], "EchoTomeFinderCharList")
    BuildOptions(pages[3])
end

function ns.RefreshWindow()
    if not (window and window:IsShown()) then return end
    for i, tab in ipairs(tabs) do tab:SetText(L(TAB_LABELS[i])) end
    if currentTab == 1 then
        RefreshTomes()
    elseif currentTab == 2 then
        RefreshChars()
    else
        RefreshOptions()
    end
end

-- Called by the core after every bag scan
function ns.OnDataChanged()
    ns.RefreshWindow()
end

function ns.ToggleWindow(tab)
    if not window then CreateWindow() end
    if window:IsShown() and (not tab or tab == currentTab) then
        window:Hide()
        return
    end
    window:Show()
    SelectTab(tab or currentTab)
end

-- ── Minimap button ───────────────────────────────────────────────────────────

local minimapButton

local function PlaceMinimapButton()
    local angle = math.rad(Core.GetDB().minimap.angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    Core.GetDB().minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    PlaceMinimapButton()
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "EchoTomeFinderMinimapButton", Minimap)
    b:SetWidth(31)
    b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]])

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture([[Interface\Icons\INV_Misc_Book_11]])
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        ns.ToggleWindow(button == "RightButton" and 3 or nil)
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", DragUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffb048f8EchoTomeFinder|r")
        GameTooltip:AddLine(L("Left click: open the window"), 1, 1, 1)
        GameTooltip:AddLine(L("Right click: options"), 1, 1, 1)
        GameTooltip:AddLine(L("Drag: move this button"), 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton = b
end

function ns.UpdateMinimapButton()
    if not minimapButton then CreateMinimapButton() end
    if Core.GetDB().minimap.hide then
        minimapButton:Hide()
    else
        PlaceMinimapButton()
        minimapButton:Show()
    end
end

-- Called by the core once the saved variables are loaded
function ns.OnLoaded()
    Core = ns.Core
    ns.UpdateMinimapButton()
end
