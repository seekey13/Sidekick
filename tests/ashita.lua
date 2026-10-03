-- Fake Ashita v4 client for the tests. Loaded by tests/run.lua before any test file so
-- the real lib/ modules can be required as they are in game. Everything the modules read
-- (player, party, recasts, entities) comes from `fake.state`, which a test edits directly
-- and resets with fake.reset(). Only the calls Sidekick makes are implemented; a missing
-- method is a nil-call error that names what to add here.
local fake = {};

local function copy(t)
    local out = {};
    for k, v in pairs(t) do out[k] = type(v) == 'table' and copy(v) or v; end
    return out;
end

local default_state = {
    player = {
        main_job = 3, sub_job = 4, main_level = 75, sub_level = 37,
        buffs = {},          -- active buff ids, in slot order
        spells = {},         -- [spell_id] = true for known spells
        abilities = {},      -- [ability_id] = true for known abilities
    },
    -- [0..5] party slots; server_id, target_index, hp, mp, tp, name, active, zone
    party = {
        [0] = { name = 'Tester', server_id = 0x100, target_index = 0x400, hp = 1000, hp_pct = 100,
                mp = 500, mp_pct = 100, tp = 0, active = true, zone = 1,
                main_job = 3, main_level = 75, sub_job = 4, sub_level = 37 },
    },
    spell_recasts = {},      -- [spell_id] = timer in 1/60 s; absent = ready
    ability_recasts = {},    -- [recast_id] = timer in 1/60 s; absent = never started
    entities = {},           -- [target_index] = { ServerId, Name, HPPercent, Movement.LocalPosition, ... }
    target_index = 0,        -- current <t>
    commands = {},           -- every QueueCommand, oldest first
    strings = {},            -- [table] = { [id] = name } for GetResourceManager():GetString
    -- [kind] = { [english name] = resource } for Get{Spell,Ability,Item}ByName (English langId 2 only)
    resources = { spells = {}, abilities = {}, items = {} },
    inventory = {},          -- [container] = list of { Id, Count }; GetContainerItem is 0-based
    inventory_reads = 0,     -- GetContainerItem calls, so a test can see a container walk
};

function fake.reset()
    fake.state = copy(default_state);
    fake.state.entities[0x400] = fake.entity({ ServerId = 0x100, Name = 'Tester', TargetIndex = 0x400 });
end

-- An entity table with the fields Sidekick reads, defaulting to a standing, alive player.
function fake.entity(fields)
    local e = {
        ServerId = 0, TargetIndex = 0, Name = '', Type = 0, Status = 0, SpawnFlags = 0x0001,
        HPPercent = 100, PetTargetIndex = 0, FellowTargetIndex = 0, ActorPointer = 1,
        Movement = { LocalPosition = { X = 0, Y = 0, Z = 0 } },
        Render = { Flags0 = 0 },
    };
    for k, v in pairs(fields or {}) do e[k] = v; end
    return e;
end

-- Globals Ashita injects before an addon loads.

addon = { name = 'Sidekick', author = '', version = '0.0.0', desc = '', link = '' };

-- T{} from Ashita's common lib: a table with table.* and a few list helpers as methods.
local tmeta = { __index = {} };
for k, v in pairs(table) do tmeta.__index[k] = v; end
function tmeta.__index.all(t, fn)
    for _, v in pairs(t) do if not fn(v) then return false; end end
    return true;
end
function tmeta.__index.any(t, fn)
    for _, v in pairs(t) do if fn(v) then return true; end end
    return false;
end
function tmeta.__index.contains(t, x)
    for _, v in pairs(t) do if v == x then return true; end end
    return false;
end
function tmeta.__index.each(t, fn) for k, v in pairs(t) do fn(v, k); end return t; end
function tmeta.__index.map(t, fn)
    local out = T{};
    for k, v in pairs(t) do out[k] = fn(v); end
    return out;
