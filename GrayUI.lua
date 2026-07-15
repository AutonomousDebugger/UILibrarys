local GrayUI = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = {
	Background = Color3.fromRGB(12, 13, 15),
	Panel = Color3.fromRGB(20, 22, 25),
	PanelLight = Color3.fromRGB(29, 32, 36),
	Control = Color3.fromRGB(35, 38, 43),
	ControlHover = Color3.fromRGB(43, 47, 53),
	Text = Color3.fromRGB(239, 241, 245),
	Muted = Color3.fromRGB(154, 160, 170),
	Stroke = Color3.fromRGB(58, 62, 69),
	Accent = Color3.fromRGB(184, 190, 200),
	Success = Color3.fromRGB(105, 201, 139),
	Danger = Color3.fromRGB(230, 104, 112),
}

GrayUI.Theme = Theme

local function create(className, properties)
	local object = Instance.new(className)
	for key, value in pairs(properties or {}) do
		if key ~= "Parent" then
			object[key] = value
		end
	end
	object.Parent = properties and properties.Parent or nil
	return object
end

local function addCorner(parent, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius or 8),
		Parent = parent,
	})
end

local function addStroke(parent, color, transparency, thickness)
	return create("UIStroke", {
		Color = color or Theme.Stroke,
		Transparency = transparency or 0,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function addPadding(parent, left, right, top, bottom)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or left or 0),
		PaddingTop = UDim.new(0, top or left or 0),
		PaddingBottom = UDim.new(0, bottom or top or left or 0),
		Parent = parent,
	})
end

local function tween(object, properties, duration)
	local animation = TweenService:Create(
		object,
		TweenInfo.new(duration or 0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		properties
	)
	animation:Play()
	return animation
end

local function trim(text)
	return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function getGuiParent()
	if type(gethui) == "function" then
		local ok, result = pcall(gethui)
		if ok and result then
			return result
		end
	end

	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and coreGui then
		return coreGui
	end

	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function bindHover(button, normalColor, hoverColor)
	button.MouseEnter:Connect(function()
		tween(button, { BackgroundColor3 = hoverColor or Theme.ControlHover })
	end)
	button.MouseLeave:Connect(function()
		tween(button, { BackgroundColor3 = normalColor or Theme.Control })
	end)
end

local function makeDraggable(handle, target)
	local dragging = false
	local dragInput
	local dragStart
	local startCenter

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startCenter = Vector2.new(
				target.AbsolutePosition.X + target.AbsoluteSize.X * target.AnchorPoint.X,
				target.AbsolutePosition.Y + target.AbsoluteSize.Y * target.AnchorPoint.Y
			)

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local delta = input.Position - dragStart
			local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
				or Vector2.new(1920, 1080)
			local halfWidth = target.AbsoluteSize.X * target.AnchorPoint.X
			local halfHeight = target.AbsoluteSize.Y * target.AnchorPoint.Y
			local center = startCenter + delta
			local minimumX = halfWidth + 4
			local maximumX = math.max(minimumX, viewport.X - (target.AbsoluteSize.X - halfWidth) - 4)
			local minimumY = halfHeight + 4
			local maximumY = math.max(minimumY, viewport.Y - (target.AbsoluteSize.Y - halfHeight) - 4)

			target.Position = UDim2.fromOffset(
				math.clamp(center.X, minimumX, maximumX),
				math.clamp(center.Y, minimumY, maximumY)
			)
		end
	end)
end

local function makeResizable(handle, target, minimum, maximum)
	local resizing = false
	local resizeInput
	local resizeStart
	local startSize

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeStart = input.Position
			startSize = target.AbsoluteSize

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			resizeInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if resizing and input == resizeInput then
			local delta = input.Position - resizeStart
			local width = math.clamp(startSize.X + delta.X, minimum.X, maximum.X)
			local height = math.clamp(startSize.Y + delta.Y, minimum.Y, maximum.Y)
			target.Size = UDim2.fromOffset(width, height)
		end
	end)
end

local Section = {}
Section.__index = Section

function Section:_makeRow(height)
	return create("Frame", {
		BackgroundColor3 = Theme.Control,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height or 42),
		Parent = self.Container,
	})
end

function Section:AddLabel(options)
	if type(options) == "string" then
		options = { Text = options }
	end
	options = options or {}

	local label = create("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		RichText = options.RichText == true,
		Size = UDim2.new(1, 0, 0, 20),
		Text = tostring(options.Text or "Label"),
		TextColor3 = options.Color or Theme.Muted,
		TextSize = options.TextSize or 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.Container,
	})

	local controller = { Object = label }
	function controller:Set(text)
		label.Text = tostring(text or "")
	end
	function controller:SetColor(color)
		label.TextColor3 = color
	end
	return controller
end

