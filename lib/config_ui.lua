--[[
    Generic configuration UI for Medic
    Dynamically generates UI based on loaded job definition
]]--

local config_ui = {}

local imgui = require('imgui')
local common = require('lib.core.common')

-- UI state
local is_open = { true }
local ui_visible = false

-- Settings reference and callback
local current_settings = nil
local save_callback = nil
local roll_module = nil

-- UI State Variables (for imgui)
local focus_enabled = { false }
local focus_target_index = { 0 }  -- 0 = None, 1-6 = <ME>-P5

-- Party buff tracking (session only, not saved to settings)
-- Structure: party_buffs[ability_name][party_index] = true/false
-- party_index: 1-5 for P1-P5 (player is always handled separately)
local party_buffs = {}

-- UI Constants
local ABILITY_LIST_INDENT = 20  -- Indent for ability checkboxes within sections
local PARTY_BUTTON_WIDTH = 45  -- Width of party toggle buttons

-- Dropdown options
local focus_target_options = { 'None', 'P0', 'P1', 'P2', 'P3', 'P4', 'P5' }

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Check if player can use an ability based on level
local function can_use_ability(ability)
    if not ability or not ability.level then
        return true
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

-- Get the highest level usable ability in a group
local function get_highest_level_ability_in_group(job_def, target_group)
    local usable = get_usable_abilities_in_group(job_def, target_group)
    if #usable == 0 then
        return nil
    end
    
    -- Sort by level descending
    table.sort(usable, function(a, b) return a.level > b.level end)
    return usable[1]
end

-- Get selected ability for a group (from settings, or auto-select highest)
local function get_selected_ability_for_group(job_def, target_group)
    if not current_settings or not job_def or not target_group then
        return nil
    end
    
    local setting_key = 'selected_' .. target_group
    local saved_name = current_settings[setting_key]
    
    -- Get all usable abilities in this group
    local usable = get_usable_abilities_in_group(job_def, target_group)
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
    
    -- If saved ability not found or not set, auto-select highest level
    local highest = get_highest_level_ability_in_group(job_def, target_group)
    if highest then
        current_settings[setting_key] = highest.name
        if save_callback then
            save_callback()
        end
    end
    
    return highest
end

-- Get the group of an ability by name
local function get_ability_group(job_def, ability_name)
    if not job_def or not job_def.abilities then
        return nil
    end
    
    -- Search through all ability categories
    for category, abilities in pairs(job_def.abilities) do
        for _, ability in ipairs(abilities) do
            if ability.name == ability_name and ability.group then
                return ability.group
            end
        end
    end
    
    return nil
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
    
    -- Convert focus_target_index (nil, 0-5) to combo index (0-6)
    if current_settings.focus_target_index == nil then
        focus_target_index[1] = 0
    else
        focus_target_index[1] = current_settings.focus_target_index + 1
    end
end

-- Check if an ability is enabled
local function is_ability_enabled(ability_name)
    if not current_settings then
        return false  -- Default to disabled if no settings
    end
    -- Check flattened key: disabled_AbilityName
    local key = 'disabled_' .. ability_name:gsub(' ', '_')
    
    -- If this key has never been set, it's a newly discovered ability
    -- Default to disabled on first display
    if current_settings[key] == nil then
        -- Initialize as disabled
        current_settings[key] = true
        return false
    end
    
    return not current_settings[key]
end

-- Toggle ability enabled state
local function toggle_ability(ability_name, enabled, job_def)
    -- Use flattened key: disabled_AbilityName
    local key = 'disabled_' .. ability_name:gsub(' ', '_')
    
    if enabled then
        current_settings[key] = false  -- Explicitly set to not disabled (enabled)
        
        -- If this ability has a group, disable all other abilities in the same group
        local ability_group = get_ability_group(job_def, ability_name)
        if ability_group and job_def then
            local group_abilities = get_abilities_in_group(job_def, ability_group)
            for _, other_ability in ipairs(group_abilities) do
                if other_ability.name ~= ability_name then
                    local other_key = 'disabled_' .. other_ability.name:gsub(' ', '_')
                    current_settings[other_key] = true
                end
            end
        end
    else
        current_settings[key] = true
    end
    
    if save_callback then
        save_callback()
    end
end

-- Check if a buff is enabled for a specific party member (session only)
local function is_party_buff_enabled(ability_name, party_index)
    if not party_buffs[ability_name] then
        return false
    end
    return party_buffs[ability_name][party_index] == true
end

