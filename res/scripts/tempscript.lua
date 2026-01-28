local data = {}

function data.helloWorld() 
	print("Hello world!")
end 

function fixLines() 
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

function data.displayLegacyTypes() 
	local result = ""
	local alreadySeen = {}
	api.engine.forEachEntity(function(entity) 
		local entityFull = game.interface.getEntity(entity)
		if entityFull and not alreadySeen[entityFull.type] then 
			result = result..entityFull.type.."\n"
			alreadySeen[entityFull.type]=true
		end 
	end)
	
	return result

end 

return data