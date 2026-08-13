--[[
Sidekick - Vana'diel environment (weather + day) and element auto-selection

Reads the current elemental weather and the Vana'diel day of the week, then
steers a group's `selected_<group>` setting at the tier whose `auto_element`
matches. Drives the right-click "Auto Select" item on the RDM enspell and SCH
storm groups. See ARCHITECTURE.md for the `auto_element` / `auto_element_source`
field contract.

Feature idea: Cedwick
]]--

local common = require('lib.core.common')
-- Aliased: apply_auto_selection's `settings` parameter is the addon's settings
-- table, not Ashita's settings module.
local settings_api = require('settings')

local vanadiel = {}

-- Neither value is exposed through AshitaCore's managers, so both are FFXiMain.dll
-- signature scans -- the same signatures LuAshitacast and fancycompass use.
local weather_addr = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0) or 0                 -- weather byte at [[sig+0x02]]
local time_addr    = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0, 0) or 0       -- clock tick at [[sig+0x34]+0x0C]

-- Weather byte 4-19 -> element, two bytes each (even = single weather, odd =
-- double; same element either way, and doubling doesn't change which tier to
-- pick). Bytes 0-3 are the non-elemental weathers (Clear/Sunshine/Clouds/Fog)
-- and fall off the front of the table as nil.
local WEATHER_ELEMENT = { 'fire', 'water', 'earth', 'wind', 'ice', 'thunder', 'light', 'dark' }

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
    Environment readers
]]--

-- Zone weather element, ignoring storms. nil when non-elemental or unreadable.
local function read_zone_weather()
    if weather_addr == 0 then return nil end
    local ptr = ashita.memory.read_uint32(weather_addr + 0x02)
    if ptr == 0 then return nil end
    return WEATHER_ELEMENT[math.floor(ashita.memory.read_uint8(ptr) / 2) - 1]
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
    if time_addr == 0 then return nil end
    local ptr = ashita.memory.read_uint32(time_addr + 0x34)
    if ptr == 0 then return nil end
    local t = ashita.memory.read_uint32(ptr + 0x0C) + 92514960
    return DAY_ELEMENT[math.floor(t / 3456) % 8]
end

--[[
    Auto-selection
]]--

-- How well `ability`'s element matches the sky. Lower is a better bonus, nil is
-- no match at all. The group's own `auto_element_source` picks the order:
--
--   'weather'  Zone weather only, storms deliberately ignored, no day fallback.
--              For groups that *cast* the storms (SCH): a storm is the group's
--              own output, so feeding it back would pin the pick to whatever it
--              last cast, and a storm stacked on matching weather is the whole
--              point (double weather bonus). No weather = nothing to match.
--   default    Storm buff (the player's effective weather) > zone weather > day.
--              For groups that merely *benefit* (RDM enspells).
local function element_rank(ability, weather, storm, day)
    if ability.auto_element_source == 'weather' then
        return ability.auto_element == weather and 1 or nil
    end
    if ability.auto_element == (storm or weather) then return 1 end
    if ability.auto_element == day then return 2 end
    return nil
end

local THROTTLE_SECONDS = 1.0
local last_apply = 0

-- Point `selected_<group>` at the element-matching tier for every group with
-- auto-select enabled. One pass over the job's abilities: best rank wins, then
-- highest level. No group name is hardcoded -- any future elemental group picks
-- the feature up just by tagging its tiers with `auto_element`. A group with no
-- matching castable tier is left alone rather than cleared. Called once per tick
-- from Sidekick.lua; weather and day only turn over on Vana'diel-minute
-- boundaries, so this is self-throttled rather than run every frame.
function vanadiel.apply_auto_selection(job_def, settings)
    local now = os.clock()
    if now - last_apply < THROTTLE_SECONDS then return end
    last_apply = now

    local main_level, sub_level = common.get_player_level()
    local weather, storm, day = read_zone_weather(), read_storm(), read_day()
    local best = {}

    for _, abilities in pairs(job_def.abilities or {}) do
        for _, ability in ipairs(abilities) do
            -- Ungrouped casts every tier independently, so there is no single
            -- selection to steer.
            local group = ability.auto_element and ability.group
            if group and settings['auto_element_' .. group] == true
                and settings['ungrouped_' .. group] ~= true
                -- Same level / main-vs-sub / learned rule the config dropdown
                -- filters by, so auto-select can only land on a spell the
                -- dropdown would also have offered.
                and common.precast_permanently_usable(ability, main_level, sub_level) then
                local rank = element_rank(ability, weather, storm, day)
                local cur = best[group]
                if rank and (not cur or rank < cur.rank
                    or (rank == cur.rank and (ability.level or 0) > (cur.ability.level or 0))) then
                    best[group] = { ability = ability, rank = rank }
                end
            end
        end
    end

    for group, pick in pairs(best) do
        local key = 'selected_' .. group
        if settings[key] ~= pick.ability.name then
            settings[key] = pick.ability.name
            settings_api.save()
            common.debugf('[Vanadiel] Auto-selected %s for %s (%s)', pick.ability.name, group, pick.ability.auto_element)
        end
    end
end

return vanadiel