-- Toggle buff enabled state for a specific party member (session only)
local function toggle_party_buff(ability_name, party_index, enabled)
    if not party_buffs[ability_name] then
        party_buffs[ability_name] = {}
    end
    party_buffs[ability_name][party_index] = enabled
    
    -- Check if ANY button (ME or P1-P5) is enabled for this ability
    local any_button_enabled = false
    for i = 0, 5 do
        if party_buffs[ability_name][i] == true then
            any_button_enabled = true
            break
        end
    end
    
    -- Update the ability's disabled setting based on button states
    local key = 'disabled_' .. ability_name:gsub(' ', '_')
    if any_button_enabled then
        -- At least one button is enabled, so enable the ability
        current_settings[key] = false
    else
        -- No buttons are enabled, so disable the ability
        current_settings[key] = true
    end
    
    if save_callback then
        save_callback()
    end
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

-- Check if ability can be cast on party members (has function command)
local function can_cast_on_party(ability)
    return type(ability.command) == 'function'
end

-- Calculate the width for the ON/OFF button based on party size
local function get_onoff_button_width()
    local party_size = common.get_party_size()
    -- Calculate width based on number of active members (ME + party members)
    -- ME is always active, plus P1-P(party_size-1) if in party
    local num_buttons = math.min(party_size, 6)
    return PARTY_BUTTON_WIDTH * num_buttons
end

-- Render an ON/OFF button for ability state
local function render_onoff_button(ability_name, job_def)
    local is_enabled = is_ability_enabled(ability_name)
    local button_width = get_onoff_button_width()
    
    -- Set button color based on state
    if is_enabled then
        -- ON state: Use default button colors
    else
        -- OFF state: Gray
        imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.5, 0.5, 0.5, 1.0 })
    end
    
    local button_text = is_enabled and 'ON' or 'OFF'
    local button_label = button_text .. '##onoff_' .. ability_name
    
    if imgui.Button(button_label, { button_width, 0 }) then
        toggle_ability(ability_name, not is_enabled, job_def)
    end
    
    if not is_enabled then
        imgui.PopStyleColor(3)
    end
end

-- Render a dropdown for selecting ability from a group
local function render_group_dropdown(job_def, target_group, dropdown_width)
    if not job_def or not target_group then
        return
    end
    
    local usable = get_usable_abilities_in_group(job_def, target_group)
    if #usable == 0 then
        return
    end
    
    -- Get currently selected ability
    local selected = get_selected_ability_for_group(job_def, target_group)
    local current_display = selected and (selected.name .. ' (' .. selected.cost .. ' MP)') or 'None'
    
    local setting_key = 'selected_' .. target_group
    local combo_label = '##dropdown_' .. target_group
    
    imgui.PushItemWidth(dropdown_width or 200)
    if imgui.BeginCombo(combo_label, current_display) then
        for _, ability in ipairs(usable) do
            local display_text = ability.name .. ' (' .. ability.cost .. ' MP)'
            local is_selected = (selected and selected.name == ability.name)
            
            if imgui.Selectable(display_text, is_selected) then
                current_settings[setting_key] = ability.name
                if save_callback then
                    save_callback()
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

-- Render a self-target single ability (not in a group)
-- Layout: [ON/OFF Button] Ability Name (Lv.XX) [Extra Tags]
local function render_self_single_ability(ability, job_def, extra_desc, id_suffix)
    -- Check if this ability is being displayed for the first time
    local key = 'disabled_' .. ability.name:gsub(' ', '_')
    if current_settings and current_settings[key] == nil then
        current_settings[key] = true
        if save_callback then
            save_callback()
        end
    end
    
    -- Check spell knowledge
    local cmd = type(ability.command) == 'function' and ability.command(0) or ability.command
    local is_spell = cmd and string.sub(cmd, 1, 3) == '/ma'
    local has_spell = true
    local spell_suffix = ''
    
    if is_spell and ability.id then
        local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
        if ok then
            has_spell = known
            if not has_spell then
                spell_suffix = ' (Not Learned)'
                current_settings[key] = true
            end
        end
    end
    
    -- Render ON/OFF button
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.5, 0.5, 1.0 })
    end
    
    render_onoff_button(ability.name, job_def)
    
    -- Display ability name and info
    imgui.SameLine()
    local desc = ability.name .. ' (Lv.' .. ability.level .. ')' .. (extra_desc or '') .. spell_suffix
    imgui.Text(desc)
    
    if not has_spell then
        imgui.PopStyleColor()
    end
end

