--[[
    Roll action module (Corsair)

    Maintains two configured Phantom Rolls and Double-Ups each one until it hits
    its lucky number or the configured hit threshold. Roll totals are not readable
    from memory, so they come from the 0x028 action packet (see
    roll.handle_action_packet at the bottom of this file).

    Deliberately NOT gated on being engaged -- rolls fire out of combat too.
]]--

local roll = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- Buff ids (status_effects.sql)
local BUST_BUFF_ID      = 309  -- Bust: costs you a roll slot until it wears
local DOUBLE_UP_BUFF_ID = 308  -- Double-Up Chance: the window in which Double-Up is usable

-- Action-packet message ids (src/map/enums/msg_basic.h)
local MSG_ROLL_MAIN       = 420
local MSG_ROLL_SUB        = 421
local MSG_DOUBLEUP        = 424
local MSG_DOUBLEUP_BUST   = 426
local MSG_DOUBLEUP_BUST_S = 427

-- Module-level state (transient, cleared on reload)
local roll_state = {
    roll1 = {
        total = 0,
        last_action_time = 0,
        expecting_double_up = false,
        is_stable = false,  -- Set when we hit lucky/threshold and have the buff
    },
    roll2 = {
        total = 0,
        last_action_time = 0,
        expecting_double_up = false,
        is_stable = false,
    },
    last_double_up_time = 0,  -- Global double-up cooldown
}

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Find a roll ability by name in a roll list (raw job list, or a level-filtered one)
local function find_roll_ability(roll_list, roll_name)
    if not roll_list or not roll_name or roll_name == '' then return nil end
    for _, ability in ipairs(roll_list) do
        if ability.name == roll_name then
            return ability
        end
    end
    return nil
end

-- Roll slots available right now: Bust eats one of the two.
local function get_available_roll_slots(player_buffs)
    return action_core.has_any_buff(player_buffs, BUST_BUFF_ID) and 1 or 2
end

-- Count how many of the configured rolls are currently active on the player
local function count_active_configured_rolls(player_buffs, roll1_ability, roll2_ability)
    local count = 0
    if roll1_ability and action_core.has_any_buff(player_buffs, roll1_ability.buff_id) then
        count = count + 1
    end
    if roll2_ability and action_core.has_any_buff(player_buffs, roll2_ability.buff_id) then
        count = count + 1
    end
    return count
end

-- Should we Double-Up this roll? (unstable, buff up, total known and below target)
local function should_double_up_roll(settings, roll_num, roll_ability, player_buffs)
    if not roll_ability then
        common.debugf('[ROLL] should_double_up_roll Roll%d: no ability', roll_num)
        return false
    end

    local state = roll_num == 1 and roll_state.roll1 or roll_state.roll2

    common.debugf('[ROLL] should_double_up_roll Roll%d (%s): total=%d, stable=%s, expecting_du=%s',
        roll_num, roll_ability.name, state.total, tostring(state.is_stable), tostring(state.expecting_double_up))

    -- Must not be stable yet
    if state.is_stable then
        common.debugf('[ROLL] should_double_up_roll Roll%d: already stable', roll_num)
        return false
    end

    -- Must be inside the Double-Up window
    if not action_core.has_any_buff(player_buffs, DOUBLE_UP_BUFF_ID) then
        common.debugf('[ROLL] should_double_up_roll Roll%d: no Double-Up buff (%d)', roll_num, DOUBLE_UP_BUFF_ID)
        return false
    end

    -- Must have the roll buff active
    if not action_core.has_any_buff(player_buffs, roll_ability.buff_id) then
        common.debugf('[ROLL] should_double_up_roll Roll%d: no roll buff (%d)', roll_num, roll_ability.buff_id)
        return false
    end

    -- Must have a valid total (from packet)
    if state.total == 0 then
        common.debugf('[ROLL] should_double_up_roll Roll%d: total is 0, waiting for packet', roll_num)
        return false
    end

    -- Stop on the lucky number
    if state.total == roll_ability.lucky then
        common.debugf('[ROLL] should_double_up_roll Roll%d: hit lucky number %d', roll_num, roll_ability.lucky)
        return false
    end

    -- Stop at/above the configured hit threshold
    local hit_threshold = settings.roll_hit_threshold or 5
    if state.total >= hit_threshold then
        common.debugf('[ROLL] should_double_up_roll Roll%d: at/above threshold (%d >= %d)', roll_num, state.total, hit_threshold)
        return false
    end

    -- Never double-up at 11 (12 busts)
    if state.total >= 11 then
        common.debugf('[ROLL] should_double_up_roll Roll%d: at/above 11', roll_num)
        return false
    end

    common.debugf('[ROLL] should_double_up_roll Roll%d: SHOULD DOUBLE-UP', roll_num)
    return true
