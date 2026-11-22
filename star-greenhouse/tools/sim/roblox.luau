-- Мини-эмулятор Roblox для смоук-тестов: типы данных, Instance, сервисы, сигналы, планировщик.
-- Не рендерит и не считает физику: цель — поймать ошибки выполнения в скриптах игры.

local SIM = { now = 0, errors = {}, log = {}, tasks = {} }

local function report(where, err, tb)
	table.insert(SIM.errors, where .. ": " .. tostring(err) .. "\n" .. (tb or ""))
end

-- безопасный запуск в своём потоке (как обработчики событий в Roblox)
local function runThread(where, f, ...)
	local co = coroutine.create(function(...)
		local ok, err = xpcall(f, function(e) return { e = e, tb = debug.traceback(tostring(e), 2) } end, ...)
		if not ok then report(where, err.e, err.tb) end
	end)
	local ok, err = coroutine.resume(co, ...)
	if not ok then report(where, err, debug.traceback(co)) end
	return co
end
SIM.runThread = runThread

------------------------------------------------------------------ планировщик
local realOs = os
local os = setmetatable({
	clock = function() return SIM.now end,
	time = function() return 1800000000 + math.floor(SIM.now) end,
}, { __index = realOs })
local task = {}
function task.wait(t)
	t = t or 0
	local co = coroutine.running()
	table.insert(SIM.tasks, { at = SIM.now + t, co = co })
	coroutine.yield()
	return t
end
function task.spawn(f, ...)
	if type(f) == "thread" then
		coroutine.resume(f, ...)
		return f
	end
	return runThread("task.spawn", f, ...)
end
task.defer = task.spawn
function task.delay(t, f, ...)
	local args = table.pack(...)
	table.insert(SIM.tasks, { at = SIM.now + (t or 0), fn = f, args = args })
end
function task.cancel() end
warn = function(...)
	local parts = {}
	for _, v in { ... } do table.insert(parts, tostring(v)) end
	table.insert(SIM.errors, "warn: " .. table.concat(parts, " "))
end
local function tick() return SIM.now end
local function time() return SIM.now end
local function wait(t) return task.wait(t) end

function SIM.step(dt)
	SIM.now += dt
	local due = {}
	local rest = {}
	for _, t in SIM.tasks do
		if t.at <= SIM.now then table.insert(due, t) else table.insert(rest, t) end
	end
	SIM.tasks = rest
	for _, t in due do
		if t.co then
			if coroutine.status(t.co) == "suspended" then
				local ok, err = coroutine.resume(t.co)
				if not ok then report("resume", err, debug.traceback(t.co)) end
			end
		else
			runThread("task.delay", t.fn, table.unpack(t.args, 1, t.args.n))
		end
	end
end

------------------------------------------------------------------ сигналы
local Signal = {}
Signal.__index = Signal
function Signal.new(name) return setmetatable({ name = name or "Signal", conns = {}, waiting = {} }, Signal) end
function Signal:Connect(f)
	local c = { f = f, connected = true }
	table.insert(self.conns, c)
	c.Disconnect = function() c.connected = false end
	c.Connected = true
	return c
end
Signal.connect = Signal.Connect
function Signal:Once(f)
	local c
	c = self:Connect(function(...) c.Disconnect() f(...) end)
	return c
end
function Signal:Fire(...)
	for _, c in table.clone(self.conns) do
		if c.connected then runThread("signal " .. self.name, c.f, ...) end
	end
	local w = self.waiting
	self.waiting = {}
	for _, co in w do coroutine.resume(co, ...) end
end
function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
SIM.Signal = Signal

------------------------------------------------------------------ типы данных
local function num(x) return type(x) == "number" end

local Vector3 = {}
local V3 = {}
V3.__index = function(v, k)
	if k == "X" then return rawget(v, 1) elseif k == "Y" then return rawget(v, 2) elseif k == "Z" then return rawget(v, 3)
	elseif k == "Magnitude" then return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
	elseif k == "Unit" then
		local m = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
		if m == 0 then return Vector3.new(0 / 0, 0 / 0, 0 / 0) end
		return Vector3.new(v[1] / m, v[2] / m, v[3] / m)
	end
	local m = V3[k]
	if m then return m end
	error("Vector3: нет поля " .. tostring(k), 2)
end
function Vector3.new(x, y, z) return setmetatable({ x or 0, y or 0, z or 0, __t = "Vector3" }, V3) end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)
V3.__add = function(a, b) return Vector3.new(a[1] + b[1], a[2] + b[2], a[3] + b[3]) end
V3.__sub = function(a, b) return Vector3.new(a[1] - b[1], a[2] - b[2], a[3] - b[3]) end
V3.__unm = function(a) return Vector3.new(-a[1], -a[2], -a[3]) end
V3.__mul = function(a, b)
	if num(a) then return Vector3.new(b[1] * a, b[2] * a, b[3] * a) end
	if num(b) then return Vector3.new(a[1] * b, a[2] * b, a[3] * b) end
	return Vector3.new(a[1] * b[1], a[2] * b[2], a[3] * b[3])
