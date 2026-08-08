--[[
    Pet Deploy action module -- shared by every job with a controllable pet that
    has an "attack my target" command: Puppetmaster (Deploy), Summoner (Assault),
    Beastmaster (Fight). Sends the pet at the player's current battle target
    whenever it doesn't already have a live target of its own. Opt-in
    (pet_deploy_enabled, off by default) and combat-only.

    Extracted from maneuver.lua (which now holds only PUP's unrelated elemental-
    maneuver upkeep) so SMN/BST can reuse it without duplicating the packet-based
    pet-target tracking. Each job supplies its own single-entry abilities.pet_deploy
    list (name/recast_id/command differ per job; everything else here is generic).
    execute() always reads job_def.abilities.pet_deploy[1] -- if a player mains and
    subs two different pet-control jobs at once, the main job's entry wins (e.g.
    BST/SMN with Carbuncle summoned would still try Fight, not Assault).

    Spec: docs/superpowers/specs/2026-08-08-pet-deploy-smn-bst-design.md
]]--

local pet_deploy = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- ============================================================================
-- Automaton/avatar/pet Deploy
-- ============================================================================

-- Server id the pet is currently believed to be attacking. Module-local,
-- cleared on /addon reload (consistent with roll.lua's roll_state).
local pet_target_id = nil

-- True when pet_target_id still resolves to a live (HP% > 0), actual mob entity.
-- Re-scans the entity array -- same GetEntity(0..2302) linear-scan pattern common.lua
-- uses to re-resolve tracked targets by server id -- only called from
-- pet_deploy.execute, so the cost is paid at most once per deploy check. The mob check
-- (SpawnFlags 0x10, same test common.is_combat() uses) matters here too: a stale or
-- mistracked id that now resolves to a non-mob entity must not read as "still live".
local function pet_target_is_live()
    if not pet_target_id or pet_target_id == 0 then
        return false
    end
    for idx = 0, 2302 do
        local e = GetEntity(idx)
        if e and e.ServerId == pet_target_id then
            local is_mob = bit.band(e.SpawnFlags or 0, 0x10) ~= 0
            return is_mob and (e.HPPercent or 0) > 0
        end
    end
    return false
end

function pet_deploy.execute(settings, job_def, main_level, sub_level, player_resource)
    if not settings.pet_deploy_enabled then
        return nil
    end

    if not job_def or not job_def.abilities or not job_def.abilities.pet_deploy then
        return nil
    end

    if not common.targets.get_pet() then
        pet_target_id = nil
        return nil
    end

    -- Deploy is combat-only by design -- unlike maneuver upkeep, which has no such gate.
    if not common.is_combat() then
        return nil
    end

    if pet_target_is_live() then
        return nil
    end
    pet_target_id = nil

    local target = common.targets.get_t()
    if not target or (target.HPPercent or 0) <= 0 then
        return nil
    end

    -- Only send the pet at an actual mob -- same SpawnFlags 0x10 check
    -- common.is_combat() uses -- so a party member the player happened to have
    -- targeted can't be Deployed at.
    local is_mob = bit.band(target.SpawnFlags or 0, 0x10) ~= 0
    if not is_mob then
        return nil
    end

    local ability = job_def.abilities.pet_deploy[1]
    if not ability then
        return nil
    end

    return action_core.try_use(ability, job_def, settings, nil, ability.name)
end

-- ============================================================================
-- Packet handling
-- ============================================================================

--[[
    Reads the pet's current target off its own 0x028 action packets -- same parsed
    structure roll.handle_action_packet reads Corsair roll totals from. On the pet's
    own action, Targets[1].Id is what it's acting on.

    KNOWN GAP (carried over from the PUP-only version, unresolved -- see
    .superpowers/sdd/2026-08-08-pup-maneuver-deploy/final-review-fix-report.md):
    this trusts Targets[1].Id off ANY action packet from the pet, including its own
    self-targeted actions (buffs/cures on itself or the master), not just attacks.
    roll.handle_action_packet filters on packet.Type ~= 6 (job ability) for the same
    reason; the equivalent filter here needs the Type value(s) that mean "the pet is
    attacking", which was not confirmed against this server's packets and was
    deliberately left unguessed rather than risk a wrong number silently passing
    muster. handle_pet_sync_packet (0x068, below) also writes pet_target_id and is
    unaffected by this gap; whichever packet arrives last currently wins.
]]--
function pet_deploy.handle_action_packet(packet, job_def)
    if not packet or not job_def or not job_def.abilities or not job_def.abilities.pet_deploy then
        return
    end

    local pet = common.targets.get_pet()
    if not pet or not pet.ServerId then
        return
    end

    if packet.UserId ~= pet.ServerId then
        return
    end

    local target = packet.Targets and packet.Targets[1]
    if not target or not target.Id or target.Id == 0 then
        return
    end

    pet_target_id = target.Id
end

--[[
    0x068 (pet sync) isn't parsed anywhere else in Sidekick, so this reads the
    two fields needed directly off the raw packet, same inline struct.unpack
    style parse_packets.parse_message_packet uses for 0x029: owner server id
    at byte 0x08, the pet's current target server id at byte 0x14, both
    little-endian uint32. Only updates state when the owner is the player --
    other players' pets send this packet too.
]]--
function pet_deploy.handle_pet_sync_packet(e, job_def)
    if not e or not e.data or not job_def or not job_def.abilities or not job_def.abilities.pet_deploy then
        return
    end

    -- Guard against a truncated/malformed packet before reading through 0x18 --
    -- same self-guard convention as common.handle_check_packet.
    if #e.data < 0x18 then
        return
    end

    local party = common.get_party()
    local player_id = party and party:GetMemberServerId(0)
    if not player_id then
        return
    end

    local owner_id = struct.unpack('I4', e.data, 0x08 + 1)
    if owner_id ~= player_id then
        return
    end

    pet_target_id = struct.unpack('I4', e.data, 0x14 + 1)
end

return pet_deploy
