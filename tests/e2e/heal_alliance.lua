-- A player in the alliance's other parties, under the danger line: a heal that reaches them.
return {
    about = 'an alliance member at 40% HP is healed',
    run = function (t)
        local who = t.ally()
        t.start()
        t.settle()
        t.gm.hp_pct(who, 40)
        t.wait_for(function () return t.who(who).hpp <= 45 end, 5, who .. ' at 40%')  -- else "none sent" proves nothing
        t.lands(t.expect({ behavior = 'heal', on = who }, 10), 15)
    end,
}
