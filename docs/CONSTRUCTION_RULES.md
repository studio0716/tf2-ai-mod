# Transport Fever 2 - AI Construction Rules & Methods

This document captures the learned rules and patterns for programmatically constructing infrastructure in TF2 using the AI Builder mod's utilities.

## Game Management

### Restart Script
To restart the game and reload the last save:
```bash
python3 restart_tf2.py
```

This script (`/Users/lincolncarlton/Dev/tf2-ai-optimizer/restart_tf2.py`):
1. Force quits TF2 if running
2. Launches TF2 via Steam
3. Waits for main menu (15s)
4. Clicks "Continue" button at coordinates (782, 528)
5. Waits for game to load (18s)

**Use this when:** You need to reset the game state, reload a save, or recover from errors.

---

## Core Architecture

### File-Based IPC
- **Commands**: `/tmp/tf2_ai_commands.json` - JSON with `{action, params}` structure
- **Results**: `/tmp/tf2_ai_result.json` - Command execution results
- **State**: `/tmp/tf2_ai_state.json` - Periodic game state export

### Key Dependencies
```lua
local util = require('ai_builder_base_util')
local constructionUtil = require('ai_builder_construction_util')
local vec3 = require('vec3')
```

---

## Road Depots

### Placement Rules
1. **Distance from road**: 40-60m perpendicular offset from road node
2. **Orientation**: Entrance must face toward the road
3. **Road type**: Works best with dead-end nodes, but mid-road nodes work too
4. **Connection**: Must build connecting road after depot construction

### Construction Pattern
```lua
util.cacheNode2SegMaps()

-- Find road node and calculate position
local roadNode = <node_id>
local roadNodePos = util.nodePos(roadNode)
local segments = util.getSegmentsForNode(roadNode)
local edgeId = segments[1]
local baseEdge = api.engine.getComponent(edgeId, api.type.ComponentType.BASE_EDGE)

-- Get tangent direction
local tangent
if baseEdge.node0 == roadNode then
  tangent = vec3.new(baseEdge.tangent0.x, baseEdge.tangent0.y, baseEdge.tangent0.z or 0)
else
  tangent = vec3.new(baseEdge.tangent1.x, baseEdge.tangent1.y, baseEdge.tangent1.z or 0)
end
tangent = vec3.normalize(tangent)

-- Place perpendicular to road
local perpTangent = util.rotateXY(tangent, math.rad(90))
local offset = 60  -- meters
local depotPos = roadNodePos + offset * perpTangent

-- Calculate angle
local baseTangent = vec3.new(0, 1, 0)
local angle = util.signedAngle(perpTangent, baseTangent)

-- Create depot
local naming = {name = 'DepotName'}  -- REQUIRED: table with .name field
local depotConstruction = constructionUtil.createRoadDepotConstruction(naming, depotPos, -angle)

-- Build depot
local newProposal = api.type.SimpleProposal.new()
newProposal.constructionsToAdd[1] = depotConstruction
api.cmd.sendCommand(api.cmd.make.buildProposal(newProposal, util.initContext(), true), function(res, success)
  if success then
    -- CRITICAL: Connect in deferred callback
    constructionUtil.addWork(function()
      util.cacheNode2SegMaps()
      local entity = util.buildConnectingRoadToNearestNode(roadNode, -1, true)
      util.clearCacheNode2SegMaps()
      if entity then
        local newProposal2 = api.type.SimpleProposal.new()
        newProposal2.streetProposal.edgesToAdd[1] = entity
        api.cmd.sendCommand(api.cmd.make.buildProposal(newProposal2, util.initContext(), true), callback)
      end
    end)
  end
end)

util.clearCacheNode2SegMaps()
```

### Function Signature
```lua
constructionUtil.createRoadDepotConstruction(naming, position, angle)
-- naming: table with {name = "string"} - used for depot name
-- position: Vec3f position
-- angle: rotation in radians
```

---

## Truck/Cargo Stations

### Placement Rules
1. **Distance from road**: 80m+ offset (MORE than depots!)
2. **Orientation**: ALONG road tangent, NOT perpendicular
3. **Curvature**: Perpendicular placement causes "Too much curvature" error
4. **Connection**: Longer connecting roads work better

### Critical Differences from Depots
| Aspect | Depot | Station |
|--------|-------|---------|
| Offset distance | 40-60m | 80m+ |
| Orientation | Perpendicular to road | Along road tangent |
| Placement direction | Use perpTangent | Use tangent directly |

