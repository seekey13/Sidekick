--[[
    Geo action module
    Handles Full Circle when player is far from pet luopan
    Handles Entrust + Indi spell casting on party members
]]--

local geo = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- Current luopan was placed by a Geo-bt (enemy debuff) cast. Keeps the
-- distance-based Full Circle off our debuff luopan, and dismisses it when combat
-- ends. An addon reload mid-combat resets it, costing one redundant Full Circle.
local geo_bt_pending = false

-- os.clock() when combat ended with a Geo-bt luopan still out. Starts the
-- geo_bt_timer grace period before Full Circle dismisses it, so a fresh battle
-- target can reuse the luopan.
local geo_bt_end_time = nil

-- os.clock() of a Geo-bt cast, cleared once its luopan spawns. Covers the gap
-- where the entity has not registered yet, which would otherwise clear
-- geo_bt_pending and Full Circle the luopan the instant it lands.
local geo_bt_cast_time = nil

-- Luopan was out on the previous execute(), so its disappearance can be detected
-- (see clear_tracked_geo_buffs).
local had_luopan = false

-- os.clock() of the Geo-Voidance cast in flight. The "luopan is our throwaway
-- Radial Arcana bubble" flag itself lives on common.arcana_luopan (the job's
-- validate_ability reads it) and is only raised once the luopan spawns. Expires
-- so an interrupted cast cannot wedge the sequence.
local arcana_cast_time = nil

-- os.clock() cutoff for the Radial Arcana sequence, nil when none is running.
-- A deadline rather than a flag because it must survive the Full Circle refund
-- lifting us back over the recovery threshold and the JA recast reading
-- not-ready for a few ticks after the Full Circle.
local arcana_deadline = nil
local ARCANA_SEQUENCE_TIMEOUT = 20

-- os.clock() when Radial Arcana was sent. Its recast lags, so without this the JA
-- reads ready, MP is still low, and a second sequence arms immediately.
local arcana_spent_time = nil
local ARCANA_SPENT_GRACE = 10

-- execute() runs every frame (only sends are throttled), so "waiting on X" lines
-- need rate limiting or they bury the log.
local last_hold_log = 0
local function hold_log(fmt, ...)
    if os.clock() - last_hold_log >= 2 then
        last_hold_log = os.clock()
        common.debugf(fmt, ...)
    end
end

-- A luopan costing more than this is kept; only Full Circled for Radial Arcana
-- once nearly spent (ARCANA_HPP_FLOOR).
local ARCANA_KEEP_COST = 75
local ARCANA_HPP_FLOOR = 5

-- Luopan gone means its Geo auras died with it. Real members self-correct from
-- memory, but Trust buffs are packet-tracked and an aura ending with its luopan
-- sends no wear-off packet -- the stale entry would make buff.lua skip the recast.
-- Group 'Geo' only: Indi follows the caster, Geo-bt ids live on the enemy.
local function clear_tracked_geo_buffs(job_def)
    local party = common.game_state and common.game_state.party
    if not party then return end

    for _, ability in ipairs(job_def.abilities.buff or {}) do
        if ability.group == 'Geo' then
            for _, buff_id in ipairs(action_core.normalize_ids(ability.buff_id)) do
                for _, member in pairs(party) do
                    if member and member.server_id then
                        common.handle_buff_removal(member.server_id, buff_id)
                    end
                end
            end
        end
    end
end

-- Geo-bt ability to maintain in combat, or nil. Honors the selected_Geo-bt
-- dropdown, else highest cost. filter_abilities_by_level applies the level +
-- <bt> combat gate, so this is nil out of combat or under-leveled.
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

-- Party slot the Geo bubble belongs to (0 = ME, 1-5 = party member), or nil.
-- Indexed rather than pairs(): undefined order would resolve differently between
-- callers if two toggles are briefly on at once.
local function selected_geo_target(ui_config)
    local party_buffs = ui_config.get_party_buffs()
    local geo_targets = party_buffs and party_buffs['Geo']
    if not geo_targets then return nil end
    for idx = 0, 5 do
        if geo_targets[idx] == true then return idx end
    end
    return nil
end