end
V3.__div = function(a, b)
	if num(b) then return Vector3.new(a[1] / b, a[2] / b, a[3] / b) end
	return Vector3.new(a[1] / b[1], a[2] / b[2], a[3] / b[3])
end
V3.__eq = function(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
V3.__tostring = function(a) return ("%g, %g, %g"):format(a[1], a[2], a[3]) end
function V3.Dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
function V3.Cross(a, b) return Vector3.new(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]) end
function V3.Lerp(a, b, t) return a + (b - a) * t end

local Vector2 = {}
local V2 = {}
V2.__index = function(v, k)
	if k == "X" then return v[1] elseif k == "Y" then return v[2]
	elseif k == "Magnitude" then return math.sqrt(v[1] ^ 2 + v[2] ^ 2) end
	error("Vector2: нет поля " .. tostring(k), 2)
end
function Vector2.new(x, y) return setmetatable({ x or 0, y or 0 }, V2) end
Vector2.zero = Vector2.new(0, 0)
V2.__add = function(a, b) return Vector2.new(a[1] + b[1], a[2] + b[2]) end
V2.__sub = function(a, b) return Vector2.new(a[1] - b[1], a[2] - b[2]) end
V2.__mul = function(a, b) if num(b) then return Vector2.new(a[1] * b, a[2] * b) end return Vector2.new(a[1] * b[1], a[2] * b[2]) end
V2.__div = function(a, b) if num(b) then return Vector2.new(a[1] / b, a[2] / b) end return Vector2.new(a[1] / b[1], a[2] / b[2]) end

-- CFrame: позиция + матрица поворота (столбцы: right, up, back)
local CFrame = {}
local CF = {}
local function mkcf(p, m) return setmetatable({ p = p, m = m }, CF) end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function mmul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function mvec(m, v)
	return Vector3.new(m[1] * v[1] + m[2] * v[2] + m[3] * v[3], m[4] * v[1] + m[5] * v[2] + m[6] * v[3], m[7] * v[1] + m[8] * v[2] + m[9] * v[3])
end
local function mT(m) return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] } end
function CFrame.new(a, b, c, ...)
	if a == nil then return mkcf(Vector3.zero, IDENT) end
	if num(a) then
		local extra = { ... }
		if #extra >= 9 then return mkcf(Vector3.new(a, b, c), extra) end
		return mkcf(Vector3.new(a, b, c), IDENT)
	end
	if b then return CFrame.lookAt(a, b) end
	return mkcf(a, IDENT)
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return mkcf(Vector3.zero, mmul(mmul(X, Y), Z))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.lookAt(at, target, up)
	up = up or Vector3.yAxis
	local look = (target - at)
	if look.Magnitude < 1e-9 then return mkcf(at, IDENT) end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then right = Vector3.xAxis else right = right.Unit end
	local up2 = right:Cross(look)
	return mkcf(at, { right[1], up2[1], -look[1], right[2], up2[2], -look[2], right[3], up2[3], -look[3] })
end
CFrame.identity = CFrame.new()
CF.__index = function(cf, k)
	local m = cf.m
	if k == "Position" or k == "p" then return cf.p
	elseif k == "X" then return cf.p[1] elseif k == "Y" then return cf.p[2] elseif k == "Z" then return cf.p[3]
	elseif k == "LookVector" then return Vector3.new(-m[3], -m[6], -m[9])
	elseif k == "RightVector" then return Vector3.new(m[1], m[4], m[7])
	elseif k == "UpVector" then return Vector3.new(m[2], m[5], m[8])
	elseif k == "Rotation" then return mkcf(Vector3.zero, m) end
	local f = CF[k]
	if f then return f end
	error("CFrame: нет поля " .. tostring(k), 2)
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then return mkcf(a.p + mvec(a.m, b.p), mmul(a.m, b.m)) end
	return a.p + mvec(a.m, b)
end
CF.__add = function(a, v) return mkcf(a.p + v, a.m) end
CF.__sub = function(a, v) return mkcf(a.p - v, a.m) end
function CF.Inverse(a)
	local t = mT(a.m)
	return mkcf(-mvec(t, a.p), t)
end
function CF.Lerp(a, b, t) return mkcf(a.p:Lerp(b.p, t), t < 0.5 and a.m or b.m) end
function CF.VectorToObjectSpace(a, v) return mvec(mT(a.m), v) end
function CF.VectorToWorldSpace(a, v) return mvec(a.m, v) end
function CF.PointToObjectSpace(a, v) return mvec(mT(a.m), v - a.p) end
function CF.PointToWorldSpace(a, v) return a * v end
function CF.ToObjectSpace(a, b) return a:Inverse() * b end
function CF.ToWorldSpace(a, b) return a * b end
function CF.GetComponents(a) return a.p[1], a.p[2], a.p[3], table.unpack(a.m) end

local Color3 = {}
local C3 = {}
C3.__index = function(c, k)
	if k == "R" then return c[1] elseif k == "G" then return c[2] elseif k == "B" then return c[3] end
	local f = C3[k]
	if f then return f end
	error("Color3: нет поля " .. tostring(k), 2)
