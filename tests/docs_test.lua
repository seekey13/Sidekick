-- README.md, ARCHITECTURE.md and ui/README.md kept in step with the code: every
-- /sk3 command documented, every module named, every link going somewhere.

local function read(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a')
    f:close()
    return s
end

local function exists(path)
    local f = io.open(path, 'rb')
    if f then f:close() end
    return f ~= nil
end

local function lua_files(dir)
    local windows = package.config:sub(1, 1) == '\\'
    local names = {}
    for f in io.popen(windows and ('dir /b ' .. dir) or ('ls ' .. dir)):lines() do
        local name = f:match('^(.-)%.lua$')
        if name then names[#names + 1] = name end
    end
    return names
end

-- GitHub's anchor for a heading: lower case, punctuation dropped, spaces to dashes.
local function anchor(heading)
    return (heading:lower():gsub('[^%w%- ]', ''):gsub(' ', '-'))
end

local readme, arch = read('README.md'), read('ARCHITECTURE.md')

test('every command /sk3 help lists is in the README\'s command list', function ()
    local literals = read('Sidekick3.lua'):match('local HELP = (.-)\n\n')
    local block = readme:match('## Commands\n\n```\n(.-)```')
    assert(literals and block, 'HELP or the README command block not found')
    local help = {}
    for part in literals:gmatch("'(.-)'") do help[#help + 1] = part end
    local missing, words = {}, 0
    for item in (table.concat(help):match('Commands: (.*)') .. ','):gmatch('(.-),%s*') do
        local word = item:match('^(%a+)')
        words = words + 1
        -- '/sk3 start | stop' documents both
        if not (block:find('/sk3 ' .. word, 1, true) or block:find('/sk3 %a+ | ' .. word .. '%f[%W]')) then
            missing[#missing + 1] = word
        end
    end
    assert(words > 10, 'HELP not parsed')
    eq(missing, {})
end)

test('ARCHITECTURE.md names every core module, behavior and job module', function ()
    local missing = {}
    for _, name in ipairs(lua_files('core')) do
        if not arch:find('core/' .. name .. '.lua', 1, true) then missing[#missing + 1] = 'core/' .. name end
    end
    local behaviors = arch:match('| `behaviors/%*%.lua` |([^\n]*)')
    for _, name in ipairs(lua_files('behaviors')) do
        if not behaviors:find('%f[%w]' .. name .. '%f[%W]') then missing[#missing + 1] = 'behaviors/' .. name end
    end
    local jobs = arch:match('| `jobs/%*%.lua` |([^\n]*)')
    for _, name in ipairs(lua_files('jobs')) do
        if not jobs:find('`' .. name .. '`', 1, true) then missing[#missing + 1] = 'jobs/' .. name end
    end
    eq(missing, {})
end)

test('every link in the docs leads to a file or a heading that exists', function ()
    local bad = {}
    for _, doc in ipairs({ 'README.md', 'ARCHITECTURE.md', 'ui/README.md' }) do
        local text, dir = read(doc), doc:match('^(.*/)') or ''
        local anchors = {}
        for heading in text:gmatch('\n#+ ([^\n]+)') do anchors[anchor(heading)] = true end
        for target in text:gmatch('%]%(([^)%s]+)%)') do
            if not target:match('^%a+://') then
                local file, frag = target:match('^([^#]*)#?(.*)$')
                if file == '' then
                    if not anchors[frag] then bad[#bad + 1] = doc .. ': ' .. target end
                elseif not exists(dir .. file) and not exists(dir .. file .. '/README.md') then
                    bad[#bad + 1] = doc .. ': ' .. target
                end
            end
        end
    end
    eq(bad, {})
end)