end
function tmeta.__index.filter(t, fn)
    local out = T{};
    for _, v in ipairs(t) do if fn(v) then table.insert(out, v); end end
    return out;
end
function tmeta.__index.append(t, v) table.insert(t, v); return t; end
function tmeta.__index.len(t) return #t; end
function tmeta.__index.keys(t)
    local out = T{};
    for k in pairs(t) do table.insert(out, k); end
    return out;
end
function T(t) return setmetatable(t or {}, tmeta); end

function table.range(from, to)
    local out = T{};
    for i = from, to do table.insert(out, i); end
    return out;
end

function GetEntity(index) return fake.state.entities[index]; end
function GetPlayerEntity() return fake.state.entities[fake.state.party[0].target_index]; end

ashita = {
    memory = {
        find = function() return 1; end,   -- non-zero so lib/core/targets.lua's pointer check passes
        read_uint = function() return 0; end,
        read_array = function() return {}; end,
    },
    events = { register = function() end, unregister = function() end },
    fs = { get_dir = function() return {}; end, exists = function() return false; end, create_dir = function() end },
    bits = { unpack_be = function() return 0; end },
};

-- Ashita's struct lib: only the fixed-width reads the packet parsers use.
struct = {
    unpack = function(fmt, data, pos)
        local n = ({ B = 1, H = 2, i4 = 4 })[fmt];
        local v = 0;
        for i = n, 1, -1 do v = v * 256 + data:byte(pos + i - 1); end
        if fmt == 'i4' and v >= 0x80000000 then v = v - 0x100000000; end
        return v, pos + n;
    end,
};

local function player()
    local p = fake.state.player;
    return {
        GetMainJob = function() return p.main_job; end,
        GetSubJob = function() return p.sub_job; end,
        GetMainJobLevel = function() return p.main_level; end,
        GetSubJobLevel = function() return p.sub_level; end,
        HasSpell = function(_, id) return p.spells[id] == true; end,
        HasAbility = function(_, id) return p.abilities[id] == true; end,
        GetBuffs = function()
            local out = {};
            for i = 1, 32 do out[i] = p.buffs[i] or 255; end
            return out;
        end,
    };
end

local function party()
    local function member(i) return fake.state.party[i] or {}; end
    local function field(name, default)
        return function(_, i) local v = member(i)[name]; if v == nil then return default; end return v; end
    end
    return {
        GetMemberIsActive = function(_, i) return member(i).active and 1 or 0; end,
        GetMemberServerId = field('server_id', 0),
        GetMemberTargetIndex = field('target_index', 0),
        GetMemberName = field('name', ''),
        GetMemberHP = field('hp', 0),
        GetMemberHPPercent = function(_, i)
            local row = member(i)
            if row.hp_pct_read == 'nil' then return nil end
            if row.hp_pct_read == 'error' then error('HPP read failed') end
            local value = row.hp_pct
            if value == nil then return 0 end
            return value
        end,
        GetMemberMP = field('mp', 0),
        GetMemberMPPercent = field('mp_pct', 0),
        GetMemberTP = field('tp', 0),
        GetMemberZone = field('zone', 0),
        GetMemberMainJob = field('main_job', 0),
        GetMemberMainJobLevel = field('main_level', 0),
        GetMemberSubJob = field('sub_job', 0),
        GetMemberSubJobLevel = field('sub_level', 0),
        GetMemberPointer = function() return 1; end,
    };
end

-- The ability recast list is 32 slots of (timer id, timer); slot order follows the
-- order the test filled ability_recasts in.
local function recast()
    local function slots()
        local ids = {};
        for id in pairs(fake.state.ability_recasts) do table.insert(ids, id); end
        table.sort(ids);
        return ids;
    end
    return {
        GetSpellTimer = function(_, id) return fake.state.spell_recasts[id] or 0; end,
        GetAbilityTimerId = function(_, slot) return slots()[slot + 1] or 0; end,
        GetAbilityTimer = function(_, slot)
            local id = slots()[slot + 1];
            return id and fake.state.ability_recasts[id] or 0;
        end,
    };
