# LÖVE2D MCP — LLM Interaction Guide

This file provides comprehensive guidance for LLMs (Claude, GPT, etc.) interacting with a LÖVE2D game through the love2d-mcp server. This is NOT a user-facing README — it's the agent's reference for how to work with the MCP tools and LÖVE2D APIs effectively.

## Architecture

```
MCP Client (LLM) ◄──stdio──► MCP Server (TypeScript) ◄──TCP──► LÖVE2D Game (Lua)
```

- The MCP server registers tools. When the LLM calls a tool, the server sends a JSON-RPC command over TCP to the LÖVE2D game's bridge.
- The Lua bridge (`game/mcp_bridge.lua`) processes commands and returns JSON responses.
- The bridge provides **hooks** — callbacks the game registers. Some tools use these hooks, others have sensible defaults.

## Available MCP Tools

### Read-Only Observation Tools

| Tool | Purpose |
|------|---------|
| `list_objects` | Quick overview of all objects (id, type, x, y) |
| `get_object` | Full details on one object by ID |
| `get_game_state` | Comprehensive snapshot: window, FPS, objects, version, pause state |
| `get_performance_stats` | FPS, object count, deltaTime, elapsed time, dimensions |

### Game Modification Tools

| Tool | Purpose |
|------|---------|
| `add_object(type, properties?)` | Create a new entity. Returns auto-generated ID |
| `remove_object(id)` | Delete an entity by ID |
| `modify_object(id, properties)` | Update specific properties on an existing entity |
| `pause_game(paused)` | Pause/resume the game loop |
| `create_debug_text(text, x?, y?, color?)` | Draw a text overlay (auto-clears after 10s) |
| `capture_screenshot` | Save a PNG screenshot to the game's save directory |

### Power Tool

| Tool | Purpose |
|------|---------|
| `run_lua(code)` | Execute arbitrary Lua. Full access to the `love` API, the `objects` table, and **`mcp_bridge`** (the bridge module itself — for self-healing). |

