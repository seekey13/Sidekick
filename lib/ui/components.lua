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
local PARTY_BUTTON_WIDTH = 44
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
local HEADER_COLOR_NORMAL = { 0.05, 0.1, 0.2, 0.31 }
local HEADER_COLOR_HOVERED = { 0.05, 0.1, 0.2, 0.80 }
local HEADER_COLOR_ACTIVE = { 0.05, 0.1, 0.2, 1.00 }

-- ============================================================================
-- Helper Functions
-- ============================================================================

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

-- Get the group of an ability by name
local function get_ability_group(job_def, ability_name)
    if not job_def or not job_def.abilities then
        return nil
    end
    
    for category, abilities in pairs(job_def.abilities) do
        for _, ability in ipairs(abilities) do
            if ability.name == ability_name and ability.group then
                return ability.group
            end
        end
    end
    
    return nil
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
            
            if sample_ability.target_modifier == true then
                -- Determine the limit based on main/sub job
                local is_main_job = sample_ability.is_main_job ~= false
                local song_limit = is_main_job and 2 or 1
                
                -- Count currently enabled song groups with target_modifier for this party member
                local active_song_groups = {}
                for other_group_name, targets in pairs(ctx.party_buffs) do
                    if other_group_name ~= group_name and targets[party_index] == true then
                        local other_abilities = get_abilities_in_group(ctx.job_def, other_group_name)
                        if #other_abilities > 0 and other_abilities[1].target_modifier == true then
                            table.insert(active_song_groups, other_group_name)
                        end
                    end
                end
                
                -- If at or over limit, deselect one existing song group for this party member
                if #active_song_groups >= song_limit then
                    local group_to_remove = active_song_groups[1]
                    ctx.party_buffs[group_to_remove][party_index] = false
                    
                    -- Ensure persistence structure exists
                    ctx.settings.party_buffs = ctx.settings.party_buffs or {}
                    ctx.settings.party_buffs[group_to_remove] = ctx.settings.party_buffs[group_to_remove] or {}
                    ctx.settings.party_buffs[group_to_remove][party_index] = false
                    
                    -- Check if removed group is still enabled for any party member
                    local removed_still_enabled = false
                    for i = 0, 5 do
                        if ctx.party_buffs[group_to_remove][i] == true then
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
    
    -- Set the new buff state
    ctx.party_buffs[group_name][party_index] = enabled
    
    -- Check if ANY button is enabled for this group
    local any_button_enabled = false
    for i = 0, 5 do
        if ctx.party_buffs[group_name][i] == true then
            any_button_enabled = true
            break
        end
    end
    
    -- Update the group's disabled setting
    ctx.settings['disabled_group_' .. group_name] = not any_button_enabled
    
    -- Save party_buffs to settings for persistence
    ctx.settings.party_buffs = ctx.settings.party_buffs or {}
    ctx.settings.party_buffs[group_name] = ctx.settings.party_buffs[group_name] or {}
    ctx.settings.party_buffs[group_name][party_index] = enabled
    
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
        
        if ability and ability.target_modifier == true then
            -- Determine the limit based on main/sub job
            local is_main_job = ability.is_main_job ~= false
            local song_limit = is_main_job and 2 or 1
            
            -- Count currently enabled songs with target_modifier for this party member
            local active_songs = {}
            for other_ability_name, targets in pairs(ctx.party_buffs) do
                if other_ability_name ~= ability_name and targets[party_index] == true then
                    local other_ability = find_ability_by_name(ctx.job_def, other_ability_name)
                    if other_ability and other_ability.target_modifier == true then
                        table.insert(active_songs, other_ability_name)
                    end
                end
            end
            
            -- If at or over limit, deselect one existing song for this party member
            if #active_songs >= song_limit then
                local song_to_remove = active_songs[1]  -- Remove first found (random due to table iteration)
                ctx.party_buffs[song_to_remove][party_index] = false
                
                -- Ensure persistence structure exists, then update settings for the removed song
                ctx.settings.party_buffs = ctx.settings.party_buffs or {}
                ctx.settings.party_buffs[song_to_remove] = ctx.settings.party_buffs[song_to_remove] or {}
                ctx.settings.party_buffs[song_to_remove][party_index] = false
                
                -- Check if removed song is still enabled for any party member
                local removed_still_enabled = false
                for i = 0, 5 do
                    if ctx.party_buffs[song_to_remove][i] == true then
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
    for i = 0, 5 do
        if ctx.party_buffs[ability_name][i] == true then
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
    
    -- Save party_buffs to settings for persistence
    if not ctx.settings.party_buffs then
        ctx.settings.party_buffs = {}
    end
    if not ctx.settings.party_buffs[ability_name] then
        ctx.settings.party_buffs[ability_name] = {}
    end
    ctx.settings.party_buffs[ability_name][party_index] = enabled
    
    if ctx.save_callback then
        ctx.save_callback()
    end
end

-- Calculate the width for the ON/OFF button based on party size
local function get_onoff_button_width()
    local party_size = common.get_party_size()
    local num_buttons = math.min(party_size, 6)
    return PARTY_BUTTON_WIDTH * num_buttons + (SPACE_BETWEEN_BUTTONS * (num_buttons - 1))
