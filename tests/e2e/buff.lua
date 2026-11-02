-- A buff row on for a party member: once Sidekick3 has it on them, it's taken off, and Sidekick3 puts it back. The
-- first row on for them whose status Sidekick3 can tell; with none, a Protect row on for them for this scenario.
local settings = require('core.settings')

return {
    about = 'a buff a row keeps on a party member, taken off, goes back on',
    timeout = 150,
    run = function (t)
        local who = t.member()
        local u = t.who(who)
        local cfg = t.cfg()
        local buff
        for key, row in pairs(cfg.rows) do
            if row.on and row.targets and (row.targets[u.slot] or row.targets[u.name]) then
                for _, a in ipairs(t.actions()) do
                    if not buff and settings.key(a) == key and a.role == 'buff' and a.status then buff = a end
                end
            end
        end
        if not buff then
            for _, a in ipairs(t.actions()) do
                if not buff and a.family == 'Protect' and a.role == 'buff' and a.status then buff = a end
            end
            t.need(buff, 'no buff row on for %s, and no Protect to put one on for', who)
            t.setting({ 'rows', settings.key(buff) }, { on = true, targets = { [u.slot] = true } })
        end
        t.note('%s, by its row %s', buff.name, settings.key(buff))
        local function on()
            local x = t.unit(who)
            for _, id in ipairs(buff.status) do if x and x.buffs[id] then return id end end
        end
        t.start()
        t.settle()
        local id = t.wait_for(on, 60, ('%s on %s to begin with'):format(buff.family, who))
        t.idle(3, 30)
        t.gm.uneffect(who, id)
        local sent = t.expect({ behavior = 'buff', on = who }, 15)
        t.lands(sent, 15)
        t.wait_for(on, 8, ('%s back on %s'):format(buff.family, who))
    end,
}
