local GrayUI = {}
GrayUI.Version = "2.1.9"

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

local Defaults = {
	WindowRadius = 16,
	SectionRadius = 12,
	ControlRadius = 9,
	TabRadius = 10,
	TabSpacing = 6,
	TabMinimumWidth = 82,
	TabMaximumWidth = 190,
	MinTextScale = 0.78,
	MaxTextScale = 1.5,
}

GrayUI.Theme = Theme
GrayUI.Defaults = Defaults

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

local function inputPosition2(input)
	local position = input.Position
	return Vector2.new(position.X, position.Y)
end

local function pointerPosition(input, mode)
	if mode == "Mouse" then
		return UserInputService:GetMouseLocation()
	end
	return inputPosition2(input)
end

local function isTextObject(object)
	return object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")
end

local function bindResponsiveTypography(root, referenceSize, options)
	local enabled = options.ScaleText ~= false
	local minimumScale = options.MinTextScale or Defaults.MinTextScale
	local maximumScale = options.MaxTextScale or Defaults.MaxTextScale
	local baseSizes = setmetatable({}, { __mode = "k" })
	local currentScale = 1
	local updateQueued = false

	local function register(object)
		if isTextObject(object) and not baseSizes[object] then
			baseSizes[object] = object.TextSize
		end
	end

	local function update()
		updateQueued = false
		if not root.Parent then
			return
		end

		local size = root.AbsoluteSize
		local widthRatio = size.X / math.max(1, referenceSize.X)
		local heightRatio = size.Y / math.max(1, referenceSize.Y)
		currentScale = enabled
			and math.clamp(math.sqrt(widthRatio * heightRatio), minimumScale, maximumScale)
			or 1

		for object, baseSize in pairs(baseSizes) do
			if object.Parent then
				object.TextSize = math.max(8, math.floor(baseSize * currentScale + 0.5))
			else
				baseSizes[object] = nil
			end
		end
	end

	local function queueUpdate()
		if not updateQueued then
			updateQueued = true
			task.defer(update)
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		register(descendant)
	end
	root.DescendantAdded:Connect(function(descendant)
		register(descendant)
		queueUpdate()
	end)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueUpdate)
	queueUpdate()

	return {
		GetScale = function()
			return currentScale
		end,
		Refresh = function()
			for _, descendant in ipairs(root:GetDescendants()) do
				if isTextObject(descendant) then
					baseSizes[descendant] = descendant.TextSize / math.max(currentScale, 0.001)
				end
			end
			queueUpdate()
		end,
		SetEnabled = function(value)
			enabled = value == true
			queueUpdate()
		end,
	}
end

local function makeDraggable(handle, target)
	local dragging = false
	local dragMode
	local touchInput
	local dragStart
	local startPosition
	local startTopLeft
	local startSize

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragMode = input.UserInputType == Enum.UserInputType.Touch and "Touch" or "Mouse"
			touchInput = dragMode == "Touch" and input or nil
			dragStart = pointerPosition(input, dragMode)
			startPosition = target.Position
			startTopLeft = target.AbsolutePosition
			startSize = target.AbsoluteSize

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					dragMode = nil
					touchInput = nil
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		local isMouseMove = dragMode == "Mouse"
			and input.UserInputType == Enum.UserInputType.MouseMovement
		local isTouchMove = dragMode == "Touch" and input == touchInput

		if dragging and (isMouseMove or isTouchMove) then
			local delta = pointerPosition(input, dragMode) - dragStart
			local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
				or Vector2.new(1920, 1080)
			local desiredTopLeft = startTopLeft + delta
			local maximumX = math.max(4, viewport.X - startSize.X - 4)
			local maximumY = math.max(4, viewport.Y - startSize.Y - 4)
			local clampedTopLeft = Vector2.new(
				math.clamp(desiredTopLeft.X, 4, maximumX),
				math.clamp(desiredTopLeft.Y, 4, maximumY)
			)
			local appliedDelta = clampedTopLeft - startTopLeft

			target.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + appliedDelta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + appliedDelta.Y
			)
		end
	end)
end

