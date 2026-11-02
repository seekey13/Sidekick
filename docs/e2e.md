# In-game end-to-end tests

For [issue #56](https://github.com/seekey13/Sidekick3/issues/56). A scenario sets a scene in a live game with GM commands, lets Sidekick3 act on it, and checks what it sent and what landed. It runs on the dev server, where `Test` and `Dev` are GMs. The offline tests (`luajit tests/run.lua`) check the decisions. These check everything the offline tests can't: the client taking the command, the server taking the action, and how long each step takes.

| Piece | What it is |
|---|---|
| [tools/gm.lua](../tools/gm.lua) | The GM commands that set a scene. [gm-commands.md](gm-commands.md) has the commands and their quirks. |
| [tools/e2e.lua](../tools/e2e.lua) | The runner. It lives in Sidekick3's own Lua state, which VanaCore's MCP reaches. |
| [tests/e2e/](../tests/e2e/) | The scenarios, one file each. `suite.lua` lists the order `all` runs them in. |
| [tools/e2e.mjs](../tools/e2e.mjs) | Runs scenarios from a terminal, through the MCP. |
| [tests/e2e_test.lua](../tests/e2e_test.lua) | The runner's own offline tests, against a fake client. |

Nothing in Sidekick3 requires any of these, and release zips leave `tools/` and `tests/` out.

## Running them

The game under test needs:
- VanaCore's MCP on: `[mcp] enabled=1` in `vanacore.ini`, or /vana > Client > AI MCP. Each game takes the next free port from 47800, and `game_state` names the character on a port.
- Sidekick3 loaded.
- Its character at GM level 1 or more. Level 4 adds `!exec`, used for a tracked player's HP %.
- Around it:
  - a player in its party (`t.member()`, Test);
  - one in the alliance's other parties (`t.ally()`, Alliance);
  - a tracked player near it (`t.tracked()`, Tracked).

  A scenario that needs one who isn't there skips.

From a terminal:

```
node tools/e2e.mjs run all            # or names: run heal wake
node tools/e2e.mjs list               # the scenarios and what each checks
node tools/e2e.mjs report             # the results since the runner loaded
node tools/e2e.mjs status | abort
node tools/e2e.mjs --port 47801 run all
```

`run` prints each result as it finishes and exits 1 if any failed. A failure comes with its last 15 events and what Sidekick3 thought at that moment. Before a run, the runner and the GM commands are loaded again from their files, so edits take effect.

From a Claude session, connect the MCP with `claude mcp add --transport http vanacore http://127.0.0.1:47800/mcp`. Then call `hello`, and use the `lua` tool with `addon = "Sidekick3"`:

```
return require('tools.e2e').run('all')    -- queues them; one runs at a time, a frame at a time
return require('tools.e2e').status()      -- running, queued, finished
return require('tools.e2e').report()      -- results: result, why, seconds, notes, timings, trail
```

What a scene changes is undone after it, whatever the result:
- HP and MP go back to full.
- A status given is taken off.
- A death is revived: `!homepoint` revives the dead at their home point, then `!bring` brings them back.
- Settings go back to what they were.
- Automation is stopped again if it was off.

Run one suite at a time, and leave the characters standing still while it runs.

## The scenarios

As run on 2026-11-02, with Dev a WHM75, Test in its party, Alliance in the alliance, and Tracked tracked:

| Scenario | Checks | Result |
|---|---|---|
| `idle` | Everyone full, nothing on them: no sends for 8 s | pass |
| `heal` | Test at 40%: a heal on Test that lands | pass: Cure V sent 0.4–0.8 s after, landed 2.9–3.2 s after that |
| `heal_self` | You at 40% | pass: Cure IV / Cure V on Dev |
| `heal_tracked` | Tracked at 40% (set from the server's max) | pass: Cure V on Tracked, by name |
| `heal_alliance` | Alliance at 40%: healed only with Heal > Alliance on | pass: off, so none sent |
| `remove` | Poison on Test: Poisona, and the Poison goes | pass: sent 0.4 s after, landed 1.2 s after that |
| `wake` | Sleep on Test at full HP: a heal that wakes | pass: Cure |
| `doom` | Doom on Test: Cursna, and again while the Doom stays | pass: the first had no effect, a second went at its recast |
| `buff` | A row's buff taken off Test goes back on (a Protect row for Test for the scenario, if none is on) | pass: Protect IV |
| `rest` | Low MP with resting on (on for the scenario): `/heal` after the quiet seconds | pass |
| `revive` | Test dies: a Raise that lands | **fail**: "Dev cannot cast Arise." (below) |

### What they found

- **Fixed: every command on another player failed.** `can.command` aimed at a server id (`/ma "Cure V" 2`), and the client takes no numeric target: "...A command error occurred.", every 1.1 s. It sends names now, and a member whose name has a space goes by party slot. A mob another party of the alliance claimed still goes by server id, which the client refuses just the same: marked in `core/can.lua` as one to solve.
- **Open: Arise.** The client's data has Arise at WHM75, so Sidekick3 picks it over Raise III. The server's `spell_list` has it at WHM 99, and answers "Dev cannot cast Arise." `behaviors/revive.lua` marks a raise as done when it's sent and waits 60 s (`RAISE_WAIT`) before raising again, so a raise the server refuses is never noticed. It would send Arise every minute and never Raise III.
- **Set up on Dev, not a code fault: Sidekick3's Japanese-client switch was on with an English client.** Every name went in Japanese and was refused. It's off now.
- **For reference:** Cursna takes off Doom (10 + healing skill / 30)% of the time, about one cast in five at WHM75, and its recast is 10 s. A heal reached the server 0.4–0.8 s after the HP fell, and a spell landed 1.2–3.2 s after it was sent.

## Writing one

A scenario is a file in `tests/e2e/` that returns `{ about, run = function (t) ... end }`, with optional `timeout` seconds (120 by default). Add its name to `suite.lua` for `all`. The usual shape:

```lua
return {
    about = 'a party member at 40% HP gets a heal that lands',
    run = function (t)
        local who = t.member()          -- skips when there's none
        t.start()                       -- automation on (off again after, if it was)
        t.settle()                      -- everyone full, Sidekick3 quiet for 3 s
        t.gm.hp_pct(who, 40)            -- the scene: timed from here, undone after
        local sent = t.expect({ behavior = 'heal', on = who }, 10)
        t.lands(sent, 15)
    end,
}
```

| Call | Does |
|---|---|
| `t.gm.<command>(...)` | A [tools/gm.lua](../tools/gm.lua) command, which sets `t.since` (the scene's moment) and undoes itself after the scenario |
| `t.expect(want, timeout)` | Waits for Sidekick3's next send since `t.since` matching `want`, and returns it with `after`, its seconds after the scene. `want` can give `behavior` (heal, remove, wake, revive, buff, rest, recover, pet, follow), `on` (a name, any case), `action` (the English name), `family` (Cure for Cure III) and `kind` (`ma`, `ja`, `item`). |
| `t.lands(sent, timeout)` | Waits for your 0x028 finish of that kind on that target, and returns it, with the first target's `message`. It fails on the client's "A command error occurred", on the server's "cannot cast" and the like, and on an interrupt. |
| `t.expect_none(want, seconds)` | Fails if a matching send goes within that time |
| `t.wait(s)`, `t.wait_for(pred, timeout, what)` | Waits, a frame at a time. Never block: a scenario runs inside the game's frame. |
| `t.check(ok, fmt, ...)`, `t.fail(...)` | Fails the scenario |
| `t.need(ok, fmt, ...)`, `t.skip(...)` | Skips it, for a setting or a player that isn't there |
| `t.note(fmt, ...)`, `t.time(label, s)` | Adds to the report |
| `t.setting(path, value)` | A Sidekick3 setting for this scenario only: `'rest.on'`, or `{ 'rows', 'Protect' }`. Saved, and put back after. |
| `t.finally(fn)` | Runs after, whatever happens. The last registered runs first. |
| `t.me()`, `t.member()`, `t.ally()`, `t.tracked()` | Who's who |
| `t.who(name)` | What the client reads of a player (gm.who) |
| `t.unit(name)` | Sidekick3's own unit for them, with its `buffs` |
| `t.cfg()`, `t.actions()`, `t.action(name)` | Sidekick3's settings and catalog, as it decides on them |
| `t.status()` | Sidekick3's own status: `running`, `intent`, `why`, `sent` |
| `t.sk3(args)` | A `/sk3` command |
| `t.events(kind)`, `t.sends(want)` | What the runner recorded since the scenario began: `sent`, `act` (0x01A, 0x037), `camp` (0x0E8), `begin`, `finish`, `interrupt` (0x028), `gm`, `line` (chat) |
| `t.revive(name)`, `t.settle()`, `t.idle(quiet, timeout)` | The cleanup's revive; the starting point; Sidekick3 quiet |

How the runner sees Sidekick3, with no line in `Sidekick3.lua`: it wraps `share.tick` and `engine.decide` in their modules. These hand it Sidekick3's `status` and the snapshot, catalog and settings it decides on, and pass everything on untouched. `e2e.unwatch()` puts them back, and so does a reload of Sidekick3. A fault in the runner ends the scenario as an error, never the frame, so VanaCore never unloads Sidekick3 for it.