end

-- ============================================================================
-- Party Button Helper
-- ============================================================================

-- Render party toggle buttons (<ME> <P1> <P2> etc.)
-- Returns: true if any button was rendered
-- For grouped abilities, pass group_name instead of ability_name
local function render_party_buttons(ctx, key_name, has_spell, ability, is_group)
    local any_rendered = false
    
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
    
    -- Render [<ME>] button
    local me_enabled = is_group and is_group_party_buff_enabled(ctx, key_name, 0) or is_party_buff_enabled(ctx, key_name, 0)
    
    if not has_spell then
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
    
    local me_button_label = '<ME>##' .. key_name .. '_me'
    if has_spell and imgui.Button(me_button_label, { PARTY_BUTTON_WIDTH, 0 }) then
        if is_group then
            toggle_group_party_buff(ctx, key_name, 0, not me_enabled)
        else
            toggle_party_buff(ctx, key_name, 0, not me_enabled)
        end
    elseif not has_spell then
        imgui.Button(me_button_label, { PARTY_BUTTON_WIDTH, 0 })
    end
    
    if not has_spell then
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
                
                local button_label = '<P' .. party_index .. '>##' .. key_name .. '_p' .. party_index
                if party_has_spell and imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 }) then
                    if is_group then
                        toggle_group_party_buff(ctx, key_name, party_index, not is_enabled)
                    else
                        toggle_party_buff(ctx, key_name, party_index, not is_enabled)
                    end
                elseif not party_has_spell then
                    imgui.Button(button_label, { PARTY_BUTTON_WIDTH, 0 })
                end
                
                -- NOTE: Trust tooltip removed -- Trusts can now be buffed
                -- if is_trust_member and imgui.IsItemHovered() then
                --     imgui.SetTooltip('Trust can not be buffed')
                -- end
                
                if not party_has_spell then
                    imgui.PopStyleColor(4)
                elseif not is_enabled then
                    imgui.PopStyleColor(3)
                end
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
            current_display = selected.name .. ' (' .. selected.cost .. ' ' .. resource_label .. ')'
        else
            current_display = selected.name
        end
    else
        current_display = 'None'
    end
    
    local setting_key = 'selected_' .. target_group
    local combo_label = '##dropdown_' .. target_group
    
    -- Apply color styling
    if selected then
        if selected.engaged_only then
            imgui.PushStyleColor(ImGuiCol_Text, LIGHT_RED)
        elseif selected.combat_only then
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
                display_text = ability.name .. ' (' .. ability.cost .. ' ' .. resource_label .. ')'
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
    
    -- Show tooltip
    if imgui.IsItemHovered() and selected then
        if selected.engaged_only then
            imgui.SetTooltip('Engaged Only')
        elseif selected.combat_only then
            imgui.SetTooltip('Combat Only')
        elseif selected.idle_only then
            imgui.SetTooltip('Idle Only')
        end
    end
    
    imgui.PopItemWidth()
    
    if selected and (selected.engaged_only or selected.combat_only or selected.idle_only) then
        imgui.PopStyleColor()
    end
end

-- Render a self-target single ability
-- Layout: [ON/OFF Button] Ability Name
function ui_components.self_single_ability(ctx, ability, job_def, id_suffix)
    local has_spell = common.has_spell_learned(ability)
    local spell_suffix = has_spell and '' or ' (Not Learned)'
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif ability.engaged_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_RED)
    elseif ability.combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif ability.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end
    
    ui_components.onoff_button(ctx, ability.name, job_def, has_spell)
    
    imgui.SameLine()
    local desc
    if ability.cost and ability.cost > 0 then
        local resource_label = (ability.resource_type or job_def.resource_type) == 'tp' and 'TP' or 'MP'
        desc = ability.name .. ' (' .. ability.cost .. ' ' .. resource_label .. ')' .. spell_suffix
    else
        desc = ability.name .. spell_suffix
    end
    imgui.Text(desc)
    
    if imgui.IsItemHovered() then
        if ability.engaged_only then
            imgui.SetTooltip('Engaged Only')
        elseif ability.combat_only then
            imgui.SetTooltip('Combat Only')
        elseif ability.idle_only then
            imgui.SetTooltip('Idle Only')
        end
    end
    
    if not has_spell or ability.engaged_only or ability.combat_only or ability.idle_only then
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
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif selected.engaged_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_RED)
    elseif selected.combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif selected.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end
    
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
    
    imgui.SameLine()
    ui_components.group_dropdown(ctx, job_def, ability.group, DROPDOWN_WIDTH)
    
    if not has_spell or selected.engaged_only or selected.combat_only or selected.idle_only then
        imgui.PopStyleColor()
    end
end

