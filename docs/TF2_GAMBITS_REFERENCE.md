# Transport Fever 2: Early-Game Supply Chain Gambits

## Quick Reference for Planning Agents

---

## Core Mechanics Summary

### Revenue Formula
- **Distance**: Paid for straight-line (crow-flies) distance, NOT actual route length
- **Speed**: Faster delivery = higher payment (10km/h earns 1/3 of 30km/h)
- **Implication**: Winding routes waste time and reduce profit

### Production Ratios
| Chain | Ratio | Notes |
|-------|-------|-------|
| Stone → ConMat | 1:1 | **UNIQUE** - Easiest chain |
| Grain → Food | 2:1 | |
| Logs → Planks | 2:1 | |
| Crude → Oil | 2:1 | |
| Oil → Fuel | 1:1 | |
| Planks → Tools | 1:1 | |
| Coal+Iron → Steel | 2+2:1 | |

### Key Insight: Demand-Driven System
Factories only produce if there's demand for output. **You don't need to complete chains to profit.**

---

## The Golden Routes (Highest Priority)

### 1. Fuel Chain (Tank Car Route)
```
Crude Oil → Oil Refinery → Fuel Processor → City Industrial
     [tank car]    [tank car]      [tank car]
```

**Optimal Setup**: Find 2 oil wells + refinery + fuel plant + town in line
**Route**: Well A → Refinery → Well B → Refinery → Fuel Plant → Town → Well A
**Efficiency**: 4 of 6 legs loaded
**Note**: Takes ~5 years to become highly profitable

**Geographic Tip**: Oil industry next to river = "won the lottery"

### 2. Tools Chain (Stake Car Route)
```
Logs → Sawmill → Tool Factory → City Commercial
  [stake car]  [stake car]
```

**Optimal Setup**: Forest far from sawmill, tool factory and town between
**Key**: Logs and planks use same wagon type

---

## Era-Specific Gambits

### 1850 Era

#### Transport Priority Order
1. **Cargo Ships** (if water available)
   - Zoroaster: 90 capacity, any cargo
   - No infrastructure cost for waterways
   - Lowest maintenance

2. **Horse Carts**
   - Routes under 15-20 minutes only
   - Short distances profitable

3. **Early Trains**
   - Only for gentle gradients
   - AVOID HILLS at all costs

#### 1850 Gambits

**GAMBIT: Ship Start**
```
Prerequisites: Map with water access to industries
1. Find coastal oil wells + refinery on water
2. Build two small harbors
3. Purchase Zoroaster (90 capacity)
4. Run crude outbound, oil return
5. Add trucks for final delivery to towns
```

**GAMBIT: Stone Loop**
```
Prerequisites: Quarry, ConMat plant, nearby town
Route: Quarry → Plant → Town → Quarry
Efficiency: Only 1/3 empty (1:1 ratio = balanced loads)
```

**GAMBIT: River Food**
```
Prerequisites: Farm + food processor both on water
1. Run 2-3 boats with grain outbound
2. Return with half-loads of food (2:1 ratio)
3. Add road service if second farm near processor
```

**GAMBIT: Cattle-Food Backhaul**
```
Cattle and food use SAME wagon type
Run cattle to distant processor, food back
```

#### 1850 Critical Tips
- Use CONTOURS map mode for track laying
- Avoid bridges and tunnels
- Keep trips under 20 minutes
- Add cheap passenger line to encourage growth

---

### 1900 Era

**New Capability**: First trucks available

**GAMBIT: Rail Trunk + Truck Feeders**
```
1. Main rail line between industrial clusters
2. Trucks gather raw materials to rail stations
3. Trucks distribute finished goods from stations
```

**Upgrade Rule**: Only at end-of-life or major improvement

---

### 1950+ Era

**GAMBIT: Hub Circle Network**
```
1. Circular main rail line touching all regions
2. Hub stations at river crossings, industry clusters
3. Trucks connect local industries to hubs
4. Inter-hub trains for long distance
5. Town-delivery trains from hubs
```

**Key**: Network self-optimizes cargo routing

---

## Geographic Strategies

