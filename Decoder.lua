-- Decoder - outgoing/incoming Roblox remote traffic viewer
-- Shared GUI: AutonomousDebugger/UILibrarys/GrayUI.lua

local GRAY_UI_URL = "https://raw.githubusercontent.com/AutonomousDebugger/UILibrarys/refs/heads/main/GrayUI.lua"

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

local function LoadGrayUI()
	assert(type(loadstring) == "function", "loadstring is unavailable")
	local Source = game:HttpGet(GRAY_UI_URL)
	local Chunk, CompileError = loadstring(Source)
	assert(Chunk, CompileError)
	local Library = Chunk()
	assert(type(Library) == "table", "GrayUI.lua did not return a library")
	Environment.GrayUI = Library
	return Library
end

local GrayUI = LoadGrayUI()
local SetClipboard, ClipboardName = ResolveApi("settoclipboard", "setclipboard", "toclipboard", "setrbxclipboard")
local HookMetamethod, HookName = ResolveApi("hookmetamethod")
local GetNamecallMethod = ResolveApi("getnamecallmethod")
local NewCClosure = ResolveApi("newcclosure") or function(Callback)
	return Callback
end
local HookFunction, HookFunctionName = ResolveApi("hookfunction")

local Window = GrayUI:CreateWindow({
	Id = "GrayDecoder",
	Title = "Decoder",
	Subtitle = "REMOTE TRAFFIC",
	ReopenText = "DECODER",
	Size = Vector2.new(760, 535),
	MinSize = Vector2.new(420, 330),
	MaxSize = Vector2.new(1350, 950),
})

local OutgoingPage = Window:AddTab("Outgoing")
local IncomingPage = Window:AddTab("Incoming")
local InformationPage = Window:AddTab("Information")

local OutgoingList = OutgoingPage:AddSection("Outgoing Traffic")
local OutgoingStatus = OutgoingList:AddLabel({
	Text = "Waiting for FireServer or InvokeServer traffic.",
	Color = GrayUI.Theme.Muted,
})

local OutgoingNotepad = OutgoingPage:AddSection("Packet Notepad")
local OutgoingEditor = OutgoingNotepad:AddTextArea({
	Text = "Latest selected outgoing packet",
	Default = "-- Select an outgoing remote.",
	Height = 290,
	Code = true,
	Wrap = false,
})
OutgoingEditor:SetEditable(true)

local IncomingList = IncomingPage:AddSection("Incoming Traffic")
local IncomingStatus = IncomingList:AddLabel({
	Text = "Waiting for OnClientEvent or OnClientInvoke traffic.",
	Color = GrayUI.Theme.Muted,
})

local IncomingNotepad = IncomingPage:AddSection("Arguments Notepad")
local IncomingEditor = IncomingNotepad:AddTextArea({
	Text = "Latest selected incoming arguments",
	Default = "-- Select an incoming remote.",
	Height = 290,
	Code = true,
	Wrap = false,
})
IncomingEditor:SetEditable(true)

local Runtime = {
	Active = true,
	CaptureOutgoing = true,
	CaptureIncoming = true,
	Connections = {},
	Outgoing = {},
	Incoming = {},
	OutgoingCount = 0,
	IncomingCount = 0,
	SelectedOutgoing = nil,
	SelectedIncoming = nil,
	ObservedRemotes = setmetatable({}, { __mode = "k" }),
	HookedInvokeCallbacks = setmetatable({}, { __mode = "k" }),
	Window = Window,
}

local Bus = rawget(Environment, "__DecoderNamecallBus")
if type(Bus) ~= "table" then
	Bus = {
		HookInstalled = false,
		Callback = nil,
		OldNamecall = nil,
	}
	Environment.__DecoderNamecallBus = Bus
end

if Bus.Runtime and Bus.Runtime ~= Runtime then
	Bus.Runtime.Active = false
	for _, Connection in ipairs(Bus.Runtime.Connections or {}) do
		pcall(function()
			Connection:Disconnect()
		end)
	end
	if Bus.Runtime.Window then
		pcall(function()
			Bus.Runtime.Window:Destroy()
		end)
	end
