# Sidekick Architecture

This document provides a detailed technical overview of the Sidekick automation framework architecture.

## Design Philosophy

Sidekick follows these core principles:

1. **Separation of Concerns**: Logic, data, and presentation are clearly separated
2. **Configuration over Code**: Job-specific details are data-driven, not hard-coded
3. **Extensibility**: New jobs can be added without modifying core logic
4. **Reusability**: Common patterns are extracted into shared modules
5. **Safety**: Multiple validation layers prevent errors and resource exhaustion

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Sidekick.lua                          │
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
    │  - heal, heal_aoe, wake                   │
    │  - debuff_removal, buff, debuff           │
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
- `has_pet`: Pet validation (for Summoner)
- `get_party_size`: Party member counting
- `get_party_member_*`: Party member data access
- `check_party_hp(threshold, focus, focus_target)`: Returns members needing heal
- `get_party_buffs(member_index)`: Returns buff array for party member (via memory pointers)
- `has_buff/get_player_buffs`: Buff checking via memory pointers
- `has_status/get_removable_debuffs`: Status effect checking
- `is_in_range(target, range)`: Distance validation
- `is_valid_target(target)`: Target validity checking

**Constants:**
- `STATUS.*`: Status effect IDs (SLEEP, POISON, etc.)
- `BUFF.*`: Buff IDs (PROTECT, SHELL, HASTE, etc.)

**Memory Access:**
Uses memory pointers to read buff/status data directly from party member structures. This is more reliable than relying on chat log parsing.

#### resource.lua
Manages resource checking and cooldown tracking.

**Key Functions:**
- `has_resource(type, amount)`: Check MP or TP availability
- `get_resource(type)`: Get current MP or TP
- `is_ability_ready(id)`: Check ability recast timer
- `get_ability_recast(id)`: Get remaining recast time
- `is_spell_ready(id)`: Check spell recast timer
- `set_custom_recast/is_custom_recast_ready`: Manual cooldown tracking

**Recast System:**
Uses Ashita's Recast Manager to check ability/spell cooldowns. Supports custom cooldown tracking for abilities that share timers.

#### automation.lua
Priority-based action selection engine.

**Key Functions:**
- `can_execute_command()`: Check if throttle allows execution
- `execute_command(cmd, desc)`: Execute command and log
- `execute_priority_actions(...)`: Main loop for action selection
- `set_throttle(seconds)`: Configure throttle time
- `reset_throttle()`: Force immediate execution

**Throttling:**
Enforces 1-second minimum between commands to prevent spam. Configurable but defaults to safe value.

**Error Handling:**
Uses pcall to catch errors in action modules, preventing one module's failure from breaking automation.

### Action Modules

#### heal.lua
Single-target healing logic.

**Priority Order:**
1. Focus target (if enabled and needs healing)
2. Lowest HP party member

**Ability Selection:**
Tries abilities from strongest to weakest, checking:
- Resource availability (MP/TP)
- Cooldown status
- Range (21 yalms)

**Command Building:**
Supports both function-based and string-based commands. Functions receive party_index parameter for dynamic targeting.

#### heal_aoe.lua
AOE/party-wide healing logic.

**Trigger Conditions:**
- X or more members below threshold (default: 2)
- OR average party HP below threshold

**Ability Selection:**
Similar to heal.lua but for AOE abilities. Prefers AOE when multiple members need healing.

#### wake.lua
Sleep removal logic.

**Detection Method:**
- Scans party members 1-5 (excludes player at 0)
- Uses `get_party_buffs(i)` to read buff arrays directly
- Uses `is_buff_sleep(buffs)` helper to check for sleep (buff ID 2 or 19)
- Matches BackupDancer's proven approach for reliability

**Strategy:**
- 0 sleeping members: Exit, no action needed
- 1 sleeping member: Use cheapest single-target ability
- 2+ sleeping members: Use cheapest AOE ability (more efficient)

**Focus Target Support:**
- If focus is enabled and focus target is sleeping, prioritize them for single-target wake

**Ability Sources:**
Can use dedicated wake abilities OR healing abilities marked with `wakes = true` flag.

**Constants:**
- `wake.SLEEP_BUFF_ID = 2`: Sleep buff ID
- `wake.SLEEP_II_BUFF_ID = 19`: Sleep II buff ID

