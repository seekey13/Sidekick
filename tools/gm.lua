--[[
    GM commands that set the scene for in-game tests on the dev server (issue #56). A session drives the game through
    the VanaCore MCP and runs these in Sidekick3's own Lua state with the MCP's `lua` tool:

        lua  addon = "Sidekick3"  code = "return require('tools.gm').hp_pct('Test', 40)"

    then reads the server's answer with `chat_log`. tools/e2e.lua runs scenarios built on it. Nothing in Sidekick3
    requires this file, and release zips leave tools/ out. docs/gm-commands.md has the commands and their quirks.

    Each command, its arguments and whom it acts on are the server's own (scripts/commands/*.lua in the CatsEyeXI
    server). The server answers a command it doesn't know, or one above your GM level, with nothing at all, and reads
    a number it can't parse as 0 (`!hp abc` kills): so only the commands below go out, their arguments checked first.

    Whom a command acts on: a player's name always goes in the line, yours too ('me'). Without one the server takes
    your cursor target as it last heard of it, from your position packet (0x015) a moment later, not as it is now;
    the commands that take only the cursor (a mob's HP or level) wait for that: gm.cursor().
]]--

local gm = {}

-- The server keeps 128 bytes of a chat line (Str, 0x0b5_chat_std.h); a longer one would be cut.
gm.MAX_LINE = 120

local PC_FIRST, PC_LAST = 0x400, 0x6FF  -- players' entity indexes (core/game.lua)
local MOB_FIRST, MOB_LAST = 1, 0x3FF    -- mobs' and NPCs'
local MOB = 0x10                        -- spawn flag
local DEAD = 3                          -- entity status

-- Jobs as the server spells them (xi.job, scripts/enum/job.lua).
gm.JOBS = { WAR = 1, MNK = 2, WHM = 3, BLM = 4, RDM = 5, THF = 6, PLD = 7, DRK = 8, BST = 9, BRD = 10, RNG = 11,
            SAM = 12, NIN = 13, DRG = 14, SMN = 15, BLU = 16, COR = 17, PUP = 18, DNC = 19, SCH = 20, GEO = 21, RUN = 22 }

-- Status ids by the server's names (xi.effect, scripts/enum/effect.lua) in lower case: what Sidekick3 removes, wakes
-- from and keeps up. Always sent as the id: !deleffect with a player's name reads the status with atoi, so 'poison'
-- would be 0, which it takes as 1 (Weakness).
gm.EFFECTS = {
    weakness = 1, sleep = 2, sleep_i = 2, poison = 3, paralysis = 4, blindness = 5, silence = 6, petrification = 7,
    disease = 8, curse = 9, curse_i = 9, stun = 10, bind = 11, weight = 12, slow = 13, charm = 14, doom = 15,
    amnesia = 16, gradual_petrification = 18, sleep_ii = 19, curse_ii = 20, addle = 21, terror = 28, mute = 29,
    bane = 30, plague = 31, burn = 128, frost = 129, choke = 130, rasp = 131, shock = 132, drown = 133, dia = 134,
    bio = 135, str_down = 136, max_hp_down = 144, max_mp_down = 145, accuracy_down = 146, attack_down = 147,
    evasion_down = 148, defense_down = 149, flash = 156, magic_def_down = 167, magic_atk_down = 175, helix = 186,
    requiem = 192, lullaby = 193, elegy = 194,
    haste = 33, blaze_spikes = 34, ice_spikes = 35, blink = 36, stoneskin = 37, shock_spikes = 38, aquaveil = 39,
    protect = 40, shell = 41, regen = 42, refresh = 43, invisible = 69, deodorize = 70, sneak = 71, reraise = 113,
    phalanx = 116,
}

local function fail(fmt, ...) error(fmt:format(...), 0) end

local function whole(n, lo, hi, what)
    if type(n) ~= 'number' or n ~= math.floor(n) or n < lo or n > hi then
        fail('%s: a whole number from %d to %d, not %s', what, lo, hi, tostring(n))
    end
    return n
end

local function number(n, what)
    if type(n) ~= 'number' or n ~= n or n == math.huge or n == -math.huge then fail('%s: a number, not %s', what, tostring(n)) end
    return n
end

-- Your character's name.
function gm.me() return AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) end

-- A player's name for the line: 'me' is yours. Names are 3 to 15 letters; the server matches them in any case.
local function player(who)
    if who == nil then fail('name a player (\'me\' for yourself)') end
    if who == 'me' then who = gm.me() end
    if type(who) ~= 'string' or not who:match('^%a+$') or #who < 3 or #who > 15 then
        fail('not a player\'s name: %s', tostring(who))
    end
    return who
end