end

-- Mark a roll stable (hit lucky or threshold while the buff is up)
local function mark_roll_stable(roll_num, roll_ability, settings, player_buffs)
    local state = roll_num == 1 and roll_state.roll1 or roll_state.roll2

    if not action_core.has_any_buff(player_buffs, roll_ability.buff_id) then
        return  -- Can't be stable without the buff
    end

    local hit_threshold = settings.roll_hit_threshold or 5
    if state.total == roll_ability.lucky or state.total >= hit_threshold then
        state.is_stable = true
        state.expecting_double_up = false  -- Clear double-up flag when stable
        common.debugf('[ROLL] Roll%d (%s) is now stable at total %d (lucky=%d, threshold=%d)',
            roll_num, roll_ability.name, state.total, roll_ability.lucky, hit_threshold)
    end
end

-- ============================================================================
-- Main Execute Function
-- ============================================================================

function roll.execute(settings, job_def, main_level, sub_level, player_resource)
    if not settings.roll_enabled then
        return nil
    end

    if not job_def or not job_def.abilities or not job_def.abilities.roll then
        return nil
    end

    local player_buffs = common.game_state.player.buffs or {}
    local current_time = os.clock()

    -- Level filter here (not in the packet handler): a saved roll name the player
    -- can no longer use must never be cast, but its packets still decode fine.
    local available = common.filter_abilities_by_level(job_def.abilities.roll, settings, main_level, sub_level, job_def)
    local roll1_ability = find_roll_ability(available, settings.roll1_name)
    local roll2_ability = find_roll_ability(available, settings.roll2_name)

    -- Mark rolls that have reached lucky/threshold so we stop doubling them
    if roll1_ability then mark_roll_stable(1, roll1_ability, settings, player_buffs) end
    if roll2_ability then mark_roll_stable(2, roll2_ability, settings, player_buffs) end

    -- Priority 1: Double-Up an unstable roll (Roll1 first, then Roll2)
    for roll_num = 1, 2 do
        -- Explicit on both arms: `n == 1 and roll1 or roll2` would fall through to
        -- Roll2 when only Roll2 is configured, and evaluate it as Roll1.
        local roll_ability = (roll_num == 1) and roll1_ability or (roll_num == 2) and roll2_ability or nil

        if roll_ability and should_double_up_roll(settings, roll_num, roll_ability, player_buffs) then
            local state = roll_num == 1 and roll_state.roll1 or roll_state.roll2

            -- 1 second after the initial roll, then 6 seconds between double-ups.
            -- Both timers are in-game proven -- do not tighten them.
            local ready_after_roll = (current_time - state.last_action_time) >= 1
            local ready_after_du   = (roll_state.last_double_up_time == 0)
                or ((current_time - roll_state.last_double_up_time) >= 6)

            if ready_after_roll and ready_after_du and not common.is_command_blocked('/ja "Double-Up" <me>') then
                common.debugf('[ROLL] Attempting Double-Up for Roll%d (%s) at total %d',
                    roll_num, roll_ability.name, state.total)

                -- Only one roll may await a packet at a time
                roll_state.roll1.expecting_double_up = false
                roll_state.roll2.expecting_double_up = false
                state.expecting_double_up = true

                return {
                    command     = '/ja "Double-Up" <me>',
                    description = string.format('Double-Up: %s (Total: %d)', roll_ability.name, state.total),
                }
            end
        end
    end

    -- Priority 2: cast a missing roll, unless we're at slot capacity
    local active_rolls = count_active_configured_rolls(player_buffs, roll1_ability, roll2_ability)
    if active_rolls >= get_available_roll_slots(player_buffs) then
        common.debugf('[ROLL] Blocked from casting - at capacity')
        return nil
    end

    local has_roll1_buff = roll1_ability and action_core.has_any_buff(player_buffs, roll1_ability.buff_id) or false
    local has_roll2_buff = roll2_ability and action_core.has_any_buff(player_buffs, roll2_ability.buff_id) or false

    -- Which roll are we casting? Roll1 if it's missing; otherwise Roll2, but only
    -- once Roll1 exists and is no longer awaiting packets (one roll in flight).
    local cast_num, cast_ability
    if roll1_ability and not has_roll1_buff then
        cast_num, cast_ability = 1, roll1_ability
    elseif has_roll1_buff and not roll_state.roll1.expecting_double_up and roll2_ability and not has_roll2_buff then
        cast_num, cast_ability = 2, roll2_ability
    end

    if cast_ability then
        local state = cast_num == 1 and roll_state.roll1 or roll_state.roll2
        -- Throttle: 2 seconds between roll casts (in-game proven)
        if (current_time - state.last_action_time) >= 2 then
            -- is_usable covers Phantom Roll's shared recast (193) and Amnesia
            local result = action_core.try_use(cast_ability, job_def, settings, nil,
                string.format('Casting: %s', cast_ability.name))
            if result then
                -- Reset state and mark that we're expecting this roll's packet value
                state.total = 0
                state.expecting_double_up = true
                state.is_stable = false
                state.last_action_time = current_time
                return result
            end
            common.debugf('[ROLL] Roll%d (%s) not usable yet', cast_num, cast_ability.name)
        end
    end

    return nil
