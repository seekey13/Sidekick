--[[
    Dancer (v2's dancer.lua): the stances and Trance. The server refuses a
    waltz under Saber Dance and a samba under Fan Dance, so they aren't sent
    (knowledge's blocked_by, as v2), and a row one blocks says which. Under
    Trance (the 2-hour) the server waives the TP of a waltz and of Aspir Samba
    (LSB's ability checks; knowledge's `trance`): they go at any TP and a waltz
    then costs healing nothing. Drain and Haste Samba
    still want their TP, though they don't spend it. Finishing moves past five
    show as one status, Finishing Move (6+), which counts as five for Reverse
    Flourish and No Foot Rise.
]]--

local dnc = {}

dnc.TRANCE = 376

-- The TP `a` needs from you now: none under Trance for a waltz or Aspir Samba.
function dnc.tp(a, g)
    if a.trance and g.me.buffs[dnc.TRANCE] then return 0 end
    return math.max(a.tp or 0, 0)
end

return dnc
