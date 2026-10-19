-- README.md, ARCHITECTURE.md and ui/README.md kept in step with the code: every
-- /sk3 command documented, every module named, every link going somewhere.

-- A Windows checkout may have CRLF line ends: the patterns below expect \n.
local function read(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a')
    f:close()
    return (s:gsub('\r\n', '\n'))
end

-- A file, not a directory (which opens on Linux but reads nil).
local function exists(path)
    local f = io.open(path, 'rb')
    if not f then return false end
    local ok = f:read(0) ~= nil or f:seek('end') == 0
    f:close()
    return ok
end

local function lua_files(dir)
    local windows = package.config:sub(1, 1) == '\\'
    local names = {}
    for f in io.popen(windows and ('dir /b ' .. dir) or ('ls ' .. dir)):lines() do
        local name = f:match('^(.-)%.lua\r?$')
        if name then names[#names + 1] = name end
    end
    assert(#names > 0, 'no Lua files listed in ' .. dir)
    return names
end

-- The text outside fenced code blocks, so a `# comment` in one is no heading.
local function prose(text)
    return (('\n' .. text):gsub('\n```.-\n```', '\n'))
end

-- GitHub's anchors for a doc's headings: lower case, punctuation but - and _
-- dropped, spaces to dashes; a repeated heading gets -1, -2...
local function anchors(text)
    local set, seen = {}, {}
    for heading in prose(text):gmatch('\n#+ ([^\n]+)') do
        local a = heading:lower():gsub('[^%w%-_ \128-\255]', ''):gsub(' ', '-')
        set[seen[a] and (a .. '-' .. seen[a]) or a] = true
        seen[a] = (seen[a] or 0) + 1
    end
    return set
end

local readme, arch = read('README.md'), read('ARCHITECTURE.md')

test('every /sk3 command is in /sk3 help and the README\'s command list, and back', function ()
    local main = read('Sidekick3.lua')
    local literals = main:match('local HELP = (.-)\n\n')
    local block = readme:match('## Commands\n\n```\n(.-)```')
    assert(literals and block, 'HELP or the README command block not found')
    local help = {}
    for part in literals:gmatch("'(.-)'") do help[#help + 1] = part end
    local listed = {}
    for item in (table.concat(help):match('Commands: (.*)') .. ','):gmatch('(.-),%s*') do
        listed[assert(item:match('^(%a+)'), 'HELP item with no command: ' .. item)] = true
    end
    local handled = {}
    for word in main:gmatch("sub == '(%a+)'") do handled[word] = true end
    local documented = {}
    for line in block:gmatch('[^\n]+') do
        -- '/sk3 start | stop Name' documents both
        local words = line:match('^/sk3 ([%a |]*)')
        for word in (words or ''):gmatch('%a+') do
            if word == word:lower() then documented[word] = true end
        end
    end
    local wrong = {}
    for word in pairs(handled) do
        if not listed[word] then wrong[#wrong + 1] = word .. ' not in /sk3 help' end
        if not documented[word] then wrong[#wrong + 1] = word .. ' not in the README' end
    end
    for word in pairs(listed) do
        if not handled[word] then wrong[#wrong + 1] = word .. ' in /sk3 help but not handled' end
    end
    assert(next(handled), 'no commands found in Sidekick3.lua')
    table.sort(wrong)
    eq(wrong, {})
end)

test('ARCHITECTURE.md names every module', function ()
    local missing = {}
    for _, dir in ipairs({ 'core', 'ui', 'tools' }) do
        for _, name in ipairs(lua_files(dir)) do
            local path = dir .. '/' .. name .. '.lua'
            if name ~= 'custom' and not arch:find(path, 1, true) then missing[#missing + 1] = path end
        end
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
    local docs = { 'README.md', 'ARCHITECTURE.md', 'ui/README.md' }
    local texts, heads = {}, {}
    for _, doc in ipairs(docs) do
        texts[doc] = read(doc)
        heads[doc] = anchors(texts[doc])
    end
    local bad, links = {}, 0
    for _, doc in ipairs(docs) do
        local dir = doc:match('^(.*/)') or ''
        for target in prose(texts[doc]):gmatch('%]%((.-)%)') do
            target = target:match('^<(.-)>') or target:match('^(%S*)')  -- drop a "title"
            if not target:match('^%a+:') then
                links = links + 1
                local file, frag = target:match('^([^#]*)#?(.*)$')
                -- Normalise ../ so a link to another doc finds its anchors.
                local path = (dir .. file):gsub('[^/]+/%.%./', '')
                local ok
                if file == '' then ok = heads[doc][frag]
                elseif file:find('%20', 1, true) then ok = false
                elseif not exists(path) then ok = exists(path .. '/README.md') and frag == ''
                else ok = frag == '' or (heads[path] and heads[path][frag]) or (not heads[path] and frag:match('^L%d')) end
                if not ok then bad[#bad + 1] = doc .. ': ' .. target end
            end
        end
    end
    assert(links > 10, 'no links found')
    eq(bad, {})
end)
