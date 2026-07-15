--[[
    Follow action
    /follow the configured leader when they walk beyond follow_distance. The
    0x0D/0x37 packet guard in Sidekick.lua keeps /follow alive across position syncs.
    Wired low in priority (above rest) so support actions preempt following.
]]--

local common = require('lib.core.common')

local follow = {}

function follow.execute(settings, job_def, main_level, sub_level, player_resource)
    if settings.multisend_follow then  -- Multisend mode owns movement
        return nil
    end

    if not settings.follow_enabled then
        return nil
    end

    local target_name = settings.follow_target
    if not target_name then
        return nil
    end

    local gs = common.game_state
    if not gs or not gs.party then
        return nil
    end

    -- Party index i maps directly to <pi> (both 0-based, <p0> = player). Excludes
    -- the player, so only matches P1-P5. Same index feeds get_party_member_distance
    -- below (which happens to use a 1..5 convention that lines up here).
    local idx = nil
    for i = 1, 5 do
        local m = gs.party[i]
        if m and m.name == target_name then
            idx = i
            break
        end
    end
    if not idx then
        return nil  -- not in party -> silent
    end

    -- In-zone gate: a zoned-out member keeps their slot with a garbage position (and
    -- get_party_member_distance may return it rather than nil), so test SpawnFlags.
    local ti = gs.party[idx].target_index
    if not ti or ti == 0 then return nil end
    local ent = GetEntity(ti)
    if not ent or (ent.SpawnFlags or 0) <= 0 then
        return nil
    end

    local distance = common.get_party_member_distance(idx)
    if not distance or distance <= (settings.follow_distance or 5) then
        return nil  -- close enough -> client holds position
    end

    return {
        command     = '/follow <p' .. idx .. '>',
        description = string.format('Following %s (%.1f yalms)', target_name, distance),
    }
end

return follow
