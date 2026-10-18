-- core/jobs.lua: the job modules' contract, and the rule that keeps jobs out of
-- the shared code: core/, behaviors/ and ui/ reach a job module only through it.
local jobs = require('core.jobs')

local windows = package.config:sub(1, 1) == '\\'
local function lua_files(dir)
    local out = {}
    for f in io.popen(windows and ('dir /b ' .. dir) or ('ls ' .. dir)):lines() do
        if f:match('%.lua$') then out[#out + 1] = dir .. '/' .. f end
    end
    return out
end

local function read(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a')
    f:close()
    return s
end

local function code(s)  -- without comments, so a comment may still point at jobs/geo.lua
    return (s:gsub('%-%-%[(=*)%[.-%]%1%]', ''):gsub('%-%-[^\n]*', ''))
end

test('core, behaviors and ui never require a job module or name a job (core/jobs.lua does)', function ()
    local found = {}
    for _, dir in ipairs({ 'core', 'behaviors', 'ui' }) do
        for _, path in ipairs(lua_files(dir)) do
            if path ~= 'core/jobs.lua' then
                local s = code(read(path))
                if s:find("require%s*%(?%s*['\"]jobs%.") then found[#found + 1] = path .. ': requires a job module' end
                if s:find('%.JOB%f[%W]') then found[#found + 1] = path .. ': compares against a job id' end
            end
        end
    end
    eq(found, {})
end)

local FIELDS = { JOB = 'number', knowledge = 'table', behaviors = 'table', settings = 'table', read = 'function',
                 recast = 'function', ability = 'function', zone = 'function', pet_auras = 'table',
                 spare = 'function', ui = 'table' }

test('every job module is in core/jobs.lua\'s list, and its contract fields are the documented ones', function ()
    local listed, wrong = {}, {}
    for _, j in ipairs(jobs.all) do listed[j] = true end
    for _, path in ipairs(lua_files('jobs')) do
        local j = require(path:gsub('%.lua$', ''):gsub('/', '.'))
        if not listed[j] then wrong[#wrong + 1] = path .. ': not in jobs.all' end
    end
    for _, j in ipairs(jobs.all) do
        for name, kind in pairs(FIELDS) do
            if j[name] ~= nil and type(j[name]) ~= kind then wrong[#wrong + 1] = ('job %s: %s is not a %s'):format(j.JOB, name, kind) end
        end
        for _, b in ipairs(j.behaviors or {}) do
            if type(b.name) ~= 'string' or type(b.run) ~= 'function' then wrong[#wrong + 1] = ('job %s: a behavior needs name and run'):format(j.JOB) end
        end
        if j.ui and not (j.ui.section and j.ui.section.id and type(j.ui.view) == 'function') then
            wrong[#wrong + 1] = ('job %s: ui needs a section and a view'):format(j.JOB)
        end
    end
    eq(wrong, {})
end)

test('the modules plug in where the shared code had them: rows, behaviors, settings, sections', function ()
    local K = require('core.knowledge')
    eq({ K['Penury'].chip, K['Corsair\'s Roll'].lucky, K['Geo-Regen'].luopan, type(K['Radial Arcana'].decide) },
       { 'Pen', 5, 'buff', 'function' })
    local names = {}
    for _, b in ipairs(require('core.engine').BEHAVIORS) do names[#names + 1] = b.name end
    eq(names, { 'heal', 'remove', 'wake', 'recover', 'pet', 'revive', 'roll', 'geo', 'buff', 'pet_send', 'follow', 'rest' })
    local d = require('core.settings').defaults()
    eq({ d.roll.risk, d.geo.distance }, { 'medium', 10 })
    local ids = {}
    for _, s in ipairs(require('ui.model').SECTIONS) do ids[#ids + 1] = s.id end
    eq(ids, { 'profile', 'follow', 'heal', 'revive', 'wake', 'remove', 'buff', 'roll', 'geo', 'pet', 'recover', 'rest', 'track', 'ui' })
end)
