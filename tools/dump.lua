--[[
    /sk3 dump: writes the client's spell, ability and status resources to
    tests/data/*.lua. The offline tests and the v2 parity check read these, so
    they run against the same DATs the game does. Rerun after a client update.
]]--

local resources = require('core.resources')

local dump = {}

-- Bytes outside printable ASCII become \ddd: Japanese names are Shift-JIS, and
-- the files should stay plain ASCII so they diff cleanly.
local function q(s)
    return '"' .. tostring(s or ''):gsub('.', function (c)
        local b = c:byte()
        if b < 32 or b > 126 or c == '"' or c == '\\' then
            return ('\\%03d'):format(b)
        end
    end) .. '"'
end

local function value(v)
    if type(v) == 'string' then return q(v) end
    if type(v) ~= 'table' then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = ('[%d]=%s'):format(k, value(v[k])) end
    return '{ ' .. table.concat(parts, ', ') .. ' }'
end

local function write(dir, name, rows)
    local fields = resources.FIELDS[name]
    local ids = {}
    for id in pairs(rows) do ids[#ids + 1] = id end
    table.sort(ids)

    local f = assert(io.open(dir .. name .. '.lua', 'wb'))
    f:write(('-- Generated in-game by /sk3 dump on %s; do not edit by hand.\n-- [id] = { %s }\nreturn {\n')
        :format(os.date('%Y-%m-%d'), table.concat(fields, ', ')))
    for _, id in ipairs(ids) do
        local parts = {}
        for _, k in ipairs(fields) do parts[#parts + 1] = k .. ' = ' .. value(rows[id][k]) end
        f:write(('    [%d] = { %s },\n'):format(id, table.concat(parts, ', ')))
    end
    f:write('}\n')
    f:close()
    return #ids
end

function dump.run(addon_path)
    local dir = addon_path:gsub('[\\/]+$', '') .. '\\tests\\data\\'
    if not ashita.fs.exists(dir) then ashita.fs.create_directory(dir) end
    local res = resources.load()
    return {
        spells    = write(dir, 'spells', res.spells),
        abilities = write(dir, 'abilities', res.abilities),
        statuses  = write(dir, 'statuses', res.statuses),
    }
end

return dump
