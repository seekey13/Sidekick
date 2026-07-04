--[[
    Generic configuration UI for Medic
    Dynamically generates UI based on loaded job definition
]]--

local ui_config = {}

local imgui = require('imgui')
local common = require('lib.core.common')
local ui = require('lib.ui.components')
local tooltips = require('lib.ui.tooltips')

-- UI state
local is_open = { true }
local ui_visible = false
local force_expand = false  -- when true, next render un-collapses the window once

-- Settings reference and callback
local current_settings = nil
local save_callback = nil
local roll_module = nil

-- UI State Variables (for imgui)
local focus_enabled = { false }
local focus_recovery_enabled = { false }

-- Focus state (now saved to settings as names)
local focus_target_name = nil  -- Character name or nil for None
local focus_recovery_target_name = nil  -- Character name or nil for None
local follow_target_name = nil  -- Character name or nil for None

-- Entrust state (now saved to settings)
local entrust_target_name = nil  -- Character name or nil for None
local entrust_spell_name = nil   -- Spell name like "Indi-Haste" or nil for None

-- Party buff tracking (session only, not saved to settings)
-- Structure: party_buffs[ability_name][party_index] = true/false
-- party_index: 1-5 for P1-P5 (player is always handled separately)
local party_buffs = {}

-- ============================================================================
-- Helper Functions (Remaining in ui_config)
-- ============================================================================

-- Check if player can use an ability based on level
local function can_use_ability(ability)
    if not ability or not ability.level then
        return true
    end
    
    -- Check if ability requires main job only (e.g., Geo spells)
    if ability.main_job_only and ability.is_main_job == false then
        return false
    end
    
    local main_level, sub_level
    main_level, sub_level = common.get_player_level()
    
    -- Check if this ability is for main job or subjob
    -- Abilities marked with is_main_job = false are from subjob
    local result
    if ability.is_main_job == false then
        result = sub_level >= ability.level
    else
        result = main_level >= ability.level
    end
    
    return result
end

-- Get all abilities in the same group as the given ability (returns ability objects, not just names)
local function get_abilities_in_group(job_def, target_group)
    local group_abilities = {}
    if not job_def or not target_group then
        return group_abilities
    end
    
    -- Search through all ability categories
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
local function get_usable_abilities_in_group(job_def, target_group)
    local all_abilities = get_abilities_in_group(job_def, target_group)
    local usable = {}
    
    for _, ability in ipairs(all_abilities) do
        if can_use_ability(ability) and common.has_spell_learned(ability) then
            table.insert(usable, ability)
        end
    end
    
    return usable
end

-- Check if a list of abilities has any usable abilities (level-appropriate)
local function has_usable_abilities(abilities)
    if not abilities then
        return false
    end
    
    -- Check if table has any entries at all
    local has_any = false
    for _, ability in pairs(abilities) do
        has_any = true
        if can_use_ability(ability) then
            return true
        end
    end
    
    return false
end

-- Check if an ability is a duplicate from subjob
local function is_subjob_duplicate(job_def, ability)
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

-- Check if a party member is a Trust (server_id >= 0x1000000)
local function is_trust(party_index)
    local party = common.get_party()
    if not party then
        return false
    end
    
    local ok_server, server_id = pcall(function()
        return party:GetMemberServerId(party_index)
    end)
    
    if not ok_server or not server_id or server_id == 0 then
        return false
    end
    
    -- Trusts have server IDs >= 0x1000000 (16777216)
    return server_id >= 0x1000000
end

-- Render a party-member dropdown (reusable for Focus/Follow/Recovery/Entrust Target)
-- Args:
--   label (string) - Combo display label
--   setting_key (string) - Key in settings to read/write the selected name
--   include_player (bool) - Whether to include P0 (the player) in the list
--   party_member_names (table) - Pre-built list of P1-P5 names
--   settings (table) - Current settings table
--   on_change (function|nil) - Callback after selection changes
--   include_tracked (bool|nil) - Whether to include tracked targets (default false)
-- Returns: string|nil - The currently selected name (or nil for 'None')
local function render_party_dropdown(label, setting_key, include_player, party_member_names, settings, on_change, include_tracked)
    local options = { 'None' }
    if include_player then
        local player_name = common.get_party_member_name(0)
        if player_name and player_name ~= '' then
            table.insert(options, player_name)
        end
    end
    for _, name in ipairs(party_member_names) do
        table.insert(options, name)
    end

    -- Include tracked target names if requested
    if include_tracked then
        local tracked_list = common.get_tracked_targets()
        for _, tt in pairs(tracked_list) do
            if tt.name and tt.name ~= '' then
                table.insert(options, tt.name)
            end
        end
    end

    -- Validate saved name is in current party
    local current_name = settings[setting_key]
    local current_display = 'None'
    if current_name then
        local found = false
        for _, name in ipairs(options) do
            if name == current_name then
                current_display = current_name
                found = true
                break
            end
        end
        if not found then
            settings[setting_key] = nil
            if on_change then on_change() end
        end
    end

    -- Render dropdown
    imgui.PushItemWidth(250)
    imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.2, 0.2, 0.2, 1.0 })
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, { 0.3, 0.3, 0.3, 1.0 })
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, { 0.4, 0.4, 0.4, 1.0 })
    if imgui.BeginCombo(label, current_display) then
        for _, option in ipairs(options) do
            local is_selected = (option == current_display)
            if imgui.Selectable(option, is_selected) then
                settings[setting_key] = (option ~= 'None') and option or nil
                if on_change then on_change() end
            end
            if is_selected then
                imgui.SetItemDefaultFocus()
            end
        end
        imgui.EndCombo()
    end
    imgui.PopStyleColor(3)
    imgui.PopItemWidth()

    return settings[setting_key]
