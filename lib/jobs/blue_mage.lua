--[[
    Blue Mage job definition
    Defines abilities, validators, and configuration for Blue Mage automation
]]--

local common = require('lib.core.common')

return {
    job_id = 16,  -- Blue Mage
    job_name = 'Blue Mage',
    resource_type = 'mp',
    
    abilities = {
    },
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = false,
        heal_threshold = 75,
        heal_aoe_enabled = false,
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        wake_enabled = false,
        buff_enabled = false,
        debuff_removal_enabled = false,
        focus_enabled = false,
        focus_target_index = nil,
        focus_threshold = 85,
    },
    
    -- Action priority order
    priority_order = {
    },
}