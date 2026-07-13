--[[
    Automation engine for Sidekick
    Priority-based action selection and command execution
]]--

local automation = {}
local common = require('lib.core.common')


-- Last command execution time
local last_command_time = 0
local command_throttle = 1.0 -- 1 second between commands

-- Pending stratagem follow-up: when a stratagem JA fires, we lock the next
-- tick to the same action_type so the paired ability gets executed before the
-- priority loop can pre-empt it with something else.
local pending_stratagem = nil   -- { action_type = string, timestamp = number }
local STRATAGEM_FOLLOWUP_TIMEOUT = 5.0  -- seconds before we give up waiting

-- Action types that should interrupt resting (/heal) before firing.
local REST_BREAKING = { heal = true, recover = true, item = true, status_removal = true, debuff_removal = true, wake = true, revive = true }

--[[
    Command Execution
]]--

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

--[[
    Action Priority System
]]--

-- Helper: execute a single action result (table or string) and handle
-- stratagem follow-up bookkeeping.  Returns true when a command was sent.
local function dispatch_result(result, action_type)
    if type(result) == 'table' then
        if automation.execute_command(result.command, result.description) then
            common.reset_rest_timer()
            -- If this was a stratagem JA, lock the next tick to the same action_type
            if result.is_stratagem then
                pending_stratagem = { action_type = action_type, timestamp = os.clock() }
            else
                -- Successful non-stratagem action clears any pending lock
                pending_stratagem = nil
            end
            return true
        end
    elseif type(result) == 'string' then
        if automation.execute_command(result, action_type) then
            common.reset_rest_timer()
            pending_stratagem = nil
            return true
        end
    end
    return false
end

function automation.execute_priority_actions(priority_order, action_modules, settings, job_def, main_level, sub_level, player_resource)
    if (os.clock() - last_command_time) < command_throttle then
        return false
    end

    -- ----------------------------------------------------------------
    -- Stratagem follow-up: if a stratagem JA fired on the previous tick,
    -- run ONLY the originating action module so the paired ability fires
    -- before anything else can pre-empt it.
    -- ----------------------------------------------------------------
    if pending_stratagem then
        local elapsed = os.clock() - pending_stratagem.timestamp
        if elapsed > STRATAGEM_FOLLOWUP_TIMEOUT then
            -- Timed out waiting — abandon the lock and resume normal priority
            common.debugf('[STRAT] Follow-up for %s timed out after %.1fs — resuming normal priority',
                pending_stratagem.action_type, elapsed)
            pending_stratagem = nil
        else
            local locked_type   = pending_stratagem.action_type
            local action_module = action_modules[locked_type]
            if action_module and action_module.execute then
                local success, result = pcall(action_module.execute, settings, job_def, main_level, sub_level, player_resource)
                if success and result then
                    -- Break rest if needed (same logic as normal path)
                    if REST_BREAKING[locked_type] and common.is_resting() then
                        common.set_resting(false)
                        common.reset_rest_timer()
                        automation.execute_command('/heal off', 'Breaking rest for: ' .. locked_type)
                        return true
                    end
                    if dispatch_result(result, locked_type) then
                        return true
                    end
                elseif not success then
                    common.errorf('Action module "%s" (strat follow-up) failed: %s', locked_type, tostring(result))
                end
                -- If the locked module returned nil (conditions changed) or the
                -- result was a new stratagem (multiple charges needed), keep the
                -- lock alive — it will either resolve or time out.
                if not (result and type(result) == 'table' and result.is_stratagem) then
                    -- No result or non-stratagem result means conditions changed; release lock
                    if not result then
                        common.debugf('[STRAT] Follow-up for %s returned nil — releasing lock', locked_type)
                        pending_stratagem = nil
                    end
                end
            else
                pending_stratagem = nil
            end
            -- Whether the follow-up fired or not, skip the normal priority
            -- loop this tick to avoid pre-empting the stratagem.
            return false
        end
    end
    
    for _, action_type in ipairs(priority_order) do
        local action_module = action_modules[action_type]
        if action_module and action_module.execute then
            local success, result = pcall(action_module.execute, settings, job_def, main_level, sub_level, player_resource)
            
            if success and result then
                -- If resting and this is an urgent action type, break rest first.
                -- buff and geo are low-priority and do not interrupt rest.
                -- The actual action fires next tick once /heal off has landed.
                if REST_BREAKING[action_type] and common.is_resting() then
                    common.set_resting(false)
                    common.reset_rest_timer()
                    automation.execute_command('/heal off', 'Breaking rest for: ' .. action_type)
                    return true
                end

                if dispatch_result(result, action_type) then
                    return true
                end
            elseif not success then
                common.errorf('Action module "%s" failed: %s', action_type, tostring(result))
            end
        end
    end
    
    return false
end

return automation