-- Geo spell that would be cast next, or nil: the <bt> debuff in combat, else the
-- selected Geo buff tier if its target still needs it. Tells Blaze of Glory
-- whether there is anything to enhance.
local function next_geo_spell(job_def, settings, main_level, sub_level, geo_bt, in_combat)
    if in_combat and geo_bt then return geo_bt end

    -- Geo buff group: one enabled target (single luopan) that lacks the buff.
    local target_index = selected_geo_target(require('lib.ui.config'))
    if not target_index then return nil end

    local candidates = {}
    for _, ability in ipairs(job_def.abilities.buff or {}) do
        if ability.group == 'Geo' then
            table.insert(candidates, ability)
        end
    end
    local available = common.filter_abilities_by_level(candidates, settings, main_level, sub_level, job_def)
    if #available == 0 then return nil end

    local spell = available[1]  -- cost-sorted fallback, same rule buff.lua uses
    local selected_name = settings['selected_Geo']
    if selected_name then
        spell = nil
        for _, ability in ipairs(available) do
            if ability.name == selected_name then spell = ability break end
        end
        if not spell then return nil end
    end

    local state = common.game_state
    local target_buffs
    if target_index == 0 then
        target_buffs = state.player.buffs or {}
    else
        local member = state.party[target_index]
        if not member then return nil end
        target_buffs = member.buffs or {}
    end
    if not action_core.needs_buff(target_buffs, spell.buff_id) then return nil end

    return spell
end

-- Blaze of Glory enhances the luopan the next Geo spell creates, so it is a
-- precast: callers only reach here with no luopan out, and it is held unless that
-- spell is affordable so the 10-minute recast isn't burned for nothing.
-- Recast checked before next_geo_spell (which allocates + filters) because this
-- runs every frame the luopan slot is empty.
local function try_blaze_of_glory(job_def, settings, main_level, sub_level, geo_bt, in_combat)
    local geo_abilities = common.filter_abilities_by_level(job_def.abilities.geo or {}, settings, main_level, sub_level, job_def)
    local bog
    for _, ability in ipairs(geo_abilities) do
        if ability.name == 'Blaze of Glory' then bog = ability break end
    end
    if not bog or not action_core.is_ability_recast_zero(bog.recast_id) then return nil end

    local next_spell = next_geo_spell(job_def, settings, main_level, sub_level, geo_bt, in_combat)
    if not next_spell then return nil end
    if not action_core.has_resource(job_def.resource_type, next_spell.cost or 0) then return nil end

    return action_core.try_use(bog, job_def, settings, 0,
        string.format('Blaze of Glory (precast for %s)', next_spell.name))
end

-- Full Circle result if usable right now, else nil. Callers ensure a luopan is out.
local function try_full_circle(job_def, settings, main_level, sub_level, description)
    local geo_abilities = common.filter_abilities_by_level(job_def.abilities.geo or {}, settings, main_level, sub_level, job_def)
    for _, ability in ipairs(geo_abilities) do
        if ability.name == 'Full Circle' then
            if common.is_command_blocked(ability.command) then return nil end
            local resource_type = ability.resource_type or job_def.resource_type
            if ability.recast_id and action_core.has_resource(resource_type, ability.cost) and action_core.is_ability_ready(ability.recast_id) then
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

-- Radial Arcana when level-appropriate and enabled, cooldown ignored. Looked up
-- directly, not via filter_abilities_by_level, because validate_ability hides it
-- while outside the bubble -- the situation this module exists to fix. try_use
-- re-checks the recast, so the cooldown only gates *starting* a sequence.
local function arcana_ability(job_def, settings, main_level)
    -- Key must match the UI's 'disabled_' .. name with spaces as underscores
    -- (lib/ui/components.lua).
    if settings['disabled_Radial_Arcana'] == true then return nil end
    for _, ability in ipairs(job_def.abilities.recover_mp or {}) do
        if ability.name == 'Radial Arcana' then
            if (ability.level or 1) <= (main_level or 0) then
                return ability
            end
            return nil
        end
    end
    return nil
end

-- MP cost of the Geo spell holding the luopan, so an expensive bubble is not
-- thrown away for one Radial Arcana. Geo-bt owns it in combat; otherwise it is the
-- tier buff.lua would have cast: the named selection, else the most EXPENSIVE
-- castable one (buff.lua takes [1] of a cost-descending list -- the job list is
-- level-ordered, so scanning it raw picks the wrong, cheaper spell).
-- Level/learned gates are hand-applied because validate_ability hides group 'Geo'
-- whenever a luopan is out, which is the only time this is called.
local function current_luopan_cost(job_def, settings, geo_bt, main_level)
    if geo_bt_pending then return (geo_bt and geo_bt.cost) or math.huge end
    local selected = settings['selected_Geo']
    local cost = 0
    for _, ability in ipairs(job_def.abilities.buff or {}) do
        if ability.group == 'Geo' and ability.is_main_job ~= false
            and (ability.level or 1) <= (main_level or 0)
            and common.has_spell_learned(ability) then
            if selected then
                if ability.name == selected then return ability.cost or 0 end
            elseif (ability.cost or 0) > cost then
                cost = ability.cost or 0
            end
        end
    end
    return cost
