--[[
    UI Components for Medic Configuration
    Reusable UI rendering components extracted for DRY principles
]]--

local ui_components = {}

local imgui = require('imgui')
local common = require('lib.core.common')
local item_module = require('lib.actions.item')

-- ============================================================================
-- UI Constants
-- ============================================================================

-- Layout Constants
local ABILITY_LIST_INDENT = 10
local PARTY_BUTTON_WIDTH = 35
local SPACE_BETWEEN_BUTTONS = 8

-- Width Constants
local DROPDOWN_WIDTH = 300
local SLIDER_WIDTH = 250
local DROPDOWN_FALLBACK_WIDTH = 200
local AUTOMATION_BUTTON_WIDTH = 80

-- Color Constants - Text
local LIGHT_RED = { 1.0, 0.7, 0.7, 1.0 }
local LIGHT_YELLOW = { 1.0, 1.0, 0.7, 1.0 }
local LIGHT_GREEN = { 0.7, 1.0, 0.7, 1.0 }
local LIGHT_BLUE = { 0.7, 0.7, 1.0, 1.0 }
local LIGHT_GRAY = { 0.5, 0.5, 0.5, 1.0 }

-- Color Constants - Buttons
local COLOR_BUTTON_DISABLED = { 0.2, 0.2, 0.2, 1.0 }
local COLOR_BUTTON_UNSELECTED = { 0.3, 0.3, 0.3, 1.0 }
local COLOR_BUTTON_UNSELECTED_HOVER = { 0.4, 0.4, 0.4, 1.0 }
local COLOR_BUTTON_UNSELECTED_ACTIVE = { 0.5, 0.5, 0.5, 1.0 }

-- Color Constants - Headers
local HEADER_COLOR_NORMAL = { 0.2, 0.2, 0.2, 0.31 }
local HEADER_COLOR_HOVERED = { 0.2, 0.2, 0.2, 0.45 }
local HEADER_COLOR_ACTIVE = { 0.2, 0.2, 0.2, 0.65 }

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Returns true if the ability's effective (user-driven) combat_only setting is enabled.
local function effective_combat_only(ability, ctx)
    if not ability or not ctx or not ctx.settings then return false end
    return common.is_ability_combat_only(ability, ctx.settings)
end

-- Render a right-click 'Combat Only' toggle popup for an ability/group.
-- Call immediately after the imgui item the popup should attach to.
-- Suppressed for idle_only abilities since combat_only is meaningless there.
local function render_combat_only_context_menu(ctx, ability)
    if not ability or not ctx or not ctx.settings then return end
    if ability.idle_only then return end
    -- <bt> abilities are inherently combat-only; the toggle would be a no-op, so
    -- don't offer it.
    if common.ability_targets_bt(ability) then return end
    local key, popup_id
    if ability.group then
        key = 'combat_only_group_' .. ability.group
        -- Per-ability popup id (not per-group): when a group is ungrouped, each
        -- tier renders its own row, so a shared group id would stack duplicate
        -- menus into one popup. The setting key stays group-level.
        popup_id = '##cmenu_combat_only_group_' .. ability.group .. '_' .. (ability.name and ability.name:gsub(' ', '_') or '')
    else
        if not ability.name then return end
        local safe_name = ability.name:gsub(' ', '_')
        key = 'combat_only_' .. safe_name
        popup_id = '##cmenu_combat_only_' .. safe_name
    end
    if imgui.BeginPopupContextItem(popup_id) then
        local current = { ctx.settings[key] == true }
        if imgui.Checkbox('Combat Only', current) then
            ctx.settings[key] = current[1]
            if ctx.save_callback then ctx.save_callback() end
        end
        -- Ungroup: cast every tier in the group independently instead of only
        -- the selected tier. Off (grouped) by default; persisted per group.
        if ability.group then
            local ung_key = 'ungrouped_' .. ability.group
            local ung = { ctx.settings[ung_key] == true }
            if imgui.Checkbox('Ungroup', ung) then
                ctx.settings[ung_key] = ung[1] or nil
                if ctx.save_callback then ctx.save_callback() end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Cast each tier in this group independently\n(e.g. both Mage\'s Ballad and Mage\'s Ballad II).')
            end
        end
        imgui.EndPopup()
    end
end

-- Default filter functions (can be overridden via ctx.filter_func)
local default_filters = {}

-- Check if player can use an ability based on level
function default_filters.can_use_ability(ability)
    if not ability or not ability.level then
        return true
    end
    
    -- Check if ability requires main job only (e.g., Geo spells)
    if ability.main_job_only and ability.is_main_job == false then
        return false
    end
    
    local main_level, sub_level = common.get_player_level()
    
    -- Check if this ability is for main job or subjob
    if ability.is_main_job == false then
        return sub_level >= ability.level
    else
        return main_level >= ability.level
    end
end

-- Get filter functions from context or use defaults
local function get_filters(ctx)
    if ctx and ctx.filter_func then
        return ctx.filter_func
    end
    return default_filters
end

-- Get all abilities in the same group
local function get_abilities_in_group(job_def, target_group)
    local group_abilities = {}
    if not job_def or not target_group then
        return group_abilities
    end
    
    if job_def.abilities then
        for category, abilities in pairs(job_def.abilities) do
            for _, ability in ipairs(abilities) do
                if ability.group == target_group then
                    table.insert(group_abilities, ability)
                end
            end
        end
    end
    
    return group_abilities
end

-- Get usable abilities in a group (level-appropriate and spell learned)
local function get_usable_abilities_in_group(job_def, target_group, ctx)
    local all_abilities = get_abilities_in_group(job_def, target_group)
    local usable = {}
    local filters = get_filters(ctx)
    
    for _, ability in ipairs(all_abilities) do
        local can_use = filters.can_use_ability(ability)
        
        if can_use then
            if common.has_spell_learned(ability) then
                table.insert(usable, ability)
            end
        end
    end
    
    return usable
end

-- Get the highest level usable ability in a group
local function get_highest_level_ability_in_group(job_def, target_group, ctx)
    local usable = get_usable_abilities_in_group(job_def, target_group, ctx)
    if #usable == 0 then
        return nil
    end
    
    table.sort(usable, function(a, b) return a.level > b.level end)
    return usable[1]
end

-- Get selected ability for a group (from settings, or auto-select highest)
local function get_selected_ability_for_group(ctx, job_def, target_group)
    if not ctx.settings or not job_def or not target_group then
        return nil
    end
    
    local setting_key = 'selected_' .. target_group
    local saved_name = ctx.settings[setting_key]
    
    local usable = get_usable_abilities_in_group(job_def, target_group, ctx)
    if #usable == 0 then
        return nil
    end
    
    -- Check if saved ability is still usable
    if saved_name then
        for _, ability in ipairs(usable) do
            if ability.name == saved_name then
                return ability
            end
        end
    end
    
    -- Auto-select highest level
    local highest = get_highest_level_ability_in_group(job_def, target_group, ctx)
    if highest then
        ctx.settings[setting_key] = highest.name
        if ctx.save_callback then
            ctx.save_callback()
        end
    end
    
    return highest
end

-- Check if an ability is a duplicate from subjob
local function is_subjob_duplicate(job_def, ability, ctx)
    if ability.is_main_job ~= false then
        return false
    end
    
    if not job_def or not job_def.abilities then
        return false
    end
    
    for category, abilities in pairs(job_def.abilities) do
        for _, other_ability in ipairs(abilities) do
            if other_ability.name == ability.name and other_ability.is_main_job ~= false then
                return true
            end
        end
    end
    
    return false
end

-- Check if ability can be cast on party members
local function can_cast_on_party(ability)
    return type(ability.command) == 'function'
end

-- Check if a group is enabled
local function is_group_enabled(ctx, group_name)
    if not ctx.settings then
        return false
    end
    
    local key = 'disabled_group_' .. group_name
    
    if ctx.settings[key] == nil then
        return true  -- Default to enabled when not in settings
    end
    
    return not ctx.settings[key]
end

-- Toggle group enabled state
local function toggle_group(ctx, group_name, enabled)
    local key = 'disabled_group_' .. group_name
    ctx.settings[key] = not enabled
    
    if ctx.save_callback then
        ctx.save_callback()
    end
end

-- Check if an ability is enabled (for non-grouped abilities)
local function is_ability_enabled(ctx, ability_name)
    if not ctx.settings then
        return false
    end
    
    local key = 'disabled_' .. ability_name:gsub(' ', '_')
    
    if ctx.settings[key] == nil then
        return true  -- Default to enabled when not in settings
    end
    
    return not ctx.settings[key]
end

-- Toggle ability enabled state (for non-grouped abilities)
local function toggle_ability(ctx, ability_name, enabled, job_def)
    local key = 'disabled_' .. ability_name:gsub(' ', '_')
    ctx.settings[key] = not enabled
    
    if ctx.save_callback then
        ctx.save_callback()
    end
end

