--[[
    Shared Party List

    Two Sidekick sessions on the same PC share party rosters through small text
    files. Every session publishes its own party to
    config/addons/sidekick/party_<CharName>.txt, and every session reads every *other*
    published file, tracking the players listed there.

    So the box healing from outside the party has to do nothing at all: whoever it is
    boxing with publishes their party, and it gets tracked automatically, kept in sync
    as members join and leave. Discovery is by directory listing -- there is no host to
    nominate and nothing to configure.

    The roster carries each member's job, sub job, levels and max HP, because the
    publisher is *in* the party and reads those for real. That replaces both of the
    guesses a hand-added tracked target has to live with: the /check round-trip for
    job/level (which needs the target in range) and the AVERAGE_HP_BY_LEVEL estimate
    for max HP (non-party entities expose only HP percent).

    Auto-added entries are tagged with the name of the character whose file listed them
    (tracked_targets[sid].auto) and are the only ones this module ever removes --
    hand-added targets are never touched.
]]--

local common = require('lib.core.common')

local party_share = {}

local POLL_INTERVAL = 2.0   -- Seconds between publish/sync passes
local next_poll     = 0
local last_roster   = nil   -- Text last written, so an unchanged party is a no-op
local my_file       = nil   -- Path this session publishes to, for cleanup on unload

-- config/addons/sidekick/ is created by the settings module at load, so there is
-- nothing to mkdir here.
local function shared_dir()
    return string.format('%s\\config\\addons\\sidekick\\', AshitaCore:GetInstallPath())
end

local function shared_path(name)
    return string.format('%sparty_%s.txt', shared_dir(), name)
end

--[[
    Publishing
]]--

-- One line per active party slot, numeric fields first so the name stays unambiguous last:
--
--   <server_id> <main_job> <sub_job> <main_level> <sub_level> <max_hp> <name>
--
-- Read straight off game_state, which the tick already refreshed: a member's own party
-- list carries their real job/level, and max_hp is the observed-at-100% cache rather
-- than an hp/hpp derivation, so the value is stable and doesn't churn the file.
-- 0 means unknown (an /anon member publishes job 0 / level 0, same as a failed /check).
-- Trusts are left out: they are only targetable by their owner's own party, so they are
-- useless to the box reading this file.
-- nil while game_state isn't populated (zoning) -- publishing nothing beats an empty roster.
local function roster_lines()
    local gs = common.game_state
    if not gs or not gs.player then return nil end

    local lines = {}
    for i = 0, 5 do
        local m = (i == 0) and gs.player or (gs.party and gs.party[i])
        if m and m.is_active ~= false and not m.is_trust
            and m.server_id and m.server_id > 0 and m.name and m.name ~= '' then
            table.insert(lines, string.format('%d %d %d %d %d %d %s',
                m.server_id,
                m.job or 0, m.sub_job or 0,
                m.main_level or 0, m.sub_level or 0,
                m.max_hp or 0,
                m.name))
        end
    end

    if #lines == 0 then return nil end
    return lines
end

