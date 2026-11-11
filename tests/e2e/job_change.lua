-- A job change: the new job's abilities listed, none of the old one's. The server sends its ability list (0x0AC)
-- after the job, and Sidekick rebuilds its catalog on that list too (core/packets.lua). Your main job changes to
-- another at the same level, and back after, sub job and all.
local TO = { 'WAR', 'WHM', 'THF' }  -- the first that's neither of your jobs
local POLLS = 20                    -- a second each

return {
    about = 'a job change lists the new job\'s abilities and none of the old one\'s',
    timeout = 90,
    run = function (t)
        local p = AshitaCore:GetMemoryManager():GetPlayer()
        local main, lv, sub, sub_lv = p:GetMainJob(), p:GetMainJobLevel(), p:GetSubJob(), p:GetSubJobLevel()
        local to
        for _, j in ipairs(TO) do
            if not to and t.gm.JOBS[j] ~= main and t.gm.JOBS[j] ~= sub then to = j end
        end

        -- The job abilities Sidekick lists, by name, as it decides this moment (a plan, a second for it to show).
        local function abilities()
            t.sk('plan')
            t.wait(1)
            local out = {}
            for _, a in ipairs(t.actions()) do
                if a.kind == 'ja' and not a.hidden then out[a.name] = a.id end
            end
            return out
        end
        local function names(set)
            local out = {}
            for name in pairs(set) do out[#out + 1] = name end
            table.sort(out)
            return table.concat(out, ', ')
        end

        local before = abilities()
        t.need(next(before), 'no job abilities listed for your job')
        t.note('before: %s', names(before))
        t.finally(function () t.gm.job(main, lv, sub > 0 and sub or nil, sub_lv) end)
        t.gm.job(to, lv)
        t.wait_for(function () return p:GetMainJob() == t.gm.JOBS[to] end, 15, 'your main job ' .. to)

        -- Until every ability listed is one the client has, and some of the old job's have gone.
        local now, stale, gone
        for i = 1, POLLS do
            now, stale, gone = abilities(), {}, {}
            for name, id in pairs(now) do
                if not p:HasAbility(id) then stale[name] = true end
            end
            for name in pairs(before) do
                if not now[name] then gone[name] = true end
            end
            if not next(stale) and next(gone) then
                t.time('listed', i)
                break
            end
        end
        t.note('after: %s', names(now))
        t.check(not next(stale), 'listed, but not the client\'s abilities now: %s', names(stale))
        t.check(next(gone), 'none of the old job\'s abilities gone (did the server send its ability list?)')
    end,
}
