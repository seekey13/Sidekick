--[[
    Beastmaster: Ready charges (v2's calculate_ready). A jug pet's Ready moves
    share one charge pool, recast timer 102 (Sic's too), whose timer counts down
    to every charge back: 3 charges, 30s each, as v2. Each move costs the charges
    the DAT gives as its MP (Wild Carrot 2), which core/catalog.lua keeps as
    a.charges; core/game.lua reads the pool through bst.charges and
    bst.charge_wait, so a move is usable once it has its charges, not only at a
    full pool. Reward's pet food is equipped by pet care (core/ammo.lua).
]]--

local bst = {}

bst.JOB, bst.READY = 9, 102

-- ponytail: v2's fixed pool; if CatsEyeXI scales it (merits, gear), tier it as jobs/sch.lua does.
local CHARGES, RATE = 3, 30

-- Charges banked, from the pool timer's seconds.
function bst.charges(seconds)
    return math.max(0, CHARGES - math.ceil(seconds / RATE))
end

-- The wait until `n` charges are banked (1 if nil), from the pool timer's seconds.
function bst.charge_wait(seconds, n)
    return math.max(0, seconds - (CHARGES - (n or 1)) * RATE)
end

return bst
