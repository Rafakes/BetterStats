require "BetterStats/00_BetterStats_Shared"
require "BetterStats/01_BetterStats_Data"
require "BetterStats/02_BetterStats_HUD"
require "BetterStats/03_BetterStats_DetailWindow"

BetterStats = BetterStats or {}

local hooked = false

local function onKeyPressed(key)
    if key == Keyboard.KEY_F7 then
        BetterStats.HUD.toggleFromKey()
    elseif key == Keyboard.KEY_F8 then
        BetterStats.Detail.toggleWindow()
    end
end

local function hookKeys()
    if hooked then return end
    hooked = true
    Events.OnKeyPressed.Add(onKeyPressed)
end

Events.OnGameStart.Add(hookKeys)
