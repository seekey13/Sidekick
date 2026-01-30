--[[
    Rest action
    Handles automatic MP recovery through resting (/heal on)
    - Starts resting when conditions are met (not moving, not casting, timer elapsed)
    - Stops resting if party member moves too far away
    - In PL Mode: sends /mst commands to PL player
]]--

local common = require('lib.core.common')
local targets = require('lib.core.targets')

local rest = {}

-- State tracking
local conditions_met_time = 0  -- Timestamp when rest conditions first became favorable

-- Check if we should start resting
local function should_start_resting(settings, job_def)
    -- Only for MP-based jobs
    if not job_def or job_def.resource_type ~= 'mp' then
        conditions_met_time = 0  -- Reset conditions timer
        return false
    end
    
    -- Check if resting is enabled
    if not settings.rest_enabled then
        conditions_met_time = 0  -- Reset conditions timer
        return false
    end
    
    -- Already resting
    if common.is_resting() then
        conditions_met_time = 0  -- Reset conditions timer
        return false
    end
    
    -- Check if player is engaged in combat
    if common.is_engaged() then
        conditions_met_time = 0  -- Reset conditions timer
        return false
    end
    
    -- Check if player is moving or casting
    if common.is_player_moving() then
        conditions_met_time = 0  -- Reset conditions timer
        return false
    end
    
    if common.is_casting() then
        conditions_met_time = 0  -- Reset conditions timer
        return false
    end
    
    -- Check if MP is below 100%
    local mp_percent = common.get_party_member_mp_percent(0)
    if mp_percent >= 100 then
        conditions_met_time = 0  -- Reset conditions timer
        return false
    end
    
    -- Check distance to follow target (if set)
    local rest_distance = settings.rest_distance or 7
    local follow_target = settings.follow_target
    
    -- In PL mode, use PL player entity for distance check
    if settings.pl_mode_enabled and settings.pl_connected_player then
        local player_entity = targets.get_me()
        local pl_entity = common.get_entity_by_name(settings.pl_connected_player)
        
        if player_entity and pl_entity then
            local distance = common.calculate_distance(player_entity, pl_entity)
            if distance and distance > rest_distance then
                conditions_met_time = 0  -- Reset conditions timer
                return false
            end
        end
    elseif follow_target then
        -- Normal mode: Find the party member by name
        local party = common.get_party()
        if party then
            for i = 1, 5 do
                if common.is_party_member_active(i) then
                    local member_name = common.get_party_member_name(i)
                    if member_name == follow_target then
                        local distance = common.get_party_member_distance(i)
                        if distance and distance > rest_distance then
                            conditions_met_time = 0  -- Reset conditions timer
                            return false
                        end
                        break
                    end
                end
            end
        end
    end
    
    -- All base conditions are met (not moving, not casting, MP not full, distance ok)
    local current_time = os.clock()
    local rest_timer = settings.rest_timer or 5
    
    -- Start the conditions timer if not already started
    if conditions_met_time == 0 then
        conditions_met_time = current_time
        return false
    end
    
    -- Check if enough time has passed since conditions became favorable
    local time_since_conditions = current_time - conditions_met_time
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
    local mp_percent = common.get_party_member_mp_percent(0)
    if mp_percent >= 100 then
        return true
    end
    
    -- Check distance to follow target (if set)
    local rest_distance = settings.rest_distance or 7
    
    -- In PL mode, use PL player entity for distance check
    if settings.pl_mode_enabled and settings.pl_connected_player then
        local player_entity = targets.get_me()
        local pl_entity = common.get_entity_by_name(settings.pl_connected_player)
        
        if player_entity and pl_entity then
            local distance = common.calculate_distance(player_entity, pl_entity)
            if distance and distance > rest_distance then
                return true
            end
        end
    else
        -- Normal mode: Check distance to follow target party member
        local follow_target = settings.follow_target
        if follow_target then
            -- Find the party member by name
            local party = common.get_party()
            if party then
                for i = 1, 5 do
                    if common.is_party_member_active(i) then
                        local member_name = common.get_party_member_name(i)
                        if member_name == follow_target then
                            local distance = common.get_party_member_distance(i)
                            if distance and distance > rest_distance then
                                return true
                            end
                            break
                        end
                    end
                end
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
    
    -- Check if resting is enabled
    if not settings.rest_enabled then
        return nil
    end
    
    -- Check if in PL mode
    local in_pl_mode = settings.pl_mode_enabled and settings.pl_connected_player
    
    -- PL Mode: Always check distance and send /heal off if exceeded
    if in_pl_mode then
        local rest_distance = settings.rest_distance or 7
        local player_entity = targets.get_me()
        local pl_entity = common.get_entity_by_name(settings.pl_connected_player)
        
        if player_entity and pl_entity then
            local distance = common.calculate_distance(player_entity, pl_entity)
            if distance and distance > rest_distance then
                local command = string.format('/mst %s /heal off', settings.pl_connected_player)
                return {
                    command = command,
                    description = string.format('Stopping PL rest (distance: %.1f > %.1f)', distance, rest_distance)
                }
            end
        end
        
        -- Check for casting (need healing)
        if common.is_casting() then
            local command = string.format('/mst %s /heal off', settings.pl_connected_player)
            return {
                command = command,
                description = 'Stopping PL rest (casting detected)'
            }
        end
        
        -- PL mode doesn't start resting (PL handles that)
        return nil
    end
    
    -- Normal Mode: Track our own resting state
    -- If currently resting, check if movement or casting started
    if common.is_resting() then
        if common.is_player_moving() then
            common.set_resting(false)
            conditions_met_time = 0  -- Reset conditions timer
            return {
                command = '/heal off',
                description = 'Stopping rest (movement detected)'
            }
        end
        
        if common.is_casting() then
            common.set_resting(false)
            conditions_met_time = 0  -- Reset conditions timer
            return {
                command = '/heal off',
                description = 'Stopping rest (casting detected)'
            }
        end
    end
    
    -- Check if we should stop resting (priority check)
    if should_stop_resting(settings, job_def) then
        common.set_resting(false)
        conditions_met_time = 0  -- Reset conditions timer
        return {
            command = '/heal off',
            description = 'Stopping rest (distance or MP full)'
        }
    end
    
    -- Check if we should start resting
    if should_start_resting(settings, job_def) then
        local mp_percent = common.get_party_member_mp_percent(0)
        common.set_resting(true)
        conditions_met_time = 0  -- Reset after starting
        return {
            command = '/heal on',
            description = string.format('Starting rest to recover MP (%.1f%%)', mp_percent)
        }
    end
    
    return nil
end

return rest
