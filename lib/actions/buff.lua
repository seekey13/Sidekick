--[[
    Buff maintenance action module
    Handles maintaining self and party buffs
]]--

local buff = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- Song AoE radius (yalms). Party members beyond this can't be covered by an area
-- song, so they don't count as "missing" and never force an endless recast.
local SONG_AOE_RANGE = 10

-- Config keys (group name, or ability name when ungrouped) for THIS job's songs.
-- Only these count toward a member's song slots. party_buff_config is shared
-- across every job and buff type (WHM cures/-na, Geo, etc.), so scanning all of
-- it would mistake unrelated self-buffs for songs and wrongly mark everyone's
-- slots full -- which silently kills every area song.
local function song_config_keys(job_def, settings)
    local keys = {}
    for _, ability in ipairs(job_def.abilities.buff or {}) do
        if ability.magic == 'song' then
            local grouped = ability.group and settings['ungrouped_' .. ability.group] ~= true
            keys[grouped and ability.group or ability.name] = true
        end
    end
    return keys
end

-- Party indices (0-5) whose song slots are already FULL of single-target
-- (Pianissimo) songs. A bard holds `song_limit` songs per member (2 main / 1
-- sub); once that many single-target SONGS are assigned to a member there's no
-- free slot for an area song, so it must not TRIGGER an area recast for them. A
-- member with a free slot still gets covered.
-- ponytail: counts only single-target songs, not other active [A] songs, so
-- 1 single-target + 2 area songs can still overflow -- fix by counting area
-- coverage too if that combo comes up in practice.
local function dedicated_targets(party_buff_config, song_keys, song_limit)
    local counts = {}
    for key in pairs(song_keys) do
        local targets = party_buff_config[key]
        if type(targets) == 'table' then
            for idx, v in pairs(targets) do
                if v == true and type(idx) == 'number' and idx >= 0 and idx <= 5 then
                    counts[idx] = (counts[idx] or 0) + 1
                end
            end
        end
    end
    local dedicated = {}
    for idx, c in pairs(counts) do
        if c >= song_limit then dedicated[idx] = true end
    end
    return dedicated
end

-- True when any in-range party member with a free song slot lacks the song, so
-- the area song should be (re)cast.
local function area_needs_recast(ability, party_buff_config, song_keys, state)
    local song_limit = (ability.is_main_job ~= false) and 2 or 1
    local dedicated   = dedicated_targets(party_buff_config, song_keys, song_limit)
    local player_zone = common.get_party_member_zone(0)
    for ti = 0, 5 do
        if not dedicated[ti] then
            if ti == 0 then
                -- Self is always in range/zone and covered by a self-cast song.
                if action_core.needs_buff(state.player.buffs or {}, ability.buff_id) then
                    return true
                end
            else
                local member = state.party[ti]
                if member then
                    local ei = member.target_index
                    local mz = common.get_party_member_zone(ti)
                    if ei and ei > 0 and player_zone == mz and common.is_in_range(ei, SONG_AOE_RANGE) then
                        if action_core.needs_buff(member.buffs or {}, ability.buff_id) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

-- If `ability` is the active [A] area song to consider this cycle, return its
-- config key (group name, or ability name when ungrouped); else nil. Mirrors the
-- group-selection rules the single-target pass uses.
local function area_song_config_key(ability, settings, party_buff_config, area_processed)
    -- Every bard song gets an area toggle. Pianissimo songs cast area by omitting
    -- Pianissimo; Mazurka has no Pianissimo and is always area.
    if ability.magic ~= 'song' then return nil end
    local grouped = ability.group and settings['ungrouped_' .. ability.group] ~= true
    local config_key
    if grouped then
        config_key = ability.group
        local selected = settings['selected_' .. ability.group]
        if selected then
            if selected ~= ability.name then return nil end
        else
            if area_processed[ability.group] then return nil end
            area_processed[ability.group] = true
        end
    else
        config_key = ability.name
    end
    if not (party_buff_config[config_key] and party_buff_config[config_key]['A'] == true) then
        return nil
    end
    return config_key
end

