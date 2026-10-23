require "ISUI/ISCollapsableWindow"
require "BetterStats/00_BetterStats_Shared"
require "BetterStats/01_BetterStats_Data"

BetterStats = BetterStats or {}
BetterStats.Detail = BetterStats.Detail or {}

local Detail = BetterStats.Detail

BetterStatsDetailWindow = ISCollapsableWindow:derive("BetterStatsDetailWindow")

local DETAIL_WINDOW_W = 472
local DETAIL_DEFAULT_H = 700

local function getToneColor(tone)
    if tone == "good" then
        return { r = 0.62, g = 0.86, b = 0.46 }
    end
    if tone == "warning" then
        return { r = 0.93, g = 0.69, b = 0.35 }
    end
    if tone == "danger" then
        return { r = 0.89, g = 0.38, b = 0.38 }
    end
    return { r = 1.0, g = 1.0, b = 1.0 }
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

local function getFontHeight(font)
    return getTextManager():getFontHeight(font)
end

local function getMetricStackHeight(valueFont, trailingGap)
    local drawFont = valueFont or UIFont.Medium
    return getFontHeight(UIFont.Small) + 2 + getFontHeight(drawFont) + (trailingGap or 8)
end

function BetterStatsDetailWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

function BetterStatsDetailWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.pinButton:setVisible(false)
    self.collapseButton:setVisible(false)
    self:setResizable(false)
end

function BetterStatsDetailWindow:close()
    self:setVisible(false)
    self.moving = false
    BetterStats.Data.setDetailVisible(false)
    BetterStats.Data.saveNow()
end

function BetterStatsDetailWindow:clampToScreen()
    local maxX = math.max(0, getCore():getScreenWidth() - self.width)
    local maxY = math.max(0, getCore():getScreenHeight() - self.height)
    if self:getX() < 0 then self:setX(0) end
    if self:getY() < 0 then self:setY(0) end
    if self:getX() > maxX then self:setX(maxX) end
    if self:getY() > maxY then self:setY(maxY) end
end

local function cancelPositionRestore()
    if BetterStats.HUD and BetterStats.HUD.cancelRestore then
        BetterStats.HUD.cancelRestore()
    end
end

function BetterStatsDetailWindow:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    self.moving = false
    cancelPositionRestore()
    BetterStats.Data.setDetailPosition(self:getX(), self:getY())
end

function BetterStatsDetailWindow:onMouseUpOutside(x, y)
    ISCollapsableWindow.onMouseUpOutside(self, x, y)
    self.moving = false
    cancelPositionRestore()
    BetterStats.Data.setDetailPosition(self:getX(), self:getY())
end

function BetterStatsDetailWindow:onMouseDown(x, y)
    if not self:getIsVisible() then
        return
    end

    if self.ignoreMouseUntilRelease then
        return false
    end

    if y > self:titleBarHeight() then
        return false
    end

    self.downX = x
    self.downY = y
    self.moving = true
    self:bringToTop()
    return true
end

function BetterStatsDetailWindow:prerender()
    if self.ignoreMouseUntilRelease and not isMouseButtonDown(0) and not isMouseButtonDown(1) and not isMouseButtonDown(2) then
        self.ignoreMouseUntilRelease = false
    end
    self:clampToScreen()
    ISCollapsableWindow.prerender(self)
end

function BetterStatsDetailWindow:drawPanelBox(x, y, width, height, title)
    self:drawRect(x, y, width, height, 0.22, 0.08, 0.10, 0.10)
    self:drawRectBorder(x, y, width, height, 0.10, 1, 1, 1)
    self:drawText(title, x + 10, y + 8, 0.96, 0.96, 0.96, 1, UIFont.Small)
end

function BetterStatsDetailWindow:drawMetricStack(x, y, width, label, value, valueColor, valueFont)
    local drawFont = valueFont or UIFont.Medium
    local labelFont = UIFont.Small
    local labelText = fitText(labelFont, label, width)
    local valueText = fitText(drawFont, tostring(value or ""), width)
    local valueY = y + getFontHeight(labelFont) + 2
    self:drawText(labelText, x, y, 0.68, 0.72, 0.70, 1, labelFont)
    self:drawText(valueText, x, valueY, valueColor.r, valueColor.g, valueColor.b, 1, drawFont)
end

