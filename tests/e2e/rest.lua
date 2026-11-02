-- Resting on: with your MP low, out of combat and standing still, Sidekick3 rests (/heal) once rest.delay seconds have
-- passed since anything happened (its last send, a cast finishing, a move, combat: behaviors/rest.lua), not since the
-- MP fell, and you sit. Resting is turned on for the scenario if it's off; you stand again after.
local RESTING = 33  -- entity status

return {
    about = 'low MP with resting on: /heal, the quiet seconds after the last action',
    run = function (t)
        local cfg = t.cfg()
        if not cfg.rest.on then t.setting('rest.on', true) end
        local me = t.me()
        local function resting()
            local mm = AshitaCore:GetMemoryManager()
            return mm:GetEntity():GetStatus(mm:GetParty():GetMemberTargetIndex(0)) == RESTING
        end
        t.start()
        t.settle()
        t.finally(function ()  -- after MP is full again: up, once the server has you sitting
            for _ = 1, 2 do
                if not resting() then return end
                AshitaCore:GetChatManager():QueueCommand(1, '/heal off')
                if pcall(t.wait_for, function () return not resting() end, 5, 'standing') then return end
            end
        end)
        t.gm.mp_pct(me, 10)
        local sent = t.expect({ behavior = 'rest' }, cfg.rest.delay + 10)
        t.wait_for(resting, 5, 'resting')
        local last  -- what came before it: Sidekick3's last send, or the last cast it finished
        for _, ev in ipairs(t.events()) do
            if ev.seq < sent.seq and (ev.type == 'sent' or ev.type == 'finish') then last = ev end
        end
        if last then
            t.check(sent.at - last.at >= cfg.rest.delay - 0.2, 'rested %.1fs after its last %s, before its %ds',
                sent.at - last.at, last.type, cfg.rest.delay)
            t.note('rested %.1fs after its last %s', sent.at - last.at, last.type)
        end
    end,
}
