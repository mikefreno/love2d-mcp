-- Simple LÖVE2D game with MCP support
local mcp_bridge = require("mcp_bridge")

-- Game objects
local objects = {}
local nextId = 1

-- Game state for MCP control
local gamePaused = false
local debugTexts = {}
local debugTextIdCounter = 1

function love.load()
    -- Initialize MCP bridge
    mcp_bridge.init(12345)

    -- Create some example objects (bouncing balls)
    for i = 1, 5 do
        local obj = {
            id = "ball_" .. nextId,
            type = "ball",
            x = math.random(50, 750),
            y = math.random(50, 550),
            vx = math.random(-200, 200),
            vy = math.random(-200, 200),
            radius = math.random(10, 30),
            r = math.random(),
            g = math.random(),
            b = math.random()
        }
        objects[obj.id] = obj
        nextId = nextId + 1
    end

    -- Register object access functions with MCP bridge
    mcp_bridge.setObjectGetter(function()
        return objects
    end)

    -- Register object creator
    mcp_bridge.setObjectAdder(function(objType, properties)
        local id = "entity_" .. nextId
        nextId = nextId + 1
        local obj = {id = id, type = objType}
        for k, v in pairs(properties) do
            obj[k] = v
        end
        objects[id] = obj
        return obj
    end)

    -- Register object remover (optional, bridge has default)
    mcp_bridge.setObjectRemover(function(id)
        if objects[id] then
            objects[id] = nil
            return true
        end
        return false
    end)

    -- Register object modifier (optional, bridge has default)
    mcp_bridge.setObjectModifier(function(id, properties)
        local obj = objects[id]
        if not obj then
            error("Object not found: " .. id)
        end
        for k, v in pairs(properties) do
            obj[k] = v
        end
        return obj
    end)

    -- Register pause setter
    mcp_bridge.setPauseSetter(function(paused)
        gamePaused = paused
    end)

    -- Register debug text setter
    mcp_bridge.setDebugTextSetter(function(text, x, y, color)
        local id = "debug_" .. debugTextIdCounter
        debugTextIdCounter = debugTextIdCounter + 1
        debugTexts[id] = {
            text = tostring(text),
            x = x or 10,
            y = y or love.graphics.getHeight() - 60,
            r = (color and color.r) or 0,
            g = (color and color.g) or 1,
            b = (color and color.b) or 0,
            createdAt = love.timer.getTime()
        }
        -- Remove old debug texts after 10 seconds
        local now = love.timer.getTime()
        for k, v in pairs(debugTexts) do
            if now - v.createdAt > 10 then
                debugTexts[k] = nil
            end
        end
    end)

    -- Register comprehensive game state getter
    mcp_bridge.setGameStateGetter(function()
        local state = {
            window = {
                width = love.graphics.getWidth(),
                height = love.graphics.getHeight()
            },
            fps = love.timer.getFPS(),
            objectCount = 0,
            objects = {},
            version = {},
            paused = gamePaused,
        }

        local major, minor, revision = love.getVersion()
        state.version = {major = major, minor = minor, revision = revision}

        for id, obj in pairs(objects) do
            state.objectCount = state.objectCount + 1
            table.insert(state.objects, {
                id = id,
                type = obj.type,
                x = obj.x,
                y = obj.y
            })
        end

        return state
    end)
end

function love.update(dt)
    -- Update MCP bridge (check for incoming commands)
    mcp_bridge.update()

    -- Skip game logic when paused
    if gamePaused then
        return
    end

    -- Update game objects
    for _, obj in pairs(objects) do
        if obj.type == "ball" then
            -- Update position
            obj.x = obj.x + obj.vx * dt
            obj.y = obj.y + obj.vy * dt

            -- Bounce off walls
            if obj.x - obj.radius < 0 or obj.x + obj.radius > love.graphics.getWidth() then
                obj.vx = -obj.vx
                obj.x = math.max(obj.radius, math.min(love.graphics.getWidth() - obj.radius, obj.x))
            end

            if obj.y - obj.radius < 0 or obj.y + obj.radius > love.graphics.getHeight() then
                obj.vy = -obj.vy
                obj.y = math.max(obj.radius, math.min(love.graphics.getHeight() - obj.radius, obj.y))
            end
        end
    end
end

function love.draw()
    -- Draw all objects
    for _, obj in pairs(objects) do
        if obj.type == "ball" then
            love.graphics.setColor(obj.r, obj.g, obj.b)
            love.graphics.circle("fill", obj.x, obj.y, obj.radius)
        end
    end

    -- Draw debug text overlays
    for _, dtxt in pairs(debugTexts) do
        love.graphics.setColor(dtxt.r, dtxt.g, dtxt.b)
        love.graphics.print(dtxt.text, dtxt.x, dtxt.y)
    end

    -- Draw HUD
    love.graphics.setColor(1, 1, 1)
    local hudY = 10
    love.graphics.print("LÖVE2D MCP Demo - Bouncing Balls", 10, hudY)
    hudY = hudY + 20
    love.graphics.print("MCP Server: localhost:12345", 10, hudY)
    hudY = hudY + 20
    love.graphics.print("Objects: " .. getObjectCount(), 10, hudY)
    hudY = hudY + 20
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, hudY)

    -- Show pause indicator
    if gamePaused then
        love.graphics.setColor(1, 1, 0)
        love.graphics.print("PAUSED", love.graphics.getWidth() / 2 - 30, love.graphics.getHeight() / 2 - 10)
    end
end

function getObjectCount()
    local count = 0
    for _ in pairs(objects) do
        count = count + 1
    end
    return count
end

function love.quit()
    mcp_bridge.shutdown()
end