-- Find an ability by name in job definition
local function find_ability_by_name(job_def, ability_name)
    if not job_def or not job_def.abilities then
        return nil
    end
    
    for category, abilities in pairs(job_def.abilities) do
        if type(abilities) == 'table' then
            for _, ability in ipairs(abilities) do
                if ability.name == ability_name then
                    return ability
                end
            end
        end
    end

    return nil
end

-- Is this party_buffs key a song? The key is a group name (grouped songs) OR an
-- ability name (ungrouped songs), so the song-limit count must recognize both --
-- otherwise grouped and ungrouped songs keep separate tallies.
local function is_song_config_key(job_def, key)
    local group_abilities = get_abilities_in_group(job_def, key)
    if #group_abilities > 0 then
        return group_abilities[1].magic == 'song'
    end
    local ability = find_ability_by_name(job_def, key)
    return ability ~= nil and ability.magic == 'song'
end

-- Check if a group buff is enabled for a specific party member
local function is_group_party_buff_enabled(ctx, group_name, party_index)
    if not ctx.party_buffs[group_name] then
        return false
    end
    return ctx.party_buffs[group_name][party_index] == true
end

-- Check if a buff is enabled for a specific party member (non-grouped abilities)
local function is_party_buff_enabled(ctx, ability_name, party_index)
    if not ctx.party_buffs[ability_name] then
        return false
    end
    return ctx.party_buffs[ability_name][party_index] == true
end

-- Party-buff target keys that must persist to disk. Numeric ME/P1-P5 (0-5) and
-- the bard area key 'A' are stable config; alliance ('al_')/tracked ('tt_') keys
-- are session-only because those members come and go.
local function is_persisted_target_key(k)
    return (type(k) == 'number' and k <= 5) or k == 'A'
end

-- Toggle group buff enabled state for a specific party member
local function toggle_group_party_buff(ctx, group_name, party_index, enabled)
    if not ctx.party_buffs[group_name] then
        ctx.party_buffs[group_name] = {}
    end
    
    -- Check if this is a song group that counts toward the limit
    if enabled then
        -- Get any ability from this group to check target_modifier
        local group_abilities = get_abilities_in_group(ctx.job_def, group_name)
        if #group_abilities > 0 then
            local sample_ability = group_abilities[1]
            
            if sample_ability.magic == 'song' then
                -- Determine the limit based on main/sub job
                local is_main_job = sample_ability.is_main_job ~= false
                local song_limit = is_main_job and 2 or 1

                -- Count currently enabled song groups for this party member. Every
                -- song occupies a slot (incl. Mazurka, which has no Pianissimo), so
                -- the predicate is magic=='song', not target_modifier.
                local active_song_groups = {}
                for other_group_name, targets in pairs(ctx.party_buffs) do
                    if other_group_name ~= group_name and targets[party_index] == true then
                        if is_song_config_key(ctx.job_def, other_group_name) then
                            table.insert(active_song_groups, other_group_name)
                        end
                    end
                end
                
                -- If at or over limit, deselect one existing song group for this party member
                if #active_song_groups >= song_limit then
                    local group_to_remove = active_song_groups[1]
                    ctx.party_buffs[group_to_remove][party_index] = false
                    
                    -- Ensure persistence structure exists (skip tracked targets)
                    if is_persisted_target_key(party_index) then
                        ctx.settings.party_buffs = ctx.settings.party_buffs or {}
                        ctx.settings.party_buffs[group_to_remove] = ctx.settings.party_buffs[group_to_remove] or {}
                        ctx.settings.party_buffs[group_to_remove][party_index] = false
                    end
                    
                    -- Check if removed group is still enabled for any member
                    local removed_still_enabled = false
                    for k, v in pairs(ctx.party_buffs[group_to_remove]) do
                        if v == true then
                            removed_still_enabled = true
                            break
                        end
                    end
                    
                    -- Update disabled setting for removed group
                    if not removed_still_enabled then
                        ctx.settings['disabled_group_' .. group_to_remove] = true
                    end
                end
            end
        end
    end
    
    -- Exclusive single-target groups (e.g. Geo): only one target at a time.
    -- Geo creates a single luopan, so selecting a target deselects the others.
    if enabled then
        local group_abilities = get_abilities_in_group(ctx.job_def, group_name)
        if #group_abilities > 0 and group_abilities[1].exclusive_target then
            for other_index, val in pairs(ctx.party_buffs[group_name]) do
                if other_index ~= party_index and val == true then
                    ctx.party_buffs[group_name][other_index] = false
                    if is_persisted_target_key(other_index) then
                        ctx.settings.party_buffs = ctx.settings.party_buffs or {}
                        ctx.settings.party_buffs[group_name] = ctx.settings.party_buffs[group_name] or {}
                        ctx.settings.party_buffs[group_name][other_index] = false
                    end
                end
            end
        end
    end

    -- Set the new buff state
    ctx.party_buffs[group_name][party_index] = enabled

    -- Check if ANY button is enabled for this group
    local any_button_enabled = false
    for k, v in pairs(ctx.party_buffs[group_name]) do
        if v == true then
            any_button_enabled = true
            break
        end
    end
    
    -- Update the group's disabled setting
    ctx.settings['disabled_group_' .. group_name] = not any_button_enabled
    
    -- Save party_buffs to settings for persistence (skip tracked targets)
    if is_persisted_target_key(party_index) then
        ctx.settings.party_buffs = ctx.settings.party_buffs or {}
        ctx.settings.party_buffs[group_name] = ctx.settings.party_buffs[group_name] or {}
        ctx.settings.party_buffs[group_name][party_index] = enabled
    end
    
    if ctx.save_callback then
        ctx.save_callback()
    end
end

-- Toggle buff enabled state for a specific party member (non-grouped abilities)
local function toggle_party_buff(ctx, ability_name, party_index, enabled)
    if not ctx.party_buffs[ability_name] then
        ctx.party_buffs[ability_name] = {}
    end
    
    -- Check if this is a song that counts toward the limit
    if enabled then
        local ability = find_ability_by_name(ctx.job_def, ability_name)
        
        if ability and ability.magic == 'song' then
            -- Determine the limit based on main/sub job
            local is_main_job = ability.is_main_job ~= false
            local song_limit = is_main_job and 2 or 1

            -- Count currently enabled songs for this party member. Every song
            -- occupies a slot (incl. Mazurka, no Pianissimo), so match magic=='song'.
            local active_songs = {}
            for other_ability_name, targets in pairs(ctx.party_buffs) do
                if other_ability_name ~= ability_name and targets[party_index] == true then
                    if is_song_config_key(ctx.job_def, other_ability_name) then
                        table.insert(active_songs, other_ability_name)
                    end
                end
            end
            
            -- If at or over limit, deselect one existing song for this party member
            if #active_songs >= song_limit then
                local song_to_remove = active_songs[1]  -- Remove first found (random due to table iteration)
                ctx.party_buffs[song_to_remove][party_index] = false
                
                -- Ensure persistence structure exists (skip tracked targets)
                if is_persisted_target_key(party_index) then
                    ctx.settings.party_buffs = ctx.settings.party_buffs or {}
                    ctx.settings.party_buffs[song_to_remove] = ctx.settings.party_buffs[song_to_remove] or {}
                    ctx.settings.party_buffs[song_to_remove][party_index] = false
                end
                
                -- Check if removed song is still enabled for any member
                local removed_still_enabled = false
                for k, v in pairs(ctx.party_buffs[song_to_remove]) do
                    if v == true then
                        removed_still_enabled = true
                        break
                    end
                end
                
                -- Update disabled setting for removed song
                local removed_key = 'disabled_' .. song_to_remove:gsub(' ', '_')
                if not removed_still_enabled then
                    ctx.settings[removed_key] = true
                end
            end
        end
    end
    
    -- Set the new buff state
    ctx.party_buffs[ability_name][party_index] = enabled
    
    -- Check if ANY button is enabled
    local any_button_enabled = false
    for k, v in pairs(ctx.party_buffs[ability_name]) do
        if v == true then
            any_button_enabled = true
            break
        end
    end
    
    -- Update the ability's disabled setting
    local key = 'disabled_' .. ability_name:gsub(' ', '_')
    if any_button_enabled then
        ctx.settings[key] = false
    else
        ctx.settings[key] = true
    end
    
    -- Save party_buffs to settings for persistence (skip tracked targets)
    if is_persisted_target_key(party_index) then
        if not ctx.settings.party_buffs then
            ctx.settings.party_buffs = {}
        end
        if not ctx.settings.party_buffs[ability_name] then
            ctx.settings.party_buffs[ability_name] = {}
        end
        ctx.settings.party_buffs[ability_name][party_index] = enabled
    end
    
    if ctx.save_callback then
        ctx.save_callback()
    end
end

