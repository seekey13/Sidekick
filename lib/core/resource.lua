--[[
    Resource management for Medic
    Handles MP/TP checking and cooldown tracking
]]--

local resource = {}

local AshitaCore = AshitaCore

-- Cooldown tracking
local recast_timers = {}

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
            return timer == 0
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
    return recast_time == 0
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
