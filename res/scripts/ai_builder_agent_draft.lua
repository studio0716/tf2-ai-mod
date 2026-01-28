local util = require "ai_builder_base_util"
local api = require "api"

local agent = {}

function agent.handle(msg)
    local cmd = msg.type
    if cmd == "GET_INDUSTRIES" then
        return agent.getIndustries()
    elseif cmd == "BUILD_RAIL" then
        return agent.buildRail(msg.data)
    else 
        return { status = "error", message = "Unknown command" }
    end
end

function agent.getIndustries()
    local result = {}
    local industries = api.engine.system.streetConnectorSystem.getConstructionEntities()
    -- This is a guess at the API, I need to check how minimap gets industries.
    -- Minimap uses: api.engine.forEachEntityWithComponent(..., api.type.ComponentType.SIM_BUILDING)
    
    api.engine.forEachEntityWithComponent(function(entity)
        local constructionId = api.engine.system.streetConnectorSystem.getConstructionEntityForSimBuilding(entity)
        if constructionId and constructionId ~= -1 then
            local construction = util.getComponent(constructionId, api.type.ComponentType.CONSTRUCTION)
            local nameComp = util.getComponent(constructionId, api.type.ComponentType.NAME)
            local transf = construction.transf
            
            table.insert(result, {
                id = constructionId,
                name = nameComp and nameComp.name or "Unknown",
                fileName = construction.fileName,
                pos = { x = transf:cols(3).x, y = transf:cols(3).y, z = transf:cols(3).z }
            })
        end
    end, api.type.ComponentType.SIM_BUILDING)
    
    return { status = "ok", data = result }
end

function agent.poll()
    local raw = util.socket.receive(nil) -- nil sock for bridge
    if raw then
        print("[AGENT] Received: " .. raw)
        -- In bridge mode, raw is the JSON string
        -- We need a JSON parser. TF2 likely has one or we use regex for simple commands.
        -- Python bridge sends: {"status": "ok", "data": "..."} or just the data?
        -- Wait, echo server sends: {"status": "ok", "data": MSG}
        -- The MSG itself is what we care about.
        
        -- Simple JSON match for "type"
        local type = raw:match('"type"%s*:%s*"(.-)"')
        if type then
             local response = agent.handle({type=type})
             if response then
                 -- Send response back
                 -- We need a JSON encoder. 
                 -- For now, manual concat for simple table
                 util.socket.send(nil, "{ \"type\": \"RESPONSE\", \"status\": \"ok\" }")
             end
        end
    end
end

return agent
