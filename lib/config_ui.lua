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
local focus_target_index = { 0 }  -- 0 = None, 1-6 = P0-P5

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

-- Get all abilities in the same group as the given ability
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
                    table.insert(group_abilities, ability.name)
                end
            end
        end
    end
    
    return group_abilities
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
                if other_ability ~= ability_name then
                    local other_key = 'disabled_' .. other_ability:gsub(' ', '_')
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
    if imgui.BeginCombo(label, options[ui_var[1] + 1]) then
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

-- Render an ability checkbox with spell knowledge checking
local function render_ability_checkbox(ability, job_def, extra_desc)
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
    
    if not has_spell then
        imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.5, 0.5, 1.0 })  -- Gray color for unknown spells
    end
    
    local ability_enabled = { is_ability_enabled(ability.name) }
    if imgui.Checkbox(desc, ability_enabled) then
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
        local button_text = settings.automation_enabled and 'Stop' or 'Start'
        local status_text = settings.automation_enabled and 'Automation running.' or 'Automation stopped.'
        local status_color = settings.automation_enabled and { 0.0, 1.0, 0.0, 1.0 } or { 1.0, 0.0, 0.0, 1.0 }
        
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
                    imgui.TextWrapped('The focus target will be prioritized for healing when their HP falls below the threshold.')
                end
                
                imgui.Separator()
            end
        end
        
        -- Party Healing settings
        if job_def and job_def.abilities.heal and has_usable_abilities(job_def.abilities.heal) then
            create_checkbox('Enable Party Healing', 'heal_enabled', { settings.heal_enabled or false })
            
            if settings.heal_enabled then
                create_slider_int('Party Heal Threshold (HP%)', 'heal_threshold', { settings.heal_threshold or 75 }, 1, 100)
                imgui.TextWrapped('Heals the lowest HP party member when their HP falls below the threshold.')
                
                imgui.Text('Healing abilities:')
                imgui.TextWrapped('(Used by both Focus Healing and Party Healing)')
                for _, ability in ipairs(job_def.abilities.heal) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def)
                    end
                end
            end
            
            imgui.Separator()
        end
        
        -- AOE Healing settings
        if job_def and job_def.abilities.heal_aoe and has_usable_abilities(job_def.abilities.heal_aoe) then
            create_checkbox('Enable AOE Healing', 'heal_aoe_enabled', { settings.heal_aoe_enabled or false })
            
            if settings.heal_aoe_enabled then
                create_slider_int('AOE Heal Threshold (HP%)', 'heal_aoe_threshold', { settings.heal_aoe_threshold or 70 }, 1, 100)
                
                create_slider_int('Min Members Needing Heal', 'heal_aoe_count_threshold', { settings.heal_aoe_count_threshold or 2 }, 1, 6)
                
                imgui.Text('AOE healing abilities:')
                for _, ability in ipairs(job_def.abilities.heal_aoe) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def)
                    end
                end
            end
            
            imgui.Separator()
        end
        
        -- Pet Healing settings
        if job_def and job_def.abilities.heal_pet and has_usable_abilities(job_def.abilities.heal_pet) then
            create_checkbox('Enable Pet Healing', 'heal_pet_enabled', { settings.heal_pet_enabled or false })
            
            if settings.heal_pet_enabled then
                create_slider_int('Pet Heal Threshold (HP%)', 'heal_pet_threshold', { settings.heal_pet_threshold or 50 }, 1, 100)
                
                imgui.Text('Pet healing abilities:')
                for _, ability in ipairs(job_def.abilities.heal_pet) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def)
                    end
                end
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
            
            if settings.wake_enabled then
                imgui.Text('Will automatically wake sleeping party members.')
            end
            
            imgui.Separator()
        end
        
        -- Debuff removal settings
        if job_def and job_def.abilities.debuff_removal and has_usable_abilities(job_def.abilities.debuff_removal) then
            create_checkbox('Enable Debuff Removal', 'debuff_removal_enabled', { settings.debuff_removal_enabled or false })
            
            if settings.debuff_removal_enabled then
                imgui.Text('Debuff removal abilities:')
                for _, ability in ipairs(job_def.abilities.debuff_removal) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def)
                    end
                end
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
                    imgui.TextWrapped('Use MP recovery abilities when MP falls below this percentage.')
                    
                    imgui.Text('MP recovery abilities:')
                    for _, ability in ipairs(job_def.abilities.recover_mp) do
                        if can_use_ability(ability) then
                            render_ability_checkbox(ability, job_def)
                        end
                    end
                end
                
                -- TP Recovery
                if has_tp_recovery then
                    if has_mp_recovery then
                        imgui.Spacing()
                    end
                    create_slider_int('TP Recovery Threshold', 'recover_tp_threshold', { settings.recover_tp_threshold or 500 }, 100, 3000)
                    imgui.TextWrapped('Use TP recovery abilities when TP falls below this threshold.')
                    
                    imgui.Text('TP recovery abilities:')
                    for _, ability in ipairs(job_def.abilities.recover_tp) do
                        if can_use_ability(ability) then
                            render_ability_checkbox(ability, job_def)
                        end
                    end
                end
            end
            
            imgui.Separator()
        end
        
        -- Buff settings
        if job_def and job_def.abilities.buff and has_usable_abilities(job_def.abilities.buff) then
            create_checkbox('Enable Buffs', 'buff_enabled', { settings.buff_enabled or false })
            
            if settings.buff_enabled then
                imgui.Text('Buffs:')
                for _, ability in ipairs(job_def.abilities.buff) do
                    if can_use_ability(ability) then
                        local extra_desc = ''
                        if ability.combat_only then
                            extra_desc = ' [Combat Only]'
                        elseif ability.idle_only then
                            extra_desc = ' [Idle Only]'
                        end
                        render_ability_checkbox(ability, job_def, extra_desc)
                    end
                end
            end
            
            imgui.Separator()
        end
        
        -- Geo settings (Geomancer)
        if job_def and job_def.abilities.geo and has_usable_abilities(job_def.abilities.geo) then
            create_checkbox('Enable Geo (Full Circle)', 'geo_enabled', { settings.geo_enabled or false })
            
            if settings.geo_enabled then
                create_slider_int('Pet Distance Threshold (yalms)', 'geo_distance_threshold', { settings.geo_distance_threshold or 10 }, 7, 30)
                imgui.TextWrapped('Uses Full Circle when pet (Luopan) is farther than this distance.')
                
                imgui.Text('Geo abilities:')
                for _, ability in ipairs(job_def.abilities.geo) do
                    if can_use_ability(ability) then
                        render_ability_checkbox(ability, job_def)
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
