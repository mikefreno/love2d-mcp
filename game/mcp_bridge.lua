-- MCP Bridge - TCP server for communicating with MCP server
local socket = require("socket")

local mcp_bridge = {}
local server = nil
local clients = {}
local objectGetter = nil
local objectAdder = nil
local objectRemover = nil
local objectModifier = nil
local pauseSetter = nil
local debugTextSetter = nil
local gameStateGetter = nil

-- Initialize TCP server
function mcp_bridge.init(port)
    server = assert(socket.tcp())
    server:bind("*", port)
    server:listen(5)
    server:settimeout(0) -- Non-blocking
    print("MCP Bridge listening on port " .. port)
end

-- Set function to get game objects
function mcp_bridge.setObjectGetter(getter)
    objectGetter = getter
end

-- Set function to create new game objects
function mcp_bridge.setObjectAdder(adder)
    objectAdder = adder
end

-- Set function to remove game objects
function mcp_bridge.setObjectRemover(remover)
    objectRemover = remover
end

-- Set function to modify game objects directly
function mcp_bridge.setObjectModifier(modifier)
    objectModifier = modifier
end

-- Set function to pause/unpause the game
function mcp_bridge.setPauseSetter(setter)
    pauseSetter = setter
end

-- Set function to display debug text
function mcp_bridge.setDebugTextSetter(setter)
    debugTextSetter = setter
end

-- Set function to get comprehensive game state
function mcp_bridge.setGameStateGetter(getter)
    gameStateGetter = getter
end

-- Handle incoming connections and commands
function mcp_bridge.update()
    if not server then return end

    -- Accept new clients
    local client = server:accept()
    if client then
        client:settimeout(0)
        table.insert(clients, client)
        print("MCP client connected")
    end

    -- Handle existing clients
    for i = #clients, 1, -1 do
        local client = clients[i]
        local line, err = client:receive("*l")

        if line then
            -- Process command
            local success, response = pcall(mcp_bridge.handleCommand, line)
            if success then
                client:send(response .. "\n")
            else
                client:send(json.encode({error = tostring(response)}) .. "\n")
            end
        elseif err == "closed" then
            -- Client disconnected
            client:close()
            table.remove(clients, i)
            print("MCP client disconnected")
        end
        -- err == "timeout" means no data available, continue
    end
end

-- Handle a command from MCP server
function mcp_bridge.handleCommand(line)
    local command = json.decode(line)

    if command.command == "list_objects" then
        return mcp_bridge.listObjects()
    elseif command.command == "get_object" then
        return mcp_bridge.getObject(command.id)
    elseif command.command == "run_lua" then
        return mcp_bridge.runLua(command.code)
    elseif command.command == "add_object" then
        return mcp_bridge.addObject(command.type, command.properties)
    elseif command.command == "remove_object" then
        return mcp_bridge.removeObject(command.id)
    elseif command.command == "modify_object" then
        return mcp_bridge.modifyObject(command.id, command.properties)
    elseif command.command == "get_game_state" then
        return mcp_bridge.getGameState()
    elseif command.command == "pause_game" then
        return mcp_bridge.pauseGame(command.paused)
    elseif command.command == "get_performance_stats" then
        return mcp_bridge.getPerformanceStats()
    elseif command.command == "set_debug_text" then
        return mcp_bridge.setDebugText(command.text, command.x, command.y, command.color)
    elseif command.command == "capture_screenshot" then
        return mcp_bridge.captureScreenshot()
    else
        return json.encode({error = "Unknown command: " .. tostring(command.command)})
    end
end

-- List all objects
function mcp_bridge.listObjects()
    if not objectGetter then
        return json.encode({error = "No object getter configured"})
    end

    local objects = objectGetter()
    local result = {}

    for id, obj in pairs(objects) do
        table.insert(result, {
            id = id,
            type = obj.type,
            x = obj.x,
            y = obj.y
        })
    end

    return json.encode({objects = result})
end

-- Get specific object details
function mcp_bridge.getObject(id)
    if not objectGetter then
        return json.encode({error = "No object getter configured"})
    end

    local objects = objectGetter()
    local obj = objects[id]

    if not obj then
        return json.encode({error = "Object not found: " .. tostring(id)})
    end

    return json.encode({object = obj})
end

-- Add a new object to the game
function mcp_bridge.addObject(objType, properties)
    if objectAdder then
        local ok, obj = pcall(objectAdder, objType, properties or {})
        if ok then
            return json.encode({object = obj, success = true})
        else
            return json.encode({error = "Failed to create object: " .. tostring(obj)})
        end
    end
    return json.encode({error = "No object adder configured. Register one via run_lua: mcp_bridge.setObjectAdder(function(objType, properties) ... end)"})
