--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║                     SPYMM TRAINER                          ║
    ║                  Dead Shelter - Roblox                      ║
    ║                                                             ║
    ║  UI: Obsidian by deivid (https://docs.mspaint.cc/obsidian) ║
    ║                                                             ║
    ║  Features:                                                  ║
    ║    • Walkspeed / Jump Power / Infinite Jump / No Clip      ║
    ║    • FOV Changer                                           ║
    ║    • Kill Aura (FE Bypass, melee required)                 ║
    ║    • Item ESP / Monster ESP (separate text display)        ║
    ║    • No Fog / Full Bright                                  ║
    ║    • Bring Item (Unweld + GetLocalWeld FE Bypass)          ║
    ╚══════════════════════════════════════════════════════════════╝
--]]

-- ═══════════════════════════════════════════════════════════════
-- SERVICES & REFERENCES
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════════
-- GAME PATHS (from decompiled scripts & lists)
-- ═══════════════════════════════════════════════════════════════

local ENEMIES_FOLDER = Workspace:FindFirstChild("Enemies")
local ITEMS_FOLDER = Workspace:FindFirstChild("DraggableFolder")
local REMOTE_EVENTS = ReplicatedStorage:FindFirstChild("RemoteEvents")
local DRAG_EVENTS = ReplicatedStorage:FindFirstChild("DragEvents")

-- GetLocalWeld remote: bidirectional (server <-> client)
-- The server asks the client for an item's CFrame, the client fires it back.
-- We can proactively call FireServer(item, cframe) to tell the server
-- an item has moved — this is the game's own position-sync mechanism.
local GetLocalWeldRemote = nil
if DRAG_EVENTS then
    GetLocalWeldRemote = DRAG_EVENTS:FindFirstChild("GetLocalWeld")
end

-- Known enemy types from Enemie List.txt
local KNOWN_ENEMIES = {
    "Cave Zombie", "Dynamite Zombie", "Police Zombie",
    "Ranged Zombie", "Runner Zombie", "Sewer Zombie",
    "Tank Zombie", "Zombie"
}

-- Known melee weapons from Item List.txt
local MELEE_WEAPONS = {
    "Katana", "Spiked Bat", "Rusted Pipe", "Repair Hammer",
    "Torch", "Molotov", "Dynamite"
}

-- Item whitelist for Bring Item feature (valuable items)
local BRING_ITEMS_WHITELIST = {
    "Bandage", "Defibrillator", "Desert Eagle", "Glock",
    "Katana", "Pump Shotgun", "Sawed-off Shotgun", "Spiked Bat",
    "Molotov", "Dynamite", "Pistol Ammo", "Rifle Ammo",
    "Shotgun Ammo", "Blue Keycard", "Green Keycard", "Red Keycard",
    "Power Fuse", "Lockpick", "Gold Bar", "Silver Bar",
    "Deadbuck", "Zombie", "Zombie Seller",
    "Lantern", "Laptop", "Vacuum Cleaner", "Money Printer"
}

-- All draggable items from Item List.txt
local ALL_ITEMS = {
    "Bandage", "Barbed Wire", "Big Plank", "Big Sheet Metal",
    "Blue Keycard", "Brick Wall", "Bricks", "Cardboard Box",
    "Chair", "Construction Barricade", "Construction Lamp",
    "Deadbuck", "Defibrillator", "Desert Eagle", "Dynamite",
    "Electric Fence", "Glock", "Gold Bar", "Green Keycard",
    "Katana", "Lantern", "Laptop", "Lockpick",
    "Long Sheet Metal", "Metal Barrel", "Metal Fence", "Metal Shelf",
    "Molotov", "Money Printer", "Pistol Ammo", "Plank",
    "Power Fuse", "Power Generator", "Pump Shotgun", "Red Keycard",
    "Repair Hammer", "Rifle Ammo", "Rusted Pipe",
    "Sawed-off Shotgun", "Sheet Metal", "Shotgun Ammo",
    "Silver Bar", "Silver Painting", "Silver Vase", "Small Plank",
    "Spiked Bat", "Table", "Torch", "Vacuum Cleaner",
    "Window", "Wood Barrel", "Wood Painting", "Wood Pallet",
    "Wood Wall", "Zombie", "Zombie Seller"
}

-- ═══════════════════════════════════════════════════════════════
-- OBSIDIAN UI SETUP
-- ═══════════════════════════════════════════════════════════════

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "SPYMM",
    Footer = "Dead Shelter Trainer v1.3",
    NotifySide = "Right",
    ShowCustomCursor = true,
    Center = false,
    Resizable = true,
})

-- ═══════════════════════════════════════════════════════════════
-- TABS
-- ═══════════════════════════════════════════════════════════════

