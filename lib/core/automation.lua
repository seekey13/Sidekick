--[[
    Automation engine for Medic
    Priority-based action selection and command execution
]]--

local automation = {}
local common = require('lib.core.common')


-- Last command execution time
local last_command_time = 0
local command_throttle = 1.0 -- 1 second between commands

--[[
    Command Execution
]]--

function automation.can_execute_command()
    local current_time = os.clock()
    return (current_time - last_command_time) >= command_throttle
end

function automation.execute_command(command, description)
    if not command then return false end
    
    local current_time = os.clock()
    if (current_time - last_command_time) < command_throttle then
        return false
    end
    
    -- Execute the command
    AshitaCore:GetChatManager():QueueCommand(0, command)
    last_command_time = current_time
    
    return true
end

function automation.set_throttle(seconds)
    command_throttle = seconds
end

function automation.get_throttle()
    return command_throttle
end

function automation.reset_throttle()
    last_command_time = 0
end

--[[
    Action Priority System
]]--

function automation.execute_priority_actions(priority_order, action_modules, settings, job_def, main_level, sub_level, player_resource)
    local common = require('lib.core.common')
    
    if not automation.can_execute_command() then
        -- Don't spam this debug message
        return false
    end
    
    for _, action_type in ipairs(priority_order) do
        local action_module = action_modules[action_type]
        if action_module and action_module.execute then
            local success, result = pcall(action_module.execute, settings, job_def, main_level, sub_level, player_resource)
            
            if success and result then
                -- If resting and this is an urgent action type, break rest first.
                -- buff and geo are low-priority and do not interrupt rest.
                -- The actual action fires next tick once /heal off has landed.
                local rest_breaking_actions = { heal = true, recover = true, item = true, status_removal = true, debuff_removal = true, wake = true, revive = true }
                if rest_breaking_actions[action_type] and common.is_resting() then
                    common.set_resting(false)
                    common.reset_rest_timer()
                    automation.execute_command('/heal off', 'Breaking rest for: ' .. action_type)
                    return true
                end

                if type(result) == 'table' then
                    -- Result is {command, description}
                    if automation.execute_command(result.command, result.description) then
                        common.reset_rest_timer()  -- Any action resets the rest conditions timer
                        return true
                    end
                elseif type(result) == 'string' then
                    -- Result is just the command
                    if automation.execute_command(result, action_type) then
                        common.reset_rest_timer()  -- Any action resets the rest conditions timer
                        return true
                    end
                end
            elseif not success then
                common.errorf('Action module "%s" failed: %s', action_type, tostring(result))
            end
        end
    end
    
    return false
end

return automation
