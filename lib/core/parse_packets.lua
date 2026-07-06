--[[
    Packet parsing utilities for Medic
    
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
            .Type - action type (4 = magic)
            .Param - spell/ability ID
            .Recast - recast time
            .Targets - array of targets with .Id and .Actions
]]--
function parse_packets.parse_action_packet(e)
    local bitData
    local bitOffset
    local maxLength = e.size * 8
    
    local function UnpackBits(length)
        if ((bitOffset + length) >= maxLength) then
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

    if (maxLength ~= 0) and (#actionPacket.Targets > 0) then
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
    -- Only .target (buff recipient) and .param (buff ID) are consumed by the
    -- sole caller; struct.unpack offsets are independent, so dropping the rest
    -- is safe.
    local basic = {
        target = struct.unpack('i4', e.data, 0x08 + 1),
        param  = struct.unpack('i4', e.data, 0x0C + 1),
    }
    return basic
end

return parse_packets