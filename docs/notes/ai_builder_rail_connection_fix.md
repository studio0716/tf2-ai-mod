# AI Builder Rail Connection Fix

## Problem
AI Builder's `evaluateBestNewConnection()` was returning "sleeping" or finding no matching industries when trying to connect the iron ore mine to the steel mill.

## Root Cause
The base game industry construction files (e.g., `industry/iron_ore_mine.con`) are missing the AI Builder-specific parameters:
- `outputCargoTypeForAiBuilder`
- `inputCargoTypeForAiBuilder`
- `capacityForAiBuilder`
- `sourcesCountForAiBuilder`

Without these params, `discoverIndustryData()` cannot properly populate:
- `evaluation.industriesToOutput` - empty `{}` instead of `{'IRON_ORE'}`
- `evaluation.producerToConsumerMap` - empty `{}` instead of `{'industry/steel_mill.con'}`
- `evaluation.inputsToIndustries` - missing IRON_ORE -> steel_mill mapping

### The Bug
In `discoverIndustryData()` around line 389:
```lua
if not industriesToOutput[industryName] then  -- BUG: {} is truthy!
    result[industryName]=backupResult[industryName]  -- backup never used
```

The backup map at line 229 has the correct mapping:
```lua
backupResult["industry/iron_ore_mine.con"]={ "industry/steel_mill.con"}
```

But since `industriesToOutput["industry/iron_ore_mine.con"] = {}` (empty table, not nil), the condition `not industriesToOutput[industryName]` is false, so the backup is never used.

## Solution
Bypass the evaluation system entirely and call `buildIndustryRailConnection` directly via script event with a properly constructed result object.

### Key Discovery: SIM_BUILDING vs CONSTRUCTION IDs
- Construction ID 7740 = Iron ore mine construction
- SIM_BUILDING ID 15602 = Iron ore mine simulation entity (has `itemsProduced`, `itemsShipped`, etc.)
- Construction ID 1841 = Steel mill construction
- SIM_BUILDING ID 24324 = Steel mill simulation entity

The AI Builder functions expect SIM_BUILDING entities from `game.interface.getEntities()` with `includeData=true`, not construction entities.

### Working Code
```lua
local util = require 'ai_builder_base_util'

-- Get full entity data with SIM_BUILDING type
local circle = {pos = {0, 0}, radius = math.huge}
local entities = game.interface.getEntities(circle, {type='SIM_BUILDING', includeData=true})

local ironMine, steelMill
for id, entity in pairs(entities) do
    if entity.name == 'Independence Iron ore mine #2' then
        ironMine = entity
        ironMine.id = id
    elseif entity.name == 'Independence Steel mill' then
        steelMill = entity
        steelMill.id = id
    end
end

-- Build result object
local result = {
    industry1 = ironMine,
    industry2 = steelMill,
    cargoType = 'IRON_ORE',
    distance = 900,
    initialTargetLineRate = 200,
    edge1 = {id = 15563},  -- Edge must be object with .id field
    edge2 = nil,
    isAutoBuildMode = false,
    carrier = api.type.enum.Carrier.RAIL,
    isCargo = true
}

-- Trigger build via script event
api.cmd.sendCommand(
    api.cmd.make.sendScriptEvent('ai_builder_script', 'buildIndustryRailConnection', '', {result = result})
)
```

## Result
- Rail cargo station built at iron ore mine (ID 33502)
- Rail cargo station built at steel mill (ID 33505)
- Rail line created: "Independence Iron ore mine #2 Iron ore" (ID 32018)
- Line has 2 stops and rate of 224

## Lessons Learned
1. AI Builder expects `outputCargoTypeForAiBuilder` params in construction files - base game industries don't have these
2. The backup producer-to-consumer map exists but isn't used due to truthy empty table bug
3. Use SIM_BUILDING entities from `game.interface.getEntities()` with `includeData=true`
4. Edge parameters must be objects with `.id` field, not raw edge IDs
5. Script events like `buildIndustryRailConnection` can bypass the evaluation system entirely
6. **Game starts paused after restart** - must set game speed with `game.interface.setGameSpeed(3)` for 4x speed
7. **Always use cheapest build options** - Add `alreadyBudgetChecked = true` and `paramOverrides` with `stationLengthParam = 1`, `isDoubleTrack = false` to prevent "Not enough money" failures

