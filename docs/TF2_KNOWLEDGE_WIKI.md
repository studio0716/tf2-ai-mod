# Transport Fever 2 AI Bridge Knowledge Wiki

**Purpose**: Persistent knowledge base for TF2 modding via the AI Bridge. This document captures working patterns, API knowledge, and lessons learned.

**Last Updated**: 2024-12-20

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [File-Based IPC](#file-based-ipc)
3. [AI Builder Modules](#ai-builder-modules)
4. [Working Patterns](#working-patterns)
   - [Road Infrastructure](#road-infrastructure)
   - [Rail Infrastructure](#rail-infrastructure)
   - [Vehicles and Lines](#vehicles-and-lines)
5. [API Reference](#api-reference)
6. [Common Pitfalls](#common-pitfalls)
7. [Quick Reference Cards](#quick-reference-cards)

---

## Architecture Overview

### Components

```
┌─────────────────────┐     ┌─────────────────────┐
│   Python Scripts    │     │   Transport Fever 2  │
│   (tf2cmd.py etc)   │     │   Game Engine        │
└─────────┬───────────┘     └──────────┬──────────┘
          │                            │
          ▼                            ▼
┌─────────────────────┐     ┌─────────────────────┐
│ /tmp/tf2_ai_        │◄───►│   ai_bridge.lua     │
│ commands.json       │     │   (game_script)     │
└─────────────────────┘     └──────────┬──────────┘
                                       │
          ┌────────────────────────────┼────────────────────────────┐
          ▼                            ▼                            ▼
┌─────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│ ai_builder_     │     │ ai_builder_         │     │ ai_builder_         │
│ base_util.lua   │     │ construction_util   │     │ vehicle_util.lua    │
│ (426 functions) │     │ (155 functions)     │     │ (110 functions)     │
└─────────────────┘     └─────────────────────┘     └─────────────────────┘
```

### Key Files

| File | Location | Purpose |
|------|----------|---------|
| ai_bridge.lua | mod/res/config/game_script/ | Handles IPC, executes commands |
| ai_builder_base_util.lua | ai_builder_src/res/scripts/ | Core utilities (426 functions) |
| ai_builder_construction_util.lua | ai_builder_src/res/scripts/ | Building stations, depots (155 functions) |
| ai_builder_vehicle_util.lua | ai_builder_src/res/scripts/ | Vehicle configs (110 functions) |
| ai_builder_line_manager.lua | ai_builder_src/res/scripts/ | Line management (192 functions) |

---

## File-Based IPC

### Command File

**Location**: `/tmp/tf2_ai_commands.json`

**Format**:
```json
{
  "action": "eval",
  "params": {
    "code": "-- Lua code here"
  }
}
```

### Result File

**Location**: `/tmp/tf2_ai_result.json`

**Format**:
```json
{
  "command": "eval",
  "success": true,
  "value": "result string"
}
```

### Important: `api` Access in Eval

The `load()` function in Lua does NOT have access to `api` by default. The ai_bridge.lua MUST inject it:

```lua
-- CORRECT: api injected into environment
local env = setmetatable({api = api}, {__index = _G})
local fn, er = load(code, nil, "t", env)
```

---

## AI Builder Modules

### Module Loading

```lua
local util = require('ai_builder_base_util')
local constructionUtil = require('ai_builder_construction_util')
local vehicleUtil = require('ai_builder_vehicle_util')
local lineManager = require('ai_builder_line_manager')
local pathFindingUtil = require('ai_builder_pathfinding_util')
local vec3 = require('vec3')
```

### Key Function Categories (1871 total)

| Category | Count | Primary Module |
|----------|-------|----------------|
| Node Operations | 228 | ai_builder_base_util |
| Edge/Segment Ops | 255 | ai_builder_base_util |
| Pathfinding | 251 | ai_builder_pathfinding_util |
| Construction | 199 | ai_builder_construction_util |
| Stations | 197 | ai_builder_construction_util |
| Lines | 114 | ai_builder_line_manager |
| Road | 103 | ai_builder_base_util |
| Track | 99 | ai_builder_route_builder |
| Vehicles | 80 | ai_builder_vehicle_util |
| Connections | 65 | ai_builder_construction_util |
| Depots | 49 | ai_builder_construction_util |

---

## Working Patterns

### Road Infrastructure

#### Pattern: Build Connected Road Station

**CRITICAL**: Stations are NOT automatically connected. They have a "free node" with only 1 segment. Connection requires building an edge to an existing road node.

```lua
-- Step 1: Find a dead-end road node
local util = require('ai_builder_base_util')
local constructionUtil = require('ai_builder_construction_util')
local vec3 = require('vec3')

util.cacheNode2SegMaps()
local industryPos = vec3.new(-484, 852, 26)  -- Near target industry
local deadEnds = util.searchForDeadEndNodes(industryPos, 200)
local roadNode = deadEnds[1].id
local nodeDetails = util.getDeadEndNodeDetails(roadNode)

-- Step 2: Calculate station position (80m along tangent from dead-end)
local roadNodePos = vec3.new(nodeDetails.nodePos.x, nodeDetails.nodePos.y, nodeDetails.nodePos.z)
local tangent = vec3.normalize(vec3.new(nodeDetails.tangent.x, nodeDetails.tangent.y, 0))
local stationPos = roadNodePos + vec3.mul(80, tangent)

-- Step 3: Get terrain height and calculate angle
local z = api.engine.terrain.getHeightAt(api.type.Vec2f.new(stationPos.x, stationPos.y))
stationPos = vec3.new(stationPos.x, stationPos.y, z)
local baseTangent = vec3.new(0, 1, 0)
local angle = util.signedAngle(tangent, baseTangent)

util.clearCacheNode2SegMaps()

-- Step 4: Create and build station
local naming = {name = "Coal Station"}
local construction = constructionUtil.createRoadStationConstruction(
    stationPos, -angle, {isCargo=true}, naming, false, 1, 0, "Truck", 2
)

local proposal = api.type.SimpleProposal.new()
proposal.constructionsToAdd[1] = construction
api.cmd.sendCommand(api.cmd.make.buildProposal(proposal, util.initContext(), true),
    function(res, success)
        if success then
            local constructionId = res.resultEntities[1]
            -- Now connect it (see Step 5)
        end
    end
)
```

#### Pattern: Connect Construction to Road

```lua
-- Step 5: Get free node and connect to road
local function connectConstruction(constructionId, targetRoadNode)
    util.cacheNode2SegMaps()

    -- Get the free node
    local nodes = util.getFreeNodesForConstruction(constructionId)
    local freeNode = nodes[1]
    local freePos = util.nodePos(freeNode)

    -- Get target road position
    local roadPos = util.nodePos(targetRoadNode)
    local diff = roadPos - freePos

    -- Build connecting road
    local streetTypeId = api.res.streetTypeRep.find("standard/country_small_new.lua") or 16
    local proposal = api.type.SimpleProposal.new()
    local e = api.type.SegmentAndEntity.new()
    e.entity = -1
    e.type = 0  -- road (1 = rail)
    e.comp.node0 = freeNode
    e.comp.node1 = targetRoadNode
    util.setTangent(e.comp.tangent0, diff)
    util.setTangent(e.comp.tangent1, diff)
    e.streetEdge.streetType = streetTypeId
    proposal.streetProposal.edgesToAdd[1] = e

    util.clearCacheNode2SegMaps()

    api.cmd.sendCommand(api.cmd.make.buildProposal(proposal, util.initContext(), true), callback)
end
```

#### Verifying Connection

```lua
-- A construction is connected when its free node has ≥2 segments
util.cacheNode2SegMaps()
local segs = util.getSegmentsForNode(freeNode)
local isConnected = #segs > 1  -- true = connected
util.clearCacheNode2SegMaps()
```

### Road Depot

Similar to station, but use perpendicular offset:

```lua
-- Depot: 50m perpendicular to road tangent
local perpTangent = util.rotateXY(tangent, math.rad(90))
local depotPos = roadNodePos + vec3.mul(50, perpTangent)
local angle = util.signedAngle(perpTangent, baseTangent)

local naming = {name = "Truck Depot"}
local construction = constructionUtil.createRoadDepotConstruction(naming, depotPos, -angle)
```

---

### Vehicles and Lines

#### Pattern: Buy Vehicle and Assign to Line

**CRITICAL**: Use AI Builder's vehicleUtil for proper vehicle config.

```lua
-- Step 1: Build vehicle config
local vehicleUtil = require('ai_builder_vehicle_util')

local params = {
    cargoType = 'COAL',  -- COAL, IRON_ORE, STEEL, PASSENGERS, etc.
    distance = 2000      -- Route distance in meters
}
local truckConfig = vehicleUtil.buildTruck(params)
local apiVehicle = vehicleUtil.copyConfigToApi(truckConfig)  -- MUST convert!

-- Step 2: Buy vehicle
local playerId = api.engine.util.getPlayer()
local depotId = 24912  -- VehicleDepot entity, NOT construction entity

local buyCmd = api.cmd.make.buyVehicle(playerId, depotId, apiVehicle)
api.cmd.sendCommand(buyCmd, function(res, success)
    if success then
        local vehicleId = res.resultVehicleEntity

        -- Step 3: Assign to line
        local lineId = 24159
        local stopIndex = 0
        local assignCmd = api.cmd.make.setLine(vehicleId, lineId, stopIndex)
        api.cmd.sendCommand(assignCmd, function(res2, success2)
            -- Vehicle now operating on line
        end)
    end
end)
```

#### Pattern: Create Transport Line

```lua
local lineManager = require('ai_builder_line_manager')

-- Get station entities (NOT construction entities)
local coalStationId = 13790  -- Station entity
local steelStationId = 24985

-- Create line
local lineName = "Coal to Steel"
local line = api.type.Line.new()
line.vehicleInfo = api.type.VehicleInfo.new()
line.vehicleInfo.transportModes = {CARGO = true}

-- Add stops
local stop1 = api.type.Line.Stop.new()
stop1.station = coalStationId
stop1.terminal = 0
line.stops[1] = stop1

local stop2 = api.type.Line.Stop.new()
stop2.station = steelStationId
stop2.terminal = 0
line.stops[2] = stop2

-- Build line command
local createLineCmd = api.cmd.make.createLine(api.engine.util.getPlayer(), line)
api.cmd.sendCommand(createLineCmd, function(res, success)
    if success then
        local lineId = res.resultEntities[1]
        -- Now buy vehicles for line
    end
end)
```

#### Verify Vehicle on Line

```lua
local tvs = api.engine.system.transportVehicleSystem
local lineVehs = tvs.getLineVehicles(lineId)
-- lineVehs contains all vehicle IDs on the line
```

---

### Rail Infrastructure

#### Pattern: Build Rail Station

```lua
-- Similar to road but with trackType and different construction function
local trackTypeId = api.res.trackTypeRep.find("standard.lua") or 0

-- Use constructionUtil.createRailStationConstruction()
-- Rotation is in RADIANS
-- If station is 90° off from track, subtract math.rad(90) from rotation
```

---

## API Reference

### Key Systems

```lua
api.engine.system.lineSystem                 -- Transport lines
api.engine.system.transportVehicleSystem     -- Vehicles
api.engine.system.stationSystem              -- Stations
api.engine.system.stationGroupSystem         -- Station groups
api.engine.system.streetSystem               -- Roads
api.engine.system.streetConnectorSystem      -- Road connections, depots
api.engine.system.vehicleDepotSystem         -- Depots
api.engine.system.townBuildingSystem         -- Town buildings
api.engine.system.stockListSystem            -- Industry stocks
```

### Key Component Types

```lua
api.type.ComponentType.NAME                  -- Entity name
api.type.ComponentType.CONSTRUCTION          -- Construction entity
api.type.ComponentType.STATION               -- Station entity
api.type.ComponentType.LINE                  -- Line entity
api.type.ComponentType.TRANSPORT_VEHICLE     -- Vehicle entity
api.type.ComponentType.SIM_BUILDING          -- Industry
api.type.ComponentType.TOWN                  -- Town
api.type.ComponentType.VEHICLE_DEPOT         -- Depot entity
```

### Key Commands

```lua
-- Building
api.cmd.make.buildProposal(proposal, context, instant)

-- Vehicles
api.cmd.make.buyVehicle(playerId, depotId, vehicleConfig)
api.cmd.make.sellVehicle(vehicleId)
api.cmd.make.setLine(vehicleId, lineId, stopIndex)

-- Lines
api.cmd.make.createLine(playerId, line)
api.cmd.make.updateLine(lineId, line)
```

### Entity Discovery

```lua
-- Get all entities of a type
api.engine.forEachEntityWithComponent(function(entity, comp)
    -- Process entity
end, api.type.ComponentType.SIM_BUILDING)

-- Get component from entity
local name = api.engine.getComponent(entityId, api.type.ComponentType.NAME)
local comp = api.engine.getComponent(entityId, api.type.ComponentType.CONSTRUCTION)

-- Check entity exists
api.engine.entityExists(entityId)

-- Get player
api.engine.util.getPlayer()
```

---

## Common Pitfalls

### 1. API Not Available in Eval

**Problem**: `api` is nil in load() context
**Solution**: Inject api into environment:
```lua
local env = setmetatable({api = api}, {__index = _G})
local fn = load(code, nil, "t", env)
```

### 2. Station Not Connected

**Problem**: Station built but not reachable
**Cause**: Constructions have only 1 segment on their free node by default
**Solution**: Build connecting edge from free node to road/rail node

### 3. Wrong Entity Type for Depot

**Problem**: buyVehicle fails
**Cause**: Using construction entity instead of VehicleDepot entity
**Solution**: Get depot entity from vehicleDepotSystem or construction.depots[1]

### 4. Vehicle Config Not Converted

**Problem**: buyVehicle fails with type error
**Cause**: Passing raw config instead of API-compatible config
**Solution**: Use `vehicleUtil.copyConfigToApi(config)`

### 5. Multi-line Code Compile Error

**Problem**: "unexpected symbol near 'local'" error
**Cause**: ai_bridge adding "return " prefix to multi-statement code
**Solution**: Start code with comment `-- Comment` to force statement parsing

### 6. Cache Not Cleared

**Problem**: Node operations fail or return stale data
**Solution**: Always call `util.cacheNode2SegMaps()` before and `util.clearCacheNode2SegMaps()` after

### 7. Station vs Construction Entity

**Problem**: Line creation fails
**Cause**: Using construction entity ID instead of station entity ID
**Solution**: Get station from construction via `util.getStationsForConstruction(constructionId)[1]`

### 8. Connecting Industries to Town Stations (NOT Industry-to-Industry)

**Problem**: `buildNewIndustryRoadConnection` fails when target is a town station
**Cause**: The AI Builder's connection functions expect TWO INDUSTRIES, not industry → station
**Solution**: Use a two-step process:

1. **Build stations at industries** by connecting them to another industry that already has a station:
   ```lua
   -- This builds stations at BOTH industries
   result = {industry1 = sourceIndustry, industry2 = intermediaryIndustry, ...}
   api.cmd.sendCommand(api.cmd.make.sendScriptEvent('ai_builder_script', 'buildNewIndustryRoadConnection', '', {result = result}))
   ```

2. **Create lines directly** from industry stations to the town station:
   ```lua
   -- Get the station group for the industry (from existing line stops or search)
   local line = api.type.Line.new()
   local stop1 = api.type.Line.Stop.new()
   stop1.stationGroup = industryStationGroup  -- From existing line
   stop1.loadMode = 2  -- ANY cargo
   line.stops[1] = stop1
   local stop2 = api.type.Line.Stop.new()
   stop2.stationGroup = townStationGroup
   stop2.loadMode = 2
   line.stops[2] = stop2
   line.vehicleInfo.transportModes[api.type.enum.TransportMode.TRUCK+1] = 1
   api.cmd.sendCommand(api.cmd.make.createLine(name, color, player, line), callback)
   ```

**Key insight**: To find station groups from existing lines:
```lua
local lineComp = api.engine.getComponent(lineId, api.type.ComponentType.LINE)
local stationGroup = lineComp.stops[1].stationGroup  -- First stop's station group
```

---

## Quick Reference Cards

### Road Station Quick Build

```lua
-- Minimal pattern for connected road cargo station
local util = require('ai_builder_base_util')
local constructionUtil = require('ai_builder_construction_util')
local vec3 = require('vec3')

util.cacheNode2SegMaps()
local deadEnds = util.searchForDeadEndNodes(targetPos, 200)
local nodeDetails = util.getDeadEndNodeDetails(deadEnds[1].id)
local tangent = vec3.normalize(vec3.new(nodeDetails.tangent.x, nodeDetails.tangent.y, 0))
local stationPos = vec3.new(nodeDetails.nodePos.x, nodeDetails.nodePos.y, nodeDetails.nodePos.z) + vec3.mul(80, tangent)
stationPos = vec3.new(stationPos.x, stationPos.y, api.engine.terrain.getHeightAt(api.type.Vec2f.new(stationPos.x, stationPos.y)))
local angle = util.signedAngle(tangent, vec3.new(0,1,0))
util.clearCacheNode2SegMaps()

local construction = constructionUtil.createRoadStationConstruction(stationPos, -angle, {isCargo=true}, {name="Station"}, false, 1, 0, "Truck", 2)
local proposal = api.type.SimpleProposal.new()
proposal.constructionsToAdd[1] = construction
api.cmd.sendCommand(api.cmd.make.buildProposal(proposal, util.initContext(), true), callback)
-- Then connect free node to road!
```

### Vehicle Purchase Quick Pattern

```lua
local vehicleUtil = require('ai_builder_vehicle_util')
local config = vehicleUtil.buildTruck({cargoType='COAL', distance=2000})
local apiConfig = vehicleUtil.copyConfigToApi(config)
local cmd = api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depotEntityId, apiConfig)
api.cmd.sendCommand(cmd, function(res, success)
    if success then
        local vehicleId = res.resultVehicleEntity
        api.cmd.sendCommand(api.cmd.make.setLine(vehicleId, lineId, 0), callback)
    end
end)
```

### Connection Verification

```lua
util.cacheNode2SegMaps()
local segs = util.getSegmentsForNode(freeNodeId)
local connected = #segs > 1
util.clearCacheNode2SegMaps()
```

---

## Entity ID Reference (Current Game Session)

| Entity | Type | ID |
|--------|------|-----|
| Depot (construction) | CONSTRUCTION | 24729 |
| Depot (vehicle depot) | VEHICLE_DEPOT | 24912 |
| Coal Station (construction) | CONSTRUCTION | 24913 |
| Coal Station (station) | STATION | 13790 |
| Steel Station (construction) | CONSTRUCTION | 24988 |
| Steel Station (station) | STATION | 24985 |
| Line "Coal to Steel" | LINE | 24159 |
| Truck | TRANSPORT_VEHICLE | 25050 |
| Coal Mine #2 | SIM_BUILDING | 19566 |
| Steel Mill | SIM_BUILDING | 17850 |

---

## See Also

- `AI_BUILDER_FUNCTION_INDEX.md` - Complete function index (1871 functions)
- `ai_builder_functions.json` - Programmatic function lookup
- `TASK_LOG.md` - Execution log with step-by-step examples
- `TF2_API_Reference.md` - Original API discoveries
