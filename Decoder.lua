-- Decoder GUI - all capture/replay logic is loaded from DecoderCore.lua.

local GRAY_UI_URL = "https://raw.githubusercontent.com/AutonomousDebugger/UILibrarys/refs/heads/main/GrayUI.lua?v=2"
local CORE_URL = "https://raw.githubusercontent.com/AutonomousDebugger/UILibrarys/refs/heads/main/DecoderCore.lua?v=2"

local function LoadLibrary(Url, Name)
	assert(type(loadstring) == "function", "loadstring is unavailable")
	local Source = game:HttpGet(Url)
	local Chunk, CompileError = loadstring(Source)
	assert(Chunk, CompileError)
	local Result = Chunk()
	assert(type(Result) == "table", Name .. " did not return a table")
	return Result
end

local GrayUI = LoadLibrary(GRAY_UI_URL, "GrayUI")
local DecoderCore = LoadLibrary(CORE_URL, "DecoderCore")
local UserInputService = game:GetService("UserInputService")
local Environment = type(getgenv) == "function" and getgenv() or _G

local function ResolveClipboard()
	for _, Name in ipairs({ "settoclipboard", "setclipboard", "toclipboard", "setrbxclipboard" }) do
		local Value = rawget(Environment, Name) or rawget(_G, Name)
		if type(Value) == "function" then
			return Value, Name
		end
	end
	return nil, nil
end

local SetClipboard, ClipboardName = ResolveClipboard()
local Window = GrayUI:CreateWindow({
	Id = "GrayDecoder",
	Title = "Decoder",
	Subtitle = "REMOTE TRAFFIC",
	ReopenText = "DECODER",
	Size = Vector2.new(760, 535),
	MinSize = Vector2.new(420, 330),
	MaxSize = Vector2.new(1350, 950),
})

local function AddReliableDrag(Handle, Target)
	Handle.Active = true
	local Dragging = false
	local DragInput
	local DragStart
	local StartPosition

	Handle.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch then
			Dragging = true
			DragStart = Input.Position
			StartPosition = Target.Position
			DragInput = Input.UserInputType == Enum.UserInputType.Touch and Input or nil
			Input.Changed:Connect(function()
				if Input.UserInputState == Enum.UserInputState.End then
					Dragging = false
					DragInput = nil
				end
			end)
		end
	end)

	Handle.InputChanged:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseMovement
			or Input.UserInputType == Enum.UserInputType.Touch then
			DragInput = Input
		end
	end)

	UserInputService.InputChanged:Connect(function(Input)
		if Dragging and (Input == DragInput
			or Input.UserInputType == Enum.UserInputType.MouseMovement) then
			local Delta = Input.Position - DragStart
			Target.Position = UDim2.new(
				StartPosition.X.Scale,
				StartPosition.X.Offset + Delta.X,
				StartPosition.Y.Scale,
				StartPosition.Y.Offset + Delta.Y
			)
		end
	end)
end

local DragSurface = Instance.new("TextButton")
DragSurface.Name = "DecoderDragSurface"
DragSurface.Active = true
DragSurface.AutoButtonColor = false
DragSurface.BackgroundTransparency = 1
DragSurface.BorderSizePixel = 0
DragSurface.Position = UDim2.fromOffset(0, 0)
DragSurface.Size = UDim2.new(1, -58, 0, 48)
DragSurface.Text = ""
DragSurface.ZIndex = 15
DragSurface.Parent = Window.Main
AddReliableDrag(DragSurface, Window.Main)

local OutgoingPage = Window:AddTab("Outgoing")
local IncomingPage = Window:AddTab("Incoming")
local InformationPage = Window:AddTab("Information")

local OutgoingList = OutgoingPage:AddSection("Outgoing Traffic")
local OutgoingStatus = OutgoingList:AddLabel("Waiting for FireServer or InvokeServer traffic.")
local OutgoingNotepad = OutgoingPage:AddSection("Packet Notepad")
local OutgoingEditor = OutgoingNotepad:AddTextArea({
	Text = "Selected outgoing packet",
	Default = "-- Select an outgoing remote.",
	Height = 290,
	Code = true,
	Wrap = false,
})

local IncomingList = IncomingPage:AddSection("Incoming Traffic")
local IncomingStatus = IncomingList:AddLabel("Waiting for OnClientEvent or OnClientInvoke traffic.")
local IncomingNotepad = IncomingPage:AddSection("Arguments Notepad")
local IncomingEditor = IncomingNotepad:AddTextArea({
	Text = "Selected incoming arguments",
	Default = "-- Select an incoming remote.",
	Height = 290,
	Code = true,
	Wrap = false,
})

local GuiState = {
	Active = true,
	Buttons = {
		Outgoing = setmetatable({}, { __mode = "k" }),
		Incoming = setmetatable({}, { __mode = "k" }),
	},
	SelectedOutgoing = nil,
	SelectedIncoming = nil,
}

local function EntryTitle(Entry)
	return string.format("%s · %s · x%d", Entry.Remote.Name, Entry.Method, Entry.Count)
end

local function SelectEntry(Entry)
	if Entry.Direction == "Outgoing" then
		GuiState.SelectedOutgoing = Entry
		OutgoingEditor:Set(DecoderCore.BuildOutgoingPacket(Entry))
	else
		GuiState.SelectedIncoming = Entry
		IncomingEditor:Set(DecoderCore.BuildIncomingText(Entry))
	end
end

