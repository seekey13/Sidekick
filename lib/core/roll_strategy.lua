--[[
    Roll strategy (Corsair) -- the Double-Up / Snake Eye / Fold decision math.

    Deliberately dependency-free: no common, no action_core, no AshitaCore. Primitives
    in, primitives out, so roll_strategy.self_test() can exercise every branch inside
    Ashita's own Lua VM without a live roll sequence (/sidekick roll_test).

    Everything stateful -- packet totals, buff reads, throttles, command building --
    stays in lib/actions/roll.lua, which calls decide() once per eligible tick.

    Tiers ('lowest' / 'medium' / 'highest') are rule-based rather than
    expected-value based: only one real per-total payoff table is confirmed
    (Corsair's Roll), so the rules lean on bust probability and reachability, which
    are exact, instead of guessed payoffs for the other 24 rolls.
]]--

local roll_strategy = {}

local unpack = unpack or table.unpack

-- A die is 1-6, so any total <= 5 cannot bust (worst case 5 + 6 = 11).
local ZERO_RISK_MAX = 5
-- Bust is anything over 11, so 11 is the ceiling and 10 is the last total a forced
-- Snake Eye die (always 1) can finish off with no risk at all.
local MAX_TOTAL = 11
-- Past 8 a die busts more often than not, so an unlucky total is no longer worth
-- rerolling: 8 + 6 = 14, i.e. 3 of 6 faces bust.
local UNLUCKY_REROLL_MAX = 8

-- Is the lucky number still exactly one die away?
local function lucky_reachable(total, lucky)
    return lucky ~= nil and lucky > total and lucky <= total + 6
end

-- Medium's zone rule; Highest borrows it when Fold is on cooldown.
local function zone_decision(total, lucky, unlucky)
    if lucky_reachable(total, lucky) then
        return 'double'
    end

    -- Sitting exactly on unlucky is worth one more gamble while the bust chance is
    -- still <= 50%: nearly every other total beats unlucky, and Bust isn't much worse.
    if unlucky ~= nil and total == unlucky and total <= UNLUCKY_REROLL_MAX then
        return 'double'
    end

    -- Lucky is gone and we're not sitting on unlucky: bank it.
    return 'stop'
end

--[[
    Decide what to do with a roll sitting at a known total.

      total           - current roll total (1-11), from the 0x028 packet
      lucky / unlucky - the roll's own numbers (lib/jobs/corsair.lua)
      tier            - 'lowest' | 'medium' | 'highest' (settings.risk_tier)
      snake_eye_ready - Snake Eye is off cooldown and usable right now
      fold_ready      - Fold is off cooldown and usable right now

    Returns: 'stop' | 'double' | 'snake_eye_then_double'
]]--
function roll_strategy.decide(total, lucky, unlucky, tier, snake_eye_ready, fold_ready)
    tier = tier or 'medium'

    -- 1. Never gamble at 11 -- every die busts from here.
    if total >= MAX_TOTAL then
        return 'stop'
    end

    -- 2. Zero-risk zone: no die can bust, so roll on. Banking the lucky number here is
    --    only right for the tiers whose ceiling IS lucky. Highest is chasing 11 and
    --    gives lucky up to keep rolling -- which costs nothing at <= 5, since the worst
    --    a die can do from 5 is land on 11.
    if total <= ZERO_RISK_MAX then
        if total == lucky and tier ~= 'highest' then
            return 'stop'
        end
        return 'double'
    end

    -- 3. Snake Eye at 10 guarantees 11, the best total there is. No randomness, so
    --    every tier takes it, Lowest included.
    if snake_eye_ready and total == MAX_TOTAL - 1 then
        return 'snake_eye_then_double'
    end

    -- 4. Snake Eye at lucky-1 guarantees lucky. Its ~5 min recast outlasts a single
    --    roll chase, so spending it here forecloses case 3 later: only the tiers whose
    --    ceiling IS the lucky number spend it. Highest reserves it for the 11 finish.
    if snake_eye_ready and tier ~= 'highest' and lucky ~= nil and total == lucky - 1 then
        return 'snake_eye_then_double'
    end

    -- 5. Lowest never accepts an actual bust chance past the zero-risk zone. Fold
    --    being ready does not unlock gambling here -- that's Highest's job.
    if tier == 'lowest' then
        return 'stop'
    end

    -- 6. Highest chases 11 across the whole 6-10 range, but only while Fold can undo
    --    a Bust. Uninsured, it falls back to Medium's zone logic for this tick.
    if tier == 'highest' and fold_ready then
        return 'double'
    end

    return zone_decision(total, lucky, unlucky)
end

-- Universal and tier-independent: Bust (buff 309) costs a roll slot until it wears,
-- and Fold clears it outright, so take it the instant both are true.
function roll_strategy.should_fold(has_bust_buff, fold_ready)
    return (has_bust_buff and fold_ready) and true or false
end

-- ============================================================================
-- Self test (/sidekick roll_test)
-- ============================================================================

-- {total, lucky, unlucky, tier, snake_eye_ready, fold_ready}, expected, description
local DECIDE_CASES = {
    { { 11,  5, 9, 'highest', true,  true  }, 'stop',                  'never doubles at 11' },
    { {  3,  5, 9, 'lowest',  false, false }, 'double',                'zero-risk zone always doubles' },
    { {  5,  5, 9, 'medium',  true,  true  }, 'stop',                  'Medium banks lucky in the zero-risk zone' },
    { {  5,  5, 9, 'lowest',  true,  true  }, 'stop',                  'Lowest banks lucky in the zero-risk zone' },
    { {  5,  5, 9, 'highest', false, false }, 'double',                'Highest gives up lucky to chase 11 (no bust risk at 5)' },
    { {  3,  3, 7, 'highest', false, false }, 'double',                'Highest rolls through lucky even with Fold down' },
    { { 10,  5, 9, 'lowest',  true,  false }, 'snake_eye_then_double', 'Snake Eye finishes 10 -> 11 on every tier' },
    { { 10,  5, 9, 'lowest',  false, false }, 'stop',                  'Lowest stops at 10 without Snake Eye' },
    { {  6,  4, 8, 'lowest',  false, true  }, 'stop',                  'Lowest will not gamble even with Fold up' },
    { {  7,  8, 2, 'medium',  true,  false }, 'snake_eye_then_double', 'Medium spends Snake Eye at lucky-1' },
    { {  7,  8, 2, 'highest', true,  false }, 'double',                'Highest reserves Snake Eye for 10, doubles instead' },
    { {  6, 10, 7, 'medium',  false, false }, 'double',                'Medium chases a reachable lucky' },
    { {  6,  4, 9, 'medium',  false, false }, 'stop',                  'Medium banks once lucky is unreachable' },
    { {  8,  4, 8, 'medium',  false, false }, 'double',                'Medium rerolls off unlucky at <= 50% bust' },
    { {  9,  5, 9, 'medium',  false, false }, 'stop',                  'Medium sits on unlucky past 50% bust' },
    { {  7,  4, 8, 'highest', false, true  }, 'double',                'Highest chases 11 while Fold insures it' },
    { {  7,  4, 8, 'highest', false, false }, 'stop',                  'Highest falls back to Medium without Fold' },
}

-- {has_bust_buff, fold_ready}, expected, description
local FOLD_CASES = {
    { { true,  true  }, true,  'Fold on Bust when ready' },
    { { true,  false }, false, 'no Fold while on cooldown' },
    { { false, true  }, false, 'no Fold without a Bust' },
}

-- Prints PASS/FAIL per case via `log` (defaults to print). Returns passed, failed.
function roll_strategy.self_test(log)
    log = log or print
    local passed, failed = 0, 0

    local function check(got, expect, desc)
        if got == expect then
            passed = passed + 1
            log(string.format('PASS  %s', desc))
        else
            failed = failed + 1
            log(string.format('FAIL  %s (expected %s, got %s)', desc, tostring(expect), tostring(got)))
        end
    end

    for _, case in ipairs(DECIDE_CASES) do
        check(roll_strategy.decide(unpack(case[1], 1, 6)), case[2], case[3])
    end
    for _, case in ipairs(FOLD_CASES) do
        check(roll_strategy.should_fold(unpack(case[1], 1, 2)), case[2], case[3])
    end

    log(string.format('roll_strategy: %d passed, %d failed', passed, failed))
    return passed, failed
end

return roll_strategy
