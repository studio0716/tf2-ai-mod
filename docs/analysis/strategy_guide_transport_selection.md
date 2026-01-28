# Strategy Guide: Transport Selection & Route Planning

## Core Principle: Minimize Deadheading

Deadheading = vehicles traveling empty. This is the #1 cause of unprofitable routes.

**Goal**: Vehicles should be LOADED in both directions on the longest legs.

## Era-Based Transport Selection

### 1850-1899 (Horse-Drawn Era)
| Transport | Max Efficient Distance | Notes |
|-----------|----------------------|-------|
| Road | 800m straight-line | Slow (0.3x speed), expensive maintenance |
| Rail | Unlimited | Preferred for all medium+ distances |
| Water | Unlimited | Best for bulk cargo if water route exists |

**Critical Rule**: For 1880s, if straight-line distance > 800m, use RAIL or WATER.

### 1900-1949 (Early Motor Era)
| Transport | Max Efficient Distance | Notes |
|-----------|----------------------|-------|
| Road | 1600m straight-line | Improving speeds (0.6x) |
| Rail | Unlimited | Still preferred for bulk |
| Water | Unlimited | Bulk shipping advantage |

### 1950+ (Modern Era)
| Transport | Max Efficient Distance | Notes |
|-----------|----------------------|-------|
| Road | 3000m straight-line | Full speed, flexible |
| Rail | Unlimited | Bulk/long-haul advantage |
| Water | Unlimited | Intercontinental |

## Distance Calculation

**Road Multiplier**: Actual road distance = straight-line * 2.0 (conservative)

```python
def should_use_rail(straight_line_dist: float, year: int) -> bool:
    """Determine if rail is required based on era and distance."""
    road_multiplier = 2.0

    if year < 1900:
        road_limit = 800  # meters
    elif year < 1950:
        road_limit = 1600
    else:
        road_limit = 3000

    return straight_line_dist > road_limit
```

## Bi-Directional Cargo Patterns

### Pattern 1: True Bi-Directional
Two industries that trade with each other:
```
Industry A produces X, consumes Y
Industry B produces Y, consumes X

A -> B: Carry X
B -> A: Carry Y
Utilization: 100%
```

**Note**: Rare in TF2 - most chains are one-directional.

### Pattern 2: Hub-and-Spoke with Return Cargo
Multiple suppliers to one processor, consumers near suppliers:
```
Coal Mine (near Iron Ore Mine) -> Steel Mill: Coal + Iron Ore
Steel Mill -> ConMats Plant (near mines): Steel
ConMats Plant -> Town (near mines): ConMats
Town -> Coal Mine area: Empty but short

Long legs loaded, short deadhead.
```

### Pattern 3: Triangle Loop
Three industries forming a geographic triangle:
```
A -> B: Cargo 1
B -> C: Cargo 2
C -> A: Empty (but short distance)

Utilization = (AB + BC) / (AB + BC + CA)
Target: > 75% utilization
```

### Pattern 4: Multi-Stop Rail Line
Rail line serving multiple industries along the route:
```
Station 1 (Coal Mine)
  -> Station 2 (Iron Ore Mine): Pick up both
  -> Station 3 (Steel Mill): Drop both, pick up Steel
  -> Station 4 (ConMats): Drop Steel, pick up ConMats
  -> Station 5 (Town): Drop ConMats
  -> Return with mixed cargo
```

## Supply Chain Analysis

### Step 1: Map All Industries
- Identify all producers and consumers
- Note geographic locations

### Step 2: Find Cargo Clusters
Look for areas where:
- Multiple raw material producers are near each other
- Processors are within rail distance
- Final goods consumers (towns) are near raw material areas

### Step 3: Calculate Bi-Directional Potential
For each potential route:
1. What cargo goes forward?
2. What cargo can go backward?
3. What's the loaded vs total distance?

### Step 4: Prioritize High Utilization
Build routes in order of utilization:
1. 100% bi-directional (if any exist)
2. >85% triangle loops
3. >75% hub-and-spoke
4. Last resort: point-to-point (only if VERY short road)

## Multi-Cargo Vehicles

### Trains
Can have multiple wagon types:
- Gondolas (bulk: coal, ore, stone)
- Flatcars (logs, planks, steel)
- Boxcars (goods, food)

**Strategy**: Design trains that can carry the cargo needed in BOTH directions.

### Ships
Can carry any cargo type. Ideal for:
- Bulk raw materials
- Long coastal routes
- Bi-directional port-to-port trade

### Trucks
Single cargo type but flexible routing.
Use for:
- Short last-mile delivery
- Roads only when distance < era limit

## Implementation Checklist

Before building ANY route:

1. [ ] Check year and determine transport type limits
2. [ ] Calculate straight-line distance
3. [ ] Apply road multiplier (x2.0) for actual road distance
4. [ ] If > era limit: MUST use rail or water
5. [ ] Identify cargo in FORWARD direction
6. [ ] Identify cargo in BACKWARD direction (or nearby pickup)
7. [ ] Calculate utilization: loaded_distance / total_distance
8. [ ] Only build if utilization > 75% OR distance < 500m

## Common Mistakes to Avoid

1. **Building long road routes in 1880s** - Horse-drawn is too slow
2. **Point-to-point single cargo** - 50% deadheading guaranteed
3. **Ignoring return cargo** - Always ask "what goes back?"
4. **Using straight-line for road planning** - Roads are ~2x longer
5. **Building before analyzing** - Plan the full chain first

## Tags
#strategy #transport-selection #bi-directional #deadheading #utilization
