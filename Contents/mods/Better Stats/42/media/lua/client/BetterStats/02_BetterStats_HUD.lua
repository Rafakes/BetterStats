require "ISUI/ISPanel"
require "ISUI/ISContextMenu"
require "BetterStats/00_BetterStats_Shared"
require "BetterStats/01_BetterStats_Data"

BetterStats = BetterStats or {}
BetterStats.HUD = BetterStats.HUD or {}

local HUD = BetterStats.HUD

BetterStatsHUD = ISPanel:derive("BetterStatsHUD")

local ROW_X = 8
local ROW_W = 126
local ROW_H = 48
local ROW_GAP = 6
local HUD_CONTENT_W = 156
local DETAIL_BTN_SIZE = 26
local DETAIL_BTN_TOP_GAP = 8
local STATUS_SECTION_GAP = 8
local STATUS_ROW_H = 36
local STATUS_ROW_GAP = 5
local STATUS_ICON_BOX_X = ROW_X + 4
local STATUS_ICON_BOX_W = 28
local STATUS_ICON_BOX_H = 28
local STATUS_ICON_SIZE = 24
local STATUS_BAR_H = 18
local STATUS_BAR_X = ROW_X + 36
local STATUS_BAR_W = HUD_CONTENT_W - 42
local ROW_ICON_BOX_X = ROW_X + 5
local ROW_ICON_BOX_W = 40
local ROW_ICON_BOX_H = 40
local ROW_ICON_DRAW_SIZE = 32
local ROW_TEXT_X = ROW_ICON_BOX_X + ROW_ICON_BOX_W + 10

local ALIVE_ICON = getTexture("media/ui/BetterStats/icon_alive.png")
local KILLS_ICON = getTexture("media/ui/BetterStats/icon_kills.png")
local TODAY_ICON = getTexture("media/ui/BetterStats/icon_today.png")
local AVERAGE_ICON = getTexture("media/ui/BetterStats/icon_average.png")
local DISTANCE_ICON = getTexture("media/ui/BetterStats/icon_distance.png")
local WEIGHT_ICON = getTexture("media/ui/BetterStats/icon_weight.png")
local HEALTH_ICON = getTexture("media/ui/BetterStats/icon_health.png")
local HUNGER_ICON = getTexture("media/ui/BetterStats/icon_hunger.png")
local THIRST_ICON = getTexture("media/ui/BetterStats/icon_thirst.png")
local STAMINA_ICON = getTexture("media/ui/BetterStats/icon_stamina.png")
local DETAIL_ICON = getTexture("media/ui/BetterStats/icon_detail.png")
local WEIGHT_UP_ICON = getTexture("media/ui/Moodle_chevron_up.png")
local WEIGHT_DOWN_ICON = getTexture("media/ui/Moodle_chevron_down.png")

local HUD_TINTS = {
    white = { r = 1.0, g = 1.0, b = 1.0 },
    amber = { r = 1.0, g = 0.58, b = 0.08 },
    green = { r = 0.20, g = 1.0, b = 0.20 },
    blue = { r = 0.0, g = 0.62, b = 1.0 },
    red = { r = 1.0, g = 0.10, b = 0.18 },
    violet = { r = 0.76, g = 0.18, b = 1.0 },
}

local HUD_TINT_ORDER = {
    { key = "white", text = "IGUI_BetterStats_HUDColorWhite" },
    { key = "amber", text = "IGUI_BetterStats_HUDColorAmber" },
    { key = "green", text = "IGUI_BetterStats_HUDColorGreen" },
    { key = "blue", text = "IGUI_BetterStats_HUDColorBlue" },
    { key = "red", text = "IGUI_BetterStats_HUDColorRed" },
    { key = "violet", text = "IGUI_BetterStats_HUDColorViolet" },
}

local function getTintColor(key)
    return HUD_TINTS[tostring(key or "white")] or HUD_TINTS.white
end

local function scaleMetric(scale, value)
    return math.max(1, math.floor((tonumber(value) or 0) * scale + 0.5))
end

