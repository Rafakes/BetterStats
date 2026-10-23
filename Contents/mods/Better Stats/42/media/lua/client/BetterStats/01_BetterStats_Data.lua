require "BetterStats/00_BetterStats_Shared"

BetterStats = BetterStats or {}
BetterStats.Data = BetterStats.Data or {}

local Data = BetterStats.Data

local state = nil
local runtime = {
    saveFileName = nil,
    savePending = false,
    shoveActive = false,
    lastStatusBars = nil,
    prefsRestored = false,
}

local function getDefaults()
    return {
        version = BetterStats.STATE_VERSION,
        prefs = {
            hudVisible = true,
            hudX = 20,
            hudY = 120,
            detailVisible = false,
            detailX = 980,
            detailY = 80,
            hudShowBoxes = false,
            hudLocked = false,
            hudScale = 100,
            hudTint = "white",
            hudShowStatusBars = true,
        },
        run = {
            lastRecordedTotalKills = 0,
            lastKnownHoursSurvived = 0,
            distanceTotal = 0,
            hitsLanded = 0,
            totalPushes = 0,
            caloriesConsumed = 0,
            caloriesBurned = 0,
            lastCalories = nil,
            lastX = nil,
            lastY = nil,
            weaponUsage = {},
            dayKillsHistory = {},
            dayDistanceHistory = {},
        },
    }
end

local function getPlayer()
    return BetterStats.getLocalPlayer()
end

local function getCurrentKills(player)
    return math.max(0, math.floor((player and player:getZombieKills()) or 0))
end

local function getCurrentHours(player)
    return math.max(0, tonumber((player and player:getHoursSurvived()) or 0))
end

local function getCurrentCalories(player)
    if not player or not player.getNutrition or not player:getNutrition() then
        return nil
    end
    return tonumber(player:getNutrition():getCalories())
end

local function clamp01(value)
    local numeric = tonumber(value) or 0
    if numeric < 0 then return 0 end
    if numeric > 1 then return 1 end
    return numeric
end

local function getNeedStatusFill(rawValue, stageMax)
    local maxValue = math.max(0.01, tonumber(stageMax) or 0.15)
    local ratio = clamp01((tonumber(rawValue) or 0) / maxValue)
    return ratio * ratio
end

local function getNeedStatusFillFromMoodle(player, rawValue, moodleType, fallbackThreshold)
    local moodles = player and player.getMoodles and player:getMoodles() or nil
    if moodles and moodleType then
        local stage = tonumber(moodles:getMoodleLevel(moodleType)) or 0
        if stage >= 1 then
            return 1
        end
    end

    return getNeedStatusFill(rawValue, fallbackThreshold)
end

local function isPlayerDead(player)
    if not player then
        return false
    end

    if player.isDead and player:isDead() then
        return true
    end

    local bodyDamage = player.getBodyDamage and player:getBodyDamage() or nil
    if bodyDamage and bodyDamage.getHealth and bodyDamage:getHealth() <= 0 then
        return true
    end

    return false
end

local function getRoundedWeight(player)
    if not player or not player.getNutrition or not player:getNutrition() then
        return nil
    end
    return math.floor((tonumber(player:getNutrition():getWeight()) or 0) + 0.5)
end

local function getWeightTrend(player)
    if not player or not player.getNutrition or not player:getNutrition() then
        return nil
    end

    local nutrition = player:getNutrition()
    if nutrition.isIncWeightLot and nutrition:isIncWeightLot() then
        return "up_lot"
    end
    if nutrition.isIncWeight and nutrition:isIncWeight() then
        return "up"
    end
    if nutrition.isDecWeight and nutrition:isDecWeight() then
        return "down"
    end

    return nil
end

local function migratePrefs()
    if not state or type(state.prefs) ~= "table" then
        return
    end

    -- "hudTransparent" was the old opt-in for hiding the boxes. It only ever got
    -- written by the default, never by a real choice, so drop it and let the new
    -- box-less default apply instead of inverting a value nobody picked.
    if state.prefs.hudTransparent ~= nil then
        state.prefs.hudTransparent = nil
    end
end

local function readPrefsFromModData(player)
    local modData = BetterStats.getPlayerModData(player)
    if not modData or type(modData.prefs) ~= "table" then
        return false
    end

    state.prefs = BetterStats.mergeDefaults(modData.prefs, state.prefs)
    migratePrefs()
    return true
end

