--[[
    Follow action
    /follow the configured leader when they walk beyond follow_distance. The
    0x0D packet guard in Sidekick.lua keeps /follow alive across position syncs.
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

    -- Resolves party P1-P5 first, then session tracked targets; nil when the
    -- name matches neither or the member is zoned out (SpawnFlags gate).
    local distance, idx = common.get_follow_target_distance(target_name)
    if not distance then
        return nil  -- not in party/tracked -> silent
    end

    if distance <= (settings.follow_distance or 5) then
        return nil  -- close enough -> client holds position
    end

    -- Party members use the <p_> token (idx maps directly onto <pi>); tracked
    -- targets sit outside the party so they are followed by name, the same
    -- name-command convention /check uses in common.add_tracked_target.
    local cmd_target = idx and ('<p' .. idx .. '>') or target_name
    return {
        command     = '/follow ' .. cmd_target,
        description = string.format('Following %s (%.1f yalms)', target_name, distance),
    }
end

return follow