local function fitText(font, text, maxWidth)
    local value = tostring(text or "")
    if getTextManager():MeasureStringX(font, value) <= maxWidth then
        return value
    end

    local suffix = "..."
    while #value > 0 do
        value = value:sub(1, #value - 1)
        local candidate = value .. suffix
        if getTextManager():MeasureStringX(font, candidate) <= maxWidth then
            return candidate
        end
    end

    return suffix
end

local function mixColor(a, b, t)
    local ratio = math.max(0, math.min(1, tonumber(t) or 0))
    return {
        r = a.r + ((b.r - a.r) * ratio),
        g = a.g + ((b.g - a.g) * ratio),
        b = a.b + ((b.b - a.b) * ratio),
    }
end

local function getProgressiveBarColor(baseColor, dangerRatio)
    local warningColor = { r = 1.0, g = 0.78, b = 0.10 }
    local dangerColor = { r = 1.0, g = 0.10, b = 0.16 }
    local danger = math.max(0, math.min(1, tonumber(dangerRatio) or 0))

    if danger <= 0.5 then
        return mixColor(baseColor, warningColor, danger * 2)
    end

    return mixColor(warningColor, dangerColor, (danger - 0.5) * 2)
end

local function getStatusStyle(key)
    if key == "health" then
        return {
            texture = HEALTH_ICON,
            safeColor = { r = 0.25, g = 1.0, b = 0.28 },
            danger = function(fill) return 1 - fill end,
            badWhenIncreasing = false,
            showArrows = false,
        }
    end

    if key == "hunger" then
        return {
            texture = HUNGER_ICON,
            safeColor = { r = 1.0, g = 0.92, b = 0.12 },
            danger = function(fill) return fill end,
            badWhenIncreasing = true,
        }
    end

    if key == "thirst" then
        return {
            texture = THIRST_ICON,
            safeColor = { r = 0.0, g = 0.70, b = 1.0 },
            danger = function(fill) return fill end,
            badWhenIncreasing = true,
        }
    end

    return {
        texture = STAMINA_ICON,
        safeColor = { r = 0.25, g = 1.0, b = 0.28 },
        danger = function(fill) return 1 - fill end,
        badWhenIncreasing = false,
    }
end

local function getRowTexture(key)
    if key == "alive" then return ALIVE_ICON end
    if key == "kills" then return KILLS_ICON end
    if key == "today" then return TODAY_ICON end
    if key == "average" then return AVERAGE_ICON end
    if key == "distance" then return DISTANCE_ICON end
    if key == "weight" then return WEIGHT_ICON end
    return nil
end

local function getStatusLabel(key)
    if key == "health" then
        return getText("IGUI_BetterStats_Health")
    end
    if key == "hunger" then
        return getText("IGUI_BetterStats_Hunger")
    end
    if key == "thirst" then
        return getText("IGUI_BetterStats_Thirst")
    end
    if key == "stamina" then
        return getText("IGUI_BetterStats_Stamina")
    end
    return ""
end

function BetterStatsHUD:getMetrics()
    local scale = 1
    if BetterStats.Data.getHUDScale then
        scale = (BetterStats.Data.getHUDScale() or 100) / 100
    end

    local m = {
        scale = scale,
        rowX = scaleMetric(scale, ROW_X),
        rowW = scaleMetric(scale, ROW_W),
        rowH = scaleMetric(scale, ROW_H),
        rowGap = scaleMetric(scale, ROW_GAP),
        hudContentW = scaleMetric(scale, HUD_CONTENT_W),
        detailBtnSize = scaleMetric(scale, DETAIL_BTN_SIZE),
        detailBtnTopGap = scaleMetric(scale, DETAIL_BTN_TOP_GAP),
        statusSectionGap = scaleMetric(scale, STATUS_SECTION_GAP),
        statusRowH = scaleMetric(scale, STATUS_ROW_H),
        statusRowGap = scaleMetric(scale, STATUS_ROW_GAP),
        statusIconBoxX = scaleMetric(scale, STATUS_ICON_BOX_X),
        statusIconBoxW = scaleMetric(scale, STATUS_ICON_BOX_W),
        statusIconBoxH = scaleMetric(scale, STATUS_ICON_BOX_H),
        statusIconSize = scaleMetric(scale, STATUS_ICON_SIZE),
        statusBarH = scaleMetric(scale, STATUS_BAR_H),
        statusBarX = scaleMetric(scale, STATUS_BAR_X),
        statusBarW = scaleMetric(scale, STATUS_BAR_W),
        rowIconBoxX = scaleMetric(scale, ROW_ICON_BOX_X),
        rowIconBoxW = scaleMetric(scale, ROW_ICON_BOX_W),
        rowIconBoxH = scaleMetric(scale, ROW_ICON_BOX_H),
        rowIconDrawSize = scaleMetric(scale, ROW_ICON_DRAW_SIZE),
        rowTextX = scaleMetric(scale, ROW_TEXT_X),
    }

    m.statusLabelMaxW = math.max(1, m.statusBarW - scaleMetric(scale, 10))
    m.rowValueMaxW = math.max(1, m.rowW - (m.rowTextX - m.rowX) - scaleMetric(scale, 8))
    return m
end

function BetterStatsHUD:getVisualPrefs()
    local tintKey = BetterStats.Data.getHUDTint and BetterStats.Data.getHUDTint() or "white"
    local showBoxes = BetterStats.Data.isHUDBoxesVisible and BetterStats.Data.isHUDBoxesVisible() or false
    return {
        transparent = not showBoxes,
        locked = BetterStats.Data.isHUDLocked and BetterStats.Data.isHUDLocked() or false,
        tintKey = tintKey,
        tint = getTintColor(tintKey),
    }
end

function BetterStatsHUD:getLayout(rows, statusBars, metrics)
    local m = metrics or self:getMetrics()
    local compactRows = rows or BetterStats.Data.getCompactRows()
    local compactStatusBars = statusBars or BetterStats.Data.getCompactStatusBars()

    local rowsHeight = 0
    if #compactRows > 0 then
        rowsHeight = (#compactRows * m.rowH) + ((#compactRows - 1) * m.rowGap)
    end

    local statusY = rowsHeight
    local statusHeight = 0
    if #compactStatusBars > 0 then
        if rowsHeight > 0 then
            statusY = rowsHeight + m.statusSectionGap
        end
        statusHeight = (#compactStatusBars * m.statusRowH) + ((#compactStatusBars - 1) * m.statusRowGap)
    end

    local contentBottom = math.max(rowsHeight, statusY + statusHeight)
    local detailRect = nil
    if BetterStats.Data.canOpenDetailedPanel() then
        local buttonY = contentBottom
        if buttonY > 0 then
            buttonY = buttonY + m.detailBtnTopGap
        end
        detailRect = {
            x = m.rowX + m.hudContentW - m.detailBtnSize,
            y = buttonY,
            w = m.detailBtnSize,
            h = m.detailBtnSize,
        }
        contentBottom = buttonY + m.detailBtnSize
    end

    return {
        width = m.rowX + m.hudContentW + m.rowX,
        height = math.max(contentBottom, 1),
        statusY = statusY,
        detailRect = detailRect,
    }
end

function BetterStatsHUD:getDetailButtonRect()
    if not BetterStats.Data.canOpenDetailedPanel() then
        return nil
    end

    return self:getLayout().detailRect
end

function BetterStatsHUD:isInsideRect(x, y, rect)
    if not rect then return false end
    return x >= rect.x and x <= (rect.x + rect.w) and y >= rect.y and y <= (rect.y + rect.h)
end

function BetterStatsHUD:clampToScreen()
    local maxX = math.max(0, getCore():getScreenWidth() - self.width)
    local maxY = math.max(0, getCore():getScreenHeight() - self.height)

    if self:getX() < 0 then self:setX(0) end
    if self:getY() < 0 then self:setY(0) end
    if self:getX() > maxX then self:setX(maxX) end
    if self:getY() > maxY then self:setY(maxY) end
end

function BetterStatsHUD:initialise()
    ISPanel.initialise(self)
end

function BetterStatsHUD:prerender()
    if not self.layoutReady then
        return
    end
    self:clampToScreen()
end

function BetterStatsHUD:updateStatusAnimations(statusBars)
    self.statusAnimations = self.statusAnimations or {}
    self.animationTick = (self.animationTick or 0) + 1

    for _, bar in ipairs(statusBars) do
        local anim = self.statusAnimations[bar.key] or {
            lastFill = bar.fill,
            direction = 0,
            timer = 0,
        }

        local delta = bar.fill - (anim.lastFill or bar.fill)
        if math.abs(delta) > 0.004 then
            anim.direction = delta > 0 and 1 or -1
            anim.timer = 18
        elseif anim.timer > 0 then
            anim.timer = anim.timer - 1
            if anim.timer <= 0 then
                anim.direction = 0
                anim.timer = 0
            end
        end

        anim.lastFill = bar.fill
        self.statusAnimations[bar.key] = anim
    end
end

function BetterStatsHUD:drawStatusBar(y, bar, m, visual)
    local style = getStatusStyle(bar.key)
    local anim = self.statusAnimations and self.statusAnimations[bar.key] or nil
    local danger = style.danger(bar.fill)
    local fillColor = getProgressiveBarColor(style.safeColor, danger)
    local iconBoxY = y + math.floor((m.statusRowH - m.statusIconBoxH) / 2)
    local iconX = m.statusIconBoxX + math.floor((m.statusIconBoxW - m.statusIconSize) / 2)
    local iconY = y + math.floor((m.statusRowH - m.statusIconSize) / 2)
    local trackY = y + math.floor((m.statusRowH - m.statusBarH) / 2)
    local fillW = math.floor(m.statusBarW * bar.fill)

    if not visual.transparent then
        self:drawRect(m.rowX, y, m.hudContentW, m.statusRowH, 0.28, 0.09, 0.11, 0.11)
        self:drawRectBorder(m.rowX, y, m.hudContentW, m.statusRowH, 0.10, 1, 1, 1)
        self:drawRect(m.statusIconBoxX, iconBoxY, m.statusIconBoxW, m.statusIconBoxH, 0.22, 0.15, 0.17, 0.17)
    end

    if style.texture then
        self:drawTextureScaled(style.texture, iconX, iconY, m.statusIconSize, m.statusIconSize, 0.94, visual.tint.r, visual.tint.g, visual.tint.b)
    else
        self:drawText("?", iconX + 1, iconY, 1, 1, 1, 1, UIFont.Small)
    end

    self:drawRect(m.statusBarX, trackY, m.statusBarW, m.statusBarH, visual.transparent and 0.14 or 0.20, 0.20, 0.22, 0.22)
    self:drawRectBorder(m.statusBarX, trackY, m.statusBarW, m.statusBarH, visual.transparent and 0.08 or 0.12, 1, 1, 1)
    if fillW > 0 then
        self:drawRect(m.statusBarX + 1, trackY + 1, math.max(1, fillW - 2), m.statusBarH - 2, 0.96, fillColor.r, fillColor.g, fillColor.b)
    end

    local label = getStatusLabel(bar.key)
    if label ~= "" then
        local labelFont = UIFont.Small
        local labelText = fitText(labelFont, label, m.statusLabelMaxW)
        local labelCenterX = m.statusBarX + (m.statusBarW / 2)
        local labelY = y + math.floor((m.statusRowH - getTextManager():getFontHeight(labelFont)) / 2) - 1
        self:drawTextCentre(labelText, labelCenterX + 1, labelY + 1, 0, 0, 0, 0.75, labelFont)
        self:drawTextCentre(labelText, labelCenterX, labelY, visual.tint.r, visual.tint.g, visual.tint.b, 1, labelFont)
    end

    if style.showArrows ~= false and anim and anim.timer and anim.timer > 0 and anim.direction ~= 0 then
        local isBadDirection = (style.badWhenIncreasing and anim.direction > 0) or ((not style.badWhenIncreasing) and anim.direction < 0)
        local arrowText = anim.direction > 0 and ">>" or "<<"
        local alpha = 0.58 + (0.36 * math.abs(math.sin((self.animationTick or 0) / 3)))
        local arrowColor = isBadDirection
            and getProgressiveBarColor({ r = 0.93, g = 0.66, b = 0.30 }, danger)
            or { r = 0.60, g = 0.86, b = 0.46 }
        self:drawTextRight(arrowText, m.rowX + m.hudContentW - scaleMetric(m.scale, 6), y + scaleMetric(m.scale, 5), arrowColor.r, arrowColor.g, arrowColor.b, alpha, UIFont.Small)
    end
end

function BetterStatsHUD:drawWeightTrend(row, valueX, valueY, valueText, valueFont, m, visual)
    if not row or not row.trend then
        return
    end

    local textWidth = getTextManager():MeasureStringX(valueFont or UIFont.Small, valueText or "")
    local iconSize = scaleMetric(m.scale, 7)
    local iconX = valueX + textWidth + scaleMetric(m.scale, 6)
    local iconY = valueY + scaleMetric(m.scale, 3)

    if row.trend == "up_lot" then
        if WEIGHT_UP_ICON then
            self:drawTextureScaled(WEIGHT_UP_ICON, iconX, iconY, iconSize, iconSize, 0.9, visual.tint.r, visual.tint.g, visual.tint.b)
            self:drawTextureScaled(WEIGHT_UP_ICON, iconX + scaleMetric(m.scale, 6), iconY, iconSize, iconSize, 0.9, visual.tint.r, visual.tint.g, visual.tint.b)
        else
            self:drawText(">>", iconX, valueY + 1, visual.tint.r, visual.tint.g, visual.tint.b, 0.9, UIFont.Small)
        end
        return
    end

    local texture = row.trend == "down" and WEIGHT_DOWN_ICON or WEIGHT_UP_ICON
    if texture then
        self:drawTextureScaled(texture, iconX, iconY, iconSize, iconSize, 0.9, visual.tint.r, visual.tint.g, visual.tint.b)
    else
        local text = row.trend == "down" and "<" or ">"
        self:drawText(text, iconX, valueY + 1, visual.tint.r, visual.tint.g, visual.tint.b, 0.9, UIFont.Small)
    end
end

function BetterStatsHUD:render()
    local rows = BetterStats.Data.getCompactRows()
    local statusBars = BetterStats.Data.getCompactStatusBars()
    local m = self:getMetrics()
    local visual = self:getVisualPrefs()
    local layout = self:getLayout(rows, statusBars, m)
    local detailRect = layout.detailRect

    self:setWidth(layout.width)
    self:setHeight(layout.height)
    self.layoutReady = true
    self.moveWithMouse = BetterStats.getSandboxBool("AllowHUDDrag", true) and not visual.locked
    self:updateStatusAnimations(statusBars)

    local buttonHovered = false
    if detailRect and self:isMouseOver() then
        local mouseX = self:getMouseX()
        local mouseY = self:getMouseY()
        buttonHovered = self:isInsideRect(mouseX, mouseY, detailRect)
    end

    if detailRect then
        local alpha = buttonHovered and 0.46 or 0.32
        if not visual.transparent then
            self:drawRect(detailRect.x, detailRect.y, detailRect.w, detailRect.h, alpha, 0.11, 0.13, 0.13)
            self:drawRectBorder(detailRect.x, detailRect.y, detailRect.w, detailRect.h, 0.28, 1, 1, 1)
        end
        if DETAIL_ICON then
            self:drawTextureScaled(DETAIL_ICON, detailRect.x + scaleMetric(m.scale, 4), detailRect.y + scaleMetric(m.scale, 4), scaleMetric(m.scale, 18), scaleMetric(m.scale, 18), 0.95, visual.tint.r, visual.tint.g, visual.tint.b)
        else
            local barX = detailRect.x + scaleMetric(m.scale, 5)
            local baseY = detailRect.y + detailRect.h - scaleMetric(m.scale, 5)
            self:drawRect(barX, baseY - scaleMetric(m.scale, 6), scaleMetric(m.scale, 4), scaleMetric(m.scale, 6), 0.95, visual.tint.r, visual.tint.g, visual.tint.b)
            self:drawRect(barX + scaleMetric(m.scale, 5), baseY - scaleMetric(m.scale, 11), scaleMetric(m.scale, 4), scaleMetric(m.scale, 11), 0.95, visual.tint.r, visual.tint.g, visual.tint.b)
            self:drawRect(barX + scaleMetric(m.scale, 10), baseY - scaleMetric(m.scale, 15), scaleMetric(m.scale, 4), scaleMetric(m.scale, 15), 0.95, visual.tint.r, visual.tint.g, visual.tint.b)
            self:drawRect(barX + scaleMetric(m.scale, 15), baseY - scaleMetric(m.scale, 9), scaleMetric(m.scale, 4), scaleMetric(m.scale, 9), 0.95, visual.tint.r, visual.tint.g, visual.tint.b)
        end
    end

    local y = 0
    for _, row in ipairs(rows) do
        local rowIconBoxY = y + math.floor((m.rowH - m.rowIconBoxH) / 2)
        local rowIconDrawX = m.rowIconBoxX + math.floor((m.rowIconBoxW - m.rowIconDrawSize) / 2)
        local rowIconDrawY = y + math.floor((m.rowH - m.rowIconDrawSize) / 2)
        if not visual.transparent then
            self:drawRect(m.rowX, y, m.rowW, m.rowH, 0.28, 0.09, 0.11, 0.11)
            self:drawRectBorder(m.rowX, y, m.rowW, m.rowH, 0.10, 1, 1, 1)
            self:drawRect(m.rowIconBoxX, rowIconBoxY, m.rowIconBoxW, m.rowIconBoxH, 0.22, 0.15, 0.17, 0.17)
        end
        local rowTexture = getRowTexture(row.key)
        if rowTexture then
            self:drawTextureScaled(rowTexture, rowIconDrawX, rowIconDrawY, m.rowIconDrawSize, m.rowIconDrawSize, 0.95, visual.tint.r, visual.tint.g, visual.tint.b)
        else
            self:drawText(row.icon, m.rowIconBoxX + scaleMetric(m.scale, 11), rowIconDrawY + scaleMetric(m.scale, 3), visual.tint.r, visual.tint.g, visual.tint.b, 1, UIFont.Medium)
        end

        local valueFont = m.scale >= 1.15 and UIFont.Medium or UIFont.Small
        local valueMaxWidth = row.trend and (m.rowValueMaxW - scaleMetric(m.scale, 18)) or m.rowValueMaxW
        local valueText = fitText(valueFont, row.value, valueMaxWidth)
        local valueX = m.rowTextX
        local valueY = y + math.floor((m.rowH - getTextManager():getFontHeight(valueFont)) / 2) - 1
        self:drawText(valueText, valueX, valueY, visual.tint.r, visual.tint.g, visual.tint.b, 1, valueFont)
        self:drawWeightTrend(row, valueX, valueY, valueText, valueFont, m, visual)
        y = y + m.rowH + m.rowGap
    end

    y = layout.statusY
    for _, bar in ipairs(statusBars) do
        self:drawStatusBar(y, bar, m, visual)
        y = y + m.statusRowH + m.statusRowGap
    end
end

function BetterStatsHUD:onMouseDown(x, y)
    local detailRect = self:getDetailButtonRect()
    if self:isInsideRect(x, y, detailRect) then
        self.pendingDetailClick = true
        self.moving = false
        return true
    end

    self.pendingDetailClick = false
    return ISPanel.onMouseDown(self, x, y)
end

function BetterStatsHUD:onMouseUp(x, y)
    local detailRect = self:getDetailButtonRect()

    if self.pendingDetailClick then
        self.pendingDetailClick = false
        self.moving = false
        if self:isInsideRect(x, y, detailRect) and BetterStats.Detail and BetterStats.Detail.toggleWindow then
            BetterStats.Detail.toggleWindow()
        end
        return true
    end

    ISPanel.onMouseUp(self, x, y)
    HUD.cancelRestore()
    BetterStats.Data.setHUDPosition(self:getX(), self:getY())
end

function BetterStatsHUD:onMouseUpOutside(x, y)
    self.pendingDetailClick = false
    ISPanel.onMouseUpOutside(self, x, y)
    HUD.cancelRestore()
    BetterStats.Data.setHUDPosition(self:getX(), self:getY())
end

function BetterStatsHUD:addCustomizationMenu(context)
    local customOption = context:addOption(getText("IGUI_BetterStats_CustomizeHUD"))
    local customMenu = ISContextMenu:getNew(context)
    context:addSubMenu(customOption, customMenu)

    local boxesOption = customMenu:addOption(getText("IGUI_BetterStats_ShowHUDBoxes"), nil, function()
        BetterStats.Data.toggleHUDBoxes()
    end)
    customMenu:setOptionChecked(boxesOption, BetterStats.Data.isHUDBoxesVisible())

    local lockOption = customMenu:addOption(getText("IGUI_BetterStats_LockHUD"), nil, function()
        BetterStats.Data.toggleHUDLocked()
        HUD.refreshVisibility()
    end)
    customMenu:setOptionChecked(lockOption, BetterStats.Data.isHUDLocked())

    local statusBarsOption = customMenu:addOption(getText("IGUI_BetterStats_ShowStatusBars"), nil, function()
        BetterStats.Data.toggleCompactStatusBars()
        HUD.refreshVisibility()
    end)
    customMenu:setOptionChecked(statusBarsOption, BetterStats.Data.isCompactStatusBarsVisible())

    local scaleLabel = getText("IGUI_BetterStats_HUDScale") .. ": " .. tostring(BetterStats.Data.getHUDScale()) .. "%"
    local scaleOption = customMenu:addOption(scaleLabel)
    local scaleMenu = ISContextMenu:getNew(customMenu)
    customMenu:addSubMenu(scaleOption, scaleMenu)
    scaleMenu:addOption(getText("IGUI_BetterStats_HUDScaleUp"), nil, function()
        BetterStats.Data.adjustHUDScale(10)
        HUD.refreshVisibility()
    end)
    scaleMenu:addOption(getText("IGUI_BetterStats_HUDScaleDown"), nil, function()
        BetterStats.Data.adjustHUDScale(-10)
        HUD.refreshVisibility()
    end)
    scaleMenu:addOption(getText("IGUI_BetterStats_HUDScaleReset"), nil, function()
        BetterStats.Data.setHUDScale(100)
        HUD.refreshVisibility()
    end)

    local colorOption = customMenu:addOption(getText("IGUI_BetterStats_HUDColor"))
    local colorMenu = ISContextMenu:getNew(customMenu)
    customMenu:addSubMenu(colorOption, colorMenu)
    local currentTint = BetterStats.Data.getHUDTint()
    for _, tint in ipairs(HUD_TINT_ORDER) do
        local tintKey = tint.key
        local option = colorMenu:addOption(getText(tint.text), nil, function()
            BetterStats.Data.setHUDTint(tintKey)
        end)
        colorMenu:setOptionChecked(option, currentTint == tintKey)
    end

    customMenu:addOption(getText("IGUI_BetterStats_ResetHUDCustomization"), nil, function()
        BetterStats.Data.resetHUDCustomization()
        HUD.refreshVisibility()
    end)
end

function BetterStatsHUD:onRightMouseUp(x, y)
    if not self:isMouseOver() then return end

    local context = ISContextMenu.get(0, getMouseX(), getMouseY())
    self:addCustomizationMenu(context)

    context:addOption(getText("IGUI_BetterStats_HideHUD"), nil, function()
        BetterStats.Data.toggleHUD()
        HUD.refreshVisibility()
    end)

    if BetterStats.Data.canOpenDetailedPanel() then
        context:addOption(getText("IGUI_BetterStats_ToggleDetailedPanel"), nil, function()
            if BetterStats.Detail and BetterStats.Detail.toggleWindow then
                BetterStats.Detail.toggleWindow()
            end
        end)
    end

    context:addOption(getText("IGUI_BetterStats_ResetPosition"), nil, function()
        BetterStats.Data.resetPositions()
        HUD.applyPrefs()
        if BetterStats.Detail and BetterStats.Detail.applyPrefs then
            BetterStats.Detail.applyPrefs()
        end
        BetterStats.Data.saveNow()
    end)
end

function BetterStatsHUD:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = BetterStats.getSandboxBool("AllowHUDDrag", true)
    return o
end

function HUD.ensure()
    if isDedicatedServer and isDedicatedServer() then
        return nil
    end
    if not BetterStats.Data.ensureReady() then
        return nil
    end
    if HUD.instance then
        return HUD.instance
    end

    local prefs = BetterStats.Data.getPrefs()
    local ui = BetterStatsHUD:new(prefs.hudX or 20, prefs.hudY or 120, 188, 320)
    ui:initialise()
    ui:addToUIManager()
    ui:setVisible(BetterStats.Data.isHUDVisible())
    HUD.instance = ui
    return ui
end

function HUD.applyPrefs()
    if not HUD.instance then return end
    local prefs = BetterStats.Data.getPrefs()
    if not prefs then return end

    local layout = HUD.instance:getLayout()
    HUD.instance:setWidth(layout.width)
    HUD.instance:setHeight(layout.height)
    HUD.instance.layoutReady = true
    HUD.instance:setX(prefs.hudX or 20)
    HUD.instance:setY(prefs.hudY or 120)
    HUD.instance:clampToScreen()
end

function HUD.refreshVisibility()
    local ui = HUD.ensure()
    if not ui then return end
    ui:setVisible(BetterStats.Data.isHUDVisible())
    ui.moveWithMouse = BetterStats.getSandboxBool("AllowHUDDrag", true) and not BetterStats.Data.isHUDLocked()
end

function HUD.toggleFromKey()
    BetterStats.Data.toggleHUD()
    HUD.refreshVisibility()
end

local RESTORE_WINDOW_TICKS = 600

local restoreTicksLeft = 0
local restoreHooked = false
local restoreTick = nil

function HUD.cancelRestore()
    restoreTicksLeft = 0
    if restoreHooked then
        restoreHooked = false
        Events.OnTick.Remove(restoreTick)
    end
end

restoreTick = function()
    restoreTicksLeft = restoreTicksLeft - 1
    if restoreTicksLeft <= 0 then
        HUD.cancelRestore()
        return
    end

    if HUD.instance and HUD.instance.moving then
        HUD.cancelRestore()
        return
    end

    local detail = BetterStats.Detail and BetterStats.Detail.instance or nil
    if detail and detail.moving then
        HUD.cancelRestore()
        return
    end

    if not BetterStats.Data.reloadPrefsFromModData() then
        return
    end

    HUD.applyPrefs()
    if BetterStats.Detail and BetterStats.Detail.applyPrefs then
        BetterStats.Detail.applyPrefs()
    end
    HUD.cancelRestore()
end

function HUD.scheduleRestore()
    restoreTicksLeft = RESTORE_WINDOW_TICKS
    if not restoreHooked then
        restoreHooked = true
        Events.OnTick.Add(restoreTick)
    end
end

local function bootstrapHUD()
    local ui = HUD.ensure()
    if not ui then return end
    HUD.applyPrefs()
    HUD.refreshVisibility()
    if not BetterStats.Data.arePrefsRestored() then
        HUD.scheduleRestore()
    end
end

local function onResolutionChange()
    if HUD.instance then
        HUD.instance:clampToScreen()
        BetterStats.Data.setHUDPosition(HUD.instance:getX(), HUD.instance:getY())
    end
end

Events.OnGameStart.Add(bootstrapHUD)
Events.OnCreatePlayer.Add(function(playerIndex, playerObj)
    if playerObj and playerObj.isLocalPlayer and not playerObj:isLocalPlayer() then
        return
    end
    bootstrapHUD()
end)
Events.OnResolutionChange.Add(onResolutionChange)
