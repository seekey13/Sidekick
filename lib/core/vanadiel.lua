--[[
Sidekick - Vana'diel environment (weather + day) and element auto-selection

Reads the current elemental weather and the Vana'diel day of the week, then
steers a group's `selected_<group>` setting at the tier whose `element` matches.
Used by the enspell group's right-click "Auto Select for Weather/Day" item.

Both readers are FFXiMain.dll signature scans -- the same signatures LuAshitacast
and fancycompass use. Neither value is exposed through AshitaCore's managers.

Feature idea: Cedwick
]]--

local common = require('lib.core.common')
-- Aliased: apply_auto_selection's `settings` parameter is the addon's settings
-- table, not Ashita's settings module.
local settings_api = require('settings')

local vanadiel = {}

-- Weather byte lives at [[sig + 0x02]]. Sig shared with LuAshitacast.
local WEATHER_SIG = '66A1????????663D????72'
-- Vana'diel clock: tick counter at [[sig + 0x34] + 0x0C].
local TIME_SIG    = 'B0015EC390518B4C24088D4424005068'

-- Raw weather byte -> element. Even = single weather, odd = double; the element
-- is the same either way and doubling doesn't change which enspell to pick.
-- Bytes 0-3 are the non-elemental weathers (Clear/Sunshine/Clouds/Fog).
local WEATHER_ELEMENT = {
    [4]  = 'fire',    [5]  = 'fire',
    [6]  = 'water',   [7]  = 'water',
    [8]  = 'earth',   [9]  = 'earth',
    [10] = 'wind',    [11] = 'wind',
    [12] = 'ice',     [13] = 'ice',
    [14] = 'thunder', [15] = 'thunder',
    [16] = 'light',   [17] = 'light',
    [18] = 'dark',    [19] = 'dark',
}

-- Day index (0..7) -> element.
local DAY_ELEMENT = {
    [0] = 'fire',
    [1] = 'earth',
    [2] = 'water',
    [3] = 'wind',
    [4] = 'ice',
    [5] = 'thunder',
    [6] = 'light',
    [7] = 'dark',
}

