-- Poison on a party member: Poisona on them, and it clears (as Sidekick3 reads their statuses).
local POISON = 3

return {
    about = 'a poisoned party member gets Poisona, and the Poison goes',
    run = function (t)
        local who = t.member()
        t.need(t.action('Poisona'), 'no Poisona among Sidekick3\'s actions for this job')
        local cfg = t.cfg()
        t.need(cfg.remove.on and not cfg.remove.skip.Poison, 'Poison removal is off (Debuffs)')
        t.start()
        t.settle()
        t.gm.effect(who, 'poison', 1, 120)  -- 1 HP a tick: nothing for a heal to do
        local sent = t.expect({ behavior = 'remove', on = who, action = 'Poisona' }, 10)
        t.lands(sent, 10)
        t.wait_for(function () local u = t.unit(who); return u and not u.buffs[POISON] end, 8, 'Poison gone from ' .. who)
    end,
}