---

## Road Connection

### Script Event
Use `buildNewIndustryRoadConnection` instead of `buildIndustryRailConnection`.

### Working Code
```lua
local util = require 'ai_builder_base_util'

-- Get full entity data
local circle = {pos = {0, 0}, radius = math.huge}
local entities = game.interface.getEntities(circle, {type='SIM_BUILDING', includeData=true})

local ironMine, steelMill
for id, entity in pairs(entities) do
    if entity.name and string.find(entity.name, 'Iron ore mine #2') then
        ironMine = entity
        ironMine.id = id
    elseif entity.name and string.find(entity.name, 'Independence Steel mill') then
        steelMill = entity
        steelMill.id = id
    end
end

-- Get positions and edges
local p1 = util.v3fromArr(ironMine.position)
local p2 = util.v3fromArr(steelMill.position)
local edge1 = util.searchForNearestEdge(p1)
local edge2 = util.searchForNearestEdge(p2)

-- Calculate distance
local dx = ironMine.position[1] - steelMill.position[1]
local dy = ironMine.position[2] - steelMill.position[2]
local dz = ironMine.position[3] - steelMill.position[3]
local distance = math.sqrt(dx*dx + dy*dy + dz*dz)

-- Build result object for road
local result = {
    industry1 = ironMine,
    industry2 = steelMill,
    cargoType = 'IRON_ORE',
    distance = distance,
    initialTargetLineRate = 200,
    edge1 = edge1 and {id = edge1} or nil,
    edge2 = edge2 and {id = edge2} or nil,
    p0 = p1,
    p1 = p2,
    isAutoBuildMode = false,
    carrier = api.type.enum.Carrier.ROAD,
    isCargo = true,
    needsNewRoute = true
}

-- Send script event
api.cmd.sendCommand(
    api.cmd.make.sendScriptEvent('ai_builder_script', 'buildNewIndustryRoadConnection', '', {result = result})
)
```

### Result
- Truck station at iron mine (ID 33318)
- Truck station at steel mill (ID 33320)
- 2 truck lines created connecting both stations

---

## Water/Ship Connection

### Prerequisites
Industries must be near navigable water. Use `getAppropriateVerticiesForPair()` to check:
```lua
local vertices = connectEval.getAppropriateVerticiesForPair(industry1, industry2, {transhipmentRange = 1500}, 1500)
-- If vertices.v1 and vertices.v2 are nil, no water nearby
```

### Script Event
Use `buildNewWaterConnections` with `verticies1` and `verticies2` fields.

### Working Code
```lua
local util = require 'ai_builder_base_util'
local connectEval = require 'ai_builder_new_connections_evaluation'

-- Get full entity data
local circle = {pos = {0, 0}, radius = math.huge}
local entities = game.interface.getEntities(circle, {type='SIM_BUILDING', includeData=true})

local coalMine, steelMill
for id, entity in pairs(entities) do
    if entity.name == 'Oceanside Coal mine' then
        coalMine = entity
        coalMine.id = id
    elseif entity.name == 'Oceanside Steel mill' then
        steelMill = entity
        steelMill.id = id
    end
end

-- Get water vertices (REQUIRED for ship connections)
local range = 1500
local vertices = connectEval.getAppropriateVerticiesForPair(coalMine, steelMill, {transhipmentRange = range}, range)

-- Calculate distance
local p1 = util.v3fromArr(coalMine.position)
local p2 = util.v3fromArr(steelMill.position)
local dx = coalMine.position[1] - steelMill.position[1]
local dy = coalMine.position[2] - steelMill.position[2]
local dz = coalMine.position[3] - steelMill.position[3]
local distance = math.sqrt(dx*dx + dy*dy + dz*dz)

-- Build result object with water vertices
local result = {
    industry1 = coalMine,
    industry2 = steelMill,
    cargoType = 'COAL',
    distance = distance,
    initialTargetLineRate = 200,
    p0 = p1,
    p1 = p2,
    verticies1 = vertices.v1,  -- REQUIRED for water
    verticies2 = vertices.v2,  -- REQUIRED for water
    isAutoBuildMode = false,
    carrier = api.type.enum.Carrier.WATER,
    isCargo = true
}

-- Send script event
api.cmd.sendCommand(
    api.cmd.make.sendScriptEvent('ai_builder_script', 'buildNewWaterConnections', '', {result = result})
)
```

