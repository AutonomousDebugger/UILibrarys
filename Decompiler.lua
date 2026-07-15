-- GrayUI Decompiler
-- Replace the URL after GrayUI.lua is uploaded to GitHub.

local GRAY_UI_URL = "https://raw.githubusercontent.com/AutonomousDebugger/UILibrarys/refs/heads/main/GrayUI.lua"

local function loadGrayUI()
	local sharedEnvironment = type(getgenv) == "function" and getgenv() or _G
	if type(sharedEnvironment.GrayUI) == "table" then
		return sharedEnvironment.GrayUI
	end

	assert(type(loadstring) == "function", "loadstring is unavailable in this environment")
	assert(type(game.HttpGet) == "function", "game:HttpGet is unavailable in this environment")
	local source = game:HttpGet(GRAY_UI_URL)
	local chunk, compileError = loadstring(source)
	assert(chunk, compileError)

	local library = chunk()
	assert(type(library) == "table", "GrayUI.lua did not return a library table")
	sharedEnvironment.GrayUI = library
	return library
end

local GrayUI = loadGrayUI()

local Window = GrayUI:CreateWindow({
	Id = "GrayDecompiler",
	Title = "Gray Decompiler",
	Subtitle = "SCRIPT INSPECTOR",
	ReopenText = "DECOMPILER",
	Size = Vector2.new(680, 480),
	MinSize = Vector2.new(390, 310),
	MaxSize = Vector2.new(1280, 900),
})

local DecompilerPage = Window:AddTab("Decompiler")
local RuntimePage = Window:AddTab("Runtime Values")
local InformationPage = Window:AddTab("Information")

local State = {
	Target = nil,
	Closure = nil,
	Path = "",
	Source = "",
	Constants = {},
	Upvalues = {},
	Protos = {},
}

local Environment = type(getgenv) == "function" and getgenv() or _G
local Debug = type(debug) == "table" and debug or {}

local APIs = {
	Decompile = Environment.decompile or decompile,
	GetScriptClosure = Environment.getscriptclosure or Environment.getscriptfunction
		or getscriptclosure or getscriptfunction,
	GetConstants = Debug.getconstants or Environment.getconstants or getconstants,
	SetConstant = Debug.setconstant or Environment.setconstant or setconstant,
	GetUpvalues = Debug.getupvalues or Environment.getupvalues or getupvalues,
	GetUpvalue = Debug.getupvalue or Environment.getupvalue or getupvalue,
	SetUpvalue = Debug.setupvalue or Environment.setupvalue or setupvalue,
	GetProtos = Debug.getprotos or Environment.getprotos or getprotos,
	GetInfo = Debug.getinfo or Environment.getinfo or getinfo,
}