### Construction Pattern
```lua
util.cacheNode2SegMaps()

local roadNode = <node_id>
local roadNodePos = util.nodePos(roadNode)
local nodeDetails = util.getDeadEndNodeDetails(roadNode)  -- For dead-end nodes
local tangent = vec3.normalize(nodeDetails.tangent)

-- KEY DIFFERENCE: Place ALONG tangent, not perpendicular
local baseTangent = vec3.new(0, 1, 0)
local offset = 80  -- KEY: 80m for stations, not 40-50m
local stationPos = roadNodePos + offset * tangent  -- Along tangent!

local angle = util.signedAngle(tangent, baseTangent)
local params = {isCargo = true}
local naming = {name = 'StationName'}

-- Create station
local newConstruction = constructionUtil.createRoadStationConstruction(
  stationPos,
  -angle,
  params,
  naming,
  false,  -- isRight
  1,      -- platL (platforms left)
  0,      -- platR (platforms right)
  'Truck',
  2       -- terminalCount
)

-- Build and connect (same pattern as depot)
local newProposal = api.type.SimpleProposal.new()
newProposal.constructionsToAdd[1] = newConstruction
api.cmd.sendCommand(api.cmd.make.buildProposal(newProposal, util.initContext(), true), function(res, success)
  if success then
    constructionUtil.addWork(function()
      util.cacheNode2SegMaps()
      local entity = util.buildConnectingRoadToNearestNode(roadNode, -1, true)
      util.clearCacheNode2SegMaps()
      if entity then
        local newProposal2 = api.type.SimpleProposal.new()
        newProposal2.streetProposal.edgesToAdd[1] = entity
        api.cmd.sendCommand(api.cmd.make.buildProposal(newProposal2, util.initContext(), true), callback)
      end
    end)
  end
end)

util.clearCacheNode2SegMaps()
```

### Function Signature
```lua
constructionUtil.createRoadStationConstruction(position, angle, params, naming, isRight, platL, platR, vehicleType, terminalCount)
-- position: Vec3f
-- angle: radians
-- params: {isCargo = true/false}
-- naming: {name = "string"}
-- isRight: boolean
-- platL: platforms on left (integer)
-- platR: platforms on right (integer)
-- vehicleType: "Truck" or "Bus"
-- terminalCount: number of terminals
```

---

## Lines

### Creation Pattern
```lua
local line = api.type.Line.new()

-- Add stops (use station IDs, system finds station groups)
for i, stationId in ipairs(stationIds) do
  local stop = api.type.Line.Stop.new()

  -- Get station group from station
  local stationGroup = api.engine.system.stationGroupSystem.getStationGroup(stationId)
  stop.stationGroup = stationGroup
  stop.station = 0  -- First station in group
  stop.terminal = 0  -- First terminal
  line.stops[#line.stops + 1] = stop
end

-- Set transport mode
local transportModes = line.vehicleInfo.transportModes
transportModes[api.type.enum.TransportMode.TRUCK] = 1  -- For cargo trucks
-- Other modes: BUS, TRAM, TRAIN

-- Create line
local color = api.type.Vec3f.new(0.2, 0.2, 0.8)  -- RGB
local cmd = api.cmd.make.createLine("Line Name", color, api.engine.util.getPlayer(), line)
api.cmd.sendCommand(cmd, callback)
```

### Important Notes
- Station ID and Station Group ID are DIFFERENT entities
- Always use `stationGroupSystem.getStationGroup(stationId)` to get the correct group
- Line requires at least 2 stops

---

## Vehicles

### Buying Vehicles
```lua
-- CRITICAL: Need VEHICLE_DEPOT entity, not CONSTRUCTION entity
local vehicleDepotEntity = nil
api.engine.system.vehicleDepotSystem.forEach(function(vdEntity)
  vehicleDepotEntity = vdEntity
end)

-- Find model by name
local modelId = nil
local models = api.res.modelRep.getAll()
for i, name in pairs(models) do
  if string.find(name:lower(), "horse_cart_universal") then
    local model = api.res.modelRep.get(i)
    if model and model.metadata and model.metadata.transportVehicle then
      modelId = i
      break
    end
  end
end

-- Create vehicle config
local vehicleConfig = api.type.TransportVehicleConfig.new()
local tvPart = api.type.TransportVehiclePart.new()
tvPart.part.modelId = modelId
tvPart.part.loadConfig = {0}
tvPart.autoLoadConfig = {1}
tvPart.purchaseTime = api.engine.getComponent(
  api.engine.util.getWorld(),
  api.type.ComponentType.GAME_TIME
).gameTime
vehicleConfig.vehicles[1] = tvPart

-- Buy vehicle
local cmd = api.cmd.make.buyVehicle(api.engine.util.getPlayer(), vehicleDepotEntity, vehicleConfig)
api.cmd.sendCommand(cmd, function(res, success)
  if success then
    local vehicleId = res.resultVehicleEntity
    -- Assign to line (MUST be deferred!)
    constructionUtil.addWork(function()
      constructionUtil.addWork(function()
        local assignCmd = api.cmd.make.setLine(vehicleId, lineId, 0)
        api.cmd.sendCommand(assignCmd, callback)
      end)
    end)
  end
end)
```