end

-- Sync UI state from settings
local function sync_from_settings()
    if not current_settings then return end
    
    focus_enabled[1] = current_settings.focus_enabled or false
    
    -- Focus target settings are now loaded on first render
end

-- ============================================================================
-- Module Functions
-- ============================================================================

function ui_config.initialize()
    -- No-op, reserved for future use
end

function ui_config.show()
    ui_visible = true
    is_open[1] = true
    -- Force the window uncollapsed on open. imgui persists a collapsed state in
    -- imgui.ini; without this, opening a previously-collapsed window shows only
    -- the title bar (and used to be force-closed by the render below).
    force_expand = true
end

function ui_config.hide()
    ui_visible = false
    is_open[1] = false
end

function ui_config.toggle()
    if ui_visible then
        ui_config.hide()
    else
        ui_config.show()
    end
end

function ui_config.is_visible()
    return ui_visible
end

function ui_config.get_party_buffs()
    return party_buffs
end

function ui_config.get_entrust_config()
    -- Return nil if entrust target or spell is None
    if not entrust_target_name or not entrust_spell_name then
        return nil
    end
    
    -- Find party member by name (check P1-P5 only, not P0)
    local party = common.get_party()
    if not party then
        return nil
    end
    
    local target_index = nil
    for i = 1, 5 do
        local member_name = common.get_party_member_name(i)
        if member_name and member_name == entrust_target_name then
            target_index = i
            break
        end
    end
    
    if not target_index then
        -- Target not in party
        return nil
    end
    
    return {
        target_index = target_index,         -- 1-5 for P1-P5
        target_name = entrust_target_name,   -- Character name
        spell_name = entrust_spell_name,     -- Spell name like "Indi-Haste"
    }
end

