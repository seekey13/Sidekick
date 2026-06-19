# Medic Config UI Tooltips — Design

## Goal

Add hover tooltips to the main Medic Configuration window that explain *what
each automation feature does* (thresholds, priority order, requirements,
limitations) — not just the existing dynamic state hints ("Combat Only",
"Idle Only", Trust warnings, etc.), which remain unchanged.

## Mechanism

- Tooltips trigger by **hovering the existing control** (section header,
  slider, dropdown, button, or checkbox). No new "(?)" icons are added.
- A new generic helper in `lib/ui/components.lua`:

```lua
-- Show a static help tooltip for the most recently rendered item.
function ui_components.item_tooltip(text)
    if text and imgui.IsItemHovered() then
        imgui.SetTooltip(text)
    end
end
```

- All tooltip strings live in a new module, `lib/ui/tooltips.lua`, returning
  a flat table of `key -> string`. Long strings use manual `\n` line breaks
  (~40-50 chars/line) since `imgui.SetTooltip` does not word-wrap.
- `lib/ui/config.lua` requires `lib.ui.tooltips` and calls
  `ui.item_tooltip(tooltips.KEY)` immediately after the relevant control.
- The two item-removal checkboxes (Silence/Doom) keep their existing
  dynamic tooltip (`render_item_removal_checkbox` in `components.lua`);
  the new explanatory text is appended to that string via an extra
  parameter, separated by `\n\n`.

## Tooltip content & attach points

All keys live in `lib/ui/tooltips.lua`. Attach points are in `config.lua`
unless noted.

### Top of window

**`automation_status`** — attached to the automation status text (after
`imgui.Text(status_text)`).
```
Start/Stop toggles all Medic automation.
Status shows why it may be paused:
- Loading: waiting for job data
- Mounted: automation suspended
- Dead: automation suspended
- Resting: recovering MP (only rest-stop logic runs)
- Paused: combat is currently blocked
- Running: fully active
```

**`tracked_targets`** — attached to the "Add Tracked Target" button.
```
Tracks a player outside your party/alliance.
Only abilities marked to target outside
the party (heal, buff, wake, debuff removal)
can affect tracked targets, and removal/wake
on them is less reliable than on party members.
They must still be in range.
```

**`attack_range`** — attached to the Attack Range combo.
```
Requires the Multisend addon (/ms).
While in combat, Medic disables Multisend
follow once you're within this distance
of your battle target (<bt>), and re-enables
follow if you fall outside it or leave combat.
'Off' leaves follow control to you/Multisend.
```

### Focus / Group / Critical / AOE / Pet

**`focus_healing`** — "Enable Focus Healing" header.
```
Gives one party/tracked/alliance member their
own HP% healing threshold (usually higher),
checked before the Group threshold.
The Focus Target also gets priority for
Debuff Removal over other members.
```

**`group_healing`** — "Enable Group Healing" header.
```
When a group member's HP drops below this %,
Medic casts a heal sized to their missing HP
(largest spell that won't overheal, or the
smallest available if none fit).
```

**`critical_hp`** — "Critical (HP%)" slider.
```
Critical abilities use their own (normally
lower) threshold. If ANY group member drops
below this %, Medic uses one of these abilities
first - before Focus or Group healing.
```

**`aoe_healing`** — "Enable AOE Healing" header.
```
When the group's average HP falls below this %
AND at least 2 members are below it, Medic
casts the checked AOE healing spell(s) instead
of single-target heals.
```

**`pet_healing`** — "Enable Pet Healing" header.
```
When your pet's HP falls below this %,
Medic casts the checked pet-healing ability.
```

### Wake / Debuff / Items

**`sleep_removal`** — "Enable Sleep Removal" header.
```
Scans party, tracked, and alliance members
(never yourself) for Sleep/Sleep II.
2+ asleep -> uses a checked AOE wake spell.
Otherwise wakes the first sleeper (your Focus
Target preferred) with the cheapest option.
```

**`debuff_removal`** — "Enable Debuff Removal" header.
```
Removes debuffs using abilities matched to
specific status IDs. Priority: yourself, then
your Focus Target, then whichever selected
member has the most removable debuffs.
```

**`item_silence_removal`** — appended to the Echo Drops checkbox tooltip.
```

Also auto-uses this item on yourself when
you have Silence, independent of the spell-
based removal above. Limited to once per 4s.
```

**`item_doom_removal`** — appended to the Holy Water checkbox tooltip.
```

Also auto-uses this item on yourself when
you have Doom, independent of the spell-
based removal above. Limited to once per 4s.
```

### Rest (per-setting)

**`resting`** — "Enable Resting" header.
```
While idle (not moving/casting/engaged) and
MP < 100%, Medic waits Timer seconds after
conditions become favorable, then sends
/heal on. Stops at full MP, on movement/
casting, or if Follow Target exceeds Distance.
```

**`rest_timer`** — "Timer (seconds)" slider.
```
Seconds to wait after conditions first become
favorable (idle, not casting, MP < 100%)
before Medic starts resting.
```

**`rest_follow_target`** — "Follow Target" dropdown.
```
Party member whose distance from you is
watched while resting. If they move beyond
the Distance below, resting stops (and won't
start) so you aren't left behind.
```

**`rest_distance`** — "Distance (yalms)" slider.
```
Max distance (yalms) from the Follow Target
before resting is stopped or blocked from
starting.
```

### Recovery / Buff

**`resource_recovery`** — "Enable Resource Recovery" header.
```
Self Recover (TP/MP%) casts the checked
abilities when your TP/MP drops below the
set value. Chivalry Min TP holds back TP-cost
MP recovery until your TP reaches that amount.
If a Recovery Target is set, Devotion is cast
on them when THEIR MP drops below Target
Recover %, sharing your MP with them.
```

**`buffs`** — "Enable Buffs" header.
```
For each checked buff, Medic checks the
target's active buff IDs. If none of this
ability's buff IDs are active, it casts the
configured spell on that target (self, party,
or Trust). Grouped buffs let you pick one
option; some require a target-modifier spell
(e.g. Pianissimo) cast first.
```

### Geo (per-component)

**`geo`** — "Enable Geo" header.
```
Geomancer automation: keeps your luopan in
range via Full Circle, and optionally casts
an Indi spell on a party member via Entrust.
```

**`geo_distance`** — "Distance (yalms)" slider.
```
If your luopan drifts beyond this many yalms
from you, Medic uses Full Circle to recall it
and recast your active Geo spell.
```

**`geo_full_circle`** — Full Circle ability checkbox.
```
When checked, Medic uses Full Circle to
recast your current Geo spell once the
luopan exceeds the Distance threshold above.
```

**`geo_entrust_target`** — "Entrust Target" dropdown.
```
Party member who will receive the Entrust-
assisted Indi spell selected below.
```

**`geo_entrust_spell`** — "Entrust Spell" dropdown.
```
Indi spell Medic casts on the Entrust Target.
Medic uses Entrust on itself first, then casts
this spell on the target while Entrust is active.
```

**`geo_entrust_enable`** — Entrust ability checkbox.
```
Enables the Entrust automation above, using
the Target and Spell selected.
```

### Revive

**`revive`** — "Enable Revive" header.
```
Scans party, tracked, and alliance members
for 0 HP / dead status and casts a raise spell
(checks range and buff prerequisites, e.g.
Addendum: White). Raise spells are idle-only,
so this won't trigger while you're in combat.
```

## Out of scope

- No changes to existing dynamic tooltips (Combat Only / Idle Only / Trust
  warnings / item count).
- No per-ability tooltips for individual spells within a section (only the
  per-setting items listed above).