### Era-Appropriate Vehicles (1850s)
- `vehicle/truck/horse_cart.mdl`
- `vehicle/truck/horse_cart_universal.mdl` - Can carry any cargo
- `vehicle/truck/horse_cart_stake_v2.mdl`
- `vehicle/truck/horsewagon_1850.mdl`

### Vehicle Types by Cargo
- **Universal**: Any cargo type
- **Tipper**: Bulk cargo (coal, ore, stone)
- **Tanker**: Liquids (oil, fuel)
- **Stake**: Logs, lumber, long goods

---

## Finding Road Nodes

### Dead-End Nodes (Best for Placement)
```lua
util.cacheNode2SegMaps()
local deadEnds = util.searchForDeadEndNodes(position, radius)
-- Returns nodes with only 1 connected segment
util.clearCacheNode2SegMaps()
```

### All Nodes in Range
```lua
local nodeMap = api.engine.system.streetSystem.getNode2SegmentMap()
for nodeId, segments in pairs(nodeMap) do
  local nodeComp = api.engine.getComponent(nodeId, api.type.ComponentType.BASE_NODE)
  local pos = nodeComp.position
  local segCount = segments:size()
  -- segCount == 1: dead-end
  -- segCount == 2: mid-road
  -- segCount > 2: intersection
end
```

### Getting Node Details
```lua
local nodeDetails = util.getDeadEndNodeDetails(nodeId)
-- Returns: {position, tangent}
```

---

## Connection Verification

### Check if Construction is Connected
```lua
local freeNodes = util.getFreeNodesForConstruction(constructionId)
for i, nodeId in pairs(freeNodes) do
  local segs = util.getSegmentsForNode(nodeId)
  local numSegs = #segs
  -- numSegs == 1: Only internal edge (NOT connected)
  -- numSegs > 1: Connected to road network
end
```

---

## Critical Patterns

### Deferred Execution
Always use `constructionUtil.addWork()` for operations after construction:
```lua
api.cmd.sendCommand(buildCommand, function(res, success)
  if success then
    constructionUtil.addWork(function()
      -- This runs on next tick after construction settles
      -- Safe to connect roads, assign vehicles, etc.
    end)
  end
end)
```

### Cache Management
Always bracket node operations with cache calls:
```lua
util.cacheNode2SegMaps()
-- ... node operations ...
util.clearCacheNode2SegMaps()
```

### Context Initialization
```lua
local context = util.initContext()  -- or api.type.Context:new()
```

---

## Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "Too much curvature" | Station perpendicular to road | Place station ALONG tangent |
| "Construction not possible" | Connecting road too short | Increase offset (80m+ for stations) |
| Connection fails silently | Race condition | Use `addWork()` for deferred execution |
| Vehicle assignment crash | Called setLine immediately | Double-defer with `addWork()` |
| "attempt to index 'naming'" | Wrong function signature | Pass `{name="string"}` table |

---

## Distance Guidelines

### From Industry to Station
- **Ideal**: 100-150m (within catchment area)
- **Maximum**: ~200m (may be outside catchment)

### From Road to Construction
- **Depots**: 40-60m perpendicular
- **Stations**: 80m+ along tangent

### Search Radius for Road Nodes
- Use 200-300m radius to find suitable placement nodes

---

## WORKING Example: Complete Truck Line Setup

This is the verified working sequence to build a complete truck line with vehicle assignment:

### Step 1: Build Depot (using bridge command)
```json
{
  "action": "buildDepot",
  "params": {
    "position": {"x": 539, "y": 1696, "z": 18},
    "depotType": "road",
    "searchRadius": 300
  }
}
```
The bridge's `buildDepot` command handles road connections automatically.
**Result:** Returns `vehicleDepotId` - save this for buying vehicles.

