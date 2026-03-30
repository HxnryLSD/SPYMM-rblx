--[[
    Deadly Delivery Trainer v3.0
    Purpose: Accessibility assistance for players with disabilities
    Game: Deadly Delivery (Roblox)
    Executor: Potassium
    UI Library: Ventura UI
]]

-- Load Ventura UI Library
local Library = loadstring(game:HttpGet("https://codeberg.org/VenomVent/Ventura-UI/raw/branch/main/VenturaLibrary.lua"))()

-- Create Main GUI
local GUI = Library:new({
    name       = "Deadly Delivery Trainer",
    keyEnabled = false,
    key        = "",
    aiEnabled  = false,
})

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Local Player References
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Configuration
local Config = {
    MonsterESP = { Enabled = false, BoxEnabled = true, HealthEnabled = true, NameEnabled = true, MaxDistance = 500 },
    LootESP = { Enabled = false, NameEnabled = true, MaxDistance = 500 },
    Walkspeed = { Enabled = false, Speed = 16, Noclip = false },
    Stamina = { Unlimited = false },
    JumpPower = { Value = 50 },
    Fly = { Enabled = false, Speed = 50, Noclip = false },
    KillAura = { Enabled = false, Range = 15, TargetPriority = "Closest", HitChance = 100 },
    GodMode = { Enabled = false, AntiKnockback = false },
    AutoPickup = { Enabled = false, Range = 20, Delay = 100 },
    AutoTeleport = { Enabled = false, HPThreshold = 20 }
}

-- ESP Drawing Storage
local MonsterDrawings = {}
local LootDrawings = {}

-- Colors
local RarityColors = {
    [1] = Color3.fromRGB(200, 200, 200),
    [2] = Color3.fromRGB(0, 255, 0),
    [3] = Color3.fromRGB(0, 150, 255),
    [4] = Color3.fromRGB(180, 0, 255),
    [5] = Color3.fromRGB(255, 200, 0),
    [6] = Color3.fromRGB(255, 0, 100)
}

local TypeColors = {
    Container = Color3.fromRGB(128, 128, 128),
    Item = Color3.fromRGB(0, 255, 0),
    Coin = Color3.fromRGB(255, 255, 0),
    Food = Color3.fromRGB(0, 200, 0),
    Tool = Color3.fromRGB(100, 150, 255)
}

-- Utility Functions
local function getPlayer() return LocalPlayer end
local function getCharacter() local p = getPlayer(); return p and p.Character end
local function getHumanoid() local c = getCharacter(); return c and c:FindFirstChild("Humanoid") end
local function getRootPart() local c = getCharacter(); return c and c:FindFirstChild("HumanoidRootPart") end
local function getHealth() local h = getHumanoid(); if h then return h.Health, h.MaxHealth end; return 0, 100 end
local function isAlive() local h = getHumanoid(); return h and h.Health > 0 end

local function worldToScreen(position)
    local vector, onScreen = Camera:WorldToViewportPoint(position)
    return Vector2.new(vector.X, vector.Y), onScreen, vector.Z
end

local function getHealthColor(health, maxHealth)
    local ratio = health / maxHealth
    if ratio > 0.5 then
        return Color3.fromRGB(0, 255, 0):Lerp(Color3.fromRGB(255, 255, 0), (ratio - 0.5) * 2)
    else
        return Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(255, 255, 0), ratio * 2)
    end
end

-- Drawing Pool System
local DrawingPool = { Squares = {}, Texts = {} }

local function getSquare()
    local d = table.remove(DrawingPool.Squares) or Drawing.new("Square")
    d.Visible = false; d.Thickness = 1; d.Filled = false
    return d
end

local function getText()
    local d = table.remove(DrawingPool.Texts) or Drawing.new("Text")
    d.Visible = false; d.Size = 13; d.Center = true; d.Outline = true
    return d
end

