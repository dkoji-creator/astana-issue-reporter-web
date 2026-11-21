-- UI-кит «Звёздной оранжереи»: тёмное полупрозрачное стекло, тонкие рамки, сдержанные акценты (золото, бирюза).
-- API совместим с прежним китом: make, text, panel, button, iconButton, pill, window, open, close, scroll, bar, viewport, icon, recolor.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Icons"))

local K = {}
K.Icons = Icons
local rgb = Color3.fromRGB
K.T = {
	ink = rgb(6, 9, 18),
	panel = rgb(12, 17, 30),
	panel2 = rgb(22, 30, 50),
	line = rgb(110, 150, 200),
	text = rgb(236, 240, 250),
	sub = rgb(150, 162, 192),
	gold = rgb(232, 192, 112),
	blue = rgb(88, 150, 230),
	green = rgb(84, 196, 150),
	red = rgb(220, 90, 96),
	orange = rgb(232, 150, 84),
	purple = rgb(150, 120, 230),
	pink = rgb(220, 120, 180),
	cold = rgb(90, 200, 210),
}
local T = K.T
K.Font = Enum.Font.GothamBold
K.FontMedium = Enum.Font.GothamMedium

function K.make(class, props, parent)
	local o = Instance.new(class)
	for k, v in props or {} do
		o[k] = v
	end
	if parent then o.Parent = parent end
	return o
end
local make = K.make

function K.corner(o, r)
	return make("UICorner", { CornerRadius = r or UDim.new(0, 10) }, o)
end
function K.stroke(o, color, th, contextual, transparency)
	return make("UIStroke", {
		Color = color or T.line, Thickness = th or 1, Transparency = transparency or 0.55,
		ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, o)
end
function K.gradient(o, top, bottom, rot)
	return make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rot or 90 }, o)
end
local function lighten(c, k) return c:Lerp(Color3.new(1, 1, 1), k) end
local function darken(c, k) return c:Lerp(Color3.new(0, 0, 0), k) end
K.lighten, K.darken = lighten, darken

-- текст: чистый шрифт, лёгкая тень вместо толстой обводки
function K.text(parent, text, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1, Text = text or "", TextScaled = true, Font = K.Font,
		TextColor3 = T.text, Size = UDim2.fromScale(1, 1),
	}, parent)
	for k, v in props or {} do
		if k ~= "MaxText" and k ~= "StrokeThickness" and k ~= "Medium" then l[k] = v end
	end
	if props and props.Medium then l.Font = K.FontMedium end
	make("UIStroke", { Color = T.ink, Thickness = 1, Transparency = 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	make("UITextSizeConstraint", { MaxTextSize = (props and props.MaxText) or 22, MinTextSize = 7 }, l)
	return l
end

-- стеклянная панель
function K.panel(parent, props)
	local f = make("Frame", { BackgroundColor3 = T.panel, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, parent)
	for k, v in props or {} do f[k] = v end
	K.corner(f, UDim.new(0, 12))
	K.stroke(f, T.line, 1, false, 0.62)
	K.gradient(f, Color3.new(1, 1, 1), rgb(200, 210, 230))
	return f
end

function K.icon(parent, key, props)
	local i = make("ImageLabel", { BackgroundTransparency = 1, Image = Icons[key] or "", ScaleType = Enum.ScaleType.Fit }, parent)
	for k, v in props or {} do i[k] = v end
	return i
end

-- пружинящее нажатие
function K.bounce(o)
	local sc = o:FindFirstChild("Bounce") or make("UIScale", { Name = "Bounce" }, o)
	sc.Scale = 0.92
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
function K.pop(o)
	local sc = o:FindFirstChild("Bounce") or make("UIScale", { Name = "Bounce" }, o)
	sc.Scale = 1.12
	TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local clickHook = nil
function K.onClick(fn) clickHook = fn end

-- кнопка: мягкий градиент акцентного цвета, тонкая светлая кромка
function K.button(parent, text, color, props)
	local b = make("TextButton", {
		BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "", BorderSizePixel = 0,
	}, parent)
	for k, v in props or {} do
		if k ~= "MaxText" then b[k] = v end
	end
	K.corner(b, UDim.new(0, 9))
	K.stroke(b, lighten(color, 0.45), 1, false, 0.45)
	K.gradient(b, lighten(color, 0.08), darken(color, 0.32))
	local lbl = K.text(b, text, { Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), MaxText = (props and props.MaxText) or 18 })
	b.Activated:Connect(function()
		K.bounce(b)
		if clickHook then clickHook() end
	end)
	return b, lbl
end
function K.recolor(b, color)
	local g = b:FindFirstChildOfClass("UIGradient")
	if g then g.Color = ColorSequence.new(lighten(color, 0.08), darken(color, 0.32)) end
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then s.Color = lighten(color, 0.45) end
end

-- квадратная стеклянная кнопка с иконкой и короткой подписью (левая колонка)
function K.iconButton(parent, iconKey, label, color, size)
	size = size or 56
	local b = make("TextButton", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = T.panel, BackgroundTransparency = 0.15, AutoButtonColor = false, Text = "" }, parent)
	K.corner(b, UDim.new(0, 12))
	local st = K.stroke(b, color, 1.2, false, 0.35)
	K.gradient(b, lighten(T.panel2, 0.08), T.panel)
	local glow = make("Frame", { Name = "Accent", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(0.5, 0, 0, 2), BackgroundColor3 = color, BorderSizePixel = 0 }, b)
	K.corner(glow, UDim.new(1, 0))
	K.icon(b, iconKey, { Size = UDim2.fromScale(0.56, 0.56), Position = UDim2.fromScale(0.22, 0.08) })
	K.text(b, label, { Size = UDim2.new(1, 4, 0.26, 0), Position = UDim2.new(0, -2, 0.66, 0), MaxText = 11, TextColor3 = T.sub, Medium = true })
	local badge = make("Frame", { Name = "Badge", Size = UDim2.fromOffset(12, 12), Position = UDim2.new(1, -9, 0, -3), BackgroundColor3 = T.gold, Visible = false }, b)
	K.corner(badge, UDim.new(1, 0))
	K.stroke(badge, T.ink, 1.5, false, 0)
	b.Activated:Connect(function()
		K.bounce(b)
		if clickHook then clickHook() end
	end)
	return b
end

-- плашка с иконкой и числом (валюта)
function K.pill(parent, iconKey, color, width)
	local f = make("Frame", { Size = UDim2.fromOffset(width or 150, 34), BackgroundColor3 = T.panel, BackgroundTransparency = 0.15 }, parent)
	K.corner(f, UDim.new(1, 0))
	K.stroke(f, color, 1, false, 0.4)
	K.icon(f, iconKey, { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(6, 4) })
	local l = K.text(f, "0", { Size = UDim2.new(1, -46, 1, -10), Position = UDim2.fromOffset(38, 5), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20 })
	return f, l
end

-- окна живут в отдельном слое без UIScale: их размер на телефоне задаётся долями экрана
local function windowLayer(parent)
	local pg = parent:IsA("ScreenGui") and parent.Parent
	if not pg then return parent end
	local layer = pg:FindFirstChild("SpiritWindows")
	if not layer then
		layer = make("ScreenGui", { Name = "SpiritWindows", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)
	end
	return layer
end
function K.window(parent, title, iconKey, color, w, h)
	parent = windowLayer(parent)
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.fromScale(w or 0.84, h or 0.8),
		BackgroundColor3 = T.panel, BackgroundTransparency = 0.06, Visible = false, ZIndex = 5,
	}, parent)
	K.corner(f, UDim.new(0, 16))
	K.stroke(f, T.line, 1, false, 0.5)
	K.gradient(f, rgb(255, 255, 255), rgb(190, 200, 225))
	make("UISizeConstraint", { MaxSize = Vector2.new(1100, 720) }, f)
	-- шапка: иконка, заголовок, тонкая акцентная линия
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, f)
	K.icon(head, iconKey, { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(14, 7) })
	local t = K.text(head, string.upper(title), { Size = UDim2.new(1, -120, 0, 22), Position = UDim2.fromOffset(48, 9), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 19 })
	local line = make("Frame", { Position = UDim2.new(0, 14, 1, -1), Size = UDim2.new(1, -28, 0, 1), BackgroundColor3 = color, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, head)
	K.gradient(line, color, T.panel, 0)
	local close = make("TextButton", { Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 5), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, ZIndex = 6 }, f)
	K.corner(close, UDim.new(1, 0))
	K.stroke(close, T.line, 1, false, 0.4)
	K.text(close, "X", { MaxText = 14, ZIndex = 6, TextColor3 = T.sub })
	close.Activated:Connect(function()
		if clickHook then clickHook() end
		K.close(f)
	end)
	local body = make("Frame", { Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 1, -54), BackgroundTransparency = 1 }, f)
	return f, body, t
