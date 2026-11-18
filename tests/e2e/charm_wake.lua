--[[
    PR #110: a party member charmed and then put to sleep was woken with a Cure, which put them back to fighting for
    the enemy. The engine now leaves anyone charmed out of support until it wears off (core/engine.lua: supported).
      1. Charm on the party player (Test), then Sleep, each read by Sidekick from the client's icons.
      2. Nothing sent on them for QUIET seconds: no wake, no heal, no removal.
      3. Charm taken off: Sidekick reads it gone, sends a heal that wakes them, it lands, and they wake.
    A GM's !addeffect gives Charm's status only, not the charm (battleutils::applyCharm), so the server leaves them on
    your side. Your party's statuses are read from the client's icons, and that is all Sidekick goes by for them, so
    this is the case as it plays. charm_alliance has a real charm. Taking it off runs its wear-off
    (scripts/effects/charm.lua): their TP to 0 and uncharm, which does nothing more to one who wasn't charmed.
]]--

local CHARM, SLEEP = 14, 2
local QUIET = 8  -- seconds with nothing sent on them, charmed and asleep

return {
    about = 'a charmed party member put to sleep is left asleep; once the charm goes, a heal wakes them',
    run = function (t)
        local who = t.member()
        t.need(t.cfg().wake.on, 'waking is off (Wake)')
        t.start()
        t.settle()
        local function has(id) local u = t.unit(who); return u ~= nil and u.buffs[id] == true end

        t.gm.effect(who, 'charm', 1, 90)
        t.wait_for(function () return has(CHARM) end, 5, ('Sidekick reading Charm on %s'):format(who))
        t.gm.effect(who, 'sleep', 1, 90)
        t.wait_for(function () return has(SLEEP) end, 5, ('Sidekick reading Sleep on %s'):format(who))
        t.expect_none({ on = who }, QUIET)
        t.note('charmed and asleep: nothing sent on %s for %ds', who, QUIET)

        t.gm.uneffect(who, 'charm')
        local _, gone = t.wait_for(function () return not has(CHARM) end, 5,
            ('Charm gone from %s in Sidekick\'s reading'):format(who))
        t.time('charm_gone', gone)
        t.check(has(SLEEP), '%s woke as the Charm went: nothing left to wake', who)
        local sent = t.expect({ behavior = 'wake', on = who }, 10)
        t.lands(sent, 10)
        t.wait_for(function () return not has(SLEEP) end, 8, who .. ' awake')
    end,
}