-- Calculate the width for the ON/OFF button based on party size + alliance + tracked targets
local function get_onoff_button_width()
    local party_size = common.get_party_size()
    local alliance_count = common.get_alliance_count()
    local tracked_count = 0
    local tt_list = common.get_tracked_targets()
    for _ in pairs(tt_list) do tracked_count = tracked_count + 1 end
    local num_buttons = math.min(party_size, 6) + alliance_count + tracked_count
    return PARTY_BUTTON_WIDTH * num_buttons + (SPACE_BETWEEN_BUTTONS * (num_buttons - 1))
end

-- ============================================================================
-- Scholar Stratagem Button
-- ============================================================================

-- Helper: get the stratagem_settings table from ctx, creating it if needed
local function get_stratagem_settings(ctx)
    if not ctx or not ctx.settings then return nil end
    if not ctx.settings.stratagem_settings then
        ctx.settings.stratagem_settings = {}
    end
    return ctx.settings.stratagem_settings
end

-- Helper: get the stratagem_hold table from ctx, creating it if needed
-- stratagem_hold[ability_key] = true means "skip the spell until the stratagem is ready"
local function get_stratagem_hold(ctx)
    if not ctx or not ctx.settings then return nil end
    if not ctx.settings.stratagem_hold then
        ctx.settings.stratagem_hold = {}
    end
    return ctx.settings.stratagem_hold
end

-- Helper: check if any stratagem is assigned to an ability key in settings
local function has_any_stratagem(ctx, ability_key)
    local ss = ctx and ctx.settings and ctx.settings.stratagem_settings
    if not ss or not ss[ability_key] then return false end
    return next(ss[ability_key]) ~= nil
end

-- Helper: compute the MP modifier multiplier for an ability based on its assigned stratagems
-- Returns: multiplier (number, 1.0 = no change)
local function get_stratagem_mp_modifier(ctx, ability_key)
    local ss = ctx and ctx.settings and ctx.settings.stratagem_settings
    if not ss or not ss[ability_key] then return 1.0 end
    local job_def = ctx.job_def
    if not job_def or not job_def.abilities or not job_def.abilities.stratagem then return 1.0 end

    local modifier = 1.0
    for strat_name, _ in pairs(ss[ability_key]) do
        for _, strat in ipairs(job_def.abilities.stratagem) do
            if strat.name == strat_name and strat.mp_modifier then
                modifier = modifier * strat.mp_modifier
            end
        end
    end
    return modifier
end

-- Filter stratagems from job_def that apply to a given ability at the given level
local function get_available_stratagems(job_def, sch_level, ability)
    if not job_def or not job_def.abilities or not job_def.abilities.stratagem then
        return {}
    end
    local ability_magic      = ability and ability.magic
    local ability_magic_type = ability and ability.magic_type
    local available = {}
    for _, strat in ipairs(job_def.abilities.stratagem) do
        if strat.level and sch_level >= strat.level then
            -- Match stratagem magic colour to the ability
            local magic_ok = (not strat.magic) or (strat.magic == ability_magic)
            -- If stratagem restricts to specific magic_types, ability must match one
            local type_ok = true
            if magic_ok and strat.magic_types then
                type_ok = false
                if ability_magic_type then
                    for _, mt in ipairs(strat.magic_types) do
                        if mt == ability_magic_type then
                            type_ok = true
                            break
                        end
                    end
                end
            end
            if magic_ok and type_ok then
                table.insert(available, strat)
            end
        end
    end
    return available
end

-- Render the Scholar stratagem selector button for a single ability row.
-- ability_key: unique string key for the ability (e.g. ability name or group name)
-- ability: (optional) the ability table; when provided, only /ma commands get the button
-- ctx: (optional) UI context with settings and save_callback for persistence
-- Returns: consumed (bool) -- true when this drew a leading element (the S button
--   OR an alignment spacer), false when it drew nothing. The caller uses this to
--   avoid stacking a second indent (e.g. the bard [A] column) on the same row.
local function render_scholar_stratagem_button(ability_key, ability, ctx)
    -- Resolve Scholar level from main or sub job (SCH = job ID 20)
    local main_job_id, sub_job_id = common.get_player_job()
    local main_level, sub_level   = common.get_player_level()

    local sch_level = 0
    if main_job_id == 20 then
        sch_level = main_level
    elseif sub_job_id == 20 then
        sch_level = sub_level
    end

    if sch_level < 10 then
        return false, 0
    end

    -- Check if player is in any arts stance (required for stratagems)
    local in_light = common.has_buff(0, 358) or common.has_buff(0, 401)
    local in_dark  = common.has_buff(0, 359) or common.has_buff(0, 402)
    local in_arts  = in_light or in_dark

    -- No arts active → no S button or spacer on any row
    if not in_arts then
        return false, 0
    end

    -- Only magic (/ma) commands can use stratagems; skip job abilities (/ja)
    if ability and type(ability.command) == 'string' and ability.command:sub(1, 3) == '/ja' then
        imgui.Dummy({ 20, 0 })
        imgui.SameLine(0, SPACE_BETWEEN_BUTTONS)
        return true, 0
    end

    -- Geo-bt debuffs render in the Geo section, which has no S-button rows to
    -- align with, so skip the spacer to avoid an unwanted indent. Indi/Geo buffs
    -- still fall through to the spacer below to align with buff-section rows.
    if ability and ability.group == 'Geo-bt' then
        return false, 0
    end

    -- Bard songs get the area [A] button in the leading slot (drawn by
    -- render_party_buttons), so it already provides the indent. Adding a
    -- stratagem spacer here too would double-indent the row. Either the [A]
    -- button or the S button triggers the indent, never both.
    if ability and ability.magic == 'song' then
        return false, 0
    end

    -- Stratagems only apply to white/black magic; skip singing, geomancy, etc.
    -- Render an invisible spacer so these rows stay aligned with S-button rows.
    if ability and ability.magic then
        if ability.magic ~= 'white' and ability.magic ~= 'black' then
            imgui.Dummy({ 20, 0 })
            imgui.SameLine(0, SPACE_BETWEEN_BUTTONS)
            return true, 0
        end
    end

    -- Check arts stance: Light Arts → white only, Dark Arts → black only
    -- Wrong-stance spells get an invisible spacer to stay aligned with S-button rows
    if ability and ability.magic then
        if (ability.magic == 'white' and not in_light) or (ability.magic == 'black' and not in_dark) then
            imgui.Dummy({ 20, 0 })
            imgui.SameLine(0, SPACE_BETWEEN_BUTTONS)
            return true, 0
        end
    end

    -- Get job_def from ctx for stratagem definitions
    local job_def = ctx and ctx.job_def
    local available = get_available_stratagems(job_def, sch_level, ability)

    if #available == 0 then
        return false, 0
    end

    local has_sel  = has_any_stratagem(ctx, ability_key)
    local popup_id = '##sch_strat_popup_' .. ability_key

    -- Color: default (active) when a stratagem is chosen, gray when idle
    if not has_sel then
        imgui.PushStyleColor(ImGuiCol_Button,        COLOR_BUTTON_UNSELECTED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  COLOR_BUTTON_UNSELECTED_ACTIVE)
    end

    if imgui.Button('S##sch_' .. ability_key, { 20, 0 }) then
        imgui.OpenPopup(popup_id)
    end

    if imgui.IsItemHovered() then
        imgui.SetTooltip('Scholar Stratagem: apply a stratagem to this spell to\n' ..
            'reduce MP cost or boost its effect. Click to choose which\n' ..
            'stratagems to spend. Lit when one is assigned.')
    end

    if not has_sel then
        imgui.PopStyleColor(3)
    end

    if imgui.BeginPopup(popup_id) then
        imgui.TextColored({ 0.8, 0.8, 0.8, 1.0 }, 'Scholar Stratagem')
        imgui.Separator()

        -- Ensure settings table exists
        local ss = get_stratagem_settings(ctx)
        if ss then
            if not ss[ability_key] then
                ss[ability_key] = {}
            end

            for _, strat in ipairs(available) do
                local is_checked = ss[ability_key] and ss[ability_key][strat.name] == true
                local label = strat.name
                -- Show MP modifier info in label
                if strat.mp_modifier then
                    if strat.mp_modifier < 1.0 then
                        label = label .. '  (-' .. math.floor((1.0 - strat.mp_modifier) * 100) .. '% MP)'
                    else
                        label = label .. '  (+' .. math.floor((strat.mp_modifier - 1.0) * 100) .. '% MP)'
                    end
                end

                local cb_val = { is_checked }
                if imgui.Checkbox(label .. '##sch_opt_' .. strat.name .. '_' .. ability_key, cb_val) then
                    if not ss[ability_key] then
                        ss[ability_key] = {}
                    end
                    if cb_val[1] then
                        ss[ability_key][strat.name] = true
                    else
                        ss[ability_key][strat.name] = nil
                    end
                    if ctx.save_callback then
                        ctx.save_callback()
                    end
                end
            end

            -- Clean up empty tables after the loop
            if ss[ability_key] and not next(ss[ability_key]) then
                ss[ability_key] = nil
                if ctx.save_callback then
                    ctx.save_callback()
                end
            end
        end

        -- "Hold for Stratagem": gate casting on the stratagem being ready.
        imgui.Separator()
        local hold_tbl = get_stratagem_hold(ctx)
        if hold_tbl then
            local hold_val = { hold_tbl[ability_key] == true }
            if imgui.Checkbox('Hold for Stratagem##sch_hold_' .. ability_key, hold_val) then
                hold_tbl[ability_key] = hold_val[1] or nil
                if ctx.save_callback then
                    ctx.save_callback()
                end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('On: skip this spell until the stratagem is ready.\n' ..
                    'Off (default): cast the spell without the stratagem when it is on cooldown.')
            end
        end

        imgui.EndPopup()
    end

    imgui.SameLine(0, SPACE_BETWEEN_BUTTONS)
    return true, 0
