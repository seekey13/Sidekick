--[[
    Generic configuration UI for Medic
    Dynamically generates UI based on loaded job definition
]]--

local config_ui = {}

local imgui = require('imgui')
local common = require('lib.core.common')
local resource = require('lib.core.resource')
local ui = require('lib.ui_components')

-- UI state
local is_open = { true }
local ui_visible = false

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
-- Helper Functions (Remaining in config_ui)
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
    
    local main_level, sub_level = common.get_player_level()
    
    -- Check if this ability is for main job or subjob
    -- Abilities marked with is_main_job = false are from subjob
    if ability.is_main_job == false then
        return sub_level >= ability.level
    else
        return main_level >= ability.level
    end
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
        if can_use_ability(ability) then
            -- Check if spell is learned (for magic spells)
            local cmd = type(ability.command) == 'function' and ability.command(0) or ability.command
            local is_spell = cmd and string.sub(cmd, 1, 3) == '/ma'
            local has_spell = true
            
            if is_spell and ability.id then
                local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
                if ok then
                    has_spell = known
                end
            end
            
            if has_spell then
                table.insert(usable, ability)
            end
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

-- Sync UI state from settings
local function sync_from_settings()
    if not current_settings then return end
    
    focus_enabled[1] = current_settings.focus_enabled or false
    
    -- Focus target settings are now loaded on first render
end

-- ============================================================================
-- Module Functions
-- ============================================================================

function config_ui.initialize()
    -- Initialize ImGui if needed
end

function config_ui.show()
    ui_visible = true
    is_open[1] = true
end

function config_ui.hide()
    ui_visible = false
    is_open[1] = false
end

function config_ui.toggle()
    if ui_visible then
        config_ui.hide()
    else
        config_ui.show()
    end
end

function config_ui.is_visible()
    return ui_visible
end

function config_ui.get_party_buffs()
    return party_buffs
end

function config_ui.get_entrust_config()
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

