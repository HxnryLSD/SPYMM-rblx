--[[
    Deadly Delivery Trainer v2.0
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

-- Configuration Tables
local Config = {
    MonsterESP = {
        Enabled = false,
        BoxEnabled = true,
        HealthEnabled = true,
        NameEnabled = true,
        MaxDistance = 500
    },
    LootESP = {
        Enabled = false,
        NameEnabled = true,
        MaxDistance = 500,
        MinValue = 0
    },
    Walkspeed = {
        Enabled = false,
        Speed = 16,
        Noclip = false,
        SprintAlways = false
    },
    Stamina = {
        Unlimited = false
    },
    JumpPower = {
        Value = 50
    },
    Fly = {
        Enabled = false,
        Speed = 50,
        Noclip = false
    },
    KillAura = {
        Enabled = false,
        Range = 15,
        TargetPriority = "Closest",
        Damage = 100,
        HitChance = 100
    },
    GodMode = {
        Enabled = false,
        AntiKnockback = false
    },
    AutoPickup = {
        Enabled = false,
        Range = 20,
        Delay = 100
    },
    InstantInteract = {
        Enabled = false,
        Range = 20
    },
    Teleport = {
        Cooldown = 0,
        LastUse = 0
    },
    AutoTeleport = {
        Enabled = false,
        HPThreshold = 20,
        AutoOffload = false
    }
}

-- ESP Drawing Storage (cleaned each frame)
local MonsterDrawings = {}
local LootDrawings = {}

-- Rarity Colors
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
    Money = Color3.fromRGB(255, 255, 0),
    Food = Color3.fromRGB(0, 200, 0),
    Tool = Color3.fromRGB(100, 150, 255)
}

-- Utility Functions
local function getPlayer()
    return LocalPlayer
end

local function getCharacter()
    local player = getPlayer()
    return player and player.Character or nil
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChild("Humanoid") or nil
end

local function getRootPart()
    local character = getCharacter()
    return character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")) or nil
end

local function getHealth()
    local humanoid = getHumanoid()
    if humanoid then
        return humanoid.Health, humanoid.MaxHealth
    end
    return 0, 100
end

local function isAlive()
    local humanoid = getHumanoid()
    return humanoid and humanoid.Health > 0
end

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

-- Drawing Pool System (prevents memory leaks and ghost drawings)
local DrawingPool = {
    Squares = {},
    Texts = {},
    Lines = {}
}

function DrawingPool.GetSquare()
    local drawing = table.remove(DrawingPool.Squares) or Drawing.new("Square")
    drawing.Visible = false
    drawing.Thickness = 1
    drawing.Filled = false
    drawing.Color = Color3.new(1, 1, 1)
    drawing.Size = Vector2.new(0, 0)
    drawing.Position = Vector2.new(0, 0)
    return drawing
end

function DrawingPool.GetText()
    local drawing = table.remove(DrawingPool.Texts) or Drawing.new("Text")
    drawing.Visible = false
    drawing.Text = ""
    drawing.Size = 13
    drawing.Center = true
    drawing.Outline = true
    drawing.Color = Color3.new(1, 1, 1)
    drawing.Position = Vector2.new(0, 0)
    return drawing
end

function DrawingPool.ReleaseSquare(drawing)
    drawing.Visible = false
    table.insert(DrawingPool.Squares, drawing)
end

function DrawingPool.ReleaseText(drawing)
    drawing.Visible = false
    table.insert(DrawingPool.Texts, drawing)
end

function DrawingPool.ReleaseAll(t)
    for i = #t, 1, -1 do
        local d = table.remove(t, i)
        if d.Type == "Square" then
            DrawingPool.ReleaseSquare(d.Drawing)
        elseif d.Type == "Text" then
            DrawingPool.ReleaseText(d.Drawing)
        end
    end
end

-- Clear all ESP drawings
local function clearAllESP()
    for i = #MonsterDrawings, 1, -1 do
        local d = table.remove(MonsterDrawings, i)
        if d.Drawing then
            d.Drawing.Visible = false
            if d.Type == "Square" then
                DrawingPool.ReleaseSquare(d.Drawing)
            elseif d.Type == "Text" then
                DrawingPool.ReleaseText(d.Drawing)
            end
        end
    end
    
    for i = #LootDrawings, 1, -1 do
        local d = table.remove(LootDrawings, i)
        if d.Drawing then
            d.Drawing.Visible = false
            if d.Type == "Square" then
                DrawingPool.ReleaseSquare(d.Drawing)
            elseif d.Type == "Text" then
                DrawingPool.ReleaseText(d.Drawing)
            end
        end
    end
    
    MonsterDrawings = {}
    LootDrawings = {}
end

-- Helper to add drawing to tracking
local function addMonsterDrawing(drawing, dtype)
    table.insert(MonsterDrawings, {Drawing = drawing, Type = dtype})
    return drawing
end

local function addLootDrawing(drawing, dtype)
    table.insert(LootDrawings, {Drawing = drawing, Type = dtype})
    return drawing
end

-- Find monsters in workspace
local function findMonsters()
    local monsters = {}
    
    -- Check GameSystem.Monsters
    local gameSystem = Workspace:FindFirstChild("GameSystem")
    if gameSystem then
        local monstersFolder = gameSystem:FindFirstChild("Monsters")
        if monstersFolder then
            for _, monster in pairs(monstersFolder:GetChildren()) do
                if monster:IsA("Model") then
                    table.insert(monsters, monster)
                end
            end
        end
    end
    
    -- Check workspace for monsters by name patterns
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Model") then
            local name = obj.Name:lower()
            if name:find("monster") or name:find("enemy") or name:find("bloomaw") 
            or name:find("forsaken") or name:find("turkey") or name:find("fridge")
            or name:find("mimic") or name:find("sneakrat") or name:find("crocodile")
            or name:find("guest") or name:find("umbra") or name:find("burden")
            or name:find("faceless") or name:find("vecna") or name:find("santa") then
                table.insert(monsters, obj)
            end
        end
    end
    
    return monsters
end

-- Find loot items
local function findLoot()
    local lootItems = {}
    
    local gameSystem = Workspace:FindFirstChild("GameSystem")
    if gameSystem then
        -- Check Loots folder
        local lootsFolder = gameSystem:FindFirstChild("Loots")
        if lootsFolder then
            for _, lootType in pairs(lootsFolder:GetChildren()) do
                for _, loot in pairs(lootType:GetChildren()) do
                    if loot:IsA("Model") or loot:IsA("BasePart") then
                        table.insert(lootItems, loot)
                    end
                end
            end
        end
        
        -- Check InteractiveItem folder
        local interactiveFolder = gameSystem:FindFirstChild("InteractiveItem")
        if interactiveFolder then
            for _, item in pairs(interactiveFolder:GetChildren()) do
                if item:IsA("Model") then
                    table.insert(lootItems, item)
                end
            end
        end
    end
    
    -- Check for dropped items in workspace
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local name = obj.Name:lower()
            if name:find("coin") or name:find("cash") or name:find("gold")
            or name:find("item") or name:find("loot") or name:find("drop") then
                table.insert(lootItems, obj)
            end
        end
    end
    
    return lootItems
end

-- Get loot info
local function getLootInfo(loot)
    local lootType = "Item"
    local lootName = loot.Name
    local rarity = 1
    
    local name = loot.Name:lower()
    if name:find("crate") or name:find("cabinet") or name:find("soil") 
    or name:find("oilbucket") or name:find("chest") then
        lootType = "Container"
    elseif name:find("coin") or name:find("cash") or name:find("gold") then
        lootType = "Coin"
    elseif name:find("food") then
        lootType = "Food"
    end
    
    return lootType, lootName, rarity
end

-- Draw Monster ESP
local function drawMonsterESP(monster)
    if not Config.MonsterESP.Enabled then return end
    
    -- Find primary part
    local primaryPart = monster:FindFirstChild("HumanoidRootPart") 
        or monster:FindFirstChild("Torso") 
        or monster:FindFirstChild("Head")
    
    if not primaryPart then
        for _, part in pairs(monster:GetDescendants()) do
            if part:IsA("BasePart") then
                primaryPart = part
                break
            end
        end
    end
    
    if not primaryPart then return end
    
    local rootPart = getRootPart()
    if not rootPart then return end
    
    local distance = (rootPart.Position - primaryPart.Position).Magnitude
    
    -- Distance check
    if distance > Config.MonsterESP.MaxDistance then return end
    
    local screenPos, onScreen = worldToScreen(primaryPart.Position)
    if not onScreen then return end
    
    local humanoid = monster:FindFirstChild("Humanoid")
    local head = monster:FindFirstChild("Head")
    
    -- Calculate box size based on distance
    local boxSize = math.clamp(2000 / distance, 20, 200)
    
    -- Draw Box
    if Config.MonsterESP.BoxEnabled then
        local box = addMonsterDrawing(DrawingPool.GetSquare(), "Square")
        box.Size = Vector2.new(boxSize, boxSize * 1.5)
        box.Position = Vector2.new(screenPos.X - boxSize/2, screenPos.Y - boxSize * 0.75)
        box.Color = Color3.fromRGB(255, 0, 0)
        box.Thickness = 1
        box.Visible = true
        
        -- Outline
        local outline = addMonsterDrawing(DrawingPool.GetSquare(), "Square")
        outline.Size = Vector2.new(boxSize, boxSize * 1.5)
        outline.Position = Vector2.new(screenPos.X - boxSize/2, screenPos.Y - boxSize * 0.75)
        outline.Color = Color3.new(0, 0, 0)
        outline.Thickness = 3
        outline.Visible = true
    end
    
    -- Draw Name
    if Config.MonsterESP.NameEnabled then
        local nameText = addMonsterDrawing(DrawingPool.GetText(), "Text")
        nameText.Text = string.format("%s [%dst]", monster.Name, math.floor(distance))
        nameText.Size = 13
        nameText.Color = Color3.new(1, 1, 1)
        nameText.Position = Vector2.new(screenPos.X, screenPos.Y - boxSize * 0.75 - 15)
        nameText.Visible = true
    end
    
    -- Draw Health
    if Config.MonsterESP.HealthEnabled and humanoid then
        local health = humanoid.Health
        local maxHealth = humanoid.MaxHealth
        local healthRatio = math.clamp(health / maxHealth, 0, 1)
        
        local barWidth = boxSize
        local barHeight = 4
        local barY = screenPos.Y + boxSize * 0.75 + 5
        
        -- Health bar background
        local bgBar = addMonsterDrawing(DrawingPool.GetSquare(), "Square")
        bgBar.Size = Vector2.new(barWidth, barHeight)
        bgBar.Position = Vector2.new(screenPos.X - barWidth/2, barY)
        bgBar.Color = Color3.new(0, 0, 0)
        bgBar.Filled = true
        bgBar.Visible = true
        
        -- Health bar fill
        local healthBar = addMonsterDrawing(DrawingPool.GetSquare(), "Square")
        healthBar.Size = Vector2.new(barWidth * healthRatio, barHeight)
        healthBar.Position = Vector2.new(screenPos.X - barWidth/2, barY)
        healthBar.Color = getHealthColor(health, maxHealth)
        healthBar.Filled = true
        healthBar.Visible = true
        
        -- Health text
        local healthText = addMonsterDrawing(DrawingPool.GetText(), "Text")
        healthText.Text = string.format("%d/%d", math.floor(health), math.floor(maxHealth))
        healthText.Size = 11
        healthText.Position = Vector2.new(screenPos.X, barY + 10)
        healthText.Visible = true
    end
end

-- Draw Loot ESP
local function drawLootESP(loot)
    if not Config.LootESP.Enabled then return end
    
    -- Skip non-models (Parts, Sounds, etc.)
    if not loot:IsA("Model") then return end
    
    -- Find position
    local primaryPart = loot:FindFirstChild("Handle") 
        or loot:FindFirstChild("Main") 
    
    -- Only check PrimaryPart if it's a Model and PrimaryPart exists
    if not primaryPart and loot:IsA("Model") then
        primaryPart = loot.PrimaryPart
    end
    
    if not primaryPart then
        for _, part in pairs(loot:GetDescendants()) do
            if part:IsA("BasePart") then
                primaryPart = part
                break
            end
        end
    end
    
    if not primaryPart then return end
    
    local rootPart = getRootPart()
    if not rootPart then return end
    
    local distance = (rootPart.Position - primaryPart.Position).Magnitude
    
    -- Distance check
    if distance > Config.LootESP.MaxDistance then return end
    
    local screenPos, onScreen = worldToScreen(primaryPart.Position)
    if not onScreen then return end
    
    local lootType, lootName, rarity = getLootInfo(loot)
    local typeColor = TypeColors[lootType] or RarityColors[rarity] or Color3.fromRGB(0, 255, 0)
    
    -- Box size based on distance
    local boxSize = math.clamp(1500 / distance, 15, 50)
    
    -- Draw Box
    local box = addLootDrawing(DrawingPool.GetSquare(), "Square")
    box.Size = Vector2.new(boxSize, boxSize)
    box.Position = Vector2.new(screenPos.X - boxSize/2, screenPos.Y - boxSize/2)
    box.Color = typeColor
    box.Thickness = 1
    box.Visible = true
    
    -- Outline
    local outline = addLootDrawing(DrawingPool.GetSquare(), "Square")
    outline.Size = Vector2.new(boxSize, boxSize)
    outline.Position = Vector2.new(screenPos.X - boxSize/2, screenPos.Y - boxSize/2)
    outline.Color = Color3.new(0, 0, 0)
    outline.Thickness = 3
    outline.Visible = true
    
    -- Draw Name
    if Config.LootESP.NameEnabled then
        local nameText = addLootDrawing(DrawingPool.GetText(), "Text")
        nameText.Text = string.format("%s [%dst]", lootName, math.floor(distance))
        nameText.Size = 12
        nameText.Color = typeColor
        nameText.Position = Vector2.new(screenPos.X, screenPos.Y - boxSize/2 - 15)
        nameText.Visible = true
    end
    
    -- Draw Type
    local typeText = addLootDrawing(DrawingPool.GetText(), "Text")
    typeText.Text = string.format("[%s]", lootType)
    typeText.Size = 10
    typeText.Color = typeColor
    typeText.Position = Vector2.new(screenPos.X, screenPos.Y + boxSize/2 + 5)
    typeText.Visible = true
end

-- Stamina System - Hook into game's stamina
local staminaConnection = nil
local function setupStamina()
    if staminaConnection then
        staminaConnection:Disconnect()
    end
    
    -- Try multiple locations for stamina
    local player = getPlayer()
    if not player then return end
    
    -- Check player stats
    local stats = player:FindFirstChild("stats") or player:FindFirstChild("Stats")
    local stamina = stats and (stats:FindFirstChild("Stamina") or stats:FindFirstChild("stamina"))
    
    if stamina and stamina:IsA("ValueBase") then
        staminaConnection = stamina:GetPropertyChangedSignal("Value"):Connect(function()
            if Config.Stamina.Unlimited then
                stamina.Value = 100
            end
        end)
        return true
    end
    
    -- Check character attributes
    local character = getCharacter()
    if character then
        local staminaAttr = character:GetAttribute("Stamina")
        if staminaAttr then
            return true
        end
    end
    
    return false
end

-- Unlimited Stamina - Force update
local function updateStamina()
    if not Config.Stamina.Unlimited then return end
    
    local player = getPlayer()
    if not player then return end
    
    -- Try different stamina locations
    local stats = player:FindFirstChild("stats") or player:FindFirstChild("Stats")
    if stats then
        local stamina = stats:FindFirstChild("Stamina") or stats:FindFirstChild("stamina")
        if stamina and stamina:IsA("ValueBase") then
            if stamina.Value < 100 then
                stamina.Value = 100
            end
        end
    end
    
    -- Check player folder
    local playerData = player:FindFirstChild("PlayerData") or player:FindFirstChild("Data")
    if playerData then
        local stamina = playerData:FindFirstChild("Stamina") or playerData:FindFirstChild("stamina")
        if stamina and stamina:IsA("ValueBase") then
            if stamina.Value < 100 then
                stamina.Value = 100
            end
        end
    end
    
    -- Try to set via attribute
    local character = getCharacter()
    if character then
        character:SetAttribute("Stamina", 100)
    end
end

-- Auto Pickup System
local lastPickupTime = 0
local function autoPickup()
    if not Config.AutoPickup.Enabled then return end
    if not isAlive() then return end
    
    local currentTime = tick()
    if currentTime - lastPickupTime < (Config.AutoPickup.Delay / 1000) then return end
    
    local rootPart = getRootPart()
    if not rootPart then return end
    
    local lootItems = findLoot()
    
    for _, loot in pairs(lootItems) do
        local primaryPart = loot:FindFirstChild("Handle") 
            or loot.PrimaryPart
        
        if not primaryPart then
            for _, part in pairs(loot:GetDescendants()) do
                if part:IsA("BasePart") then
                    primaryPart = part
                    break
                end
            end
        end
        
        if primaryPart then
            local distance = (rootPart.Position - primaryPart.Position).Magnitude
            if distance <= Config.AutoPickup.Range then
                -- Method 1: firetouchinterest
                pcall(function()
                    firetouchinterest(rootPart, primaryPart, 0)
                    task.wait()
                    firetouchinterest(rootPart, primaryPart, 1)
                end)
                
                -- Method 2: Try to find pickup remote
                pcall(function()
                    local remotes = ReplicatedStorage:GetDescendants()
                    for _, remote in pairs(remotes) do
                        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
                            local name = remote.Name:lower()
                            if name:find("pickup") or name:find("collect") or name:find("grab") 
                            or name:find("take") or name:find("interact") then
                                remote:FireServer(loot)
                            end
                        end
                    end
                end)
                
                lastPickupTime = currentTime
                break
            end
        end
    end
end

-- Kill Aura
local lastAttackTime = 0
local function killAura()
    if not Config.KillAura.Enabled then return end
    if not isAlive() then return end
    
    local rootPart = getRootPart()
    if not rootPart then return end
    
    local monsters = findMonsters()
    local validTargets = {}
    
    for _, monster in pairs(monsters) do
        local humanoid = monster:FindFirstChild("Humanoid")
        local primaryPart = monster:FindFirstChild("HumanoidRootPart") 
            or monster:FindFirstChild("Torso")
        
        if humanoid and primaryPart and humanoid.Health > 0 then
            local distance = (rootPart.Position - primaryPart.Position).Magnitude
            if distance <= Config.KillAura.Range then
                table.insert(validTargets, {
                    monster = monster,
                    distance = distance,
                    health = humanoid.Health
                })
            end
        end
    end
    
    -- Sort by priority
    if Config.KillAura.TargetPriority == "Closest" then
        table.sort(validTargets, function(a, b) return a.distance < b.distance end)
    else
        table.sort(validTargets, function(a, b) return a.health < b.health end)
    end
    
    -- Attack
    for _, target in pairs(validTargets) do
        if math.random(1, 100) <= Config.KillAura.HitChance then
            pcall(function()
                -- Try different attack remotes
                local remotes = ReplicatedStorage:GetDescendants()
                for _, remote in pairs(remotes) do
                    if remote:IsA("RemoteEvent") then
                        local name = remote.Name:lower()
                        if name:find("attack") or name:find("damage") or name:find("hit") then
                            remote:FireServer(target.monster, Config.KillAura.Damage / 100)
                        end
                    end
                end
            end)
        end
        break
    end
end

-- Fly System
local flying = false
local flyBodyVelocity = nil
local flyBodyGyro = nil

local function updateFly()
    local rootPart = getRootPart()
    local humanoid = getHumanoid()
    
    if not rootPart or not humanoid then
        if flying then
            flying = false
            if flyBodyVelocity then flyBodyVelocity:Destroy() flyBodyVelocity = nil end
            if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
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
        
        local camera = Workspace.CurrentCamera
        local moveDir = Vector3.new(0, 0, 0)
        local forward = camera.CFrame.LookVector
        local right = camera.CFrame.RightVector
        
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDir = moveDir + Vector3.new(forward.X, 0, forward.Z)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir = moveDir - Vector3.new(forward.X, 0, forward.Z)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDir = moveDir - Vector3.new(right.X, 0, right.Z)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir = moveDir + Vector3.new(right.X, 0, right.Z)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveDir = moveDir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            moveDir = moveDir - Vector3.new(0, 1, 0)
        end
        
        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit * Config.Fly.Speed
        end
        
        flyBodyVelocity.Velocity = moveDir
        flyBodyGyro.CFrame = CFrame.new(rootPart.Position, rootPart.Position + Vector3.new(forward.X, 0, forward.Z))
        humanoid.PlatformStand = true
    else
        if flying then
            flying = false
            if flyBodyVelocity then flyBodyVelocity:Destroy() flyBodyVelocity = nil end
            if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
            humanoid.PlatformStand = false
        end
    end
end

-- ============================================
-- CREATE UI TABS
-- ============================================

local VisualsTab = GUI:CreateTab({ name = "Visuals", icon = Library.Icons.eye })
local MovementTab = GUI:CreateTab({ name = "Movement", icon = Library.Icons.player })
local CombatTab = GUI:CreateTab({ name = "Combat", icon = Library.Icons.sword })
local UtilityTab = GUI:CreateTab({ name = "Utility", icon = Library.Icons.wrench })

-- VISUALS TAB
VisualsTab:Toggle({
    name = "Monster ESP",
    callback = function(value)
        Config.MonsterESP.Enabled = value
        if not value then clearAllESP() end
    end
})

VisualsTab:Toggle({
    name = "Monster Box",
    callback = function(value)
        Config.MonsterESP.BoxEnabled = value
    end
})

VisualsTab:Toggle({
    name = "Monster Health Bar",
    callback = function(value)
        Config.MonsterESP.HealthEnabled = value
    end
})

VisualsTab:Toggle({
    name = "Monster Name",
    callback = function(value)
        Config.MonsterESP.NameEnabled = value
    end
})

VisualsTab:Slider({
    name = "Monster Max Distance",
    min = 100,
    max = 2000,
    default = 500,
    callback = function(value)
        Config.MonsterESP.MaxDistance = value
    end
})

VisualsTab:Toggle({
    name = "Loot ESP",
    callback = function(value)
        Config.LootESP.Enabled = value
        if not value then clearAllESP() end
    end
})

VisualsTab:Toggle({
    name = "Loot Name",
    callback = function(value)
        Config.LootESP.NameEnabled = value
    end
})

VisualsTab:Slider({
    name = "Loot Max Distance",
    min = 100,
    max = 2000,
    default = 500,
    callback = function(value)
        Config.LootESP.MaxDistance = value
    end
})

-- MOVEMENT TAB
MovementTab:Toggle({
    name = "Walkspeed",
    callback = function(value)
        Config.Walkspeed.Enabled = value
    end
})

MovementTab:Slider({
    name = "Speed",
    min = 16,
    max = 100,
    default = 16,
    callback = function(value)
        Config.Walkspeed.Speed = value
    end
})

MovementTab:Toggle({
    name = "Noclip",
    callback = function(value)
        Config.Walkspeed.Noclip = value
    end
})

MovementTab:Toggle({
    name = "Unlimited Stamina",
    callback = function(value)
        Config.Stamina.Unlimited = value
        if value then
            setupStamina()
        end
    end
})

MovementTab:Slider({
    name = "Jump Power",
    min = 0,
    max = 200,
    default = 50,
    callback = function(value)
        Config.JumpPower.Value = value
    end
})

MovementTab:Toggle({
    name = "Fly (WASD + Space/Ctrl)",
    callback = function(value)
        Config.Fly.Enabled = value
    end
})

MovementTab:Slider({
    name = "Fly Speed",
    min = 10,
    max = 200,
    default = 50,
    callback = function(value)
        Config.Fly.Speed = value
    end
})

-- COMBAT TAB
CombatTab:Toggle({
    name = "Kill Aura",
    callback = function(value)
        Config.KillAura.Enabled = value
    end
})

CombatTab:Slider({
    name = "Kill Aura Range",
    min = 5,
    max = 50,
    default = 15,
    callback = function(value)
        Config.KillAura.Range = value
    end
})

CombatTab:Dropdown({
    name = "Target Priority",
    options = { "Closest", "Lowest HP" },
    default = "Closest",
    callback = function(value)
        Config.KillAura.TargetPriority = value
    end
})

CombatTab:Slider({
    name = "Hit Chance %",
    min = 1,
    max = 100,
    default = 100,
    callback = function(value)
        Config.KillAura.HitChance = value
    end
})

CombatTab:Toggle({
    name = "God Mode",
    callback = function(value)
        Config.GodMode.Enabled = value
    end
})

CombatTab:Toggle({
    name = "Anti-Knockback",
    callback = function(value)
        Config.GodMode.AntiKnockback = value
    end
})

-- UTILITY TAB
UtilityTab:Toggle({
    name = "Auto Pickup",
    callback = function(value)
        Config.AutoPickup.Enabled = value
    end
})

UtilityTab:Slider({
    name = "Pickup Range",
    min = 5,
    max = 50,
    default = 20,
    callback = function(value)
        Config.AutoPickup.Range = value
    end
})

UtilityTab:Slider({
    name = "Pickup Delay (ms)",
    min = 0,
    max = 1000,
    default = 100,
    callback = function(value)
        Config.AutoPickup.Delay = value
    end
})

UtilityTab:Button({
    name = "Teleport to Base",
    callback = function()
        local rootPart = getRootPart()
        if rootPart then
            local baseLocation = Workspace:FindFirstChild("Base") 
                or Workspace:FindFirstChild("SafeZone") 
                or Workspace:FindFirstChild("SpawnLocation")
            if baseLocation then
                local spawnPos = baseLocation:GetPivot().Position
                rootPart.CFrame = CFrame.new(spawnPos + Vector3.new(0, 5, 0))
                GUI.notify("Teleport", "Teleported to base!", 3)
            else
                GUI.notify("Teleport", "Base location not found!", 3)
            end
        end
    end
})

UtilityTab:Toggle({
    name = "Auto Teleport (Emergency)",
    callback = function(value)
        Config.AutoTeleport.Enabled = value
    end
})

UtilityTab:Slider({
    name = "HP Threshold %",
    min = 5,
    max = 50,
    default = 20,
    callback = function(value)
        Config.AutoTeleport.HPThreshold = value
    end
})

-- ============================================
-- MAIN UPDATE LOOP
-- ============================================

RunService.RenderStepped:Connect(function()
    -- Clear ESP drawings each frame (prevents ghost drawings)
    clearAllESP()
    
    -- Walkspeed
    if Config.Walkspeed.Enabled then
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.WalkSpeed = Config.Walkspeed.Speed
        end
    end
    
    -- Jump Power
    local humanoid = getHumanoid()
    if humanoid then
        humanoid.JumpPower = Config.JumpPower.Value
    end
    
    -- Noclip
    if Config.Walkspeed.Noclip or Config.Fly.Noclip then
        local character = getCharacter()
        if character then
            for _, part in pairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = false
                end
            end
        end
    end
    
    -- Unlimited Stamina
    updateStamina()
    
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
        if rootPart then
            rootPart.Velocity = Vector3.new(0, 0, 0)
        end
    end
    
    -- Kill Aura
    killAura()
    
    -- Auto Pickup
    autoPickup()
    
    -- Auto Teleport
    if Config.AutoTeleport.Enabled then
        local health, maxHealth = getHealth()
        local healthPercent = (health / maxHealth) * 100
        
        if healthPercent <= Config.AutoTeleport.HPThreshold and health > 0 then
            local rootPart = getRootPart()
            if rootPart then
                local baseLocation = Workspace:FindFirstChild("Base") or Workspace:FindFirstChild("SafeZone")
                if baseLocation then
                    local spawnPos = baseLocation:GetPivot().Position
                    rootPart.CFrame = CFrame.new(spawnPos + Vector3.new(0, 5, 0))
                    GUI.notify("Emergency", "Auto-teleported to safety!", 3)
                end
            end
        end
    end
    
    -- Draw ESPs (after clearing)
    if Config.MonsterESP.Enabled then
        local monsters = findMonsters()
        for _, monster in pairs(monsters) do
            drawMonsterESP(monster)
        end
    end
    
    if Config.LootESP.Enabled then
        local loots = findLoot()
        for _, loot in pairs(loots) do
            drawLootESP(loot)
        end
    end
end)

-- Character added handler
LocalPlayer.CharacterAdded:Connect(function()
    if Config.Stamina.Unlimited then
        task.wait(1)
        setupStamina()
    end
end)

-- Initial setup
task.wait(1)
if Config.Stamina.Unlimited then
    setupStamina()
end

-- Notify
GUI.notify("Trainer Loaded", "All systems operational!", 3)

print([[
==============================================
    Deadly Delivery Trainer v2.0
    Fixed: ESP ghosting, Stamina, Auto Pickup
==============================================
]])
