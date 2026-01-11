# Medic Architecture

This document provides a technical overview of the Medic support-only addon architecture.

## Design Philosophy

Medic follows these core principles:

1. **Support-Only Focus**: No combat automation, only healing, buffing, and debuff removal
2. **Configuration over Code**: Job-specific details are data-driven, not hard-coded
3. **Extensibility**: New support jobs can be added without modifying core logic
4. **Reusability**: Common patterns are extracted into shared modules
5. **Safety**: Multiple validation layers prevent errors and resource exhaustion

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Medic.lua                             │
│                    (Main Addon File)                         │
│  - Job Detection                                             │
│  - Event Loop (d3d_present)                                  │
│  - Command Handler                                           │
│  - Settings Management                                       │
└────────────┬──────────────────────────────────┬─────────────┘
             │                                  │
             │ loads                            │ loads
             ▼                                  ▼
    ┌─────────────────┐              ┌──────────────────┐
    │  Job Definition │              │   Config UI      │
    │  (jobs/*.lua)   │              │ (config_ui.lua)  │
    └────────┬────────┘              └──────────────────┘
             │
             │ provides abilities
             ▼
    ┌──────────────────────────────────────────┐
    │         Automation Engine                 │
    │       (core/automation.lua)               │
    │  - Priority-based action selection        │
    │  - Command throttling                     │
    │  - Error handling (pcall)                 │
    └──────────────┬───────────────────────────┘
                   │
                   │ executes in order
                   ▼
    ┌───────────────────────────────────────────┐
    │         Action Modules                     │
    │        (actions/*.lua)                     │
    │  - heal, heal_aoe, heal_pet               │
    │  - wake, debuff_removal                   │
    │  - buff, recover, geo                     │
    └──────────────┬────────────────────────────┘
                   │
                   │ uses
                   ▼
    ┌───────────────────────────────────────────┐
    │         Core Utilities                     │
    │         (core/common.lua)                  │
    │  - Party management                        │
    │  - Buff/status checking                    │
    │  - Target validation                       │
    │  - Logging                                 │
    └────────────────────────────────────────────┘
    
    ┌───────────────────────────────────────────┐
    │      Resource Management                   │
    │       (core/resource.lua)                  │
    │  - MP/TP checking                          │
    │  - Cooldown tracking                       │
    └────────────────────────────────────────────┘
```

## Data Flow

### Automation Tick Flow

```
1. d3d_present event fires (every frame)
   ↓
2. Check: is_loaded? automation_enabled? in_event?
   ↓
3. Get player info (level, job, resources)
   ↓
4. Iterate priority_order (defined by job)
   ↓
5. For each action type:
   a. Load action module
   b. Execute module.execute(settings, job_def, level, resources)
   c. Module returns command string or nil
   ↓
6. If command returned:
   a. Check throttle (1 second minimum)
   b. Execute command via QueueCommand
   c. Update last_command_time
   d. Break (one action per tick)
   ↓
7. Wait for next frame
```

### Action Module Flow

Each action module follows this pattern:

```
1. Check if enabled in settings
   ↓
2. Get relevant abilities from job_def
   ↓
3. Filter by level requirement
   ↓
4. Sort by priority (cost, level, etc.)
   ↓
5. Check conditions (party HP, buffs, etc.)
   ↓
6. Select best ability
   a. Check resources (MP/TP)
   b. Check cooldown
   c. Check range/validity
   ↓
7. Build command (function or string)
   ↓
8. Return {command, description} or nil
```

## Module Details

### Core Modules

#### common.lua
Provides shared utilities used across all modules.

**Key Functions:**
- `printf/debugf/errorf/warnf`: Logging with consistent formatting
- `get_player_level/job/mp/tp`: Player state access
- `is_idle/engaged/in_event`: Status checking
- `has_pet`: Pet validation
- `get_party_size`: Party member counting
- `get_party_member_*`: Party member data access
- `check_party_hp(threshold, focus, focus_target)`: Returns members needing heal
- `get_party_buffs(member_index)`: Returns buff array for party member
- `has_buff/get_player_buffs`: Buff checking via memory pointers
- `has_status/get_removable_debuffs`: Status effect checking
- `is_in_range(target, range)`: Distance validation
- `get_pet_distance()`: Pet distance from player (for geo)
- `is_casting()`: Casting state detection
- `filter_abilities_by_level()`: Shared ability filtering logic

#### resource.lua
Manages resource checking and cooldown tracking.

**Key Functions:**
- `has_resource(type, amount)`: Check MP or TP availability
- `get_resource(type)`: Get current MP or TP
- `is_ability_ready(id)`: Check ability recast timer
- `get_ability_recast(id)`: Get remaining recast time
- `is_spell_ready(id)`: Check spell recast timer

#### automation.lua
Priority-based action selection engine.

**Key Functions:**
- `can_execute_command()`: Check if throttle allows execution
- `execute_command(cmd, desc)`: Execute command and log
- `execute_priority_actions(...)`: Main loop for action selection
- `set_throttle(seconds)`: Configure throttle time

**Throttling:**
Enforces 1-second minimum between commands to prevent spam.

**Error Handling:**
Uses pcall to catch errors in action modules, preventing one module's failure from breaking automation.

### Action Modules

#### heal.lua
Single-target healing logic with HP deficit-based selection.

**Priority Order:**
1. Focus target (if enabled and needs healing)
2. Lowest HP party member

**Ability Selection:**
- Calculates exact HP deficit
- Selects heal that best matches deficit to minimize overheal
- Falls back to smallest heal if all would overheal
- Uses strongest heal for emergency situations (low HP with unreliable data)

#### heal_aoe.lua
AOE/party-wide healing logic.

**Trigger Conditions:**
- X or more members below threshold (default: 2)
- Prefers AOE when multiple members need healing

#### heal_pet.lua
Pet healing logic.

**Functionality:**
- Monitors pet HP percentage
- Configurable heal threshold (default 50%)
- Always targets `<me>` for pet healing commands
- Priority after player healing

#### wake.lua
Sleep removal logic.

**Detection Method:**
- Scans party members 1-5 (excludes player at 0)
- Uses `get_party_buffs(i)` to read buff arrays directly
- Checks for sleep (buff ID 2 or 19)

**Strategy:**
- 1 sleeping member: Use cheapest single-target ability
- 2+ sleeping members: Use cheapest AOE ability

**Focus Target Support:**
- Prioritizes focus target for single-target wake if they are sleeping

#### debuff_removal.lua
Debuff removal (erase/cleanse) logic.

**Priority Order:**
1. Focus target with debuffs
2. Party member with most debuffs

**Removable Debuffs:**
Configurable whitelist: Poison, Paralysis, Blindness, Silence, Slow, Disease, Curse

#### buff.lua
Buff maintenance logic.

**Buff Types:**
- Self buffs (apply to player)
- Party buffs (apply to party)

**Conditions:**
- `combat_only`: Only use in combat
- `idle_only`: Only use when idle
- `requires_pet`: Requires pet active

**Uptime Checking:**
Checks player buffs to avoid reapplying active buffs using buff_id.

#### recover.lua
MP and TP recovery logic.

**Functionality:**
- MP recovery: Monitors MP percentage, triggers when below threshold
- TP recovery: Monitors TP, triggers when below threshold
- Prioritizes MP recovery over TP recovery

**Abilities:**
- Red Mage: Convert (HP/MP swap)
- Other jobs: Various MP/TP recovery abilities

#### geo.lua
Geomancer-specific Full Circle automation.

**Functionality:**
- Monitors pet luopan distance in real-time
- Configurable distance threshold (7-30 yalms, default 10)
- Automatically executes Full Circle when pet exceeds distance
- Requires active pet and geo abilities enabled

### Job Definitions

Job definitions are Lua modules that return a configuration table.

**Structure:**
```lua
return {
    job_id = 3,               -- FFXI job ID
    job_name = 'White Mage',  -- Display name
    resource_type = 'mp',     -- 'mp' or 'tp'
    
    abilities = {
        heal = { ... },       -- Array of abilities
        heal_aoe = { ... },
        heal_pet = { ... },
        buff = { ... },
        -- etc.
    },
    
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        -- etc.
    },
    
    priority_order = {
        'heal_aoe',
        'heal',
        'heal_pet',
        'debuff_removal',
        'wake',
        'recover',
        'geo',
        'buff',
    }
}
```

**Ability Definition:**
```lua
{
    name = 'Cure IV',                 -- Display name
    level = 48,                       -- Required level
    cost = 88,                        -- MP/TP cost
    value = 400,                      -- HP restored (for deficit selection)
    id = 0,                           -- Recast ID (optional)
    command = function(idx)           -- Command to execute
        return '/ma "Cure IV" <p' .. idx .. '>'
    end,
    buff_id = 43,                     -- Buff to check (optional)
    combat_only = false,              -- Combat requirement (optional)
    idle_only = false,                -- Idle requirement (optional)
    requires_pet = false,             -- Pet requirement (optional)
    wakes = true,                     -- Can wake from sleep (optional)
}
```

## Event System

### Load Event
Fires when addon loads. Sets initialization flag.

### Unload Event
Fires when addon unloads. Saves settings.

### d3d_present Event
Fires every frame. Main automation loop runs here.

**Tasks:**
1. One-time initialization (setup_job)
2. Render config UI (if visible)
3. Run automation tick (if enabled)

**Performance:**
Optimized to minimize frame impact:
- Early returns for disabled/invalid states
- Throttling prevents excessive command execution
- Efficient party/buff checking

### packet_in Event
Fires on incoming packets. Used for:
- Job change detection (packets 0x1B, 0x44, 0x1A)
- Casting state tracking (packet 0x028)

### command Event
Fires on chat commands. Handles /medic commands.

## Settings System

Uses Ashita's settings module for JSON persistence.

**File Naming:**
- `settings_white_mage.json`
- `settings_summoner.json`
- `settings_dancer.json`
- etc.

**Loading:**
1. Detect player job
2. Load job definition
3. Load settings file for that job
4. Merge with default settings
5. Save merged settings

**Saving:**
Automatic save on:
- Setting changes (via UI or commands)
- Addon unload

## Error Handling

### Module Level
Each action module is called with pcall:
```lua
local success, result = pcall(action_module.execute, ...)
if not success then
    errorf('[ERROR] Module failed: ' .. tostring(result))
end
```

### Resource Validation
Before executing any ability:
1. Check MP/TP availability
2. Check cooldown status
3. Check range
4. Check target validity

### Nil Safety
All functions check for nil values:
```lua
if not player then return false end
if not party then return {} end
```

## Performance Considerations

### Frame Budget
Automation runs every frame but:
- Early returns for disabled states
- Throttling limits actual command execution
- Efficient algorithms for party checking

### Memory Management
- Buff checking reuses arrays
- No memory leaks in event handlers
- Efficient data structures

## Extensibility

### Adding a New Support Job

1. **Create job definition** (`lib/jobs/newjob.lua`)
2. **Register in job_map** (Medic.lua line ~75)
3. **Test thoroughly**

No core code changes needed!

### Adding a New Support Action

1. **Create action module** (`lib/actions/newaction.lua`)
2. **Add to action_modules table** (Medic.lua line ~29)
3. **Add to master_priority** (Medic.lua line ~170)
4. **Update config_ui** (optional, for UI)

### Adding a New Ability

Just add to job definition:
```lua
abilities = {
    heal = {
        -- Add new ability here
        { name = '...', level = X, cost = Y, ... }
    }
}
```

## Design Constraints

### Support-Only Focus
- **No** combat automation
- **No** tanking/enmity management
- **No** magic bursting or offensive spells
- **Only** healing, buffing, debuff removal, and basic pet management

### Safety First
- Multiple validation layers
- Automatic resource checking
- Cooldown tracking
- Event/cutscene blocking

### Configuration Over Code
- Jobs defined via configuration files
- No hard-coded ability names in core logic
- Easy to adjust per-job settings

## Known Limitations

- Party only (no alliance support)
- Fixed 21 yalm range for most abilities
- Some buff IDs may vary by private server
- Requires Ashita v4

## Conclusion

Medic's architecture prioritizes:
- **Support-Only Focus**: Clear boundaries on what is and isn't automated
- **Modularity**: Clear separation of concerns
- **Extensibility**: Easy to add support jobs/abilities
- **Safety**: Multiple validation layers
- **Performance**: Efficient algorithms
- **Maintainability**: Clean, documented code

The result is a robust, focused support-only addon that can be easily extended with new support jobs and abilities through configuration rather than code changes.
