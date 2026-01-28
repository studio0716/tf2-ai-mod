# TF2 AI Mod - Transport Fever 2 AI Builder

A Transport Fever 2 mod that enables AI-powered route building and game control through file-based IPC.

## Overview

This mod integrates with external AI systems (like the tf2-ralphy MCP server) to provide intelligent transport network construction in Transport Fever 2. It exposes game state and build commands via a simple file-based IPC protocol.

## Features

- Query game state (towns, industries, lines, vehicles)
- Build road/rail connections between industries
- Deliver cargo to towns
- Vehicle management (add/remove/optimize)
- State snapshots for build verification

## Installation

### Quick Install

```bash
# From this repository's root
./scripts/install_mod.sh
```

### Manual Install

1. Copy the entire contents to your TF2 mods folder:
   - macOS: `~/Library/Application Support/Transport Fever 2/mods/ai_builder_1/`
   - Linux: `~/.local/share/Transport Fever 2/mods/ai_builder_1/`
   - Windows: `%APPDATA%\Transport Fever 2\mods\ai_builder_1\`

2. Enable the mod in TF2's mod manager

### Verify Installation

1. Start Transport Fever 2
2. Check the game log for: `SimpleIPC initialized`
3. Test with: `echo '{"id":"test","cmd":"ping","ts":"0"}' > /tmp/tf2_cmd.json`
4. Check response: `cat /tmp/tf2_resp.json` should show `"pong"`

## Restarting the Game

Use the provided script to restart TF2 (macOS):

```bash
./scripts/restart_tf2.sh
```

## IPC Protocol

The mod communicates via two JSON files:

| File | Direction | Description |
|------|-----------|-------------|
| `/tmp/tf2_cmd.json` | External → Game | Commands to execute |
| `/tmp/tf2_resp.json` | Game → External | Command responses |

See [IPC_PROTOCOL.md](IPC_PROTOCOL.md) for full protocol documentation.

### Example: Query Game State

```bash
# Send command
echo '{"id":"abc123","cmd":"query_game_state","ts":"0"}' > /tmp/tf2_cmd.json

# Read response (after game processes it)
cat /tmp/tf2_resp.json
# {"id":"abc123","status":"ok","data":{"year":"1855","money":"2500000",...}}
```

### Important: JSON String Values

TF2's Lua JSON parser requires **all values to be strings**:

```json
// CORRECT
{"year": "1855", "money": "2500000", "paused": "false"}

// INCORRECT - will break!
{"year": 1855, "money": 2500000, "paused": false}
```

## Project Structure

```
tf2-ai-mod/
├── mod.lua                 # Mod manifest
├── res/
│   ├── scripts/            # Lua implementation
│   │   ├── simple_ipc.lua  # IPC server
│   │   ├── ai_builder_*.lua # AI builder logic
│   │   └── ...
│   ├── config/             # Game config overrides
│   ├── construction/       # Construction definitions
│   └── textures/           # UI textures
├── scripts/
│   ├── install_mod.sh      # Install to TF2
│   └── restart_tf2.sh      # Restart game (macOS)
├── docs/                   # Documentation
├── IPC_PROTOCOL.md         # IPC specification
└── CLAUDE.md               # AI assistant instructions
```

## Debugging

### Check IPC Log

```bash
tail -f /tmp/tf2_simple_ipc.log
```

### Check Game Log (macOS)

```bash
tail -f ~/Library/Application\ Support/Steam/userdata/*/1066780/local/crash_dump/stdout.txt
```

## Supply Chain Reference

The mod includes documentation on TF2 supply chains in `CLAUDE.md`. Key points:

- Towns demand specific cargo types (not all towns want all products)
- Use `query_town_demands` to check actual demands before routing
- Build chains backwards from verified town demands

## Related Repository

- **tf2-ralphy** - Python MCP server that provides Claude Code integration

## License

MIT