end
function Color3.new(r, g, b) return setmetatable({ r or 0, g or 0, b or 0 }, C3) end
function Color3.fromRGB(r, g, b)
	assert(num(r) and num(g) and num(b), "Color3.fromRGB: нужны числа")
	return Color3.new(r / 255, g / 255, b / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local r, g, b = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i % 6 + 1][1], 0, 0
	local row = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i % 6 + 1]
	return Color3.new(row[1], row[2], row[3])
end
function C3.Lerp(a, b, t) return Color3.new(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t) end
function C3.ToHSV(c) return 0, 0, math.max(c[1], c[2], c[3]) end

local UDim = {}
function UDim.new(s, o) return { Scale = s or 0, Offset = o or 0 } end
local UDim2 = {}
local U2 = {}
U2.__index = U2
function UDim2.new(xs, xo, ys, yo) return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo), Width = UDim.new(xs, xo), Height = UDim.new(ys, yo) }, U2) end
function UDim2.fromOffset(x, y) return UDim2.new(0, x or 0, 0, y or 0) end
function UDim2.fromScale(x, y) return UDim2.new(x or 0, 0, y or 0, 0) end
function U2.Lerp(a, b, t) return b end
U2.__add = function(a, b) return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end

local function seq(kind) return { new = function(...) local a = { ... } assert(#a > 0, kind .. ".new без аргументов") return { __t = kind, a = a } end } end
local ColorSequence = seq("ColorSequence")
local NumberSequence = seq("NumberSequence")
local ColorSequenceKeypoint = seq("ColorSequenceKeypoint")
local NumberSequenceKeypoint = seq("NumberSequenceKeypoint")
local NumberRange = seq("NumberRange")
local PhysicalProperties = seq("PhysicalProperties")
local Rect = seq("Rect")
local TweenInfo = { new = function(t, ...) return { Time = t or 1, args = { ... } } end }
local DateTime = { now = function() return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000 } end }

local Random = {}
local RND = {}
RND.__index = RND
function Random.new(seed) return setmetatable({ s = seed or 1 }, RND) end
function RND.NextNumber(r, a, b)
	a, b = a or 0, b or 1
	return a + math.random() * (b - a)
end
function RND.NextInteger(r, a, b) return math.random(a, b) end

-- Enum.Тип.Имя → один и тот же объект
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, typeName)
		enumCache[typeName] = enumCache[typeName] or setmetatable({}, {
			__index = function(t, item)
				local e = rawget(t, item)
				if not e then
					e = setmetatable({ Name = item, EnumType = typeName, Value = 0 }, { __tostring = function() return "Enum." .. typeName .. "." .. item end })
					rawset(t, item, e)
				end
				return e
			end,
		})
		return enumCache[typeName]
	end,
})

------------------------------------------------------------------ Instance
local CLASS_PARENTS = {
	Part = "BasePart", WedgePart = "BasePart", SpawnLocation = "BasePart", MeshPart = "BasePart", TrussPart = "BasePart",
	BasePart = "PVInstance", Model = "PVInstance", PVInstance = "Instance",
	Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton", TextBox = "GuiObject",
	ImageLabel = "GuiObject", ScrollingFrame = "GuiObject", ViewportFrame = "GuiObject", GuiButton = "GuiObject", GuiObject = "GuiBase2d",
	ScreenGui = "LayerCollector", BillboardGui = "LayerCollector", SurfaceGui = "LayerCollector", LayerCollector = "GuiBase2d", GuiBase2d = "Instance",
	PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light", Light = "Instance",
	UIStroke = "Instance", UICorner = "Instance", UIGradient = "Instance", UIScale = "Instance",
	Trail = "Instance", Beam = "Instance", ParticleEmitter = "Instance",
	Folder = "Instance", Sound = "Instance", SoundGroup = "Instance", Attachment = "Instance",
	Highlight = "Instance", Humanoid = "Instance", Camera = "Instance",
}
local function isA(class, target)
	local c = class
	while c do
		if c == target then return true end
		c = CLASS_PARENTS[c]
	end
	return target == "Instance"
end

