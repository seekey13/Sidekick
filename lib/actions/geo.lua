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

-- os.clock() when combat ended with a Geo-bt luopan still out, or nil. Starts
-- the grace period (geo_bt_timer setting) before Full Circle dismisses the
-- luopan, so a fresh battle target can reuse it. Reset when a battle target
-- reappears or the luopan is gone.
local geo_bt_end_time = nil

-- os.clock() when we issued a Geo-bt cast, cleared once its luopan spawns. The
-- luopan entity registers a moment after the cast completes; without this the
-- brief has_luopan==false gap would clear geo_bt_pending and the "take the
-- luopan" branch would Full Circle the debuff luopan the instant it lands.
local geo_bt_cast_time = nil

-- Whether a luopan was out on the previous execute(), so the moment it goes away
-- can be detected (see clear_tracked_geo_buffs).
local had_luopan = false

-- The "luopan out is our throwaway Radial Arcana bubble" flag lives on `common`
-- (common.arcana_luopan) because the job's validate_ability reads it too. It is
-- only raised once the luopan actually spawns; arcana_cast_time holds the
-- Geo-Voidance cast in flight until then, and expires so an interrupted cast
-- cannot wedge the sequence.
local arcana_cast_time = nil

-- os.clock() cutoff for the Radial Arcana sequence, or nil when none is running.
-- Armed the moment we tear down a luopan for Radial Arcana and held until the JA
-- is spent. It has to survive two things that would otherwise strand us with the
-- bubble gone and the JA unused: the Full Circle refund lifting us back over the
-- recovery threshold, and Radial Arcana's recast reading as not-ready for a few
-- ticks right after the Full Circle. Hence a deadline rather than a plain flag --
-- nothing else reliably marks the end of a sequence that never got started.
local arcana_deadline = nil
local ARCANA_SEQUENCE_TIMEOUT = 20

-- os.clock() when Radial Arcana was sent. Its recast does not register for a
-- moment afterwards, so without this the JA still reads as ready, MP is still
-- low, and a second sequence arms on the spot -- chasing a Geo-Voidance that is
-- now on its own 18-second recast.
local arcana_spent_time = nil
local ARCANA_SPENT_GRACE = 10

-- geo.execute runs every frame (only command *sends* are throttled), so the
-- "waiting on X" debug lines have to be rate limited or they bury the log.
local last_hold_log = 0
local function hold_log(fmt, ...)
    if os.clock() - last_hold_log >= 2 then
        last_hold_log = os.clock()
        common.debugf(fmt, ...)
    end
end

-- A luopan whose Geo spell cost more than this is worth keeping: it is only Full
-- Circled for Radial Arcana once nearly spent (see ARCANA_HPP_FLOOR).
local ARCANA_KEEP_COST = 75
local ARCANA_HPP_FLOOR = 5

-- The luopan is gone, so every Geo aura it was feeding died with it. Real party
-- members read their own buffs from memory and correct themselves; Trusts do not
-- exist in memory (common.get_member_buffs falls back to packet-tracked
-- trust_buffs for server ids >= 0x1000000), and an aura ending because its luopan
-- went away sends no wear-off packet at all. Left alone the tracked buff lingers
-- until its duration cap, so buff.lua sees the Trust as already buffed and never
-- recasts the Geo spell after a Full Circle.
--
-- Only group 'Geo' -- Indi spells follow the caster, not the luopan, and Geo-bt
-- ids live on the enemy. handle_buff_removal no-ops on anything untracked.
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

-- Party slot the Geo bubble belongs to (0 = ME, 1-5 = party member), or nil when
-- none is selected. The Geo group is single-select -- one luopan -- so at most one
-- is on. Indexed rather than iterated with pairs(): pairs order is undefined, so
-- two toggles briefly on at once would resolve differently in the two callers.
local function selected_geo_target(ui_config)
    local party_buffs = ui_config.get_party_buffs()
    local geo_targets = party_buffs and party_buffs['Geo']
    if not geo_targets then return nil end
    for idx = 0, 5 do
        if geo_targets[idx] == true then return idx end
    end
    return nil
end

-- The Geo spell that would be cast next, or nil if none is pending: the combat
-- <bt> debuff when one is selected, else the selected Geo <me>/party buff tier
-- (buff.lua casts that one) provided its target still needs it. Used to decide
-- whether Blaze of Glory has anything to enhance.
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
-- precast: callers only reach here with no luopan out, and we hold it unless
-- that spell is affordable so the 10-minute recast isn't burned for nothing.
--
-- Order matters for cost: the ability lookup is a linear scan of a short list,
-- while next_geo_spell allocates and filters, so the recast is checked first and
-- the "what would we be enhancing?" work only happens once the JA is actually up.
-- This runs every frame the luopan slot is empty, which for a GEO below 60 or with
-- Blaze of Glory unchecked is every frame, full stop.
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