end

function K.open(f)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if vp.Y > 0 and vp.Y < 760 then
		f.Size = UDim2.fromScale(0.9, 0.86)
		f.Position = UDim2.fromScale(0.53, 0.54) -- правее левой колонки кнопок
	end
	f.Visible = true
	local sc = f:FindFirstChild("Bounce") or make("UIScale", { Name = "Bounce" }, f)
	sc.Scale = 0.94
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
function K.close(f)
	f.Visible = false
end

function K.scroll(parent, props)
	local s = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = T.line, ScrollBarImageTransparency = 0.3,
		ScrollingDirection = Enum.ScrollingDirection.Y, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Size = UDim2.fromScale(1, 1),
	}, parent)
	for k, v in props or {} do s[k] = v end
	return s
end

-- тонкая полоска прогресса
function K.bar(parent, color, props)
	local back = make("Frame", { BackgroundColor3 = T.ink, BackgroundTransparency = 0.3, Size = UDim2.new(1, 0, 0, 6) }, parent)
	for k, v in props or {} do back[k] = v end
	K.corner(back, UDim.new(1, 0))
	local fill = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0, 1) }, back)
	K.corner(fill, UDim.new(1, 0))
	K.gradient(fill, darken(color, 0.15), lighten(color, 0.2), 0)
	return back, fill
end

-- 3D-превью модели в интерфейсе
function K.viewport(parent, model, props)
	local vp = make("ViewportFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Ambient = rgb(150, 150, 175), LightColor = Color3.new(1, 0.97, 0.92), LightDirection = Vector3.new(-1, -1.2, -0.6) }, parent)
	for k, v in props or {} do vp[k] = v end
	local cam = make("Camera", { FieldOfView = 30 }, vp)
	vp.CurrentCamera = cam
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local r = math.max(size.X, size.Y, size.Z)
	local dist = r / math.tan(math.rad(15)) * 0.6
	local function setAngle(a)
		local offset = CFrame.Angles(0, a, 0) * CFrame.new(0, r * 0.28, -dist)
		cam.CFrame = CFrame.lookAt((cf * offset).Position, cf.Position)
	end
	setAngle(math.rad(-35))
	return vp, setAngle
end

return K
