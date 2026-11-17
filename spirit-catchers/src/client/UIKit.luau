-- UI-кит в стиле популярных симуляторов: толстые контуры, градиенты, иконки, пружинящие кнопки.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Icons"))

local K = {}
K.Icons = Icons
K.T = {
	ink = Color3.fromRGB(24, 20, 38),
	panel = Color3.fromRGB(34, 32, 58),
	panel2 = Color3.fromRGB(48, 46, 80),
	text = Color3.new(1, 1, 1),
	sub = Color3.fromRGB(200, 205, 230),
	gold = Color3.fromRGB(255, 205, 70),
	blue = Color3.fromRGB(80, 150, 255),
	green = Color3.fromRGB(80, 210, 120),
	red = Color3.fromRGB(235, 70, 80),
	orange = Color3.fromRGB(255, 140, 60),
	purple = Color3.fromRGB(160, 110, 255),
	pink = Color3.fromRGB(255, 120, 190),
	cold = Color3.fromRGB(120, 210, 255),
}
local T = K.T

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
	return make("UICorner", { CornerRadius = r or UDim.new(0, 12) }, o)
end
function K.stroke(o, color, th, contextual)
	return make("UIStroke", {
		Color = color or T.ink, Thickness = th or 3,
		ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, o)
end
function K.gradient(o, top, bottom)
	return make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, o)
end
local function lighten(c, k) return c:Lerp(Color3.new(1, 1, 1), k) end
local function darken(c, k) return c:Lerp(Color3.new(0, 0, 0), k) end
K.lighten, K.darken = lighten, darken

-- текст с тёмной обводкой (как в популярных плейсах)
function K.text(parent, text, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1, Text = text or "", TextScaled = true, Font = Enum.Font.GothamBlack,
		TextColor3 = T.text, Size = UDim2.fromScale(1, 1),
	}, parent)
	for k, v in props or {} do
		if k ~= "MaxText" and k ~= "StrokeThickness" then l[k] = v end
	end
	K.stroke(l, T.ink, (props and props.StrokeThickness) or 2, true)
	make("UITextSizeConstraint", { MaxTextSize = (props and props.MaxText) or 28 }, l)
	return l
end

function K.panel(parent, props)
	local f = make("Frame", { BackgroundColor3 = T.panel, BorderSizePixel = 0 }, parent)
	for k, v in props or {} do f[k] = v end
	K.corner(f, UDim.new(0, 14))
	K.stroke(f, T.ink, 3)
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
	sc.Scale = 0.88
	TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
function K.pop(o)
	local sc = o:FindFirstChild("Bounce") or make("UIScale", { Name = "Bounce" }, o)
	sc.Scale = 1.18
	TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local clickHook = nil
function K.onClick(fn) clickHook = fn end

function K.button(parent, text, color, props)
	local b = make("TextButton", {
		BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "", BorderSizePixel = 0,
	}, parent)
	for k, v in props or {} do
		if k ~= "MaxText" then b[k] = v end
	end
	K.corner(b, UDim.new(0, 12))
	K.stroke(b, T.ink, 3)
	K.gradient(b, lighten(color, 0.25), darken(color, 0.1))
	local lbl = K.text(b, text, { Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), MaxText = (props and props.MaxText) or 24 })
	b.Activated:Connect(function()
		K.bounce(b)
		if clickHook then clickHook() end
	end)
	return b, lbl
end
function K.recolor(b, color)
	local g = b:FindFirstChildOfClass("UIGradient")
	if g then g.Color = ColorSequence.new(lighten(color, 0.25), darken(color, 0.1)) end
end

-- квадратная кнопка с иконкой и подписью (левая колонка)
function K.iconButton(parent, iconKey, label, color, size)
	size = size or 70
	local b = make("TextButton", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "" }, parent)
	K.corner(b, UDim.new(0, 16))
	K.stroke(b, T.ink, 3)
	K.gradient(b, lighten(color, 0.3), darken(color, 0.15))
	K.icon(b, iconKey, { Size = UDim2.fromScale(0.68, 0.68), Position = UDim2.fromScale(0.16, 0.02) })
	K.text(b, label, { Size = UDim2.new(1, 4, 0.3, 0), Position = UDim2.new(0, -2, 0.72, 0), MaxText = 15 })
	local badge = make("Frame", { Name = "Badge", Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -14, 0, -6), BackgroundColor3 = T.red, Visible = false }, b)
	K.corner(badge, UDim.new(1, 0))
	K.stroke(badge, Color3.new(1, 1, 1), 2)
	K.text(badge, "!", { MaxText = 14 })
	b.Activated:Connect(function()
		K.bounce(b)
		if clickHook then clickHook() end
	end)
	return b