function config_ui.render(settings, job_def, callback, roll_mod)
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
        get_usable_abilities_in_group = get_usable_abilities_in_group
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
    
    -- Calculate fixed window width based on party size
    local party_size = common.get_party_size()
    local num_buttons = math.min(party_size, 6)
    local button_width = ui.PARTY_BUTTON_WIDTH * num_buttons + (ui.SPACE_BETWEEN_BUTTONS * (num_buttons - 1))
    local dropdown_width = ui.DROPDOWN_WIDTH
    local window_width = math.max((button_width + dropdown_width + ui.ABILITY_LIST_INDENT + 50), 1)
    
    imgui.SetNextWindowSize({window_width, 0}, ImGuiCond_Always)
    
    -- Build window title with job name if available
    local window_title = 'Medic Configuration'
    if job_def and job_def.job_name then
        window_title = window_title .. ' - ' .. job_def.job_name
    end
    
    if imgui.Begin(window_title, is_open, ImGuiWindowFlags_NoCollapse + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_AlwaysAutoResize) then
        
        -- Automation toggle button
        local can_attack = common.can_attack()
        local is_resting = common.is_resting()
        local button_text
        local status_text
        local status_color
        
        if settings.automation_enabled then
            if is_resting then
                -- Resting state (automation enabled but resting for MP)
                button_text = 'Resting'
                status_text = 'Automation resting.'
                status_color = ui.LIGHT_BLUE
            elseif can_attack then
                -- Running state
                button_text = 'Stop'
                status_text = 'Automation running.'
                status_color = ui.LIGHT_GREEN
            else
                -- Paused state (automation enabled but combat blocked)
                button_text = 'Paused'
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
        
        imgui.Separator()
        
        -- Attack Range settings (global setting for all jobs)
        local attack_range_options = { 'Off', 'Melee', 'Ranged' }
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
        
        imgui.Separator()

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
                if is_open and is_enabled then
                    -- Build dynamic focus target options (None + all party including player)
                    local focus_target_options = { 'None' }
                    -- Add player (P0)
                    local player_name = common.get_party_member_name(0)
                    if player_name and player_name ~= '' then
                        table.insert(focus_target_options, player_name)
                    end
                    -- Add party members (P1-P5)
                    for _, name in ipairs(party_member_names) do
                        table.insert(focus_target_options, name)
                    end
                    
                    -- Validate saved focus target name is in current party
                    local current_focus_display = 'None'
                    if focus_target_name then
                        local found = false
                        for _, name in ipairs(focus_target_options) do
                            if name == focus_target_name then
                                current_focus_display = focus_target_name
                                found = true
                                break
                            end
                        end
                        if not found then
                            -- Saved target not in party, reset
                            focus_target_name = nil
                            settings.focus_target = nil
                            if callback then callback() end
                        end
                    end
                    
                    -- Focus Target dropdown
                    imgui.PushItemWidth(250)
                    if imgui.BeginCombo('Focus Target', current_focus_display) then
                        for _, option in ipairs(focus_target_options) do
                            local is_selected = (option == current_focus_display)
                            if imgui.Selectable(option, is_selected) then
                                if option == 'None' then
                                    focus_target_name = nil
                                    settings.focus_target = nil
                                else
                                    focus_target_name = option
                                    settings.focus_target = option
                                end
                                if callback then callback() end
                            end
                            if is_selected then
                                imgui.SetItemDefaultFocus()
                            end
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()
                    
                    ui.slider_int(ctx, 'Focus Healing (HP%)', 'focus_threshold', { settings.focus_threshold or 85 }, 1, 100)
                end
                
                imgui.Separator()
            end
        end
        
        -- Party Healing settings
        if job_def and job_def.abilities.heal and has_usable_abilities(job_def.abilities.heal) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Party Healing', 'heal_enabled', false)
            if is_open and is_enabled then
                ui.slider_int(ctx, 'Party (HP%)', 'heal_threshold', { settings.heal_threshold or 75 }, 1, 100)
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.heal) do
                    if can_use_ability(ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'heal')
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
                
                -- Critical HP section (inside Party Healing)
                if job_def.abilities.critical and has_usable_abilities(job_def.abilities.critical) then
                    ui.slider_int(ctx, 'Critical (HP%)', 'critical_threshold', { settings.critical_threshold or 30 }, 1, 50)
                    imgui.Indent(ui.ABILITY_LIST_INDENT)
                    for _, ability in ipairs(job_def.abilities.critical) do
                        if can_use_ability(ability) then
                            ui.ability_checkbox(ctx, ability, job_def, 'critical')
                        end
                    end
                    imgui.Unindent(ui.ABILITY_LIST_INDENT)
                end
            end
            
            imgui.Separator()
        end
        
        -- AOE Healing settings
        if job_def and job_def.abilities.heal_aoe and has_usable_abilities(job_def.abilities.heal_aoe) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable AOE Healing', 'heal_aoe_enabled', false)
            if is_open and is_enabled then
                ui.slider_int(ctx, 'AOE (HP%)', 'heal_aoe_threshold', { settings.heal_aoe_threshold or 70 }, 1, 100)
                
                ui.slider_int(ctx, 'Min Members', 'heal_aoe_count_threshold', { settings.heal_aoe_count_threshold or 2 }, 1, 6)
                
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.heal_aoe) do
                    if can_use_ability(ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'heal_aoe')
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end
        
        -- Pet Healing settings
        if job_def and job_def.abilities.heal_pet and has_usable_abilities(job_def.abilities.heal_pet) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Pet Healing', 'heal_pet_enabled', false)
            if is_open and is_enabled then
                ui.slider_int(ctx, 'Pet (HP%)', 'heal_pet_threshold', { settings.heal_pet_threshold or 50 }, 1, 100)
                
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.heal_pet) do
                    if can_use_ability(ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'heal_pet')
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
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
        
        if has_wake_abilities then
            ui.checkbox(ctx, 'Enable Sleep Removal', 'wake_enabled', { settings.wake_enabled or false })
            
            imgui.Separator()
        end
        
        -- Debuff removal settings
        if job_def and job_def.abilities.debuff_removal and has_usable_abilities(job_def.abilities.debuff_removal) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Debuff Removal', 'debuff_removal_enabled', false)
            if is_open and is_enabled then
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.debuff_removal) do
                    if can_use_ability(ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'debuff_removal')
                    end
                end
                
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end

        -- Item checkboxes for Silence and Doom removal (always shown)
        ui.item_silence_removal_checkbox(ctx)
        ui.item_doom_removal_checkbox(ctx)

        imgui.Separator()
        
        -- Rest settings (only for MP-based jobs)
        if job_def and job_def.resource_type == 'mp' then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Resting', 'rest_enabled', false)
            if is_open and is_enabled then
                ui.slider_int(ctx, 'Timer (seconds)', 'rest_timer', { settings.rest_timer or 5 }, 1, 20)
                ui.slider_int(ctx, 'Threshold (HP%)', 'rest_threshold', { settings.rest_threshold or 70 }, 1, 99)
                
                -- Build dynamic follow target options (None + party members P1-P5, exclude player)
                local follow_target_options = { 'None' }
                for _, name in ipairs(party_member_names) do
                    table.insert(follow_target_options, name)
                end
                
                -- Validate saved follow target name is in current party
                local current_follow_display = 'None'
                if follow_target_name then
                    local found = false
                    for _, name in ipairs(follow_target_options) do
                        if name == follow_target_name then
                            current_follow_display = follow_target_name
                            found = true
                            break
                        end
                    end
                    if not found then
                        -- Saved target not in party, reset
                        follow_target_name = nil
                        settings.follow_target = nil
                        if callback then callback() end
                    end
                end
                
                -- Follow Target dropdown
                imgui.PushItemWidth(250)
                if imgui.BeginCombo('Follow Target', current_follow_display) then
                    for _, option in ipairs(follow_target_options) do
                        local is_selected = (option == current_follow_display)
                        if imgui.Selectable(option, is_selected) then
                            if option == 'None' then
                                follow_target_name = nil
                                settings.follow_target = nil
                            else
                                follow_target_name = option
                                settings.follow_target = option
                            end
                            if callback then callback() end
                        end
                        if is_selected then
                            imgui.SetItemDefaultFocus()
                        end
                    end
                    imgui.EndCombo()
                end
                imgui.PopItemWidth()
                
                ui.slider_int(ctx, 'Distance (yalms)', 'rest_distance', { settings.rest_distance or 7 }, 1, 15)
            end
            
            imgui.Separator()
        end
        
        -- Recovery settings
        local has_mp_recovery = job_def and job_def.abilities.recover_mp and has_usable_abilities(job_def.abilities.recover_mp)
        local has_tp_recovery = job_def and job_def.abilities.recover_tp and has_usable_abilities(job_def.abilities.recover_tp)
        local has_party_mp_recovery = job_def and job_def.abilities.recover_party_mp and has_usable_abilities(job_def.abilities.recover_party_mp)
        
        if has_mp_recovery or has_tp_recovery or has_party_mp_recovery then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Resource Recovery', 'recover_enabled', false)
            if is_open and is_enabled then
                -- Self Recover (TP%) section
                if has_tp_recovery then
                    ui.slider_int(ctx, 'Self Recover (TP)', 'recover_tp_threshold', { settings.recover_tp_threshold or 500 }, 100, 3000)
                    imgui.Indent(ui.ABILITY_LIST_INDENT)
                    for _, ability in ipairs(job_def.abilities.recover_tp) do
                        if can_use_ability(ability) then
                            ui.ability_checkbox(ctx, ability, job_def, 'recover_tp')
                        end
                    end
                    imgui.Unindent(ui.ABILITY_LIST_INDENT)
                    
                    if has_mp_recovery or has_party_mp_recovery then
                        imgui.Spacing()
                    end
                end
                
                -- Self Recover (MP%) section
                if has_mp_recovery then
                    ui.slider_int(ctx, 'Self Recover (MP%)', 'recover_mp_threshold', { settings.recover_mp_threshold or 30 }, 1, 100)
                    imgui.Indent(ui.ABILITY_LIST_INDENT)
                    for _, ability in ipairs(job_def.abilities.recover_mp) do
                        if can_use_ability(ability) then
                            ui.ability_checkbox(ctx, ability, job_def, 'recover_mp')
                        end
                    end
                    imgui.Unindent(ui.ABILITY_LIST_INDENT)
                    
                    if has_party_mp_recovery then
                        imgui.Spacing()
                    end
                end
                
                -- Party MP recovery section (for Devotion)
                if has_party_mp_recovery then
                    -- Build dynamic recovery target options (None + party members P1-P5, exclude player)
                    local recovery_target_options = { 'None' }
                    for _, name in ipairs(party_member_names) do
                        table.insert(recovery_target_options, name)
                    end
                    
                    -- Validate saved recovery target name is in current party
                    local current_recovery_display = 'None'
                    if focus_recovery_target_name then
                        local found = false
                        for _, name in ipairs(recovery_target_options) do
                            if name == focus_recovery_target_name then
                                current_recovery_display = focus_recovery_target_name
                                found = true
                                break
                            end
                        end
                        if not found then
                            -- Saved target not in party, reset
                            focus_recovery_target_name = nil
                            settings.focus_recovery_target = nil
                            if callback then callback() end
                        end
                    end
                    
                    -- Recovery Target dropdown
                    imgui.PushItemWidth(250)
                    if imgui.BeginCombo('Recovery Target', current_recovery_display) then
                        for _, option in ipairs(recovery_target_options) do
                            local is_selected = (option == current_recovery_display)
                            if imgui.Selectable(option, is_selected) then
                                if option == 'None' then
                                    focus_recovery_target_name = nil
                                    settings.focus_recovery_target = nil
                                else
                                    focus_recovery_target_name = option
                                    settings.focus_recovery_target = option
                                end
                                if callback then callback() end
                            end
                            if is_selected then
                                imgui.SetItemDefaultFocus()
                            end
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()
                    
                    if focus_recovery_target_name then
                        ui.slider_int(ctx, 'Target Recover (MP%)', 'focus_recovery_threshold', { settings.focus_recovery_threshold or 30 }, 1, 100)
                    end
                    
                    imgui.Indent(ui.ABILITY_LIST_INDENT)
                    for _, ability in ipairs(job_def.abilities.recover_party_mp) do
                        if can_use_ability(ability) then
                            ui.ability_checkbox(ctx, ability, job_def, 'recover_party_mp')
                        end
                    end
                    imgui.Unindent(ui.ABILITY_LIST_INDENT)
                end
            end
            
            imgui.Separator()
        end
        
        -- Buff settings
        if job_def and job_def.abilities.buff and has_usable_abilities(job_def.abilities.buff) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Buffs', 'buff_enabled', false)
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
                    if can_use_ability(ability) then
                        ui.render_ability(ctx, ability, job_def, 'buff')
                    end
                end
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end
        
        -- Geo settings (Geomancer)
        if job_def and job_def.abilities.geo and has_usable_abilities(job_def.abilities.geo) then
            local is_open, is_enabled = ui.collapsing_checkbox_header(ctx, 'Enable Geo', 'geo_enabled', false)
            if is_open and is_enabled then
                ui.slider_int(ctx, 'Distance (yalms)', 'geo_distance_threshold', { settings.geo_distance_threshold or 10 }, 7, 30)
                imgui.Indent(ui.ABILITY_LIST_INDENT)
                
                -- Full Circle checkbox
                for _, ability in ipairs(job_def.abilities.geo) do
                    if ability.name ~= 'Entrust' and can_use_ability(ability) then
                        ui.ability_checkbox(ctx, ability, job_def, 'geo')
                    end
                end
                
                imgui.Unindent(ui.ABILITY_LIST_INDENT)
                
                -- Entrust settings (only for Geomancer)
                if job_def.job_id == 21 then
                    -- Build list of available Indi spells
                    local available_indi_spells = {}
                    if job_def.abilities.buff then
                        for _, ability in ipairs(job_def.abilities.buff) do
                            if ability.group == 'Indi' and can_use_ability(ability) then
                                -- Check if spell is learned
                                local cmd = type(ability.command) == 'function' and ability.command(0) or ability.command
                                local is_spell = cmd and string.sub(cmd, 1, 3) == '/ma'
                                local has_spell = true
                                
                                if is_spell and ability.id then
                                    local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
                                    if ok then
                                        has_spell = known
                                    end
                                end
                                
                                if has_spell then
                                    table.insert(available_indi_spells, ability)
                                end
                            end
                        end
                    end
                    
                    -- Sort by level descending (highest first)
                    table.sort(available_indi_spells, function(a, b) return a.level > b.level end)
                    
                    if #available_indi_spells > 0 then
                        -- Build dynamic party target options (None + party member names for P1-P5)
                        local party_target_options = { 'None' }
                        for _, name in ipairs(party_member_names) do
                            table.insert(party_target_options, name)
                        end
                        
                        -- Validate saved target name is in current party
                        local current_target_display = 'None'
                        if entrust_target_name then
                            local found = false
                            for _, name in ipairs(party_target_options) do
                                if name == entrust_target_name then
                                    current_target_display = entrust_target_name
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                -- Saved target not in party, reset
                                entrust_target_name = nil
                                settings.entrust_target = nil
                                if callback then callback() end
                            end
                        end
                        
                        -- Entrust Target dropdown
                        imgui.PushItemWidth(250)
                        if imgui.BeginCombo('Entrust Target', current_target_display) then
                            for _, option in ipairs(party_target_options) do
                                local is_selected = (option == current_target_display)
                                if imgui.Selectable(option, is_selected) then
                                    if option == 'None' then
                                        entrust_target_name = nil
                                        settings.entrust_target = nil
                                    else
                                        entrust_target_name = option
                                        settings.entrust_target = option
                                    end
                                    if callback then callback() end
                                end
                                if is_selected then
                                    imgui.SetItemDefaultFocus()
                                end
                            end
                            imgui.EndCombo()
                        end
                        imgui.PopItemWidth()
                        
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
                        
                        -- Entrust ability checkbox (indented)
                        imgui.Indent(ui.ABILITY_LIST_INDENT)
                        for _, ability in ipairs(job_def.abilities.geo) do
                            if ability.name == 'Entrust' and can_use_ability(ability) then
                                ui.ability_checkbox(ctx, ability, job_def, 'geo')
                            end
                        end
                        imgui.Unindent(ui.ABILITY_LIST_INDENT)
                    end
                end
            end
            
            imgui.Separator()
        end
        
        -- Debug mode (at end)
        local debug_var = { common.debug }
        if imgui.Checkbox('Debug Mode', debug_var) then
            common.debug = debug_var[1]
        end
        
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
            
            imgui.Unindent(ui.ABILITY_LIST_INDENT)
        end

        imgui.End()
    else
        -- Window was closed via X button, sync state
        ui_visible = false
        is_open[1] = false
    end
    
    -- Also check if is_open was changed by imgui (user clicked X)
    if not is_open[1] then
        ui_visible = false
    end
end

return config_ui
