local util = require "ai_builder_base_util"
local data = {}

function data.helloWorld() 
	print("Hello world!")
end 

function data.fixLines() 
	for i, lineId in pairs(api.engine.system.lineSystem.getLines()) do 
		local line = util.getComponent(lineId, api.type.ComponentType.LINE)
		if line.stops[1].loadMode==api.type.enum.LineLoadMode.FULL_LOAD_ALL then 
			if line.vehicleInfo.transportModes[9]==1 then 
				print(lineId, util.getComponent(lineId, api.type.ComponentType.NAME).name) 
				local newLine =  api.type.Line.new()
				 
				for i, stop in pairs(line.stops) do 	
					newLine.stops[i]=stop
					if i == 1 then 
						newLine.stops[i].loadMode = api.type.enum.LineLoadMode.LOAD_IF_AVAILABLE
					end 
				end 
				 
				local updateLine = api.cmd.make.updateLine(lineId, newLine)
				api.cmd.sendCommand(updateLine, function(res, success) 
					print("Attempt to update line was",success)
				end)
				
			end
		end
	end
end
function data.debugLineInfo(lineId) 
	local simPersons = api.engine.system.simPersonSystem.getSimPersonsForLine(lineId)
	local naming = util.getComponent(lineId, api.type.ComponentType.NAME)
	print("There were",#simPersons,"for",lineId,"name=",naming.name)
	local account = util.getComponent(lineId, api.type.ComponentType.ACCOUNT)
	--debugPrint(account)
	local journal = account.journal 
	local sum = 0
	local gameTimeComp = util.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	local gameTime = gameTimeComp.gameTime 
	-- reckon 2000 millis per day 
	local oneYear = 2000*365
	local shownOneMonth = false 
	local oneMonth= 2000*30
	local oneYearAgo = gameTime - oneYear
	local oneMonthAgo = gameTime - oneMonth
	print("There were",#account.journal,"entries")
	for i = #account.journal, 1, -1 do 
		local entry = account.journal[i]
		if entry.time < oneYearAgo then 
			print("Breaking loop at ",i)
			break
		end 	
		if entry.time < oneMonthAgo and not shownOneMonth then 
			print("Found one month ago with ",sum,"at i=",i)
			shownOneMonth = true 
		end 
		if entry.category.type == api.type.enum.JournalEntryType.INCOME then  
			sum = sum + entry.amount 
		end 
	end 
	print("The total income was",sum)
	
	local logBook = util.getComponent(lineId, api.type.ComponentType.LOG_BOOK)
	local times = logBook.name2log.itemsTransported.times
	local timeTo = #times
	for i = #times, 1, -1 do 
		if times[i]<oneYearAgo then 
			print("Breakting at i=",i,"of",#times)
			break 
		end 
		timeTo = i 
	end 
	local sumValue = 0
	local values = logBook.name2log.itemsTransported.values
	for i = #values, 1, -1 do 
		if i < timeTo then 
			break 
		end 
		sumValue = sumValue + values[i]
	end 
	local alternativeCalc = values[#values]-values[timeTo]
	local lineEntityFull = game.interface.getEntity(lineId)
	local rate = lineEntityFull.rate
	print("The sumValue was",sumValue,"alternativeCalc=",alternativeCalc,"rate=",rate)
end 

function data.attemptLengthUpgrade(constructionId) 
	local construction = util.getComponent(constructionId, api.type.ComponentType.CONSTRUCTION)
	local stationParams = util.deepClone(construction.params) 
	 
	 
	--stationParams.length = stationParams.length+1
	local helper = require "ai_builder_station_template_helper"
	stationParams.modules = util.setupModuleDetailsForTemplate(helper.createRoadTemplateFn(stationParams))   
	
	print("About to execute upgradeConstruction for constructionId ",constructionId)
	stationParams.seed = nil
	game.interface.upgradeConstruction(constructionId, construction.fileName, stationParams)
--	pcall(function()end)
end 

function data.fixLinesWaste() 
	for i, lineId in pairs(api.engine.system.lineSystem.getLines()) do 
		local line = util.getComponent(lineId, api.type.ComponentType.LINE)
		local naming = util.getComponent(lineId, api.type.ComponentType.NAME)
		local name = naming.name 
		local condition = line.stops[1] and line.stops[1].loadMode==api.type.enum.LineLoadMode.FULL_LOAD_ALL and (string.find(name, "Waste") or string.find(name, "Unsorted mail") or string.find(name, "Recycling"))
		if line.stops[1] and line.stops[1].loadMode==api.type.enum.LineLoadMode.FULL_LOAD_ALL then 
			print("FOUND LINE WITH FULL_LOAD_ALL:",lineId,name)
		end 
		if true then 
			print("Inspecting line",lineId,"name=",name," found waste?",string.find(name, "Waste"),"had line.stops[1]?",line.stops[1],"condition=",condition,"loadmode=",line.stops[1].loadMode)
		end
		if condition then 
			print("Inspecting line",lineId,"name=",name)
			if line.vehicleInfo.transportModes[9]==1 or true then 
				print(lineId, util.getComponent(lineId, api.type.ComponentType.NAME).name) 
				local newLine =  api.type.Line.new()
				 
				for i, stop in pairs(line.stops) do 	
					newLine.stops[i]=stop
					if i == 1 then 
						newLine.stops[i].loadMode = api.type.enum.LineLoadMode.LOAD_IF_AVAILABLE
					end 
				end 
				 
				local updateLine = api.cmd.make.updateLine(lineId, newLine)
				api.cmd.sendCommand(updateLine, function(res, success) 
					print("Attempt to update line",lindId,name,"was",success)
				end)
				
			end
		end
	end
end

function data.removeMailDelivery()
	local toremove = {}
	api.engine.forEachEntityWithComponent(function(entity)
		local naming = util.getComponent(entity, api.type.ComponentType.NAME)
		if string.find(naming.name, "Mail Delivery") and #api.engine.system.lineSystem.getLineStopsForStation(entity)==0 
		and api.engine.system.streetConnectorSystem.getConstructionEntityForStation(entity) == -1  and entity ~= 716025 then 
		--	print("Found entity,",entity)
			table.insert(toremove, entity)
		end 	
	end, api.type.ComponentType.STATION)
	local util = require "ai_builder_base_util"
	local newProposal = api.type.SimpleProposal.new()
	for i = 1, #toremove do 
		local station = util.getComponent(toremove[i], api.type.ComponentType.STATION)
		local edgeId = station.terminals[1].vehicleNodeId.entity
		local replacementEdge = util.copyExistingEdge(edgeId)
		replacementEdge.comp.objects = {}
		newProposal.streetProposal.edgesToAdd[i]=replacementEdge
		newProposal.streetProposal.edgesToRemove[i]=edgeId 
		newProposal.streetProposal.edgeObjectsToRemove[i]=toremove[i]
		if true then 
			--break 
		end
	end 
	debugPrint({newProposal=newProposal})
	local build = api.cmd.make.buildProposal(newProposal, util.initContext(), true)
		api.cmd.sendCommand(build, function(res, success) 
			print("Attempt to removeMailDelivery",success,"for ",#toremove)
		end)
	
end 

function data.fixDuplicates() 
	local lineIds = api.engine.system.lineSystem.getLines()
	local alreadySeen = {}
	for i, lineId in pairs(lineIds) do 
		local name = util.getComponent(lineId, api.type.ComponentType.NAME).name
		local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(lineId)
		if #vehicles == 0 then 
			print("LineID had no vehicles,removing",lineId,name)
			api.cmd.sendCommand(api.cmd.make.deleteLine(lineId))
		else 
			if alreadySeen[name] then 
				local line = util.getComponent(lineId, api.type.ComponentType.LINE)
				if line.stops[2] then 
					local util = require "ai_builder_base_util"
					if util.isTruckStop(util.stationFromStop(line.stops[2])) then 
						print("LineID appears duplicated selling vehices",lineId,name)
						for k, vehicle in pairs(vehicles) do 
							api.cmd.sendCommand(api.cmd.make.sellVehicle(vehicle))
						end 
					end 
				end 
				
				
			else 
				alreadySeen[name]=true 
			end 
		end 		
	end
end 

function data.removeMailLines() 
	local lineIds = api.engine.system.lineSystem.getLines()
	 
	for i, lineId in pairs(lineIds) do 
		local name = util.getComponent(lineId, api.type.ComponentType.NAME).name
		local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(lineId)
		if #vehicles == 0 then 
			print("LineID had no vehicles,removing",lineId,name)
			api.cmd.sendCommand(api.cmd.make.deleteLine(lineId))
		else 
			if string.find(name,"Mail") and not string.find(name,"Unsorted") then 
				print("Removing mail line",lineId,name)
				for k, vehicle in pairs(vehicles) do 
					api.cmd.sendCommand(api.cmd.make.sellVehicle(vehicle))
				end 
			 
			end 
		end 		
	end
end 
local directionOptions = { "left", "up", "right", "down",  }
local util = require("ai_builder_base_util")
function  data.rotateDirection(direction)
	local index = util.indexOf(directionOptions, direction)
	return directionOptions[(index)%#directionOptions+1]
end 
 function data.flipDirection(direction)
	local index = util.indexOf(directionOptions, direction)
	return directionOptions[(index+1)%#directionOptions+1]
end 
function data.findMissingDirection(directions)
	for i, direction in pairs(directionOptions) do 
		if not util.contains(directions,direction) then 
			return direction
		end 
	end 

end

function data.getComponents(modelId)
	--332041
	local enums =  getmetatable(api.type.ComponentType).__index
	local result = ""
	for name, id in pairs(enums) do 
		local comp = util.getComponent(modelId, id)
		if comp then 
			result = result..name.."\n"
		
		end 
	
	end 
	return result
	
end 

function data.findInconsistentStations()

	local result = ""
	--332041
	
	api.engine.forEachEntityWithComponent(function(station) 
		local constructionId = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)
		if constructionId ~= -1 then 
			local construction = util.getComponent(constructionId, api.type.ComponentType.CONSTRUCTION)
			if construction.fileName == "station/street/modular_terminal.con"  then 
				local stationFull = util.getComponent(station, api.type.ComponentType.STATION)
				local platL = construction.params.platL or 0
				local platR = construction.params.platR or 0
				if #stationFull.terminals ~= (platL+platR) then 
					result = result..tostring(station).."\n"
				end 
				
			end 
			
		end 
		
	end, api.type.ComponentType.STATION)
	
	 
	return result
	
end 

function data.reload()
	local unloaded = {}
	for k, v in pairs(package.loaded) do 
		print("Got, k=",k,"v=",v)
		if k:match("^ai_builder") then
			package.loaded[k] = nil 
			trace("Found ai_builder")
			table.insert(unloaded, v)
		end 
	end
	for i, script in pairs(unloaded) do 
		require(script)
	end 
     print("End reload")

end 

function data.coroutinesTest() 
	local gameTimeFn = game.interface.getGameTime
	 local gametime = gameTimeFn()
				--local gametime = util.getComponent(0, api.type.ComponentType.WORLD)
	debugPrint(gametime)
	 co = coroutine.create(function ()
           for i=1,10 do
             print("co", i)
			 xpcall(function() 
				 local gametime = gameTimeFn()
				--local gametime = util.getComponent(0, api.type.ComponentType.WORLD)
				debugPrint(gametime)
			 end, 
			 function(e) 
				print(e)
				print(debug.traceback())
			end )
			 
			 
             coroutine.yield()
           end
         end)
	return co 	
end 
-- Vector helpers for 3D
local function subtract(a, b)
    return {
        x = a.x - b.x,
        y = a.y - b.y,
        z = a.z - b.z,
    }
end

local function length(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- Hermite curve evaluation in 3D
local function hermite(p0, p1, t0, t1, t)
    local h00 = 2 * t^3 - 3 * t^2 + 1
    local h10 = t^3 - 2 * t^2 + t
    local h01 = -2 * t^3 + 3 * t^2
    local h11 = t^3 - t^2

    return {
        x = h00 * p0.x + h10 * t0.x + h01 * p1.x + h11 * t1.x,
        y = h00 * p0.y + h10 * t0.y + h01 * p1.y + h11 * t1.y,
        z = h00 * p0.z + h10 * t0.z + h01 * p1.z + h11 * t1.z,
    }
end

-- Length approximation
local function hermite_length(p0, p1, t0, t1, steps)
    steps = steps or 100 -- number of subdivisions
    local length_sum = 0
    local prev = hermite(p0, p1, t0, t1, 0)
    for i = 1, steps do
        local t = i / steps
        local curr = hermite(p0, p1, t0, t1, t)
        length_sum = length_sum + length(subtract(curr, prev))
        prev = curr
    end
    return length_sum
end
function data.hermiteExample()
	-- Example usage
	local p0 = {x = 0, y = 0, z = 0}
	local p1 = {x = 1, y = 0, z = 1}
	local t0 = {x = 1, y = 2, z = 0}
	local t1 = {x = 1, y = -1, z = 2}

	local len = hermite_length(p0, p1, t0, t1, 200)
	print("Approximate 3D curve length:", len)
end 

function data.checkDepotsErr()
	xpcall(data.checkDepots, function(e) 
		print(e)
		print(debug.traceback())
	end)
end  

function data.checkDepots() 
	print("Begin checkDepots")
	local depotsFound1 = {}
	api.engine.system.vehicleDepotSystem.forEach(function(entity) 
		--print("Checking entity",entity)
		depotsFound1[entity]=true 
		local depotComp = util.getComponent(entity, api.type.ComponentType.VEHICLE_DEPOT)
		local constructionId = api.engine.system.streetConnectorSystem.getConstructionEntityForDepot(entity)
		local construction = util.getComponent(constructionId, api.type.ComponentType.CONSTRUCTION)
		if not depotComp or not construction then 
			print("WARNING! (1) No depot or construction found for",entity,"depotComp?",depotComp,"construciton?",construction)
		end 
		
	end )
	print("Begin checkDepots2")
	local depotsFound2 = {}
	api.engine.forEachEntityWithComponent(function(entity) 
		depotsFound2[entity]=true 
		local depotComp = util.getComponent(entity, api.type.ComponentType.VEHICLE_DEPOT)
		local constructionId = api.engine.system.streetConnectorSystem.getConstructionEntityForDepot(entity)
		local construction = util.getComponent(constructionId, api.type.ComponentType.CONSTRUCTION)
		if not depotComp or not construction then 
			print("WARNING! (2) No depot or construction found for",entity,"depotComp?",depotComp,"construciton?",construction)
		end 
		
	end, api.type.ComponentType.VEHICLE_DEPOT )
	local util = require "ai_builder_base_util"
	print("Depots found1 size=",util.size(depotsFound1),"depots found2 size=",util.size(depotsFound2))
	for depot, bool in pairs(depotsFound1) do 
		if not depotsFound2[depot] then 
			print("WARNING! Depot found in depots found 1 but not depots found2 for",depot)
		end 
	end 
	for depot, bool in pairs(depotsFound2) do 
		if not depotsFound1[depot] then 
			print("WARNING! Depot found in depots found 2 but not depots found1 for",depot)
		end 
	end 
end 


function data.clearCaches()
	util.clearCacheNode2SegMaps()
end 

function data.checkNodes() 
	local invalid = {}
	local allNodes = {}
	api.engine.forEachEntityWithComponent(function(node) table.insert(allNodes, node) end, api.type.ComponentType.BASE_NODE)
	util.cacheNode2SegMaps()
	for i , node in pairs(allNodes) do 
		--print("Node =",node)
		if #util.getSegmentsForNode(node) ==0 then 
			table.insert(invalid, node)
			print("WARNING! Node ",node,"had no segments")
		end 
		local nodeFull = util.getNode(node)
		local p = util.nodePos(node)
		if p.x~=p.x or p.y~=p.y or p.z~=p.z then 
			table.insert(invalid, node)
			print("WARNING! Node had NaN",node)
			debugPrint(nodeFull)
		end 
		if not util.isValidCoordinate(p) then 
			table.insert(invalid, node)
			trace("WARNING! node",node," at invalid coord")
			debugPrint(nodeFull)
		end 
		
	end 
	util.clearCacheNode2SegMaps()
	return invalid
end 

-- Vector helpers for 3D

function data.hermiteExample2()
-- Example usage
local p0 = {x = 0, y = 0, z = 0}
local p1 = {x = 1, y = 0, z = 1}
local t0 = {x = 1, y = 2, z = 0}
local t1 = {x = 1, y = -1, z = 2}

local len = hermite_length_gauss(p0, p1, t0, t1)
print("Approximate 3D curve length (Gaussian quadrature):", len)
end


function data.runTests()
	package.loaded["ai_builder_tests"]=nil
	local tests = require "ai_builder_tests"
	for i, fun in pairs(tests) do 
		fun()
	end 
end 

function data.removeOutOfBoundsNodes() 
	local util = require "ai_builder_base_util"
	util.clearCacheNode2SegMaps()
	local nodesToRemove = {}
	api.engine.forEachEntityWithComponent(function(node)
		local p = util.nodePos(node)
		if not util.isValidCoordinate(p) and not util.isNodeConnectedToFrozenEdge(node) then 
			print("Removing node",node,"at",p.x,p.y)
			table.insert(nodesToRemove,node)
		end 
		
	end, api.type.ComponentType.BASE_NODE)
	local alreadySeen = {}
	print("Got ",#nodesToRemove)
	local newProposal = api.type.SimpleProposal.new()
	
	local edgesToRemove = {}
	local edgeObjectsToRemove = {}
	
	for i, node in pairs(nodesToRemove) do 
		newProposal.streetProposal.nodesToRemove[i]=node
		local segs = util.getSegmentsForNode(node)
		for j, seg in pairs(segs) do 
			if not alreadySeen[seg] then 
				alreadySeen[seg]=true 
				table.insert(edgesToRemove, seg)
			end 
		end 
		
	end 
	for i, edgeId in pairs(edgesToRemove) do 
		newProposal.streetProposal.edgesToRemove[i]=edgeId
		local edge = util.getEdge(edgeId)
		for j, edgeObj in pairs(edge.objects) do 
			newProposal.streetProposal.edgeObjectsToRemove[1+#newProposal.streetProposal.edgeObjectsToRemove]=edgeObj[1]
		end 
	end 
	
	
	debugPrint({newProposal=newProposal})
	local build = api.cmd.make.buildProposal(newProposal, util.initContext(), true)
	api.cmd.sendCommand(build, function(res, success) 
		print("Attempt to removeOutOfBoundsNodes",success,"for ",#nodesToRemove)
	end)
end 


function data.printBusiest()
	local pathFindingUtil = require "ai_builder_pathfinding_util"
	local allEdges = pathFindingUtil.getAllEdgesUsedByLines(filterFn )
	local util = require "ai_builder_base_util"
	local byLines = {}
	for edgeId, lineList in pairs(allEdges) do 
		table.insert(byLines, {
			edgeId=edgeId,
			lineList=lineList,
			scores={
				-#lineList
			}
		})
	end 
	local sorted = util.evaluateAndSortFromScores(byLines, {1})
	
	for i = 1, math.min(#sorted, 25) do 
		local result = sorted[i]
		debugPrint(result)
	end 
	
end 

-- 7-point Gaussian quadrature points (on [-1, 1])
local gauss_points = {
    -0.9491079123,
    -0.7415311856,
    -0.4058451514,
    0.0,
    0.4058451514,
    0.7415311856,
    0.9491079123,
}

-- Corresponding weights
local gauss_weights = {
    0.1294849662,
    0.2797053915,
    0.3818300505,
    0.4179591837,
    0.3818300505,
    0.2797053915,
    0.1294849662,
}


-- 9-point Gaussian quadrature points
local gauss_points = {
    -0.9681602395,
    -0.8360311073,
    -0.6133714327,
    -0.3242534234,
    0.0,
    0.3242534234,
    0.6133714327,
    0.8360311073,
    0.9681602395,
}

-- Corresponding weights
local gauss_weights = {
    0.0812743884,
    0.1806481607,
    0.2606106964,
    0.3123470770,
    0.3302393550,
    0.3123470770,
    0.2606106964,
    0.1806481607,
    0.0812743884,
}
return data