-- Test runner, from the repo root:
--   luajit tests/run.lua              every tests/*_test.lua
--   luajit tests/run.lua catalog      one file
package.path = './?.lua;' .. package.path

local pass, fail, current = 0, 0, nil

local function dump(v)
    if type(v) ~= 'table' then return tostring(v) end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. '=' .. dump(x) end
    table.sort(parts)
    return '{' .. table.concat(parts, ', ') .. '}'
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function eq(actual, expected, msg)
    if not same(actual, expected) then
        error(('%s\n  expected: %s\n  actual:   %s'):format(msg or 'eq', dump(expected), dump(actual)), 2)
    end
end

function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; print(('FAIL %s :: %s\n  %s'):format(current, name, tostring(err))) end
end

local files = {}
if arg[1] then
    files[1] = arg[1]:gsub('^tests[/\\]', ''):gsub('%.lua$', ''):gsub('_test$', '') .. '_test.lua'
else
    local windows = package.config:sub(1, 1) == '\\'
    for f in io.popen(windows and 'dir /b tests' or 'ls tests'):lines() do
        if f:match('_test%.lua$') then files[#files + 1] = f end
    end
    table.sort(files)
end

for _, f in ipairs(files) do
    current = f
    local ok, err = pcall(dofile, 'tests/' .. f)
    if not ok then fail = fail + 1; print(('FAIL %s :: could not load\n  %s'):format(f, tostring(err))) end
end
print(('total: %d passed, %d failed'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
