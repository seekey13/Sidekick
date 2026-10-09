local fake = require('tests.ashita');
local common = require('lib.core.common');

-- Mute the "Now tracking" / "Stopped tracking" chat lines.
local real_printf = common.printf;
common.printf = function() end;

-- The rescan throttle reads os.clock; freeze it so a test controls elapsed time.
local now = 100;
local real_clock = os.clock;
os.clock = function() return now; end

local SID = 0x200;

-- Counts every entity-slot read (GetEntity and the entity manager's getters both index
-- fake.state.entities), so a test can tell a cached lookup from a full table scan.
local reads;
local function reset()
    fake.reset();
    for sid in pairs(common.get_tracked_targets()) do common.remove_tracked_target(sid); end
    now = now + 1000;   -- far past any earlier rescan
    local real = fake.state.entities;
    reads = 0;
    fake.state.entities = setmetatable({}, {
        __index = function(_, k) reads = reads + 1; return real[k]; end,
        __newindex = real,
    });
end

local function refresh()
    reads = 0;
    common.refresh_game_state();
    return reads;
end

local function track(index, sid)
    local e = fake.entity({ ServerId = sid or SID, Name = 'Other', TargetIndex = index });
    fake.state.entities[index] = e;
    common.add_tracked_target(e, { main_level = 75 });
end

test('a tracked target at its cached index is read without a scan', function()
    reset();
    track(0x401);
    local n = refresh();
    assert_eq(common.game_state.tracked[SID].is_active, true);
    assert_eq(n < 20, true, 'slot reads: ' .. n);
end);

test('tracked HPP accepts only percentages from zero through one hundred', function()
    for _, value in ipairs({ -1, 101, 0, 55, math.huge, -math.huge, 0 / 0 }) do
        reset();
        track(0x401);
        fake.state.entities[0x401].HPPercent = value;
        refresh();
        local valid = value == value and value >= 0 and value <= 100;
        local t = common.game_state.tracked[SID];
        assert_eq({ t.hpp, t.hpp_valid }, { valid and value or 0, valid });
    end
    reset();
    track(0x401);
    fake.state.entities[0x401].HPPercent = nil;
    refresh();
    local t = common.game_state.tracked[SID];
    assert_eq({ t.hpp, t.hpp_valid }, { 0, false });
end);

test('a missing tracked target rescans at most once a second', function()
    reset();
    track(0x401);
    fake.state.entities[0x401] = nil;
    assert_eq(refresh() > 0x800, true, 'first miss scans');
    assert_eq(common.game_state.tracked[SID].is_active, false);
    now = now + 0.5;
    assert_eq(refresh() < 20, true, 'no second scan inside the interval');
    now = now + 0.5;
    assert_eq(refresh() > 0x800, true, 'scans again once the interval passes');
end);

test('a target back in range at its cached index is picked up before the next scan', function()
    reset();
    track(0x401);
    fake.state.entities[0x401] = nil;
    refresh();
    now = now + 0.1;
    fake.state.entities[0x401] = fake.entity({ ServerId = SID, Name = 'Other', TargetIndex = 0x401 });
    assert_eq(refresh() < 20, true);
    assert_eq(common.game_state.tracked[SID].is_active, true);
end);

test('a target whose slot now holds another player is found again by the scan', function()
    reset();
    track(0x401);
    fake.state.entities[0x401] = fake.entity({ ServerId = 0x300, Name = 'Someone', TargetIndex = 0x401 });
    fake.state.entities[0x402] = fake.entity({ ServerId = SID, Name = 'Other', TargetIndex = 0x402 });
    refresh();
    local t = common.game_state.tracked[SID];
    assert_eq({ t.is_active, t.target_index }, { true, 0x402 });
end);

test('two missing tracked targets share one scan', function()
    reset();
    track(0x401);
    track(0x403, SID + 1);
    fake.state.entities[0x401] = nil;
    fake.state.entities[0x403] = nil;
    local n = refresh();
    assert_eq(n > 0x800 and n < 0x1000, true, 'slot reads: ' .. n);
end);

for sid in pairs(common.get_tracked_targets()) do common.remove_tracked_target(sid); end
os.clock = real_clock;
common.printf = real_printf;
