-- Luacheck config. In-game Lua is LuaJIT (Lua 5.1 + bit, ffi, ...) and the test runner is
-- plain luajit, so 'luajit' is the right std everywhere.
std = 'luajit'

max_line_length = false

-- Claude Code agent worktrees are full repo copies; the per-file ignores below don't match them.
exclude_files = { '.claude/**' }

-- Ashita v4 API available inside the game client.
read_globals = {
    'AshitaCore',
    'GetEntity',
    'GetPlayerEntity',
    'struct',
    'switch',
    ashita = {
        fields = {
            bits = { fields = { 'unpack_be' } },
            events = { fields = { 'register', 'unregister' } },
            fs = { fields = { 'create_dir', 'exists', 'get_dir' } },
            memory = { fields = { 'find', 'read_array', 'read_uint' } },
        },
    },
}

-- Ashita creates the addon table before loading; the entry point fills in its fields.
globals = { 'addon' }

ignore = {
    -- Ashita's imgui binding injects the ImGui enums and FLT_MAX as globals.
    '113/ImGui[%w_]+', '113/FLT_MAX',
    -- Ashita's common lib extends the table library (T{}, table.range, ...).
    '143/table',
    -- Whitespace-only and trailing-whitespace lines in files the game loads as-is.
    '611', '612', '613', '614',
}

-- Pre-existing shape of the shipped code, kept out of the gate so the lint job is green from
-- the first run. Tighten by deleting a line here once its warnings are fixed:
--   211/212/213 unused variable, argument, loop variable   311 value assigned but unused
--   421/431 shadowing                                       542 empty if branch
files['Sidekick.lua'] = { ignore = { '211', '212', '213', '311', '421', '431', '542' } }
files['lib/'] = { ignore = { '211', '212', '213', '311', '421', '431', '542' } }

files['tests/run.lua'] = {
    -- The runner defines the assertion helpers the *_test.lua files use.
    allow_defined_top = true,
}
files['tests/ashita.lua'] = {
    -- The fake client defines the globals Ashita would inject.
    allow_defined_top = true,
    globals = { 'T', 'addon', 'ashita', 'AshitaCore', 'GetEntity', 'GetPlayerEntity', 'struct', 'table' },
}
files['tests/*_test.lua'] = {
    read_globals = { 'test', 'assert_eq' },
    -- Tests freeze os.clock to drive recast timing.
    ignore = { '122/os' },
}
files['tests/data/'] = { max_line_length = false }