local function writePrefsToModData(player)
    if not state or type(state.prefs) ~= "table" then
        return false
    end

    local modData = BetterStats.getPlayerModData(player)
    if not modData then
        return false
    end

    -- In multiplayer the stored prefs can land in mod data a few frames after the
    -- player is created. Adopt them instead of overwriting them with the defaults.
    if runtime.prefsRestored ~= true and type(modData.prefs) == "table" then
        readPrefsFromModData(player)
        runtime.prefsRestored = true
    end

    modData.version = BetterStats.STATE_VERSION
    modData.prefs = BetterStats.deepCopy(state.prefs)
    BetterStats.transmitPlayerModData(player)
    return true
end

local function ensureState(player)
    if not player then
        return nil
    end

    local profileId = BetterStats.getProfileId(player)
    if state and state.profileId == profileId then
        return state
    end

    local loaded = BetterStats.loadStateFromFile(BetterStats.getStateFileName(player))
    if not loaded then
        loaded = BetterStats.loadStateFromFile(BetterStats.getLegacyStateFileName(player))
    end

    state = BetterStats.mergeDefaults(loaded or {}, getDefaults())
    state.profileId = profileId
    migratePrefs()

    runtime.saveFileName = BetterStats.getStateFileName(player)
    runtime.savePending = false
    runtime.shoveActive = false
    runtime.lastStatusBars = nil
    runtime.prefsRestored = readPrefsFromModData(player)

    return state
end

local function markDirty()
    runtime.savePending = true
end

local function inferRunStartWorldDay(player, currentDay)
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getTimeOfDay then
        local currentHour = tonumber(gameTime:getTimeOfDay())
        if currentHour then
            local currentTimestampHours = ((tonumber(currentDay) or 0) * 24) + currentHour
            local survivedHours = getCurrentHours(player)
            return math.floor((currentTimestampHours - survivedHours) / 24)
        end
    end

    return (tonumber(currentDay) or 0) - math.floor(getCurrentHours(player) / 24)
end

local function ensureRunStartDay(player, currentDay)
    if not state or not state.run then
        return tonumber(currentDay) or 0
    end

    local startDay = tonumber(state.run.startWorldDay)
    local today = tonumber(currentDay) or 0
    if startDay == nil or startDay > today then
        startDay = math.min(today, inferRunStartWorldDay(player, today))
        state.run.startWorldDay = startDay
        markDirty()
    end

    return startDay
end

local function getAverageKillsPerDay(totalKills, currentDay)
    local startDay = state and state.run and tonumber(state.run.startWorldDay) or tonumber(currentDay) or 0
    local days = math.max(1, ((tonumber(currentDay) or startDay) - startDay) + 1)
    return (tonumber(totalKills) or 0) / days
end

local function clampInt(value, minValue, maxValue, defaultValue)
    local numeric = math.floor(tonumber(value) or defaultValue or minValue)
    if numeric < minValue then return minValue end
    if numeric > maxValue then return maxValue end
    return numeric
end

local function initializeDayBuckets(currentDay)
    state.run.dayKillsHistory[currentDay] = tonumber(state.run.dayKillsHistory[currentDay] or 0)
    state.run.dayDistanceHistory[currentDay] = tonumber(state.run.dayDistanceHistory[currentDay] or 0)
    BetterStats.trimHistory(state.run.dayKillsHistory, currentDay, 7)
    BetterStats.trimHistory(state.run.dayDistanceHistory, currentDay, 7)
end

local function resetRunState(player)
    local defaults = getDefaults().run
    state.run = BetterStats.deepCopy(defaults)

    local currentDay = BetterStats.getCurrentWorldDay()
    state.run.startWorldDay = currentDay
    initializeDayBuckets(currentDay)

    state.run.lastRecordedTotalKills = getCurrentKills(player)
    state.run.lastKnownHoursSurvived = getCurrentHours(player)
    state.run.lastCalories = getCurrentCalories(player)
    state.run.lastX = player and player:getX() or nil
    state.run.lastY = player and player:getY() or nil

    runtime.shoveActive = false
    runtime.lastStatusBars = nil
    markDirty()
end

local function detectNewCharacter(player)
    local currentHours = getCurrentHours(player)
    local currentKills = getCurrentKills(player)

    if currentHours + 1 < tonumber(state.run.lastKnownHoursSurvived or 0) then
        return true
    end

    if currentKills + 5 < tonumber(state.run.lastRecordedTotalKills or 0) then
        return true
    end

    return false
end

