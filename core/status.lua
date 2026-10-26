-- Status ids more than one module reads; each module keeps the ones only it reads.
return {
    INVISIBLE = 69,      -- any action breaks it: only danger healing and travel buffs go under it (core/engine.lua)
    SLEEP = { 2, 19 },   -- Sleep, Sleep II: a heal of yours wakes
    REGEN = 42,
    DOOM = 15,           -- kills: always removed, whatever Debuff removal's chips say (behaviors/remove.lua)
}
