-- Загружает 3D-модели питомцев (art/pets/pets.glb) и раскладывает по ReplicatedStorage.PetMeshes/<питомец>/<Область>.
-- Если модели не загрузились, клиент рисует питомцев из простых фигур.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local Ids = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PetMeshes"))

local Loader = {}
function Loader.run()
	local root = ReplicatedStorage:FindFirstChild("PetMeshes") or Instance.new("Folder")
	root.Name = "PetMeshes"
	local n = 0
	local model
	for attempt = 1, 3 do
		local ok, res = pcall(function() return InsertService:LoadAsset(Ids.all) end)
		if ok and res then model = res break end
		warn("PetLoader: модели питомцев не загрузились", res)
		task.wait(2 * attempt)
	end
	if model then
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") then
				local pet, region = d.Name:match("^(%w+)__(%w+)$")
				if pet then
					local pf = root:FindFirstChild(pet)
					if not pf then
						pf = Instance.new("Folder")
						pf.Name = pet
						pf.Parent = root
					end
					d:ClearAllChildren()
					d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.CastShadow = true, false, false, false, false
					d.Name = region
					d.Parent = pf
					n += 1
				end
			end
		end
		model:Destroy()
		-- импорт мог сдвинуть модель: ставим каждого питомца лапами на y=0 и центром тела в x=z=0
		for _, pf in root:GetChildren() do
			local body = pf:FindFirstChild("Fur")
			local minY = math.huge
			for _, p in pf:GetChildren() do
				if p:IsA("BasePart") and not p.Name:find("^Crystal") and not p.Name:find("^Halo") then
					minY = math.min(minY, p.Position.Y - p.Size.Y / 2)
				end
			end
			if body and minY < math.huge then
				local shift = Vector3.new(-body.Position.X, -minY, 0)
				for _, p in pf:GetChildren() do
					if p:IsA("BasePart") then p.CFrame = p.CFrame + shift end
				end
			end
		end
	end
	root.Parent = ReplicatedStorage
	ReplicatedStorage:SetAttribute("PetMeshes", n)
	return n
end
return Loader