end

function geo.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Recomputed further down; cleared up front so an early return can't leave the
    -- JA gated against a stale bubble.
    common.arcana_usable = false

    -- Expired and published ahead of the guards below: the latch keeps buff.lua off
    -- the luopan slot even on ticks where geo itself is skipped (resting, disabled).
    if arcana_deadline and os.clock() >= arcana_deadline then
        arcana_deadline      = nil
        common.arcana_luopan = false
    end
    common.arcana_sequence = arcana_deadline ~= nil

    -- Geo-Voidance landed: mark the bubble ours so it is spendable whatever Geo tier
    -- is selected (current_luopan_cost can only guess from settings).
    if arcana_cast_time then
        if common.targets.get_pet() then
            common.arcana_luopan = true
            arcana_cast_time     = nil
        elseif os.clock() - arcana_cast_time > 8 then
            arcana_cast_time = nil  -- cast never landed; let the sequence retry
        end
    end

    -- Throwaway bubble is down: spend it, ahead of every guard below -- it exists for
    -- nothing else, so the MP threshold, resting, or geo being switched off must not
    -- strand it. recover.lua can't cover this: it is threshold-gated, and the Full
    -- Circle refund usually lifted us back over the threshold already.
    if common.arcana_luopan then
        local gs_player = common.game_state and common.game_state.player
        local ja = arcana_ability(job_def, settings, gs_player and gs_player.main_level or 0)
        common.arcana_usable = common.is_in_luopan_radius()
        if ja and common.arcana_usable then
            local result, reason = action_core.try_use(ja, job_def, settings, 0,
                string.format('Radial Arcana (MP: %.1f%%)', (gs_player and gs_player.mpp) or 0))
            if result then
                arcana_deadline        = nil
                arcana_spent_time      = os.clock()
                common.arcana_sequence = false
                common.arcana_luopan   = false
                return result
            end
            hold_log('[GEO] Radial Arcana held: %s', reason or 'unavailable')
        elseif not ja then
            hold_log('[GEO] Radial Arcana held: ability unavailable (level / disabled)')
        end
    end

    if not settings.geo_enabled then
        return nil
    end

    if common.is_resting() then
        return nil
    end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end
    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level

    -- Needed up here because every Full Circle below decides whether the slot it
    -- frees belongs to the arcana sequence. arcana_ja is the ability; arcana is it
    -- only while off cooldown, which gates *starting* a sequence.
    local arcana_ja = arcana_ability(job_def, settings, derived_main_level)
    local just_spent = arcana_spent_time ~= nil
        and (os.clock() - arcana_spent_time) < ARCANA_SPENT_GRACE
    local arcana = (arcana_ja and not just_spent
        and action_core.is_ability_ready(arcana_ja.recast_id)) and arcana_ja or nil
    local mp_low = settings.recover_enabled == true
        and common.below_threshold(player.mpp or 0, settings.recover_mp_threshold or 30)

    local arcana_sequence = arcana_deadline ~= nil

    -- Any Full Circle empties the luopan slot, whatever fired it. If MP was low and
    -- Radial Arcana is up, claim that empty slot for the sequence.
    local function full_circle(description)
        local fc = try_full_circle(job_def, settings, derived_main_level, derived_sub_level, description)
        if fc and arcana and mp_low then
            arcana_deadline = os.clock() + ARCANA_SEQUENCE_TIMEOUT
            common.arcana_sequence = true
            common.debugf('[GEO] Full Circle frees the luopan; claiming it for Radial Arcana (MP: %.1f%%)', player.mpp or 0)
        end
        return fc
    end

    -- Lazy require to avoid a circular require; shared with the Entrust logic below.
    local ui_config = require('lib.ui.config')

    -- ========================================================================
    -- Geo-bt Logic (enemy <bt> debuffs)
    -- Geo-bt claims the luopan during combat, Full Circled when combat ends. The
    -- enemy debuff is unreadable, so our own luopan is the "already applied" signal.
    -- ========================================================================
    local geo_bt     = get_selected_geo_bt(job_def, settings, derived_main_level, derived_sub_level)
    local in_combat  = common.is_combat()
    local has_luopan = common.targets.get_pet() ~= nil

    -- Luopan spawned: cast no longer in flight.
    if has_luopan then
        geo_bt_cast_time = nil
    end

    -- Luopan went away (Full Circle, expiry, killed): drop its packet-tracked auras.
    -- Keyed on the entity disappearing so every way of losing it is covered. Leaves
    -- common.arcana_luopan alone -- the pet can read absent for a tick while Radial
    -- Arcana resolves; that flag is cleared where the sequence genuinely ends.
    if had_luopan and not has_luopan then
        clear_tracked_geo_buffs(job_def)
    end
    had_luopan = has_luopan

    -- Debuff luopan gone (expired / target died): clear tracking, ignoring the window
    -- right after a cast where the entity has not registered yet.
    if geo_bt_pending and not has_luopan then
        if not geo_bt_cast_time or (os.clock() - geo_bt_cast_time) > 8 then
            geo_bt_pending = false
            geo_bt_end_time = nil
            geo_bt_cast_time = nil
        end
    end

    -- Battle target present: cancel the combat-ended countdown so a fresh <bt> reuses
    -- the existing luopan instead of Full Circle + recast.
    if in_combat then
        geo_bt_end_time = nil
    end

    -- Combat over with the Geo-bt luopan still out: dismiss it after geo_bt_timer so
    -- the slot is free for Geo <me> buffs again.
    if geo_bt_pending and not in_combat and has_luopan then
        if not geo_bt_end_time then
            geo_bt_end_time = os.clock()
        elseif os.clock() - geo_bt_end_time >= (settings.geo_bt_timer or 5) then
            local fc = full_circle('Full Circle (dismissing Geo-bt luopan, combat ended)')
            if fc then return fc end
        end
    end

    -- ========================================================================
    -- Radial Arcana
    -- Consumes the luopan and only refills members inside its aura, so the bubble it
    -- eats must be affordable to lose and one we stand in. Cheap or nearly-spent
    -- qualifies; a fresh expensive one refunds more via Full Circle than Radial
    -- Arcana yields, so it is Full Circled and replaced with a throwaway
    -- Geo-Voidance on <me> first.
    -- ========================================================================
    -- Published for the job's validate_ability, which gates Radial Arcana on it.
    local spendable = has_luopan and (common.arcana_luopan
        or current_luopan_cost(job_def, settings, geo_bt, derived_main_level) <= ARCANA_KEEP_COST
        or (player.pet_hpp or 100) <= ARCANA_HPP_FLOOR)
    common.arcana_usable = spendable and common.is_in_luopan_radius()

    -- The throwaway bubble is spent at the top of execute; a spendable luopan that
    -- is not ours is left to recover.lua's threshold.

    -- Not spendable / out of range: build a bubble we can spend. Once armed the
    -- sequence drives itself -- neither the MP threshold nor a momentarily not-ready
    -- recast may cancel it, or buff.lua refills the slot with the expensive spell.
    if ((arcana and mp_low) or arcana_sequence) and not common.arcana_usable and not arcana_cast_time then
        if has_luopan then
            local fc = full_circle(string.format(
                'Full Circle (luopan too dear for Radial Arcana, MP: %.1f%%)', player.mpp or 0))
            if fc then return fc end
        else
            local voidance
            for _, ability in ipairs(job_def.abilities.buff or {}) do
                if ability.name == 'Geo-Voidance' then voidance = ability break end
            end
            if voidance and (voidance.level or 1) <= derived_main_level
                and settings['disabled_Geo-Voidance'] ~= true
                and common.has_spell_learned(voidance) then
                local result, reason = action_core.try_use(voidance, job_def, settings, 0,
                    'Geo-Voidance on self (bubble for Radial Arcana)')
                if result then
                    arcana_cast_time = os.clock()
                    arcana_deadline = os.clock() + ARCANA_SEQUENCE_TIMEOUT
                    common.arcana_sequence = true
                    return result
                end
                hold_log('[GEO] Radial Arcana bubble on hold: Geo-Voidance %s', reason or 'unavailable')
            else
                hold_log('[GEO] Radial Arcana bubble on hold: Geo-Voidance unusable (level / disabled / not learned)')
            end
        end
    end

    -- ponytail: no dedicated teardown for a stranded Geo-Voidance bubble -- the
    -- deadline lapse releases the Geo group again and the existing luopan-drift /
    -- Geo-bt-takeover Full Circles clear it. Add one if it is seen to linger.

    -- Blaze of Glory precast: only with the slot free and a Geo spell pending. Runs
    -- ahead of the Geo-bt cast below and of buff.lua's Geo <me> cast.
    if not has_luopan then
        local bog = try_blaze_of_glory(job_def, settings, derived_main_level, derived_sub_level,
            geo_bt, in_combat)
        if bog then return bog end
    end

    -- In combat with a Geo-bt debuff selected: make sure the luopan is ours.
    if geo_bt and in_combat then
        if has_luopan and not geo_bt_pending then
            -- A non-debuff luopan holds the slot; take it over for this fight.
            local fc = full_circle('Full Circle (Geo-bt taking the luopan)')
            if fc then return fc end
        elseif not has_luopan then
            local result = action_core.first_command({ geo_bt }, job_def, settings, '[GEO-BT]', 0,
                function(ability) return string.format('Geo-bt: %s on battle target', ability.name) end)
            if result then
                geo_bt_pending = true
                geo_bt_cast_time = os.clock()
                return result
            end
        end
        -- else: our debuff luopan is already up — nothing to do.
    end

    -- ========================================================================
    -- Full Circle Logic
    -- ========================================================================

    -- Skip while our own Geo-bt luopan is out so the distance check can't dismiss
    -- the debuff.
    if common.targets.get_pet() and not geo_bt_pending then
        -- Measured from whichever target holds the bubble; no selection, no check.
        local selected_target_index = selected_geo_target(ui_config)  -- 0 = ME, 1-5 = party

        local pet_distance = selected_target_index ~= nil
            and common.get_pet_distance_from_member(selected_target_index)
            or nil
        if pet_distance then
            local distance_threshold = settings.geo_distance_threshold or 10

            -- try_full_circle, not first_command: the geo list also holds high-cost
            -- Geo-bt debuffs that would sort ahead of Full Circle.
            if pet_distance > distance_threshold then
                local fc = full_circle(string.format('Using Full Circle (Pet distance: %.1f yalms)', pet_distance))
                if fc then return fc end
            end
        end
    end
    
    -- ========================================================================
    -- Entrust Logic
    -- ========================================================================
    
    local entrust_config = ui_config.get_entrust_config()

    if entrust_config then
        if settings['disabled_Entrust'] == true then
            return nil
        end

        local target_index = entrust_config.target_index  -- 1-5 for P1-P5
        local spell_name = entrust_config.spell_name

        local selected_spell = nil
        if job_def.abilities.buff then
            for _, ability in ipairs(job_def.abilities.buff) do
                if ability.group == 'Indi' and ability.name == spell_name then
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

        -- Party index (1-5) to entity target index
        local party_member = state.party[target_index]
        if not party_member then
            return nil
        end

        local entity_target_index = party_member.target_index
        if not entity_target_index or entity_target_index == 0 then
            return nil
        end
        
        local target_in_range = common.is_in_range(entity_target_index, 20)

        if not target_in_range then
            return nil
        end

        -- Don't burn Entrust (5 min recast) unless the Indi spell is affordable
        if not action_core.has_resource('mp', selected_spell.cost or 0) then
            return nil
        end

        local has_entrust_buff = action_core.has_any_buff(player.buffs, 584)  -- Entrust

        if has_entrust_buff then
            -- Buff is up: cast the Indi spell on the party member.
            local blocked_by = common.is_command_blocked(selected_spell.command)
            if blocked_by then
                return nil
            end

            local command
            if type(selected_spell.command) == 'function' then
                command = selected_spell.command(target_index)
            else
                command = selected_spell.command:gsub('<me>', '<p' .. target_index .. '>')
            end

            if command then
                return {
                    command = command,
                    description = string.format('Entrust: %s on P%d', selected_spell.name, target_index)
                }
            end
        else
            -- No buff yet: use the JA. check_target_modifier does the validation, so
            -- Entrust is handed to it in a throwaway target_modifier job_def.
            local temp_job_def = {
                abilities = {
                    target_modifier = {}
                },
                resource_type = job_def.resource_type
            }
            
            if job_def.abilities.geo then
                for _, ability in ipairs(job_def.abilities.geo) do
                    if ability.name == 'Entrust' then
                        table.insert(temp_job_def.abilities.target_modifier, ability)
                        break
                    end
                end
            end
            
            local entrust_result = common.check_target_modifier(temp_job_def, settings, derived_main_level, derived_sub_level)

            if entrust_result then
                entrust_result.description = string.format('Using Entrust (for %s on P%d)', selected_spell.name, target_index)
                return entrust_result
            end
        end
    end
    
    return nil
end

return geo
