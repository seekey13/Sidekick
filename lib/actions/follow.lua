--[[
    Follow action
    Issues /follow at the configured leader when they walk beyond follow_distance.
    Movement/mount/dead/casting guards all live in automation + common; the
    0x0D/0x37 packet guard in Sidekick.lua keeps /follow alive across the server's
    position syncs (without it autofollow breaks on every sync). Wired LOW in the
    priority order (just above rest) so healing and every other support action
    always preempt following.
]]--

local common = require('lib.core.common')

local follow = {}

function follow.execute(settings, job_def, main_level, sub_level, player_resource)
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

    -- Locate the leader's party index. FFXI's <pN> is zero-based with <p0> = the
    -- player, and Sidekick's party indices are already 0-based, so index i maps
    -- directly to <pi>. follow_target excludes the player, so this only ever
    -- matches P1-P5 (indices 1-5). (get_party_member_distance uses a different
    -- 1..5 convention -- do not conflate; we pass the same index to both here.)
    local idx = nil
    for i = 1, 5 do
        local m = gs.party[i]
        if m and m.name == target_name then
            idx = i
            break
        end
    end
    if not idx then
        return nil  -- follow target absent / not in party -> silent
    end

    -- Gate on the leader actually being rendered in this zone. A zoned-out member
    -- keeps their party slot with a garbage position, and get_party_member_distance
    -- can hand back that bogus distance instead of nil, so SpawnFlags > 0 is the
    -- reliable in-zone test.
    local ti = gs.party[idx].target_index
    if not ti or ti == 0 then return nil end
    local ent = GetEntity(ti)
    if not ent or (ent.SpawnFlags or 0) <= 0 then
        return nil
    end

    local distance = common.get_party_member_distance(idx)
    if not distance or distance <= (settings.follow_distance or 5) then
        return nil  -- close enough (or unreadable) -> let the client hold position
    end

    return {
        command     = '/follow <p' .. idx .. '>',
        description = string.format('Following %s (%.1f yalms)', target_name, distance),
    }
end

return follow