local Inst = {}
local instMeta = {}
local function newInstance(className)
	local self = setmetatable({}, instMeta)
	rawset(self, "__p", {
		ClassName = className, Name = className, Parent = nil, Archivable = true,
	})
	rawset(self, "__c", {})
	rawset(self, "__a", {})
	rawset(self, "__sig", {})
	local p = self.__p
	if isA(className, "BasePart") then
		p.CFrame, p.Size, p.Transparency, p.Anchored, p.CanCollide = CFrame.new(), Vector3.new(4, 1, 2), 0, false, true
		p.Color, p.Material = Color3.new(0.6, 0.6, 0.6), Enum.Material.Plastic
	end
	if isA(className, "GuiObject") then
		p.Size, p.Position, p.Visible, p.BackgroundTransparency, p.AbsolutePosition, p.AbsoluteSize = UDim2.new(), UDim2.new(), true, 0, Vector2.new(0, 0), Vector2.new(100, 40)
		p.BackgroundColor3, p.ZIndex, p.Rotation, p.LayoutOrder = Color3.new(1, 1, 1), 1, 0, 0
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		p.Text, p.TextTransparency, p.TextColor3 = className == "TextBox" and "" or "Label", 0, Color3.new()
	end
	if className == "Humanoid" then p.Health, p.WalkSpeed, p.MaxHealth = 100, 16, 100 end
	if className == "Camera" then p.ViewportSize, p.CFrame, p.FieldOfView = Vector2.new(844, 390), CFrame.new(0, 10, 20), 70 end
	if className == "Sound" then p.IsLoaded, p.Volume, p.Playing = true, 0.5, false end
	if className == "UIStroke" then p.Transparency, p.Thickness, p.Color = 0, 1, Color3.new() end
	if className == "UIScale" then p.Scale = 1 end
	if className == "PointLight" or className == "SpotLight" then p.Brightness, p.Range, p.Enabled, p.Color = 1, 8, true, Color3.new(1, 1, 1) end
	if className == "ParticleEmitter" or className == "Trail" or className == "Beam" then p.Enabled = true end
	if className == "Model" then p.PrimaryPart = nil end
	if className == "ScreenGui" or className == "BillboardGui" or className == "SurfaceGui" then p.Enabled = true end
	return self
end
SIM.newInstance = newInstance

local function sig(self, name)
	local s = self.__sig[name]
	if not s then
		s = Signal.new(self.__p.Name .. "." .. name)
		self.__sig[name] = s
	end
	return s
end

local SIGNALS = {
	ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, Changed = true, AncestryChanged = true, Destroying = true,
	Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, MouseEnter = true, MouseLeave = true, FocusLost = true,
	OnServerEvent = true, OnClientEvent = true, Triggered = true, PromptShown = true, Touched = true, TouchEnded = true,
	CharacterAdded = true, CharacterRemoving = true, Died = true, Completed = true, Ended = true, PlayerAdded = true, PlayerRemoving = true,
	Heartbeat = true, RenderStepped = true, Stepped = true, InputBegan = true, InputEnded = true, InputChanged = true,
	PromptTriggered = true, PromptGamePassPurchaseFinished = true, PromptProductPurchaseFinished = true, AttributeChanged = true,
}

instMeta.__index = function(self, k)
	local p = rawget(self, "__p")
	if Inst[k] then return Inst[k] end
	if SIGNALS[k] then return sig(self, k) end
	local v = p[k]
	if v ~= nil then return v end
	if k == "Position" and p.CFrame then return p.CFrame.Position end
	if k == "Orientation" then return Vector3.zero end
	for _, c in rawget(self, "__c") do
		if c.__p.Name == k then return c end
	end
	return nil