local Tabs = {
    Player = Window:AddTab("Player", "user"),
    Combat = Window:AddTab("Combat", "sword"),
    Visuals = Window:AddTab("Visuals", "eye"),
    Items = Window:AddTab("Items", "package"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- ═══════════════════════════════════════════════════════════════
-- PLAYER TAB
-- ═══════════════════════════════════════════════════════════════

local PlayerMovementBox = Tabs.Player:AddLeftGroupbox("Movement")
local PlayerCameraBox = Tabs.Player:AddRightGroupbox("Camera & Survival")

-- ── Walkspeed ──────────────────────────────────────────────────
PlayerMovementBox:AddToggle("WalkSpeedEnabled", {
    Text = "Walkspeed",
    Default = false,
    Tooltip = "Modify your character's walk speed",
    Risky = true,
})
PlayerMovementBox:AddSlider("WalkSpeedValue", {
    Text = "Speed",
    Default = 32,
    Min = 1,
    Max = 300,
    Rounding = 0,
    Suffix = " studs/s",
    Compact = false,
})

-- ── Jump Power ─────────────────────────────────────────────────
PlayerMovementBox:AddToggle("JumpPowerEnabled", {
    Text = "Jump Power",
    Default = false,
    Tooltip = "Modify your character's jump power",
    Risky = true,
})
PlayerMovementBox:AddSlider("JumpPowerValue", {
    Text = "Power",
    Default = 100,
    Min = 0,
    Max = 500,
    Rounding = 0,
    Suffix = " power",
    Compact = false,
})

-- ── Infinite Jump ─────────────────────────────────────────────
local InfiniteJumpToggle = PlayerMovementBox:AddToggle("InfiniteJump", {
    Text = "Infinite Jump",
    Default = false,
    Tooltip = "Jump mid-air without needing ground contact",
    Risky = true,
})
InfiniteJumpToggle:AddKeyPicker("InfiniteJumpKey", {
    Default = "Space",
    Mode = "Hold",
    SyncToggleState = true,
    Text = "Infinite Jump",
    NoUI = false,
})

-- ── No Clip ───────────────────────────────────────────────────
local NoClipToggle = PlayerMovementBox:AddToggle("NoClip", {
    Text = "No Clip",
    Default = false,
    Tooltip = "Walk through walls and objects",
    Risky = true,
})
NoClipToggle:AddKeyPicker("NoClipKey", {
    Default = "N",
    Mode = "Toggle",
    SyncToggleState = true,
    Text = "No Clip",
    NoUI = false,
})

-- ── FOV Changer ───────────────────────────────────────────────
PlayerCameraBox:AddToggle("FOVEnabled", {
    Text = "Custom FOV",
    Default = false,
    Tooltip = "Change your field of view",
})
PlayerCameraBox:AddSlider("FOVValue", {
    Text = "Field of View",
    Default = 90,
    Min = 1,
    Max = 120,
    Rounding = 0,
    Suffix = "°",
    Compact = false,
})

-- ═══════════════════════════════════════════════════════════════
-- COMBAT TAB
-- ═══════════════════════════════════════════════════════════════

local KillAuraBox = Tabs.Combat:AddLeftGroupbox("Kill Aura")
local KillAuraInfoBox = Tabs.Combat:AddRightGroupbox("Kill Aura Info")

-- ── Kill Aura Toggle ──────────────────────────────────────────
local KillAuraToggle = KillAuraBox:AddToggle("KillAura", {
    Text = "Kill Aura",
    Default = false,
    Tooltip = "Kill all monsters within range using the game's MeleeHitEvent remote. No weapon required.",
    Risky = true,
})
KillAuraToggle:AddKeyPicker("KillAuraKey", {
    Default = "K",
    Mode = "Toggle",
    SyncToggleState = true,
    Text = "Kill Aura",
    NoUI = false,
})

-- ── Kill Aura Delay ───────────────────────────────────────────
KillAuraBox:AddSlider("KillAuraDelay", {
    Text = "Attack Delay",
    Default = 0.1,
    Min = 0.01,
    Max = 1,
    Rounding = 2,
    Suffix = " sec",
    Compact = false,
    Tooltip = "Delay between each kill attempt (lower = faster)",
})

-- ── Kill Aura Damage ─────────────────────────────────────────
KillAuraBox:AddSlider("KillAuraDamage", {
    Text = "Damage Per Hit",
    Default = 999999,
    Min = 1,
    Max = 999999,
    Rounding = 0,
    Suffix = " dmg",
    Compact = false,
    Tooltip = "Damage dealt per remote call. 999999 = instant kill.",
})

-- ── Kill Aura Info ────────────────────────────────────────────
KillAuraInfoBox:AddLabel("Fires the game's MeleeHitEvent remote directly. No melee weapon required — works even with bare fists.", true)
KillAuraInfoBox:AddDivider()
KillAuraInfoBox:AddLabel("Remote: RemoteEvents.Events.MeleeHitEvent", false)
KillAuraInfoBox:AddLabel("FireServer(enemy, damage, hitPos, sound)", false)
KillAuraInfoBox:AddDivider()
KillAuraInfoBox:AddLabel("The server validates distance server-side, so you must be near enemies (close range). Sound is hardcoded to Spiked Bat.Hit.", true)

-- Status label (updated at runtime)
local KillAuraStatusLabel = KillAuraInfoBox:AddLabel("Status: Idle", false)

-- ═══════════════════════════════════════════════════════════════
-- VISUALS TAB
-- ═══════════════════════════════════════════════════════════════

local ESPBox = Tabs.Visuals:AddLeftGroupbox("ESP")
local EnvironmentBox = Tabs.Visuals:AddRightGroupbox("Environment")

-- ── Item ESP ──────────────────────────────────────────────────
local ItemESPToggle = ESPBox:AddToggle("ItemESP", {
    Text = "Item ESP",
    Default = false,
    Tooltip = "Highlight all items through walls with name and distance",
})
ItemESPToggle:AddColorPicker("ItemESPColor", {
    Default = Color3.fromRGB(0, 200, 255),
    Title = "Item ESP Color",
    Transparency = 0.5,
})

-- ── Monster ESP ───────────────────────────────────────────────
local MonsterESPToggle = ESPBox:AddToggle("MonsterESP", {
    Text = "Monster ESP",
    Default = false,
    Tooltip = "Highlight all monsters through walls with name and distance",
})
MonsterESPToggle:AddColorPicker("MonsterESPColor", {
    Default = Color3.fromRGB(255, 50, 50),
    Title = "Monster ESP Color",
    Transparency = 0.5,
})

-- ── ESP Text Size ─────────────────────────────────────────────
ESPBox:AddSlider("ESPTextSize", {
    Text = "ESP Text Size",
    Default = 14,
    Min = 10,
    Max = 24,
    Rounding = 0,
    Suffix = " px",
    Compact = false,
})

-- ── ESP Max Distance ──────────────────────────────────────────
ESPBox:AddSlider("ESPMaxDistance", {
    Text = "ESP Max Distance",
    Default = 500,
    Min = 50,
    Max = 2000,
    Rounding = 0,
    Suffix = " studs",
    Compact = false,
    Tooltip = "Maximum distance to show ESP elements",
})

-- ── No Fog ────────────────────────────────────────────────────
EnvironmentBox:AddToggle("NoFog", {
    Text = "No Fog",
    Default = false,
    Tooltip = "Remove all fog for long-distance viewing",
})

-- ── Full Bright ───────────────────────────────────────────────
EnvironmentBox:AddToggle("FullBright", {
    Text = "Full Bright",
    Default = false,
    Tooltip = "Maximum brightness and ambient light for clear visibility",
})

-- ═══════════════════════════════════════════════════════════════
-- ITEMS TAB
-- ═══════════════════════════════════════════════════════════════

local BringItemBox = Tabs.Items:AddLeftGroupbox("Bring Item")
local UnweldBox = Tabs.Items:AddRightGroupbox("Weld Control")
local ItemWhitelistBox = Tabs.Items:AddLeftGroupbox("Item Whitelist")

-- ── Item Whitelist Dropdown ───────────────────────────────────
ItemWhitelistBox:AddLabel("Select items to bring to your position:", true)
ItemWhitelistBox:AddDropdown("BringItemWhitelist", {
    Text = "Whitelisted Items",
    Values = ALL_ITEMS,
    Default = 1,
    Multi = true,
    Searchable = true,
    MaxVisibleDropdownItems = 15,
    Tooltip = "Select which items to bring when pressing 'Bring Items'",
    Callback = function(Value)
        -- Value is a table of selected items
    end,
})

-- ── Unweld Before Bringing ────────────────────────────────────
UnweldBox:AddLabel("Welded items have their PrimaryPart.Anchored = true, making them immovable.", true)
UnweldBox:AddDivider()
UnweldBox:AddToggle("UnweldBeforeBring", {
    Text = "Unweld Before Bring",
    Default = true,
    Tooltip = "Temporarily unweld (unanchor) welded items before bringing them. Required for welded high-value items.",
    Risky = true,
})
UnweldBox:AddToggle("ReweldAfterBring", {
    Text = "Reweld After Bring",
    Default = false,
    Tooltip = "Re-anchor items after bringing them (re-weld them at your position).",
})
UnweldBox:AddDivider()
UnweldBox:AddButton({
    Text = "Scan Welded Items",
    Tooltip = "Scan all items and report which ones are welded (anchored)",
    Func = function()
        ScanWeldedItems()
    end,
})

-- ── Weld Status Label ─────────────────────────────────────────
local WeldStatusLabel = UnweldBox:AddLabel("Weld scan: Not run yet", false)

-- ── Bring Item Buttons ────────────────────────────────────────
BringItemBox:AddLabel("Uses the game's own GetLocalWeld remote to sync item positions with the server. Welded items are temporarily unanchored via the same mechanism as DragEvents.WeldAngular.", true)
BringItemBox:AddDivider()
BringItemBox:AddButton({
    Text = "Bring Selected Items",
    Tooltip = "Bring whitelisted items to your position (unwelds welded items first)",
    Func = function()
        BringSelectedItems()
    end,
    Risky = true,
})
BringItemBox:AddButton({
    Text = "Bring All Items",
    Tooltip = "Bring every item in the map to your position",
    Func = function()
        BringAllItems()
    end,
    Risky = true,
})

-- ── Bring Item Status ─────────────────────────────────────────
local BringItemStatusLabel = BringItemBox:AddLabel("Ready", false)

-- ═══════════════════════════════════════════════════════════════
-- UI SETTINGS TAB
-- ═══════════════════════════════════════════════════════════════

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open Keybind Menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})
MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = true,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})
MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(Value)
        Library:SetNotifySide(Value)
    end,
})
MenuGroup:AddDropdown("DPIDropdown", {
    Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default = "100%",
    Text = "DPI Scale",
    Callback = function(Value)
        Value = Value:gsub("%%", "")
        local DPI = tonumber(Value)
        Library:SetDPIScale(DPI)
    end,
})
MenuGroup:AddSlider("UICornerSlider", {
    Text = "Corner Radius",
    Default = Library.CornerRadius,
    Min = 0,
    Max = 20,
    Rounding = 0,
    Callback = function(value)
        Window:SetCornerRadius(value)
    end,
})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
MenuGroup:AddButton("Unload", function()
    Library:Unload()
end)