end

-- Draw a row's leading slot: the [A] button (bard, drawn later by
-- render_party_buttons), the S button (scholar), or a spacer so the row aligns
-- under whichever column is on-screen. Exactly ONE indent per row -- if scholar
-- already drew its S button/spacer we don't add a bard spacer, so BRD/SCH gets a
-- single indent, not two.
local function render_leading_slot(ability_key, ability, ctx)
    -- Song rows: render_party_buttons draws the [A] button in this slot.
    if ability and ability.magic == 'song' then return end

    -- Scholar's S button (or its own alignment spacer) fills the slot when active
    -- (i.e. in Light/Dark Arts). Returns true when it drew something.
    if render_scholar_stratagem_button(ability_key, ability, ctx) then return end

    -- Nothing drawn. If this job carries song magic the buff UI shows the bard [A]
    -- area column, so non-song rows still need the indent. Geo-bt debuffs sit in
    -- their own section with no [A] column -- skip those.
    local has_songs = ctx and ctx.job_def and ctx.job_def.has_songs
    if has_songs and not (ability and ability.group == 'Geo-bt') then
        imgui.Dummy({ 20, 0 })
        imgui.SameLine(0, SPACE_BETWEEN_BUTTONS)
    end
end

-- ============================================================================
-- Party Button Helper
-- ============================================================================

-- Render party toggle buttons ([ME] [P1] [P2] etc.)
-- Returns: true if any button was rendered
-- For grouped abilities, pass group_name instead of ability_name
local function render_party_buttons(ctx, key_name, has_spell, ability, is_group)
    local any_rendered = false

    -- Leading slot: scholar S button / bard [A] indent / spacer (aligns the row)
    render_leading_slot(key_name, ability, ctx)

    -- Check if this ability requires a target modifier (like Pianissimo)
    if not ability then
        ability = find_ability_by_name(ctx.job_def, key_name)
    end
    
    local requires_target_modifier = ability and ability.target_modifier == true
    local has_target_modifier = true  -- Default to true for non-modifier abilities
    
    if requires_target_modifier then
        -- Check if the target_modifier ability is available (e.g., Pianissimo at level 20)
        has_target_modifier = false
        if ctx.job_def.abilities.target_modifier then
            local main_level, sub_level = common.get_player_level()
            for _, modifier_ability in ipairs(ctx.job_def.abilities.target_modifier) do
                local is_main_job = ability.is_main_job ~= false
                local level_to_check = is_main_job and main_level or sub_level
                if modifier_ability.level and level_to_check >= modifier_ability.level then
                    has_target_modifier = true
                    break
                end
            end
        end
    end
    
    -- ME now behaves like P1-P5: for songs it uses Pianissimo, so it needs the
    -- target modifier to be available (same gate the party buttons use).
    local party_has_spell = has_spell and has_target_modifier

    -- Bard area-song [A] button: sing WITHOUT Pianissimo so everyone in range
    -- gets the song. Sits in the leading slot (like the Scholar S button on other
    -- jobs). Needs no Pianissimo, so it stays usable below Pianissimo's level.
    -- Every bard song gets it (Mazurka has no Pianissimo but is always area).
    if ability and ability.magic == 'song' then
        local a_enabled = is_group and is_group_party_buff_enabled(ctx, key_name, 'A')
            or is_party_buff_enabled(ctx, key_name, 'A')

        if not has_spell then
            imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_DISABLED)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_DISABLED)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_DISABLED)
            imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
        elseif a_enabled then
            -- Use default colors
        else
            imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
        end

        local a_label = 'A##' .. key_name .. '_area'
        if has_spell and imgui.Button(a_label, { 20, 0 }) then
            if is_group then
                toggle_group_party_buff(ctx, key_name, 'A', not a_enabled)
            else
                toggle_party_buff(ctx, key_name, 'A', not a_enabled)
            end
        elseif not has_spell then
            imgui.Button(a_label, { 20, 0 })
        end

        if imgui.IsItemHovered() then
            imgui.SetTooltip('Area: sing without Pianissimo so everyone in range gets it.\nRecast tracks party members not given a specific ME/P button.')
        end

        if not has_spell then
            imgui.PopStyleColor(4)
        elseif not a_enabled then
            imgui.PopStyleColor(3)
        end

        imgui.SameLine(0, SPACE_BETWEEN_BUTTONS)
    end

    -- Render [ME] button
    local me_enabled = is_group and is_group_party_buff_enabled(ctx, key_name, 0) or is_party_buff_enabled(ctx, key_name, 0)

    if not party_has_spell then
        imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif me_enabled then
        -- Use default colors
    else
        imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
    end

    local me_button_label = 'ME##' .. key_name .. '_me'
    if party_has_spell and imgui.Button(me_button_label, { PARTY_BUTTON_WIDTH, 0 }) then
        if is_group then
            toggle_group_party_buff(ctx, key_name, 0, not me_enabled)
        else
            toggle_party_buff(ctx, key_name, 0, not me_enabled)
        end
    elseif not party_has_spell then
        imgui.Button(me_button_label, { PARTY_BUTTON_WIDTH, 0 })
    end

    if imgui.IsItemHovered() then
        imgui.SetTooltip(common.get_party_member_name(0) or 'ME')
    end

    if not party_has_spell then
        imgui.PopStyleColor(4)
    elseif not me_enabled then
        imgui.PopStyleColor(3)
    end

    any_rendered = true
    
    -- Render party member buttons (P1-P5)
    local party_size = common.get_party_size()
    if party_size > 1 then
        for party_index = 1, 5 do
            local is_active = party_index < party_size
            
            if is_active then
                imgui.SameLine()
                
                local is_enabled = is_group and is_group_party_buff_enabled(ctx, key_name, party_index) or is_party_buff_enabled(ctx, key_name, party_index)
                
                -- Treat party button as "not has_spell" if target_modifier is required but not available
                -- NOTE: `and not is_trust_member` removed -- Trusts can now be buffed
                local party_has_spell = has_spell and has_target_modifier
                
                if not party_has_spell then
                    imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_DISABLED)
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_DISABLED)
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_DISABLED)
                    imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
                elseif is_enabled then
                    -- Use default colors
                else
                    imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
                end
                
                local button_label = 'P' .. party_index .. '##' .. key_name .. '_p' .. party_index
                if party_has_spell and imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 }) then
                    if is_group then
                        toggle_group_party_buff(ctx, key_name, party_index, not is_enabled)
                    else
                        toggle_party_buff(ctx, key_name, party_index, not is_enabled)
                    end
                elseif not party_has_spell then
                    imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 })
                end
                
                -- Tooltip: party member name, plus a Trust reliability caveat
                -- (removal vs. buff tracking) appended only on actual Trust buttons.
                if imgui.IsItemHovered() then
                    local pname = common.get_party_member_name(party_index) or ('P' .. party_index)
                    if ctx.is_trust and ctx.is_trust(party_index) and ctx.show_trust_warning then
                        imgui.SetTooltip(pname .. '\nTrust/Tracked Removal is not totally reliable')
                    elseif ctx.is_trust and ctx.is_trust(party_index) and ctx.show_buff_warning then
                        imgui.SetTooltip(pname .. '\nTrust/Tracked Buff tracking is not totally reliable')
                    else
                        imgui.SetTooltip(pname)
                    end
                end
                
                if not party_has_spell then
                    imgui.PopStyleColor(4)
                elseif not is_enabled then
                    imgui.PopStyleColor(3)
                end
            end
        end
    end
    
    -- Render alliance member buttons ([B0]-[B5], [C0]-[C5])
    -- Uses key format 'al_<flat_index>' (flat_index 6-17) in party_buffs.
    -- Alliance members are targeted by server_id (same mechanism as tracked targets).
    local al_gs = common.game_state
    if al_gs and al_gs.alliance then
        local alliance_prefixes = { [2] = 'B', [3] = 'C' }
        for pi = 2, 3 do
            local sub_party = al_gs.alliance[pi]
            if sub_party and next(sub_party) ~= nil then
                local prefix = alliance_prefixes[pi]
                local sorted_al = common.sorted_alliance_members(sub_party)

                for _, entry in ipairs(sorted_al) do
                    local local_idx = entry.local_idx
                    local m         = entry.m
                    local flat_index = (pi - 1) * 6 + local_idx  -- 6-17
                    local al_key     = 'al_' .. flat_index

                    imgui.SameLine()

                    local is_enabled    = is_group and is_group_party_buff_enabled(ctx, key_name, al_key) or is_party_buff_enabled(ctx, key_name, al_key)
                    local is_compatible = ability and ability.target_outside
                    local is_disabled   = not has_spell or not is_compatible

                    if is_disabled then
                        imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_DISABLED)
                        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_DISABLED)
                        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_DISABLED)
                        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
                    elseif is_enabled then
                        -- Use default colors
                    else
                        imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
                        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
                        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
                    end

                    local button_label = prefix .. local_idx .. '##' .. key_name .. '_' .. al_key
                    local clicked = imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 })
                    if clicked and not is_disabled then
                        if is_group then
                            toggle_group_party_buff(ctx, key_name, al_key, not is_enabled)
                        else
                            toggle_party_buff(ctx, key_name, al_key, not is_enabled)
                        end
                    end

                    if imgui.IsItemHovered() then
                        if not is_compatible then
                            imgui.SetTooltip('Not compatible with out-of-party targets')
                        else
                            imgui.SetTooltip(m.name or (prefix .. local_idx))
                        end
                    end

                    if is_disabled then
                        imgui.PopStyleColor(4)
                    elseif not is_enabled then
                        imgui.PopStyleColor(3)
                    end
                end
            end
        end
    end

    -- Render tracked target buttons for every buff row.
    -- Buttons are grayed out and non-clickable when the ability is not compatible
    -- with out-of-party targets (i.e. ability.target_outside is not set).
    local tracked_list = common.get_tracked_targets()
    local sorted_tracked = {}
    for sid, tt in pairs(tracked_list) do
        table.insert(sorted_tracked, { sid = sid, name = tt.name })
    end
    table.sort(sorted_tracked, function(a, b) return a.name < b.name end)

    if #sorted_tracked > 0 then
        local is_compatible = ability and ability.target_outside

        for t_idx, tt in ipairs(sorted_tracked) do
            imgui.SameLine()

            local tt_key = 'tt_' .. tt.sid
            local is_tt_enabled = is_group and is_group_party_buff_enabled(ctx, key_name, tt_key) or is_party_buff_enabled(ctx, key_name, tt_key)
            local is_disabled = not has_spell or not is_compatible

            if is_disabled then
                imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_DISABLED)
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_DISABLED)
                imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_DISABLED)
                imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
            elseif is_tt_enabled then
                -- Use default colors
            else
                imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
                imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
            end

            local tt_button_label = 'T' .. t_idx .. '##' .. key_name .. '_t' .. tt.sid
            local clicked = imgui.Button(tt_button_label, { PARTY_BUTTON_WIDTH, 0 })
            if clicked and not is_disabled then
                if is_group then
                    toggle_group_party_buff(ctx, key_name, tt_key, not is_tt_enabled)
                else
                    toggle_party_buff(ctx, key_name, tt_key, not is_tt_enabled)
                end
            end

            -- Tooltip: show target name, or reason why button is disabled
            if imgui.IsItemHovered() then
                if not is_compatible then
                    imgui.SetTooltip('Not compatible with out-of-party targets')
                elseif ctx.show_trust_warning then
                    imgui.SetTooltip(tt.name .. '\nTrust/Tracked Removal is not totally reliable')
                elseif ctx.show_buff_warning then
                    imgui.SetTooltip(tt.name .. '\nTrust/Tracked Buff tracking is not totally reliable')
                else
                    imgui.SetTooltip(tt.name)
                end
            end

            if is_disabled then
                imgui.PopStyleColor(4)
            elseif not is_tt_enabled then
                imgui.PopStyleColor(3)
            end
        end
    end

    return any_rendered
