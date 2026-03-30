--[[
    Protectio v2.0
    A comprehensive user protection script
]]

if not game:IsLoaded() then game.Loaded:Wait() end

--===========================================
-- UI LIBRARIES
--===========================================
local Alurt = loadstring(game:HttpGet("https://raw.githubusercontent.com/azir-py/project/refs/heads/main/Zwolf/AlurtUI.lua"))()
local Seraph = loadstring(game:HttpGet("https://raw.githubusercontent.com/53845052/roblox-uis/refs/heads/main/SeraphLib.lua"))()
Seraph:SetWindowKeybind(Enum.KeyCode.RightShift)

-- Theme loading
local Themes = game:GetService("HttpService"):JSONDecode(game:HttpGet("https://raw.githubusercontent.com/53845052/roblox-uis/refs/heads/main/themes/Seraph.json"))
local ThemeList, ThemeNames = {}, {"Default"}
ThemeList.Default = Seraph:GetTheme()
for Theme, Data in Themes do
    ThemeNames[#ThemeNames + 1] = Theme
    ThemeList[Theme] = {}
    for Property, Color in Data do
        ThemeList[Theme][Property] = Color3.fromRGB(unpack(Color:split(",")))
    end
end

-- Filesystem stubs for Studio
if game:GetService("RunService"):IsStudio() then
    local files = {}
    writefile = function(path, content) files[path] = content end
    readfile = function(path) return files[path] end
    isfolder = function(path) return true end
    makefolder = function(path) end
    listfiles = function(path)
        local list = {}
        for filepath in files do
            if filepath:find(path) then list[#list + 1] = filepath end
        end
        return list
    end
end

if not isfolder("protectio") then makefolder("protectio") end

--===========================================
-- CONFIGURATION
--===========================================
local Config = {
    AntiPurchase = {
        Enabled = true,
        BlockPrompts = true,
        BlockPerformPurchase = true,
        ShowProductInfo = true,
    },
    AntiWebhook = {
        Enabled = true,
        BlockDiscord = true,
        BlockGeneric = true,
        ShowLoggedData = true,
        DeleteWebhook = false,
    },
    AntiChatManipulation = {
        Enabled = true,
        BlockForceChat = true,
        BlockMessagePost = true,
        BlockNewChat = true,
        ShowWarning = true,
    },
    AntiKick = {
        Enabled = true,
        ShowKickMessage = true,
    },
    AntiAPI = {
        Enabled = true,
        BlockRbxAnalytics = true,
        BlockHttpRbxApi = true,
        ShowEndpoint = true,
    },
    AntiDetection = {
        MemorySpoof = true,
        GUIDetection = true,
        GroupBypass = true,
        ClearTraces = false,
    },
    AntiBypass = {
        Enabled = true,
        BlockHookfunction = true,
        BlockClonefunction = true,
    },
    Misc = {
        AntiIdle = true,
        DisableErrors = true,
        DisableLogMessages = true,
        AntiReportAbuse = true,
    },
    OutputMode = "warn",
}

--===========================================
-- UTILITY FUNCTIONS
--===========================================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Stats = game:GetService("Stats")
local ContentProvider = game:GetService("ContentProvider")

local cloneref = cloneref or function(...) return ... end
local clonefunction = clonefunction or function(...) return ... end
local cGame = cloneref(game)

local strFind = clonefunction(string.find)
local strMatch = clonefunction(string.match)
local strSub = clonefunction(string.sub)
local strUpper = clonefunction(string.upper)
local strLower = clonefunction(string.lower)
local typeF = clonefunction(type)

-- Notification images and sounds
local NotifAssets = {
    Shield = "rbxassetid://17616650704",
    Warning = "rbxassetid://6031068421",
    Blocked = "rbxassetid://6023426912",
    Success = "rbxassetid://6031075671",
    Audio = "rbxassetid://17208361335",
    AudioWarning = "rbxassetid://17525305988",
}

-- Output function
local function Output(message)
    local mode = Config.OutputMode
    if mode == "print" then
        print("[Protectio] " .. message)
    elseif mode == "warn" then
        warn("[Protectio] " .. message)
    elseif mode == "rconsoleprint" then
        rconsoleprint("[Protectio] " .. message .. "\n")
    elseif mode == "rconsolewarn" then
        rconsolewarn("[Protectio] " .. message)
    end
end

-- AlurtUI Notification function
local function Notify(title, text, length, barColor, image)
    pcall(function()
        Alurt.CreateNode({
            Title = title,
            Content = text,
            Audio = NotifAssets.Audio,
            Length = length or 5,
            Image = image or NotifAssets.Shield,
            BarColor = barColor or Color3.fromRGB(75, 150, 255),
        })
    end)
end

local function NotifyWarning(title, text, length)
    Notify(title, text, length, Color3.fromRGB(255, 170, 50), NotifAssets.Warning)
end

local function NotifyBlocked(title, text, length)
    Notify(title, text, length, Color3.fromRGB(255, 75, 75), NotifAssets.Blocked)
end

local function NotifySuccess(title, text, length)
    Notify(title, text, length, Color3.fromRGB(75, 255, 120), NotifAssets.Success)
end

-- Table to string for logging
local function TableToString(tbl, indent)
    indent = indent or 0
    local result = "{\n"
    for key, value in pairs(tbl) do
        local keyStr = tostring(key)
        local valueStr = (typeof(value) == "table" and TableToString(value, indent + 1)) or tostring(value):gsub("\n", "")
        result = result .. string.rep("  ", indent + 1) .. keyStr .. " = " .. valueStr .. ",\n"
    end
    return result .. string.rep("  ", indent) .. "}"
end

--===========================================
-- MALICIOUS FUNCTION DEFINITIONS
--===========================================
local MaliciousFunctions = {
    MarketplaceService = {
        PerformPurchase = { reason = "Direct purchase execution" },
        PerformPurchaseV2 = { reason = "Direct purchase execution v2" },
        PromptGamePassPurchase = { reason = "Game pass purchase prompt" },
        PromptPurchase = { reason = "Asset purchase prompt" },
        PromptBundlePurchase = { reason = "Bundle purchase prompt" },
        PromptProductPurchase = { reason = "Product purchase prompt" },
        PromptSubscriptionPurchase = { reason = "Subscription purchase prompt" },
        PromptThirdPartyPurchase = { reason = "Third-party purchase prompt" },
        PromptRobloxPurchase = { reason = "Roblox purchase prompt" },
        PromptNativePurchase = { reason = "Native purchase prompt" },
        PromptCollectiblesPurchase = { reason = "Collectibles purchase prompt" },
        PrepareCollectiblesPurchase = { reason = "Collectibles preparation" },
    },
    BrowserService = {
        OpenBrowserWindow = { reason = "External browser opening" },
        ExecuteJavaScript = { reason = "JavaScript execution" },
        SendCommand = { reason = "Browser command" },
        OpenNativeOverlay = { reason = "Native overlay opening" },
    },
    HttpService = {
        RequestInternal = { reason = "Internal HTTP request" },
        GetSecret = { reason = "Secret retrieval" },
    },
    GuiService = {
        OpenBrowserWindow = { reason = "GUI browser opening" },
        OpenNativeOverlay = { reason = "GUI native overlay" },
    },
    RbxAnalyticsService = {
        GetClientId = { reason = "Client ID tracking" },
        GetSessionId = { reason = "Session tracking" },
        GetPlaySessionId = { reason = "Play session tracking" },
    },
    HttpRbxApiService = {
        GetAsync = { reason = "API GET request" },
        GetAsyncFullUrl = { reason = "API GET request (full URL)" },
        PostAsync = { reason = "API POST request" },
        PostAsyncFullUrl = { reason = "API POST request (full URL)" },
        RequestAsync = { reason = "API request" },
        RequestLimitedAsync = { reason = "Limited API request" },
    },
    OpenCloudService = {
        HttpRequestAsync = { reason = "Cloud HTTP request" },
        InvokeAsync = { reason = "Cloud invoke" },
    },
    CaptureService = {
        PromptSaveCapturesToGallery = { reason = "Capture save prompt" },
        PromptShareCapture = { reason = "Capture share prompt" },
    },
    LoginService = {
        PromptLogin = { reason = "Login prompt" },
        Logout = { reason = "Forced logout" },
    },
    LinkingService = {
        OpenUrl = { reason = "External URL opening" },
    },
}

--===========================================
-- HTTP REQUEST HANDLERS
--===========================================
local HttpRequestFunctions = {}

if typeof(syn) == "table" and syn.request then
    table.insert(HttpRequestFunctions, syn.request)
end

if typeof(http) == "table" and http.request then
    table.insert(HttpRequestFunctions, http.request)
end

if typeof(fluxus) == "table" and fluxus.request then
    table.insert(HttpRequestFunctions, fluxus.request)
end

if request then
    table.insert(HttpRequestFunctions, request)
end

if http_request and http_request ~= request then
    table.insert(HttpRequestFunctions, http_request)
end

if typeof(syn_backup) == "table" and syn_backup.request then
    table.insert(HttpRequestFunctions, syn_backup.request)
end

--===========================================
-- CHAT SYSTEM SETUP
--===========================================
local ChatSystem = {
    Legacy = false,
    ChatBar = nil,
    ChatScript = nil,
    SayMessageRequest = nil,
    MessagePostedEvent = nil,
}

local function InitializeChatSystem()
    pcall(function()
        local textChatService = cGame:GetService("TextChatService")
        if textChatService.ChatVersion == Enum.ChatVersion.LegacyChatService then
            ChatSystem.Legacy = true
            ChatSystem.ChatBar = LocalPlayer.PlayerGui:WaitForChild("Chat"):WaitForChild("Frame")
                :WaitForChild("ChatBarParentFrame").Frame.BoxFrame.Frame.ChatBar
            ChatSystem.ChatScript = LocalPlayer.PlayerScripts:WaitForChild("ChatScript")
            ChatSystem.SayMessageRequest = cGame:GetService("ReplicatedStorage")
                .DefaultChatSystemChatEvents.SayMessageRequest
            local chatMain = ChatSystem.ChatScript:WaitForChild("ChatMain")
            local messagePosted = require(chatMain).MessagePosted
            if messagePosted then
                for _, event in next, debug.getupvalues(messagePosted.fire) do
                    if typeof(event) == "Instance" then
                        ChatSystem.MessagePostedEvent = event
                        break
                    end
                end
            end
        end
    end)
end

InitializeChatSystem()

--===========================================
-- SERAPH GUI SETUP
--===========================================
local Window = Seraph:Window("Protectio")

local AntiPurchaseTab = Window:AddTab({"rbxassetid://10723407389"})
local AntiWebhookTab = Window:AddTab({"rbxassetid://10723407389"})
local AntiChatTab = Window:AddTab({"rbxassetid://10723407389"})
local AntiKickTab = Window:AddTab({"rbxassetid://10723407389"})
local AntiAPITab = Window:AddTab({"rbxassetid://10723407389"})
local AntiDetectionTab = Window:AddTab({"rbxassetid://10723407389"})
local AntiBypassTab = Window:AddTab({"rbxassetid://10723407389"})
local MiscTab = Window:AddTab({"rbxassetid://10723407389"})
local ConfigTab = Window:AddTab({"rbxassetid://10734941499"})

-- Anti-Purchase Tab
do
    local Category = AntiPurchaseTab:AddCategory("Anti-Purchase")
    local Main = Category:AddSubCategory("Main")
    local Section = Main:AddSection("Protection")
    
    Section:Toggle({
        Title = "Enabled",
        Flag = "AntiPurchase_Enabled",
        Default = Config.AntiPurchase.Enabled,
        Callback = function(val) Config.AntiPurchase.Enabled = val end
    })
    Section:Toggle({
        Title = "Block Purchase Prompts",
        Flag = "AntiPurchase_BlockPrompts",
        Default = Config.AntiPurchase.BlockPrompts,
        Callback = function(val) Config.AntiPurchase.BlockPrompts = val end
    })
    Section:Toggle({
        Title = "Block PerformPurchase",
        Flag = "AntiPurchase_BlockPerformPurchase",
        Default = Config.AntiPurchase.BlockPerformPurchase,
        Callback = function(val) Config.AntiPurchase.BlockPerformPurchase = val end
    })
    
    local Info = Main:AddSection("Information")
    Info:Toggle({
        Title = "Show Product Info",
        Flag = "AntiPurchase_ShowProductInfo",
        Default = Config.AntiPurchase.ShowProductInfo,
        Callback = function(val) Config.AntiPurchase.ShowProductInfo = val end
    })
end

-- Anti-Webhook Tab
do
    local Category = AntiWebhookTab:AddCategory("Anti-Webhook")
    local Main = Category:AddSubCategory("Main")
    local Section = Main:AddSection("Protection")
    
    Section:Toggle({
        Title = "Enabled",
        Flag = "AntiWebhook_Enabled",
        Default = Config.AntiWebhook.Enabled,
        Callback = function(val) Config.AntiWebhook.Enabled = val end
    })
    Section:Toggle({
        Title = "Block Discord Webhooks",
        Flag = "AntiWebhook_BlockDiscord",
        Default = Config.AntiWebhook.BlockDiscord,
        Callback = function(val) Config.AntiWebhook.BlockDiscord = val end
    })
    Section:Toggle({
        Title = "Block Generic Loggers",
        Flag = "AntiWebhook_BlockGeneric",
        Default = Config.AntiWebhook.BlockGeneric,
        Callback = function(val) Config.AntiWebhook.BlockGeneric = val end
    })
    
    local Info = Main:AddSection("Information")
    Info:Toggle({
        Title = "Show Logged Data",
        Flag = "AntiWebhook_ShowLoggedData",
        Default = Config.AntiWebhook.ShowLoggedData,
        Callback = function(val) Config.AntiWebhook.ShowLoggedData = val end
    })
    Info:Toggle({
        Title = "Delete Webhook (Risky)",
        Flag = "AntiWebhook_DeleteWebhook",
        Default = Config.AntiWebhook.DeleteWebhook,
        Callback = function(val) Config.AntiWebhook.DeleteWebhook = val end
    })
end

-- Anti-Chat Tab
do
    local Category = AntiChatTab:AddCategory("Anti-Chat Manipulation")
    local Main = Category:AddSubCategory("Protection")
    local Section = Main:AddSection("Blocks")
    
    Section:Toggle({
        Title = "Enabled",
        Flag = "AntiChat_Enabled",
        Default = Config.AntiChatManipulation.Enabled,
        Callback = function(val) Config.AntiChatManipulation.Enabled = val end
    })
    Section:Toggle({
        Title = "Block Force Chat",
        Flag = "AntiChat_BlockForceChat",
        Default = Config.AntiChatManipulation.BlockForceChat,
        Callback = function(val) Config.AntiChatManipulation.BlockForceChat = val end
    })
    Section:Toggle({
        Title = "Block MessagePost",
        Flag = "AntiChat_BlockMessagePost",
        Default = Config.AntiChatManipulation.BlockMessagePost,
        Callback = function(val) Config.AntiChatManipulation.BlockMessagePost = val end
    })
    Section:Toggle({
        Title = "Block New Chat System",
        Flag = "AntiChat_BlockNewChat",
        Default = Config.AntiChatManipulation.BlockNewChat,
        Callback = function(val) Config.AntiChatManipulation.BlockNewChat = val end
    })
    
    local Notif = Main:AddSection("Notifications")
    Notif:Toggle({
        Title = "Show Warnings",
        Flag = "AntiChat_ShowWarning",
        Default = Config.AntiChatManipulation.ShowWarning,
        Callback = function(val) Config.AntiChatManipulation.ShowWarning = val end
    })
end

-- Anti-Kick Tab
do
    local Category = AntiKickTab:AddCategory("Anti-Kick")
    local Main = Category:AddSubCategory("Main")
    local Section = Main:AddSection("Protection")
    
    Section:Toggle({
        Title = "Enabled",
        Flag = "AntiKick_Enabled",
        Default = Config.AntiKick.Enabled,
        Callback = function(val) Config.AntiKick.Enabled = val end
    })
    Section:Toggle({
        Title = "Show Kick Message",
        Flag = "AntiKick_ShowKickMessage",
        Default = Config.AntiKick.ShowKickMessage,
        Callback = function(val) Config.AntiKick.ShowKickMessage = val end
    })
end

-- Anti-API Tab
do
    local Category = AntiAPITab:AddCategory("Anti-API")
    local Main = Category:AddSubCategory("Protection")
    local Section = Main:AddSection("Blocks")
    
    Section:Toggle({
        Title = "Enabled",
        Flag = "AntiAPI_Enabled",
        Default = Config.AntiAPI.Enabled,
        Callback = function(val) Config.AntiAPI.Enabled = val end
    })
    Section:Toggle({
        Title = "Block RbxAnalytics",
        Flag = "AntiAPI_BlockRbxAnalytics",
        Default = Config.AntiAPI.BlockRbxAnalytics,
        Callback = function(val) Config.AntiAPI.BlockRbxAnalytics = val end
    })
    Section:Toggle({
        Title = "Block HttpRbxApi",
        Flag = "AntiAPI_BlockHttpRbxApi",
        Default = Config.AntiAPI.BlockHttpRbxApi,
        Callback = function(val) Config.AntiAPI.BlockHttpRbxApi = val end
    })
    
    local Info = Main:AddSection("Information")
    Info:Toggle({
        Title = "Show Endpoint",
        Flag = "AntiAPI_ShowEndpoint",
        Default = Config.AntiAPI.ShowEndpoint,
        Callback = function(val) Config.AntiAPI.ShowEndpoint = val end
    })
end

-- Anti-Detection Tab
do
    local Category = AntiDetectionTab:AddCategory("Anti-Detection")
    local Main = Category:AddSubCategory("Spoofing")
    local Section = Main:AddSection("Protection")
    
    Section:Toggle({
        Title = "Memory Spoof",
        Flag = "AntiDetection_MemorySpoof",
        Default = Config.AntiDetection.MemorySpoof,
        Callback = function(val) Config.AntiDetection.MemorySpoof = val end
    })
    Section:Toggle({
        Title = "GUI Detection Block",
        Flag = "AntiDetection_GUIDetection",
        Default = Config.AntiDetection.GUIDetection,
        Callback = function(val) Config.AntiDetection.GUIDetection = val end
    })
    Section:Toggle({
        Title = "Group Bypass",
        Flag = "AntiDetection_GroupBypass",
        Default = Config.AntiDetection.GroupBypass,
        Callback = function(val) Config.AntiDetection.GroupBypass = val end
    })
    
    local Experimental = Main:AddSection("Experimental")
    Experimental:Toggle({
        Title = "Clear Traces",
        Flag = "AntiDetection_ClearTraces",
        Default = Config.AntiDetection.ClearTraces,
        Callback = function(val) Config.AntiDetection.ClearTraces = val end
    })
end

-- Anti-Bypass Tab
do
    local Category = AntiBypassTab:AddCategory("Anti-Bypass")
    local Main = Category:AddSubCategory("Protection")
    local Section = Main:AddSection("Blocks")
    
    Section:Toggle({
        Title = "Enabled",
        Flag = "AntiBypass_Enabled",
        Default = Config.AntiBypass.Enabled,
        Callback = function(val) Config.AntiBypass.Enabled = val end
    })
    Section:Toggle({
        Title = "Block Hookfunction",
        Flag = "AntiBypass_BlockHookfunction",
        Default = Config.AntiBypass.BlockHookfunction,
        Callback = function(val) Config.AntiBypass.BlockHookfunction = val end
    })
    Section:Toggle({
        Title = "Block Clonefunction",
        Flag = "AntiBypass_BlockClonefunction",
        Default = Config.AntiBypass.BlockClonefunction,
        Callback = function(val) Config.AntiBypass.BlockClonefunction = val end
    })
end

-- Misc Tab
do
    local Category = MiscTab:AddCategory("Miscellaneous")
    local Main = Category:AddSubCategory("Main")
    local Section = Main:AddSection("Protections")
    
    Section:Toggle({
        Title = "Anti-Idle",
        Flag = "Misc_AntiIdle",
        Default = Config.Misc.AntiIdle,
        Callback = function(val) Config.Misc.AntiIdle = val end
    })
    Section:Toggle({
        Title = "Disable Errors",
        Flag = "Misc_DisableErrors",
        Default = Config.Misc.DisableErrors,
        Callback = function(val) Config.Misc.DisableErrors = val end
    })
    Section:Toggle({
        Title = "Disable Log Messages",
        Flag = "Misc_DisableLogMessages",
        Default = Config.Misc.DisableLogMessages,
        Callback = function(val) Config.Misc.DisableLogMessages = val end
    })
    Section:Toggle({
        Title = "Anti-Report Abuse",
        Flag = "Misc_AntiReportAbuse",
        Default = Config.Misc.AntiReportAbuse,
        Callback = function(val) Config.Misc.AntiReportAbuse = val end
    })
end

-- Config Tab
do
    local Saves = ConfigTab:AddCategory("Saves")
    local ConfigCategory = Saves:AddSubCategory("Config")
    local Main = ConfigCategory:AddSection("Main")
    
    Main:Textbox({
        Title = "Config Name",
        Placeholder = "myconfig",
        Flag = "Config_TextBox"
    })
    
    Main:Button({
        Title = "Save Config",
        Callback = function()
            local ConfigName = Seraph.Flags.Config_TextBox:GetValue()
            if not ConfigName or ConfigName == "" then
                NotifyWarning("Config", "Please enter a config name!")
                return
            end
            local Serialized = {}
            for Flag, Component in Seraph.Flags do
                if not (Flag:find("Config_") or Flag:find("Theme_")) then
                    local Value = Component:GetValue()
                    if typeof(Value) == "EnumItem" then
                        Value = Value.Name
                    end
                    if typeof(Value) == "Color3" then
                        Value = tostring(Value.R) .. "," .. tostring(Value.G) .. "," .. tostring(Value.B)
                    end
                    Serialized[Flag] = Value
                end
            end
            writefile("protectio/" .. ConfigName .. ".json", game:GetService("HttpService"):JSONEncode(Serialized))
            NotifySuccess("Config", "Saved as " .. ConfigName .. "!")
        end
    })
    
    Main:Dropdown({
        Title = "Configs",
        Options = {},
        Flag = "Config_ConfigList"
    })
    
    Main:Button({
        Title = "Load Config",
        Callback = function()
            local ConfigName = Seraph.Flags.Config_ConfigList:GetValue()
            if not ConfigName then return end
            
            local function GetEnum(Name)
                for _, v in Enum.KeyCode:GetEnumItems() do
                    if v.Name == Name then return Enum.KeyCode[Name] end
                end
                for _, v in Enum.UserInputType:GetEnumItems() do
                    if v.Name == Name then return Enum.UserInputType[Name] end
                end
                return nil
            end
            
            local Content = game:GetService("HttpService"):JSONDecode(readfile("protectio/" .. ConfigName .. ".json"))
            for Flag, Value in Content do
                if typeof(Value) == "string" then
                    local enumVal = GetEnum(Value)
                    if enumVal then
                        Value = enumVal
                    elseif #Value:split(",") == 3 then
                        Value = Color3.new(unpack(Value:split(",")))
                    end
                end
                if Seraph.Flags[Flag] then
                    Seraph.Flags[Flag]:SetValue(Value)
                end
            end
            NotifySuccess("Config", "Loaded " .. ConfigName .. "!")
        end
    })
    
    Main:Button({
        Title = "Refresh Configs",
        Callback = function()
            local ConfigDropdown = Seraph.Flags.Config_ConfigList
            local PrettyNames = {}
            local Files = listfiles("protectio/")
            for _, File in Files do
                local name = File:gsub("protectio/", ""):gsub(".json", "")
                PrettyNames[#PrettyNames + 1] = name
            end
            ConfigDropdown:SetOptions(PrettyNames)
        end
    })
    
    Main:Button({
        Title = "Enable All",
        Callback = function()
            for Flag, Component in Seraph.Flags do
                if not (Flag:find("Config_") or Flag:find("Theme_")) then
                    if type(Component.GetValue) == "function" and typeof(Component:GetValue()) == "boolean" then
                        Component:SetValue(true)
                    end
                end
            end
            NotifySuccess("Protectio", "All protections enabled!")
        end
    })
    
    Main:Button({
        Title = "Disable All",
        Callback = function()
            for Flag, Component in Seraph.Flags do
                if not (Flag:find("Config_") or Flag:find("Theme_")) then
                    if type(Component.GetValue) == "function" and typeof(Component:GetValue()) == "boolean" then
                        Component:SetValue(false)
                    end
                end
            end
            NotifyWarning("Protectio", "All protections disabled!")
        end
    })
    
    local Interface = Saves:AddSubCategory("Interface")
    local WindowSection = Interface:AddSection("Window")
    
    WindowSection:Label({
        Title = "Interface Toggle"
    }):Bind({
        Default = Seraph.WindowKeybind,
        Flag = "WindowBind",
        Callback = function(Bind)
            Seraph:SetWindowKeybind(Bind)
        end
    })
    
    local Colors = Interface:AddSection("Colors")
    for i, v in Seraph:GetTheme() do
        Colors:Label({ Title = i }):Colorpicker({
            Default = v,
            Flag = "Theme_" .. i,
            Callback = function(NewColor)
                local NTheme = Seraph:GetTheme()
                NTheme[i] = NewColor
                Seraph:SetTheme(NTheme)
            end
        })
    end
    
    Colors:Dropdown({
        Title = "Themes",
        Options = ThemeNames,
        Default = "Default",
        Callback = function(Option)
            for Property, Val in ThemeList[Option] do
                local flagName = "Theme_" .. Property
                if Seraph.Flags[flagName] then
                    Seraph.Flags[flagName]:SetValue(Val)
                end
            end
            Seraph:SetTheme(ThemeList[Option])
        end
    })
    
    Colors:Slider({
        Title = "Animation Speed",
        ZeroValue = 1,
        Default = 1,
        Min = 0.25,
        Max = 2,
        Decimal = 2,
        Callback = function(Val)
            Seraph:SetAnimationSpeed(Val)
        end
    })
end

--===========================================
-- PROTECTION IMPLEMENTATION
--===========================================
local ProtectionCount = 0

local function IncrementProtection()
    ProtectionCount = ProtectionCount + 1
end

local function SetupProtections()
    if not hookmetamethod or not hookfunction then
        NotifyWarning("Warning", "Missing core functions! Protection limited.", 10)
        Output("WARNING: Executor missing hookmetamethod or hookfunction")
    end
    
    if not checkcaller then
        NotifyWarning("Warning", "Missing checkcaller! Bypass limited.", 10)
    end

    --=======================================
    -- SERVICE FUNCTION HOOKS
    --=======================================
    if hookfunction then
        for serviceName, methods in pairs(MaliciousFunctions) do
            local service = cGame:GetService(serviceName)
            if service then
                for methodName, info in pairs(methods) do
                    local method = service[methodName]
                    if type(method) == "function" then
                        pcall(function()
                            local oldFunc = hookfunction(method, function(...)
                                local block = false
                                
                                if serviceName == "MarketplaceService" and Config.AntiPurchase.Enabled then
                                    if (Config.AntiPurchase.BlockPrompts and methodName:find("Prompt")) or
                                       (Config.AntiPurchase.BlockPerformPurchase and methodName:find("Perform")) or
                                       methodName:find("Prepare") then
                                        block = true
                                    end
                                elseif serviceName == "RbxAnalyticsService" and Config.AntiAPI.Enabled and Config.AntiAPI.BlockRbxAnalytics then
                                    block = true
                                elseif serviceName == "HttpRbxApiService" and Config.AntiAPI.Enabled and Config.AntiAPI.BlockHttpRbxApi then
                                    block = true
                                else
                                    block = true
                                end
                                
                                if block then
                                    Output("Malicious call blocked: " .. serviceName .. "." .. methodName .. " - " .. info.reason)
                                    NotifyBlocked("Blocked", "Blocked: " .. serviceName .. "." .. methodName, 4)
                                    return nil
                                end
                                return oldFunc(...)
                            end)
                            IncrementProtection()
                        end)
                    end
                end
            end
        end
        
        -- Anti-Report Abuse
        if Config.Misc.AntiReportAbuse then
            pcall(function()
                local oldReport = hookfunction(Players.ReportAbuse, function(...)
                    Output("ReportAbuse attempt blocked")
                    NotifyBlocked("Anti-Report", "False report attempt blocked!", 4)
                    return nil
                end)
                IncrementProtection()
            end)
        end
    end
    
        -- Chat Manipulation Protection
        if Config.AntiChatManipulation.Enabled and getcallingscript then
            if ChatSystem.Legacy then
                if Config.AntiChatManipulation.BlockMessagePost and ChatSystem.SayMessageRequest then
                    local oldFireServer = hookfunction(ChatSystem.SayMessageRequest.FireServer, function(self, ...)
                        if getcallingscript() ~= ChatSystem.ChatScript then
                            local scriptName = "unknown"
                            if getcallingscript() then
                                scriptName = getcallingscript():GetFullName()
                            end
                            Output("SayMessageRequest abuse blocked from: " .. scriptName)
                            if Config.AntiChatManipulation.ShowWarning then
                                NotifyBlocked("Chat Blocked", "Script tried to send message as you!\n" .. scriptName, 6)
                            end
                            return
                        end
                        return oldFireServer(self, ...)
                    end)
                    IncrementProtection()
                end
                
                if Config.AntiChatManipulation.BlockMessagePost and ChatSystem.MessagePostedEvent then
                    local oldFire = hookfunction(ChatSystem.MessagePostedEvent.Fire, function(self, ...)
                        Output("MessagePosted abuse blocked")
                        return
                    end)
                    IncrementProtection()
                end

                if Config.AntiChatManipulation.BlockForceChat and ChatSystem.ChatBar then
                    local oldCaptureFocus = hookfunction(ChatSystem.ChatBar.CaptureFocus, function(self, ...)
                        if getcallingscript() ~= ChatSystem.ChatScript then
                            local scriptName = "unknown"
                            if getcallingscript() then
                                scriptName = getcallingscript():GetFullName()
                            end
                            Output("CaptureFocus hijack blocked from: " .. scriptName)
                            if Config.AntiChatManipulation.ShowWarning then
                                NotifyBlocked("Force Chat Blocked", "Script tried to force chat focus!\n" .. scriptName, 6)
                            end
                            return
                        end
                        return oldCaptureFocus(self, ...)
                    end)
                    IncrementProtection()
                end
            end
            
            -- New Chat System Protection
            if Config.AntiChatManipulation.BlockNewChat then
                pcall(function()
                    local textChannel = Instance.new("TextChannel")
                    local oldSendAsync = hookfunction(textChannel.SendAsync, function(self, ...)
                        Output("TextChannel.SendAsync blocked")
                        NotifyBlocked("Chat Blocked", "New chat system message blocked!", 4)
                        return
                    end)
                    textChannel:Destroy()
                    IncrementProtection()
                end)
            end
        end

        -- GUI Detection Blocking
        if Config.AntiDetection.GUIDetection then
            local oldPreloadAsync = hookfunction(ContentProvider.PreloadAsync, function(self, ...)
                local args = {...}
                if typeof(args[1]) == "table" then
                    Output("GUI detection via PreloadAsync blocked")
                    return
                end
                return oldPreloadAsync(self, ...)
            end)
            IncrementProtection()
        end

    --=======================================
    -- FUNCTION HOOKS
    --=======================================
    if hookfunction then
        -- Anti-Kick direct hook
        local oldKick = hookfunction(LocalPlayer.Kick, function(...)
            if Config.AntiKick.Enabled then
                Output("Direct kick attempt blocked")
                NotifyBlocked("Anti-Kick", "Direct kick blocked!", 4)
                return
            end
            return oldKick(...)
        end)
        IncrementProtection()

        -- Memory info spoofing
        if gcinfo then
            local oldGcInfo = hookfunction(gcinfo, function(...)
                if Config.AntiDetection.MemorySpoof then
                    return math.random(1500, 2500)
                end
                return oldGcInfo(...)
            end)
            IncrementProtection()
        end

        local oldMemory = hookfunction(Stats.GetTotalMemoryUsageMb, function(...)
            if Config.AntiDetection.MemorySpoof then
                return math.random(350, 500)
            end
            return oldMemory(...)
        end)
        IncrementProtection()

        local oldIsInGroup = hookfunction(LocalPlayer.IsInGroup, function(...)
            if Config.AntiDetection.GroupBypass then
                local args = {...}
                if typeof(args[1]) == "number" then
                    if args[1] > 0 then
                        return true
                    end
                end
            end
            return oldIsInGroup(...)
        end)
        IncrementProtection()

        --=======================================
        -- HTTP REQUEST PROTECTION
        --=======================================
        for _, reqFunc in ipairs(HttpRequestFunctions) do
            pcall(function()
                local oldRequest = hookfunction(reqFunc, function(...)
                    local args = {...}
                    local requestTable = args[1] or args

                    if typeof(requestTable) == "table" then
                        local url = requestTable.Url or ""
                        local body = requestTable.Body or ""

                        -- Webhook blocking
                        if Config.AntiWebhook.Enabled then
                            local isWebhook = false
                            
                            if Config.AntiWebhook.BlockDiscord then
                                local found1 = strFind(strLower(url), "webhook")
                                local found2 = strFind(strLower(url), "discord")
                                if found1 or found2 then
                                    isWebhook = true
                                end
                            end
                            
                            if Config.AntiWebhook.BlockGeneric then
                                local found3 = strFind(strLower(url), "websec")
                                local found4 = strFind(strLower(url), "logs")
                                local found5 = strFind(strLower(url), "logger")
                                if found3 or found4 or found5 then
                                    isWebhook = true
                                end
                            end

                            if isWebhook then
                                local logInfo = ""
                                if Config.AntiWebhook.ShowLoggedData then
                                    if body ~= "" then
                                        pcall(function()
                                            local decoded = HttpService:JSONDecode(body)
                                            logInfo = "\nLogged data:\n" .. TableToString(decoded)
                                        end)
                                    end
                                end
                                
                                local urlDisplay = "[URL HIDDEN]"
                                if Config.AntiWebhook.ShowLoggedData then
                                    urlDisplay = url
                                end
                                
                                Output("Webhook blocked: " .. urlDisplay .. logInfo)
                                NotifyBlocked("Anti-Webhook", "Data logging attempt blocked!", 5)
                                
                                if Config.AntiWebhook.DeleteWebhook then
                                    requestTable.Method = "DELETE"
                                else
                                    requestTable.Url = "https://httpbin.org/post"
                                end
                                return oldRequest(unpack(args))
                            end
                        end

                        -- Discord auto-join blocking
                        local foundDiscord = strFind(url, "discord.com/api")
                        local foundRpc = strFind(body, "rpc")
                        if foundDiscord and foundRpc then
                            Output("Discord auto-join attempt blocked")
                            NotifyBlocked("Anti-Webhook", "Discord auto-join blocked!", 4)
                            return
                        end

                        -- Roblox API blocking
                        if Config.AntiAPI.Enabled then
                            if Config.AntiAPI.BlockHttpRbxApi then
                                local foundApi = strMatch(url, "%l+%.roblox%.com/v%d/")
                                if foundApi then
                                    local endpointDisplay = "[HIDDEN]"
                                    if Config.AntiAPI.ShowEndpoint then
                                        endpointDisplay = url
                                    end
                                    Output("API access blocked: " .. endpointDisplay)
                                    return
                                end
                            end
                        end
                    end
                    return oldRequest(...)
                end)
                IncrementProtection()
            end)
        end

        --=======================================
        -- ANTI-BYPASS PROTECTION
        --=======================================
        if Config.AntiBypass.Enabled then
            if Config.AntiBypass.BlockHookfunction then
                local blockedFunctions = {}
                blockedFunctions[hookfunction] = true
                blockedFunctions[hookmetamethod] = true
                
                local oldHookFunc = hookfunction(hookfunction, function(func, replacement)
                    if blockedFunctions[func] then
                        Output("Attempt to hook Protectio's functions blocked")
                        NotifyBlocked("Anti-Bypass", "Hookfunction bypass attempt blocked!", 5)
                        return print
                    end
                    return oldHookFunc(func, replacement)
                end)
                IncrementProtection()
            end

            if Config.AntiBypass.BlockClonefunction then
                local protectedFunctions = {}
                protectedFunctions[hookfunction] = true
                protectedFunctions[clonefunction] = true
                
                local oldCloneFunc = hookfunction(clonefunction, function(func)
                    if protectedFunctions[func] then
                        Output("Attempt to clone Protectio's functions blocked")
                        NotifyBlocked("Anti-Bypass", "Clonefunction bypass attempt blocked!", 5)
                        return print
                    end
                    return oldCloneFunc(func)
                end)
                IncrementProtection()
            end

            if restorefunction then
                local oldRestore = hookfunction(restorefunction, function(...)
                    if typeF(...) == "function" then
                        Output("restorefunction attempt blocked")
                        NotifyBlocked("Anti-Bypass", "Restorefunction attempt blocked!", 5)
                        return error("Protected")
                    end
                    return ...
                end)
                IncrementProtection()
            end
        end

        local oldGetBalance = hookfunction(MarketplaceService.GetRobuxBalance, function(...)
            return nil
        end)
        IncrementProtection()
    end

    --=======================================
    -- MISC PROTECTIONS
    --=======================================
    if Config.Misc.AntiIdle then
        pcall(function()
            for _, connection in ipairs(getconnections(LocalPlayer.Idled)) do
                connection:Disable()
            end
        end)
        IncrementProtection()
    end

    if Config.Misc.DisableErrors then
        pcall(function()
            for _, connection in ipairs(getconnections(cGame:GetService("ScriptContext").Error)) do
                connection:Disable()
            end
        end)
        IncrementProtection()
    end

    if Config.Misc.DisableLogMessages then
        pcall(function()
            for _, connection in ipairs(getconnections(cGame:GetService("LogService").MessageOut)) do
                connection:Disable()
            end
        end)
        IncrementProtection()
    end

    if Config.AntiDetection.ClearTraces then
        pcall(function()
            local isExecutorClosure = (is_synapse_function or isexecutorclosure or iskrnlclosure or issentinelclosure or is_protosmasher_closure or is_sirhurt_closure or iselectronfunction or checkclosure)
            if isExecutorClosure then
                if getgc then
                    for _, v in next, getgc() do
                        if typeof(v) == "function" then
                            if isExecutorClosure(v) then
                                pcall(function() v = nil end)
                            end
                        end
                    end
                end
            end
        end)
        IncrementProtection()
    end
end

--===========================================
-- INITIALIZE
--===========================================
SetupProtections()

NotifySuccess("Protectio", "Protection active with " .. ProtectionCount .. " shields!", 6)
Output("Protectio initialized with " .. ProtectionCount .. " active protections")

Output("\n=== PROTECTIO STATUS ===")
Output("Anti-Purchase: " .. tostring(Config.AntiPurchase.Enabled))
Output("Anti-Webhook: " .. tostring(Config.AntiWebhook.Enabled))
Output("Anti-Chat: " .. tostring(Config.AntiChatManipulation.Enabled))
Output("Anti-Kick: " .. tostring(Config.AntiKick.Enabled))
Output("Anti-API: " .. tostring(Config.AntiAPI.Enabled))
Output("Anti-Detection: " .. tostring(Config.AntiDetection.MemorySpoof))
Output("Anti-Bypass: " .. tostring(Config.AntiBypass.Enabled))
Output("Anti-Idle: " .. tostring(Config.Misc.AntiIdle))
Output("========================\n")

return {
    Config = Config,
    UpdateConfig = function(newConfig)
        for k, v in pairs(newConfig) do
            if Config[k] and type(v) == "table" then
                for k2, v2 in pairs(v) do
                    Config[k][k2] = v2
                end
            else
                Config[k] = v
            end
        end
        Output("Config updated")
    end
}