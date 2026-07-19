--[[
    Total War (75755764395750) - Aimbot & ESP
    Library: Obsidian (deividcomsono fork) via loadstring + game:HttpGet
    Stealth posture: ZERO remote firing. Pure client-side visuals, camera,
    and lighting only. No hooks, no C-side method overwrites, no network
    footprint -> invisible to the server. The game's AC is client-side
    (Players/.../AntiCheat + isolated AC-signal remotes) so we never touch
    any RemoteEvent and never read/write their honeypot attributes.
]]

-- ============================== SERVICES ==============================
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer

local cam = Workspace.CurrentCamera
local running = true

-- ============================== LIBRARY ==============================
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library
do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(repo .. "Library.lua"))()
    end)
    if not ok or not lib then
        warn("[TotalWar] Obsidian failed to load - " .. tostring(lib))
        return
    end
    Library = lib
end

local okTm, ThemeManager = pcall(function()
    return loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
end)
ThemeManager = okTm and ThemeManager or nil
if not ThemeManager then warn("[TotalWar] ThemeManager addon unavailable - skipping") end
local okSm, SaveManager = pcall(function()
    return loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
end)
SaveManager = okSm and SaveManager or nil
if not SaveManager then warn("[TotalWar] SaveManager addon unavailable - skipping") end
if ThemeManager then ThemeManager:SetLibrary(Library) end
if SaveManager  then SaveManager:SetLibrary(Library) end

