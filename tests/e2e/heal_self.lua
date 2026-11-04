-- You, under the danger line: Sidekick heals you, the heal lands, your HP comes up.
return {
    about = 'you at 40% HP get a heal that lands',
    run = function (t)
        local me = t.me()
        t.start()
        t.settle()
        t.gm.hp_pct(me, 40)
        local sent = t.expect({ behavior = 'heal', on = me }, 10)
        t.lands(sent, 15)
        t.wait_for(function () return t.who(me).hpp > 40 end, 5, 'your HP up')
    end,
}
