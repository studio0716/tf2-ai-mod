# IPC Protocol - TF2 AI Builder

This document defines the Inter-Process Communication protocol between the TF2 Lua mod and external Python clients.

## Overview

The IPC uses simple file-based communication:

```
Python Client                                TF2 Lua Mod
     │                                            │
     │  1. Write command to /tmp/tf2_cmd.json     │
     ├───────────────────────────────────────────►│
     │                                            │
     │  2. Lua polls and reads command            │
     │                                            │
     │  3. Lua executes and writes to             │
     │     /tmp/tf2_resp.json                     │
     │◄───────────────────────────────────────────┤
     │                                            │
     │  4. Python polls and reads response        │
     │                                            │
```

## File Paths

| File | Direction | Description |
|------|-----------|-------------|
| `/tmp/tf2_cmd.json` | Python → Lua | Commands TO the game |
| `/tmp/tf2_resp.json` | Lua → Python | Responses FROM the game |
| `/tmp/tf2_simple_ipc.log` | Lua → Disk | Debug logging |

## JSON String Requirement

**CRITICAL**: TF2's Lua JSON parser has limitations. **ALL values must be strings**.

```json
// CORRECT
{"year": "1855", "money": "2500000", "paused": "false"}

// INCORRECT - will break!
{"year": 1855, "money": 2500000, "paused": false}
```

This includes:
- Numbers → `"123"`
- Booleans → `"true"` / `"false"`
- Null → `"null"`

## Command Format

```json
{
  "id": "a1b2c3d4",      // Unique request ID (8-char hex)
  "cmd": "query_game_state",  // Command name
  "ts": "1706380000000", // Timestamp in milliseconds
  "params": {            // Optional parameters (all values as strings)
    "param1": "value1"
  }
}
```

## Response Format

```json
{
  "id": "a1b2c3d4",      // Matching request ID
  "status": "ok",        // "ok" or "error"
  "data": { ... },       // Response data (on success)
  "message": "..."       // Error message (on error)
}
```

## Available Commands

### Game State

#### `ping`
Check if game is responding.

**Response:**
```json
{"id": "...", "status": "ok", "data": "pong"}
```

#### `query_game_state`
Get current game state.

**Response:**
```json
{
  "status": "ok",
  "data": {
    "year": "1855",
    "month": "3",
    "day": "15",
    "money": "2500000",
    "speed": "1",
    "paused": "false"
  }
}
```

#### `set_speed`
Set game speed.

**Params:** `{"speed": "0-4"}` (0=paused, 1-4=speed levels)

### Queries

#### `query_towns`
Get all towns.

**Response:**
```json
{
  "status": "ok",
  "data": {
    "towns": [
      {"id": "12345", "name": "Indianapolis", "population": "5000"}
    ]
  }
}
```

#### `query_town_demands`
Get all towns with their actual cargo demands.

**Response:**
```json
{
  "status": "ok",
  "data": {
    "towns": [
      {
        "id": "12345",
        "name": "Indianapolis",
        "x": "216",
        "y": "-1968",
        "population": "5000",
        "building_count": "45",
        "cargo_demands": "FOOD:80, CONSTRUCTION_MATERIALS:72"
      }
    ]
  }
}
```

#### `query_town_buildings`
Get buildings in a specific town.

**Params:** `{"town_id": "12345"}`

**Response:**
```json
{
  "status": "ok",
  "data": {
    "town_id": "12345",
    "town_name": "Indianapolis",
    "building_count": "45",
    "town_center_x": "216",
    "town_center_y": "-1968",
    "commercial_count": "12",
    "residential_count": "30",
    "cargo_demands": "FOOD, GOODS",
    "cargo_details": "FOOD:80/100; GOODS:50/80"
  }
}
```

#### `query_industries`
Get all industries.

**Response:**
```json
{
  "status": "ok",
  "data": {
    "industries": [
      {
        "id": "67890",
        "name": "Oil Well",
        "type": "oil_well",
        "x": "1234",
        "y": "5678"
      }
    ]
  }
}
```

#### `query_lines`
Get all transport lines.

**Response:**
```json
{
  "status": "ok",
  "data": {
    "lines": [
      {
        "id": "33418",
        "name": "Coal Route",
        "vehicle_count": "3",
        "stop_count": "2",
        "rate": "120",
        "frequency": "0.05",
        "interval": "20"
      }
    ]
  }
}
```

#### `query_vehicles`
Get all vehicles.

#### `query_stations`
Get all stations.

### Building

#### `build_road`
Trigger AI Builder to build best road connection.

**Params:** `{"cargo": "COAL"}` (optional cargo filter)

#### `build_industry_connection`
Build road between two specific industries.

**Params:**
```json
{
  "industry1_id": "12345",
  "industry2_id": "67890"
}
```

#### `build_cargo_to_town`
Build cargo delivery route from industry to town.

**Params:**
```json
{
  "industry_id": "12345",
  "town_id": "67890",
  "cargo": "FOOD"
}
```

### Vehicle Management

#### `add_vehicle`
Add vehicle to a line.

**Params:**
```json
{
  "line_id": "33418",
  "vehicle_type": "truck"
}
```

#### `delete_line`
Delete a transport line.

**Params:** `{"line_id": "33418"}`

#### `optimize_line_vehicles`
Optimize vehicle count on a line.

**Params:** `{"line_id": "33418"}`

### State Management

#### `snapshot_state`
Take a snapshot of current game state for later comparison.

**Response:**
```json
{
  "status": "ok",
  "data": {
    "snapshot_id": "snap_abc123"
  }
}
```

#### `diff_state`
Compare current state with a previous snapshot.

**Params:** `{"snapshot_id": "snap_abc123"}`

### Game Control

#### `pause`
Pause the game.

#### `resume`
Resume the game.

## Timing

| Parameter | Value |
|-----------|-------|
| Poll interval | 100ms |
| Default timeout | 30 seconds |
| Ping timeout | 5 seconds |

## Error Handling

Errors are returned with `status: "error"`:

```json
{
  "id": "a1b2c3d4",
  "status": "error",
  "message": "Invalid town_id parameter"
}
```

Common errors:
- `"Game interface not available"` - Game not ready
- `"Need [param] parameter"` - Missing required parameter
- `"Invalid [param]"` - Parameter validation failed

## Implementation Notes

### Python Client
- Atomic writes: Write to `.tmp` file, then `os.rename()`
- Clear stale response before sending new command
- Match response `id` to request `id`
- All values automatically stringified

### Lua Server
- Poll command file each game tick (in `guiUpdate`)
- Track `last_cmd_id` to avoid re-processing
- Clear command file after processing
- Log to `/tmp/tf2_simple_ipc.log` for debugging

## Related Files

- **Lua implementation**: `res/scripts/simple_ipc.lua`
- **Python client** (in tf2-ralphy repo): `mcp_server/internal/ipc_client.py`