-- Render a self-target grouped ability with dropdown
-- Layout: [ON/OFF Button] [Dropdown]
local function render_self_grouped_ability(ability, job_def, extra_desc)
    if not ability.group then
        return
    end
    
    -- Get usable abilities in this group
    local usable = get_usable_abilities_in_group(job_def, ability.group)
    if #usable == 0 then
        return
    end
    
    -- Get the selected ability for this group (for enable/disable state)
    local selected = get_selected_ability_for_group(job_def, ability.group)
    if not selected then
        return
    end
    
    -- Render ON/OFF button using the selected ability's name
    render_onoff_button(selected.name, job_def)
    
    -- Render dropdown
    imgui.SameLine()
    render_group_dropdown(job_def, ability.group, 200)
end

-- Render a party-target single ability (not in a group)
-- Layout: [<ME>] [<P1>] [<P2>]... Ability Name (Lv.XX) [Extra Tags]
local function render_party_single_ability(ability, job_def, extra_desc)
    -- Check spell knowledge
    local cmd = type(ability.command) == 'function' and ability.command(0) or ability.command
    local is_spell = cmd and string.sub(cmd, 1, 3) == '/ma'
    local has_spell = true
    local spell_suffix = ''
    
    if is_spell and ability.id then
        local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
        if ok then
            has_spell = known
            if not has_spell then
                spell_suffix = ' (Not Learned)'
            end
        end
    end
    
    local desc = ability.name .. ' (Lv.' .. ability.level .. ')' .. (extra_desc or '') .. spell_suffix
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.5, 0.5, 1.0 })
    end
    
    -- Render [<ME>] button
    local me_enabled = is_party_buff_enabled(ability.name, 0)
    
    if me_enabled then
        -- Selected: Use default button colors
    else
        -- Not selected: Gray
        imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.5, 0.5, 0.5, 1.0 })
    end
    
    local me_button_label = '<ME>##' .. ability.name .. '_me'
    if has_spell and imgui.Button(me_button_label, { PARTY_BUTTON_WIDTH, 0 }) then
        toggle_party_buff(ability.name, 0, not me_enabled)
    end
    
    if not me_enabled then
        imgui.PopStyleColor(3)
    end
    
    -- Render party member buttons (P1-P5)
    local party_size = common.get_party_size()
    if party_size > 1 then
        for party_index = 1, 5 do
            local is_active = party_index < party_size
            
            if is_active then
                imgui.SameLine()
                
                local is_trust_member = is_trust(party_index)
                local is_enabled = is_party_buff_enabled(ability.name, party_index)
                
                if is_trust_member then
                    imgui.PushStyleColor(ImGuiCol_Button, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_Text, { 0.4, 0.4, 0.4, 1.0 })
                elseif is_enabled then
                    -- Selected: Use default button colors
                else
                    imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.5, 0.5, 0.5, 1.0 })
                end
                
                local button_label = '<P' .. party_index .. '>##' .. ability.name .. '_p' .. party_index
                if has_spell and imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 }) then
                    if not is_trust_member then
                        toggle_party_buff(ability.name, party_index, not is_enabled)
                    end
                end
                
                if is_trust_member and imgui.IsItemHovered() then
                    imgui.SetTooltip('Trust buffs are not available')
                end
                
                if is_trust_member then
                    imgui.PopStyleColor(4)
                elseif not is_enabled then
                    imgui.PopStyleColor(3)
                end
            end
        end
    end
    
    -- Display spell name after buttons
    imgui.SameLine()
    imgui.Text(desc)
    
    if not has_spell then
        imgui.PopStyleColor()
    end
end

