--[[
    Common utilities for Medic automation framework
    Shared across all jobs: party management, buffs, targeting, logging
]]--

local common = {}
local chat = require('chat')
local targets = require('lib.core.targets')

-- Export targets module for direct access
common.targets = targets

-- Ashita API references
local ashita = ashita or {}
local AshitaCore = AshitaCore

-- Debug flag
common.debug = false

-- Addon name for header
local addon_name = 'Medic'

-- Casting state tracking (packet-based)
local casting_state = {
    is_casting = false,
    last_action_time = 0,
    cast_timeout = 5.0,  -- Maximum time for a cast (seconds)
}

-- Movement tracking state
local movement_state = {
    last_position = {0, 0, 0},
    last_check = 0,
    is_moving = false,
    check_interval = 0.25  -- Check every 250ms
}

-- Resting state tracking
local is_resting = false

-- Mount state tracking
local is_mounted = false

-- Dead state tracking
local is_dead = false

-- Rest conditions timer (shared so other modules can reset it)
-- Holds the os.clock() timestamp when rest conditions first became favorable (0 = not started)
local rest_conditions_met_time = 0

-- Cached max HP/MP per member (server_id -> {max_hp, max_mp})
-- Updated only when the member is observed at 100% HP or MP, since GetMemberMaxHP/GetMemberMaxMP do not exist.
local member_max_stats = {}

-- Trust buff tracking (packet-based since memory reads don't work for Trusts)
local trust_buffs = {}  -- trust_buffs[server_id] = {buff_id1, buff_id2, ...}

-- Alliance member server_id set — rebuilt each refresh_game_state tick.
-- Used by packet handlers to decide whether to track buffs for a given server_id.
local alliance_member_sids = {}  -- alliance_member_sids[server_id] = true
local pending_buffs = {}  -- pending_buffs[n] = {server_id=x, buff_id=y, timestamp=t}
local PENDING_BUFF_TIMEOUT = 10.0  -- Seconds before pending buff expires

-- Tracked targets (session-only, not saved to settings)
-- Players outside the party that we monitor for heal/buff/status_removal automation.
-- tracked_targets[server_id] = { server_id, name, target_index, main_level }
-- Buffs are tracked via trust_buffs (same packet-based system as Trusts).
-- Max HP is tracked via member_max_stats (same system as party members).
-- main_level is populated once the 0x0C9 check-response packet is received.
local tracked_targets = {}

-- Pending check requests: server_id -> timestamp (waiting for 0x0C9 response)
local pending_checks = {}
local PENDING_CHECK_TIMEOUT = 10.0

-- Pending raise flags: set when a 0x029 packet arrives for a dead target,
-- indicating the server rejected a raise spell because one is already pending.
-- Cleared in refresh_game_state when entity_status returns to non-dead.
local pending_raise_flags = {}  -- pending_raise_flags[server_id] = true

-- Average HP by level, averaged across all races/jobs in FFXI.
-- Used to estimate max HP for non-party tracked targets before they are seen at 100%.
local AVERAGE_HP_BY_LEVEL = {
    [1] = 70,   [2] = 86,   [3] = 101,  [4] = 117,  [5] = 133,
    [6] = 148,  [7] = 164,  [8] = 180,  [9] = 195,  [10] = 204,
    [11] = 227, [12] = 242, [13] = 258, [14] = 274, [15] = 289,
    [16] = 305, [17] = 321, [18] = 336, [19] = 352, [20] = 367,
    [21] = 382, [22] = 398, [23] = 414, [24] = 430, [25] = 445,
    [26] = 461, [27] = 477, [28] = 493, [29] = 508, [30] = 525,
    [31] = 540, [32] = 556, [33] = 572, [34] = 588, [35] = 603,
    [36] = 619, [37] = 635, [38] = 651, [39] = 665, [40] = 682,
    [41] = 697, [42] = 713, [43] = 729, [44] = 745, [45] = 760,
    [46] = 776, [47] = 792, [48] = 808, [49] = 823, [50] = 840,
    [51] = 855, [52] = 871, [53] = 887, [54] = 903, [55] = 918,
    [56] = 934, [57] = 950, [58] = 962, [59] = 979, [60] = 997,
    [61] = 1012, [62] = 1028, [63] = 1044, [64] = 1060, [65] = 1075,
    [66] = 1091, [67] = 1107, [68] = 1123, [69] = 1138, [70] = 1155,
    [71] = 1170, [72] = 1186, [73] = 1202, [74] = 1218, [75] = 1233,
}

-- Non-combat zone IDs (safe zones where combat is blocked)
local non_combat_zone_ids = {
    230, 231, 232, 233, -- San d'Oria
    234, 235, 236, 237, -- Bastok
    238, 239, 240, 241, 242, -- Windurst
    243, 244, 245, 246, -- Jeuno
    80, 87, 94, -- WotG Cities of the past (San d'Oria [S], Bastok [S], Windurst [S])
    48, 50, 53, -- Aht Urhgan cities/towns (Al Zahbi, Aht Urhgan Whitegate, Nashmau)
    26, 247, 248, 249, 250, 252, -- Other Towns (Tavnazian Safehold, Rabao, Selbina, Mhaura, Kazham, Norg)
    256, 257, -- Adoulin
    280, -- Mog Garden
    46, 47, -- Open sea routes
    220, 221, -- Ships bound for Selbina/Mhaura
    223, 224, 225, 226, -- Airships
    227, 228, -- Ships with Pirates (still safe zones)
    70, -- Chocobo Circuit
    251, -- Hall of the Gods
    284, -- Celennia Memorial Library
}

-- Helper function to get current zone ID
function common.get_zone_id()
    local ok, zone_id = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    end)
    if not ok or not zone_id then
        return 0
    end
    return zone_id
end

-- Helper function for distance calculation (public for use in other modules)
function common.calculate_distance(entity1, entity2)
    local ok_calc, distance = pcall(function()
        local dx = entity1.Movement.LocalPosition.X - entity2.Movement.LocalPosition.X
        local dy = entity1.Movement.LocalPosition.Y - entity2.Movement.LocalPosition.Y
        local dz = entity1.Movement.LocalPosition.Z - entity2.Movement.LocalPosition.Z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    
    if not ok_calc or not distance then
        return nil
    end
    
    return distance
end

--[[
    Logging Utilities
]]--

-- Shared log helper: formats message, applies chat style, and prints.
-- @param style_fn  chat.message | chat.error | chat.warning
-- @param prefix    optional string prepended to message (e.g. '[DEBUG] ')
-- @param fmt       format string
-- @param ...       format arguments
local function log(style_fn, prefix, fmt, ...)
    local args = {...}
    local msg = fmt
    if #args > 0 then
        local ok, result = pcall(string.format, fmt, ...)
        if ok then msg = result end
    end
    print(chat.header(addon_name) .. style_fn((prefix or '') .. msg))
end

function common.printf(fmt, ...)  log(chat.message, nil, fmt, ...) end
function common.errorf(fmt, ...)  log(chat.error,   nil, fmt, ...) end
function common.warnf(fmt, ...)   log(chat.warning, nil, fmt, ...) end

function common.debugf(fmt, ...)
    if common.debug then log(chat.message, '[DEBUG] ', fmt, ...) end
end

--[[
    Player Status Checking
]]--

function common.is_idle()
    -- Idle == not in combat (exact inverse of is_combat, error paths included).
    return not common.is_combat()
end

function common.is_combat()
    local ok, bt = pcall(function()
        return targets.get_bt()
    end)
    
    if not ok then
        return false  -- Assume not in combat if we can't get battle target
    end
    
    -- Check if battle target is a mob (0x10 flag in SpawnFlags)
    local is_mob = bt and bit.band(bt.SpawnFlags, 0x10) ~= 0 or false
    
    return is_mob
end

-- Returns true if the given ability should be gated to combat-only based on user settings.
-- Grouped abilities use a per-group setting (combat_only_group_<group>);
-- ungrouped abilities use a per-name setting (combat_only_<ability_name_with_spaces_replaced_by_underscores>).
-- Defaults to false (allowed outside of combat).
-- Abilities marked idle_only never participate in the combat_only gate.
-- <bt> abilities (e.g. Geo-bt debuffs) target the battle target and are
-- INHERENTLY combat-only -- there is no valid target outside combat -- so they
-- always return true regardless of (and independent of) the user setting.
function common.is_ability_combat_only(ability, settings)
    if not ability then return false end
    if ability.idle_only then return false end
    if common.ability_targets_bt(ability) then return true end
    if not settings then return false end
    local key
    if ability.group then
        key = 'combat_only_group_' .. ability.group
    else
        if not ability.name then return false end
        key = 'combat_only_' .. ability.name:gsub(' ', '_')
    end
    return settings[key] == true
end

-- Returns true if the ability's command targets the battle target (<bt>).
-- These abilities cannot be cast without a valid mob battle target.
function common.ability_targets_bt(ability)
    if not ability or type(ability.command) ~= 'string' then return false end
    return ability.command:find('<bt>', 1, true) ~= nil
end

function common.is_engaged()
    local ok, player_entity = pcall(function()
        return GetPlayerEntity()
    end)
    
    if not ok or not player_entity then
        return false
    end
    
    local ok_status, status = pcall(function()
        return player_entity.Status
    end)
    
    if not ok_status or not status then
        return false
    end
    
    return status == 1
end

function common.can_attack()
    -- Get current zone
    local zone_id = common.get_zone_id()
    if zone_id == 0 then
        return false
    end
    
    -- Check if zone is in non-combat list
    for _, safe_zone_id in ipairs(non_combat_zone_ids) do
        if zone_id == safe_zone_id then
            return false
        end
    end
    
    -- Event system pointer (code from Thorny)
    local pEventSystem = ashita.memory.find('FFXiMain.dll', 0, "A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3", 0, 0)

    -- Check if event system is currently active (cutscene, dialog, etc.)
    if pEventSystem ~= 0 then
        local ptr = ashita.memory.read_uint32(pEventSystem + 1)
        if ptr ~= 0 and ashita.memory.read_uint8(ptr) == 1 then
            return false  -- Cannot attack during events
        end
    end
    
    return true
end

function common.is_casting()
    -- Returns true when player is casting a spell
    -- State is tracked via packet 0x028 offset 0x0F:
    --   0x00 = casting started
    --   0x02 = casting complete
    -- Prevents automation from spamming actions during cast time
    
    -- Timeout check: if too much time has passed, clear the casting state
    if casting_state.is_casting then
        local elapsed = os.clock() - casting_state.last_action_time
        if elapsed > casting_state.cast_timeout then
            common.debugf('[Casting] Timeout after %.1fs, clearing stuck casting state', elapsed)
            casting_state.is_casting = false
            return false
        end
    end
    
    return casting_state.is_casting
end

-- Handle action packet for casting detection
-- Args: packet (string) - Raw packet data
-- This should be called from the main addon's packet handler
function common.handle_action_packet(packet)
    if not packet or #packet < 16 then return end
    
    -- Parse actor ID (offset 0x05, 4 bytes)
    local actor_id = struct.unpack('I', packet, 0x05 + 1)
    
    -- Get player's server ID
    local party = common.get_party()
    if not party then return end
    
    local player_id = party:GetMemberServerId(0)
    
    if not player_id or actor_id ~= player_id then
        return  -- Not player's action
    end
    
    -- Parse category (offset 0x04, 1 byte)
    local category = struct.unpack('B', packet, 0x04 + 1)
    
    -- Parse action state byte (offset 0x0F, 1 byte)
    -- 0x00 = Action/Casting started
    -- 0x01-0x04 = Action/Casting complete (various completion states)
    local action_state = 0
    if #packet >= 16 then
        action_state = struct.unpack('B', packet, 0x0F + 1)
    end
    
    -- Parse action ID if available (offset 0x0A, 2 bytes)
    local action_id = 0
    if #packet >= 12 then
        action_id = struct.unpack('H', packet, 0x0A + 1)
    end
    
    -- Track previous casting state to detect changes
    local was_casting = casting_state.is_casting
    
    -- Simplified casting state logic based on action_state byte (offset 0x0F)
    -- 0x00 = Action started (casting/channeling)
    -- 0x01-0x04 = Action complete (various completion types)
    -- Note: ActionID changes between start (0x58E0) and completion (spell ID), so we can't rely on it
    
    -- Autoattack check (should not affect casting state)
    local is_autoattack = (action_id == 0x1844)
    
    if not is_autoattack then
        -- Only track casting state for actual spell casts (category 4 = magic).
        -- Job abilities (6), weapon skills (7/11), item usage (9), etc. are
        -- instant and should NOT engage the casting lock — they may never send
        -- a completion packet, causing the lock to stick until the 5s timeout.
        local is_spell_cast = (category == 4)

        if is_spell_cast then
            if action_state == 0x00 then
                -- Spell casting started
                casting_state.is_casting = true
                casting_state.last_action_time = os.clock()
                -- Clear resting state when we start casting
                is_resting = false
            elseif action_state > 0x00 then
                -- Spell casting complete
                casting_state.is_casting = false
            end
        else
            -- Non-spell action (JA, WS, etc.) — always clear the casting lock
            -- in case a previous spell's completion packet was missed.
            if casting_state.is_casting then
                common.debugf('[CASTING] Cleared by non-spell action (category %d)', category)
            end
            casting_state.is_casting = false
            -- Clear resting state for JA usage as well
            if action_state == 0x00 then
                is_resting = false
            end
        end
    end
    
    -- Output state change messages
    if casting_state.is_casting and not was_casting then
        common.debugf('[CASTING STARTED] State: 0x%02X, Category: %d, ActionID: 0x%04X', action_state, category, action_id)
    elseif not casting_state.is_casting and was_casting then
        common.debugf('[CASTING ENDED] State: 0x%02X, Category: %d, ActionID: 0x%04X', action_state, category, action_id)
    end
end

function common.is_player_moving()
    -- Check if player is currently moving (for magic casting restrictions)
    -- Returns true if player has moved since last check
    if os.clock() - movement_state.last_check < movement_state.check_interval then
        return movement_state.is_moving
    end
    
    movement_state.last_check = os.clock()

    local entity_mgr = common.get_entity_manager()
    local party = common.get_party()
    if not entity_mgr or not party then
        return movement_state.is_moving
    end
    
    local player_index = party:GetMemberTargetIndex(0)
    if not player_index or player_index == 0 then
        return movement_state.is_moving
    end
    
    -- Get current position (with error handling)
    local ok, x, y, z = pcall(function()
        return entity_mgr:GetLocalPositionX(player_index),
               entity_mgr:GetLocalPositionY(player_index),
               entity_mgr:GetLocalPositionZ(player_index)
    end)
    
    if not ok then
        return movement_state.is_moving
    end
    
    -- Compare with last known position
    local last_pos = movement_state.last_position
    movement_state.is_moving = (x ~= last_pos[1] or y ~= last_pos[2] or z ~= last_pos[3])

    -- Update last known position
    movement_state.last_position = {x, y, z}
    
    return movement_state.is_moving
end

function common.get_player_level()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if not player then return 0, 0 end
    local main_level = player:GetMainJobLevel()
    local sub_level = player:GetSubJobLevel()
    return main_level, sub_level
end

function common.get_player_job()
    -- Use Party manager like JobBinds does for better packet sync
    local party = common.get_party()
    if not party then return 0, 0 end
    local ok, job = pcall(function() return party:GetMemberMainJob(0) end)
    if not ok or not job then return 0, 0 end
    local ok_sub, subjob = pcall(function() return party:GetMemberSubJob(0) end)
    if not ok_sub or not subjob then subjob = 0 end
    return job, subjob
end

-- Job data mappings (single source of truth)
local job_data = {
    {id = 1,  abbr = 'WAR', name = 'Warrior'},
    {id = 2,  abbr = 'MNK', name = 'Monk'},
    {id = 3,  abbr = 'WHM', name = 'White Mage'},
    {id = 4,  abbr = 'BLM', name = 'Black Mage'},
    {id = 5,  abbr = 'RDM', name = 'Red Mage'},
    {id = 6,  abbr = 'THF', name = 'Thief'},
    {id = 7,  abbr = 'PLD', name = 'Paladin'},
    {id = 8,  abbr = 'DRK', name = 'Dark Knight'},
    {id = 9,  abbr = 'BST', name = 'Beastmaster'},
    {id = 10, abbr = 'BRD', name = 'Bard'},
    {id = 11, abbr = 'RNG', name = 'Ranger'},
    {id = 12, abbr = 'SAM', name = 'Samurai'},
    {id = 13, abbr = 'NIN', name = 'Ninja'},
    {id = 14, abbr = 'DRG', name = 'Dragoon'},
    {id = 15, abbr = 'SMN', name = 'Summoner'},
    {id = 16, abbr = 'BLU', name = 'Blue Mage'},
    {id = 17, abbr = 'COR', name = 'Corsair'},
    {id = 18, abbr = 'PUP', name = 'Puppetmaster'},
    {id = 19, abbr = 'DNC', name = 'Dancer'},
    {id = 20, abbr = 'SCH', name = 'Scholar'},
    {id = 21, abbr = 'GEO', name = 'Geomancer'},
    {id = 22, abbr = 'RUN', name = 'Rune Fencer'}
}

-- Get full job name from ID
function common.get_job_name_from_id(job_id)
    if not job_id then return 'Unknown' end
    for _, job in ipairs(job_data) do
        if job.id == job_id then
            return job.name
        end
    end
    return 'Unknown'
end

function common.get_job_name(job_id)
    -- Try to get full job name first from our data
    local name = common.get_job_name_from_id(job_id)
    if name ~= 'Unknown' then
        return name
    end
    
    -- Fallback to resource manager
    local ok, res_name = pcall(function() 
        return AshitaCore:GetResourceManager():GetString('jobs.names', job_id) 
    end)
    if ok and res_name then
        return res_name
    end
    
    -- Fallback to abbreviated name if full name not available
    ok, res_name = pcall(function() 
        return AshitaCore:GetResourceManager():GetString('jobs.names_abbr', job_id) 
    end)
    if ok and res_name then
        return res_name:upper()
    end
    
    return tostring(job_id)
end

-- Get pet entity
-- Returns: pet entity object or nil if no pet
function common.get_pet_entity()
    return targets.get_pet()
end

-- Get party manager
-- Returns: party object or nil on error
function common.get_party()
    local ok, party = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty()
    end)
    
    if not ok or not party then
        return nil
    end
    
    return party
end

-- Containers an equippable (armor) item can be worn from: main inventory (0)
-- plus all eight Mog Wardrobes (8, 10-16). Matches the client's equip-eligible
-- container set, so a "count" here reflects everything the player could equip.
local EQUIP_CONTAINERS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 }