end

-- плашка с иконкой и числом (валюта)
function K.pill(parent, iconKey, color, width)
	local f = make("Frame", { Size = UDim2.fromOffset(width or 150, 38), BackgroundColor3 = Color3.new(1, 1, 1) }, parent)
	K.corner(f, UDim.new(1, 0))
	K.stroke(f, T.ink, 3)
	K.gradient(f, lighten(color, 0.15), darken(color, 0.25))
	K.icon(f, iconKey, { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(-12, -5) })
	local l = K.text(f, "0", { Size = UDim2.new(1, -46, 1, -8), Position = UDim2.fromOffset(38, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 22 })
	return f, l
end

-- окно: шапка с иконкой и названием, круглая кнопка закрытия
function K.window(parent, title, iconKey, color, w, h)
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.fromScale(w or 0.84, h or 0.8),
		BackgroundColor3 = T.panel, Visible = false, ZIndex = 5,
	}, parent)
	K.corner(f, UDim.new(0, 18))
	K.stroke(f, T.ink, 4)
	make("UISizeConstraint", { MaxSize = Vector2.new(980, 620) }, f)
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Color3.new(1, 1, 1) }, f)
	K.corner(head, UDim.new(0, 18))
	K.gradient(head, lighten(color, 0.2), darken(color, 0.1))
	make("Frame", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), BackgroundColor3 = darken(color, 0.05), BorderSizePixel = 0 }, head)
	K.icon(head, iconKey, { Size = UDim2.fromOffset(58, 58), Position = UDim2.fromOffset(10, -14) })
	local t = K.text(head, title, { Size = UDim2.new(1, -150, 0, 36), Position = UDim2.fromOffset(74, 7), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 30 })
	local close = make("TextButton", { Size = UDim2.fromOffset(44, 44), Position = UDim2.new(1, -30, 0, -14), BackgroundColor3 = Color3.new(1, 1, 1), Text = "", AutoButtonColor = false, ZIndex = 6 }, f)
	K.corner(close, UDim.new(1, 0))
	K.stroke(close, T.ink, 3)
	K.gradient(close, lighten(T.red, 0.2), darken(T.red, 0.15))
	K.text(close, "X", { MaxText = 26, ZIndex = 6 })
	close.Activated:Connect(function()
		if clickHook then clickHook() end
		K.close(f)
	end)
	local body = make("Frame", { Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 1, -68), BackgroundTransparency = 1 }, f)
	return f, body, t
end

function K.open(f)
	f.Visible = true
	local sc = f:FindFirstChild("Bounce") or make("UIScale", { Name = "Bounce" }, f)
	sc.Scale = 0.85
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
function K.close(f)
	f.Visible = false
end

function K.scroll(parent, props)
	local s = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = T.sub,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Size = UDim2.fromScale(1, 1),
	}, parent)
	for k, v in props or {} do s[k] = v end
	return s
end

-- полоска прогресса
function K.bar(parent, color, props)
	local back = make("Frame", { BackgroundColor3 = T.ink, Size = UDim2.new(1, 0, 0, 12) }, parent)
	for k, v in props or {} do back[k] = v end
	K.corner(back, UDim.new(1, 0))
	local fill = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0, 1) }, back)
	K.corner(fill, UDim.new(1, 0))
	K.gradient(fill, lighten(color, 0.3), color)
	return back, fill
end

-- 3D-превью модели в интерфейсе
function K.viewport(parent, model, props)
	local vp = make("ViewportFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Ambient = Color3.fromRGB(200, 200, 210), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1) }, parent)
	for k, v in props or {} do vp[k] = v end
	local cam = make("Camera", { FieldOfView = 30 }, vp)
	vp.CurrentCamera = cam
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local r = math.max(size.X, size.Y, size.Z)
	local dist = r / math.tan(math.rad(15)) * 0.62
	local function setAngle(a)
		-- духи смотрят в -Z: камера спереди и чуть сбоку
		local offset = CFrame.Angles(0, a, 0) * CFrame.new(0, r * 0.15, -dist)
		cam.CFrame = CFrame.lookAt((cf * offset).Position, cf.Position)
	end
	setAngle(math.rad(-35))
	return vp, setAngle
end

return K