function Section:AddButton(options)
	if type(options) == "string" then
		options = { Text = options }
	end
	options = options or {}

	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Size = UDim2.new(1, 0, 0, options.Height or 42),
		Text = tostring(options.Text or "Button"),
		TextColor3 = Theme.Text,
		TextSize = 13,
		Parent = self.Container,
	})
	addCorner(button, 7)
	addStroke(button, Theme.Stroke, 0.2)
	bindHover(button)

	button.Activated:Connect(function()
		if type(options.Callback) == "function" then
			task.spawn(options.Callback)
		end
	end)

	local controller = { Object = button }
	function controller:SetText(text)
		button.Text = tostring(text or "")
	end
	function controller:SetEnabled(enabled)
		button.Active = enabled
		button.TextTransparency = enabled and 0 or 0.5
	end
	return controller
end

function Section:AddTextbox(options)
	options = options or {}
	local row = self:_makeRow(options.Height or 58)
	addCorner(row, 7)
	addStroke(row, Theme.Stroke, 0.2)

	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 7),
		Size = UDim2.new(1, -24, 0, 16),
		Text = tostring(options.Text or "Input"),
		TextColor3 = Theme.Muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local box = create("TextBox", {
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = options.Code and Enum.Font.Code or Enum.Font.Gotham,
		PlaceholderColor3 = Color3.fromRGB(105, 110, 120),
		PlaceholderText = tostring(options.Placeholder or ""),
		Position = UDim2.fromOffset(12, 25),
		Size = UDim2.new(1, -24, 0, 25),
		Text = tostring(options.Default or ""),
		TextColor3 = Theme.Text,
		TextSize = options.TextSize or 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	box.FocusLost:Connect(function(enterPressed)
		if type(options.Callback) == "function" then
			task.spawn(options.Callback, box.Text, enterPressed)
		end
	end)

	local controller = { Object = box, Row = row }
	function controller:Get()
		return box.Text
	end
	function controller:Set(text)
		box.Text = tostring(text or "")
	end
	function controller:Focus()
		box:CaptureFocus()
	end
	return controller
end

function Section:AddTextArea(options)
	options = options or {}
	local height = options.Height or 220
	local row = self:_makeRow(height)
	row.ClipsDescendants = true
	addCorner(row, 7)
	addStroke(row, Theme.Stroke, 0.2)

	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.new(1, -24, 0, 18),
		Text = tostring(options.Text or "Text"),
		TextColor3 = Theme.Muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local box = create("TextBox", {
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = options.Code == false and Enum.Font.Gotham or Enum.Font.Code,
		MultiLine = true,
		PlaceholderColor3 = Color3.fromRGB(92, 98, 108),
		PlaceholderText = tostring(options.Placeholder or ""),
		Position = UDim2.fromOffset(9, 32),
		Size = UDim2.new(1, -18, 1, -41),
		Text = tostring(options.Default or ""),
		TextColor3 = Theme.Text,
		TextSize = options.TextSize or 13,
		TextWrapped = options.Wrap == true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = row,
	})
	addCorner(box, 6)
	addPadding(box, 10, 10, 9, 9)

	local controller = { Object = box, Row = row }
	function controller:Get()
		return box.Text
	end
	function controller:Set(text)
		box.Text = tostring(text or "")
	end
	function controller:SetEditable(editable)
		box.TextEditable = editable
	end
	return controller
end

function Section:AddToggle(options)
	options = options or {}
	local state = options.Default == true
	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Control,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 44),
		Text = "",
		Parent = self.Container,
	})
	addCorner(button, 7)
	addStroke(button, Theme.Stroke, 0.2)
	bindHover(button)

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -62, 1, 0),
		Text = tostring(options.Text or "Toggle"),
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})

	local track = create("Frame", {
		BackgroundColor3 = state and Theme.Accent or Color3.fromRGB(68, 72, 79),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -48, 0.5, -10),
		Size = UDim2.fromOffset(36, 20),
		Parent = button,
	})
	addCorner(track, 10)

	local knob = create("Frame", {
		BackgroundColor3 = state and Theme.Background or Theme.Text,
		BorderSizePixel = 0,
		Position = state and UDim2.fromOffset(18, 3) or UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(14, 14),
		Parent = track,
	})
	addCorner(knob, 7)

	local function setState(value, fire)
		state = value == true
		tween(track, {
			BackgroundColor3 = state and Theme.Accent or Color3.fromRGB(68, 72, 79),
		})
		tween(knob, {
			BackgroundColor3 = state and Theme.Background or Theme.Text,
			Position = state and UDim2.fromOffset(18, 3) or UDim2.fromOffset(3, 3),
		})
		if fire and type(options.Callback) == "function" then
			task.spawn(options.Callback, state)
		end
	end

	button.Activated:Connect(function()
		setState(not state, true)
	end)

	local controller = { Object = button }
	function controller:Get()
		return state
	end
	function controller:Set(value)
		setState(value, true)
	end
	return controller
