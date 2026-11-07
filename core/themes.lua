--[[
    Themes: what draws Sidekick's windows (ui/README.md). Standard is ui/window.lua;
    every other .lua file in ui/ is a theme too, but for Sidekick's own kit.lua and
    model.lua. A theme may give its name (`name`); one that doesn't goes by its file's.

    Every theme in ui/ is loaded as Sidekick loads, so a switch is only a swap, and each
    one's `load` runs from Ashita's load event, before any frame (ImGui 1.81 takes no font
    mid-frame). A file added later is loaded the next time the folder is scanned (Sidekick
    Settings opened, /sk theme); an edit to one already loaded waits for /addon reload sidekick.

    The theme picked is the PC's, every character's: config/addons/sidekick/theme.txt holds
    its file's name, beside the sessions' files (core/share.lua). With none picked,
    ui/custom.lua is drawn when there is one, as before themes, else Standard.
]]--

local share = require('core.share')

local themes = {}

themes.STANDARD = 'window'  -- Standard's key: ui/window.lua
themes.OLD = 'custom'       -- ui/custom.lua, the one file Sidekick took before themes

-- Sidekick's own files in ui/: none is a theme, but window.lua, which is Standard.
local OWN = { kit = true, model = true, window = true }

local FILE = 'theme.txt'

-- Every theme, Standard first and the rest by name: { key (its file's name, .lua left off), name, file ('ui/x.lua'),
-- ui (the table it returned) or error (why it didn't load), loaded (its `load` has run) }.
themes.list = {}

-- ui/, where Sidekick's UI files are and themes go: in the addon's folder in game, else where the tests run.
function themes.folder()
    local root = rawget(_G, 'addon') and addon.path
    if type(root) ~= 'string' or root == '' then return 'ui/' end
    return (root:gsub('[\\/]+$', '')) .. '\\ui\\'
end

-- The .lua files in ui/, by their bare names. Not its subfolders' (a third argument of true would go into each, and
-- run a theme's own helper files as themes); the mask is matched with case counting, hence [Ll][Uu][Aa].
function themes.files()
    local ok, files = pcall(ashita.fs.get_dir, themes.folder(), '.*\\.[Ll][Uu][Aa]')
    return ok and type(files) == 'table' and files or {}
end

-- The theme in the file at `path`: the table it returns, or nil and why not. `name` is its `...`, as require gives
-- a module ('ui.classic'), for a theme that requires its own files beside it.
function themes.open(path, name)
    local chunk, err = loadfile(path)
    if not chunk then return nil, tostring(err) end
    local ok, ui = pcall(chunk, name)
    if not ok then return nil, tostring(ui) end
    if type(ui) ~= 'table' or type(ui.render) ~= 'function' then return nil, 'it returns no table with a render function' end
    return ui
end

local function entry(key, file, ui, err)
    local name = ui and type(ui.name) == 'string' and ui.name:match('^%s*(.-)%s*$') or ''
    return { key = key, name = name ~= '' and name or key, file = file, ui = ui, error = err }
end

-- The theme of the file named `key` (.lua left off, any case), or nil.
function themes.get(key)
    if type(key) ~= 'string' then return nil end
    key = key:lower()
    for _, t in ipairs(themes.list) do
        if t.key:lower() == key then return t end
    end
end

-- The theme `word` names: its name, else its file's, any case ('standard' is Standard); nil for none.
function themes.find(word)
    local w = type(word) == 'string' and word:match('^%s*(.-)%s*$'):lower() or ''
    if w == '' then return nil end
    for _, t in ipairs(themes.list) do
        if t.name:lower() == w then return t end
    end
    return themes.get(w)
end

local function by_name(a, b)
    local an, bn = a.name:lower(), b.name:lower()
    if an ~= bn then return an < bn end
    return a.key:lower() < b.key:lower()
end

-- Every theme in ui/ now. A file new since the last scan is loaded, and so is one that failed to before (fixed since,
-- maybe); the rest stay as they were. One whose file is gone is dropped, but `keep` (the theme in use).
function themes.scan(keep)
    local rest, seen = {}, {}
    for _, file in ipairs(themes.files()) do
        local key = tostring(file):match('^([^\\/]+)%.[Ll][Uu][Aa]$')  -- in ui/ itself, not a folder under it
        local low = key and key:lower()
        if key and not OWN[low] and not seen[low] then
            seen[low] = true
            local t = themes.get(key)
            if not (t and t.ui) then t = entry(key, 'ui/' .. file, themes.open(themes.folder() .. file, 'ui.' .. key)) end
            rest[#rest + 1] = t
        end
    end
    local standard = themes.list[1]
    if keep and keep ~= standard and not seen[keep.key:lower()] then rest[#rest + 1] = keep end
    table.sort(rest, by_name)
    themes.list = { standard }
    for _, t in ipairs(rest) do themes.list[#themes.list + 1] = t end
end

-- Standard, from the ui/window.lua Sidekick requires, then every theme in ui/.
function themes.init(window)
    themes.list = { entry(themes.STANDARD, 'ui/window.lua', window) }
    themes.list[1].name = 'Standard'
    themes.scan()
end

-- Each theme's `load`, once: from Ashita's load event, before the first frame. Returns those that raised an error,
-- { { theme, error } }.
function themes.load_all()
    local failed = {}
    for _, t in ipairs(themes.list) do
        if t.ui and type(t.ui.load) == 'function' and not t.loaded then
            t.loaded = true
            local ok, err = pcall(t.ui.load)
            if not ok then failed[#failed + 1] = { t, tostring(err) } end
        end
    end
    return failed
end

-- The themes for the view: { current = the key of `current`, list = { { key, name, file, error, standard } } }.
function themes.shown(current)
    local list = {}
    for i, t in ipairs(themes.list) do
        list[i] = { key = t.key, name = t.name, file = t.file, error = t.error, standard = t.key == themes.STANDARD or nil }
    end
    return { current = current and current.key, list = list }
end

-- The theme picked for this PC (a key), or nil: none picked, or the file caught as another session rewrites it.
function themes.read()
    local text = share.read_file(share.dir() .. FILE)
    local key = text and text:match('^%s*(.-)%s*$')
    return key ~= '' and key or nil
end

-- `key` saved as this PC's theme. Returns whether it was.
function themes.write(key)
    local path = share.dir() .. FILE
    if share.write_file(path, key .. '\n') then return true end
    pcall(ashita.fs.create_dir, share.dir())  -- no character has saved settings yet
    return share.write_file(path, key .. '\n')
end

return themes
