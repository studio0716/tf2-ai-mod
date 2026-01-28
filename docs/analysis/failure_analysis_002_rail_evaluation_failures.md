# Failure Analysis #002: Rail Evaluation Failures

## Hypothesis
Using AI Builder's `buildIndustryRailConnection` with `preSelectedPair` would allow building any rail connection between two industries.

## Test Conditions
- **Year**: 1880
- **Starting Capital**: $10,000,000
- **Transport Type**: Rail

## Routes Attempted
1. **Coal Mine -> Steel Mill**: SUCCESS
   - IDs: 20373 -> 24324
   - Cost: ~$7M
   - Result: 1 train running

2. **Iron Ore Mine -> Steel Mill**: PARTIAL
   - IDs: 15602 -> 24324
   - Evaluation succeeded but no additional train added
   - May have extended existing line

3. **Steel Mill -> ConMats**: FAILED
   - IDs: 24324 -> 21553
   - Error: "No matching industries were found for rail"
   - Road evaluation also failed

## Root Cause Analysis

### Issue 1: Evaluation Function Limitations
The `connectEval.evaluateNewIndustryConnectionForTrains()` function returns nil for some valid industry pairs.

Possible reasons:
- Cargo type compatibility check fails
- Distance outside acceptable range
- Terrain/path finding fails
- Industry already has a rail connection

### Issue 2: Shared Line Behavior
When a second rail route is built to the same destination (Steel Mill):
- No new train was added
- Possible that AI Builder extends existing line instead of creating new one
- Or route was rejected as duplicate

### Issue 3: Auto-Build Ineffective
Enabling auto-build options didn't result in additional routes being built:
- `autoEnableTruckFreight`, `autoEnableFreightTrains`, etc.
- AI Builder may be waiting for better opportunities
- Or evaluations are failing for available routes

## Results
- **Money trajectory**: $10M -> $2.8M (rail build) -> $2.5M (stable/declining)
- **Vehicles**: 1 train
- **Profitability**: Barely break-even with single-direction deadheading

## Lessons Learned

### L1: AI Builder Evaluation is Restrictive
The evaluation functions have criteria beyond just producer-consumer matching:
- May check cargo flow rates
- May check existing connections
- May have terrain requirements
- May have distance thresholds

### L2: preSelectedPair Doesn't Guarantee Build
Even with preSelectedPair set, the evaluation can still return nil if:
- The pair doesn't meet internal criteria
- Path finding fails
- Cargo compatibility fails

### L3: Need to Investigate Evaluation Functions
To build arbitrary connections, we need to understand:
- What criteria `evaluateNewIndustryConnectionForTrains` uses
- What makes a "valid" rail connection
- How to bypass evaluation when we know the connection is valid

## Next Steps for Future Agents

1. **Read evaluation function code**:
   - `res/scripts/ai_builder_connect_eval.lua`
   - Look for criteria that cause rejection

2. **Try alternative approach**:
   - Build stations manually
   - Build tracks manually
   - Create line manually
   - Add vehicles manually

3. **Use road for shorter legs**:
   - 1880s road is inefficient for long distances
   - But short connections might work

4. **Consider multi-stop rail lines**:
   - buildMultiStopCargoRoute event might work better
   - Can specify multiple industries in one build

## Tags
#failure #rail #evaluation #ai-builder #preSelectedPair