-- Render a party-target single ability
-- Layout: [<ME>] [<P1>] [<P2>]... Ability Name
function ui_components.party_single_ability(ctx, ability, job_def)
    local has_spell = common.has_spell_learned(ability)
    local spell_suffix = has_spell and '' or ' (Not Learned)'
    
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
        desc = ability.name .. ' (' .. ability.cost .. ' ' .. resource_label .. ')' .. spell_suffix
    else
        desc = ability.name .. spell_suffix
    end
    
    render_party_buttons(ctx, ability.name, has_spell, ability, false)
    
    imgui.SameLine()
    
    if not has_spell or not has_modifier then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif ability.engaged_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_RED)
    elseif ability.combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif ability.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end
    
    imgui.Text(desc)
    
    if imgui.IsItemHovered() then
        if ability.engaged_only then
            imgui.SetTooltip('Engaged Only')
        elseif ability.combat_only then
            imgui.SetTooltip('Combat Only')
        elseif ability.idle_only then
            imgui.SetTooltip('Idle Only')
        end
    end
    
    if not has_spell or not has_modifier or ability.engaged_only or ability.combat_only or ability.idle_only then
        imgui.PopStyleColor()
    end
end

-- Render a party-target grouped ability with dropdown
-- Layout: [<ME>] [<P1>] [<P2>]... [Dropdown]
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
    
    if not has_spell or not has_modifier then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif selected.engaged_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_RED)
    elseif selected.combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif selected.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end
    
    ui_components.group_dropdown(ctx, job_def, ability.group, DROPDOWN_WIDTH)
    
    if not has_spell or not has_modifier or selected.engaged_only or selected.combat_only or selected.idle_only then
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
    
    local has_group = ability.group ~= nil
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
    local setting_var = { ctx.settings[setting_name] or default_value }
    if imgui.Checkbox('##' .. setting_name, setting_var) then
        ctx.settings[setting_name] = setting_var[1]
        if ctx.save_callback then
            ctx.save_callback()
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
function ui_components.ability_checkbox(ctx, ability, job_def, id_suffix)
    local has_spell = common.has_spell_learned(ability)
    local spell_suffix = ''
    if not has_spell then
        spell_suffix = ' (Not Learned)'
        ctx.settings['disabled_' .. ability.name:gsub(' ', '_')] = true
    end
    
    local desc
    if ability.cost and ability.cost > 0 then
        local resource_label = (ability.resource_type or job_def.resource_type) == 'tp' and 'TP' or 'MP'
        desc = ability.name .. ' (' .. ability.cost .. ' ' .. resource_label .. ')' .. spell_suffix
    else
        desc = ability.name .. spell_suffix
    end
    
    local checkbox_label = desc
    if id_suffix then
        checkbox_label = desc .. '##' .. id_suffix
    end
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GRAY)
    elseif ability.engaged_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_RED)
    elseif ability.combat_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_YELLOW)
    elseif ability.idle_only then
        imgui.PushStyleColor(ImGuiCol_Text, LIGHT_GREEN)
    end
    
    local ability_enabled = { is_ability_enabled(ctx, ability.name) }
    if imgui.Checkbox(checkbox_label, ability_enabled) then
        toggle_ability(ctx, ability.name, ability_enabled[1], job_def)
    end
    
    if imgui.IsItemHovered() then
        if ability.engaged_only then
            imgui.SetTooltip('Engaged Only')
        elseif ability.combat_only then
            imgui.SetTooltip('Combat Only')
        elseif ability.idle_only then
            imgui.SetTooltip('Idle Only')
        end
    end
    
    if not has_spell or ability.engaged_only or ability.combat_only or ability.idle_only then
        imgui.PopStyleColor()
    end
end

-- ============================================================================
-- Item Checkbox Component
-- ============================================================================

-- Render a checkbox for item-based debuff removal (DRY helper)
-- Args: ctx, item_name, setting_key, debuff_name
local function render_item_removal_checkbox(ctx, item_name, setting_key, debuff_name)
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
        if is_disabled then
            imgui.SetTooltip(string.format('No %s in inventory', item_name))
        else
            imgui.SetTooltip(string.format('Use %s to remove %s (Item)', item_name, debuff_name))
        end
    end
end

function ui_components.item_silence_removal_checkbox(ctx)
    render_item_removal_checkbox(ctx, 'Echo Drops', 'item_silence_removal_enabled', 'Silence')
end

function ui_components.item_doom_removal_checkbox(ctx)
    render_item_removal_checkbox(ctx, 'Holy Water', 'item_doom_removal_enabled', 'Doom')
end

-- ============================================================================
-- Export Constants
-- ============================================================================

ui_components.ABILITY_LIST_INDENT = ABILITY_LIST_INDENT
ui_components.PARTY_BUTTON_WIDTH = PARTY_BUTTON_WIDTH
ui_components.SPACE_BETWEEN_BUTTONS = SPACE_BETWEEN_BUTTONS
ui_components.DROPDOWN_WIDTH = DROPDOWN_WIDTH
ui_components.AUTOMATION_BUTTON_WIDTH = AUTOMATION_BUTTON_WIDTH
ui_components.LIGHT_GREEN = LIGHT_GREEN
ui_components.LIGHT_BLUE = LIGHT_BLUE
ui_components.LIGHT_RED = LIGHT_RED
ui_components.LIGHT_GRAY = LIGHT_GRAY
ui_components.LIGHT_YELLOW = LIGHT_YELLOW

return ui_components