-- Ashita's internal container id -> the container number the /equip command
-- expects (0 = Inventory, 1-8 = Mog Wardrobe 1-8).
local EQUIP_COMMAND_CONTAINER = { [0] = 0, [8] = 1, [10] = 2, [11] = 3, [12] = 4, [13] = 5, [14] = 6, [15] = 7, [16] = 8 }

-- Normalize an "ammo spec" to a set of item ids. A spec may be a single id, a
-- flat list of ids, or a list of { id=, name=, level= } tier entries.
local function ammo_id_set(spec)
    local set = {}
    if type(spec) ~= 'table' then
        if spec then set[spec] = true end
        return set
    end
    for _, e in ipairs(spec) do
        local id = type(e) == 'table' and e.id or e
        if id then set[id] = true end
    end
    return set
end

-- Count how many of the given items the player holds across every
-- equip-eligible container. spec may be a single id, a list of ids, or a list
-- of tier entries. Returns a total count (0 if none / inventory not loaded).
function common.count_equippable_items(spec)
    local ok_inv, inventory = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    if not ok_inv or not inventory then return 0 end

    local id_set = ammo_id_set(spec)

    local total = 0
    for _, container in ipairs(EQUIP_CONTAINERS) do
        local ok_max, max = pcall(function() return inventory:GetContainerCountMax(container) end)
        if ok_max and max then
            for i = 0, max do
                local entry = inventory:GetContainerItem(container, i)
                if entry and id_set[entry.Id] then
                    total = total + entry.Count
                end
            end
        end
    end
    return total
end

-- Return the item id equipped in the given equipment slot (0-indexed:
-- 0=main, 1=sub, 2=range, 3=ammo, ...), or nil if the slot is empty.
function common.get_equipped_item_id(slot)
    local ok_inv, inventory = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    if not ok_inv or not inventory then return nil end

    local eq = inventory:GetEquippedItem(slot)
    if not eq or not eq.Index or eq.Index == 0 then return nil end

    -- Index packs the source slot: high byte = container, low byte = slot index.
    local entry = inventory:GetContainerItem(math.floor(eq.Index / 256), eq.Index % 256)
    if not entry then return nil end
    local id = entry.Id
    if id == 0 or id == -1 or id == 65535 then return nil end
    return id
end

-- True when one of the spec's item ids is equipped in the ammo slot (slot 3).
function common.is_ammo_equipped(spec)
    local equipped = common.get_equipped_item_id(3)
    if not equipped then return false end
    return ammo_id_set(spec)[equipped] == true
end

