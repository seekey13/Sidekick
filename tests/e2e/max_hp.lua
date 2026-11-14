--[[
    Not a scenario: what max_hp_weakness, max_hp_curse and max_hp_alliance share. A status that lowers max HP on a
    player at full, then taken off: their max is back, and their HP stays where the lower max held it. Sidekick has
    to read the max they have now, not the one it saw them at full under the status. Before PR #98 it kept that one
    (core/game.lua: HP seen at 100% was the max for good), so it read them as near full: no HP missing, no heal, not
    even in danger.

    For `kind` 'party' (t.member(), Test) or 'alliance' (t.ally(), Alliance), and `status` 'weakness' or 'curse':
      1. Sidekick's max for them known, at full: their own.
      2. The status on them, their HP falling with the max, still 100%:
           Weakness  max HP down 75%, whatever its power (scripts/effects/weakness.lua): left at 25%, under the
                     critical line, as after a raise;
           Curse     down by its power in % (scripts/effects/curse.lua), set to leave them halfway between their
                     danger line and threshold: efficient healing's band, where the report saw no heal.
         Your party's: Sidekick reads the status from the client's icons and keeps no max while it stands (the
         fix's first half). The alliance's: from packets, noted either way. Read (as on 2026-11-14), no max is
         kept; missed, Sidekick keeps the lower max seen at full, and the next step is what catches that (the fix's
         second half: a max their HP and HP% disagree with is dropped).
      3. The status taken off (as it wears off, or Cursna takes it): Sidekick's max for them their own again, within
         what whole HP% allows. A max seen under the status, kept, fails here.
      4. A heal on them that lands, and their HP up.
    Skipped: healing off for them; for Curse, removal's Cursna would take it first, so removal is off for the
    scenario; efficient healing with no heal to use for them, or their danger line and threshold too close.
    A wait that fails says what Sidekick was doing then. The cleanup takes the status off and fills their HP.
]]--

local heal = require('behaviors.heal')

local STATUS = {
    weakness = { id = 1, name = 'Weakness' },
    curse = { id = 9, name = 'Curse' },
}
local SECONDS = 300  -- the status's duration: it's taken off long before
local HOLD = 3       -- seconds at full under it: nothing to heal, and frames enough for a max seen then to be kept
local BAND = 6       -- danger line to threshold: at least this many points for Curse to leave them inside

local WHO = {
    party = function (t) return t.member() end,
    alliance = function (t) return t.ally() end,
}

-- `wait` (t.wait_for or t.expect) with its arguments, a timeout saying what Sidekick was doing then. An abort, or
-- the scenario's own time running out, goes on as it came.
local function explained(t, wait, ...)
    local ok, v, took = pcall(wait, ...)
    if ok then return v, took end
    local why = type(v) == 'table' and v.why or nil
    if not (why and why:find(': not within ', 1, true)) then error(v, 0) end
    local s = t.status() or {}
    t.fail('%s (Sidekick: %s%s)', why, tostring(s.why), s.intent and (', next ' .. tostring(s.intent.action)) or '')
end

return function (kind, status)
    local pick = assert(WHO[kind], 'party or alliance')
    local st = assert(STATUS[status], 'weakness or curse')
    return {
        about = ('%s on the %s player at full, then taken off: Sidekick reads their own max HP again and heals them')
            :format(st.name, kind),
        run = function (t)
            local who = pick(t)
            t.note('%s on %s (%s)', st.name, who, kind)
            local cfg = t.cfg()
            local hs = cfg.heal or {}
            t.need(hs.on and not (hs.skip or {})[who], 'healing is off for %s (Heal)', who)
            local power = 1  -- Weakness's: more is a double Weakness (accuracy and magic attack down too)
            if status == 'curse' then
                local focus = (hs.focus or ''):lower() == who:lower()
                local danger = focus and hs.focus_danger or hs.danger
                local threshold = focus and hs.focus_threshold or hs.threshold
                t.need(danger and threshold and threshold - danger >= BAND,
                    '%s\'s danger line (%s%%) and threshold (%s%%) are too close for Curse to leave them between',
                    who, tostring(danger), tostring(threshold))
                local _, others = heal.efficient_heals(t.actions(), cfg)
                t.need(others == 'on', 'efficient healing has no heal to use on %s (Heal under)', who)
                power = 100 - math.floor((danger + threshold) / 2)
                t.setting('remove.on', false)  -- Cursna would take it before it's taken off here
            end
            t.start()
            t.settle()

            -- 1. Their own max, known (none is kept under the status: one left from before fails here, saying so).
            local function unit() return t.unit(who) end
            local u = explained(t, t.wait_for, function ()
                local x = unit()
                return x and x.hpp == 100 and (x.max_known or x.buffs[st.id]) and x
            end, 5, ('Sidekick reading %s at full, their max HP known'):format(who))
            t.check(not u.buffs[st.id], '%s has %s already, before any was given', who, st.name)
            local own = u.max_hp

            -- 2. The status on them: their max, and their HP with it, down; still 100%.
            t.gm.effect(who, status, power, SECONDS)
            u = explained(t, t.wait_for, function ()
                local x = unit()
                return x and x.hpp == 100 and x.hp < own and (kind ~= 'party' or x.buffs[st.id]) and x
            end, 5, kind == 'party' and ('Sidekick reading %s on %s, at full HP of a lower max'):format(st.name, who)
                or ('%s at full HP of a lower max'):format(who))
            local lower = u.hp
            t.note('%s\'s max HP: %d; under %s, %d', who, own, st.name, lower)
            t.expect_none({ behavior = 'heal', on = who }, HOLD)
            u = unit()
            if kind == 'party' then
                t.check(not u.max_known, 'Sidekick kept %s as %s\'s max HP under %s, seen at full: their own is %d',
                    tostring(u.max_hp), who, st.name, own)
            else
                t.note('under %s: Sidekick %s it on %s, and %s', st.name, u.buffs[st.id] and 'reads' or 'can\'t read',
                    who, u.max_known and ('keeps %s as their max'):format(tostring(u.max_hp)) or 'keeps no max')
            end

            -- 3. Taken off: their max back, their HP where it was. Sidekick's max for them is their own again.
            t.gm.uneffect(who, status)
            local took
            u, took = explained(t, t.wait_for, function ()
                local x = unit()
                return x and x.hpp > 0 and x.hpp < 100 and (kind ~= 'party' or not x.buffs[st.id]) and x
            end, 5, ('%s gone from %s, their HP under 100%% of their max'):format(st.name, who))
            t.time('read_gone', took)
            local read, low = u.max_hp, u.hpp
            t.note('%s gone: %d HP, %d%%, Sidekick\'s max %s', st.name, u.hp, low, tostring(read))
            -- Whole HP% puts a max worked out from HP and HP% at most a point's worth of HP off.
            t.check(read and math.abs(read - own) <= own / low + 1,
                'Sidekick reads %s\'s max HP as %s once %s went (%d HP, %d%%): their own is %d%s', who, tostring(read),
                st.name, u.hp, low, own, read and math.abs(read - lower) <= 1 and (', the max seen under ' .. st.name
                .. ' kept') or '')

            -- 4. A heal on them that lands, and their HP up (a Regen's takes a tick or two).
            local sent = explained(t, t.expect, { behavior = 'heal', on = who }, 10)
            t.lands(sent, 15)
            local a = t.action(sent.action)
            explained(t, t.wait_for, function () local x = t.who(who); return x and x.hpp > low end,
                a and a.tick and 15 or 5, who .. '\'s HP up')
        end,
    }
end
