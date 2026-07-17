--[[
    Packet parsing utilities for Sidekick
    
    Contains functions to parse raw packet data into structured objects
    Based on HXUI helpers.lua ParseActionPacket implementation
]]--

local parse_packets = {}

--[[
    Parse action packet (0x028) from raw bytes into structured object
    
    Args:
        e - packet event with .data_raw and .size fields
    
    Returns:
        actionPacket - structured table with:
            .UserId - actor server ID
            .Type - action category (8 = casting start, 4 = casting finish,
                    1 = melee, 6 = job ability -- see common.handle_action_packet)
            .Param - spell/ability ID
            .Recast - recast time
            .Targets - array of targets with .Id and .Actions (may be empty)
]]--
function parse_packets.parse_action_packet(e)
    local bitData
    local bitOffset
    local maxLength = e.size * 8
    
    local function UnpackBits(length)
        if ((bitOffset + length) > maxLength) then
            maxLength = 0 -- Using this as a flag since any malformed fields mean the data is trash anyway
            return 0
        end
        local value = ashita.bits.unpack_be(bitData, 0, bitOffset, length)
        bitOffset = bitOffset + length
        return value
    end

    local actionPacket = {}
    bitData = e.data_raw
    bitOffset = 40
    
    actionPacket.UserId = UnpackBits(32)

    local targetCount = UnpackBits(6)
    -- Unknown 4 bits
    bitOffset = bitOffset + 4
    
    actionPacket.Type = UnpackBits(4)
    
    -- Bandaid fix until we have more flexible packet parsing
    if actionPacket.Type == 8 or actionPacket.Type == 9 then
        actionPacket.Param = UnpackBits(16)
        UnpackBits(16)  -- consume SpellGroup bits (field unused; read kept to preserve bit offset)
    else
        -- Not every action packet has the same data at the same offsets so we just skip this for now
        actionPacket.Param = UnpackBits(32)
    end

    actionPacket.Recast = UnpackBits(32)

    actionPacket.Targets = {}
    if (targetCount > 0) then
        for i = 1, targetCount do
            local target = {}
            target.Id = UnpackBits(32)
            local actionCount = UnpackBits(4)
            target.Actions = {}
            
            if (actionCount == 0) then
                break
            else
                for j = 1, actionCount do
                    local action = {}
                    action.Reaction = UnpackBits(5)
                    action.Animation = UnpackBits(12)
                    action.SpecialEffect = UnpackBits(7)
                    action.Knockback = UnpackBits(3)
                    action.Param = UnpackBits(17)
                    action.Message = UnpackBits(10)
                    action.Flags = UnpackBits(31)

                    local hasAdditionalEffect = (UnpackBits(1) == 1)
                    if hasAdditionalEffect then
                        local additionalEffect = {}
                        additionalEffect.Damage = UnpackBits(10)
                        additionalEffect.Param = UnpackBits(17)
                        additionalEffect.Message = UnpackBits(10)
                        action.AdditionalEffect = additionalEffect
                    end

                    local hasSpikesEffect = (UnpackBits(1) == 1)
                    if hasSpikesEffect then
                        local spikesEffect = {}
                        spikesEffect.Damage = UnpackBits(10)
                        spikesEffect.Param = UnpackBits(14)
                        spikesEffect.Message = UnpackBits(10)
                        action.SpikesEffect = spikesEffect
                    end

                    table.insert(target.Actions, action)
                end
            end
            table.insert(actionPacket.Targets, target)
        end
    end

    -- Targets may legitimately be empty; casting detection only needs the header
    -- fields (UserId/Type), and the buff-tracking loop no-ops on an empty list.
    if (maxLength ~= 0) then
        return actionPacket
    end

    return nil
end

--[[
    Parse message packet (0x029) from raw bytes into structured object
    
    Args:
        e - packet event with .data field
        
    Returns:
        basic - structured table with message fields
]]--
function parse_packets.parse_message_packet(e)
    -- 0x029 (GP_SERV_COMMAND_BATTLE_MESSAGE) layout: UniqueNoTar @0x08,
    -- Data (param1) @0x0C, MessageNum (uint16) @0x18. The message id decides
    -- what param1 means -- only status gain/loss messages carry a status id, so
    -- the caller MUST gate on .message or every battle message (damage, synth
    -- results, misses...) is mistaken for a buff. High bit of MessageNum is a
    -- flag; mask to the low 15-bit id. Other struct fields are unused.
    local basic = {
        target  = struct.unpack('i4', e.data, 0x08 + 1),
        param   = struct.unpack('i4', e.data, 0x0C + 1),
        message = struct.unpack('H',  e.data, 0x18 + 1) % 0x8000,
    }
    return basic
end

return parse_packets