--[[
    ====================================================================
    SPYTERMINAL v10 — Advanced Developer Console
    ====================================================================
    Target : StarterPlayerScripts (LocalScript)
    Toggle : DELETE key
    Style  : Dark-mode, monospace, sharp corners, IDE-inspired
    ====================================================================
--]]

-- luacheck: globals game Color3 Enum Instance UDim2 UDim Vector2 Vector3
-- luacheck: globals TweenInfo task workspace setclipboard warn pcall tonumber tostring
-- luacheck: globals ipairs pairs next table string math os loadstring type

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LogService       = game:GetService("LogService")
local TweenService     = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local C = {
    Bg         = Color3.fromRGB(20, 20, 24),
    TopBar     = Color3.fromRGB(28, 28, 32),
    Border     = Color3.fromRGB(50, 50, 55),
    SearchBg   = Color3.fromRGB(32, 32, 36),
    EvalBg     = Color3.fromRGB(16, 16, 20),
    SettingsBg = Color3.fromRGB(34, 34, 40),

    BtnIdle    = Color3.fromRGB(45, 45, 50),
    BtnHover   = Color3.fromRGB(60, 60, 66),
    BtnActive  = Color3.fromRGB(78, 78, 85),
    BtnTxt     = Color3.fromRGB(180, 180, 185),
    BtnAccent  = Color3.fromRGB(70, 130, 230),
    BtnSel     = Color3.fromRGB(50, 110, 210),

    Placeholder = Color3.fromRGB(100, 100, 110),
    Text        = Color3.fromRGB(195, 195, 200),
    Stamp       = Color3.fromRGB(90, 90, 100),

    LogMsg      = Color3.fromRGB(185, 185, 190),
    LogWarn     = Color3.fromRGB(235, 185, 45),
    LogErr      = Color3.fromRGB(235, 55, 55),
    TitleCol    = Color3.fromRGB(0, 220, 130),

    DefW       = 680, DefH = 380, MinW = 320, MinH = 200,
    TopBarH    = 32, EvalH = 26, Margin = 12,
    TweenT     = 0.28, SlideOff = 50, MaxLogs = 800, MaxChars = 180000,

    Font       = Enum.Font.Code,
    BtnFont    = Enum.Font.GothamBold,
    LogSz      = 13, BarSz = 11, TitleSz = 13,

    ShadowOff  = 5,
    ShadowAlpha = 0.62,

}

local function new(cls, props)
    local inst = Instance.new(cls)
    for k, v in next, props do
        inst[k] = v
    end
    return inst
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function fmtScale(val)
    return string.format("x%.1f", val)
end

