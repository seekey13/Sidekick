# Tests

Runs outside the game under plain `luajit`. No dependencies.

```
make test               # every tests/*_test.lua
make test FILE=jobs_test
make lint               # luacheck, config in .luacheckrc
make check              # both; CI runs the same on Ubuntu and Windows
```

## How it works

`tests/run.lua` loads `tests/ashita.lua` first, then runs each `*_test.lua`.

`tests/ashita.lua` is a fake Ashita client. It defines the globals the game injects
(`T{}`, `AshitaCore`, `ashita`, `GetEntity`, `GetPlayerEntity`, `struct`, `addon`) and the
`chat`, `settings` and `imgui` modules, so the real `lib/` modules load unchanged. It
also stubs `targets.get_bt`, whose ffi call crashes against the fake. Every read comes
from `fake.state`:

| Field | What it feeds |
|---|---|
| `player` | job, levels, `buffs`, known `spells` and `abilities` |
| `party[0..5]` | name, server id, HP, MP, TP, active flag |
| `spell_recasts[spell_id]` | `GetSpellTimer`, in 1/60 s |
| `ability_recasts[recast_id]` | the 32-slot ability recast list |
| `entities[target_index]` | tables from `fake.entity{...}` |
| `commands` | everything sent through `QueueCommand` |
| `inventory[container]` | list of `{ Id, Count }`; `GetContainerItem` slot `i` is `[i + 1]` |
| `inventory_reads` | count of `GetContainerItem` calls, to see a container walk |

A test edits that table and calls `fake.reset()` between cases.

Every `imgui` call returns `false` unless a test puts a handler under its name in
`fake.imgui` (`fake.imgui = { BeginTabBar = function(id) ... end }`); `fake.reset()`
clears it.

## Test files

- `jobs_test.lua` checks every `lib/jobs/*.lua` against the CatsEyeXI tables in `data/`:
  each `spell_id`, `recast_id` and `ability_id` resolves to the server row the command
  names, `cost` equals the server MP cost, every buff and debuff id is a status effect,
  an ability the server gates on an Arts stance accepts both that stance and its Addendum,
  every `default_settings` key is read by the engine, and each job is registered under
  its own id in `Sidekick.lua`. A failure here is a wrong id in a job file, not a test bug.
- `action_core_test.lua` drives `action_core.is_usable` through the fake client.
- `stratagem_test.lua` drives `common.check_stratagem` with the real Scholar job file: which
  stratagem fires next for a spell under each Arts stance.
- `snapshot_test.lua` pins every field of a party and an alliance member snapshot, the
  fallback when a party-manager read throws, the `/anon` patch-up, and the 0.1 s
  `refresh_game_state_if_stale` guard.
- `inventory_test.lua` holds `count_equippable_items` to one container walk per spec per
  0.5 s.
- `tracked_targets_test.lua` counts entity-slot reads per `refresh_game_state()`: a
  tracked target is read at its cached index, and misses share one rescan at most once
  a second.
- `ui_components_test.lua` drives the config window's section display through a
  recording `fake.imgui`: the header, tab and group-page layouts, group filtering, and
  the one-frame-deferred layout switch.

## Adding a test

1. Create `tests/<module>_test.lua`. The runner picks it up by name.
2. Require `tests.ashita` and the module under test, set `fake.state`, call the module,
   `assert_eq(actual, expected, message)`.
3. Name each test for the behavior: `a spell on recast reports the seconds left`, not
   `test is_usable`.
4. If the module calls something the fake does not implement, the nil-call error names
   it. Add that one method to `tests/ashita.lua`, reading from `fake.state`.
5. Freeze `os.clock` when the module measures time (see `action_core_test.lua`).

Copy this shape:

```lua
local fake = require('tests.ashita');
local heal = require('lib.actions.heal');

test('a member below the threshold gets the largest cure they can afford', function()
    fake.reset();
    fake.state.party[1] = { name = 'Tank', server_id = 0x101, hp_pct = 40, active = true };
    -- ...
    assert_eq(result.command, '/ma "Cure IV" 257');
end);
```

## Server data

`data/spells.lua`, `data/abilities.lua` and `data/status_effects.lua` are generated from
the CatsEyeXI SQL and pinned to the commit in each file's header. Regenerate after a server
update:

```
make resources CATSEYE=../catseyexi
```

A spell the job files keep although the server has no row for it goes in the
`missing_on_server` table at the top of `jobs_test.lua`, with the job file's note as the reason.