### Step 2: Build Connected Stations (using eval with AI Builder)
```json
{
  "action": "eval",
  "params": {
    "code": "local util = require('ai_builder_base_util')\nlocal constructionUtil = require('ai_builder_construction_util')\nlocal vec3 = require('vec3')\n\nutil.cacheNode2SegMaps()\nlocal deadEnds = util.searchForDeadEndNodes({X, Y, Z}, 300, true)\nlocal roadNode = deadEnds[1]\nlocal nodeDetails = util.getDeadEndNodeDetails(roadNode)\nlocal roadNodePos = vec3.new(nodeDetails.nodePos.x, nodeDetails.nodePos.y, nodeDetails.nodePos.z)\nlocal tangent = vec3.normalize(vec3.new(nodeDetails.tangent.x, nodeDetails.tangent.y, nodeDetails.tangent.z or 0))\n\nlocal offset = 80\nlocal stationPos = roadNodePos + vec3.mul(offset, tangent)\nlocal baseTangent = vec3.new(0, 1, 0)\nlocal angle = util.signedAngle(tangent, baseTangent)\n\nlocal params = {isCargo = true}\nlocal naming = {name = 'Station Name'}\n\nlocal newConstruction = constructionUtil.createRoadStationConstruction(\n  stationPos, -angle, params, naming, false, 1, 0, 'Truck', 2\n)\n\nlocal newProposal = api.type.SimpleProposal.new()\nnewProposal.constructionsToAdd[1] = newConstruction\n\napi.cmd.sendCommand(api.cmd.make.buildProposal(newProposal, util.initContext(), true), function(res, success)\n  if success then\n    constructionUtil.addWork(function()\n      util.cacheNode2SegMaps()\n      local entity = util.buildConnectingRoadToNearestNode(roadNode, -1, true)\n      util.clearCacheNode2SegMaps()\n      if entity then\n        local newProposal2 = api.type.SimpleProposal.new()\n        newProposal2.streetProposal.edgesToAdd[1] = entity\n        api.cmd.sendCommand(api.cmd.make.buildProposal(newProposal2, util.initContext(), true), function(res2, success2)\n          -- Station built and connected!\n        end)\n      end\n    end)\n  end\nend)\n\nutil.clearCacheNode2SegMaps()\nreturn 'Station initiated'"
  }
}
```

**Key Details:**
- `nodeDetails.nodePos.x/y/z` - Use `.x/.y/.z` format (NOT array indices)
- `nodeDetails.tangent.x/y/z` - Same format
- `util.searchForDeadEndNodes({X, Y, Z}, radius, true)` - Position is array format
- The deferred road connection (`constructionUtil.addWork`) is CRITICAL

### Step 3: Get Station IDs
```json
{
  "action": "getStations",
  "params": {}
}
```
Returns station IDs and their `stationGroup` values (often same number).

### Step 4: Create Line
```json
{
  "action": "createLine",
  "params": {
    "stations": [24922, 24921],
    "name": "Coal to Steel",
    "carrier": "ROAD",
    "color": [0.6, 0.3, 0.1]
  }
}
```
**Result:** Returns `lineId`.

### Step 5: Buy Vehicle and Assign to Line
```json
{
  "action": "buyVehicle",
  "params": {
    "depotId": 24914,
    "modelName": "horse_cart_universal",
    "lineId": 24159,
    "carrier": "ROAD"
  }
}
```
**CRITICAL:** Use the `vehicleDepotId` from step 1, NOT the construction entity ID.
**Result:** `assignedToLine: true` means success!

### Why Vehicle Assignment Fails
If `assignedToLine: false`:
1. **Depot not connected** - Use bridge's `buildDepot` command which auto-connects
2. **Stations not connected** - Must use the deferred `buildConnectingRoadToNearestNode` pattern
3. **No path exists** - Vehicle can't pathfind from depot to station stops

### Verified Working Pattern
1. `buildDepot` (bridge command) → auto-connects, returns `vehicleDepotId`
2. Build stations via `eval` with AI Builder's full pattern including deferred road connection
3. `getStations` → get station IDs
4. `createLine` with station IDs → get `lineId`
5. `buyVehicle` with `vehicleDepotId` and `lineId` → vehicle assigned!

---

## Train Stations

### Construction Pattern
Train stations use `station/rail/modular_station/modular_station.con` with auto-generated modules.