end

-- Remove an object from the game
function mcp_bridge.removeObject(id)
    if objectRemover then
        local ok, result = pcall(objectRemover, id)
        if ok then
            return json.encode({success = true, removed = result ~= false})
        else
            return json.encode({success = false, error = tostring(result)})
        end
    end
    -- Default: use object getter and remove directly from the table
    if not objectGetter then
        return json.encode({error = "No object getter configured"})
    end
    local objects = objectGetter()
    if objects[id] then
        objects[id] = nil
        return json.encode({success = true})
    end
    return json.encode({error = "Object not found: " .. tostring(id)})
end

-- Modify an existing object's properties
function mcp_bridge.modifyObject(id, properties)
    if not properties then
        return json.encode({error = "No properties provided"})
    end

    if objectModifier then
        local ok, obj = pcall(objectModifier, id, properties)
        if ok then
            return json.encode({object = obj, success = true})
        else
            return json.encode({error = "Failed to modify object: " .. tostring(obj)})
        end
    end

    -- Default: use object getter and modify in place
    if not objectGetter then
        return json.encode({error = "No object getter configured"})
    end
    local objects = objectGetter()
    local obj = objects[id]
    if not obj then
        return json.encode({error = "Object not found: " .. tostring(id)})
    end
    for k, v in pairs(properties) do
        obj[k] = v
    end
    return json.encode({object = obj, success = true})
end

-- Get comprehensive game state
function mcp_bridge.getGameState()
    if gameStateGetter then
        local ok, state = pcall(gameStateGetter)
        if ok then
            return json.encode(state)
        else
            return json.encode({error = "State getter failed: " .. tostring(state)})
        end
    end

    -- Default: build state from available data
    local state = {
        window = {},
        fps = 0,
        objectCount = 0,
        objects = {},
        version = {},
    }

    if love and love.graphics then
        state.window.width = love.graphics.getWidth()
        state.window.height = love.graphics.getHeight()
    end
    if love and love.timer then
        state.fps = love.timer.getFPS()
    end
    if love and love.getVersion then
        local major, minor, revision = love.getVersion()
        state.version = {major = major, minor = minor, revision = revision}
    end
    if objectGetter then
        local objects = objectGetter()
        for id, obj in pairs(objects) do
            state.objectCount = state.objectCount + 1
            table.insert(state.objects, {
                id = id,
                type = obj.type,
                x = obj.x,
                y = obj.y
            })
        end
    end

    return json.encode(state)
end

-- Pause or unpause the game
function mcp_bridge.pauseGame(paused)
    if pauseSetter then
        local ok, err = pcall(pauseSetter, paused)
        if ok then
            return json.encode({success = true, paused = paused})
        else
            return json.encode({error = "Pause setter failed: " .. tostring(err)})
        end
    end
    return json.encode({error = "No pause setter configured. Register one via run_lua: mcp_bridge.setPauseSetter(function(paused) ... end)"})
end

-- Get performance statistics
function mcp_bridge.getPerformanceStats()
    local stats = {
        fps = 0,
        objectCount = 0,
        deltaTime = 0,
    }

    if love and love.timer then
        stats.fps = love.timer.getFPS()
        stats.deltaTime = love.timer.getDelta()
        stats.time = love.timer.getTime()
    end
    if love and love.graphics then
        stats.width = love.graphics.getWidth()
        stats.height = love.graphics.getHeight()
    end
    if objectGetter then
        local objects = objectGetter()
        for _ in pairs(objects) do
            stats.objectCount = stats.objectCount + 1
        end
    end

    return json.encode(stats)
end

-- Display debug text overlay in the game
function mcp_bridge.setDebugText(text, x, y, color)
    if debugTextSetter then
        local ok, err = pcall(debugTextSetter, text, x, y, color)
        if ok then
            return json.encode({success = true})
        else
            return json.encode({error = "Debug text setter failed: " .. tostring(err)})
        end
    end
    return json.encode({error = "No debug text setter configured. Register one via run_lua: mcp_bridge.setDebugTextSetter(function(text, x, y, color) ... end)"})
end

