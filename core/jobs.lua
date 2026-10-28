--[[
    The job modules (jobs/*.lua), and the one way the rest of the addon reaches
    them: core/, behaviors/ and ui/ never require a job module or name a job
    (tests/jobs_test.lua checks). A module is a table with any of these:

      JOB        its job id
      knowledge  rows merged into core/knowledge.lua (a name already there is an error)
      behaviors  { { name, run, before = a behavior's name } }: added to core/engine.lua's list
      settings   its cfg sections' defaults (core/settings.lua)
      read       function (g, timer): add its fields to the snapshot `g` (core/game.lua);
                 timer(id) is the seconds left on ability recast timer `id`
      POOL       its charge pool (core/charges.lua): an action drawing on it is ready
                 once the charges it costs are back (core/game.lua)
      ability    function (id, total, message, now, info): one of your job abilities'
                 results on you, from 0x028 (core/packets.lua)
      zone       function (): zoning
      pet_auras  status ids that end with your pet, with no message (main job only)
      spare      function (a, g, cfg): false when a buff row must not spend action `a` now
      short      function (mods, g, cfg): of the modifiers a buff row fires together, the
                 first there aren't charges enough for (nil: there are) (behaviors/buff.lua)
      reserves   function (a): whether action `a` spends what heal.reserve keeps for
                 healing, so Healing shows the switch (ui/model.lua)
      ui         its Sidekick Settings section (ui/model.lua):
                 section  as ui/model.lua's SECTIONS, with `before` = the section it goes before
                 view     function (cat, cfg, g, party_names): the view's field named like
                          the section, and whether the section is shown
                 set      the settings another session may change: as model.REMOTE_SET

    Add a field only when a module needs it, and write it down here.
]]--

local jobs = {}

jobs.all = { require('jobs.sch'), require('jobs.cor'), require('jobs.geo') }

-- Each module's `field`, in module order, skipping those without it; with `job`,
-- only the module for that job.
function jobs.each(field, job)
    local i = 0
    return function ()
        while true do
            i = i + 1
            local j = jobs.all[i]
            if not j then return nil end
            if j[field] ~= nil and (job == nil or j.JOB == job) then return j[field] end
        end
    end
end

return jobs
