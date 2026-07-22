-- DecoderCore - remote capture, stacking, serialization, and replay
-- No GUI code belongs in this file.

local DecoderCore = {
	Version = "2.2.0",
}

local Environment = type(getgenv) == "function" and getgenv() or _G

local function ResolveApi(...)
	for Index = 1, select("#", ...) do
		local Name = select(Index, ...)
		local Value = rawget(Environment, Name) or rawget(_G, Name)
		if type(Value) == "function" then
			return Value, Name
		end
	end
	return nil, nil
end

-- Potassium exposes these as executor globals. Read them directly first because
-- some builds expose callable globals without making them enumerable in getgenv().
local HookMetamethod = hookmetamethod or ResolveApi("hookmetamethod")
local HookMetamethodName = type(HookMetamethod) == "function" and "hookmetamethod" or nil
local GetNamecallMethod = getnamecallmethod or ResolveApi("getnamecallmethod")
local GetNamecallName = type(GetNamecallMethod) == "function" and "getnamecallmethod" or nil
local HookFunction = hookfunction or ResolveApi("hookfunction")
local HookFunctionName = type(HookFunction) == "function" and "hookfunction" or nil
local GetCallingScript = getcallingscript or ResolveApi("getcallingscript")
local GetCallingScriptName = type(GetCallingScript) == "function" and "getcallingscript" or nil
local NewCClosure = newcclosure or ResolveApi("newcclosure") or function(Callback)
	return Callback
end

local State = {
	Active = false,
	CaptureOutgoing = true,
	CaptureIncoming = true,
	Connections = {},
	Listeners = {},
	Outgoing = {},
	Incoming = {},
	OutgoingCalls = 0,
	IncomingCalls = 0,
	ObservedRemotes = setmetatable({}, { __mode = "k" }),
	HookedInvokeCallbacks = setmetatable({}, { __mode = "k" }),
}
DecoderCore.State = State

local PreviousNamecallBus = rawget(Environment, "__DecoderCoreNamecallBus")
local NamecallBus = PreviousNamecallBus
if type(NamecallBus) == "table" and NamecallBus.Version ~= 3 then
	-- Older Decoder hooks scheduled live Instances with task.defer. Their hook
	-- closure reads this field dynamically, so clearing it safely retires them.
	NamecallBus.Callback = nil
	NamecallBus = nil
end
if type(NamecallBus) ~= "table" then
	NamecallBus = {
		Version = 3,
		Installed = false,
		Callback = nil,
		OldNamecall = nil,
		Depth = setmetatable({}, { __mode = "k" }),
	}
	Environment.__DecoderCoreNamecallBus = NamecallBus
end

local PreviousMethodBus = rawget(Environment, "__DecoderCoreMethodBus")
local MethodBus = PreviousMethodBus
if type(MethodBus) == "table" and MethodBus.Version ~= 2 then
	MethodBus.Callback = nil
	MethodBus = nil
end
if type(MethodBus) ~= "table" then
	MethodBus = {
		Version = 2,
		Installed = false,
		Callback = nil,
		OldFireServer = nil,
		OldInvokeServer = nil,
	}
	Environment.__DecoderCoreMethodBus = MethodBus
end

local function CurrentThread()
	return coroutine.running() or NamecallBus
end

local function EnterNamecall()
	local Thread = CurrentThread()
	NamecallBus.Depth[Thread] = (NamecallBus.Depth[Thread] or 0) + 1
	return Thread
end

local function LeaveNamecall(Thread)
	local Depth = (NamecallBus.Depth[Thread] or 1) - 1
	NamecallBus.Depth[Thread] = Depth > 0 and Depth or nil
end