function buff.execute(settings, job_def, main_level, sub_level, player_resource, party_buff_config)
    -- Check if buff is enabled
    if not settings.buff_enabled then
        return nil
    end

    -- Do not apply buffs while resting
    if common.is_resting() then
        return nil
    end

    -- Read player data from game_state
    local state  = common.game_state
    local player = state and state.player
    if not player then
        return nil
    end

    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level

    -- Track which groups have been processed in this execution (local, never persisted)
    local processed_groups = {}
    
    -- Get party buff configuration from ui_config if not provided
    if not party_buff_config then
        local ui_config = require('lib.ui.config')
        party_buff_config = ui_config.get_party_buffs()
    end
    
    -- Get buff abilities from job definition
    local buff_abilities = job_def.abilities.buff or {}
    if #buff_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level and settings
    local available_abilities = common.filter_abilities_by_level(buff_abilities, settings, derived_main_level, derived_sub_level, job_def)

    if #available_abilities == 0 then
        return nil
    end

    -- Phase 1: area songs ([A]). Checked before the single-target ME/P1-P5 pass
    -- because an AoE song overwrites single-target songs on everyone it hits, so
    -- the area baseline must be established first. Covers every in-range party
    -- member that isn't given a specific ME/P button (see dedicated_targets).
    --
    -- Skip while Pianissimo is active: it makes the NEXT song single-target, so an
    -- area cast now would fire single-target by mistake. Let the single-target
    -- pass consume the Pianissimo first, then area-cast on a later cycle.
    local tmods = job_def.abilities.target_modifier
    local has_pianissimo = tmods and tmods[1]
        and action_core.has_any_buff(state.player.buffs, tmods[1].buff_id)
    if not has_pianissimo then
        local song_keys = song_config_keys(job_def, settings)
        local area_processed = {}
        for _, ability in ipairs(available_abilities) do
            local config_key = area_song_config_key(ability, settings, party_buff_config, area_processed)
            if config_key and area_needs_recast(ability, party_buff_config, song_keys, state) then
                local desc = string.format('Applying area buff: %s', ability.name)
                local result = action_core.try_use(ability, job_def, settings, 0, desc, state)
                if result then
                    return result
                end
            end
        end
    end

    -- Phase 2: single-target buffs (ME/P1-P5, alliance, tracked).
    -- Check each buff to see if it needs to be applied/refreshed
    for _, ability in ipairs(available_abilities) do
        local should_skip = false

        -- A group the user has "ungrouped" casts every tier independently
        -- (keyed by ability name, like a non-grouped ability) instead of only
        -- the single selected tier. Off (grouped) by default.
        local grouped = ability.group and settings['ungrouped_' .. ability.group] ~= true

        -- While in combat with Geo-bt enabled, reserve the single luopan for the
        -- enemy debuff -- don't try to place a Geo buff luopan. (Geo-bt itself
        -- lives in abilities.geo now, so it never reaches this buff loop.)
        if ability.group == 'Geo' and common.is_combat() and settings['disabled_group_Geo-bt'] ~= true then
            goto continue_ability
        end

        -- Check pet requirement
        if not should_skip and ability.pet_required then
            if not common.targets.get_pet() then
                should_skip = true
            end
        end
        
        -- Check required buff prerequisite for player
        if not should_skip and ability.requires_buff then
            if not action_core.has_any_buff(state.player.buffs, ability.requires_buff) then
                should_skip = true
            end
        end
        
        -- Check if this ability is blocked by status ailments
        if not should_skip then
            local blocked_by = common.is_command_blocked(ability.command)
            if blocked_by then
                should_skip = true
            end
        end
        
        if not should_skip then
            -- Determine if this is a single-target buff (function command) or self-only buff (string command)
            local is_single_target = type(ability.command) == 'function'
            
            if is_single_target then
                -- Single-target buff: Check button states for ME and party members (P1-P5)
                -- First check if ability/group is enabled via settings
                local key
                local config_key
                if grouped then
                    key = 'disabled_group_' .. ability.group
                    config_key = ability.group
                    
                    -- Check if this ability is the selected one for this group
                    local selected_key = 'selected_' .. ability.group
                    local selected_ability = settings[selected_key]
                    if selected_ability then
                        -- A specific ability is selected, only use that one
                        if selected_ability ~= ability.name then
                            goto continue_ability
                        end
                    else
                        -- No selection made yet - UI will handle this on next open
                        -- For now, skip all but the first available ability in this group
                        -- (filter_abilities_by_level already sorted by cost descending = highest level first)
                        -- Check if we've already processed an ability from this group
                        if processed_groups[ability.group] then
                            -- Already processed another ability from this group, skip this one
                            goto continue_ability
                        else
                            -- Mark this group as processed for this execution cycle
                            processed_groups[ability.group] = true
                        end
                    end
                else
                    key = 'disabled_' .. ability.name:gsub(' ', '_')
                    config_key = ability.name
                end
                local is_ability_enabled = settings[key] == false or settings[key] == nil
                
                if not is_ability_enabled then
                    goto continue_ability
                end
                
                -- Check if any party buttons are enabled
                local has_any_target = false
                if party_buff_config and party_buff_config[config_key] then
                    for k, v in pairs(party_buff_config[config_key]) do
                        if v == true then
                            has_any_target = true
                            break
                        end
                    end
                end
                
                if not has_any_target then
                    goto continue_ability
                end
                
                -- Priority order: ME, P1, P2, P3, P4, P5
                local targets_to_check = {0, 1, 2, 3, 4, 5}  -- 0 = ME, 1-5 = P1-P5
                
                for _, target_index in ipairs(targets_to_check) do
                    -- Check if this target is enabled in party_buff_config
                    local is_target_enabled = false
                    if party_buff_config and party_buff_config[config_key] then
                        is_target_enabled = party_buff_config[config_key][target_index] == true
                    end
                    
                    if is_target_enabled then
                        local target_needs_buff = false
                        local target_entity_index = nil
                        
                        -- Get target buffs and entity index
                        if target_index == 0 then
                            -- ME: Check player buffs from game_state
                            target_buffs = state.player.buffs or {}
                            target_entity_index = 0
                        else
                            -- P1-P5: Check party member buffs from game_state
                            -- Zone check stays as live call (zone not stored in game_state)
                            local party_member = state.party[target_index]
                            if party_member then
                                local player_zone = common.get_party_member_zone(0)
                                local member_zone = common.get_party_member_zone(target_index)
                                target_entity_index = party_member.target_index
                                
                                if target_entity_index and target_entity_index > 0 and player_zone == member_zone and common.is_in_range(target_entity_index, 20) then
                                    target_buffs = party_member.buffs or {}
                                else
                                    -- Party member not available or out of range, skip
                                    goto continue_target
                                end
                            else
                                -- Party member not active in game_state, skip
                                goto continue_target
                            end
                        end
                        
                        -- Check if target needs buff
                        target_needs_buff = action_core.needs_buff(target_buffs, ability.buff_id)
                        
                        if target_needs_buff then
                            -- Check if this ability requires a target modifier (Pianissimo, Entrust, etc.)
                            -- Includes ME (target_index 0): songs are now single-target on self via
                            -- Pianissimo, matching P1-P5. The area ([A]) pass above handles no-Pianissimo AoE.
                            if ability.target_modifier and target_index >= 0 then
                                -- Check if we already have the modifier buff active
                                local has_modifier_buff = false
                                if job_def.abilities.target_modifier and #job_def.abilities.target_modifier > 0 then
                                    local modifier_ability = job_def.abilities.target_modifier[1]
                                    has_modifier_buff = action_core.has_any_buff(state.player.buffs, modifier_ability.buff_id)
                                end
                                
                                if not has_modifier_buff then
                                    -- Don't have modifier buff, try to use it
                                    local modifier_result = common.check_target_modifier(job_def, settings, derived_main_level, derived_sub_level)
                                    if modifier_result then
                                        -- Need to use modifier ability first
                                        return modifier_result
                                    else
                                        -- Modifier unavailable (on cooldown, disabled, etc.), skip this ability for now
                                        return nil
                                    end
                                end
                                -- If we reach here, we have the modifier buff, proceed to cast the song
                            end
                            
                            -- Use action_core for resource + cooldown + command building
                            local target_name = target_index == 0 and 'self' or (state.party[target_index] and state.party[target_index].name or ('P' .. target_index))
                            local desc = string.format('Applying buff: %s to %s', ability.name, target_name)

                            local result, reason = action_core.try_use(ability, job_def, settings, target_index, desc, state)
                            if result then
                                return result
                            end
                        end
                        
                        ::continue_target::
                    end
                end

                -- After checking party members, check enabled alliance members
                -- (only if ability has target_outside, same restriction as tracked targets).
                if ability.target_outside and state.alliance then
                    for al_pi = 2, 3 do
                        local sub_party = state.alliance[al_pi]
                        if sub_party then
                            local base_flat = (al_pi - 1) * 6
                            for local_idx = 0, 5 do
                                local flat_index = base_flat + local_idx
                                local al_key = 'al_' .. flat_index
                                local is_al_enabled = party_buff_config and party_buff_config[config_key] and party_buff_config[config_key][al_key] == true
                                if is_al_enabled then
                                    local m = sub_party[local_idx]
                                    if m and m.is_active and m.target_index and m.target_index > 0 and common.is_in_range(m.target_index, 20) then
                                        local al_buffs = m.buffs or {}
                                        local al_needs_buff = action_core.needs_buff(al_buffs, ability.buff_id)
                                        if al_needs_buff then
                                            local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                                            local ok_use, _ = action_core.is_usable(ability, job_def, eff_cost)
                                            if ok_use then
                                                -- Check stratagems before casting
                                                local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                                                if strat_result == false then ok_use = false
                                                elseif strat_result then return strat_result end
                                            end
                                            if ok_use then
                                                local command = common.build_ability_command_for_target(ability, m.server_id)
                                                if command then
                                                    if ability.buff_id then
                                                        local bid = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                                        common.register_pending_buff(m.server_id, bid)
                                                    end
                                                    local desc = string.format('Applying buff: %s to alliance %s', ability.name, m.name)
                                                    return { command = command, description = desc }
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                -- After checking party members, also check tracked targets (only if ability has target_outside)
                if ability.target_outside and state.tracked then
                    for sid, tt in pairs(state.tracked) do
                        -- Check if this tracked target has its button enabled in the config
                        local tt_key = 'tt_' .. sid
                        local is_tt_enabled = party_buff_config and party_buff_config[config_key] and party_buff_config[config_key][tt_key] == true
                        if is_tt_enabled and tt.is_active and tt.target_index and tt.target_index > 0 and common.is_in_range(tt.target_index, 20) then
                            local tt_buffs = tt.buffs or {}
                            local tt_needs_buff = action_core.needs_buff(tt_buffs, ability.buff_id)
                            if tt_needs_buff then
                                local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                                local ok, reason = action_core.is_usable(ability, job_def, eff_cost)
                                if ok then
                                    -- Check stratagems before casting
                                    local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                                    if strat_result == false then ok = false
                                    elseif strat_result then return strat_result end
                                end
                                if ok then
                                    local command = common.build_ability_command_for_target(ability, sid)
                                    if command then
                                        -- Register pending buff for packet tracking
                                        if ability.buff_id then
                                            local bid = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                            common.register_pending_buff(sid, bid)
                                        end
                                        local desc = string.format('Applying buff: %s to tracked %s', ability.name, tt.name)
                                        return { command = command, description = desc }
                                    end
                                end
                            end
                        end
                    end
                end
            else
                -- Self-only buff: Use checkbox-based logic (original behavior)
                -- Check if ability/group is enabled via settings
                local key
                if grouped then
                    key = 'disabled_group_' .. ability.group
                    
                    -- Check if this ability is the selected one for this group
                    local selected_key = 'selected_' .. ability.group
                    local selected_ability = settings[selected_key]
                    if selected_ability then
                        -- A specific ability is selected, only use that one
                        if selected_ability ~= ability.name then
                            goto continue_ability
                        end
                    else
                        -- No selection made yet - UI will handle this on next open
                        -- For now, skip all but the first available ability in this group
                        -- (filter_abilities_by_level already sorted by cost descending = highest level first)
                        -- Check if we've already processed an ability from this group
                        if processed_groups[ability.group] then
                            -- Already processed another ability from this group, skip this one
                            goto continue_ability
                        else
                            -- Mark this group as processed for this execution cycle
                            processed_groups[ability.group] = true
                        end
                    end
                else
                    key = 'disabled_' .. ability.name:gsub(' ', '_')
                end
                local is_enabled = settings[key] == false or settings[key] == nil
                
                if not is_enabled then
                    goto continue_ability
                end
                
                -- Check if buff is already active
                local needs_buff = action_core.needs_buff(state.player.buffs, ability.buff_id)
                
                if needs_buff then
                    -- Use action_core for resource + cooldown + command building
                    local desc = string.format('Applying buff: %s', ability.name)
                    local result, reason = action_core.try_use(ability, job_def, settings, 0, desc, state)
                    if result then
                        return result
                    end
                end
            end
        end
        
        ::continue_ability::
    end
    
    return nil
end

return buff
