# Usage Examples

This document provides detailed examples of using the LÖVE2D MCP Server.

## Table of Contents

- [Basic Introspection](#basic-introspection)
- [Analyzing Game Objects](#analyzing-game-objects)
- [Dynamic Game Modification](#dynamic-game-modification)
- [Debugging](#debugging)
- [Advanced Lua Queries](#advanced-lua-queries)

## Basic Introspection

### List All Objects

Use the `list_objects` tool to get an overview of all game objects:

```json
// Input: (no parameters)
// Output:
{
  "objects": [
    {"id": "ball_1", "type": "ball", "x": 234.5, "y": 156.2},
    {"id": "ball_2", "type": "ball", "x": 567.8, "y": 432.1},
    {"id": "ball_3", "type": "ball", "x": 123.4, "y": 345.6},
    {"id": "ball_4", "type": "ball", "x": 789.0, "y": 234.5},
    {"id": "ball_5", "type": "ball", "x": 456.7, "y": 567.8}
  ]
}
```

### Get Object Details

Use `get_object` to inspect a specific object:

```json
// Input:
{
  "id": "ball_1"
}

// Output:
{
  "object": {
    "id": "ball_1",
    "type": "ball",
    "x": 234.5,
    "y": 156.2,
    "vx": 150.0,
    "vy": -100.0,
    "radius": 25,
    "r": 0.8,
    "g": 0.2,
    "b": 0.9
  }
}
```

## Analyzing Game Objects

### Count Objects by Type

```lua
local count = 0
for id, obj in pairs(objects) do
  if obj.type == "ball" then
    count = count + 1
  end
end
return count
```

### Find Objects by Color

Count purple balls (high red and blue, low green):

```lua
local purpleBalls = {}
for id, obj in pairs(objects) do
  if obj.type == "ball" then
    local isPurple = obj.b > 0.5 and obj.r > 0.5 and obj.g < 0.5
    if isPurple then
      table.insert(purpleBalls, id)
    end
  end
end
return purpleBalls
```

### Find Objects by Position

Find all objects in the top-left quadrant:

```lua
local topLeft = {}
for id, obj in pairs(objects) do
  if obj.x < 400 and obj.y < 300 then
    table.insert(topLeft, {
      id = id,
      x = obj.x,
      y = obj.y
    })
  end
end
return topLeft
```

### Calculate Object Statistics

Get average position of all balls:

```lua
local sumX, sumY, count = 0, 0, 0
for id, obj in pairs(objects) do
  if obj.type == "ball" then
    sumX = sumX + obj.x
    sumY = sumY + obj.y
    count = count + 1
  end
end
return {
  avgX = sumX / count,
  avgY = sumY / count,
  count = count
}
```

## Dynamic Game Modification

### Change Object Color

Make all balls red:

```lua
for id, obj in pairs(objects) do
  if obj.type == "ball" then
    obj.r = 1.0
    obj.g = 0.0
    obj.b = 0.0
  end
end
return "All balls are now red"
```

### Modify Object Velocities

Make all balls move faster:

```lua
local speedMultiplier = 2.0
for id, obj in pairs(objects) do
  if obj.type == "ball" then
    obj.vx = obj.vx * speedMultiplier
    obj.vy = obj.vy * speedMultiplier
  end
end
return "Speed increased by " .. speedMultiplier .. "x"
```

### Freeze/Unfreeze Objects

Stop all ball movement:

```lua
for id, obj in pairs(objects) do
  if obj.type == "ball" then
    obj.vx = 0
    obj.vy = 0
  end
end
return "All balls frozen"
```

### Teleport Objects

Move all balls to the center:

```lua
local centerX = love.graphics.getWidth() / 2
local centerY = love.graphics.getHeight() / 2

for id, obj in pairs(objects) do
  if obj.type == "ball" then
    obj.x = centerX
    obj.y = centerY
  end
end
return "All balls moved to center"
```

## Debugging

### Check for Objects Outside Bounds

```lua
local width = love.graphics.getWidth()
local height = love.graphics.getHeight()
local outOfBounds = {}

for id, obj in pairs(objects) do
  if obj.x < 0 or obj.x > width or obj.y < 0 or obj.y > height then
    table.insert(outOfBounds, {
      id = id,
      x = obj.x,
      y = obj.y
    })
  end
end

return outOfBounds
```

### Find Overlapping Objects

Detect if any balls are overlapping:

```lua
local overlaps = {}
local checked = {}

for id1, obj1 in pairs(objects) do
  if obj1.type == "ball" then
    for id2, obj2 in pairs(objects) do
      if obj2.type == "ball" and id1 ~= id2 and not checked[id2..id1] then
        local dx = obj1.x - obj2.x
        local dy = obj1.y - obj2.y
        local distance = math.sqrt(dx*dx + dy*dy)
        local minDist = obj1.radius + obj2.radius

        if distance < minDist then
          table.insert(overlaps, {id1, id2})
        end
        checked[id1..id2] = true
      end
    end
  end
end

return overlaps
```

### Monitor Object Properties

Get min/max values for specific properties:

```lua
local minX, maxX = math.huge, -math.huge
local minY, maxY = math.huge, -math.huge

for id, obj in pairs(objects) do
  if obj.type == "ball" then
    minX = math.min(minX, obj.x)
    maxX = math.max(maxX, obj.x)
    minY = math.min(minY, obj.y)
    maxY = math.max(maxY, obj.y)
  end
end

return {
  bounds = {
    x = {min = minX, max = maxX},
    y = {min = minY, max = maxY}
  }
}
```

## Advanced Lua Queries

### Get Game Information

```lua
return {
  windowSize = {
    width = love.graphics.getWidth(),
    height = love.graphics.getHeight()
  },
  fps = love.timer.getFPS(),
  version = table.concat({love.getVersion()}, ".")
}
```

### Create Color Histogram

Count balls by color family:

```lua
local colors = {red = 0, green = 0, blue = 0, other = 0}

for id, obj in pairs(objects) do
  if obj.type == "ball" then
    if obj.r > obj.g and obj.r > obj.b then
      colors.red = colors.red + 1
    elseif obj.g > obj.r and obj.g > obj.b then
      colors.green = colors.green + 1
    elseif obj.b > obj.r and obj.b > obj.g then
      colors.blue = colors.blue + 1
    else
      colors.other = colors.other + 1
    end
  end
end

return colors
```

### Calculate Total Kinetic Energy

```lua
local totalEnergy = 0
for id, obj in pairs(objects) do
  if obj.type == "ball" and obj.vx and obj.vy then
    local speed = math.sqrt(obj.vx * obj.vx + obj.vy * obj.vy)
    -- Assuming mass proportional to radius squared
    local mass = obj.radius * obj.radius
    totalEnergy = totalEnergy + 0.5 * mass * speed * speed
  end
end
return {totalKineticEnergy = totalEnergy}
```

### Sort Objects by Distance from Point

Find objects nearest to center:

```lua
local centerX = love.graphics.getWidth() / 2
local centerY = love.graphics.getHeight() / 2
local sorted = {}

for id, obj in pairs(objects) do
  if obj.type == "ball" then
    local dx = obj.x - centerX
    local dy = obj.y - centerY
    local distance = math.sqrt(dx*dx + dy*dy)
    table.insert(sorted, {
      id = id,
      distance = distance
    })
  end
end

-- Simple bubble sort
for i = 1, #sorted do
  for j = i + 1, #sorted do
    if sorted[j].distance < sorted[i].distance then
      sorted[i], sorted[j] = sorted[j], sorted[i]
    end
  end
end

return sorted
```

## Using Dedicated Tools

### Game State & Performance

Get a comprehensive game snapshot:

```json
// get_game_state (no parameters)
// Output:
{
  "window": {"width": 800, "height": 600},
  "fps": 60,
  "objectCount": 5,
  "objects": [
    {"id": "ball_1", "type": "ball", "x": 234.5, "y": 156.2},
    {"id": "ball_2", "type": "ball", "x": 567.8, "y": 432.1}
  ],
  "version": {"major": 11, "minor": 4, "revision": 0},
  "paused": false
}
```

Quick performance check:

```json
// get_performance_stats (no parameters)
// Output:
{
  "fps": 60,
  "objectCount": 5,
  "deltaTime": 0.016,
  "time": 42.5,
  "width": 800,
  "height": 600
}
```

### Creating Objects

Add a new ball:

```json
// add_object
// Input:
{
  "type": "ball",
  "properties": {
    "x": 400, "y": 300,
    "vx": 100, "vy": -50,
    "radius": 20,
    "r": 1.0, "g": 0.0, "b": 0.0
  }
}

// Output:
{
  "object": {
    "id": "entity_6",
    "type": "ball",
    "x": 400, "y": 300,
    "vx": 100, "vy": -50,
    "radius": 20,
    "r": 1.0, "g": 0.0, "b": 0.0
  },
  "success": true
}
```

### Removing Objects

```json
// remove_object
// Input: {"id": "ball_3"}
// Output:
{
  "success": true
}
```

### Modifying Objects

Change a ball's color and speed:

```json
// modify_object
// Input:
{
  "id": "ball_1",
  "properties": {
    "r": 1.0, "g": 0.0, "b": 0.0,
    "vx": 300, "vy": 200
  }
}

// Output:
{
  "object": {
    "id": "ball_1",
    "type": "ball",
    "x": 234.5, "y": 156.2,
    "vx": 300, "vy": 200,
    "radius": 25,
    "r": 1.0, "g": 0.0, "b": 0.0
  },
  "success": true
}
```

### Pause/Resume

Pause the game to inspect state safely:

```json
// pause_game
// Input: {"paused": true}
// Output:
{
  "success": true,
  "paused": true
}
```

When paused, the game loop skips all logic but continues processing MCP commands, so you can inspect and modify freely.

### Debug Text Overlays

Add visual annotations to the game screen:

```json
// create_debug_text
// Input:
{
  "text": "Collision point",
  "x": 400, "y": 300,
  "color": {"r": 1.0, "g": 1.0, "b": 0.0}
}

// Output:
{
  "success": true
}
```

Text overlays auto-clear after 10 seconds.

### Screenshots

```json
// capture_screenshot (no parameters)
// Output:
{
  "success": true,
  "file": "/path/to/love2d/save/dir/love2d_mcp_screenshot.png",
  "filename": "love2d_mcp_screenshot.png",
  "width": 800,
  "height": 600
}
```

## Debugging Patterns

### The Pause-Inspect-Modify Loop

1. `pause_game(true)` — freeze everything
2. `get_game_state()` + `get_object("id")` — understand the state
3. `modify_object("id", {...})` — make targeted changes
4. `create_debug_text("note", x, y)` — annotate for later reference
5. `capture_screenshot()` — save visual evidence
6. `pause_game(false)` — resume and observe

This is the safest way to make complex modifications without race conditions from the game loop.

### Performance Checks

```
1. get_performance_stats() — check FPS and object count
2. If FPS is low, check for excessive object creation
3. list_objects() — see if unexpected objects exist
4. remove_object("unwanted_id") — clean up
```

## Tips

1. **Tables are returned as JSON**: When returning tables, they're automatically JSON-encoded
2. **Use standard libraries**: Access to `math`, `string`, `table`, etc.
3. **LÖVE API available**: Use `love.graphics`, `love.timer`, etc.
4. **Modify in-place**: Changes to objects persist in the game
5. **Error handling**: Syntax errors and runtime errors are reported back

## Next Steps

- Integrate MCP into your own game
- Build custom tools for your specific needs
- Experiment with AI-assisted game development
- Share your use cases and examples!