end

function Section:AddDropdown(options)
	options = options or {}
	local choices = options.Values or {}
	local selected = options.Default or choices[1]
	local open = false

	local holder = create("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 42),
		Parent = self.Container,
	})
	local layout = create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})

	local main = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Control,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 42),
		Text = "",
		Parent = holder,
	})
	addCorner(main, 7)
	addStroke(main, Theme.Stroke, 0.2)
	bindHover(main)

	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.45, -12, 1, 0),
		Text = tostring(options.Text or "Dropdown"),
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = main,
	})
	local valueLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.new(0.45, 0, 0, 0),
		Size = UDim2.new(0.55, -30, 1, 0),
		Text = tostring(selected or "None"),
		TextColor3 = Theme.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = main,
	})
	local arrow = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -25, 0, 0),
		Size = UDim2.fromOffset(16, 42),
		Text = "+",
		TextColor3 = Theme.Muted,
		TextSize = 16,
		Parent = main,
	})

	local optionsFrame = create("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		Visible = false,
		Parent = holder,
	})
	addCorner(optionsFrame, 7)
	addStroke(optionsFrame, Theme.Stroke, 0.2)
	addPadding(optionsFrame, 5)
	local optionsLayout = create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = optionsFrame,
	})

	local function choose(value, fire)
		selected = value
		valueLabel.Text = tostring(value)
		if fire and type(options.Callback) == "function" then
			task.spawn(options.Callback, value)
		end
	end

	local function rebuild()
		for _, child in ipairs(optionsFrame:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		for _, value in ipairs(choices) do
			local item = create("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Control,
				BorderSizePixel = 0,
				Font = Enum.Font.Gotham,
				Size = UDim2.new(1, 0, 0, 32),
				Text = tostring(value),
				TextColor3 = Theme.Text,
				TextSize = 12,
				Parent = optionsFrame,
			})
			addCorner(item, 5)
			bindHover(item)
			item.Activated:Connect(function()
				choose(value, true)
				open = false
				optionsFrame.Visible = false
				arrow.Text = "+"
			end)
		end
	end

	rebuild()
	main.Activated:Connect(function()
		open = not open
		optionsFrame.Visible = open
		arrow.Text = open and "−" or "+"
	end)

	local controller = { Object = holder }
	function controller:Get()
		return selected
	end
	function controller:Set(value)
		choose(value, true)
	end
	function controller:SetValues(values)
		choices = values or {}
		rebuild()
	end
	return controller
end

function Section:Clear()
	for _, child in ipairs(self.Container:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local Page = {}
Page.__index = Page

function Page:AddSection(title)
	local frame = create("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = self.Container,
	})
	addCorner(frame, 9)
	addStroke(frame, Theme.Stroke, 0.35)
	addPadding(frame, 10)
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})

	create("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 18),
		Text = tostring(title or "Section"),
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	return setmetatable({
		Container = frame,
		Page = self,
	}, Section)
end

local Window = {}
Window.__index = Window

function Window:AddTab(name)
	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Size = UDim2.fromOffset(105, 32),
		Text = tostring(name or "Tab"),
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Parent = self.TabBar,
	})
	addCorner(button, 6)

	local scrolling = create("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarImageColor3 = Theme.Stroke,
		ScrollBarThickness = 3,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = self.PageHolder,
	})
	addPadding(scrolling, 2, 5, 2, 8)
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scrolling,
	})

	local page = setmetatable({
		Button = button,
		Container = scrolling,
		Name = name,
		Window = self,
	}, Page)

	local function selectTab()
		for _, other in ipairs(self.Tabs) do
			local active = other == page
			other.Container.Visible = active
			tween(other.Button, {
				BackgroundColor3 = active and Theme.Control or Theme.Panel,
				TextColor3 = active and Theme.Text or Theme.Muted,
			})
		end
	end

	button.Activated:Connect(selectTab)
	table.insert(self.Tabs, page)
	if #self.Tabs == 1 then
		selectTab()
	end

	return page
end

function Window:Notify(message, kind, duration)
	local colors = {
		success = Theme.Success,
		error = Theme.Danger,
		neutral = Theme.Accent,
	}
	local notice = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.fromOffset(290, 52),
		Parent = self.ScreenGui,
	})
	addCorner(notice, 8)
	addStroke(notice, colors[kind] or colors.neutral, 0.1)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Text = tostring(message or ""),
		TextColor3 = Theme.Text,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = notice,
	})

	notice.BackgroundTransparency = 1
	notice.Position = UDim2.new(1, -14, 1, 12)
	tween(notice, { BackgroundTransparency = 0, Position = UDim2.new(1, -14, 1, -14) }, 0.2)
	task.delay(duration or 2.5, function()
		if notice.Parent then
			tween(notice, { BackgroundTransparency = 1, Position = UDim2.new(1, -14, 1, 12) }, 0.2)
			task.wait(0.22)
			notice:Destroy()
		end
	end)
