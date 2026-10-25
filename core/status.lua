-- Status ids more than one module reads; each module keeps the ones only it reads.
return {
    INVISIBLE = 69,      -- any action breaks it: only danger healing and travel buffs go under it (can.hidden)
    SNEAK = 71,          -- nothing breaks it, but it's kept as quiet as Invisible
    SLEEP = { 2, 19 },   -- Sleep, Sleep II: a heal of yours wakes
    REGEN = 42,
}