-- ============================== HELPERS ==============================
-- Resolve a world position for any PVInstance (Model / BasePart / etc.)
local function getWorldPos(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    local rp = obj:FindFirstChild("HumanoidRootPart")
        or obj:FindFirstChild("Torso")
        or obj:FindFirstChild("Head")
        or obj.PrimaryPart
    if rp then return rp.Position end
    local ok, pivot = pcall(function() return obj:GetPivot() end)
    if ok and pivot then return pivot.Position end
    return nil
end

-- Real-player detection.
-- Verified from dump: real players are Models DIRECTLY under Workspace with a
-- Humanoid. Decoys are (a) hex-named Models inside subfolders like
-- "7e7b11b35fc8", and (b) honeypot Folders marked @SENHoneypot = true.
local function isRealPlayerModel(m)
    if not (m and m:IsA("Model")) then return false end
    if m.Parent ~= Workspace then return false end
    if m:GetAttribute("SENHoneypot") then return false end
    if not m:FindFirstChildWhichIsA("Humanoid") then return false end
    if LocalPlayer and m.Name == LocalPlayer.Name then return false end
    local pl = Players:GetPlayerFromCharacter(m)
    if pl and pl == LocalPlayer then return false end
    return true
end

-- Team resolution: prefer the linked Player object, else the @Team attribute.
-- Real-player models are direct Workspace children (NOT Player.Character),
-- so Players:GetPlayerFromCharacter() returns nil. Match by NAME against the
-- Players service instead. Dump confirms Players/8x_EQ == Workspace/8x_EQ.
local function nameToPlayer(name)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name == name then return p end
    end
    return nil
end
local function getTeamValue(team)
    -- Team can be a Team instance or a name string; normalize to comparable value.
    if team == nil then return nil end
    if typeof(team) == "string" then return team end
    if typeof(team) == "Instance" then return team.Name end
    return tostring(team)
end
local function modelTeam(m)
    local pl = nameToPlayer(m.Name)
    if pl then return getTeamValue(pl.Team) end
    return getTeamValue(m:GetAttribute("Team"))
end
local function myTeam()
    if LocalPlayer then return getTeamValue(LocalPlayer.Team) end
    return nil
end
local function isTeammate(m)
    local t = modelTeam(m)
    local mt = myTeam()
    if t == nil or mt == nil then return false end
    return t == mt
end

-- World -> screen. Returns Vector2 + depth, or nil when off-screen.
local function worldToScreen(worldPos)
    local c = Workspace.CurrentCamera
    if not c then return nil end
    local sp, on = c:WorldToViewportPoint(worldPos)
    if not on then return nil end
    return Vector2.new(sp.X, sp.Y), sp.Z
end

-- Line-of-sight check (wall check).
-- CRITICAL: blacklist the TARGET'S OWN parts so the ray to its head/root
-- doesn't hit its own body (self-occlusion made every shot "blocked").
local function hasLineOfSight(from, to, ignoreModel)
    local dir = (to - from)
    local dist = dir.Magnitude
    if dist < 0.1 then return true end
    local rp = pcall(function() return RaycastParams.new() end) and RaycastParams.new()
    if not rp then return true end
    rp.FilterType = Enum.RaycastFilterType.Blacklist
    local filter = {}
    if LocalPlayer and LocalPlayer.Character then
        filter[#filter + 1] = LocalPlayer.Character
    end
    if ignoreModel then
        filter[#filter + 1] = ignoreModel
    end
    rp.FilterDescendantsInstances = filter
    local ok, res = pcall(function()
        return Workspace:Raycast(from, dir.Unit * dist, rp)
    end)
    if not ok then return true end
    return res == nil
end

-- ============================== ENTITY CACHE ==============================
local realPlayers = {}        -- verified real-player Models
local spawnPoints = {}        -- SpawnPoint parts + SpawnLocation
local lastPlayerScan = 0
local lastSpawnScan = 0
local diedConns = {}          -- model -> Humanoid.Died connection (kill credit)

local function creditKill()
    -- Stealth: a real enemy just died. Mark a cat to spawn (no remotes fired).
    -- Nil-guarded: this can fire during the first refreshPlayers() before the
    -- UI toggles are declared, or if a toggle failed to create.
    if not (WinnerCat and WinnerCat.Value) then return end
    if not (AimEnabled and AimEnabled.Value) then return end
    pendingCat = true
end

local function wireDied(model)
    if diedConns[model] then return end
    local hum = model:FindFirstChildWhichIsA("Humanoid")
    if hum then
        local ok, conn = pcall(function() return hum.Died:Connect(creditKill) end)
        if ok and conn then diedConns[model] = conn end
    end
end

local function refreshPlayers()
    local now = os.clock()
    if now - lastPlayerScan < 1.5 then return end
    lastPlayerScan = now
    local out = {}
    for _, child in ipairs(Workspace:GetChildren()) do
        if isRealPlayerModel(child) then
            out[#out + 1] = child
            wireDied(child)
        end
    end
    -- Disconnect Died listeners for models no longer present.
    for model, conn in pairs(diedConns) do
        if not model or not model.Parent or not table.find(out, model) then
            pcall(function() conn:Disconnect() end)
            diedConns[model] = nil
        end
    end
    realPlayers = out
end

local function refreshSpawns()
    local now = os.clock()
    if now - lastSpawnScan < 3 then return end
    lastSpawnScan = now
    local out = {}
    local ok, descs = pcall(function() return Workspace:GetDescendants() end)
    if not ok or not descs then return end
    for _, obj in ipairs(descs) do
        if obj:IsA("SpawnLocation") or obj.Name == "SpawnPoint" then
            if obj:IsA("BasePart") then
                out[#out + 1] = obj
            end
        end
    end
    spawnPoints = out
end

refreshPlayers()
refreshSpawns()
Workspace.ChildAdded:Connect(function(c)
    if isRealPlayerModel(c) then lastPlayerScan = 0 end
end)
Workspace.ChildRemoved:Connect(function()
    lastPlayerScan = 0
end)

-- ============================== DRAWING SETUP ==============================
local Drawing = Drawing
local espAvailable = true
-- Probe SetRound support ONCE. Some executor Drawing libs (e.g. certain
-- Potassium builds) have no Square:SetRound and THROW on call. Never call
-- it unguarded; gate every use on this boolean.
local boxSupportsRound = false
do
    local probe = pcall(function() return Drawing.new("Square") end)
    if probe and type(probe) == "table" then
        boxSupportsRound = pcall(function() probe:SetRound(0) end)
    end
end
local function safeDrawing(type)
    local ok, d = pcall(function() return Drawing.new(type) end)
    if not ok or not d then
        espAvailable = false
        return nil
    end
    return d
end

-- Per-target ESP records, keyed by Model.
local espRecords = {}
-- Pool size for the line-based rounded-rectangle / corner renderer.
-- 4 edges + 4 corners; each corner arc uses CORNER_SEGS short segments.
local CORNER_SEGS = 8
local TRACER_POOL = 4 + 4 * CORNER_SEGS

-- Draw a FULL rectangle with rounded corners as a closed line path, using the
-- rec.tracers pool. Needed because this executor has no Square:SetRound.
-- x,y = top-left; w,h = size; r = corner radius (px).
local function hideTracers(rec, from)
    for i = from or 1, #rec.tracers do
        local tl = rec.tracers[i]
        if tl then tl.Visible = false end
    end
end

local function drawRoundedRect(rec, x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    if r < 1 then r = 1 end
    -- Build the closed path point list (clockwise from top-left, after the arc).
    local pts = {}
    local right, bottom = x + w, y + h
    -- top edge (left of TL arc -> right of TR arc)
    table.insert(pts, Vector2.new(x + r, y))
    table.insert(pts, Vector2.new(right - r, y))
    -- TR corner
    for i = 0, CORNER_SEGS do
        local a = (i / CORNER_SEGS) * (math.pi / 2)
        table.insert(pts, Vector2.new(right - r + math.cos(a) * r, y + r - math.sin(a) * r))
    end
    -- right edge
    table.insert(pts, Vector2.new(right, bottom - r))
    -- BR corner
    for i = 0, CORNER_SEGS do
        local a = (i / CORNER_SEGS) * (math.pi / 2)
        table.insert(pts, Vector2.new(right - r + math.sin(a) * r, bottom - r + math.cos(a) * r))
    end
    -- bottom edge
    table.insert(pts, Vector2.new(x + r, bottom))
    -- BL corner
    for i = 0, CORNER_SEGS do
        local a = (i / CORNER_SEGS) * (math.pi / 2)
        table.insert(pts, Vector2.new(x + r - math.cos(a) * r, bottom - r + math.sin(a) * r))
    end
    -- left edge
    table.insert(pts, Vector2.new(x, y + r))
    -- TL corner
    for i = 0, CORNER_SEGS do
        local a = (i / CORNER_SEGS) * (math.pi / 2)
        table.insert(pts, Vector2.new(x + r - math.sin(a) * r, y + r - math.cos(a) * r))
    end
    -- Emit segments.
    local n = #pts
    local used = 0
    for i = 1, n do
        local p0 = pts[i]
        local p1 = pts[i % n + 1]
        used = used + 1
        local tl = rec.tracers[used] or safeDrawing("Line")
        rec.tracers[used] = tl
        if tl then
            tl.Visible = true
            tl.Thickness = 1
            tl.Color = color
            tl.From = p0
            tl.To = p1
        end
    end
    hideTracers(rec, used + 1)
end

local function getEspRecord(model)
    local rec = espRecords[model]
    if rec then return rec end
    rec = {
        box      = safeDrawing("Square"),
        outline  = safeDrawing("Square"),
        name     = safeDrawing("Text"),
        info     = safeDrawing("Text"),
        health   = safeDrawing("Text"),
        tracer   = safeDrawing("Line"),
        tracers  = {},   -- Line pool for rounded-rect / corner rendering (TRACER_POOL)
        highlight = (function()
            local ok, h = pcall(function() return Instance.new("Highlight") end)
            if ok and h then
                h.Enabled = false
                h.DepthMode = Enum.HighlightDepthMode.Occluded
                h.Adornee = model
                -- Parent into PlayerGui so the Highlight renders (HUD-friendly, off-Character).
                local pg = pcall(function() return LocalPlayer:WaitForChild("PlayerGui", 1) end) and LocalPlayer:FindFirstChild("PlayerGui")
                if not pg then pg = game:GetService("CoreGui") end
                h.Parent = pg
                return h
            end
            return nil
        end)(),
    }
    if rec.box then
        rec.box.Thickness = 1
        rec.box.Filled = false
        rec.box.ZIndex = 2
        rec.box.Visible = false
    end
    if rec.outline then
        rec.outline.Thickness = 3
        rec.outline.Color = Color3.new(0, 0, 0)
        rec.outline.Filled = false
        rec.outline.ZIndex = 1
        rec.outline.Visible = false
    end
    if rec.name then
        rec.name.Size = 13
        rec.name.Center = true
        rec.name.Outline = true
        rec.name.OutlineColor = Color3.new(0, 0, 0)
        rec.name.ZIndex = 3
        rec.name.Visible = false
    end
    if rec.info then
        rec.info.Size = 12
        rec.info.Center = true
        rec.info.Outline = true
        rec.info.OutlineColor = Color3.new(0, 0, 0)
        rec.info.ZIndex = 3
        rec.info.Visible = false
    end
    if rec.health then
        rec.health.Size = 12
        rec.health.Center = true
        rec.health.Outline = true
        rec.health.OutlineColor = Color3.new(0, 0, 0)
        rec.health.ZIndex = 3
        rec.health.Visible = false
    end
    if rec.tracer then
        rec.tracer.Thickness = 1
        rec.tracer.ZIndex = 1
        rec.tracer.Visible = false
    end
    espRecords[model] = rec
    return rec
end

local function clearEspRecord(rec)
    if not rec then return end
    for _, k in ipairs({ "box", "outline", "name", "info", "health", "tracer" }) do
        if rec[k] then
            pcall(function() rec[k]:Remove() end)
        end
    end
    if rec.tracers then
        for _, tl in ipairs(rec.tracers) do
            pcall(function() tl:Remove() end)
        end
    end
    if rec.highlight then
        pcall(function() rec.highlight:Destroy() end)
    end
end

-- Spawnpoint markers (rebuilt when spawn list changes).
local spawnDrawings = {}
local function rebuildSpawnDrawings()
    for _, d in ipairs(spawnDrawings) do
        pcall(function() d:Remove() end)
    end
    spawnDrawings = {}
    for _, sp in ipairs(spawnPoints) do
        local circ = safeDrawing("Circle")
        local lbl = safeDrawing("Text")
        if circ then
            circ.Thickness = 2
            circ.Filled = false
            circ.NumSides = 24
            circ.Radius = 8
            circ.ZIndex = 2
            circ.Visible = false
        end
        if lbl then
            lbl.Size = 12
            lbl.Center = true
            lbl.Outline = true
            lbl.OutlineColor = Color3.new(0, 0, 0)
            lbl.ZIndex = 3
            lbl.Visible = false
        end
        spawnDrawings[#spawnDrawings + 1] = { circ = circ, lbl = lbl, part = sp }
    end
end

-- FOV circle (aimbot range indicator).
-- FOV circle: built as a 64-segment Line ring (Drawing "Circle" is unsupported
-- on some executors and silently returns nil). Lines are universal.
local fovLines = {}
local fovSegN = 64
do
    for i = 1, fovSegN do
        local ln = safeDrawing("Line")
        if ln then
            ln.Visible = false
            ln.Thickness = 1
            ln.ZIndex = 5
            fovLines[i] = ln
        end
    end
end
local function fovRingVisible(v)
    for _, ln in ipairs(fovLines) do
        if ln then ln.Visible = v end
    end
end

-- ============================== STORED ORIGINALS (restore on unload) ==============================
local origFogEnd = Lighting.FogEnd
local origFogStart = Lighting.FogStart
local origFogColor = Lighting.FogColor
local origBrightness = Lighting.Brightness
local origClockTime = Lighting.ClockTime
local origAmbient = Lighting.Ambient
local origOutdoor = Lighting.OutdoorAmbient
local origShadows = Lighting.GlobalShadows
local origFOV = cam and cam.FieldOfView or 70

-- DoF / Blur effects: discovered lazily inside the render loop (cam is valid
-- there). At load time cam may be nil, so finding here would always fail.
local dofEffect, blurEffect
local origDofEnabled, origBlurEnabled
-- Clear View post-FX (Bloom / SunRays / Atmosphere), discovered lazily.
local bloomEffect, sunRaysEffect, clearAtmo
local origBloomIntensity, origSunRaysIntensity, origAtmoDensity
-- ============================== UI ==============================
local Window = Library:CreateWindow({
    Title = "SPYBOT | Total War",
    Footer = "v1.0",
    Center = true,
    AutoShow = true,
    ToggleKeybind = Enum.KeyCode.RightShift,
    Resizable = true,
})

local Tabs = {
    Visuals = Window:AddTab("Visuals", "eye"),
    Aimbot = Window:AddTab("Aimbot", "crosshair"),
    ESP = Window:AddTab("ESP", "scan"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- ---- VISUALS ----
local VLeft = Tabs.Visuals:AddLeftGroupbox("World")
local Fullbright = VLeft:AddToggle("Fullbright", {
    Text = "Fullbright",
    Default = false,
    Callback = function(v) if not v then Lighting.Brightness = origBrightness; Lighting.ClockTime = origClockTime; Lighting.Ambient = origAmbient; Lighting.OutdoorAmbient = origOutdoor; Lighting.GlobalShadows = origShadows end end,
})
local NoFog = VLeft:AddToggle("NoFog", {
    Text = "No Fog",
    Default = false,
    Callback = function(v) if not v then Lighting.FogEnd = origFogEnd; Lighting.FogStart = origFogStart; Lighting.FogColor = origFogColor end end,
})
local NoDoF = VLeft:AddToggle("NoDoF", {
    Text = "No DoF / Blur",
    Default = false,
    Callback = function(v)
        if dofEffect then pcall(function() dofEffect.Enabled = v and false or origDofEnabled end) end
        if blurEffect then pcall(function() blurEffect.Enabled = v and false or origBlurEnabled end) end
    end,
})
local Potato = VLeft:AddToggle("Potato", {
    Text = "Potato Graphics",
    Default = false,
    Callback = function(v)
        if not v then
            local ok, gu = pcall(function() return UserSettings().GameSettings end)
            if ok and gu then
                pcall(function() gu.MasterQualityLevel = Enum.QualityLevel.Automatic end)
                pcall(function() gu.SavedQualityLevel = Enum.QualityLevel.Automatic end)
            end
            Lighting.GlobalShadows = origShadows
        end
    end,
})
local ClearView = VLeft:AddToggle("ClearView", {
    Text = "Clear View",
    Default = false,
    Tooltip = "One-click clarity: softens Bloom, disables Godrays + DoF/Blur, clears Atmosphere haze.",
})

local VRight = Tabs.Visuals:AddRightGroupbox("Camera")
local FovChanger = VRight:AddToggle("FovChanger", {
    Text = "FOV Changer",
    Default = false,
    Callback = function(v) if not v and cam then cam.FieldOfView = origFOV end end,
})
local FovSlider = VRight:AddSlider("FovValue", {
    Text = "Field of View",
    Default = 70,
    Min = 40,
    Max = 120,
    Rounding = 0,
})

-- ---- AIMBOT ----
local ALeft = Tabs.Aimbot:AddLeftGroupbox("Aimbot")
local AimEnabled = ALeft:AddToggle("AimEnabled", {
    Text = "Enable Aimbot",
    Default = true,
})
local AimMode = ALeft:AddDropdown("AimMode", {
    Text = "Mode",
    Values = { "Camera", "Mouse" },
    Default = 1,
})
local Sticky = ALeft:AddToggle("Sticky", {
    Text = "Sticky Aim",
    Default = true,
})
local AimTeamCheck = ALeft:AddToggle("AimTeamCheck", {
    Text = "Team Check",
    Default = true,
})
local AimVisible = ALeft:AddToggle("AimVisible", {
    Text = "Visible Check (Wall)",
    Default = true,
})
local AimDead = ALeft:AddToggle("AimDead", {
    Text = "Dead Check",
    Default = true,
    Tooltip = "Never aim at KO/dead targets",
})
local AimPriority = ALeft:AddDropdown("AimPriority", {
    Text = "Target Priority",
    Values = { "Nearest", "Closest to Mouse", "Both" },
    Default = 3,
})
local AimToggle = ALeft:AddDropdown("AimToggle", {
    Text = "Aim Trigger",
    Values = { "Hold", "Toggle" },
    Default = 1,
    Tooltip = "Hold = press+keep key; Toggle = tap to lock on/off",
})
local Predict = ALeft:AddToggle("Predict", {
    Text = "Target Leading",
    Default = true,
    Tooltip = "Aims where the target WILL be (velocity prediction)",
})
local LowHp = ALeft:AddToggle("LowHp", {
    Text = "Prioritize Low HP",
    Default = true,
    Tooltip = "Within priority, prefer targets with less health",
})

local ARight = Tabs.Aimbot:AddRightGroupbox("Tuning")

-- Manual aim-key (Obsidian fork has no AddKeybind method -> use UIS directly).
local cfg = { AimKey = Enum.KeyCode.F }
local rebinding = false
local keyLabel = ARight:AddLabel("Aim Key (hold): F", false, "AimKeyLabel")
ARight:AddButton({
    Text = "Rebind Aim Key",
    Func = function()
        if rebinding then return end
        rebinding = true
        keyLabel:SetText("Press any key...")
    end,
})
local AimFov = ARight:AddSlider("AimFov", {
    Text = "Aim FOV",
    Default = 12,
    Min = 5,
    Max = 360,
    Rounding = 0,
})
local AimSmooth = ARight:AddSlider("AimSmooth", {
    Text = "Smoothing (Balant)",
    Default = 15,
    Min = 1,
    Max = 100,
    Rounding = 0,
})
local AimSens = ARight:AddSlider("AimSens", {
    Text = "Sensitivity",
    Default = 0.8,
    Min = 0.01,
    Max = 1,
    Rounding = 2,
    Tooltip = "How fast/direct the bot snaps to the target (vs Smoothing = slide)",
})
local Lead = ARight:AddSlider("Lead", {
    Text = "Lead Time (s)",
    Default = 0.15,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Tooltip = "How far ahead to predict (only when Target Leading on)",
})

-- ---- ESP ----
local ELeft = Tabs.ESP:AddLeftGroupbox("Players")
local EspEnabled = ELeft:AddToggle("EspEnabled", {
    Text = "Player ESP",
    Default = true,
})
local EspBox = ELeft:AddToggle("EspBox", { Text = "Box", Default = true })
local EspName = ELeft:AddToggle("EspName", { Text = "Name", Default = true })
local EspDist = ELeft:AddToggle("EspDist", { Text = "Distance", Default = true })
local EspHealth = ELeft:AddToggle("EspHealth", { Text = "Health", Default = true })
local EspTeamColor = ELeft:AddToggle("EspTeamColor", {
    Text = "Team Color",
    Default = true,
    Tooltip = "Color boxes by team (green = teammate, red = enemy)",
})
local EspWall = ELeft:AddToggle("EspWall", {
    Text = "Wall Check",
    Default = false,
    Tooltip = "Grey out players behind walls",
})
local EspTracer = ELeft:AddToggle("EspTracer", { Text = "Tracers", Default = false })
local EspHighlight = ELeft:AddToggle("EspHighlight", {
    Text = "Highlight (enemy, no wall)",
    Default = true,
    Tooltip = "Highlights enemies ONLY when they are visible (not behind a wall) - legit-ish.",
})
local EspDead = ELeft:AddToggle("EspDead", {
    Text = "Dead Check",
    Default = true,
    Tooltip = "Hide KO/dead players from ESP",
})
local EspBoxMode = ELeft:AddDropdown("EspBoxMode", {
    Text = "Box Mode",
    Values = { "Box", "Corner" },
    Default = 1,
    Tooltip = "Box = full rectangle; Corner = bracket corners",
})
local EspBoxRound = ELeft:AddSlider("EspBoxRound", {
    Text = "Box Roundness",
    Default = 5,
    Min = 0,
    Max = 30,
    Rounding = 0,
    Tooltip = "0px = square; higher = more rounded",
})
local EspTextScale = ELeft:AddSlider("EspTextScale", {
    Text = "Text Scale",
    Default = 1,
    Min = 0.5,
    Max = 3,
    Rounding = 2,
    Tooltip = "ESP text size multiplier",
})
local EspTextAA = ELeft:AddToggle("EspTextAA", {
    Text = "Text Antialiasing",
    Default = true,
    Tooltip = "Smoother, more readable ESP text",
})
local WinnerCat = ELeft:AddToggle("WinnerCat", {
    Text = "Winner Cat",
    Default = true,
    Tooltip = "Spawns a cat near a credited kill (never center screen)",
})
local okHl = pcall(function()
    EspHighlight:AddColorPicker("HlColorCP", {
        Default = Color3.fromRGB(255, 60, 60),
        Title = "Enemy Highlight Color",
    })
end)
if not okHl then
    warn("[TotalWar] AddColorPicker unavailable - using default highlight color")
end

local ERight = Tabs.ESP:AddRightGroupbox("World")
local EspSpawn = ERight:AddToggle("EspSpawn", {
    Text = "Spawnpoint ESP",
    Default = false,
})
local FovCircleOpt = ERight:AddToggle("FovCircleEnable", {
    Text = "Show FOV Circle",
    Default = true,
    Tooltip = "Draws the aim FOV cone. Color + transparency below.",
})
local okCp = pcall(function()
    FovCircleOpt:AddColorPicker("FovCircleCP", {
        Default = Color3.fromRGB(255, 80, 80),
        Title = "FOV Circle Color",
    })
end)
if not okCp then
    warn("[TotalWar] AddColorPicker unavailable in this Obsidian build - using default FOV color")
end

-- Crosshair (pure Drawing, screen-center).
local Crosshair = ERight:AddToggle("Crosshair", {
    Text = "Crosshair",
    Default = false,
    Tooltip = "Custom center crosshair for manual aim",
})
local chLines = {}
for i = 1, 4 do
    local ln = safeDrawing("Line")
    if ln then
        ln.Thickness = 1
        ln.Visible = false
        chLines[i] = ln
    end
end
local okCh = pcall(function()
    Crosshair:AddColorPicker("ChColorCP", {
        Default = Color3.fromRGB(0, 255, 120),
        Title = "Crosshair Color",
    })
end)
if not okCh then
    warn("[TotalWar] AddColorPicker unavailable - using default crosshair color")
end

-- ============================== AIMBOT STATE ==============================
local stickyTarget = nil
local aimKeyHeld = false
UserInputService.InputBegan:Connect(function(input, gpe)
    if rebinding then
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            cfg.AimKey = input.KeyCode
            rebinding = false
            keyLabel:SetText("Aim Key (hold): " .. input.KeyCode.Name)
        end
        return
    end
    if gpe then return end
    if input.KeyCode == cfg.AimKey then
        if AimToggle.Value == "Toggle" then
            aimKeyHeld = not aimKeyHeld
        else
            aimKeyHeld = true
        end
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == cfg.AimKey and AimToggle.Value ~= "Toggle" then
        aimKeyHeld = false
    end
end)

local lastPosCache = {}   -- model -> last target point (for velocity prediction)
local lastDt = 0.016       -- last frame delta (for per-second velocity)
local prevAlive = {}       -- model -> was alive last frame (kill detection)
local catGui, catImages, pendingCat = nil, {}, false
local function computeTargetPoint(model)
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head.Position end
    local root = model:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then return root.Position end
    return getWorldPos(model)
end
local function computePredictedPoint(model, leadTime)
    if leadTime <= 0 then return computeTargetPoint(model) end
    local cur = computeTargetPoint(model)
    if not cur then return nil end
    local prev = lastPosCache[model]
    local vel = Vector3.new(0, 0, 0)
    if prev then
        -- True per-second velocity: delta over actual frame time, not over Lead.
        -- Dividing by Lead (old code) cancelled the *Lead below -> Lead had no effect.
        local dt = math.max(lastDt, 0.001)
        vel = (cur - prev) / dt
    end
    lastPosCache[model] = cur
    return cur + vel * leadTime
end

local mousemoverel = (getgenv and getgenv().mousemoverel) or mousemoverel
local function aimAt(targetPos)
    if not cam then return end
    local camPos = cam.CFrame.Position
    local sens = math.clamp(tonumber(AimSens.Value) or 0.8, 0.01, 1)
    local smooth = math.clamp(tonumber(AimSmooth.Value) / 100, 0.01, 1)
    if AimMode.Value == "Mouse" and type(mousemoverel) == "function" then
        local sp = worldToScreen(targetPos)
        if sp then
            local m = UserInputService:GetMouseLocation()
            -- Sensitivity scales how much of the error we correct this frame.
            local sx = (sp.X - m.X) * sens
            local sy = (sp.Y - m.Y) * sens
            pcall(function() mousemoverel(sx * smooth, sy * smooth) end)
        end
    else
        -- Sensitivity picks the intermediate point (directness);
        -- Smoothing eases the camera toward it (slide).
        local desired = CFrame.lookAt(camPos, targetPos)
        local weighted = cam.CFrame:Lerp(desired, sens)
        cam.CFrame = cam.CFrame:Lerp(weighted, smooth)
    end
end

local function pickAimbotTarget()
    local camPos = cam.CFrame.Position
    local lookVec = cam.CFrame.LookVector
    local aimFovRad = math.rad(tonumber(AimFov.Value) / 2)
    local priority = AimPriority.Value
    local mouse = UserInputService:GetMouseLocation()
    local best, bestScore = nil, math.huge

    for _, m in ipairs(realPlayers) do
        local hum = m:FindFirstChildWhichIsA("Humanoid")
        if hum then
            -- AimDead ON (default): skip KO/dead targets. OFF: allow aiming dead bodies.
            local dead = (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead)
            if (not AimDead.Value) or (not dead) then
                if AimTeamCheck.Value and isTeammate(m) then
                    -- skip teammates
                else
                    -- Use the REAL (un-predicted) position for scoring/FOV/LOS so the
                    -- velocity cache stays pristine for the single prediction at aim
                    -- time (line ~1209). Predicting here would zero the cache and kill Lead.
                    local tPos = computeTargetPoint(m)
                    if tPos then
                        local dir = (tPos - camPos)
                        local dist = dir.Magnitude
                        local ang = math.acos(math.clamp(dir.Unit:Dot(lookVec), -1, 1))
                        if ang <= aimFovRad then
                            local ok = true
                            if AimVisible.Value then
                                if not hasLineOfSight(camPos, computeTargetPoint(m), m) then
                                    ok = false
                                end
                            end
                            if ok then
                                local score
                                if priority == "Closest to Mouse" then
                                    local sp = worldToScreen(tPos)
                                    if sp then
                                        score = (sp - mouse).Magnitude
                                    else
                                    score = math.huge
                                end
                            elseif priority == "Both" then
                                -- Composite: cursor proximity + distance, normalized.
                                local sp = worldToScreen(tPos)
                                local mouseDist = sp and (sp - mouse).Magnitude or math.huge
                                local normMouse = math.min(mouseDist / 800, 1)
                                local normDist = math.min(dist / 500, 1)
                                score = (normMouse * 0.7) + (normDist * 0.3)
                            else
                                score = dist
                            end
                            -- Low-HP bonus: subtract a normalized health term so
                            -- weaker targets win ties within the chosen priority.
                            if LowHp.Value and hum.MaxHealth > 0 then
                                local hpFrac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                                score = score - (1 - hpFrac) * 50
                            end
    if score < bestScore then
                                bestScore = score
                                best = m
                            end
                        end
                    end
                end
            end
            end
        end
    end
    return best
end

-- ============================== MAIN RENDER LOOP ==============================
RunService.RenderStepped:Connect(function(dt)
    if not running then return end

    cam = Workspace.CurrentCamera
    if not cam then return end
    lastDt = (dt and dt > 0) and dt or 0.016

    -- Lazily discover camera post-effects (DoF/Blur) now that cam is valid.
    if not dofEffect then
        dofEffect = pcall(function() return cam:FindFirstChildOfClass("DepthOfFieldEffect") end) and cam:FindFirstChildOfClass("DepthOfFieldEffect") or nil
        if dofEffect and origDofEnabled == nil then origDofEnabled = dofEffect.Enabled end
    end
    if not blurEffect then
        blurEffect = pcall(function() return cam:FindFirstChildOfClass("BlurEffect") end) and cam:FindFirstChildOfClass("BlurEffect") or nil
        if blurEffect and origBlurEnabled == nil then origBlurEnabled = blurEffect.Enabled end
    end
    -- Lazily discover Lighting post-FX for Clear View (Bloom / SunRays / Atmosphere).
    if not bloomEffect then
        bloomEffect = pcall(function() return Lighting:FindFirstChildOfClass("BloomEffect") end) and Lighting:FindFirstChildOfClass("BloomEffect") or nil
        if bloomEffect and origBloomIntensity == nil then origBloomIntensity = bloomEffect.Intensity end
    end
    if not sunRaysEffect then
        sunRaysEffect = pcall(function() return Lighting:FindFirstChildOfClass("SunRaysEffect") end) and Lighting:FindFirstChildOfClass("SunRaysEffect") or nil
        if sunRaysEffect and origSunRaysIntensity == nil then origSunRaysIntensity = sunRaysEffect.Intensity end
    end
    if not clearAtmo then
        clearAtmo = pcall(function() return Lighting:FindFirstChildOfClass("Atmosphere") end) and Lighting:FindFirstChildOfClass("Atmosphere") or nil
        if clearAtmo and origAtmoDensity == nil then origAtmoDensity = clearAtmo.Density end
    end

    refreshPlayers()
    refreshSpawns()

    -- ---- KILL SCAN (stealth credit, single source of truth) ----
    -- Any real-player enemy that transitions alive->dead this frame counts as a
    -- credit, provided the aimbot feature is enabled (cheat is in use). No remotes.
    -- Centralized here only; the old aimbot-block attribution was removed to avoid
    -- double-firing and to stop it pre-zeroing prevAlive (which masked transitions).
    do
        local cheatActive = AimEnabled.Value
        for _, m in ipairs(realPlayers) do
            local hum = m:FindFirstChildWhichIsA("Humanoid")
            if hum then
                local dead = (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead)
                local was = prevAlive[m]
                if dead and was == true and cheatActive and WinnerCat.Value then
                    pendingCat = true
                end
                prevAlive[m] = not dead
            end
        end
    end

    -- ---- VISUALS (applied every frame; idempotent + reversible) ----
    if Fullbright.Value then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.GlobalShadows = false
    end
    if NoFog.Value then
        Lighting.FogEnd = 9e9
        Lighting.FogStart = 9e9
        -- Also kill Atmosphere-based fog if the game uses it instead of classic fog.
        pcall(function()
            local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
            if atmo then atmo.Density = 0 end
        end)
    end
    if NoDoF.Value then
        if dofEffect then pcall(function() dofEffect.Enabled = false end) end
        if blurEffect then pcall(function() blurEffect.Enabled = false end) end
    end
    if ClearView.Value then
        -- One-click clarity. Softens (not disables) Bloom, kills Godrays,
        -- DoF/Blur, and Atmosphere haze so the scene reads cleanly.
        if bloomEffect then pcall(function() bloomEffect.Intensity = origBloomIntensity * 0.35 end) end
        if sunRaysEffect then pcall(function() sunRaysEffect.Enabled = false end) end
        if dofEffect then pcall(function() dofEffect.Enabled = false end) end
        if blurEffect then pcall(function() blurEffect.Enabled = false end) end
        if clearAtmo then pcall(function() clearAtmo.Density = math.min(origAtmoDensity or 0, 0) * 0.15 end) end
    end
    if Potato.Value then
        local ok, gu = pcall(function() return UserSettings().GameSettings end)
        if ok and gu then
            pcall(function() gu.MasterQualityLevel = Enum.QualityLevel.Level01 end)
            pcall(function() gu.SavedQualityLevel = Enum.QualityLevel.Level01 end)
        end
        Lighting.GlobalShadows = false
    end
    if FovChanger.Value and cam then
        cam.FieldOfView = tonumber(FovSlider.Value)
    end

    -- ---- ESP: PLAYERS ----
    local showEsp = EspEnabled.Value and espAvailable
    -- hide stale records for models no longer present
    for model, rec in pairs(espRecords) do
        local stillReal = false
        for _, m in ipairs(realPlayers) do
            if m == model then stillReal = true; break end
        end
        if not stillReal then
            clearEspRecord(rec)
            espRecords[model] = nil
        end
    end

    if showEsp then
        for _, m in ipairs(realPlayers) do
            local hum0 = m:FindFirstChildWhichIsA("Humanoid")
            if EspDead.Value and hum0 and (hum0.Health <= 0 or hum0:GetState() == Enum.HumanoidStateType.Dead) then
                -- dead/KO: hide record
                local rec0 = espRecords[m]
                if rec0 then clearEspRecord(rec0) end
                espRecords[m] = nil
            else
            local rec = getEspRecord(m)
            if not rec or not rec.box then
                -- drawing unavailable; skip
            else
                local rootPos = getWorldPos(m)
                local hum = m:FindFirstChildWhichIsA("Humanoid")
                if not rootPos or not hum then
                    rec.box.Visible = false
                    rec.outline.Visible = false
                    rec.name.Visible = false
                    rec.info.Visible = false
                    rec.health.Visible = false
                    rec.tracer.Visible = false
                    if rec.highlight then rec.highlight.Enabled = false end
                else
                    local top = rootPos + Vector3.new(0, 3, 0)
                    local bottom = rootPos - Vector3.new(0, 3, 0)
                    local sTop = worldToScreen(top)
                    local sBot = worldToScreen(bottom)
                    -- Viewport cull: a point in front of the camera but outside the
                    -- screen (e.g. when you turn away) still returns onScreen=true
                    -- with extreme coords, so boxes linger off-screen. Hide records
                    -- whose projected bounds fall fully outside the viewport.
                    local vp = cam.ViewportSize
                    local margin = 80
                    local onScreen = sTop and sBot
                        and sTop.X > -margin and sTop.X < vp.X + margin
                        and sBot.X > -margin and sBot.X < vp.X + margin
                        and sTop.Y > -margin and sTop.Y < vp.Y + margin
                        and sBot.Y > -margin and sBot.Y < vp.Y + margin
                    if not sTop or not sBot or not onScreen then
                        rec.box.Visible = false
                        rec.outline.Visible = false
                        rec.name.Visible = false
                        rec.info.Visible = false
                        rec.health.Visible = false
                        rec.tracer.Visible = false
                        if rec.highlight then rec.highlight.Enabled = false end
                    else
                        local h = math.abs(sBot.Y - sTop.Y)
                        local w = math.max(h * 0.45, 16)
                        local x = sTop.X - w / 2
                        local y = sTop.Y

                        local color
                        if EspTeamColor.Value and isTeammate(m) then
                            color = Color3.fromRGB(60, 220, 90)
                        else
                            color = Color3.fromRGB(255, 70, 70)
                        end
                        if EspWall.Value then
                            if not hasLineOfSight(cam.CFrame.Position, rootPos, m) then
                                color = Color3.fromRGB(140, 140, 140)
                            end
                        end

                        -- Highlight: only for ENEMIES and ONLY when visible (no wall).
                        -- DepthMode = Occluded so it never shows through walls.
                        local wantHl = false
                        local hlColor = Color3.fromRGB(255, 60, 60)
                        pcall(function()
                            if Library.Options and Library.Options.HlColorCP then
                                hlColor = Library.Options.HlColorCP.Value
                            end
                        end)
                        if rec.highlight then
                            if EspHighlight.Value
                                and (not EspTeamColor.Value or not isTeammate(m))
                                and not (EspWall.Value and not hasLineOfSight(cam.CFrame.Position, rootPos, m))
                            then
                                wantHl = true
                                rec.highlight.FillColor = hlColor
                                rec.highlight.OutlineColor = hlColor
                            end
                            rec.highlight.Enabled = wantHl
                        end

                        if EspBox.Value then
                            local round = math.floor(tonumber(EspBoxRound.Value) or 0)
                            local ts = (tonumber(EspTextScale.Value) or 1) * 1.3
                            local aa = EspTextAA.Value
                            if EspBoxMode.Value == "Corner" then
                                -- Bracket corners only. Cut size = EspBoxRound (px),
                                -- falling back to 28% of the shorter side when 0.
                                local c = (round > 0) and round or math.min(w, h) * 0.28
                                local corners = {
                                    { x, y, x + c, y },
                                    { x, y, x, y + c },
                                    { x + w, y, x + w - c, y },
                                    { x + w, y, x + w, y + c },
                                    { x, y + h, x + c, y + h },
                                    { x, y + h, x, y + h - c },
                                    { x + w, y + h, x + w - c, y + h },
                                    { x + w, y + h, x + w, y + h - c },
                                }
                                rec.box.Visible = false
                                rec.outline.Visible = false
                                for i = 1, 8 do
                                    local seg = corners[i]
                                    local tl = rec.tracers[i] or safeDrawing("Line")
                                    rec.tracers[i] = tl
                                    if tl then
                                        tl.Visible = true
                                        tl.Thickness = 1
                                        tl.Color = color
                                        tl.From = Vector2.new(seg[1], seg[2])
                                        tl.To = Vector2.new(seg[3], seg[4])
                                    end
                                end
                                hideTracers(rec, 9)
                            else
                                -- FULL rectangle. If SetRound is supported, use it.
                                -- Otherwise draw a real rounded-corner full box as a
                                -- closed line path (this executor has no SetRound).
                                if round > 0 and boxSupportsRound then
                                    rec.box.Visible = true
                                    rec.box.Filled = false
                                    rec.box.Size = Vector2.new(w, h)
                                    rec.box.Position = Vector2.new(x, y)
                                    rec.box.Color = color
                                    pcall(function() rec.box:SetRound(round) end)
                                    rec.outline.Visible = false
                                    hideTracers(rec, 1)
                                elseif round > 0 then
                                    -- Rounded full box via line path.
                                    rec.box.Visible = false
                                    rec.outline.Visible = false
                                    drawRoundedRect(rec, x, y, w, h, round, color)
                                else
                                    -- Plain full rectangle.
                                    rec.outline.Visible = true
                                    rec.outline.Size = Vector2.new(w, h)
                                    rec.outline.Position = Vector2.new(x - 1, y - 1)
                                    rec.box.Visible = true
                                    rec.box.Filled = false
                                    rec.box.Size = Vector2.new(w, h)
                                    rec.box.Position = Vector2.new(x, y)
                                    rec.box.Color = color
                                    hideTracers(rec, 1)
                                end
                            end
                            -- Text scale + antialias applied to all text.
                            local base = { rec.name, rec.info, rec.health }
                            for _, t in ipairs(base) do
                                if t then
                                    t.Size = math.max(8, math.floor((t == rec.name and 13 or 12) * ts))
                                    t.Font = aa and 3 or 1
                                end
                            end
                        else
                            rec.box.Visible = false
                            rec.outline.Visible = false
                            hideTracers(rec, 1)
                        end

                        local labelY = y - 16
                        if EspName.Value then
                            rec.name.Visible = true
                            rec.name.Text = m.Name
                            rec.name.Position = Vector2.new(sTop.X, labelY)
                            rec.name.Color = color
                        else
                            rec.name.Visible = false
                        end

                        local infoY = sBot.Y + 4
                        local infoParts = {}
                        if EspDist.Value then
                            infoParts[#infoParts + 1] = math.floor((rootPos - cam.CFrame.Position).Magnitude) .. "m"
                        end
                        if EspHealth.Value then
                            infoParts[#infoParts + 1] = math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth)
                        end
                        if #infoParts > 0 then
                            rec.info.Visible = true
                            rec.info.Text = table.concat(infoParts, "  ")
                            rec.info.Position = Vector2.new(sTop.X, infoY)
                            rec.info.Color = color
                        else
                            rec.info.Visible = false
                        end
                        rec.health.Visible = false

                        if EspTracer.Value then
                            local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                            rec.tracer.Visible = true
                            rec.tracer.From = center
                            rec.tracer.To = Vector2.new(sTop.X, y + h / 2)
                            rec.tracer.Color = color
                        else
                            rec.tracer.Visible = false
                        end
                    end
                end
            end
            end
        end
    end

    -- ---- ESP: SPAWNPOINTS ----
    if EspSpawn.Value and espAvailable then
        if #spawnDrawings ~= #spawnPoints then
            rebuildSpawnDrawings()
        end
        for _, d in ipairs(spawnDrawings) do
            if d.part and d.part.Parent then
                local pos = getWorldPos(d.part)
                local sp = pos and worldToScreen(pos)
                if sp and d.circ then
                    d.circ.Visible = true
                    d.circ.Position = sp
                    d.circ.Color = Color3.fromRGB(90, 160, 255)
                    if d.lbl then
                        d.lbl.Visible = true
                        d.lbl.Text = "Spawn"
                        d.lbl.Position = Vector2.new(sp.X, sp.Y - 16)
                        d.lbl.Color = Color3.fromRGB(90, 160, 255)
                    end
                else
                    if d.circ then d.circ.Visible = false end
                    if d.lbl then d.lbl.Visible = false end
                end
            else
                if d.circ then d.circ.Visible = false end
                if d.lbl then d.lbl.Visible = false end
            end
        end
    else
        for _, d in ipairs(spawnDrawings) do
            if d.circ then d.circ.Visible = false end
            if d.lbl then d.lbl.Visible = false end
        end
    end

    -- ---- FOV CIRCLE (line ring) ----
    if FovCircleOpt.Value and #fovLines > 0 and cam then
        local fovCircleColor = Color3.fromRGB(255, 80, 80)
        pcall(function()
            if Library.Options and Library.Options.FovCircleCP then
                fovCircleColor = Library.Options.FovCircleCP.Value
            end
        end)
        local cx = cam.ViewportSize.X / 2
        local cy = cam.ViewportSize.Y / 2
        local radius = (tonumber(AimFov.Value) / cam.FieldOfView) * (cam.ViewportSize.Y / 2)
        for i = 1, #fovLines do
            local a0 = (i - 1) / fovSegN * (2 * math.pi)
            local a1 = i / fovSegN * (2 * math.pi)
            local ln = fovLines[i]
            if ln then
                ln.Visible = true
                ln.Color = fovCircleColor
                ln.Thickness = 1
                ln.From = Vector2.new(cx + math.cos(a0) * radius, cy + math.sin(a0) * radius)
                ln.To = Vector2.new(cx + math.cos(a1) * radius, cy + math.sin(a1) * radius)
            end
        end
    else
        fovRingVisible(false)
    end

    -- ---- CROSSHAIR ----
    do
        local cx = cam.ViewportSize.X / 2
        local cy = cam.ViewportSize.Y / 2
        local gap = 5
        local len = 8
        local chColor = Color3.fromRGB(0, 255, 120)
        pcall(function()
            if Library.Options and Library.Options.ChColorCP then
                chColor = Library.Options.ChColorCP.Value
            end
        end)
        local segs = {
            { cx - gap - len, cy, cx - gap, cy },
            { cx + gap, cy, cx + gap + len, cy },
            { cx, cy - gap - len, cx, cy - gap },
            { cx, cy + gap, cx, cy + gap + len },
        }
        for i, ln in ipairs(chLines) do
            if Crosshair.Value then
                local s = segs[i]
                ln.Visible = true
                ln.From = Vector2.new(s[1], s[2])
                ln.To = Vector2.new(s[3], s[4])
                ln.Color = chColor
            else
                ln.Visible = false
            end
        end
    end

    -- ---- WINNER CAT ----
    do
        if not catGui then
            local pg = (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")) or game:GetService("CoreGui")
            local okGui = pcall(function()
                catGui = Instance.new("ScreenGui")
                catGui.Name = "WinnerCatGui"
                catGui.ResetOnSpawn = false
                catGui.DisplayOrder = 50
                catGui.IgnoreGuiInset = true
                catGui.Parent = pg
            end)
            if not okGui then catGui = nil end
        end
        -- spawn a cat for a freshly-credited kill (off-center, never screen middle)
        if WinnerCat.Value and pendingCat then
            local vp = cam.ViewportSize
            local rx = math.random(40, math.max(60, vp.X - 120))
            local ry = math.random(60, math.max(100, vp.Y - 120))
            local cx0 = vp.X / 2
            local cy0 = vp.Y / 2
            if math.abs(rx - cx0) < vp.X * 0.2 and math.abs(ry - cy0) < vp.Y * 0.2 then
                ry = ry - vp.Y * 0.28
                if ry < 40 then ry = ry + vp.Y * 0.5 end
            end
            local okImg = pcall(function()
                local img = Instance.new("ImageLabel")
                img.Name = "WinnerCat"
                img.Size = UDim2.fromOffset(90, 90)
                img.Position = UDim2.fromOffset(rx, ry)
                img.BackgroundTransparency = 1
                img.Image = "rbxassetid://8665513552"
                img.ImageTransparency = 0
                img.ZIndex = 50
                img.Parent = catGui
                catImages[#catImages + 1] = { obj = img, t = 0 }
            end)
            pendingCat = false
            if not okImg then
                warn("[TotalWar] Winner Cat image load blocked")
            end
        end
        -- advance each cat: 1s visible, then 3s fade
        for i = #catImages, 1, -1 do
            local c = catImages[i]
            c.t = c.t + (dt or 0.016)
            if c.t > 1 then
                local f = c.t - 1
                if f >= 3 then
                    pcall(function() c.obj:Destroy() end)
                    table.remove(catImages, i)
                else
                    local tr = 1 - (f / 3)
                    pcall(function() c.obj.ImageTransparency = tr end)
                end
            end
        end
    end

    -- ---- AIMBOT ----
    if AimEnabled.Value and aimKeyHeld and running then
        local target = nil
        if Sticky.Value and stickyTarget and stickyTarget.Parent then
            local hum = stickyTarget:FindFirstChildWhichIsA("Humanoid")
            local stillValid = hum and hum.Health > 0
            if stillValid and AimTeamCheck.Value and isTeammate(stickyTarget) then
                stillValid = false
            end
            if stillValid then
                target = stickyTarget
            else
                stickyTarget = nil
            end
        end
        if not target then
            target = pickAimbotTarget()
            stickyTarget = target
        end
        if target then
            -- Single velocity sample per frame: compute the (optionally predicted)
            -- point exactly once here. pickAimbotTarget used computeTargetPoint for
            -- scoring/LOS only; prediction is done once at aim time.
            local tPos = computeTargetPoint(target)
            if Predict.Value then
                tPos = computePredictedPoint(target, tonumber(Lead.Value))
            end
            if tPos then
                aimAt(tPos)
            end
        end
    else
        stickyTarget = nil
    end
end)

-- ============================== SAVE / THEME ==============================
if SaveManager then
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetFolder("TotalWarAimbot")
    SaveManager:BuildConfigSection(Tabs["UI Settings"])
    SaveManager:LoadAutoloadConfig()
end
if ThemeManager then
    ThemeManager:SetFolder("TotalWarAimbot")
    ThemeManager:ApplyToTab(Tabs["UI Settings"])
    ThemeManager:LoadDefault()
end

-- ============================== STARTUP EASTER EGG ==============================
-- 10% chance on execution to flash asset 6742954963 once, then auto-dismiss.
do
    if math.random() < 0.10 then
        local pg = (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")) or game:GetService("CoreGui")
        pcall(function()
            local egg = Instance.new("ScreenGui")
            egg.Name = "StartupEgg"
            egg.ResetOnSpawn = false
            egg.IgnoreGuiInset = true
            egg.DisplayOrder = 200
            egg.Parent = pg
            local img = Instance.new("ImageLabel")
            img.Size = UDim2.fromScale(0.5, 0.5)
            img.Position = UDim2.fromScale(0.25, 0.25)
            img.BackgroundTransparency = 1
            img.Image = "rbxassetid://6742954963"
            img.ImageTransparency = 0
            img.ZIndex = 200
            img.Parent = egg
            task.delay(4, function()
                pcall(function() egg:Destroy() end)
            end)
        end)
    end
end

-- Unload button on the UI Settings tab.
Tabs["UI Settings"]:AddRightGroupbox("Control"):AddButton({
    Text = "Unload Cheat",
    Func = function()
        Library:Unload()
    end,
})

-- ============================== CLEANUP ==============================
Library:OnUnload(function()
    running = false
    -- remove all drawings
    for _, rec in pairs(espRecords) do clearEspRecord(rec) end
    espRecords = {}
    for _, d in ipairs(spawnDrawings) do
        if d.circ then pcall(function() d.circ:Remove() end) end
        if d.lbl then pcall(function() d.lbl:Remove() end) end
    end
    spawnDrawings = {}
    for _, ln in ipairs(fovLines) do
        if ln then pcall(function() ln:Remove() end) end
    end
    for _, ln in ipairs(chLines) do
        pcall(function() ln:Remove() end)
    end
    lastPosCache = {}
    for _, c in ipairs(catImages) do pcall(function() c.obj:Destroy() end) end
    catImages = {}
    if catGui then pcall(function() catGui:Destroy() end) catGui = nil end
    -- restore visuals
    pcall(function()
        Lighting.FogEnd = origFogEnd
        Lighting.FogStart = origFogStart
        Lighting.FogColor = origFogColor
        Lighting.Brightness = origBrightness
        Lighting.ClockTime = origClockTime
        Lighting.Ambient = origAmbient
        Lighting.OutdoorAmbient = origOutdoor
        Lighting.GlobalShadows = origShadows
    end)
    if cam then pcall(function() cam.FieldOfView = origFOV end) end
    if dofEffect and origDofEnabled ~= nil then pcall(function() dofEffect.Enabled = origDofEnabled end) end
    if blurEffect and origBlurEnabled ~= nil then pcall(function() blurEffect.Enabled = origBlurEnabled end) end
    if bloomEffect and origBloomIntensity ~= nil then pcall(function() bloomEffect.Intensity = origBloomIntensity end) end
    if sunRaysEffect and origSunRaysIntensity ~= nil then pcall(function() sunRaysEffect.Intensity = origSunRaysIntensity end) end
    if clearAtmo and origAtmoDensity ~= nil then pcall(function() clearAtmo.Density = origAtmoDensity end) end
end)

-- ============================== STARTUP ==============================
Library:Notify({
    Title = "Total War Aimbot & ESP",
    Description = "Loaded. RightShift = toggle UI. F = aim key (hold). Rebind in Aimbot tab.",
    Time = 6,
})
