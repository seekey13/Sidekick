--[[
    PR #110: a charmed player is left out of support until it wears off. For one whose statuses come from packets
    (the alliance's other parties, tracked players), the server tells only them that it wore off
    (status_effect_container.cpp), so Sidekick reads its start and end from their update, 0x00D, which carries a
    CharmFlag to everyone in range (core/packets.lua). Before, a Charm read from packets was held 300 s.
      1. A real charm on the alliance player, by you: Charm's status (for its timer), then player:charm
         (battleutils::applyCharm), through !exec (GM level 4). Neither sends you anything read as a status, so
         Sidekick can read it only from the CharmFlag in their 0x00D. The server's own word (isCharmed, printed to
         your chat log by !exec) is checked first; no answer at all skips (no GM level 4).
      2. Their HP to 40%: nothing sent on them for QUIET seconds, and the Charm still read (each update says so).
      3. Charm taken off as it wears off (!deleffect: the wear-off goes to them alone, then uncharm): Sidekick reads
         it gone from their next 0x00D within GONE seconds, far short of buffs.CHARM_HOLD, and a heal on them lands.
    Charmed by a player, they follow you and fight only what you fight: stand still and engage nothing while it runs.
    The cleanup takes the Charm off and uncharms them (so does Charm's own 90 s timer, should the cleanup be lost),
    then brings their HP back.
]]--

local buffs = require('core.buffs')
local gm = require('tools.gm')

local CHARM = 14
local QUIET = 8  -- seconds with nothing sent on them, charmed and at 40%
local GONE = 5   -- seconds for Sidekick to read the Charm gone once it's taken off

-- The server's own word on whether `who` is charmed: true, false, or nil for no answer (no GM level 4). A read, so
-- through tools/gm.lua itself: it doesn't move t.since, which Sidekick's sends are timed from.
local function server_charmed(t, who)
    local before = t.events()
    local from = before[#before] and before[#before].seq or 0  -- the answer is a line after this
    gm.exec(("player:printToPlayer('sk e2e: charmed '..tostring(GetPlayerByName('%s'):isCharmed()))"):format(who))
    local ok, answer = pcall(t.wait_for, function ()
        for _, ev in ipairs(t.events('line')) do
            local v = ev.seq > from and ev.text:match('sk e2e: charmed (%a+)')
            if v then return v end
        end
    end, 5, 'the server\'s answer to !exec')
    if not ok then
        if type(answer) == 'table' and (answer.why or ''):find(': not within ', 1, true) then return nil end
        error(answer, 0)  -- an abort, or the time running out
    end
    return answer == 'true'
end

return {
    about = 'a real charm on an alliance member: read from their update (0x00D), not healed; read gone as it wears '
        .. 'off, then healed',
    run = function (t)
        local who = t.ally()
        t.need(t.here(who), '%s isn\'t near you: their updates (0x00D) go only to those in range', who)
        local hs = t.cfg().heal or {}
        t.need(hs.on and not (hs.skip or {})[who], 'healing is off for %s (Heal)', who)
        t.start()
        t.settle()
        local function charmed() local u = t.unit(who); return u ~= nil and u.buffs[CHARM] == true end
        t.wait_for(function () return not charmed() end, 5,
            ('no Charm on %s in Sidekick\'s reading before any was given'):format(who))

        t.finally(function ()
            gm.exec(("local a=GetPlayerByName('%s') a:delStatusEffect(%d) a:uncharm()"):format(who, CHARM))
        end)
        t.gm.exec(("local a=GetPlayerByName('%s') a:addStatusEffect(%d,1,0,90) player:charm(a)"):format(who, CHARM))
        local now = server_charmed(t, who)
        t.need(now ~= nil, 'no answer from !exec: charming a player needs GM level 4')
        t.need(now, 'the server didn\'t charm %s (isCharmed false)', who)
        local _, read = t.wait_for(charmed, 5, ('Sidekick reading Charm on %s from their update (0x00D)'):format(who))
        t.time('charm_read', read)

        t.gm.hp_pct(who, 40)
        t.wait_for(function () return t.who(who).hpp <= 45 end, 5, who .. ' at 40%')  -- else "none sent" proves nothing
        t.expect_none({ on = who }, QUIET)
        t.check(charmed(), 'Sidekick lost the Charm on %s while the server still had them charmed', who)
        t.note('charmed at 40%%: nothing sent on %s for %ds', who, QUIET)

        t.gm.uneffect(who, 'charm')
        local ok, err, gone = pcall(t.wait_for, function () return not charmed() end, GONE, 'Charm gone')
        if not ok and type(err) == 'table' and (err.why or ''):find(': not within ', 1, true) then
            t.fail('Sidekick still read Charm on %s %ds after it wore off: their update (0x00D) wasn\'t read, so it\'s '
                .. 'held up to %ds', who, GONE, buffs.CHARM_HOLD)
        elseif not ok then
            error(err, 0)
        end
        t.time('charm_gone', gone)
        t.note('Charm read gone %.1fs after it wore off', gone)
        t.lands(t.expect({ behavior = 'heal', on = who }, 10), 15)
        t.check(server_charmed(t, who) == false, 'the server still has %s charmed after the Charm went', who)
    end,
}