```lua
local helper = require('ai_builder_station_template_helper')
local util = require('ai_builder_base_util')
local transf = require('transf')

-- Station position
local stationX, stationY = 700, 1700
local stationZ = api.engine.terrain.getHeightAt(api.type.Vec2f.new(stationX, stationY))
local rotation = 0  -- radians

-- Station params
local stationParams = {
  catenary = 0,        -- 0 = no electric, 1 = electric
  length = 1,          -- platform length parameter
  paramX = 0,
  paramY = 0,
  seed = 0,
  templateIndex = 7,   -- Station type (see below)
  trackType = 0,       -- 0 = standard, 1 = high speed
  tracks = 0,          -- 0 = single, 1 = double, etc.
  year = 1850
}

-- Generate modules using helper
local moduleBasics = helper.createTemplateFn(stationParams)
stationParams.modules = util.setupModuleDetailsForTemplate(moduleBasics)

-- Create construction
local newConstruction = api.type.SimpleProposal.ConstructionEntity.new()
newConstruction.fileName = 'station/rail/modular_station/modular_station.con'
newConstruction.playerEntity = api.engine.util.getPlayer()
newConstruction.params = stationParams
newConstruction.name = 'Station Name'

-- Transform matrix
local stationtransf = transf.rotZTransl(rotation, api.type.Vec3f.new(stationX, stationY, stationZ))
newConstruction.transf = util.transf2Mat4f(stationtransf)

-- Build
local newProposal = api.type.SimpleProposal.new()
newProposal.constructionsToAdd[1] = newConstruction
api.cmd.sendCommand(api.cmd.make.buildProposal(newProposal, util.initContext(), true), callback)
```

### Template Index Values
| Value | Type | Description |
|-------|------|-------------|
| 1 | Passenger | Terminus station |
| 2 | Passenger | Through station |
| 6 | Cargo | Through station |
| 7 | Cargo | Terminus station |

**Terminus** = trains enter and exit from the same end
**Through** = trains pass through (enter one end, exit other)

### Track Count (`tracks` param)
- `0` = 1 track
- `1` = 2 tracks
- `2` = 3 tracks, etc.

### Module Generation
The helper generates appropriate modules based on params:
- Main building (cargo or era-appropriate passenger)
- Platform segments (cargo or passenger)
- Track modules (with/without catenary)
- Roofs and underpasses (passenger only)

### Key Dependencies
```lua
local helper = require('ai_builder_station_template_helper')
local util = require('ai_builder_base_util')
local transf = require('transf')
```

### Transform Helper
```lua
util.transf2Mat4f(transf.rotZTransl(rotation, api.type.Vec3f.new(x, y, z)))
```
Converts rotation (radians) and position to the Mat4f format required by the game.

### Finding Station Track Exit Nodes
Terminus stations have dead-end track nodes where trains enter/exit:
```lua
local function findDeadEndTrackNode(constructionId)
  local construction = api.engine.getComponent(constructionId, api.type.ComponentType.CONSTRUCTION)
  if not construction then return nil end

  local nodeConnections = {}
  for i, edgeId in pairs(construction.frozenEdges) do
    local edge = api.engine.getComponent(edgeId, api.type.ComponentType.BASE_EDGE)
    if edge then
      nodeConnections[edge.node0] = (nodeConnections[edge.node0] or 0) + 1
      nodeConnections[edge.node1] = (nodeConnections[edge.node1] or 0) + 1
    end
  end

  local deadEnds = {}
  for nodeId, count in pairs(nodeConnections) do
    if count == 1 then  -- Only 1 edge = dead end
      local nodeComp = api.engine.getComponent(nodeId, api.type.ComponentType.BASE_NODE)
      if nodeComp then
        table.insert(deadEnds, {id = nodeId, pos = nodeComp.position})
      end
    end
  end
  return deadEnds
end
```

---

## Rail Track Building

**Status: Complex - Requires manual intervention or AI Builder route builder**

Building rail track is significantly more complex than road stations/depots because:
1. Track must follow terrain contours
2. Maximum gradient constraints (typically 2-4%)
3. Bridge/tunnel decisions for terrain obstacles
4. Proper curve radii for train speeds
5. Long distances require intermediate waypoints

