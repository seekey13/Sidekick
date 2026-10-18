--[[
    Phase 1 parity check: v2's hand-written job files vs the v3 catalog.
    Delete this (and the v2 dependency) once it reports clean.

    Run from the v2 repo root, which provides the job files and their fake client:
        cd ../Sidekick && luajit ../Sidekick3/tools/parity.lua

    For every job at level 75 (all spells and abilities known) each v2 entry in a
    generic category must appear in the catalog with the same role, and agree on
    status, removes, potency, gates, level and MP; rolls on their lucky and unlucky
    totals too. The other job-mechanic categories (geo, precast) belong to job
    modules and are not checked here; the luopan's (v2's geo and its Geo buff
    group) are, as v3's geo role, the runes and wards, as its rune and ward roles,
    and the maneuvers, as its maneuver role.
]]--

local sk3 = arg[0]:gsub('[\\/]tools[\\/]parity%.lua$', '')
package.path = './?.lua;' .. sk3 .. '/?.lua;' .. package.path
require('tests.ashita')  -- v2's fake client, so its job files load

local catalog = require('core.catalog')
local K = require('core.knowledge')
local res = {
    spells = dofile(sk3 .. '/tests/data/spells.lua'),
    abilities = dofile(sk3 .. '/tests/data/abilities.lua'),
    statuses = dofile(sk3 .. '/tests/data/statuses.lua'),
}

local ROLE = {
    heal = 'heal', heal_aoe = 'heal', heal_pet = 'pet_heal', debuff_removal = 'remove',
    pet_debuff_removal = 'pet_remove', critical = 'emergency', revive = 'revive',
    recover_mp = 'recover', recover_tp = 'recover', recover_party_mp = 'recover', buff = 'buff',
    pet_control = 'pet_send', roll = 'roll', roll_control = 'roll', geo = 'geo', rune = 'rune', rune_ja = 'ward',
    maneuver = 'maneuver',
}
-- v2 entries a v3 job module owns instead of the generic role.
local MODULE_OWNED = {}

-- Known, intended differences from v2: job|name|what -> why.
local ACCEPTED = {
    -- v2 sent the long name the client doesn't know; drop both once Sidekick PR #298 merges.
    ['blue_mage|Orcish Counterstance|MISSING'] = 'v2 casts "Orcish Counterstance"; the client only knows "O. Counterstance"',
    ['blue_mage|O. Counterstance|EXTRA'] = 'same spell, under its client name',
    ['paladin|Raise|EXTRA'] = 'PLD learns Raise at 50; v2 never offered it',
    ['scholar|Accession|MISSING'] = 'v2 paired it with cures in heal_aoe; v3 lists it as an emergency boost',
    ['scholar|Accession|EXTRA'] = 'same ability, as a healing boost',
    ['corsair|Snake Eye|MISSING'] = 'a modifier fired before a Double-Up (jobs/cor.lua)',
    ['geomancer|Blaze of Glory|status'] = 'a modifier before a luopan: its status says it is waiting (jobs/geo.lua)',
    -- Finishing moves past five show one status, Finishing Move (6+) (jobs/dnc.lua).
    ['dancer|No Foot Rise|status'] = 'five or more finishing moves: 385 or 588',
    ['dancer|Reverse Flourish|requires'] = 'five or more finishing moves: 385 or 588',
    -- v2 sent the pet at <t> by default (<bt> by option); v3 always at the battle target.
    ['beastmaster|Fight|enemy'] = 'sent at <bt>',
    ['puppetmaster|Deploy|enemy'] = 'sent at <bt>',
    ['summoner|Assault|enemy'] = 'sent at <bt>',
    -- CatsEyeXI's Reward refuses Pet Poultice and Pet Roborant: it takes pet food only.
    ['beastmaster|Reward (Regen)|MISSING'] = 'the server refuses Pet Poultice; every Reward gives Regen',
    ['beastmaster|Reward (Erase)|MISSING'] = 'the server refuses Pet Roborant; Reward never erases',
    -- Ammo v2 didn't list but the server takes (core/knowledge.lua).
    ['beastmaster|Reward|ammo'] = 'Pet Food Eta and Theta Biscuit too',
    ['puppetmaster|Repair|ammo'] = 'Automaton Oil +3 too',
    ['puppetmaster|Maintenance|ammo'] = 'Automaton Oil +3 too',
    -- v2 copied the server's spell_list cost; the client blocks the cast by its own
    -- (reported to the CatsEyeXI devs as a server/client mismatch).
    ['white_mage|Arise|mp'] = 'client 150, server 300',
    ['geomancer|Geo-Haste|mp'] = 'client 200, server 63',
    ['blue_mage|Triumphant Roar|mp'] = 'client 24, server 36',
    ['blue_mage|Carcharian Verve|mp'] = 'client 65, server 52 (row commented out)',
}

local function list(v)
    if v == nil then return nil end
    local t = type(v) == 'table' and { unpack(v) } or { v }
    table.sort(t)
    return table.concat(t, ',')
end
local function str(v) return v == nil and 'nil' or tostring(v) end

