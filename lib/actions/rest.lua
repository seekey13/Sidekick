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
        return false
    end
    
    -- Check if resting is enabled
    if not settings.rest_enabled then
        return false
    end
    
    -- Already resting
    if common.is_resting() then
        return false
    end
    
    -- Check if player is moving or casting
    if common.is_player_moving() then
        return false
    end
    
    if common.is_casting() then
        return false
    end
    
    -- Check if enough time has passed since last rest attempt
    local current_time = os.clock()
    local rest_timer = settings.rest_timer or 5
    if current_time - last_rest_time < rest_timer then
        return false
    end
    
    -- Check if MP is below 100%
    local party = common.get_party()
    if not party then
        return false
    end
    
    local mp = party:GetMemberMP(0)
    local max_mp = party:GetMemberMPMax(0)
    if not mp or not max_mp or mp >= max_mp then
        return false
    end
    
    -- All conditions met, can start resting
    return true
end

-- Check if we should stop resting
local function should_stop_resting(settings, job_def)
    -- Not resting, nothing to stop
    if not common.is_resting() then
        return false
    end
    
    -- Check if MP is full
    local party = common.get_party()
    if not party then
        return false
    end
    
    local mp = party:GetMemberMP(0)
    local max_mp = party:GetMemberMPMax(0)
    if mp and max_mp and mp >= max_mp then
        common.debugf('[Rest] MP full, stopping rest')
        return true
    end
    
    -- Check if any party member is below resting threshold
    local rest_threshold = settings.rest_threshold or 70
    
    -- Check player (P0)
    local player_hp_pct = common.get_party_member_hp_percent(0)
    if player_hp_pct < rest_threshold then
        common.debugf('[Rest] Player HP %d%% < %d%%, stopping rest', player_hp_pct, rest_threshold)
        return true
    end
    
    -- Check party members (P1-P5)
    for i = 1, 5 do
        if common.is_party_member_active(i) then
            local member_hp_pct = common.get_party_member_hp_percent(i)
            if member_hp_pct and member_hp_pct < rest_threshold then
                local member_name = common.get_party_member_name(i) or ('P' .. i)
                common.debugf('[Rest] %s HP %d%% < %d%%, stopping rest', member_name, member_hp_pct, rest_threshold)
                return true
            end
        end
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
        common.debugf('[Rest] Starting rest')
        common.set_resting(true)
        last_rest_time = os.clock()
        return {
            command = '/heal on',
            description = 'Starting rest to recover MP'
        }
    end
    
    return nil
end

return rest