-- Render a party-target grouped ability with dropdown
-- Layout: [<ME>] [<P1>] [<P2>]... [Dropdown]
local function render_party_grouped_ability(ability, job_def, extra_desc)
    if not ability.group then
        return
    end
    
    -- Get usable abilities in this group
    local usable = get_usable_abilities_in_group(job_def, ability.group)
    if #usable == 0 then
        return
    end
    
    -- Get the selected ability for this group
    local selected = get_selected_ability_for_group(job_def, ability.group)
    if not selected then
        return
    end
    
    -- Check spell knowledge for selected ability
    local cmd = type(selected.command) == 'function' and selected.command(0) or selected.command
    local is_spell = cmd and string.sub(cmd, 1, 3) == '/ma'
    local has_spell = true
    
    if is_spell and selected.id then
        local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(selected.id) end)
        if ok then
            has_spell = known
        end
    end
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.5, 0.5, 1.0 })
    end
    
    -- Render [<ME>] button (using selected ability name)
    local me_enabled = is_party_buff_enabled(selected.name, 0)
    
    if me_enabled then
        -- Selected: Use default button colors
    else
        -- Not selected: Gray
        imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.5, 0.5, 0.5, 1.0 })
    end
    
    local me_button_label = '<ME>##' .. selected.name .. '_me'
    if has_spell and imgui.Button(me_button_label, { PARTY_BUTTON_WIDTH, 0 }) then
        toggle_party_buff(selected.name, 0, not me_enabled)
    end
    
    if not me_enabled then
        imgui.PopStyleColor(3)
    end
    
    -- Render party member buttons (P1-P5)
    local party_size = common.get_party_size()
    if party_size > 1 then
        for party_index = 1, 5 do
            local is_active = party_index < party_size
            
            if is_active then
                imgui.SameLine()
                
                local is_trust_member = is_trust(party_index)
                local is_enabled = is_party_buff_enabled(selected.name, party_index)
                
                if is_trust_member then
                    imgui.PushStyleColor(ImGuiCol_Button, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_Text, { 0.4, 0.4, 0.4, 1.0 })
                elseif is_enabled then
                    -- Selected: Use default button colors
                else
                    imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.5, 0.5, 0.5, 1.0 })
                end
                
                local button_label = '<P' .. party_index .. '>##' .. selected.name .. '_p' .. party_index
                if has_spell and imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 }) then
                    if not is_trust_member then
                        toggle_party_buff(selected.name, party_index, not is_enabled)
                    end
                end
                
                if is_trust_member and imgui.IsItemHovered() then
                    imgui.SetTooltip('Trust buffs are not available')
                end
                
                if is_trust_member then
                    imgui.PopStyleColor(4)
                elseif not is_enabled then
                    imgui.PopStyleColor(3)
                end
            end
        end
    end
    
    -- Display dropdown after buttons
    imgui.SameLine()
    render_group_dropdown(job_def, ability.group, 200)
    
    if not has_spell then
        imgui.PopStyleColor()
    end
end

-- Main ability renderer - determines which rendering function to use
local function render_ability(ability, job_def, extra_desc, id_suffix)
    if not ability or not can_use_ability(ability) then
        return false
    end
    
    local has_group = ability.group ~= nil
    local is_party_target = can_cast_on_party(ability)
    
    -- Determine if this is the first ability in the group to be rendered
    -- (to avoid rendering the same group multiple times)
    if has_group then
        -- Check if we've already rendered this group
        local group_key = 'rendered_group_' .. ability.group
        if current_settings and current_settings[group_key] then
            return false
        end
        
        -- Get usable abilities in group
        local usable = get_usable_abilities_in_group(job_def, ability.group)
        if #usable == 0 then
            return false
        end
        
        -- Only render if more than 1 usable ability in group
        if #usable == 1 then
            -- Treat as single ability
            has_group = false
        else
            -- Mark group as rendered (temporary flag for this frame)
            current_settings[group_key] = true
        end
    end
    
    -- Choose appropriate render function
    if has_group then
        if is_party_target then
            render_party_grouped_ability(ability, job_def, extra_desc)
        else
            render_self_grouped_ability(ability, job_def, extra_desc)
        end
    else
        if is_party_target then
            render_party_single_ability(ability, job_def, extra_desc)
        else
            render_self_single_ability(ability, job_def, extra_desc, id_suffix)
        end
    end
    
    return true
end

-- Create a checkbox UI element linked to a setting
local function create_checkbox(label, setting_name, ui_var)
    if imgui.Checkbox(label, ui_var) then
        current_settings[setting_name] = ui_var[1]
        if save_callback then save_callback() end
    end
end

-- Create an integer slider UI element linked to a setting
local function create_slider_int(label, setting_name, ui_var, min, max, width)
    width = width or 250  -- Default width of 250 pixels
    imgui.PushItemWidth(width)
    if imgui.SliderInt(label, ui_var, min, max) then
        current_settings[setting_name] = ui_var[1]
        if save_callback then save_callback() end
    end
    imgui.PopItemWidth()
end

-- Create a combo dropdown UI element linked to a setting
local function create_combo(label, setting_name, ui_var, options, converter, width)
    width = width or 250  -- Default width of 250 pixels
    imgui.PushItemWidth(width)
    local current_value = options[ui_var[1] + 1] or options[1] or ""
    if imgui.BeginCombo(label, current_value) then
        for i = 0, #options - 1 do
            local is_selected = (ui_var[1] == i)
            if imgui.Selectable(options[i + 1], is_selected) then
                ui_var[1] = i
                -- Convert and store the setting value
                if converter then
                    current_settings[setting_name] = converter(i)
                else
                    current_settings[setting_name] = i
                end
                if save_callback then save_callback() end
            end
            if is_selected then
                imgui.SetItemDefaultFocus()
            end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