-- Capture a screenshot of the current frame
function mcp_bridge.captureScreenshot()
    if not (love and love.graphics and love.graphics.newScreenshot) then
        return json.encode({error = "Screenshots not supported in this LÖVE2D version"})
    end

    local ok, result = pcall(function()
        local imageData = love.graphics.newScreenshot()
        local encoded = love.image.newEncodedData(imageData, "png")
        local bytes = encoded:getString()
        local filename = "love2d_mcp_screenshot.png"
        love.filesystem.write(filename, bytes)
        local saveDir = love.filesystem.getSaveDirectory()
        return {
            success = true,
            file = saveDir .. "/" .. filename,
            filename = filename,
            width = imageData:getWidth(),
            height = imageData:getHeight()
        }
    end)

    if ok then
        return json.encode(result)
    else
        return json.encode({error = "Screenshot failed: " .. tostring(result)})
    end
end

-- Run arbitrary Lua code with access to game objects
function mcp_bridge.runLua(code)
    local func, err = loadstring(code)
    if not func then
        return json.encode({error = "Syntax error: " .. tostring(err)})
    end

    -- Set up environment with access to objects, love, and the bridge itself
    local env = {
        objects = objectGetter and objectGetter() or {},
        love = love,
        mcp_bridge = mcp_bridge,
        package = package,
        print = print,
        pairs = pairs,
        ipairs = ipairs,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        table = table,
        math = math,
        string = string,
        _G = _G,
    }
    setfenv(func, env)

    local success, result = pcall(func)
    if not success then
        return json.encode({error = "Runtime error: " .. tostring(result)})
    end

    -- Handle table results by encoding them
    if type(result) == "table" then
        return json.encode({result = result})
    else
        return json.encode({result = tostring(result)})
    end
end

-- Shutdown server
function mcp_bridge.shutdown()
    -- Close all clients
    for _, client in ipairs(clients) do
        client:close()
    end
    clients = {}

    -- Close server
    if server then
        server:close()
        server = nil
        print("MCP Bridge shut down")
    end
end

-- Simple JSON encoder/decoder
json = {}

function json.encode(obj)
    local t = type(obj)
    if t == "table" then
        local parts = {}
        local isArray = true
        local arraySize = 0

        -- Check if it's an array
        for k, v in pairs(obj) do
            if type(k) ~= "number" then
                isArray = false
                break
            end
            arraySize = arraySize + 1
        end

        if isArray and arraySize > 0 then
            for i, v in ipairs(obj) do
                table.insert(parts, json.encode(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(obj) do
                local key = type(k) == "string" and json.encode(k) or tostring(k)
                table.insert(parts, key .. ":" .. json.encode(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    elseif t == "string" then
        return '"' .. obj:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(obj)
    elseif t == "nil" then
        return "null"
    else
        return '"' .. tostring(obj) .. '"'
    end
end

function json.decode(str)
    local pos = 1

    local function skip_whitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function decode_string()
        local result = ""
        pos = pos + 1 -- skip opening quote
        while pos <= #str do
            local char = str:sub(pos, pos)
            if char == '"' then
                pos = pos + 1
                return result
            elseif char == "\\" then
                pos = pos + 1
                local escape = str:sub(pos, pos)
                if escape == "n" then result = result .. "\n"
                elseif escape == "t" then result = result .. "\t"
                elseif escape == "r" then result = result .. "\r"
                elseif escape == "\\" then result = result .. "\\"
                elseif escape == '"' then result = result .. '"'
                else result = result .. escape end
                pos = pos + 1
            else
                result = result .. char
                pos = pos + 1
            end
        end
        error("Unterminated string")
    end

    local function decode_value()
        skip_whitespace()
        local char = str:sub(pos, pos)

        if char == '"' then
            return decode_string()
        elseif char == "{" then
            local obj = {}
            pos = pos + 1
            skip_whitespace()
            if str:sub(pos, pos) == "}" then
                pos = pos + 1
                return obj
            end
            while true do
                skip_whitespace()
                local key = decode_string()
                skip_whitespace()
                if str:sub(pos, pos) ~= ":" then error("Expected :") end
                pos = pos + 1
                obj[key] = decode_value()
                skip_whitespace()
                char = str:sub(pos, pos)
                if char == "}" then
                    pos = pos + 1
                    return obj
                elseif char == "," then
                    pos = pos + 1
                else
                    error("Expected , or }")
                end
            end
        elseif char == "[" then
            local arr = {}
            pos = pos + 1
            skip_whitespace()
            if str:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            end
            while true do
                table.insert(arr, decode_value())
                skip_whitespace()
                char = str:sub(pos, pos)
                if char == "]" then
                    pos = pos + 1
                    return arr
                elseif char == "," then
                    pos = pos + 1
                else
                    error("Expected , or ]")
                end
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local num_str = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if num_str then
                pos = pos + #num_str
                return tonumber(num_str)
            end
            error("Invalid JSON value at position " .. pos)
        end
    end

    return decode_value()
end

return mcp_bridge
