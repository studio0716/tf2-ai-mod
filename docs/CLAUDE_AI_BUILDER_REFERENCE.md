# Transport Fever 2 AI Builder - Claude Agent Reference

This document provides a comprehensive reference for Claude agents working with the Transport Fever 2 AI Builder mod. It covers game APIs, supply chain logic, town management, and line building functions.

---

Key misses you forget all the time:
++++++TO RESTART THE GAME USE restart_tf2.sh
++++++REVIEW THE LOGS /Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt after every command and periodically
to understand if there are errors.  you must get the async results from the ai builder.
++++++The game starts paused from teh save.  To do anthing you need to set game speed 1-4x.

## Table of Contents

0. [Getting Started - CRITICAL SETUP](#0-getting-started---critical-setup)
1. [Architecture Overview](#1-architecture-overview)
2. [Game API Reference](#2-game-api-reference)
3. [Industries and Supply Chains](#3-industries-and-supply-chains)
4. [Town Management](#4-town-management)
5. [Line Building and Management](#5-line-building-and-management)
6. [Vehicle Management](#6-vehicle-management)
7. [Error Monitoring (CRITICAL)](#7-error-monitoring-critical)
8. [IPC Command System (HOW TO SEND COMMANDS)](#8-ipc-command-system-how-to-send-commands) ⭐ **START HERE**
   - 8.1 Architecture Overview
   - 8.2 Step-by-Step: How to Send a Command
   - 8.3 Sending Commands Programmatically (Python)
   - 8.4 Using Auto Manage Functions
   - 8.5 Querying Game State
   - 8.6 Complete Workflow Example
   - 8.7 Understanding the Async Work Queue
   - 8.8 File IPC Details
9. [Common Patterns](#9-common-patterns)
10. [Supply Chain Optimization Strategy](#10-supply-chain-optimization-strategy)
11. [Critical Rules and Common Pitfalls](#11-critical-rules-and-common-pitfalls)
12. [Profit Strategy: Bidirectional Routes](#12-profit-strategy-bidirectional-routes)
12.3. [High-Utilization Line Strategies](#123-high-utilization-line-strategies-critical-for-profitability) ⭐ **AVOID 50% P2P WASTE**
   - Strategy 1: Multi-Stop Circular Routes
   - Strategy 2: Reuse Existing Stations
   - Strategy 3: Reassign Vehicles (DON'T SELL/BUY)
   - Strategy 4: Extend Existing Lines
   - Strategy 5: Identify Complementary Cargo Flows
12.4. [Smart Route Generation (3+ STOPS)](#124-smart-route-generation-3-stop-candidates) ⭐ **THINK SUPPLY CHAINS**
   - Return Cargo Analysis (check B→A before building A→B)
   - Existing Station Detection (don't build if one exists)
   - Route Generation Priority Order
   - Updated Decision Tree
12.45. [Multi-Stop Route Implementation](#1245-multi-stop-route-implementation-current-state) 🔧 **CURRENT STATE**
   - Files: `ai_builder_new_connections_evaluation.lua`, `ai_builder_script.lua`
   - Functions: `evaluateMultiStopCargoRoutes`, staged build in `buildIndustryRailConnection`
   - Debug: `/tmp/tf2_multistop_trace.txt`
   - Limitation: Creates 2 separate lines (not 1 multi-stop line yet)
12.5. [IPC Troubleshooting Guide](#125-ipc-troubleshooting-guide)
13. [Common Workflow Patterns (Claude Agent Tested)](#13-common-workflow-patterns-claude-agent-tested) ⭐ **NEW**
   - 13.1 Query Industries by Region/Name
   - 13.2 Find Stations by Name
   - 13.3 Connect Industries to Existing Town Station (Two-Step Process)
   - 13.4 Get Station Groups from Existing Lines
   - 13.5 Batch Connect Multiple Industries to One Station
   - 13.6 File IPC Query Pattern
   - 13.7 Supply Chain Compatibility Notes
14. [Quick Reference Cards](#14-quick-reference-cards)

---

## 0. Getting Started - CRITICAL SETUP

### Restarting the Game

To restart Transport Fever 2 with the AI Builder mod loaded, use the restart script:

```bash
./restart_tf2.sh
```

This script:
1. Kills any running TF2 process
2. Launches the game via Steam
3. Automatically clicks through the menu to load the save
4. Waits for the game to fully load (~20 seconds)

### CRITICAL: Set Game Speed Before Sending Commands

**The game starts PAUSED (speed 0).** Before sending any build commands, you MUST set the game speed to 4x:

```bash
python3 tf2_eval.py "game.interface.setGameSpeed(4)"
```

**IMPORTANT: This command DOES work even when the game appears paused.** The game still processes IPC commands at speed 0, just more slowly. Send the command and wait - it will execute.

**DO NOT ask the user to manually unpause.** The `setGameSpeed(4)` command works via IPC. If the command seems slow to respond, just wait longer (up to 30 seconds). The daemon queues the command and the game will process it.

**After sending setGameSpeed(4), verify it worked:**
```bash
python3 tf2_eval.py "return game.interface.getGameSpeed()"
# Should return: 4
```

Build commands execute faster at higher speeds. Always set to 4x before construction operations.

### CRITICAL: Set Load Mode to ANY for Cargo Lines

**For cargo lines and vehicles, you MUST set the load mode to ANY (autoload).** Without this, vehicles will wait indefinitely at stations for full loads that may never come.

```lua
-- When creating line stops, set loadMode to ANY (value 2)
local stop = api.type.Line.Stop.new()
stop.stationGroup = stationGroup
stop.station = stationId
stop.terminal = terminalIndex
stop.loadMode = 2  -- 0=default, 1=full load, 2=ANY (autoload)

-- Load modes:
-- 0 = Default (game decides)
-- 1 = Full Load (wait until full - AVOID for cargo)
-- 2 = ANY / Autoload (load what's available and go - USE THIS)
```

When using line manager functions, ensure params include autoload settings:
```lua
params.loadMode = 2  -- Force autoload/ANY mode
```

### Startup Checklist for Claude Agents

1. **Restart game** if needed: `./restart_tf2.sh`
2. **Wait for load**: Allow 20-30 seconds after script completes
3. **Verify IPC connection** (simple test that always works):
   ```bash
   echo '{"command":"print(\"[CLAUDE_TEST] IPC OK - \" .. os.date())"}' > /tmp/tf2_llm_command.json
   sleep 3
   tail -5 "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt" | grep CLAUDE_TEST
   ```
   You should see: `[CLAUDE_TEST] IPC OK - <timestamp>`

4. **Set game speed to 4x**:
   ```bash
   echo '{"command":"game.interface.setGameSpeed(4)"}' > /tmp/tf2_llm_command.json
   ```

5. **Start error monitor**: Launch parallel agent to tail game logs (see Section 7)
6. **Begin operations**: Now safe to send build commands

**NOTE:** The simple `print()` + `os.date()` test is more reliable than `api.engine.getGameTime()` which can fail if game APIs aren't fully loaded.

### Two-Agent Architecture (RECOMMENDED)

When building infrastructure, run **two parallel agents**:

```
┌─────────────────────┐     ┌─────────────────────┐
│   BUILD AGENT       │     │   MONITOR AGENT     │
│   (Main thread)     │     │   (Parallel thread) │
├─────────────────────┤     ├─────────────────────┤
│ - Sends tf2_eval    │     │ - Tails stdout.txt  │
│ - Executes Lua code │     │ - Watches for errors│
│ - Manages work queue│     │ - Reports failures  │
│ - Retries on failure│◄────│ - Alerts main agent │
└─────────────────────┘     └─────────────────────┘
```

**Why this matters:** AI Builder's async work queue means build failures happen *after* the command returns. Without a monitor, you'll think builds succeeded when they actually failed.

---

## 1. Architecture Overview

### Core Files

| File | Purpose |
|------|---------|
| `ai_builder_script.lua` | Main game script - GUI, work queues, Auto Manage toggles |
| `ai_builder_line_manager.lua` | Line creation, vehicle management, profitability analysis |
| `ai_builder_new_connections_evaluation.lua` | Industry/town connection evaluation, supply chain logic |
| `ai_builder_route_evaluation.lua` | Route pathfinding and scoring |
| `ai_builder_construction_util.lua` | Station and depot construction |
| `ai_builder_base_util.lua` | Utility functions, API wrappers |
| `ai_builder_town_panel.lua` | Town-specific bus coverage and cargo delivery |
| `ai_builder_vehicle_util.lua` | Vehicle selection and configuration |

### Work Queue System

The mod uses asynchronous work queues to avoid blocking the game:

```lua
-- Add work to primary queue
lineManager.addWork(function() ... end)

-- Add high-priority work (front of queue)
lineManager.addDelayedWork(function() ... end)

-- Add background/low-priority work
lineManager.addBackgroundWork(function() ... end)

-- Execute immediately with error handling
lineManager.executeImmediateWork(function() ... end)
```

---

## 2. Game API Reference

### Getting Entities

```lua
-- Get all industries on the map
local industries = game.interface.getEntities({radius=math.huge, pos={0,0,0}}, {type="SIM_BUILDING", includeData=false})

-- Get all towns
local towns = game.interface.getEntities({radius=math.huge, pos={0,0,0}}, {type="TOWN", includeData=false})

-- Get entities in a specific area
local nearby = game.interface.getEntities({radius=500, pos={x, y, z}}, {type="SIM_BUILDING", includeData=true})

-- Get entity data
local entityData = game.interface.getEntity(entityId)
```

### Component Access

```lua
-- Get any component from an entity
local component = api.engine.getComponent(entityId, api.type.ComponentType.XXX)

-- Common component types:
-- api.type.ComponentType.STATION
-- api.type.ComponentType.LINE
-- api.type.ComponentType.CONSTRUCTION
-- api.type.ComponentType.TRANSPORT_VEHICLE
-- api.type.ComponentType.TOWN
-- api.type.ComponentType.SIM_BUILDING
-- api.type.ComponentType.NAME

-- Iterate all entities with a component type
api.engine.forEachEntityWithComponent(function(entityId)
    -- Process entity
end, api.type.ComponentType.XXX)

-- Check if entity exists
if api.engine.entityExists(entityId) then ... end
```

### Station and Line Systems

```lua
-- Get all lines
local allLines = api.engine.system.lineSystem.getLines()

-- Get problem lines (unprofitable, stuck vehicles, etc.)
local problemLines = api.engine.system.lineSystem.getProblemLines(api.engine.util.getPlayer())

-- Get stations for a town
local townStations = api.engine.system.stationSystem.getStations(townId)

-- Get lines stopping at a station
local lines = api.engine.system.lineSystem.getLineStopsForStation(stationId)

-- Get station group
local stationGroup = api.engine.system.stationGroupSystem.getStationGroup(stationId)

-- Get construction for a station
local constructionId = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(stationId)
```

### Game Time and Player

```lua
-- Get current game time
local gameTime = game.interface.getGameTime()
local year = gameTime.date.year
local timeUnits = gameTime.time  -- 60 units = 1 month

-- Get player entity
local player = api.engine.util.getPlayer()

-- Get player's balance
local balance = game.interface.getEntity(game.interface.getPlayer()).balance

-- Set game speed (0 = paused)
game.interface.setGameSpeed(speed)
```

---

## 3. Industries and Supply Chains

### Understanding Industry Data

The mod discovers industry data from construction templates:

```lua
-- Key data structures (from discoverIndustryData):
evaluation.industriesToOutput[fileName] = {"CARGO1", "CARGO2"}  -- What industry produces
evaluation.inputsToIndustries[cargoType] = {"industry1.con", "industry2.con"}  -- Who consumes cargo
evaluation.ruleSources[fileName][cargoType] = sourceCount  -- How many sources needed
evaluation.baseCapacities[fileName] = capacity  -- Base production rate
evaluation.productionLevelCache[industryId] = levels  -- Upgrade levels available
evaluation.maxConsumption[fileName][cargoType] = maxRate  -- Max consumption rate
```

### Monitoring Industry Production Levels

**CRITICAL: Industries have Production, Supply, and Transport metrics that determine output.**

```lua
-- Get industry production rate (current output)
local production = game.interface.getIndustryProduction(industry.stockList)

-- Get production limit (max possible output based on supplies)
local productionLimit = game.interface.getIndustryProductionLimit(constructionId)

-- Get shipping rate (how much is being transported away)
local shippingRate = game.interface.getIndustryShipping(constructionId)

-- Check if industry is at full capacity
local isAtCapacity = (production >= productionLimit)

-- Check if industry needs more transport
local needsMoreTransport = (production > shippingRate)
```

### Industry Entity Fields

```lua
-- Get industry entity data
local industry = game.interface.getEntity(industryId)

-- Key fields available on industry entity:
industry.id                 -- Entity ID
industry.name              -- Display name
industry.position          -- {x, y, z} array
industry.stockList         -- Construction ID (confusingly named)
industry.itemsProduced     -- Table: {CARGO_NAME = rate, _sum = total}
industry.itemsConsumed     -- Table: {CARGO_NAME = rate, _sum = total}
industry.itemsShipped      -- Table: {CARGO_NAME = rate, _sum = total} - what's being transported

-- Check if primary industry (produces without inputs)
local isPrimary = (industry.itemsConsumed._sum == 0 and industry.itemsProduced._sum > 0)
```

### Production Level Optimization

**Industries level up when supplied and served. Monitor these metrics:**

```lua
-- Get SIM_BUILDING component for level info
local simBuilding = api.engine.getComponent(industryId, api.type.ComponentType.SIM_BUILDING)
local currentLevel = (simBuilding.level or 0) + 1  -- zero-based

-- Get max production levels from template
local maxLevels = evaluation.productionLevelCache[industryId]

-- Check if industry can still upgrade
local canUpgrade = (currentLevel < maxLevels)

-- Industry upgrades when:
-- 1. All input cargo types are being delivered
-- 2. Output cargo is being transported away
-- 3. Sustained over time
```

### Vanilla Supply Chains

```
Raw Materials (Primary Industries - No Inputs):
- Iron Ore Mine → IRON_ORE → Steel Mill
- Coal Mine → COAL → Steel Mill
- Forest → LOGS → Saw Mill
- Oil Well → CRUDE → Oil Refinery
- Quarry → STONE → Construction Materials
- Farm → GRAIN → Food Processing Plant

Processing Industries (Require Inputs):
- Steel Mill (IRON_ORE + COAL) → STEEL
- Saw Mill (LOGS) → PLANKS
- Oil Refinery (CRUDE) → FUEL + PLASTIC
- Chemical Plant (CRUDE) → PLASTIC

Final Goods (Delivered to Towns):
- Food Processing Plant (GRAIN) → FOOD → COMMERCIAL buildings
- Tools Factory (STEEL + PLANKS) → TOOLS → INDUSTRIAL buildings
- Machines Factory (STEEL + PLASTIC) → MACHINES → INDUSTRIAL buildings
- Goods Factory (STEEL + PLASTIC) → GOODS → COMMERCIAL buildings
- Construction Materials (STONE + STEEL) → CONSTRUCTION_MATERIALS → INDUSTRIAL buildings
- Fuel Refinery (CRUDE) → FUEL → COMMERCIAL buildings
```

### Supply Chain Connectivity Analysis

```lua
-- Check if industries are already connected
local isConnected = evaluation.checkIfIndustriesAlreadyConnected(industry1, industry2, cargoType)

-- Get existing sources supplying an industry
local sources = api.engine.system.stockListSystem.getSources(constructionId)

-- Get cargo source map (who produces what, who consumes what)
local cargoMap = api.engine.system.stockListSystem.getCargoType2stockList2sourceAndCount()

-- Check how many sources an industry has vs. needs
local maxSourcesNeeded = evaluation.ruleSources[fileName][cargoType]
local currentSources = countSourcesOfSameType(producer, consumer, cargoType)
local canAcceptMore = (currentSources < maxSourcesNeeded)
```

### Industry API Functions

```lua
-- Get industry production levels
local production = game.interface.getIndustryProduction(industry.stockList)

-- Get cargo sources for an entity (who supplies it)
local sources = api.engine.system.stockListSystem.getSources(constructionId)

-- Get cargo type to stock list mapping
local cargoMap = api.engine.system.stockListSystem.getCargoType2stockList2sourceAndCount()

-- Get construction ID for industry
local constructionId = api.engine.system.streetConnectorSystem.getConstructionEntityForSimBuilding(industryId)

-- Check cargo type info
local cargoTypeId = api.res.cargoTypeRep.find("STEEL")
local cargoRep = api.res.cargoTypeRep.get(cargoTypeId)
local townInput = cargoRep.townInput  -- Land use types that consume this cargo
```

### Evaluating New Connections

```lua
-- Key functions in ai_builder_new_connections_evaluation.lua:

-- Check if connection already attempted and failed
evaluation.checkIfFailed(transportType, locationId1, locationId2)

-- Mark connection as failed (with cooldown)
evaluation.markConnectionAsFailed(transportType, locationId1, locationId2)

-- Mark connection as complete
evaluation.markConnectionAsComplete(transportType, locationId1, locationId2)

-- Check if already connected
evaluation.checkIfIndustriesAlreadyConnected(industry1, industry2, cargoType)

-- Evaluate new train connection
local result = connectEval.evaluateNewIndustryConnectionForTrains(circle)

-- Evaluate new truck connection
local result = connectEval.evaluateNewIndustryConnectionForRoad(circle)
```

---

## 4. Town Management

### Town Capacities and Needs

```lua
-- Get town capacities (residential, commercial, industrial)
local capacities = game.interface.getTownCapacities(townId)
-- capacities[1] = residential capacity
-- capacities[2] = commercial capacity
-- capacities[3] = industrial capacity

-- Get town entity data
local town = game.interface.getEntity(townId)
local position = town.position  -- {x, y, z}
local name = town.name
```

### Land Use Types and Cargo Demands

**CRITICAL: Different town building types need different cargo types!**

```lua
-- Towns have different building types that need different cargo:
api.type.enum.LandUseType.RESIDENTIAL  -- People need transport (passengers)
api.type.enum.LandUseType.COMMERCIAL   -- Needs GOODS, FOOD, FUEL
api.type.enum.LandUseType.INDUSTRIAL   -- Needs MACHINES, TOOLS, CONSTRUCTION_MATERIALS
```

### Cargo → Town Building Mapping

```lua
-- Get which cargo types go to towns (have townInput defined)
local function getTownCargoTypes()
    local townCargos = {}
    for _, cargoTypeName in pairs(api.res.cargoTypeRep.getAll()) do
        local i = api.res.cargoTypeRep.find(cargoTypeName)
        local cargoRep = api.res.cargoTypeRep.get(i)
        if #cargoRep.townInput > 0 then
            -- cargoRep.townInput contains LandUseType values
            -- e.g., FOOD → {COMMERCIAL}, TOOLS → {INDUSTRIAL}
            table.insert(townCargos, {name = cargoTypeName, landUse = cargoRep.townInput[1]})
        end
    end
    return townCargos
end

-- Cargo to Land Use mapping:
-- FOOD         → COMMERCIAL
-- GOODS        → COMMERCIAL
-- FUEL         → COMMERCIAL
-- TOOLS        → INDUSTRIAL
-- MACHINES     → INDUSTRIAL
-- CONSTRUCTION_MATERIALS → INDUSTRIAL
```

### Town Demand Analysis

```lua
-- Get town's capacity for each building type
local capacities = game.interface.getTownCapacities(townId)
local residentialCap = capacities[1]  -- Population potential
local commercialCap = capacities[2]   -- Commercial building capacity
local industrialCap = capacities[3]   -- Industrial building capacity

-- Commercial capacity determines demand for: FOOD, GOODS, FUEL
-- Industrial capacity determines demand for: TOOLS, MACHINES, CONSTRUCTION_MATERIALS

-- Get town reachability (how many destinations town can reach)
local reachability = game.interface.getTownReachability(townId)
-- reachability[1] = residential destinations reachable
-- reachability[2] = commercial + industrial destinations reachable

-- Towns grow when:
-- 1. Residents have transport to jobs (passenger lines)
-- 2. Commercial buildings receive FOOD/GOODS/FUEL
-- 3. Industrial buildings receive TOOLS/MACHINES/CONSTRUCTION_MATERIALS
```

### Checking Town Cargo Coverage

```lua
-- Get buildings in a town
local townBuildingMap = api.engine.system.townBuildingSystem.getTown2BuildingMap()
local buildings = townBuildingMap[townId]

-- For each building, check if it's in a cargo station catchment
local catchmentMap = api.engine.system.catchmentAreaSystem.getEdge2stationsMap()

-- Check if town is already receiving a cargo type
local function townIsReceivingCargo(townId, cargoType)
    -- Check if any cargo stations in town are on lines delivering this cargo
    local townStations = api.engine.system.stationSystem.getStations(townId)
    for _, stationId in pairs(townStations) do
        local lines = api.engine.system.lineSystem.getLineStopsForStation(stationId)
        for _, lineId in pairs(lines) do
            local lineCargoType = lineManager.discoverLineCargoType(lineId)
            if lineCargoType == cargoType then
                return true
            end
        end
    end
    return false
end
```

### Town Delivery Priority Strategy

**Order of importance for town growth:**

1. **FOOD** (COMMERCIAL) - Basic necessity, unlocks growth
2. **GOODS** (COMMERCIAL) - Enables commercial expansion
3. **CONSTRUCTION_MATERIALS** (INDUSTRIAL) - Enables building new structures
4. **TOOLS** (INDUSTRIAL) - Supports industrial production
5. **MACHINES** (INDUSTRIAL) - Advanced industrial growth
6. **FUEL** (COMMERCIAL) - Vehicle support

**Strategy:** Prioritize delivering FOOD first, then GOODS, then industrial cargo.

### Town Coverage Analysis

The `ai_builder_town_panel.lua` module analyzes coverage:

```lua
-- Get catchment area mapping (which edges are covered by stations)
local catchmentAreaMap = api.engine.system.catchmentAreaSystem.getEdge2stationsMap()

-- Get station to edges mapping
local station2edges = api.engine.system.catchmentAreaSystem.getStation2edgesMap()

-- Get town buildings
local townBuildingMap = api.engine.system.townBuildingSystem.getTown2BuildingMap()

-- Get parcel data (buildings on road segments)
local parcelData = api.engine.system.parcelSystem.getSegment2ParcelData()
```

### Expanding Coverage

```lua
-- Key functions in townPanel:
townPanel.autoExpandBusCoverage()      -- Add bus stops to uncovered areas
townPanel.autoExpandCargoCoverage()    -- Add cargo stations
townPanel.autoExpandAllCoverage()      -- Combined (more efficient)
townPanel.buildNewTownBusStop(param)   -- Build specific bus stop
```

---

## 5. Line Building and Management

### Creating Lines

```lua
-- Create a line with vehicles
lineManager.createLineAndAssignVechicles(
    vehicleConfig,    -- Vehicle configuration
    stations,         -- Array of station entities
    lineName,         -- String name
    numberOfVehicles, -- Initial vehicle count
    carrier,          -- api.type.enum.Carrier.XXX
    params,           -- Additional parameters
    callback          -- Completion callback
)

-- Create line via API command
local line = api.type.Line.new()
line.vehicleInfo.transportModes[api.type.enum.TransportMode.TRAIN+1] = 1
-- Add stops...
local create = api.cmd.make.createLine(name, color, player, line)
api.cmd.sendCommand(create, callback)

-- Update existing line
api.cmd.sendCommand(api.cmd.make.updateLine(lineId, newLine), callback)
```

### Line Types (Carriers)

```lua
api.type.enum.Carrier.ROAD   -- Buses, trucks
api.type.enum.Carrier.TRAM   -- Trams
api.type.enum.Carrier.RAIL   -- Trains
api.type.enum.Carrier.WATER  -- Ships
api.type.enum.Carrier.AIR    -- Aircraft
```

### Transport Modes

```lua
api.type.enum.TransportMode.BUS
api.type.enum.TransportMode.TRUCK
api.type.enum.TransportMode.TRAM
api.type.enum.TransportMode.ELECTRIC_TRAM
api.type.enum.TransportMode.TRAIN
api.type.enum.TransportMode.ELECTRIC_TRAIN
api.type.enum.TransportMode.SHIP
api.type.enum.TransportMode.SMALL_SHIP
api.type.enum.TransportMode.AIRCRAFT
api.type.enum.TransportMode.SMALL_AIRCRAFT
```

### Line Reports and Profitability

```lua
-- Get comprehensive line report
local report = lineManager.getLineReport(lineId, line, isForVehicleReport, useRouteInfo, displayOnly, paramOverrides)

-- Report contains:
report.isOk              -- Boolean: line is healthy
report.isCongested       -- Boolean: too many vehicles
report.currentRate       -- Current throughput rate
report.targetLineRate    -- Target throughput based on demand
report.averageSpeed      -- Average vehicle speed
report.tripTime          -- Round trip time
report.problems          -- Table of detected issues
report.recommendations   -- Table of suggested fixes
report.upgradeBudget     -- Cost to implement recommendations

-- Execute line updates
report.executeUpdate()

-- Get demand rate for cargo lines
local demandRate = lineManager.getDemandRate(lineId, line, report, params)

-- Check and update all lines
lineManager.checkLinesAndUpdate(param, reportFn)
```

### Line Upgrades

```lua
-- Upgrade track to double track
lineManager.upgradeToDoubleTrack(lineId)

-- Electrify track
lineManager.upgradeToElectricTrack(lineId)

-- Upgrade to high speed track
lineManager.upgradeToHighSpeedTrack(lineId)

-- Extend station platforms
lineManager.upgradeStationLength(lineId, callback)

-- Add double terminals (more platform capacity)
lineManager.addDoubleTerminalsToLine(lineId)
```

### Specific Line Types

```lua
-- Train lines between stations
lineManager.setupTrainLineBetweenStations(station1, station2, params, callback)
lineManager.createNewTrainLineBetweenStations(stations, params, callback, suffix)

-- Bus/tram lines
lineManager.setupBusLineBetweenStations(station1, station2, params)
lineManager.setupBusOrTramLine(vehicleConfig, station1, station2, lineName, numberOfBusses, isTram, callback, params)

-- Truck lines (cargo)
lineManager.setupTruckLine(stations, params, result, alreadyCalled)

-- Ship lines
lineManager.createShipLine(result, stationConstr1, depotConst1, stationConstr2, depotConst2, callback, cargoType, initialTargetRate)

-- Air lines
lineManager.createAirLine(town1, town2, result)
lineManager.setupCargoAirline(result, callback)
```

---

## 6. Vehicle Management

### Buying Vehicles

```lua
-- Buy and assign vehicle to line
lineManager.buyVehicleForLine(lineId, stopIndex, depotOptions, newVehicleConfig, callback, alreadyAttempted)

-- Build vehicle and assign
lineManager.buildVehicleAndAssignToLine(vehicleConfig, depotEntity, lineId, callback, stopIndex)

-- Replace old vehicle
lineManager.replaceVehicle(vehicleId, alreadyAttempted)

-- Replace all vehicles on line with newer models
lineManager.replaceLineVehicles(lineId, params)

-- Sell all vehicles on a line
lineManager.sellAllVehicles(lineId)
```

### Vehicle States

```lua
-- Get vehicles by state
local vehicles = api.engine.system.transportVehicleSystem.getVehiclesWithState(state)

-- States:
api.type.enum.TransportVehicleState.AT_TERMINAL
api.type.enum.TransportVehicleState.IN_DEPOT
api.type.enum.TransportVehicleState.EN_ROUTE
```

### Finding Depots

```lua
-- Find depots that can service a line
local depots = lineManager.findDepotsForLine(lineId, carrier, nonStrict, isElectric)

-- Build depot for line if none exists
lineManager.buildDepotForLine(lineId, callback)
```

---

## 7. Error Monitoring (CRITICAL)

### Log File Location

**Game logs are stored at:**
```
/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/
```

Key files:
- `stdout.txt` - Main game output including Lua errors and AI Builder traces
- `stderr.txt` - Error output

### Why Error Monitoring is Essential

**AI Builder uses an async work queue.** Build commands don't fail immediately - they're queued and executed on subsequent game ticks. This means:

1. `api.cmd.sendCommand()` returns immediately (success just means "queued")
2. Actual build failures happen later in the callback
3. Some errors only appear in game logs, not in callbacks
4. Without monitoring, you won't know a build failed

### Required: Parallel Error Monitoring Thread

**When sending build commands, you MUST run a parallel agent to monitor logs:**

```python
# Start error monitor BEFORE sending build commands
# Monitor thread should:
# 1. Tail the stdout.txt file
# 2. Watch for error patterns
# 3. Report failures back to main agent

LOG_PATH = "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt"
```

### Common Error Patterns to Watch For

```
# Build failures
"Construction not possible"
"Too much curvature"
"Collision detected"
"Invalid proposal"
"errorState"

# Connection failures
"No path found"
"Unable to connect"
"Edge creation failed"

# Vehicle/Line failures
"Vehicle could not be purchased"
"Line creation failed"
"No valid depot"

# Lua errors
"attempt to index"
"attempt to call"
"nil value"
"stack traceback"
```

### Error Monitoring Script Pattern

```python
import subprocess
import time
import re

LOG_PATH = "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt"

ERROR_PATTERNS = [
    r"Construction not possible",
    r"Too much curvature",
    r"Collision detected",
    r"errorState",
    r"attempt to index",
    r"attempt to call",
    r"nil value",
    r"stack traceback",
    r"FAILED",
    r"Error:",
]

def monitor_logs(duration_seconds=30):
    """Monitor game logs for errors during build operations."""
    # Get current file size to start from
    import os
    start_pos = os.path.getsize(LOG_PATH) if os.path.exists(LOG_PATH) else 0

    errors_found = []
    start_time = time.time()

    while time.time() - start_time < duration_seconds:
        with open(LOG_PATH, 'r') as f:
            f.seek(start_pos)
            new_content = f.read()

            for pattern in ERROR_PATTERNS:
                matches = re.findall(f".*{pattern}.*", new_content, re.IGNORECASE)
                errors_found.extend(matches)

            start_pos = f.tell()

        time.sleep(0.5)

    return errors_found
```

### Integration with Build Commands

**Pattern: Send command + Monitor in parallel**

```python
import threading

def build_with_monitoring(lua_code, monitor_duration=10):
    """Execute build command while monitoring for errors."""
    errors = []

    # Start monitor thread
    def monitor_thread():
        nonlocal errors
        errors = monitor_logs(monitor_duration)

    monitor = threading.Thread(target=monitor_thread)
    monitor.start()

    # Send build command
    result = send_tf2_eval(lua_code)

    # Wait for monitor to complete
    monitor.join()

    return {
        'command_result': result,
        'errors_detected': errors,
        'success': len(errors) == 0
    }
```

### Debugging Failed Builds

When an error is detected:

1. **Parse the error message** - Identify the specific failure type
2. **Check callback result** - Look for `resultProposalData.errorState`
3. **Examine the proposal** - Log the construction/edge data that failed
4. **Try alternative approaches**:
   - Different position (offset further from obstacles)
   - Different angle (rotate station)
   - Simpler construction (single terminal instead of double)

### AI Builder Trace Messages

AI Builder logs extensive trace information. Look for:

```
trace("Building station at", position)
trace("Connection result:", success)
trace("Line created with id:", lineId)
```

These help identify where in the async queue a failure occurred.

---

## 8. IPC Command System (HOW TO SEND COMMANDS)

This section explains the EXACT mechanism for sending commands to the running game. This is the most important section for Claude agents who want to build and manage transport networks.

### 8.1 Architecture Overview (SIMPLIFIED)

```
┌─────────────────────┐                    ┌─────────────────────┐
│   Claude Agent      │    File IPC        │   TF2 Game          │
│   (bash/python)     │  ◄────────────►    │   (ai_builder mod)  │
└─────────────────────┘                    └─────────────────────┘
        │                                           │
        │ echo '{"command":"..."}' >                │ Polls /tmp/tf2_llm_command.json
        │   /tmp/tf2_llm_command.json               │ every ~30 ticks (~0.5s)
        │                                           │
        │ cat /tmp/tf2_llm_result.json        ◄─────│ Writes results to
        │                                           │ /tmp/tf2_llm_result.json
        └───────────────────────────────────────────┘
```

**NO DAEMON REQUIRED** - Direct file IPC is simpler and more reliable.

**Key Files:**
| File | Purpose |
|------|---------|
| `/tmp/tf2_llm_command.json` | Claude writes commands, game reads & clears |
| `/tmp/tf2_llm_result.json` | Game writes results, Claude reads |
| `/tmp/tf2_socket_manager.log` | Debug log from game-side IPC |
| `res/scripts/socket_manager.lua` | Game-side file IPC handler |
| `res/scripts/ai_builder_agent.lua` | Game-side command executor |

### 8.2 Step-by-Step: How to Send a Command

**Step 1: Send a Lua command (one line)**

```bash
# Simple: just write JSON to the command file
echo '{"command":"print(\"Hello from Claude!\")"}' > /tmp/tf2_llm_command.json
```

**Step 2: Wait for game to process (~0.5-1 second)**

The game polls every ~30 ticks. At 4x speed, this is roughly 0.5 seconds.

```bash
sleep 1
```

**Step 3: Check the result (if any)**

```bash
cat /tmp/tf2_llm_result.json
```

**Step 4: Check game stdout for output**

```bash
tail -5 "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt"
```

### 8.3 Sending Commands Programmatically (Python)

```python
import json
import time

COMMAND_FILE = "/tmp/tf2_llm_command.json"
RESULT_FILE = "/tmp/tf2_llm_result.json"
GAME_LOG = "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt"

def send_lua(code: str):
    """Send Lua code to the game."""
    with open(COMMAND_FILE, "w") as f:
        json.dump({"command": code}, f)

def get_result(timeout: float = 5.0):
    """Wait for and read result from game."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            with open(RESULT_FILE, "r") as f:
                content = f.read().strip()
                if content:
                    # Clear the file
                    open(RESULT_FILE, "w").close()
                    return json.loads(content)
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.2)
    return None

def eval_lua(code: str, timeout: float = 5.0):
    """Execute Lua code and wait for result."""
    send_lua(code)
    time.sleep(0.5)  # Give game time to poll
    return get_result(timeout)

# Example usage:
send_lua("game.interface.setGameSpeed(4)")
time.sleep(1)
send_lua("print('[CLAUDE] Speed set to 4x')")
```

### 8.4 Using Auto Manage Functions

The Auto Manage system is controlled by the `aiEnableOptions` table in the game. Here's how to trigger specific build operations:

**Available Auto Manage Options:**
```lua
aiEnableOptions = {
    autoEnablePassengerTrains = false,   -- Build intercity passenger rail
    autoEnableFreightTrains = false,     -- Build cargo rail connections
    autoEnableTruckFreight = false,      -- Build truck cargo routes
    autoEnableIntercityBus = false,      -- Build intercity bus lines
    autoEnableShipFreight = false,       -- Build cargo ship routes
    autoEnableShipPassengers = false,    -- Build passenger ferry routes
    autoEnableAirPassengers = false,     -- Build passenger air routes
    autoEnableAirFreight = false,        -- Build cargo air routes
    autoEnableLineManager = false,       -- Manage existing lines (add vehicles)
    autoEnableHighwayBuilder = false,    -- Build highway connections
    autoEnableFullManagement = false,    -- Full auto mode (all operations)
    autoExpandBusCoverage = false,       -- Expand bus coverage in towns
    autoExpandCargoCoverage = false,     -- Expand cargo coverage in towns
    pauseOnError = false,                -- Pause game on build errors
}
```

**Method 1: Toggle Auto Manage Options via Script Event**

```bash
# Enable freight trucks
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"aiEnableOptions\", \"\", {aiEnableOptions = {autoEnableTruckFreight = true}}))"}' > /tmp/tf2_llm_command.json

# Enable both trains and trucks
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"aiEnableOptions\", \"\", {aiEnableOptions = {autoEnableFreightTrains = true, autoEnableTruckFreight = true}}))"}' > /tmp/tf2_llm_command.json
```

**Method 2: Trigger Specific Build Operations Directly**

```bash
# Build a new industry road connection (trucks)
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"buildNewIndustryRoadConnection\", \"\", {ignoreErrors = false}))"}' > /tmp/tf2_llm_command.json

# Build a new industry rail connection (trains)
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"buildIndustryRailConnection\", \"\", {ignoreErrors = false}))"}' > /tmp/tf2_llm_command.json

# Build intercity bus connection
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"buildNewTownRoadConnection\", \"\", {ignoreErrors = false}))"}' > /tmp/tf2_llm_command.json

# Build passenger train connection
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"buildNewPassengerTrainConnections\", \"\", {ignoreErrors = false}))"}' > /tmp/tf2_llm_command.json

# Build water/ship connections
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"buildNewWaterConnections\", \"\", {ignoreErrors = false}))"}' > /tmp/tf2_llm_command.json

# Build air connections
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"buildNewAirConnections\", \"\", {ignoreErrors = false}))"}' > /tmp/tf2_llm_command.json
```

**Method 3: Multi-line Lua Scripts**

For complex scripts, use a heredoc or Python:

```python
import json

code = """
local connectEval = require('ai_builder_new_connections_evaluation')
local result = connectEval.evaluateNewIndustryConnectionForCarrier(nil, api.type.enum.Carrier.ROAD)
if result then
    api.cmd.sendCommand(api.cmd.make.sendScriptEvent('ai_builder_script', 'buildNewIndustryRoadConnection', '', {result = result}))
end
"""
with open("/tmp/tf2_llm_command.json", "w") as f:
    json.dump({"command": code}, f)
```

### 8.5 Querying Game State

**Get Game Speed:**
```bash
echo '{"command":"print(\"[SPEED] \" .. game.interface.getGameSpeed())"}' > /tmp/tf2_llm_command.json
# Check stdout for result
```

**Print All Lines:**
```bash
echo '{"command":"local lines = api.engine.system.lineSystem.getLines(); for _, id in pairs(lines) do local n = api.engine.getComponent(id, api.type.ComponentType.NAME); print(\"[LINE] \" .. (n and n.name or id)) end"}' > /tmp/tf2_llm_command.json
```

**Get Current Funds:**
```bash
echo '{"command":"local p = api.engine.util.getPlayer(); local m = api.engine.system.budgetSystem.getMoney(p); print(\"[FUNDS] \" .. m)"}' > /tmp/tf2_llm_command.json
```

### 8.6 Complete Workflow Example

Here's a complete example using the simplified file IPC:

```python
#!/usr/bin/env python3
"""Example: Build a truck freight route using AI Builder (Simple File IPC)"""

import json
import time

COMMAND_FILE = "/tmp/tf2_llm_command.json"
GAME_LOG = "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt"

def send_lua(code: str):
    """Send Lua code to the game."""
    with open(COMMAND_FILE, "w") as f:
        json.dump({"command": code}, f)
    print(f"Sent: {code[:50]}...")

def wait_and_check(seconds=1):
    """Wait and show recent log output."""
    time.sleep(seconds)
    with open(GAME_LOG, "r") as f:
        lines = f.readlines()[-5:]
        for line in lines:
            if "[CLAUDE]" in line or "[SOCKET_MGR]" in line:
                print(line.strip())

# Step 1: Set game speed to 4x
print("Setting game speed to 4x...")
send_lua("game.interface.setGameSpeed(4); print('[CLAUDE] Speed set to 4x')")
wait_and_check(2)

# Step 2: Trigger auto-evaluation and build
print("Building new truck freight connection...")
send_lua("""
api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
    'ai_builder_script',
    'buildNewIndustryRoadConnection',
    '',
    {ignoreErrors = false}
))
print('[CLAUDE] Build command sent')
""")
wait_and_check(2)

# Step 3: Wait and monitor for completion
print("Monitoring for build completion (check game logs)...")
time.sleep(10)  # Give time for async build
```

### 8.7 Understanding the Async Work Queue

**CRITICAL:** Build commands are ASYNCHRONOUS. When you send a command, it:
1. Gets queued in the AI Builder work queue
2. Executes over multiple game ticks
3. May spawn child work items (e.g., build station → build road → create line)
4. Reports completion/failure via game logs (NOT via command response)

**This means:**
- Command responses only confirm the command was QUEUED, not that it succeeded
- You MUST monitor game logs for actual success/failure
- Use the Two-Agent Architecture (build agent + monitor agent)
- Allow time between commands for work queue to clear

### 8.8 File IPC Details (Simplified)

**Claude → Game (Commands):**
- File: `/tmp/tf2_llm_command.json`
- Format: `{"command": "lua code here"}`
- Game polls every ~30 ticks (~0.5s at 4x speed)
- Game clears file after reading

**Game → Claude (Results):**
- File: `/tmp/tf2_llm_result.json`
- Game writes results from `socket_manager.send_result()`
- Claude reads and processes

**Debug Log:**
- File: `/tmp/tf2_socket_manager.log`
- Shows all IPC activity from game side

**Polling Interval:** Game polls every ~30 ticks (configurable in `ai_builder_agent.lua`)

---

## 9. Common Patterns

### Building a Complete Cargo Route

```lua
-- 1. Evaluate best connection
local result = connectEval.evaluateNewIndustryConnectionForTrains(circle)

-- 2. Check budget
if not budgetCheck(params) then return end

-- 3. Build stations if needed
constructionUtil.buildStations(...)

-- 4. Build track/road
routeBuilder.buildRoute(...)

-- 5. Create line and vehicles
lineManager.createLineAndAssignVechicles(...)

-- 6. Mark connection as complete
connectEval.markConnectionAsComplete(carrier, location1, location2)
```

### Auto Manage Loop

```lua
-- In tickUpdate(), when auto manage is enabled:
local function doTriggerWork()
    if aiEnableOptions.autoEnableFreightTrains then
        buildIndustryRailConnection()
    end
    if aiEnableOptions.autoEnableLineManager then
        checkLines()
    end
    -- etc...
end
```

### Error Handling Pattern

```lua
xpcall(function()
    -- Risky operation
end, function(x)
    print("Error:", x)
    print(debug.traceback())
    -- Mark current build as failed
    if currentBuildParams then
        currentBuildParams.status2 = "Failed"
        connectEval.markConnectionAsFailed(carrier, loc1, loc2)
    end
end)
```

### Callback Pattern

```lua
local function standardCallback(res, success)
    util.clearCacheNode2SegMaps()
    if not success then
        trace("Command failed")
        debugPrint(res.resultProposalData.errorState)
    end
end
```

---

## Quick Reference: Key Functions for Claude Agents

### Get Game State
- `game.interface.getGameTime()` - Current date/time
- `game.interface.getEntity(id)` - Entity data
- `util.getAvailableBudget()` - Current money

### Find Things
- `game.interface.getEntities(area, filter)` - Find entities
- `api.engine.system.lineSystem.getLines()` - All lines
- `api.engine.system.stationSystem.getStations(town)` - Town's stations

### Analyze Industries
- `game.interface.getIndustryProduction(stockList)` - Production rate
- `api.engine.system.stockListSystem.getSources(construction)` - Supply sources
- `connectEval.checkIfIndustriesAlreadyConnected(i1, i2, cargo)` - Existing routes

### Build Routes
- `lineManager.createLineAndAssignVechicles(...)` - Create complete line
- `lineManager.setupTrainLineBetweenStations(...)` - Train line
- `lineManager.setupTruckLine(...)` - Truck route

### Manage Lines
- `lineManager.getLineReport(lineId)` - Analyze line health
- `lineManager.checkLinesAndUpdate()` - Auto-optimize all lines
- `lineManager.replaceLineVehicles(lineId)` - Upgrade vehicles

### Town Delivery
- `game.interface.getTownCapacities(town)` - Town needs
- `townPanel.autoExpandCargoCoverage()` - Add cargo stations
- `lineManager.setupBusLineBetweenStations(...)` - Intercity bus

### Monitor & Optimize
- `game.interface.getIndustryProduction(stockList)` - Current production
- `game.interface.getIndustryProductionLimit(constructionId)` - Max possible production
- `game.interface.getIndustryShipping(constructionId)` - Transport rate
- `industry.itemsConsumed` / `industry.itemsProduced` / `industry.itemsShipped` - Flow analysis

---

## 10. Supply Chain Optimization Strategy

### The Three Metrics: Production, Supply, Transport

**Every industry has three key metrics to monitor:**

| Metric | API Call | Meaning |
|--------|----------|---------|
| **Production** | `getIndustryProduction(stockList)` | Current output rate |
| **ProductionLimit** | `getIndustryProductionLimit(constructionId)` | Max possible with current supply |
| **Shipping** | `getIndustryShipping(constructionId)` | Rate cargo is being transported away |

### Optimization Decision Tree

```
IF production < productionLimit:
    → Industry needs MORE SUPPLY (connect more source industries)

IF production == productionLimit AND shipping < production:
    → Industry needs MORE TRANSPORT (add vehicles to lines)

IF production == productionLimit AND shipping == production:
    → Industry is OPTIMIZED (look for expansion opportunities)
```

### Bottleneck Detection

```lua
local function analyzeIndustry(industryId)
    local industry = game.interface.getEntity(industryId)
    local constructionId = industry.stockList

    local production = game.interface.getIndustryProduction(constructionId)
    local productionLimit = game.interface.getIndustryProductionLimit(constructionId)
    local shipping = game.interface.getIndustryShipping(constructionId)

    local bottleneck = nil

    if production < productionLimit * 0.9 then
        bottleneck = "SUPPLY"  -- Need to connect more input sources
    elseif shipping < production * 0.9 then
        bottleneck = "TRANSPORT"  -- Need more vehicles on output lines
    else
        bottleneck = "NONE"  -- Industry running efficiently
    end

    return {
        production = production,
        productionLimit = productionLimit,
        shipping = shipping,
        bottleneck = bottleneck,
        inputsNeeded = industry.itemsConsumed,
        outputsProduced = industry.itemsProduced
    }
end
```

### Full Supply Chain Audit

**Audit each stage of the supply chain:**

```
1. PRIMARY INDUSTRIES (Mines, Farms, Forests, Oil Wells)
   - Check: Is shipping == production? If not, add transport.
   - Goal: 100% of production transported away

2. PROCESSING INDUSTRIES (Steel Mills, Saw Mills, Refineries)
   - Check: Is production == productionLimit? If not, add supply lines.
   - Check: Is shipping == production? If not, add transport.
   - Goal: Full supply AND full transport

3. FINAL GOODS FACTORIES (Food Processing, Tools, Goods, Machines)
   - Check: Is production == productionLimit? If not, supply is constrained.
   - Check: Is shipping to towns? If not, connect to towns.
   - Goal: Full production delivered to towns

4. TOWNS
   - Check: Are COMMERCIAL buildings receiving FOOD/GOODS?
   - Check: Are INDUSTRIAL buildings receiving TOOLS/MACHINES?
   - Goal: All building types have cargo coverage
```

### Priority Order for New Connections

**Build connections in this order for fastest ROI:**

1. **Unserved Primary Industries** → Processing
   - Mines/Farms with 0% shipping rate
   - Quick wins: high production, no competition

2. **Underserved Processing** → Get to 100% supply
   - Steel mills with < 2 supply sources
   - Saw mills with no log supply

3. **Full Processing** → Towns
   - Factories at 100% production but low shipping
   - Connect to nearest town's commercial/industrial zones

4. **Town Coverage Expansion**
   - Add cargo stations to uncovered commercial/industrial areas
   - Ensure all building types have access

### Line Efficiency Monitoring

```lua
local function getLineEfficiency(lineId)
    local report = lineManager.getLineReport(lineId)

    -- Key metrics from report:
    -- report.currentRate - actual throughput
    -- report.targetLineRate - desired throughput based on demand
    -- report.isCongested - too many vehicles
    -- report.problems - table of issues
    -- report.recommendations - suggested fixes

    local efficiency = 0
    if report.targetLineRate > 0 then
        efficiency = report.currentRate / report.targetLineRate * 100
    end

    return {
        efficiency = efficiency,
        isCongested = report.isCongested,
        problems = report.problems,
        upgradeBudget = report.upgradeBudget
    }
end
```

---

## 11. Critical Rules and Common Pitfalls

### Station Placement Rules

**Truck/Cargo Stations:**
- Place on the **SAME side** of the road as the industry
- Offset **80m+** from the road node (NOT 40-60m like depots)
- Orient **ALONG** the road tangent (NOT perpendicular)
- Perpendicular placement causes "Too much curvature" error

**Train Stations:**
- Place on the **OPPOSITE side** of the road from the industry
- Tracks at rotation=0 run north-south (y-axis)
- Track approaching station MUST align with station track direction

**Depots:**
- Offset 40-60m **perpendicular** to the road
- Entrance must face toward the road
- Train depot exit is ~40m south of center (at rotation=0)

### Entity ID Confusion

**CRITICAL**: Different entity types are NOT interchangeable!

| Task | WRONG Entity Type | RIGHT Entity Type |
|------|-------------------|-------------------|
| Buy vehicles | Construction ID | VehicleDepot ID |
| Create line stops | Construction ID | Station ID |
| Assign stop to line | Station ID | StationGroup ID |

```lua
-- Get StationGroup from Station
local stationGroup = api.engine.system.stationGroupSystem.getStationGroup(stationId)

-- Get VehicleDepot entity (iterate depots)
api.engine.system.vehicleDepotSystem.forEach(function(vdEntity) ... end)

-- Get Station from Construction
local station = util.getStationsForConstruction(constructionId)[1]
```

### Deferred Execution is MANDATORY

Construction commands are **asynchronous**. Operations after construction MUST be deferred:

```lua
api.cmd.sendCommand(buildCommand, function(res, success)
    if success then
        constructionUtil.addWork(function()
            -- This runs on next tick AFTER construction settles
            -- Safe to: connect roads, assign vehicles, etc.
        end)
    end
end)
```

**Common failure:** Vehicle assignment crash when calling setLine immediately.
**Solution:** Double-defer with `addWork(function() addWork(function() ... end) end)`

### Cache Management

Always bracket node operations with cache calls:

```lua
util.cacheNode2SegMaps()
-- ... node operations (search, pathfinding, etc.) ...
util.clearCacheNode2SegMaps()
```

**Failure mode:** Stale data, operations fail silently, or return wrong nodes.

### Connection Verification

A construction is connected when its free node has ≥2 segments:

```lua
util.cacheNode2SegMaps()
local freeNodes = util.getFreeNodesForConstruction(constructionId)
local segs = util.getSegmentsForNode(freeNodes[1])
local isConnected = #segs > 1  -- true = connected to network
util.clearCacheNode2SegMaps()
```

### Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| "Too much curvature" | Station perpendicular to road | Place ALONG tangent, not perpendicular |
| "Construction not possible" | Connecting road too short | Increase offset (80m+ for stations) |
| Connection fails silently | Race condition | Use `addWork()` for deferred execution |
| Vehicle assignment crash | Called setLine immediately | Double-defer with `addWork()` |
| "attempt to index 'naming'" | Wrong function signature | Pass `{name="string"}` table |
| `api` is nil in eval | Not injected into load() | Use `setmetatable({api=api}, {__index=_G})` |

---

## 12. Profit Strategy: Bidirectional Routes

### The Problem with Simple Routes

A typical Coal → Steel Mill route has trains:
- **Full** going TO the steel mill (carrying coal)
- **Empty** returning FROM the steel mill

This means **50% of train capacity is wasted**.

### The Solution: Bidirectional Raw Materials

Steel mills require TWO inputs: **Coal** and **Iron Ore**.

By connecting TWO steel mills:
- Train carries **Coal** from Steel Mill A → Steel Mill B
- Train carries **Iron Ore** from Steel Mill B → Steel Mill A
- **100% capacity utilization in both directions**

```
Coal Mine ─────┐                           ┌───── Iron Ore Mine
    (truck)    │                           │    (truck)
               ▼                           ▼
        ┌─────────────┐             ┌─────────────┐
        │ Steel Mill A │◄═══════════►│ Steel Mill B │
        │  Receives:  │   TRAIN      │  Receives:  │
        │  - Coal     │   LINE       │  - Iron Ore │
        │    (truck)  │ ──────────►  │    (truck)  │
        │  - Iron Ore │   Iron Ore   │  - Coal     │
        │    (train)  │ ◄──────────  │    (train)  │
        └─────────────┘    Coal      └─────────────┘
```

### Why This Works Financially

| Route Type | Outbound Load | Return Load | Efficiency |
|------------|---------------|-------------|------------|
| Simple (coal→steel) | Full | Empty | 50% |
| Bidirectional | Full | Full | **100%** |

- Double the revenue per train round trip
- Same operating costs (fuel, maintenance)
- Faster ROI on expensive train infrastructure

### Distance Guidelines

- **Ideal train distance**: 2-5km between industries
- **Truck feeder routes**: 1-2km from mine to steel mill station
- **Station catchment**: ~400m radius

---

## 12.3 High-Utilization Line Strategies (CRITICAL FOR PROFITABILITY)

### The P2P Problem

Point-to-point (P2P) lines like "Coal Mine → Steel Mill" have **50% utilization** because vehicles return empty. This is financially wasteful.

```
P2P Line (BAD - 50% utilization):
Coal Mine ──[FULL]──► Steel Mill
Coal Mine ◄──[EMPTY]── Steel Mill
```

### Strategy 1: Multi-Stop Circular Routes

Instead of separate P2P lines, create ONE circular line that picks up cargo at multiple stops:

```
Circular Route (BETTER - 75-100% utilization):
Coal Mine → Steel Mill → Iron Mine → Steel Mill → Coal Mine
   [coal]      [iron]      [iron]      [coal]
```

**Implementation:**
```lua
-- Create line with multiple stops (not just 2)
local stops = {
    {stationGroup = coalMineStation, loadMode = 2},    -- Pick up coal
    {stationGroup = steelMillStation, loadMode = 2},   -- Drop coal, pick up nothing
    {stationGroup = ironMineStation, loadMode = 2},    -- Pick up iron
    {stationGroup = steelMillStation, loadMode = 2},   -- Drop iron
}
-- Single line serves multiple industries
```

### Strategy 2: Reuse Existing Stations (DON'T BUILD NEW)

Before building a new station, check if one already exists nearby:

```lua
-- Find existing stations near a position
local function findNearbyStations(pos, radius)
    local stations = {}
    api.engine.forEachEntityWithComponent(function(entity, comp)
        local stationPos = api.engine.getComponent(entity, api.type.ComponentType.POSITION)
        if stationPos then
            local dist = math.sqrt((pos.x - stationPos.position.x)^2 + (pos.y - stationPos.position.y)^2)
            if dist < radius then
                table.insert(stations, {id = entity, distance = dist})
            end
        end
    end, api.type.ComponentType.STATION)
    return stations
end

-- Use existing station instead of building new
local nearby = findNearbyStations(industryPos, 500)
if #nearby > 0 then
    -- ADD this industry to existing line, don't build new station
    local existingStation = nearby[1].id
end
```

### Strategy 3: Reassign Vehicles (DON'T SELL/BUY)

When rebalancing lines, **reassign vehicles** instead of selling and buying:

```lua
-- Reassign vehicle from one line to another
local function reassignVehicle(vehicleId, newLineId)
    -- Vehicle must be stopped or at depot for clean reassignment
    api.cmd.sendCommand(
        api.cmd.make.setLine(vehicleId, newLineId, 0),  -- 0 = first stop
        function(res, success)
            if success then
                print("Vehicle reassigned to new line")
            end
        end
    )
end

-- Get all vehicles on a line
local function getLineVehicles(lineId)
    return api.engine.system.transportVehicleSystem.getLineVehicles(lineId)
end

-- Rebalance: move vehicles from overstaffed to understaffed lines
local function rebalanceLines(fromLineId, toLineId, count)
    local vehicles = getLineVehicles(fromLineId)
    for i = 1, math.min(count, #vehicles) do
        reassignVehicle(vehicles[i], toLineId)
    end
end
```

### Strategy 4: Extend Existing Lines (Add Stops)

Instead of creating new lines, add stops to existing profitable lines:

```lua
-- Add a new stop to an existing line
local function addStopToLine(lineId, newStationGroup, insertPosition)
    local line = api.engine.getComponent(lineId, api.type.ComponentType.LINE)
    local stops = line.stops

    -- Create new stop
    local newStop = api.type.LineStop.new()
    newStop.stationGroup = newStationGroup
    newStop.loadMode = 2  -- ANY/autoload

    -- Insert at position (or append)
    table.insert(stops, insertPosition or #stops + 1, newStop)

    -- Update line
    api.cmd.sendCommand(
        api.cmd.make.updateLine(lineId, stops, line.vehicleInfo),
        standardCallback
    )
end
```

### Strategy 5: Identify Complementary Cargo Flows

Look for industries that produce what others consume:

| Industry A Produces | Industry B Produces | Bidirectional Potential |
|---------------------|---------------------|-------------------------|
| Coal Mine → Coal | Iron Mine → Iron Ore | Both feed Steel Mill |
| Forest → Logs | Quarry → Stone | Both feed Construction |
| Oil Well → Oil | Refinery → Fuel | Chain linkable |

---

## 12.4 Smart Route Generation (3+ STOP CANDIDATES)

### The Key Insight

**Don't just evaluate A→B. Always look for A→B→C (or more).**

When the AI evaluates a new connection, it should:
1. Find the primary connection (e.g., Coal Mine → Steel Mill)
2. Ask: "What else is near the destination that needs cargo OR produces cargo?"
3. Build a 3+ stop route instead of P2P

### Example: Supply Chain Extension Routes

Instead of building isolated P2P lines, think in **supply chains**:

```
BAD (3 separate P2P lines, 50% utilization each):
  Coal Mine → Steel Mill     [empty return]
  Iron Mine → Steel Mill     [empty return]
  Steel Mill → Tool Factory  [empty return]

GOOD (1 circular line, ~85% utilization):
  Coal Mine → Steel Mill → Iron Mine → Steel Mill → Tool Factory → Town → Coal Mine
      [coal]     [steel]     [iron]      [steel]      [tools]    [goods]
```

### 3+ Stop Route Templates

| Route Pattern | Stops | Cargo Flow |
|---------------|-------|------------|
| **Raw→Process→Deliver** | Forest → Saw Mill → Town | Logs → Planks → (town consumes) |
| **Dual-Input Processor** | Coal Mine → Steel Mill → Iron Mine | Coal → Steel, Iron → Steel |
| **Production Chain** | Oil Well → Refinery → Town | Oil → Fuel → (town consumes) |
| **Triangle Trade** | Quarry → Construction → Forest → Saw Mill | Stone → Planks → Stone... |

### Return Cargo Analysis (CRITICAL)

**Before building A→B, ALWAYS check if B→A has cargo potential:**

```lua
-- Return cargo analysis function
local function analyzeReturnCargo(fromIndustry, toIndustry)
    -- Get what 'to' industry produces
    local toProduction = getIndustryProduction(toIndustry.id)

    -- Get what 'from' industry (or nearby industries) consumes
    local fromConsumes = getIndustryInputs(fromIndustry.id)
    local nearbyConsumers = findNearbyIndustries(fromIndustry.position, 1000)

    -- Check for match
    for _, cargo in pairs(toProduction) do
        if fromConsumes[cargo] then
            return {hasBidirectional = true, returnCargo = cargo, target = fromIndustry}
        end
        for _, nearby in pairs(nearbyConsumers) do
            if getIndustryInputs(nearby.id)[cargo] then
                return {hasBidirectional = true, returnCargo = cargo, target = nearby}
            end
        end
    end

    return {hasBidirectional = false}
end

-- Prioritize routes with bidirectional potential
local function scoreRouteCandidate(route)
    local baseScore = route.profit  -- or distance-based score
    local returnAnalysis = analyzeReturnCargo(route.from, route.to)

    if returnAnalysis.hasBidirectional then
        return baseScore * 2.0  -- Double score for bidirectional potential
    end
    return baseScore * 0.5  -- Penalize pure P2P routes
end
```

### Existing Station Detection (BEFORE BUILDING NEW)

```lua
-- ALWAYS run this before building a new station
local function findExistingStationForIndustry(industryPos, cargoType, radius)
    radius = radius or 500
    local candidates = {}

    -- Get all stations
    local allStations = {}
    api.engine.forEachEntityWithComponent(function(entity, comp)
        table.insert(allStations, entity)
    end, api.type.ComponentType.STATION)

    for _, stationId in pairs(allStations) do
        local pos = api.engine.getComponent(stationId, api.type.ComponentType.POSITION)
        if pos then
            local dist = math.sqrt(
                (industryPos.x - pos.position.x)^2 +
                (industryPos.y - pos.position.y)^2
            )
            if dist < radius then
                -- Check if station handles this cargo type
                local stationComp = api.engine.getComponent(stationId, api.type.ComponentType.STATION)
                table.insert(candidates, {
                    id = stationId,
                    distance = dist,
                    -- Could also check cargo compatibility
                })
            end
        end
    end

    -- Sort by distance
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    return candidates
end

-- Usage in route building:
local function buildSmartRoute(fromIndustry, toIndustry, cargoType)
    -- Step 1: Check for existing stations
    local existingFromStation = findExistingStationForIndustry(fromIndustry.position, cargoType)
    local existingToStation = findExistingStationForIndustry(toIndustry.position, cargoType)

    if #existingFromStation > 0 and #existingToStation > 0 then
        -- BEST: Both stations exist, just create/extend line
        print("Using existing stations - no construction needed!")
        return createLineWithExistingStations(existingFromStation[1], existingToStation[1])
    elseif #existingFromStation > 0 or #existingToStation > 0 then
        -- GOOD: One station exists, only build one new
        print("Reusing one existing station")
    else
        -- OK: Must build both (but still check for 3+ stop potential)
        print("Building new stations - checking for 3+ stop route...")
    end
end
```

### Route Generation Priority Order

When evaluating potential new routes, score them in this order:

```
PRIORITY 1 (Best): Extend existing line with new stop
  - No new stations needed
  - No new vehicles needed
  - Immediate utilization improvement

PRIORITY 2: Create line between existing stations
  - No construction cost
  - Only vehicle cost
  - Fast to implement

PRIORITY 3: Build 3+ stop circular/chain route
  - Higher construction cost
  - But 75-100% utilization from start
  - Better long-term ROI

PRIORITY 4 (Worst): Build P2P route
  - Construction cost
  - Only 50% utilization
  - ONLY use when no alternatives exist
```

### Decision Tree for New Connections (UPDATED)

```
1. RETURN CARGO CHECK: Does B produce cargo that A (or nearby) consumes?
   YES → Plan bidirectional route (A↔B), continue to find more stops
   NO  → Continue, but flag as lower priority

2. THIRD STOP CHECK: Is there a C near B that produces/consumes compatible cargo?
   YES → Plan 3-stop route (A→B→C or A→B→C→A circular)
   NO  → Continue with A→B evaluation

3. EXISTING STATION CHECK: Are there stations within 500m of A or B?
   YES at A → Use existing station, don't build new
   YES at B → Use existing station, don't build new
   NO  → Must build new stations

4. EXISTING LINE CHECK: Is there a line with empty return trips passing near A or B?
   YES → Extend that line instead of creating new
   NO  → Create new line

5. BUILD DECISION:
   - If 3+ stops possible → Build multi-stop route (GOOD)
   - If bidirectional possible → Build bidirectional route (GOOD)
   - If only P2P possible → Build P2P (LAST RESORT, low priority)
```

### Utilization Targets

| Line Type | Expected Utilization | When to Use |
|-----------|---------------------|-------------|
| P2P (A→B) | 50% | Only when no alternatives |
| Bidirectional (A↔B) | 100% | Complementary cargo available |
| Circular (A→B→C→A) | 75-90% | Multiple nearby industries |
| Hub-and-spoke | 60-80% | Central processing plant |

### Vehicle Count Optimization

```lua
-- Calculate optimal vehicle count for a line
local function calculateOptimalVehicles(lineId)
    local line = api.engine.getComponent(lineId, api.type.ComponentType.LINE)
    local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(lineId)

    -- Get line stats (if available)
    local stats = api.engine.system.lineSystem.getLineStats(lineId)

    -- Rule of thumb:
    -- - If vehicles often waiting at stations → too many vehicles
    -- - If cargo piling up at stations → too few vehicles
    -- - Target: vehicles should rarely wait

    return {
        current = #vehicles,
        -- Adjust based on cargo waiting vs vehicle waiting
    }
end
```

---

## 12.45 Multi-Stop Route Implementation (CURRENT STATE)

### What's Implemented

Multi-stop cargo route evaluation and building has been added to the AI Builder:

**Files Modified:**
- `ai_builder_new_connections_evaluation.lua` (lines 4236-4405)
- `ai_builder_script.lua` (lines 630-651, 687-716)

### How It Works

1. **Evaluation Phase** (`evaluateMultiStopCargoRoutes`):
   - Identifies processing industries that need multiple inputs:
     - Steel Mill (needs Coal + Iron Ore)
     - Goods Factory (needs multiple inputs)
     - Machines Factory
     - Tools Factory
   - Finds source industries for each required cargo type
   - Creates multi-stop candidates: `Source1 → Source2 → Processor`
   - Scores candidates by distance, terrain, gradient, and utilization bonus
   - Uses LLM-powered selection when daemon is available

2. **Build Phase** (`buildIndustryRailConnection`):
   - Tries multi-stop routes FIRST before falling back to P2P
   - Converts multi-stop candidates to staged builds
   - Stores multi-stop info in params for later extension

3. **Extension Phase** (`connectDepotAndSetupTrainLineBetweenStations`):
   - After first leg completes, schedules building second leg
   - Second leg connects station2 to third industry
   - Result: Two connected rail lines serving the processing industry

### Example Flow

```
Auto-build triggered → buildIndustryRailConnection(nil)
    │
    ▼
evaluateMultiStopCargoRoutes() finds:
  Coal Mine → Iron Ore Mine → Steel Mill
    │
    ▼
Builds first leg: Coal Mine → Iron Ore Mine (P2P)
    │
    ▼
On completion, queues second leg: Iron Ore Mine → Steel Mill
    │
    ▼
Result: Two rail lines, both feeding Steel Mill
```

### Debug Output

Multi-stop evaluation writes debug info to:
```
/tmp/tf2_multistop_trace.txt
```

Check this file to see:
- Which processing industries were found
- What source candidates were evaluated
- Scoring details for each candidate

### Current Limitation

**Creates two separate lines, not one multi-stop line.**

This is because `lineManager.checkAndExtendFrom` only supports passenger lines currently.

**Future Enhancement:** Modify cargo line creation to support direct multi-stop line building instead of staged P2P legs.

### Testing Multi-Stop Routes

```bash
# 1. Restart game (IPC may have stopped)
./restart_tf2.sh

# 2. Enable freight trains
echo '{"command":"api.cmd.sendCommand(api.cmd.make.sendScriptEvent(\"ai_builder_script\", \"aiEnableOptions\", \"\", {aiEnableOptions = {autoEnableFreightTrains = true}}))"}' > /tmp/tf2_llm_command.json

# 3. Check debug output
tail -f /tmp/tf2_multistop_trace.txt

# 4. Watch game logs for multi-stop activity
tail -f "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt" | grep -i "multi\|staged\|leg"
```

---

## 12.5 IPC Troubleshooting Guide

### "Command not executing" - Checklist

1. **Is the game at the right speed?**
   ```bash
   python3 tf2_eval.py "return game.interface.getGameSpeed()"
   # Should return 4 for fastest execution
   # If 0 or low, run: python3 tf2_eval.py "game.interface.setGameSpeed(4)"
   # NOTE: This command WORKS even at speed 0 - just wait for it (up to 30s)
   # DO NOT ask the user to manually unpause - the IPC command will work
   ```

2. **Is the game loaded (not on main menu)?**
   ```bash
   python3 tf2_eval.py "return api.engine.getGameTime().date"
   # Should return {year=..., month=..., day=...}
   # If error, the game is on main menu or loading
   ```

3. **Check game stdout:**
   ```bash
   tail -f "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt" | grep -E "(Error|FAILED|trace)"
   ```

### "Command queued but no result"

The game polls commands every 50ms. If no result after 10 seconds:
- Game might be on main menu (not in a loaded save)
- Lua syntax error in command (check game stdout)
- Wait longer - at speed 0, commands still execute but slowly (up to 30s)

**NOTE:** Commands DO work at speed 0. Don't assume paused = broken. Just wait longer or send `setGameSpeed(4)` first.

### "Build command failed silently"

Build commands are async. Use the error monitor:
```bash
python3 monitor_tf2_errors.py --duration 30
```

Or check logs manually:
```bash
tail -100 "/Users/lincolncarlton/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt" | grep -i "error\|failed\|not possible"
```

### Common Lua Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `attempt to index nil value` | Component not found | Check entity ID exists |
| `bad argument` | Wrong type passed | Verify param types (e.g., Vec3f vs table) |
| `Construction not possible` | Terrain/collision issue | Try different position |
| `Too much curvature` | Road too curved | Use straighter route |

---

## 13. Common Workflow Patterns (Claude Agent Tested)

These patterns were tested and verified in Claude agent sessions.

### 13.1 Query Industries by Region/Name

```lua
-- Find all industries matching a name pattern (e.g., "Augusta", "Indianapolis")
local result = {}
local circle = {pos = {0, 0}, radius = math.huge}
local entities = game.interface.getEntities(circle, {type='SIM_BUILDING', includeData=true})
for id, entity in pairs(entities) do
    if entity.name and string.find(entity.name, "Augusta") then
        table.insert(result, {id=id, name=entity.name, pos=entity.position})
    end
end
-- result contains all Augusta industries with their IDs and positions
```

### 13.2 Find Stations by Name

```lua
-- Find all stations matching a name pattern
local result = {}
api.engine.forEachEntityWithComponent(function(entity)
    local name = api.engine.getComponent(entity, api.type.ComponentType.NAME)
    if name and name.name and string.find(name.name, "Indianapolis") then
        local stationGroup = api.engine.system.stationGroupSystem.getStationGroup(entity)
        table.insert(result, {id=entity, name=name.name, group=stationGroup})
    end
end, api.type.ComponentType.STATION)
```

### 13.3 Connect Industries to Existing Town Station (Two-Step Process)

**IMPORTANT:** `buildNewIndustryRoadConnection` only works between TWO INDUSTRIES. To connect industries to an existing town station:

**Step 1: Build stations at industries** (by connecting them to each other or another industry)
```lua
-- Connect industry A to industry B - this builds stations at BOTH
local result = {
    industry1 = industryA,  -- Full entity from getEntities with includeData=true
    industry2 = industryB,
    cargoType = 'CARGO_TYPE',
    distance = calculatedDistance,
    initialTargetLineRate = 100,
    edge1 = edge1 and {id = edge1} or nil,
    edge2 = edge2 and {id = edge2} or nil,
    p0 = posA,
    p1 = posB,
    isAutoBuildMode = false,
    carrier = api.type.enum.Carrier.ROAD,
    isCargo = true,
    needsNewRoute = true
}
api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
    'ai_builder_script', 'buildNewIndustryRoadConnection', '', {result = result}
))
```

**Step 2: Create lines from industry stations to town station**
```lua
-- After stations exist, create a line to the town station
local targetStationGroup = 37359  -- Town station's stationGroup
local sourceStationGroup = 53359  -- Industry station's stationGroup

local line = api.type.Line.new()

local stop1 = api.type.Line.Stop.new()
stop1.stationGroup = sourceStationGroup
stop1.station = 0
stop1.terminal = 0
stop1.loadMode = 2  -- ANY/autoload (CRITICAL for cargo)
line.stops[1] = stop1

local stop2 = api.type.Line.Stop.new()
stop2.stationGroup = targetStationGroup
stop2.station = 0
stop2.terminal = 0
stop2.loadMode = 2
line.stops[2] = stop2

line.vehicleInfo.transportModes[api.type.enum.TransportMode.TRUCK+1] = 1

local color = api.type.Vec3f.new(0.4, 0.6, 0.2)
local cmd = api.cmd.make.createLine("Industry to Town", color, api.engine.util.getPlayer(), line)
api.cmd.sendCommand(cmd, function(res, success)
    if success then
        local lineId = res.resultEntities[1]
        -- Line created, vehicles will be auto-assigned or use lineManager.buyVehicleForLine()
    end
end)
```

### 13.4 Get Station Groups from Existing Lines

When industries are already connected via lines, extract station groups:

```lua
-- Get station groups from line stops
local lineId = 32327  -- Existing line ID
local line = api.engine.getComponent(lineId, api.type.ComponentType.LINE)
if line and line.stops then
    local station1Group = line.stops[1].stationGroup  -- First stop's station group
    local station2Group = line.stops[2].stationGroup  -- Second stop's station group
end
```

### 13.5 Batch Connect Multiple Industries to One Station

Pattern for connecting all industries in a region to a single destination:

```lua
-- 1. Query all industries in region
-- 2. For each industry without a station, connect to another industry (builds stations)
-- 3. Query the new station groups from the created lines
-- 4. Create lines from each industry station to the target station
```

**Practical example:** Connecting all "Indianapolis" industries to "Indianapolis Branch":
1. Found 9 industries: Construction materials plant, Saw mill, Tools factory, Oil refinery, Farm, Chemical plant, Coal mine, Coal mine #2, Oil well
2. Connected each to Construction materials plant (which had a station) → built stations at all industries
3. Retrieved station groups from the auto-created lines
4. Created 8 new lines from each industry station to Indianapolis Branch

### 13.6 File IPC Query Pattern

For complex queries, write results to temp files:

```lua
-- In Lua command:
local json = require("json")
local f = io.open("/tmp/tf2_query_result.json", "w")
f:write(json.encode(result))
f:close()
print("[CLAUDE] Query complete")

-- Then read from bash:
-- cat /tmp/tf2_query_result.json | python3 -m json.tool
```

### 13.7 Supply Chain Compatibility Notes

When connecting industries, be aware of cargo compatibility:

| Industry Type | Produces | Consumed By |
|---------------|----------|-------------|
| Forest | LOGS | Saw mill |
| Saw mill | PLANKS | Tools factory, Construction materials plant |
| Coal mine | COAL | Steel mill, Power plant |
| Iron ore mine | IRON_ORE | Steel mill |
| Steel mill | STEEL | Tools factory, Machines factory |
| Farm | GRAIN | Food processing plant |
| Oil well | CRUDE | Oil refinery, Chemical plant |
| Oil refinery | FUEL | Towns (commercial) |
| Chemical plant | PLASTIC | Machines factory, Goods factory |

**Warning:** Connecting incompatible industries (e.g., Farm → Saw mill) will create a truck line, but cargo won't be accepted at the destination.

---

## 14. Quick Reference Cards

### Road Station Quick Build

```lua
local util = require('ai_builder_base_util')
local constructionUtil = require('ai_builder_construction_util')
local vec3 = require('vec3')

util.cacheNode2SegMaps()
local deadEnds = util.searchForDeadEndNodes(targetPos, 200)
local nodeDetails = util.getDeadEndNodeDetails(deadEnds[1].id)
local tangent = vec3.normalize(vec3.new(nodeDetails.tangent.x, nodeDetails.tangent.y, 0))
local stationPos = vec3.new(nodeDetails.nodePos.x, nodeDetails.nodePos.y, nodeDetails.nodePos.z)
    + vec3.mul(80, tangent)  -- 80m along tangent
stationPos = vec3.new(stationPos.x, stationPos.y,
    api.engine.terrain.getHeightAt(api.type.Vec2f.new(stationPos.x, stationPos.y)))
local angle = util.signedAngle(tangent, vec3.new(0,1,0))
util.clearCacheNode2SegMaps()

local construction = constructionUtil.createRoadStationConstruction(
    stationPos, -angle, {isCargo=true}, {name="Station"}, false, 1, 0, "Truck", 2)
local proposal = api.type.SimpleProposal.new()
proposal.constructionsToAdd[1] = construction
api.cmd.sendCommand(api.cmd.make.buildProposal(proposal, util.initContext(), true), callback)
-- THEN connect free node to road!
```

### Vehicle Purchase Quick Pattern

```lua
local vehicleUtil = require('ai_builder_vehicle_util')
local config = vehicleUtil.buildTruck({cargoType='COAL', distance=2000})
local apiConfig = vehicleUtil.copyConfigToApi(config)  -- MUST convert!
local cmd = api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depotEntityId, apiConfig)
api.cmd.sendCommand(cmd, function(res, success)
    if success then
        local vehicleId = res.resultVehicleEntity
        -- MUST defer line assignment!
        constructionUtil.addWork(function()
            api.cmd.sendCommand(api.cmd.make.setLine(vehicleId, lineId, 0), callback)
        end)
    end
end)
```

### Era-Appropriate Vehicles (1850s)

- `vehicle/truck/horse_cart.mdl`
- `vehicle/truck/horse_cart_universal.mdl` - **Best choice**: carries any cargo
- `vehicle/truck/horse_cart_stake_v2.mdl`
- `vehicle/truck/horsewagon_1850.mdl`

### Transport Mode Numbers (Line System)

When querying lines via `api.engine.system.lineSystem.getLines()`, the `transportMode` field uses these values:

| Mode | Type | Description | Typical Vehicles |
|------|------|-------------|------------------|
| 5 | ROAD | Road cargo (trucks) | Horse carts, trucks (17-21 per line typical) |
| 8 | RAIL | Rail (trains) | Electric/steam trains (1-3 per line typical) |
| 13 | WATER | Ships | Cargo ships (2-3 per line typical) |

**IMPORTANT:** Mode 5 is ROAD/TRUCK for cargo, NOT tram. Tram mode is for passenger trams only.

**Example: Query all lines with transport types:**
```lua
local lines = api.engine.system.lineSystem.getLines()
for _, lineId in pairs(lines) do
    local line = api.engine.getComponent(lineId, api.type.ComponentType.LINE)
    local name = api.engine.getComponent(lineId, api.type.ComponentType.NAME)
    local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(lineId)
    print(name.name, "mode:" .. line.transportMode, "vehicles:" .. #vehicles)
end
-- Output example:
-- Augusta Forest-Augusta Saw mill Log mode:5 vehicles:17
-- Independence Iron ore mine #2 Iron mode:8 vehicles:1
-- Oceanside Coal mine-Steel mill mode:13 vehicles:3
```

### Startup Sequence Reminder

1. `./restart_tf2.sh` - Restart game
2. Wait 20-30 seconds for load
3. `game.interface.setGameSpeed(4)` - **MUST unpause!**
4. Verify connection: `python tf2_eval.py "return api.engine.getGameTime().date"`
5. Set `loadMode = 2` (ANY) for all cargo line stops
6. Begin build operations

---

*Document generated for Claude AI agents working with Transport Fever 2 AI Builder mod*