local function InstallNamecallHook()
	if NamecallBus.Installed then
		return true, "already installed"
	end
	if not HookMetamethod or not GetNamecallMethod then
		return false, "hookmetamethod/getnamecallmethod unavailable"
	end

	local OldNamecall
	OldNamecall = HookMetamethod(game, "__namecall", NewCClosure(function(Self, ...)
		local Method = GetNamecallMethod()
		local LowerMethod = type(Method) == "string" and string.lower(Method) or ""
		local ClassName = typeof(Self) == "Instance" and Self.ClassName or ""
		local IsFire = LowerMethod == "fireserver" and ClassName == "RemoteEvent"
		local IsInvoke = LowerMethod == "invokeserver" and ClassName == "RemoteFunction"

		if not IsFire and not IsInvoke then
			return OldNamecall(Self, ...)
		end

		local Arguments = table.pack(...)
		local CanonicalMethod = IsFire and "FireServer" or "InvokeServer"
		local CallingScript
		if GetCallingScript then
			local CallingSuccess, CallingResult = pcall(GetCallingScript)
			CallingScript = CallingSuccess and CallingResult or nil
		end

		-- Forward the untouched call before doing any path/GUI work. Formatting an
		-- Instance can perform nested namecalls, which must never happen while the
		-- executor is still preparing to forward FireServer/InvokeServer.
		local Thread = EnterNamecall()
		local Results = table.pack(OldNamecall(Self, table.unpack(Arguments, 1, Arguments.n)))
		LeaveNamecall(Thread)
		if NamecallBus.Callback then
			-- Keep live Instances on this capability-bearing hook thread.
			pcall(NamecallBus.Callback, Self, CanonicalMethod, Arguments, IsInvoke and Results or nil, "__namecall", CallingScript)
		end
		return table.unpack(Results, 1, Results.n)
	end))

	NamecallBus.OldNamecall = OldNamecall
	NamecallBus.Installed = true
	return true, HookMetamethodName .. "/" .. GetNamecallName
end

local function Quote(Value)
	return string.format("%q", tostring(Value))
end

local ReservedWords = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
}

local function IsIdentifier(Value)
	return type(Value) == "string"
		and Value:match("^[%a_][%w_]*$") ~= nil
		and not ReservedWords[Value]
end

local function ChildExpression(ParentExpression, Object)
	local Parent = Object.Parent
	if Parent then
		local Children = Parent:GetChildren()
		local SameNameCount = 0
		local ObjectIndex
		for Index, Child in ipairs(Children) do
			if Child.Name == Object.Name then
				SameNameCount = SameNameCount + 1
			end
			if Child == Object then
				ObjectIndex = Index
			end
		end
		if SameNameCount > 1 and ObjectIndex then
			return ParentExpression .. ":GetChildren()[" .. tostring(ObjectIndex) .. "]"
		end
	end
	if IsIdentifier(Object.Name) then
		return ParentExpression .. "." .. Object.Name
	end
	return ParentExpression .. "[" .. Quote(Object.Name) .. "]"
end

function DecoderCore.GetInstancePath(Object)
	if typeof(Object) ~= "Instance" then
		return "nil --[[not an Instance]]"
	end
	local Chain = {}
	local Current = Object
	while Current and Current ~= game do
		table.insert(Chain, 1, Current)
		Current = Current.Parent
	end
	if Current ~= game then
		return "nil --[[instance is no longer parented to game]]"
	end

	local Expression = "game"
	for Index, Item in ipairs(Chain) do
		if Index == 1 then
			if Item == workspace then
				Expression = "workspace"
			else
				local Success, Service = pcall(game.GetService, game, Item.Name)
				if Success and Service == Item then
				Expression = "game:GetService(" .. Quote(Item.Name) .. ")"
				else
					Expression = ChildExpression(Expression, Item)
				end
			end
		else
			Expression = ChildExpression(Expression, Item)
		end
	end
	return Expression
end

local function DisplayPath(Object)
	local Success, Result = pcall(function()
		return Object:GetFullName()
	end)
	return Success and Result or tostring(Object)
end

local function SerializeBuffer(Value)
	local Length = buffer.len(Value)
	local Lines = {
		"(function()",
		string.format("\tlocal Value = buffer.create(%d)", Length),
	}
	for Offset = 0, Length - 1 do
		table.insert(Lines, string.format("\tbuffer.writeu8(Value, %d, %d)", Offset, buffer.readu8(Value, Offset)))
	end
	table.insert(Lines, "\treturn Value")
	table.insert(Lines, "end)()")
	return table.concat(Lines, "\n")
end

