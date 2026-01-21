--[[
    Resource management for Medic
    Handles MP/TP checking and cooldown tracking
]]--

local resource = {}

local AshitaCore = AshitaCore

-- Cooldown tracking
local recast_timers = {}

-- Post-recast delay tracking (when recast hits 0, track when it became ready)
-- Format: {ability_123 = timestamp, spell_456 = timestamp}
local recast_ready_time = {}
local POST_RECAST_DELAY = 0.5  -- 0.5 second delay after recast hits 0

-- Helper function to check if recast timer is ready with post-delay
-- Args: key (string), timer (number)
-- Returns: boolean
local function is_recast_ready_with_delay(key, timer)
    if timer == 0 then
        -- Recast timer is 0, check if we've waited long enough
        if not recast_ready_time[key] then
            -- First time seeing it at 0, record the time
            recast_ready_time[key] = os.clock()
            return false  -- Not ready yet, need to wait POST_RECAST_DELAY
        end
        
        -- Check if enough time has passed since it hit 0
        local elapsed = os.clock() - recast_ready_time[key]
        if elapsed >= POST_RECAST_DELAY then
            recast_ready_time[key] = nil  -- Clear tracking
            return true  -- Ready!
        end
        return false  -- Still waiting
    else
        -- Timer is not 0, clear any tracking
        recast_ready_time[key] = nil
        return false
    end
end

--[[
    Resource Checking
]]--

function resource.has_resource(resource_type, amount)
    if resource_type == 'mp' then
        local party = AshitaCore:GetMemoryManager():GetParty()
        if not party then return false end
        local current_mp = party:GetMemberMP(0)
        return current_mp >= amount
    elseif resource_type == 'tp' then
        local party = AshitaCore:GetMemoryManager():GetParty()
        if not party then return false end
        local current_tp = party:GetMemberTP(0)
        return current_tp >= amount
    end
    return false
end

function resource.get_resource(resource_type)
    if resource_type == 'mp' then
        local party = AshitaCore:GetMemoryManager():GetParty()
        if not party then return 0 end
        return party:GetMemberMP(0)
    elseif resource_type == 'tp' then
        local party = AshitaCore:GetMemoryManager():GetParty()
        if not party then return 0 end
        return party:GetMemberTP(0)
    end
    return 0
end

--[[
    Cooldown/Recast Tracking
]]--

function resource.is_ability_ready(ability_id)
    if not ability_id then return true end
    
    local recast_mgr = AshitaCore:GetMemoryManager():GetRecast()
    if not recast_mgr then return false end
    
    -- Loop through recast slots to find our ability by timer ID
    for i = 0, 31 do
        local ok_id, timer_id = pcall(function()
            return recast_mgr:GetAbilityTimerId(i)
        end)
        
        if ok_id and timer_id == ability_id then
            -- Found our ability, check its timer
            local ok_timer, timer = pcall(function()
                return recast_mgr:GetAbilityTimer(i)
            end)
            
            if not ok_timer then
                return false
            end
            
            -- Timer is in 60ths of a second, 0 means ready
            local key = 'ability_' .. ability_id
            return is_recast_ready_with_delay(key, timer)
        end
    end
    
    -- Ability not found in recast array, assume it's ready
    return true
end

function resource.get_ability_recast(ability_id)
    if not ability_id then return 0 end
    
    local recast_mgr = AshitaCore:GetMemoryManager():GetRecast()
    if not recast_mgr then return 0 end
    
    return recast_mgr:GetAbilityTimer(ability_id)
end

function resource.is_spell_ready(spell_recast_id)
    if not spell_recast_id then return true end
    
    local recast_mgr = AshitaCore:GetMemoryManager():GetRecast()
    if not recast_mgr then return false end
    
    local recast_time = recast_mgr:GetSpellTimer(spell_recast_id)
    local key = 'spell_' .. spell_recast_id
    
    return is_recast_ready_with_delay(key, recast_time)
end

function resource.get_spell_recast(spell_recast_id)
    if not spell_recast_id then return 0 end
    
    local recast_mgr = AshitaCore:GetMemoryManager():GetRecast()
    if not recast_mgr then return 0 end
    
    return recast_mgr:GetSpellTimer(spell_recast_id)
end

--[[
    Custom recast tracking (for abilities that share cooldowns)
]]--

function resource.set_custom_recast(key, duration)
    recast_timers[key] = os.clock() + duration
end

function resource.is_custom_recast_ready(key)
    if not recast_timers[key] then return true end
    return os.clock() >= recast_timers[key]
end

function resource.get_custom_recast(key)
    if not recast_timers[key] then return 0 end
    local remaining = recast_timers[key] - os.clock()
    return math.max(0, remaining)
end

function resource.clear_custom_recast(key)
    recast_timers[key] = nil
end

return resource
