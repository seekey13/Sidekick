--[[
    Rest action
    Handles automatic MP recovery through resting (/heal on)
    - Starts resting when conditions are met (not moving, not casting, timer elapsed)
    - Stops resting if any party member drops below threshold
]]--

local common = require('lib.core.common')

local rest = {}

-- State tracking
local last_rest_time = 0  -- Timestamp of last rest attempt

-- Check if we should start resting
local function should_start_resting(settings, job_def)
    -- Only for MP-based jobs
    if not job_def or job_def.resource_type ~= 'mp' then
        common.debugf('[Rest] should_start_resting: not MP job')
        return false
    end
    
    -- Check if resting is enabled
    if not settings.rest_enabled then
        common.debugf('[Rest] should_start_resting: not enabled')
        return false
    end
    
    -- Already resting
    if common.is_resting() then
        common.debugf('[Rest] should_start_resting: already resting')
        return false
    end
    
    -- Check if player is moving or casting
    if common.is_player_moving() then
        common.debugf('[Rest] should_start_resting: player moving')
        return false
    end
    
    if common.is_casting() then
        common.debugf('[Rest] should_start_resting: player casting')
        return false
    end
    
    -- Check if enough time has passed since last rest attempt
    local current_time = os.clock()
    local rest_timer = settings.rest_timer or 5
    local time_since_last = current_time - last_rest_time
    if time_since_last < rest_timer then
        common.debugf('[Rest] should_start_resting: timer not elapsed (%.1fs / %ds)', time_since_last, rest_timer)
        return false
    end
    
    -- Check if MP is below 100%
    local mp_percent = common.get_party_member_mp_percent(0)
    if mp_percent >= 100 then
        common.debugf('[Rest] should_start_resting: MP full (%.1f%%)', mp_percent)
        return false
    end
    
    -- All conditions met, can start resting
    common.debugf('[Rest] should_start_resting: YES (MP: %.1f%%, timer: %.1fs)', mp_percent, time_since_last)
    return true
end

-- Check if we should stop resting
local function should_stop_resting(settings, job_def)
    -- Not resting, nothing to stop
    if not common.is_resting() then
        return false
    end
    
    common.debugf('[Rest] should_stop_resting: checking conditions')
    
    -- Check if MP is full
    local mp_percent = common.get_party_member_mp_percent(0)
    if mp_percent >= 100 then
        common.debugf('[Rest] should_stop_resting: YES - MP full (%.1f%%)', mp_percent)
        return true
    end
    
    -- Check distance to P1 (first party member)
    local rest_distance = settings.rest_distance or 7
    if common.is_party_member_active(1) then
        local distance = common.get_party_member_distance(1)
        if distance and distance > rest_distance then
            local p1_name = common.get_party_member_name(1) or 'P1'
            common.debugf('[Rest] should_stop_resting: YES - Distance to %s is %.1f yalms > %d yalms', 
                p1_name, distance, rest_distance)
            return true
        elseif distance then
            common.debugf('[Rest] should_stop_resting: Distance to P1: %.1f yalms (threshold: %d)', 
                distance, rest_distance)
        end
    end
    
    -- Check if any party member is below resting threshold
    local rest_threshold = settings.rest_threshold or 70
    
    -- Check player (P0)
    local player_hp_pct = common.get_party_member_hp_percent(0)
    if player_hp_pct < rest_threshold then
        common.debugf('[Rest] should_stop_resting: YES - Player HP %d%% < %d%%', player_hp_pct, rest_threshold)
        return true
    end
    
    -- Check party members (P1-P5)
    for i = 1, 5 do
        if common.is_party_member_active(i) then
            local member_hp_pct = common.get_party_member_hp_percent(i)
            if member_hp_pct and member_hp_pct < rest_threshold then
                local member_name = common.get_party_member_name(i) or ('P' .. i)
                common.debugf('[Rest] should_stop_resting: YES - %s HP %d%% < %d%%', member_name, member_hp_pct, rest_threshold)
                return true
            end
        end
    end
    
    -- No reason to stop resting
    common.debugf('[Rest] should_stop_resting: NO - continue resting')
    return false
end

-- Execute rest action
function rest.execute(settings, job_def, main_level, sub_level, player_resource)
    common.debugf('[Rest] execute() called - job_type=%s, rest_enabled=%s, is_resting=%s', 
        tostring(job_def and job_def.resource_type or 'nil'),
        tostring(settings.rest_enabled),
        tostring(common.is_resting()))
    
    -- Only for MP-based jobs
    if not job_def or job_def.resource_type ~= 'mp' then
        common.debugf('[Rest] Skipping - not MP-based job')
        return nil
    end
    
    -- Check if resting is enabled
    if not settings.rest_enabled then
        common.debugf('[Rest] Skipping - rest not enabled in settings')
        return nil
    end
    
    -- If currently resting, check if movement or casting started
    if common.is_resting() then
        if common.is_player_moving() then
            common.debugf('[Rest] Movement detected while resting, stopping rest')
            common.set_resting(false)
            return {
                command = '/heal off',
                description = 'Stopping rest (movement detected)'
            }
        end
        
        if common.is_casting() then
            common.debugf('[Rest] Casting detected while resting, stopping rest')
            common.set_resting(false)
            return {
                command = '/heal off',
                description = 'Stopping rest (casting detected)'
            }
        end
    end
    
    -- Check if we should stop resting (priority check)
    if should_stop_resting(settings, job_def) then
        common.debugf('[Rest] Stopping rest')
        common.set_resting(false)
        return {
            command = '/heal off',
            description = 'Stopping rest (party needs healing or MP full)'
        }
    end
    
    -- Check if we should start resting
    if should_start_resting(settings, job_def) then
        local mp_percent = common.get_party_member_mp_percent(0)
        common.debugf('[Rest] Starting rest (MP: %.1f%%)', mp_percent)
        common.set_resting(true)
        last_rest_time = os.clock()
        return {
            command = '/heal on',
            description = string.format('Starting rest to recover MP (%.1f%%)', mp_percent)
        }
    end
    
    common.debugf('[Rest] No action needed')
    return nil
end

return rest
