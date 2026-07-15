--[[
    SPYTERMINAL v11 — Professional Developer Console
    Toggle : DELETE          Close : ESC
    Clear  : Ctrl+L          Search: Ctrl+F

    Features
      • Live log capture (LogService) with dedup + frame-coalesced debounce
      • Clean ASCII log prefixes: [INFO] [WARN] [ERR!] [OUT] >>  (plain text
        so selection + Ctrl+C copy works perfectly — Roblox RichText
        breaks text selection/copy, so the log box stays plain)
      • Filters: All / Info / Warn / Err  +  live case-insensitive search
      • Text selection that survives new logs — view freezes when you
        scroll up or click into the log; a "↓ N new" indicator appears
        and one click resumes following.
      • Lua eval bar with history (Up/Dn), loadstring-based, guarded
      • Pause logging, timestamp toggle, follow (auto-scroll) toggle
      • Drag + resize, 6 position presets, dual font-scale (console/menu)
      • Polished slide animation, soft shadow, tooltips, keyboard shortcuts
      • Recent log-history pull on startup so the console isn't empty
      • Double-execution guard: blocks re-execution if already loaded in
        the current session (rejoin required to re-execute)
--]]

-- luacheck: globals game Color3 Enum Instance UDim2 UDim Vector2 utf8
-- luacheck: globals TweenInfo task workspace setclipboard warn pcall
-- luacheck: globals ipairs pairs next table string math os loadstring type
-- luacheck: globals tonumber tostring

-- ====================================================================
-- DOUBLE EXECUTION GUARD
-- ====================================================================
if _G.SPYTERMINAL_LOADED then
    warn("[SPYTERMINAL] Execution blocked — duplicated execution detected.")
    warn("[SPYTERMINAL] Script is already loaded. Rejoin to re-execute the script.")
    return
end
_G.SPYTERMINAL_LOADED = true

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LogService       = game:GetService("LogService")
local TweenService     = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ====================================================================
-- CONFIG
-- ====================================================================
local C = {
    -- Surfaces
    Bg         = Color3.fromRGB(20, 20, 24),
    TopBar     = Color3.fromRGB(28, 28, 32),
    Border     = Color3.fromRGB(50, 50, 55),
    SearchBg   = Color3.fromRGB(32, 32, 36),
    EvalBg     = Color3.fromRGB(16, 16, 20),
    SettingsBg = Color3.fromRGB(34, 34, 40),

    -- Buttons
    BtnIdle   = Color3.fromRGB(45, 45, 50),
    BtnHover  = Color3.fromRGB(60, 60, 66),
    BtnActive = Color3.fromRGB(78, 78, 85),
    BtnTxt    = Color3.fromRGB(180, 180, 185),
    BtnAccent = Color3.fromRGB(70, 130, 230),
    BtnSel    = Color3.fromRGB(50, 110, 210),
    BtnGood   = Color3.fromRGB(40, 160, 80),
    BtnWarn   = Color3.fromRGB(200, 140, 30),

    -- Text
    Placeholder = Color3.fromRGB(100, 100, 110),
    Text        = Color3.fromRGB(195, 195, 200),
    Stamp       = Color3.fromRGB(90, 90, 100),
    TitleCol    = Color3.fromRGB(0, 220, 130),
    LogMsg      = Color3.fromRGB(185, 185, 190),

    -- RichText hex colors (used by the title status dot only — the log
    -- box is plain text so selection/copy stays clean)
    RT = {
        Warn   = "#ebb92d",
        Err    = "#eb3737",
        EvalIn = "#00dc82",
        Dim    = "#5a5a64",
    },

    -- Layout
    DefW = 680, DefH = 380, MinW = 320, MinH = 200,
    TopBarH = 32, EvalH = 28, Margin = 12,
    TweenT = 0.22, SlideOff = 60,
    MaxLogs = 800, MaxChars = 180000,

    -- Fonts
    Font    = Enum.Font.Code,
    BtnFont = Enum.Font.GothamBold,
    LogSz   = 13, BarSz = 11, TitleSz = 13,
}

-- ====================================================================
-- HELPERS
-- ====================================================================
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

-- Character (code-point) count — needed because Luau's # returns byte
-- length, but TextBox.CursorPosition indexes characters.  Falls back to
-- byte length if the string isn't valid UTF-8.
local function charCount(s)
    if not s or s == "" then return 0 end
    local n = utf8.len(s)
    return n or #s
end

local function fmtScale(val)
    return string.format("x%.1f", val)
end