-- Storm status effects (status_effects.sql). A storm on the player overrides the
-- zone weather for that player. 178-185 are tier I, 589-596 tier II; both run in
-- the standard element order Fire/Ice/Wind/Earth/Thunder/Water/Light/Dark
-- (decoded from LuAshitacast's constants.StormWeather).
local STORM_ELEMENT = {
    [178] = 'fire',    [589] = 'fire',
    [179] = 'ice',     [590] = 'ice',
    [180] = 'wind',    [591] = 'wind',
    [181] = 'earth',   [592] = 'earth',
    [182] = 'thunder', [593] = 'thunder',
    [183] = 'water',   [594] = 'water',
    [184] = 'light',   [595] = 'light',
    [185] = 'dark',    [596] = 'dark',
}

--[[
    Signature scanning (lazy, once)
]]--

-- nil = not scanned yet, 0 = scan failed (don't rescan every tick).
local weather_addr = nil
local time_addr    = nil

local function scan_signatures()
    if weather_addr ~= nil then return end
    weather_addr = ashita.memory.find('FFXiMain.dll', 0, WEATHER_SIG, 0, 0) or 0
    time_addr    = ashita.memory.find('FFXiMain.dll', 0, TIME_SIG, 0, 0) or 0
    if weather_addr == 0 or time_addr == 0 then
        -- Not fatal: auto-select simply never moves the selection.
        common.debugf('[Vanadiel] Signature scan failed (weather=%d time=%d)', weather_addr, time_addr)
    end
end

--[[
    Environment readers
]]--

-- Zone weather element, ignoring storms. nil when non-elemental or unreadable.
local function read_zone_weather()
    scan_signatures()
    if weather_addr == 0 then return nil end
    local ptr = ashita.memory.read_uint32(weather_addr + 0x02)
    if ptr == 0 then return nil end
    return WEATHER_ELEMENT[ashita.memory.read_uint8(ptr)]
end

-- Element of a storm status on the player, or nil when none is up. Walks the
-- player's buff list once rather than calling has_buff for all 16 storm ids.
local function read_storm()
    for _, buff_id in ipairs(common.get_player_buffs()) do
        local element = STORM_ELEMENT[buff_id]
        if element then return element end
    end
    return nil
end

local function read_day()
    scan_signatures()
    if time_addr == 0 then return nil end
    local ptr = ashita.memory.read_uint32(time_addr + 0x34)
    if ptr == 0 then return nil end
    local t = ashita.memory.read_uint32(ptr + 0x0C) + 92514960
    return DAY_ELEMENT[math.floor(t / 3456) % 8]
end

-- Weather and day only turn over on Vana'diel-minute boundaries, so re-reading
-- (and walking the player's buff list) every frame is pure waste.
local CACHE_SECONDS = 1.0
local last_read     = 0
local cached_weather = nil
local cached_day     = nil

local function refresh()
    local now = os.clock()
    if now - last_read < CACHE_SECONDS then return end
    last_read = now
    cached_weather = read_storm() or read_zone_weather()
    cached_day = read_day()
end

-- Current weather element -- a storm on the player wins over the zone weather.
function vanadiel.weather_element()
    refresh()
    return cached_weather
end

function vanadiel.day_element()
    refresh()
    return cached_day
end

-- Elements to try, best bonus first: weather, then day. Either may be absent,
-- and the two collapse to one entry when they match.
function vanadiel.candidate_elements()
    refresh()
    local out = {}
    if cached_weather then table.insert(out, cached_weather) end
    if cached_day and cached_day ~= cached_weather then table.insert(out, cached_day) end
    return out
end

--[[
    Auto-selection
]]--

-- Same level/main-vs-sub rule the config dropdown filters by (see
-- default_filters.can_use_ability in lib/ui/components.lua), so auto-select can
-- only land on a spell the dropdown would also have offered.
local function level_ok(ability, main_level, sub_level)
    if not ability.level then return true end
    if ability.main_job_only and ability.is_main_job == false then return false end
    if ability.is_main_job == false then return sub_level >= ability.level end
    return main_level >= ability.level
end

-- Highest-level castable ability in `group` whose element matches, or nil.
local function best_for_element(job_def, group, element, main_level, sub_level)
    local best = nil
    for _, abilities in pairs(job_def.abilities or {}) do
        for _, ability in ipairs(abilities) do
            if ability.group == group and ability.element == element
                and level_ok(ability, main_level, sub_level)
                and common.has_spell_learned(ability)
                and (not best or ability.level > best.level) then
                best = ability
            end
        end
    end
    return best
end

-- Groups in this job that carry per-ability elements, so no group name is
-- hardcoded here -- any future elemental group picks the feature up for free.
local function elemental_groups(job_def)
    local groups = {}
    for _, abilities in pairs(job_def.abilities or {}) do
        for _, ability in ipairs(abilities) do
            if ability.group and ability.element then groups[ability.group] = true end
        end
    end
    return groups
end

local THROTTLE_SECONDS = 1.0
local last_apply = 0

-- Point `selected_<group>` at the element-matching tier for every group with
-- 'Auto Select for Weather/Day' enabled. Weather first, day as the fallback;
-- when neither element has a castable tier the existing selection is left alone
-- rather than cleared. Called once per tick from Sidekick.lua.
function vanadiel.apply_auto_selection(job_def, settings)
    if not job_def or not settings then return end

    local now = os.clock()
    if now - last_apply < THROTTLE_SECONDS then return end
    last_apply = now

    local groups = elemental_groups(job_def)
    if not next(groups) then return end

    local elements = vanadiel.candidate_elements()
    if #elements == 0 then return end

    local main_level, sub_level = common.get_player_level()

    for group in pairs(groups) do
        -- Ungrouped casts every tier independently, so there is no single
        -- selection to steer.
        if settings['auto_element_' .. group] == true
            and settings['ungrouped_' .. group] ~= true then
            for _, element in ipairs(elements) do
                local pick = best_for_element(job_def, group, element, main_level, sub_level)
                if pick then
                    local key = 'selected_' .. group
                    if settings[key] ~= pick.name then
                        settings[key] = pick.name
                        settings_api.save()
                        common.debugf('[Vanadiel] Auto-selected %s for %s (%s)', pick.name, group, element)
                    end
                    break
                end
            end
        end
    end
end

return vanadiel
