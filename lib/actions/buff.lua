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

-- Invisible (status_effects.sql id 69). Casting anything at all breaks it, so any
-- non-travel buff cast while it's up costs an Invisible reapply on top of itself.
local INVISIBLE_BUFF = 69

-- os.clock() of our last cast per ability name, for buffs whose target we can't
-- read (pet buffs aren't tracked). Cleared on reload -> re-applies immediately.
local last_self_cast = {}

-- How many distinct selected songs share this ability's buff_id for target_key
-- (0-5, or 'A'). A grouped group contributes one (only one tier is ever active);
-- an ungrouped group contributes one per selected tier, so stacking tiers each
-- demand their own instance.
local function wanted_instances(ability, target_key, available_abilities, settings, party_buff_config)
    local keys = {}
    for _, b in ipairs(available_abilities) do
        if b.buff_id == ability.buff_id then
            keys[common.ability_config_key(b, settings)] = true
        end
    end
    local n = 0
    for key in pairs(keys) do
        local cfg = party_buff_config[key]
        if cfg and cfg[target_key] == true then n = n + 1 end
    end
    return n
end

-- True when target lacks enough instances of this song's buff to satisfy every
-- selected tier sharing that buff_id. Falls back to the plain presence check
-- (handles buff_id == nil) unless two or more tiers are stacked. Songs that
-- share a buff_id stack as separate instances (e.g. Mage's Ballad + Mage's
-- Ballad II = two of buff 196), so a plain "has it" check is not enough.
local function song_needed(target_buffs, ability, target_key, available_abilities, settings, party_buff_config)
    local wanted = wanted_instances(ability, target_key, available_abilities, settings, party_buff_config)
    if wanted <= 1 then
        return action_core.needs_buff(target_buffs, ability.buff_id)
    end
    return action_core.count_instances(target_buffs, ability.buff_id) < wanted
end

-- Config keys (group name, or ability name when ungrouped) for THIS job's songs.
-- Only these count toward a member's song slots. party_buff_config is shared
-- across every job and buff type (WHM cures/-na, Geo, etc.), so scanning all of
-- it would mistake unrelated self-buffs for songs and wrongly mark everyone's
-- slots full -- which silently kills every area song.
local function song_config_keys(job_def, settings)
    local keys = {}
    for _, ability in ipairs(job_def.abilities.buff or {}) do
        if ability.magic == 'song' then
            keys[common.ability_config_key(ability, settings)] = true
        end
    end
    return keys
end

-- Party indices (0-5) mapped to how many single-target (Pianissimo) songs are
-- configured for that member. Feeds both dedicated_targets (full/not-full) and
-- area_needs_recast (partial capacity math).
local function single_target_song_counts(party_buff_config, song_keys)
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
    return counts
end

-- Party indices (0-5) whose song slots are already FULL of single-target
-- (Pianissimo) songs. A bard holds `song_limit` songs per member (2 main / 1
-- sub); once that many single-target SONGS are assigned to a member there's no
-- free slot for an area song, so it must not TRIGGER an area recast for them. A
-- member with a free slot still gets covered.
local function dedicated_targets(party_buff_config, song_keys, song_limit)
    local counts = single_target_song_counts(party_buff_config, song_keys)
    local dedicated = {}
    for idx, c in pairs(counts) do
        if c >= song_limit then dedicated[idx] = true end
    end
    return dedicated
end

-- If `ability` is the active [A] area song to consider this cycle, return its
-- config key (group name, or ability name when ungrouped); else nil. Mirrors the
-- group-selection rules the single-target pass uses.
local function area_song_config_key(ability, settings, party_buff_config, area_processed)
    -- Every bard song gets an area toggle. Songs cast area by omitting Pianissimo;
    -- the single-target pass adds Pianissimo for ME/P1-P5.
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

-- True when any in-range party member with a free song slot lacks the song, so
-- the area song should be (re)cast.
--
-- "Free slot" is capacity math, not all-or-nothing: a member with one
-- single-target song assigned (e.g. Ballad) and two area songs configured
-- (e.g. Minuet + March) only has room for song_limit - 1 of them. Once
-- they're holding that many area songs -- whichever ones they happen to be --
-- they're satisfied (single target OK with Ballad + (Minuet OR March)); this
-- stops the single/area songs from endlessly knocking each other off the same
-- member's last slot.
local function area_needs_recast(ability, party_buff_config, song_keys, available_abilities, settings, state)
    local tier_is_main  = ability.is_main_job ~= false
    local song_limit    = tier_is_main and 2 or 1
    local single_counts = single_target_song_counts(party_buff_config, song_keys)

    -- Every ability that is this cycle's active [A] area song and shares this
    -- ability's main/sub tier, for counting how many area-song slots a member
    -- already holds (presence-only -- area songs are normally distinct buffs).
    local area_list = {}
    local area_processed = {}
    for _, a in ipairs(available_abilities) do
        if (a.is_main_job ~= false) == tier_is_main
           and area_song_config_key(a, settings, party_buff_config, area_processed) then
            area_list[#area_list + 1] = a
        end
    end

    local player_zone = common.get_party_member_zone(0)
    for ti = 0, 5 do
        local remaining = song_limit - (single_counts[ti] or 0)
        if remaining > 0 then
            local target_buffs
            if ti == 0 then
                -- Self is always in range/zone and covered by a self-cast song.
                target_buffs = state.player.buffs or {}
            else
                local member = state.party[ti]
                -- Trusts have unreliable buff tracking: drops aren't detected and
                -- only one copy of a buff_id is visible (stacked songs like Ballad
                -- I+II always look short), which would force an endless area recast.
                -- Skip them -- self/real players drive recast timing and the AoE
                -- covers in-range trusts on that same cast.
                if member and not member.is_trust then
                    local ei = member.target_index
                    local mz = common.get_party_member_zone(ti)
                    if ei and ei > 0 and player_zone == mz and common.is_in_range(ei, SONG_AOE_RANGE) then
                        target_buffs = member.buffs or {}
                    end
                end
            end
            if target_buffs and song_needed(target_buffs, ability, 'A', available_abilities, settings, party_buff_config) then
                local held = 0
                for _, a in ipairs(area_list) do
                    if action_core.has_any_buff(target_buffs, a.buff_id) then held = held + 1 end
                end
                if held < remaining then return true end
            end
        end
    end
    return false
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
    local ui_config = require('lib.ui.config')
    if not party_buff_config then
        party_buff_config = ui_config.get_party_buffs()
    end
    -- Session-only per-target Combat/Idle overrides (right-click on ME/P1-P5).
    local party_buff_gates = ui_config.get_party_buff_gates()
    
    -- Get buff abilities from job definition
    local buff_abilities = job_def.abilities.buff or {}
    if #buff_abilities == 0 then
        return nil
    end

    -- Auto-equip a consumable a buff needs in the ammo slot (BST Reward Regen ->
    -- Pet Poultice; NIN Sange -> Shuriken). For pet buffs this is only reached
    -- after the higher-priority pet-heal passed this tick, so biscuit and poultice
    -- never contend; ammo_equip_command itself skips pet-only ammo when no pet.
    local equip = common.ammo_equip_command(buff_abilities, settings, player)
    if equip then return equip end

    -- Filter abilities by level and settings
    local available_abilities = common.filter_abilities_by_level(buff_abilities, settings, derived_main_level, derived_sub_level, job_def, party_buff_gates)

    if #available_abilities == 0 then
        return nil
    end

    -- Any cast breaks Invisible (69), so while it's up cast travel buffs only.
    -- Heals, -na, wake and revive are other modules and stay ungated.
    if action_core.has_any_buff(state.player.buffs, INVISIBLE_BUFF) then
        local travel_only = {}
        for _, a in ipairs(available_abilities) do
            if a.travel_buff then travel_only[#travel_only + 1] = a end
        end
        -- No travel buff castable (job has none, or in combat -- all are idle_only) = no gate.
        if #travel_only > 0 then available_abilities = travel_only end
    end

    -- Phase 1: area songs ([A]). Checked before the single-target ME/P1-P5 pass
    -- because an AoE song overwrites single-target songs on everyone it hits, so
    -- the area baseline must be established first. Covers every in-range party
    -- member that isn't given a specific ME/P button (see dedicated_targets).
    --
    -- Skip while Pianissimo is active: it makes the NEXT song single-target, so an
    -- area cast now would fire single-target by mistake. Let the single-target
    -- pass consume the Pianissimo first, then area-cast on a later cycle.
    -- (Fast-casting mode is the deliberate exception -- see below.)
    local tmods = job_def.abilities.target_modifier
    local has_pianissimo = tmods and tmods[1]
        and action_core.has_any_buff(state.player.buffs, tmods[1].buff_id)
    -- Fast-casting mode raises Pianissimo on purpose for the area cast (shorter
    -- cast time), then strips it mid-cast so the song still lands as area. In that
    -- mode we run the area phase even while Pianissimo is up, since it's ours.
    local fast_casting = settings.pianissimo_fast_casting == true
    if fast_casting or not has_pianissimo then
        local song_keys = song_config_keys(job_def, settings)
        -- Hold AOE for Group: members with at least one single-target (Pianissimo)
        -- song assigned are managed individually, so their range must not gate the
        -- area cast -- exclude them (threshold 1, not song_limit).
        local aoe_excl = settings.hold_aoe_for_group
            and dedicated_targets(party_buff_config, song_keys, 1) or nil
        local area_processed = {}
        -- Fast-casting only: set when an [A] song still needs (re)casting but
        -- couldn't fire this tick (on recast). Forces a hold so the single-target
        -- pass can't jump ahead and get overwritten by the area song later.
        local area_pending = false
        for _, ability in ipairs(available_abilities) do
            local config_key = area_song_config_key(ability, settings, party_buff_config, area_processed)
            -- The area [A] button has no per-target override of its own, so it must
            -- still obey the ability's plain global gate even when filter_abilities_by_level
            -- let the ability through only because some OTHER target (ME/P1-P5) overrode it.
            if config_key and common.ability_gate_ok_now(ability, settings)
               and area_needs_recast(ability, party_buff_config, song_keys, available_abilities, settings, state) then
                if aoe_excl and not common.group_in_aoe_range(SONG_AOE_RANGE, aoe_excl) then
                    -- Hold: a member with no single-target song is out of range.
                    -- Don't area-cast and don't mark pending, so the single-target
                    -- pass still manages Pianissimo-assigned members this tick.
                    common.announce_gather(ability.name)
                elseif fast_casting and not has_pianissimo then
                    -- Only raise Pianissimo once the song is off recast and affordable,
                    -- else Pianissimo's own recast burns down while the song waits.
                    local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                    if action_core.is_usable(ability, job_def, eff_cost) then
                        -- Fast mode always holds: wait for Pianissimo rather than
                        -- casting the area song without it.
                        return common.check_target_modifier(job_def, settings, derived_main_level, derived_sub_level)
                    end
                    area_pending = true
                else
                    local desc = string.format('Applying area buff: %s', ability.name)
                    local result = action_core.try_use(ability, job_def, settings, 0, desc, state)
                    if result then
                        -- Pianissimo up (fast cast): schedule its removal so the song
                        -- reverts single-target -> area once casting is underway.
                        if fast_casting and has_pianissimo then
                            if type(result) ~= 'table' then result = { command = result, description = desc } end
                            result.scheduled_removal = { command = '/debuff 409', delay = 1.0 }
                        end
                        return result
                    end
                    area_pending = true
                end
            end
        end
        -- Fast-casting: every configured [A] song must be established before the
        -- single-target pass runs. If one still needs recasting but was on recast
        -- this tick, hold here rather than letting Phase 2 fire a single-target
        -- song the area recast would just overwrite. (Normal mode falls through --
        -- an on-recast song there simply can't be area-cast, so single-target may
        -- proceed.)
        -- ponytail: holds through silence too (song not usable), but Phase 2 songs
        -- are equally blocked then, so nothing is lost.
        if fast_casting and area_pending then
            return nil
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
        
        -- Check required buff prerequisite for player. An assigned precast that grants
        -- the buff (SCH Enlightenment) counts as met -- check_stratagem fires the JA
        -- below and holds the spell until its buff lands.
        if not should_skip and ability.requires_buff then
            if not action_core.has_any_buff(state.player.buffs, ability.requires_buff)
                and not common.precast_satisfies_prereq(job_def, settings, ability) then
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

        -- Check if a self-buff blocks this ability (DNC Fan Dance blocks Sambas)
        if not should_skip and action_core.is_self_blocked(ability, state.player.buffs) then
            should_skip = true
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
                
                -- Priority order: ME, P1, P2, P3, P4, P5 (0 = ME, 1-5 = P1-P5).
                -- travel buffs put the caster LAST: their own Invisible must be the final
                -- cast of the run or the next one breaks it.
                local targets_to_check = ability.travel_buff and {1, 2, 3, 4, 5, 0} or {0, 1, 2, 3, 4, 5}

                for _, target_index in ipairs(targets_to_check) do
                    -- Check if this target is enabled in party_buff_config
                    local is_target_enabled = false
                    if party_buff_config and party_buff_config[config_key] then
                        is_target_enabled = party_buff_config[config_key][target_index] == true
                    end
                    
                    if is_target_enabled then
                        -- Per-target Combat/Idle override (right-click on ME/P1-P5) replaces
                        -- the ability's own gate for this one target; falls back to it otherwise.
                        if not common.target_gate_ok(ability, config_key, target_index, settings, party_buff_gates) then
                            goto continue_target
                        end

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
                            -- Trusts take none of the aggro travel buffs prevent, so casting
                            -- one on a Trust is wasted MP and a wasted tick.
                            if party_member and (common.is_trust_excluded(party_member.name, party_member.server_id)
                                or (ability.travel_buff and party_member.is_trust)) then
                                goto continue_target
                            end
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
                        target_needs_buff = song_needed(target_buffs, ability, target_index, available_abilities, settings, party_buff_config)
                        
                        if target_needs_buff then
                            -- Check if this ability requires a target modifier (Pianissimo, Entrust, etc.)
                            -- Includes ME (target_index 0): songs are now single-target on self via
                            -- Pianissimo, matching P1-P5. The area ([A]) pass above handles no-Pianissimo AoE.
                            if ability.target_modifier then
                                -- Check if we already have the modifier buff active
                                local has_modifier_buff = false
                                if job_def.abilities.target_modifier and #job_def.abilities.target_modifier > 0 then
                                    local modifier_ability = job_def.abilities.target_modifier[1]
                                    has_modifier_buff = action_core.has_any_buff(state.player.buffs, modifier_ability.buff_id)
                                end
                                
                                if not has_modifier_buff then
                                    -- Only raise the modifier once the song is off recast
                                    -- and affordable, else its recast burns down while the
                                    -- song waits.
                                    local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                                    if not action_core.is_usable(ability, job_def, eff_cost) then
                                        goto continue_ability
                                    end
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
                -- Alliance targets have no per-target override, so they must still obey the
                -- ability's plain global gate even if a ME/P1-P5 override let it past the
                -- filter above for a different target.
                if ability.target_outside and state.alliance and common.ability_gate_ok_now(ability, settings) then
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
                                    -- Same travel_buff Trust skip as the party loop -- other
                                    -- players' Trusts show up in the alliance sub-parties.
                                    if m and not (ability.travel_buff and m.is_trust) and m.is_active and m.target_index and m.target_index > 0 and common.is_in_range(m.target_index, 20) then
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
                                                        common.register_pending_buff(m.server_id, bid, ability.name)
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
                -- Same global-gate guard as the alliance loop above -- tracked targets have
                -- no per-target override either.
                if ability.target_outside and state.tracked and common.ability_gate_ok_now(ability, settings) then
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
                                            common.register_pending_buff(sid, bid, ability.name)
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
                
                -- For buffs we can't detect on the target (e.g. pet Regen from
                -- Reward), reapply_interval is the effect's duration in seconds;
                -- skip until that has elapsed since our last cast so we don't
                -- reapply every recast and waste the consumable.
                if ability.reapply_interval then
                    local last = last_self_cast[ability.name]
                    if last and (os.clock() - last) < ability.reapply_interval then
                        goto continue_ability
                    end
                end

                -- Ninja "Cast with 1 Shadow": Utsusemi normally blocks while ANY
                -- Copy Image buff is up (66/444/445/446). This mode ignores the
                -- 1-shadow buff (one_shadow_buff = 66) so it recasts at 1 shadow,
                -- then strips 66 mid-cast (/debuff 66) so the new shadows apply.
                local needs_buff
                local strip_one_shadow = false
                if ability.one_shadow_buff and settings.cast_with_1_shadow == true then
                    local blocking = {}
                    for _, id in ipairs(action_core.normalize_ids(ability.buff_id)) do
                        if id ~= ability.one_shadow_buff then blocking[#blocking + 1] = id end
                    end
                    needs_buff = action_core.needs_buff(state.player.buffs, blocking)
                    strip_one_shadow = needs_buff
                        and action_core.has_any_buff(state.player.buffs, ability.one_shadow_buff)
                else
                    needs_buff = action_core.needs_buff(state.player.buffs, ability.buff_id)
                end

                if needs_buff then
                    -- Hold AOE for Group: Protectra/Shellra/Bar (WHM), Diamondhide
                    -- (BLU) are <me> self-casts that hit the party. Hold until the
                    -- group is in range. goto (not return) so a held AOE buff doesn't
                    -- block lower-priority non-AOE self-buffs this tick.
                    if ability.aoe and settings.hold_aoe_for_group
                       and not common.group_in_aoe_range() then
                        common.announce_gather(ability.name)
                        goto continue_ability
                    end

                    -- Always-required precast (BLU Unbridled Learning): the
                    -- spell cannot function without the JA's buff. Fire the JA
                    -- first -- but only when the spell itself could follow it
                    -- (usable, and not held back waiting on Diffusion) so the
                    -- JA isn't popped for nothing.
                    local pre = common.check_required_precast(job_def, ability)
                    if pre == false then goto continue_ability end
                    if pre then
                        local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                        if not action_core.is_usable(ability, job_def, eff_cost) then
                            goto continue_ability
                        end
                        if common.check_stratagem(job_def, settings, ability.name, ability) == false then
                            goto continue_ability
                        end
                        return pre
                    end

                    -- Use action_core for resource + cooldown + command building
                    local desc = string.format('Applying buff: %s', ability.name)
                    local result, reason = action_core.try_use(ability, job_def, settings, 0, desc, state)
                    if result then
                        last_self_cast[ability.name] = os.clock()
                        -- Strip the lingering 1-shadow buff mid-cast so the new
                        -- shadows apply cleanly (Ninja "Cast with 1 Shadow").
                        if strip_one_shadow then
                            if type(result) ~= 'table' then result = { command = result, description = desc } end
                            result.scheduled_removal = { command = '/debuff ' .. ability.one_shadow_buff, delay = 1.0 }
                        end
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