end
Bus.Runtime = Runtime

local function Quote(Value)
	return string.format("%q", tostring(Value))
end

local function GetInstancePath(Object)
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
		return "nil --[[instance is no longer parented to game: " .. tostring(Object) .. "]]"
	end

	local Expression = "game"
	for Index, Item in ipairs(Chain) do
		if Index == 1 then
			local Success, Service = pcall(game.GetService, game, Item.Name)
			if Success and Service == Item then
				Expression = "game:GetService(" .. Quote(Item.Name) .. ")"
			else
				Expression = Expression .. "[" .. Quote(Item.Name) .. "]"
			end
		else
			Expression = Expression .. "[" .. Quote(Item.Name) .. "]"
		end
	end
	return Expression
end

local function GetDisplayPath(Object)
	local Success, FullName = pcall(function()
		return Object:GetFullName()
	end)
	return Success and FullName or tostring(Object)
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

local function Serialize(Value, Depth, Seen)
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
		return GetInstancePath(Value)
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
		return string.format(
			"UDim2.new(%s, %s, %s, %s)",
			Value.X.Scale,
			Value.X.Offset,
			Value.Y.Scale,
			Value.Y.Offset
		)
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
	end
	if Depth >= 12 then
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
		local KeyCode = "[" .. Serialize(Key, Depth + 1, Seen) .. "]"
		local ValueCode = Serialize(Value[Key], Depth + 1, Seen)
		table.insert(Lines, string.rep("\t", Depth + 1) .. KeyCode .. " = " .. ValueCode .. ",")
	end
	table.insert(Lines, string.rep("\t", Depth) .. "}")
	Seen[Value] = nil
	return table.concat(Lines, "\n")
end