end
local VALID_PROPS = {}
for _, k in { "Name", "Parent", "Archivable", "CFrame", "Position", "Size", "Orientation", "Rotation", "Transparency", "Anchored", "CanCollide", "CanTouch", "CanQuery", "CastShadow", "Color", "Material", "Reflectance", "Shape", "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface", "Massless", "Locked", "MeshType", "Scale", "Offset", "VertexColor", "TextureId", "MeshId", "Texture", "Face", "PrimaryPart", "WorldPivot", "Brightness", "Range", "Enabled", "Shadows", "Angle", "Rate", "Lifetime", "Speed", "SpreadAngle", "LightEmission", "LightInfluence", "ZOffset", "Acceleration", "Drag", "RotSpeed", "Squash", "EmissionDirection", "TimeScale", "VelocityInheritance", "LockedToPart", "Attachment0", "Attachment1", "Width0", "Width1", "FaceCamera", "Segments", "CurveSize0", "CurveSize1", "MinLength", "WidthScale", "Text", "TextColor3", "TextSize", "TextScaled", "TextWrapped", "TextXAlignment", "TextYAlignment", "TextTransparency", "TextStrokeTransparency", "TextStrokeColor3", "Font", "FontFace", "RichText", "MaxVisibleGraphemes", "PlaceholderText", "PlaceholderColor3", "ClearTextOnFocus", "TextEditable", "MultiLine", "LineHeight", "TextTruncate", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel", "BorderColor3", "BorderMode", "AnchorPoint", "Visible", "ZIndex", "LayoutOrder", "ClipsDescendants", "AutomaticSize", "Active", "Selectable", "AutoButtonColor", "Modal", "Image", "ImageColor3", "ImageTransparency", "ImageRectOffset", "ImageRectSize", "ScaleType", "SliceCenter", "SliceScale", "TileSize", "ResampleMode", "HoverImage", "PressedImage", "CanvasSize", "CanvasPosition", "ScrollBarThickness", "ScrollBarImageColor3", "ScrollBarImageTransparency", "ScrollingDirection", "AutomaticCanvasSize", "ElasticBehavior", "VerticalScrollBarInset", "HorizontalScrollBarInset", "ScrollingEnabled", "TopImage", "MidImage", "BottomImage", "ResetOnSpawn", "IgnoreGuiInset", "DisplayOrder", "ZIndexBehavior", "ScreenInsets", "SafeAreaCompatibility", "ClipToDeviceSafeArea", "CornerRadius", "Thickness", "ApplyStrokeMode", "LineJoinMode", "Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Wraps", "HorizontalFlex", "VerticalFlex", "ItemLineAlignment", "CellSize", "CellPadding", "FillDirectionMaxCells", "StartCorner", "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight", "MaxSize", "MinSize", "MaxTextSize", "MinTextSize", "AspectRatio", "AspectType", "DominantAxis", "Ambient", "LightColor", "LightDirection", "CurrentCamera", "FieldOfView", "CameraType", "CameraSubject", "Focus", "StudsOffset", "StudsOffsetWorldSpace", "ExtentsOffset", "ExtentsOffsetWorldSpace", "AlwaysOnTop", "MaxDistance", "Adornee", "SizingMode", "PixelsPerStud", "ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance", "RequiresLineOfSight", "KeyboardKeyCode", "GamepadKeyCode", "UIOffset", "Style", "Exclusivity", "ClickablePrompt", "SoundId", "Volume", "Looped", "Playing", "TimePosition", "PlaybackSpeed", "SoundGroup", "RollOffMaxDistance", "RollOffMinDistance", "RollOffMode", "PlayOnRemove", "ClockTime", "GeographicLatitude", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows", "ExposureCompensation", "FogColor", "FogEnd", "FogStart", "ShadowSoftness", "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "CelestialBodiesShown", "StarCount", "SunAngularSize", "MoonAngularSize", "SunTextureId", "MoonTextureId", "SkyboxOrientation", "Intensity", "Threshold", "Contrast", "Saturation", "TintColor", "Spread", "Density", "Haze", "Glare", "Decay", "Gravity", "CameraMaxZoomDistance", "CameraMinZoomDistance", "Neutral", "Duration", "AllowTeamChangeOnTouch", "Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "Character", "DisplayName", "Value", "Axis", "SecondaryAxis", "WorldPosition", "WorldCFrame", "FillColor", "OutlineColor", "FillTransparency", "OutlineTransparency", "DepthMode", "CollisionFidelity", "RenderFidelity", "DoubleSided", "CollisionGroup", "ModelStreamingMode", "LevelOfDetail", "ColorSequence", "InfluenceDistance", "WaterColor", "WaterReflectance", "WaterTransparency", "WaterWaveSize", "WaterWaveSpeed", "Decoration", "PlaybackLoudness", "CustomPhysicalProperties", "OnServerInvoke", "OnClientInvoke", "ProcessReceipt", "AssemblyLinearVelocity", "AssemblyAngularVelocity", "LocalTransparencyModifier" } do VALID_PROPS[k] = true end
instMeta.__newindex = function(self, k, v)
	local p = rawget(self, "__p")
	if not VALID_PROPS[k] then error("нет такого свойства у Roblox: " .. tostring(k) .. " (" .. tostring(p.ClassName) .. ")", 2) end
	if k == "Parent" then
		local old = p.Parent
		if old == v then return end
		if old then
			local list = rawget(old, "__c")
			local i = table.find(list, self)
			if i then table.remove(list, i) end
			sig(old, "ChildRemoved"):Fire(self)
		end
		p.Parent = v
		if v then
			assert(getmetatable(v) == instMeta, "Parent должен быть Instance")
			table.insert(rawget(v, "__c"), self)
			sig(v, "ChildAdded"):Fire(self)
			local a = v
			while a do
				sig(a, "DescendantAdded"):Fire(self)
				a = a.__p.Parent
			end
		end
		return
	end
	if k == "Position" and p.CFrame then
		assert(getmetatable(v) == V3, "Position должен быть Vector3")
		p.CFrame = mkcf(v, p.CFrame.m)
		return
	end
	if k == "CFrame" then assert(getmetatable(v) == CF, "CFrame должен быть CFrame (" .. p.Name .. ")") end
	if k == "Size" and isA(p.ClassName, "BasePart") then assert(getmetatable(v) == V3, "Size должен быть Vector3 (" .. p.Name .. ")") end
	if (k == "BackgroundColor3" or k == "TextColor3" or (k == "Color" and (isA(p.ClassName, "BasePart") or isA(p.ClassName, "Light") or p.ClassName == "UIStroke" or p.ClassName == "Highlight"))) then
		assert(getmetatable(v) == C3, k .. " должен быть Color3 (" .. p.Name .. ")")
	end
	if SIGNALS[k] then error("нельзя присвоить сигнал " .. k, 2) end
	p[k] = v
	local ps = self.__sig["prop_" .. k]
	if ps then ps:Fire() end
end
instMeta.__tostring = function(self) return self.__p.Name end

function Inst.GetChildren(self) return table.clone(self.__c) end
function Inst.GetDescendants(self)
	local out = {}
	local function walk(x)
		for _, c in x.__c do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Inst.FindFirstChild(self, name, rec)
	for _, c in self.__c do
		if c.__p.Name == name then return c end
	end
	if rec then
		for _, c in self.__c do
			local f = c:FindFirstChild(name, true)
			if f then return f end
		end
	end
	return nil