end

local function target()
    return {
        GetTargetIndex = function() return fake.state.target_index; end,
        GetIsSubTargetActive = function() return 0; end,
        GetFocusTargetIndex = function() return 0; end,
    };
end

local function entity()
    local function field(name, default)
        return function(_, i)
            local e = fake.state.entities[i];
            local v = e and e[name];
            if v == nil then return default; end
            return v;
        end
    end
    local function pos(axis)
        return function(_, i)
            local e = fake.state.entities[i];
            return e and e.Movement.LocalPosition[axis] or 0;
        end
    end
    return {
        GetServerId = field('ServerId', 0), GetName = field('Name', ''),
        GetHPPercent = field('HPPercent', 0), GetSpawnFlags = field('SpawnFlags', 0),
        GetClaimStatus = field('ClaimStatus', 0), GetDistance = field('Distance', 0),
        GetTargetIndex = field('TargetIndex', 0), GetType = field('Type', 0),
        GetLocalPositionX = pos('X'), GetLocalPositionY = pos('Y'), GetLocalPositionZ = pos('Z'),
    };
end

local function inventory()
    return {
        GetContainerCountMax = function(_, c)
            local items = fake.state.inventory[c];
            return items and #items or 0;
        end,
        GetContainerItem = function(_, c, i)
            fake.state.inventory_reads = fake.state.inventory_reads + 1;
            local items = fake.state.inventory[c];
            return items and items[i + 1] or { Id = 0, Count = 0 };
        end,
        GetEquippedItem = function() return { Index = 0 }; end,
    };
end

AshitaCore = {
    GetMemoryManager = function()
        return {
            GetPlayer = player, GetParty = party, GetRecast = recast, GetTarget = target,
            GetEntity = entity, GetInventory = inventory,
            GetAutoFollow = function() return { GetIsAutoRunning = function() return 0; end }; end,
        };
    end,
    GetResourceManager = function()
        return {
            GetString = function(_, tbl, id)
                local t = fake.state.strings[tbl];
                return t and t[id] or nil;
            end,
            GetSpellById = function() return nil; end,
            GetItemById = function() return nil; end,
            GetSpellByName = function(_, name, lang_id) return lang_id == 2 and fake.state.resources.spells[name] or nil; end,
            GetAbilityByName = function(_, name, lang_id) return lang_id == 2 and fake.state.resources.abilities[name] or nil; end,
            GetItemByName = function(_, name, lang_id) return lang_id == 2 and fake.state.resources.items[name] or nil; end,
        };
    end,
    GetChatManager = function()
        return { QueueCommand = function(_, _, cmd) table.insert(fake.state.commands, cmd); end };
    end,
    GetPointerManager = function() return { Get = function() return 0; end }; end,
    GetInstallPath = function() return ''; end,
};

-- Ashita library modules the addon requires.
local function identity(s) return s; end
package.preload['common'] = function() return {}; end
package.preload['win32types'] = function() return {}; end
package.preload['chat'] = function()
    return {
        header = function(name) return '[' .. name .. '] '; end,
        message = identity, error = identity, warning = identity, success = identity,
        color1 = function(_, s) return s; end, color2 = function(_, s) return s; end,
    };
end
package.preload['settings'] = function()
    return {
        load = function(defaults) return copy(defaults); end,
        save = function() return true; end,
        register = function() end,
    };
end
-- Any imgui call is a no-op returning false unless a focused UI test supplies a handler.
package.preload['imgui'] = function()
    return setmetatable({}, { __index = function(_, name)
        return function(...)
            local handler = fake.imgui and fake.imgui[name];
            if handler then return handler(...); end
            return false;
        end;
    end });
end

-- get_bt calls into FFXiMain through an ffi function pointer; the fake's is address 1,
-- a crash no pcall can catch. refresh_game_state samples <bt> movement, so stub it.
require('lib.core.targets').get_bt = function() return nil; end

fake.reset();
return fake;
