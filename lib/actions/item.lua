--[[
    Item action module
    Handles using items for status removal (e.g., Echo Drops for Silence)
]]--

local common = require('lib.core.common')

local item = {}

-- Item usage cooldown tracking (7 seconds)
local last_item_use = 0
local ITEM_COOLDOWN = 7.0

-- Get item count in player's inventory (container 0)
-- Args: item_name (string) - Name of the item to count
-- Returns: number - Total count of the item in inventory
local function get_item_count(item_name)
    local ok_item, target_item = pcall(function()
        return AshitaCore:GetResourceManager():GetItemByName(item_name, 0)
    end)
    
    if not ok_item or not target_item then
        return 0
    end
    
    local ok_inv, inventory = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    
    if not ok_inv or not inventory then
        return 0
    end
    
    local total_count = 0
    local ok_max, max_slots = pcall(function()
        return inventory:GetContainerMax(0)
    end)
    
    if not ok_max or not max_slots then
        return 0
    end
    
    for i = 1, max_slots do
        local ok_item_slot, item = pcall(function()
            return inventory:GetItem(0, i)
        end)
        
        if ok_item_slot and item and item.Id == target_item.Id and item.Id ~= 0 and item.Id ~= -1 and item.Id ~= 65535 then
            total_count = total_count + item.Count
        end
    end
    
    return total_count
end

-- Check if item action should be executed
-- Args:
--   settings (table) - Addon settings
--   job_def (table) - Job definition
-- Returns: string (command) or nil
function item.check(settings, job_def)
    -- Check if item silence removal is enabled
    if not settings or not settings.item_silence_removal_enabled then
        return nil
    end
    
    -- Check if player has Silence debuff (buff_id 6)
    if not common.has_buff(0, 6) then
        return nil
    end
    
    -- Check cooldown (7 seconds since last use)
    local current_time = os.clock()
    if current_time - last_item_use < ITEM_COOLDOWN then
        common.debugf('[Item] On cooldown, %.1f seconds remaining', ITEM_COOLDOWN - (current_time - last_item_use))
        return nil
    end
    
    -- Get Echo Drops item
    local echo_drops = AshitaCore:GetResourceManager():GetItemByName('Echo Drops', 0)
    if not echo_drops then
        common.debugf('[Item] Echo Drops not found in resource manager')
        return nil
    end
    
    -- Check if player has Echo Drops in inventory
    local item_count = get_item_count('Echo Drops')
    if item_count == 0 then
        common.debugf('[Item] No Echo Drops in inventory')
        return nil
    end
    
    -- Check item recast timer
    local recast = AshitaCore:GetDataManager():GetRecast():GetRecast(0, echo_drops.Id)
    if recast > 0 then
        common.debugf('[Item] Echo Drops on recast: %d seconds remaining', recast)
        return nil
    end
    
    common.debugf('[Item] Using Echo Drops to remove Silence')
    last_item_use = current_time
    
    return '/item "Echo Drops" <me>'
end

-- Export get_item_count for UI to use
item.get_item_count = get_item_count

return item
