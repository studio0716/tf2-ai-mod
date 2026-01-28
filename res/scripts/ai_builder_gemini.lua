local util = require "ai_builder_base_util"
 
local th = util.th 

local SplineMath = {}

-- Evaluate a Cubic Hermite Spline at time t (0.0 to 1.0)
-- p0, p1: Start/End positions {x, y, z}
-- t0, t1: Start/End tangents {x, y, z}
function SplineMath.evaluate(p0, p1, t0, t1, t)
    local t2 = t * t
    local t3 = t2 * t
    
    -- Hermite Basis Functions
    local h1 =  2*t3 - 3*t2 + 1
    local h2 = -2*t3 + 3*t2
    local h3 =    t3 - 2*t2 + t
    local h4 =    t3 - t2
    
    local x = h1*p0.x + h2*p1.x + h3*t0.x + h4*t1.x
    local y = h1*p0.y + h2*p1.y + h3*t0.y + h4*t1.y
    local z = h1*p0.z + h2*p1.z + h3*t0.z + h4*t1.z
    
    return {x=x, y=y, z=z}
end


local RoadBuilder = {}

-- Config
local MAX_GRADIENT = 0.05 -- 5% slope limit (typical for highways)
local SEGMENT_SAMPLES = 5 -- How many points to check along the curve for collision

function RoadBuilder.calculateEarthworks(segment)
    local totalCut = 0
    local totalFill = 0
    
    -- Check 10 points along the 100m segment
    for i = 0, 10 do
        local t = i / 10.0
        local pos = SplineMath.evaluate(segment.p0, segment.p1, segment.t0, segment.t1, t)
        local groundH = th(pos.x, pos.y)
        
        local diff = pos.z - groundH
        
        if diff > 0 then
            -- Road is above ground (Fill/Embankment needed)
            totalFill = totalFill + diff
        else
            -- Road is below ground (Cut/Excavation needed)
            totalCut = totalCut + math.abs(diff)
        end
    end
    
    return totalCut, totalFill
end

function RoadBuilder.buildRoute(path2D)
    -- path2D is a list of {x, y} tables
    local nodes = {}

    -- 1. Initial Z Assignment (Snap to Terrain)
    for i, point in ipairs(path2D) do
        nodes[i] = {
            x = point.x,
            y = point.y,
            z = th(point.x, point.y) -- Your terrain function
        }
    end

    -- 2. Gradient Solver (Iterative Smoothing)
    -- We run this multiple times to propagate changes along the chain
    local iterations = 10
    for iter = 1, iterations do
        local stable = true
        
        -- Check every segment
        for i = 1, #nodes - 1 do
            local pA = nodes[i]
            local pB = nodes[i+1]
            
            -- Calculate current dist and height diff
            local dx = pB.x - pA.x
            local dy = pB.y - pA.y
            local dist = math.sqrt(dx*dx + dy*dy)
            local zDiff = pB.z - pA.z
            
            -- Current Slope
            local slope = math.abs(zDiff) / dist
            
            if slope > MAX_GRADIENT then
                stable = false
                
                -- Calculate allowed height difference
                local maxDiff = dist * MAX_GRADIENT
                
                -- Determine the target Z to fix the slope
                -- We usually want to meet in the middle to minimize earthworks
                local currentDir = (zDiff > 0) and 1 or -1
                local excess = math.abs(zDiff) - maxDiff
                
                -- Push both points towards each other to flatten slope
                -- (You can weight this: e.g., if pA is a fixed bridge, only move pB)
                pA.z = pA.z + (excess * currentDir * 0.5)
                pB.z = pB.z - (excess * currentDir * 0.5)
            end
        end
        
        -- Optimization: If no changes were made, break early
        if stable then break end
    end

    -- 3. Generate Tangents (Catmull-Rom)
    -- Now that Z is stable, we calculate smooth tangents
    local routeSegments = {}
    
    for i = 1, #nodes - 1 do
        local p0 = nodes[i]
        local p1 = nodes[i+1]
        
        -- Calculate previous and next points for Catmull-Rom context
        local pPrev = nodes[i-1] or p0
        local pNext = nodes[i+2] or p1
        
        -- Calculate Tangents
        -- Tension factor 0.5 is standard
        local t0 = RoadBuilder.getTangent(pPrev, p0, p1, 0.5)
        local t1 = RoadBuilder.getTangent(p0, p1, pNext, 0.5)
        
        table.insert(routeSegments, {
            p0 = p0, p1 = p1, t0 = t0, t1 = t1
        })
    end
    
    return routeSegments
