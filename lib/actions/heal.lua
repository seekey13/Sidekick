--[[
    Single-target healing action module
    Handles priority-based healing for individual party members
]]--

local heal = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- Session-only per-target selection for Group/AOE healing (set via config UI).
-- Asymmetric defaults so behaviour is correct even when the config window was
-- never opened this session (the common case each login): party/tracked members
-- are included unless explicitly disabled; alliance members are excluded unless
-- explicitly enabled. Keys match the UI: numeric 0-5 (party), 'tt_<sid>'
-- (tracked), 'al_<flat>' (alliance).
-- Forced self heal: set by recover.lua when an ability tagged force_self_heal
-- (RDM Convert) fires — HP was just dumped into MP, so the next single-target
-- heal must go to the player regardless of focus/lowest-HP logic.
--
-- The throttle stamps at *send*; between the Convert send and its 0x028
-- resolution the game state is still pre-swap (old low MP, old HP). Selecting
-- in that window picks a cure sized to the MP that's about to become HP
-- (Cure III at 50 MP, nothing at all at 7 MP). So while the player's MP is
-- still below recover_mp_threshold — the very condition that fired Convert —
-- the swap hasn't landed yet: hold single-target healing and decide nothing.
-- Cleared when the forced heal is returned, when the player's HP is already
-- above heal_threshold *after* the swap landed, when the swap never lands
-- within FORCE_SELF_WAIT_TIMEOUT, or after FORCE_SELF_TIMEOUT overall.
local FORCE_SELF_WAIT_TIMEOUT = 5   -- max wait for the ability to resolve (MP jump)
local FORCE_SELF_TIMEOUT      = 30  -- overall safety valve (e.g. silenced the whole window)
local force_self = { active = false, ts = 0 }

function heal.force_next_self_heal()
    force_self.active = true
    force_self.ts     = os.clock()
end

local function make_group_filter(key_name)
    local ui_config = require('lib.ui.config')
    local cfg = ui_config.get_party_buffs()
    local targets = cfg and cfg[key_name]
    return function(key, is_alliance)
        if is_alliance then
            return targets ~= nil and targets[key] == true
        end
        return not (targets ~= nil and targets[key] == false)
    end
end