-- Build a Full Circle action result if it is usable right now. Callers ensure a
-- pet/luopan is present. Returns { command, description } or nil.
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

-- Radial Arcana when it is level-appropriate and enabled, cooldown ignored. Looked
-- up directly rather than through filter_abilities_by_level because the job's
-- validate_ability hides it while we are outside the bubble -- which is exactly
-- the situation this module exists to fix. Casting it goes through try_use, which
-- re-checks the recast, so the cooldown only matters when *deciding* to start a
-- sequence (arcana_ready) -- never when finishing one.
local function arcana_ability(job_def, settings, main_level)
    -- Key must match what the UI writes: 'disabled_' .. name with spaces mapped to
    -- underscores (lib/ui/components.lua). 'disabled_Radial Arcana' never matched.
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

-- MP cost of the Geo spell holding the luopan right now, so an expensive bubble
-- is not thrown away for one Radial Arcana. Geo-bt owns the luopan in combat;
-- otherwise it is the Geo buff tier buff.lua would have cast.
--
-- That tier is the named selection, else the most EXPENSIVE castable one --
-- filter_abilities_by_level sorts cost-descending and buff.lua takes [1]. The job
-- list itself is ordered by level, so scanning it raw and taking the first 'Geo'
-- entry reported Geo-Haste (74, 63 MP) for a luopan buff.lua had actually filled
-- with Geo-Acumen (50, 182 MP): under ARCANA_KEEP_COST, so the expensive bubble
-- got eaten instead of preserved -- exactly what the threshold exists to stop.
--
-- The level/learned gates are applied by hand rather than through
-- filter_abilities_by_level because the job's validate_ability hides group 'Geo'
-- whenever a luopan is out, and a luopan being out is the only time this is called.
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
    -- Radial Arcana's gate is recomputed further down; clear it up front so an
    -- early return here can never leave the JA cleared against a stale bubble.
    common.arcana_usable = false

    -- The sequence latch is expired and published ahead of the guards below: it
    -- keeps buff.lua off the luopan slot, and must keep doing so on ticks where
    -- geo itself is skipped (resting, disabled) rather than silently lapsing.
    if arcana_deadline and os.clock() >= arcana_deadline then
        arcana_deadline      = nil
        common.arcana_luopan = false
    end
    common.arcana_sequence = arcana_deadline ~= nil

    -- Our Geo-Voidance has landed: mark the bubble as ours, so it is spendable no
    -- matter what Geo tier is selected (current_luopan_cost can only guess from
    -- settings). Up here with the spend itself so a guard below cannot skip it.
    if arcana_cast_time then
        if common.targets.get_pet() then
            common.arcana_luopan = true
            arcana_cast_time     = nil
        elseif os.clock() - arcana_cast_time > 8 then
            arcana_cast_time = nil  -- cast never landed; let the sequence retry
        end
    end

    -- Our throwaway Geo-Voidance bubble is down: spend it, now. Deliberately ahead
    -- of every guard below -- the bubble exists for no other purpose, so nothing
    -- about the MP threshold, resting, or geo being switched off part-way should
    -- leave it sitting there. recover.lua cannot cover this: it is threshold-gated,
    -- and the Full Circle refund that started the sequence usually lifted us back
    -- over the threshold before the bubble even landed.
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

    -- Radial Arcana state, needed up here because every Full Circle below has to
    -- decide whether the luopan slot it frees belongs to the arcana sequence.
    -- arcana_ja is the ability; arcana is it only while off cooldown, which is what
    -- gates *starting* a sequence (there is no point tearing a luopan down for a JA
    -- that is not up).
    local arcana_ja = arcana_ability(job_def, settings, derived_main_level)
    local just_spent = arcana_spent_time ~= nil
        and (os.clock() - arcana_spent_time) < ARCANA_SPENT_GRACE
    local arcana = (arcana_ja and not just_spent
        and action_core.is_ability_ready(arcana_ja.recast_id)) and arcana_ja or nil
    local mp_low = settings.recover_enabled == true
        and common.below_threshold(player.mpp or 0, settings.recover_mp_threshold or 30)

    local arcana_sequence = arcana_deadline ~= nil

    -- Any Full Circle empties the single luopan slot, whatever fired it -- ours for
    -- Radial Arcana, luopan drift, Geo-bt takeover. If MP was low and Radial Arcana
    -- is up, claim that empty slot for the sequence.
    local function full_circle(description)
        local fc = try_full_circle(job_def, settings, derived_main_level, derived_sub_level, description)
        if fc and arcana and mp_low then
            arcana_deadline = os.clock() + ARCANA_SEQUENCE_TIMEOUT
            common.arcana_sequence = true
            common.debugf('[GEO] Full Circle frees the luopan; claiming it for Radial Arcana (MP: %.1f%%)', player.mpp or 0)
        end
        return fc
    end

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

    -- Our Geo-bt luopan has spawned: stop treating the cast as in-flight.
    if has_luopan then
        geo_bt_cast_time = nil
    end

    -- Luopan just went away (Full Circle, expiry, killed): drop the auras it was
    -- feeding from packet-based buff tracking. Keyed on the entity disappearing
    -- rather than on issuing Full Circle, so every way of losing it is covered.
    -- Deliberately does not touch common.arcana_luopan: the pet entity can read as
    -- absent for a tick while the Radial Arcana cast resolves, and clearing on that
    -- flicker strands the bubble with the sequence over. It is cleared where the
    -- sequence genuinely ends instead (JA spent, dismissal, deadline lapse).
    if had_luopan and not has_luopan then
        clear_tracked_geo_buffs(job_def)
    end
    had_luopan = has_luopan

    -- Our debuff luopan is gone (expired / battle target died): clear tracking.
    -- Ignore the short window right after a cast where the luopan entity has not
    -- registered yet, so we don't drop geo_bt_pending and then Full Circle the
    -- luopan the instant it appears.
    if geo_bt_pending and not has_luopan then
        if not geo_bt_cast_time or (os.clock() - geo_bt_cast_time) > 8 then
            geo_bt_pending = false
            geo_bt_end_time = nil
            geo_bt_cast_time = nil
        end
    end

    -- A battle target is present: cancel any pending combat-ended countdown so a
    -- fresh <bt> reuses the existing luopan instead of Full Circle recasting.
    if in_combat then
        geo_bt_end_time = nil
    end

    -- Combat is over but our Geo-bt luopan is still out: after the grace period
    -- (geo_bt_timer) elapses with no new battle target, dismiss it so the luopan
    -- is freed for Geo <me> buffs again.
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
    -- Radial Arcana consumes the luopan and only refills party members standing
    -- inside its aura, so the bubble it eats has to be one we can afford to
    -- lose and one we are stood in. A cheap or nearly-spent luopan qualifies as
    -- is; a fresh expensive one does not -- Full Circle refunds more MP from
    -- that than Radial Arcana would yield -- so it is Full Circled and replaced
    -- with a throwaway Geo-Voidance on <me> first.
    -- ========================================================================
    -- Published for the job's validate_ability, which gates Radial Arcana on it.
    local spendable = has_luopan and (common.arcana_luopan
        or current_luopan_cost(job_def, settings, geo_bt, derived_main_level) <= ARCANA_KEEP_COST
        or (player.pet_hpp or 100) <= ARCANA_HPP_FLOOR)
    common.arcana_usable = spendable and common.is_in_luopan_radius()

    -- The throwaway bubble is spent at the top of execute, ahead of the guards; a
    -- luopan that is spendable but not ours is left to recover.lua's threshold.

    -- Not spendable / out of range: build a bubble we can spend. Once the sequence
    -- is armed it drives this on its own -- neither the MP threshold nor a Radial
    -- Arcana recast that momentarily reads as not-ready may cancel it, or the
    -- luopan slot sits empty and buff.lua recasts the expensive Geo spell into it.
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

    -- Blaze of Glory precast: only with the luopan slot free and a Geo spell
    -- actually pending. Runs ahead of the Geo-bt cast below and ahead of
    -- buff.lua's Geo <me> cast (buff comes after geo in priority_order).
    if not has_luopan then
        local bog = try_blaze_of_glory(job_def, settings, derived_main_level, derived_sub_level,
            geo_bt, in_combat)
        if bog then return bog end
    end

    -- In combat with a Geo-bt debuff selected: make sure the luopan is ours.
    if geo_bt and in_combat then
        if has_luopan and not geo_bt_pending then
            -- A non-debuff luopan (e.g. a Geo <me> buff) holds the slot; take it
            -- over so Geo-bt can claim the luopan for this fight.
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

    -- Check if player has a pet (only needed for Full Circle). Skip while our
    -- own Geo-bt luopan is out so the distance check can't dismiss the debuff.
    if common.targets.get_pet() and not geo_bt_pending then
        -- Distance is measured from whichever target holds the Geo bubble; if none
        -- is selected we skip the distance-based Full Circle entirely.
        local selected_target_index = selected_geo_target(ui_config)  -- 0 = ME, 1-5 = party

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
                local fc = full_circle(string.format('Using Full Circle (Pet distance: %.1f yalms)', pet_distance))
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
        if settings['disabled_Entrust'] == true then
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
        
        -- Don't burn Entrust (5 min recast) unless the Indi spell is affordable
        if not action_core.has_resource('mp', selected_spell.cost or 0) then
            return nil
        end

        -- Check if we have the Entrust buff (584)
        local has_entrust_buff = action_core.has_any_buff(player.buffs, 584)

        if has_entrust_buff then
            -- We have Entrust buff, cast the Indi spell on party member
            -- Check if spell is blocked by status ailments
            local blocked_by = common.is_command_blocked(selected_spell.command)
            if blocked_by then
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
