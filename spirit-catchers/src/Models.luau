-- Shared: builds original spirit models from parts (no external assets)
local M = {}

local function part(parent, cls, size, cf, color, props)
	local p = Instance.new(cls)
	p.Size = size; p.CFrame = cf; p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CastShadow = false
	for k, v in pairs(props or {}) do p[k] = v end
	p.Parent = parent
	return p
end

-- Paper fox: folded origami look, white paper with red ink markings
function M.PaperFox(scale)
	scale = scale or 1
	local s = function(x, y, z) return Vector3.new(x, y, z) * scale end
	local m = Instance.new("Model"); m.Name = "PaperFox"
	local white = Color3.fromRGB(246, 240, 226)
	local ink = Color3.fromRGB(200, 40, 50)
	local root = part(m, "Part", s(1.6, 1.1, 2.4), CFrame.new(), white)
	root.Name = "Root"; m.PrimaryPart = root
	-- folded back ridge
	part(m, "WedgePart", s(1.6, 0.5, 2.4), CFrame.new(s(0, 0.8, 0)), white)
	-- head (two wedges = pointed snout)
	part(m, "Part", s(1.3, 1, 1), CFrame.new(s(0, 0.6, -1.5)), white)
	part(m, "WedgePart", s(1.3, 1, 1), CFrame.new(s(0, 0.6, -2.5)) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(-90), 0, 0), white)
	-- ears
	for _, x in ipairs({-0.4, 0.4}) do
		part(m, "WedgePart", s(0.2, 0.9, 0.6), CFrame.new(s(x, 1.5, -1.4)), white)
		part(m, "WedgePart", s(0.21, 0.5, 0.3), CFrame.new(s(x, 1.35, -1.25)), ink)
	end
	-- eyes + ink stripes
	for _, x in ipairs({-0.45, 0.45}) do
		part(m, "Part", s(0.12, 0.12, 0.3), CFrame.new(s(x, 0.75, -1.95)), ink, {Material = Enum.Material.Neon})
	end
	part(m, "Part", s(1.62, 0.15, 0.2), CFrame.new(s(0, 0.3, 0.3)), ink)
	part(m, "Part", s(1.62, 0.15, 0.2), CFrame.new(s(0, 0.3, -0.4)), ink)
	-- legs
	for _, p in ipairs({{-0.6,-0.9},{0.6,-0.9},{-0.6,0.9},{0.6,0.9}}) do
		part(m, "Part", s(0.3, 0.9, 0.3), CFrame.new(s(p[1], -0.9, p[2])), white)
	end
	-- big folded tail
	local tail = part(m, "WedgePart", s(0.9, 1.6, 2), CFrame.new(s(0, 0.9, 2.1)) * CFrame.Angles(math.rad(-30), 0, 0), white)
	tail.Name = "Tail"
	part(m, "WedgePart", s(0.92, 0.6, 0.7), CFrame.new(s(0, 1.6, 2.9)) * CFrame.Angles(math.rad(-30), 0, 0), ink)
	-- soft spirit glow
	local l = Instance.new("PointLight"); l.Color = Color3.fromRGB(255, 200, 170); l.Range = 10; l.Brightness = 1.2; l.Parent = root
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = d; w.Parent = d
			d.Anchored = false
		end
	end
	return m
end

M.Build = { fox = M.PaperFox }
M.Names = { fox = "Бумажный лис" }
return M