function DecoderCore.Serialize(Value, Depth, Seen)
	Depth = Depth or 0
	Seen = Seen or {}
	local ValueType = typeof(Value)

	if Value == nil then
		return "nil"
	elseif ValueType == "string" then
		return Quote(Value)
	elseif ValueType == "number" then
		if Value ~= Value then
			return "0 / 0"
		elseif Value == math.huge then
			return "math.huge"
		elseif Value == -math.huge then
			return "-math.huge"
		end
		return tostring(Value)
	elseif ValueType == "boolean" then
		return tostring(Value)
	elseif ValueType == "Instance" then
		return DecoderCore.GetInstancePath(Value)
	elseif ValueType == "EnumItem" then
		return tostring(Value)
	elseif ValueType == "Vector2" then
		return string.format("Vector2.new(%s, %s)", Value.X, Value.Y)
	elseif ValueType == "Vector3" then
		return string.format("Vector3.new(%s, %s, %s)", Value.X, Value.Y, Value.Z)
	elseif ValueType == "Color3" then
		return string.format("Color3.new(%s, %s, %s)", Value.R, Value.G, Value.B)
	elseif ValueType == "BrickColor" then
		return "BrickColor.new(" .. Quote(Value.Name) .. ")"
	elseif ValueType == "CFrame" then
		local Components = { Value:GetComponents() }
		for Index, Component in ipairs(Components) do
			Components[Index] = tostring(Component)
		end
		return "CFrame.new(" .. table.concat(Components, ", ") .. ")"
	elseif ValueType == "UDim" then
		return string.format("UDim.new(%s, %s)", Value.Scale, Value.Offset)
	elseif ValueType == "UDim2" then
		return string.format("UDim2.new(%s, %s, %s, %s)", Value.X.Scale, Value.X.Offset, Value.Y.Scale, Value.Y.Offset)
	elseif ValueType == "Rect" then
		return string.format("Rect.new(%s, %s, %s, %s)", Value.Min.X, Value.Min.Y, Value.Max.X, Value.Max.Y)
	elseif ValueType == "NumberRange" then
		return string.format("NumberRange.new(%s, %s)", Value.Min, Value.Max)
	elseif ValueType == "buffer" then
		return SerializeBuffer(Value)
	elseif ValueType ~= "table" then
		return "nil --[[unsupported " .. ValueType .. ": " .. tostring(Value) .. "]]"
	end

	if Seen[Value] then
		return "nil --[[circular table]]"
	elseif Depth >= 12 then
		return "nil --[[table depth limit]]"
	end
	Seen[Value] = true

	local Keys = {}
	for Key in pairs(Value) do
		table.insert(Keys, Key)
	end
	table.sort(Keys, function(A, B)
		if typeof(A) == typeof(B) then
			return tostring(A) < tostring(B)
		end
		return typeof(A) < typeof(B)
	end)

	local Lines = { "{" }
	for _, Key in ipairs(Keys) do
		local KeyText
		if type(Key) == "string" and IsIdentifier(Key) then
			KeyText = Key
		else
			KeyText = "[" .. DecoderCore.Serialize(Key, Depth + 1, Seen) .. "]"
		end
		local ValueText = DecoderCore.Serialize(Value[Key], Depth + 1, Seen)
		table.insert(Lines, string.rep("    ", Depth + 1) .. KeyText .. " = " .. ValueText .. ",")
	end
	table.insert(Lines, string.rep("    ", Depth) .. "}")
	Seen[Value] = nil
	return table.concat(Lines, "\n")
end

function DecoderCore.SerializeArguments(Arguments, VariableName)
	local Lines = { "local " .. tostring(VariableName or "args") .. " = table.pack(" }
	local Count = Arguments.n or #Arguments
	for Index = 1, Count do
		local Suffix = Index < Count and "," or ""
		local Text = DecoderCore.Serialize(Arguments[Index], 1, {})
		table.insert(Lines, "    " .. Text .. Suffix)
	end
	table.insert(Lines, ")")
	return table.concat(Lines, "\n")
end

function DecoderCore.BuildOutgoingPacket(Entry)
	local CallingScriptText = Entry.CallingScript and DecoderCore.GetInstancePath(Entry.CallingScript) or "Unknown"
	local Lines = {
		"-- Calling Script: " .. CallingScriptText,
		"-- Captured: x" .. tostring(Entry.Count) .. " via " .. tostring(Entry.Source),
		"local Event = " .. DecoderCore.GetInstancePath(Entry.Remote),
		"Event:" .. Entry.Method .. "(",
	}
	local Count = Entry.Arguments.n or #Entry.Arguments
	for Index = 1, Count do
		local Suffix = Index < Count and "," or ""
		local ValueText = DecoderCore.Serialize(Entry.Arguments[Index], 1, {})
		table.insert(Lines, "    " .. ValueText .. Suffix)
	end
	table.insert(Lines, ")")
	return table.concat(Lines, "\n")
