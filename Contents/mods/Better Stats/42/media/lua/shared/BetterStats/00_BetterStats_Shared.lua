BetterStats = BetterStats or {}

-- PZ 42.20.4 / 42.19.2 / 41.78.21 removed loadstring/loadstream entirely, so
-- state files can no longer be compiled and executed as raw Lua text.
-- See 00_BetterStats_SafeParser.lua for the replacement (parses as data).
require "BetterStats/00_BetterStats_SafeParser"

BetterStats.MOD_ID = "BetterStats"
BetterStats.MOD_NAME = "Better Stats"
BetterStats.VERSION = "1.0.0"
BetterStats.STATE_VERSION = 1
BetterStats.SAVE_PREFIX = "BetterStats_"

local function sbGetOptionValue(fullName)
    if not getSandboxOptions then return nil end

    local options = getSandboxOptions()
    if not options or not options.getOptionByName then return nil end

    local ok, option = pcall(function()
        return options:getOptionByName(fullName)
    end)
    if not ok or not option then return nil end

    if option.getValue then
        local okValue, value = pcall(function()
            return option:getValue()
        end)
        if okValue then
            return value
        end
    end

    return nil
end

function BetterStats.getLocalPlayer()
    if getSpecificPlayer then
        return getSpecificPlayer(0)
    end
    if getPlayer then
        return getPlayer()
    end
    return nil
end

BetterStats.MODDATA_KEY = "BetterStats"

function BetterStats.getPlayerModData(playerObj)
    local player = playerObj or BetterStats.getLocalPlayer()
    if not player or not player.getModData then
        return nil
    end

    local ok, modData = pcall(function()
        return player:getModData()
    end)
    if not ok or type(modData) ~= "table" then
        return nil
    end

    if type(modData[BetterStats.MODDATA_KEY]) ~= "table" then
        modData[BetterStats.MODDATA_KEY] = {}
    end

    return modData[BetterStats.MODDATA_KEY]
end

function BetterStats.transmitPlayerModData(playerObj)
    local player = playerObj or BetterStats.getLocalPlayer()
    if not player or not player.transmitModData then
        return false
    end

    local ok = pcall(function()
        player:transmitModData()
    end)
    return ok
end

function BetterStats.getSandboxBool(modKey, default)
    if SandboxVars and SandboxVars.BetterStats and SandboxVars.BetterStats[modKey] ~= nil then
        return SandboxVars.BetterStats[modKey] == true
    end

    local value = sbGetOptionValue("BetterStats." .. tostring(modKey))
    if value ~= nil then
        return value == true
    end

    return default == true
end

function BetterStats.getSandboxInt(modKey, default)
    if SandboxVars and SandboxVars.BetterStats and SandboxVars.BetterStats[modKey] ~= nil then
        local value = tonumber(SandboxVars.BetterStats[modKey])
        if value then
            return math.floor(value)
        end
    end

    local value = tonumber(sbGetOptionValue("BetterStats." .. tostring(modKey)))
    if value then
        return math.floor(value)
    end

    return math.floor(default or 0)
end

function BetterStats.deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, innerValue in pairs(value) do
        copy[key] = BetterStats.deepCopy(innerValue)
    end
    return copy
end

function BetterStats.mergeDefaults(existing, defaults)
    local merged = BetterStats.deepCopy(defaults or {})
    if type(existing) ~= "table" then
        return merged
    end

    for key, value in pairs(existing) do
        if type(value) == "table" and type(merged[key]) == "table" then
            merged[key] = BetterStats.mergeDefaults(value, merged[key])
        else
            merged[key] = BetterStats.deepCopy(value)
        end
    end

    return merged
end

function BetterStats.formatHours(hours)
    local wholeHours = math.max(0, math.floor(tonumber(hours) or 0))
    local days = math.floor(wholeHours / 24)
    local remainder = wholeHours % 24
    return string.format("%dd %dh", days, remainder)
end

function BetterStats.formatOneDecimal(value)
    return string.format("%.1f", tonumber(value) or 0)
end

function BetterStats.formatDistance(distanceMeters)
    local distance = tonumber(distanceMeters) or 0
    if distance >= 1000 then
        return string.format("%.1f km", distance / 1000)
    end
    return string.format("%dm", math.floor(distance + 0.5))
end

function BetterStats.sanitizeToken(value)
    local token = tostring(value or "unknown")
    token = token:gsub("[^%w%-_]+", "_")
    token = token:gsub("_+", "_")
    token = token:gsub("^_", "")
    token = token:gsub("_$", "")
    if token == "" then
        token = "unknown"
    end
    return token:sub(1, 64)
end

local cachedProfileOwner = nil
local cachedProfileId = nil
local cachedProfileReliable = false

-- Returns the profile id plus whether every token it was built from was actually
-- available. Right after a multiplayer login getServerName() can still be empty,
-- which used to produce a second, throwaway profile ("mp_unknown_...") and made the
-- mod load a different save file than the one it had written.
local function buildProfileId(player)
    local username = "local"
    if player and player.getUsername then
        local rawName = player:getUsername()
        if rawName and rawName ~= "" then
            username = rawName
        end
    end

    local userToken = BetterStats.sanitizeToken(username)
    local userKnown = username ~= "local" and userToken ~= "unknown"

    if getWorld and getWorld() and getWorld():getGameMode() == "Multiplayer" then
        local serverName = getServerName and getServerName() or ""
        local serverToken = BetterStats.sanitizeToken(serverName)
        local profileId = table.concat({ "mp", serverToken, userToken }, "_")
        return profileId, (userKnown and serverToken ~= "unknown")
    end

    local worldName = "world"
    local gameMode = "Sandbox"
    local world = getWorld and getWorld() or nil
    if world then
        if world.getWorld then
            worldName = world:getWorld() or worldName
        end
        if world.getGameMode then
            gameMode = world:getGameMode() or gameMode
        end
    end

    local profileId = table.concat({
        "sp",
        BetterStats.sanitizeToken(gameMode),
        BetterStats.sanitizeToken(worldName),
        userToken,
    }, "_")

    return profileId, true
