-- Resting on: with your MP dropped under Rest under's line (rest.mp), out of combat and standing still, Sidekick
-- rests (/heal) within seconds (behaviors/rest.lua: 3 s after your last move or its last send), and you sit. Resting is turned on for the scenario if it's off, and the
-- line raised over the 10% the scene drops you to if it's under; you stand again after.
local RESTING = 33  -- entity status
local SOON = 5      -- seconds: the MP drop reaching the client, and a tick

return {
    about = 'low MP with resting on: /heal within seconds under the MP line',
    run = function (t)
        local cfg = t.cfg()
        if not cfg.rest.on then t.setting('rest.on', true) end
        if cfg.rest.mp <= 10 then t.setting('rest.mp', 50) end
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
        local sent = t.expect({ behavior = 'rest' }, 10)
        t.wait_for(resting, 5, 'resting')
        t.check(sent.after <= SOON, 'rested %.1fs after the MP drop, not within %ds', sent.after, SOON)
        t.note('rested %.1fs after the MP drop', sent.after)
    end,
}