local function effect(e)
    local id = type(e) == 'number' and e or type(e) == 'string' and gm.EFFECTS[e:lower()]
    if not id then fail('no status "%s" here: give its id (xi.effect) or add it to gm.EFFECTS', tostring(e)) end
    return whole(id, 1, 1023, 'status id')  -- the server takes 0 as 1
end

local function job(j)
    local id = type(j) == 'string' and gm.JOBS[j:upper()] or type(j) == 'number' and j
    for abbr, n in pairs(gm.JOBS) do if n == id then return abbr, n end end
    fail('no job "%s"', tostring(j))
end

local function fits(line)
    if #line > gm.MAX_LINE then fail('%d bytes, more than the server reads whole (%d): %s', #line, gm.MAX_LINE, line) end
    if line:find('[^\32-\126]') then fail('ASCII only: %s', line) end
    return line
end

-- The line as a say chat packet (0x0B5): the server reads a line starting with '!' before anyone hears it, and never
-- says a GM's. Not typed through the chat box, which drops a line sent within about 1.5 seconds of the last ("A
-- command error occurred") and echoes each: packets go as fast as a scene needs, several in one frame.
local function send(line)
    fits(line)
    local b = { 0xB5, 0, 0, 0, 0x00, 0x00 }  -- header (its size below; the game numbers it), say, padding
    for i = 1, #line do b[#b + 1] = line:byte(i) end
    repeat b[#b + 1] = 0 until #b % 4 == 0
    b[2] = #b / 4 * 2  -- the size in 4-byte units, above the id's ninth bit
    AshitaCore:GetPacketManager():AddOutgoingPacket(0xB5, b)
    return line
end

-- Several lines, all or none: each checked before the first goes.
local function all(lines)
    for _, line in ipairs(lines) do fits(line) end
    for _, line in ipairs(lines) do send(line) end
    return lines
end

-- Whether the client draws entity `i`: spawned near you, not hidden (core/game.lua's present).
local function present(em, i)
    local flags = em:GetRenderFlags0(i)
    return em:GetRawEntity(i) ~= nil and bit.band(flags, 0x200) ~= 0 and bit.band(flags, 0x4000) == 0
end

-- What the client reads of player `who`: a member of your party or alliance (HP, MP and TP in points and %, max HP
-- and MP: yours exact, a member's from HP and HP %, exact at 100%), or else a player near you (HP % only). Nil when
-- neither.
function gm.who(who)
    local name = player(who):lower()
    local mm = AshitaCore:GetMemoryManager()
    local party, em = mm:GetParty(), mm:GetEntity()
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 and (party:GetMemberName(i) or ''):lower() == name then
            local hp, hpp, mp, mpp = party:GetMemberHP(i), party:GetMemberHPPercent(i), party:GetMemberMP(i), party:GetMemberMPPercent(i)
            local u = { name = party:GetMemberName(i), slot = i, index = party:GetMemberTargetIndex(i), hp = hp, hpp = hpp,
                        mp = mp, mpp = mpp, tp = party:GetMemberTP(i), dead = hpp == 0 }
            if i == 0 then
                local p = mm:GetPlayer()
                u.max_hp, u.max_mp = p:GetHPMax(), p:GetMPMax()
            else
                u.max_hp = hpp > 0 and math.floor(hp * 100 / hpp) or nil
                u.max_mp = mpp > 0 and math.floor(mp * 100 / mpp) or nil
            end
            return u
        end
    end
    for i = PC_FIRST, PC_LAST do
        if present(em, i) and (em:GetName(i) or ''):lower() == name then
            local hpp = em:GetHPPercent(i)
            return { name = em:GetName(i), index = i, hpp = hpp, dead = hpp == 0 or em:GetStatus(i) == DEAD }
        end
    end
end

-- The nearest live mob near you named `name` (any case): { index, id = its server id, name, hpp, dist }, else nil.
function gm.mob(name)
    if type(name) ~= 'string' then fail('name a mob') end
    local em = AshitaCore:GetMemoryManager():GetEntity()
    local want, best = name:lower(), nil
    for i = MOB_FIRST, MOB_LAST do
        if present(em, i) and bit.band(em:GetSpawnFlags(i), MOB) ~= 0 and em:GetHPPercent(i) > 0
            and (em:GetName(i) or ''):lower() == want then
            local dist = math.sqrt(em:GetDistance(i))
            if not best or dist < best.dist then
                best = { index = i, id = em:GetServerId(i), name = em:GetName(i), hpp = em:GetHPPercent(i), dist = dist }
            end
        end
    end
    return best
end

-- Vitals. The amount is set outright, and more than the max gives the max. A dead player keeps 0: raise them.
-- !tp sets their pet's TP too.
function gm.hp(who, n) return send(('!hp %d %s'):format(whole(n, 0, 99999, 'HP'), player(who))) end
function gm.mp(who, n) return send(('!mp %d %s'):format(whole(n, 0, 99999, 'MP'), player(who))) end
function gm.tp(who, n) return send(('!tp %d %s'):format(whole(n, 0, 3000, 'TP'), player(who))) end
function gm.kill(who) return gm.hp(who, 0) end
function gm.full(who) return all({ ('!hp 99999 %s'):format(player(who)), ('!mp 99999 %s'):format(player(who)) }) end

-- HP or MP to a % of the max, from what the client reads (gm.who): you and your party or alliance. Start from full
-- for a member, whose max is exact only then. Anyone else (a player outside your alliance shows HP % only): the
-- server's own max, through !exec (GM level 4).
local function pct(who, p, kind)
    whole(p, 0, 100, kind .. ' %')
    local u = gm.who(who)
    if not u then fail('%s isn\'t in your party or near you', player(who)) end
    local max = kind == 'HP' and u.max_hp or u.max_mp
    if u.slot == nil then
        return send(('!exec local p=GetPlayerByName(\'%s\') p:set%s(math.ceil(p:getMax%s()*%d/100))')
            :format(u.name, kind, kind, p))
    end
    if not max or max == 0 then fail('%s\'s max %s is unknown here: set it in points', u.name, kind) end
    local n = math.ceil(max * p / 100)
    return kind == 'HP' and gm.hp(u.name, n) or gm.mp(u.name, n)
end
function gm.hp_pct(who, p) return pct(who, p, 'HP') end
function gm.mp_pct(who, p) return pct(who, p, 'MP') end

-- The raise menu on a dead player, Raise I to III (III by default); they must take it.
function gm.raise(who, tier) return send(('!raise %d %s'):format(whole(tier or 3, 1, 3, 'tier'), player(who))) end

-- Toggles: HP never falls below 1. On is the char var Immortal (!checkvar <name> Immortal).
function gm.immortal(who) return send('!immortal ' .. player(who)) end

-- Statuses, given straight to them (no resist, no immunity): power and seconds as the status takes them (a Poison's
-- power is its HP a tick). The server's own list of someone's statuses goes to your chat log with gm.effects.
function gm.effect(who, e, power, seconds)
    return send(('!addeffect %s %d %d %d'):format(player(who), effect(e), whole(power or 1, 0, 9999, 'power'),
        whole(seconds or 60, 1, 86400, 'seconds')))
end
function gm.uneffect(who, e) return send(('!deleffect %s %d'):format(player(who), effect(e))) end
function gm.effects(who) return send('!geteffects ' .. player(who)) end

-- Their job ability and spell recasts back to 0. It also clears the sender's debuffs (the erasable ones and Sleep,
-- Silence, Poison, Doom and the rest it lists), whomever you name: yours, not theirs (scripts/commands/reset.lua).
function gm.reset(who) return send('!reset ' .. player(who)) end

-- Your own jobs (the server changes only the sender's), and their levels; the sub's is held to the server's cap.
function gm.job(main, lv, sub, sub_lv)
    local lines = { ('!changejob %s %d'):format(job(main), whole(lv, 1, 99, 'level')) }
    if sub then lines[2] = ('!changesjob %s %d'):format(job(sub), whole(sub_lv, 1, 99, 'sub level')) end
    return all(lines)
end

-- Another player's jobs, through the server's Lua (!exec: GM level 4). Each line has to fit gm.MAX_LINE.
function gm.job_of(who, main, lv, sub, sub_lv)
    local get = ('!exec local p=GetPlayerByName(\'%s\') '):format(player(who))
    local _, m = job(main)
    local lines = { get .. ('p:changeJob(%d) p:setLevel(%d)'):format(m, whole(lv, 1, 99, 'level')) }
    if sub then
        local _, s = job(sub)
        lines[2] = get .. ('p:changesJob(%d) p:setsLevel(%d)'):format(s, whole(sub_lv, 1, 99, 'sub level'))
    end
    return all(lines)
end

-- Their main job's level.
function gm.level(who, lv) return send(('!setplayerlevel %s %d'):format(player(who), whole(lv, 1, 99, 'level'))) end

-- Spells: every one but the trusts, the trusts, or one (by id).
function gm.spells(who) return send('!addallspells ' .. player(who)) end
function gm.trusts(who) return send('!addalltrusts ' .. player(who)) end
function gm.spell(who, id) return send(('!addspell %d %s'):format(whole(id, 1, 1023, 'spell id'), player(who))) end

-- Items: into your own inventory, or theirs (the server says when it's full).
function gm.item(id, qty) return send(('!additem %d %d'):format(whole(id, 1, 65535, 'item id'), whole(qty or 1, 1, 99, 'quantity'))) end
function gm.give(who, id, qty)
    return send(('!giveitem %s %d %d'):format(player(who), whole(id, 1, 65535, 'item id'), whole(qty or 1, 1, 99, 'quantity')))
end

-- Moving people: them to you, you to them, you to a zone (its id, xi.zone), them to their home point, and them to a
-- point (x, y, z as !where gives them; in a zone, else theirs).
function gm.bring(who) return send('!bring ' .. player(who)) end
function gm.go(who) return send('!goto ' .. player(who)) end
function gm.zone(id) return send(('!zone %d'):format(whole(id, 1, 298, 'zone id'))) end
function gm.homepoint(who) return send('!homepoint ' .. player(who)) end
function gm.pos(who, x, y, z, zone)
    local at = ('%g %g %g'):format(number(x, 'x'), number(y, 'y'), number(z, 'z'))
    zone = zone and whole(zone, 1, 298, 'zone id') or nil
    return send(('!pos %s %s%s'):format(at, zone and (zone .. ' ') or '', player(who)))
end

-- Mobs, by server id (gm.mob gives a nearby one's; the server's sql/mob_spawn_points.sql has the rest): spawned where
-- they spawn, spawned or moved to where you stand, or gone.
function gm.spawn(id) return send(('!spawnmob %d'):format(whole(id, 1, 0x7FFFFFFF, 'mob id'))) end
function gm.mobhere(id) return send(('!mobhere %d'):format(whole(id, 1, 0x7FFFFFFF, 'mob id'))) end
function gm.despawn(id) return send(('!despawnmob %d'):format(whole(id, 1, 0x7FFFFFFF, 'mob id'))) end

-- Your target as the server last heard of it: the target index in your last position packet.
local heard
if ashita and ashita.events then
    ashita.events.register('packet_out', 'sidekick3_gm_packet_out', function (e)
        if e.id == 0x015 and #e.data >= 0x18 then heard = e.data:byte(0x16 + 1) + e.data:byte(0x16 + 2) * 256 end
    end)
end

-- Targets a player or mob by name (yours, a member's, else the nearest mob of that name) or by entity index, as the
-- game's own targeting does (VanaCore's set_target). The entity index targeted, else an error.
function gm.target(what)
    local i = what
    if type(what) == 'string' then
        local u = (what == 'me' or what:match('^%a%a%a+$') and #what <= 15) and gm.who(what)
        local m = not u and gm.mob(what)
        i = u and u.index or m and m.index
        if not i then fail('no "%s" near you', what) end
    end
    whole(i, 1, 0x8FF, 'entity index')
    if not (vana and vana.game and vana.game.set_target) then fail('targeting needs VanaCore (vana.game.set_target)') end
    if not vana.game.set_target(i) then fail('can\'t target entity %d: out of range?', i) end
    return i
end

-- Your target: { index (0 none), name, mob = whether it's a mob, heard = the index the server has, ready = it has
-- this one }. A command that acts on your cursor target goes only when it's ready.
function gm.cursor()
    local mm = AshitaCore:GetMemoryManager()
    local t, em = mm:GetTarget(), mm:GetEntity()
    local sub = t:GetIsSubTargetActive() ~= 0
    local i = t:GetTargetIndex(sub and 1 or 0)
    return { index = i, name = i ~= 0 and em:GetName(i) or nil, mob = i ~= 0 and bit.band(em:GetSpawnFlags(i), MOB) ~= 0,
             heard = heard, ready = not sub and heard == i }
end

-- A command on the targeted mob: with nothing targeted, or the server not yet told, it would be your own.
local function on_mob(line)
    local c = gm.cursor()
    if not c.mob then fail('target a mob first (gm.target)') end
    if not c.ready then fail('the server hasn\'t heard of your target yet (it has %s): try again', tostring(c.heard)) end
    return send(line)
end
function gm.mob_hp(n) return on_mob(('!hp %d'):format(whole(n, 0, 9999999, 'HP'))) end
function gm.mob_level(lv) return on_mob(('!setmoblevel %d'):format(whole(lv, 1, 255, 'level'))) end

-- Lua on the server (GM level 4), `player` and `target` (your cursor's) defined: one line of ASCII within
-- gm.MAX_LINE, no <...> (typed in the chat box, the client would fill in its own <t>, <me>).
function gm.exec(code)
    if type(code) ~= 'string' or code == '' or code:find('[\r\n]') or code:find('<%w+>') then
        fail('one line of Lua, with no <...> in it')
    end
    return send('!exec ' .. code)
end

-- Your GM level as far as tests go: !where shows your position for level 1 or more, !exec says so for 4 or more. No
-- answer in the chat log at all: not a GM here.
function gm.probe()
    return all({ '!where', '!exec player:printToPlayer(\'Sidekick3 gm: level 4 or more\')' })
end

return gm
