# GrayUI Decompiler

A compact black-and-gray Roblox GUI library and script inspector.

## Files

- `GrayUI.lua` — reusable window library.
- `Decompiler.lua` — decompiler and runtime-value inspector using `GrayUI.lua`.

## Decompiler loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/AutonomousDebugger/UILibrarys/refs/heads/main/Decompiler.lua"))()
```

The environment must provide `decompile()`. Constants, upvalues, and nested
prototype inspection activate only when the matching debug APIs are available.
Runtime setters are never simulated.

## Minimal library example

```lua
local GrayUI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/AutonomousDebugger/UILibrarys/refs/heads/main/GrayUI.lua"
))()

local Window = GrayUI:CreateWindow({
	Title = "My Window",
	Size = Vector2.new(620, 430),
	MinSize = Vector2.new(390, 310),
})

local Main = Window:AddTab("Main")
local Section = Main:AddSection("Controls")

Section:AddButton({
	Text = "Run",
	Callback = function()
		print("Run")
	end,
})

Section:AddToggle({
	Text = "Enabled",
	Default = false,
	Callback = function(enabled)
		print(enabled)
	end,
})
```

Windows support mouse and touch dragging, bottom-right resizing, animated hide,
and a draggable reopen button. Closing a window keeps its current state.
