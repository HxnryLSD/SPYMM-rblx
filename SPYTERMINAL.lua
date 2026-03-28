--[[
    ====================================================================
    SPYTERMINAL v9 — Advanced Developer Console
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
    TweenT     = 0.28, SlideOff = 50, MaxLogs = 800,

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

    -- UI REFS
    local gui, consoleFrame, shadowFrame
    local logBox, searchBox, evalBox, evalPrompt
    local btnClear, btnCopy, btnAutoScroll, btnSettings
    local btnAll, btnWarn, btnError
    local countLabel, titleLabel
    local resizeHandle
    local settingsOverlay
    local positionSettingsPanel
    local settingsConsoleVal, settingsMenuVal

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

    local function tag(mt)
        if mt == Enum.MessageType.MessageWarning then
            return "WARN"
        end
        if mt == Enum.MessageType.MessageError then
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
                       btnAll, btnWarn, btnError }
        for _, b in ipairs(btns) do
            if b then
                b.TextSize = barSz
            end
        end
    end

    -- LOG MANAGEMENT (dependency order — Luau has no forward hoisting)
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
                table.insert(parts, string.format(
                    "[%s] [%s] %s", e.stamp, tag(e.msgType), e.text
                ))
            end
        end
        if countLabel then
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

    local function addLog(msg, msgType)
        totalCount = totalCount + 1
        table.insert(logs, { stamp = stamp(), msgType = msgType, text = msg })
        while #logs > C.MaxLogs do
            table.remove(logs, 1)
        end
        if isOpen then
            refresh()
        end
    end

    local function clearLogs()
        logs = {}
        totalCount = 0
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
    local titleText = "SPYTERMINAL"

    local function setTitle(text)
        titleLabel.Text = text
    end

    local function typewriterLoop()
        while isOpen do
            -- PHASE 1: Type characters one by one (60 ms each)
            for i = 1, #titleText do
                if not isOpen then
                    return
                end
                setTitle(titleText:sub(1, i) .. "_")
                task.wait(0.06)
            end

            -- PHASE 2: Show full title for 4 seconds
            setTitle(titleText)
            task.wait(4)
            if not isOpen then
                return
            end

            -- PHASE 3: Erase characters one by one (40 ms each)
            for i = #titleText - 1, 0, -1 do
                if not isOpen then
                    return
                end
                if i > 0 then
                    setTitle(titleText:sub(1, i) .. "_")
                else
                    setTitle("_")
                end
                task.wait(0.04)
            end

            -- Brief pause before restarting
            task.wait(0.5)
        end
    end

    local function startTypewriter()
        task.spawn(typewriterLoop)
    end

    -- ANIMATION
    local function openConsole()
        if isAnimating then
            return
        end
        isAnimating = true
        local v = viewport()
        local w = C.DefW
        local h = C.DefH
        local tl = calcTopLeft(currentPreset, v, w, h, C.Margin)
        consoleFrame.Size = UDim2.fromOffset(w, h)
        local isTop = (currentPreset == "TopLeft"
                    or currentPreset == "TopRight"
                    or currentPreset == "Center")
        local startY
        if isTop then
            startY = tl.Y - h - C.SlideOff
        else
            startY = tl.Y + h + C.SlideOff
        end
        consoleFrame.Position = UDim2.fromOffset(tl.X, startY)
        consoleFrame.Visible  = true
        syncShadow()
        local tw = TweenService:Create(consoleFrame, TweenInfo.new(
            C.TweenT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out
        ), { Position = UDim2.fromOffset(tl.X, tl.Y) })
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
    --   0 = Title label
    --   1 = Clear       2 = Copy
    --   3 = All         4 = Warn        5 = Error
    --   6 = Scroll
    --   7 = Count
    --   8 = SearchBox   (flex-fill via UIFlexItem)
    --   9 = Settings button
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

    local function addHover(btn, restore)
        btn.MouseEnter:Connect(function()
            btn.BackgroundColor3 = C.BtnHover
        end)
        btn.MouseLeave:Connect(function()
            restore()
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

    -- Clear (1)
    btnClear = mkBtn("Clear", "Clear", 1, 34)
    btnClear.MouseButton1Click:Connect(clearLogs)
    addHover(btnClear, function()
        btnClear.BackgroundColor3 = C.BtnIdle
    end)

    -- Copy All (2)
    btnCopy = mkBtn("Copy", "Copy", 2, 34)
    btnCopy.MouseButton1Click:Connect(function()
        if setclipboard then
            pcall(setclipboard, buildText())
        end
    end)
    addHover(btnCopy, function()
        btnCopy.BackgroundColor3 = C.BtnIdle
    end)

    -- Filter buttons (3-5)
    btnAll   = mkBtn("All",   "All",   3, 26)
    btnWarn  = mkBtn("Warn",  "Warn",  4, 36)
    btnError = mkBtn("Error", "Err",   5, 28)

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
    addHover(btnAll,   updateFilters)
    addHover(btnWarn,  updateFilters)
    addHover(btnError, updateFilters)
    updateFilters()

    -- Auto-Scroll (6)
    btnAutoScroll = mkBtn("Scroll", "Scroll:ON", 6, 60)
    btnAutoScroll.MouseButton1Click:Connect(function()
        autoScroll = not autoScroll
        updateAutoScroll()
        if autoScroll then
            logBox.CursorPosition = #logBox.Text + 1
        end
    end)
    addHover(btnAutoScroll, updateAutoScroll)
    updateAutoScroll()

    -- Log counter (7)
    countLabel = new("TextLabel", {
        Name = "Count",
        Text = "0/0",
        Font = C.Font,
        TextSize = C.BarSz,
        TextColor3 = C.Stamp,
        BackgroundTransparency = 1,
        LayoutOrder = 7,
        Size = UDim2.fromOffset(38, 20),
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
        LayoutOrder = 8,
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
        LayoutOrder = 9,
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
    end)

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

    new("Frame", {
        BackgroundColor3 = C.Border,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
    }).Parent = evalBar

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
        PlaceholderText = "Lua... (Enter to run)",
        PlaceholderColor3 = C.Placeholder,
        Text = "",
        Font = C.Font,
        TextSize = C.LogSz,
        TextColor3 = C.Text,
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.fromScale(1, 1),
    })
    evalBox.Parent = evalBar

    evalBox.FocusLost:Connect(function(enterPressed)
        if not enterPressed then
            return
        end
        local code = evalBox.Text
        if code == "" then
            return
        end
        evalBox.Text = ""
        addLog("> " .. code, Enum.MessageType.MessageOutput)
        local fn, err = loadstring(code)
        if not fn then
            addLog("Compile error: " .. tostring(err), Enum.MessageType.MessageError)
        else
            local ok, res = pcall(fn)
            if not ok then
                addLog("Runtime error: " .. tostring(res), Enum.MessageType.MessageError)
            elseif res ~= nil then
                addLog(tostring(res), Enum.MessageType.MessageOutput)
            end
        end
    end)

    -- ================================================================
    -- RESIZE HANDLE (subtle, bottom-right corner)
    -- ================================================================
    resizeHandle = new("ImageButton", {
        Name = "Resize",
        BackgroundColor3 = Color3.fromRGB(40, 40, 45),
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromScale(1, 1),
        AnchorPoint = Vector2.new(1, 1),
        ZIndex = 15,
    })
    resizeHandle.Parent = consoleFrame

    for i = 0, 2 do
        new("Frame", {
            BackgroundColor3 = Color3.fromRGB(80, 80, 88),
            BackgroundTransparency = 0.3,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(6, 1),
            Position = UDim2.fromOffset(5 + i * 3, 7 + i * 3),
            Rotation = 45,
        }).Parent = resizeHandle
    end

    resizeHandle.MouseEnter:Connect(function()
        resizeHandle.BackgroundTransparency = 0.2
    end)
    resizeHandle.MouseLeave:Connect(function()
        if dragMode ~= "resize" then
            resizeHandle.BackgroundTransparency = 0.6
        end
    end)

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
            Size = UDim2.fromOffset(200, 210),
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

        settingsConsoleVal = makeScaleRow("Console Font", 4, consoleFontScale, function(val)
            consoleFontScale = val
            applyFontScales()
        end, function()
            return consoleFontScale
        end)

        settingsMenuVal = makeScaleRow("Menu Font", 5, menuFontScale, function(val)
            menuFontScale = val
            applyFontScales()
        end, function()
            return menuFontScale
        end)

        -- Position the panel near the console's top-right corner
        local function positionPanel()
            if not consoleFrame or not settingsOverlay then
                return
            end
            local absPos = consoleFrame.AbsolutePosition
            local absSz  = consoleFrame.AbsoluteSize
            local pw, ph = 200, 210
            local x = absPos.X + absSz.X - pw - 4
            local y = absPos.Y + C.TopBarH + 4
            local vpV = viewport()
            if x + pw > vpV.X then
                x = vpV.X - pw - 8
            end
            if y + ph > vpV.Y then
                y = vpV.Y - ph - 8
            end
            if x < 4 then
                x = 4
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
            consoleFrame.Position = UDim2.new(
                dragPos0.X.Scale, dragPos0.X.Offset + dx,
                dragPos0.Y.Scale, dragPos0.Y.Offset + dy
            )
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
            resizeHandle.BackgroundTransparency = 0.6
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

    -- DELETE KEY TOGGLE
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then
            return
        end
        if input.KeyCode == Enum.KeyCode.Delete then
            toggleConsole()
        end
    end)

    -- LOG SERVICE HOOK
    LogService.MessageOut:Connect(function(msg, mt)
        addLog(msg, mt)
    end)

    -- WELCOME MESSAGES
    addLog("[SPYTERMINAL] Loaded. Press DELETE to toggle.", Enum.MessageType.MessageOutput)
    addLog("[Features] Clear | Copy | Filter | Search | Eval | Settings", Enum.MessageType.MessageOutput)
    addLog("[Tip] Settings > presets & font scale. Corner grip = resize.", Enum.MessageType.MessageOutput)
end

-- Run with error protection
local ok, err = pcall(Main)
if not ok then
    warn("[SPYTERMINAL] ERROR: " .. tostring(err))
end
