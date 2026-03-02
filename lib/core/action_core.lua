--[[
    Action core: shared ability candidacy and execution helpers.
    Consolidates the repeated blocked → resource → cooldown → build-command
    pattern used by heal_aoe, heal_pet, heal, and recover.
]]--

local action_core = {}

local common   = require('lib.core.common')
local resource = require('lib.core.resource')

-- Determine if an ability's command is a spell (/ma ...) or a job ability.
-- Accepts both string and function commands; probes function commands with a
-- test build against party index 0.
local function is_spell_command(ability)
    if type(ability.command) == 'string' then
        return ability.command:match('^/ma%s') ~= nil
    elseif type(ability.command) == 'function' then
        local test = common.build_ability_command(ability, 0, nil)
        return test ~= nil and test:match('^/ma%s') ~= nil
    end
    return false
end

--[[
    Check whether a single ability is currently usable.
    Evaluates in order: status-blocked → resource → cooldown.
    Returns: is_ready (bool), reason (string or nil)
]]--
function action_core.is_usable(ability, job_def)
    -- 1. Blocked by a status ailment?
    local blocked_by = common.is_command_blocked(ability.command)
    if blocked_by then
        return false, 'blocked by ' .. blocked_by
    end

    -- 2. Enough resource?
    local res_type = ability.resource_type or job_def.resource_type
    if not resource.has_resource(res_type, ability.cost) then
        return false, 'insufficient ' .. res_type
    end

    -- 3. Off cooldown?
    if ability.id then
        if is_spell_command(ability) then
            if not resource.is_spell_ready(ability.id) then
                local secs = resource.get_spell_recast(ability.id) / 60.0
                return false, string.format('spell cooldown (%.1fs)', secs)
            end
        else
            if not resource.is_ability_ready(ability.id) then
                return false, 'ability cooldown'
            end
        end
    end

    return true, nil
end

--[[
    Filter a list of abilities down to those that pass is_usable.
    Logs skipped abilities at debug level when tag is provided.
    Returns a new table of usable abilities (preserves original order).
]]--
function action_core.filter_usable(abilities, job_def, tag)
    local usable = {}
    for _, ability in ipairs(abilities) do
        local ok, reason = action_core.is_usable(ability, job_def)
        if ok then
            table.insert(usable, ability)
        elseif tag then
            common.debugf('%s %s: %s', tag, ability.name, reason)
        end
    end
    return usable
end

--[[
    Find the first usable ability, build its command, and return an action
    result table  { command, description }.  Returns nil if nothing is usable.

    abilities      – already level/settings-filtered ability list
    job_def        – job definition table (for resource_type fallback)
    settings       – settings table (forwarded to build_ability_command)
    tag            – debug prefix string, e.g. '[HEAL_AOE]'
    party_index    – nil for AOE/self-targeted abilities, number for party member
    description_fn – function(ability) → string  (optional; falls back to ability.name)
]]--
function action_core.first_command(abilities, job_def, settings, tag, party_index, description_fn)
    for _, ability in ipairs(abilities) do
        local ok, reason = action_core.is_usable(ability, job_def)
        if not ok then
            if tag then common.debugf('%s %s: %s', tag, ability.name, reason) end
        else
            local command = common.build_ability_command(ability, party_index, settings)
            if command then
                if tag then common.debugf('%s >>> Using %s', tag, ability.name) end
                return {
                    command     = command,
                    description = description_fn and description_fn(ability) or ability.name,
                }
            end
        end
    end
    return nil
end

return action_core