local function syncKillCounters(player)
    if not player or not state then return end

    if detectNewCharacter(player) then
        resetRunState(player)
    end

    local currentDay = BetterStats.getCurrentWorldDay()
    initializeDayBuckets(currentDay)
    ensureRunStartDay(player, currentDay)

    local currentKills = getCurrentKills(player)
    local previousKills = tonumber(state.run.lastRecordedTotalKills or 0)
    if currentKills > previousKills then
        local delta = currentKills - previousKills
        state.run.dayKillsHistory[currentDay] = tonumber(state.run.dayKillsHistory[currentDay] or 0) + delta
        state.run.lastRecordedTotalKills = currentKills
        markDirty()
    else
        state.run.lastRecordedTotalKills = currentKills
    end

    state.run.lastKnownHoursSurvived = getCurrentHours(player)
end

local function updateDistance(player)
    if not BetterStats.getSandboxBool("TrackDistance", true) then return end
    if not player or not state then return end

    local currentX = player:getX()
    local currentY = player:getY()
    if not currentX or not currentY then return end

    if state.run.lastX == nil or state.run.lastY == nil then
        state.run.lastX = currentX
        state.run.lastY = currentY
        return
    end

    local dx = currentX - state.run.lastX
    local dy = currentY - state.run.lastY
    local distance = math.sqrt((dx * dx) + (dy * dy))

    state.run.lastX = currentX
    state.run.lastY = currentY

    if distance <= 0.01 or distance > 25 then
        return
    end

    local currentDay = BetterStats.getCurrentWorldDay()
    initializeDayBuckets(currentDay)
    state.run.distanceTotal = tonumber(state.run.distanceTotal or 0) + distance
    state.run.dayDistanceHistory[currentDay] = tonumber(state.run.dayDistanceHistory[currentDay] or 0) + distance
    markDirty()
end

local function updateShoves(player)
    if not player or not state then return end

    if player:isDoShove() then
        if not runtime.shoveActive then
            runtime.shoveActive = true
            state.run.totalPushes = math.floor(tonumber(state.run.totalPushes or 0)) + 1
            markDirty()
        end
    else
        runtime.shoveActive = false
    end
end

local function updateCalories(player)
    if not BetterStats.getSandboxBool("TrackCalories", true) then return end
    if not player or not state then return end

    local currentCalories = getCurrentCalories(player)
    if currentCalories == nil then return end

    if state.run.lastCalories == nil then
        state.run.lastCalories = currentCalories
        return
    end

    local delta = currentCalories - state.run.lastCalories
    if math.abs(delta) < 0.05 then
        return
    end

    if delta > 0 then
        state.run.caloriesConsumed = tonumber(state.run.caloriesConsumed or 0) + delta
    else
        state.run.caloriesBurned = tonumber(state.run.caloriesBurned or 0) + math.abs(delta)
    end

    state.run.lastCalories = currentCalories
    markDirty()
end

local function recordWeaponUsage(weapon)
    if not weapon or not state then return end

    local name = nil
    if weapon.getDisplayName then
        name = weapon:getDisplayName()
    elseif weapon.getName then
        name = weapon:getName()
    end

    if not name or name == "" then
        name = getText("IGUI_BetterStats_None")
    end

    state.run.weaponUsage[name] = tonumber(state.run.weaponUsage[name] or 0) + 1
    markDirty()
end

local function getPrimaryWeapon()
    if not state then
        return getText("IGUI_BetterStats_None"), 0
    end

    local topName = getText("IGUI_BetterStats_None")
    local topCount = 0
    for name, count in pairs(state.run.weaponUsage or {}) do
        local numericCount = tonumber(count) or 0
        if numericCount > topCount then
            topName = tostring(name)
            topCount = numericCount
        end
    end

    return topName, topCount
end

function Data.ensureReady(playerObj)
    local player = playerObj or getPlayer()
    if not player then return false end

    ensureState(player)
    if detectNewCharacter(player) then
        resetRunState(player)
    end

    local currentDay = BetterStats.getCurrentWorldDay()
    initializeDayBuckets(currentDay)
    ensureRunStartDay(player, currentDay)

    if state.run.lastCalories == nil then
        state.run.lastCalories = getCurrentCalories(player)
    end

    if state.run.lastX == nil or state.run.lastY == nil then
        state.run.lastX = player:getX()
        state.run.lastY = player:getY()
    end

    syncKillCounters(player)
    return true
end