local function Main()

    -- STATE
    local isOpen          = false
    local isAnimating     = false
    local dragMode        = nil
    local autoScroll      = true
    local activeFilter    = "All"
    local searchQuery     = ""
    local currentPreset   = "BottomLeft"
    local consoleFontScale = 1.0
    local menuFontScale    = 1.0
    local logs            = {}
    local totalCount      = 0
    local dragMouse0, dragPos0
    local resizeMouse0, resizeSize0
    local flushPending    = false  -- batch log flush debounce
    local logsPendingFlush = 0    -- how many logs arrived this defer-frame
    local logChars         = 0    -- estimated total chars of stored log entries
    local evalHistory     = {}    -- eval command history
    local evalHistIdx     = 0     -- current history navigation index
    local showTimestamp   = true   -- toggle log timestamp visibility
    local dedupLast       = nil    -- last log entry for dedup detection
    local dedupCount      = 0      -- consecutive repeat count of last log
    local savedFramePos   = nil    -- position saved before slide-out (Draggable)
    local savedFrameSize  = nil    -- size saved before slide-out (preserves resize)

    -- UI REFS
    local gui, consoleFrame, shadowFrame
    local logBox, searchBox, evalBox, evalPrompt
    local btnClear, btnCopy, btnAutoScroll, btnSettings
    local btnAll, btnWarn, btnError
    local countLabel, titleLabel
    local resizeHandle
    local settingsOverlay
    local positionSettingsPanel
    local btnTimestamp              -- timestamp toggle button
    local evalHistLabel             -- history index indicator in eval bar
    local showTooltip, hideTooltip  -- tooltip helpers (assigned after GUI build)

    -- UTILITY
    local function viewport()
        local cam = workspace.CurrentCamera
        if cam then
            return cam.ViewportSize
        end
        return Vector2.new(1920, 1080)
    end

    local function stamp()
        return os.date("%H:%M:%S")
            .. "." .. string.format("%03d", math.floor((os.clock() % 1) * 1000))
    end

    local function tag(msgType)
        if msgType == Enum.MessageType.MessageWarning then
            return "WARN"
        end
        if msgType == Enum.MessageType.MessageError then
            return "ERR!"
        end
        return "INFO"
    end

    -- POSITION (AnchorPoint 0,0)
    local function calcTopLeft(preset, vpV, w, h, m)
        local x, y
        if preset == "BottomLeft" then
            x, y = m, vpV.Y - h - m
        elseif preset == "TopLeft" then
            x, y = m, m
        elseif preset == "BottomRight" then
            x, y = vpV.X - w - m, vpV.Y - h - m
        elseif preset == "TopRight" then
            x, y = vpV.X - w - m, m
        elseif preset == "Center" then
            x, y = (vpV.X - w) / 2, (vpV.Y - h) / 2
        elseif preset == "Draggable" then
            local abs = consoleFrame.AbsolutePosition
            x, y = abs.X, abs.Y
        else
            x, y = m, vpV.Y - h - m
        end
        return Vector2.new(math.max(0, x), math.max(0, y))
    end

    local function syncShadow()
        if not consoleFrame or not shadowFrame then
            return
        end
        -- Shadow frame mirrors console exactly; child layers add their own offsets
        shadowFrame.Position = consoleFrame.Position
        shadowFrame.Size = consoleFrame.Size
        shadowFrame.Visible = consoleFrame.Visible
    end

    local function snapToPreset(animate)
        local v  = viewport()
        local w  = consoleFrame.AbsoluteSize.X
        local h  = consoleFrame.AbsoluteSize.Y
        -- AbsoluteSize is (0,0) before first render — fall back to defaults
        if w < 1 then w = C.DefW end
        if h < 1 then h = C.DefH end
        local tl = calcTopLeft(currentPreset, v, w, h, C.Margin)
        if animate and isOpen then
            local tw = TweenService:Create(consoleFrame, TweenInfo.new(
                C.TweenT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out
            ), { Position = UDim2.fromOffset(tl.X, tl.Y) })
            tw:Play()
        else
            consoleFrame.Position = UDim2.fromOffset(tl.X, tl.Y)
        end
    end

    -- FONT SCALE
    local function applyFontScales()
        local logSz   = math.round(C.LogSz * consoleFontScale)
        local barSz   = math.round(C.BarSz * menuFontScale)
        local titleSz = math.round(C.TitleSz * menuFontScale)

        -- Console font
        logBox.TextSize = logSz
        evalBox.TextSize = logSz
        if evalPrompt then
            evalPrompt.TextSize = logSz
        end

        -- Menu font — title
        titleLabel.TextSize = titleSz

        -- Menu font — labels
        countLabel.TextSize = barSz
        searchBox.TextSize = barSz

        -- Menu font — buttons
        local btns = { btnClear, btnCopy, btnAutoScroll, btnSettings,
                       btnAll, btnWarn, btnError, btnTimestamp }
        for _, b in ipairs(btns) do
            if b then
                b.TextSize = barSz
            end
        end
    end

    -- LOG MANAGEMENT (dependency order — Luau has no forward hoisting)
    local function formatLine(e)
        local dc = e.dedupCount or 1
        local suffix = dc > 1 and ("  [×" .. dc .. "]") or ""
        if showTimestamp then
            return string.format("[%s] [%s] %s%s", e.stamp, tag(e.msgType), e.text, suffix)
        else
            return string.format("[%s] %s%s", tag(e.msgType), e.text, suffix)
        end
    end

    local function buildText()
        local parts = {}
        local vc = 0
        local f = activeFilter
        local q = searchQuery:lower()
        for _, e in ipairs(logs) do
            local skip = false
            if f == "Warning" and e.msgType ~= Enum.MessageType.MessageWarning then
                skip = true
            elseif f == "Error" and e.msgType ~= Enum.MessageType.MessageError then
                skip = true
            elseif q ~= "" and not e.text:lower():find(q, 1, true) then
                skip = true
            end
            if not skip then
                vc = vc + 1
                table.insert(parts, formatLine(e))
            end
        end
        if countLabel then
            -- totalCount reflects how many logs arrived total; #logs may be
            -- capped at MaxLogs, so display the real received count.
            countLabel.Text = string.format("%d/%d", vc, totalCount)
        end
        return table.concat(parts, "\n")
    end

    local function refresh()
        local t = buildText()
        logBox.Text = t
        if autoScroll and #t > 0 then
            task.defer(function()
                logBox.CursorPosition = #t + 1
            end)
        end
    end

    -- Fast incremental append: adds one line without full rebuild.
    -- Only called when no filter and no search query are active.
    local function appendLine(entry)
        local line = formatLine(entry)
        local cur = logBox.Text
        if cur == "" then
            logBox.Text = line
        else
            logBox.Text = cur .. "\n" .. line
        end
        -- Update visible count label: fast-path is only reached when
        -- no filter and no search are active, so all #logs entries are visible.
        if countLabel then
            countLabel.Text = string.format("%d/%d", #logs, totalCount)
        end
        if autoScroll then
            local len = #logBox.Text
            task.defer(function()
                logBox.CursorPosition = len + 1
            end)
        end
    end

    local function addLog(msg, msgType)
        totalCount = totalCount + 1
        -- Dedup: identical consecutive message — bump counter on last entry
        if dedupLast and dedupLast.text == msg and dedupLast.msgType == msgType then
            dedupCount = dedupCount + 1
            dedupLast.dedupCount = dedupCount
            if isOpen and not flushPending then
                flushPending = true
                task.defer(function()
                    logsPendingFlush = 0
                    flushPending = false
                    refresh()
                end)
            end
            return
        end
        dedupCount = 1
        local entry = { stamp = stamp(), msgType = msgType, text = msg, dedupCount = 1 }
        dedupLast = entry
        table.insert(logs, entry)
        -- 22 chars = overhead of "[HH:MM:SS.mmm] [INFO] " prefix per line
        logChars = logChars + #msg + 22
        -- Trim from the front while over either limit
        while #logs > C.MaxLogs or logChars > C.MaxChars do
            local removed = table.remove(logs, 1)
            logChars = logChars - (#removed.text + 22)
            if dedupLast == removed then dedupLast = nil end
        end
        if not isOpen then
            return
        end
        logsPendingFlush = logsPendingFlush + 1
        if not flushPending then
            flushPending = true
            task.defer(function()
                local burst = logsPendingFlush
                logsPendingFlush = 0
                flushPending = false
                if burst == 1 and activeFilter == "All" and searchQuery == "" then
                    -- Fast path: single log, no filter — just append the line.
                    appendLine(entry)
                else
                    -- Burst or filtered: full rebuild needed.
                    refresh()
                end
            end)
        end
    end

    local function clearLogs()
        logs = {}
        totalCount = 0
        logChars = 0
        dedupLast  = nil
        dedupCount = 0
        logBox.Text = ""
        if countLabel then
            countLabel.Text = "0/0"
        end
    end

    -- UI HELPERS
    local function updateFilters()
        local map = {
            All = btnAll,
            Warning = btnWarn,
            Error = btnError,
        }
        for name, btn in pairs(map) do
            if name == activeFilter then
                btn.BackgroundColor3 = C.BtnAccent
                btn.TextColor3 = Color3.new(1, 1, 1)
            else
                btn.BackgroundColor3 = C.BtnIdle
                btn.TextColor3 = C.BtnTxt
            end
        end
    end

    local function updateAutoScroll()
        if autoScroll then
            btnAutoScroll.BackgroundColor3 = C.BtnAccent
            btnAutoScroll.TextColor3 = Color3.new(1, 1, 1)
            btnAutoScroll.Text = "Scroll:ON"
        else
            btnAutoScroll.BackgroundColor3 = C.BtnIdle
            btnAutoScroll.TextColor3 = C.BtnTxt
            btnAutoScroll.Text = "Scroll:OFF"
        end
    end

    -- ================================================================
    -- TYPEWRITER — looping animation with type / hold / erase cycle
    -- ================================================================
    local titleText    = "SPYTERMINAL"
    local twGeneration = 0  -- incremented each time a new loop is spawned;
                            -- old loops compare and self-terminate immediately

    local function setTitle(text)
        titleLabel.Text = text
    end

    local function typewriterLoop(gen)
        while isOpen and twGeneration == gen do
            -- PHASE 1: Type characters one by one (80 ms each)
            for i = 1, #titleText do
                if not isOpen or twGeneration ~= gen then return end
                setTitle(titleText:sub(1, i) .. "_")
                task.wait(0.08)
            end

            -- PHASE 2: Show full title for 5 seconds
            if not isOpen or twGeneration ~= gen then return end
            setTitle(titleText)
            task.wait(5)

            -- PHASE 3: Erase characters one by one (55 ms each)
            for i = #titleText - 1, 0, -1 do
                if not isOpen or twGeneration ~= gen then return end
                setTitle(i > 0 and (titleText:sub(1, i) .. "_") or "_")
                task.wait(0.055)
            end

            -- Pause before restarting
            if not isOpen or twGeneration ~= gen then return end
            task.wait(0.6)
        end
    end

    local function startTypewriter()
        twGeneration = twGeneration + 1
        local gen = twGeneration
        task.spawn(typewriterLoop, gen)
    end

    -- ANIMATION
    local function openConsole()
        if isAnimating then
            return
        end
        isAnimating = true
        local v = viewport()
        -- Restore saved size (preserves any user resize); fall back to defaults
        local w = savedFrameSize and savedFrameSize.X.Offset or C.DefW
        local h = savedFrameSize and savedFrameSize.Y.Offset or C.DefH
        if w < C.MinW then w = C.DefW end
        if h < C.MinH then h = C.DefH end
        consoleFrame.Size = UDim2.fromOffset(w, h)
        local targetPos
        if currentPreset == "Draggable" and savedFramePos then
            -- Restore the exact pre-close position instead of reading the
            -- (now off-screen) AbsolutePosition that the slide-out left behind.
            targetPos = savedFramePos
        else
            local tl = calcTopLeft(currentPreset, v, w, h, C.Margin)
            targetPos = UDim2.fromOffset(tl.X, tl.Y)
        end
        local tx = targetPos.X.Offset
        local ty = targetPos.Y.Offset
        local isTop = (currentPreset == "TopLeft"
                    or currentPreset == "TopRight"
                    or currentPreset == "Center")
        local startY
        if isTop then
            startY = ty - h - C.SlideOff
        else
            startY = ty + h + C.SlideOff
        end
        consoleFrame.Position = UDim2.fromOffset(tx, startY)
        consoleFrame.Visible  = true
        syncShadow()
        local tw = TweenService:Create(consoleFrame, TweenInfo.new(
            C.TweenT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out
        ), { Position = UDim2.fromOffset(tx, ty) })
        tw.Completed:Connect(function()
            isAnimating = false
            isOpen = true
            refresh()
            startTypewriter()
        end)
        tw:Play()
    end

    local function closeConsole()
        if isAnimating then
            return
        end
        isAnimating = true
        if settingsOverlay then
            settingsOverlay.Visible = false
        end
        -- Save current position and size BEFORE the slide-out tween moves the
        -- frame off-screen — openConsole reads these back on the next show.
        savedFramePos  = consoleFrame.Position
        savedFrameSize = consoleFrame.Size
        local pos = consoleFrame.Position
        local h   = consoleFrame.AbsoluteSize.Y
        local isTop = (currentPreset == "TopLeft"
                    or currentPreset == "TopRight"
                    or currentPreset == "Center")
        local endY
        if isTop then
            endY = pos.Y.Offset - h - C.SlideOff
        else
            endY = pos.Y.Offset + h + C.SlideOff
        end
        local tw = TweenService:Create(consoleFrame, TweenInfo.new(
            C.TweenT, Enum.EasingStyle.Quad, Enum.EasingDirection.In
        ), { Position = UDim2.new(pos.X.Scale, pos.X.Offset, 0, endY) })
        tw.Completed:Connect(function()
            consoleFrame.Visible = false
            syncShadow()
            isAnimating = false
            isOpen = false
        end)
        tw:Play()
    end

    local function toggleConsole()
        if isAnimating then
            return
        end
        if isOpen then
            closeConsole()
        else
            openConsole()
        end
    end

    -- ================================================================
    -- BUILD GUI
    -- ================================================================

    gui = new("ScreenGui", {
        Name = "SpyTerminal",
        DisplayOrder = 9999,
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
    })
    gui.Parent = PlayerGui

    -- Drop shadow — 3 layers for soft blur effect
    local shadowConfigs = {
        { off = 3, alpha = 0.70 },
        { off = 5, alpha = C.ShadowAlpha },
        { off = 8, alpha = 0.80 },
    }
    shadowFrame = new("Frame", {
        Name = "Shadow",
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(C.DefW, C.DefH),
        Position = UDim2.fromOffset(C.Margin, 500),
        Visible = false,
        ZIndex = 0,
    })
    shadowFrame.Parent = gui
    for _, sc in ipairs(shadowConfigs) do
        local layer = new("Frame", {
            Name = "ShadowLayer",
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = sc.alpha,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromOffset(sc.off, sc.off),
        })
        layer.Parent = shadowFrame
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4 + sc.off)
        corner.Parent = layer
    end

    consoleFrame = new("Frame", {
        Name = "Console",
        BackgroundColor3 = C.Bg,
        BorderSizePixel = 0,
        Visible = false,
        Position = UDim2.fromOffset(C.Margin, 500),
        Size = UDim2.fromOffset(C.DefW, C.DefH),
        ClipsDescendants = true,
        ZIndex = 1,
    })
    consoleFrame.Parent = gui
    new("UICorner", {
        CornerRadius = UDim.new(0, 4),
    }).Parent = consoleFrame
    new("UIStroke", {
        Color = C.Border,
        Thickness = 1,
    }).Parent = consoleFrame

    -- Auto-track shadow
    consoleFrame:GetPropertyChangedSignal("Position"):Connect(syncShadow)
    consoleFrame:GetPropertyChangedSignal("Size"):Connect(syncShadow)
    consoleFrame:GetPropertyChangedSignal("Visible"):Connect(syncShadow)

    -- ================================================================
    -- TOP BAR
    --
    -- LayoutOrder:
    --   0  = Title label
    --   5  = Divider
    --   10 = Clear      11 = Copy
    --   15 = Divider
    --   20 = All        21 = Warn       22 = Err    23 = Ts
    --   25 = Divider
    --   30 = Scroll
    --   35 = Divider
    --   40 = Count
    --   50 = SearchBox  (flex-fill via UIFlexItem)
    --   55 = Divider
    --   60 = Settings button
    -- ================================================================
    local topBar = new("Frame", {
        Name = "TopBar",
        BackgroundColor3 = C.TopBar,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, C.TopBarH),
    })
    topBar.Parent = consoleFrame

    -- Top bar bottom border (child of consoleFrame, NOT topBar)
    new("Frame", {
        BackgroundColor3 = C.Border,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.fromOffset(0, C.TopBarH),
    }).Parent = consoleFrame

    -- Layout: horizontal row, vertically centered
    new("UIListLayout", {
        FillDirection       = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment   = Enum.VerticalAlignment.Center,
        Padding            = UDim.new(0, 3),
        SortOrder          = Enum.SortOrder.LayoutOrder,
    }).Parent = topBar

    new("UIPadding", {
        PaddingLeft   = UDim.new(0, 6),
        PaddingRight  = UDim.new(0, 6),
        PaddingTop    = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
    }).Parent = topBar

    -- Button factory
    local function mkBtn(name, text, order, w)
        local b = new("TextButton", {
            Name = name,
            Text = text,
            Font = C.BtnFont,
            TextSize = C.BarSz,
            TextColor3 = C.BtnTxt,
            BackgroundColor3 = C.BtnIdle,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            LayoutOrder = order,
            Size = UDim2.fromOffset(w or 60, 20),
        })
        b.Parent = topBar
        return b
    end

    local function addHover(btn, restore, tip)
        btn.MouseEnter:Connect(function()
            btn.BackgroundColor3 = C.BtnHover
            if tip and showTooltip then showTooltip(tip) end
        end)
        btn.MouseLeave:Connect(function()
            restore()
            if hideTooltip then hideTooltip() end
        end)
        btn.MouseButton1Down:Connect(function()
            btn.BackgroundColor3 = C.BtnActive
        end)
        btn.MouseButton1Up:Connect(function()
            restore()
        end)
    end

    -- ================================================================
    -- TITLE
    -- ================================================================
    titleLabel = new("TextLabel", {
        Name = "Title",
        Text = "",
        Font = C.Font,
        TextSize = C.TitleSz,
        TextColor3 = C.TitleCol,
        BackgroundTransparency = 1,
        LayoutOrder = 0,
        Size = UDim2.fromOffset(100, 20),
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    titleLabel.Parent = topBar

    -- Clear (10)
    btnClear = mkBtn("Clear", "Clear", 10, 34)
    btnClear.MouseButton1Click:Connect(function()
        clearLogs()
        -- Brief green flash as confirmation feedback
        btnClear.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
        task.delay(0.35, function()
            if btnClear then
                btnClear.BackgroundColor3 = C.BtnIdle
            end
        end)
    end)
    addHover(btnClear, function()
        btnClear.BackgroundColor3 = C.BtnIdle
    end, "Clear logs")

    -- Copy All (11)
    btnCopy = mkBtn("Copy", "Copy", 11, 34)
    btnCopy.MouseButton1Click:Connect(function()
        if setclipboard then
            pcall(setclipboard, buildText())
        end
    end)
    addHover(btnCopy, function()
        btnCopy.BackgroundColor3 = C.BtnIdle
    end, "Copy logs to clipboard")

    -- Filter buttons (20-22)
    btnAll   = mkBtn("All",   "All",   20, 26)
    btnWarn  = mkBtn("Warn",  "Warn",  21, 36)
    btnError = mkBtn("Error", "Err",   22, 28)

    btnAll.MouseButton1Click:Connect(function()
        activeFilter = "All"
        updateFilters()
        refresh()
    end)
    btnWarn.MouseButton1Click:Connect(function()
        activeFilter = "Warning"
        updateFilters()
        refresh()
    end)
    btnError.MouseButton1Click:Connect(function()
        activeFilter = "Error"
        updateFilters()
        refresh()
    end)
    addHover(btnAll,   updateFilters, "Show all logs")
    addHover(btnWarn,  updateFilters, "Filter warnings")
    addHover(btnError, updateFilters, "Filter errors")
    updateFilters()

    -- Auto-Scroll (30)
    btnAutoScroll = mkBtn("Scroll", "Scroll:ON", 30, 60)
    btnAutoScroll.MouseButton1Click:Connect(function()
        autoScroll = not autoScroll
        updateAutoScroll()
        if autoScroll then
            logBox.CursorPosition = #logBox.Text + 1
        end
    end)
    addHover(btnAutoScroll, updateAutoScroll, "Toggle auto-scroll")
    updateAutoScroll()

    -- Log counter (40)
    countLabel = new("TextLabel", {
        Name = "Count",
        Text = "0/0",
        Font = C.Font,
        TextSize = C.BarSz,
        TextColor3 = C.Stamp,
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 40,
        Size = UDim2.fromOffset(0, 20),
    })
    countLabel.Parent = topBar

    -- Search TextBox (8) — flex-fills remaining space
    searchBox = new("TextBox", {
        Name = "SearchBox",
        PlaceholderText = "Search...",
        PlaceholderColor3 = C.Placeholder,
        Text = "",
        Font = C.Font,
        TextSize = C.BarSz,
        TextColor3 = C.Text,
        BackgroundColor3 = C.SearchBg,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 50,
        Size = UDim2.fromScale(1, 1),
    })
    searchBox.Parent = topBar
    new("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Fill,
    }).Parent = searchBox

    local sBusy = false
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        searchQuery = searchBox.Text
        if not sBusy then
            sBusy = true
            task.defer(function()
                refresh()
                sBusy = false
            end)
        end
    end)

    -- Settings button (9)
    btnSettings = new("TextButton", {
        Name = "SettingsBtn",
        Text = "Settings",
        Font = C.BtnFont,
        TextSize = C.BarSz,
        TextColor3 = C.BtnTxt,
        BackgroundColor3 = C.BtnIdle,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        LayoutOrder = 60,
        Size = UDim2.fromOffset(50, 20),
    })
    btnSettings.Parent = topBar
    btnSettings.MouseButton1Click:Connect(function()
        if settingsOverlay then
            settingsOverlay.Visible = not settingsOverlay.Visible
            if settingsOverlay.Visible and positionSettingsPanel then
                positionSettingsPanel()
            end
        end
    end)
    addHover(btnSettings, function()
        btnSettings.BackgroundColor3 = C.BtnIdle
    end, "Open settings")

    -- ================================================================
    -- TOPBAR GROUPS: dividers and timestamp toggle
    -- ================================================================
    local function mkDivider(order)
        local d = new("Frame", {
            BackgroundColor3 = C.Border,
            BorderSizePixel  = 0,
            Size             = UDim2.fromOffset(1, 16),
            LayoutOrder      = order,
        })
        d.Parent = topBar
        return d
    end

    mkDivider(5)   -- title | actions
    mkDivider(15)  -- actions | filters
    mkDivider(25)  -- filters | scroll
    mkDivider(35)  -- scroll | count
    mkDivider(55)  -- search | settings

    local function updateTimestamp()
        if showTimestamp then
            btnTimestamp.BackgroundColor3 = C.BtnAccent
            btnTimestamp.TextColor3 = Color3.new(1, 1, 1)
        else
            btnTimestamp.BackgroundColor3 = C.BtnIdle
            btnTimestamp.TextColor3 = C.BtnTxt
        end
    end

    btnTimestamp = mkBtn("Ts", "Ts", 23, 24)
    btnTimestamp.MouseButton1Click:Connect(function()
        showTimestamp = not showTimestamp
        updateTimestamp()
        refresh()
    end)
    addHover(btnTimestamp, updateTimestamp, "Toggle timestamps")
    updateTimestamp()

    -- ================================================================
    -- LOG DISPLAY
    -- ================================================================
    local logArea = new("Frame", {
        Name = "LogArea",
        BackgroundColor3 = C.Bg,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, C.TopBarH + 1),
        Size = UDim2.new(1, 0, 1, -(C.TopBarH + C.EvalH + 3)),
    })
    logArea.Parent = consoleFrame
    new("UIPadding", {
        PaddingLeft   = UDim.new(0, 6),
        PaddingRight  = UDim.new(0, 6),
        PaddingTop    = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 2),
    }).Parent = logArea

    logBox = new("TextBox", {
        Name               = "LogBox",
        Text               = "",
        PlaceholderText    = "",
        Font               = C.Font,
        TextSize           = C.LogSz,
        TextColor3         = C.LogMsg,
        BackgroundColor3   = C.Bg,
        BackgroundTransparency = 0,
        BorderSizePixel    = 0,
        TextEditable       = false,
        ClearTextOnFocus   = false,
        MultiLine          = true,
        TextXAlignment     = Enum.TextXAlignment.Left,
        TextYAlignment     = Enum.TextYAlignment.Top,
        RichText           = false,
        Size               = UDim2.fromScale(1, 1),
    })
    logBox.Parent = logArea

    -- Clicking inside the log box means the user is manually reading —
    -- disable autoScroll so the view stays put.
    logBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
        if logBox:IsFocused() then
            autoScroll = false
            updateAutoScroll()
        end
    end)

    -- ================================================================
    -- EVAL BAR (at bottom of console)
    -- ================================================================
    local evalBar = new("Frame", {
        Name = "EvalBar",
        BackgroundColor3 = C.EvalBg,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, C.EvalH),
        Position = UDim2.fromScale(0, 1),
        AnchorPoint = Vector2.new(0, 1),
    })
    evalBar.Parent = consoleFrame

    -- EvalBar top border — child of consoleFrame (NOT evalBar) to avoid
    -- being included in evalBar's UIListLayout and breaking the layout.
    new("Frame", {
        BackgroundColor3 = C.Border,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -C.EvalH),
    }).Parent = consoleFrame

    new("UIPadding", {
        PaddingLeft   = UDim.new(0, 8),
        PaddingRight  = UDim.new(0, 8),
        PaddingTop    = UDim.new(0, 3),
        PaddingBottom = UDim.new(0, 3),
    }).Parent = evalBar

    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }).Parent = evalBar

    evalPrompt = new("TextLabel", {
        Text = ">",
        Font = C.Font,
        TextSize = C.LogSz,
        TextColor3 = C.TitleCol,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(12, 16),
    })
    evalPrompt.Parent = evalBar

    evalBox = new("TextBox", {
        Name = "EvalInput",
        PlaceholderText = "Lua... (Enter to run, ↑↓ history)",
        PlaceholderColor3 = C.Placeholder,
        Text = "",
        Font = C.Font,
        TextSize = C.LogSz,
        TextColor3 = C.Text,
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.fromOffset(0, 0),  -- UIFlexItem controls actual size
    })
    evalBox.Parent = evalBar
    new("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Fill,
    }).Parent = evalBox

    evalHistLabel = new("TextLabel", {
        Name = "HistIdx",
        Text = "",
        Font = C.Font,
        TextSize = C.LogSz - 1,
        TextColor3 = C.Stamp,
        BackgroundTransparency = 1,
        Visible = false,
        Size = UDim2.fromOffset(38, 16),
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    evalHistLabel.Parent = evalBar

    evalBox.FocusLost:Connect(function(enterPressed)
        if not enterPressed then
            -- User blurred without submitting: hide history indicator and
            -- reset the navigation index so the next session starts fresh.
            evalHistIdx = 0
            if evalHistLabel then evalHistLabel.Visible = false end
            return
        end
        local code = evalBox.Text
        if code == "" then
            return
        end
        evalBox.Text = ""
        evalHistIdx = 0  -- reset navigation on new submission
        if evalHistLabel then evalHistLabel.Visible = false end
        -- Add to history (skip duplicates at top)
        if evalHistory[1] ~= code then
            table.insert(evalHistory, 1, code)
            if #evalHistory > 50 then
                table.remove(evalHistory)
            end
        end
        addLog("> " .. code, Enum.MessageType.MessageOutput)
        local fn, compErr = loadstring(code)
        if not fn then
            addLog("Compile error: " .. tostring(compErr), Enum.MessageType.MessageError)
        else
            local ok, res = pcall(fn)
            if not ok then
                addLog("Runtime error: " .. tostring(res), Enum.MessageType.MessageError)
            elseif res ~= nil then
                addLog(tostring(res), Enum.MessageType.MessageOutput)
            end
        end
    end)

    -- Eval history navigation: Up = older, Down = newer
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if not evalBox:IsFocused() then return end
        if input.KeyCode == Enum.KeyCode.Up then
            if #evalHistory == 0 then return end
            evalHistIdx = math.min(evalHistIdx + 1, #evalHistory)
            evalBox.Text = evalHistory[evalHistIdx]
            if evalHistLabel then
                evalHistLabel.Text = evalHistIdx .. "/" .. #evalHistory
                evalHistLabel.Visible = true
            end
            -- Move cursor to end
            task.defer(function()
                evalBox.CursorPosition = #evalBox.Text + 1
            end)
        elseif input.KeyCode == Enum.KeyCode.Down then
            if evalHistIdx <= 0 then return end
            evalHistIdx = evalHistIdx - 1
            if evalHistIdx == 0 then
                evalBox.Text = ""
                if evalHistLabel then evalHistLabel.Visible = false end
            else
                evalBox.Text = evalHistory[evalHistIdx]
                if evalHistLabel then
                    evalHistLabel.Text = evalHistIdx .. "/" .. #evalHistory
                end
                task.defer(function()
                    evalBox.CursorPosition = #evalBox.Text + 1
                end)
            end
        end
    end)

    -- ================================================================
    -- RESIZE HANDLE (subtle, bottom-right corner)
    -- ================================================================
    resizeHandle = new("ImageButton", {
        Name = "Resize",
        BackgroundColor3 = Color3.fromRGB(32, 32, 38),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.fromScale(1, 1),
        AnchorPoint = Vector2.new(1, 1),
        ZIndex = 15,
    })
    resizeHandle.Parent = consoleFrame
    new("UIStroke", {
        Color = C.Border,
        Thickness = 1,
        ZIndex = 15,
    }).Parent = resizeHandle

    -- Grip lines: 3 diagonal lines of increasing length
    for i = 0, 2 do
        new("Frame", {
            BackgroundColor3 = Color3.fromRGB(110, 110, 122),
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(4 + i * 2, 1),
            Position = UDim2.fromOffset(4 + i * 3, 8 + i * 3),
            Rotation = 45,
            ZIndex = 16,
        }).Parent = resizeHandle
    end

    resizeHandle.MouseEnter:Connect(function()
        resizeHandle.BackgroundTransparency = 0.0
        if showTooltip then showTooltip("Resize") end
    end)
    resizeHandle.MouseLeave:Connect(function()
        if dragMode ~= "resize" then
            resizeHandle.BackgroundTransparency = 0.2
        end
        if hideTooltip then hideTooltip() end
    end)

    -- ================================================================
    -- TOOLTIP — floating hint label at ScreenGui level
    -- ================================================================
    local tooltipFrame = new("Frame", {
        Name = "Tooltip",
        BackgroundColor3 = Color3.fromRGB(36, 36, 42),
        BorderSizePixel = 0,
        Visible = false,
        AutomaticSize = Enum.AutomaticSize.XY,
        ZIndex = 300,
    })
    tooltipFrame.Parent = gui
    new("UIStroke", { Color = C.Border, Thickness = 1, ZIndex = 300 }).Parent = tooltipFrame
    new("UIPadding", {
        PaddingLeft   = UDim.new(0, 6),
        PaddingRight  = UDim.new(0, 6),
        PaddingTop    = UDim.new(0, 3),
        PaddingBottom = UDim.new(0, 3),
    }).Parent = tooltipFrame
    local tooltipText = new("TextLabel", {
        Text = "",
        Font = C.BtnFont,
        TextSize = 10,
        TextColor3 = C.Text,
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        ZIndex = 301,
    })
    tooltipText.Parent = tooltipFrame

    showTooltip = function(tip)
        tooltipText.Text = tip
        local mouse = UserInputService:GetMouseLocation()
        local vpV   = viewport()
        local tx    = math.min(mouse.X + 14, vpV.X - 130)
        local ty    = math.min(mouse.Y + 20, vpV.Y - 24)
        tooltipFrame.Position = UDim2.fromOffset(tx, ty)
        tooltipFrame.Visible  = true
    end

    hideTooltip = function()
        tooltipFrame.Visible = false
    end

    -- ================================================================
    -- SETTINGS — overlay at ScreenGui level, never clipped
    -- Includes: Position Presets, Console Font Scale, Menu Font Scale
    -- ================================================================
    local function buildSettings()
        if settingsOverlay then
            settingsOverlay:Destroy()
        end

        settingsOverlay = new("Frame", {
            Name = "SettingsOverlay",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 100,
        })
        settingsOverlay.Parent = gui

        -- Click empty space to close
        settingsOverlay.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                settingsOverlay.Visible = false
            end
        end)

        local panelZ = 101
        local panel = new("Frame", {
            Name = "Panel",
            BackgroundColor3 = C.SettingsBg,
            BorderSizePixel = 0,
            ZIndex = panelZ,
            Size = UDim2.fromOffset(200, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
        })
        panel.Parent = settingsOverlay
        new("UIStroke", {
            Color = C.Border,
            Thickness = 1,
            ZIndex = panelZ,
        }).Parent = panel
        new("UIPadding", {
            PaddingLeft   = UDim.new(0, 8),
            PaddingRight  = UDim.new(0, 8),
            PaddingTop    = UDim.new(0, 8),
            PaddingBottom = UDim.new(0, 8),
        }).Parent = panel

        -- Vertical layout for panel sections
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            SortOrder   = Enum.SortOrder.LayoutOrder,
            Padding     = UDim.new(0, 8),
        }).Parent = panel

        local barSz = math.round(C.BarSz * menuFontScale)

        -- ── Panel Title ──
        new("TextLabel", {
            Text = "Console Settings",
            Font = C.BtnFont,
            TextSize = barSz,
            TextColor3 = C.TitleCol,
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(184, 16),
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = -2,
            ZIndex = panelZ + 1,
        }).Parent = panel
        new("Frame", {
            BackgroundColor3 = C.Border,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 1),
            LayoutOrder = -1,
            ZIndex = panelZ + 1,
        }).Parent = panel

        -- ── Section 1: Position Presets ──
        new("TextLabel", {
            Text = "Position Preset",
            Font = C.BtnFont,
            TextSize = barSz,
            TextColor3 = C.Placeholder,
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(184, 16),
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 1,
            ZIndex = panelZ + 1,
        }).Parent = panel

        local grid = new("Frame", {
            Name = "Grid",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(184, 52),
            LayoutOrder = 2,
            ZIndex = panelZ + 1,
        })
        grid.Parent = panel

        new("UIGridLayout", {
            CellSize    = UDim2.fromOffset(58, 22),
            CellPadding = UDim2.fromOffset(4, 4),
            SortOrder   = Enum.SortOrder.LayoutOrder,
        }).Parent = grid

        local presets = {
            { id = "TopLeft",     label = "TL",     order = 1 },
            { id = "TopRight",    label = "TR",     order = 2 },
            { id = "BottomLeft",  label = "BL",     order = 3 },
            { id = "BottomRight", label = "BR",     order = 4 },
            { id = "Center",      label = "Center", order = 5 },
            { id = "Draggable",   label = "Drag",   order = 6 },
        }

        for _, p in ipairs(presets) do
            local b = new("TextButton", {
                Name = p.id,
                Text = p.label,
                Font = C.BtnFont,
                TextSize = barSz,
                TextColor3 = C.BtnTxt,
                BackgroundColor3 = C.BtnIdle,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                LayoutOrder = p.order,
                ZIndex = panelZ + 2,
            })
            b.Parent = grid

            if p.id == currentPreset then
                b.BackgroundColor3 = C.BtnSel
                b.TextColor3 = Color3.new(1, 1, 1)
            end

            b.MouseButton1Click:Connect(function()
                currentPreset = p.id
                settingsOverlay.Visible = false
                snapToPreset(true)
                buildSettings()
            end)
            b.MouseEnter:Connect(function()
                if p.id ~= currentPreset then
                    b.BackgroundColor3 = C.BtnHover
                end
            end)
            b.MouseLeave:Connect(function()
                if p.id ~= currentPreset then
                    b.BackgroundColor3 = C.BtnIdle
                end
            end)
        end

        -- ── Separator ──
        new("Frame", {
            BackgroundColor3 = C.Border,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 1),
            LayoutOrder = 3,
            ZIndex = panelZ + 1,
        }).Parent = panel

        -- ── Section 2: Console Font Scale ──
        local function makeScaleRow(labelText, order, currentVal, onChange, getVal)
            local row = new("Frame", {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 22),
                LayoutOrder = order,
                ZIndex = panelZ + 1,
            })
            row.Parent = panel

            new("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Left,
                VerticalAlignment   = Enum.VerticalAlignment.Center,
                Padding            = UDim.new(0, 4),
            }).Parent = row

            new("TextLabel", {
                Text = labelText,
                Font = C.BtnFont,
                TextSize = barSz,
                TextColor3 = C.Placeholder,
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(82, 20),
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = panelZ + 2,
            }).Parent = row

            local btnMinus = new("TextButton", {
                Text = "-",
                Font = C.BtnFont,
                TextSize = barSz + 1,
                TextColor3 = C.BtnTxt,
                BackgroundColor3 = C.BtnIdle,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Size = UDim2.fromOffset(22, 20),
                ZIndex = panelZ + 2,
            })
            btnMinus.Parent = row

            local valLabel = new("TextLabel", {
                Text = fmtScale(currentVal),
                Font = C.Font,
                TextSize = barSz,
                TextColor3 = C.Text,
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(34, 20),
                ZIndex = panelZ + 2,
            })
            valLabel.Parent = row

            local btnPlus = new("TextButton", {
                Text = "+",
                Font = C.BtnFont,
                TextSize = barSz + 1,
                TextColor3 = C.BtnTxt,
                BackgroundColor3 = C.BtnIdle,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Size = UDim2.fromOffset(22, 20),
                ZIndex = panelZ + 2,
            })
            btnPlus.Parent = row

            local function hoverRestore()
                btnMinus.BackgroundColor3 = C.BtnIdle
                btnPlus.BackgroundColor3 = C.BtnIdle
            end
            addHover(btnMinus, hoverRestore)
            addHover(btnPlus, hoverRestore)

            btnMinus.MouseButton1Click:Connect(function()
                local cur = getVal()
                local newVal = clamp(cur - 0.1, 0.5, 1.5)
                newVal = math.floor(newVal * 10 + 0.5) / 10
                onChange(newVal)
                valLabel.Text = fmtScale(newVal)
            end)

            btnPlus.MouseButton1Click:Connect(function()
                local cur = getVal()
                local newVal = clamp(cur + 0.1, 0.5, 1.5)
                newVal = math.floor(newVal * 10 + 0.5) / 10
                onChange(newVal)
                valLabel.Text = fmtScale(newVal)
            end)

            return valLabel
        end

        makeScaleRow("Console Font", 4, consoleFontScale, function(val)
            consoleFontScale = val
            applyFontScales()
        end, function()
            return consoleFontScale
        end)

        makeScaleRow("Menu Font", 5, menuFontScale, function(val)
            menuFontScale = val
            applyFontScales()
        end, function()
            return menuFontScale
        end)

        -- Position the panel adjacent to the Settings button.
        -- Prefer opening downward-left; flip sides when near viewport edges.
        local function positionPanel()
            if not consoleFrame or not settingsOverlay then
                return
            end
            local absPos = consoleFrame.AbsolutePosition
            local absSz  = consoleFrame.AbsoluteSize
            local vpV    = viewport()
            local pw     = 200
            local ph     = panel.AbsoluteSize.Y
            if ph < 10 then ph = 220 end  -- fallback before first render

            -- Horizontal: align to right edge of console, flip left if it would overflow
            local x = absPos.X + absSz.X - pw - 4
            if x < 4 then
                x = absPos.X + 4  -- flip: open from left edge instead
            end
            if x + pw > vpV.X - 4 then
                x = vpV.X - pw - 4
            end

            -- Vertical: open below the topbar, flip upward if not enough room below
            local y = absPos.Y + C.TopBarH + 4
            if y + ph > vpV.Y - 4 then
                y = absPos.Y - ph - 4  -- flip: open above the console
            end
            if y < 4 then
                y = 4
            end

            panel.Position = UDim2.fromOffset(x, y)
        end

        positionSettingsPanel = positionPanel
    end

    buildSettings()

    -- Reposition settings panel periodically while visible
    task.defer(function()
        while true do
            task.wait(0.15)
            if settingsOverlay and settingsOverlay.Visible then
                if positionSettingsPanel then
                    positionSettingsPanel()
                end
            end
        end
    end)

    -- ================================================================
    -- DRAG + RESIZE INPUT
    -- ================================================================
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        if currentPreset ~= "Draggable" or dragMode then
            return
        end
        dragMode = "drag"
        dragMouse0 = UserInputService:GetMouseLocation()
        dragPos0 = consoleFrame.Position
    end)

    resizeHandle.MouseButton1Down:Connect(function()
        if dragMode then
            return
        end
        dragMode = "resize"
        resizeMouse0 = UserInputService:GetMouseLocation()
        resizeSize0 = consoleFrame.Size
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        if not dragMode then
            return
        end
        local cur = UserInputService:GetMouseLocation()
        if dragMode == "drag" then
            local dx = cur.X - dragMouse0.X
            local dy = cur.Y - dragMouse0.Y
            local vpV = viewport()
            local fw  = consoleFrame.AbsoluteSize.X
            local fh  = consoleFrame.AbsoluteSize.Y
            local nx  = clamp(dragPos0.X.Offset + dx, 0, vpV.X - fw)
            local ny  = clamp(dragPos0.Y.Offset + dy, 0, vpV.Y - fh)
            consoleFrame.Position = UDim2.fromOffset(nx, ny)
        elseif dragMode == "resize" then
            local dx = cur.X - resizeMouse0.X
            local dy = cur.Y - resizeMouse0.Y
            consoleFrame.Size = UDim2.fromOffset(
                clamp(resizeSize0.X.Offset + dx, C.MinW, 1600),
                clamp(resizeSize0.Y.Offset + dy, C.MinH, 900)
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragMode then
            dragMode = nil
            resizeHandle.BackgroundTransparency = 0.2
            if currentPreset ~= "Draggable" then
                snapToPreset(false)
            end
        end
    end)

    -- VIEWPORT RESIZE
    task.defer(function()
        local cam = workspace.CurrentCamera
        if cam then
            cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if isOpen and currentPreset ~= "Draggable" then
                    snapToPreset(false)
                end
            end)
        end
    end)

    -- DELETE / ESC KEY TOGGLE
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then
            return
        end
        if input.KeyCode == Enum.KeyCode.Delete then
            toggleConsole()
        elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
            -- Only close on ESC if the eval box is not focused
            -- (so the user can ESC out of the textbox focus first)
            if not evalBox:IsFocused() and not searchBox:IsFocused() then
                closeConsole()
            end
        end
    end)

    -- LOG SERVICE HOOK
    LogService.MessageOut:Connect(function(msg, msgType)
        addLog(msg, msgType)
    end)

end

-- Run with error protection
local ok, err = pcall(Main)
if not ok then
    warn("[SPYTERMINAL] ERROR: " .. tostring(err))
end
