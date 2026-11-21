-- Загружает 3D-модели растений (меши) из Roblox и раскладывает по ReplicatedStorage.PlantMeshes/<id>/<Роль>.
-- Если что-то не загрузилось, игра использует запасные модели из блоков (PlantModels.build).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local Ids = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PlantMeshes"))

local Loader = {}

function Loader.run()
	local root = ReplicatedStorage:FindFirstChild("PlantMeshes")
	if not root then
		root = Instance.new("Folder")
		root.Name = "PlantMeshes"
		root.Parent = ReplicatedStorage
	end
	local loaded = 0
	for planet, assetId in Ids do
		local model
		for attempt = 1, 3 do
			local ok, res = pcall(function() return InsertService:LoadAsset(assetId) end)
			if ok and res then model = res break end
			warn("PlantLoader: не загрузилась планета", planet, res)
			task.wait(2 * attempt)
		end
		if model then
			for _, d in model:GetDescendants() do
				if d:IsA("MeshPart") then
					local pid, role = d.Name:match("^(%w+_%d+)__(%a)$")
					if pid then
						local pf = root:FindFirstChild(pid)
						if not pf then
							pf = Instance.new("Folder")
							pf.Name = pid
							pf.Parent = root
						end
						d:ClearAllChildren()
						d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false
						d.Name = role
						d.Parent = pf
						loaded += 1
					end
				end
			end
			model:Destroy()
		end
	end
	ReplicatedStorage:SetAttribute("MeshParts", loaded)
	ReplicatedStorage:SetAttribute("MeshesReady", loaded > 0)
	return loaded
end

return Loader