function Data.saveNow()
    if not state then
        return false
    end

    local prefsSaved = writePrefsToModData(getPlayer())

    local fileSaved = false
    if runtime.saveFileName and BetterStats.isProfileReliable() then
        local payload = BetterStats.deepCopy(state)
        payload.profileId = nil
        fileSaved = BetterStats.saveStateToFile(runtime.saveFileName, payload)
    end

    if prefsSaved or fileSaved then
        runtime.savePending = false
    end

    return prefsSaved or fileSaved
end

function Data.reloadPrefsFromModData()
    local player = getPlayer()
    if not player or not ensureState(player) then
        return false
    end

    if readPrefsFromModData(player) then
        runtime.prefsRestored = true
        return true
    end

    return false
end

function Data.arePrefsRestored()
    return runtime.prefsRestored == true
end

function Data.getPrefs()
    if not Data.ensureReady() then
        return nil
    end
    return state.prefs
end

function Data.setHUDPosition(x, y)
    if not Data.ensureReady() then return end
    state.prefs.hudX = math.max(0, math.floor(tonumber(x) or 0))
    state.prefs.hudY = math.max(0, math.floor(tonumber(y) or 0))
    markDirty()
    Data.saveNow()
end

function Data.setDetailPosition(x, y)
    if not Data.ensureReady() then return end
    state.prefs.detailX = math.max(0, math.floor(tonumber(x) or 0))
    state.prefs.detailY = math.max(0, math.floor(tonumber(y) or 0))
    markDirty()
    Data.saveNow()
end

function Data.resetPositions()
    if not Data.ensureReady() then return end
    state.prefs.hudX = 20
    state.prefs.hudY = 120
    state.prefs.detailX = 980
    state.prefs.detailY = 80
    markDirty()
    Data.saveNow()
end

function Data.isHUDBoxesVisible()
    if not Data.ensureReady() then return false end
    return state.prefs.hudShowBoxes == true
end

function Data.toggleHUDBoxes()
    if not Data.ensureReady() then return false end
    state.prefs.hudShowBoxes = not (state.prefs.hudShowBoxes == true)
    markDirty()
    Data.saveNow()
    return state.prefs.hudShowBoxes == true
end

function Data.isHUDLocked()
    if not Data.ensureReady() then return false end
    return state.prefs.hudLocked == true
end

function Data.toggleHUDLocked()
    if not Data.ensureReady() then return false end
    state.prefs.hudLocked = not (state.prefs.hudLocked == true)
    markDirty()
    Data.saveNow()
    return state.prefs.hudLocked == true
end

function Data.getHUDScale()
    if not Data.ensureReady() then return 100 end
    state.prefs.hudScale = clampInt(state.prefs.hudScale, 80, 130, 100)
    return state.prefs.hudScale
end

function Data.adjustHUDScale(delta)
    if not Data.ensureReady() then return 100 end
    local current = Data.getHUDScale()
    state.prefs.hudScale = clampInt(current + (tonumber(delta) or 0), 80, 130, 100)
    markDirty()
    Data.saveNow()
    return state.prefs.hudScale
end

function Data.setHUDScale(scale)
    if not Data.ensureReady() then return 100 end
    state.prefs.hudScale = clampInt(scale, 80, 130, 100)
    markDirty()
    Data.saveNow()
    return state.prefs.hudScale
end

function Data.isCompactStatusBarsVisible()
    if not Data.ensureReady() then return true end
    return state.prefs.hudShowStatusBars ~= false
end

function Data.toggleCompactStatusBars()
    if not Data.ensureReady() then return true end
    state.prefs.hudShowStatusBars = not (state.prefs.hudShowStatusBars ~= false)
    markDirty()
    Data.saveNow()
    return state.prefs.hudShowStatusBars ~= false
end

function Data.getHUDTint()
    if not Data.ensureReady() then return "white" end
    local tint = tostring(state.prefs.hudTint or "white")
    if tint ~= "white" and tint ~= "amber" and tint ~= "green" and tint ~= "blue" and tint ~= "red" and tint ~= "violet" then
        tint = "white"
        state.prefs.hudTint = tint
        markDirty()
    end
    return tint
end

function Data.setHUDTint(tint)
    if not Data.ensureReady() then return "white" end
    local value = tostring(tint or "white")
    if value ~= "white" and value ~= "amber" and value ~= "green" and value ~= "blue" and value ~= "red" and value ~= "violet" then
        value = "white"
    end
    state.prefs.hudTint = value
    markDirty()
    Data.saveNow()
    return value
end