local function AddEntryButton(Entry)
	local DirectionButtons = GuiState.Buttons[Entry.Direction]
	local Button = DirectionButtons[Entry]
	if Button then
		Button:SetText(EntryTitle(Entry))
		return Button
	end
	local Section = Entry.Direction == "Outgoing" and OutgoingList or IncomingList
	Button = Section:AddButton({
		Text = EntryTitle(Entry),
		Callback = function()
			SelectEntry(Entry)
		end,
	})
	DirectionButtons[Entry] = Button
	return Button
end

local DisconnectTraffic = DecoderCore.OnTraffic(function(Entry)
	if not GuiState.Active then
		return
	end
	local Button = AddEntryButton(Entry)
	Button:SetText(EntryTitle(Entry))
	if Entry.Direction == "Outgoing" then
		OutgoingStatus:Set(string.format(
			"%d calls across %d stacked remotes.",
			DecoderCore.State.OutgoingCalls,
			Entry.UniqueCount
		))
		if GuiState.SelectedOutgoing == Entry then
			OutgoingEditor:Set(DecoderCore.BuildOutgoingPacket(Entry))
		end
	else
		IncomingStatus:Set(string.format(
			"%d calls across %d stacked remotes.",
			DecoderCore.State.IncomingCalls,
			Entry.UniqueCount
		))
		if GuiState.SelectedIncoming == Entry then
			IncomingEditor:Set(DecoderCore.BuildIncomingText(Entry))
		end
	end
end)

local function Copy(Text, Message)
	if not SetClipboard then
		Window:Notify("No clipboard API was found.", "error")
		return
	end
	local Success, ErrorMessage = pcall(SetClipboard, Text)
	Window:Notify(Success and Message or tostring(ErrorMessage), Success and "success" or "error", 4)
end

OutgoingNotepad:AddButton({
	Text = "Copy Ready Packet",
	Callback = function()
		if not GuiState.SelectedOutgoing then
			Window:Notify("Select an outgoing remote first.", "error")
			return
		end
		Copy(DecoderCore.BuildOutgoingPacket(GuiState.SelectedOutgoing), "Ready packet copied.")
	end,
})

OutgoingNotepad:AddButton({
	Text = "Fire Selected Packet",
	Callback = function()
		if not GuiState.SelectedOutgoing then
			Window:Notify("Select an outgoing remote first.", "error")
			return
		end
		local Success, Result = pcall(DecoderCore.Fire, GuiState.SelectedOutgoing)
		Window:Notify(Success and "Packet fired." or tostring(Result), Success and "success" or "error", 4)
	end,
})

OutgoingNotepad:AddToggle({
	Text = "Capture outgoing traffic",
	Default = true,
	Callback = function(Enabled)
		DecoderCore.State.CaptureOutgoing = Enabled
	end,
})

local function ClearDirection(Direction)
	for _, Button in pairs(GuiState.Buttons[Direction]) do
		if Button.Object then
			Button.Object:Destroy()
		end
	end
	table.clear(GuiState.Buttons[Direction])
	DecoderCore.Clear(Direction)
	if Direction == "Outgoing" then
		GuiState.SelectedOutgoing = nil
		OutgoingStatus:Set("Waiting for FireServer or InvokeServer traffic.")
		OutgoingEditor:Set("-- Select an outgoing remote.")
	else
		GuiState.SelectedIncoming = nil
		IncomingStatus:Set("Waiting for OnClientEvent or OnClientInvoke traffic.")
		IncomingEditor:Set("-- Select an incoming remote.")
	end
end

OutgoingNotepad:AddButton({
	Text = "Clear Outgoing",
	Callback = function()
		ClearDirection("Outgoing")
	end,
})

IncomingNotepad:AddButton({
	Text = "Copy Incoming Arguments",
	Callback = function()
		if not GuiState.SelectedIncoming then
			Window:Notify("Select an incoming remote first.", "error")
			return
		end
		Copy(DecoderCore.BuildIncomingText(GuiState.SelectedIncoming), "Incoming arguments copied.")
	end,
})

IncomingNotepad:AddToggle({
	Text = "Capture incoming traffic",
	Default = true,
	Callback = function(Enabled)
		DecoderCore.State.CaptureIncoming = Enabled
	end,
})

IncomingNotepad:AddButton({
	Text = "Clear Incoming",
	Callback = function()
		ClearDirection("Incoming")
	end,
})

DecoderCore.Start()
local ApiStatus = DecoderCore.GetApiStatus()
local ApiSection = InformationPage:AddSection("Capture APIs")
ApiSection:AddLabel({
	Text = "__namecall · " .. ApiStatus.NamecallStatus,
	Color = ApiStatus.NamecallReady and GrayUI.Theme.Success or GrayUI.Theme.Danger,
})
ApiSection:AddLabel({
	Text = "Direct/cached method hooks · " .. ApiStatus.MethodHooksStatus,
	Color = ApiStatus.MethodHooksReady and GrayUI.Theme.Success or GrayUI.Theme.Danger,
})
ApiSection:AddLabel({
	Text = "Clipboard · " .. tostring(ClipboardName or "unavailable"),
	Color = SetClipboard and GrayUI.Theme.Success or GrayUI.Theme.Muted,
})

local BehaviorSection = InformationPage:AddSection("Behavior")
BehaviorSection:AddLabel("Outgoing uses both __namecall and direct FireServer/InvokeServer hooks. Calls seen by both hooks are counted once.")
BehaviorSection:AddLabel("Incoming RemoteEvents are captured by OnClientEvent connections. RemoteFunctions use hookfunction when available.")
BehaviorSection:AddButton({
	Text = "Delete Decoder",
	Callback = function()
		GuiState.Active = false
		DisconnectTraffic()
		DecoderCore:Stop()
		Window:Destroy()
	end,
})

Window:Notify("Decoder 2.0 is capturing traffic.", "success")
