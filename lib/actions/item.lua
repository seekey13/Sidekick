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
        common.debugf('[Item] Failed to get item resource for: %s', item_name)
        return 0
    end
    
    common.debugf('[Item] Looking for item ID: %d (%s)', target_item.Id, item_name)
    
    local ok_inv, inventory = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    
    if not ok_inv or not inventory then
        common.debugf('[Item] Failed to get inventory manager')
        return 0
    end
    
    local total_count = 0
    -- Inventory container 0 has 80 slots in FFXI
    local max_slots = 80
    
    common.debugf('[Item] Scanning %d inventory slots', max_slots)
    
    for i = 0, max_slots - 1 do
        local ok_item_slot, item_entry = pcall(function()
            return inventory:GetContainerItem(0, i)
        end)
        
        if ok_item_slot and item_entry and item_entry.Id ~= 0 and item_entry.Id ~= -1 and item_entry.Id ~= 65535 then
            if item_entry.Id == target_item.Id then
                common.debugf('[Item] Found %s in slot %d, count: %d', item_name, i, item_entry.Count)
                total_count = total_count + item_entry.Count
            end
        end
    end
    
    common.debugf('[Item] Total count for %s: %d', item_name, total_count)
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
