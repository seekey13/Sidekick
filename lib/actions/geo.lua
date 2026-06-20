--[[
    Geo action module
    Handles Full Circle when player is far from pet luopan
    Handles Entrust + Indi spell casting on party members
]]--

local geo = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- Tracks whether the current luopan was placed by a Geo-bt (enemy debuff) cast.
-- Geo-bt owns the single luopan during combat; this flag lets us (a) keep the
-- distance-based Full Circle from dismissing our debuff luopan, and (b) Full
-- Circle it once combat ends. Module-scoped so it persists across execute() calls.
-- Caveat: an addon reload mid-combat resets this to false while a
-- debuff luopan is still out, costing one redundant Full Circle + recast as the
-- ownership is re-established.
local geo_bt_pending = false

-- Returns the Geo-bt ability the user wants maintained in combat, or nil.
-- Honors the selected_Geo-bt dropdown (falls back to the highest-cost available
-- debuff). filter_abilities_by_level applies the level + <bt> combat gate, so
-- this returns nil when out of combat or under-leveled.
local function get_selected_geo_bt(job_def, settings, main_level, sub_level)
    local candidates = {}
    for _, ability in ipairs(job_def.abilities.geo or {}) do
        if ability.group == 'Geo-bt' then
            table.insert(candidates, ability)
        end
    end
    local available = common.filter_abilities_by_level(candidates, settings, main_level, sub_level, job_def)
    if #available == 0 then return nil end
    local selected_name = settings['selected_Geo-bt']
    if selected_name then
        for _, ability in ipairs(available) do
            if ability.name == selected_name then return ability end
        end
        return nil
    end
    return available[1]
end

-- Build a Full Circle action result if it is usable right now. Callers ensure a
-- pet/luopan is present. Returns { command, description } or nil.
local function try_full_circle(job_def, settings, main_level, sub_level, description)
    local geo_abilities = common.filter_abilities_by_level(job_def.abilities.geo or {}, settings, main_level, sub_level, job_def)
    for _, ability in ipairs(geo_abilities) do
        if ability.name == 'Full Circle' then
            if common.is_command_blocked(ability.command) then return nil end
            local resource_type = ability.resource_type or job_def.resource_type
            if ability.id and action_core.has_resource(resource_type, ability.cost) and action_core.is_ability_ready(ability.id) then
                local command = common.build_ability_command(ability, 0)
                if command then
                    return { command = command, description = description }
                end
            end
            return nil
        end
    end
    return nil
end