end

function RoadBuilder.getTangent(prevP, currP, nextP, tension)
    -- Vector from previous to next
    local vx = nextP.x - prevP.x
    local vy = nextP.y - prevP.y
    local vz = nextP.z - prevP.z
    
    -- Scale by tension
    return { x = vx * tension, y = vy * tension, z = vz * tension }
end

local Optimizer = {}

-- Helper: Linear Interpolation
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Helper: Get 2D perpendicular vector (normalized)
-- Returns a vector 90 degrees to the right of the direction (pPrev -> pNext)
local function getLateralDir(pPrev, pNext)
    local dx = pNext.x - pPrev.x
    local dy = pNext.y - pPrev.y
    local len = math.sqrt(dx*dx + dy*dy)
    if len == 0 then return {x=0, y=0} end
    -- Rotate 90 degrees: (x, y) -> (-y, x)
    return { x = -dy/len, y = dx/len }
end

-- Main Optimization Function
-- nodes: Array of {x,y,z} generated from your initial spline breakdown
-- th: The terrain height function th(x,y)
function Optimizer.optimizeRoute2D(nodes, th)
    local ITERATIONS = 20
    local SEARCH_radius = 10.0 -- How far sideways to peek (in meters)
    local MOVEMENT_speed = 0.5 -- How fast nodes slide (0.0 to 1.0)
    local SMOOTHING_strength = 0.3 -- Resistance to sharp turns (0.0 to 1.0)

    -- 1. Calculate the "Ideal" Z profile (Constant Gradient)
    -- We want to minimize the difference between Terrain(x,y) and this IdealZ
    local totalDist = 0
    local dists = {0} -- Cache distances to calculate ideal Z
    for i = 1, #nodes - 1 do
        local dx = nodes[i+1].x - nodes[i].x
        local dy = nodes[i+1].y - nodes[i].y
        local d = math.sqrt(dx*dx + dy*dy)
        totalDist = totalDist + d
        table.insert(dists, totalDist)
    end

    local startZ = nodes[1].z
    local endZ = nodes[#nodes].z

    -- 2. Iterative Physics Loop
    for iter = 1, ITERATIONS do
        -- A. LATERAL SEARCH PASS
        -- We skip the first and last nodes (anchors)
        -- We also skip indices 2 and N-1 if we want to strictly preserve start/end tangents
        for i = 2, #nodes - 1 do
            local p = nodes[i]
            
            -- Calculate Ideal Z at this specific progress percentage
            local progress = dists[i] / totalDist
            local targetZ = lerp(startZ, endZ, progress)
            
            -- Calculate Lateral Direction (Sideways)
            local lat = getLateralDir(nodes[i-1], nodes[i+1])
            
            -- Sample Terrain Left, Center, Right
            local hCenter = th(p.x, p.y)
            local hLeft   = th(p.x + lat.x * SEARCH_radius, p.y + lat.y * SEARCH_radius)
            local hRight  = th(p.x - lat.x * SEARCH_radius, p.y - lat.y * SEARCH_radius)
            
            -- Calculate Errors (Difference from Target Z)
            local errCenter = math.abs(hCenter - targetZ)
            local errLeft   = math.abs(hLeft - targetZ)
            local errRight  = math.abs(hRight - targetZ)
            
            -- Decide movement direction
            local moveX, moveY = 0, 0
            
            -- If Left is a better match (closer to target Z) than current spot
            if errLeft < errCenter and errLeft < errRight then
                moveX = lat.x * SEARCH_radius
                moveY = lat.y * SEARCH_radius
            -- If Right is better
            elseif errRight < errCenter and errRight < errLeft then
                moveX = -lat.x * SEARCH_radius
                moveY = -lat.y * SEARCH_radius
            end
            
            -- Apply Movement (Sliding the node)
            nodes[i].x = nodes[i].x + (moveX * MOVEMENT_speed)
            nodes[i].y = nodes[i].y + (moveY * MOVEMENT_speed)
        end
        
        -- B. SMOOTHING PASS (String Tightening)
        -- This prevents the road from becoming jagged while searching for height
        -- It pulls every node towards the average of its neighbors
        for i = 2, #nodes - 1 do
            local prev = nodes[i-1]
            local next = nodes[i+1]
            
            local avgX = (prev.x + next.x) * 0.5
            local avgY = (prev.y + next.y) * 0.5
            
            nodes[i].x = lerp(nodes[i].x, avgX, SMOOTHING_strength)
            nodes[i].y = lerp(nodes[i].y, avgY, SMOOTHING_strength)
        end
    end

    -- 3. Final Height Update
    -- Update the Z values to the new terrain heights
    for i, p in ipairs(nodes) do
        p.z = th(p.x, p.y)
    end

    return nodes
end
local TangentSolver = {}

-- Helper: Vector distance
local function dist3d(pA, pB)
    local dx = pB.x - pA.x
    local dy = pB.y - pA.y
    local dz = pB.z - pA.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Helper: Vector subtraction
local function sub3d(pA, pB)
    return { x = pA.x - pB.x, y = pA.y - pB.y, z = pA.z - pB.z }
end

-- Helper: Normalize vector
local function normalize(v)
    local len = math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
    if len < 0.0001 then return {x=0, y=0, z=0}, 0 end -- Safety check
    return { x = v.x/len, y = v.y/len, z = v.z/len }, len
end

---------------------------------------------------------
-- MAIN FUNCTION
-- nodes: List of {x,y,z} coordinates
-- tension: 0.5 is standard "Catmull-Rom", 0.0 is sharp corners
---------------------------------------------------------
function TangentSolver.generateSegments(nodes, tension)
    tension = tension or 0.5
    local segments = {}
    local count = #nodes
    
    if count < 2 then return {} end

    for i = 1, count - 1 do
        local pCurr = nodes[i]
        local pNext = nodes[i+1]
        
        -- 1. Calculate Segment Length
        -- This is the anchor for our scaling. The curve is relative to THIS distance.
        local segLen = dist3d(pCurr, pNext)
        
        -- 2. Determine Start Tangent (t0) for this segment
        -- Direction is based on (Next - Prev)
        local pPrev = nodes[i-1]
        local dir0
        
        if pPrev then
            -- Normal case: direction is average of incoming/outgoing
            local rawV = sub3d(pNext, pPrev)
            dir0 = normalize(rawV)
        else
            -- Start of line case: direction points straight to next
            local rawV = sub3d(pNext, pCurr)
            dir0 = normalize(rawV)
        end
        
        -- 3. Determine End Tangent (t1) for this segment
        -- Direction is based on (NextNext - Curr)
        local pNextNext = nodes[i+2]
        local dir1
        
        if pNextNext then
            -- Normal case
            local rawV = sub3d(pNextNext, pCurr)
            dir1 = normalize(rawV)
        else
            -- End of line case: direction points straight from prev
            local rawV = sub3d(pNext, pCurr)
            dir1 = normalize(rawV)
        end
        
        -- 4. SCALE TANGENTS
        -- We force the tangent magnitude to be a percentage of the segment length.
        -- This prevents loops on short segments.
        local t0 = {
            x = dir0.x * segLen * tension,
            y = dir0.y * segLen * tension,
            z = dir0.z * segLen * tension
        }
        
        local t1 = {
            x = dir1.x * segLen * tension,
            y = dir1.y * segLen * tension,
            z = dir1.z * segLen * tension
        }

        -- 5. Store
        table.insert(segments, {
            p0 = pCurr,
            p1 = pNext,
            t0 = t0,
            t1 = t1
        })
    end

    return segments
end

 
return Optimizer