### Basic Track Segment (Short distances only)
```lua
local entity = api.type.SegmentAndEntity.new()
entity.type = 1  -- Track type
entity.comp.node0 = startNodeId
entity.comp.node1 = endNodeId
entity.trackEdge.trackType = api.res.trackTypeRep.find("standard.lua")
-- Set tangents...
testProposal.streetProposal.edgesToAdd[1] = entity
```

### AI Builder Route Builder
For complex routes, use AI Builder's route building:
```lua
local routeBuilder = require('ai_builder_route_builder')
local proposalUtil = require('ai_builder_proposal_util')
-- This module handles pathfinding, terrain, bridges, tunnels
```

**Note:** The AI Builder's route building is designed for automated network construction and requires significant integration. For MVP, consider building track manually in-game.

### WORKING Track Building Pattern (Discovered Dec 2024)

The `buildTrackRoute` command creates NEW nodes at waypoint positions - it does NOT snap to existing construction (frozen) nodes. To connect track to stations/depots:

1. **Build track ending 5-10m away from construction nodes**
```json
{"action": "buildTrackRoute", "params": {
  "waypoints": [
    {"x": 360, "y": 1615, "z": 19.5},  // 5m from depot exit
    {"x": 360, "y": 1590, "z": 19.7},
    {"x": 360, "y": 1565, "z": 19.9}   // 5m from station node
  ],
  "trackType": "standard.lua"
}}
```

2. **Connect gaps with direct edge building**
```lua
local vec3 = require("vec3")
local util = require("ai_builder_base_util")
local proposal = api.type.SimpleProposal.new()
local trackTypeId = api.res.trackTypeRep.find("standard.lua") or 1

local entity = api.type.SegmentAndEntity.new()
entity.entity = -1
entity.type = 1
entity.trackEdge.trackType = trackTypeId
entity.comp.node0 = depotExitNodeId    -- Frozen node
entity.comp.node1 = trackStartNodeId   -- New track node

-- Calculate tangent
local t = vec3.new(0, -1, 0)  -- Direction from node0 to node1
local len = util.calculateTangentLength(pos0, pos1, t, t)
t = len * vec3.normalize(t)
util.setTangent(entity.comp.tangent0, t)
util.setTangent(entity.comp.tangent1, t)

proposal.streetProposal.edgesToAdd[1] = entity
local cmd = api.cmd.make.buildProposal(proposal, util.initContext(), true)
```

This pattern works because:
- The 5-10m gap allows buildTrackRoute to create independent nodes
- Direct edge building CAN connect to frozen nodes when done one edge at a time
- Tangent direction must be correct (pointing from node0 toward node1)

### Train Depot Orientation

Train depots have fixed exit direction:
- **Exit is always ~40m south of depot center** (at rotation=0)
- To have depot exit point north toward a station, place depot north of station
- Station tracks at rotation=0 run north-south (y-axis)

Example: Station at (360, 1560) → Place depot at (360, 1660) so exit is at (360, 1620)

### Track Alignment with Stations

**CRITICAL**: Tracks approaching a station MUST align with the station's track direction.

- Station with rotation=0 has tracks running north-south
- Main line track at an angle (e.g., 45° diagonal) will NOT connect to station
- Solution: End main line ~400m from station, then build curved approach track
- The curved track must transition from main line direction to station track direction

### Train Station Parameters

The `buildTrainStation` command uses boolean flags, NOT templateIndex directly:
```json
{"action": "buildTrainStation", "params": {
  "position": {"x": 350, "y": 1500, "z": 20},
  "rotation": 0,
  "name": "Station Name",
  "cargo": true,       // true=cargo, false=passenger
  "terminus": false,   // true=terminus, false=through
  "length": 1,
  "tracks": 0          // 0=1 track, 1=2 tracks
}}
```

---

## Entity ID Types

Understanding the different entity types is crucial:

| Entity Type | Component | Use Case |
|-------------|-----------|----------|
| Construction | CONSTRUCTION | Building/removing structures |
| Station | STATION | Line stops |
| Station Group | STATION_GROUP | Line stop assignment |
| Vehicle Depot | VEHICLE_DEPOT | Buying vehicles |
| Vehicle | TRANSPORT_VEHICLE | Line assignment |

### Finding Correct Entity
```lua
-- Station -> Station Group
local stationGroup = api.engine.system.stationGroupSystem.getStationGroup(stationId)

-- Construction -> Vehicle Depot (iterate all depots)
api.engine.system.vehicleDepotSystem.forEach(function(vdEntity)
  -- vdEntity is VEHICLE_DEPOT, not CONSTRUCTION
end)
```