end
function Inst.FindFirstChildOfClass(self, cls)
	for _, c in self.__c do
		if c.__p.ClassName == cls then return c end
	end
	return nil
end
function Inst.FindFirstChildWhichIsA(self, cls)
	for _, c in self.__c do
		if isA(c.__p.ClassName, cls) then return c end
	end
	return nil
end
function Inst.FindFirstAncestorOfClass(self, cls)
	local a = self.__p.Parent
	while a do
		if a.__p.ClassName == cls then return a end
		a = a.__p.Parent
	end
	return nil
end
function Inst.WaitForChild(self, name, timeout)
	local c = self:FindFirstChild(name)
	if c then return c end
	-- ждём до 5 с симуляции, иначе ошибка (в Roblox будет вечное ожидание)
	local t0 = SIM.now
	while SIM.now - t0 < (timeout or 5) do
		task.wait(0.1)
		c = self:FindFirstChild(name)
		if c then return c end
	end
	if timeout then return nil end
	error("WaitForChild: нет " .. tostring(name) .. " в " .. self.__p.Name, 2)
end
function Inst.IsA(self, cls) return isA(self.__p.ClassName, cls) end
function Inst.Destroy(self)
	for _, c in table.clone(self.__c) do c:Destroy() end
	self.Parent = nil
	rawset(self, "__destroyed", true)
end
function Inst.ClearAllChildren(self) for _, c in table.clone(self.__c) do c:Destroy() end end
function Inst.Clone(self)
	local c = newInstance(self.__p.ClassName)
	for k, v in self.__p do
		if k ~= "Parent" then c.__p[k] = v end
	end
	for k, v in self.__a do c.__a[k] = v end
	for _, ch in self.__c do
		local cc = ch:Clone()
		cc.Parent = c
	end
	return c
end
function Inst.SetAttribute(self, k, v)
	local t = typeof(v)
	assert(v == nil or t == "number" or t == "string" or t == "boolean" or getmetatable(v) == V3 or getmetatable(v) == CF or getmetatable(v) == C3 or getmetatable(v) == V2,
		"SetAttribute: недопустимый тип для " .. tostring(k))
	self.__a[k] = v
end
function Inst.GetAttribute(self, k) return self.__a[k] end
function Inst.GetAttributes(self) return table.clone(self.__a) end
function Inst.GetPropertyChangedSignal(self, k) return sig(self, "prop_" .. k) end
function Inst.GetAttributeChangedSignal(self, k) return sig(self, "attr_" .. k) end
function Inst.GetFullName(self) return self.__p.Name end
-- части и модели
function Inst.GetPivot(self)
	if self.__p.ClassName == "Model" then
		local pp = self.__p.PrimaryPart
		return pp and pp.CFrame or CFrame.new()
	end
	return self.__p.CFrame
end
function Inst.PivotTo(self, cf)
	assert(getmetatable(cf) == CF, "PivotTo: нужен CFrame")
	if self.__p.ClassName == "Model" then
		local root = self:FindFirstChild("HumanoidRootPart") or self.__p.PrimaryPart
		if root then root.CFrame = cf end
	else
		self.CFrame = cf
	end
end
function Inst.ScreenPointToRay(self, x, y) return { Origin = Vector3.new(0, 10, 0), Direction = Vector3.new(0, 0, -1) } end
function Inst.ViewportPointToRay(self, x, y) return { Origin = Vector3.new(0, 10, 0), Direction = Vector3.new(0, 0, -1) } end
function Inst.WorldToScreenPoint(self, v) return Vector3.new(422, 195, 50), true end
function Inst.WorldToViewportPoint(self, v) return Vector3.new(422, 231, 50), true end
function Inst.GetExtentsSize(self)
	local _, size = self:GetBoundingBox()
	return size
end
function Inst.GetBoundingBox(self)
	local pp = self.__p.PrimaryPart
	return pp and pp.CFrame or CFrame.new(), Vector3.new(4, 4, 6)
end
function Inst.ScaleTo(self, s) end
function Inst.GetScale(self) return 1 end
function Inst.SetPrimaryPartCFrame(self, cf) self:PivotTo(cf) end
-- звук, эффекты
function Inst.Play(self) self.__p.Playing = true end
function Inst.Stop(self) self.__p.Playing = false end
function Inst.Pause(self) end
function Inst.Resume(self) end
function Inst.Emit(self, n) assert(num(n), "Emit: нужно число") end
function Inst.Clear(self) end
-- сеть: один игрок, сервер и клиент в одной VM
function Inst.FireServer(self, ...) sig(self, "OnServerEvent"):Fire(SIM.player, ...) end
function Inst.FireClient(self, plr, ...)
	assert(plr and plr.__p.ClassName == "Player", "FireClient: первый аргумент — Player")
	if plr == SIM.player then sig(self, "OnClientEvent"):Fire(...) end