Library.ToggleKeybind = Options.MenuKeybind

-- ═══════════════════════════════════════════════════════════════
-- SAVE & THEME MANAGERS
-- ═══════════════════════════════════════════════════════════════

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("SPYMM")
SaveManager:SetFolder("SPYMM/DeadShelter")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

-- ═══════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- Get the character safely
local function GetCharacter()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") then
        return char
    end
    return nil
end

-- Get the HumanoidRootPart safely
local function GetRootPart()
    local char = GetCharacter()
    if char then
        return char:FindFirstChild("HumanoidRootPart")
    end
    return nil
end

-- Get the Humanoid safely
local function GetHumanoid()
    local char = GetCharacter()
    if char then
        return char:FindFirstChild("Humanoid")
    end
    return nil
end

-- Check if player has a melee weapon equipped
local function HasMeleeWeapon()
    local char = GetCharacter()
    if not char then return false end
    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") then
            local toolName = tool.Name
            for _, meleeName in ipairs(MELEE_WEAPONS) do
                if string.find(string.lower(toolName), string.lower(meleeName)) then
                    return true
                end
            end
            -- Also accept any Tool since we can't be sure of all melee names
            -- The game might have unnamed melee weapons
            return true
        end
    end
    return false
end

-- Get the primary part of a model or the part itself
local function GetPrimaryPart(instance)
    if instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
    elseif instance:IsA("BasePart") then
        return instance
    end
    return nil
end

-- Get the humanoid of a model
local function GetModelHumanoid(model)
    if model and model:IsA("Model") then
        return model:FindFirstChildOfClass("Humanoid")
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: WALKSPEED
-- ═══════════════════════════════════════════════════════════════

local walkSpeedConnection = nil

local function UpdateWalkSpeed()
    local humanoid = GetHumanoid()
    if humanoid then
        if Toggles.WalkSpeedEnabled.Value then
            humanoid.WalkSpeed = Options.WalkSpeedValue.Value
        else
            -- Restore default (game default is typically 16)
            humanoid.WalkSpeed = 16
        end
    end
end

Toggles.WalkSpeedEnabled:OnChanged(function()
    UpdateWalkSpeed()
end)