end

function DecoderCore.BuildIncomingText(Entry)
	local Lines = {
		"-- Decoder incoming capture",
		"-- Remote: " .. Entry.Path,
		"-- Signal: " .. Entry.Method,
		"-- Captured: x" .. tostring(Entry.Count),
		DecoderCore.SerializeArguments(Entry.Arguments, "args"),
	}
	if Entry.Results then
		table.insert(Lines, "")
		table.insert(Lines, "-- Returned values")
		table.insert(Lines, DecoderCore.SerializeArguments(Entry.Results, "results"))
	end
	return table.concat(Lines, "\n")
end

local function StoreCount(Store)
	local Count = 0
	for _, Methods in pairs(Store) do
		for _ in pairs(Methods) do
			Count = Count + 1
		end
	end
	return Count
end

local function Emit(Entry, IsNew)
	for Listener in pairs(State.Listeners) do
		-- Listeners must run before this capability-bearing thread returns.
		pcall(Listener, Entry, IsNew)
	end
end

function DecoderCore.Record(Direction, Remote, Method, Arguments, Results, Source, CallingScript)
	if not State.Active then
		return
	end
	if Direction == "Outgoing" and not State.CaptureOutgoing then
		return
	elseif Direction == "Incoming" and not State.CaptureIncoming then
		return
	end
	if typeof(Remote) ~= "Instance" then
		return
	end

	local Store = Direction == "Outgoing" and State.Outgoing or State.Incoming
	local Methods = Store[Remote]
	if not Methods then
		Methods = {}
		Store[Remote] = Methods
	end

	local Entry = Methods[Method]
	local IsNew = Entry == nil
	if IsNew then
		Entry = {
			Direction = Direction,
			Remote = Remote,
			Path = DisplayPath(Remote),
			Method = Method,
			Count = 0,
		}
		Methods[Method] = Entry
	end
	Entry.Count = Entry.Count + 1
	Entry.Arguments = Arguments
	Entry.Results = Results
	Entry.Source = Source
	Entry.CallingScript = CallingScript
	Entry.LastClock = os.clock()
	Entry.UniqueCount = StoreCount(Store)
	if Direction == "Outgoing" then
		State.OutgoingCalls = State.OutgoingCalls + 1
	else
		State.IncomingCalls = State.IncomingCalls + 1
	end
	Emit(Entry, IsNew)
end

local function OutgoingCallback(Remote, Method, Arguments, Results, Source, CallingScript)
	DecoderCore.Record("Outgoing", Remote, Method, Arguments, Results, Source, CallingScript)
end
NamecallBus.Callback = OutgoingCallback
-- Namecall-only outgoing capture is intentional. Layering a FireServer
-- hookfunction hook can double-observe or disturb executor forwarding.
MethodBus.Callback = nil

function DecoderCore.OnTraffic(Callback)
	assert(type(Callback) == "function", "OnTraffic callback must be a function")
	State.Listeners[Callback] = true
	return function()
		State.Listeners[Callback] = nil
	end
end

local function ObserveRemoteEvent(Remote)
	if State.ObservedRemotes[Remote] then
		return
	end
	State.ObservedRemotes[Remote] = true
	local Success, Connection = pcall(function()
		return Remote.OnClientEvent:Connect(function(...)
			DecoderCore.Record("Incoming", Remote, "OnClientEvent", table.pack(...), nil, "OnClientEvent")
		end)
	end)
	if Success and Connection then
		table.insert(State.Connections, Connection)
	end
end