function heal.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if healing is enabled
    if not settings.heal_enabled then
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

    -- Get heal abilities from job definition
    local heal_abilities = job_def.abilities.heal or {}
    
    if #heal_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level using DRY helper
    local available_abilities = common.filter_abilities_by_level(
        heal_abilities,
        settings,
        derived_main_level,
        derived_sub_level,
        job_def
    )

    -- Drop Waltzes etc. blocked by an active self-buff (DNC Saber Dance blocks Waltzes)
    available_abilities = action_core.filter_self_buff_blocked(available_abilities, state.player.buffs)

    if #available_abilities == 0 then
        return nil
    end
    
    -- Check if all abilities are self-only
    local all_self_only = true
    for _, ability in ipairs(available_abilities) do
        if not ability.self_only then
            all_self_only = false
            break
        end
    end
    
    -- If all abilities are self-only, only check player HP
    if all_self_only then
        local player_hpp = state.player.hpp
        
        if common.below_threshold(player_hpp, settings.heal_threshold or 75) then
            -- Select appropriate ability
            local selected_ability = heal.select_ability(available_abilities, player_hpp, job_def, player_resource, 0, nil, settings)
            if selected_ability then
                -- Check stratagems before casting
                local strat_result = common.check_stratagem(job_def, settings, selected_ability.name, selected_ability)
                if strat_result == false then return nil
                elseif strat_result then return strat_result end

                local command = common.build_ability_command(selected_ability, 0)
                
                if command then
                    common.debugf('[HEAL] >>> Using self-only heal %s', selected_ability.name)
                    return {
                        command = command,
                        description = string.format('Self-healing with %s (HP: %.1f%%)', selected_ability.name, player_hpp)
                    }
                end
            end
        end
        return nil
    end
    
    -- Build party_status from game_state snapshot
    local threshold       = settings.heal_threshold or 75
    local focus_enabled   = settings.focus_enabled
    local focus_threshold = settings.focus_threshold or 85

    -- Resolve focus target: check party first, then tracked targets, then alliance
    local focus_kind, focus_ref = common.resolve_focus_target(settings, state)
    local focus_party_idx    = focus_kind == 'party'    and focus_ref or nil
    local focus_tracked_sid  = focus_kind == 'tracked'  and focus_ref or nil
    local focus_alliance_sid = focus_kind == 'alliance' and focus_ref or nil

    local party_status = {
        needs_heal        = {},
        focus_needs_heal  = false,
        lowest_hp_index   = nil,
        lowest_hp_percent = 100,
        average_hp        = 100,
        -- Tracked target with lowest HP (separate from party lowest)
        lowest_tracked_sid   = nil,
        lowest_tracked_hpp   = 100,
        -- Alliance member with lowest HP (separate from tracked lowest)
        lowest_alliance_sid  = nil,
        lowest_alliance_hpp  = 100,
    }
    local group_allowed = make_group_filter('heal_group')

    local total_hp     = 0
    local active_count = 0
    for i = 0, 5 do
        local m = i == 0 and state.player or state.party[i]
        if not m then goto continue_hp_check end
        local hpp        = m.hpp or 0
        local target_idx = m.target_index or 0
        if not common.is_active_member(hpp) then goto continue_hp_check end
        if common.is_trust_excluded(m.name, m.server_id) then goto continue_hp_check end
        if not group_allowed(i) then goto continue_hp_check end
        total_hp     = total_hp     + hpp
        active_count = active_count + 1
        local is_focus      = focus_enabled and focus_party_idx ~= nil and i == focus_party_idx
        local eff_threshold = is_focus and focus_threshold or threshold
        if hpp < eff_threshold and target_idx > 0 then
            table.insert(party_status.needs_heal, { index = i, target_index = target_idx, hpp = hpp })
            if hpp < party_status.lowest_hp_percent then
                party_status.lowest_hp_percent = hpp
                party_status.lowest_hp_index   = i
            end
            if is_focus then
                party_status.focus_needs_heal = true
            end
        end
        ::continue_hp_check::
    end

    -- Also scan tracked targets for healing needs
    if state.tracked then
        for sid, tt in pairs(state.tracked) do
            if tt.is_active and tt.target_index and tt.target_index > 0 and group_allowed('tt_' .. sid) then
                local hpp = tt.hpp or 0
                if common.is_active_member(hpp) then
                    local is_focus = focus_tracked_sid and sid == focus_tracked_sid
                    local eff_threshold = is_focus and focus_threshold or threshold
                    if hpp < eff_threshold then
                        table.insert(party_status.needs_heal, {
                            index = nil,
                            target_index = tt.target_index,
                            hpp = hpp,
                            is_tracked = true,
                            server_id = sid,
                            name = tt.name,
                        })
                        if hpp < party_status.lowest_tracked_hpp then
                            party_status.lowest_tracked_hpp = hpp
                            party_status.lowest_tracked_sid = sid
                        end
                        if is_focus then
                            party_status.focus_needs_heal = true
                        end
                    end
                end
            end
        end
    end

    -- Also scan alliance members for healing needs (target_outside abilities only)
    if state.alliance then
        for al_pi = 2, 3 do
            local sub_party = state.alliance[al_pi]
            if sub_party then
                for local_idx, m in pairs(sub_party) do
                    local al_key = 'al_' .. ((al_pi - 1) * 6 + local_idx)
                    if m and m.is_active and m.target_index and m.target_index > 0 and group_allowed(al_key, true) then
                        local hpp = m.hpp or 0
                        if common.is_active_member(hpp) then
                            local is_focus = focus_alliance_sid and m.server_id == focus_alliance_sid
                            local eff_threshold = is_focus and focus_threshold or threshold
                            if hpp < eff_threshold then
                                table.insert(party_status.needs_heal, {
                                    index        = nil,
                                    target_index = m.target_index,
                                    hpp          = hpp,
                                    is_alliance  = true,
                                    server_id    = m.server_id,
                                    name         = m.name,
                                })
                                if hpp < party_status.lowest_alliance_hpp then
                                    party_status.lowest_alliance_hpp = hpp
                                    party_status.lowest_alliance_sid = m.server_id
                                end
                                if is_focus then
                                    party_status.focus_needs_heal = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if active_count > 0 then
        party_status.average_hp = total_hp / active_count
    end
    
    -- Priority 1: Critical HP (if anyone is below critical threshold)
    local critical_threshold = settings.critical_threshold or 30
    local critical_abilities = job_def.abilities.critical or {}
    
    if #critical_abilities > 0 then
        -- Filter critical abilities by level
        local available_critical = common.filter_abilities_by_level(
            critical_abilities,
            settings,
            derived_main_level,
            derived_sub_level,
            job_def
        )
        
        if #available_critical > 0 then
            -- Find lowest HP party member (ignoring focus)
            local critical_party_index = nil
            local critical_hpp = 100
            
            for i = 0, 5 do
                local m = i == 0 and state.player or state.party[i]
                if m and group_allowed(i) and not common.is_trust_excluded(m.name, m.server_id) then
                    local hpp = m.hpp or 0
                    if common.below_threshold(hpp, critical_threshold) and hpp < critical_hpp then
                        critical_hpp = hpp
                        critical_party_index = i
                    end
                end
            end
            
            if critical_party_index then
                common.debugf('[HEAL] Critical HP detected: party[%d] at %.1f%% (threshold: %.1f%%)',
                             critical_party_index, critical_hpp, critical_threshold)
                
                -- Try to use a critical ability
                for _, ability in ipairs(available_critical) do
                    if settings['disabled_' .. ability.name:gsub(' ', '_')] ~= true then
                        local ok, reason = action_core.is_usable(ability, job_def)
                        if ok then
                            -- Determine target: self-target (Divine Seal) vs party-target (Martyr)
                            local cmd_test         = common.build_ability_command(ability, 0)
                            local target_party_index
                            local in_range         = true
                            if cmd_test and cmd_test:find('<me>') then
                                target_party_index = 0
                            else
                                target_party_index   = critical_party_index
                                local cm             = critical_party_index == 0 and state.player or state.party[critical_party_index]
                                local target_index   = cm and cm.target_index
                                if not target_index or target_index == 0 then
                                    in_range = false
                                else
                                    local rng = type(ability.range) == 'number' and ability.range or 21
                                    in_range  = common.is_in_range(target_index, rng)
                                end
                            end
                            if in_range then
                                local command = common.build_ability_command(ability, target_party_index)
                                if command then
                                    common.debugf('[HEAL] >>> Using critical ability %s', ability.name)
                                    local cm = critical_party_index == 0 and state.player or state.party[critical_party_index]
                                    return { command = command,
                                        description = string.format('Critical: %s for %s (HP: %.1f%%)',
                                            ability.name,
                                            target_party_index == 0 and 'self' or (cm and cm.name or 'party member'),
                                            critical_hpp) }
                                end
                            end
                        end
                    end
                end
                
            end
        end
    end
    
    -- Forced self heal after a force_self_heal ability (RDM Convert) fired.
    -- Sits AFTER the critical branch on purpose: post-swap HP is usually below
    -- critical_threshold, so a critical boost JA (Divine Seal, Contradance)
    -- fires first — the flag survives it, and the forced cure lands boosted on
    -- the following tick. Critical heals for party members are likewise never
    -- blocked by the in-flight hold below (critical JAs cost no MP).
    if force_self.active then
        local player_hpp = state.player.hpp
        local elapsed    = os.clock() - force_self.ts
        if elapsed > FORCE_SELF_TIMEOUT then
            force_self.active = false
        elseif (state.player.mpp or 0) < (settings.recover_mp_threshold or 0) then
            -- MP still pre-swap: Convert hasn't resolved yet. Hold healing so we
            -- don't size a cure to (or burn) the MP that's about to become HP.
            -- Plain < rather than below_threshold: that helper treats 0 as
            -- dead/invalid, but 0 MP here (drained between the send and the
            -- 0x028, e.g. an Aspir) is still pre-swap and must keep holding —
            -- below_threshold would misread it as the swap having landed and
            -- clear the flag against pre-swap HP.
            if elapsed <= FORCE_SELF_WAIT_TIMEOUT then
                return nil
            end
            -- Swap never landed (command eaten): give up, resume normal logic
            force_self.active = false
        elseif not common.below_threshold(player_hpp, settings.heal_threshold or 75) then
            -- Swap landed but HP is fine (someone healed us first): no forced heal
            force_self.active = false
        else
            local selected_ability = heal.select_ability(available_abilities, player_hpp, job_def, player_resource, 0, nil, settings)
            if selected_ability then
                -- Check stratagems before casting
                local strat_result = common.check_stratagem(job_def, settings, selected_ability.name, selected_ability)
                if strat_result == false then return nil
                elseif strat_result then return strat_result end

                local command = common.build_ability_command(selected_ability, 0)
                if command then
                    force_self.active = false
                    common.debugf('[HEAL] >>> Forced self heal with %s', selected_ability.name)
                    return {
                        command = command,
                        description = string.format('Forced self-heal with %s (HP: %.1f%%)', selected_ability.name, player_hpp)
                    }
                end
            end
            -- Nothing castable this tick (silence, cooldowns): fall through, flag stays set
        end
    end

    -- Priority 2: Focus target (party or tracked or alliance)
    if settings.focus_enabled and settings.focus_target and party_status.focus_needs_heal then
        -- Case A: Focus is a tracked target
        if focus_tracked_sid and state.tracked[focus_tracked_sid] then
            local tt = state.tracked[focus_tracked_sid]
            local focus_hpp = tt.hpp or 0
            local focus_target_index = tt.target_index or 0
            if focus_target_index > 0 and common.is_active_member(focus_hpp) then
                local outside_abilities = common.outside_abilities(available_abilities)
                local selected_ability = heal.select_ability(outside_abilities, focus_hpp, job_def, player_resource, nil, tt, settings)
                if selected_ability then
                    -- Check stratagems before casting
                    local strat_result = common.check_stratagem(job_def, settings, selected_ability.name, selected_ability)
                    if strat_result == false then return nil
                    elseif strat_result then return strat_result end

                    local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                    if common.is_in_range(focus_target_index, ability_range) then
                        local command = common.build_ability_command_for_target(selected_ability, focus_tracked_sid)
                        if command then
                            -- Register pending buff for packet tracking
                            if selected_ability.buff_id then
                                local bid = type(selected_ability.buff_id) == 'table' and selected_ability.buff_id[1] or selected_ability.buff_id
                                common.register_pending_buff(focus_tracked_sid, bid)
                            end
                            common.debugf('[HEAL] >>> Healing tracked focus target %s with %s', tt.name, selected_ability.name)
                            return {
                                command = command,
                                description = string.format('Healing focus target %s with %s (HP: %.1f%%)', tt.name, selected_ability.name, focus_hpp)
                            }
                        end
                    end
                end
            end
        -- Case A2: Focus is an alliance member
        elseif focus_alliance_sid then
            local al_member = common.find_alliance_member(state, focus_alliance_sid)
            if al_member and al_member.is_active and al_member.target_index and al_member.target_index > 0 then
                local focus_hpp = al_member.hpp or 0
                if common.is_active_member(focus_hpp) then
                    local outside_abilities = common.outside_abilities(available_abilities)
                    local selected_ability = heal.select_ability(outside_abilities, focus_hpp, job_def, player_resource, nil, al_member, settings)
                    if selected_ability then
                        -- Check stratagems before casting
                        local strat_result = common.check_stratagem(job_def, settings, selected_ability.name, selected_ability)
                        if strat_result == false then return nil
                        elseif strat_result then return strat_result end

                        local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                        if common.is_in_range(al_member.target_index, ability_range) then
                            local command = common.build_ability_command_for_target(selected_ability, focus_alliance_sid)
                            if command then
                                if selected_ability.buff_id then
                                    local bid = type(selected_ability.buff_id) == 'table' and selected_ability.buff_id[1] or selected_ability.buff_id
                                    common.register_pending_buff(focus_alliance_sid, bid)
                                end
                                common.debugf('[HEAL] >>> Healing alliance focus %s with %s', al_member.name, selected_ability.name)
                                return {
                                    command = command,
                                    description = string.format('Healing alliance focus %s with %s (HP: %.1f%%)', al_member.name, selected_ability.name, focus_hpp)
                                }
                            end
                        end
                    end
                end
            end
        -- Case B: Focus is a party member
        elseif focus_party_idx then
            local focus_member = focus_party_idx == 0 and state.player or state.party[focus_party_idx]
            local focus_target_index = focus_member and focus_member.target_index
            if focus_target_index and focus_target_index > 0 then
                local focus_hpp = nil
                for _, member in ipairs(party_status.needs_heal) do
                    if member.target_index == focus_target_index then
                        focus_hpp = member.hpp
                        break
                    end
                end
                
                if focus_hpp then
                    local focus_party_index = focus_party_idx
                    if not focus_party_index then
                        return nil
                    end
                    
                    local selected_ability = heal.select_ability(available_abilities, focus_hpp, job_def, player_resource, focus_party_index, nil, settings)
                    
                    if selected_ability and focus_party_index then
                        -- Check stratagems before casting
                        local strat_result = common.check_stratagem(job_def, settings, selected_ability.name, selected_ability)
                        if strat_result == false then return nil
                        elseif strat_result then return strat_result end

                        local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                        if not common.is_in_range(focus_target_index, ability_range) then
                            return nil
                        end
                        local command = common.build_ability_command(selected_ability, focus_party_index)
                        if command then
                            common.debugf('[HEAL] >>> Healing focus target with %s', selected_ability.name)
                            return {
                                command = command,
                                description = string.format('Healing focus target with %s (HP: %.1f%%)', selected_ability.name, focus_hpp)
                            }
                        end
                    end
                end
            end
        end
    end
    
    -- Priority 3: Lowest HP party member
    if party_status.lowest_hp_index then
        local lowest_hp_member = party_status.lowest_hp_index == 0 and state.player or state.party[party_status.lowest_hp_index]
        local target_index = lowest_hp_member and lowest_hp_member.target_index
        if target_index and target_index > 0 then
            local selected_ability = heal.select_ability(available_abilities, party_status.lowest_hp_percent, job_def, player_resource, party_status.lowest_hp_index, nil, settings)
            if selected_ability then
                -- Check stratagems before casting
                local strat_result = common.check_stratagem(job_def, settings, selected_ability.name, selected_ability)
                if strat_result == false then return nil
                elseif strat_result then return strat_result end

                local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                if not common.is_in_range(target_index, ability_range) then
                    -- Don't return nil yet, check tracked targets below
                else
                    local command = common.build_ability_command(selected_ability, party_status.lowest_hp_index)
                    if command then
                        return {
                            command = command,
                            description = string.format('Healing %s with %s (HP: %.1f%%)', 
                                (lowest_hp_member and lowest_hp_member.name or 'party member'),
                                selected_ability.name,
                                party_status.lowest_hp_percent)
                        }
                    end
                end
            end
        end
    end

    -- Priority 4: Lowest HP tracked target (outside party)
    if party_status.lowest_tracked_sid and state.tracked then
        local tt = state.tracked[party_status.lowest_tracked_sid]
        if tt and tt.is_active and tt.target_index and tt.target_index > 0 then
            local outside_abilities = common.outside_abilities(available_abilities)
            if #outside_abilities > 0 then
                local selected_ability = heal.select_ability(outside_abilities, party_status.lowest_tracked_hpp, job_def, player_resource, nil, tt, settings)
                if selected_ability then
                    -- Check stratagems before casting
                    local strat_result = common.check_stratagem(job_def, settings, selected_ability.name, selected_ability)
                    if strat_result == false then return nil
                    elseif strat_result then return strat_result end

                    local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                    if common.is_in_range(tt.target_index, ability_range) then
                        local command = common.build_ability_command_for_target(selected_ability, party_status.lowest_tracked_sid)
                        if command then
                            if selected_ability.buff_id then
                                local bid = type(selected_ability.buff_id) == 'table' and selected_ability.buff_id[1] or selected_ability.buff_id
                                common.register_pending_buff(party_status.lowest_tracked_sid, bid)
                            end
                            return {
                                command = command,
                                description = string.format('Healing tracked %s with %s (HP: %.1f%%)',
                                    tt.name, selected_ability.name, party_status.lowest_tracked_hpp)
                            }
                        end
                    end
                end
            end
        end
    end

    -- Priority 5: Lowest HP alliance member (target_outside abilities only)
    if party_status.lowest_alliance_sid and state.alliance then
        local al_member = common.find_alliance_member(state, party_status.lowest_alliance_sid)
        if al_member and al_member.is_active and al_member.target_index and al_member.target_index > 0 then
            local outside_abilities = common.outside_abilities(available_abilities)
            if #outside_abilities > 0 then
                local selected_ability = heal.select_ability(outside_abilities, party_status.lowest_alliance_hpp, job_def, player_resource, nil, al_member, settings)
                if selected_ability then
                    -- Check stratagems before casting
                    local strat_result = common.check_stratagem(job_def, settings, selected_ability.name, selected_ability)
                    if strat_result == false then return nil
                    elseif strat_result then return strat_result end

                    local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                    if common.is_in_range(al_member.target_index, ability_range) then
                        local command = common.build_ability_command_for_target(selected_ability, party_status.lowest_alliance_sid)
                        if command then
                            if selected_ability.buff_id then
                                local bid = type(selected_ability.buff_id) == 'table' and selected_ability.buff_id[1] or selected_ability.buff_id
                                common.register_pending_buff(party_status.lowest_alliance_sid, bid)
                            end
                            return {
                                command = command,
                                description = string.format('Healing alliance %s with %s (HP: %.1f%%)',
                                    al_member.name, selected_ability.name, party_status.lowest_alliance_hpp)
                            }
                        end
                    end
                end
            end
        end
    end

    return nil