function BetterStatsDetailWindow:render()
    local snapshot = BetterStats.Data.getDetailedSnapshot()
    if not snapshot then
        ISCollapsableWindow.render(self)
        return
    end

    local offsetY = self:titleBarHeight() + 12
    local left = 14
    local totalWidth = self.width - 28
    local sectionGap = 14
    local summaryPadding = 14
    local summaryRightWidth = 108
    local summaryGap = 22
    local metricFont = UIFont.Medium
    local summaryStackHeight = getMetricStackHeight(metricFont, 18)
    local summaryHeight = math.max(154, 28 + (summaryStackHeight * 2) + 24)
    local summaryLeftWidth = totalWidth - (summaryPadding * 2) - summaryRightWidth - summaryGap
    local summaryLeftX = left + summaryPadding
    local summaryRightX = summaryLeftX + summaryLeftWidth + summaryGap
    local summaryContentY = offsetY + 28
    local chartY = offsetY + summaryHeight + sectionGap
    local chartHeight = 176
    local lowerY = chartY + chartHeight + sectionGap
    local lowerGap = 12
    local lowerWidth = math.floor((totalWidth - lowerGap) / 2)
    local metricStep = getMetricStackHeight(metricFont, 22)
    local lowerHeight = math.max(248, 36 + (metricStep * 3) + 22)
    local metricWidth = lowerWidth - 24
    local metricTop = lowerY + 34
    local requiredHeight = lowerY + lowerHeight + 18

    if self:getHeight() ~= requiredHeight then
        self:setHeight(requiredHeight)
        self:clampToScreen()
    end

    ISCollapsableWindow.render(self)
    self:drawRect(1, self:titleBarHeight(), self.width - 2, self.height - self:titleBarHeight() - 1, 0.72, 0.04, 0.06, 0.06)

    self:drawPanelBox(left, offsetY, totalWidth, summaryHeight, getText("IGUI_BetterStats_RunSummary"))
    self:drawText(getText("IGUI_BetterStats_PrimaryWeapon"), summaryLeftX, summaryContentY, 0.68, 0.72, 0.70, 1, UIFont.Small)
    self:drawText(fitText(metricFont, snapshot.primaryWeapon, summaryLeftWidth), summaryLeftX, summaryContentY + getFontHeight(UIFont.Small) + 4, 1, 1, 1, 1, metricFont)
    self:drawMetricStack(summaryRightX, summaryContentY, summaryRightWidth, getText("IGUI_BetterStats_TotalKills"), tostring(snapshot.totalKills), { r = 1, g = 1, b = 1 }, metricFont)
    self:drawMetricStack(summaryRightX, summaryContentY + summaryStackHeight, summaryRightWidth, getText("IGUI_BetterStats_AveragePerDay"), snapshot.averagePerDay, { r = 0.93, g = 0.69, b = 0.35 }, metricFont)

    self:drawPanelBox(left, chartY, totalWidth, chartHeight, getText("IGUI_BetterStats_KillTrend"))

    local chartInnerLeft = left + 14
    local chartTop = chartY + 48
    local chartBottom = chartY + chartHeight - 38
    local chartBarAreaHeight = chartBottom - chartTop
    local slotWidth = math.floor((totalWidth - 28) / #snapshot.trend)
    local barWidth = math.max(24, math.min(36, slotWidth - 10))

    for index, value in ipairs(snapshot.trend) do
        local ratio = 0
        if snapshot.trendMax > 0 then
            ratio = value / snapshot.trendMax
        end

        local barHeight = math.floor(ratio * chartBarAreaHeight)
        local slotX = chartInnerLeft + ((index - 1) * slotWidth)
        local x = slotX + math.floor((slotWidth - barWidth) / 2)
        local y = chartBottom - barHeight

        self:drawRect(x, chartTop, barWidth, chartBarAreaHeight, 0.08, 1, 1, 1)
        self:drawRect(x, y, barWidth, barHeight, 0.92, 0.88, 0.59, 0.32)
        self:drawTextCentre(tostring(value), x + (barWidth / 2), math.max(chartTop - 2, y - 16), 1, 1, 1, 1, UIFont.Small)

        if index == #snapshot.trend then
            self:drawTextCentre(getText("IGUI_BetterStats_TodayShort"), x + (barWidth / 2), chartBottom + 12, 0.68, 0.72, 0.70, 1, UIFont.Small)
        else
            self:drawTextCentre("-" .. tostring(#snapshot.trend - index), x + (barWidth / 2), chartBottom + 12, 0.68, 0.72, 0.70, 1, UIFont.Small)
        end
    end

    self:drawPanelBox(left, lowerY, lowerWidth, lowerHeight, getText("IGUI_BetterStats_CombatProfile"))
    self:drawMetricStack(left + 12, metricTop, metricWidth, getText("IGUI_BetterStats_HitsLanded"), tostring(snapshot.hitsLanded), { r = 1, g = 1, b = 1 }, metricFont)
    self:drawMetricStack(left + 12, metricTop + metricStep, metricWidth, getText("IGUI_BetterStats_Pushes"), tostring(snapshot.pushes), { r = 1, g = 1, b = 1 }, metricFont)
    self:drawMetricStack(left + 12, metricTop + (metricStep * 2), metricWidth, getText("IGUI_BetterStats_KillsPerHour"), snapshot.killsPerHour, { r = 0.93, g = 0.69, b = 0.35 }, metricFont)

    local rightCardX = left + lowerWidth + lowerGap
    self:drawPanelBox(rightCardX, lowerY, lowerWidth, lowerHeight, getText("IGUI_BetterStats_BodyTravel"))
    self:drawMetricStack(rightCardX + 12, metricTop, metricWidth, getText("IGUI_BetterStats_DistanceToday"), snapshot.distanceToday, { r = 1, g = 1, b = 1 }, metricFont)
    self:drawMetricStack(rightCardX + 12, metricTop + metricStep, metricWidth, getText("IGUI_BetterStats_Distance"), snapshot.totalDistance, { r = 1, g = 1, b = 1 }, metricFont)

    local balanceTone = snapshot.caloriesBalance <= 0 and getToneColor("danger") or getToneColor("good")
    self:drawMetricStack(rightCardX + 12, metricTop + (metricStep * 2), metricWidth, getText("IGUI_BetterStats_CalorieBalance"), tostring(snapshot.caloriesBalance), balanceTone, metricFont)
end

function BetterStatsDetailWindow:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = getText("IGUI_BetterStats_DetailedTitle")
    o.backgroundColor = { r = 0.04, g = 0.06, b = 0.06, a = 0.78 }
    o.borderColor = { r = 0.35, g = 0.35, b = 0.35, a = 0.8 }
    o.resizable = false
    o.pin = true
    o.ignoreMouseUntilRelease = false
    return o
end

function Detail.ensure()
    if not BetterStats.Data.canOpenDetailedPanel() then
        return nil
    end
    if not BetterStats.Data.ensureReady() then
        return nil
    end
    if Detail.instance then
        Detail.instance:setWidth(DETAIL_WINDOW_W)
        Detail.instance:setHeight(DETAIL_DEFAULT_H)
        Detail.instance:clampToScreen()
        return Detail.instance
    end

    local prefs = BetterStats.Data.getPrefs()
    local ui = BetterStatsDetailWindow:new(prefs.detailX or 980, prefs.detailY or 80, DETAIL_WINDOW_W, DETAIL_DEFAULT_H)
    ui:initialise()
    ui:addToUIManager()
    ui:setVisible(BetterStats.Data.isDetailVisible())
    Detail.instance = ui
    return ui
end

function Detail.applyPrefs()
    if not Detail.instance then return end
    local prefs = BetterStats.Data.getPrefs()
    if not prefs then return end
    Detail.instance:setX(prefs.detailX or 980)
    Detail.instance:setY(prefs.detailY or 80)
    Detail.instance:clampToScreen()
end

function Detail.refreshVisibility()
    if not BetterStats.Data.canOpenDetailedPanel() then
        if Detail.instance then
            Detail.instance:setVisible(false)
        end
        return
    end

    local ui = Detail.ensure()
    if not ui then return end
    ui:setVisible(BetterStats.Data.isDetailVisible())
end

function Detail.show()
    if not BetterStats.Data.canOpenDetailedPanel() then
        return false
    end

    local ui = Detail.ensure()
    if not ui then return false end

    BetterStats.Data.setDetailVisible(true)
    ui:setVisible(true)
    ui.moving = false
    ui.ignoreMouseUntilRelease = isMouseButtonDown(0) or isMouseButtonDown(1) or isMouseButtonDown(2)
    ui:bringToTop()
    BetterStats.Data.saveNow()
    return true
end

function Detail.hide()
    if Detail.instance then
        Detail.instance:setVisible(false)
    end
    BetterStats.Data.setDetailVisible(false)
    BetterStats.Data.saveNow()
end

function Detail.toggleWindow()
    if BetterStats.Data.toggleDetailVisible() then
        Detail.show()
    else
        Detail.hide()
    end
end

local function bootstrapDetail()
    if not BetterStats.Data.canOpenDetailedPanel() then
        Detail.hide()
        return
    end

    local ui = Detail.ensure()
    if not ui then return end
    Detail.applyPrefs()
    Detail.refreshVisibility()
end

local function onResolutionChange()
    if Detail.instance then
        Detail.instance:clampToScreen()
        BetterStats.Data.setDetailPosition(Detail.instance:getX(), Detail.instance:getY())
    end
end

Events.OnGameStart.Add(bootstrapDetail)
Events.OnCreatePlayer.Add(function(playerIndex, playerObj)
    if playerObj and playerObj.isLocalPlayer and not playerObj:isLocalPlayer() then
        return
    end
    bootstrapDetail()
end)
Events.OnResolutionChange.Add(onResolutionChange)
