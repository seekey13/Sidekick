--[[
    AFK Sleep
    Automation sleeps after afk_timeout seconds of no party movement (game_state
    positions, indices 0-5) and no party combat (common.is_combat()). A runtime gate,
    not a stop: automation_enabled stays true and nothing is written to disk.

    Asymmetric by design: the whole party keeps automation awake, but only the
    player's OWN movement wakes it -- a mob claim is not proof a human is present.
]]--

local common = require('lib.core.common')

local afk = {}

-- Runtime-only state -- never persisted, does not survive /addon reload.
local last_positions = {}       -- [0-5] = {x, y, z} sampled on the previous update
local still_since = os.clock()  -- When the still-and-out-of-combat condition began
local sleeping = false

local DEFAULT_TIMEOUT = 600  -- Seconds; mirrors default_settings.afk_timeout

-- Minutes when they divide evenly (10m), else seconds (90s).
local function format_timeout(seconds)
    if seconds % 60 == 0 then
        return string.format('%dm', seconds / 60)
    end
    return string.format('%ds', seconds)
end

-- Samples every party slot into last_positions; true when any member moved since the
-- previous sample. Out-of-zone members read a frozen {0,0,0}, so they never register.
-- Index 0 is the player, held in game_state.player (game_state.party is 1-5 only).
local function sample_party_movement()
    local moved = false
    local gs = common.game_state
    local party = gs and gs.party
    for i = 0, 5 do
        local member = (i == 0) and (gs and gs.player) or (party and party[i])
        local pos = member and member.position
        if pos then
            local last = last_positions[i]
            -- Exact float inequality, as common.is_player_moving() does.
            if last and (pos.x ~= last.x or pos.y ~= last.y or pos.z ~= last.z) then
                moved = true
            end
            last_positions[i] = { x = pos.x, y = pos.y, z = pos.z }
        else
            -- Slot empty (member left/zoned) -- drop it so rejoining is not "movement".
            last_positions[i] = nil
        end
    end
    return moved
end

-- Advances the state machine. Called every tick while automation is started.
-- Prints on transition only.
function afk.update(settings)
    if not settings or not settings.afk_enabled then
        -- Reset every tick so it can't be left asleep, and so re-enabling starts a
        -- full interval instead of sleeping instantly.
        afk.reset()
        return
    end

    local timeout = settings.afk_timeout or DEFAULT_TIMEOUT
    local party_moved = sample_party_movement()
    local now = os.clock()

    if sleeping then
        -- Only the player's own movement wakes. Combat deliberately does not: an AFK
        -- player in a party that pulls should stay asleep.
        if common.is_player_moving() then
            sleeping = false
            still_since = now
            common.printf('AFK: movement detected. Automation resumed.')
        end
        return
    end

    if party_moved or common.is_combat() then
        still_since = now
    elseif now - still_since >= timeout then
        sleeping = true
        common.printf('AFK: no party movement or combat for %s. Automation asleep - move to wake.',
            format_timeout(timeout))
    end
end

-- Gate query for the tick loop and the debug panel.
function afk.is_sleeping()
    return sleeping
end

-- Seconds left before sleep. Display only (debug panel); 0 when asleep or disabled.
function afk.seconds_remaining(settings)
    if not settings or not settings.afk_enabled or sleeping then
        return 0
    end
    local timeout = settings.afk_timeout or DEFAULT_TIMEOUT
    local remaining = timeout - (os.clock() - still_since)
    if remaining < 0 then remaining = 0 end
    return remaining
end

-- Clears the timer and wakes, silently. Called on job change and on /sk start.
function afk.reset()
    last_positions = {}
    still_since = os.clock()
    sleeping = false
end

return afk