local findings, accepted = {}, 0
local function report(job, name, what, v2, v3)
    if ACCEPTED[job .. '|' .. name .. '|' .. what] then accepted = accepted + 1; return end
    findings[#findings + 1] = ('%-13s %-26s %-10s v2=%-12s v3=%s'):format(job, name, what, str(v2), str(v3))
end

local jobs = {}
for f in io.popen('dir /b lib\\jobs 2>nul || ls lib/jobs'):lines() do jobs[#jobs + 1] = f:match('^(.-)%.lua$') end
table.sort(jobs)

local checked, groups, groups3 = 0, {}, {}
for _, job in ipairs(jobs) do
    local def = require('lib.jobs.' .. job)
    -- Spells: the DAT knows who casts what. Abilities: the server does (HasAbility), so
    -- stand in with the ones this v2 job names.
    local named = {}
    for _, entries in pairs(def.abilities) do
        for _, e in ipairs(entries) do
            local cmd = type(e.command) == 'function' and e.command('<t>') or e.command
            if not cmd:find('^/ma ') then named[cmd:match('"(.-)"')] = true end
        end
    end
    local player = { main = def.job_id, main_lv = 75, sub = nil, sub_lv = 0,
        has_spell = function () return true end,
        has_ability = function (id) return named[res.abilities[id].en] == true end }
    local by, acts = {}, {}
    for _, a in ipairs(catalog.build(res, player, K)) do
        if a.role then
            acts[#acts + 1] = a
            by[a.role .. '|' .. (a.label or a.name)] = a
            by[a.role .. '|' .. a.name] = by[a.role .. '|' .. a.name] or a  -- "Regen (keep up)" is v2's Regen
        end
    end

    local seen = {}
    for cat, entries in pairs(def.abilities) do
        for _, e in ipairs(ROLE[cat] and entries or {}) do
            local role = cat == 'buff' and e.group == 'Geo' and 'geo' or ROLE[cat]  -- a luopan
            local cmd = type(e.command) == 'function' and e.command('<t>') or e.command
            local real = cmd:match('"(.-)"')
            if not MODULE_OWNED[role .. '|' .. real] then
                checked = checked + 1
                local a = by[role .. '|' .. e.name] or by[role .. '|' .. real]
                if not a then
                    report(job, e.name, 'MISSING', role, nil)
                else
                    seen[a] = true
                    local function cmp(what, v2, v3) if v2 ~= v3 then report(job, e.name, what, v2, v3) end end
                    if a.kind == 'ma' then
                        cmp('level', e.level, a.level)
                        cmp('mp', e.cost, a.mp)
                    end
                    -- v2 had no boosts; its Geo debuffs named the enemy's status, which can't be read.
                    if not a.boost and a.luopan ~= 'debuff' then cmp('status', list(e.buff_id), list(a.status)) end
                    cmp('removes', list(e.debuff_id), list(a.removes))
                    -- v2 read value only for single-target heals; v3's area priors are new.
                    if role == 'heal' and e.value then cmp('potency', e.value, a.potency) end
                    cmp('wakes', e.wakes == true or nil, a.wakes)
                    cmp('lucky', e.lucky, a.lucky)
                    cmp('unlucky', e.unlucky, a.unlucky)
                    cmp('blocked_by', list(e.blocked_by), list(a.blocked_by))
                    cmp('requires', list(e.requires_buff), list(a.requires))
                    cmp('priority', e.priority or 0, a.priority)
                    cmp('charges', e.ready_charge_cost or e.requires_ready_charge and 1 or nil, a.charges)
                    -- v2's tools list the family's own first, then Shikanofuda (jobs/nin.lua's).
                    cmp('tool', e.requires_item and e.requires_item[1].id, a.tool)
                    local worn = {}
                    for i, it in ipairs(e.requires_equipped_ammo or {}) do worn[i] = it.id end
                    cmp('ammo', list(e.requires_equipped_ammo and worn), list(a.ammo))
                    local enemy = cmd:find('<bt>') ~= nil
                    cmp('gate', e.combat_only and not enemy and 'combat' or e.idle_only and 'idle' or nil, a.gate)
                    cmp('enemy', enemy, a.targets == 32)
                    cmp('pet', list(e.requires_pet_name) or e.pet_required, type(a.pet) == 'table' and list(a.pet) or a.pet)
                    -- Grouping: one v2 group <-> one v3 group (pick_one, else the family).
                    if e.group then
                        local v2g, v3g = job .. '|' .. role .. '|' .. e.group, a.pick_one or a.family
                        groups[v2g] = groups[v2g] or {}
                        groups[v2g][v3g] = true
                        groups3[job .. '|' .. role .. '|' .. v3g] = groups3[job .. '|' .. role .. '|' .. v3g] or {}
                        groups3[job .. '|' .. role .. '|' .. v3g][e.group] = true
                    end
                end
            end
        end
    end

    -- Catalog actions in a generic role that v2 never offered this job (new coverage or a false
    -- positive). Regen as a heal is new everywhere: v2 only kept it up as a buff. Items
    -- were v2's item module, not a job file's; modifiers its precast slot, not checked.
    for _, a in ipairs(acts) do
        if not seen[a] and not a.tick and a.kind ~= 'item' and a.role ~= 'modifier' then
            report(job, a.label or a.name, 'EXTRA', nil, a.role)
        end
    end
end

local function keys(t) local k = {} for x in pairs(t) do k[#k + 1] = x end table.sort(k) return table.concat(k, ',') end
for g, v3 in pairs(groups) do
    if keys(v3):find(',') then report(g:match('^[^|]+'), g:match('[^|]+$'), 'GROUP', g:match('[^|]+$'), keys(v3)) end
end
for g, v2 in pairs(groups3) do
    if keys(v2):find(',') then report(g:match('^[^|]+'), g:match('[^|]+$'), 'GROUP', keys(v2), g:match('[^|]+$')) end
end

table.sort(findings)
local ngroups = 0
for _ in pairs(groups) do ngroups = ngroups + 1 end
print(('%d v2 entries and %d groups checked, %d findings, %d accepted differences')
    :format(checked, ngroups, #findings, accepted))
for _, f in ipairs(findings) do print(f) end
os.exit(#findings == 0 and 0 or 1)
