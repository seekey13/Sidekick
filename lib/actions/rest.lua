--[[
    Rest action
    Handles automatic MP recovery through resting (/heal on)
    - Starts resting when conditions are met (not moving, not casting, timer elapsed)
    - Stops resting if party member moves too far away
]]--

local common = require('lib.core.common')

local rest = {}

-- True when a follow target is set and the matching party member is farther than
-- rest_distance. Shared by both the start and stop checks.
local function follow_target_too_far(settings, game_state)
    local follow_target = settings.follow_target
    if not (follow_target and game_state) then return false end
    local rest_distance = settings.rest_distance or 7
    for i = 1, 5 do
        local member = game_state.party[i]
        if member and member.name == follow_target then
            local distance = common.get_party_member_distance(i)
            return distance ~= nil and distance > rest_distance
        end
    end
    return false
end

-- Check if we should start resting
local function should_start_resting(settings, job_def)
    -- Only for MP-based jobs
    if not job_def or job_def.resource_type ~= 'mp' then
        common.reset_rest_timer()
        return false
    end
    
    -- Check if resting is enabled
    if not settings.rest_enabled then
        common.reset_rest_timer()
        return false
    end
    
    -- Already resting
    if common.is_resting() then
        common.reset_rest_timer()
        return false
    end
    
    -- Check if player is engaged in combat
    if common.is_engaged() then
        common.reset_rest_timer()
        return false
    end
    
    -- Check if player is moving or casting
    if common.is_player_moving() then
        common.reset_rest_timer()
        return false
    end
    
    if common.is_casting() then
        common.reset_rest_timer()
        return false
    end
    
    -- Check if MP is below 100%
    local game_state = common.game_state
    local player     = game_state and game_state.player
    local mp_percent = player and player.mpp or 0
    if mp_percent >= 100 then
        common.reset_rest_timer()
        return false
    end

    -- Check distance to follow target (if set)
    if follow_target_too_far(settings, game_state) then
        common.reset_rest_timer()
        return false
    end

    -- All base conditions are met (not moving, not casting, MP not full, distance ok)
    local current_time = os.clock()
    local rest_timer = settings.rest_timer or 5
    
    -- Start the conditions timer if not already started
    if common.get_rest_timer() == 0 then
        common.set_rest_timer(current_time)
        return false
    end
    
    -- Check if enough time has passed since conditions became favorable
    local time_since_conditions = current_time - common.get_rest_timer()
    if time_since_conditions < rest_timer then
        return false
    end
    
    -- Timer has elapsed, can start resting
    return true
end

-- Check if we should stop resting
local function should_stop_resting(settings, job_def)
    -- Not resting, nothing to stop
    if not common.is_resting() then
        return false
    end
    
    -- Check if MP is full
    local game_state = common.game_state
    local player     = game_state and game_state.player
    local mp_percent = player and player.mpp or 0
    if mp_percent >= 100 then
        return true
    end

    -- Check distance to follow target (if set)
    if follow_target_too_far(settings, game_state) then
        return true
    end

    -- No reason to stop resting
    return false
end

-- Execute rest action
function rest.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Only for MP-based jobs
    if not job_def or job_def.resource_type ~= 'mp' then
        return nil
    end
    
    -- Check if resting is enabled
    if not settings.rest_enabled then
        return nil
    end
    
    -- Normal Mode: Track our own resting state
    -- If currently resting, check if movement or casting started
    if common.is_resting() then
        if common.is_player_moving() then
            common.set_resting(false)
            common.reset_rest_timer()
            return {
                command = '/heal off',
                description = 'Stopping rest (movement detected)'
            }
        end
        
        if common.is_casting() then
            common.set_resting(false)
            common.reset_rest_timer()
            return {
                command = '/heal off',
                description = 'Stopping rest (casting detected)'
            }
        end
    end
    
    -- Check if we should stop resting (priority check)
    if should_stop_resting(settings, job_def) then
        common.set_resting(false)
        common.reset_rest_timer()
        return {
            command = '/heal off',
            description = 'Stopping rest (distance or MP full)'
        }
    end
    
    -- Check if we should start resting
    if should_start_resting(settings, job_def) then
        local state_snap = common.game_state
        local mp_percent = state_snap and state_snap.player and state_snap.player.mpp or 0
        common.set_resting(true)
        common.reset_rest_timer()  -- Reset after starting
        return {
            command = '/heal on',
            description = string.format('Starting rest to recover MP (%.1f%%)', mp_percent)
        }
    end
    
    return nil
end

return rest