-- Find the first owned item (matching the spec) across equip-eligible
-- containers. Returns container, item_id -- or nil if none owned.
function common.find_equippable_item(spec)
    local ok_inv, inventory = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    if not ok_inv or not inventory then return nil end

    local id_set = ammo_id_set(spec)
    for _, container in ipairs(EQUIP_CONTAINERS) do
        local ok_max, max = pcall(function() return inventory:GetContainerCountMax(container) end)
        if ok_max and max then
            for i = 0, max do
                local entry = inventory:GetContainerItem(container, i)
                if entry and entry.Count and entry.Count > 0 and id_set[entry.Id] then
                    return container, entry.Id
                end
            end
        end
    end
    return nil
end

-- Build a native "/equip ammo" command for the best ammo tier the player can
-- use and actually owns. spec must be a list of { id=, name=, level= } entries,
-- ordered worst -> best. Picks the highest-level entry with level <= player_level
-- (the main job level) that is owned, and names its container so the game equips
-- it straight from a wardrobe if needed. When several tiers share a level
-- (e.g. oils are all level 1), the later/better list entry wins.
-- Returns { command, description } or nil (own none / none level-eligible).
function common.select_ammo_equip_command(spec, player_level)
    if type(spec) ~= 'table' then return nil end
    local best, best_container
    for _, e in ipairs(spec) do
        if type(e) == 'table' and e.name and (e.level or 0) <= (player_level or 0) then
            local container = common.find_equippable_item(e.id)  -- nil if not owned
            if container and ((not best) or (e.level or 0) >= (best.level or 0)) then
                best, best_container = e, container
            end
        end
    end
    if not best then return nil end
    local equip_num = EQUIP_COMMAND_CONTAINER[best_container] or 0
    return {
        command     = string.format('/equip ammo "%s" %d', best.name, equip_num),
        description = string.format('Equipping %s', best.name),
    }
end

-- For the first enabled, level-eligible ability in `abilities` that needs a
-- consumable in the ammo slot (BST biscuit/poultice, PUP oil) and isn't wearing
-- one, return the /equip command for the best owned tier. nil when all are
-- already equipped, disabled, none owned, or not equippable on this job.
function common.ammo_equip_command(abilities, settings, player)
    for _, ability in ipairs(abilities or {}) do
        local spec = ability.requires_equipped_ammo
        if spec and not common.is_ammo_equipped(spec) then
            local disabled     = settings['disabled_' .. ability.name:gsub(' ', '_')] == true
            local usable_level = ability.is_main_job == false and (player.sub_level or 0) or (player.main_level or 0)
            -- Oils equip PUP-main only; biscuits/poultice equip on any job.
            local wrong_main   = ability.ammo_main_job_only and ability.is_main_job == false
            if not disabled and not wrong_main and (ability.level or 0) <= usable_level then
                local equip = common.select_ammo_equip_command(spec, player.main_level or 0)
                if equip then return equip end
            end
        end
    end
    return nil
end

-- Get entity manager
-- Returns: entity manager object or nil on error
function common.get_entity_manager()
    local ok, entity_mgr = pcall(function()
        return AshitaCore:GetMemoryManager():GetEntity()
    end)
    
    if not ok or not entity_mgr then
        return nil
    end
    
    return entity_mgr
end

-- Resolve a server ID to an entity name using fast index derivation.
-- Uses the same shortcut that parse_packets.GetIndexFromId does for NPCs/Trusts
-- (bit-mask on the lower 12 bits) and falls back to a party/tracked lookup,
-- avoiding a full O(2304) entity scan in the common case.
-- Args:   server_id (number) - Entity server ID
-- Returns: string - Entity name or 'Unknown'
function common.resolve_entity_name(server_id)
    if not server_id or server_id == 0 then return 'Unknown' end
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    if not entMgr then return 'Unknown' end

    -- Fast path for NPCs/Trusts (server_id has 0x1000000 bit set)
    if bit.band(server_id, 0x1000000) ~= 0 then
        local index = bit.band(server_id, 0xFFF)
        if index >= 0x900 then index = index - 0x100 end
        if index < 0x900 and entMgr:GetServerId(index) == server_id then
            local name = entMgr:GetName(index)
            if name and name ~= '' then return name end
        end
    end

    -- Try party members (indices are low, fast check)
    local party = common.get_party()
    if party then
        for i = 0, 5 do
            if party:GetMemberIsActive(i) == 1 and party:GetMemberServerId(i) == server_id then
                local ti = party:GetMemberTargetIndex(i)
                if ti and ti > 0 then
                    local name = entMgr:GetName(ti)
                    if name and name ~= '' then return name end
                end
            end
        end
    end

    -- Try tracked targets
    local tt = tracked_targets[server_id]
    if tt then
        if tt.name and tt.name ~= '' then return tt.name end
        if tt.target_index and tt.target_index > 0 then
            local name = entMgr:GetName(tt.target_index)
            if name and name ~= '' then return name end
        end
    end

    -- Fallback: full entity scan (rare, only for unknown entities)
    for idx = 1, 0x8FF do
        if entMgr:GetServerId(idx) == server_id then
            local name = entMgr:GetName(idx)
            if name and name ~= '' then return name end
            break
        end
    end

    return 'Unknown'
end

-- Get player's current target server ID
-- Returns: number (target server ID) or 0 if no target
function common.get_target_id()
    local target_entity = targets.get_t()
    if not target_entity then
        return 0
    end
    
    local server_id = target_entity.ServerId
    if not server_id or server_id == 0 then
        return 0
    end
    
    return server_id
end

-- Get array of party member server IDs
-- Returns: table of server IDs (numbers) for active party members
function common.get_party_server_ids()
    local party = common.get_party()
    if not party then
        return {}
    end
    
    local server_ids = {}
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            local server_id = party:GetMemberServerId(i)
            if server_id and server_id > 0 then
                table.insert(server_ids, server_id)
            end
        end
    end
    
    return server_ids
end

function common.get_party_size()
    local party = common.get_party()
    if not party then return 0 end
    
    local count = 0
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            count = count + 1
        end
    end
    return count
end

function common.is_party_member_active(index)
    local party = common.get_party()
    if not party then return false end
    return party:GetMemberIsActive(index) == 1
end

function common.get_party_member_name(index)
    local party = common.get_party()
    if not party then return nil end
    return party:GetMemberName(index)
end

function common.get_party_member_zone(index)
    local party = common.get_party()
    if not party then return nil end
    return party:GetMemberZone(index)
end

function common.get_party_index_by_name(name)
    -- Returns party index (0-5) for given character name, or nil if not found
    if not name then return nil end
    
    local party = common.get_party()
    if not party then return nil end
    
    -- Check all party slots (0=player, 1-5=party members)
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            local member_name = party:GetMemberName(i)
            if member_name == name then
                return i
            end
        end
    end
    
    return nil
end

function common.get_target_index_by_name(name)
    -- Returns entity target index for given character name, or nil if not found
    local party_index = common.get_party_index_by_name(name)
    if not party_index then return nil end
    
    local party = common.get_party()
    if not party then return nil end
    
    local target_index = party:GetMemberTargetIndex(party_index)
    if target_index and target_index > 0 then
        return target_index
    end
    
    return nil
end

-- Returns true if value is above zero and below threshold (i.e. alive/present but needs attention).
-- Consolidates the repeated pattern: value > 0 and value < threshold
function common.below_threshold(value, threshold)
    return value > 0 and value < threshold
end

-- Returns true if a member's HP% indicates they are alive and not at full health.
-- Used to skip dead (0%) and full-health (100%) members in party loops.
function common.is_active_member(hpp)
    return common.below_threshold(hpp, 100)
end

function common.is_in_range(target_index, range)
    -- Ensure range is a number
    local range_value = type(range) == 'number' and range or 21
    
    -- Get both entities
    local player_entity = targets.get_me()
    if not player_entity then
        return false
    end
    
    local target_entity = GetEntity(target_index)
    if not target_entity then
        return false
    end
    
    -- Calculate distance between player and target
    local distance = common.calculate_distance(player_entity, target_entity)
    return distance and distance <= range_value
end

-- Get distance between player and party member
-- Args: party_index (number) - Party member index (1-5)
-- Returns: number (distance in yalms) or nil if error
function common.get_party_member_distance(party_index)
    if not party_index or party_index < 1 or party_index > 5 then
        return nil
    end
    
    local player_entity = targets.get_me()
    if not player_entity then
        return nil
    end
    
    local party = common.get_party()
    if not party or not common.is_party_member_active(party_index) then
        return nil
    end
    
    local target_index = party:GetMemberTargetIndex(party_index)
    if not target_index or target_index == 0 then
        return nil
    end
    
    local member_entity = GetEntity(target_index)
    if not member_entity then
        return nil
    end

    return common.calculate_distance(player_entity, member_entity)
end

-- Get distance between a party member (0 = player) and the pet/luopan.
-- Used by Geo automation to measure luopan drift from the party member who
-- is holding the Geo bubble, rather than always from the caster.
-- Args: party_index (number) - Party member index (0-5)
-- Returns: number (distance in yalms) or nil if member or pet unavailable
function common.get_pet_distance_from_member(party_index)
    local pet_entity = targets.get_pet()
    if not pet_entity then
        return nil
    end

    -- Index 0 is the player: measure from the player's own entity.
    if party_index == 0 then
        local player_entity = targets.get_me()
        if not player_entity then return nil end
        return common.calculate_distance(player_entity, pet_entity)
    end

    if party_index < 1 or party_index > 5 then
        return nil
    end

    local party = common.get_party()
    if not party or not common.is_party_member_active(party_index) then
        return nil
    end

    local target_index = party:GetMemberTargetIndex(party_index)
    if not target_index or target_index == 0 then
        return nil
    end

    local member_entity = GetEntity(target_index)
    if not member_entity then
        return nil
    end

    return common.calculate_distance(member_entity, pet_entity)
end

--[[
    Buff/Debuff Checking
]]--

function common.has_buff(target_index, buff_id)
    if not target_index then return false end
    
    -- Special case: target_index 0 is the player - use the working get_player_buffs() method
    if target_index == 0 then
        local player_buffs = common.get_player_buffs()
        for _, player_buff in ipairs(player_buffs) do
            if player_buff == buff_id then
                return true
            end
        end
        return false
    end
    
    -- For other targets, use party member lookup
    local party = common.get_party()
    if not party then return false end
    
    -- Find party member index and server ID for this target
    local party_index = -1
    local server_id = nil
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            if party:GetMemberTargetIndex(i) == target_index then
                party_index = i
                local ok_server, sid = pcall(function()
                    return party:GetMemberServerId(i)
                end)
                if ok_server then
                    server_id = sid
                end
                break
            end
        end
    end
    
    if party_index == -1 then return false end
    
    -- Check if this is a Trust (server_id >= 0x1000000)
    if server_id and server_id >= 0x1000000 then
        -- Use Trust buff tracking
        local trust_buff_list = common.get_trust_buffs(server_id)
        for _, trust_buff in ipairs(trust_buff_list) do
            if trust_buff == buff_id then
                return true
            end
        end
        return false
    end
    
    -- For regular party members, check buffs via memory pointer
    local ok_ptr, ptr = pcall(function() return party:GetMemberPointer(party_index) end)
    if not ok_ptr or not ptr or ptr == 0 then return false end
    
    local buffs_ptr = ashita.memory.read_uint32(ptr + 0x0C)
    if buffs_ptr == 0 then return false end
    
    for i = 0, 31 do
        local buff = ashita.memory.read_uint16(buffs_ptr + (i * 2))
        if buff == buff_id then
            return true
        end
    end
    
    return false