end

-- ============================================================================
-- Render Functions
-- ============================================================================

-- Render an ON/OFF button for ability state
function ui_components.onoff_button(ctx, ability_name, job_def, has_spell)
    has_spell = has_spell == nil and true or has_spell

    -- Leading slot: scholar S button / bard [A] indent / spacer (aligns the row)
    -- Look up the ability to check if it's a /ja (not eligible for stratagems)
    local ability_obj = find_ability_by_name(job_def, ability_name)
    render_leading_slot(ability_name, ability_obj, ctx)

    local is_enabled = is_ability_enabled(ctx, ability_name)
    local button_width = get_onoff_button_width()
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_DISABLED)
    elseif is_enabled then
        -- Use default colors
    else
        imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
    end
    
    local button_text = is_enabled and 'ON' or 'OFF'
    local button_label = button_text .. '##onoff_' .. ability_name
    
    if has_spell and imgui.Button(button_label, { button_width, 0 }) then
        toggle_ability(ctx, ability_name, not is_enabled, job_def)
    elseif not has_spell then
        imgui.Button(button_label, { button_width, 0 })
    end
    
    if not has_spell or not is_enabled then
        imgui.PopStyleColor(3)
    end
end

-- Render a dropdown for selecting ability from a group
function ui_components.group_dropdown(ctx, job_def, target_group, dropdown_width)
    if not job_def or not target_group then
        return
    end
    
    local usable = get_usable_abilities_in_group(job_def, target_group, ctx)
    if #usable == 0 then
        return
    end
    
    local selected = get_selected_ability_for_group(ctx, job_def, target_group)
    local current_display
    if selected then
        if selected.cost and selected.cost > 0 then
            local resource_label = (selected.resource_type or job_def.resource_type) == 'tp' and 'TP' or 'MP'
            local display_cost = math.floor(selected.cost * get_stratagem_mp_modifier(ctx, target_group))
            current_display = selected.name .. ' (' .. display_cost .. ' ' .. resource_label .. ')'
        else
            current_display = selected.name
        end
    else
        current_display = 'None'
    end
    
    local setting_key = 'selected_' .. target_group
    local combo_label = '##dropdown_' .. target_group
    local selected_combat_only = selected and effective_combat_only(selected, ctx) or false
    
    -- Apply color styling
    if selected then
        if selected_combat_only then
            imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
        elseif selected.idle_only then
            imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
        end
    end
    
    imgui.PushItemWidth(dropdown_width or DROPDOWN_FALLBACK_WIDTH)
    if imgui.BeginCombo(combo_label, current_display) then
        for _, ability in ipairs(usable) do
            local display_text
            if ability.cost and ability.cost > 0 then
                local resource_label = (ability.resource_type or job_def.resource_type) == 'tp' and 'TP' or 'MP'
                local display_cost = math.floor(ability.cost * get_stratagem_mp_modifier(ctx, target_group))
                display_text = ability.name .. ' (' .. display_cost .. ' ' .. resource_label .. ')'
            else
                display_text = ability.name
            end
            local is_selected = (selected and selected.name == ability.name)
            
            if imgui.Selectable(display_text, is_selected) then
                ctx.settings[setting_key] = ability.name
                
                if ctx.save_callback then
                    ctx.save_callback()
                end
            end
            
            if is_selected then
                imgui.SetItemDefaultFocus()
            end
        end
        imgui.EndCombo()
    end
    
    -- Right-click context menu for combat_only toggle (attaches to the combo)
    if selected then
        render_combat_only_context_menu(ctx, selected)
    end
    
    -- Show tooltip
    if imgui.IsItemHovered() and selected then
        if selected_combat_only then
            imgui.SetTooltip('Combat Only')
        elseif selected.idle_only then
            imgui.SetTooltip('Idle Only')
        end
    end
    
    imgui.PopItemWidth()
    
    if selected and (selected_combat_only or selected.idle_only) then
        imgui.PopStyleColor()
    end
end

-- True when an ability needs a specific pet summoned (requires_pet_name) that
-- isn't out right now -- used to gray the row and tooltip why.
local function pet_type_unmet(ability)
    return ability.requires_pet_name ~= nil and not common.pet_type_ok(ability)
end

-- Tooltip text naming the pet(s) a requires_pet_name ability needs.
local function pet_type_tooltip(ability)
    return 'Requires pet ' .. table.concat(ability.requires_pet_name, ' / ')
end

