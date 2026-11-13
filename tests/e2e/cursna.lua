--[[
    Not a scenario: what cursna_party, cursna_alliance and cursna_tracked share. Doom on one player, then Sidekick's
    Cursna on them until it's gone, and Sidekick still acting after each one: the report of automation doing nothing
    once a Cursna went off.

    For `kind` 'party' (t.member(), Test), 'alliance' (t.ally(), Alliance) or 'tracked' (t.tracked(), Tracked):
      1. Doom on them (60 s), and Sidekick reading it: your party's from the client's icons, the alliance's and a
         tracked player's from packets (core/packets.lua). A Doom Sidekick never reads fails here, saying so.
      2. A Cursna on them that lands.
      3. Sidekick still acting (the probe): their HP set to 40% and seen to fall, and a heal on them that lands. After
         the first Cursna when it missed, and again at the end, whatever the Doom did.
      4. While the Doom stays, another Cursna within CURSNA_RECAST + SLACK of the last one sent, up to MAX_CASTS, until
         the Doom is gone, read the same way as in 1. A Doom that outlasts MAX_CASTS is bad luck (Cursna takes it one
         time in five at WHM75), noted: what fails is a Cursna not sent once its recast is up.
      5. The Doom gone: no more Cursnas on them. Only a Cursna takes it off here, so Sidekick reading it gone with
         none that took it fails: the server still counts it down (the alliance's and a tracked player's Doom is read
         from that count, core/buffs.lua).
    A tracked player's HP is set by !exec (GM level 4): checked first, before any Doom, skipping without it.
    Each Cursna's result goes in the notes (message 75: no effect; 359: Doom taken off). A wait that fails says what
    Sidekick was doing then (its `why` and next action). The cleanup takes the Doom off, and raises them should it
    run out.
]]--

local settings = require('core.settings')