local function trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function startsWith(text, prefix)
	return text:sub(1, #prefix) == prefix
end

local function splitPath(path)
	local normalized = trim(path)
	normalized = normalized:gsub(
		"game%s*:%s*GetService%s*%(%s*['\"]([^'\"]+)['\"]%s*%)",
		"game.%1"
	)
	normalized = normalized:gsub("%[%s*['\"]([^'\"]+)['\"]%s*%]", ".%1")
	normalized = normalized:gsub("^%.*", "")
	normalized = normalized:gsub("%.*$", "")

	local parts = {}
	for part in normalized:gmatch("[^%.]+") do
		part = trim(part)
		if part ~= "" then
			table.insert(parts, part)
		end
	end
	return parts
end

local function resolvePath(path)
	local parts = splitPath(path)
	if #parts == 0 then
		return nil, "Enter a script path first."
	end

	local current
	local first = parts[1]:lower()
	local startIndex = 2

	if first == "game" then
		current = game
	elseif first == "workspace" then
		current = workspace
	else
		return nil, "Path must begin with game or workspace."
	end

	for index = startIndex, #parts do
		local name = parts[index]
		local nextObject

		if current == game then
			local serviceOk, service = pcall(game.GetService, game, name)
			if serviceOk then
				nextObject = service
			end
		end

		if not nextObject and typeof(current) == "Instance" then
			nextObject = current:FindFirstChild(name)
		end

		if not nextObject then
			return nil, string.format("Could not find '%s' in the supplied path.", name)
		end
		current = nextObject
	end

	return current
end

local function describeTarget(target)
	if typeof(target) ~= "Instance" then
		return tostring(target)
	end

	local fullName = target:GetFullName()
	return string.format("%s | %s", target.ClassName, fullName)
end

local function valueToText(value)
	local kind = typeof(value)
	if kind == "string" then
		return string.format("%q", value)
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return tostring(value)
	elseif kind == "Vector2" then
		return string.format("Vector2.new(%s, %s)", value.X, value.Y)
	elseif kind == "Vector3" then
		return string.format("Vector3.new(%s, %s, %s)", value.X, value.Y, value.Z)
	elseif kind == "Color3" then
		return string.format(
			"Color3.fromRGB(%d, %d, %d)",
			math.floor(value.R * 255 + 0.5),
			math.floor(value.G * 255 + 0.5),
			math.floor(value.B * 255 + 0.5)
		)
	elseif kind == "CFrame" then
		local components = { value:GetComponents() }
		for index, component in ipairs(components) do
			components[index] = tostring(component)
		end
		return "CFrame.new(" .. table.concat(components, ", ") .. ")"
	elseif kind == "Instance" then
		return "@" .. value:GetFullName()
	elseif kind == "EnumItem" then
		return tostring(value)
	end

	return string.format("<%s> %s", kind, tostring(value))
end

local function parseNumbers(text, constructor)
	local body = text:match("^" .. constructor:gsub("([%.%(%)])", "%%%1") .. "%((.*)%)$")
	if not body then
		return nil
	end

	local values = {}
	for piece in body:gmatch("[^,]+") do
		local number = tonumber(trim(piece))
		if number == nil then
			return nil
		end
		table.insert(values, number)
	end
	return values
end

local function parseEnum(text)
	local enumTypeName, itemName = text:match("^Enum%.([%w_]+)%.([%w_]+)$")
	if not enumTypeName then
		return nil
	end

	local enumType = Enum[enumTypeName]
	if not enumType then
		return nil
	end
	return enumType[itemName]
end

local function unquote(text)
	local quote = text:sub(1, 1)
	if (quote ~= "\"" and quote ~= "'") or text:sub(-1) ~= quote then
		return nil
	end

	local value = text:sub(2, -2)
	value = value:gsub("\\n", "\n")
	value = value:gsub("\\r", "\r")
	value = value:gsub("\\t", "\t")
	value = value:gsub("\\\"", "\"")
	value = value:gsub("\\'", "'")
	value = value:gsub("\\\\", "\\")
	return value
end

local function parseValue(text)
	text = trim(text)
	if text == "nil" then
		return true, nil
	elseif text == "true" then
		return true, true
	elseif text == "false" then
		return true, false
	end

	local number = tonumber(text)
	if number ~= nil then
		return true, number
	end

	local quoted = unquote(text)
	if quoted ~= nil then
		return true, quoted
	end

	local vector2 = parseNumbers(text, "Vector2.new")
	if vector2 and #vector2 == 2 then
		return true, Vector2.new(vector2[1], vector2[2])
	end

	local vector3 = parseNumbers(text, "Vector3.new")
	if vector3 and #vector3 == 3 then
		return true, Vector3.new(vector3[1], vector3[2], vector3[3])
	end

	local color = parseNumbers(text, "Color3.fromRGB")
	if color and #color == 3 then
		return true, Color3.fromRGB(color[1], color[2], color[3])
	end

	local cframe = parseNumbers(text, "CFrame.new")
	if cframe and (#cframe == 3 or #cframe == 12) then
		return true, CFrame.new(table.unpack(cframe))
	end

	local enumItem = parseEnum(text)
	if enumItem then
		return true, enumItem
	end

	if startsWith(text, "@") then
		local instance, pathError = resolvePath(text:sub(2))
		if instance then
			return true, instance
		end
		return false, pathError
	end

	return false, "Use nil, a number, true/false, a quoted string, Vector2, Vector3, Color3, CFrame, Enum, or @instance path."
end

local TargetSection = DecompilerPage:AddSection("Target")
TargetSection:AddLabel({
	Text = "Supports game.Service.Folder.Script, workspace.Folder.Script, bracket names, and game:GetService(\"Service\").Script.",
})

local PathInput = TargetSection:AddTextbox({
	Text = "Script path",
	Placeholder = "game.StarterPlayer.StarterPlayerScripts.RbxCharacterSounds",
	Code = true,
})

local TargetStatus = TargetSection:AddLabel({
	Text = "No target selected.",
	Color = GrayUI.Theme.Muted,
})

local SourceSection = DecompilerPage:AddSection("Pseudocode")
local SourceEditor = SourceSection:AddTextArea({
	Text = "Decompiler output (editable copy)",
	Placeholder = "Decompiler output appears here.",
	Height = 285,
	Code = true,
	Wrap = false,
})

local RuntimeStatus
local ConstantsSection
local UpvaluesSection
local ProtosSection

local function findClosure(target)
	if type(target) == "function" then
		return target
	end
	if typeof(target) ~= "Instance" then
		return nil, "Runtime inspection requires a resolved script instance or function."
	end
	if type(APIs.GetScriptClosure) ~= "function" then
		return nil, "getscriptclosure/getscriptfunction is unavailable. Decompiling still works."
	end

	local ok, closure = pcall(APIs.GetScriptClosure, target)
	if not ok or type(closure) ~= "function" then
		return nil, ok and "No script closure was returned." or tostring(closure)
	end
	return closure
end

local function safeList(api, closure)
	if type(api) ~= "function" then
		return {}
	end
	local ok, result = pcall(api, closure)
	if not ok or type(result) ~= "table" then
		return {}
	end
	return result
end

local function getUpvalueName(closure, index)
	if type(APIs.GetUpvalue) ~= "function" then
		return "upvalue"
	end
	local ok, first = pcall(APIs.GetUpvalue, closure, index)
	if ok and type(first) == "string" and first ~= "" then
		return first
	end
	return "upvalue"
end

local function addEditableValue(section, kind, index, name, value, applyFunction)
	local typeName = typeof(value)
	local title = string.format("%s #%s · %s · %s", kind, tostring(index), name or "value", typeName)
	local input = section:AddTextbox({
		Text = title,
		Default = valueToText(value),
		Code = true,
		Height = 62,
	})

	section:AddButton({
		Text = string.format("Apply %s #%s", kind, tostring(index)),
		Callback = function()
			local parsed, newValue = parseValue(input:Get())
			if not parsed then
				Window:Notify(newValue, "error", 4)
				return
			end

			local ok, result = pcall(applyFunction, index, newValue)
			if ok then
				Window:Notify(string.format("%s #%s updated.", kind, tostring(index)), "success")
			else
				Window:Notify("Update failed: " .. tostring(result), "error", 4)
			end
		end,
	})
end

local function refreshRuntime()
	ConstantsSection:Clear()
	UpvaluesSection:Clear()
	ProtosSection:Clear()

	if not State.Target then
		RuntimeStatus:Set("Decompile a resolved script path first.")
		RuntimeStatus:SetColor(GrayUI.Theme.Danger)
		return
	end

	local closure, closureError = findClosure(State.Target)
	State.Closure = closure
	if not closure then
		RuntimeStatus:Set(closureError)
		RuntimeStatus:SetColor(GrayUI.Theme.Danger)
		return
	end

	State.Constants = safeList(APIs.GetConstants, closure)
	State.Upvalues = safeList(APIs.GetUpvalues, closure)
	State.Protos = safeList(APIs.GetProtos, closure)

	local message = string.format(
		"Loaded %d constants, %d upvalues, and %d nested prototypes.",
		#State.Constants,
		#State.Upvalues,
		#State.Protos
	)
	RuntimeStatus:Set(message)
	RuntimeStatus:SetColor(GrayUI.Theme.Success)

	if #State.Constants == 0 then
		ConstantsSection:AddLabel("No constants returned, or getconstants is unavailable.")
	else
		for index, value in ipairs(State.Constants) do
			addEditableValue(ConstantsSection, "Constant", index, "constant", value, function(itemIndex, newValue)
				assert(type(APIs.SetConstant) == "function", "setconstant is unavailable")
				return APIs.SetConstant(closure, itemIndex, newValue)
			end)
		end
	end

	if #State.Upvalues == 0 then
		UpvaluesSection:AddLabel("No upvalues returned, or getupvalues is unavailable.")
	else
		for index, value in ipairs(State.Upvalues) do
			local upvalueName = getUpvalueName(closure, index)
			addEditableValue(UpvaluesSection, "Upvalue", index, upvalueName, value, function(itemIndex, newValue)
				assert(type(APIs.SetUpvalue) == "function", "setupvalue is unavailable")
				return APIs.SetUpvalue(closure, itemIndex, newValue)
			end)
		end
	end

	if #State.Protos == 0 then
		ProtosSection:AddLabel("No nested prototypes returned, or getprotos is unavailable.")
	else
		for index, proto in ipairs(State.Protos) do
			local details = "function"
			if type(APIs.GetInfo) == "function" then
				local ok, info = pcall(APIs.GetInfo, proto)
				if ok and type(info) == "table" then
					details = string.format(
						"%s | source: %s | line: %s",
						tostring(info.name or "anonymous"),
						tostring(info.source or "unknown"),
						tostring(info.currentline or info.linedefined or "?")
					)
				end
			end
			ProtosSection:AddLabel(string.format("Prototype #%d · %s", index, details))
		end
	end
end

local function decompileTarget()
	if type(APIs.Decompile) ~= "function" then
		Window:Notify("decompile() is unavailable in this environment.", "error", 4)
		return
	end

	local path = trim(PathInput:Get())
	if path == "" then
		Window:Notify("Enter a script path first.", "error")
		return
	end

	State.Path = path
	local resolved, resolveError = resolvePath(path)
	State.Target = resolved

	local decompileInput = resolved or path
	TargetStatus:Set(resolved and describeTarget(resolved) or ("String target · " .. resolveError))
	TargetStatus:SetColor(resolved and GrayUI.Theme.Success or GrayUI.Theme.Muted)

	SourceEditor:Set("Decompiling…")
	local ok, result = pcall(APIs.Decompile, decompileInput)
	if not ok then
		State.Source = ""
		SourceEditor:Set("-- Decompilation failed\n-- " .. tostring(result))
		Window:Notify("Decompilation failed.", "error", 4)
		return
	end

	State.Source = tostring(result or "")
	SourceEditor:Set(State.Source)
	Window:Notify("Decompilation complete.", "success")
	refreshRuntime()
end

TargetSection:AddButton({
	Text = "Decompile Path",
	Callback = decompileTarget,
})

TargetSection:AddButton({
	Text = "Paste Clipboard Path",
	Callback = function()
		if type(getclipboard) ~= "function" then
			Window:Notify("getclipboard is unavailable. Paste directly into the path box instead.", "error", 4)
			return
		end

		local ok, clipboardText = pcall(getclipboard)
		if not ok or type(clipboardText) ~= "string" or trim(clipboardText) == "" then
			Window:Notify("The clipboard did not contain a path.", "error")
			return
		end

		PathInput:Set(trim(clipboardText))
		Window:Notify("Path pasted from clipboard.", "success")
	end,
})

TargetSection:AddButton({
	Text = "Resolve Path Only",
	Callback = function()
		local target, resolveError = resolvePath(PathInput:Get())
		if not target then
			State.Target = nil
			TargetStatus:Set(resolveError)
			TargetStatus:SetColor(GrayUI.Theme.Danger)
			return
		end

		State.Target = target
		State.Path = trim(PathInput:Get())
		TargetStatus:Set(describeTarget(target))
		TargetStatus:SetColor(GrayUI.Theme.Success)
		Window:Notify("Script path resolved.", "success")
	end,
})

SourceSection:AddButton({
	Text = "Copy Current Text",
	Callback = function()
		if type(setclipboard) ~= "function" then
			Window:Notify("setclipboard is unavailable.", "error")
			return
		end
		setclipboard(SourceEditor:Get())
		Window:Notify("Current editor text copied.", "success")
	end,
})

SourceSection:AddLabel({
	Text = "Editing the pseudocode box changes only your copy. Use Runtime Values to apply supported constant or upvalue changes to the live closure.",
})

local RuntimeControlSection = RuntimePage:AddSection("Inspector")
RuntimeStatus = RuntimeControlSection:AddLabel({
	Text = "Decompile a resolved script path first.",
})
RuntimeControlSection:AddButton({
	Text = "Refresh Constants, Upvalues, and Prototypes",
	Callback = refreshRuntime,
})
RuntimeControlSection:AddLabel({
	Text = "Editable types: nil, numbers, booleans, quoted strings, Vector2, Vector3, Color3, CFrame, Enum items, and @instance paths.",
})

ConstantsSection = RuntimePage:AddSection("Constants")
ConstantsSection:AddLabel("Constants will appear after inspection.")

UpvaluesSection = RuntimePage:AddSection("Upvalues")
UpvaluesSection:AddLabel("Upvalues will appear after inspection.")

ProtosSection = RuntimePage:AddSection("Nested Prototypes")
ProtosSection:AddLabel("Prototype information will appear after inspection.")

local APISection = InformationPage:AddSection("Detected APIs")

local function apiStatus(name, api, requiredFor)
	local available = type(api) == "function"
	APISection:AddLabel({
		Text = string.format(
			"%s · %s · %s",
			name,
			available and "available" or "unavailable",
			requiredFor
		),
		Color = available and GrayUI.Theme.Success or GrayUI.Theme.Danger,
	})
end

apiStatus("decompile", APIs.Decompile, "pseudocode")
apiStatus("getscriptclosure/getscriptfunction", APIs.GetScriptClosure, "runtime closure")
apiStatus("getconstants", APIs.GetConstants, "constant list")
apiStatus("setconstant", APIs.SetConstant, "constant editing")
apiStatus("getupvalues", APIs.GetUpvalues, "upvalue list")
apiStatus("setupvalue", APIs.SetUpvalue, "upvalue editing")
apiStatus("getprotos", APIs.GetProtos, "nested functions")
apiStatus("getinfo", APIs.GetInfo, "function metadata")

local NotesSection = InformationPage:AddSection("Behavior")
NotesSection:AddLabel({
	Text = "The app never invents decompiled output. If decompile() fails, its real error is shown. Runtime editing is enabled only when the matching setter API exists.",
})
NotesSection:AddLabel({
	Text = "A decompiler produces pseudocode and may not recover original names, comments, formatting, or every optimized expression.",
})