end

-- Render a buff ability with button-based selection for single-target buffs
local function render_buff_with_buttons(ability, job_def, extra_desc)
    -- Get the command string (handle both string and function commands)
    local cmd = type(ability.command) == 'function' and ability.command(0) or ability.command
    local is_spell = cmd and string.sub(cmd, 1, 3) == '/ma'
    local has_spell = true
    local spell_suffix = ''
    
    if is_spell and ability.id then
        local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
        if ok then
            has_spell = known
            if not has_spell then
                spell_suffix = ' (Not Learned)'
            end
        else
            common.errorf('Failed to check spell knowledge for %s (ID: %d)', ability.name, ability.id)
        end
    end
    
    local desc = ability.name .. ' (Lv.' .. ability.level .. ')' .. (extra_desc or '') .. spell_suffix
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.5, 0.5, 1.0 })  -- Gray color for unknown spells
    end
    
    -- Render [<ME>] button
    local me_enabled = is_party_buff_enabled(ability.name, 0)
    
    -- Set button color based on selection state
    if me_enabled then
        -- Selected: Use default button colors (no custom styling)
    else
        -- Not selected: Gray
        imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.5, 0.5, 0.5, 1.0 })
    end
    
    local me_button_label = '<ME>##' .. ability.name .. '_me'
    if has_spell and imgui.Button(me_button_label, { PARTY_BUTTON_WIDTH, 0 }) then
        toggle_party_buff(ability.name, 0, not me_enabled)
    end
    
    if not me_enabled then
        imgui.PopStyleColor(3)
    end
    
    -- Render party member buttons (P1-P5)
    local party_size = common.get_party_size()
    if party_size > 1 then
        for party_index = 1, 5 do
            local is_active = party_index < party_size  -- P1-P(size-1) are active
            
            if is_active then
                imgui.SameLine()
                
                -- Check if this party member is a Trust
                local is_trust_member = is_trust(party_index)
                
                -- Get current state
                local is_enabled = is_party_buff_enabled(ability.name, party_index)
                
                -- Set button color and disable state based on Trust status
                if is_trust_member then
                    -- Trust: Dark gray and disabled
                    imgui.PushStyleColor(ImGuiCol_Button, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.2, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_Text, { 0.4, 0.4, 0.4, 1.0 })
                elseif is_enabled then
                    -- Selected: Use default button colors (no custom styling)
                else
                    -- Not selected: Gray
                    imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.5, 0.5, 0.5, 1.0 })
                end
                
                local button_label = '<P' .. party_index .. '>##' .. ability.name .. '_p' .. party_index
                if has_spell and imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 }) then
                    -- Only toggle if not a Trust
                    if not is_trust_member then
                        toggle_party_buff(ability.name, party_index, not is_enabled)
                    end
                end
                
                -- Show tooltip for Trusts explaining why they're disabled
                if is_trust_member and imgui.IsItemHovered() then
                    imgui.SetTooltip('Trust buffs are not available')
                end
                
                if is_trust_member then
                    imgui.PopStyleColor(4)
                elseif not is_enabled then
                    imgui.PopStyleColor(3)
                end
            end
        end
    end
    
    -- Display spell name after buttons
    imgui.SameLine()
    imgui.Text(desc)
    
    if not has_spell then
        imgui.PopStyleColor()
    end
end