local function releaseSquare(d) d.Visible = false; table.insert(DrawingPool.Squares, d) end
local function releaseText(d) d.Visible = false; table.insert(DrawingPool.Texts, d) end

local function clearAllDrawings(t)
    for i = #t, 1, -1 do
        local d = table.remove(t, i)
        if d then
            d.Visible = false
            if d._type == "Square" then releaseSquare(d) elseif d._type == "Text" then releaseText(d) end
        end
    end
end

local function addDrawing(t, d, dtype)
    d._type = dtype
    table.insert(t, d)
    return d
end

-- ============================================
-- GAME-SPECIFIC FUNCTIONS
-- ============================================

-- Get elevator/safe zone position
local function getElevatorPosition()
    local elevator = Workspace:FindFirstChild("电梯")
    if elevator then
        -- Find the main part
        local mainPart = elevator:FindFirstChild("CollodeV") 
            or elevator:FindFirstChild("LightPart")
            or elevator:FindFirstChild("BottomPart")
        if mainPart then
            return mainPart.Position
        end
        -- Try to find any Part
        for _, obj in pairs(elevator:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:find("Part") then
                return obj.Position
            end
        end
    end
    -- Fallback: return known position from scan
    return Vector3.new(-311, 324, 407)
end

-- Find monsters
local function findMonsters()
    local monsters = {}
    local gameSystem = Workspace:FindFirstChild("GameSystem")
    if gameSystem then
        local folder = gameSystem:FindFirstChild("Monsters")
        if folder then
            for _, m in pairs(folder:GetChildren()) do
                if m:IsA("Model") then table.insert(monsters, m) end
            end
        end
    end
    -- Also check workspace for monster models
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Model") then
            local name = obj.Name:lower()
            if name:find("monster") or name:find("enemy") or name:find("bloomaw") 
            or name:find("forsaken") or name:find("turkey") or name:find("fridge")
            or name:find("mimic") or name:find("sneakrat") or name:find("crocodile")
            or name:find("guest") or name:find("umbra") or name:find("burden")
            or name:find("faceless") or name:find("vecna") or name:find("santa")
            or name:find("guide") or name:find("pet") then
                -- Skip player character
                if not Players:GetPlayerFromCharacter(obj) then
                    table.insert(monsters, obj)
                end
            end
        end
    end
    return monsters
end

-- Find loot items
local function findLoot()
    local items = {}
    local gameSystem = Workspace:FindFirstChild("GameSystem")
    if gameSystem then
        -- Check Loots/World folder
        local loots = gameSystem:FindFirstChild("Loots")
        if loots then
            local world = loots:FindFirstChild("World")
            if world then
                for _, item in pairs(world:GetChildren()) do
                    if item:IsA("Model") then table.insert(items, item) end
                end
            end
            for _, folder in pairs(loots:GetChildren()) do
                if folder:IsA("Folder") then
                    for _, item in pairs(folder:GetChildren()) do
                        if item:IsA("Model") then table.insert(items, item) end
                    end
                end
            end
        end
        -- Check InteractiveItem folder (crates, cabinets, etc.)
        local interactive = gameSystem:FindFirstChild("InteractiveItem")
        if interactive then
            for _, item in pairs(interactive:GetChildren()) do
                if item:IsA("Model") then table.insert(items, item) end
            end
        end
    end
    return items
end

-- Get loot info
local function getLootInfo(loot)
    local name = loot.Name
    local lname = name:lower()
    local lootType = "Item"
    
    if lname:find("crate") or lname:find("cabinet") or lname:find("soil") 
    or lname:find("oilbucket") or lname:find("fridge") then
        lootType = "Container"
    elseif lname:find("coin") or lname:find("cash") or lname:find("gold") then
        lootType = "Coin"
    end
    
    return lootType, name
end

-- ============================================
-- STAMINA SYSTEM (Hook into game's system)
-- ============================================

local staminaHooked = false
local originalStaminaConsume = nil

local function hookStamina()
    if staminaHooked then return end
    
    -- Method 1: Hook into humanoid state changes
    local humanoid = getHumanoid()
    if humanoid then
        humanoid.Running:Connect(function(speed)
            if Config.Stamina.Unlimited and speed > 16 then
                -- Try to prevent stamina drain by modifying run speed
                local char = getCharacter()
                if char then
                    local animate = char:FindFirstChild("Animate")
                    if animate then
                        local run = animate:FindFirstChild("run")
                        if run then
                            -- This is a StringValue, check for stamina values
                        end
                    end
                end
            end
        end)
    end
    
    -- Method 2: Find and hook the stamina config
    local staminaConfig = ReplicatedStorage:FindFirstChild("Config")
    if staminaConfig then
        staminaConfig = staminaConfig:FindFirstChild("property_staminasystem")
        if staminaConfig and staminaConfig:IsA("ModuleScript") then
            -- Config found - game uses this for stamina values
            -- We'll override by constantly resetting
        end
    end
    
    staminaHooked = true
end

-- ============================================
-- AUTO PICKUP SYSTEM
-- ============================================

local lastPickupTime = 0

local function autoPickup()
    if not Config.AutoPickup.Enabled then return end
    if not isAlive() then return end
    
    local currentTime = tick()
    if currentTime - lastPickupTime < (Config.AutoPickup.Delay / 1000) then return end
    
    local rootPart = getRootPart()
    if not rootPart then return end
    
    local items = findLoot()
    
    for _, item in pairs(items) do
        -- Find the item's base part
        local itemPart = item:FindFirstChild("Handle") 
            or item:FindFirstChild("Main")
            or item.PrimaryPart
        
        if not itemPart then
            for _, part in pairs(item:GetDescendants()) do
                if part:IsA("BasePart") then
                    itemPart = part
                    break
                end
            end
        end
        
        if itemPart and itemPart:IsA("BasePart") then
            local distance = (rootPart.Position - itemPart.Position).Magnitude
            if distance <= Config.AutoPickup.Range then
                -- Method 1: Touch the item
                local success, err = pcall(function()
                    firetouchinterest(rootPart, itemPart, 0)
                    task.wait(0.05)
                    firetouchinterest(rootPart, itemPart, 1)
                end)
                
                -- Method 2: Look for ProximityPrompt
                for _, descendant in pairs(item:GetDescendants()) do
                    if descendant:IsA("ProximityPrompt") then
                        fireproximityprompt(descendant)
                    end
                end
                
                lastPickupTime = currentTime
                break
            end
        end
    end
end

-- ============================================
-- GOD MODE SYSTEM
-- ============================================

local godModeConnection = nil

local function setupGodMode()
    if godModeConnection then
        godModeConnection:Disconnect()
        godModeConnection = nil
    end
    
    if not Config.GodMode.Enabled then return end
    
    local humanoid = getHumanoid()
    if humanoid then
        -- Method 1: Constantly heal
        godModeConnection = humanoid.HealthChanged:Connect(function(health)
            if Config.GodMode.Enabled and health < humanoid.MaxHealth then
                humanoid.Health = humanoid.MaxHealth
            end
        end)
    end
end

-- ============================================
-- FLY SYSTEM
-- ============================================

local flying = false
local flyBodyVelocity = nil
local flyBodyGyro = nil

local function updateFly()
    local rootPart = getRootPart()
    local humanoid = getHumanoid()
    
    if not rootPart or not humanoid then
        if flying then
            flying = false
            if flyBodyVelocity then flyBodyVelocity:Destroy(); flyBodyVelocity = nil end
            if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
        end
        return
    end
    
    if Config.Fly.Enabled then
        if not flying then
            flying = true
            flyBodyVelocity = Instance.new("BodyVelocity", rootPart)
            flyBodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            flyBodyVelocity.Velocity = Vector3.new(0, 0, 0)
            
            flyBodyGyro = Instance.new("BodyGyro", rootPart)
            flyBodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            flyBodyGyro.P = 9e4
        end
        
        local moveDir = Vector3.new(0, 0, 0)
        local forward = Camera.CFrame.LookVector
        local right = Camera.CFrame.RightVector
        
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Vector3.new(forward.X, 0, forward.Z) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Vector3.new(forward.X, 0, forward.Z) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Vector3.new(right.X, 0, right.Z) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Vector3.new(right.X, 0, right.Z) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end
        
        if moveDir.Magnitude > 0 then moveDir = moveDir.Unit * Config.Fly.Speed end
        
        flyBodyVelocity.Velocity = moveDir
        flyBodyGyro.CFrame = CFrame.new(rootPart.Position, rootPart.Position + Vector3.new(forward.X, 0, forward.Z))
        humanoid.PlatformStand = true
    else
        if flying then
            flying = false
            if flyBodyVelocity then flyBodyVelocity:Destroy(); flyBodyVelocity = nil end
            if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
            humanoid.PlatformStand = false
        end
    end
end

-- ============================================
-- KILL AURA
-- ============================================

local lastAttackTime = 0

local function killAura()
    if not Config.KillAura.Enabled then return end
    if not isAlive() then return end
    
    local rootPart = getRootPart()
    if not rootPart then return end
    
    local monsters = findMonsters()
    local targets = {}
    
    for _, monster in pairs(monsters) do
        local humanoid = monster:FindFirstChild("Humanoid")
        local primaryPart = monster:FindFirstChild("HumanoidRootPart") or monster:FindFirstChild("Torso") or monster:FindFirstChild("Head")
        
        if humanoid and primaryPart and humanoid.Health > 0 then
            local dist = (rootPart.Position - primaryPart.Position).Magnitude
            if dist <= Config.KillAura.Range then
                table.insert(targets, { monster = monster, distance = dist, health = humanoid.Health })
            end
        end
    end
    
    if #targets == 0 then return end
    
    -- Sort
    if Config.KillAura.TargetPriority == "Closest" then
        table.sort(targets, function(a, b) return a.distance < b.distance end)
    else
        table.sort(targets, function(a, b) return a.health < b.health end)
    end
    
    -- Attack nearest
    if math.random(1, 100) <= Config.KillAura.HitChance then
        local target = targets[1].monster
        local humanoid = target:FindFirstChild("Humanoid")
        if humanoid then
            -- Try to damage directly
            pcall(function()
                humanoid:TakeDamage(humanoid.MaxHealth)
            end)
        end
    end
end

-- ============================================
-- ESP DRAWING
-- ============================================

local function drawMonsterESP(monster)
    if not Config.MonsterESP.Enabled then return end
    
    local primaryPart = monster:FindFirstChild("HumanoidRootPart") or monster:FindFirstChild("Torso") or monster:FindFirstChild("Head")
    if not primaryPart then
        for _, p in pairs(monster:GetDescendants()) do
            if p:IsA("BasePart") then primaryPart = p; break end
        end
    end
    if not primaryPart then return end
    
    local rootPart = getRootPart()
    if not rootPart then return end
    
    local distance = (rootPart.Position - primaryPart.Position).Magnitude
    if distance > Config.MonsterESP.MaxDistance then return end
    
    local screenPos, onScreen = worldToScreen(primaryPart.Position)
    if not onScreen then return end
    
    local humanoid = monster:FindFirstChild("Humanoid")
    local boxSize = math.clamp(2000 / distance, 20, 200)
    
    -- Box
    if Config.MonsterESP.BoxEnabled then
        local box = addDrawing(MonsterDrawings, getSquare(), "Square")
        box.Size = Vector2.new(boxSize, boxSize * 1.5)
        box.Position = Vector2.new(screenPos.X - boxSize/2, screenPos.Y - boxSize * 0.75)
        box.Color = Color3.fromRGB(255, 0, 0)
        box.Visible = true
        
        local outline = addDrawing(MonsterDrawings, getSquare(), "Square")
        outline.Size = Vector2.new(boxSize, boxSize * 1.5)
        outline.Position = Vector2.new(screenPos.X - boxSize/2, screenPos.Y - boxSize * 0.75)
        outline.Color = Color3.new(0, 0, 0)
        outline.Thickness = 3
        outline.Visible = true
    end
    
    -- Name
    if Config.MonsterESP.NameEnabled then
        local nameText = addDrawing(MonsterDrawings, getText(), "Text")
        nameText.Text = string.format("%s [%dst]", monster.Name, math.floor(distance))
        nameText.Position = Vector2.new(screenPos.X, screenPos.Y - boxSize * 0.75 - 15)
        nameText.Visible = true
    end
    
    -- Health
    if Config.MonsterESP.HealthEnabled and humanoid then
        local health, maxHealth = humanoid.Health, humanoid.MaxHealth
        local ratio = math.clamp(health / maxHealth, 0, 1)
        local barWidth, barHeight = boxSize, 4
        local barY = screenPos.Y + boxSize * 0.75 + 5
        
        local bg = addDrawing(MonsterDrawings, getSquare(), "Square")
        bg.Size = Vector2.new(barWidth, barHeight)
        bg.Position = Vector2.new(screenPos.X - barWidth/2, barY)
        bg.Color = Color3.new(0, 0, 0)
        bg.Filled = true
        bg.Visible = true
        
        local healthBar = addDrawing(MonsterDrawings, getSquare(), "Square")
        healthBar.Size = Vector2.new(barWidth * ratio, barHeight)
        healthBar.Position = Vector2.new(screenPos.X - barWidth/2, barY)
        healthBar.Color = getHealthColor(health, maxHealth)
        healthBar.Filled = true
        healthBar.Visible = true
    end
end

local function drawLootESP(loot)
    if not Config.LootESP.Enabled then return end
    if not loot:IsA("Model") then return end
    
    local primaryPart = loot:FindFirstChild("Handle") or loot:FindFirstChild("Main")
    if not primaryPart and loot:IsA("Model") then
        pcall(function() primaryPart = loot.PrimaryPart end)
    end
    if not primaryPart then
        for _, p in pairs(loot:GetDescendants()) do
            if p:IsA("BasePart") then primaryPart = p; break end
        end
    end
    if not primaryPart then return end
    
    local rootPart = getRootPart()
    if not rootPart then return end
    
    local distance = (rootPart.Position - primaryPart.Position).Magnitude
    if distance > Config.LootESP.MaxDistance then return end
    
    local screenPos, onScreen = worldToScreen(primaryPart.Position)
    if not onScreen then return end
    
    local lootType, name = getLootInfo(loot)
    local color = TypeColors[lootType] or Color3.fromRGB(0, 255, 0)
    local boxSize = math.clamp(1500 / distance, 15, 50)
    
    local box = addDrawing(LootDrawings, getSquare(), "Square")
    box.Size = Vector2.new(boxSize, boxSize)
    box.Position = Vector2.new(screenPos.X - boxSize/2, screenPos.Y - boxSize/2)
    box.Color = color
    box.Visible = true
    
    local outline = addDrawing(LootDrawings, getSquare(), "Square")
    outline.Size = Vector2.new(boxSize, boxSize)
    outline.Position = Vector2.new(screenPos.X - boxSize/2, screenPos.Y - boxSize/2)
    outline.Color = Color3.new(0, 0, 0)
    outline.Thickness = 3
    outline.Visible = true
    
    if Config.LootESP.NameEnabled then
        local nameText = addDrawing(LootDrawings, getText(), "Text")
        nameText.Text = string.format("%s [%dst]", name, math.floor(distance))
        nameText.Color = color
        nameText.Position = Vector2.new(screenPos.X, screenPos.Y - boxSize/2 - 15)
        nameText.Visible = true
    end
end

-- ============================================
-- CREATE UI
-- ============================================

local VisualsTab = GUI:CreateTab({ name = "Visuals", icon = Library.Icons.eye })
local MovementTab = GUI:CreateTab({ name = "Movement", icon = Library.Icons.player })
local CombatTab = GUI:CreateTab({ name = "Combat", icon = Library.Icons.sword })
local UtilityTab = GUI:CreateTab({ name = "Utility", icon = Library.Icons.wrench })

-- VISUALS
VisualsTab:Toggle({ name = "Monster ESP", callback = function(v) Config.MonsterESP.Enabled = v end })
VisualsTab:Toggle({ name = "Monster Box", callback = function(v) Config.MonsterESP.BoxEnabled = v end })
VisualsTab:Toggle({ name = "Monster Health", callback = function(v) Config.MonsterESP.HealthEnabled = v end })
VisualsTab:Toggle({ name = "Monster Name", callback = function(v) Config.MonsterESP.NameEnabled = v end })
VisualsTab:Slider({ name = "Monster Max Distance", min = 100, max = 2000, default = 500, callback = function(v) Config.MonsterESP.MaxDistance = v end })
VisualsTab:Toggle({ name = "Loot ESP", callback = function(v) Config.LootESP.Enabled = v end })
VisualsTab:Toggle({ name = "Loot Name", callback = function(v) Config.LootESP.NameEnabled = v end })
VisualsTab:Slider({ name = "Loot Max Distance", min = 100, max = 2000, default = 500, callback = function(v) Config.LootESP.MaxDistance = v end })

-- MOVEMENT
MovementTab:Toggle({ name = "Walkspeed", callback = function(v) Config.Walkspeed.Enabled = v end })
MovementTab:Slider({ name = "Speed", min = 16, max = 100, default = 16, callback = function(v) Config.Walkspeed.Speed = v end })
MovementTab:Toggle({ name = "Noclip", callback = function(v) Config.Walkspeed.Noclip = v end })
MovementTab:Toggle({ name = "Unlimited Stamina", callback = function(v) Config.Stamina.Unlimited = v; if v then hookStamina() end end })
MovementTab:Slider({ name = "Jump Power", min = 0, max = 200, default = 50, callback = function(v) Config.JumpPower.Value = v end })
MovementTab:Toggle({ name = "Fly (WASD+Space/Ctrl)", callback = function(v) Config.Fly.Enabled = v end })
MovementTab:Slider({ name = "Fly Speed", min = 10, max = 200, default = 50, callback = function(v) Config.Fly.Speed = v end })
MovementTab:Toggle({ name = "Fly Noclip", callback = function(v) Config.Fly.Noclip = v end })

-- COMBAT
CombatTab:Toggle({ name = "Kill Aura", callback = function(v) Config.KillAura.Enabled = v end })
CombatTab:Slider({ name = "Kill Aura Range", min = 5, max = 50, default = 15, callback = function(v) Config.KillAura.Range = v end })
CombatTab:Dropdown({ name = "Target Priority", options = { "Closest", "Lowest HP" }, default = "Closest", callback = function(v) Config.KillAura.TargetPriority = v end })
CombatTab:Slider({ name = "Hit Chance %", min = 1, max = 100, default = 100, callback = function(v) Config.KillAura.HitChance = v end })
CombatTab:Toggle({ name = "God Mode", callback = function(v) Config.GodMode.Enabled = v; setupGodMode() end })
CombatTab:Toggle({ name = "Anti-Knockback", callback = function(v) Config.GodMode.AntiKnockback = v end })

-- UTILITY
UtilityTab:Toggle({ name = "Auto Pickup", callback = function(v) Config.AutoPickup.Enabled = v end })
UtilityTab:Slider({ name = "Pickup Range", min = 5, max = 50, default = 20, callback = function(v) Config.AutoPickup.Range = v end })
UtilityTab:Slider({ name = "Pickup Delay (ms)", min = 0, max = 1000, default = 100, callback = function(v) Config.AutoPickup.Delay = v end })
UtilityTab:Button({ name = "Teleport to Elevator", callback = function()
    local rootPart = getRootPart()
    if rootPart then
        local pos = getElevatorPosition()
        rootPart.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
        GUI.notify("Teleport", "Teleported to elevator!", 3)
    end
end })
UtilityTab:Toggle({ name = "Auto Teleport (Emergency)", callback = function(v) Config.AutoTeleport.Enabled = v end })
UtilityTab:Slider({ name = "HP Threshold %", min = 5, max = 50, default = 20, callback = function(v) Config.AutoTeleport.HPThreshold = v end })

-- ============================================
-- MAIN UPDATE LOOP
-- ============================================

RunService.RenderStepped:Connect(function()
    -- Clear ESP drawings
    clearAllDrawings(MonsterDrawings)
    clearAllDrawings(LootDrawings)
    
    -- Walkspeed
    if Config.Walkspeed.Enabled then
        local h = getHumanoid()
        if h then h.WalkSpeed = Config.Walkspeed.Speed end
    end
    
    -- Jump Power
    local h = getHumanoid()
    if h then h.JumpPower = Config.JumpPower.Value end
    
    -- Noclip
    if Config.Walkspeed.Noclip or Config.Fly.Noclip then
        local char = getCharacter()
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end
    end
    
    -- Unlimited Stamina - Try to find and reset stamina
    if Config.Stamina.Unlimited then
        -- Method 1: Check player for stamina values
        local player = getPlayer()
        if player then
            for _, obj in pairs(player:GetDescendants()) do
                if obj.Name:lower():find("stamina") and obj:IsA("ValueBase") then
                    obj.Value = 100
                end
            end
        end
        -- Method 2: Set running state to false to prevent drain
        local char = getCharacter()
        if char then
            for _, obj in pairs(char:GetDescendants()) do
                if obj.Name:lower():find("stamina") and obj:IsA("ValueBase") then
                    obj.Value = 100
                end
            end
        end
    end
    
    -- Fly
    updateFly()
    
    -- God Mode
    if Config.GodMode.Enabled then
        local humanoid = getHumanoid()
        if humanoid and humanoid.Health < humanoid.MaxHealth then
            humanoid.Health = humanoid.MaxHealth
        end
    end
    
    -- Anti-Knockback
    if Config.GodMode.AntiKnockback then
        local rootPart = getRootPart()
        if rootPart then rootPart.Velocity = Vector3.new(0, 0, 0) end
    end
    
    -- Kill Aura
    killAura()
    
    -- Auto Pickup
    autoPickup()
    
    -- Auto Teleport
    if Config.AutoTeleport.Enabled then
        local health, maxHealth = getHealth()
        if (health / maxHealth) * 100 <= Config.AutoTeleport.HPThreshold and health > 0 then
            local rootPart = getRootPart()
            if rootPart then
                rootPart.CFrame = CFrame.new(getElevatorPosition() + Vector3.new(0, 3, 0))
                GUI.notify("Emergency", "Auto-teleported!", 3)
            end
        end
    end
    
    -- ESP
    if Config.MonsterESP.Enabled then
        for _, m in pairs(findMonsters()) do drawMonsterESP(m) end
    end
    if Config.LootESP.Enabled then
        for _, l in pairs(findLoot()) do drawLootESP(l) end
    end
end)

-- Character spawn handler
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if Config.Stamina.Unlimited then hookStamina() end
    if Config.GodMode.Enabled then setupGodMode() end
end)

GUI.notify("Trainer v3.0", "Loaded!", 3)
print([[Deadly Delivery Trainer v3.0 - Ready]])