-- Render a self-target single ability
-- Layout: [ON/OFF Button] Ability Name
function ui_components.self_single_ability(ctx, ability, job_def, id_suffix)
    local has_spell = common.has_spell_learned(ability)
    -- Ammo-gated ability (BST Reward Regen) with none of the consumable owned:
    -- gray it like an unlearned spell and say what's missing.
    local no_ammo = ability.requires_equipped_ammo
        and common.count_equippable_items(ability.requires_equipped_ammo) == 0
    local wrong_pet = pet_type_unmet(ability)
    local spell_suffix = ''
    local ability_combat_only = effective_combat_only(ability, ctx)

    ui_components.onoff_button(ctx, ability.name, job_def, has_spell)

    imgui.SameLine()

    -- Push text color after buttons so S button / ON/OFF button are not tinted
    if not has_spell or no_ammo or wrong_pet then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif ability_combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif ability.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end
    
    local desc
    if ability.cost and ability.cost > 0 then
        local resource_label = (ability.resource_type or job_def.resource_type) == 'tp' and 'TP' or 'MP'
        local display_cost = math.floor(ability.cost * get_stratagem_mp_modifier(ctx, ability.name))
        desc = ability.name .. ' (' .. display_cost .. ' ' .. resource_label .. ')' .. spell_suffix
    else
        desc = ability.name .. spell_suffix
    end
    imgui.Text(desc)
    
    render_combat_only_context_menu(ctx, ability)

    if imgui.IsItemHovered() then
        if not has_spell then
            imgui.SetTooltip('Not Learned')
        elseif no_ammo then
            imgui.SetTooltip('No ' .. (ability.ammo_label or 'item') .. ' found in storage.')
        elseif wrong_pet then
            imgui.SetTooltip(pet_type_tooltip(ability))
        elseif ability_combat_only then
            imgui.SetTooltip('Combat Only')
        elseif ability.idle_only then
            imgui.SetTooltip('Idle Only')
        end
    end

    if not has_spell or no_ammo or wrong_pet or ability_combat_only or ability.idle_only then
        imgui.PopStyleColor()
    end
end

-- Render a self-target grouped ability with dropdown
-- Layout: [ON/OFF Button] [Dropdown]
function ui_components.self_grouped_ability(ctx, ability, job_def)
    if not ability.group then
        return
    end
    
    local usable = get_usable_abilities_in_group(job_def, ability.group, ctx)
    if #usable == 0 then
        return
    end
    
    local selected = get_selected_ability_for_group(ctx, job_def, ability.group)
    if not selected then
        return
    end
    
    local has_spell = common.has_spell_learned(selected)
    
    -- Leading slot: scholar S button / bard [A] indent / spacer (aligns the row)
    render_leading_slot(ability.group, selected, ctx)

    -- Use group-based ON/OFF button
    local is_enabled = is_group_enabled(ctx, ability.group)
    local button_width = get_onoff_button_width()
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_DISABLED)
    elseif is_enabled then
        -- Use default colors
    else
        imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
    end
    
    local button_text = is_enabled and 'ON' or 'OFF'
    local button_label = button_text .. '##onoff_group_' .. ability.group
    
    if has_spell and imgui.Button(button_label, { button_width, 0 }) then
        toggle_group(ctx, ability.group, not is_enabled)
    elseif not has_spell then
        imgui.Button(button_label, { button_width, 0 })
    end
    
    if not has_spell or not is_enabled then
        imgui.PopStyleColor(3)
    end
    
    -- Push text color after buttons so S button / ON/OFF button are not tinted
    local selected_combat_only = effective_combat_only(selected, ctx)
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif selected_combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif selected.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end
    
    imgui.SameLine()
    ui_components.group_dropdown(ctx, job_def, ability.group, DROPDOWN_WIDTH)
    
    if not has_spell or selected_combat_only or selected.idle_only then
        imgui.PopStyleColor()
    end
end

-- Render a party-target single ability
-- Layout: [ME] [P1] [P2]... Ability Name
function ui_components.party_single_ability(ctx, ability, job_def)
    local has_spell = common.has_spell_learned(ability)
    local spell_suffix = ''

    -- Check if Pianissimo/target modifier is required but not available
    local requires_modifier = ability.target_modifier == true
    local has_modifier = true
    if requires_modifier and has_spell then
        has_modifier = false
        if job_def.abilities.target_modifier then
            local main_level, sub_level = common.get_player_level()
            for _, modifier_ability in ipairs(job_def.abilities.target_modifier) do
                local is_main_job = ability.is_main_job ~= false
                local level_to_check = is_main_job and main_level or sub_level
                if modifier_ability.level and level_to_check >= modifier_ability.level then
                    has_modifier = true
                    break
                end
            end
        end
        if not has_modifier then
            spell_suffix = spell_suffix .. ' (Pianissimo Lv20)'
        end
    end
    
    local desc
    if ability.cost and ability.cost > 0 then
        local resource_label = (ability.resource_type or job_def.resource_type) == 'tp' and 'TP' or 'MP'
        local display_cost = math.floor(ability.cost * get_stratagem_mp_modifier(ctx, ability.name))
        desc = ability.name .. ' (' .. display_cost .. ' ' .. resource_label .. ')' .. spell_suffix
    else
        desc = ability.name .. spell_suffix
    end
    
    local wrong_pet = pet_type_unmet(ability)

    render_party_buttons(ctx, ability.name, has_spell, ability, false)

    imgui.SameLine()

    local ability_combat_only = effective_combat_only(ability, ctx)
    if not has_spell or not has_modifier or wrong_pet then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif ability_combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif ability.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end

    imgui.Text(desc)

    render_combat_only_context_menu(ctx, ability)

    if imgui.IsItemHovered() then
        if not has_spell then
            imgui.SetTooltip('Not Learned')
        elseif wrong_pet then
            imgui.SetTooltip(pet_type_tooltip(ability))
        elseif ability_combat_only then
            imgui.SetTooltip('Combat Only')
        elseif ability.idle_only then
            imgui.SetTooltip('Idle Only')
        end
    end

    if not has_spell or not has_modifier or wrong_pet or ability_combat_only or ability.idle_only then
        imgui.PopStyleColor()
    end
end

-- Render a party-target grouped ability with dropdown
-- Layout: [ME] [P1] [P2]... [Dropdown]
function ui_components.party_grouped_ability(ctx, ability, job_def)
    if not ability.group then
        return
    end
    
    local usable = get_usable_abilities_in_group(job_def, ability.group, ctx)
    if #usable == 0 then
        return
    end
    
    local selected = get_selected_ability_for_group(ctx, job_def, ability.group)
    if not selected then
        return
    end
    
    local has_spell = common.has_spell_learned(selected)
    
    -- Check if Pianissimo/target modifier is required but not available
    local requires_modifier = selected.target_modifier == true
    local has_modifier = true
    if requires_modifier and has_spell then
        has_modifier = false
        if job_def.abilities.target_modifier then
            local main_level, sub_level = common.get_player_level()
            for _, modifier_ability in ipairs(job_def.abilities.target_modifier) do
                local is_main_job = selected.is_main_job ~= false
                local level_to_check = is_main_job and main_level or sub_level
                if modifier_ability.level and level_to_check >= modifier_ability.level then
                    has_modifier = true
                    break
                end
            end
        end
    end
    
    render_party_buttons(ctx, ability.group, has_spell, selected, true)
    
    imgui.SameLine()
    
    local selected_combat_only = effective_combat_only(selected, ctx)
    if not has_spell or not has_modifier then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif selected_combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif selected.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end
    
    ui_components.group_dropdown(ctx, job_def, ability.group, DROPDOWN_WIDTH)
    
    if not has_spell or not has_modifier or selected_combat_only or selected.idle_only then
        imgui.PopStyleColor()
    end
end

-- Main ability renderer - determines which rendering function to use
function ui_components.render_ability(ctx, ability, job_def, id_suffix)
    local filters = get_filters(ctx)
    
    if not ability or not filters.can_use_ability(ability) then
        return false
    end
    
    if is_subjob_duplicate(job_def, ability, ctx) then
        return false
    end
    
    -- Ungrouped groups render every tier as its own row (per-name), like a
    -- non-grouped ability, instead of a single-select dropdown.
    local has_group = ability.group ~= nil
        and not (ctx.settings and ctx.settings['ungrouped_' .. ability.group])
    local is_party_target = can_cast_on_party(ability)
    
    if has_group then
        local group_key = 'rendered_group_' .. ability.group
        if ctx.settings and ctx.settings[group_key] then
            return false
        end
        
        local usable = get_usable_abilities_in_group(job_def, ability.group, ctx)
        if #usable == 0 then
            return false
        end
        
        ctx.settings[group_key] = true
    end
    
    if has_group then
        if is_party_target then
            ui_components.party_grouped_ability(ctx, ability, job_def)
        else
            ui_components.self_grouped_ability(ctx, ability, job_def)
        end
    else
        if is_party_target then
            ui_components.party_single_ability(ctx, ability, job_def)
        else
            ui_components.self_single_ability(ctx, ability, job_def, id_suffix)
        end
    end
    
    return true
end

-- ============================================================================
-- UI Element Creators
-- ============================================================================

-- Show a static help tooltip for the most recently rendered item.
function ui_components.item_tooltip(text)
    if text and imgui.IsItemHovered() then
        imgui.SetTooltip(text)
    end
end