-- ====================================================================
-- MAIN
-- ====================================================================
local function Main()

    -- ----------------------------------------------------------------
    -- STATE
    -- ----------------------------------------------------------------
    local isOpen            = false
    local isAnimating       = false
    local dragMode          = nil   -- "drag" | "resize" | nil
    local autoScroll        = true  -- follow new logs
    local paused            = false -- drop incoming external logs
    local activeFilter      = "All" -- All | Info | Warning | Error
    local searchQuery       = ""
    local currentPreset     = "BottomLeft"
    local consoleFontScale  = 1.0
    local menuFontScale     = 1.0
    local showTimestamp     = true
    local logs              = {}    -- array of entries
    local totalCount        = 0
    local logChars          = 0
    local dedupLast         = nil
    local unseenCount       = 0     -- logs buffered while autoScroll off
    local visibleCount      = 0
    local lastTextLen       = 0     -- char length of current logBox.Text
    local evalHistory       = {}
    local evalHistIdx       = 0
    local savedFramePos     = nil
    local savedFrameSize    = nil
    local flushScheduled    = false
    local pendingCount      = 0     -- logs stored since the last flush
    local suppressCursorSig = false -- guard: programmatic cursor change

    local dragMouse0, dragPos0
    local resizeMouse0, resizeSize0

    -- ----------------------------------------------------------------
    -- UI REFERENCES (forward-declared, assigned during GUI build)
    -- ----------------------------------------------------------------
    local gui, consoleFrame, shadowFrame
    local logBox, searchBox, evalBox, evalPrompt, evalHistLabel
    local btnClear, btnCopy, btnPause, btnAutoScroll, btnSettings, btnTimestamp
    local btnAll, btnInfo, btnWarn, btnError
    local countLabel, titleLabel
    local resizeHandle, scrollBtn
    local settingsOverlay, settingsPanel
    local presetButtons = {}
    local showTooltip, hideTooltip
    local dotFrames = {}

    -- ----------------------------------------------------------------
    -- UTILITY
    -- ----------------------------------------------------------------
    local function viewport()
        local cam = workspace.CurrentCamera
        if cam then return cam.ViewportSize end
        return Vector2.new(1920, 1080)
    end

    local function stamp()
        return os.date("%H:%M:%S")
            .. "." .. string.format("%03d", math.floor((os.clock() % 1) * 1000))
    end

    local function tagText(e)
        if e.kind == "evalin" then return ">>" end
        local mt = e.msgType
        if mt == Enum.MessageType.MessageWarning then return "WARN" end
        if mt == Enum.MessageType.MessageError   then return "ERR!" end
        if mt == Enum.MessageType.MessageOutput  then return "OUT"  end
        return "INFO"
    end

    -- ----------------------------------------------------------------
    -- LOG FORMATTING  (plain text — keeps selection/copy clean)
    -- ----------------------------------------------------------------
    local function formatLinePlain(e)
        local dc = e.dedupCount or 1
        local suffix = dc > 1 and (" [x" .. dc .. "]") or ""
        if showTimestamp then
            return string.format("[%s] [%s] %s%s", e.stamp, tagText(e), e.text, suffix)
        end
        return string.format("[%s] %s%s", tagText(e), e.text, suffix)
    end

    local function matchesFilter(e)
        local f = activeFilter
        if f == "Info"    and e.msgType ~= Enum.MessageType.MessageInfo    then return false end
        if f == "Warning" and e.msgType ~= Enum.MessageType.MessageWarning then return false end
        if f == "Error"   and e.msgType ~= Enum.MessageType.MessageError   then return false end
        if searchQuery ~= "" then
            if not e.text:lower():find(searchQuery:lower(), 1, true) then return false end
        end
        return true
    end

    -- ----------------------------------------------------------------
    -- RENDER
    -- ----------------------------------------------------------------
    local function rebuildText()
        if not logBox then return end
        local parts = {}
        local vc = 0
        for _, e in ipairs(logs) do
            if matchesFilter(e) then
                vc = vc + 1
                parts[vc] = formatLinePlain(e)
            end
        end
        local text = table.concat(parts, "\n")
        visibleCount = vc
        lastTextLen = charCount(text)

        suppressCursorSig = true
        logBox.Text = text
        suppressCursorSig = false

        if countLabel then
            countLabel.Text = string.format("%d/%d", vc, totalCount)
        end

        if autoScroll and vc > 0 then
            local targetLen = lastTextLen
            task.defer(function()
                if logBox and logBox.Parent and autoScroll and not suppressCursorSig then
                    suppressCursorSig = true
                    logBox.CursorPosition = targetLen + 1
                    suppressCursorSig = false
                end
            end)
        end
    end

    -- updateScrollBtn is defined later (UI UPDATERS) but referenced from
    -- the deferred closure below — forward-declare so the closure binds
    -- to the local, not a global.
    local updateScrollBtn

    local function scheduleFlush()
        if flushScheduled then return end
        flushScheduled = true
        task.defer(function()
            flushScheduled = false
            local n = pendingCount
            pendingCount = 0
            if autoScroll then
                rebuildText()
            elseif n > 0 then
                -- autoScroll turned off after the log arrived — count
                -- those pending logs as unseen so the indicator is right.
                unseenCount = unseenCount + n
                updateScrollBtn()
            end
        end)
    end

    -- ----------------------------------------------------------------
    -- LOG STORAGE
    -- ----------------------------------------------------------------
    -- Core store — used by both live logs and history pull.
    -- Returns (entry, isDedup).
    local function storeLog(msg, msgType, stampVal, kind)
        kind = kind or "log"
        totalCount = totalCount + 1

        if dedupLast
           and dedupLast.text == msg
           and dedupLast.msgType == msgType
           and dedupLast.kind == kind then
            dedupLast.dedupCount = (dedupLast.dedupCount or 1) + 1
            return dedupLast, true
        end

        local entry = {
            stamp       = stampVal or stamp(),
            msgType     = msgType,
            text        = msg,
            dedupCount  = 1,
            kind        = kind,
        }
        dedupLast = entry
        table.insert(logs, entry)
        logChars = logChars + charCount(msg) + 32

        while #logs > C.MaxLogs or logChars > C.MaxChars do
            local removed = table.remove(logs, 1)
            logChars = logChars - (charCount(removed.text) + 32)
            if dedupLast == removed then dedupLast = nil end
        end
        return entry, false
    end

    local function addLog(msg, msgType, kind)
        kind = kind or "log"
        -- Pause only drops external (LogService) logs; eval always shows.
        if paused and kind == "log" then return end

        storeLog(msg, msgType, nil, kind)

        if not isOpen then return end

        -- Always schedule; the deferred flush checks autoScroll and either
        -- rebuilds the view or rolls the count into the unseen indicator.
        -- This avoids a race where autoScroll flips between store and flush.
        pendingCount = pendingCount + 1
        scheduleFlush()
    end

    local function clearLogs()
        logs = {}
        totalCount = 0
        logChars = 0
        dedupLast = nil
        unseenCount = 0
        visibleCount = 0
        lastTextLen = 0
        pendingCount = 0
        if logBox then
            suppressCursorSig = true
            logBox.Text = ""
            suppressCursorSig = false
        end
        if countLabel then
            countLabel.Text = "0/0"
        end
        if scrollBtn then scrollBtn.Visible = false end
    end

    -- ----------------------------------------------------------------
    -- UI UPDATERS
    -- ----------------------------------------------------------------
    local function updateFilters()
        local map = { All = btnAll, Info = btnInfo, Warning = btnWarn, Error = btnError }
        for name, btn in pairs(map) do
            if btn then
                if name == activeFilter then
                    btn.BackgroundColor3 = C.BtnAccent
                    btn.TextColor3 = Color3.new(1, 1, 1)
                else
                    btn.BackgroundColor3 = C.BtnIdle
                    btn.TextColor3 = C.BtnTxt
                end
            end
        end
    end

    local function updateAutoScroll()
        if not btnAutoScroll then return end
        if autoScroll then
            btnAutoScroll.BackgroundColor3 = C.BtnAccent
            btnAutoScroll.TextColor3 = Color3.new(1, 1, 1)
            btnAutoScroll.Text = "Follow:ON"
        else
            btnAutoScroll.BackgroundColor3 = C.BtnIdle
            btnAutoScroll.TextColor3 = C.BtnTxt
            btnAutoScroll.Text = "Follow:OFF"
        end
    end

    updateScrollBtn = function()
        if not scrollBtn then return end
        if autoScroll then
            scrollBtn.Visible = false
        else
            scrollBtn.Text = (unseenCount > 0)
                and ("\u{2193} " .. unseenCount .. " new")
                or  "\u{2193} Scroll to end"
            scrollBtn.Visible = true
        end
    end

    local function updatePause()
        if not btnPause then return end
        if paused then
            btnPause.BackgroundColor3 = C.BtnWarn
            btnPause.TextColor3 = Color3.new(1, 1, 1)
            btnPause.Text = "Paused"
        else
            btnPause.BackgroundColor3 = C.BtnIdle
            btnPause.TextColor3 = C.BtnTxt
            btnPause.Text = "Live"
        end
    end

    local function updateTimestamp()
        if not btnTimestamp then return end
        if showTimestamp then
            btnTimestamp.BackgroundColor3 = C.BtnAccent
            btnTimestamp.TextColor3 = Color3.new(1, 1, 1)
        else
            btnTimestamp.BackgroundColor3 = C.BtnIdle
            btnTimestamp.TextColor3 = C.BtnTxt
        end
    end

    local function updateTitle()
        if not titleLabel then return end
        local dot
        if paused then
            dot = C.RT.Err
        elseif not autoScroll then
            dot = C.RT.Warn
        else
            dot = C.RT.EvalIn
        end
        titleLabel.Text = '<font color="' .. dot .. '">\u{25CF}</font> SPYTERMINAL '
            .. '<font color="' .. C.RT.Dim .. '">v11</font>'
    end

    local function updatePresetButtons()
        for id, btn in pairs(presetButtons) do
            if id == currentPreset then
                btn.BackgroundColor3 = C.BtnSel
                btn.TextColor3 = Color3.new(1, 1, 1)
            else
                btn.BackgroundColor3 = C.BtnIdle
                btn.TextColor3 = C.BtnTxt
            end
        end
    end

    -- ----------------------------------------------------------------
    -- FONT SCALE
    -- ----------------------------------------------------------------
    local function applyFontScales()
        local logSz   = math.round(C.LogSz * consoleFontScale)
        local barSz   = math.round(C.BarSz * menuFontScale)
        local titleSz = math.round(C.TitleSz * menuFontScale)
        if logBox      then logBox.TextSize      = logSz end
        if evalBox     then evalBox.TextSize     = logSz end
        if evalPrompt  then evalPrompt.TextSize  = logSz end
        if titleLabel  then titleLabel.TextSize = titleSz end
        if countLabel  then countLabel.TextSize = barSz end
        if searchBox   then searchBox.TextSize  = barSz end
        local btns = { btnClear, btnCopy, btnPause, btnAutoScroll, btnSettings,
                       btnTimestamp, btnAll, btnInfo, btnWarn, btnError }
        for _, b in ipairs(btns) do
            if b then b.TextSize = barSz end
        end
        if scrollBtn then scrollBtn.TextSize = barSz end
        for _, b in pairs(presetButtons) do
            if b then b.TextSize = barSz end
        end
    end

    -- ----------------------------------------------------------------
    -- POSITION
    -- ----------------------------------------------------------------
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
        if not consoleFrame or not shadowFrame then return end
        shadowFrame.Position = consoleFrame.Position
        shadowFrame.Size     = consoleFrame.Size
        shadowFrame.Visible  = consoleFrame.Visible
    end

    local function snapToPreset(animate)
        local v = viewport()
        local w = consoleFrame.AbsoluteSize.X
        local h = consoleFrame.AbsoluteSize.Y
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

    -- ----------------------------------------------------------------
    -- ANIMATION
    -- ----------------------------------------------------------------
    local function openConsole()
        if isAnimating then return end
        isAnimating = true
        local v = viewport()
        local w = savedFrameSize and savedFrameSize.X.Offset or C.DefW
        local h = savedFrameSize and savedFrameSize.Y.Offset or C.DefH
        if w < C.MinW then w = C.DefW end
        if h < C.MinH then h = C.DefH end
        consoleFrame.Size = UDim2.fromOffset(w, h)

        local targetPos
        if currentPreset == "Draggable" and savedFramePos then
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
        local startY = isTop and (ty - h - C.SlideOff) or (ty + h + C.SlideOff)

        consoleFrame.Position = UDim2.fromOffset(tx, startY)
        consoleFrame.Visible  = true
        syncShadow()

        local tw = TweenService:Create(consoleFrame, TweenInfo.new(
            C.TweenT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out
        ), { Position = UDim2.fromOffset(tx, ty) })
        tw.Completed:Connect(function()
            isAnimating = false
            isOpen = true
            rebuildText()
        end)
        tw:Play()
    end

    local function closeConsole()
        if isAnimating then return end
        isAnimating = true
        if settingsOverlay then settingsOverlay.Visible = false end
        savedFramePos  = consoleFrame.Position
        savedFrameSize = consoleFrame.Size
        local pos = consoleFrame.Position
        local h   = consoleFrame.AbsoluteSize.Y
        local isTop = (currentPreset == "TopLeft"
                    or currentPreset == "TopRight"
                    or currentPreset == "Center")
        local endY = isTop and (pos.Y.Offset - h - C.SlideOff)
                           or (pos.Y.Offset + h + C.SlideOff)
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
        if isAnimating then return end
        if isOpen then closeConsole() else openConsole() end
    end

    local function enableAutoScroll()
        autoScroll = true
        unseenCount = 0
        updateAutoScroll()
        updateScrollBtn()
        updateTitle()
        rebuildText()
    end

    -- ====================================================================
    -- BUILD GUI
    -- ====================================================================
    gui = new("ScreenGui", {
        Name = "SpyTerminal",
        DisplayOrder = 9999,
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
    })
    gui.Parent = PlayerGui

    -- ----------------------------------------------------------------
    -- SHADOW (3 soft layers, cascading)
    -- ----------------------------------------------------------------
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
    local shadowLayers = {
        { off = 2, alpha = 0.50 },
        { off = 5, alpha = 0.68 },
        { off = 9, alpha = 0.82 },
    }
    for _, sc in ipairs(shadowLayers) do
        local layer = new("Frame", {
            Name = "ShadowLayer",
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = sc.alpha,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromOffset(sc.off, sc.off),
        })
        layer.Parent = shadowFrame
        new("UICorner", { CornerRadius = UDim.new(0, 4 + sc.off) }).Parent = layer
    end

    -- ----------------------------------------------------------------
    -- CONSOLE FRAME
    -- ----------------------------------------------------------------
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
    new("UICorner", { CornerRadius = UDim.new(0, 4) }).Parent = consoleFrame
    new("UIStroke", { Color = C.Border, Thickness = 1 }).Parent = consoleFrame

    -- Thin accent line at the very top (IDE titlebar feel)
    new("Frame", {
        BackgroundColor3 = C.TitleCol,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        ZIndex = 2,
    }).Parent = consoleFrame

    consoleFrame:GetPropertyChangedSignal("Position"):Connect(syncShadow)
    consoleFrame:GetPropertyChangedSignal("Size"):Connect(syncShadow)
    consoleFrame:GetPropertyChangedSignal("Visible"):Connect(syncShadow)

    -- ====================================================================
    -- TOP BAR
    -- ====================================================================
    local topBar = new("Frame", {
        Name = "TopBar",
        BackgroundColor3 = C.TopBar,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, C.TopBarH),
        ZIndex = 2,
    })
    topBar.Parent = consoleFrame

    new("Frame", {
        BackgroundColor3 = C.Border,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.fromOffset(0, C.TopBarH),
        ZIndex = 2,
    }).Parent = consoleFrame

    new("UIListLayout", {
        FillDirection       = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment   = Enum.VerticalAlignment.Center,
        Padding             = UDim.new(0, 3),
        SortOrder           = Enum.SortOrder.LayoutOrder,
    }).Parent = topBar

    new("UIPadding", {
        PaddingLeft   = UDim.new(0, 6),
        PaddingRight  = UDim.new(0, 6),
        PaddingTop    = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
    }).Parent = topBar

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
            Size = UDim2.fromOffset(w or 60, 22),
            ZIndex = 2,
        })
        b.Parent = topBar
        return b
    end

    local function mkDivider(order)
        local d = new("Frame", {
            BackgroundColor3 = C.Border,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(1, 18),
            LayoutOrder = order,
            ZIndex = 2,
        })
        d.Parent = topBar
        return d
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

    -- Title (0) — status dot + name + version
    titleLabel = new("TextLabel", {
        Name = "Title",
        Text = "",
        RichText = true,
        Font = C.Font,
        TextSize = C.TitleSz,
        TextColor3 = C.Text,
        BackgroundTransparency = 1,
        LayoutOrder = 0,
        Size = UDim2.fromOffset(150, 22),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 2,
    })
    titleLabel.Parent = topBar
    updateTitle()

    mkDivider(5)

    -- Clear (10)
    btnClear = mkBtn("Clear", "Clear", 10, 38)
    btnClear.MouseButton1Click:Connect(function()
        clearLogs()
        btnClear.BackgroundColor3 = C.BtnGood
        task.delay(0.35, function()
            if btnClear then btnClear.BackgroundColor3 = C.BtnIdle end
        end)
    end)
    addHover(btnClear, function() btnClear.BackgroundColor3 = C.BtnIdle end,
        "Clear logs  (Ctrl+L)")

    -- Copy (11)
    btnCopy = mkBtn("Copy", "Copy", 11, 38)
    btnCopy.MouseButton1Click:Connect(function()
        if setclipboard then
            pcall(setclipboard, logBox.Text)
        end
        btnCopy.BackgroundColor3 = C.BtnGood
        task.delay(0.35, function()
            if btnCopy then btnCopy.BackgroundColor3 = C.BtnIdle end
        end)
    end)
    addHover(btnCopy, function() btnCopy.BackgroundColor3 = C.BtnIdle end,
        "Copy all visible logs to clipboard")

    -- Pause (12)
    btnPause = mkBtn("Pause", "Live", 12, 40)
    btnPause.MouseButton1Click:Connect(function()
        paused = not paused
        updatePause()
        updateTitle()
    end)
    addHover(btnPause, updatePause, "Pause / resume log capture")

    mkDivider(15)

    -- Filters (20-23)
    btnAll   = mkBtn("All",   "All",   20, 28)
    btnInfo  = mkBtn("Info",  "Info",  21, 32)
    btnWarn  = mkBtn("Warn",  "Warn",  22, 38)
    btnError = mkBtn("Error", "Err",   23, 30)

    btnAll.MouseButton1Click:Connect(function()
        activeFilter = "All"; updateFilters(); rebuildText()
    end)
    btnInfo.MouseButton1Click:Connect(function()
        activeFilter = "Info"; updateFilters(); rebuildText()
    end)
    btnWarn.MouseButton1Click:Connect(function()
        activeFilter = "Warning"; updateFilters(); rebuildText()
    end)
    btnError.MouseButton1Click:Connect(function()
        activeFilter = "Error"; updateFilters(); rebuildText()
    end)
    addHover(btnAll,   updateFilters, "Show all logs")
    addHover(btnInfo,  updateFilters, "Show info only")
    addHover(btnWarn,  updateFilters, "Show warnings only")
    addHover(btnError, updateFilters, "Show errors only")
    updateFilters()

    mkDivider(25)

    -- Timestamp toggle (30)
    btnTimestamp = mkBtn("Ts", "Ts", 30, 26)
    btnTimestamp.MouseButton1Click:Connect(function()
        showTimestamp = not showTimestamp
        updateTimestamp()
        rebuildText()
    end)
    addHover(btnTimestamp, updateTimestamp, "Toggle timestamps")
    updateTimestamp()

    mkDivider(35)

    -- Follow / auto-scroll (40)
    btnAutoScroll = mkBtn("Follow", "Follow:ON", 40, 66)
    btnAutoScroll.MouseButton1Click:Connect(function()
        if not autoScroll then
            enableAutoScroll()
        else
            autoScroll = false
            updateAutoScroll()
            updateScrollBtn()
            updateTitle()
        end
    end)
    addHover(btnAutoScroll, updateAutoScroll,
        "Toggle follow mode — freeze the view to select text")
    updateAutoScroll()

    mkDivider(45)

    -- Count (50)
    countLabel = new("TextLabel", {
        Name = "Count",
        Text = "0/0",
        Font = C.Font,
        TextSize = C.BarSz,
        TextColor3 = C.Stamp,
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 50,
        Size = UDim2.fromOffset(0, 22),
        ZIndex = 2,
    })
    countLabel.Parent = topBar

    -- Search (60) — flex-fills remaining space
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
        LayoutOrder = 60,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 2,
    })
    searchBox.Parent = topBar
    new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }).Parent = searchBox
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 5),
        PaddingRight = UDim.new(0, 5),
    }).Parent = searchBox

    local sBusy = false
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        searchQuery = searchBox.Text
        if not sBusy then
            sBusy = true
            task.defer(function()
                sBusy = false
                rebuildText()
            end)
        end
    end)

    mkDivider(65)

    -- Settings (70)
    btnSettings = new("TextButton", {
        Name = "SettingsBtn",
        Text = "Settings",
        Font = C.BtnFont,
        TextSize = C.BarSz,
        TextColor3 = C.BtnTxt,
        BackgroundColor3 = C.BtnIdle,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        LayoutOrder = 70,
        Size = UDim2.fromOffset(52, 22),
        ZIndex = 2,
    })
    btnSettings.Parent = topBar
    btnSettings.MouseButton1Click:Connect(function()
        if settingsOverlay then
            settingsOverlay.Visible = not settingsOverlay.Visible
        end
    end)
    addHover(btnSettings, function() btnSettings.BackgroundColor3 = C.BtnIdle end,
        "Open settings")

    -- ====================================================================
    -- LOG AREA
    -- ====================================================================
    local logArea = new("Frame", {
        Name = "LogArea",
        BackgroundColor3 = C.Bg,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, C.TopBarH + 1),
        Size = UDim2.new(1, 0, 1, -(C.TopBarH + C.EvalH + 3)),
        ZIndex = 1,
    })
    logArea.Parent = consoleFrame
    new("UIPadding", {
        PaddingLeft   = UDim.new(0, 6),
        PaddingRight  = UDim.new(0, 6),
        PaddingTop    = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
    }).Parent = logArea

    logBox = new("TextBox", {
        Name = "LogBox",
        Text = "",
        PlaceholderText = "Waiting for output...",
        PlaceholderColor3 = C.Placeholder,
        Font = C.Font,
        TextSize = C.LogSz,
        TextColor3 = C.LogMsg,
        BackgroundColor3 = C.Bg,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        TextEditable = false,   -- selection + copy allowed, typing blocked
        ClearTextOnFocus = false,
        MultiLine = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        RichText = false,  -- plain text: selection + Ctrl+C copy stay clean
        Size = UDim2.fromScale(1, 1),
        ZIndex = 1,
    })
    logBox.Parent = logArea

    -- The KEY selection-preservation hook: when the user moves the cursor
    -- inside the log (click / select), freeze auto-scroll so new logs no
    -- longer overwrite their selection.  A "↓ N new" pill lets them
    -- resume following with one click.
    logBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
        if suppressCursorSig then return end
        if not logBox:IsFocused() then return end
        if autoScroll then
            autoScroll = false
            updateAutoScroll()
            updateScrollBtn()
            updateTitle()
        end
    end)

    -- Floating "scroll to end / N new" pill (bottom-right of log area)
    scrollBtn = new("TextButton", {
        Name = "ScrollBtn",
        Text = "\u{2193} Scroll to end",
        Font = C.BtnFont,
        TextSize = C.BarSz,
        TextColor3 = Color3.new(1, 1, 1),
        BackgroundColor3 = C.BtnAccent,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Visible = false,
        Size = UDim2.fromOffset(130, 22),
        Position = UDim2.new(1, -4, 1, -4),
        AnchorPoint = Vector2.new(1, 1),
        ZIndex = 10,
    })
    scrollBtn.Parent = logArea
    new("UICorner", { CornerRadius = UDim.new(0, 3) }).Parent = scrollBtn
    scrollBtn.MouseButton1Click:Connect(enableAutoScroll)
    scrollBtn.MouseEnter:Connect(function()
        scrollBtn.BackgroundColor3 = C.BtnSel
    end)
    scrollBtn.MouseLeave:Connect(function()
        scrollBtn.BackgroundColor3 = C.BtnAccent
    end)

    -- ====================================================================
    -- EVAL BAR
    -- ====================================================================
    local evalBar = new("Frame", {
        Name = "EvalBar",
        BackgroundColor3 = C.EvalBg,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, C.EvalH),
        Position = UDim2.fromScale(0, 1),
        AnchorPoint = Vector2.new(0, 1),
        ZIndex = 2,
    })
    evalBar.Parent = consoleFrame

    new("Frame", {
        BackgroundColor3 = C.Border,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -C.EvalH),
        ZIndex = 2,
    }).Parent = consoleFrame

    new("UIPadding", {
        PaddingLeft   = UDim.new(0, 8),
        PaddingRight  = UDim.new(0, 8),
        PaddingTop    = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
    }).Parent = evalBar

    new("UIListLayout", {
        FillDirection       = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment   = Enum.VerticalAlignment.Center,
        Padding             = UDim.new(0, 6),
    }).Parent = evalBar

    evalPrompt = new("TextLabel", {
        Text = ">",
        Font = C.Font,
        TextSize = C.LogSz,
        TextColor3 = C.TitleCol,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(12, 20),
        ZIndex = 2,
    })
    evalPrompt.Parent = evalBar

    evalBox = new("TextBox", {
        Name = "EvalInput",
        PlaceholderText = "Lua...  (Enter=run, Up/Dn=history, Ctrl+L=clear)",
        PlaceholderColor3 = C.Placeholder,
        Text = "",
        Font = C.Font,
        TextSize = C.LogSz,
        TextColor3 = C.Text,
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.fromOffset(0, 20),
        ZIndex = 2,
    })
    evalBox.Parent = evalBar
    new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }).Parent = evalBox

    evalHistLabel = new("TextLabel", {
        Name = "HistIdx",
        Text = "",
        Font = C.Font,
        TextSize = C.LogSz - 1,
        TextColor3 = C.Stamp,
        BackgroundTransparency = 1,
        Visible = false,
        Size = UDim2.fromOffset(40, 20),
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 2,
    })
    evalHistLabel.Parent = evalBar

    evalBox.FocusLost:Connect(function(enterPressed)
        if not enterPressed then
            evalHistIdx = 0
            if evalHistLabel then evalHistLabel.Visible = false end
            return
        end
        local code = evalBox.Text
        if code == "" then return end
        evalBox.Text = ""
        evalHistIdx = 0
        if evalHistLabel then evalHistLabel.Visible = false end
        if evalHistory[1] ~= code then
            table.insert(evalHistory, 1, code)
            if #evalHistory > 50 then table.remove(evalHistory) end
        end
        addLog("> " .. code, Enum.MessageType.MessageOutput, "evalin")

        -- loadstring is server-gated in live games; guard against nil.
        if type(loadstring) ~= "function" then
            addLog("Eval unavailable: loadstring is disabled on this client",
                Enum.MessageType.MessageError)
            return
        end
        local pok, fn, compErr = pcall(loadstring, code)
        if not pok then
            addLog("Eval error: " .. tostring(fn), Enum.MessageType.MessageError)
            return
        end
        if not fn then
            addLog("Compile error: " .. tostring(compErr), Enum.MessageType.MessageError)
        else
            local rok, res = pcall(fn)
            if not rok then
                addLog("Runtime error: " .. tostring(res), Enum.MessageType.MessageError)
            elseif res ~= nil then
                addLog(tostring(res), Enum.MessageType.MessageOutput, "evalout")
            end
        end
    end)

    -- ====================================================================
    -- RESIZE HANDLE (corner grip dots)
    -- ====================================================================
    resizeHandle = new("ImageButton", {
        Name = "Resize",
        BackgroundColor3 = Color3.fromRGB(32, 32, 38),
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromScale(1, 1),
        AnchorPoint = Vector2.new(1, 1),
        ZIndex = 15,
    })
    resizeHandle.Parent = consoleFrame
    new("UIStroke", { Color = C.Border, Thickness = 1, ZIndex = 15 }).Parent = resizeHandle

    -- Triangle of dots pointing toward the bottom-right corner
    local dotPos = {
        {4, 4},
        {4, 8}, {8, 8},
        {4, 12}, {8, 12}, {12, 12},
    }
    for _, p in ipairs(dotPos) do
        local d = new("Frame", {
            BackgroundColor3 = Color3.fromRGB(120, 120, 132),
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(2, 2),
            Position = UDim2.fromOffset(p[1], p[2]),
            ZIndex = 16,
        })
        d.Parent = resizeHandle
        dotFrames[#dotFrames + 1] = d
    end

    resizeHandle.MouseEnter:Connect(function()
        resizeHandle.BackgroundTransparency = 0.0
        for _, d in ipairs(dotFrames) do
            d.BackgroundColor3 = Color3.fromRGB(170, 170, 182)
        end
        if showTooltip then showTooltip("Drag to resize") end
    end)
    resizeHandle.MouseLeave:Connect(function()
        if dragMode ~= "resize" then
            resizeHandle.BackgroundTransparency = 0.25
            for _, d in ipairs(dotFrames) do
                d.BackgroundColor3 = Color3.fromRGB(120, 120, 132)
            end
        end
        if hideTooltip then hideTooltip() end
    end)

    -- ====================================================================
    -- TOOLTIP
    -- ====================================================================
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
    new("UICorner", { CornerRadius = UDim.new(0, 3) }).Parent = tooltipFrame
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
        local tx    = math.min(mouse.X + 14, vpV.X - 150)
        local ty    = math.min(mouse.Y + 20, vpV.Y - 24)
        tooltipFrame.Position = UDim2.fromOffset(tx, ty)
        tooltipFrame.Visible  = true
    end

    hideTooltip = function()
        tooltipFrame.Visible = false
    end

    -- ====================================================================
    -- SETTINGS PANEL
    -- ====================================================================
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
    settingsPanel = new("Frame", {
        Name = "Panel",
        BackgroundColor3 = C.SettingsBg,
        BorderSizePixel = 0,
        ZIndex = panelZ,
        Size = UDim2.fromOffset(214, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    settingsPanel.Parent = settingsOverlay
    new("UIStroke", { Color = C.Border, Thickness = 1, ZIndex = panelZ }).Parent = settingsPanel
    new("UICorner", { CornerRadius = UDim.new(0, 4) }).Parent = settingsPanel
    new("UIPadding", {
        PaddingLeft   = UDim.new(0, 8),
        PaddingRight  = UDim.new(0, 8),
        PaddingTop    = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
    }).Parent = settingsPanel

    new("UIListLayout", {
        FillDirection       = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder           = Enum.SortOrder.LayoutOrder,
        Padding             = UDim.new(0, 6),
    }).Parent = settingsPanel

    local barSz = math.round(C.BarSz * menuFontScale)

    new("TextLabel", {
        Text = "Console Settings",
        Font = C.BtnFont,
        TextSize = barSz,
        TextColor3 = C.TitleCol,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = -2,
        ZIndex = panelZ + 1,
    }).Parent = settingsPanel
    new("Frame", {
        BackgroundColor3 = C.Border,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        LayoutOrder = -1,
        ZIndex = panelZ + 1,
    }).Parent = settingsPanel

    -- Section: Position
    new("TextLabel", {
        Text = "Position",
        Font = C.BtnFont,
        TextSize = barSz,
        TextColor3 = C.Placeholder,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        ZIndex = panelZ + 1,
    }).Parent = settingsPanel

    local grid = new("Frame", {
        Name = "Grid",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 52),
        LayoutOrder = 2,
        ZIndex = panelZ + 1,
    })
    grid.Parent = settingsPanel
    new("UIGridLayout", {
        CellSize    = UDim2.fromOffset(64, 22),
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
        presetButtons[p.id] = b
        b.MouseButton1Click:Connect(function()
            currentPreset = p.id
            updatePresetButtons()       -- just recolor, no rebuild
            settingsOverlay.Visible = false
            snapToPreset(true)
        end)
        b.MouseEnter:Connect(function()
            if p.id ~= currentPreset then b.BackgroundColor3 = C.BtnHover end
        end)
        b.MouseLeave:Connect(function()
            if p.id ~= currentPreset then b.BackgroundColor3 = C.BtnIdle end
        end)
    end
    updatePresetButtons()

    -- Separator
    new("Frame", {
        BackgroundColor3 = C.Border,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        LayoutOrder = 3,
        ZIndex = panelZ + 1,
    }).Parent = settingsPanel

    -- Section: Font Size
    new("TextLabel", {
        Text = "Font Size",
        Font = C.BtnFont,
        TextSize = barSz,
        TextColor3 = C.Placeholder,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 4,
        ZIndex = panelZ + 1,
    }).Parent = settingsPanel

    local function makeScaleRow(labelText, order, getVal, onChange)
        local row = new("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 22),
            LayoutOrder = order,
            ZIndex = panelZ + 1,
        })
        row.Parent = settingsPanel

        new("UIListLayout", {
            FillDirection       = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            VerticalAlignment   = Enum.VerticalAlignment.Center,
            Padding             = UDim.new(0, 4),
        }).Parent = row

        new("TextLabel", {
            Text = labelText,
            Font = C.BtnFont,
            TextSize = barSz,
            TextColor3 = C.Placeholder,
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(78, 20),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = panelZ + 2,
        }).Parent = row

        local btnMinus = new("TextButton", {
            Text = "-", Font = C.BtnFont, TextSize = barSz + 2,
            TextColor3 = C.BtnTxt, BackgroundColor3 = C.BtnIdle,
            BorderSizePixel = 0, AutoButtonColor = false,
            Size = UDim2.fromOffset(22, 20), ZIndex = panelZ + 2,
        })
        btnMinus.Parent = row

        local valLabel = new("TextLabel", {
            Text = fmtScale(getVal()),
            Font = C.Font, TextSize = barSz,
            TextColor3 = C.Text, BackgroundTransparency = 1,
            Size = UDim2.fromOffset(36, 20), ZIndex = panelZ + 2,
        })
        valLabel.Parent = row

        local btnPlus = new("TextButton", {
            Text = "+", Font = C.BtnFont, TextSize = barSz + 2,
            TextColor3 = C.BtnTxt, BackgroundColor3 = C.BtnIdle,
            BorderSizePixel = 0, AutoButtonColor = false,
            Size = UDim2.fromOffset(22, 20), ZIndex = panelZ + 2,
        })
        btnPlus.Parent = row

        addHover(btnMinus, function() btnMinus.BackgroundColor3 = C.BtnIdle end)
        addHover(btnPlus,  function() btnPlus.BackgroundColor3  = C.BtnIdle end)

        local function adjust(delta)
            local v = clamp(getVal() + delta, 0.5, 1.5)
            v = math.floor(v * 10 + 0.5) / 10
            onChange(v)
            valLabel.Text = fmtScale(v)
        end
        btnMinus.MouseButton1Click:Connect(function() adjust(-0.1) end)
        btnPlus.MouseButton1Click:Connect(function() adjust(0.1) end)
    end

    makeScaleRow("Console", 5,
        function() return consoleFontScale end,
        function(v) consoleFontScale = v; applyFontScales() end)
    makeScaleRow("Menu", 6,
        function() return menuFontScale end,
        function(v) menuFontScale = v; applyFontScales() end)

    -- Position the panel near the Settings button (event-driven, no polling)
    local function positionPanel()
        if not consoleFrame or not settingsOverlay or not settingsPanel then return end
        if not settingsOverlay.Visible then return end
        local absPos = consoleFrame.AbsolutePosition
        local absSz  = consoleFrame.AbsoluteSize
        local vpV    = viewport()
        local pw = 214
        local ph = settingsPanel.AbsoluteSize.Y
        if ph < 10 then ph = 240 end

        local x = absPos.X + absSz.X - pw - 4
        if x < 4 then x = absPos.X + 4 end
        if x + pw > vpV.X - 4 then x = vpV.X - pw - 4 end

        local y = absPos.Y + C.TopBarH + 4
        if y + ph > vpV.Y - 4 then y = absPos.Y - ph - 4 end
        if y < 4 then y = 4 end

        settingsPanel.Position = UDim2.fromOffset(x, y)
    end

    -- Reposition on open, on console move/resize, and after the panel
    -- finishes auto-sizing its content.
    settingsOverlay:GetPropertyChangedSignal("Visible"):Connect(function()
        if settingsOverlay.Visible then
            positionPanel()
            task.defer(function()
                if settingsOverlay.Visible then positionPanel() end
            end)
        end
    end)
    settingsPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if settingsOverlay and settingsOverlay.Visible then positionPanel() end
    end)
    consoleFrame:GetPropertyChangedSignal("Position"):Connect(function()
        if settingsOverlay and settingsOverlay.Visible then positionPanel() end
    end)
    consoleFrame:GetPropertyChangedSignal("Size"):Connect(function()
        if settingsOverlay and settingsOverlay.Visible then positionPanel() end
    end)

    -- ====================================================================
    -- INPUT HANDLING (consolidated into one InputBegan)
    -- ====================================================================
    -- Drag from the top bar (Draggable preset only)
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if currentPreset ~= "Draggable" or dragMode then return end
        dragMode = "drag"
        dragMouse0 = UserInputService:GetMouseLocation()
        dragPos0   = consoleFrame.Position
    end)

    resizeHandle.MouseButton1Down:Connect(function()
        if dragMode then return end
        dragMode = "resize"
        resizeMouse0 = UserInputService:GetMouseLocation()
        resizeSize0  = consoleFrame.Size
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if not dragMode then return end
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
                clamp(resizeSize0.X.Offset + dx, C.MinW, 2000),
                clamp(resizeSize0.Y.Offset + dy, C.MinH, 1200)
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragMode then
            dragMode = nil
            resizeHandle.BackgroundTransparency = 0.25
            for _, d in ipairs(dotFrames) do
                d.BackgroundColor3 = Color3.fromRGB(120, 120, 132)
            end
            if currentPreset ~= "Draggable" then
                snapToPreset(false)
            end
        end
    end)

    -- Keyboard: toggle, close, shortcuts, eval history — all in one handler
    UserInputService.InputBegan:Connect(function(input, gpe)
        local key = input.KeyCode

        -- Eval history navigation (only while the eval bar is focused)
        if evalBox:IsFocused() then
            if key == Enum.KeyCode.Up then
                if #evalHistory == 0 then return end
                evalHistIdx = math.min(evalHistIdx + 1, #evalHistory)
                evalBox.Text = evalHistory[evalHistIdx]
                if evalHistLabel then
                    evalHistLabel.Text = evalHistIdx .. "/" .. #evalHistory
                    evalHistLabel.Visible = true
                end
                task.defer(function()
                    if evalBox then evalBox.CursorPosition = #evalBox.Text + 1 end
                end)
                return
            elseif key == Enum.KeyCode.Down then
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
                        if evalBox then evalBox.CursorPosition = #evalBox.Text + 1 end
                    end)
                end
                return
            end
        end

        -- Ctrl+L = clear, Ctrl+F = focus search (work even while typing)
        local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                      or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        if ctrlDown then
            if key == Enum.KeyCode.L then
                clearLogs()
                return
            elseif key == Enum.KeyCode.F then
                if searchBox then searchBox:CaptureFocus() end
                return
            end
        end

        if gpe then return end

        if key == Enum.KeyCode.Delete then
            toggleConsole()
        elseif key == Enum.KeyCode.Escape and isOpen then
            -- First ESC blurs a focused text field; second ESC closes.
            if evalBox:IsFocused() then
                evalBox:ReleaseFocus(false)
            elseif searchBox:IsFocused() then
                searchBox:ReleaseFocus(false)
            else
                closeConsole()
            end
        end
    end)

    -- Viewport resize → re-snap (event-driven, no deferred wrapper)
    local cam = workspace.CurrentCamera
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if isOpen and currentPreset ~= "Draggable" then
                snapToPreset(false)
            end
            if settingsOverlay and settingsOverlay.Visible then
                positionPanel()
            end
        end)
    end

    -- ====================================================================
    -- LOG HISTORY + LIVE CAPTURE
    -- ====================================================================
    -- Pull recent history synchronously BEFORE connecting the live hook so
    -- nothing is missed between the two.  GetLogHistory timestamps are
    -- epoch seconds; we format them to match the live stamp style.
    local histOk, history = pcall(function() return LogService:GetLogHistory() end)
    if histOk and history then
        for _, h in ipairs(history) do
            storeLog(h.message, h.messageType,
                os.date("%H:%M:%S", h.timestamp) .. ".000", "log")
        end
    end

    LogService.MessageOut:Connect(function(msg, msgType)
        addLog(msg, msgType)
    end)

end

-- ====================================================================
-- BOOT
-- ====================================================================
local ok, err = pcall(Main)
if not ok then
    warn("[SPYTERMINAL] ERROR: " .. tostring(err))
end