### Result
- Oceanside Coal mine Harbour (ID 34069)
- Oceanside Steel mill Harbour (ID 34073)
- Ship line "Oceanside Coal mine-Oceanside Steel mill Coal" (ID 17993)

---

## Budget Bypass for Expensive Connections

### Problem
Long-distance rail connections fail with "Not enough money" even when funds are available, because the AI Builder tries to build expensive double-track stations by default.

### Solution
Use `alreadyBudgetChecked = true` and `paramOverrides` to force cheapest build options:

```lua
local result = {
    industry1 = coalMine,
    industry2 = steelMill,
    cargoType = 'COAL',
    distance = distance,
    initialTargetLineRate = 50,  -- Lower rate = fewer trains
    isAutoBuildMode = false,
    carrier = api.type.enum.Carrier.RAIL,
    isCargo = true,
    alreadyBudgetChecked = true,  -- CRITICAL: Skip budget validation
    paramOverrides = {
        stationLengthParam = 1,   -- Shortest/cheapest station
        isDoubleTrack = false,    -- Single track only
        ignoreErrors = true       -- Continue despite minor issues
    }
}

api.cmd.sendCommand(
    api.cmd.make.sendScriptEvent('ai_builder_script', 'buildIndustryRailConnection', '', {result = result, ignoreErrors = true})
)
```

### Key Parameters
- `alreadyBudgetChecked = true` - Skips budget validation that can reject builds
- `stationLengthParam = 1` - Builds shortest possible station (cheapest)
- `isDoubleTrack = false` - Single track instead of double (cheaper)
- `ignoreErrors = true` - Prevents build from aborting on minor issues

### Result (Oceanside Coal → Independence Steel)
- Rail station at Oceanside Coal mine (ID 35860)
- Rail station at Independence Steel mill
- Rail line "Oceanside Coal mine Coal" (ID 35364) with 2 stops, rate 44

### IMPORTANT: Always Use Cheapest Options
When building connections, **always** include these parameters to minimize cost:
- `alreadyBudgetChecked = true`
- `paramOverrides.stationLengthParam = 1`
- `paramOverrides.isDoubleTrack = false`

---

## Vehicle Assignment and autoLoadConfig

### autoLoadConfig = {1} enables ALL CARGO mode
Vehicles with `autoLoadConfig = {1}` will automatically load ANY compatible cargo at stations, not just a specific cargo type.

```lua
-- When creating vehicles, ALWAYS set:
vehiclePart.autoLoadConfig = {1}  -- ALL vehicles, NO EXCEPTIONS
```

### setLine Quirks
1. **Must try multiple stop indices** - `setLine(vehId, lineId, 0)` sometimes fails, try indices 0, 1, 2
2. **Don't call from Lua callback** - `setLine` in buyVehicle callback doesn't work reliably
3. **Call separately from Python** after vehicle creation

### Working Vehicle Assignment Pattern
```python
# After buying vehicle, try multiple stop indices
for stop_idx in [0, 1, 2]:
    eval_lua(f'api.cmd.sendCommand(api.cmd.make.setLine({veh_id}, {line_id}, {stop_idx}))')
    time.sleep(1)

# Verify assignment
vehicles = eval_lua(f'return api.engine.system.transportVehicleSystem.getLineVehicles({line_id})')
```

### Finding Vehicles in Depot
```lua
local depotVehicles = api.engine.system.transportVehicleSystem.getDepotVehicles(depotEntity)
```