#### debuff_removal.lua
Debuff removal (erase/cleanse) logic.

**Priority Order:**
1. Focus target with debuffs
2. Party member with most debuffs

**Removable Debuffs:**
Configurable whitelist in settings:
- Poison, Paralysis, Blindness, Silence
- Slow, Disease, Curse

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
Checks player buffs to avoid reapplying active buffs. Uses buff_id or custom check_buff function.

#### debuff.lua
Debuff application logic (Dancer steps pattern).

**Stacking Debuffs:**
Tracks debuff stacks per target using packet sniffing.

**Packet Handling:**
- **0x028 (Action)**: Contains step application data
- **0x029 (Message)**: Confirms step level

**Stack Tracking:**
```lua
step_levels[target_id][action_id] = level
```

Maintains step levels per target, per step type. Stops at max stacks (5 for Dancer steps).

**Cooldown Logic:**
After reaching max stacks, respects cooldown timer before reapplying.

#### counter.lua
Enemy ability interruption logic.

**Detection Method:**
Parses incoming text messages (text_in event) to detect enemy abilities:
- Looks for "readies" or "ready" patterns
- Extracts enemy name and ability name
- Tracks timing window for interrupt

**Trigger Conditions:**
- Enemy must be current target
- Enemy must be a monster (spawn flag 0x10)
- Ability must be within timing window (default: 0.5s - 2.5s)
- Optional: Ability must match filter list

**Timing Windows:**
- `counter_min_delay`: Minimum delay before attempting counter (default 0.5s)
- `counter_max_window`: Maximum window to attempt counter (default 2.5s)

**Ability Filtering:**
- `counter_filter_enabled`: Enable ability filtering
- `counter_filter_abilities`: List of ability names to interrupt
- If disabled, attempts to interrupt all enemy abilities

**Priority System:**
Counter abilities can specify priority (lower = higher priority):
```lua
{
    name = 'Holy II',
    priority = 1,  -- Try first
    cost = 93,
    -- ...
}
```

**Text Pattern Examples:**
- "The goblin readies Bomb Toss."
- "Adamantoise ready Tortoise Stomp."

**Reset Conditions:**
- Enemy completes ability (detected via "uses"/"use" text)
- Timing window expires (>3 seconds)
- Target changes or becomes invalid

### Job Definitions

Job definitions are Lua modules that return a configuration table.

**Structure:**
```lua
return {
    job_id = 15,              -- FFXI job ID
    job_name = 'Summoner',    -- Display name
    resource_type = 'mp',     -- 'mp' or 'tp'
    
    abilities = {
        heal = { ... },       -- Array of abilities
        heal_aoe = { ... },
        buff = { ... },
        -- etc.
    },
    
    validators = {
        requires_pet = function() ... end
    },
    
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        -- etc.
    },
    
    priority_order = {
        'heal_aoe',
        'wake',
        'heal',
        'buff',
    }
}
```

**Ability Definition:**
```lua
{
    name = 'Healing Ruby',           -- Display name
    level = 1,                       -- Required level
    cost = 6,                        -- MP/TP cost
    id = 174,                        -- Recast ID (optional)
    command = function(idx)          -- Command to execute
        return '/pet "Healing Ruby" <p' .. idx .. '>'
    end,
    buff_id = 43,                    -- Buff to check (optional)
    combat_only = false,             -- Combat requirement (optional)
    idle_only = false,               -- Idle requirement (optional)
    requires_pet = true,             -- Pet requirement (optional)
    wakes = true,                    -- Can wake from sleep (optional)
    max_stacks = 5,                  -- Max debuff stacks (optional)
    track_stacks = true,             -- Enable stack tracking (optional)
    action_id = 617,                 -- For packet tracking (optional)
    check_buff = function() ... end  -- Custom buff check (optional)
}
```

**Validators:**
Job-specific validation functions (e.g., requires_pet for Summoner).

**Priority Order:**
Defines the order in which action types are checked. Allows job-specific customization.

### Configuration UI

Dynamic ImGui interface that adapts to loaded job definition.

**Features:**
- Automatically generates UI elements from job abilities
- Displays available abilities with level requirements
- Provides sliders for thresholds
- Checkboxes for enable/disable toggles
- Saves settings per job (settings_summoner.json, etc.)