local function makeResizable(handle, target, minimum, maximum)
	local resizing = false
	local resizeMode
	local touchInput
	local resizeStart
	local startSize
	local startTopLeft
	local startPosition

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeMode = input.UserInputType == Enum.UserInputType.Touch and "Touch" or "Mouse"
			touchInput = resizeMode == "Touch" and input or nil
			resizeStart = pointerPosition(input, resizeMode)
			startSize = target.AbsoluteSize
			startTopLeft = target.AbsolutePosition
			startPosition = target.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
					resizeMode = nil
					touchInput = nil
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		local isMouseMove = resizeMode == "Mouse"
			and input.UserInputType == Enum.UserInputType.MouseMovement
		local isTouchMove = resizeMode == "Touch" and input == touchInput

		if resizing and (isMouseMove or isTouchMove) then
			local delta = pointerPosition(input, resizeMode) - resizeStart
			local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
				or Vector2.new(1920, 1080)
			local maximumWidth = math.max(minimum.X, math.min(maximum.X, viewport.X - startTopLeft.X - 4))
			local maximumHeight = math.max(minimum.Y, math.min(maximum.Y, viewport.Y - startTopLeft.Y - 4))
			local width = math.clamp(startSize.X + delta.X, minimum.X, maximumWidth)
			local height = math.clamp(startSize.Y + delta.Y, minimum.Y, maximumHeight)
			target.Size = UDim2.fromOffset(width, height)
			target.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + (width - startSize.X) * target.AnchorPoint.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + (height - startSize.Y) * target.AnchorPoint.Y
			)
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
	addCorner(button, options.Radius or Defaults.ControlRadius)
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
	addCorner(row, options.Radius or Defaults.ControlRadius)
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
	addCorner(row, options.Radius or Defaults.ControlRadius)
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

	local scroller = create("ScrollingFrame", {
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		HorizontalScrollBarInset = Enum.ScrollBarInset.None,
		Position = UDim2.fromOffset(10, 33),
		ScrollBarImageTransparency = 1,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		Size = UDim2.new(1, -20, 1, -43),
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		Parent = row,
	})
	addCorner(scroller, 6)

	local box = create("TextBox", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = options.Code == false and Enum.Font.Gotham or Enum.Font.Code,
		MultiLine = true,
		PlaceholderColor3 = Color3.fromRGB(92, 98, 108),
		PlaceholderText = tostring(options.Placeholder or ""),
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(100, 100),
		Text = tostring(options.Default or ""),
		TextColor3 = Theme.Text,
		TextSize = options.TextSize or 13,
		TextWrapped = options.Wrap == true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = scroller,
	})

	-- Native nested scrollbars can render outside an ancestor ScrollingFrame.
	-- These normal Frames stay clipped by the rounded text-area row instead.
	local verticalTrack = create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -7, 0, 36),
		Size = UDim2.new(0, 3, 1, -48),
		Visible = false,
		ZIndex = 6,
		Parent = row,
	})
	addCorner(verticalTrack, 2)
	local verticalThumb = create("Frame", {
		BackgroundColor3 = Theme.Muted,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(3, 18),
		ZIndex = 7,
		Parent = verticalTrack,
	})
	addCorner(verticalThumb, 2)

	local horizontalTrack = create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 12, 1, -7),
		Size = UDim2.new(1, -24, 0, 3),
		Visible = false,
		ZIndex = 6,
		Parent = row,
	})
	addCorner(horizontalTrack, 2)
	local horizontalThumb = create("Frame", {
		BackgroundColor3 = Theme.Muted,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(18, 3),
		ZIndex = 7,
		Parent = horizontalTrack,
	})
	addCorner(horizontalThumb, 2)

	local canvasPixels = Vector2.new(1, 1)
	local function updateIndicators()
		if not scroller.Parent then
			return
		end

		local viewportSize = scroller.AbsoluteSize
		local overflowX = math.max(0, canvasPixels.X - viewportSize.X)
		local overflowY = math.max(0, canvasPixels.Y - viewportSize.Y)
		local horizontalWidth = horizontalTrack.AbsoluteSize.X
		local verticalHeight = verticalTrack.AbsoluteSize.Y

		horizontalTrack.Visible = overflowX > 1 and horizontalWidth > 0
		if horizontalTrack.Visible then
			local thumbWidth = math.max(18, math.floor(horizontalWidth * viewportSize.X / canvasPixels.X + 0.5))
			thumbWidth = math.min(horizontalWidth, thumbWidth)
			local progress = math.clamp(scroller.CanvasPosition.X / overflowX, 0, 1)
			horizontalThumb.Size = UDim2.fromOffset(thumbWidth, 3)
			horizontalThumb.Position = UDim2.fromOffset((horizontalWidth - thumbWidth) * progress, 0)
		end

		verticalTrack.Visible = overflowY > 1 and verticalHeight > 0
		if verticalTrack.Visible then
			local thumbHeight = math.max(18, math.floor(verticalHeight * viewportSize.Y / canvasPixels.Y + 0.5))
			thumbHeight = math.min(verticalHeight, thumbHeight)
			local progress = math.clamp(scroller.CanvasPosition.Y / overflowY, 0, 1)
			verticalThumb.Size = UDim2.fromOffset(3, thumbHeight)
			verticalThumb.Position = UDim2.fromOffset(0, (verticalHeight - thumbHeight) * progress)
		end
	end

	local function updateCanvas()
		if not scroller.Parent then
			return
		end

		local minimumWidth = math.max(80, scroller.AbsoluteSize.X - 16)
		local minimumHeight = math.max(80, scroller.AbsoluteSize.Y - 16)
		local textBounds = box.TextBounds
		local contentWidth = options.Wrap == true and minimumWidth
			or math.max(minimumWidth, math.ceil(textBounds.X) + 20)
		local contentHeight = math.max(minimumHeight, math.ceil(textBounds.Y) + 20)

		box.Size = UDim2.fromOffset(contentWidth, contentHeight)
		canvasPixels = Vector2.new(contentWidth + 16, contentHeight + 16)
		scroller.CanvasSize = UDim2.fromOffset(canvasPixels.X, canvasPixels.Y)
		task.defer(updateIndicators)
	end

	box:GetPropertyChangedSignal("Text"):Connect(updateCanvas)
	box:GetPropertyChangedSignal("TextBounds"):Connect(updateCanvas)
	scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas)
	scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(updateIndicators)
	horizontalTrack:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateIndicators)
	verticalTrack:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateIndicators)
	task.defer(updateCanvas)

	local controller = { Object = box, Row = row, Scroller = scroller }
	function controller:Get()
		return box.Text
	end
	function controller:Set(text)
		box.Text = tostring(text or "")
		task.defer(updateCanvas)
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
	addCorner(button, options.Radius or Defaults.ControlRadius)
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
	addCorner(main, options.Radius or Defaults.ControlRadius)
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
	addCorner(optionsFrame, options.Radius or Defaults.ControlRadius)
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