### Map Selection
| Map Type | Advantages | Notes |
|----------|------------|-------|
| Tropical | Islands, coastline, water everywhere | Best for ships |
| Temperate | Rivers only | Can fake coast with climate setting |

### What to Look For
- Oil industry next to river
- Two oil wells near each other
- Industries in linear arrangements
- Towns with water access to nearby industries

### Terrain Rules
- Use CONTOURS map mode
- 10km/h uphill = 1/3 revenue of 30km/h flat
- Follow natural contours, avoid modification

---

## Multi-Transport Integration

### Hub Design Principles
1. Place near cities (dual-purpose: local + intercity)
2. Mixed consists between hubs (boxcars + gondolas + flatcars)
3. Prioritize rivers for ship-rail intermodal

### Transfer Patterns
| Pattern | Use Case |
|---------|----------|
| Ship → Train | Coastal to inland, bulk cargo |
| Train → Truck | Main line to local distribution |
| Truck → Ship → Truck | Cross-water where bridges expensive |

### Requirements
- Stations must be in catchment of each other
- All lines need active vehicles
- Catchment = road segments, not circular radius

---

## Multi-Cargo Optimization

### Automatic Refit
Leave cargo type on "Automatic" - vehicle refits at each station

### 50/50 Loading (for dual-input factories)
```
At Coal stop: Load 50%, no unload
At Iron stop: Load 50%, no unload
At Steel Mill: Unload both
```
**Tip**: Use even wagon numbers
**Warning**: Can be buggy - try 55/45 or use separate trains

### Wagon Ratio Formula
Match wagons to production ratio:
- Grain (2:1) → 2 grain wagons : 1 food wagon

---

## Common Mistakes to Avoid

| Mistake | Why Bad | Fix |
|---------|---------|-----|
| Expensive infrastructure early | Slow trains don't need it | Follow terrain |
| Parallel competing routes | Split revenue | One mode per corridor |
| Ignoring gradients | Kills profit | Use contours map |
| Too many vehicles | Congestion | Match to rate needed |
| Over-upgrading | Maintenance exceeds gains | Upgrade at end-of-life |
| Completing unnecessary chains | Wasted effort | Partial chains OK |
| Winding routes | Paid for straight-line | Keep routes direct |

---

## Troubleshooting Quick Reference

### Industry Not Producing
**Cause**: No demand for output
**Fix**: Connect downstream customers first, work backwards

### Cargo Not Loading
**Check 1**: Click station - industry should highlight white
**Check 2**: Verify vehicle assigned to line

### Line Not Profitable
1. Run cheaper/longer vehicles
2. Minimize travel time
3. Keep vehicles full most of journey
4. Check for gradient issues

### 50/50 Loading Stuck
**Try**: 55/45 split instead, or use separate trains

---

## Planning Agent Checklist

### Evaluation Order
1. Check map for water access (ship routes most profitable)
2. Identify golden route opportunities
3. Assess terrain for gradient issues
4. Find industry clusters supporting two-way loading
5. Prioritize 1:1 ratio chains for simplicity

### 1850 Hard Mode Priority
1. Scan for water routes (ship gambit)
2. If no water: stone→conmat→town
3. Establish food supply
4. Add cheap passenger line (2-3 towns)
5. Expand to fuel/tools when capital allows

### Validation Checks
- [ ] Station highlights industry white (catchment OK)
- [ ] All lines have vehicles assigned
- [ ] No parallel competing routes
- [ ] Gradients acceptable for era
- [ ] Wagon ratios match production ratios

---

## Sources

- [UnicornPoacher's TF2 Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=2810866275)
- [Expert Optimization Tips](https://steamcommunity.com/sharedfiles/filedetails/?id=2089370475)
- [Hard Mode 1850 Start Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=2099094898)
- [TF2 Wiki: Tips and Tricks](https://wiki.transportfever2.com/doku.php?id=gamemanual:tipstricks)
- [TF2 Wiki: Industries and Cargo](https://wiki.transportfever2.com/doku.php?id=gamemanual:industriescargos)
- [Hard Mode Guide (Made Easy)](https://gameplay.tips/guides/9066-transport-fever-2.html)