**First thing to do when connecting to a new or unfamiliar game:**
1. Call `get_game_state()` to see the overall game structure
2. Call `list_objects()` to see what entities exist
3. Call `get_object("some_id")` on a representative entity to learn its property schema
4. **Test the hooks** — try `add_object`, `pause_game`, `create_debug_text`. If any return "no X configured" errors, register the missing hook via `run_lua` (see [Self-Healing](#self-healing-registering-missing-hooks-at-runtime))
5. Only then consider `run_lua` for deeper queries

---

## LÖVE2D API Reference (Most Useful Functions)

These are the LÖVE2D APIs the LLM is most likely to need when writing Lua code for `run_lua` or understanding game state.

### Graphics (`love.graphics`)

Used inside `love.draw()` or for querying display info.

```lua
-- Display info
love.graphics.getWidth()            -- number: window width in pixels
love.graphics.getHeight()           -- number: window height in pixels
love.graphics.getDimensions()       -- width, height
love.graphics.getBackgroundColor()  -- r, g, b, a

-- Drawing (cannot call these inside love.update() — will crash)
love.graphics.setColor(r, g, b, a?)  -- 0-1 floats for subsequent draws
love.graphics.circle(mode, x, y, radius, segments?)  -- mode: "fill" or "line"
love.graphics.rectangle(mode, x, y, w, h)
love.graphics.polygon(mode, ...)
love.graphics.print(text, x, y, rotation?, sx?, sy?)
love.graphics.printf(text, x, y, limit, align?)  -- "left", "center", "right"
love.graphics.line(x1, y1, x2, y2, ...)
love.graphics.points(x1, y1, x2, y2, ...)
love.graphics.ellipse(mode, x, y, rx, ry)
love.graphics.arc(mode, x, y, r, angle1, angle2, segments?)
love.graphics.newImage(filename)     -- Image (loaded outside draw loop)
love.graphics.draw(image, x, y, ...)

-- Transformations
love.graphics.push()                 -- save transform state
love.graphics.pop()                  -- restore transform state
love.graphics.translate(x, y)
love.graphics.scale(sx, sy)
love.graphics.rotate(angle)          -- radians
love.graphics.setLineWidth(width)
love.graphics.setFont(font)
love.graphics.newFont(size)          -- create a raster font

-- Screenshots (11.0+)
love.graphics.newScreenshot()        -- ImageData of current frame
```

### Timer (`love.timer`)

```lua
love.timer.getFPS()                  -- number: current frames per second
love.timer.getDelta()                -- number: time since last frame in seconds
love.timer.getTime()                 -- number: seconds since love.load()
love.timer.sleep(seconds)            -- block (avoid in love.update/draw)
```

### Input (`love.keyboard`, `love.mouse`)

```lua
-- Keyboard
love.keyboard.isDown(key)           -- boolean: "space", "return", "a-z", "up", "down", "left", "right"
love.keyboard.getScancodeFromKey(key)
love.keyboard.getKeyFromScancode(scancode)

-- Mouse
love.mouse.getX()                   -- number: mouse x position
love.mouse.getY()                   -- number: mouse y position
love.mouse.getPosition()            -- x, y
love.mouse.isDown(button)           -- 1 = left, 2 = right, 3 = middle
```

### Window (`love.window`)

```lua
love.window.getMode()               -- width, height, flags table
love.window.setMode(w, h, flags?)   -- set window size (use sparingly)
love.window.getTitle()
```

### Filesystem (`love.filesystem`)

```lua
love.filesystem.getSaveDirectory()   -- string: path to save folder
love.filesystem.write(name, data)    -- write file in save directory
love.filesystem.read(name)           -- file contents or nil
love.filesystem.getInfo(path)        -- file info or nil
love.filesystem.exists(path)         -- boolean
```

### Audio (`love.audio`, `love.sound`)

```lua
love.audio.newSource(filename, type) -- type: "static" or "stream"
source:play()                        -- start/resume playback
source:pause()
source:stop()
source:setVolume(vol)                -- 0.0 to 1.0
source:isPlaying()                   -- boolean
source:getDuration()                 -- seconds (static only)
```

### Physics (`love.physics`) — Box2D wrapper

```lua
love.physics.newWorld(xg, yg, sleep?)  -- World
world:setGravity(x, y)
love.physics.newBody(world, x, y, type) -- type: "static", "dynamic", "kinematic"
love.physics.newCircleShape(radius)
love.physics.newRectangleShape(w, h)
love.physics.newFixture(body, shape, density?)
```

### Version

```lua
love.getVersion()                   -- major, minor, revision, codename
love.isVersionCompatible(major, minor, revision?)  -- boolean
```

---

## Coordinate System

- **Origin:** top-left corner of window (0, 0)
- **X-axis:** increases to the right
- **Y-axis:** increases downward (unlike standard Cartesian)
- **Angles:** measured in radians, clockwise from the right (3 o'clock)
- **LÖVE2D versions:** 11.x is current; 11.0 introduced most modern APIs; 12.x is in development
- **draw() order matters:** later draw calls appear on top

---

## Game Interaction Patterns

### 1. Discovering an Unknown Game's Architecture

```lua
-- Get the full object schema from a representative object
local info = {}
for id, obj in pairs(objects) do
  info[id] = {}
  for k, v in pairs(obj) do
    info[id][k] = type(v)
  end
  break  -- Just one object to see the schema
end
return info
```

### 2. Filtering Objects by Criteria

```lua
-- Find all objects of a specific type in a region
local results = {}
for id, obj in pairs(objects) do
  if obj.type == "ball" and obj.x > 400 and obj.y < 300 then
    table.insert(results, {id = id, x = obj.x, y = obj.y})
  end
end
return results
```

### 3. Batch Modifications

```lua
-- Safely modify many objects
local modified = 0
for id, obj in pairs(objects) do
  if obj.type == "ball" and obj.radius > 20 then
    obj.r = 1.0  -- Make them red
    obj.g = 0
    obj.b = 0
    modified = modified + 1
  end
end
return {modified = modified}
```

### 4. Adding Visual Debug Info via create_debug_text

```
Preferred pattern: use the `create_debug_text` tool instead of run_lua
when you just want the LLM to see output.
```

### 5. Using Pause for Safe Inspection

```
Pattern: pause_game → inspect/modify → resume_game
This is the safest way to make complex changes without worrying about game
loop timing or race conditions.
```

### 6. Screenshot-Driven Debugging

```
Pattern: modify_game_state → capture_screenshot → inspect_screenshot
This gives you visual confirmation of your changes.
```
Note: `capture_screenshot` saves to the game's save directory. The response
includes `file` (full path), `filename`, `width`, and `height`.

---

## Safe Operations Guide

### ✅ Safe to do anytime via `modify_object`
- Change position (x, y)
- Change velocity (vx, vy)
- Change color (r, g, b)
- Change size (radius, width, height)
- Toggle boolean properties
- Any numeric property

### ✅ Safe via `run_lua` (read-only)
- Loop over objects to count/filter
- Call `love.timer.getFPS()`, `love.timer.getTime()`
- Call `love.graphics.getWidth()`, `love.graphics.getHeight()`
- Access `love.keyboard.isDown()`
- Access `love.mouse.getPosition()`

### ✅ Safe via `run_lua` (with care)
- Creating new objects with `add_object` tool (not raw Lua — use the tool)
- Modifying objects by setting properties directly
- Calling `love.graphics.setColor()` + print for debug overlays (but only inside draw context — actually, just use `create_debug_text` tool)
- Setting `love._paused = true` / `false` to stop game loop

---

## 🚫 Dangerous Operations — AVOID

These operations can crash the game, corrupt state, or cause infinite loops.

### CRASH: Graphics calls in update context
```lua
-- ❌ NEVER call draw functions in love.update()
love.graphics.setColor(1, 0, 0)
love.graphics.print("hello", 10, 10)
-- These can only be called from within love.draw(), not from run_lua
```

### CRASH: love.event.quit()
```lua
-- ❌ This exits the game immediately
love.event.quit()
-- If you need a soft restart, use pause_game instead
```

### CRASH: Destroying love modules
```lua
-- ❌ Never nil out or replace love modules
love.graphics = nil  -- Game will crash immediately
love = nil           -- Complete meltdown
```

### CRASH: Infinite loops
```lua
-- ❌ Will freeze the game (and MCP stops responding)
while true do end

-- ❌ Same — use iteration limits
for i = 1, math.huge do end
```

### CRASH: Invalid object states
```lua
-- ❌ Division by zero in game logic
obj.radius = 0    -- If game code divides by radius

-- ❌ Nil-critical properties
obj.x = nil       -- Physics calculations will error
```

### Data Loss: Overwriting objects table
```lua
-- ❌ This destroys ALL game objects
objects = {}   -- Use remove_object tool or iterate with nil instead
```

### Danger: Unexpected File Operations
```lua
-- ❌ love.filesystem can write outside sandbox in some configurations
love.filesystem.write("../../.bashrc", "evil code")
-- Be conservative with filesystem operations
```

---

## Debugging Best Practices

### Quick Health Check
```
1. get_performance_stats() — see FPS, object count
2. get_game_state() — see everything at once
3. If FPS dropped, check if something is spawning too many objects
```

### Diagnosing a Problem
```
1. pause_game(true) — freeze everything
2. get_object() / run_lua() to inspect suspect objects
3. Think about what should be happening vs. what is
4. Make targeted changes
5. pause_game(false) — resume and observe
6. capture_screenshot() for visual confirmation
```

### If the Game Crashed
The MCP TCP bridge may still be running, or it may have shut down with the game.
- Restart the game: `love game/` in the project directory
- The screenshot file may still exist in the save directory if it was captured before the crash

### Memory & Performance Concerns
- Each `run_lua` call creates a sandboxed environment. Don't create massive tables inside run_lua.
- Prefer tools over raw Lua for simple operations (they're more efficient).
- The game's object table is modified in-place. Changes to objects persist.
- Debug text auto-clears after 10 seconds.

---

## Object Schema Conventions

The example game uses this schema for balls, but **your game may differ**:

```lua
-- Typical ball object:
{
  id = "ball_1",     -- string: unique identifier
  type = "ball",     -- string: entity classifier
  x = 234.5,         -- number: x position (pixels)
  y = 156.2,         -- number: y position (pixels)
  vx = 150.0,        -- number: velocity x (pixels/sec)
  vy = -100.0,       -- number: velocity y (pixels/sec)
  radius = 25,       -- number: circle radius (pixels)
  r = 0.8,           -- number: red color 0-1
  g = 0.2,           -- number: green color 0-1
  b = 0.9            -- number: blue color 0-1
}
```

**Always discover the actual schema** by calling `get_object()` on an existing entity rather than assuming the schema above.

---

## Key LÖVE2D Callback Lifecycle

For understanding what code runs and when:

```
love.load()        — Runs once at startup
  ↓
love.update(dt)    — Runs every frame (dt = seconds since last frame)
  ↓
love.draw()        — Runs every frame, after update
  ↓
[repeat love.update → love.draw ~60 times/second]
  ↓
love.quit()        — Runs once on exit
```

Other callbacks (run when events occur):
- `love.keypressed(key, scancode, isRepeat)` — on key press
- `love.keyreleased(key, scancode)` — on key release
- `love.mousepressed(x, y, button)` — on mouse button press
- `love.mousereleased(x, y, button)` — on mouse button release
- `love.mousemoved(x, y, dx, dy)` — on mouse move
- `love.focus(focused)` — window focus changed
- `love.resize(w, h)` — window resized

---

## MCP Server Tool Descriptions (for reference)

The MCP tools are registered by `src/index.ts` and handled by `game/mcp_bridge.lua`. The bridge provides hook callbacks that `game/main.lua` registers. If a hook isn't registered, the bridge tries a default implementation (e.g., `modify_object` defaults to direct table manipulation; `add_object` requires a hook).

The tool-to-bridge-command mapping:

| MCP Tool | Bridge Command | Requires Hook? |
|----------|---------------|----------------|
| `list_objects` | `list_objects` | objectGetter |
| `get_object` | `get_object` | objectGetter |
| `run_lua` | `run_lua` | objectGetter (optional, for `objects` access) |
| `add_object` | `add_object` | YES — objectAdder |
| `remove_object` | `remove_object` | No (default removes from table) |
| `modify_object` | `modify_object` | No (default modifies in place) |
| `get_game_state` | `get_game_state` | No (default builds from love + getter) |
| `pause_game` | `pause_game` | YES — pauseSetter |
| `get_performance_stats` | `get_performance_stats` | No (uses love APIs) |
| `create_debug_text` | `set_debug_text` | YES — debugTextSetter |
| `capture_screenshot` | `capture_screenshot` | No (uses love APIs) |

---

## Self-Healing: Registering Missing Hooks at Runtime

Some tools require the game to register callback hooks. If the game's `main.lua` hasn't registered them, the tool returns an error like:

```
"No object adder configured. Register one via run_lua: mcp_bridge.setObjectAdder(...)"
```

**You can fix this without editing or restarting the game.** The `run_lua` sandbox includes `mcp_bridge` — so you can register any missing hook on-the-fly.

### Quick Repair Template

If `add_object` fails, register an object adder:

```lua
mcp_bridge.setObjectAdder(function(objType, properties)
  -- Create a unique ID (incrementing numeric ID)
  local id = 0
  for k in pairs(objects) do
    local n = tonumber(k:match("(%d+)$"))
    if n and n > id then id = n end
  end
  id = id + 1
  -- Build the new object
  local obj = {id = "entity_" .. id, type = objType}
  for k, v in pairs(properties or {}) do
    obj[k] = v
  end
  objects["entity_" .. id] = obj
  return obj
end)
```

If `pause_game` fails, register a pause setter:

```lua
mcp_bridge.setPauseSetter(function(paused)
  love._paused = paused  -- Use love as a namespace since it's global
end)
```

Then in a subsequent `run_lua`, register the guard in the game loop:

```lua
-- Modify the game's update function to respect the pause flag
local originalUpdate = love.update
love.update = function(dt)
  if love._paused then
    -- Still process MCP commands
    mcp_bridge.update()
    return
  end
  originalUpdate(dt)
end
```

If `create_debug_text` fails, register a debug text setter:

```lua
mcp_bridge.setDebugTextSetter(function(text, x, y, color)
  love.graphics.setColor(color and color.r or 0, color and color.g or 1, color and color.b or 0)
  love.graphics.print(tostring(text), x or 10, y or love.graphics.getHeight() - 30)
end)
```

### Self-Healing Workflow

```
1. Try the tool → if it errors with "no X configured", proceed
2. Use run_lua to register the hook via mcp_bridge.setXxx(...)
3. Retry the tool → it should succeed now
4. The hook stays registered for the lifetime of the game session
```

This works for all three hook-requiring tools: `add_object`, `pause_game`, and `create_debug_text`. The hooks persist until the game restarts.