end

-- ============================================================================
-- Packet Handler
-- ============================================================================
--[[
    Roll totals come out of the already-parsed 0x028 action packet
    (lib/core/parse_packets.lua), whose bit layout matches the server packer at
    src/map/packets/s2c/0x028_battle2.cpp.

    For a roll, on the caster's OWN target entry:
        packet.Type    = 6      -- cmd_no: job ability
        packet.Param            -- cmd_arg: the roll's ability id. On a Double-Up the
                                   server rewrites it to the UNDERLYING roll's id
                                   (action:actionID(prevAbility:getID())), so every
                                   packet self-identifies which roll it belongs to.
        action.Info             -- the die value 1-6, set by action:info() in
                                   scripts/globals/job_utils/corsair.lua. Only present
                                   on the caster's own entry.
        action.Param            -- the running total (the Lua ability's return value)
        action.Message          -- 420/421 roll, 424 double-up, 426/427 bust
]]--

function roll.handle_action_packet(packet, settings, job_def)
    if not settings or not settings.roll_enabled or not packet then
        return
    end

    -- cmd_no 6 = job ability
    if packet.Type ~= 6 then
        return
    end

    -- Actor must be us -- party members' rolls come through here too
    local party = common.get_party()
    local player_id = party and party:GetMemberServerId(0)
    if not player_id or packet.UserId ~= player_id then
        return
    end

    -- The die value only exists on the caster's own target entry
    local action
    for _, target in ipairs(packet.Targets or {}) do
        if target.Id == player_id then
            action = target.Actions and target.Actions[1]
            break
        end
    end
    if not action then
        return
    end

    -- Which configured slot is this? cmd_arg carries the roll's ability id.
    local roll_list = job_def and job_def.abilities and job_def.abilities.roll
    local roll_num, roll_ability
    for n = 1, 2 do
        local ability = find_roll_ability(roll_list, n == 1 and settings.roll1_name or settings.roll2_name)
        if ability and ability.action_id == packet.Param then
            roll_num, roll_ability = n, ability
            break
        end
    end
    if not roll_num then
        return
    end

    local state = roll_num == 1 and roll_state.roll1 or roll_state.roll2
    local total = action.Param
    local die   = action.Info
    local msg   = action.Message

    -- Bust: the slot is spent until the Bust status wears off
    if msg == MSG_DOUBLEUP_BUST or msg == MSG_DOUBLEUP_BUST_S or total > 11 then
        state.total = 0
        state.expecting_double_up = false
        state.is_stable = false
        common.printf('[Roll] Bust: %s', roll_ability.name)
        return
    end

    -- Anything else (fail, already-active, ...) carries no usable total
    if msg ~= MSG_ROLL_MAIN and msg ~= MSG_ROLL_SUB and msg ~= MSG_DOUBLEUP then
        return
    end

    state.total = total

    if msg == MSG_DOUBLEUP then
        roll_state.last_double_up_time = os.clock()
        common.printf('[Roll] Double-Up %s: %d (Total: %d)', roll_ability.name, die, total)
    else
        common.printf('[Roll] %s: %d (Total: %d)', roll_ability.name, die, total)
    end

    -- Stop doubling once we hit lucky / threshold / 11
    local hit_threshold = settings.roll_hit_threshold or 5
    if total == roll_ability.lucky or total >= hit_threshold or total >= 11 then
        state.expecting_double_up = false
        common.debugf('[ROLL] Roll%d stopped doubling: total=%d, lucky=%d, threshold=%d',
            roll_num, total, roll_ability.lucky, hit_threshold)
    end
end

-- ============================================================================
-- State Reset / Inspection
-- ============================================================================

-- Called when a roll selection changes in the config UI, so a stale packet total
-- can't leak into the newly picked roll.
function roll.reset_state()
    for _, state in ipairs({ roll_state.roll1, roll_state.roll2 }) do
        state.total = 0
        state.last_action_time = 0
        state.expecting_double_up = false
        state.is_stable = false
    end

    roll_state.last_double_up_time = 0

    common.debugf('[ROLL] State reset')
end

-- Current roll state (debug/UI display)
function roll.get_state()
    return roll_state
end

return roll