local function publish(my_name)
    local lines = roster_lines()
    if not lines then return end

    local text = table.concat(lines, '\n') .. '\n'
    if text == last_roster then return end

    local path = shared_path(my_name)
    local f = io.open(path, 'w')
    if not f then return end
    f:write(text)
    f:close()

    my_file     = path
    last_roster = text
    common.debugf('[PartyShare] Published %d member(s) to %s', #lines, path)
end

--[[
    Reading
]]--

-- Returns { [server_id] = {name, main_job, sub_job, main_level, sub_level, max_hp} } for a
-- published roster, or nil when there is no file or it parsed empty (caught mid-rewrite).
-- nil never drives removals -- see sync().
local function read_roster(owner)
    local f = io.open(shared_path(owner), 'r')
    if not f then return nil end

    local members = {}
    local found   = false
    for line in f:lines() do
        local sid, job, sub, mlvl, slvl, mhp, member =
            line:match('^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (.+)$')
        if sid then
            members[tonumber(sid)] = {
                name       = member,
                main_job   = tonumber(job),
                sub_job    = tonumber(sub),
                main_level = tonumber(mlvl),
                sub_level  = tonumber(slvl),
                max_hp     = tonumber(mhp),
            }
            found = true
        end
    end
    f:close()

    if not found then return nil end
    return members
end

-- Every roster published on this PC except our own, as { [owner name] = roster }.
-- ashita.fs.get_dir returns bare file names; the owner is what sits between the
-- 'party_' prefix and the extension. The listing is taken unfiltered ('.*') and narrowed
-- with a Lua pattern below -- get_dir's filter is a C++ std::regex, and there is no reason
-- to depend on its dialect for a match we have to make anyway to pull the owner out.
local function read_all_rosters(my_name)
    local rosters = {}

    local ok, files = pcall(function()
        return ashita.fs.get_dir(shared_dir(), '.*', true)
    end)
    if not ok or not files then return rosters end

    for _, file in ipairs(files) do
        local owner = tostring(file):match('^party_(.+)%.txt$')
        if owner and owner ~= my_name then
            local roster = read_roster(owner)
            if roster then rosters[owner] = roster end
        end
    end
    return rosters
end

-- Locate loaded entities for a set of server ids in one pass over the entity table
-- (one scan for the whole set, not one per member). Returns
-- [server_id] = stand-in table carrying the three fields common.add_tracked_target reads.
-- Players absent from our client's entity table -- out of range, another zone -- are simply
-- missing from the result and retried next poll, so HP and buff reads are never made
-- against a phantom entry.
local function find_entities(server_ids)
    local found = {}
    local ent   = common.get_entity_manager()
    if not ent then return found end

    for idx = 1, 0x8FF do
        local sid = ent:GetServerId(idx)
        if sid and server_ids[sid] then
            local name = ent:GetName(idx)
            if name and name ~= '' then
                found[sid] = { ServerId = sid, Name = name, TargetIndex = idx }
            end
        end
    end
    return found
end

-- Our own party's server ids, our own included (slot 0). Anything in here is already
-- covered by the normal party path and must never become a tracked target.
local function my_party_sids()
    local sids  = {}
    local party = common.get_party()
    if not party then return sids end

    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            sids[party:GetMemberServerId(i)] = true
        end
    end
    return sids
end

--[[
    Syncing
]]--

local function sync(my_name)
    local tracked = common.get_tracked_targets()
    local mine    = my_party_sids()

    local wanted     = {}  -- [server_id] = owner name that vouched for this member
    local infos      = {}  -- [server_id] = roster entry
    local live_owner = {}  -- Owners whose file read back with members this pass
    for owner, roster in pairs(read_all_rosters(my_name)) do
        live_owner[owner] = true
        for sid, info in pairs(roster) do
            if not mine[sid] then
                wanted[sid] = owner
                infos[sid]  = info
            end
        end
    end

    -- Drop auto entries a live owner's file no longer lists. An owner that stopped
    -- publishing (logged out, unloaded) is deliberately not live, so its members stay
    -- tracked rather than being wiped by a file that is merely absent -- the same
    -- guard covers a read that caught the file mid-rewrite.
    local stale = {}
    for sid, tt in pairs(tracked) do
        if tt.auto and live_owner[tt.auto] and wanted[sid] ~= tt.auto then
            table.insert(stale, sid)
        end
    end
    for _, sid in ipairs(stale) do
        common.remove_tracked_target(sid)
    end

    -- Refresh what the roster knows onto entries we already hold, so a level-up or a
    -- job change on the other box lands here too (the file is rewritten whenever any
    -- published field changes, so this only ever runs on real changes). Hand-added
    -- targets have no .auto and keep their own checked data.
    for sid, owner in pairs(wanted) do
        local tt = tracked[sid]
        if tt and tt.auto then
            tt.auto = owner
            common.set_tracked_target_info(sid, infos[sid])
            common.set_member_max_hp(sid, infos[sid].max_hp)
        end
    end

    -- Add everything still missing. No /check is sent for a roster-driven add, so there is
    -- nothing to stagger and the whole party can land in one pass.
    local missing = {}
    local any     = false
    for sid, _ in pairs(wanted) do
        if not tracked[sid] then
            missing[sid] = true
            any = true
        end
    end
    if not any then return end

    for sid, entity in pairs(find_entities(missing)) do
        if common.add_tracked_target(entity, infos[sid]) then
            tracked[sid].auto = wanted[sid]
            common.set_member_max_hp(sid, infos[sid].max_hp)
        end
    end
end

--[[
    Public
]]--

function party_share.tick()
    local now = os.clock()
    if now < next_poll then return end
    next_poll = now + POLL_INTERVAL

    -- Our own character name keys both halves: the file we write, and the one file in
    -- the directory we must not read back.
    local my_name = common.get_party_member_name(0)
    if not my_name or my_name == '' then return end

    publish(my_name)
    sync(my_name)
end

-- Drop our published file so a closed session doesn't leave a roster behind for
-- the other box to mirror.
function party_share.cleanup()
    if my_file then
        os.remove(my_file)
        my_file     = nil
        last_roster = nil
    end
end

return party_share