end

function heal.select_ability(abilities, target_hpp, job_def, player_resource, party_index, target_snapshot, settings)
    -- Drop self-only heals (BLU Pollen) when the target isn't the player;
    -- their <me> command would silently heal the caster instead.
    if party_index ~= 0 then
        local others = {}
        for _, a in ipairs(abilities) do
            if not a.self_only then table.insert(others, a) end
        end
        abilities = others
    end

    -- Special case: Summoner should always try Healing Ruby first
    if job_def and job_def.job_id == 15 then
        -- Look for Healing Ruby in abilities
        for _, ability in ipairs(abilities) do
            if ability.name == 'Healing Ruby' then
                -- Check if usable: has pet, has resource, not on cooldown
                if common.targets.get_pet() then
                    local ability_resource_type = ability.resource_type or job_def.resource_type
                    if action_core.has_resource(ability_resource_type, ability.cost) then
                        local is_ready = true
                        if ability.recast_id then
                            is_ready = action_core.is_ability_ready(ability.recast_id)
                        end
                        if is_ready then
                            return ability
                        end
                    else
                    end
                else
                end
                break
            end
        end
    end
    
    -- Calculate HP deficit for target
    local hp_deficit = 0
    if party_index then
        local snapshot     = common.game_state
        local target_member = snapshot and (party_index == 0 and snapshot.player or snapshot.party[party_index])
        if target_member then
            local current_hp = target_member.hp
            local max_hp     = target_member.max_hp
            if current_hp and max_hp and max_hp > 0 then
                hp_deficit = max_hp - current_hp
            end
        end
    elseif target_snapshot then
        local current_hp = target_snapshot.hp
        local max_hp     = target_snapshot.max_hp
        if current_hp and max_hp and max_hp > 0 then
            hp_deficit = max_hp - current_hp
        end
    end
    
    -- Filter abilities by resource availability and cooldowns
    local usable_abilities = action_core.filter_usable(abilities, job_def, nil, settings)
    
    if #usable_abilities == 0 then
        return nil
    end
    
    -- Gear-augmented potency (+x% from /sk panel) scales each ability's base
    -- value: waltz_potency for TP heals (Waltzes), cure_potency for MP heals.
    local function potency_value(ability)
        local rtype = ability.resource_type or (job_def and job_def.resource_type)
        local pct = (rtype == 'tp') and settings.waltz_potency or settings.cure_potency
        return math.floor((tonumber(ability.value) or 0) * (1 + (pct or 0) / 100))
    end

    -- If we have HP deficit info, select based on heal value
    if hp_deficit > 0 then
        -- Sort by value descending (largest to smallest heal)
        table.sort(usable_abilities, function(a, b)
            return potency_value(a) > potency_value(b)
        end)

        -- Find the largest heal that fits within the deficit (round down approach)
        local best_ability = nil
        for _, ability in ipairs(usable_abilities) do
            local ability_value = potency_value(ability)
            if ability_value > 0 and ability_value <= hp_deficit then
                best_ability = ability
                return best_ability
            end
        end
        
        -- If no heal fits within the deficit, use the smallest available (least overheal)
        best_ability = usable_abilities[#usable_abilities]
        return best_ability
    else
        -- Fallback: no HP deficit info, use first available (already sorted by cost descending)
        return usable_abilities[1]
    end
end

-- ============================================================================
-- AOE Healing  (formerly lib.actions.heal_aoe)
-- ============================================================================

-- An AOE heal radiates from its TARGET and lands on that target's party, so each
-- party of the alliance is averaged on its own and healed through its lowest
-- member. Party slots carry party_index (0-5); alliance members carry only their
-- server id and are reachable by target_outside abilities alone.
local function aoe_groups(state, group_allowed, threshold)
    local function add(g, m, party_index)
        local hpp = m.hpp or 0
        if not common.is_active_member(hpp) or common.is_trust_excluded(m.name, m.server_id) then return end
        g.total = g.total + hpp
        g.count = g.count + 1
        if common.below_threshold(hpp, threshold) then
            table.insert(g.hurt, { m = m, hpp = hpp, party_index = party_index })
        end
    end

    local groups = { { own = true, total = 0, count = 0, hurt = {} } }
    for i = 0, 5 do
        local m = i == 0 and state.player or state.party[i]
        if m and group_allowed(i) then add(groups[1], m, i) end
    end
    for al_pi = 2, 3 do
        local sub = state.alliance and state.alliance[al_pi]
        if sub then
            local g = { total = 0, count = 0, hurt = {} }
            for local_idx, m in pairs(sub) do
                if m and m.is_active and m.target_index and m.target_index > 0
                    and group_allowed('al_' .. ((al_pi - 1) * 6 + local_idx), true) then
                    add(g, m, nil)
                end
            end
            table.insert(groups, g)
        end
    end

    for _, g in ipairs(groups) do
        g.avg = g.count > 0 and (g.total / g.count) or 100
        table.sort(g.hurt, function(a, b) return a.hpp < b.hpp end)
    end
    return groups
end

-- Groups with at least min_hurt members below threshold (and, when need_avg, an
-- average below it too), neediest first -- by their lowest member's HP.
local function needy_groups(groups, min_hurt, need_avg, threshold)
    local out = {}
    for _, g in ipairs(groups) do
        if #g.hurt >= min_hurt and (not need_avg or common.below_threshold(g.avg, threshold)) then
            table.insert(out, g)
        end
    end
    table.sort(out, function(a, b) return a.hurt[1].hpp < b.hurt[1].hpp end)
    return out
end

-- Command aiming a targetable ability (function command) at hurt member t, or nil
-- when t is out of range or outside the party for a party-only ability.
local function aim(a, t)
    local tidx = t.m.target_index
    if not (tidx and tidx > 0 and common.is_in_range(tidx, type(a.range) == 'number' and a.range or 21)) then
        return nil
    end
    if t.party_index then return common.build_ability_command(a, t.party_index) end
    return a.target_outside and common.build_ability_command_for_target(a, t.m.server_id) or nil
end

-- A string command is self-centred (Healing Breeze, Mending Halation, Healing Ruby II)
-- and only ever covers the caster's own party.
local function aoe_command(a, g, t)
    if type(a.command) ~= 'function' then
        return g.own and a.command or nil
    end
    return aim(a, t)
end

function heal.execute_aoe(settings, job_def)
    if not settings.heal_aoe_enabled then return nil end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end

    local abilities = common.filter_abilities_by_level(
        job_def.abilities.heal_aoe or {}, settings,
        player.main_level, player.sub_level, job_def)
    abilities = action_core.filter_self_buff_blocked(abilities, player.buffs)
    if #abilities == 0 then return nil end

    local threshold = settings.heal_aoe_threshold or 70
    local groups    = aoe_groups(state, make_group_filter('heal_aoe_group'), threshold)
    -- The bar for STARTING an AOE heal: 2+ members of one party below threshold and
    -- that party's average below it too. The buff-already-up branch below runs on a
    -- looser gate (the charge is already spent).
    local ready = needy_groups(groups, 2, true, threshold)

    -- An aoe_precast entry (SCH Accession) is a JA that heals nothing on its own: it
    -- makes the NEXT single-target cure land on everyone in range. Split it out of the
    -- list -- the plain loop would otherwise fire the bare JA as though it were the heal.
    -- Keyed off the data flag, not the job id, so any job that gains one is covered.
    local precast, plain = nil, {}
    for _, a in ipairs(abilities) do
        if a.aoe_precast then precast = a else table.insert(plain, a) end
    end

    -- The cure an aoe_precast entry would spread onto hurt member t: this job's
    -- single-target heals, narrowed to the spells the stratagem applies to, aimed at t
    -- (the spell radiates from its TARGET, not the caster). Consulted BEFORE the JA
    -- fires, so a charge is never spent on a tick where no cure could follow.
    -- Returns the cure and its command.
    local function paired_cure(t)
        local mp    = action_core.get_resource(job_def.resource_type)
        local cures = {}
        for _, a in ipairs(common.filter_abilities_by_level(
            job_def.abilities.heal or {}, settings,
            player.main_level, player.sub_level, job_def)) do
            -- Budgeted at the doubled cost Accession will charge, before the buff -- and
            -- so effective_ability_cost -- knows anything about it.
            if common.stratagem_applies(precast, a)
                and (t.party_index or a.target_outside)
                and math.floor((a.cost or 0) * precast.mp_modifier) <= mp then
                table.insert(cures, a)
            end
        end
        local cure = heal.select_ability(cures, t.hpp, job_def, nil, t.party_index,
            not t.party_index and t.m or nil, settings)
        local command = cure and aim(cure, t)
        if command then return cure, command end
        return nil
    end

    -- Buff already up: the follow-up tick, or the player raised Accession by hand. The
    -- charge is already spent, so one member below threshold is enough -- but not zero,
    -- or a hand-pressed Accession would fire a cure into a full-HP party.
    if precast and common.has_buff(0, precast.buff_id) then
        for _, g in ipairs(needy_groups(groups, 1, false, threshold)) do
            local t = g.hurt[1]
            -- Cast the cure directly and let it land as an AOE. Deliberately NOT routed
            -- through common.check_stratagem -- a stratagem the user assigned to Cure via
            -- the S popup would spend a second charge here and break the follow-up lock.
            local cure, command = paired_cure(t)
            if command then
                return {
                    command = command,
                    description = string.format('AOE healing %s with %s (avg HP: %.1f%%)',
                        t.m.name or 'party member', cure.name, g.avg),
                }
            end
        end
    end

    if #ready == 0 then return nil end

    -- A real AOE heal outranks the precast: a free Curaga beats a charge plus double MP.
    -- Aimed at the neediest party's lowest member it can reach; no Hold AOE for Group
    -- gate -- that is a buff setting, and healing is too urgent to wait on a gather.
    for _, g in ipairs(ready) do
        for _, a in ipairs(plain) do
            local eff_cost = common.effective_ability_cost(a, settings, job_def)
            if action_core.is_usable(a, job_def, eff_cost) then
                for _, t in ipairs(g.hurt) do
                    local command = aoe_command(a, g, t)
                    if command then
                        -- Stratagems only once the heal is known to be castable here.
                        local strat_result = common.check_stratagem(job_def, settings, a.name, a)
                        if strat_result then return strat_result end
                        if strat_result == nil then
                            return {
                                command = command,
                                description = string.format('AOE healing %s with %s (avg HP: %.1f%%)',
                                    t.m.name or 'party member', a.name, g.avg),
                            }
                        end
                        break
                    end
                end
            end
        end
    end

    -- Fire the JA: cheap gates first (charge, arts stance, silence/movement), and only
    -- then confirm a cure could actually follow it. The buff check guards the branch above
    -- falling through (server id unresolved, so no command could be built) -- re-firing
    -- would spend a second charge on a buff the player already holds.
    if precast
        and not common.has_buff(0, precast.buff_id)
        and (common.game_state.stratagems or 0) >= 1
        and action_core.has_any_buff(player.buffs, precast.requires_buff)
        and not common.is_command_blocked(precast.command) then
        for _, g in ipairs(ready) do
            if paired_cure(g.hurt[1]) then
                -- is_stratagem reuses automation.lua's follow-up lock, which re-runs ONLY
                -- this module next tick so nothing pre-empts the paired cure -- which is
                -- why no cross-module "forced heal" flag is needed.
                return {
                    command      = precast.command,
                    description  = string.format('Using %s (avg HP: %.1f%%)', precast.name, g.avg),
                    is_stratagem = true,
                }
            end
        end
    end

    return nil
end

-- ============================================================================
-- Pet Healing  (formerly lib.actions.heal_pet)
-- ============================================================================

function heal.execute_pet(settings, job_def)
    if not settings.heal_pet_enabled      then return nil end
    if not common.targets.get_pet()       then return nil end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end

    local pet_hpp   = player.pet_hpp
    local threshold = settings.heal_pet_threshold or 50
    if not common.below_threshold(pet_hpp, threshold) then return nil end

    -- Auto-equip: a pet-heal that needs a consumable in the ammo slot (BST food,
    -- PUP oil) can't fire until one is worn. If a usable tier is owned but not
    -- equipped, equip the best one now (the heal fires a later tick). If none are
    -- owned, nothing happens and the ability stays gated out -- effectively disabled.
    local equip = common.ammo_equip_command(job_def.abilities.heal_pet, settings, player)
    if equip then return equip end

    local abilities = common.filter_abilities_by_level(
        job_def.abilities.heal_pet or {}, settings,
        player.main_level, player.sub_level, job_def)
    if #abilities == 0 then return nil end

    return action_core.first_command(abilities, job_def, settings, '[HEAL_PET]', nil,
        function(a) return string.format('Healing pet with %s (Pet HP: %.1f%%)', a.name, pet_hpp) end)
end

return heal