function Data.resetHUDCustomization()
    if not Data.ensureReady() then return end
    state.prefs.hudShowBoxes = false
    state.prefs.hudLocked = false
    state.prefs.hudScale = 100
    state.prefs.hudTint = "white"
    state.prefs.hudShowStatusBars = true
    markDirty()
    Data.saveNow()
end

function Data.isHUDVisible()
    if not BetterStats.getSandboxBool("EnableCompactHUD", true) then
        return false
    end
    if not Data.ensureReady() then
        return false
    end
    return state.prefs.hudVisible == true
end

function Data.toggleHUD()
    if not Data.ensureReady() then return false end
    state.prefs.hudVisible = not (state.prefs.hudVisible == true)
    markDirty()
    Data.saveNow()
    return state.prefs.hudVisible == true
end

function Data.canOpenDetailedPanel()
    return BetterStats.getSandboxBool("AllowDetailedPanel", false)
end

function Data.isDetailVisible()
    if not Data.canOpenDetailedPanel() then
        return false
    end
    if not Data.ensureReady() then
        return false
    end
    return state.prefs.detailVisible == true
end

function Data.setDetailVisible(visible)
    if not Data.ensureReady() then return end
    state.prefs.detailVisible = visible == true and Data.canOpenDetailedPanel()
    markDirty()
    Data.saveNow()
end

function Data.toggleDetailVisible()
    if not Data.canOpenDetailedPanel() then
        if Data.ensureReady() then
            state.prefs.detailVisible = false
            markDirty()
            Data.saveNow()
        end
        return false
    end

    if not Data.ensureReady() then
        return false
    end

    state.prefs.detailVisible = not (state.prefs.detailVisible == true)
    markDirty()
    Data.saveNow()
    return state.prefs.detailVisible == true
end

function Data.getCompactRows()
    local player = getPlayer()
    if not player or not Data.ensureReady(player) then
        return {}
    end

    syncKillCounters(player)

    local currentDay = BetterStats.getCurrentWorldDay()
    initializeDayBuckets(currentDay)
    ensureRunStartDay(player, currentDay)

    local totalKills = getCurrentKills(player)
    local hoursSurvived = getCurrentHours(player)
    local averagePerDay = getAverageKillsPerDay(totalKills, currentDay)

    local rows = {
        {
            key = "alive",
            icon = "D",
            label = getText("IGUI_BetterStats_Alive"),
            value = BetterStats.formatHours(hoursSurvived),
            tone = "neutral",
        },
        {
            key = "kills",
            icon = "Z",
            label = getText("IGUI_BetterStats_TotalKills"),
            value = tostring(totalKills),
            tone = "neutral",
        },
        {
            key = "today",
            icon = "T",
            label = getText("IGUI_BetterStats_KillsToday"),
            value = tostring(math.floor(tonumber(state.run.dayKillsHistory[currentDay] or 0))),
            tone = "warning",
        },
        {
            key = "average",
            icon = "A",
            label = getText("IGUI_BetterStats_AveragePerDay"),
            value = BetterStats.formatOneDecimal(averagePerDay),
            tone = "neutral",
        },
    }

    if BetterStats.getSandboxBool("TrackDistance", true) then
        rows[#rows + 1] = {
            key = "distance",
            icon = "K",
            label = getText("IGUI_BetterStats_Distance"),
            value = BetterStats.formatDistance(state.run.distanceTotal),
            tone = "neutral",
        }
    end

    local weight = getRoundedWeight(player)
    if weight then
        rows[#rows + 1] = {
            key = "weight",
            icon = "W",
            label = getText("IGUI_char_Weight"),
            value = tostring(weight),
            tone = "neutral",
            trend = getWeightTrend(player),
        }
    end

    return rows
end