Options.WalkSpeedValue:OnChanged(function()
    if Toggles.WalkSpeedEnabled.Value then
        UpdateWalkSpeed()
    end
end)

-- Keep walkspeed applied on character spawn / property reset
task.spawn(function()
    while task.wait(0.5) do
        if Library.Unloaded then break end
        if Toggles.WalkSpeedEnabled.Value then
            UpdateWalkSpeed()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: JUMP POWER
-- ═══════════════════════════════════════════════════════════════

local function UpdateJumpPower()
    local humanoid = GetHumanoid()
    if humanoid then
        if Toggles.JumpPowerEnabled.Value then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = Options.JumpPowerValue.Value
        else
            humanoid.UseJumpPower = true
            humanoid.JumpPower = 50
        end
    end
end

Toggles.JumpPowerEnabled:OnChanged(function()
    UpdateJumpPower()
end)

Options.JumpPowerValue:OnChanged(function()
    if Toggles.JumpPowerEnabled.Value then
        UpdateJumpPower()
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        if Library.Unloaded then break end
        if Toggles.JumpPowerEnabled.Value then
            UpdateJumpPower()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: INFINITE JUMP
-- ═══════════════════════════════════════════════════════════════

local infiniteJumpConnection = nil

infiniteJumpConnection = UserInputService.JumpRequest:Connect(function()
    if Toggles.InfiniteJump.Value then
        local humanoid = GetHumanoid()
        if humanoid and humanoid.Health > 0 then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: NO CLIP
-- ═══════════════════════════════════════════════════════════════

task.spawn(function()
    while task.wait(0.1) do
        if Library.Unloaded then break end
        if Toggles.NoClip.Value then
            local char = GetCharacter()
            if char then
                for _, part in pairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        else
            -- Re-enable collision when toggled off
            local char = GetCharacter()
            if char then
                for _, part in pairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        part.CanCollide = true
                    end
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: FOV CHANGER
-- ═══════════════════════════════════════════════════════════════

local defaultFOV = 70

local function UpdateFOV()
    if Toggles.FOVEnabled.Value then
        Camera.FieldOfView = Options.FOVValue.Value
    else
        Camera.FieldOfView = defaultFOV
    end
end

Toggles.FOVEnabled:OnChanged(function()
    UpdateFOV()
end)

Options.FOVValue:OnChanged(function()
    if Toggles.FOVEnabled.Value then
        UpdateFOV()
    end
end)

-- Keep FOV applied (some games reset it)
task.spawn(function()
    while task.wait(1) do
        if Library.Unloaded then break end
        if Toggles.FOVEnabled.Value then
            UpdateFOV()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: KILL AURA (MELEEHIT EVENT FE BYPASS)
-- ═══════════════════════════════════════════════════════════════
--
-- From hooking MeleeHitEvent in-game, the exact signature is:
--
--   MeleeHitEvent:FireServer(enemyModel, damage, hitPosition, sound)
--
--   Arg 1: Instance  → The enemy model (e.g. Workspace.Enemies.Runner Zombie)
--   Arg 2: number    → Damage amount (float, e.g. 35.46)
--   Arg 3: Vector3   → World position of the hit
--   Arg 4: Instance  → Sound reference (REQUIRED — server validates this)
--                       Always ReplicatedStorage.Sound.Spiked Bat.Hit
--                       (hardcoded in weapon LocalScripts, even for other weapons)
--
-- The server trusts this remote and processes damage server-side.
-- Distance is validated server-side (close range only).
-- No teleport, no weapon required. Sound is hardcoded to Spiked Bat.Hit.
-- ═══════════════════════════════════════════════════════════════

-- Direct reference to the MeleeHitEvent remote
local MeleeHitRemote = nil

local function GetMeleeHitRemote()
    if MeleeHitRemote then return MeleeHitRemote end
    -- Exact path from the live remote dump
    MeleeHitRemote = ReplicatedStorage:FindFirstChild("RemoteEvents")
        and ReplicatedStorage.RemoteEvents:FindFirstChild("Events")
        and ReplicatedStorage.RemoteEvents.Events:FindFirstChild("MeleeHitEvent")
    return MeleeHitRemote
end

-- The server REQUIRES a valid weapon sound instance.
-- From hooking the remote in-game: even when holding a Rusted Pipe,
-- the game's LocalScript always sends ReplicatedStorage.Sound.Spiked Bat.Hit.
-- This is hardcoded in the weapon's LocalScript, not dynamic.
local KillAuraSound = ReplicatedStorage:FindFirstChild("Sound")
    and ReplicatedStorage.Sound:FindFirstChild("Spiked Bat")
    and ReplicatedStorage.Sound["Spiked Bat"]:FindFirstChild("Hit")

-- Try to grab the remote and sound immediately
GetMeleeHitRemote()

-- Kill Aura main loop — pure remote call FE Bypass
task.spawn(function()
    while task.wait() do
        if Library.Unloaded then break end

        if Toggles.KillAura.Value then
            local char = GetCharacter()
            local rootPart = char and char:FindFirstChild("HumanoidRootPart")
            local humanoid = char and char:FindFirstChild("Humanoid")

            if not rootPart or not humanoid or humanoid.Health <= 0 then
                KillAuraStatusLabel:SetText("Status: No character")
                task.wait(1)
                continue
            end

            -- Ensure we have the remote
            if not GetMeleeHitRemote() then
                KillAuraStatusLabel:SetText("Status: MeleeHitEvent not found!")
                task.wait(2)
                continue
            end

            -- Refresh enemies folder reference
            if not ENEMIES_FOLDER then
                ENEMIES_FOLDER = Workspace:FindFirstChild("Enemies")
            end

            if ENEMIES_FOLDER then
                local attackDelay = Options.KillAuraDelay.Value
                local damage = Options.KillAuraDamage.Value
                local killCount = 0

                for _, enemy in pairs(ENEMIES_FOLDER:GetChildren()) do
                    if Library.Unloaded then break end
                    if not Toggles.KillAura.Value then break end

                    if enemy:IsA("Model") then
                        local enemyHumanoid = GetModelHumanoid(enemy)
                        local enemyPart = GetPrimaryPart(enemy)

                        -- Only target alive enemies
                        if enemyHumanoid and enemyHumanoid.Health > 0 and enemyPart then
                            -- ═══ FE BYPASS: Fire MeleeHitEvent directly ═══
                            -- No teleport, no weapon check. Just fires the remote.
                            pcall(function()
                                MeleeHitRemote:FireServer(
                                    enemy,
                                    damage,
                                    enemyPart.Position,
                                    KillAuraSound
                                )
                            end)

                            killCount = killCount + 1
                        end
                    end

                    task.wait(attackDelay)
                end

                if killCount > 0 then
                    KillAuraStatusLabel:SetText("Status: Killed " .. killCount .. " monster(s)")
                else
                    KillAuraStatusLabel:SetText("Status: Active - No enemies in range")
                end
            else
                KillAuraStatusLabel:SetText("Status: Enemies folder not found")
            end

            task.wait(0.2)
        else
            KillAuraStatusLabel:SetText("Status: Idle")
            task.wait(0.5)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: ITEM ESP & MONSTER ESP (Separate Text Display)
-- ═══════════════════════════════════════════════════════════════
-- ESP text is displayed on a separate invisible Part,
-- NOT on the same instance as the Highlight.
-- This prevents the highlight from pushing the text far up.

local espHighlights = {}     -- [instance] = Highlight
local espTextParts = {}      -- [instance] = { Part, BillboardGui, NameLabel, DistLabel }
local espCleanupFolder = nil -- Folder to hold all ESP objects for easy cleanup

local function CreateESPFolder()
    if espCleanupFolder then return espCleanupFolder end
    espCleanupFolder = Instance.new("Folder")
    espCleanupFolder.Name = "SPYMM_ESP"
    espCleanupFolder.Parent = Workspace
    return espCleanupFolder
end

local function ClearAllESP()
    for instance, data in pairs(espTextParts) do
        if data.Part and data.Part.Parent then
            data.Part:Destroy()
        end
    end
    for instance, highlight in pairs(espHighlights) do
        if highlight and highlight.Parent then
            highlight:Destroy()
        end
    end
    espHighlights = {}
    espTextParts = {}

    if espCleanupFolder then
        espCleanupFolder:Destroy()
        espCleanupFolder = nil
    end
end

-- Create a Highlight on the target and a separate invisible Part for text
local function CreateESPForTarget(instance, color)
    local part = GetPrimaryPart(instance)
    if not part then return false end

    CreateESPFolder()

    -- ── HIGHLIGHT ──
    local highlight = Instance.new("Highlight")
    highlight.Name = "SPYMM_Highlight"
    highlight.Adornee = part
    highlight.FillColor = color
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = espCleanupFolder

    espHighlights[instance] = highlight

    -- ── SEPARATE TEXT PART (invisible, follows the target) ──
    local textPart = Instance.new("Part")
    textPart.Name = "SPYMM_TextPart_" .. instance.Name
    textPart.Size = Vector3.new(0.1, 0.1, 0.1)
    textPart.Transparency = 1
    textPart.CanCollide = false
    textPart.Anchored = true
    textPart.Massless = true
    textPart.CFrame = part.CFrame
    textPart.Parent = espCleanupFolder

    -- ── BILLBOARD GUI (on the separate part, NOT on the highlight) ──
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "SPYMM_ESPGui"
    billboard.Adornee = textPart
    billboard.Size = UDim2.new(0, 200, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 4, 0) -- Offset above the highlight
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = Options.ESPMaxDistance.Value
    billboard.Parent = textPart

    -- Name Label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = color
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.TextStrokeTransparency = 0.5
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = Options.ESPTextSize.Value
    nameLabel.Text = instance.Name
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Parent = billboard

    -- Distance Label
    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistLabel"
    distLabel.Size = UDim2.new(1, 0, 0.5, 0)
    distLabel.Position = UDim2.new(0, 0, 0.5, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    distLabel.TextStrokeTransparency = 0.5
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextSize = math.max(10, Options.ESPTextSize.Value - 2)
    distLabel.Text = ""
    distLabel.TextXAlignment = Enum.TextXAlignment.Center
    distLabel.Parent = billboard

    espTextParts[instance] = {
        Part = textPart,
        BillboardGui = billboard,
        NameLabel = nameLabel,
        DistLabel = distLabel,
    }

    return true
end

-- Remove ESP for a specific target
local function RemoveESPForTarget(instance)
    if espHighlights[instance] then
        espHighlights[instance]:Destroy()
        espHighlights[instance] = nil
    end
    if espTextParts[instance] then
        if espTextParts[instance].Part and espTextParts[instance].Part.Parent then
            espTextParts[instance].Part:Destroy()
        end
        espTextParts[instance] = nil
    end
end

-- Update ESP text positions and distances
local function UpdateESPDisplay()
    local rootPart = GetRootPart()
    if not rootPart then return end

    local maxDist = Options.ESPMaxDistance.Value
    local textSize = Options.ESPTextSize.Value

    -- Update Item ESP
    for instance, data in pairs(espTextParts) do
        if not Toggles.ItemESP.Value and not Toggles.MonsterESP.Value then
            break
        end

        local part = GetPrimaryPart(instance)
        if not part then
            RemoveESPForTarget(instance)
            continue
        end

        -- Update text part position
        if data.Part then
            data.Part.CFrame = part.CFrame
        end

        -- Calculate and display distance
        local distance = (rootPart.Position - part.Position).Magnitude
        local distText = string.format("%d studs", math.floor(distance))

        -- Check if target is within max distance
        local visible = distance <= maxDist

        if data.NameLabel then
            data.NameLabel.TextTransparency = visible and 0 or 1
            data.NameLabel.TextStrokeTransparency = visible and 0.5 or 1
            data.NameLabel.TextSize = textSize
        end
        if data.DistLabel then
            data.DistLabel.Text = distText
            data.DistLabel.TextTransparency = visible and 0 or 1
            data.DistLabel.TextStrokeTransparency = visible and 0.5 or 1
            data.DistLabel.TextSize = math.max(10, textSize - 2)
        end

        -- Toggle highlight visibility
        if espHighlights[instance] then
            espHighlights[instance].Enabled = visible
        end
    end
end

-- Item ESP management
task.spawn(function()
    local itemTracked = {} -- Set of tracked items

    while task.wait(1) do
        if Library.Unloaded then break end

        if Toggles.ItemESP.Value then
            if not ITEMS_FOLDER then
                ITEMS_FOLDER = Workspace:FindFirstChild("DraggableFolder")
            end

            if ITEMS_FOLDER then
                local itemColor = Options.ItemESPColor.Value
                local currentItems = {}

                for _, item in pairs(ITEMS_FOLDER:GetChildren()) do
                    if item:IsA("Model") or item:IsA("BasePart") then
                        currentItems[item] = true

                        if not itemTracked[item] then
                            local success = pcall(function()
                                CreateESPForTarget(item, itemColor)
                            end)
                            if success then
                                itemTracked[item] = true
                            end
                        end

                        -- Update color
                        if espHighlights[item] then
                            espHighlights[item].FillColor = itemColor
                            espHighlights[item].OutlineColor = itemColor
                        end
                        if espTextParts[item] then
                            espTextParts[item].NameLabel.TextColor3 = itemColor
                        end
                    end
                end

                -- Remove ESP for items no longer present
                for item in pairs(itemTracked) do
                    if not currentItems[item] or not item.Parent then
                        RemoveESPForTarget(item)
                        itemTracked[item] = nil
                    end
                end
            end
        else
            -- Remove all item ESP
            for item in pairs(itemTracked) do
                RemoveESPForTarget(item)
            end
            itemTracked = {}
        end
    end
end)

-- Monster ESP management
task.spawn(function()
    local monsterTracked = {} -- Set of tracked monsters

    while task.wait(1) do
        if Library.Unloaded then break end

        if Toggles.MonsterESP.Value then
            if not ENEMIES_FOLDER then
                ENEMIES_FOLDER = Workspace:FindFirstChild("Enemies")
            end

            if ENEMIES_FOLDER then
                local monsterColor = Options.MonsterESPColor.Value
                local currentMonsters = {}

                for _, enemy in pairs(ENEMIES_FOLDER:GetChildren()) do
                    if enemy:IsA("Model") then
                        local enemyHumanoid = GetModelHumanoid(enemy)
                        if enemyHumanoid and enemyHumanoid.Health > 0 then
                            currentMonsters[enemy] = true

                            if not monsterTracked[enemy] then
                                local success = pcall(function()
                                    CreateESPForTarget(enemy, monsterColor)
                                end)
                                if success then
                                    monsterTracked[enemy] = true
                                end
                            end

                            -- Update color
                            if espHighlights[enemy] then
                                espHighlights[enemy].FillColor = monsterColor
                                espHighlights[enemy].OutlineColor = monsterColor
                            end
                            if espTextParts[enemy] then
                                espTextParts[enemy].NameLabel.TextColor3 = monsterColor
                            end
                        else
                            -- Dead enemy: remove ESP
                            if monsterTracked[enemy] then
                                RemoveESPForTarget(enemy)
                                monsterTracked[enemy] = nil
                            end
                        end
                    end
                end

                -- Remove ESP for monsters no longer present
                for enemy in pairs(monsterTracked) do
                    if not currentMonsters[enemy] or not enemy.Parent then
                        RemoveESPForTarget(enemy)
                        monsterTracked[enemy] = nil
                    end
                end
            end
        else
            -- Remove all monster ESP
            for enemy in pairs(monsterTracked) do
                RemoveESPForTarget(enemy)
            end
            monsterTracked = {}
        end
    end
end)

-- ESP update loop (runs every render frame for smooth text)
RunService.RenderStepped:Connect(function()
    if Library.Unloaded then return end
    if Toggles.ItemESP.Value or Toggles.MonsterESP.Value then
        UpdateESPDisplay()
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: NO FOG
-- ═══════════════════════════════════════════════════════════════

local originalFogStart = Lighting.FogStart
local originalFogEnd = Lighting.FogEnd
local atmosphereOriginal = nil

local function EnableNoFog()
    Lighting.FogStart = 0
    Lighting.FogEnd = 100000

    -- Handle Atmosphere object if present
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere then
        if not atmosphereOriginal then
            atmosphereOriginal = atmosphere.Density
        end
        atmosphere.Density = 0
    end
end

local function DisableNoFog()
    Lighting.FogStart = originalFogStart
    Lighting.FogEnd = originalFogEnd

    if atmosphereOriginal then
        local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
        if atmosphere then
            atmosphere.Density = atmosphereOriginal
        end
        atmosphereOriginal = nil
    end
end

Toggles.NoFog:OnChanged(function()
    if Toggles.NoFog.Value then
        EnableNoFog()
    else
        DisableNoFog()
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: FULL BRIGHT
-- ═══════════════════════════════════════════════════════════════

local originalBrightness = Lighting.Brightness
local originalAmbient = Lighting.Ambient
local originalOutdoorAmbient = Lighting.OutdoorAmbient
local originalExposureCompensation = Lighting.ExposureCompensation
local originalGlobalShadows = Lighting.GlobalShadows

local function EnableFullBright()
    Lighting.Brightness = 3
    Lighting.Ambient = Color3.fromRGB(200, 200, 200)
    Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
    Lighting.ExposureCompensation = 2
    Lighting.GlobalShadows = false

    -- Also remove color correction if present
    local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if cc then
        cc.Brightness = 0.2
        cc.Contrast = 0.2
        cc.Saturation = 0.2
        cc.TintColor = Color3.fromRGB(255, 255, 255)
    end
end

local function DisableFullBright()
    Lighting.Brightness = originalBrightness
    Lighting.Ambient = originalAmbient
    Lighting.OutdoorAmbient = originalOutdoorAmbient
    Lighting.ExposureCompensation = originalExposureCompensation
    Lighting.GlobalShadows = originalGlobalShadows

    local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if cc then
        cc.Brightness = 0
        cc.Contrast = 0
        cc.Saturation = 0
        cc.TintColor = Color3.fromRGB(255, 255, 255)
    end
end

Toggles.FullBright:OnChanged(function()
    if Toggles.FullBright.Value then
        EnableFullBright()
    else
        DisableFullBright()
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: BRING ITEM (UNWELD + GetLocalWeld FE BYPASS)
-- ═══════════════════════════════════════════════════════════════
--
-- How the game's drag system works (from LocalDrag decompile):
--
--   1. Welded items: PrimaryPart.Anchored = true (yellow highlight)
--      Free items:   PrimaryPart.Anchored = false (white highlight)
--
--   2. DragEvents.WeldAngular: zeroes AssemblyLinearVelocity and
--      AssemblyAngularVelocity on every BasePart in the model.
--
--   3. DragEvents.GetLocalWeld: BIDIRECTIONAL remote.
--      Server -> Client: "Give me this item's CFrame"
--      Client -> Server: FireServer(item, cframe)
--      The server trusts the CFrame the client reports.
--
-- FE Bypass strategy:
--   - For welded items: unanchor, zero velocities, claim network
--     ownership, set CFrame to player, fire GetLocalWeld to sync.
--   - For free items: claim network ownership, set CFrame, fire
--     GetLocalWeld to sync.
--   - The server accepts the position because GetLocalWeld is the
--     game's own position-sync mechanism.
-- ═══════════════════════════════════════════════════════════════

-- Check if an item is welded (anchored)
local function IsItemWelded(item)
    if item:IsA("Model") then
        local pp = item.PrimaryPart
        if pp then return pp.Anchored end
        -- Fallback: check any BasePart
        for _, child in pairs(item:GetChildren()) do
            if child:IsA("BasePart") and child.Anchored then
                return true
            end
        end
    elseif item:IsA("BasePart") then
        return item.Anchored
    end
    return false
end

-- Stop all motion on every part in a model (same as DragEvents.WeldAngular)
local function StopModelMotion(model)
    if not model then return end
    for _, part in pairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
        end
    end
end

-- The core bring function: unweld + GetLocalWeld FE bypass
local function BringItemToPlayer(item, rootPart)
    local primaryPart = GetPrimaryPart(item)
    if not primaryPart or not rootPart then return false, "no part" end

    -- Remember original state
    local wasAnchored = primaryPart.Anchored
    local targetCFrame = rootPart.CFrame * CFrame.new(
        math.random(-4, 4),
        3,
        math.random(-4, 4)
    )

    -- ── STEP 1: Unweld (unanchor) if the item is welded ──
    if wasAnchored and Toggles.UnweldBeforeBring.Value then
        pcall(function()
            primaryPart.Anchored = false
        end)
        -- Also unanchor all other parts in the model
        for _, child in pairs(item:GetDescendants()) do
            if child:IsA("BasePart") and child ~= primaryPart then
                pcall(function()
                    child.Anchored = false
                end)
            end
        end
        -- Small delay for the server to register the unanchor
        task.wait(0.05)
    end

    -- ── STEP 2: Stop all motion (like DragEvents.WeldAngular) ──
    StopModelMotion(item)

    -- ── STEP 3: Claim network ownership ──
    pcall(function()
        if primaryPart.CanSetNetworkOwnership ~= false then
            primaryPart:SetNetworkOwner(LocalPlayer)
        end
    end)

    -- ── STEP 4: Set the CFrame on every BasePart ──
    for _, child in pairs(item:GetDescendants()) do
        if child:IsA("BasePart") then
            pcall(function()
                child.CFrame = targetCFrame * CFrame.new(
                    math.random(-1, 1) * 0.5,
                    math.random(0, 1) * 0.5,
                    math.random(-1, 1) * 0.5
                )
            end)
        end
    end
    -- Set the model's PrimaryPartCFrame directly (preferred by the game)
    if item:IsA("Model") then
        pcall(function()
            item:SetPrimaryPartCFrame(targetCFrame)
        end)
    end

    -- ── STEP 5: FE BYPASS — Tell the server the new position ──
    -- Use the game's own GetLocalWeld remote (same as the game's
    -- drag system does in LocalDrag line 101). The server trusts
    -- this CFrame because it's the legitimate position-sync channel.
    if not GetLocalWeldRemote then
        if DRAG_EVENTS then
            GetLocalWeldRemote = DRAG_EVENTS:FindFirstChild("GetLocalWeld")
        end
    end

    if GetLocalWeldRemote then
        pcall(function()
            GetLocalWeldRemote:FireServer(item, targetCFrame)
        end)
    end

    -- ── STEP 6: Re-anchor (reweld) if requested ──
    if wasAnchored and Toggles.ReweldAfterBring.Value then
        task.wait(0.15)
        pcall(function()
            primaryPart.Anchored = true
        end)
        -- Stop motion again after placement
        StopModelMotion(item)
        -- Sync the final welded position with server
        if GetLocalWeldRemote then
            pcall(function()
                GetLocalWeldRemote:FireServer(item, targetCFrame)
            end)
        end
    end

    return true, nil
end

-- Scan all items and report welded vs unwelded
function ScanWeldedItems()
    if not ITEMS_FOLDER then
        ITEMS_FOLDER = Workspace:FindFirstChild("DraggableFolder")
    end

    if not ITEMS_FOLDER then
        WeldStatusLabel:SetText("Weld scan: Items folder not found!")
        Library:Notify({
            Title = "SPYMM",
            Description = "Items folder (DraggableFolder) not found!",
            Time = 3,
        })
        return
    end

    local totalItems = 0
    local weldedItems = 0
    local freeItems = 0
    local weldedNames = {}

    for _, item in pairs(ITEMS_FOLDER:GetChildren()) do
        if item:IsA("Model") or item:IsA("BasePart") then
            totalItems = totalItems + 1
            if IsItemWelded(item) then
                weldedItems = weldedItems + 1
                table.insert(weldedNames, item.Name)
            else
                freeItems = freeItems + 1
            end
        end
    end

    local weldReport = string.format("Weld scan: %d total | %d welded | %d free",
        totalItems, weldedItems, freeItems)
    WeldStatusLabel:SetText(weldReport)

    Library:Notify({
        Title = "SPYMM - Weld Scan",
        Description = string.format(
            "%d items scanned.\n%d welded (anchored), %d free.\n\nWelded items:\n%s",
            totalItems, weldedItems, freeItems,
            (#weldedNames > 0 and table.concat(weldedNames, ", ")) or "None"
        ),
        Time = 8,
    })
end

function BringSelectedItems()
    local rootPart = GetRootPart()
    if not rootPart then
        Library:Notify({
            Title = "SPYMM",
            Description = "No character found!",
            Time = 3,
        })
        return
    end

    if not ITEMS_FOLDER then
        ITEMS_FOLDER = Workspace:FindFirstChild("DraggableFolder")
    end

    if not ITEMS_FOLDER then
        Library:Notify({
            Title = "SPYMM",
            Description = "Items folder not found!",
            Time = 3,
        })
        return
    end

    -- Get selected whitelist items
    local selectedItems = Options.BringItemWhitelist.Value
    if not selectedItems or type(selectedItems) ~= "table" then
        selectedItems = { [tostring(selectedItems)] = true }
    end

    local broughtCount = 0
    local unweldedCount = 0
    local failedCount = 0
    local totalCount = 0

    for _, item in pairs(ITEMS_FOLDER:GetChildren()) do
        if item:IsA("Model") or item:IsA("BasePart") then
            local itemName = item.Name
            for selectedName, isSelected in pairs(selectedItems) do
                if isSelected and string.find(itemName, selectedName) then
                    totalCount = totalCount + 1

                    local wasWelded = IsItemWelded(item)
                    local success, err = pcall(function()
                        BringItemToPlayer(item, rootPart)
                    end)

                    if success then
                        broughtCount = broughtCount + 1
                        if wasWelded then
                            unweldedCount = unweldedCount + 1
                        end
                    else
                        failedCount = failedCount + 1
                    end
                    break
                end
            end
        end
    end

    local statusText = string.format("Brought %d/%d items (%d unwelded)",
        broughtCount, totalCount, unweldedCount)
    if failedCount > 0 then
        statusText = statusText .. string.format(" | %d failed", failedCount)
    end
    BringItemStatusLabel:SetText(statusText)

    Library:Notify({
        Title = "SPYMM - Bring Item",
        Description = string.format(
            "Brought %d/%d items to your position.\n%d welded items were unwelded first.",
            broughtCount, totalCount, unweldedCount
        ),
        Time = 5,
    })
end

function BringAllItems()
    local rootPart = GetRootPart()
    if not rootPart then
        Library:Notify({
            Title = "SPYMM",
            Description = "No character found!",
            Time = 3,
        })
        return
    end

    if not ITEMS_FOLDER then
        ITEMS_FOLDER = Workspace:FindFirstChild("DraggableFolder")
    end

    if not ITEMS_FOLDER then
        Library:Notify({
            Title = "SPYMM",
            Description = "Items folder not found!",
            Time = 3,
        })
        return
    end

    local broughtCount = 0
    local unweldedCount = 0
    local failedCount = 0

    for _, item in pairs(ITEMS_FOLDER:GetChildren()) do
        if item:IsA("Model") or item:IsA("BasePart") then
            local wasWelded = IsItemWelded(item)
            local success, err = pcall(function()
                BringItemToPlayer(item, rootPart)
            end)

            if success then
                broughtCount = broughtCount + 1
                if wasWelded then
                    unweldedCount = unweldedCount + 1
                end
            else
                failedCount = failedCount + 1
            end
        end
    end

    local statusText = string.format("Brought %d total (%d unwelded)",
        broughtCount, unweldedCount)
    if failedCount > 0 then
        statusText = statusText .. string.format(" | %d failed", failedCount)
    end
    BringItemStatusLabel:SetText(statusText)

    Library:Notify({
        Title = "SPYMM - Bring All",
        Description = string.format(
            "Brought %d items. %d welded items unwelded first.",
            broughtCount, unweldedCount
        ),
        Time = 5,
    })
end

-- ═══════════════════════════════════════════════════════════════
-- DRAGGABLE FPS/PING WATERMARK
-- ═══════════════════════════════════════════════════════════════

local Watermark = Library:AddDraggableLabel("SPYMM | Dead Shelter")
local FrameTimer, FrameCounter, FPS = tick(), 0, 0

RunService.RenderStepped:Connect(function()
    if Library.Unloaded then return end
    FrameCounter += 1
    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter
        FrameTimer = tick()
        FrameCounter = 0
    end

    local ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
    Watermark:SetText(
        string.format("SPYMM | %d fps | %d ms | Dead Shelter", FPS, ping)
    )
end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP ON UNLOAD
-- ═══════════════════════════════════════════════════════════════

Library:OnUnload(function()
    -- Disconnect infinite jump
    if infiniteJumpConnection then
        infiniteJumpConnection:Disconnect()
        infiniteJumpConnection = nil
    end

    -- Restore walkspeed
    local humanoid = GetHumanoid()
    if humanoid then
        humanoid.WalkSpeed = 16
        humanoid.JumpPower = 50
        humanoid.UseJumpPower = true
    end

    -- Restore FOV
    Camera.FieldOfView = defaultFOV

    -- Restore fog
    DisableNoFog()

    -- Restore lighting
    DisableFullBright()

    -- Restore collision
    local char = GetCharacter()
    if char then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end

    -- Clear all ESP
    ClearAllESP()

    -- Notify
    Library:Notify({
        Title = "SPYMM",
        Description = "Trainer unloaded. All features disabled.",
        Time = 3,
    })
end)

-- ═══════════════════════════════════════════════════════════════
-- STARTUP NOTIFICATION
-- ═══════════════════════════════════════════════════════════════

task.wait(1)

Library:Notify({
    Title = "SPYMM Trainer",
    Description = "Loaded successfully for Dead Shelter!\nPress RightShift to toggle menu.",
    Time = 5,
})
