--[[
    Dancer: Trance and finishing moves. The server refuses a waltz under Saber
    Dance and a samba under Fan Dance (knowledge's blocked_by). Under Trance it
    waives the TP of a waltz and of Aspir Samba (knowledge's `trance`), so they go
    at any TP and a waltz then costs healing nothing; Drain and Haste Samba still
    want their TP (LSB's ability checks), though they don't spend it. Finishing
    moves past five show as one status, Finishing Move (6+), which counts as five.
]]--

local dnc = {}

dnc.TRANCE = 376

-- The TP `a` needs from you now: none under Trance for a waltz or Aspir Samba.
function dnc.tp(a, g)
    if a.trance and g.me.buffs[dnc.TRANCE] then return 0 end
    return math.max(a.tp or 0, 0)
end

return dnc