local function SerializeArguments(Arguments)
	local Lines = { "local args = table.pack(" }
	for Index = 1, Arguments.n or #Arguments do
		local Suffix = Index < (Arguments.n or #Arguments) and "," or ""
		local Value = Serialize(Arguments[Index], 1, {})
		Value = Value:gsub("\n", "\n\t")
		table.insert(Lines, "\t" .. Value .. Suffix)
	end
	table.insert(Lines, ")")
	return table.concat(Lines, "\n")
end

local function BuildOutgoingPacket(Entry)
	local Lines = {
		"-- Decoder outgoing packet",
		"-- Remote: " .. Entry.Path,
		"-- Method: " .. Entry.Method,
		"-- Captured: x" .. tostring(Entry.Count),
		SerializeArguments(Entry.Arguments),
		"",
		"local remote = " .. GetInstancePath(Entry.Remote),
	}
	if Entry.Method == "InvokeServer" then
		table.insert(Lines, "local results = table.pack(remote:InvokeServer(table.unpack(args, 1, args.n)))")
		table.insert(Lines, "return table.unpack(results, 1, results.n)")
	else
		table.insert(Lines, "remote:FireServer(table.unpack(args, 1, args.n))")
	end
	return table.concat(Lines, "\n")
end

local function BuildIncomingText(Entry)
	local Lines = {
		"-- Decoder incoming capture",
		"-- Remote: " .. Entry.Path,
		"-- Signal: " .. Entry.Method,
		"-- Captured: x" .. tostring(Entry.Count),
		SerializeArguments(Entry.Arguments),
	}
	if Entry.Results then
		table.insert(Lines, "")
		table.insert(Lines, "-- Returned values")
		local ResultText = SerializeArguments(Entry.Results):gsub("local args", "local results", 1)
		table.insert(Lines, ResultText)
	end
	return table.concat(Lines, "\n")
end

local function CopyText(Text, SuccessMessage)
	if not SetClipboard then
		Window:Notify("No clipboard API was found.", "error", 4)
		return
	end
	local Success, ErrorMessage = pcall(SetClipboard, Text)
	Window:Notify(Success and SuccessMessage or ("Copy failed: " .. tostring(ErrorMessage)), Success and "success" or "error", 4)
end

local function EntryTitle(Entry)
	return string.format("%s · %s · x%d", Entry.Remote.Name, Entry.Method, Entry.Count)
end

local function UpdateSelected(Direction, Entry)
	if Direction == "Outgoing" then
		Runtime.SelectedOutgoing = Entry
		OutgoingEditor:Set(BuildOutgoingPacket(Entry))
	else
		Runtime.SelectedIncoming = Entry
		IncomingEditor:Set(BuildIncomingText(Entry))
	end
end

local function QueueEntryUpdate(Direction, Entry)
	if Entry.UpdateQueued then
		return
	end
	Entry.UpdateQueued = true
	task.defer(function()
		Entry.UpdateQueued = false
		if not Runtime.Active or not Entry.Button or not Entry.Button.Object.Parent then
			return
		end
		Entry.Button:SetText(EntryTitle(Entry))
		if Direction == "Outgoing" then
			OutgoingStatus:Set(string.format("%d calls across %d stacked remotes.", Runtime.OutgoingCount, Entry.UniqueCount or 0))
			if Runtime.SelectedOutgoing == Entry then
				OutgoingEditor:Set(BuildOutgoingPacket(Entry))
			end
		else
			IncomingStatus:Set(string.format("%d calls across %d stacked remotes.", Runtime.IncomingCount, Entry.UniqueCount or 0))
			if Runtime.SelectedIncoming == Entry then
				IncomingEditor:Set(BuildIncomingText(Entry))
			end
		end
	end)
end

local function CountEntries(Store)
	local Count = 0
	for _, Methods in pairs(Store) do
		for _ in pairs(Methods) do
			Count = Count + 1
		end
	end
	return Count
end

local function Record(Direction, Remote, Method, Arguments, Results)
	if not Runtime.Active then
		return
	end
	if Direction == "Outgoing" and not Runtime.CaptureOutgoing then
		return
	elseif Direction == "Incoming" and not Runtime.CaptureIncoming then
		return
	end

	local Store = Direction == "Outgoing" and Runtime.Outgoing or Runtime.Incoming
	local Methods = Store[Remote]
	if not Methods then
		Methods = {}
		Store[Remote] = Methods
	end

	local Entry = Methods[Method]
	if not Entry then
		Entry = {
			Remote = Remote,
			Path = GetDisplayPath(Remote),
			Method = Method,
			Arguments = Arguments,
			Results = Results,
			Count = 0,
			LastClock = 0,
		}
		Methods[Method] = Entry

		local List = Direction == "Outgoing" and OutgoingList or IncomingList
		Entry.Button = List:AddButton({
			Text = EntryTitle(Entry),
			Callback = function()
				UpdateSelected(Direction, Entry)
			end,
		})
	end

	Entry.Count = Entry.Count + 1
	Entry.Arguments = Arguments
	Entry.Results = Results
	Entry.LastClock = os.clock()
	Entry.UniqueCount = CountEntries(Store)
	if Direction == "Outgoing" then
		Runtime.OutgoingCount = Runtime.OutgoingCount + 1
	else
		Runtime.IncomingCount = Runtime.IncomingCount + 1
	end
	QueueEntryUpdate(Direction, Entry)
end

local function InstallNamecallHook()
	if Bus.HookInstalled then
		return true, "already installed"
	end
	if not HookMetamethod or not GetNamecallMethod then
		return false, "hookmetamethod/getnamecallmethod unavailable"
	end

	local OldNamecall
	OldNamecall = HookMetamethod(game, "__namecall", NewCClosure(function(Self, ...)
		local Method = GetNamecallMethod()
		if Method ~= "FireServer" and Method ~= "InvokeServer" then
			return OldNamecall(Self, ...)
		end

		local ClassName = typeof(Self) == "Instance" and Self.ClassName or ""
		local IsRemoteEvent = Method == "FireServer" and ClassName == "RemoteEvent"
		local IsRemoteFunction = Method == "InvokeServer" and ClassName == "RemoteFunction"
		if not IsRemoteEvent and not IsRemoteFunction then
			return OldNamecall(Self, ...)
		end

		local Arguments = table.pack(...)
		if Method == "InvokeServer" then
			local Results = table.pack(OldNamecall(Self, table.unpack(Arguments, 1, Arguments.n)))
			if Bus.Callback then
				task.defer(Bus.Callback, "Outgoing", Self, Method, Arguments, Results)
			end
			return table.unpack(Results, 1, Results.n)
		end

		if Bus.Callback then
			task.defer(Bus.Callback, "Outgoing", Self, Method, Arguments, nil)
		end
		return OldNamecall(Self, table.unpack(Arguments, 1, Arguments.n))
	end))

	Bus.OldNamecall = OldNamecall
	Bus.HookInstalled = true
	return true, HookName
end

Bus.Callback = Record
local HookCallSuccess, HookInstalled, HookDetails = pcall(InstallNamecallHook)
local OutgoingHookReady = HookCallSuccess and HookInstalled == true
local OutgoingHookStatus = HookCallSuccess and tostring(HookDetails) or tostring(HookInstalled)

local function ObserveRemoteEvent(Remote)
	if Runtime.ObservedRemotes[Remote] then
		return
	end
	Runtime.ObservedRemotes[Remote] = true
	local Success, Connection = pcall(function()
		return Remote.OnClientEvent:Connect(function(...)
			Record("Incoming", Remote, "OnClientEvent", table.pack(...), nil)
		end)
	end)
	if Success and Connection then
		table.insert(Runtime.Connections, Connection)
	end
end

local function ObserveRemoteFunction(Remote)
	Runtime.ObservedRemotes[Remote] = true
	if not HookFunction then
		return
	end

	local Callback = Remote.OnClientInvoke
	if type(Callback) ~= "function" or Runtime.HookedInvokeCallbacks[Callback] then
		return
	end

	local OldCallback
	local Success, Result = pcall(function()
		OldCallback = HookFunction(Callback, function(...)
			local Arguments = table.pack(...)
			local Results = table.pack(OldCallback(table.unpack(Arguments, 1, Arguments.n)))
			task.defer(Record, "Incoming", Remote, "OnClientInvoke", Arguments, Results)
			return table.unpack(Results, 1, Results.n)
		end)
		return OldCallback
	end)
	if Success and type(Result) == "function" then
		Runtime.HookedInvokeCallbacks[Callback] = true
	end
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

for _, Object in ipairs(game:GetDescendants()) do
	Observe(Object)
end
table.insert(Runtime.Connections, game.DescendantAdded:Connect(Observe))

task.spawn(function()
	while Runtime.Active do
		task.wait(1.5)
		if HookFunction then
			for Remote in pairs(Runtime.ObservedRemotes) do
				if Remote.Parent and Remote.ClassName == "RemoteFunction" then
					ObserveRemoteFunction(Remote)
				end
			end
		end
	end
end)

OutgoingNotepad:AddButton({
	Text = "Copy Ready Packet",
	Callback = function()
		local Entry = Runtime.SelectedOutgoing
		if not Entry then
			Window:Notify("Select an outgoing remote first.", "error")
			return
		end
		CopyText(BuildOutgoingPacket(Entry), "Ready packet copied.")
	end,
})

OutgoingNotepad:AddButton({
	Text = "Fire Selected Packet",
	Callback = function()
		local Entry = Runtime.SelectedOutgoing
		if not Entry then
			Window:Notify("Select an outgoing remote first.", "error")
			return
		end
		local Success, Result = pcall(function()
			if Entry.Method == "InvokeServer" then
				return table.pack(Entry.Remote:InvokeServer(table.unpack(Entry.Arguments, 1, Entry.Arguments.n)))
			end
			Entry.Remote:FireServer(table.unpack(Entry.Arguments, 1, Entry.Arguments.n))
			return true
		end)
		if Success then
			if Entry.Method == "InvokeServer" then
				Entry.Results = Result
			end
			Window:Notify("Packet fired.", "success")
		else
			Window:Notify("Packet failed: " .. tostring(Result), "error", 4)
		end
	end,
})

OutgoingNotepad:AddToggle({
	Text = "Capture outgoing traffic",
	Default = true,
	Callback = function(Enabled)
		Runtime.CaptureOutgoing = Enabled
	end,
})

OutgoingNotepad:AddButton({
	Text = "Clear Outgoing",
	Callback = function()
		for _, Methods in pairs(Runtime.Outgoing) do
			for _, Entry in pairs(Methods) do
				if Entry.Button and Entry.Button.Object then
					Entry.Button.Object:Destroy()
				end
			end
		end
		table.clear(Runtime.Outgoing)
		Runtime.OutgoingCount = 0
		Runtime.SelectedOutgoing = nil
		OutgoingStatus:Set("Waiting for FireServer or InvokeServer traffic.")
		OutgoingEditor:Set("-- Select an outgoing remote.")
	end,
})

IncomingNotepad:AddButton({
	Text = "Copy Incoming Arguments",
	Callback = function()
		local Entry = Runtime.SelectedIncoming
		if not Entry then
			Window:Notify("Select an incoming remote first.", "error")
			return
		end
		CopyText(BuildIncomingText(Entry), "Incoming arguments copied.")
	end,
})

IncomingNotepad:AddToggle({
	Text = "Capture incoming traffic",
	Default = true,
	Callback = function(Enabled)
		Runtime.CaptureIncoming = Enabled
	end,
})

IncomingNotepad:AddButton({
	Text = "Clear Incoming",
	Callback = function()
		for _, Methods in pairs(Runtime.Incoming) do
			for _, Entry in pairs(Methods) do
				if Entry.Button and Entry.Button.Object then
					Entry.Button.Object:Destroy()
				end
			end
		end
		table.clear(Runtime.Incoming)
		Runtime.IncomingCount = 0
		Runtime.SelectedIncoming = nil
		IncomingStatus:Set("Waiting for OnClientEvent or OnClientInvoke traffic.")
		IncomingEditor:Set("-- Select an incoming remote.")
	end,
})

local ApiSection = InformationPage:AddSection("Detected APIs")
ApiSection:AddLabel({
	Text = "Outgoing namecall · " .. (OutgoingHookReady and "ready" or ("unavailable: " .. OutgoingHookStatus)),
	Color = OutgoingHookReady and GrayUI.Theme.Success or GrayUI.Theme.Danger,
})
ApiSection:AddLabel({
	Text = "Clipboard · " .. tostring(ClipboardName or "unavailable"),
	Color = SetClipboard and GrayUI.Theme.Success or GrayUI.Theme.Danger,
})
ApiSection:AddLabel({
	Text = "Incoming RemoteEvent · ready",
	Color = GrayUI.Theme.Success,
})
ApiSection:AddLabel({
	Text = "Incoming RemoteFunction · " .. tostring(HookFunctionName or "hookfunction unavailable"),
	Color = HookFunction and GrayUI.Theme.Success or GrayUI.Theme.Muted,
})

local BehaviorSection = InformationPage:AddSection("Behavior")
BehaviorSection:AddLabel({
	Text = "Repeated calls from the same remote and method are stacked into one row as x1, x2, x3. Selecting it always shows the newest captured arguments.",
})
BehaviorSection:AddLabel({
	Text = "Outgoing packets are generated as table.pack arguments plus a ready FireServer or InvokeServer call. Buffers are reconstructed byte-for-byte.",
})
BehaviorSection:AddLabel({
	Text = "The namecall hook observes traffic and preserves the original call arguments and return values.",
})

BehaviorSection:AddButton({
	Text = "Delete Decoder",
	Callback = function()
		Runtime.Active = false
		Bus.Callback = nil
		for _, Connection in ipairs(Runtime.Connections) do
			pcall(function()
				Connection:Disconnect()
			end)
		end
		Window:Destroy()
	end,
})

Window:Notify("Decoder is capturing remote traffic.", "success")