**Sections:**
- General Settings (debug mode)
- Focus Target (party member prioritization)
- Healing (threshold, abilities list)
- AOE Healing (threshold, count, abilities)
- Sleep Removal
- Debuff Removal (abilities list)
- Buffs (abilities list with combat/idle flags)
- Debuffs (abilities list with stack info)

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
Fires on incoming packets. Used for step tracking (Dancer).

**Handled Packets:**
- 0x028: Action packets (step application)
- 0x029: Message packets (step confirmation)

### command Event
Fires on chat commands. Handles /sidekick commands.

**Command Processing:**
1. Parse command arguments
2. Route to appropriate handler
3. Block command from game (e.blocked = true)
4. Execute action and provide feedback

## Settings System

Uses Ashita's settings module for JSON persistence.

**File Naming:**
- `settings_summoner.json`
- `settings_dancer.json`
- `settings_white_mage.json`
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
- Step tracking uses weak tables (could be added)
- Buff checking reuses arrays
- No memory leaks in event handlers

### Optimization Opportunities
1. Cache party data across multiple action modules
2. Add configurable tick rate (not every frame)
3. Implement ability priority caching
4. Add smart throttling (faster in combat, slower idle)

## Extensibility

### Adding a New Job

1. **Create job definition** (`lib/jobs/newjob.lua`)
2. **Register in job_map** (Sidekick.lua)
3. **Test thoroughly**

No core code changes needed!

### Adding a New Action Type

1. **Create action module** (`lib/actions/newaction.lua`)
2. **Add to action_modules table** (Sidekick.lua)
3. **Add to default priority_order**
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

## Security Considerations

### Memory Safety
Memory pointer access is wrapped in safe checks:
```lua
if ptr == 0 then return false end
```

### Command Injection
Commands are constructed from validated data:
- Ability names from job definitions (trusted)
- Party indices validated (0-5)
- No user input directly in commands

### Resource Safety
Multiple validation layers prevent:
- Spamming abilities without resources
- Using abilities on cooldown
- Targeting invalid entities

## Future Enhancements

### Potential Improvements

1. **Alliance Support**: Extend to 18-member alliances
2. **Smart Throttling**: Dynamic throttle based on situation
3. **Ability Priorities**: Configure ability preferences
4. **Conditional Logic**: More complex ability triggers
5. **Profile System**: Multiple setting profiles per job
6. **Action Macros**: Chain multiple abilities
7. **Notification System**: Alert on low resources, etc.
8. **Telemetry**: Track usage statistics
9. **Auto-Update**: Check for new versions
10. **Job Templates**: Quick-start configurations

### Refactoring Opportunities

1. **Caching Layer**: Cache party data across modules
2. **Event Bus**: Decouple modules with event system
3. **Dependency Injection**: More testable architecture
4. **State Machine**: Explicit state management
5. **Async Actions**: Support for multi-step actions

## Testing Strategy

See TESTING.md for comprehensive testing guide.

**Key Areas:**
1. Unit tests (manual): Each component in isolation
2. Integration tests: End-to-end job automation
3. Stress tests: High-load scenarios
4. Regression tests: Verify no breaking changes

## Troubleshooting

### Common Issues

**Addon won't load:**
- Check Lua syntax errors
- Verify file structure
- Check Ashita version (v4 required)

**Automation not working:**
- Check `/sidekick status`
- Enable debug mode
- Verify settings in config UI

**Abilities not triggering:**
- Check resource availability (MP/TP)
- Verify cooldowns
- Check range (21 yalms default)
- Ensure conditions met (combat, idle, pet)

**Focus target not working:**
- Verify party member is active
- Check same zone
- Enable focus in config
- Use `/sidekick focus <0-5>`

### Debug Mode

Enable with `/sidekick debug` to see:
- Action selection logic
- Resource checking
- Cooldown status
- Target validation
- Packet processing (steps)

## Conclusion

Sidekick's architecture prioritizes:
- **Modularity**: Clear separation of concerns
- **Extensibility**: Easy to add jobs/abilities
- **Safety**: Multiple validation layers
- **Performance**: Efficient algorithms
- **Maintainability**: Clean, documented code

The result is a robust, flexible automation framework that can support nearly any job through configuration rather than code changes.