end

function common.get_player_buffs()
    local ok, player = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer()
    end)
    
    if not ok or not player then
        return {}
    end
    
    local ok_buffs, buffs = pcall(function()
        return player:GetBuffs()
    end)
    
    if not ok_buffs or not buffs then
        return {}
    end
    
    -- Filter out invalid buffs (ID 255 or 0)
    local valid_buffs = {}
    for i = 1, 32 do
        local buff_id = buffs[i]
        if buff_id and buff_id ~= 255 and buff_id > 0 then
            table.insert(valid_buffs, buff_id)
        end
    end
    
    return valid_buffs
end

-- Get party member's current buffs using direct memory reading
-- Args: member_index (number) - Party member index (0-5, where 0 is player)
-- Returns: table of buff IDs (numbers), or empty table on error/trust
function common.get_party_buffs(member_index)
    -- Special case: p0 (player) uses different method
    if member_index == 0 then
        return common.get_player_buffs()
    end
    
    local party = common.get_party()
    if not party then
        return {}
    end
    
    -- Check if member is active
    local ok_active, is_active = pcall(function()
        return party:GetMemberIsActive(member_index)
    end)
    
    if not ok_active or is_active ~= 1 then
        return {}
    end
    
    -- Get the server ID for this party member
    local ok_server, server_id = pcall(function()
        return party:GetMemberServerId(member_index)
    end)
    
    if not ok_server or not server_id or server_id == 0 then
        return {}
    end
    
    -- Trusts have server IDs > 0x1000000 (16777216)
    if server_id >= 0x1000000 then
        -- Return Trust buffs from packet-based tracking
        return trust_buffs[server_id] or {}
    end
    
    -- Get the status icons pointer (direct memory reading)
    local ok_pointer, base_ptr = pcall(function()
        return AshitaCore:GetPointerManager():Get('party.statusicons')
    end)
    
    if not ok_pointer or not base_ptr or base_ptr == 0 then
        common.errorf('Failed to get party status icons pointer for member %d', member_index)
        return {}
    end
    
    -- Dereference the pointer
    local ok_deref, dereferenced_ptr = pcall(function()
        return ashita.memory.read_uint32(base_ptr)
    end)
    
    if not ok_deref or dereferenced_ptr == 0 then
        common.errorf('Failed to dereference status icons pointer')
        return {}
    end
    
    -- Scan through party members (indices 0-4 in memory, which map to p1-p5)
    for i = 0, 4 do
        local member_ptr = dereferenced_ptr + (0x30 * i)
        
        local ok_read, player_id = pcall(function()
            return ashita.memory.read_uint32(member_ptr)
        end)
        
        if ok_read and player_id == server_id then
            -- Found matching server_id, read buffs
            local buffs = {}
            
            -- Read all 32 buff slots using bit manipulation
            for j = 0, 31 do
                local ok_buff, high_bits = pcall(function()
                    return ashita.memory.read_uint8(member_ptr + 8 + math.floor(j / 4))
                end)
                
                if ok_buff then
                    local f_mod = math.fmod(j, 4) * 2
                    high_bits = bit.lshift(bit.band(bit.rshift(high_bits, f_mod), 0x03), 8)
                    
                    local ok_low, low_bits = pcall(function()
                        return ashita.memory.read_uint8(member_ptr + 16 + j)
                    end)
                    
                    if ok_low then
                        local buff_id = high_bits + low_bits
                        
                        if buff_id ~= 255 and buff_id > 0 then
                            table.insert(buffs, buff_id)
                        end
                    end
                end
            end
            
            return buffs
        end
    end
    
    return {}
end

--[[
    Trust Buff Tracking Functions
    Since Trusts' buffs cannot be read from memory, we track them via packets
]]--

-- Register a pending buff when we initiate a cast on a Trust
-- Args: server_id (number), buff_id (number)
function common.register_pending_buff(server_id, buff_id)
    if not server_id or not buff_id then return end
    
    -- Clean up expired pending buffs first
    local current_time = os.clock()
    local i = 1
    while i <= #pending_buffs do
        if (current_time - pending_buffs[i].timestamp) > PENDING_BUFF_TIMEOUT then
            table.remove(pending_buffs, i)
        else
            i = i + 1
        end
    end
    
    -- Add new pending buff
    table.insert(pending_buffs, {
        server_id = server_id,
        buff_id = buff_id,
        timestamp = current_time
    })
    
end

