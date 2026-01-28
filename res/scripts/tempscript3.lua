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
return data