end
function Inst.FireAllClients(self, ...) sig(self, "OnClientEvent"):Fire(...) end
function Inst.InvokeServer(self, ...)
	local f = self.__p.OnServerInvoke
	assert(f, "InvokeServer: нет OnServerInvoke у " .. self.__p.Name)
	return f(SIM.player, ...)
end
-- игрок
function Inst.Kick(self, msg) table.insert(SIM.log, "KICK " .. tostring(msg)) end
function Inst.LoadCharacter(self) end
function Inst.GetMouse(self) return { Hit = CFrame.new(), Target = nil } end
-- гуманоид
function Inst.MoveTo(self) end
function Inst.TakeDamage(self, n) self.__p.Health -= n end
function Inst.ChangeState(self) end
function Inst.GetState(self) return Enum.HumanoidStateType.Running end
function Inst.LoadAnimation(self) return { Play = function() end, Stop = function() end } end
-- tween-объект
function Inst.Cancel(self) end

local Instance = { new = function(className, parent)
	local i = newInstance(className)
	if parent then i.Parent = parent end
	return i
end }

------------------------------------------------------------------ game и сервисы
local game = newInstance("DataModel")
game.Name = "Game"
rawset(game.__p, "PlaceId", 99980756426085)
rawset(game.__p, "GameId", 7664327129)
rawset(game.__p, "JobId", "sim-job")
rawset(game.__p, "CreatorId", 8432365972)
rawset(game.__p, "CreatorType", Enum.CreatorType.User)
local services = {}
function Inst.GetService(self, name)
	if services[name] then return services[name] end
	local s = newInstance(name)
	s.Name = name
	s.Parent = game
	services[name] = s
	return s
end
function Inst.BindToClose(self, f) end
function Inst.IsLoaded() return true end

local workspace = Inst.GetService(game, "Workspace")
local cam = newInstance("Camera")
cam.Name = "Camera"
cam.Parent = workspace
rawset(workspace.__p, "CurrentCamera", cam)
rawset(workspace.__p, "Gravity", 196.2)
-- рельеф: операции записываются, чтобы tools/sim/dump_world.luau мог их нарисовать
SIM.terrain = {}
local terr = newInstance("Terrain")
terr.Name = "Terrain"
terr.Parent = workspace
function Inst.FillBall(self, c, r, m)
	assert(getmetatable(c) == V3 and num(r), "FillBall(Vector3, radius, material)")
	assert(r <= 812, "FillBall: радиус больше 812")
	table.insert(SIM.terrain, { "ball", c, r, m })
end
function Inst.FillCylinder(self, cf, h, r, m)
	assert(getmetatable(cf) == CF and num(h) and num(r), "FillCylinder(CFrame, height, radius, material)")
	table.insert(SIM.terrain, { "cyl", cf, h, r, m })
end
function Inst.FillBlock(self, cf, size, m)
	assert(getmetatable(cf) == CF and getmetatable(size) == V3, "FillBlock(CFrame, Vector3, material)")
	table.insert(SIM.terrain, { "block", cf, size, m })
end
function Inst.SetMaterialColor(self, m, c) assert(getmetatable(c) == C3, "SetMaterialColor(material, Color3)") end
function Inst.Clear(self) table.clear(SIM.terrain) end
function Inst.GetServerTimeNow() return os.time() + SIM.now end
function Inst.Raycast() return nil end

local Players = Inst.GetService(game, "Players")
function Inst.GetPlayers(self)
	local out = {}
	for _, c in self.__c do
		if c.__p.ClassName == "Player" then table.insert(out, c) end
	end
	return out
end
function Inst.GetPlayerFromCharacter(self, ch)
	for _, p in Players:GetPlayers() do
		if p.Character == ch then return p end
	end
	return nil
end
function Inst.GetPlayerByUserId(self, id)
	for _, p in Players:GetPlayers() do
		if p.UserId == id then return p end
	end
	return nil
end
function Inst.GetNameFromUserIdAsync(self, id) return "User" .. tostring(id) end
function Inst.GetUserThumbnailAsync() return "", true end

local RunService = Inst.GetService(game, "RunService")
function Inst.IsStudio() return false end
function Inst.IsServer() return true end
function Inst.IsClient() return true end
function Inst.BindToRenderStep() end

local DSS = Inst.GetService(game, "DataStoreService")
SIM.store = {}
-- DataStore Roblox не принимает: массивы с пропусками, смешанные ключи, функции, NaN
local function validateStore(v, path)
	local t = typeof(v)
	if t == "function" or t == "thread" or t == "userdata" then error("DataStore: нельзя хранить " .. t .. " в " .. path, 3) end
	if t == "number" and v ~= v then error("DataStore: NaN в " .. path, 3) end
	if t ~= "table" then return end
	local n, maxI, strKeys = 0, 0, 0
	for k, x in v do
		n += 1
		if type(k) == "number" then
			if k ~= math.floor(k) or k < 1 then error("DataStore: плохой числовой ключ " .. tostring(k) .. " в " .. path, 3) end
			if k > maxI then maxI = k end
		else
			strKeys += 1
		end
		validateStore(x, path .. "." .. tostring(k))
	end
	if maxI > 0 and (strKeys > 0 or maxI ~= n) then error("DataStore: массив с пропусками или смешанные ключи в " .. path, 3) end