-- Handle casting completion (packet 0x028 with byte 0x0F == 0x01)
-- Matches the most recent pending buff and adds it to trust_buffs
function common.handle_buff_application()
    if #pending_buffs == 0 then return end

    -- Pop the most recent pending buff; apply_external_buff handles init + dedup.
    local pending = pending_buffs[#pending_buffs]
    table.remove(pending_buffs, #pending_buffs)
    common.apply_external_buff(pending.server_id, pending.buff_id)
end

-- Directly apply a buff to a Trust's tracked buff list (called from packet detection)
-- Args: server_id (number), buff_id (number)
function common.apply_trust_buff(server_id, buff_id)
    if not server_id or server_id < 0x1000000 then return end
    common.apply_external_buff(server_id, buff_id)
end

-- Handle buff removal (packet 0x029)
-- Args: server_id (number), buff_id (number)
function common.handle_buff_removal(server_id, buff_id)
    if not server_id or not buff_id then return end
    if not trust_buffs[server_id] then return end
    
    -- Remove buff from Trust's buff list
    for i = #trust_buffs[server_id], 1, -1 do
        if trust_buffs[server_id][i] == buff_id then
            table.remove(trust_buffs[server_id], i)
            break
        end
    end
    
    -- Clean up empty buff lists
    if #trust_buffs[server_id] == 0 then
        trust_buffs[server_id] = nil
    end
end

-- Clear all Trust buffs and alliance tracking (call on zone change)
function common.clear_trust_buffs()
    trust_buffs = {}
    pending_buffs = {}
    member_max_stats = {}
    alliance_member_sids = {}
    pending_raise_flags = {}
end

-- Set pending raise flag for a server_id (called from 0x029 handler when target is dead).
function common.set_pending_raise(server_id)
    if not server_id or server_id == 0 then return end
    pending_raise_flags[server_id] = true
end

-- Returns true if the given server_id has a pending raise flag set.
function common.has_pending_raise(server_id)
    if not server_id or server_id == 0 then return false end
    return pending_raise_flags[server_id] == true
end

-- Explicitly clear the pending raise flag for a server_id.
function common.clear_pending_raise(server_id)
    if not server_id or server_id == 0 then return end
    pending_raise_flags[server_id] = nil
end

-- Check if a server_id belongs to an active alliance member.
-- The set is rebuilt every refresh_game_state() tick.
function common.is_alliance_member(server_id)
    if not server_id or server_id == 0 then return false end
    return alliance_member_sids[server_id] == true
end

-- Shared helper: insert a buff into trust_buffs with dedup.
-- Used by both apply_alliance_member_buff and apply_tracked_target_buff.
function common.apply_external_buff(server_id, buff_id)
    if not server_id or not buff_id then return end

    if not trust_buffs[server_id] then
        trust_buffs[server_id] = {}
    end

    for _, existing in ipairs(trust_buffs[server_id]) do
        if existing == buff_id then return end
    end

    table.insert(trust_buffs[server_id], buff_id)
end

-- Apply a buff to an alliance member (packet-based, reuses trust_buffs table).
function common.apply_alliance_member_buff(server_id, buff_id)
    if not server_id or not buff_id then return end
    if not alliance_member_sids[server_id] then return end
    common.apply_external_buff(server_id, buff_id)
end

-- Get Trust buffs by server_id
-- Args: server_id (number)
-- Returns: table of buff IDs, or empty table
function common.get_trust_buffs(server_id)
    if not server_id then return {} end
    if server_id < 0x1000000 then return {} end  -- Not a Trust
    return trust_buffs[server_id] or {}
end

-- ============================================================================
-- Tracked Target Functions (session-only, outside-party players)
-- ============================================================================

-- Add a tracked target by entity.
-- Args: entity (userdata) - The entity to track (must be a PC with SpawnFlags & 0x0001)
-- Returns: boolean - true if added, false if already tracked or invalid
function common.add_tracked_target(entity)
    if not entity then return false end

    local server_id = entity.ServerId
    local name      = entity.Name
    if not server_id or server_id == 0 or not name or name == '' then
        return false
    end

    -- Reject if already tracked
    if tracked_targets[server_id] then
        return false
    end

    -- Reject if the target is already in our party
    local party = common.get_party()
    if party then
        for i = 0, 5 do
            if party:GetMemberIsActive(i) == 1 then
                local pid = party:GetMemberServerId(i)
                if pid == server_id then
                    return false
                end
            end
        end
    end

    tracked_targets[server_id] = {
        server_id    = server_id,
        name         = name,
        target_index = entity.TargetIndex or 0,
        main_job     = nil,
        sub_job      = nil,
        main_level   = nil,
        sub_level    = nil,
    }

    pending_checks[server_id] = os.clock()
    AshitaCore:GetChatManager():QueueCommand(1, string.format('/check %s', name))

    common.printf('Now tracking: %s (checking level...)', name)
    return true
end

-- Handle incoming packet 0x0C9 (character check response).
-- Sub-type byte at 0x00A: 0x03 = first packet (no data), 0x01 = second packet (has data).
-- Layout of the data packet:
--   0x022  main_job  (uint8)
--   0x023  sub_job   (uint8)
--   0x024  main_level (uint8)
--   0x025  sub_level  (uint8)
function common.handle_check_packet(packet)
    if not packet or #packet < 0x26 then return end

    local sub_type = struct.unpack('B', packet, 0x0A + 1)
    if sub_type ~= 0x01 then return end

    local main_job  = struct.unpack('B', packet, 0x022 + 1)
    local sub_job   = struct.unpack('B', packet, 0x023 + 1)
    local main_level = struct.unpack('B', packet, 0x024 + 1)
    local sub_level  = struct.unpack('B', packet, 0x025 + 1)
    if not main_level or main_level == 0 then return end

    local now = os.clock()
    for sid, timestamp in pairs(pending_checks) do
        if (now - timestamp) > PENDING_CHECK_TIMEOUT then
            pending_checks[sid] = nil
        elseif tracked_targets[sid] then
            tracked_targets[sid].main_job   = (main_job  and main_job  > 0) and main_job  or nil
            tracked_targets[sid].sub_job    = (sub_job   and sub_job   > 0) and sub_job   or nil
            tracked_targets[sid].main_level = main_level
            tracked_targets[sid].sub_level  = (sub_level and sub_level > 0) and sub_level or nil
            pending_checks[sid] = nil
            common.debugf('[Check] %s resolved: job=%d/%d lv=%d/%d',
                tracked_targets[sid].name,
                main_job or 0, sub_job or 0, main_level, sub_level or 0)
            return
        end
    end
end

-- Remove a tracked target by server_id.
function common.remove_tracked_target(server_id)
    if not server_id then return end
    if tracked_targets[server_id] then
        local name = tracked_targets[server_id].name
        tracked_targets[server_id] = nil
        -- Also clean buff tracking for this target
        trust_buffs[server_id] = nil
        member_max_stats[server_id] = nil
        common.printf('Stopped tracking: %s', name or tostring(server_id))
    end
end

-- Remove a tracked target by name.
function common.remove_tracked_target_by_name(name)
    if not name then return end
    for sid, tt in pairs(tracked_targets) do
        if tt.name == name then
            common.remove_tracked_target(sid)
            return
        end
    end
end

-- Clear all tracked targets (e.g., on zone change).
function common.clear_tracked_targets()
    for sid, _ in pairs(tracked_targets) do
        trust_buffs[sid] = nil
    end
    tracked_targets = {}
end

-- Get the tracked targets table (read-only reference).
function common.get_tracked_targets()
    return tracked_targets
end

-- Get tracked target buffs (uses trust_buffs since we track via packets).
function common.get_tracked_target_buffs(server_id)
    if not server_id then return {} end
    return trust_buffs[server_id] or {}
end

-- Apply a buff to a tracked target (packet-based, reuses trust_buffs table).
function common.apply_tracked_target_buff(server_id, buff_id)
    if not server_id or not buff_id then return end
    if not tracked_targets[server_id] then return end
    common.apply_external_buff(server_id, buff_id)
end

-- Check if a server_id belongs to a tracked target.
function common.is_tracked_target(server_id)
    if not server_id then return false end
    return tracked_targets[server_id] ~= nil
end

--[[
    Debug: Show all recast timers
]]--

function common.show_recast_timers()
    common.printf('=== Recast Timer Debug ===')
    
    local recast_mgr = AshitaCore:GetMemoryManager():GetRecast()
    if not recast_mgr then
        common.errorf('Failed to get recast manager')
        return
    end
    
    -- Show Job Ability Recasts
    common.printf('Job Ability Recast Timers (slots 0-31):')
    local ability_count = 0
    for i = 0, 31 do
        local ok_id, timer_id = pcall(function()
            return recast_mgr:GetAbilityTimerId(i)
        end)
        
        local ok_timer, timer = pcall(function()
            return recast_mgr:GetAbilityTimer(i)
        end)
        
        if ok_id and ok_timer and timer_id and timer_id > 0 and timer and timer > 0 then
            local recast_seconds = timer / 60.0
            common.printf('  Slot[%d]: TimerID=%d, RawTimer=%d, Recast=%.1fs', 
                i, timer_id, timer, recast_seconds)
            ability_count = ability_count + 1
        end
    end
    
    if ability_count == 0 then
        common.printf('  (No active ability recasts)')
    end
    
    -- Show Spell Recasts
    common.printf('Spell Recast Timers (IDs 0-1023):')
    local spell_count = 0
    for spell_id = 0, 1023 do
        local ok_timer, timer = pcall(function()
            return recast_mgr:GetSpellTimer(spell_id)
        end)
        
        if ok_timer and timer and timer > 0 then
            local recast_seconds = timer / 60.0
            common.printf('  SpellID=%d, RawTimer=%d, Recast=%.1fs', 
                spell_id, timer, recast_seconds)
            spell_count = spell_count + 1
        end
    end
    
    if spell_count == 0 then
        common.printf('  (No active spell recasts)')
    end
    
    common.printf('==========================')
end

--[[
    Status Ailment Blocking Checks
]]--

-- Check if player has Amnesia (blocks Job Abilities)
-- Returns: boolean
function common.has_amnesia()
    return common.has_buff(0, 16)  -- Amnesia buff_id = 16
end

-- Check if player has Silence (blocks Magic)
-- Returns: boolean
function common.has_silence()
    return common.has_buff(0, 6)  -- Silence buff_id = 6
end

-- Check if a command is blocked by status ailments
-- Args:
--   command (string or function) - Command string or function that generates one
-- Returns: string or nil - Name of blocking status ailment, or nil if not blocked
function common.is_command_blocked(command)
    -- Get command string if it's a function
    local command_str = command
    if type(command) == 'function' then
        -- Call with dummy parameter to get command string
        command_str = command(0)
    end
    
    if not command_str or type(command_str) ~= 'string' then
        return nil  -- Can't determine, assume not blocked
    end
    
    -- Check command type
    if command_str:match('^/ma ') then
        -- Magic command - blocked by Silence
        if common.has_silence() then
            return 'Silence'
        end
        
        -- Magic command - blocked by movement (can only cast while stationary)
        if common.is_player_moving() then
            return 'Moving'
        end
    elseif command_str:match('^/ja ') then
        -- Job Ability command - blocked by Amnesia
        if common.has_amnesia() then
            return 'Amnesia'
        end
    end
    
    return nil  -- Not blocked
end

--[[
    DRY Helper Functions for Action Modules
]]--

-- Check if a spell ability has been learned by the player.
-- For non-spell abilities (job abilities, items), always returns true.
-- Args:   ability (table) - Ability definition with command and optional id fields
-- Returns: boolean (true if the ability can be used / spell is known)
function common.has_spell_learned(ability)
    if not ability then return false end
    local cmd = type(ability.command) == 'function' and ability.command(0) or ability.command
    if not cmd or not cmd:match('^/ma%s') then return true end    -- not a spell
    if not ability.id then return true end                        -- no id to check
    local ok, known = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id)
    end)
    if not ok then return true end  -- assume known on error
    return known
end

-- Filter abilities by level, disabled status, and pet requirements
-- Args:
--   abilities (table) - List of abilities to filter
--   settings (table) - Settings table with disabled flags
--   main_level (number) - Player's main job level
--   sub_level (number) - Player's sub job level
--   job_def (table|nil) - Job definition with optional validate_ability function
-- Returns: table - Filtered and sorted abilities (by cost descending)
function common.filter_abilities_by_level(abilities, settings, main_level, sub_level, job_def)
    local available_abilities = {}
    
    -- Safety check: return empty table if abilities is nil
    if not abilities then
        return available_abilities
    end

    for _, ability in ipairs(abilities) do
        -- Safely get level value
        local required_level = 0
        if type(ability.level) == 'number' then
            required_level = ability.level
        elseif type(ability.level) == 'function' then
            common.errorf('[filter_abilities] ERROR: ability.level is a function for %s!', ability.name)
            goto continue
        end
        
        -- Determine which level to check based on ability source
        local player_level = ability.is_main_job == false and (sub_level or 0) or (main_level or 0)
        local job_source = ability.is_main_job == false and 'subjob' or 'main job'

        -- Check if ability requires main job only (e.g., Geo spells)
        if ability.main_job_only and ability.is_main_job == false then
            -- Skip main-job-only abilities when from subjob
            goto continue
        end
        
        -- Check if ability is disabled in settings
        local disabled_key
        if ability.group then
            disabled_key = 'disabled_group_' .. ability.group
        else
            disabled_key = 'disabled_' .. ability.name:gsub(' ', '_')
        end
        -- Default to enabled (false) if key doesn't exist (nil)
        local is_disabled = settings[disabled_key]
        if is_disabled == nil then
            is_disabled = false  -- Default new abilities to enabled
        end
        
        if is_disabled then
        elseif ability.requires_pet and not targets.get_pet() then
        elseif ability.requires_equipped_ammo and not common.is_ammo_equipped(ability.requires_equipped_ammo) then
        elseif ability.idle_only and not common.is_idle() then
        elseif common.is_ability_combat_only(ability, settings) and not common.is_combat() then
        elseif common.ability_targets_bt(ability) and not common.is_combat() then
        elseif job_def and job_def.validate_ability and not job_def.validate_ability(ability, common) then
        elseif required_level <= player_level then
            table.insert(available_abilities, ability)
        end
        
        ::continue::
    end
    
    -- Sort by cost descending (higher cost = stronger/better)
    table.sort(available_abilities, function(a, b)
        local a_cost = type(a.cost) == 'number' and a.cost or 0
        local b_cost = type(b.cost) == 'number' and b.cost or 0
        return a_cost > b_cost
    end)
    
    return available_abilities
end

-- Build command string from ability definition
-- Args:
--   ability (table) - Ability definition with command field
--   party_index (number|nil) - party index 0-5 for p0-p5
-- Returns: string - Command string or nil
function common.build_ability_command(ability, party_index)
    local command = nil
    
    if type(ability.command) == 'function' then
        -- If party_index is provided, convert party index (0-5) to server ID
        if party_index ~= nil then
            local party = common.get_party()
            if party then
                -- Convert party index to server ID
                local server_id = party:GetMemberServerId(party_index)
                if server_id and server_id > 0 then
                    command = ability.command(server_id)
                end
            end
        end
    elseif type(ability.command) == 'string' then
        command = ability.command
    end
    
    return command
end

-- Build command for tracked targets (outside-party) using server_id directly.
-- Args:
--   ability (table) - Ability definition with command field
--   server_id (number) - Server ID of the tracked target
-- Returns: string - Command string or nil
function common.build_ability_command_for_target(ability, server_id)
    if not ability or not server_id or server_id == 0 then return nil end

    if type(ability.command) == 'function' then
        return ability.command(server_id)
    elseif type(ability.command) == 'string' then
        return ability.command
    end

    return nil
end

-- ============================================================================
-- Target Modifier Management (Pianissimo, Entrust, etc.)
-- ============================================================================