function Section:SetSpacing(pixels)
	self.Layout.Padding = UDim.new(0, math.max(0, tonumber(pixels) or 0))
end

local Page = {}
Page.__index = Page

function Page:AddSection(title)
	local options = type(title) == "table" and title or { Title = title }
	local frame = create("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = self.Container,
	})
	addCorner(frame, options.Radius or Defaults.SectionRadius)
	addStroke(frame, Theme.Stroke, 0.35)
	local sectionPadding = options.Padding or 10
	addPadding(frame, sectionPadding)
	local layout = create("UIListLayout", {
		Padding = UDim.new(0, options.Spacing or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})

	create("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 18),
		Text = tostring(options.Title or options.Text or "Section"),
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	return setmetatable({
		Container = frame,
		Layout = layout,
		Page = self,
	}, Section)
end

function Page:SetSpacing(pixels)
	self.Layout.Padding = UDim.new(0, math.max(0, tonumber(pixels) or 0))
end

function Page:Select()
	self.Window:SelectTab(self)
end

function Page:SetName(name)
	self.Name = tostring(name or "Tab")
	self.Button.Text = self.Name
	self.Window:_QueueTabLayout()
end

function Page:Destroy()
	local tabs = self.Window.Tabs
	local index = table.find(tabs, self)
	if not index then
		return
	end

	local wasActive = self.Window.ActiveTab == self
	table.remove(tabs, index)
	self.Button:Destroy()
	self.Container:Destroy()
	if wasActive then
		self.Window.ActiveTab = nil
		local replacement = tabs[math.min(index, #tabs)]
		if replacement then
			self.Window:SelectTab(replacement)
		end
	end
	self.Window:_QueueTabLayout()
end

local Window = {}
Window.__index = Window

function Window:_UpdateTabLayout()
	self._TabLayoutQueued = false
	local count = #self.Tabs
	if count == 0 or not self.TabBar.Parent then
		return
	end

	local available = math.max(1, self.TabBar.AbsoluteSize.X - self.TabSidePadding * 2)
	local spacing = self.TabSpacing
	local totalDesired = spacing * math.max(0, count - 1)
	for _, tab in ipairs(self.Tabs) do
		local measured = math.max(tab.Button.TextBounds.X, #tab.Name * 7)
		tab._DesiredWidth = math.clamp(
			measured + 30,
			tab.MinimumWidth or self.TabMinimumWidth,
			tab.MaximumWidth or self.TabMaximumWidth
		)
		totalDesired = totalDesired + tab._DesiredWidth
	end

	local overflow = totalDesired > available
	local extraPerTab = overflow and 0 or (available - totalDesired) / count
	local finalWidth = spacing * math.max(0, count - 1)
	for _, tab in ipairs(self.Tabs) do
		local width = math.floor(tab._DesiredWidth + extraPerTab + 0.5)
		tab.Button.Size = UDim2.fromOffset(width, 32)
		finalWidth = finalWidth + width
	end

	-- Horizontal wheel/touch scrolling still works; keeping the native bar hidden
	-- prevents its end-cap images from escaping the rounded tab viewport.
	self.TabBar.ScrollBarThickness = 0
	self.TabBar.CanvasSize = overflow
		and UDim2.fromOffset(finalWidth + self.TabSidePadding * 2, 0)
		or UDim2.new()
end

function Window:_QueueTabLayout()
	if self._TabLayoutQueued then
		return
	end
	self._TabLayoutQueued = true
	task.defer(function()
		self:_UpdateTabLayout()
	end)
end

function Window:SelectTab(target)
	if type(target) == "string" then
		for _, tab in ipairs(self.Tabs) do
			if tab.Name == target then
				target = tab
				break
			end
		end
	end
	if type(target) ~= "table" or target.Window ~= self then
		return false
	end

	self.ActiveTab = target
	for _, tab in ipairs(self.Tabs) do
		local active = tab == target
		tab.Container.Visible = active
		tween(tab.Button, {
			BackgroundColor3 = active and Theme.Control or Theme.Panel,
			TextColor3 = active and Theme.Text or Theme.Muted,
		})
	end

	task.defer(function()
		if not target.Button.Parent then
			return
		end
		local bar = self.TabBar
		local left = target.Button.AbsolutePosition.X - bar.AbsolutePosition.X + bar.CanvasPosition.X
		local right = left + target.Button.AbsoluteSize.X
		local visibleLeft = bar.CanvasPosition.X
		local visibleRight = visibleLeft + bar.AbsoluteSize.X
		if left < visibleLeft then
			bar.CanvasPosition = Vector2.new(math.max(0, left - self.TabSidePadding), 0)
		elseif right > visibleRight then
			bar.CanvasPosition = Vector2.new(right - bar.AbsoluteSize.X + self.TabSidePadding, 0)
		end
	end)

	if type(target.OnSelected) == "function" then
		task.spawn(target.OnSelected, target)
	end
	return true
end

function Window:AddTab(name, tabOptions)
	if type(name) == "table" then
		tabOptions = name
		name = tabOptions.Name or tabOptions.Text
	else
		tabOptions = tabOptions or {}
	end
	name = tostring(name or "Tab")

	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = tabOptions.Order or (#self.Tabs + 1),
		Size = UDim2.fromOffset(self.TabMinimumWidth, 32),
		Text = name,
		TextColor3 = Theme.Muted,
		TextSize = tabOptions.TextSize or 12,
		Parent = self.TabBar,
	})
	addCorner(button, tabOptions.Radius or Defaults.TabRadius)

	local scrolling = create("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Position = UDim2.fromOffset(2, 3),
		ScrollBarImageColor3 = Theme.Stroke,
		ScrollBarImageTransparency = 0.15,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.new(1, -8, 1, -6),
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		Visible = false,
		Parent = self.PageHolder,
	})
	addPadding(scrolling, 2, 5, 2, 8)
	local pageLayout = create("UIListLayout", {
		Padding = UDim.new(0, tabOptions.Spacing or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scrolling,
	})
	local function updatePageCanvas()
		if scrolling.Parent then
			scrolling.CanvasSize = UDim2.fromOffset(0, pageLayout.AbsoluteContentSize.Y + 12)
		end
	end
	pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updatePageCanvas)
	scrolling:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePageCanvas)
	task.defer(updatePageCanvas)

	local page = setmetatable({
		Button = button,
		Container = scrolling,
		Name = name,
		Layout = pageLayout,
		MinimumWidth = tabOptions.MinimumWidth,
		MaximumWidth = tabOptions.MaximumWidth,
		OnSelected = tabOptions.OnSelected,
		Window = self,
	}, Page)

	button.Activated:Connect(function()
		self:SelectTab(page)
	end)
	button.MouseEnter:Connect(function()
		tween(button, { BackgroundColor3 = Theme.ControlHover })
	end)
	button.MouseLeave:Connect(function()
		tween(button, {
			BackgroundColor3 = self.ActiveTab == page and Theme.Control or Theme.Panel,
		})
	end)
	button:GetPropertyChangedSignal("TextBounds"):Connect(function()
		self:_QueueTabLayout()
	end)
	table.insert(self.Tabs, page)
	self:_QueueTabLayout()
	if #self.Tabs == 1 then
		self:SelectTab(page)
	end

	return page
end

function Window:AddTabs(definitions)
	assert(type(definitions) == "table", "Window:AddTabs expects an array")
	local pages = table.create(#definitions)
	for index, definition in ipairs(definitions) do
		pages[index] = type(definition) == "table"
			and self:AddTab(definition)
			or self:AddTab(tostring(definition))
	end
	return pages
end

function Window:GetTab(name)
	for _, tab in ipairs(self.Tabs) do
		if tab.Name == name then
			return tab
		end
	end
	return nil
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

function Window:GetSize()
	return self.Main.AbsoluteSize
end

function Window:SetSize(size, animated)
	assert(typeof(size) == "Vector2", "Window:SetSize expects a Vector2")
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1920, 1080)
	local maximum = Vector2.new(
		math.max(self.MinimumSize.X, math.min(self.MaximumSize.X, viewport.X - 8)),
		math.max(self.MinimumSize.Y, math.min(self.MaximumSize.Y, viewport.Y - 8))
	)
	local clamped = Vector2.new(
		math.clamp(size.X, self.MinimumSize.X, maximum.X),
		math.clamp(size.Y, self.MinimumSize.Y, maximum.Y)
	)
	local targetSize = UDim2.fromOffset(clamped.X, clamped.Y)
	if animated == false then
		self.Main.Size = targetSize
	else
		tween(self.Main, { Size = targetSize }, 0.2)
	end
	return clamped
end

function Window:CycleSize()
	if #self.SizePresets == 0 then
		return self:GetSize()
	end
	self.SizePresetIndex = self.SizePresetIndex % #self.SizePresets + 1
	local preset = self.SizePresets[self.SizePresetIndex]
	local size = preset.Size or preset
	if self.SizeButton then
		self.SizeButton.Text = string.upper(tostring(preset.Name or "SIZE"))
	end
	return self:SetSize(size, true)
end

function Window:SetTextScaling(enabled)
	self.Typography:SetEnabled(enabled)
end

function Window:GetTextScale()
	return self.Typography:GetScale()
end

function Window:RefreshTypography()
	self.Typography:Refresh()
end

function Window:SetTabSpacing(pixels)
	self.TabSpacing = math.max(0, tonumber(pixels) or 0)
	self.TabLayout.Padding = UDim.new(0, self.TabSpacing)
	self:_QueueTabLayout()
end

function Window:OnResize(callback)
	assert(type(callback) == "function", "Window:OnResize expects a function")
	self._ResizeListeners[callback] = true
	task.spawn(callback, self.Main.AbsoluteSize, self)
	return function()
		self._ResizeListeners[callback] = nil
	end
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
	local largeSize = Vector2.new(
		math.min(maximum.X, math.max(initialSize.X, math.floor(initialSize.X * 1.25 + 0.5))),
		math.min(maximum.Y, math.max(initialSize.Y, math.floor(initialSize.Y * 1.25 + 0.5)))
	)
	local sizePresets = options.SizePresets or {
		{ Name = "COMPACT", Size = minimum },
		{ Name = "DEFAULT", Size = initialSize },
		{ Name = "LARGE", Size = largeSize },
	}
	local main = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(initialSize.X, initialSize.Y),
		Parent = screenGui,
	})
	addCorner(main, options.CornerRadius or Defaults.WindowRadius)
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
	addCorner(titleBar, options.CornerRadius or Defaults.WindowRadius)
	local dragZone = create("TextButton", {
		Active = true,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -120, 1, 0),
		Text = "",
		ZIndex = 4,
		Parent = titleBar,
	})
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -270, 1, 0),
		Text = tostring(options.Title or "Gray UI"),
		TextColor3 = Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = titleBar,
	})
	local subtitle = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.new(1, -252, 0, 0),
		Size = UDim2.fromOffset(132, 48),
		Text = tostring(options.Subtitle or ""),
		TextColor3 = Theme.Muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
		Parent = titleBar,
	})
	local sizeButton = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -108, 0, 10),
		Size = UDim2.fromOffset(52, 28),
		Text = "SIZE",
		TextColor3 = Theme.Text,
		TextSize = 9,
		ZIndex = 5,
		Parent = titleBar,
	})
	addCorner(sizeButton, Defaults.ControlRadius)
	addStroke(sizeButton, Theme.Stroke, 0.25)
	bindHover(sizeButton, Theme.Control, Theme.ControlHover)

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
		ZIndex = 5,
		Parent = titleBar,
	})
	addCorner(close, 6)
	bindHover(close, Theme.Control, Color3.fromRGB(91, 43, 47))
	local tabBar = create("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		HorizontalScrollBarInset = Enum.ScrollBarInset.Always,
		Position = UDim2.fromOffset(10, 52),
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Size = UDim2.new(1, -20, 0, 40),
		Parent = main,
	})
	addCorner(tabBar, Defaults.TabRadius)
	local tabSidePadding = options.TabSidePadding or 12
	addPadding(tabBar, tabSidePadding, tabSidePadding, 4, 4)
	local tabLayout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, options.TabSpacing or Defaults.TabSpacing),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})

	local resizeFooter = create("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 8, 1, -42),
		Size = UDim2.new(1, -16, 0, 34),
		Parent = main,
	})
	addCorner(resizeFooter, Defaults.SectionRadius)
	addStroke(resizeFooter, Theme.Stroke, 0.3)
	local resizeStatus = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -54, 1, 0),
		Text = string.format("%d × %d · TEXT 100%%", initialSize.X, initialSize.Y),
		TextColor3 = Theme.Muted,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = resizeFooter,
	})

	local pageHolder = create("Frame", {
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.02,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(12, 102),
		Size = UDim2.new(1, -24, 1, -154),
		Parent = main,
	})
	addCorner(pageHolder, Defaults.SectionRadius)

	local resizeHandle = create("TextButton", {
		Active = true,
		AnchorPoint = Vector2.new(1, 0.5),
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Control,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		Position = UDim2.new(1, -3, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		Text = "◢",
		TextColor3 = Theme.Text,
		TextSize = 15,
		ZIndex = 50,
		Parent = resizeFooter,
	})
	addCorner(resizeHandle, 10)
	addStroke(resizeHandle, Theme.Stroke, 0.25, 1)
	bindHover(resizeHandle, Theme.Control, Theme.ControlHover)

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
	addCorner(reopen, Defaults.SectionRadius)
	addStroke(reopen, Theme.Stroke, 0.05)
	bindHover(reopen, Theme.PanelLight, Theme.ControlHover)

	local window = setmetatable({
		Main = main,
		PageHolder = pageHolder,
		ScreenGui = screenGui,
		Scale = mainScale,
		Reopen = reopen,
		TabBar = tabBar,
		TabLayout = tabLayout,
		TabSidePadding = tabSidePadding,
		TabSpacing = options.TabSpacing or Defaults.TabSpacing,
		TabMinimumWidth = options.TabMinimumWidth or Defaults.TabMinimumWidth,
		TabMaximumWidth = options.TabMaximumWidth or Defaults.TabMaximumWidth,
		Tabs = {},
		ActiveTab = nil,
		MinimumSize = minimum,
		MaximumSize = maximum,
		ResizeHandle = resizeHandle,
		ResizeStatus = resizeStatus,
		SizeButton = sizeButton,
		SizePresets = sizePresets,
		SizePresetIndex = math.min(2, #sizePresets),
		_ResizeListeners = {},
		_ResizeUpdateQueued = false,
		Theme = Theme,
	}, Window)

	window.Typography = bindResponsiveTypography(main, initialSize, options)
	main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		window:_QueueTabLayout()
		if not window._ResizeUpdateQueued then
			window._ResizeUpdateQueued = true
			task.defer(function()
				window._ResizeUpdateQueued = false
				for callback in pairs(window._ResizeListeners) do
					task.spawn(callback, main.AbsoluteSize, window)
				end
			end)
		end
	end)
	tabBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		window:_QueueTabLayout()
	end)

	makeDraggable(dragZone, main)
	makeDraggable(reopen, reopen)
	makeResizable(resizeHandle, main, minimum, maximum)
	window:_QueueTabLayout()

	window:OnResize(function(size)
		if resizeStatus.Parent then
			resizeStatus.Text = string.format(
				"%d × %d · TEXT %d%%",
				math.floor(size.X + 0.5),
				math.floor(size.Y + 0.5),
				math.floor(window:GetTextScale() * 100 + 0.5)
			)
		end
	end)

	sizeButton.Activated:Connect(function()
		window:CycleSize()
	end)

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