end

function Window:SetVisible(visible)
	self:SetOpen(visible == true)
end

function Window:Destroy()
	self.ScreenGui:Destroy()
end

function GrayUI:CreateWindow(options)
	options = options or {}
	local existing = getGuiParent():FindFirstChild(options.Id or "GrayUI")
	if existing then
		existing:Destroy()
	end

	local screenGui = create("ScreenGui", {
		DisplayOrder = options.DisplayOrder or 50,
		IgnoreGuiInset = true,
		Name = options.Id or "GrayUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = getGuiParent(),
	})

	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
	local requestedSize = options.Size or Vector2.new(680, 470)
	local initialSize = Vector2.new(
		math.min(requestedSize.X, math.max(360, viewport.X - 24)),
		math.min(requestedSize.Y, math.max(290, viewport.Y - 24))
	)
	local requestedMinimum = options.MinSize or Vector2.new(390, 310)
	local minimum = Vector2.new(
		math.min(requestedMinimum.X, initialSize.X),
		math.min(requestedMinimum.Y, initialSize.Y)
	)
	local maximum = options.MaxSize or Vector2.new(1200, 850)
	local main = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(initialSize.X, initialSize.Y),
		Parent = screenGui,
	})
	addCorner(main, 11)
	addStroke(main, Theme.Stroke, 0.05)
	local mainScale = create("UIScale", {
		Scale = 1,
		Parent = main,
	})

	local titleBar = create("Frame", {
		Active = true,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 48),
		Parent = main,
	})
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -112, 1, 0),
		Text = tostring(options.Title or "Gray UI"),
		TextColor3 = Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = titleBar,
	})
	local subtitle = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.new(1, -180, 0, 0),
		Size = UDim2.fromOffset(112, 48),
		Text = tostring(options.Subtitle or ""),
		TextColor3 = Theme.Muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = titleBar,
	})

	local close = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -47, 0, 10),
		Size = UDim2.fromOffset(30, 28),
		Text = "×",
		TextColor3 = Theme.Muted,
		TextSize = 18,
		Parent = titleBar,
	})
	addCorner(close, 6)
	bindHover(close, Theme.Control, Color3.fromRGB(91, 43, 47))
	local tabBar = create("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		Position = UDim2.fromOffset(0, 48),
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = main,
	})
	addPadding(tabBar, 12, 12, 6, 6)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})

	local pageHolder = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 102),
		Size = UDim2.new(1, -24, 1, -114),
		Parent = main,
	})

	local resizeHandle = create("TextButton", {
		Active = true,
		AnchorPoint = Vector2.new(1, 1),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(28, 28),
		Text = "◢",
		TextColor3 = Theme.Muted,
		TextSize = 15,
		ZIndex = 20,
		Parent = main,
	})

	local reopen = create("TextButton", {
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0),
		AutoButtonColor = false,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(96, 36),
		Text = tostring(options.ReopenText or "OPEN UI"),
		TextColor3 = Theme.Text,
		TextSize = 11,
		Visible = false,
		ZIndex = 100,
		Parent = screenGui,
	})
	addCorner(reopen, 9)
	addStroke(reopen, Theme.Stroke, 0.05)
	bindHover(reopen, Theme.PanelLight, Theme.ControlHover)

	makeDraggable(titleBar, main)
	makeDraggable(reopen, reopen)
	makeResizable(resizeHandle, main, minimum, maximum)

	local window = setmetatable({
		Main = main,
		PageHolder = pageHolder,
		ScreenGui = screenGui,
		Scale = mainScale,
		Reopen = reopen,
		TabBar = tabBar,
		Tabs = {},
		Theme = Theme,
	}, Window)

	local transitionId = 0
	function window:SetOpen(open)
		transitionId = transitionId + 1
		local thisTransition = transitionId

		if open then
			reopen.Visible = false
			main.Visible = true
			mainScale.Scale = 0.92
			tween(mainScale, { Scale = 1 }, 0.18)
		else
			tween(mainScale, { Scale = 0.92 }, 0.15)
			task.delay(0.15, function()
				if transitionId == thisTransition and screenGui.Parent then
					main.Visible = false
					reopen.Visible = true
				end
			end)
		end
	end

	close.Activated:Connect(function()
		window:SetOpen(false)
	end)
	reopen.Activated:Connect(function()
		window:SetOpen(true)
	end)

	return window
end

return GrayUI