-- Check if target modifier ability (like Pianissimo or Entrust) is needed
-- and return command to use it if necessary
-- Args:
--   job_def (table) - Job definition containing abilities
--   settings (table) - Addon settings
--   main_level (number) - Main job level
--   sub_level (number) - Sub job level
-- Returns: table|nil - {command, description} if modifier needs to be used, nil otherwise
function common.check_target_modifier(job_def, settings, main_level, sub_level)
    -- Check if job has target_modifier abilities defined
    if not job_def.abilities.target_modifier or #job_def.abilities.target_modifier == 0 then
        return nil
    end
    
    -- Get the first (and typically only) target modifier ability
    local modifier_ability = job_def.abilities.target_modifier[1]
    
    -- Check if we already have the modifier buff active
    if common.has_buff(0, modifier_ability.buff_id) then
        -- We have the buff, ready to cast the modified spell/song
        return nil
    end
    
    -- We don't have the buff, check if we can use the modifier ability
    -- Determine the appropriate player level to use for gating
    local player_level = main_level
    if modifier_ability.is_main_job == false then
        player_level = sub_level or main_level
    end

    -- Check level requirement
    if modifier_ability.level and modifier_ability.level > player_level then
        return nil
    end
    
    -- Check if ability is disabled in settings
    local key = 'disabled_' .. modifier_ability.name:gsub(' ', '_')
    if settings[key] == true then
        return nil
    end
    
    -- Check combat_only flag (user-driven via settings)
    if common.is_ability_combat_only(modifier_ability, settings) and not common.is_combat() then
        return nil
    end
    
    -- Check if blocked by status ailments
    local blocked_by = common.is_command_blocked(modifier_ability.command)
    if blocked_by then
        return nil
    end
    
    -- Check resource cost
    local action_core = require('lib.core.action_core')
    if not action_core.has_resource(job_def.resource_type, modifier_ability.cost or 0) then
        return nil
    end
    
    -- Check cooldown if ability has an ID
    if modifier_ability.id then
        local is_ready = action_core.is_ability_ready(modifier_ability.id)
        if not is_ready then
            return nil
        end
    end
    
    -- Build and return the command
    local command = common.build_ability_command(modifier_ability, 0)
    if command then
        return {
            command = command,
            description = string.format('Using %s for party targeting', modifier_ability.name)
        }
    end
    
    return nil
end

-- ============================================================================
-- Scholar Stratagem Pre-Cast Management
-- ============================================================================

-- Calculate the effective MP cost of an ability considering assigned stratagems.
-- When stratagems with mp_modifier are assigned (e.g. Penury 0.5x, Accession 3.0x),
-- the base cost is multiplied by all assigned modifiers.
-- Checks both ability.name and ability.group as lookup keys (the UI stores stratagem
-- assignments under the group name for grouped abilities like Protect/Shell).
-- Args:
--   ability  (table)  – ability definition with .name, .cost, and optionally .group
--   settings (table)  – addon settings (contains stratagem_settings)
--   job_def  (table)  – job definition (contains abilities.stratagem list)
-- Returns: number (modified cost, or base ability.cost if no stratagems apply)
function common.effective_ability_cost(ability, settings, job_def)
    if not ability or not ability.cost then return 0 end
    if not settings or not settings.stratagem_settings then return ability.cost end

    -- Try ability.name first, then ability.group as fallback
    local ss = settings.stratagem_settings[ability.name]
    if not ss and ability.group then
        ss = settings.stratagem_settings[ability.group]
    end
    if not ss then return ability.cost end

    local strat_defs = job_def and job_def.abilities and job_def.abilities.stratagem
    if not strat_defs then return ability.cost end

    -- Modifiers are multiplicative (e.g. Accession 3.0x * Penury 0.5x = 1.5x).
    -- This is commutative so iteration order of pairs(ss) does not matter.
    local modifier = 1.0
    for strat_name, _ in pairs(ss) do
        for _, strat in ipairs(strat_defs) do
            if strat.name == strat_name and strat.mp_modifier then
                modifier = modifier * strat.mp_modifier
            end
        end
    end
    return math.floor(ability.cost * modifier)
end

-- Check if scholar stratagems need to fire before casting a spell.
-- Each automation tick, this returns the NEXT action to take:
--   nil                    → no stratagems assigned OR all strat buffs active → cast the spell
--   {command, description} → fire this stratagem JA this tick; caller returns it, re-checks next tick
--   false                  → stratagems assigned, "Hold for Stratagem" ON, but the strat
--                            cannot fire (not enough charges, wrong arts, blocked) → skip ability
--                            (when hold is OFF this path returns nil instead → cast without the strat)
-- Checks both ability_key (ability.name) and the optional group key (ability.group)
-- since the UI stores assignments under the group name for grouped buffs.
-- Args:
--   job_def     (table)  – job definition (contains abilities.stratagem list)
--   settings    (table)  – addon settings (contains stratagem_settings)
--   ability_key (string) – primary lookup key (typically ability.name)
--   ability     (table)  – optional ability table; when provided, ability.group is used as fallback key
function common.check_stratagem(job_def, settings, ability_key, ability)
    if not settings or not settings.stratagem_settings then return nil end

    -- Try primary key first, then group as fallback
    local resolved_key = ability_key
    local ss = settings.stratagem_settings[ability_key]
    if not ss and ability and ability.group then
        ss = settings.stratagem_settings[ability.group]
        resolved_key = ability.group
    end
    if not ss then return nil end

    local strat_defs = job_def and job_def.abilities and job_def.abilities.stratagem
    if not strat_defs then return nil end

    -- "Hold for Stratagem": when enabled, skip the spell until the stratagem
    -- can fire. When disabled (default), a stratagem that can't fire falls
    -- through and the spell is cast without it.
    local hold = settings.stratagem_hold and settings.stratagem_hold[resolved_key] == true
    local unavailable = nil          -- value returned when a stratagem can't fire
    if hold then unavailable = false end

    -- Get player buffs once for all checks
    local player_buffs = common.get_player_buffs()

    -- Find assigned stratagems whose buff is NOT yet active.
    -- Iterate strat_defs in definition order (not pairs(ss)) so that
    -- the chosen stratagem is deterministic when multiple are assigned.
    local missing = {}
    for _, strat in ipairs(strat_defs) do
        if ss[strat.name] then
            local buff_active = false
            for _, pb in ipairs(player_buffs) do
                if pb == strat.buff_id then
                    buff_active = true
                    break
                end
            end
            if not buff_active then
                table.insert(missing, strat)
            end
        end
    end

    -- All strat buffs active → ready to cast the spell
    if #missing == 0 then return nil end

    -- Need one charge per missing stratagem buff
    local state = common.game_state
    local charges = state and state.stratagems or 0
    if charges < #missing then
        return unavailable
    end

    -- Fire the first missing stratagem
    local strat = missing[1]

    -- Verify arts-stance prerequisite (requires_buff may be a number or table)
    if strat.requires_buff then
        local req_ids = type(strat.requires_buff) == 'table' and strat.requires_buff or { strat.requires_buff }
        local has_required = false
        for _, req_id in ipairs(req_ids) do
            for _, pb in ipairs(player_buffs) do
                if pb == req_id then
                    has_required = true
                    break
                end
            end
            if has_required then break end
        end
        if not has_required then
            return unavailable
        end
    end

    -- Check if blocked by status ailment (silence, stun, etc.)
    local blocked_by = common.is_command_blocked(strat.command)
    if blocked_by then
        return unavailable
    end

    -- Return the stratagem JA command (is_stratagem flag tells the automation
    -- engine to lock the next tick to the same action type so the paired
    -- ability fires immediately without being pre-empted by higher-priority actions)
    return {
        command = strat.command,
        description = string.format('Using stratagem: %s', strat.name),
        is_stratagem = true,
    }
end

-- Remove assigned stratagems the player can no longer use. A stratagem configured
-- on a high-level SCH stays in stratagem_settings after switching to a lower level
-- or SCH subjob; without this, automation would keep trying to fire a JA the player
-- doesn't know. Called on job/level change. Returns true if anything was pruned.
function common.prune_unavailable_stratagems(job_def, settings)
    if not settings or not settings.stratagem_settings then return false end
    local strat_defs = job_def and job_def.abilities and job_def.abilities.stratagem
    if not strat_defs then return false end

    -- Resolve SCH level from main or sub job (SCH = job ID 20)
    local main_job_id, sub_job_id = common.get_player_job()
    local main_level, sub_level   = common.get_player_level()
    local sch_level = 0
    if main_job_id == 20 then
        sch_level = main_level
    elseif sub_job_id == 20 then
        sch_level = sub_level
    end

    -- Bail on a transient 0 read (e.g. zoning) so we never wipe config wrongly
    if sch_level <= 0 then return false end

    -- name -> required level lookup
    local strat_level = {}
    for _, strat in ipairs(strat_defs) do
        strat_level[strat.name] = strat.level or 0
    end

    local changed = false
    for ability_key, assigned in pairs(settings.stratagem_settings) do
        for strat_name in pairs(assigned) do
            if (strat_level[strat_name] or 0) > sch_level then
                assigned[strat_name] = nil
                changed = true
            end
        end
        if not next(assigned) then
            settings.stratagem_settings[ability_key] = nil
        end
    end
    return changed
end

-- ============================================================================
-- Resting State Management
-- ============================================================================

-- Get resting state.
-- The value is refreshed once per automation tick inside refresh_game_state()
-- from the player's cached entity_status, avoiding per-call GetPlayerEntity() overhead.
function common.is_resting()
    return is_resting
end

-- Set resting state
function common.set_resting(state)
    is_resting = state
end

-- ============================================================================
-- Mount State Management
-- ============================================================================

-- Get mount state.
-- Synced once per tick inside refresh_game_state() via the player's entity_status (5 = mounted)
-- and buff array (buff 252 = Mounted), checked with OR as a safeguard.
function common.is_mounted()
    return is_mounted
end

-- Get dead state.
-- Synced once per tick inside refresh_game_state() via the player's entity_status (3 = dead)
-- and HPP (0 = no health remaining), checked with OR as a safeguard.
function common.is_dead()
    return is_dead
end

-- Check if the player is still loading in (job reads as NON/NON and level == 0).
-- This happens during zone transitions or initial login before the server has sent
-- the player's job data.  Automation should be paused while this is true.
function common.is_loading()
    local main_level, _ = common.get_player_level()
    return not main_level or main_level == 0
end

-- ============================================================================
-- Rest Conditions Timer (shared across modules)
-- ============================================================================

-- Reset the rest conditions timer to zero (call whenever an action fires)
function common.reset_rest_timer()
    rest_conditions_met_time = 0
end

-- Get the rest conditions timer value
function common.get_rest_timer()
    return rest_conditions_met_time
end

-- Set the rest conditions timer to a specific time
function common.set_rest_timer(t)
    rest_conditions_met_time = t
end

