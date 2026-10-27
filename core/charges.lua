--[[
    Charge pools: abilities sharing one recast timer that counts down to every
    charge back (SCH's stratagems, BST's Ready moves):
        { job, kind, recast (the timer's id), tiers = { { level, charges, seconds per charge }, ... } }
    tiers by your level in the job, highest first. An action is usable once the
    charges it costs (a.charges, 1 if nil) are back, not only at a full pool.
]]--

local charges = {}
charges.__index = charges

function charges.pool(p) return setmetatable(p, charges) end

function charges:tier(lv)
    for _, t in ipairs(self.tiers) do
        if lv >= t[1] then return t end
    end
end

-- Whether catalog record `a` draws on this pool.
function charges:spends(a) return a.kind == self.kind and a.recast == self.recast end

-- Charges banked, from the pool timer's seconds and your level in the job.
function charges:banked(seconds, lv)
    local t = self:tier(lv)
    return t and math.max(0, t[2] - math.ceil(seconds / t[3])) or 0
end

-- The wait until `n` charges (1 if nil) are banked, from the pool timer's seconds.
function charges:wait(seconds, lv, n)
    local t = self:tier(lv)
    if not t then return seconds end
    return math.max(0, seconds - (t[2] - (n or 1)) * t[3])
end

return charges
