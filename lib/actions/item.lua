--[[
    Item action module
    Handles using items for status removal (e.g., Echo Drops for Silence)
]]--

local common = require('lib.core.common')

local item = {}

-- Item usage cooldown tracking (4 seconds to avoid item recast issues)
local last_item_use = 0
local ITEM_COOLDOWN = 4.0

-- Get item count in player's inventory (container 0)
-- Args: item_name (string) - Name of the item to count
-- Returns: number or nil - Total count of the item in inventory, or nil if inventory not loaded
local function get_item_count(item_name)
    local ok_item, target_item = pcall(function()
        return AshitaCore:GetResourceManager():GetItemByName(item_name, 0)
    end)
    
    if not ok_item or not target_item then
        common.debugf('[Item] Failed to get item resource for: %s', item_name)
        return nil  -- Return nil when resource manager fails (during zoning)
    end
    
    local ok_inv, inventory = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    
    if not ok_inv or not inventory then
        common.debugf('[Item] Failed to get inventory manager')
        return nil  -- Return nil when inventory isn't loaded (during zoning)
    end
    
    local total_count = 0
    local valid_item_count = 0  -- Track how many valid items we find
    -- Inventory container 0 has 80 slots in FFXI
    local max_slots = 80
    
    for i = 0, max_slots - 1 do
        local ok_item_slot, item_entry = pcall(function()
            return inventory:GetContainerItem(0, i)
        end)
        
        if ok_item_slot and item_entry then
            -- Count any non-empty slot as "valid" to detect if inventory is loaded
            if item_entry.Id ~= 0 and item_entry.Id ~= -1 and item_entry.Id ~= 65535 then
                valid_item_count = valid_item_count + 1
                
                if item_entry.Id == target_item.Id then
                    total_count = total_count + item_entry.Count
                end
            end
        end
    end
    
    -- If we found no valid items at all in the entire inventory, it's likely not loaded yet
    if valid_item_count == 0 then
        common.debugf('[Item] No valid items found in inventory - may not be loaded yet')
        return nil
    end
    
    return total_count
end

-- Item removal definitions, ordered by priority (Doom > Silence)
local ITEM_REMOVALS = {
    { setting_key = 'item_doom_removal_enabled',    buff_id = 15, item_name = 'Holy Water',  debuff_name = 'Doom' },
    { setting_key = 'item_silence_removal_enabled', buff_id = 6,  item_name = 'Echo Drops',  debuff_name = 'Silence' },
}

-- Try a single item-removal entry; returns {command, description} or nil
local function try_item_removal(entry, settings)
    if not (settings and settings[entry.setting_key]) then return nil end

    common.debugf('[Item] Checking for %s buff...', entry.debuff_name)

    if not common.has_buff(0, entry.buff_id) then
        common.debugf('[Item] Player does not have %s buff', entry.debuff_name)
        return nil
    end

    common.debugf('[Item] Player has %s! Proceeding with %s check...', entry.debuff_name, entry.item_name)

    -- Check cooldown
    local current_time = os.clock()
    if current_time - last_item_use < ITEM_COOLDOWN then
        common.debugf('[Item] On cooldown, %.1f seconds remaining', ITEM_COOLDOWN - (current_time - last_item_use))
        return nil
    end

    -- Check inventory
    local count = get_item_count(entry.item_name)
    if not count or count == 0 then
        common.debugf('[Item] No %s in inventory', entry.item_name)
        return nil
    end

    common.debugf('[Item] Using %s to remove %s', entry.item_name, entry.debuff_name)
    last_item_use = current_time

    return {
        command     = string.format('/item "%s" <me>', entry.item_name),
        description = string.format('Using %s to remove %s', entry.item_name, entry.debuff_name),
    }
end

-- Execute item action check
-- Args:
--   settings (table) - Addon settings
--   job_def (table) - Job definition
--   main_level (number) - Player's main job level
--   sub_level (number) - Player's sub job level
--   player_resource (number) - Player's current MP or TP
-- Returns: table {command, description} or nil
function item.execute(settings, job_def, main_level, sub_level, player_resource)
    for _, entry in ipairs(ITEM_REMOVALS) do
        local result = try_item_removal(entry, settings)
        if result then return result end
    end
    return nil
end

-- Export get_item_count for UI to use
item.get_item_count = get_item_count

return item