-- ============================================================================
-- Centralized Game State (refreshed once per automation tick)
-- ============================================================================
-- Snapshot of player (index 0), party members (indices 1-5), alliance sub-parties
-- (flat indices 6-17), and out-of-party tracked targets.
-- Call common.refresh_game_state() once at the start of each automation cycle
-- so all action modules share the same consistent data without redundant API calls.
--
-- common.game_state.player  (index 0) fields:
--   index, name, server_id, target_index
--   hp, hpp, max_hp (cached; 0 until member seen at 100% HP)
--   mp, mpp, max_mp (cached; 0 until member seen at 100% MP)
--   tp
--   buffs            (table of buff IDs)
--   position         ({x, y, z} in local coords)
--   job, job_name, sub_job, sub_job_name
--   main_level, sub_level
--   is_trust (always false for player), is_active (always true for player)
--   fm, pet_hpp, pet_position  (player-only)
--
-- common.game_state.party[1..5] fields: identical to player + is_trust, is_active
-- common.game_state.party_size  : active member count for main party only (indices 0-5)
-- common.game_state.alliance_size : active member count across alliance sub-parties B and C
--
-- common.game_state.alliance[2|3][0..5] fields: identical to party member fields
--   party index 2 = flat indices 6-11, party index 3 = flat indices 12-17
--   buffs: populated via 0x028/0x029 party buff packets (see read_alliance_buffs); empty if unavailable
--
-- common.game_state.alliance_leaders[1|2|3] : server IDs of each sub-party leader
--
-- common.game_state.tracked[server_id] fields:
--   server_id, name, target_index
--   hp, hpp, max_hp (cached; 0 until seen at 100% HPP)
--   buffs            (table of buff IDs, packet-tracked)
--   position         ({x, y, z} in local coords)
--   is_tracked       (always true)
--   is_active        (true if entity still visible in zone)

common.game_state = {
    refreshed_at     = 0,
    player           = nil,              -- index 0
    party            = {},               -- indices 1-5 (nil when slot is inactive)
    party_size       = 0,                -- main party only (0-5)
    alliance         = { [2] = {}, [3] = {} },  -- sub-party B (6-11) and C (12-17)
    alliance_size    = 0,                -- alliance sub-parties only (6-17)
    alliance_leaders = { [1] = 0, [2] = 0, [3] = 0 },
    tracked          = {},               -- keyed by server_id
    stratagems       = 0,                -- Scholar stratagem charges (0 when not SCH)
    ready_charges    = 0,                -- Beastmaster Ready charges (0 when not BST)
}

-- ============================================================================
-- Charge-Based Recast Calculation (Scholar Stratagems, Beastmaster Ready)
-- ============================================================================
-- Both are charge systems on a single shared recast timer: the timer counts the
-- time left until FULL, so available charges = max - ceil(remaining / rate).

local STRATAGEM_RECAST_ID = 231
local SCH_JOB_ID = 20

-- Level thresholds for stratagem charges (descending order for first-match)
local STRATAGEM_TIERS = {
    { level = 75, max_charges = 5, recharge_rate = 48  },
    { level = 65, max_charges = 4, recharge_rate = 60  },
    { level = 50, max_charges = 3, recharge_rate = 80  },
    { level = 30, max_charges = 2, recharge_rate = 120 },
    { level = 10, max_charges = 1, recharge_rate = 240 },
}

local READY_RECAST_ID     = 102
local BST_JOB_ID          = 9
local READY_MAX_CHARGES   = 3   -- 3 charges max
local READY_RECHARGE_RATE = 30  -- 30s per charge (90s from empty to full)

-- Convert the recast slot matching recast_id into how many of max_charges are
-- available right now. Shared by stratagems and Ready.
local function charges_from_recast(recast_id, max_charges, recharge_rate)
    if max_charges == 0 then return 0 end

    local recast_mgr = AshitaCore:GetMemoryManager():GetRecast()
    if not recast_mgr then return max_charges end

    local timer_value = nil
    for slot = 0, 31 do
        local ok_id, tid = pcall(function() return recast_mgr:GetAbilityTimerId(slot) end)
        if ok_id and tid == recast_id then
            local ok_t, t = pcall(function() return recast_mgr:GetAbilityTimer(slot) end)
            if ok_t then timer_value = t end
            break
        end
    end

    -- No matching slot or timer 0 -> all charges available
    if not timer_value or timer_value == 0 then
        return max_charges
    end

    -- Timer is in ticks (60 ticks = 1 second). Subtract a small epsilon before
    -- ceil to avoid over-counting by 1 near a charge boundary.
    local seconds_remaining = timer_value / 60
    local missing_charges   = math.ceil((seconds_remaining - 0.5) / recharge_rate)
    local current_charges   = max_charges - missing_charges

    if current_charges < 0 then current_charges = 0 end
    if current_charges > max_charges then current_charges = max_charges end

    return current_charges
end

--- Calculate the number of stratagem charges currently available.
--- Returns 0 if the player is not Scholar main or sub.
local function calculate_stratagems()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if not player then return 0 end

    local main_job = player:GetMainJob()
    local sub_job  = player:GetSubJob()
    local level    = 0

    if main_job == SCH_JOB_ID then
        level = player:GetMainJobLevel()
    elseif sub_job == SCH_JOB_ID then
        level = player:GetSubJobLevel()
    else
        return 0
    end

    local max_charges   = 0
    local recharge_rate = 0
    for _, tier in ipairs(STRATAGEM_TIERS) do
        if level >= tier.level then
            max_charges   = tier.max_charges
            recharge_rate = tier.recharge_rate
            break
        end
    end

    return charges_from_recast(STRATAGEM_RECAST_ID, max_charges, recharge_rate)
end

--- Ready charges currently available. 0 when not Beastmaster main or sub.
-- ponytail: fixed 3-charge max; if the server scales it by level/merits, make
-- this level-tiered like STRATAGEM_TIERS.
local function calculate_ready()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if not player then return 0 end

    local main_job = player:GetMainJob()
    local sub_job  = player:GetSubJob()
    if main_job ~= BST_JOB_ID and sub_job ~= BST_JOB_ID then
        return 0
    end

    return charges_from_recast(READY_RECAST_ID, READY_MAX_CHARGES, READY_RECHARGE_RATE)
end

-- Internal helper: return packet-tracked buffs for an alliance member.
-- All alliance member buffs are populated via 0x028/0x029 packet handlers
-- into the shared trust_buffs table (keyed by server_id).
local function read_alliance_buffs(server_id)
    if not server_id or server_id == 0 then return {} end
    return trust_buffs[server_id] or {}
end

-- Internal helper: build a member snapshot from a party manager flat index (0-17).
local function build_member_snapshot(party_mgr, entity_mgr, flat_index)
    local function safe_get(fn, fallback)
        local ok, val = pcall(fn)
        if ok and val ~= nil then return val end
        return fallback
    end

    local server_id  = safe_get(function() return party_mgr:GetMemberServerId(flat_index)     end, 0)
    local name       = safe_get(function() return party_mgr:GetMemberName(flat_index)         end, '')
    local target_idx = safe_get(function() return party_mgr:GetMemberTargetIndex(flat_index)  end, 0)

    local hp  = safe_get(function() return party_mgr:GetMemberHP(flat_index)           end, 0)
    local hpp = safe_get(function() return party_mgr:GetMemberHPPercent(flat_index)    end, 0)
    local mp  = safe_get(function() return party_mgr:GetMemberMP(flat_index)           end, 0)
    local mpp = safe_get(function() return party_mgr:GetMemberMPPercent(flat_index)    end, 0)
    local tp  = safe_get(function() return party_mgr:GetMemberTP(flat_index)           end, 0)

    if not member_max_stats[server_id] then
        member_max_stats[server_id] = {}
    end
    if hpp == 100 and hp > 0 then member_max_stats[server_id].max_hp = hp end
    if mpp == 100 and mp > 0 then member_max_stats[server_id].max_mp = mp end
    local max_hp = member_max_stats[server_id].max_hp or 0
    local max_mp = member_max_stats[server_id].max_mp or 0

    local job        = safe_get(function() return party_mgr:GetMemberMainJob(flat_index)      end, 0)
    local sub_job    = safe_get(function() return party_mgr:GetMemberSubJob(flat_index)       end, 0)
    local main_level = safe_get(function() return party_mgr:GetMemberMainJobLevel(flat_index) end, 0)
    local sub_level  = safe_get(function() return party_mgr:GetMemberSubJobLevel(flat_index)  end, 0)
    local job_name     = safe_get(function()
        return AshitaCore:GetResourceManager():GetString('jobs.names_abbr', job)
    end, '')
    local sub_job_name = safe_get(function()
        return AshitaCore:GetResourceManager():GetString('jobs.names_abbr', sub_job)
    end, '')

    local position = {x = 0, y = 0, z = 0}
    local entity_status = -1
    if entity_mgr and target_idx and target_idx > 0 then
        local ok_x, px = pcall(function() return entity_mgr:GetLocalPositionX(target_idx) end)
        local ok_y, py = pcall(function() return entity_mgr:GetLocalPositionY(target_idx) end)
        local ok_z, pz = pcall(function() return entity_mgr:GetLocalPositionZ(target_idx) end)
        if ok_x and ok_y and ok_z then
            position = {x = px, y = py, z = pz}
        end
        local ent = GetEntity(target_idx)
        if ent then
            local ok_s, s = pcall(function() return ent.Status end)
            if ok_s and s ~= nil then entity_status = s end
        end
    end

    -- Buffs: player and main-party members via normal API; alliance members via read_alliance_buffs() (packet-tracked from trust_buffs)
    local buffs
    if flat_index == 0 then
        buffs = common.get_player_buffs()
    elseif flat_index <= 5 then
        buffs = common.get_party_buffs(flat_index)
    else
        buffs = read_alliance_buffs(server_id)
    end

    return {
        index        = flat_index,
        name         = name,
        server_id    = server_id,
        target_index = target_idx,
        hp           = hp,
        hpp          = hpp,
        max_hp       = max_hp,
        mp           = mp,
        mpp          = mpp,
        max_mp       = max_mp,
        tp           = tp,
        buffs        = buffs,
        position     = position,
        job          = job,
        job_name     = job_name,
        sub_job      = sub_job,
        sub_job_name = sub_job_name,
        main_level   = main_level,
        sub_level    = sub_level,
        is_trust      = (server_id >= 0x1000000),
        is_active     = true,
        entity_status = entity_status,
        -- Player-only extras (zeroed for all non-player members)
        fm           = 0,
        pet_hpp      = 0,
        pet_position = {x = 0, y = 0, z = 0},
    }
end

