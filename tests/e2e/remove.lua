-- Poison on a party member: Poisona on them, and it clears (as Sidekick reads their statuses).
local POISON = 3

return {
    about = 'a poisoned party member gets Poisona, and the Poison goes',
    run = function (t)
        local who = t.member()
        t.need(t.action('Poisona'), 'no Poisona among Sidekick\'s actions for this job')
        local rm = t.cfg().remove
        local mine = (rm.own or {})[who]
        local skip = mine and mine.set and mine.skip or rm.skip or {}
        t.need(rm.on and not (rm.off or {})[who] and not skip.poison, 'Poison removal is off for %s (Remove)', who)
        t.start()
        t.settle()
        t.gm.effect(who, 'poison', 1, 120)  -- 1 HP a tick: nothing for a heal to do
        local sent = t.expect({ behavior = 'remove', on = who, action = 'Poisona' }, 10)
        t.lands(sent, 10)
        t.wait_for(function () local u = t.unit(who); return u and not u.buffs[POISON] end, 8, 'Poison gone from ' .. who)
    end,
}