end
function Inst.GetDataStore(self, name)
	return {
		GetAsync = function(_, key) return SIM.store[name .. "/" .. key] end,
		SetAsync = function(_, key, v)
			validateStore(v, name .. "/" .. key)
			SIM.store[name .. "/" .. key] = v
		end,
		UpdateAsync = function(_, key, f) SIM.store[name .. "/" .. key] = f(SIM.store[name .. "/" .. key]) end,
		RemoveAsync = function(_, key) SIM.store[name .. "/" .. key] = nil end,
	}
end
function Inst.GetOrderedDataStore(self, name)
	local data = {}
	return {
		SetAsync = function(_, key, v)
			assert(num(v) and v == math.floor(v), "OrderedDataStore: только целые числа")
			data[key] = v
		end,
		GetSortedAsync = function(_, asc, size)
			local list = {}
			for k, v in data do table.insert(list, { key = k, value = v }) end
			table.sort(list, function(a, b) return a.value > b.value end)
			return { GetCurrentPage = function() return list end, IsFinished = true }
		end,
	}
end

local MPS = Inst.GetService(game, "MarketplaceService")
function Inst.UserOwnsGamePassAsync() return false end
function Inst.PromptProductPurchase(self, plr, id) table.insert(SIM.log, "PROMPT product " .. tostring(id)) end
function Inst.PromptGamePassPurchase(self, plr, id) table.insert(SIM.log, "PROMPT pass " .. tostring(id)) end
function Inst.GetProductInfo() return { Name = "x", PriceInRobux = 1 } end

local MS = Inst.GetService(game, "MessagingService")
function Inst.PublishAsync(self, topic, data) table.insert(SIM.log, "PUBLISH " .. topic) end
function Inst.SubscribeAsync(self, topic, f) return { Disconnect = function() end } end

local TweenService = Inst.GetService(game, "TweenService")
function Inst.Create(self, obj, info, props)
	assert(obj and getmetatable(obj) == instMeta, "TweenService:Create: нужен Instance")
	assert(type(props) == "table", "TweenService:Create: нужны свойства")
	local tw = newInstance("Tween")
	rawset(tw.__p, "__play", function()
		for k, v in props do obj[k] = v end
		task.delay(info.Time or 0, function() sig(tw, "Completed"):Fire(Enum.PlaybackState.Completed) end)
	end)
	return tw
end
local origPlay = Inst.Play
function Inst.Play(self)
	local f = self.__p.__play
	if f then f() else origPlay(self) end
end

local CP = Inst.GetService(game, "ContentProvider")
function Inst.PreloadAsync(self, list, cb)
	for _, x in list do
		if cb then cb(x.__p and x.__p.SoundId or "", Enum.AssetFetchStatus.Success) end
	end
end
Inst.GetService(game, "Lighting")
Inst.GetService(game, "SoundService")
local GuiService = Inst.GetService(game, "GuiService")
rawset(GuiService.__p, "TouchControlsEnabled", true)
Inst.GetService(game, "HttpService")
function Inst.GenerateGUID() return "guid" end
function Inst.JSONEncode(_, v) return "{}" end
function Inst.JSONDecode(_, v) return {} end
local UIS = Inst.GetService(game, "UserInputService")
rawset(UIS.__p, "TouchEnabled", true)
rawset(UIS.__p, "KeyboardEnabled", false)
local StarterPlayer = Inst.GetService(game, "StarterPlayer")
rawset(StarterPlayer.__p, "CameraMaxZoomDistance", 400)
Inst.GetService(game, "ReplicatedStorage")
Inst.GetService(game, "ServerScriptService")
Inst.GetService(game, "StarterGui")
Inst.GetService(game, "TextChatService")
Inst.GetService(game, "BadgeService")
function Inst.AwardBadge() end
function Inst.UserHasBadgeAsync() return false end
Inst.GetService(game, "PhysicsService")
function Inst.RegisterCollisionGroup() end
function Inst.CollisionGroupSetCollidable() end

------------------------------------------------------------------ игрок и персонаж
function SIM.makeCharacter(plr, at)
	local char = newInstance("Model")
	char.Name = plr.Name
	local root = newInstance("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(at or Vector3.new(0, 3, 24))
	root.Parent = char
	local head = newInstance("Part")
	head.Name = "Head"
	head.Parent = char
	local hum = newInstance("Humanoid")
	hum.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	plr.Character = char
	sig(plr, "CharacterAdded"):Fire(char)
	return char
end
function SIM.makePlayer(userId, name)
	local plr = newInstance("Player")
	plr.Name = name
	rawset(plr.__p, "UserId", userId)
	rawset(plr.__p, "DisplayName", name)
	rawset(plr.__p, "CameraMaxZoomDistance", 400)
	local pg = newInstance("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = plr
	plr.Parent = Players
	return plr
end

return SIM
