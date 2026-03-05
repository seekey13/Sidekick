--[[
    Revive action module
    Raises dead party/tracked/alliance members (entity_status == 3).
    Abilities that have idle_only = true are automatically excluded when
    the player is in combat, satisfying the "out-of-combat only" requirement.
]]--

local revive = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

function revive.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if revive is enabled
    if not settings.revive_enabled then
        return nil
    end

    -- Read game state
    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end

    -- Get revive abilities from job definition
    local revive_abilities = job_def.abilities and job_def.abilities.revive
    if not revive_abilities or #revive_abilities == 0 then
        return nil
    end

    local derived_main_level = player.main_level or main_level
    local derived_sub_level  = player.sub_level  or sub_level

    -- Filter by level, disabled flags, and idle_only (handles not-in-combat requirement)
    local available = common.filter_abilities_by_level(
        revive_abilities,
        settings,
        derived_main_level,
        derived_sub_level,
        job_def
    )

    if #available == 0 then return nil end

    -- Filter to only usable (resource + cooldown)
    local usable = action_core.filter_usable(available, job_def, '[REVIVE]')
    if #usable == 0 then return nil end

    -- Best ability: filter_abilities_by_level sorts by cost descending (strongest first)
    local ability = usable[1]

    -- Scan party members (indices 1-5; the player themselves cannot cast while dead)
    for i = 1, 5 do
        local m = state.party[i]
        if m and m.is_active and m.entity_status == 3
            and m.target_index and m.target_index > 0 then
            common.debugf('[REVIVE] Party[%d] %s is dead, raising with %s',
                i, m.name or '?', ability.name)
            local command = common.build_ability_command(ability, i)
            if command then
                return {
                    command     = command,
                    description = string.format('Raising %s with %s',
                        m.name or 'party member', ability.name),
                }
            end
        end
    end

    -- Scan tracked targets
    if state.tracked then
        for sid, tt in pairs(state.tracked) do
            if tt.is_active and tt.entity_status == 3
                and tt.target_index and tt.target_index > 0 then
                common.debugf('[REVIVE] Tracked %s is dead, raising with %s',
                    tt.name or '?', ability.name)
                local command = common.build_ability_command_for_target(ability, sid)
                if command then
                    return {
                        command     = command,
                        description = string.format('Raising tracked target %s with %s',
                            tt.name or '?', ability.name),
                    }
                end
            end
        end
    end

    -- Scan alliance members (sub-parties 2 and 3)
    if state.alliance then
        for al_pi = 2, 3 do
            local sub_party = state.alliance[al_pi]
            if sub_party then
                for _, m in pairs(sub_party) do
                    if m and m.is_active and m.entity_status == 3
                        and m.target_index and m.target_index > 0 then
                        common.debugf('[REVIVE] Alliance %s is dead, raising with %s',
                            m.name or '?', ability.name)
                        local command = common.build_ability_command_for_target(ability, m.server_id)
                        if command then
                            return {
                                command     = command,
                                description = string.format('Raising alliance member %s with %s',
                                    m.name or '?', ability.name),
                            }
                        end
                    end
                end
            end
        end
    end

    return nil
end

return revive