local function HookRemoteFunctionCallback(Remote)
	if not HookFunction then
		return
	end
	local ReadSuccess, Callback = pcall(function()
		return Remote.OnClientInvoke
	end)
	if not ReadSuccess then
		return
	end
	if type(Callback) ~= "function" or State.HookedInvokeCallbacks[Callback] then
		return
	end

	local OldCallback
	local Success, Result = pcall(function()
		OldCallback = HookFunction(Callback, function(...)
			local Arguments = table.pack(...)
			local Results = table.pack(OldCallback(table.unpack(Arguments, 1, Arguments.n)))
			pcall(DecoderCore.Record, "Incoming", Remote, "OnClientInvoke", Arguments, Results, "OnClientInvoke")
			return table.unpack(Results, 1, Results.n)
		end)
		return OldCallback
	end)
	if Success and type(Result) == "function" then
		State.HookedInvokeCallbacks[Callback] = true
	end
end

local function ObserveRemoteFunction(Remote)
	if State.ObservedRemotes[Remote] then
		return
	end
	State.ObservedRemotes[Remote] = true

	-- Watch for games that assign OnClientInvoke after Decoder starts. This
	-- keeps the work on an engine callback instead of a capability-losing task.
	local WatchSuccess, Connection = pcall(function()
		return Remote:GetPropertyChangedSignal("OnClientInvoke"):Connect(function()
			HookRemoteFunctionCallback(Remote)
		end)
	end)
	if WatchSuccess and Connection then
		table.insert(State.Connections, Connection)
	end
	HookRemoteFunctionCallback(Remote)
end

local function Observe(Object)
	if typeof(Object) ~= "Instance" then
		return
	end
	if Object.ClassName == "RemoteEvent" then
		ObserveRemoteEvent(Object)
	elseif Object.ClassName == "RemoteFunction" then
		ObserveRemoteFunction(Object)
	end
end

function DecoderCore.Start()
	if State.Active then
		return true
	end
	local Previous = rawget(Environment, "__DecoderCoreRuntime")
	if type(Previous) == "table" and Previous ~= DecoderCore and type(Previous.Stop) == "function" then
		pcall(Previous.Stop, Previous)
	end
	Environment.__DecoderCoreRuntime = DecoderCore
	NamecallBus.Callback = OutgoingCallback
	MethodBus.Callback = nil
	State.Active = true

	local NamecallCallOk, NamecallInstalled, NamecallDetails = pcall(InstallNamecallHook)
	State.NamecallReady = NamecallCallOk and NamecallInstalled == true
	State.NamecallStatus = NamecallCallOk and tostring(NamecallDetails) or tostring(NamecallInstalled)

	State.MethodHooksReady = false
	State.MethodHooksStatus = "disabled (namecall-only mode)"

	for _, Object in ipairs(game:GetDescendants()) do
		pcall(Observe, Object)
	end
	table.insert(State.Connections, game.DescendantAdded:Connect(function(Object)
		pcall(Observe, Object)
	end))
	return State.NamecallReady
end

function DecoderCore.Stop()
	State.Active = false
	if NamecallBus.Callback then
		NamecallBus.Callback = nil
	end
	if MethodBus.Callback then
		MethodBus.Callback = nil
	end
	for _, Connection in ipairs(State.Connections) do
		pcall(function()
			Connection:Disconnect()
		end)
	end
	table.clear(State.Connections)
end

function DecoderCore.Clear(Direction)
	if Direction == "Outgoing" then
		table.clear(State.Outgoing)
		State.OutgoingCalls = 0
	elseif Direction == "Incoming" then
		table.clear(State.Incoming)
		State.IncomingCalls = 0
	end
end

function DecoderCore.Fire(Entry)
	assert(type(Entry) == "table" and typeof(Entry.Remote) == "Instance", "invalid Decoder entry")
	if Entry.Method == "InvokeServer" then
		return table.pack(Entry.Remote:InvokeServer(table.unpack(Entry.Arguments, 1, Entry.Arguments.n)))
	end
	Entry.Remote:FireServer(table.unpack(Entry.Arguments, 1, Entry.Arguments.n))
	return table.pack(true)
end

function DecoderCore.GetApiStatus()
	return {
		NamecallReady = State.NamecallReady == true,
		NamecallStatus = State.NamecallStatus or "not started",
		MethodHooksReady = State.MethodHooksReady == true,
		MethodHooksStatus = State.MethodHooksStatus or "not started",
		HookFunction = HookFunctionName or "unavailable",
		GetCallingScript = GetCallingScriptName or "unavailable",
	}
end

return DecoderCore