-- Create a checkbox UI element linked to a setting
function ui_components.checkbox(ctx, label, setting_name, ui_var)
    if imgui.Checkbox(label, ui_var) then
        ctx.settings[setting_name] = ui_var[1]
        if ctx.save_callback then
            ctx.save_callback()
        end
    end
end

-- Create a collapsible header with checkbox
function ui_components.collapsing_checkbox_header(ctx, label, setting_name, default_value)
    local setting_value = ctx.settings[setting_name]
    if setting_value == nil then
        setting_value = default_value
    end
    local setting_var = { setting_value }
    local previous_value = setting_var[1]
    if imgui.Checkbox('##' .. setting_name, setting_var) then
        ctx.settings[setting_name] = setting_var[1]
        if ctx.save_callback then
            ctx.save_callback()
        end
        -- Auto-expand when enabling the section (only on the transition from disabled to enabled)
        if setting_var[1] and not previous_value then
            imgui.SetNextItemOpen(true)
        end
    end
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol_Header, HEADER_COLOR_NORMAL)
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, HEADER_COLOR_HOVERED)
    imgui.PushStyleColor(ImGuiCol_HeaderActive, HEADER_COLOR_ACTIVE)
    local is_open = imgui.CollapsingHeader(label, ImGuiTreeNodeFlags_DefaultOpen)
    imgui.PopStyleColor(3)
    return is_open, setting_var[1]
end

-- Create an integer slider UI element linked to a setting
function ui_components.slider_int(ctx, label, setting_name, ui_var, min, max, width)
    width = width or SLIDER_WIDTH
    imgui.PushItemWidth(width)
    if imgui.SliderInt(label, ui_var, min, max) then
        ctx.settings[setting_name] = ui_var[1]
        if ctx.save_callback then
            ctx.save_callback()
        end
    end
    imgui.PopItemWidth()
end

-- Create a combo dropdown UI element linked to a setting
function ui_components.combo(ctx, label, setting_name, ui_var, options, converter, width)
    width = width or SLIDER_WIDTH
    imgui.PushItemWidth(width)
    local current_value = options[ui_var[1] + 1] or options[1] or ""
    if imgui.BeginCombo(label, current_value) then
        for i = 0, #options - 1 do
            local is_selected = (ui_var[1] == i)
            if imgui.Selectable(options[i + 1], is_selected) then
                ui_var[1] = i
                if converter then
                    ctx.settings[setting_name] = converter(i)
                else
                    ctx.settings[setting_name] = i
                end
                if ctx.save_callback then
                    ctx.save_callback()
                end
            end
            if is_selected then
                imgui.SetItemDefaultFocus()
            end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
end

-- Render an ability checkbox with spell knowledge checking
function ui_components.ability_checkbox(ctx, ability, job_def, id_suffix, show_stratagem)
    -- Optionally render the Scholar stratagem S button before the checkbox.
    -- Only call when the ability's magic matches the current arts stance so that
    -- sections where NO spell qualifies don't get pointless spacers.
    if show_stratagem and ability.magic then
        local dominated = false
        if ability.magic == 'white' then
            dominated = common.has_buff(0, 358) or common.has_buff(0, 401) -- Light Arts / Addendum: White
        elseif ability.magic == 'black' then
            dominated = common.has_buff(0, 359) or common.has_buff(0, 402) -- Dark Arts / Addendum: Black
        end
        if dominated then
            render_scholar_stratagem_button(ability.name, ability, ctx)
        end
    end

    local has_spell = common.has_spell_learned(ability)
    -- Ammo-gated abilities (BST Reward, PUP Repair) can't fire with none of the
    -- consumable in inventory/storage. Show them grayed like an unlearned spell.
    local no_ammo = ability.requires_equipped_ammo
        and common.count_equippable_items(ability.requires_equipped_ammo) == 0
    local wrong_pet = pet_type_unmet(ability)
    local spell_suffix = ''
    if not has_spell then
        ctx.settings['disabled_' .. ability.name:gsub(' ', '_')] = true
    end
    
    local desc
    if ability.cost and ability.cost > 0 then
        local resource_label = (ability.resource_type or job_def.resource_type) == 'tp' and 'TP' or 'MP'
        local display_cost = math.floor(ability.cost * get_stratagem_mp_modifier(ctx, ability.name))
        desc = ability.name .. ' (' .. display_cost .. ' ' .. resource_label .. ')' .. spell_suffix
    else
        desc = ability.name .. spell_suffix
    end
    
    local checkbox_label = desc
    if id_suffix then
        checkbox_label = desc .. '##' .. id_suffix
    end
    
    local ability_combat_only = effective_combat_only(ability, ctx)
    if not has_spell or no_ammo or wrong_pet then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif ability_combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif ability.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end

    local ability_enabled = { is_ability_enabled(ctx, ability.name) }
    if imgui.Checkbox(checkbox_label, ability_enabled) then
        toggle_ability(ctx, ability.name, ability_enabled[1], job_def)
    end

    render_combat_only_context_menu(ctx, ability)

    if imgui.IsItemHovered() then
        if not has_spell then
            imgui.SetTooltip('Not Learned')
        elseif no_ammo then
            imgui.SetTooltip('No ' .. (ability.ammo_label or 'item') .. ' found in storage.')
        elseif wrong_pet then
            imgui.SetTooltip(pet_type_tooltip(ability))
        elseif ability_combat_only then
            imgui.SetTooltip('Combat Only')
        elseif ability.idle_only then
            imgui.SetTooltip('Idle Only')
        elseif ctx.show_pet_debuff_warning then
            imgui.SetTooltip('Pet Tracked Removal is not totally reliable')
        end
    end

    if not has_spell or no_ammo or wrong_pet or ability_combat_only or ability.idle_only then
        imgui.PopStyleColor()
    end
end

-- ============================================================================
-- Item Checkbox Component
-- ============================================================================

-- Render a checkbox for item-based debuff removal (DRY helper)
-- Args: ctx, item_name, setting_key, debuff_name, extra_tooltip
local function render_item_removal_checkbox(ctx, item_name, setting_key, debuff_name, extra_tooltip)
    if not ctx or not ctx.settings then return end

    local count = item_module.get_item_count(item_name)

    -- Build label with count (show ? while inventory loads)
    local checkbox_label
    if count == nil then
        checkbox_label = string.format('Remove %s with %s (?)', debuff_name, item_name)
    else
        checkbox_label = string.format('Remove %s with %s (%d)', debuff_name, item_name, count)
    end

    local is_disabled = (count == 0)

    -- Auto-disable when inventory is loaded but item count is zero
    if is_disabled and count ~= nil and ctx.settings[setting_key] then
        ctx.settings[setting_key] = false
        if ctx.save_callback then ctx.save_callback() end
    end

    -- Disabled styling
    if is_disabled then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
        imgui.PushStyleColor(ImGuiCol_FrameBg, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_FrameBgHovered, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_FrameBgActive, COLOR_BUTTON_DISABLED)
        imgui.PushStyleColor(ImGuiCol_CheckMark, LIGHT_GRAY)
    end

    local enabled = { ctx.settings[setting_key] or false }

    if not is_disabled and imgui.Checkbox(checkbox_label, enabled) then
        ctx.settings[setting_key] = enabled[1]
        if ctx.save_callback then ctx.save_callback() end
    elseif is_disabled then
        imgui.Checkbox(checkbox_label, enabled)
    end

    if is_disabled then imgui.PopStyleColor(5) end

    if imgui.IsItemHovered() then
        local tooltip_text
        if is_disabled then
            tooltip_text = string.format('No %s in inventory', item_name)
        else
            tooltip_text = string.format('Use %s to remove %s', item_name, debuff_name)
        end
        if extra_tooltip then
            tooltip_text = tooltip_text .. '\n\n' .. extra_tooltip
        end
        imgui.SetTooltip(tooltip_text)
    end
end

function ui_components.item_silence_removal_checkbox(ctx, extra_tooltip)
    render_item_removal_checkbox(ctx, 'Echo Drops', 'item_silence_removal_enabled', 'Silence', extra_tooltip)
end

function ui_components.item_doom_removal_checkbox(ctx, extra_tooltip)
    render_item_removal_checkbox(ctx, 'Holy Water', 'item_doom_removal_enabled', 'Doom', extra_tooltip)
end

-- ============================================================================
-- Party Selection Buttons (for status removal targeting)
-- ============================================================================

