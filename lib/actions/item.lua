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
        return nil  -- Return nil when resource manager fails (during zoning)
    end
    
    local ok_inv, inventory = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    
    if not ok_inv or not inventory then
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
        return nil
    end
    
    return total_count
end

-- Stat-down family Panacea clears (the >=128 tail of ERASABLE_DEBUFFS: Defense
-- Down, Magic Def Down, base-stat downs, etc). Excludes Amnesia -- Panacea only
-- "potentially" removes it, so firing on it risks looping the item stack.
local PANACEA_DEBUFFS = {128, 129, 130, 131, 134, 135, 136, 137, 138, 139, 140,
    141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 404}

-- Item removal definitions, ordered by priority. Dedicated single-cures come
-- first so a cheap item wins over a premium multi-cure (e.g. Antidote before
-- Remedy for Poison). buff_ids lists every status the item reliably removes;
-- unreliable ("potentially") cures are omitted to avoid burning the stack on a
-- debuff the item won't clear.
local ITEM_REMOVALS = {
    { setting_key = 'item_antidote_enabled',        item_name = 'Antidote',        debuff_name = 'Poison',         buff_ids = {3} },
    { setting_key = 'item_eye_drops_enabled',       item_name = 'Eye Drops',       debuff_name = 'Blindness',      buff_ids = {5} },
    { setting_key = 'item_echo_drops_enabled',      item_name = 'Echo Drops',      debuff_name = 'Silence',        buff_ids = {6} },
    { setting_key = 'item_holy_water_enabled',      item_name = 'Holy Water',      debuff_name = 'Curse',          buff_ids = common.CURSE_DEBUFFS },
    { setting_key = 'item_hallowed_water_enabled',  item_name = 'Hallowed Water',  debuff_name = 'Curse',          buff_ids = common.CURSE_DEBUFFS },
    { setting_key = 'item_tincture_enabled',        item_name = 'Tincture',        debuff_name = 'Plague/Disease', buff_ids = {31, 8} },
    { setting_key = 'item_remedy_ointment_enabled', item_name = 'Remedy Ointment', debuff_name = 'status ailments',buff_ids = {3, 4, 5, 6} },
    { setting_key = 'item_remedy_enabled',          item_name = 'Remedy',          debuff_name = 'status ailments',buff_ids = {3, 4, 5, 6} },
    { setting_key = 'item_panacea_enabled',         item_name = 'Panacea',         debuff_name = 'stat downs',     buff_ids = PANACEA_DEBUFFS },
}

-- True if the player has any of the listed status ids.
local function has_any_buff(buff_ids)
    for _, id in ipairs(buff_ids) do
        if common.has_buff(0, id) then return true end
    end
    return false
end

-- Try a single item-removal entry; returns {command, description} or nil
local function try_item_removal(entry, settings)
    if not (settings and settings[entry.setting_key]) then return nil end

    if not has_any_buff(entry.buff_ids) then
        return nil
    end

    -- Check cooldown
    local current_time = os.clock()
    if current_time - last_item_use < ITEM_COOLDOWN then
        return nil
    end

    -- Check inventory
    local count = get_item_count(entry.item_name)
    if not count or count == 0 then
        return nil
    end
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
    if not (settings and settings.item_removal_enabled) then return nil end

    -- Items, like spells, can't be used while moving.
    if common.is_player_moving() then return nil end

    for _, entry in ipairs(ITEM_REMOVALS) do
        local result = try_item_removal(entry, settings)
        if result then return result end
    end
    return nil
end

-- Export get_item_count for UI to use
item.get_item_count = get_item_count

-- Export removal definitions so the config UI can render one checkbox per item.
item.REMOVALS = ITEM_REMOVALS

return item
