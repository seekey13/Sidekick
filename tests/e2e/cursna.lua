--[[
    Not a scenario: what cursna_party, cursna_alliance and cursna_tracked share. Doom on one player, then Sidekick's
    Cursna on them until it's gone, and Sidekick still acting after each one: the report of automation doing nothing
    once a Cursna went off.

    For `kind` 'party' (t.member(), Test), 'alliance' (t.ally(), Alliance) or 'tracked' (t.tracked(), Tracked):
      1. Doom on them (60 s), and Sidekick reading it: your party's from the client's icons, the alliance's and a
         tracked player's from packets (core/packets.lua). A Doom Sidekick never reads fails here, saying so.
      2. A Cursna on them that lands.
      3. Sidekick still acting: their HP set to 40%, and a heal on them that lands, with Doom still on them or not.
      4. While the Doom stays, another Cursna once its recast is up (CURSNA_RECAST), up to MAX_CASTS, until the Doom
         is gone, read the same way as in 1. On the alliance and a tracked player, Sidekick takes a Doom as gone after
         cfg.remove.doom_retries + 1 misses: that's noted, not failed. A Doom that outlasts MAX_CASTS is bad luck
         (Cursna takes it one time in five at WHM75), noted too; what fails is a Cursna not sent once its recast is up.
      5. The Doom gone: no more Cursnas on them.
    Each Cursna's result goes in the notes (message 75: no effect; 359: Doom taken off). A wait that fails says what
    Sidekick was doing then (its `why` and next action). The cleanup takes the Doom off, and raises them should it run out.
]]--

local DOOM = 15
local NO_EFFECT, DOOM_OFF = 75, 359  -- 0x028 messages on Cursna's target
local CURSNA_RECAST = 10  -- seconds (the server's spell_list)
local MAX_CASTS = 4       -- Cursnas waited for, the first included: four at their recasts fit in the Doom's 60 s
local SLACK = 6           -- seconds past a recast for the next send (throttle, READY_DELAY, a frame)

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
            t.need(t.action('Cursna'), 'no Cursna among Sidekick\'s actions for this job')
            local rm = t.cfg().remove
            local mine = (rm.own or {})[who]
            local skip = mine and mine.set and mine.skip or rm.skip or {}
            t.need(rm.on and not (rm.off or {})[who] and not skip.doom, 'Doom removal is off for %s (Remove)', who)
            if kind ~= 'party' then t.note('Sidekick takes a missed Doom as gone after %s misses', tostring((tonumber(rm.doom_retries) or 5) + 1)) end
            t.need(t.unit(who), '%s isn\'t among the units Sidekick decides on', who)
            t.start()
            t.settle()

            -- Whether Sidekick reads Doom on them now.
            local function doomed() local u = t.unit(who); return u ~= nil and u.buffs[DOOM] == true end
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

            t.gm.effect(who, 'doom', 10, 60)
            local _, read = waiting(doomed, 5, ('Sidekick reading Doom on %s'):format(who))
            t.time('doom_read', read)

            local last = nil  -- the last Cursna sent: the next must come after it
            local function after(list, ev)
                for _, x in ipairs(list) do if not ev or x.seq > ev.seq then return x end end
            end
            -- The next Cursna on them, or 'gone' (Sidekick reads no Doom on them now), or 'dead'.
            local function next_cursna(timeout)
                return waiting(function ()
                    local x = after(t.sends({ action = 'Cursna', on = who }), last)
                    if x then return x end
                    if (t.who(who) or {}).dead then return 'dead' end
                    if last and not doomed() then return 'gone' end
                end, timeout, ('a Cursna on %s%s'):format(who, last and ' once its recast was up' or ''))
            end

            local casts, took, probed = 0, false, false
            while casts < MAX_CASTS do
                local ev = next_cursna(last and CURSNA_RECAST + SLACK or 10)
                if ev == 'gone' or ev == 'dead' then
                    if ev == 'dead' then t.note('%s died of the Doom: the cleanup raises them', who) end
                    break
                end
                casts = casts + 1
                local landed = t.lands(ev, 10, 'cursna_' .. casts)
                local msg = landed.targets[1] and landed.targets[1].message
                t.note('Cursna %d on %s: message %s (%s)', casts, who, tostring(msg),
                    msg == NO_EFFECT and 'no effect' or msg == DOOM_OFF and 'Doom taken off' or 'other')
                last = ev
                took = msg == DOOM_OFF
                if not probed then
                    -- Sidekick still acting once a Cursna went off: a heal on them, the Doom still on or not.
                    probed = true
                    t.wait(1)
                    local before = t.sends({ on = who })
                    t.gm.hp_pct(who, 40)
                    local heal = waiting(function ()
                        return after(t.sends({ behavior = 'heal', on = who }), before[#before])
                    end, 10, ('a heal on %s after the Cursna'):format(who))
                    t.note('after the Cursna, %s on %s %.2fs after the HP fell', heal.action, who, heal.at - t.since)
                    t.time('heal_after', heal.at - t.since)
                    t.lands(heal, 15, 'heal_landed')
                    t.wait_for(function () return t.who(who).hpp > 45 end, 5, who .. '\'s HP up')
                end
                if took then break end
            end

            if doomed() and casts >= MAX_CASTS then
                -- Bad luck, not a stall: each Cursna takes Doom one time in five at WHM75's skill.
                t.note('the Doom outlasted %d Cursnas, each sent once its recast was up', casts)
                return
            end
            if (t.who(who) or {}).dead then return end
            t.wait_for(function () return not doomed() end, 5, ('Doom gone from %s in Sidekick\'s reading'):format(who))
            t.note(took and 'Doom taken off by Cursna %d' or 'Doom taken as gone after %d Cursnas with no effect', casts)
            -- Nothing left on them: no Cursna into a Doom that's gone.
            local quiet = t.sends({ action = 'Cursna', on = who })
            t.wait(CURSNA_RECAST + SLACK)
            local extra = after(t.sends({ action = 'Cursna', on = who }), quiet[#quiet])
            t.check(not extra, 'a Cursna on %s after the Doom was gone (%s)', who, extra and extra.why or '')
        end,
    }
end