function Data.getDetailedSnapshot()
    local player = getPlayer()
    if not player or not Data.ensureReady(player) or not Data.canOpenDetailedPanel() then
        return nil
    end

    syncKillCounters(player)

    local currentDay = BetterStats.getCurrentWorldDay()
    initializeDayBuckets(currentDay)
    ensureRunStartDay(player, currentDay)

    local totalKills = getCurrentKills(player)
    local hoursSurvived = getCurrentHours(player)
    local averagePerDay = getAverageKillsPerDay(totalKills, currentDay)
    local primaryWeapon = getPrimaryWeapon()
    local balance = tonumber(state.run.caloriesConsumed or 0) - tonumber(state.run.caloriesBurned or 0)

    local trend = BetterStats.getRecentSeries(state.run.dayKillsHistory, currentDay, 7)
    local trendMax = 1
    for _, value in ipairs(trend) do
        if value > trendMax then
            trendMax = value
        end
    end

    return {
        primaryWeapon = primaryWeapon,
        trend = trend,
        trendMax = trendMax,
        totalKills = totalKills,
        averagePerDay = BetterStats.formatOneDecimal(averagePerDay),
        hitsLanded = math.floor(tonumber(state.run.hitsLanded or 0)),
        pushes = math.floor(tonumber(state.run.totalPushes or 0)),
        killsPerHour = BetterStats.formatOneDecimal(totalKills / math.max(1, hoursSurvived)),
        distanceToday = BetterStats.formatDistance(state.run.dayDistanceHistory[currentDay] or 0),
        totalDistance = BetterStats.formatDistance(state.run.distanceTotal or 0),
        caloriesBalance = math.floor(balance + 0.5),
        caloriesConsumed = math.floor(tonumber(state.run.caloriesConsumed or 0) + 0.5),
        caloriesBurned = math.floor(tonumber(state.run.caloriesBurned or 0) + 0.5),
    }
end

function Data.getCompactStatusBars()
    local player = getPlayer()
    if not player or not Data.ensureReady(player) then
        return {}
    end
    if not BetterStats.getSandboxBool("ShowCompactStatusBars", true) or not Data.isCompactStatusBarsVisible() then
        return {}
    end

    local stats = player.getStats and player:getStats() or nil
    if not stats then
        return {}
    end

    if isPlayerDead(player) and runtime.lastStatusBars then
        return BetterStats.deepCopy(runtime.lastStatusBars)
    end

    local bars = {
        {
            key = "health",
            fill = clamp01((player:getBodyDamage() and player:getBodyDamage():getHealth() or 0) / 100),
        },
        {
            key = "hunger",
            fill = getNeedStatusFillFromMoodle(player, stats:get(CharacterStat.HUNGER), MoodleType and MoodleType.HUNGRY or nil, 0.15),
        },
        {
            key = "thirst",
            fill = getNeedStatusFillFromMoodle(player, stats:get(CharacterStat.THIRST), MoodleType and MoodleType.THIRST or nil, 0.12),
        },
        {
            key = "stamina",
            fill = clamp01(stats:get(CharacterStat.ENDURANCE)),
        },
    }

    runtime.lastStatusBars = BetterStats.deepCopy(bars)
    return bars
end

local function onGameStart()
    Data.ensureReady()
end

local function onCreatePlayer(playerIndex, playerObj)
    if playerObj and playerObj.isLocalPlayer and not playerObj:isLocalPlayer() then
        return
    end
    Data.ensureReady(playerObj)
end

local function onPlayerUpdate(player)
    if not player or not player.isLocalPlayer or not player:isLocalPlayer() then
        return
    end
    if not Data.ensureReady(player) then
        return
    end

    updateDistance(player)
    updateShoves(player)
end

local function onZombieDead(_zombie)
    local player = getPlayer()
    if not player or not Data.ensureReady(player) then
        return
    end
    syncKillCounters(player)
end

local function onWeaponHitCharacter(wielder, character, weapon, _damage)
    if not wielder or not wielder.isLocalPlayer or not wielder:isLocalPlayer() then
        return
    end
    if not character or not instanceof(character, "IsoZombie") then
        return
    end
    if not Data.ensureReady(wielder) then
        return
    end

    state.run.hitsLanded = math.floor(tonumber(state.run.hitsLanded or 0)) + 1
    recordWeaponUsage(weapon)
end

local function onEveryOneMinute()
    local player = getPlayer()
    if not player or not Data.ensureReady(player) then
        return
    end

    syncKillCounters(player)
    updateCalories(player)
    if runtime.savePending then
        Data.saveNow()
    end
end

local function onEveryTenMinutes()
    local player = getPlayer()
    if not player or not Data.ensureReady(player) then
        return
    end

    syncKillCounters(player)
    if runtime.savePending then
        Data.saveNow()
    end
end

local function onSave()
    if runtime.savePending then
        Data.saveNow()
    end
end

local function onPlayerDeath(player)
    if player and player.isLocalPlayer and player:isLocalPlayer() then
        Data.saveNow()
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnZombieDead.Add(onZombieDead)
Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
Events.EveryOneMinute.Add(onEveryOneMinute)
Events.EveryTenMinutes.Add(onEveryTenMinutes)
Events.OnSave.Add(onSave)
Events.OnPlayerDeath.Add(onPlayerDeath)
