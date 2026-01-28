# Transport Fever 2 - Early Game Profit Strategy

## Bidirectional Steel Mill Train Strategy

### Overview
This strategy maximizes early game profits by creating a train line between two steel mills that carries raw materials in **both directions**, ensuring trains are always loaded.

### The Problem with Simple Routes
A typical coal → steel mill route has trains:
- **Full** going TO the steel mill (carrying coal)
- **Empty** returning FROM the steel mill

This means 50% of train capacity is wasted, and empty trains still cost money to run.

### The Solution: Bidirectional Raw Materials

Steel mills require TWO inputs:
1. **Coal** (from coal mines)
2. **Iron Ore** (from iron ore mines)

By connecting TWO steel mills with a train:
- Train carries **Coal** from Steel Mill A → Steel Mill B
- Train carries **Iron Ore** from Steel Mill B → Steel Mill A
- **100% capacity utilization in both directions**

### Implementation

```
Coal Mine ─────┐                           ┌───── Iron Ore Mine
    (truck)    │                           │    (truck)
               ▼                           ▼
        ┌─────────────┐             ┌─────────────┐
        │ Steel Mill A │◄═══════════►│ Steel Mill B │
        │             │   TRAIN      │             │
        │  Receives:  │   LINE       │  Receives:  │
        │  - Coal     │ ──────────►  │  - Iron Ore │
        │    (truck)  │   Iron Ore   │    (truck)  │
        │  - Iron Ore │              │  - Coal     │
        │    (train)  │ ◄──────────  │    (train)  │
        └─────────────┘    Coal      └─────────────┘
```

### Setup Steps

1. **Identify Two Steel Mills** within reasonable train distance (2-5km ideal)

2. **Build Train Stations** at each steel mill
   - Must be within **catchment area** (~400m) of the steel mill
   - Station should also be within catchment of where trucks will deliver

3. **Build Rail Line** connecting the two stations
   - Simple point-to-point initially
   - Can add passing loops later for more trains

4. **Set Up Truck Feeder Lines**
   - **Steel Mill A**: Truck line from nearby **Coal Mine** → Steel Mill A station
   - **Steel Mill B**: Truck line from nearby **Iron Ore Mine** → Steel Mill B station

5. **Configure Train Line**
   - Trains automatically pick up what's available at each station
   - Coal accumulates at Steel Mill A (from trucks) → Train takes to B
   - Iron Ore accumulates at Steel Mill B (from trucks) → Train takes to A

### Why This Works Financially

| Route Type | Outbound Load | Return Load | Efficiency |
|------------|---------------|-------------|------------|
| Simple (coal→steel) | Full | Empty | 50% |
| Bidirectional | Full | Full | 100% |

- **Double the revenue** per train round trip
- **Same operating costs** (fuel, maintenance, crew)
- **Faster ROI** on expensive train infrastructure

### Catchment Considerations

For this to work, each train station must be in catchment of:
1. The steel mill (to deliver raw materials)
2. The truck station (to receive raw materials from trucks)

**Ideal layout:**
```
[Coal Mine] ──truck──► [Truck Station]
                              │
                        (within 400m)
                              │
                       [Train Station] ◄──► [Rail Line]
                              │
                        (within 400m)
                              │
                       [Steel Mill]
```

### Vehicle Selection (1850s Era)

**Trucks:**
- `horse_cart_universal` - Can carry any cargo type

**Trains:**
- Early steam locomotives
- Open wagons / hopper cars for bulk cargo (coal, iron ore)

### Expansion Options

Once profitable, expand by:
1. Adding more trains to the line
2. Adding passing loops for increased frequency
3. Connecting additional coal/iron mines via truck
4. Extending to a third steel mill

### Map Requirements

This strategy requires:
- At least 2 steel mills
- At least 1 coal mine near one steel mill
- At least 1 iron ore mine near the other steel mill
- Relatively flat terrain for rail construction (or budget for bridges/tunnels)

---

## Current Map Analysis

### Steel Mills on This Map:
| Name | Position | Notes |
|------|----------|-------|
| Kington Steel mill | (539, 1696) | Lower elevation, near town |
| Kington Steel mill #2 | (-2231, 3527) | Higher elevation (101m) |

**Distance:** ~3,200m - Good for train line

### Nearby Resources:

**Near Kington Steel mill (539, 1696):**
- Kington Coal mine (1325, 3139) - 1,800m - good for truck
- Kington Coal mine #2 (-502, 923) - 1,200m - good for truck

**Near Kington Steel mill #2 (-2231, 3527):**
- Kington Iron ore mine (-3535, 3094) - 1,400m - good for truck
- Kington Iron ore mine #2 (-2259, 2107) - 1,400m - good for truck

### Recommended Setup:
1. **Steel Mill A** = Kington Steel mill (lower)
   - Receives coal via truck from Kington Coal mine
   - Receives iron ore via train from Steel Mill B

2. **Steel Mill B** = Kington Steel mill #2 (upper)
   - Receives iron ore via truck from Kington Iron ore mine
   - Receives coal via train from Steel Mill A

### Elevation Consideration
Steel Mill #2 is at 101m elevation vs Steel Mill at 18m. This 83m climb over 3.2km is about 2.6% grade - manageable for trains but may need banking curves or helper locomotives later.