local DOOM = 15
local NO_EFFECT, DOOM_OFF = 75, 359  -- 0x028 messages on Cursna's target
local CURSNA_RECAST = 10  -- seconds (the server's spell_list)
local MAX_CASTS = 4       -- Cursnas waited for, the first included: four at their recasts fit in the Doom's 60 s
local SLACK = 6           -- seconds past a recast for the next send (throttle, READY_DELAY, a frame)

-- The runner's clock (tools/e2e.lua): the game's, as sends and events are stamped.
local function clock() return vana and vana.time and vana.time.clock() or os.clock() end

local WHO = {
    party = function (t) return t.member() end,
    alliance = function (t) return t.ally() end,
    tracked = function (t) return t.tracked() end,
}

return function (kind)
    local pick = assert(WHO[kind], 'party, alliance or tracked')
    return {
        about = ('Doom on the %s player: Cursna until it\'s gone, and Sidekick still acting after each'):format(kind),
        timeout = 150,
        run = function (t)
            local who = pick(t)
            t.note('on %s (%s)', who, kind)
            local cursna = t.action('Cursna')
            t.need(cursna, 'no Cursna among Sidekick\'s actions for this job')
            local cfg = t.cfg()
            t.need(settings.row(cfg, cursna).on, 'Cursna is switched off (Remove)')
            local rm = cfg.remove
            -- The statuses left on them, as behaviors/remove.lua's skip_of reads them.
            local mine = (rm.own or {})[who]
            local skip = type(mine) == 'table' and mine.set and (mine.skip or {}) or rm.skip or {}
            t.need(rm.on and not (rm.off or {})[who] and not skip.doom, 'Doom removal is off for %s (Remove)', who)
            t.need(t.unit(who), '%s isn\'t among the units Sidekick decides on', who)
            if kind == 'tracked' then
                -- The probe's 40% on a tracked player goes by !exec (GM level 4): seen to work before any Doom, with
                -- automation still as it was (off: no heal yet), then put back.
                t.gm.hp_pct(who, 40)
                local ok, err = pcall(t.wait_for, function () return t.who(who).hpp <= 45 end, 5, 'HP')
                if not ok and not (type(err) == 'table' and (err.why or ''):find(': not within ', 1, true)) then
                    error(err, 0)  -- an abort, or the time running out
                end
                t.need(ok, '%s\'s HP didn\'t fall: a tracked player\'s is set by !exec, which needs GM level 4', who)
                t.gm.full(who)
                t.wait_for(function () return t.who(who).hpp > 45 end, 5, who .. '\'s HP back')
            end
            t.start()
            t.settle()

            -- Whether Sidekick reads Doom on them now.
            local function doomed() local u = t.unit(who); return u ~= nil and u.buffs[DOOM] == true end
            local function dead() return (t.who(who) or {}).dead end
            -- What Sidekick says it's doing now.
            local function thinking()
                local s = t.status() or {}
                return ('%s%s'):format(tostring(s.why), s.intent and (', next ' .. tostring(s.intent.action)) or '')
            end
            -- t.wait_for, its failure saying what Sidekick was doing as it timed out. An abort, or the scenario's own
            -- time running out, goes on as it came.
            local function waiting(pred, timeout, what)
                local ok, v, took = pcall(t.wait_for, pred, timeout, what)
                if ok then return v, took end
                local why = type(v) == 'table' and v.why or nil
                if not (why and why:find(': not within ', 1, true)) then error(v, 0) end
                t.fail('%s (Sidekick: %s)', why, thinking())
            end
            local function after(list, ev)
                for _, x in ipairs(list) do if not ev or x.seq > ev.seq then return x end end
            end
            -- Sidekick still acting: their HP to 40%, and a heal on them that lands, the Doom still on or not.
            local function probe(label)
                t.wait(1)
                local before = t.sends({ on = who })
                t.gm.hp_pct(who, 40)
                t.wait_for(function () return t.who(who).hpp <= 45 end, 5, who .. ' at 40%')
                local heal = waiting(function ()
                    return after(t.sends({ behavior = 'heal', on = who }), before[#before])
                end, 10, ('a heal on %s %s'):format(who, label))
                t.note('%s, %s on %s %.2fs after the HP fell', label, heal.action, who, heal.at - t.since)
                t.time('heal_' .. label:gsub('%W+', '_'), heal.at - t.since)
                t.lands(heal, 15)
                t.wait_for(function () return t.who(who).hpp > 45 end, 5, who .. '\'s HP up')
            end

            t.gm.effect(who, 'doom', 10, 60)
            local doomed_at = clock()
            local _, read = waiting(doomed, 5, ('Sidekick reading Doom on %s'):format(who))
            t.time('doom_read', read)

            local last = nil  -- the last Cursna sent: the next must come after it, within its recast of it
            -- The next Cursna on them, or 'gone' (Sidekick reads no Doom on them now), or 'dead'.
            local function next_cursna()
                local timeout = last and math.max(1, last.at + CURSNA_RECAST + SLACK - clock()) or 10
                return waiting(function ()
                    local x = after(t.sends({ action = 'Cursna', on = who }), last)
                    if x then return x end
                    if dead() then return 'dead' end
                    if last and not doomed() then return 'gone' end
                end, timeout, ('a Cursna on %s%s'):format(who, last and ' once its recast was up' or ''))
            end

            local casts, took = 0, false
            while casts < MAX_CASTS do
                local ev = next_cursna()
                if ev == 'gone' or ev == 'dead' then break end
                casts = casts + 1
                local landed = t.lands(ev, 10, 'cursna_' .. casts)
                local msg = landed.targets[1] and landed.targets[1].message
                t.note('Cursna %d on %s: message %s (%s)', casts, who, tostring(msg),
                    msg == NO_EFFECT and 'no effect' or msg == DOOM_OFF and 'Doom taken off' or 'other')
                last = ev
                took = msg == DOOM_OFF
                if took then break end
                if casts == 1 then probe('after the first Cursna') end
            end

            if dead() then
                t.note('%s died of the Doom: the cleanup raises them', who)
                return
            end
            -- Not after the one that took it: Sidekick reads the icon a moment after the 0x028, so the Doom shows still.
            if not took and doomed() and casts >= MAX_CASTS then
                -- Bad luck, not a stall: each Cursna takes Doom one time in five at WHM75's skill.
                t.note('the Doom outlasted %d Cursnas, each sent once its recast was up', casts)
                probe('after the last Cursna')
                return
            end
            -- No Cursna took it, yet Sidekick reads it gone: it lost a Doom the server still counts down (the cleanup
            -- takes it off).
            t.check(took, 'Sidekick read the Doom on %s gone %.0fs after it landed, after %d Cursna%s with no effect: '
                .. 'none took it off', who, clock() - doomed_at, casts, casts == 1 and '' or 's')
            t.wait_for(function () return not doomed() end, 5, ('Doom gone from %s in Sidekick\'s reading'):format(who))
            t.note('Doom taken off by Cursna %d', casts)
            probe('after the Cursna that took it')
            -- Nothing left on them: no Cursna into a Doom that's gone.
            local quiet = t.sends({ action = 'Cursna', on = who })
            t.wait(CURSNA_RECAST + SLACK)
            local extra = after(t.sends({ action = 'Cursna', on = who }), quiet[#quiet])
            t.check(not extra, 'a Cursna on %s after the Doom was gone (%s)', who, extra and extra.why or '')
        end,
    }
end
