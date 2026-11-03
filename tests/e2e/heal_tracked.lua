-- A tracked player (outside your party and alliance), under the danger line: a heal that reaches them, by server id.
-- Their HP is set from the server's own max (!exec): the client shows theirs as a % only.
return {
    about = 'a tracked player at 40% HP gets a heal that lands',
    run = function (t)
        local who = t.tracked()
        t.start()
        t.settle()
        t.gm.hp_pct(who, 40)
        t.wait_for(function () return t.who(who).hpp <= 45 end, 5, who .. ' at 40%')
        local sent = t.expect({ behavior = 'heal', on = who }, 10)
        t.lands(sent, 15)
        t.wait_for(function () return t.who(who).hpp > 45 end, 5, who .. '\'s HP up')
    end,
}