function common.refresh_game_state()
    local state = common.game_state
    state.refreshed_at     = os.clock()
    state.player           = nil
    state.party            = {}
    state.party_size       = 0
    state.alliance         = { [2] = {}, [3] = {} }
    state.alliance_size    = 0
    state.alliance_leaders = { [1] = 0, [2] = 0, [3] = 0 }
    state.tracked          = {}
    state.stratagems       = calculate_stratagems()
    state.ready_charges    = calculate_ready()

    local party_mgr = common.get_party()
    if not party_mgr then return end

    local entity_mgr = common.get_entity_manager()

    local function safe_get(fn, fallback)
        local ok, val = pcall(fn)
        if ok and val ~= nil then return val end
        return fallback
    end

    -- Cache alliance leader server IDs
    state.alliance_leaders[1] = safe_get(function() return party_mgr:GetAlliancePartyLeaderServerId1() end, 0)
    state.alliance_leaders[2] = safe_get(function() return party_mgr:GetAlliancePartyLeaderServerId2() end, 0)
    state.alliance_leaders[3] = safe_get(function() return party_mgr:GetAlliancePartyLeaderServerId3() end, 0)

    -- -----------------------------------------------------------------------
    -- Main party: flat indices 0-5
    -- -----------------------------------------------------------------------
    for i = 0, 5 do
        local is_active = safe_get(function() return party_mgr:GetMemberIsActive(i) == 1 end, false)
        if not is_active then
            if i > 0 then state.party[i] = nil end
        else
            state.party_size = state.party_size + 1
            local member = build_member_snapshot(party_mgr, entity_mgr, i)

            if i == 0 then
                -- Player-only extras
                local fm = 0
                for fm_val, fm_num in ipairs({381, 382, 383, 384, 385}) do
                    if common.has_buff(0, fm_num) then fm = fm_val break end
                end
                member.fm = fm

                local pet_entity = targets.get_pet()
                if pet_entity then
                    member.pet_hpp = pet_entity.HPPercent or 0
                    if entity_mgr then
                        local pet_idx = pet_entity.TargetIndex
                        if pet_idx and pet_idx > 0 then
                            local ok_px, px = pcall(function() return entity_mgr:GetLocalPositionX(pet_idx) end)
                            local ok_py, py = pcall(function() return entity_mgr:GetLocalPositionY(pet_idx) end)
                            local ok_pz, pz = pcall(function() return entity_mgr:GetLocalPositionZ(pet_idx) end)
                            if ok_px and ok_py and ok_pz then
                                member.pet_position = {x = px, y = py, z = pz}
                            end
                        end
                    end
                end

                state.player = member

                -- Sync is_resting from the player's entity Status (33 = resting).
                -- Only update when the status was successfully read (>= 0) to avoid
                -- clobbering the cached value on a transient entity read failure.
                if member.entity_status >= 0 then
                    is_resting = (member.entity_status == 33)
                end

                -- Sync is_mounted: entity Status 5 OR buff 252 (Mounted), whichever fires first.
                local has_mount_buff = false
                if member.buffs then
                    for _, bid in ipairs(member.buffs) do
                        if bid == 252 then has_mount_buff = true break end
                    end
                end
                is_mounted = (member.entity_status == 5) or has_mount_buff

                -- Sync is_dead: entity Status 3 (dead) OR HPP 0, whichever fires first.
                is_dead = (member.entity_status == 3) or (member.hpp == 0)
            else
                state.party[i] = member
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Alliance sub-parties B and C: flat indices 6-17
    -- Rebuild alliance_member_sids so packet handlers know who to track.
    -- -----------------------------------------------------------------------
    local old_alliance_sids = alliance_member_sids
    alliance_member_sids = {}
    for party_index = 2, 3 do
        local first = (party_index - 1) * 6   -- 6 or 12
        local last  = first + 5                -- 11 or 17
        for flat_i = first, last do
            local is_active = safe_get(function() return party_mgr:GetMemberIsActive(flat_i) == 1 end, false)
            if is_active then
                state.alliance_size = state.alliance_size + 1
                local local_index = flat_i - first   -- 0-5 within sub-party
                local snapshot = build_member_snapshot(party_mgr, entity_mgr, flat_i)
                state.alliance[party_index][local_index] = snapshot
                -- Register server_id for packet-based buff tracking
                if snapshot.server_id and snapshot.server_id > 0 then
                    alliance_member_sids[snapshot.server_id] = true
                end
            end
        end
    end

    -- Purge stale trust_buffs for server_ids that dropped out of the alliance.
    -- Trusts are not allowed in alliances, so former alliance member entries
    -- should not linger in trust_buffs.
    for sid in pairs(old_alliance_sids) do
        if not alliance_member_sids[sid] and not tracked_targets[sid] then
            trust_buffs[sid] = nil
        end
    end

    -- -----------------------------------------------------------------------
    -- Refresh tracked targets (outside-party players)
    -- -----------------------------------------------------------------------
    for sid, tt in pairs(tracked_targets) do
        local entity = nil
        -- Re-resolve entity by server_id (target_index may change across zones)
        for idx = 0, 2302 do
            local e = GetEntity(idx)
            if e and e.ServerId == sid then
                entity = e
                tt.target_index = e.TargetIndex or 0
                break
            end
        end

        if entity and entity.TargetIndex and entity.TargetIndex > 0 then
            local hpp = entity.HPPercent or 0

            -- Position
            local position = {x = 0, y = 0, z = 0}
            if entity_mgr then
                local tidx = entity.TargetIndex
                local ok_x, px = pcall(function() return entity_mgr:GetLocalPositionX(tidx) end)
                local ok_y, py = pcall(function() return entity_mgr:GetLocalPositionY(tidx) end)
                local ok_z, pz = pcall(function() return entity_mgr:GetLocalPositionZ(tidx) end)
                if ok_x and ok_y and ok_z then
                    position = {x = px, y = py, z = pz}
                end
            end

            -- Only HPPercent is available for non-party entities from GetEntity();
            -- raw HP is not exposed in the FFXI entity array for non-party PCs.
            -- Priority: (1) observed-at-100% cache, (2) level-based estimate from AVERAGE_HP_BY_LEVEL.
            if not member_max_stats[sid] then
                member_max_stats[sid] = {}
            end
            local max_hp = member_max_stats[sid].max_hp or 0
            if max_hp == 0 and tt.main_level then
                max_hp = AVERAGE_HP_BY_LEVEL[tt.main_level] or 0
            end
            local hp = (max_hp > 0) and math.floor(hpp * max_hp / 100) or 0

            -- Buffs via packet tracking (same table as Trusts)
            local buffs = trust_buffs[sid] or {}

            local t_entity_status = -1
            local ok_es, es = pcall(function() return entity.Status end)
            if ok_es and es ~= nil then t_entity_status = es end

            state.tracked[sid] = {
                server_id     = sid,
                name          = tt.name,
                target_index  = entity.TargetIndex,
                hp            = hp,
                hpp           = hpp,
                max_hp        = max_hp,
                main_job      = tt.main_job,
                sub_job       = tt.sub_job,
                main_level    = tt.main_level,
                sub_level     = tt.sub_level,
                buffs         = buffs,
                position      = position,
                is_tracked    = true,
                is_active     = true,
                entity_status = t_entity_status,
            }
        else
            -- Entity not visible; keep entry but mark inactive
            local cached_max_hp = (member_max_stats[sid] or {}).max_hp or 0
            if cached_max_hp == 0 and tt.main_level then
                cached_max_hp = AVERAGE_HP_BY_LEVEL[tt.main_level] or 0
            end
            state.tracked[sid] = {
                server_id     = sid,
                name          = tt.name,
                target_index  = 0,
                hp            = 0,
                hpp           = 0,
                max_hp        = cached_max_hp,
                main_job      = tt.main_job,
                sub_job       = tt.sub_job,
                main_level    = tt.main_level,
                sub_level     = tt.sub_level,
                buffs         = trust_buffs[sid] or {},
                position      = {x = 0, y = 0, z = 0},
                is_tracked    = true,
                is_active     = false,
                entity_status = -1,
            }
        end
    end

    -- Clear pending_raise flags for any server_id whose entity is no longer dead.
    -- Iterating a sparse table while modifying it is safe in Lua (next-based iteration).
    for sid in pairs(pending_raise_flags) do
        local still_dead = false
        -- Check player and main party
        for i = 0, 5 do
            local m = i == 0 and state.player or state.party[i]
            if m and m.server_id == sid and m.entity_status == 3 then
                still_dead = true; break
            end
        end
        -- Check tracked targets
        if not still_dead and state.tracked and state.tracked[sid] then
            if state.tracked[sid].entity_status == 3 then still_dead = true end
        end
        -- Check alliance sub-parties
        if not still_dead and state.alliance then
            for al_pi = 2, 3 do
                if state.alliance[al_pi] then
                    for _, m in pairs(state.alliance[al_pi]) do
                        if m and m.server_id == sid and m.entity_status == 3 then
                            still_dead = true; break
                        end
                    end
                end
            end
        end
        if not still_dead then
            common.debugf('[REVIVE] server_id %d is no longer dead — clearing pending raise flag', sid)
            pending_raise_flags[sid] = nil
        end
    end
end

-- ============================================================================
-- Shared target-resolution helpers (used by heal, buff, status_removal)
-- ============================================================================

--- Resolve the focus target name across party → tracked → alliance.
--- Returns: kind ('party'|'tracked'|'alliance'|nil), ref (party_index or server_id)
function common.resolve_focus_target(settings, state)
    if not settings.focus_enabled or not settings.focus_target then
        return nil, nil
    end
    local name = settings.focus_target

    for i = 0, 5 do
        local m = i == 0 and state.player or state.party[i]
        if m and m.name == name then
            return 'party', i
        end
    end

    if state.tracked then
        for sid, tt in pairs(state.tracked) do
            if tt.name == name and tt.is_active then
                return 'tracked', sid
            end
        end
    end

    if state.alliance then
        for al_pi = 2, 3 do
            if state.alliance[al_pi] then
                for _, m in pairs(state.alliance[al_pi]) do
                    if m and m.name == name and m.is_active then
                        return 'alliance', m.server_id
                    end
                end
            end
        end
    end

    return nil, nil
end

--- Find an alliance member snapshot by server_id across both sub-parties.
--- Returns the member table or nil.
function common.find_alliance_member(state, server_id)
    if not state or not state.alliance or not server_id then return nil end
    for al_pi = 2, 3 do
        if state.alliance[al_pi] then
            for _, m in pairs(state.alliance[al_pi]) do
                if m and m.server_id == server_id then
                    return m
                end
            end
        end
    end
    return nil
end

--- Return a new list containing only abilities with target_outside == true.
function common.outside_abilities(abilities)
    local result = {}
    for _, a in ipairs(abilities) do
        if a.target_outside then
            table.insert(result, a)
        end
    end
    return result
end

--- Return the total number of active alliance members across sub-parties B and C.
function common.get_alliance_count()
    local count = 0
    local gs = common.game_state
    if gs and gs.alliance then
        for pi = 2, 3 do
            if gs.alliance[pi] then
                for _ in pairs(gs.alliance[pi]) do count = count + 1 end
            end
        end
    end
    return count
end

--- Return a sorted array of { local_idx, m } entries for a given alliance sub-party table.
--- Sorted by local_idx ascending (0-5 within the sub-party).
function common.sorted_alliance_members(sub_party)
    local sorted = {}
    if not sub_party then return sorted end
    for local_idx, m in pairs(sub_party) do
        table.insert(sorted, { local_idx = local_idx, m = m })
    end
    table.sort(sorted, function(a, b) return a.local_idx < b.local_idx end)
    return sorted
end

return common
