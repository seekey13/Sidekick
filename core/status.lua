-- Status ids more than one module reads; each module keeps the ones only it reads.
return {
    INVISIBLE = 69,      -- nothing but a travel buff goes while you're Invisible: it would break it
    SLEEP = { 2, 19 },   -- Sleep, Sleep II: a heal of yours wakes
    REGEN = 42,
}
