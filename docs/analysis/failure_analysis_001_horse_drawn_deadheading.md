# Failure Analysis #001: Horse-Drawn Deadheading

## Hypothesis
Building point-to-point road routes between industries would be profitable in 1880.

## Test Conditions
- **Year**: 1880
- **Starting Capital**: $10,000,000
- **Transport Type**: Road (horse-drawn carriages)
- **Route Pattern**: Single-direction point-to-point

## Routes Built
1. Coal Mine -> Steel Mill (~1800m straight-line)
2. Iron Ore Mine -> Steel Mill (~1800m straight-line)
3. Various other single-direction routes

## Results
- **Vehicles deployed**: 80+
- **Money trajectory**: $10M -> $2M -> $109K -> $16K (bankruptcy)
- **Time elapsed**: ~1 year in-game

## Root Cause Analysis

### Issue 1: Actual Road Distance >> Straight-Line Distance
- Straight-line distance: ~1800m
- Actual road route length: ~2888m (from debug logs)
- **Multiplier**: ~1.6x to 2.5x
- **Impact**: Routes that appeared within efficiency limits were actually far beyond

### Issue 2: Horse-Drawn Speed in 1880
- Era: 1880 = horse-drawn carriages
- Speed factor: 0.3x compared to modern trucks
- Efficient road distance for era: ~2000m actual road distance
- With 2.5x multiplier, straight-line limit should be: **~800m**

### Issue 3: Single-Direction Deadheading
- All routes were point-to-point: A -> B (loaded), B -> A (empty)
- Deadheading rate: 50%
- Vehicle utilization: 50%
- Revenue/cost ratio: Unprofitable for long slow routes

### Issue 4: No Bi-Directional Cargo Flow
- Failed to find routes where cargo flows BOTH ways
- Examples of correct patterns not implemented:
  - Iron ore one direction, coal the other (same rail line)
  - Rock to ConMats, ConMats to town near quarry

## Lessons Learned

### L1: Era-Based Transport Selection
```
1850-1899: Road max ~800m straight-line (2000m actual road)
           Use RAIL for anything longer
1900-1949: Road max ~1600m straight-line
1950+: Road viable up to ~3000m straight-line
```

### L2: Distance Calculation
```python
# WRONG: Using straight-line distance
dist = sqrt((x2-x1)^2 + (y2-y1)^2)

# RIGHT: Apply road multiplier
actual_road_dist = straight_line_dist * 2.0  # Conservative estimate
```

### L3: Bi-Directional Cargo Requirement
For ANY long route to be profitable:
1. Find cargo flowing A -> B
2. Find cargo flowing B -> A (or B -> C where C is near A)
3. Use multi-cargo vehicles (trains with mixed wagons, ships)

### L4: Hub-and-Spoke Pattern
When multiple raw materials feed one processor:
- Coal + Iron Ore -> Steel Mill
- If Coal Mine is near Iron Ore Mine:
  - Build RAIL from both mines to Steel Mill
  - Same trains can carry BOTH cargos
  - Vehicles stay loaded longer

## Correct Strategy for 1880

1. **Use RAIL for distances > 1000m straight-line**
   - Rail is efficient regardless of distance
   - Can carry multiple cargo types

2. **Find bi-directional opportunities FIRST**
   - Look for geographic clusters where cargo flows both ways
   - Example: Raw materials near finished goods consumers

3. **Multi-stop lines preferred**
   - Instead of A->B, build A->B->C->A loops
   - Each leg should carry cargo

4. **Road only for SHORT distances**
   - < 800m straight-line in 1880
   - Primarily for last-mile delivery to towns

## Implementation Checklist for Future Agents

- [ ] Check year and set transport type limits
- [ ] Calculate actual road distance (straight-line * 2.0)
- [ ] For routes > limit, MUST use rail/water
- [ ] Verify bi-directional cargo potential BEFORE building
- [ ] Prefer multi-stop lines over point-to-point
- [ ] Track vehicle utilization (loaded vs deadhead distance)

## Tags
#failure #1880 #horse-drawn #deadheading #bi-directional #transport-selection