-- Render a buff ability checkbox with party member toggle buttons
local function render_buff_checkbox_with_party_toggles(ability, job_def, extra_desc)
    -- Check if this ability is being displayed for the first time
    local key = 'disabled_' .. ability.name:gsub(' ', '_')
    if current_settings and current_settings[key] == nil then
        -- First time seeing this ability, set to disabled
        current_settings[key] = true
        if save_callback then
            save_callback()
        end
    end
    
    -- Get the command string (handle both string and function commands)
    local cmd = type(ability.command) == 'function' and ability.command(0) or ability.command
    local is_spell = cmd and string.sub(cmd, 1, 3) == '/ma'
    local has_spell = true
    local spell_suffix = ''
    
    if is_spell and ability.id then
        local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
        if ok then
            has_spell = known
            if not has_spell then
                spell_suffix = ' (Not Learned)'
                current_settings['disabled_' .. ability.name:gsub(' ', '_')] = true
            end
        else
            common.errorf('Failed to check spell knowledge for %s (ID: %d)', ability.name, ability.id)
        end
    end
    
    local desc = ability.name .. ' (Lv.' .. ability.level .. ')' .. (extra_desc or '') .. spell_suffix
    local checkbox_label = desc .. '##buff'
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.5, 0.5, 1.0 })  -- Gray color for unknown spells
    end
    
    -- Render main checkbox for player
    local ability_enabled = { is_ability_enabled(ability.name) }
    if imgui.Checkbox(checkbox_label, ability_enabled) then
        toggle_ability(ability.name, ability_enabled[1], job_def)
    end
    
    -- Only show party toggles if spell is known, can be cast on party, is enabled for self, and we're in a party
    if has_spell and can_cast_on_party(ability) and ability_enabled[1] then
        local party_size = common.get_party_size()
        
        -- Only show party toggles if we're actually in a party (size > 1)
        if party_size > 1 then
            imgui.SameLine()
            
            -- Render toggle buttons for each active party member (P1-P5)
            for party_index = 1, 5 do
                local is_active = party_index < party_size  -- P1-P(size-1) are active
                
                -- Only render buttons for active party members
                if is_active then
                    -- Check if this party member is a Trust
                    local is_trust_member = is_trust(party_index)
                    
                    -- Get current state
                    local is_enabled = is_party_buff_enabled(ability.name, party_index)
                    
                    -- Set button color and disable state based on Trust status
                    if is_trust_member then
                        -- Trust: Dark gray and disabled
                        imgui.PushStyleColor(ImGuiCol_Button, { 0.2, 0.2, 0.2, 1.0 })
                        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.2, 0.2, 0.2, 1.0 })
                        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.2, 0.2, 0.2, 1.0 })
                        imgui.PushStyleColor(ImGuiCol_Text, { 0.4, 0.4, 0.4, 1.0 })
                    elseif is_enabled then
                        -- Selected: Use default button colors (no custom styling)
                    else
                        -- Not selected: Gray
                        imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 })
                        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 })
                        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.5, 0.5, 0.5, 1.0 })
                    end
                    
                    local button_label = '<P' .. party_index .. '>##' .. ability.name .. '_p' .. party_index
                    if imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 }) then
                        -- Only toggle if not a Trust
                        if not is_trust_member then
                            toggle_party_buff(ability.name, party_index, not is_enabled)
                        end
                    end
                    
                    -- Show tooltip for Trusts explaining why they're disabled
                    if is_trust_member and imgui.IsItemHovered() then
                        imgui.SetTooltip('Trust buffs are not available')
                    end
                    
                    if is_trust_member then
                        imgui.PopStyleColor(4)
                    elseif not is_enabled then
                        imgui.PopStyleColor(3)
                    end
                    
                    -- Add spacing between buttons for next active member
                    if party_index < party_size - 1 then
                        imgui.SameLine()
                    end
                end
            end
        end
    end
    
    if not has_spell then
        imgui.PopStyleColor()
    end
end

-- Render an ability checkbox with spell knowledge checking
local function render_ability_checkbox(ability, job_def, extra_desc, id_suffix)
    -- Check if this ability is being displayed for the first time
    local key = 'disabled_' .. ability.name:gsub(' ', '_')
    if current_settings and current_settings[key] == nil then
        -- First time seeing this ability, set to disabled
        current_settings[key] = true
        if save_callback then
            save_callback()
        end
    end
    
    -- Get the command string (handle both string and function commands)
    local cmd = type(ability.command) == 'function' and ability.command(0) or ability.command
    local is_spell = cmd and string.sub(cmd, 1, 3) == '/ma'
    local has_spell = true
    local spell_suffix = ''
    
    if is_spell and ability.id then
        local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
        if ok then
            has_spell = known
            if not has_spell then
                spell_suffix = ' (Not Learned)'
                current_settings['disabled_' .. ability.name:gsub(' ', '_')] = true
            end
        else
            common.errorf('Failed to check spell knowledge for %s (ID: %d)', ability.name, ability.id)
        end
    end
    
    local desc = ability.name .. ' (Lv.' .. ability.level .. ')' .. (extra_desc or '') .. spell_suffix
    
    -- Add unique ID suffix to prevent ImGui label collisions when same ability appears in multiple sections
    local checkbox_label = desc
    if id_suffix then
        checkbox_label = desc .. '##' .. id_suffix
    end
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.5, 0.5, 1.0 })  -- Gray color for unknown spells
    end
    
    local ability_enabled = { is_ability_enabled(ability.name) }
    if imgui.Checkbox(checkbox_label, ability_enabled) then
        toggle_ability(ability.name, ability_enabled[1], job_def)
    end
    
    if not has_spell then
        imgui.PopStyleColor()
    end
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

