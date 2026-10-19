--[[
    Beastmaster: Ready charges (v2's calculate_ready). A jug pet's Ready moves
    share one charge pool, recast timer 102 (Sic's too; core/charges.lua): 3
    charges, 30s each, as v2, at any BST level. Each move costs the charges the
    DAT gives as its MP (Wild Carrot 2), which core/catalog.lua keeps as
    a.charges. Should CatsEyeXI scale the pool (merits, gear), it takes tiers by
    level as SCH's does. Reward's pet food is equipped by pet care (core/ammo.lua).
]]--

local charges = require('core.charges')

local bst = {}

bst.JOB = 9
bst.POOL = charges.pool({ job = bst.JOB, kind = 'pet', recast = 102, tiers = { { 1, 3, 30 } } })

return bst
