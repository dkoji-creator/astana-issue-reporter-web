-- Загружает объёмные формы спецэффектов (art/fx/fx.glb) в ReplicatedStorage.FxMeshes/<Имя>.
-- Клиент клонирует их для аур, ореолов, ударных волн; если не загрузились — эффекты строятся из обычных деталей.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local Ids = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("FxMeshes"))

local Loader = {}
function Loader.run()
	local root = ReplicatedStorage:FindFirstChild("FxMeshes") or Instance.new("Folder")
	root.Name = "FxMeshes"
	local n = 0
	local model
	for attempt = 1, 3 do
		local ok, res = pcall(function() return InsertService:LoadAsset(Ids.all) end)
		if ok and res then model = res break end
		warn("FxLoader: формы эффектов не загрузились", res)
		task.wait(2 * attempt)
	end
	if model then
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") then
				local name = d.Name:match("^fx__(%w+)$")
				if name and not root:FindFirstChild(name) then
					d:ClearAllChildren()
					d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.CastShadow = true, false, false, false, false
					d.Name = name
					d.CFrame = CFrame.new()
					d.Parent = root
					n += 1
				end
			end
		end
		model:Destroy()
	end
	root.Parent = ReplicatedStorage
	ReplicatedStorage:SetAttribute("FxMeshes", n)
	return n
end
return Loader