end

function BetterStats.getProfileId(playerObj)
    local player = playerObj or BetterStats.getLocalPlayer()

    if cachedProfileId and cachedProfileReliable and cachedProfileOwner == player then
        return cachedProfileId
    end

    -- Mod data travels with the character, so a profile id stored there stays stable
    -- across logins even when the world/server globals answer differently.
    local modData = BetterStats.getPlayerModData(player)
    if modData and type(modData.profileId) == "string" and modData.profileId ~= "" then
        cachedProfileOwner = player
        cachedProfileId = modData.profileId
        cachedProfileReliable = true
        return cachedProfileId
    end

    local profileId, reliable = buildProfileId(player)
    cachedProfileOwner = player
    cachedProfileId = profileId
    cachedProfileReliable = reliable

    if reliable and modData then
        modData.profileId = profileId
        BetterStats.transmitPlayerModData(player)
    end

    return profileId
end

function BetterStats.isProfileReliable()
    return cachedProfileReliable == true
end

function BetterStats.getStateFileName(playerObj)
    return BetterStats.SAVE_PREFIX .. BetterStats.getProfileId(playerObj) .. ".txt"
end

function BetterStats.getLegacyStateFileName(playerObj)
    return BetterStats.SAVE_PREFIX .. BetterStats.getProfileId(playerObj) .. ".lua"
end

local function serializeValue(value)
    local valueType = type(value)
    if valueType == "nil" then
        return "nil"
    end
    if valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType == "table" then
        local parts = {"{"}
        for key, innerValue in pairs(value) do
            local keyChunk
            if type(key) == "string" and key:match("^[%a_][%w_]*$") then
                keyChunk = key
            else
                keyChunk = "[" .. serializeValue(key) .. "]"
            end
            parts[#parts + 1] = keyChunk .. "=" .. serializeValue(innerValue) .. ","
        end
        parts[#parts + 1] = "}"
        return table.concat(parts)
    end
    return "nil"
end

function BetterStats.saveStateToFile(fileName, payload)
    if not fileName or type(payload) ~= "table" then return false end

    local writer = getFileWriter(fileName, true, false)
    if not writer then return false end

    writer:write("return " .. serializeValue(payload))
    writer:close()
    return true
end

function BetterStats.loadStateFromFile(fileName)
    if not fileName then return nil end

    local reader = getFileReader(fileName, false)
    if not reader then return nil end

    local lines = {}
    while true do
        local line = reader:readLine()
        if not line then break end
        lines[#lines + 1] = line
    end
    reader:close()

    local contents = table.concat(lines, "\n")
    if contents == "" then
        return nil
    end

    local data, err = BetterStats.parseSafeLuaData(contents)
    if type(data) ~= "table" then
        print("[BetterStats] Failed to parse state file: " .. tostring(err))
        return nil
    end

    return data
end

local function isLeapYear(year)
    local numericYear = math.floor(tonumber(year) or 0)
    if numericYear % 400 == 0 then return true end
    if numericYear % 100 == 0 then return false end
    return numericYear % 4 == 0
end

local function getDaysBeforeYear(year)
    local numericYear = math.floor(tonumber(year) or 0)
    local previousYear = numericYear - 1
    if previousYear <= 0 then
        return 0
    end

    return (numericYear * 365)
        + math.floor(previousYear / 4)
        - math.floor(previousYear / 100)
        + math.floor(previousYear / 400)
end

function BetterStats.getCurrentWorldDay()
    if getGameTime then
        local gameTime = getGameTime()
        if gameTime and gameTime.getDay and gameTime.getMonth and gameTime.getYear then
            local year = math.floor(tonumber(gameTime:getYear()) or 0)
            local month = math.floor(tonumber(gameTime:getMonth()) or 0)
            local day = math.floor(tonumber(gameTime:getDay()) or 0)
            local dayOfYear = 0

            for monthIndex = 0, month - 1 do
                local monthDays = nil
                if gameTime.daysInMonth then
                    local ok, result = pcall(function()
                        return gameTime:daysInMonth(year, monthIndex)
                    end)
                    if ok then
                        monthDays = tonumber(result)
                    end
                end

                if not monthDays then
                    local fallbackMonthDays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
                    monthDays = fallbackMonthDays[monthIndex + 1] or 30
                    if monthIndex == 1 and isLeapYear(year) then
                        monthDays = 29
                    end
                end

                dayOfYear = dayOfYear + monthDays
            end

            return math.max(0, getDaysBeforeYear(year) + dayOfYear + day)
        end

        if gameTime and gameTime.getWorldAgeHours then
            return math.max(0, math.floor(gameTime:getWorldAgeHours() / 24))
        end
    end
    return 0
end

function BetterStats.trimHistory(history, currentDay, keepDays)
    if type(history) ~= "table" then return end

    local limit = math.max(1, tonumber(keepDays) or 7)
    for key, _ in pairs(history) do
        local numericKey = tonumber(key)
        if not numericKey or numericKey < (currentDay - limit + 1) then
            history[key] = nil
        end
    end
end

function BetterStats.getRecentSeries(history, currentDay, keepDays)
    local series = {}
    local totalDays = math.max(1, tonumber(keepDays) or 7)
    local firstDay = currentDay - totalDays + 1

    for day = firstDay, currentDay do
        series[#series + 1] = math.max(0, tonumber(history[day] or 0))
    end

    return series
end