function config_ui.render(settings, job_def, callback, roll_mod)
    if not ui_visible or not is_open[1] then
        return
    end
    
    -- Store settings reference and callback
    current_settings = settings
    save_callback = callback
    roll_module = roll_mod
    
    -- Sync UI state from settings
    sync_from_settings()
    
    imgui.SetNextWindowSize({400, 600}, ImGuiCond_FirstUseEver)
    
    -- Build window title with job name if available
    local window_title = 'Medic Configuration'
    if job_def and job_def.job_name then
        window_title = window_title .. ' - ' .. job_def.job_name
    end
    
    if imgui.Begin(window_title, is_open, ImGuiWindowFlags_NoCollapse) then
        
        -- Automation toggle button
        local can_attack = common.can_attack()
        local button_text
        local status_text
        local status_color
        
        if settings.automation_enabled then
            if can_attack then
                -- Running state
                button_text = 'Stop'
                status_text = 'Automation running.'
                status_color = { 0.0, 1.0, 0.0, 1.0 }  -- Green
            else
                -- Paused state (automation enabled but combat blocked)
                button_text = 'Paused'
                status_text = 'Automation paused.'
                status_color = { 0.0, 0.5, 1.0, 1.0 }  -- Blue
            end
        else
            -- Stopped state
            button_text = 'Start'
            status_text = 'Automation stopped.'
            status_color = { 1.0, 0.0, 0.0, 1.0 }  -- Red
        end
        
        -- Use fixed width for button to keep consistent size
        if imgui.Button(button_text, { 80, 0 }) then
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
        
        create_combo('Attack Range', 'attack_range', attack_range_index, attack_range_options, function(i)
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
                create_checkbox('Enable Focus Healing', 'focus_enabled', { settings.focus_enabled or false })
                
                if settings.focus_enabled then
                    -- Focus target dropdown
                    create_combo('Focus Target', 'focus_target_index', focus_target_index, focus_target_options, function(i)
                        -- Convert combo index (0-6) to focus_target_index (nil, 0-5)
                        if i == 0 then
                            return nil
                        else
                            return i - 1
                        end
                    end)
                    
                    create_slider_int('Focus Heal Threshold (HP%)', 'focus_threshold', { settings.focus_threshold or 85 }, 1, 100)
                end
                
                imgui.Separator()
            end
        end
        
        -- Party Healing settings
        if job_def and job_def.abilities.heal and has_usable_abilities(job_def.abilities.heal) then
            create_checkbox('Enable Party Healing', 'heal_enabled', { settings.heal_enabled or false })
            
            if settings.heal_enabled then
                create_slider_int('Party Heal Threshold (HP%)', 'heal_threshold', { settings.heal_threshold or 75 }, 1, 100)
                imgui.Indent(ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.heal) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def, nil, 'heal')
                    end
                end
                imgui.Unindent(ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end
        
        -- AOE Healing settings
        if job_def and job_def.abilities.heal_aoe and has_usable_abilities(job_def.abilities.heal_aoe) then
            create_checkbox('Enable AOE Healing', 'heal_aoe_enabled', { settings.heal_aoe_enabled or false })
            
            if settings.heal_aoe_enabled then
                create_slider_int('AOE Heal Threshold (HP%)', 'heal_aoe_threshold', { settings.heal_aoe_threshold or 70 }, 1, 100)
                
                create_slider_int('Min Members Needing Heal', 'heal_aoe_count_threshold', { settings.heal_aoe_count_threshold or 2 }, 1, 6)
                
                imgui.Indent(ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.heal_aoe) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def, nil, 'heal_aoe')
                    end
                end
                imgui.Unindent(ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end
        
        -- Pet Healing settings
        if job_def and job_def.abilities.heal_pet and has_usable_abilities(job_def.abilities.heal_pet) then
            create_checkbox('Enable Pet Healing', 'heal_pet_enabled', { settings.heal_pet_enabled or false })
            
            if settings.heal_pet_enabled then
                create_slider_int('Pet Heal Threshold (HP%)', 'heal_pet_threshold', { settings.heal_pet_threshold or 50 }, 1, 100)
                
                imgui.Indent(ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.heal_pet) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def, nil, 'heal_pet')
                    end
                end
                imgui.Unindent(ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end
        
        -- Wake settings (only show if job has wake-capable heal abilities)
        local has_wake_abilities = false
        if job_def and job_def.abilities.heal then
            for _, ability in ipairs(job_def.abilities.heal) do
                if ability.wakes then
                    has_wake_abilities = true
                    break
                end
            end
        end
        
        if has_wake_abilities then
            create_checkbox('Enable Sleep Removal', 'wake_enabled', { settings.wake_enabled or false })
            
            imgui.Separator()
        end
        
        -- Debuff removal settings
        if job_def and job_def.abilities.debuff_removal and has_usable_abilities(job_def.abilities.debuff_removal) then
            create_checkbox('Enable Debuff Removal', 'debuff_removal_enabled', { settings.debuff_removal_enabled or false })
            
            if settings.debuff_removal_enabled then
                imgui.Indent(ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.debuff_removal) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def, nil, 'debuff_removal')
                    end
                end
                imgui.Unindent(ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end
        
        -- Recovery settings
        local has_mp_recovery = job_def and job_def.abilities.recover_mp and has_usable_abilities(job_def.abilities.recover_mp)
        local has_tp_recovery = job_def and job_def.abilities.recover_tp and has_usable_abilities(job_def.abilities.recover_tp)
        
        if has_mp_recovery or has_tp_recovery then
            create_checkbox('Enable Resource Recovery', 'recover_enabled', { settings.recover_enabled or false })
            
            if settings.recover_enabled then
                -- MP Recovery
                if has_mp_recovery then
                    create_slider_int('MP Recovery Threshold (%)', 'recover_mp_threshold', { settings.recover_mp_threshold or 30 }, 1, 100)
                    imgui.Indent(ABILITY_LIST_INDENT)
                    for _, ability in ipairs(job_def.abilities.recover_mp) do
                        if can_use_ability(ability) then
                            render_ability_checkbox(ability, job_def, nil, 'recover_mp')
                        end
                    end
                    imgui.Unindent(ABILITY_LIST_INDENT)
                end
                
                -- TP Recovery
                if has_tp_recovery then
                    if has_mp_recovery then
                        imgui.Spacing()
                    end
                    create_slider_int('TP Recovery Threshold', 'recover_tp_threshold', { settings.recover_tp_threshold or 500 }, 100, 3000)
                    imgui.Indent(ABILITY_LIST_INDENT)
                    for _, ability in ipairs(job_def.abilities.recover_tp) do
                        if can_use_ability(ability) then
                            render_ability_checkbox(ability, job_def, nil, 'recover_tp')
                        end
                    end
                    imgui.Unindent(ABILITY_LIST_INDENT)
                end
            end
            
            imgui.Separator()
        end
        
        -- Buff settings
        if job_def and job_def.abilities.buff and has_usable_abilities(job_def.abilities.buff) then
            create_checkbox('Enable Buffs', 'buff_enabled', { settings.buff_enabled or false })
            
            if settings.buff_enabled then
                -- Clear temporary group rendering flags
                if current_settings then
                    for key in pairs(current_settings) do
                        if key:match('^rendered_group_') then
                            current_settings[key] = nil
                        end
                    end
                end
                
                imgui.Indent(ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.buff) do
                    local extra_desc = ''
                    if ability.combat_only then
                        extra_desc = ' [Combat Only]'
                    elseif ability.idle_only then
                        extra_desc = ' [Idle Only]'
                    end
                    
                    render_ability(ability, job_def, extra_desc, 'buff')
                end
                imgui.Unindent(ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end
        
        -- Geo settings (Geomancer)
        if job_def and job_def.abilities.geo and has_usable_abilities(job_def.abilities.geo) then
            create_checkbox('Enable Geo (Full Circle)', 'geo_enabled', { settings.geo_enabled or false })
            
            if settings.geo_enabled then
                create_slider_int('Pet Distance Threshold (yalms)', 'geo_distance_threshold', { settings.geo_distance_threshold or 10 }, 7, 30)
                imgui.Indent(ABILITY_LIST_INDENT)
                for _, ability in ipairs(job_def.abilities.geo) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def, nil, 'geo')
                    end
                end
                imgui.Unindent(ABILITY_LIST_INDENT)
            end
            
            imgui.Separator()
        end
        
        -- Debug mode (at end)
        local debug_var = { common.debug }
        if imgui.Checkbox('Debug Mode', debug_var) then
            common.debug = debug_var[1]
        end
        
        if common.debug then
            imgui.Indent(ABILITY_LIST_INDENT)
            local zone_id = common.get_zone_id()
            imgui.Text(string.format('get_zone_id = %d', zone_id))
            local target_id = common.get_target_id()
            imgui.Text(string.format('get_target_id = %s', tostring(target_id)))
            local is_moving = common.is_player_moving()
            imgui.Text(string.format('is_player_moving = %s', tostring(is_moving)))
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
            
            imgui.Unindent(ABILITY_LIST_INDENT)
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
