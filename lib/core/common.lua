--[[
    Common utilities for Medic automation framework
    Shared across all jobs: party management, buffs, targeting, logging
]]--

local common = {}
local chat = require('chat')

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

-- Trust buff tracking (packet-based since memory reads don't work for Trusts)
local trust_buffs = {}  -- trust_buffs[server_id] = {buff_id1, buff_id2, ...}
local pending_buffs = {}  -- pending_buffs[n] = {server_id=x, buff_id=y, timestamp=t}
local PENDING_BUFF_TIMEOUT = 10.0  -- Seconds before pending buff expires

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

-- Helper function for distance calculation
local function calculate_distance(entity1, entity2)
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

function common.printf(fmt, ...)
    local args = {...}
    if #args == 0 then
        print(chat.header(addon_name) .. chat.message(fmt))
    else
        local success, result = pcall(string.format, fmt, ...)
        if success then
            print(chat.header(addon_name) .. chat.message(result))
        else
            print(chat.header(addon_name) .. chat.message(fmt))
        end
    end
end

function common.debugf(fmt, ...)
    if common.debug then
        local args = {...}
        if #args == 0 then
            print(chat.header(addon_name) .. chat.message('[DEBUG] ' .. fmt))
        else
            local success, result = pcall(string.format, fmt, ...)
            if success then
                print(chat.header(addon_name) .. chat.message('[DEBUG] ' .. result))
            else
                print(chat.header(addon_name) .. chat.message('[DEBUG] ' .. fmt))
            end
        end
    end
end

function common.errorf(fmt, ...)
    local args = {...}
    if #args == 0 then
        print(chat.header(addon_name) .. chat.error(fmt))
    else
        local success, result = pcall(string.format, fmt, ...)
        if success then
            print(chat.header(addon_name) .. chat.error(result))
        else
            print(chat.header(addon_name) .. chat.error(fmt))
        end
    end
end

function common.warnf(fmt, ...)
    local args = {...}
    if #args == 0 then
        print(chat.header(addon_name) .. chat.warning(fmt))
    else
        local success, result = pcall(string.format, fmt, ...)
        if success then
            print(chat.header(addon_name) .. chat.warning(result))
        else
            print(chat.header(addon_name) .. chat.warning(fmt))
        end
    end
end

--[[
    Player Status Checking
]]--

function common.is_idle()
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
    
    return status == 0
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

function common.is_in_event()
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
    
    -- Event, cutscene, or other blocking status
    return status >= 2
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
    
    -- Debug: Log all packet details to understand the structure
    common.debugf('[PACKET] Category: %d, ActionID: 0x%04X, State: 0x%02X', category, action_id, action_state)
    
    -- Simplified casting state logic based on action_state byte (offset 0x0F)
    -- 0x00 = Action started (casting/channeling)
    -- 0x01-0x04 = Action complete (various completion types)
    -- Note: ActionID changes between start (0x58E0) and completion (spell ID), so we can't rely on it
    
    -- Autoattack check (should not affect casting state)
    local is_autoattack = (action_id == 0x1844)
    
    common.debugf('[PACKET] is_autoattack: %s, was_casting: %s', tostring(is_autoattack), tostring(was_casting))
    
    if not is_autoattack then
        -- Track casting state based on action_state byte
        if action_state == 0x00 then
            -- Action started (any action that's not autoattack)
            common.debugf('[PACKET] Setting is_casting = true')
            casting_state.is_casting = true
            casting_state.last_action_time = os.clock()
        elseif action_state > 0x00 then
            -- Action complete
            common.debugf('[PACKET] Setting is_casting = false')
            casting_state.is_casting = false
        end
    end
    
    -- Output state change messages
    if casting_state.is_casting and not was_casting then
        common.debugf('[CASTING STARTED] State: 0x%02X, Category: %d, ActionID: 0x%04X', action_state, category, action_id)
    elseif not casting_state.is_casting and was_casting then
        common.debugf('[CASTING ENDED] State: 0x%02X, Category: %d, ActionID: 0x%04X', action_state, category, action_id)
    end
    
    common.debugf('[PACKET] Final is_casting: %s', tostring(casting_state.is_casting))
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

function common.get_job_name(job_id)
    -- Try to get full job name first
    local ok, name = pcall(function() 
        return AshitaCore:GetResourceManager():GetString('jobs.names', job_id) 
    end)
    if ok and name then
        return name
    end
    
    -- Fallback to abbreviated name if full name not available
    ok, name = pcall(function() 
        return AshitaCore:GetResourceManager():GetString('jobs.names_abbr', job_id) 
    end)
    if ok and name then
        return name:upper()
    end
    
    return tostring(job_id)
end

function common.get_player_mp()
    local party = common.get_party()
    if not party then return 0 end
    return party:GetMemberMP(0)
end

function common.get_player_tp()
    local party = common.get_party()
    if not party then return 0 end
    return party:GetMemberTP(0)
end

-- Get pet entity
-- Returns: pet entity object or nil if no pet
function common.get_pet_entity()
    -- Get player entity
    local ok, player = pcall(function()
        return GetPlayerEntity()
    end)
    
    if not ok or not player then
        return nil
    end
    
    -- Check if player has a pet target index
    local ok_index, pet_index = pcall(function()
        return player.PetTargetIndex
    end)
    
    if not ok_index or not pet_index or pet_index == 0 then
        return nil
    end
    
    -- Get the pet entity
    local ok_pet, pet = pcall(function()
        return GetEntity(pet_index)
    end)
    
    if not ok_pet or not pet then
        return nil
    end
    
    return pet
end

function common.has_pet()
    return common.get_pet_entity() ~= nil
end

-- Get pet's HP percentage
-- Returns: number (HP percentage 0-100) or 0 if no pet
function common.get_pet_hp_percent()
    local pet = common.get_pet_entity()
    if not pet then
        return 0
    end
    
    -- Get pet's HealthPercent
    local ok_hpp, hpp = pcall(function()
        return pet.HealthPercent
    end)
    
    if not ok_hpp or not hpp then
        return 0
    end
    
    return hpp
end

-- Get entity by index
-- Args: entity_index (number) - Entity index (0 = player)
-- Returns: entity object or nil on error
function common.get_entity(entity_index)
    -- Special case for player entity (index 0)
    if entity_index == 0 then
        local ok, player = pcall(function()
            return GetPlayerEntity()
        end)
        
        if ok and player then
            return player
        end
    end
    
    -- Try standard GetEntity for all indices (including 0 as fallback)
    local ok, entity = pcall(function()
        return GetEntity(entity_index)
    end)
    
    if ok and entity then
        return entity
    end
    
    return nil
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

-- Get target manager
-- Returns: target manager object or nil on error
function common.get_target()
    local ok, target = pcall(function()
        return AshitaCore:GetMemoryManager():GetTarget()
    end)
    
    if not ok or not target then
        return nil
    end
    
    return target
end

-- Get player's current target index
-- Returns: number (target index) or 0 if no target
function common.get_target_index()
    local target = common.get_target()
    if not target then
        return 0
    end
    
    local ok_index, target_index = pcall(function()
        return target:GetTargetIndex(0)
    end)
    
    if not ok_index or not target_index then
        return 0
    end
    
    return target_index
end

-- Get player's current target server ID
-- Returns: number (target server ID) or 0 if no target
function common.get_target_id()
    local target = common.get_target()
    if not target then
        return 0
    end
    
    local target_index = target:GetTargetIndex(0)
    if target_index == 0 then
        return 0
    end
    
    local entity_mgr = common.get_entity_manager()
    if not entity_mgr then
        return 0
    end
    
    local server_id = entity_mgr:GetServerId(target_index)
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

function common.get_party_member_hp_percent(index)
    local party = common.get_party()
    if not party then return 0 end
    
    local hp = party:GetMemberHP(index)
    local hpp = party:GetMemberHPPercent(index)
    
    if hpp then
        return hpp
    elseif hp then
        local max_hp = party:GetMemberMaxHP(index)
        if max_hp and max_hp > 0 then
            return (hp / max_hp) * 100
        end
    end
    
    return 0
end

function common.get_party_member_mp_percent(index)
    local party = common.get_party()
    if not party then return 0 end
    
    if not common.is_party_member_active(index) then
        return 0
    end
    
    local mpp = party:GetMemberMPPercent(index)
    if mpp then
        return mpp
    end
    
    return 0
end

function common.get_party_member_target_index(index)
    local party = common.get_party()
    if not party then return nil end
    return party:GetMemberTargetIndex(index)
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

function common.is_in_range(target_index, range)
    -- Ensure range is a number
    local range_value = type(range) == 'number' and range or 21
    
    -- Get both entities
    local player_entity = common.get_entity(0)
    if not player_entity then
        return false
    end
    
    local target_entity = common.get_entity(target_index)
    if not target_entity then
        return false
    end
    
    -- Calculate distance between player and target
    local distance = calculate_distance(player_entity, target_entity)
    return distance and distance <= range_value
end

-- Get distance between player and pet
-- Returns: number (distance in yalms) or nil if no pet or error
function common.get_pet_distance()
    local player_entity = common.get_entity(0)
    if not player_entity then
        return nil
    end
    
    local pet_entity = common.get_pet_entity()
    if not pet_entity then
        return nil
    end
    
    -- Calculate distance between player and pet
    return calculate_distance(player_entity, pet_entity)
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
        common.debugf('has_buff check for Trust: server_id=%d, buff_id=%d, buffs=%s', 
            server_id, buff_id, table.concat(trust_buff_list, ', '))
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
    
    common.debugf('Registered pending buff: server_id=%d, buff_id=%d', server_id, buff_id)
end

-- Handle casting completion (packet 0x028 with byte 0x0F == 0x01)
-- Matches the most recent pending buff and adds it to trust_buffs
function common.handle_buff_application()
    common.debugf('handle_buff_application called, pending_buffs count: %d', #pending_buffs)
    
    if #pending_buffs == 0 then return end
    
    -- Get the most recent pending buff
    local pending = pending_buffs[#pending_buffs]
    table.remove(pending_buffs, #pending_buffs)
    
    common.debugf('Processing pending buff: server_id=%d, buff_id=%d', pending.server_id, pending.buff_id)
    
    -- Initialize buff list for this Trust if needed
    if not trust_buffs[pending.server_id] then
        trust_buffs[pending.server_id] = {}
    end
    
    -- Check if buff already exists
    local already_has = false
    for _, buff_id in ipairs(trust_buffs[pending.server_id]) do
        if buff_id == pending.buff_id then
            already_has = true
            break
        end
    end
    
    -- Add buff if not already present
    if not already_has then
        table.insert(trust_buffs[pending.server_id], pending.buff_id)
        common.debugf('Applied buff to Trust: server_id=%d, buff_id=%d', pending.server_id, pending.buff_id)
    else
        common.debugf('Trust already has buff: server_id=%d, buff_id=%d', pending.server_id, pending.buff_id)
    end
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
            common.debugf('Removed buff from Trust: server_id=%d, buff_id=%d', server_id, buff_id)
            break
        end
    end
    
    -- Clean up empty buff lists
    if #trust_buffs[server_id] == 0 then
        trust_buffs[server_id] = nil
    end
end

-- Clear all Trust buffs (call on zone change)
function common.clear_trust_buffs()
    trust_buffs = {}
    pending_buffs = {}
    common.debugf('Cleared all Trust buffs')
end

-- Get Trust buffs by server_id
-- Args: server_id (number)
-- Returns: table of buff IDs, or empty table
function common.get_trust_buffs(server_id)
    if not server_id then return {} end
    if server_id < 0x1000000 then return {} end  -- Not a Trust
    return trust_buffs[server_id] or {}
end

function common.has_status(target_index, status_id)
    if not target_index then return false end
    
    local party = common.get_party()
    if not party then return false end
    
    -- Find party member index for this target
    local party_index = -1
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            if party:GetMemberTargetIndex(i) == target_index then
                party_index = i
                break
            end
        end
    end
    
    if party_index == -1 then return false end
    
    -- Check status effects via memory pointer
    local ok_ptr, ptr = pcall(function() return party:GetMemberPointer(party_index) end)
    if not ok_ptr or not ptr or ptr == 0 then return false end
    
    local buffs_ptr = ashita.memory.read_uint32(ptr + 0x0C)
    if buffs_ptr == 0 then return false end
    
    for i = 0, 31 do
        local status = ashita.memory.read_uint16(buffs_ptr + (i * 2))
        if status == status_id then
            return true
        end
    end
    
    return false
end

function common.get_removable_debuffs(target_index, removable_list)
    if not target_index or not removable_list then return {} end
    
    local party = common.get_party()
    if not party then return {} end
    
    -- Find party member index
    local party_index = -1
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            if party:GetMemberTargetIndex(i) == target_index then
                party_index = i
                break
            end
        end
    end
    
    if party_index == -1 then return {} end
    
    local debuffs = {}
    local ok_ptr, ptr = pcall(function() return party:GetMemberPointer(party_index) end)
    if not ok_ptr or not ptr or ptr == 0 then return debuffs end
    
    local buffs_ptr = ashita.memory.read_uint32(ptr + 0x0C)
    if buffs_ptr == 0 then return debuffs end
    
    for i = 0, 31 do
        local status = ashita.memory.read_uint16(buffs_ptr + (i * 2))
        for _, removable_id in ipairs(removable_list) do
            if status == removable_id then
                table.insert(debuffs, status)
            end
        end
    end
    
    return debuffs
end

--[[
    Party HP Checking
]]--

function common.check_party_hp(threshold, focus_enabled, focus_target, focus_threshold)
    threshold = threshold or 75
    focus_threshold = focus_threshold or threshold  -- Default to regular threshold if not specified
    
    common.debugf('[check_party_hp] threshold=%.1f%%, focus_enabled=%s, focus_target=%s, focus_threshold=%.1f%%',
                 threshold, tostring(focus_enabled), tostring(focus_target), focus_threshold)
    
    local results = {
        needs_heal = {},
        focus_needs_heal = false,
        lowest_hp_index = nil,
        lowest_hp_percent = 100,
        average_hp = 100,
    }
    
    local party = common.get_party()
    if not party then
        common.debugf('[check_party_hp] No party manager available')
        return results
    end
    
    local total_hp = 0
    local active_count = 0
    
    for i = 0, 5 do
        if common.is_party_member_active(i) then
            local member_name = common.get_party_member_name(i) or 'Unknown'
            local hpp = common.get_party_member_hp_percent(i)
            local target_index = party:GetMemberTargetIndex(i)
            
            -- Skip members with 0% HP (dead/different zone) or 100% HP (full health)
            if hpp == 0 or hpp == 100 then
                -- Skip silently
            else
                total_hp = total_hp + hpp
                active_count = active_count + 1
                
                -- Check if this is the focus target (compare party indices, not target indices)
                local is_focus = focus_enabled and focus_target ~= nil and i == focus_target
                local effective_threshold = is_focus and focus_threshold or threshold
                
                common.debugf('[check_party_hp] Party[%d] %s: HP=%.1f%%, target_index=%s, is_focus=%s, effective_threshold=%.1f%%',
                             i, member_name, hpp, tostring(target_index), tostring(is_focus), effective_threshold)
                
                if hpp < effective_threshold and target_index then
                    common.debugf('[check_party_hp]   -> Needs heal (%.1f%% < %.1f%%)', hpp, effective_threshold)
                    table.insert(results.needs_heal, {
                        index = i,
                        target_index = target_index,
                        hpp = hpp,
                    })
                    
                    if hpp < results.lowest_hp_percent then
                        results.lowest_hp_percent = hpp
                        results.lowest_hp_index = i
                    end
                    
                    -- Check focus target
                    if is_focus then
                        common.debugf('[check_party_hp]   -> Focus target needs heal!')
                        results.focus_needs_heal = true
                    end
                end
            end
        end
    end
    
    if active_count > 0 then
        results.average_hp = total_hp / active_count
    end
    
    common.debugf('[check_party_hp] Results: %d members need heal, focus_needs_heal=%s',
                 #results.needs_heal, tostring(results.focus_needs_heal))
    
    return results
end

--[[
    Target Validation
]]--

function common.is_valid_target(target_index)
    if not target_index then return false end
    
    local entity = common.get_entity(target_index)
    if not entity then return false end
    
    -- Check if entity is valid and alive
    local spawn_flags = entity.SpawnFlags
    if spawn_flags == 0 then return false end
    
    local hpp = entity.HPPercent
    if hpp == 0 then return false end
    
    return true
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
        
        -- Check if ability is disabled in settings
        local disabled_key = 'disabled_' .. ability.name:gsub(' ', '_')
        -- Default to disabled (true) if key doesn't exist (nil)
        local is_disabled = settings[disabled_key]
        if is_disabled == nil then
            is_disabled = true  -- Default new abilities to disabled
        end
        
        if is_disabled then
            -- Skip disabled ability
        elseif ability.requires_pet and not common.has_pet() then
            -- Skip if requires pet but no pet available
        elseif ability.combat_only and common.is_idle() then
            -- Skip if combat only and not engaged
        elseif job_def and job_def.validate_ability and not job_def.validate_ability(ability, common) then
            -- Skip if job-specific validator fails
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
--   target_param (number|nil) - Target parameter (party index 0-5 for p0-p5)
-- Returns: string - Command string or nil
function common.build_ability_command(ability, target_param)
    if type(ability.command) == 'function' then
        -- If target_param is provided, convert party index to server ID
        if target_param ~= nil then
            local party = common.get_party()
            if party then
                -- Convert party index to server ID (like OnegaiGEO does)
                local server_id = party:GetMemberServerId(target_param)
                if server_id and server_id > 0 then
                    return ability.command(server_id)
                end
            end
        end
    elseif type(ability.command) == 'string' then
        return ability.command
    end
    return nil
end

return common