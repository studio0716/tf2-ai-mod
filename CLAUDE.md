# TF2 AI Mod - Claude Instructions

Key reminders:
- **TO RESTART THE GAME**: `./scripts/restart_tf2.sh`
- **REVIEW GAME LOGS**: `~/Library/Application Support/Steam/userdata/46041736/1066780/local/crash_dump/stdout.txt`
- The game starts PAUSED from save. Set game speed 1-4x to do anything.

## CRITICAL: Query Town Demands BEFORE Route Planning

**NOT ALL TOWNS DEMAND ALL PRODUCTS!** You MUST query actual demands first.

Use the IPC command `query_town_demands` to get actual demand data:

```
Independence (-340, 1916): FUEL:27, GOODS:25        ← Wants FUEL, GOODS only
Augusta (2976, 2268): MACHINES:32, TOOLS:37         ← Wants MACHINES, TOOLS only
Indianapolis (216, -1968): FOOD:80, CONSTRUCTION:72 ← Wants FOOD, CONSTRUCTION
Oceanside (3164, -1212): FOOD:67, CONSTRUCTION:66   ← Wants FOOD, CONSTRUCTION
```

**NEVER assume a town wants a cargo - verify `cargo_demands` first!**

---

## TF2 Supply Chain Rules - WORK BACKWARDS FROM VERIFIED DEMANDS

**Towns CAN demand: FOOD, GOODS, FUEL, TOOLS, CONSTRUCTION_MATERIALS, MACHINES**
**But NOT all towns demand all products - check cargo_demands!**

### Complete Chains (must end at town!)

**FUEL chain (4 stages):**
```
Oil well → [CRUDE_OIL] → Oil refinery → [OIL] → Fuel refinery → [FUEL] → TOWN
```

**FOOD chain (2 stages):**
```
Farm → [GRAIN] → Food processing plant → [FOOD] → TOWN
```

**CONSTRUCTION_MATERIALS chain (2 stages):**
```
Quarry → [STONE] → Construction materials plant → [CONSTRUCTION_MATERIALS] → TOWN
```

**TOOLS chain (3 stages):**
```
Forest → [LOGS] → Saw mill → [PLANKS] → Tools factory → [TOOLS] → TOWN
```

**GOODS chain (complex - needs STEEL + PLASTIC):**
```
Coal mine ──► Steel mill ──► [STEEL] ──┐
Iron ore ───►                          ├──► Goods factory → [GOODS] → TOWN
Oil well → Oil refinery → [OIL] →      │
           Chemical plant → [PLASTIC] ─┘
```

### Cargo Classification
- **RAW (from extractors):** CRUDE_OIL, COAL, IRON_ORE, STONE, GRAIN, LIVESTOCK, LOGS
- **INTERMEDIATE (between processors):** OIL, STEEL, PLANKS, PLASTIC
- **FINAL (to towns):** FUEL, FOOD, GOODS, TOOLS, CONSTRUCTION_MATERIALS, MACHINES

### Key Rules
1. CRUDE_OIL ≠ OIL! Oil well produces CRUDE, Oil refinery turns it into OIL
2. OIL is intermediate - must go to Fuel refinery (→FUEL) or Chemical plant (→PLASTIC)
3. STEEL is intermediate - must go to Machines/Goods/Tools factory
4. PLANKS is intermediate - must go to Tools/Machines factory or Construction
5. Build DAG backwards from town demand, not forwards from raw materials

---

## Route Design Rules - MINIMIZE DEADHEADING

**Point-to-point routes = 50% deadhead (empty return trips) = FAILURE**

### Vehicle Cargo Type
**NEVER buy cargo-specific vehicles!**

**Trucks:**
- ALWAYS select "ALL CARGO" type
- Allows same truck to carry GRAIN → FOOD → etc.

**Rail:**
- Rail wagons ARE cargo-specific (can't avoid this)
- Add MULTIPLE wagon types to each train for different cargos
- Example: Grain wagon + Food wagon on same train

**Ships & Planes:**
- ALL CARGO type when available

This allows ONE truck to:
1. Pick up GRAIN at Farm
2. Deliver GRAIN to Food Plant
3. Pick up FOOD at Food Plant (same truck!)
4. Deliver FOOD to Town
5. Return to Farm (only 1/4 empty, not 1/2)

### Requirements
- **Multi-stop routes with 4+ stops** minimize empty running
- **Target 70%+ vehicle utilization** or route will lose money
- **Build loops**, not point-to-point lines
- **ALL CARGO vehicles** enable true multi-cargo loops

### Strategy
1. Build initial P2P connection first (to establish infrastructure)
2. Create NEW line that combines multiple P2P segments into a loop
3. Transfer vehicles to the combined line
4. Loop should visit: Raw1 → Processor → Factory → Town → Raw2 → ...

### Example Multi-Stop Loop (TOOLS chain):
```
Forest → Saw mill → Tools factory → Town → (back to Forest)
  LOGS     PLANKS       TOOLS      deliver   (empty but short)
```

### Anti-Patterns (DON'T DO)
- Single P2P route: A → B → A (50% empty)
- Multiple isolated P2P routes (each 50% empty)
- Building intermediate chains without town delivery
- **Delivering to a town that doesn't demand the cargo**
- Assuming all towns want FOOD/GOODS/etc. without verifying cargo_demands

---

## IPC Protocol

See [IPC_PROTOCOL.md](IPC_PROTOCOL.md) for full protocol documentation.

Files:
- `/tmp/tf2_cmd.json` - Commands TO game
- `/tmp/tf2_resp.json` - Responses FROM game

**CRITICAL**: All JSON values must be strings for TF2's Lua JSON parser.

## TF2 IPC Technical Notes

- Use `os.clock()` spin-wait for delays (`os.execute`/`sleep` unavailable in sandbox)
- Add LLM injection to ALL evaluation functions (water, road, rail - game takes different code paths)

## Debugging

Check IPC log:
```bash
tail -f /tmp/tf2_simple_ipc.log
```

Check game log:
```bash
tail -f ~/Library/Application\ Support/Steam/userdata/*/1066780/local/crash_dump/stdout.txt
```

## Related Repository

**tf2-ralphy** - Python MCP server for Claude Code integration