function geo.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if geo action is enabled
    if not settings.geo_enabled then
        return nil
    end

    -- Do not perform geo actions while resting
    if common.is_resting() then
        return nil
    end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end
    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level

    -- Required lazily (not at module load) to avoid a circular require; shared by
    -- the Full Circle target lookup and the Entrust logic below.
    local ui_config = require('lib.ui.config')

    -- ========================================================================
    -- Geo-bt Logic (enemy <bt> debuffs)
    -- The single luopan is claimed by Geo-bt during combat and dismissed with
    -- Full Circle when combat ends. The enemy debuff itself is unreadable, so
    -- an active luopan of our own is the "already applied" signal.
    -- ========================================================================
    local geo_bt     = get_selected_geo_bt(job_def, settings, derived_main_level, derived_sub_level)
    local in_combat  = common.is_combat()
    local has_luopan = common.targets.get_pet() ~= nil

    -- Our debuff luopan is gone (expired / battle target died): clear tracking.
    if geo_bt_pending and not has_luopan then
        geo_bt_pending = false
    end

    -- Combat is over but our Geo-bt luopan is still out: dismiss it so the
    -- luopan is freed for Geo <me> buffs again.
    if geo_bt_pending and not in_combat and has_luopan then
        local fc = try_full_circle(job_def, settings, derived_main_level, derived_sub_level,
            'Full Circle (dismissing Geo-bt luopan, combat ended)')
        if fc then return fc end
    end

    -- In combat with a Geo-bt debuff selected: make sure the luopan is ours.
    if geo_bt and in_combat then
        if has_luopan and not geo_bt_pending then
            -- A non-debuff luopan (e.g. a Geo <me> buff) holds the slot; take it
            -- over so Geo-bt can claim the luopan for this fight.
            local fc = try_full_circle(job_def, settings, derived_main_level, derived_sub_level,
                'Full Circle (Geo-bt taking the luopan)')
            if fc then return fc end
        elseif not has_luopan then
            local result = action_core.first_command({ geo_bt }, job_def, settings, 0,
                function(ability) return string.format('Geo-bt: %s on battle target', ability.name) end)
            if result then
                geo_bt_pending = true
                return result
            end
        end
        -- else: our debuff luopan is already up — nothing to do.
    end

    -- ========================================================================
    -- Full Circle Logic
    -- ========================================================================

    -- Check if player has a pet (only needed for Full Circle). Skip while our
    -- own Geo-bt luopan is out so the distance check can't dismiss the debuff.
    if common.targets.get_pet() and not geo_bt_pending then
        -- Determine which target currently holds the Geo bubble. The Geo group
        -- is single-select (one luopan), so at most one target is enabled.
        -- Distance is measured from that target; if none is selected we skip
        -- the distance-based Full Circle entirely.
        local party_buffs = ui_config.get_party_buffs()
        local geo_targets = party_buffs and party_buffs['Geo']
        local selected_target_index = nil  -- 0 = ME, 1-5 = party member
        if geo_targets then
            for idx, is_on in pairs(geo_targets) do
                if is_on == true and type(idx) == 'number' and idx >= 0 and idx <= 5 then
                    selected_target_index = idx
                    break
                end
            end
        end

        -- Measure luopan distance from the selected Geo target (skip if none).
        local pet_distance = selected_target_index ~= nil
            and common.get_pet_distance_from_member(selected_target_index)
            or nil
        if pet_distance then
            -- Get the distance threshold from settings (default 10 yalms)
            local distance_threshold = settings.geo_distance_threshold or 10
            
            -- Check if pet is too far. Use try_full_circle so only Full Circle is
            -- considered -- the geo ability list now also holds high-cost Geo-bt
            -- debuffs, which would otherwise sort ahead of Full Circle here.
            if pet_distance > distance_threshold then
                local fc = try_full_circle(job_def, settings, derived_main_level, derived_sub_level,
                    string.format('Using Full Circle (Pet distance: %.1f yalms)', pet_distance))
                if fc then return fc end
            end
        end
    end
    
    -- ========================================================================
    -- Entrust Logic
    -- ========================================================================
    
    -- Get entrust configuration from config UI
    local entrust_config = ui_config.get_entrust_config()
    
    if entrust_config then
        -- Check if Entrust ability is enabled in settings
        local entrust_enabled_key = 'disabled_Entrust'
        if settings[entrust_enabled_key] == true then
            return nil
        end
        
        local target_index = entrust_config.target_index  -- 1-5 for P1-P5
        local spell_name = entrust_config.spell_name
        
        -- Find the spell ability by name
        local selected_spell = nil
        if job_def.abilities.buff then
            for _, ability in ipairs(job_def.abilities.buff) do
                if ability.group == 'Indi' and ability.name == spell_name then
                    -- Check level requirements
                    if ability.level and ability.level <= derived_main_level then
                        if common.has_spell_learned(ability) then
                            selected_spell = ability
                            break
                        end
                    end
                end
            end
        end
        
        if not selected_spell then
            return nil
        end
        
        -- Convert party index (1-5) to entity target index via game state
        local party_member = state.party[target_index]
        if not party_member then
            return nil
        end

        local entity_target_index = party_member.target_index
        if not entity_target_index or entity_target_index == 0 then
            return nil
        end
        
        -- Check if target party member is valid and in range (20 yalms)
        local target_in_range = common.is_in_range(entity_target_index, 20)
        
        if not target_in_range then
            return nil
        end
        
        -- Check if we have the Entrust buff (584)
        local has_entrust_buff = false
        for _, active_buff in ipairs(player.buffs) do
            if active_buff == 584 then
                has_entrust_buff = true
                break
            end
        end
        
        if has_entrust_buff then
            -- We have Entrust buff, cast the Indi spell on party member
            -- Check if spell is blocked by status ailments
            local blocked_by = common.is_command_blocked(selected_spell.command)
            if blocked_by then
                return nil
            end
            
            -- Check MP cost
            if not action_core.has_resource('mp', selected_spell.cost or 0) then
                return nil
            end
            
            -- Build command for party member target
            local command
            if type(selected_spell.command) == 'function' then
                command = selected_spell.command(target_index)
            else
                -- Replace <me> with <p#> in command
                command = selected_spell.command:gsub('<me>', '<p' .. target_index .. '>')
            end
            
            if command then
                return {
                    command = command,
                    description = string.format('Entrust: %s on P%d', selected_spell.name, target_index)
                }
            end
        else
            -- We don't have Entrust buff, use Entrust ability
            -- Use helper function to validate and build Entrust command
            -- Note: We create a temporary job_def with Entrust in target_modifier format
            local temp_job_def = {
                abilities = {
                    target_modifier = {}
                },
                resource_type = job_def.resource_type
            }
            
            -- Find Entrust in geo abilities and add to temp structure
            if job_def.abilities.geo then
                for _, ability in ipairs(job_def.abilities.geo) do
                    if ability.name == 'Entrust' then
                        table.insert(temp_job_def.abilities.target_modifier, ability)
                        break
                    end
                end
            end
            
            -- Use common helper to validate Entrust ability
            local entrust_result = common.check_target_modifier(temp_job_def, settings, derived_main_level, derived_sub_level)
            
            if entrust_result then
                -- Override description to include spell context
                entrust_result.description = string.format('Using Entrust (for %s on P%d)', selected_spell.name, target_index)
                return entrust_result
            end
        end
    end
    
    return nil
end

return geo