-- Render party selection buttons for a feature (debuff removal, wake, etc.)
-- Provides a row of [ME] [P1] [P2]... [B0] [C0]... [T1]... toggle buttons.
-- Reuses ctx.party_buffs[key_name][party_index] for state storage.
-- Auto-initialises all current party members as enabled on first render.
-- Args:
--   ctx          - UI context (settings, save_callback, party_buffs, is_trust)
--   key_name     - Key in party_buffs (e.g. "debuff_removal", "wake")
--   show_outside - Whether to show alliance/tracked target buttons
--   include_self - Whether to show the [ME] button (default true)
-- Returns: true if any button was rendered
function ui_components.render_party_selection(ctx, key_name, show_outside, include_self)
    if include_self == nil then include_self = true end

    -- Auto-initialise on first render: enable all current party members
    if not ctx.party_buffs[key_name] then
        ctx.party_buffs[key_name] = {}
        if include_self then
            ctx.party_buffs[key_name][0] = true
        end
        local ps = common.get_party_size()
        for i = 1, math.min(ps - 1, 5) do
            ctx.party_buffs[key_name][i] = true
        end
        -- Persist
        ctx.settings.party_buffs = ctx.settings.party_buffs or {}
        ctx.settings.party_buffs[key_name] = {}
        for k, v in pairs(ctx.party_buffs[key_name]) do
            if type(k) == 'number' and k <= 5 then
                ctx.settings.party_buffs[key_name][k] = v
            end
        end
        if ctx.save_callback then ctx.save_callback() end
    end

    local function is_sel(index)
        return ctx.party_buffs[key_name][index] == true
    end

    local function toggle_sel(index, enabled)
        ctx.party_buffs[key_name][index] = enabled
        if type(index) == 'number' and index <= 5 then
            ctx.settings.party_buffs = ctx.settings.party_buffs or {}
            ctx.settings.party_buffs[key_name] = ctx.settings.party_buffs[key_name] or {}
            ctx.settings.party_buffs[key_name][index] = enabled
        end
        if ctx.save_callback then ctx.save_callback() end
    end

    local any_rendered = false

    -- [ME] button
    if include_self then
        local me_on = is_sel(0)
        if not me_on then
            imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
        end
        if imgui.Button('ME##' .. key_name .. '_sel_me', { PARTY_BUTTON_WIDTH, 0 }) then
            toggle_sel(0, not me_on)
        end
        if not me_on then
            imgui.PopStyleColor(3)
        end
        any_rendered = true
    end

    -- P1-P5 buttons
    local party_size = common.get_party_size()
    if party_size > 1 then
        for pi = 1, 5 do
            if pi < party_size then
                if any_rendered then imgui.SameLine() end
                local p_on = is_sel(pi)
                local is_trust_member = ctx.is_trust and ctx.is_trust(pi)

                if not p_on then
                    imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
                end
                if imgui.Button('P' .. pi .. '##' .. key_name .. '_sel_p' .. pi, { PARTY_BUTTON_WIDTH, 0 }) then
                    toggle_sel(pi, not p_on)
                end
                -- Trust warning tooltip
                if is_trust_member and imgui.IsItemHovered() then
                    imgui.SetTooltip('Trust/Tracked Removal is not totally reliable')
                end
                if not p_on then
                    imgui.PopStyleColor(3)
                end
                any_rendered = true
            end
        end
    end

    -- Alliance buttons
    if show_outside then
        local al_gs = common.game_state
        if al_gs and al_gs.alliance then
            local alliance_prefixes = { [2] = 'B', [3] = 'C' }
            for api = 2, 3 do
                local sub_party = al_gs.alliance[api]
                if sub_party and next(sub_party) ~= nil then
                    local prefix = alliance_prefixes[api]
                    local sorted_al = common.sorted_alliance_members(sub_party)
                    for _, entry in ipairs(sorted_al) do
                        local local_idx = entry.local_idx
                        local m = entry.m
                        local flat_index = (api - 1) * 6 + local_idx
                        local al_key = 'al_' .. flat_index

                        if any_rendered then imgui.SameLine() end
                        local al_on = is_sel(al_key)
                        if not al_on then
                            imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
                            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
                            imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
                        end
                        if imgui.Button(prefix .. local_idx .. '##' .. key_name .. '_sel_' .. al_key, { PARTY_BUTTON_WIDTH, 0 }) then
                            toggle_sel(al_key, not al_on)
                        end
                        if imgui.IsItemHovered() then
                            imgui.SetTooltip(m.name or (prefix .. local_idx))
                        end
                        if not al_on then
                            imgui.PopStyleColor(3)
                        end
                        any_rendered = true
                    end
                end
            end
        end

        -- Tracked target buttons
        local tracked_list = common.get_tracked_targets()
        local sorted_tracked = {}
        for sid, tt in pairs(tracked_list) do
            table.insert(sorted_tracked, { sid = sid, name = tt.name })
        end
        table.sort(sorted_tracked, function(a, b) return a.name < b.name end)
        for t_idx, tt in ipairs(sorted_tracked) do
            if any_rendered then imgui.SameLine() end
            local tt_key = 'tt_' .. tt.sid
            local tt_on = is_sel(tt_key)
            if not tt_on then
                imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
                imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
            end
            if imgui.Button('T' .. t_idx .. '##' .. key_name .. '_sel_t' .. tt.sid, { PARTY_BUTTON_WIDTH, 0 }) then
                toggle_sel(tt_key, not tt_on)
            end
            -- Always show warning tooltip for tracked targets
            if imgui.IsItemHovered() then
                imgui.SetTooltip(tt.name .. '\nTrust/Tracked Removal is not totally reliable')
            end
            if not tt_on then
                imgui.PopStyleColor(3)
            end
            any_rendered = true
        end
    end

    return any_rendered
end

-- Render group-target selection buttons for Group / AOE healing.
-- Unlike render_party_selection (wake/debuff) this is SESSION-ONLY (never
-- persisted) and uses asymmetric defaults so the behaviour is correct even
-- when the config window was never opened this session:
--   ME / party / tracked -> ON  by default (included unless explicitly disabled)
--   alliance (B/C)        -> OFF by default (excluded unless explicitly enabled)
-- State lives in ctx.party_buffs[key_name]; heal.lua reads it via the same keys.
-- show_outside: whether to draw alliance + tracked buttons (Group=true, AOE=false;
-- AOE healing is party-scoped so out-of-party buttons would do nothing).
function ui_components.render_heal_group_selection(ctx, key_name, show_outside)
    ctx.party_buffs[key_name] = ctx.party_buffs[key_name] or {}
    local state = ctx.party_buffs[key_name]

    -- party/tracked default ON (~= false); alliance default OFF (== true)
    local function is_sel(key, is_alliance)
        if is_alliance then return state[key] == true end
        return state[key] ~= false
    end

    local function draw(label, id, on, on_click, tooltip)
        if not on then
            imgui.PushStyleColor(ImGuiCol_Button, COLOR_BUTTON_UNSELECTED)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_BUTTON_UNSELECTED_HOVER)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_BUTTON_UNSELECTED_ACTIVE)
        end
        if imgui.Button(label .. '##' .. key_name .. '_gsel_' .. id, { PARTY_BUTTON_WIDTH, 0 }) then
            on_click()
        end
        if tooltip and imgui.IsItemHovered() then imgui.SetTooltip(tooltip) end
        if not on then imgui.PopStyleColor(3) end
    end

    -- [ME]
    do
        local on = is_sel(0)
        draw('ME', 'me', on, function() state[0] = not on end)
    end

    -- P1-P5
    local party_size = common.get_party_size()
    for pi = 1, 5 do
        if pi < party_size then
            imgui.SameLine()
            local on = is_sel(pi)
            draw('P' .. pi, 'p' .. pi, on, function() state[pi] = not on end)
        end
    end

    if not show_outside then return true end

    -- Alliance B/C
    local gs = common.game_state
    if gs and gs.alliance then
        local prefixes = { [2] = 'B', [3] = 'C' }
        for api = 2, 3 do
            local sub = gs.alliance[api]
            if sub and next(sub) ~= nil then
                for _, entry in ipairs(common.sorted_alliance_members(sub)) do
                    local al_key = 'al_' .. ((api - 1) * 6 + entry.local_idx)
                    imgui.SameLine()
                    local on = is_sel(al_key, true)
                    draw(prefixes[api] .. entry.local_idx, al_key, on,
                        function() state[al_key] = not on end, entry.m.name)
                end
            end
        end
    end

    -- Tracked targets
    local sorted = {}
    for sid, tt in pairs(common.get_tracked_targets()) do
        table.insert(sorted, { sid = sid, name = tt.name })
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    for t_idx, tt in ipairs(sorted) do
        imgui.SameLine()
        local tt_key = 'tt_' .. tt.sid
        local on = is_sel(tt_key)
        draw('T' .. t_idx, 't' .. tt.sid, on, function() state[tt_key] = not on end, tt.name)
    end

    return true
end

-- ============================================================================
-- Export Constants
-- ============================================================================

ui_components.ABILITY_LIST_INDENT = ABILITY_LIST_INDENT
ui_components.AUTOMATION_BUTTON_WIDTH = AUTOMATION_BUTTON_WIDTH
ui_components.LIGHT_GREEN = LIGHT_GREEN
ui_components.LIGHT_BLUE = LIGHT_BLUE
ui_components.LIGHT_RED = LIGHT_RED

return ui_components