function ui_config.render(settings, job_def, callback, roll_mod)
    if not ui_visible or not is_open[1] then
        return
    end
    
    -- Load entrust settings from settings on first render
    if settings.entrust_target ~= nil and entrust_target_name == nil then
        entrust_target_name = settings.entrust_target
    end
    if settings.entrust_spell ~= nil and entrust_spell_name == nil then
        entrust_spell_name = settings.entrust_spell
    end
    
    -- Load party buff selections from settings on first render
    if settings.party_buffs and next(party_buffs) == nil then
        -- Deep copy party_buffs from settings
        for ability_name, targets in pairs(settings.party_buffs) do
            party_buffs[ability_name] = {}
            for party_index, enabled in pairs(targets) do
                party_buffs[ability_name][party_index] = enabled
            end
        end
    end
    
    -- Always sync disabled_ keys from party_buffs to ensure consistency
    -- This prevents old disabled_ values from overriding the party buff selections
    if settings.party_buffs then
        for ability_name, targets in pairs(settings.party_buffs) do
            -- Check if ANY button is enabled for this ability
            local any_button_enabled = false
            for party_index, enabled in pairs(targets) do
                if enabled == true then
                    any_button_enabled = true
                    break
                end
            end
            -- Also check session-only tracked target entries (keyed as 'tt_<sid>')
            if not any_button_enabled and party_buffs[ability_name] then
                for k, v in pairs(party_buffs[ability_name]) do
                    if v == true and type(k) == 'string' then
                        any_button_enabled = true
                        break
                    end
                end
            end
            
            -- Sync the disabled_ key
            local disabled_key = 'disabled_' .. ability_name:gsub(' ', '_')
            if any_button_enabled then
                settings[disabled_key] = false
            else
                settings[disabled_key] = true
            end
        end
    end
    
    -- Load focus target settings from settings on first render
    if settings.focus_target ~= nil and focus_target_name == nil then
        focus_target_name = settings.focus_target
    end
    if settings.focus_recovery_target ~= nil and focus_recovery_target_name == nil then
        focus_recovery_target_name = settings.focus_recovery_target
    end
    if settings.follow_target ~= nil and follow_target_name == nil then
        follow_target_name = settings.follow_target
    end
    
    -- Store settings reference and callback
    current_settings = settings
    save_callback = callback
    roll_module = roll_mod
    
    -- Sync UI state from settings
    sync_from_settings()
    
    -- Create context object for ui_components
    local ctx = {
        settings = current_settings,
        save_callback = save_callback,
        party_buffs = party_buffs,
        job_def = job_def,
        can_use_ability = can_use_ability,
        get_abilities_in_group = get_abilities_in_group,
        get_usable_abilities_in_group = get_usable_abilities_in_group,
        is_trust = is_trust,
        filter_func = {
            can_use_ability = can_use_ability
        }
    }
    
    -- Build party member list once (used by multiple dropdowns)
    local party_member_names = {}  -- Names only (P1-P5, excluding player)
    local party = common.get_party()
    if party then
        for i = 1, 5 do
            if party:GetMemberIsActive(i) == 1 then
                local member_name = common.get_party_member_name(i)
                if member_name and member_name ~= '' then
                    table.insert(party_member_names, member_name)
                end
            end
        end
    end

    -- Use consistent window title to maintain position across job changes
    local window_title = 'Medic Configuration'

    -- Un-collapse once when the window is (re)opened, so a collapsed imgui.ini
    -- state doesn't leave the user staring at an empty title bar.
    if force_expand then
        if imgui.SetNextWindowCollapsed then
            imgui.SetNextWindowCollapsed(false)
        end
        force_expand = false
    end

    -- NOTE: imgui.Begin returns false when the window is COLLAPSED, not only when
    -- the [X] was clicked. Treat collapse as "still open, just skip content" and
    -- only close on the [X] (is_open flips to false). Always call End() to match
    -- Begin() per imgui rules.
    if imgui.Begin(window_title, is_open, ImGuiWindowFlags_NoResize + ImGuiWindowFlags_AlwaysAutoResize) then

        -- Display job name and levels
        if job_def and job_def.job_name then
            -- Show normal job info
            local main_job_id, sub_job_id = common.get_player_job()
            local main_level, sub_level = common.get_player_level()
            local main_job_name = common.get_job_name_from_id(main_job_id)
            local sub_job_name = 'None'
            if sub_level and sub_level > 0 and sub_job_id and sub_job_id > 0 then
                sub_job_name = common.get_job_name_from_id(sub_job_id)
            end
            imgui.TextColored(ui.LIGHT_GREEN, string.format('Job: %s %d / %s %d', main_job_name, main_level, sub_job_name, sub_level or 0))
        end
        
        -- Automation toggle button
        local is_loading = common.is_loading()
        local can_attack = common.can_attack()
        local is_resting = common.is_resting()
        local is_mounted = common.is_mounted()
        local is_dead = common.is_dead()
        local button_text
        local status_text
        local status_color
        
        if settings.automation_enabled then
            if is_loading then
                -- Loading state (automation fully suppressed while loading)
                button_text = 'Stop'
                status_text = 'Automation loading.'
                status_color = ui.LIGHT_BLUE
            elseif is_mounted then
                -- Mounted state (automation fully suppressed while on a mount)
                button_text = 'Stop'
                status_text = 'Automation mounted.'
                status_color = ui.LIGHT_BLUE
            elseif is_dead then
                -- Dead state (automation fully suppressed while dead)
                button_text = 'Stop'
                status_text = 'Automation dead.'
                status_color = ui.LIGHT_BLUE
            elseif is_resting then
                -- Resting state (automation enabled but resting for MP)
                button_text = 'Stop'
                status_text = 'Automation resting.'
                status_color = ui.LIGHT_BLUE
            elseif can_attack then
                -- Running state
                button_text = 'Stop'
                status_text = 'Automation running.'
                status_color = ui.LIGHT_GREEN
            else
                -- Paused state (automation enabled but combat blocked)
                button_text = 'Stop'
                status_text = 'Automation paused.'
                status_color = ui.LIGHT_BLUE
            end
        else
            -- Stopped state
            button_text = 'Start'
            status_text = 'Automation stopped.'
            status_color = ui.LIGHT_RED
        end
        
        -- Use fixed width for button to keep consistent size
        if imgui.Button(button_text, { ui.AUTOMATION_BUTTON_WIDTH, 0 }) then
            -- Toggle automation
            AshitaCore:GetChatManager():QueueCommand(1, '/medic toggle')
        end
        
        -- Display status on same line
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, status_color)
        imgui.Text(status_text)
        imgui.PopStyleColor()
        ui.item_tooltip(tooltips.automation_status)

        -- Add Tracked Target button: only visible when current target is a valid PC
        -- (not NPC, not Trust, not already in party, not already tracked, not already in alliance)
        local targets_lib = common.targets
        local target_entity = targets_lib.get_t()
        local show_add_btn = false
        if target_entity then
            local spawn_flags = target_entity.SpawnFlags or 0
            local is_pc = bit.band(spawn_flags, 0x0001) ~= 0
            local target_sid = target_entity.ServerId or 0
            if is_pc and target_sid > 0 and target_sid < 0x1000000 then
                -- Not a Trust; check it's not in our party
                local in_party = false
                local party_obj = common.get_party()
                if party_obj then
                    for pi = 0, 5 do
                        if party_obj:GetMemberIsActive(pi) == 1 then
                            if party_obj:GetMemberServerId(pi) == target_sid then
                                in_party = true
                                break
                            end
                        end
                    end
                end
                if not in_party and not common.is_tracked_target(target_sid) and not common.is_alliance_member(target_sid) then
                    show_add_btn = true
                end
            end
        end

        if show_add_btn then
            local add_target_btn_width = 120
            local content_max_x, _ = imgui.GetContentRegionMax()
            imgui.SameLine(content_max_x - add_target_btn_width)
            if imgui.Button('Track Target', { add_target_btn_width, 0 }) then
                AshitaCore:GetChatManager():QueueCommand(1, '/medic addtarget')
            end
            ui.item_tooltip(tooltips.tracked_targets)
        end
        
        -- Tracked Targets list (show if any are being tracked)
        local tracked_list = common.get_tracked_targets()
        local has_tracked = false
        for _ in pairs(tracked_list) do has_tracked = true; break end

        if has_tracked then
            local sorted_tt = {}
            for sid, tt in pairs(tracked_list) do
                table.insert(sorted_tt, { sid = sid, name = tt.name })
            end
            table.sort(sorted_tt, function(a, b) return a.name < b.name end)
            local remove_sid = nil
            local container_color = { 0.2, 0.2, 0.2, 1.0 }
            for t_idx, tt in ipairs(sorted_tt) do
                if t_idx > 1 then imgui.SameLine() end

                -- Non-interactive visual button container showing T-index + name
                imgui.PushStyleColor(ImGuiCol_Button, container_color)
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, container_color)
                imgui.PushStyleColor(ImGuiCol_ButtonActive, container_color)
                imgui.PushID('lbl_' .. tostring(tt.sid))
                imgui.Button('T' .. t_idx .. ' ' .. tt.name)
                imgui.PopID()
                imgui.PopStyleColor(3)

                imgui.SameLine(0, 2)
                imgui.PushID('rm_' .. tostring(tt.sid))
                if imgui.Button('X') then
                    remove_sid = tt.sid
                end
                imgui.PopID()
            end
            if remove_sid then
                common.remove_tracked_target(remove_sid)
                -- Clean up party_buffs entries for this tracked target
                local tt_key = 'tt_' .. remove_sid
                for key, targets in pairs(party_buffs) do
                    if targets[tt_key] then
                        targets[tt_key] = nil
                    end
                end
            end
        end
        
        -- Attack Range settings (global setting for all jobs)
        do
            local attack_range_options = { 'Off', 'Melee (3 yalms)', 'Ranged (15 yalms)' }
            local attack_range_current = settings.attack_range or 'Off'
            local attack_range_index = { 0 }
            
            -- Find current index
            for i, option in ipairs(attack_range_options) do
                if option == attack_range_current then
                    attack_range_index[1] = i - 1
                    break
                end
            end
            
            ui.combo(ctx, 'Attack Range', 'attack_range', attack_range_index, attack_range_options, function(i)
                return attack_range_options[i + 1]
            end)
            ui.item_tooltip(tooltips.attack_range)
        end

        -- Show job-specific sections if we have a job definition
        if job_def then
        
        -- Focus target settings (only show if job has party healing or debuff removal abilities)
        local has_party_healing = false
        local has_party_debuff_removal = false
        
        -- Check for non-self-only healing abilities
        if job_def and job_def.abilities.heal then
            for _, ability in ipairs(job_def.abilities.heal) do
                if not ability.self_only then
                    has_party_healing = true
                    break
                end
            end
        end
        
        -- Check for non-self-only debuff removal abilities
        if job_def and job_def.abilities.debuff_removal then
            for _, ability in ipairs(job_def.abilities.debuff_removal) do
                if not ability.self_only then
                    has_party_debuff_removal = true
                    break
                end
            end
        end
        
        -- Focus Healing settings
        if job_def and job_def.abilities.heal and has_usable_abilities(job_def.abilities.heal) then
            local has_non_self_heal = false
            for _, ability in ipairs(job_def.abilities.heal) do
                if not ability.self_only then
                    has_non_self_heal = true
                    break
                end
            end
            
            if has_non_self_heal then
                local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Focus Healing', 'focus_enabled', false)
                ui.item_tooltip(tooltips.focus_healing)
                if is_open and is_enabled then
                    imgui.Indent(ui.ABILITY_LIST_INDENT)
                    -- Focus Target dropdown
                    focus_target_name = render_party_dropdown('Focus Target', 'focus_target', true, party_member_names, settings, callback, true)
                    
                    ui.slider_int(ctx, 'Focus (HP%)', 'focus_threshold', { settings.focus_threshold or 85 }, 1, 100)
                    imgui.Unindent(ui.ABILITY_LIST_INDENT)
                end
            end
        end
        
        -- Group Healing settings
        if job_def and job_def.abilities.heal and has_usable_abilities(job_def.abilities.heal) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Group Healing', 'heal_enabled', false)
            ui.item_tooltip(tooltips.group_healing)
            if is_open and is_enabled then
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                ui.slider_int(ctx, 'Group (HP%)', 'heal_threshold', { settings.heal_threshold or 75 }, 1, 100)
                ui.render_heal_group_selection(ctx, 'heal_group', true)
                imgui.SameLine()
                imgui.Text('Group Targets')
                for _, ability in ipairs(job_def.abilities.heal) do
                    if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'heal', true)
                    end
                end
                
                -- Critical HP section (inside Group Healing)
                if job_def.abilities.critical and has_usable_abilities(job_def.abilities.critical) then
                    ui.slider_int(ctx, 'Critical (HP%)', 'critical_threshold', { settings.critical_threshold or 30 }, 1, 50)
                    ui.item_tooltip(tooltips.critical_hp)
                    for _, ability in ipairs(job_def.abilities.critical) do
                        if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                            ui.ability_checkbox(ctx, ability, job_def, 'critical')
                        end
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end
        
        -- AOE Healing settings
        if job_def and job_def.abilities.heal_aoe and has_usable_abilities(job_def.abilities.heal_aoe) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable AOE Healing', 'heal_aoe_enabled', false)
            ui.item_tooltip(tooltips.aoe_healing)
            if is_open and is_enabled then
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                ui.slider_int(ctx, 'AOE (HP%)', 'heal_aoe_threshold', { settings.heal_aoe_threshold or 70 }, 1, 100)
                ui.render_heal_group_selection(ctx, 'heal_aoe_group', false)
                imgui.SameLine()
                imgui.Text('AOE Targets')

                for _, ability in ipairs(job_def.abilities.heal_aoe) do
                    if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'heal_aoe', true)
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end
        
        -- Pet Healing settings
        if job_def and job_def.abilities.heal_pet and has_usable_abilities(job_def.abilities.heal_pet) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Pet Healing', 'heal_pet_enabled', false)
            ui.item_tooltip(tooltips.pet_healing)
            if is_open and is_enabled then
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                ui.slider_int(ctx, 'Pet (HP%)', 'heal_pet_threshold', { settings.heal_pet_threshold or 50 }, 1, 100)
                
                for _, ability in ipairs(job_def.abilities.heal_pet) do
                    if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'heal_pet')
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end
        
        -- Wake settings (only show if job has wake-capable heal abilities that are usable)
        local has_wake_abilities = false
        if job_def and job_def.abilities.heal then
            for _, ability in ipairs(job_def.abilities.heal) do
                if ability.wakes and can_use_ability(ability) then
                    has_wake_abilities = true
                    break
                end
            end
        end
        
        -- Debuff removal settings
        if job_def and job_def.abilities.debuff_removal and has_usable_abilities(job_def.abilities.debuff_removal) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Debuff Removal', 'debuff_removal_enabled', false)
            ui.item_tooltip(tooltips.debuff_removal)
            if is_open and is_enabled then
                -- Clear temporary group rendering flags
                if current_settings then
                    for key in pairs(current_settings) do
                        if key:match('^rendered_group_') then
                            current_settings[key] = nil
                        end
                    end
                end
                
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                ctx.show_trust_warning = true
                for _, ability in ipairs(job_def.abilities.debuff_removal) do
                    if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                        ui.render_ability(ctx, ability, job_def, 'debuff_removal')
                    end
                end
                ctx.show_trust_warning = false
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end
        
        if has_wake_abilities then
            local is_open_wake, is_enabled_wake = ui.collapsing_checkbox_header(ctx, 'Enable Sleep Removal', 'wake_enabled', false)
            ui.item_tooltip(tooltips.sleep_removal)
            if is_open_wake and is_enabled_wake then
                -- Check if any wake-capable abilities support target_outside
                local has_outside_wake = false
                if job_def.abilities.heal then
                    for _, ability in ipairs(job_def.abilities.heal) do
                        if ability.wakes and ability.target_outside then
                            has_outside_wake = true
                            break
                        end
                    end
                end
                
                -- Party selection buttons (who gets sleep removal)
                -- exclude ME since player cannot wake themselves from sleep
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                ui.render_party_selection(ctx, 'wake', has_outside_wake, false)
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end

        -- Item checkboxes for Silence and Doom removal
        ui.item_silence_removal_checkbox(ctx, tooltips.item_silence_removal)
        ui.item_doom_removal_checkbox(ctx, tooltips.item_doom_removal)

        -- Rest settings (only for MP-based jobs)
        if job_def and job_def.resource_type == 'mp' then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Resting', 'rest_enabled', false)
            ui.item_tooltip(tooltips.resting)
            if is_open and is_enabled then
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                ui.slider_int(ctx, 'Timer (seconds)', 'rest_timer', { settings.rest_timer or 5 }, 1, 20)
                ui.item_tooltip(tooltips.rest_timer)

                -- Follow Target dropdown
                follow_target_name = render_party_dropdown('Follow Target', 'follow_target', false, party_member_names, settings, callback, true)
                ui.item_tooltip(tooltips.rest_follow_target)

                ui.slider_int(ctx, 'Distance (yalms)##rest_distance', 'rest_distance', { settings.rest_distance or 7 }, 1, 15)
                ui.item_tooltip(tooltips.rest_distance)
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end
        
        -- Recovery settings
        local has_mp_recovery = job_def and job_def.abilities.recover_mp and has_usable_abilities(job_def.abilities.recover_mp)
        local has_tp_recovery = job_def and job_def.abilities.recover_tp and has_usable_abilities(job_def.abilities.recover_tp)
        local has_party_mp_recovery = job_def and job_def.abilities.recover_party_mp and has_usable_abilities(job_def.abilities.recover_party_mp)
        
        if has_mp_recovery or has_tp_recovery or has_party_mp_recovery then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Resource Recovery', 'recover_enabled', false)
            ui.item_tooltip(tooltips.resource_recovery)
            if is_open and is_enabled then
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                -- Self Recover (TP%) section
                if has_tp_recovery then
                    ui.slider_int(ctx, 'Self Recover (TP)', 'recover_tp_threshold', { settings.recover_tp_threshold or 500 }, 100, 3000)
                    for _, ability in ipairs(job_def.abilities.recover_tp) do
                        if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                            ui.ability_checkbox(ctx, ability, job_def, 'recover_tp')
                        end
                    end
                    
                    if has_mp_recovery or has_party_mp_recovery then
                        imgui.Spacing()
                    end
                end
                
                -- Self Recover (MP%) section
                if has_mp_recovery then
                    ui.slider_int(ctx, 'Self Recover (MP%)', 'recover_mp_threshold', { settings.recover_mp_threshold or 30 }, 1, 100)
                    local chivalry_visible = false
                    for _, ability in ipairs(job_def.abilities.recover_mp) do
                        if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                            ui.ability_checkbox(ctx, ability, job_def, 'recover_mp')
                            if ability.min_tp ~= nil then
                                chivalry_visible = true
                            end
                        end
                    end
                    if chivalry_visible then
                        ui.slider_int(ctx, 'Chivalry Min TP', 'chivalry_min_tp', { settings.chivalry_min_tp or 3000 }, 0, 3000)
                    end

                    if has_party_mp_recovery then
                        imgui.Spacing()
                    end
                end
                
                -- Party MP recovery section (for Devotion)
                if has_party_mp_recovery then
                    -- Recovery Target dropdown
                    focus_recovery_target_name = render_party_dropdown('Recovery Target', 'focus_recovery_target', false, party_member_names, settings, callback, true)
                    
                    if focus_recovery_target_name then
                        ui.slider_int(ctx, 'Target Recover (MP%)', 'focus_recovery_threshold', { settings.focus_recovery_threshold or 30 }, 1, 100)
                    end
                    
                    for _, ability in ipairs(job_def.abilities.recover_party_mp) do
                        if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                            ui.ability_checkbox(ctx, ability, job_def, 'recover_party_mp')
                        end
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end
        
        -- Buff settings
        if job_def and job_def.abilities.buff and has_usable_abilities(job_def.abilities.buff) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Buffs', 'buff_enabled', false)
            ui.item_tooltip(tooltips.buffs)
            if is_open and is_enabled then
                -- Clear temporary group rendering flags
                if current_settings then
                    for key in pairs(current_settings) do
                        if key:match('^rendered_group_') then
                            current_settings[key] = nil
                        end
                    end
                end
                
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.buff) do
                    if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                        ui.render_ability(ctx, ability, job_def, 'buff')
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end
        
        -- Geo settings (Geomancer)
        if job_def and job_def.abilities.geo and has_usable_abilities(job_def.abilities.geo) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Geo', 'geo_enabled', false)
            ui.item_tooltip(tooltips.geo)
            if is_open and is_enabled then
                imgui.Indent(ui.ABILITY_LIST_INDENT)

                -- Geo-bt debuff selector (<bt> enemy debuffs): self-grouped
                -- ON/OFF + dropdown. Cast/luopan lifecycle lives in geo.lua.
                if current_settings then
                    current_settings['rendered_group_Geo-bt'] = nil
                end
                for _, ability in ipairs(job_def.abilities.geo) do
                    if ability.group == 'Geo-bt' then
                        ui.render_ability(ctx, ability, job_def, 'geo')
                    end
                end

                -- Full Circle checkbox (ungrouped geo ability, excluding Entrust)
                for _, ability in ipairs(job_def.abilities.geo) do
                    if ability.group == nil and ability.name ~= 'Entrust' and can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'geo')
                        ui.item_tooltip(tooltips.geo_full_circle)
                    end
                end

                -- Distance threshold (Full Circle recast trigger)
                ui.slider_int(ctx, 'Distance (yalms)##geo_distance_threshold', 'geo_distance_threshold', { settings.geo_distance_threshold or 10 }, 7, 30)
                ui.item_tooltip(tooltips.geo_distance)
                
                -- Entrust settings (only for Geomancer)
                if job_def.job_id == 21 then
                    -- Build list of available Indi spells
                    local available_indi_spells = {}
                    if job_def.abilities.buff then
                        for _, ability in ipairs(job_def.abilities.buff) do
                            if ability.group == 'Indi' and can_use_ability(ability) and common.has_spell_learned(ability) then
                                table.insert(available_indi_spells, ability)
                            end
                        end
                    end
                    
                    -- Sort by level descending (highest first)
                    table.sort(available_indi_spells, function(a, b) return a.level > b.level end)
                    
                    if #available_indi_spells > 0 then
                        -- Entrust ability checkbox
                        for _, ability in ipairs(job_def.abilities.geo) do
                            if ability.name == 'Entrust' and can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                                ui.ability_checkbox(ctx, ability, job_def, 'geo')
                                ui.item_tooltip(tooltips.geo_entrust_enable)
                            end
                        end

                        -- Entrust Target dropdown
                        entrust_target_name = render_party_dropdown('Entrust Target', 'entrust_target', false, party_member_names, settings, callback)
                        ui.item_tooltip(tooltips.geo_entrust_target)

                        -- Validate saved spell name is in available spells
                        local current_spell_display = 'None'
                        if entrust_spell_name then
                            local found = false
                            for _, spell in ipairs(available_indi_spells) do
                                if spell.name == entrust_spell_name then
                                    current_spell_display = spell.name
                                    if spell.cost and spell.cost > 0 then
                                        current_spell_display = current_spell_display .. ' (' .. spell.cost .. ' MP)'
                                    end
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                -- Saved spell not available, reset
                                entrust_spell_name = nil
                                settings.entrust_spell = nil
                                if callback then callback() end
                            end
                        end
                        
                        -- Entrust Spell dropdown
                        imgui.PushItemWidth(250)
                        if imgui.BeginCombo('Entrust Spell', current_spell_display) then
                            -- Add None option
                            local is_none_selected = (entrust_spell_name == nil)
                            if imgui.Selectable('None', is_none_selected) then
                                entrust_spell_name = nil
                                settings.entrust_spell = nil
                                if callback then callback() end
                            end
                            if is_none_selected then
                                imgui.SetItemDefaultFocus()
                            end
                            
                            -- Add spell options
                            for _, spell in ipairs(available_indi_spells) do
                                local label = spell.name
                                if spell.cost and spell.cost > 0 then
                                    label = label .. ' (' .. spell.cost .. ' MP)'
                                end
                                local is_selected = (spell.name == entrust_spell_name)
                                if imgui.Selectable(label, is_selected) then
                                    entrust_spell_name = spell.name
                                    settings.entrust_spell = spell.name
                                    if callback then callback() end
                                end
                                if is_selected then
                                    imgui.SetItemDefaultFocus()
                                end
                            end
                            imgui.EndCombo()
                        end
                        imgui.PopItemWidth()
                        ui.item_tooltip(tooltips.geo_entrust_spell)
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end

        -- Revive settings
        if job_def and job_def.abilities.revive and has_usable_abilities(job_def.abilities.revive) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Revive', 'revive_enabled', false)
            ui.item_tooltip(tooltips.revive)
            if is_open and is_enabled then
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.revive) do
                    if can_use_ability(ability) and not is_subjob_duplicate(job_def, ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'revive', true)
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
        end
        end  -- End of job_def check

        if common.debug then
            imgui.Indent(ui.ABILITY_LIST_INDENT)
            local zone_id = common.get_zone_id()
            imgui.Text(string.format('get_zone_id = %d', zone_id))
            local target_id = common.get_target_id()
            imgui.Text(string.format('get_target_id = %s', tostring(target_id)))
            local is_moving = common.is_player_moving()
            imgui.Text(string.format('is_player_moving = %s', tostring(is_moving)))
            local is_casting = common.is_casting()
            imgui.Text(string.format('is_casting = %s', tostring(is_casting)))
            local party_server_ids = common.get_party_server_ids()
            if #party_server_ids > 0 then
                local ids_str = table.concat(party_server_ids, ', ')
                imgui.Text(string.format('get_party_server_ids = [%s]', ids_str))
            else
                imgui.Text('get_party_server_ids = []')
            end
            
            -- Show target index of currently targeted party member
            local party = common.get_party()
            if party and target_id and target_id > 0 then
                -- Find which party member matches the target server ID
                for i = 0, 5 do
                    if party:GetMemberIsActive(i) == 1 then
                        local member_server_id = party:GetMemberServerId(i)
                        if member_server_id == target_id then
                            local member_target_index = party:GetMemberTargetIndex(i)
                            imgui.Text(string.format('Target P%d GetMemberTargetIndex = %s', i, tostring(member_target_index)))
                            break
                        end
                    end
                end
            end
            
            imgui.Spacing()
            imgui.Text('get_player_buffs:')
            local player_buffs = common.get_player_buffs()
            if #player_buffs > 0 then
                local buff_str = table.concat(player_buffs, ', ')
                imgui.Text(string.format('  %s', buff_str))
            else
                imgui.Text('  None')
            end
            
            local party_size = common.get_party_size()
            if party_size > 1 then
                for i = 1, 5 do
                    if i < party_size then
                        imgui.Spacing()
                        local member_name = common.get_party_member_name(i) or ('P' .. i)
                        imgui.Text(string.format('get_party_buffs: %s', member_name))
                        local member_buffs = common.get_party_buffs(i)
                        if #member_buffs > 0 then
                            local buff_str = table.concat(member_buffs, ', ')
                            imgui.Text(string.format('  %s', buff_str))
                        else
                            imgui.Text('  None')
                        end
                    end
                end
            end

            -- Alliance sub-parties
            local gs = common.game_state
            if gs and gs.alliance and common.get_alliance_count() > 0 then
                imgui.Spacing()
                imgui.Text('Alliance Members:')
                local party_prefixes = { [2] = 'B', [3] = 'C' }
                local party_colors   = { [2] = { 1.0, 0.85, 0.4, 1.0 }, [3] = { 0.6, 0.9, 1.0, 1.0 } }
                for pi = 2, 3 do
                    local sub_party = gs.alliance[pi]
                    if sub_party and next(sub_party) ~= nil then
                        local prefix     = party_prefixes[pi]
                        local col        = party_colors[pi]
                        local leader_sid = (gs.alliance_leaders and gs.alliance_leaders[pi]) or 0
                        imgui.Spacing()
                        imgui.TextColored(col, string.format('Party %s:', prefix))
                        -- Sort by local slot
                        local sorted = common.sorted_alliance_members(sub_party)
                        for _, entry in ipairs(sorted) do
                            local local_idx = entry.local_idx
                            local m         = entry.m
                            local leader_str = (leader_sid ~= 0 and m.server_id == leader_sid) and '^' or ' '
                            imgui.Text(string.format('  %s%s%d: %-16s  %s%d/%s%d  HP:%3d%%  MP:%3d%%  TP:%d',
                                leader_str, prefix, local_idx,
                                m.name or '?',
                                m.job_name     or '??', m.main_level or 0,
                                m.sub_job_name or '??', m.sub_level  or 0,
                                m.hpp or 0, m.mpp or 0, m.tp or 0))
                            local buff_count = m.buffs and #m.buffs or 0
                            if buff_count > 0 then
                                local buff_str = table.concat(m.buffs, ', ')
                                imgui.Text(string.format('     Buffs[%d]: %s', buff_count, buff_str))
                            end
                        end
                    end
                end
            end

            imgui.Unindent(ui.ABILITY_LIST_INDENT)
        end

    end
    imgui.End()

    -- Close only when the [X] was clicked (imgui sets is_open to false). A mere
    -- collapse leaves is_open true, so the window stays open.
    if not is_open[1] then
        ui_visible = false
    end
end

return ui_config
