-- A party member under the danger line (50% by default): Sidekick heals them, the heal lands, their HP comes up.
return {
    about = 'a party member at 40% HP gets a heal that lands',
    run = function (t)
        local who = t.member()
        t.start()
        t.settle()
        t.gm.hp_pct(who, 40)
        local sent = t.expect({ behavior = 'heal', on = who }, 10)
        t.lands(sent, 15)
        t.wait_for(function () return t.who(who).hpp > 40 end, 5, who .. '\'s HP up')
    end,
}
