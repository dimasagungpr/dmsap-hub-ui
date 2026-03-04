-- =====================================================
-- UI Garden Incremental V1.0.324
-- =====================================================
-- [WORK RULES]
-- Lihat file WORK_RULES.md di repo private untuk aturan kerja dan notes UI.
-- =====================================================

-- =====================================================
-- SERVICES
-- =====================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local VirtualInputManager = nil
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

-- =====================================================
-- GLOBAL STATE / CLEANUP
-- =====================================================
local GLOBAL_KEY = "GardenIncremental__State"
local ENV = (getgenv and getgenv()) or _G
if ENV[GLOBAL_KEY] and ENV[GLOBAL_KEY].Cleanup then
    pcall(ENV[GLOBAL_KEY].Cleanup)
end

local State = {
    Connections = {},
    RemoteConnections = {},
    RemoteInvokeOld = {},
    ScreenGui = nil,
    Mt = nil,
    OldNamecall = nil,
    Hooked = false,
    RemoteHookEnabled = false,
    RemoteC2SEnabled = false,
    RemoteHookConn = nil
}

State.Version = "V1.0.324"
State.ValidateVersion = function(labelText)
    if type(labelText) ~= "string" then
        return false
    end
    if labelText ~= State.Version then
        warn("[GardenIncremental] Versi mismatch: State.Version=" .. tostring(State.Version) .. ", VersionLabel.Text=" .. tostring(labelText))
        return false
    end
    return true
end

State.RuneTeleportData = State.RuneTeleportData or {}
State.AutomationTeleport = State.AutomationTeleport or {
    Owner = nil
}
State.AutomationTeleport.TryAcquire = State.AutomationTeleport.TryAcquire or function(owner)
    if type(owner) ~= "string" or #owner == 0 then
        return false
    end
    if State.AutomationTeleport.Owner == nil or State.AutomationTeleport.Owner == owner then
        State.AutomationTeleport.Owner = owner
        return true
    end
    return false
end
State.AutomationTeleport.Release = State.AutomationTeleport.Release or function(owner)
    if owner == nil or State.AutomationTeleport.Owner == owner then
        State.AutomationTeleport.Owner = nil
    end
end
State.AutomationTeleport.IsBusy = State.AutomationTeleport.IsBusy or function(owner)
    local current = State.AutomationTeleport.Owner
    return current ~= nil and current ~= owner
end

-- =====================================================
-- GLOBAL CLICK SPEED (shared registry across tabs)
-- =====================================================
local GlobalClickCooldowns = {
    Default = 0.6
}

-- Ubah nilai ini sekali untuk semua automation deposit.
local AUTO_DEPOSIT_REQUIRED_MULTIPLIER = 1

local function setAutoDepositRequiredMultiplier(value)
    local n = tonumber(value)
    if type(n) ~= "number" then
        n = 1
    end
    AUTO_DEPOSIT_REQUIRED_MULTIPLIER = math.clamp(n, 0, 30)
    return AUTO_DEPOSIT_REQUIRED_MULTIPLIER
end

local function getAutoDepositRequiredMultiplier()
    local n = tonumber(AUTO_DEPOSIT_REQUIRED_MULTIPLIER) or 1
    return math.clamp(n, 0, 30)
end

local function setGlobalClickCooldown(key, v)
    local k = key
    local value = v
    if value == nil and type(k) ~= "string" then
        value = k
        k = "Default"
    end
    k = k or "Default"
    local n = tonumber(value)
    if n then
        GlobalClickCooldowns[k] = math.clamp(n, 0.1, 10)
    end
    return GlobalClickCooldowns[k] or GlobalClickCooldowns.Default
end

local function getGlobalClickCooldown(key)
    local k = key or "Default"
    return GlobalClickCooldowns[k] or GlobalClickCooldowns.Default
end

ENV.GardenIncremental_SetClickCooldown = setGlobalClickCooldown
ENV.GardenIncremental_GetClickCooldown = getGlobalClickCooldown

-- =====================================================
-- CONNECTION HELPERS / CLEANUP REGISTRY
-- =====================================================
local function trackConnection(conn)
    if conn then
        State.Connections[#State.Connections + 1] = conn
    end
    return conn
end

State.CleanupRegistry = State.CleanupRegistry or {}
State.CleanupRegistry.Items = State.CleanupRegistry.Items or {}
State.CleanupRegistry.Register = State.CleanupRegistry.Register or function(fn)
    if type(fn) ~= "function" then
        return
    end
    State.CleanupRegistry.Items[#State.CleanupRegistry.Items + 1] = fn
end
State.CleanupRegistry.Run = State.CleanupRegistry.Run or function()
    for _, fn in ipairs(State.CleanupRegistry.Items) do
        pcall(fn)
    end
    State.CleanupRegistry.Items = {}
end

local function cleanupAll()
    for _, conn in ipairs(State.Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    State.Connections = {}

    for _, conn in ipairs(State.RemoteConnections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    State.RemoteConnections = {}

    for obj, oldFn in pairs(State.RemoteInvokeOld) do
        pcall(function()
            if oldFn == true then
                obj.OnClientInvoke = nil
            else
                obj.OnClientInvoke = oldFn
            end
        end)
    end
    State.RemoteInvokeOld = {}

    if State.Hooked and State.Mt and State.OldNamecall then
        pcall(function()
            setreadonly(State.Mt, false)
            State.Mt.__namecall = State.OldNamecall
            setreadonly(State.Mt, true)
        end)
    end
    State.Hooked = false
    State.Mt = nil
    State.OldNamecall = nil

    if State.ScreenGui and State.ScreenGui.Parent then
        State.ScreenGui:Destroy()
    end
    State.ScreenGui = nil

    if State.AutoBuyLogGui and State.AutoBuyLogGui.Parent then
        State.AutoBuyLogGui:Destroy()
    end
    State.AutoBuyLogGui = nil

    
    if State.CleanupRegistry and State.CleanupRegistry.Run then
        State.CleanupRegistry.Run()
    end

    -- Stop any background loops that are not connection-based
    if LP and LP.Character then
        if State.WinterAutoSnow and State.WinterAutoSnow.SavedPivot then
            pcall(function()
                LP.Character:PivotTo(State.WinterAutoSnow.SavedPivot)
            end)
        end
        if State.ActionAuto and State.ActionAuto.Claim then
            local trick = State.ActionAuto.Claim.TrickOrTreat
            if trick and trick.SavedPivot then
                pcall(function()
                    LP.Character:PivotTo(trick.SavedPivot)
                end)
            end
            local santa = State.ActionAuto.Claim.SantaGift
            if santa and santa.SavedPivot then
                pcall(function()
                    LP.Character:PivotTo(santa.SavedPivot)
                end)
            end
        end
    end
    if State.AutomationTeleport and State.AutomationTeleport.Release then
        State.AutomationTeleport.Release(nil)
    end

    if ENV and ENV[GLOBAL_KEY] then
        ENV[GLOBAL_KEY] = nil
    end
end

State.AntiAfk = State.AntiAfk or {}
State.AntiAfk.Init = State.AntiAfk.Init or function()
    if State.AntiAfk.Active then
        return
    end
    State.AntiAfk.Active = true
    local ok, vu = pcall(game.GetService, game, "VirtualUser")
    local lp = Players and Players.LocalPlayer or nil
    if not (ok and vu and lp and lp.Idled) then
        return
    end
    local conn = lp.Idled:Connect(function()
        pcall(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new(0, 0))
        end)
    end)
    trackConnection(conn)
end

State.AntiAfk.Init()

State.Cleanup = cleanupAll
ENV[GLOBAL_KEY] = State

-- [FUNC] Construct teleport data
local function makeData(pos, camCFrame, camFocus, fov, camType, zoom, minZoom, maxZoom)
    if camType == nil and zoom == nil and minZoom == nil and maxZoom == nil then
        zoom = fov
        fov = 70.000
        camType = Enum.CameraType.Custom
        minZoom = 0.500
        maxZoom = 40.000
    end
    return {
        position = pos,
        camera = {
            cframe = camCFrame,
            focus = camFocus,
            fov = fov,
            type = camType,
            zoom = zoom,
            min_zoom = minZoom,
            max_zoom = maxZoom
        }
    }
end

local function isRuneLabel(label)
    if type(label) ~= "string" then
        return false
    end
    return string.find(string.lower(label), "rune", 1, true) ~= nil
end

local function registerRuneLocations(worldName, list)
    if type(worldName) ~= "string" or type(list) ~= "table" then
        return
    end
    local out = {}
    for _, item in ipairs(list) do
        if item and isRuneLabel(item.Label) and item.Data then
            out[#out + 1] = {
                Label = item.Label,
                Data = item.Data,
                Key = worldName .. " :: " .. tostring(item.Label)
            }
        end
    end
    State.RuneTeleportData[worldName] = out
end

-- =====================================================
-- EARLY LOG CAPTURE
-- =====================================================
local ConsoleLogBuffer = {}
local MaxConsoleLogs = 200
local function getLogHistoryAll()
    if not LogService.GetLogHistory then
        return {}
    end
    local ok, history = pcall(function()
        return LogService:GetLogHistory()
    end)
    if not ok or type(history) ~= "table" then
        return {}
    end
    local out = {}
    for _, item in ipairs(history) do
        out[#out + 1] = {
            Message = item.message,
            Type = item.messageType,
            Time = os.time()
        }
    end
    return out
end
local function pushConsoleLog(message, msgType)
    ConsoleLogBuffer[#ConsoleLogBuffer + 1] = {
        Message = message,
        Type = msgType,
        Time = os.time()
    }
    if #ConsoleLogBuffer > MaxConsoleLogs then
        table.remove(ConsoleLogBuffer, 1)
    end
end

trackConnection(LogService.MessageOut:Connect(function(message, msgType)
    pushConsoleLog(message, msgType)
end))

-- =====================================================
-- CONFIG SAVE / LOAD
-- =====================================================
-- =====================================================
-- CONFIG / PERSISTENCE
-- =====================================================
local CONFIG_FOLDER = "FunScripts"
local CONFIG_FILE = CONFIG_FOLDER .. "/DemoConfig.json"

local Config = {
    InfiniteJump = false,
    WalkSpeed = 16,
    WalkSpeedEnabled = false,
    NoFog = false,
    NoFX = false,
    LowGraphics = false,
    FullBright = false,
    ManualFogStart = 100000,
    ManualFogEnd = 100000,
    DisableBloom = true,
    DisableBlur = true,
    DisableSunRays = true,
    DisableColorCorrection = true,
    ManualGraphicsQuality = "Level01",
    ManualGraphicsShadows = false,
    ManualBrightness = 2,
    ManualClockTime = 12,
    ManualFullBrightShadows = false,
    FirstRun = true,
    ActionLogger = false,
    Theme = "Default",
    Font = "ChakraPetch",
    FontScale = 1.0,
    UtilityTrackNames = "",
    UtilityTrackValues = true,
    UtilityTrackAttributes = true,
    UtilityLoggerEnabled = false,
    UtilityLogSearchMode = "By Path",
    RepScanKeywords = "",
    RepScanIncludeFolders = false,
    RepScanIncludeRemotes = false,
    WindowWidth = 640,
    WindowHeight = 430,
    AutoReloadEnabled = false,
    AutoReloadSource = "",
    AutoReloadUrl = "",
    AutoReloadFile = "",
    SectionStates = {},
    AutoBuyGroups = {},
    AutoBuyLogEnabled = false,
    AutoBuyLogWidth = 200,
    AutoBuyLogHeight = 300,
    ActionPotionCyberEnabled = false,
    ActionPotion3MEnabled = false,
    ActionClaimTrickOrTreatEnabled = false,
    ActionClaimSantaGiftEnabled = false,
    ActionAutoClickerEnabled = false,
    ActionAutoRedeemCodesEnabled = false,
    ActionAutoClaimMasteryEnabled = false,
    GardenAutoClickFallTreeEnabled = false,
    ForestAutoLogEnabled = false,
    MinesAutoDepositEnabled = false,
    MinesAutoDepositItems = {},
    FishAutoDepositEnabled = false,
    FishAutoDepositItems = {},
    UniverseAutoDepositEnabled = false,
    UniverseAutoDepositItems = {},
    HellAutoDepositEnabled = false,
    HellAutoDepositItems = {},
    HellAutoDropperEnabled = false,
    HellAutoRanksEnabled = false,
    Event500KAutoUpgradeTreeEnabled = false,
    GardenAutoUpgradeTreeEnabled = false,
    DesertAutoUpgradePointsTreeEnabled = false,
    DesertAutoUpgradeBetterPointsTreeEnabled = false,
    AutoDepositRequiredMultiplier = 1,
    AutoBuyClickSpeed = 0.6,
    HideKeybind = "K",
    AutoBuyLogKeybind = "[",
    ActionAutoClickerKeybind = "G",
    FlyEnabled = false,
    FlySpeed = 60,
    FlyInertia = 0.15,
    NoClip = false,
    Freecam = false,
    FreecamSpeed = 1.6,
    AirWalk = false,
    WallHop = false,
    AutoJump = false,
    AirJump = false,
    Spinbot = false,
    SpinSpeed = 180,
    Fling = false,
    FlingPower = 2500,
    JumpPowerEnabled = false,
    JumpPower = 50,
    JumpHeightEnabled = false,
    JumpHeight = 7.2,
    FPSBoost = false,
    XRay = false
}

local MINIMIZE_ICON_URL = "https://raw.githubusercontent.com/dimasagungpr/rbx/24c574735870fa3004352b941355e9f21f6ad3e9/src/script-logo.png"
local MINIMIZED_ICON_SIZE = 48
local RESIZE_ICON_URL = "rbxassetid://97880448391331"
local HEADER_LOGO_URL = "https://raw.githubusercontent.com/dimasagungpr/rbx/24c574735870fa3004352b941355e9f21f6ad3e9/src/script-logo.png"
local COPY_ICON_ASSET = "rbxassetid://108225148244406"
local MINIMIZE_ICON_ASSET = "rbxassetid://77021826549143"
local CLOSE_ICON_ASSET = "rbxassetid://6031094678"
local function resolveMinimizeIcon()
    if getcustomasset and writefile and isfile and game and game.HttpGet then
        local iconPath = CONFIG_FOLDER .. "/minimize_logo.png"
        if not isfile(iconPath) then
            pcall(function()
                local data = game:HttpGet(MINIMIZE_ICON_URL)
                writefile(iconPath, data)
            end)
        end
        if isfile(iconPath) then
            local ok, asset = pcall(getcustomasset, iconPath)
            if ok and asset then
                return asset
            end
        end
    end
    return MINIMIZE_ICON_URL
end

local function resolveHeaderLogo()
    if getcustomasset and writefile and isfile and game and game.HttpGet then
        local iconPath = CONFIG_FOLDER .. "/header_logo.png"
        if not isfile(iconPath) then
            pcall(function()
                local data = game:HttpGet(HEADER_LOGO_URL)
                writefile(iconPath, data)
            end)
        end
        if isfile(iconPath) then
            local ok, asset = pcall(getcustomasset, iconPath)
            if ok and asset then
                return asset
            end
        end
    end
    return HEADER_LOGO_URL
end

local function resolveResizeIcon()
    return RESIZE_ICON_URL
end


local function loadConfig()
    if isfile and isfile(CONFIG_FILE) and readfile then
        local ok, data = pcall(readfile, CONFIG_FILE)
        if ok and data then
            local ok2, decoded = pcall(function()
                return HttpService:JSONDecode(data)
            end)
            if ok2 and type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    if Config[k] ~= nil then
                        Config[k] = v
                    end
                end
            end
        end
    end
end

local function saveConfig()
    if writefile and makefolder then
        if not (isfolder and isfolder(CONFIG_FOLDER)) then
            pcall(makefolder, CONFIG_FOLDER)
        end
        local ok, encoded = pcall(function()
            return HttpService:JSONEncode(Config)
        end)
        if ok and encoded then
            pcall(writefile, CONFIG_FILE, encoded)
        end
    end
end

State.Config = State.Config or {}
State.Config.Data = Config
State.Config.Get = State.Config.Get or function(key, default)
    local v = Config[key]
    if v == nil then
        return default
    end
    return v
end
State.Config.Set = State.Config.Set or function(key, value, noSave)
    Config[key] = value
    if not noSave then
        saveConfig()
    end
end
State.Config.Save = State.Config.Save or function()
    saveConfig()
end
State.Config.Normalize = State.Config.Normalize or function()
    if type(Config.SectionStates) ~= "table" then
        Config.SectionStates = {}
    end
    if type(Config.AutoBuyGroups) ~= "table" then
        Config.AutoBuyGroups = {}
    end
    if type(Config.AutoBuyClickSpeed) ~= "number" then
        Config.AutoBuyClickSpeed = 0.6
    end
    if type(Config.ActionPotionCyberEnabled) ~= "boolean" then
        Config.ActionPotionCyberEnabled = false
    end
    if type(Config.ActionPotion3MEnabled) ~= "boolean" then
        Config.ActionPotion3MEnabled = false
    end
    if type(Config.ActionClaimTrickOrTreatEnabled) ~= "boolean" then
        Config.ActionClaimTrickOrTreatEnabled = false
    end
    if type(Config.ActionClaimSantaGiftEnabled) ~= "boolean" then
        Config.ActionClaimSantaGiftEnabled = false
    end
    if type(Config.ActionAutoClickerEnabled) ~= "boolean" then
        Config.ActionAutoClickerEnabled = false
    end
    if type(Config.ActionAutoRedeemCodesEnabled) ~= "boolean" then
        Config.ActionAutoRedeemCodesEnabled = false
    end
    if type(Config.ActionAutoClaimMasteryEnabled) ~= "boolean" then
        Config.ActionAutoClaimMasteryEnabled = false
    end
    if type(Config.GardenAutoClickFallTreeEnabled) ~= "boolean" then
        Config.GardenAutoClickFallTreeEnabled = false
    end
    if type(Config.ForestAutoLogEnabled) ~= "boolean" then
        Config.ForestAutoLogEnabled = false
    end
    if type(Config.MinesAutoDepositEnabled) ~= "boolean" then
        Config.MinesAutoDepositEnabled = false
    end
    if type(Config.MinesAutoDepositItems) ~= "table" then
        Config.MinesAutoDepositItems = {}
    end
    if type(Config.FishAutoDepositEnabled) ~= "boolean" then
        Config.FishAutoDepositEnabled = false
    end
    if type(Config.FishAutoDepositItems) ~= "table" then
        Config.FishAutoDepositItems = {}
    end
    if type(Config.UniverseAutoDepositEnabled) ~= "boolean" then
        Config.UniverseAutoDepositEnabled = false
    end
    if type(Config.UniverseAutoDepositItems) ~= "table" then
        Config.UniverseAutoDepositItems = {}
    end
    if type(Config.HellAutoDepositEnabled) ~= "boolean" then
        Config.HellAutoDepositEnabled = false
    end
    if type(Config.HellAutoDepositItems) ~= "table" then
        Config.HellAutoDepositItems = {}
    end
    if type(Config.HellAutoDropperEnabled) ~= "boolean" then
        Config.HellAutoDropperEnabled = false
    end
    if type(Config.HellAutoRanksEnabled) ~= "boolean" then
        Config.HellAutoRanksEnabled = false
    end
    if type(Config.Event500KAutoUpgradeTreeEnabled) ~= "boolean" then
        Config.Event500KAutoUpgradeTreeEnabled = false
    end
    if type(Config.GardenAutoUpgradeTreeEnabled) ~= "boolean" then
        Config.GardenAutoUpgradeTreeEnabled = false
    end
    if type(Config.DesertAutoUpgradePointsTreeEnabled) ~= "boolean" then
        Config.DesertAutoUpgradePointsTreeEnabled = false
    end
    if type(Config.DesertAutoUpgradeBetterPointsTreeEnabled) ~= "boolean" then
        Config.DesertAutoUpgradeBetterPointsTreeEnabled = false
    end
    if type(Config.AutoDepositRequiredMultiplier) ~= "number" then
        Config.AutoDepositRequiredMultiplier = 1
    end
    Config.AutoDepositRequiredMultiplier = math.clamp(Config.AutoDepositRequiredMultiplier, 0, 30)
    if type(Config.HideKeybind) ~= "string" or #Config.HideKeybind == 0 then
        Config.HideKeybind = "K"
    end
    if type(Config.AutoBuyLogWidth) ~= "number" then
        Config.AutoBuyLogWidth = 200
    end
    if type(Config.AutoBuyLogHeight) ~= "number" then
        Config.AutoBuyLogHeight = 300
    end
    Config.AutoBuyLogWidth = math.clamp(math.floor(Config.AutoBuyLogWidth + 0.5), 180, 520)
    Config.AutoBuyLogHeight = math.clamp(math.floor(Config.AutoBuyLogHeight + 0.5), 140, 700)
    if type(Config.AutoBuyLogKeybind) ~= "string" or #Config.AutoBuyLogKeybind == 0 then
        Config.AutoBuyLogKeybind = "["
    end
    if type(Config.ActionAutoClickerKeybind) ~= "string" or #Config.ActionAutoClickerKeybind == 0 then
        Config.ActionAutoClickerKeybind = "G"
    end
    if type(Config.UtilityLogSearchMode) ~= "string" or #Config.UtilityLogSearchMode == 0 then
        Config.UtilityLogSearchMode = "By Path"
    end
    if type(Config.FontScale) ~= "number" then
        Config.FontScale = 1.0
    end
    if type(Config.FlySpeed) ~= "number" then
        Config.FlySpeed = 60
    end
    if type(Config.FlyInertia) ~= "number" then
        Config.FlyInertia = 0.15
    end
    if type(Config.FreecamSpeed) ~= "number" then
        Config.FreecamSpeed = 1.6
    end
    if type(Config.SpinSpeed) ~= "number" then
        Config.SpinSpeed = 180
    end
    if type(Config.FlingPower) ~= "number" then
        Config.FlingPower = 2500
    end
    if type(Config.JumpPower) ~= "number" then
        Config.JumpPower = 50
    end
    if type(Config.JumpHeight) ~= "number" then
        Config.JumpHeight = 7.2
    end
    return Config
end
State.Config.Load = State.Config.Load or function()
    loadConfig()
    State.Config.Normalize()
end

State.Config.Load()
Config.UtilityLoggerEnabled = false
Config.UtilityTrackNames = ""
setAutoDepositRequiredMultiplier(Config.AutoDepositRequiredMultiplier)

-- =====================================================
-- LOGGING
-- =====================================================
State.Log = State.Log or {}
State.Log.Enabled = State.Log.Enabled ~= false
State.Log.Debug = State.Log.Debug or function(...)
    if not State.Log.Enabled then
        return
    end
    print("[GardenIncremental]", ...)
end
State.Log.Warn = State.Log.Warn or function(...)
    warn("[GardenIncremental]", ...)
end

-- =====================================================
-- KEYBIND HELPERS
-- =====================================================
State.Keybind = State.Keybind or {}
State.Keybind.Normalize = State.Keybind.Normalize or function(value)
    if type(value) ~= "string" then
        return nil
    end
    local raw = value:gsub("%s+", "")
    if #raw == 0 then
        return nil
    end
    if #raw == 1 then
        raw = raw:upper()
        if raw == "[" or raw == "]" then
            return raw
        end
        if Enum.KeyCode[raw] then
            return raw
        end
    end
    local lower = string.lower(raw)
    for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
        if string.lower(item.Name) == lower then
            return item.Name
        end
    end
    return nil
end

State.Keybind.MapKeyCode = State.Keybind.MapKeyCode or function(name)
    if name == "[" then
        return Enum.KeyCode.LeftBracket
    end
    if name == "]" then
        return Enum.KeyCode.RightBracket
    end
    if Enum.KeyCode[name] then
        return Enum.KeyCode[name]
    end
    return nil
end

State.Keybind.ResolveKey = State.Keybind.ResolveKey or function(flag, defaultName)
    local name = State.Config and State.Config.Get and State.Config.Get(flag, defaultName) or defaultName
    local normalized = State.Keybind.Normalize(name) or defaultName
    local keyCode = State.Keybind.MapKeyCode and State.Keybind.MapKeyCode(normalized) or Enum.KeyCode[normalized]
    return keyCode, normalized
end

State.Keybind.Resolve = State.Keybind.Resolve or function()
    return State.Keybind.ResolveKey("HideKeybind", "K")
end

State.Keybind.ResolveAutoBuyLog = State.Keybind.ResolveAutoBuyLog or function()
    return State.Keybind.ResolveKey("AutoBuyLogKeybind", "[")
end

State.Keybind.ResolveAutoClicker = State.Keybind.ResolveAutoClicker or function()
    return State.Keybind.ResolveKey("ActionAutoClickerKeybind", "G")
end

State.Keybind.GetName = State.Keybind.GetName or function(flag, fallback)
    if State.Keybind and State.Keybind.ResolveKey then
        local _, keyName = State.Keybind.ResolveKey(flag, fallback)
        if keyName then
            return tostring(keyName)
        end
    end
    return fallback or ""
end

local function getHideKeyName()
    if State.Keybind and State.Keybind.GetName then
        return State.Keybind.GetName("HideKeybind", "K")
    end
    return "K"
end

local function getAutoBuyLogKeyName()
    if State.Keybind and State.Keybind.GetName then
        return State.Keybind.GetName("AutoBuyLogKeybind", "[")
    end
    return "["
end

local function getActionAutoClickerKeyName()
    if State.Keybind and State.Keybind.GetName then
        return State.Keybind.GetName("ActionAutoClickerKeybind", "G")
    end
    return "G"
end

State.Keybind.Definitions = State.Keybind.Definitions or {
    {Flag = "HideKeybind", Default = "K", Label = "Hide UI"},
    {Flag = "AutoBuyLogKeybind", Default = "[", Label = "Auto Buy Log"},
    {Flag = "ActionAutoClickerKeybind", Default = "G", Label = "Auto Clicker"}
}

State.Keybind.GetLabel = State.Keybind.GetLabel or function(flag, fallback)
    for _, item in ipairs(State.Keybind.Definitions or {}) do
        if item.Flag == flag then
            return item.Label or fallback or flag
        end
    end
    return fallback or flag
end

State.Keybind.FindConflict = State.Keybind.FindConflict or function(flag, value)
    local normalized = State.Keybind.Normalize(value)
    if not normalized then
        return nil
    end
    for _, item in ipairs(State.Keybind.Definitions or {}) do
        if item.Flag ~= flag then
            local otherName = State.Keybind.GetName(item.Flag, item.Default)
            local otherNormalized = State.Keybind.Normalize(otherName)
            if otherNormalized == normalized then
                return item
            end
        end
    end
    return nil
end

State.Keybind.AssignUnique = State.Keybind.AssignUnique or function(flag, value, defaultName)
    local normalized = State.Keybind.Normalize(value)
    if not normalized then
        return false, nil, "invalid", nil
    end
    local conflict = State.Keybind.FindConflict(flag, normalized)
    if conflict then
        return false, normalized, "conflict", conflict
    end
    if State.Config and State.Config.Set then
        State.Config.Set(flag, normalized)
    else
        Config[flag] = normalized
        saveConfig()
    end
    return true, normalized, nil, nil
end

if Config.FirstRun then
    Config.NoFog = false
    Config.NoFX = false
    Config.LowGraphics = false
    Config.FullBright = false
    Config.FirstRun = false
    saveConfig()
end

setGlobalClickCooldown("AutoBuyGlobal", Config.AutoBuyClickSpeed)

-- =====================================================
-- AUTO RELOAD ON TELEPORT/RECONNECT
-- =====================================================
local function trimText(v)
    if type(v) ~= "string" then
        return ""
    end
    return (v:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readAutoReloadFile(pathValue)
    local path = trimText(pathValue)
    if #path == 0 then
        return nil, "missing"
    end
    if not readfile then
        return nil, "file_no_read"
    end
    if isfile and not isfile(path) then
        return nil, "file_missing"
    end
    local ok, data = pcall(readfile, path)
    if ok and type(data) == "string" and #data > 0 then
        return data, nil
    end
    return nil, "file_read_fail"
end

local function resolveAutoReloadSource()
    if ENV then
        local src = trimText(ENV.GardenIncremental_Source)
        if #src > 0 then
            return src, nil
        end
        local url = trimText(ENV.GardenIncremental_Url)
        if #url > 0 then
            return ("loadstring(game:HttpGet(%q))()"):format(url), nil
        end
        local fileSrc, fileErr = readAutoReloadFile(ENV.GardenIncremental_File)
        if fileSrc then
            return fileSrc, nil
        elseif fileErr and fileErr ~= "missing" then
            return nil, fileErr
        end
    end

    local cfgSrc = trimText(Config.AutoReloadSource)
    if #cfgSrc > 0 then
        return cfgSrc, nil
    end
    local cfgUrl = trimText(Config.AutoReloadUrl)
    if #cfgUrl > 0 then
        return ("loadstring(game:HttpGet(%q))()"):format(cfgUrl), nil
    end
    local cfgFileSrc, cfgFileErr = readAutoReloadFile(Config.AutoReloadFile)
    if cfgFileSrc then
        return cfgFileSrc, nil
    elseif cfgFileErr and cfgFileErr ~= "missing" then
        return nil, cfgFileErr
    end

    return nil, "missing"
end

local function queueOnTeleport(code)
    if type(code) ~= "string" or #code == 0 then
        return false
    end
    local q = queue_on_teleport
        or queueonteleport
        or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
    if type(q) ~= "function" then
        return false
    end
    local ok = pcall(q, code)
    return ok == true
end

local function applyAutoReloadQueue()
    if not Config.AutoReloadEnabled then
        return false, "disabled"
    end
    local src, reason = resolveAutoReloadSource()
    if not src then
        return false, reason or "missing"
    end
    local ok = queueOnTeleport(src)
    return ok == true, ok and "queued" or "noqueue"
end

if Config.AutoReloadEnabled then
    local ok, reason = applyAutoReloadQueue()
    if not ok then
        if reason == "missing" then
            warn("[GardenIncremental] AutoReloadEnabled=true tapi sumber script belum diset.")
        elseif reason == "noqueue" then
            warn("[GardenIncremental] queue_on_teleport tidak tersedia.")
        elseif reason == "file_missing" then
            warn("[GardenIncremental] AutoReloadFile tidak ditemukan.")
        elseif reason == "file_no_read" then
            warn("[GardenIncremental] readfile tidak tersedia.")
        elseif reason == "file_read_fail" then
            warn("[GardenIncremental] gagal membaca AutoReloadFile.")
        end
    end
end

-- =====================================================
-- THEME SYSTEM
-- =====================================================
local Themes = {
    Default = {
        Main = Color3.fromRGB(30, 30, 36),
        Panel = Color3.fromRGB(40, 40, 48),
        Accent = Color3.fromRGB(0, 170, 255),
        Text = Color3.fromRGB(235, 235, 235),
        Muted = Color3.fromRGB(170, 170, 170),
        Skip = Color3.fromRGB(90, 50, 50)
    },
    Dark = {
        Main = Color3.fromRGB(20, 20, 24),
        Panel = Color3.fromRGB(32, 32, 40),
        Accent = Color3.fromRGB(255, 120, 0),
        Text = Color3.fromRGB(235, 235, 235),
        Muted = Color3.fromRGB(150, 150, 150),
        Skip = Color3.fromRGB(85, 45, 45)
    },
    Light = {
        Main = Color3.fromRGB(235, 235, 235),
        Panel = Color3.fromRGB(250, 250, 250),
        Accent = Color3.fromRGB(0, 120, 255),
        Text = Color3.fromRGB(35, 35, 35),
        Muted = Color3.fromRGB(90, 90, 90),
        Skip = Color3.fromRGB(255, 215, 215)
    },
    Ocean = {
        Main = Color3.fromRGB(16, 26, 36),
        Panel = Color3.fromRGB(22, 36, 48),
        Accent = Color3.fromRGB(0, 200, 200),
        Text = Color3.fromRGB(220, 240, 245),
        Muted = Color3.fromRGB(140, 170, 180),
        Skip = Color3.fromRGB(90, 55, 60)
    },
    Mint = {
        Main = Color3.fromRGB(20, 28, 28),
        Panel = Color3.fromRGB(28, 40, 40),
        Accent = Color3.fromRGB(64, 220, 180),
        Text = Color3.fromRGB(235, 245, 242),
        Muted = Color3.fromRGB(160, 190, 185),
        Skip = Color3.fromRGB(95, 55, 55)
    },
    Sunset = {
        Main = Color3.fromRGB(28, 22, 30),
        Panel = Color3.fromRGB(40, 30, 44),
        Accent = Color3.fromRGB(255, 120, 90),
        Text = Color3.fromRGB(240, 230, 240),
        Muted = Color3.fromRGB(170, 155, 180),
        Skip = Color3.fromRGB(110, 60, 60)
    },
    Aurora = {
        Main = Color3.fromRGB(18, 24, 36),
        Panel = Color3.fromRGB(26, 34, 52),
        Accent = Color3.fromRGB(120, 190, 255),
        Text = Color3.fromRGB(230, 238, 245),
        Muted = Color3.fromRGB(150, 165, 185),
        Skip = Color3.fromRGB(90, 55, 60)
    }
}

local ThemeRegistry = {}
local function compactThemeRegistry(force)
    local total = #ThemeRegistry
    if total == 0 then
        return 0
    end
    if not force and total < 600 then
        return total
    end
    local nextRegistry = {}
    for i = 1, total do
        local item = ThemeRegistry[i]
        if item and item.inst and item.inst.Parent then
            nextRegistry[#nextRegistry + 1] = item
        end
    end
    ThemeRegistry = nextRegistry
    return #ThemeRegistry
end

local function getTheme(name)
    return Themes[name] or Themes.Default
end

local function applyThemeToItem(item, theme)
    if item and item.inst and item.inst.Parent then
        item.inst[item.prop] = theme[item.role]
    end
end

local function registerTheme(inst, prop, role)
    if not inst or type(prop) ~= "string" or type(role) ~= "string" then
        return
    end
    local item = {inst = inst, prop = prop, role = role}
    ThemeRegistry[#ThemeRegistry + 1] = item
    if (#ThemeRegistry % 300) == 0 then
        compactThemeRegistry(false)
    end
    applyThemeToItem(item, getTheme(Config.Theme))
end

local function setFontClass(inst, className)
    if not inst then
        return
    end
    inst:SetAttribute("FontClass", className)
    if State.Fonts and State.Fonts.ApplyClass then
        State.Fonts.ApplyClass(inst)
    end
end

local ToggleRenders = {}
local TabButtons = {}
local ActiveTabButton
local NamecallLogHandler
local getMainRemote
local setRemoteHooking
local confirmDialog
local TeleportButtons = {}
local ActiveTeleportButton

local function applyTheme(name)
    compactThemeRegistry(true)
    local t = getTheme(name)
    for _, item in ipairs(ThemeRegistry) do
        applyThemeToItem(item, t)
    end
    for _, render in ipairs(ToggleRenders) do
        pcall(render)
    end
    for _, btn in ipairs(TabButtons) do
        if btn and btn.Parent then
            local indicator = btn:FindFirstChild("ActiveIndicator")
            if btn == ActiveTabButton then
                btn.BackgroundColor3 = t.Panel
                btn.TextColor3 = t.Text
                if indicator then
                    indicator.BackgroundColor3 = t.Accent
                    indicator.Visible = true
                end
            else
                btn.BackgroundColor3 = t.Main
                btn.TextColor3 = t.Muted
                if indicator then
                    indicator.Visible = false
                end
            end
        end
    end
    for _, btn in ipairs(TeleportButtons) do
        if btn and btn.Parent then
            if btn == ActiveTeleportButton then
                btn.BackgroundColor3 = t.Accent
                btn.TextColor3 = Color3.new(1, 1, 1)
            else
                btn.BackgroundColor3 = t.Main
                btn.TextColor3 = t.Text
            end
        end
    end
    if State.Fonts and State.Fonts.Apply then
        State.Fonts.Apply()
    end
end

State.Fonts = State.Fonts or {}
State.Fonts.ResolveEnum = State.Fonts.ResolveEnum or function(name, fallback)
    if type(name) ~= "string" or #name == 0 then
        return fallback or Enum.Font.Gotham
    end
    local ok, font = pcall(function()
        return Enum.Font[name]
    end)
    if ok and font then
        return font
    end
    local okItems, items = pcall(function()
        return Enum.Font:GetEnumItems()
    end)
    if okItems and type(items) == "table" then
        for _, item in ipairs(items) do
            if item and item.Name == name then
                return item
            end
        end
    end
    return fallback or Enum.Font.Gotham
end
State.Fonts.Families = State.Fonts.Families or {
    ChakraPetch = {
        Regular = State.Fonts.ResolveEnum("ChakraPetch", Enum.Font.Gotham),
        Semibold = State.Fonts.ResolveEnum("ChakraPetch", Enum.Font.GothamSemibold),
        Medium = State.Fonts.ResolveEnum("ChakraPetch", Enum.Font.GothamMedium)
    },
    Cinzel = {
        Regular = State.Fonts.ResolveEnum("Cinzel", Enum.Font.Gotham),
        Semibold = State.Fonts.ResolveEnum("Cinzel", Enum.Font.GothamSemibold),
        Medium = State.Fonts.ResolveEnum("Cinzel", Enum.Font.GothamMedium)
    },
    Gotham = {
        Regular = Enum.Font.Gotham,
        Semibold = Enum.Font.GothamSemibold,
        Medium = Enum.Font.GothamMedium
    },
    SourceSans = {
        Regular = Enum.Font.SourceSans,
        Semibold = Enum.Font.SourceSansSemibold,
        Medium = Enum.Font.SourceSans
    },
    Arial = {
        Regular = Enum.Font.Arial,
        Semibold = Enum.Font.ArialBold,
        Medium = Enum.Font.Arial
    },
    Code = {
        Regular = Enum.Font.Code,
        Semibold = Enum.Font.Code,
        Medium = Enum.Font.Code
    },
    Roboto = {
        Regular = Enum.Font.Roboto,
        Semibold = Enum.Font.Roboto,
        Medium = Enum.Font.Roboto
    },
    RobotoMono = {
        Regular = Enum.Font.RobotoMono,
        Semibold = Enum.Font.RobotoMono,
        Medium = Enum.Font.RobotoMono
    },
    Montserrat = {
        Regular = Enum.Font.Montserrat,
        Semibold = Enum.Font.Montserrat,
        Medium = Enum.Font.Montserrat
    },
    Oswald = {
        Regular = Enum.Font.Oswald,
        Semibold = Enum.Font.Oswald,
        Medium = Enum.Font.Oswald
    },
    TitilliumWeb = {
        Regular = Enum.Font.TitilliumWeb,
        Semibold = Enum.Font.TitilliumWeb,
        Medium = Enum.Font.TitilliumWeb
    },
    Ubuntu = {
        Regular = Enum.Font.Ubuntu,
        Semibold = Enum.Font.Ubuntu,
        Medium = Enum.Font.Ubuntu
    },
    Nunito = {
        Regular = Enum.Font.Nunito,
        Semibold = Enum.Font.Nunito,
        Medium = Enum.Font.Nunito
    }
}

State.Fonts.Classes = State.Fonts.Classes or {
    Title = 16,
    Heading = 13,
    Subheading = 11,
    Body = 12,
    Small = 11,
    Tiny = 10,
    Button = 12,
    Nav = 13,
    Mono = 11
}

State.Fonts.Resolve = State.Fonts.Resolve or function(role)
    local name = Config.Font or "ChakraPetch"
    local family = State.Fonts.Families and State.Fonts.Families[name] or nil
    if not family then
        family = State.Fonts.Families and State.Fonts.Families.Gotham or nil
    end
    if not family then
        return Enum.Font.Gotham
    end
    return family[role or "Regular"] or family.Regular or Enum.Font.Gotham
end

State.Fonts.ApplyToRoot = State.Fonts.ApplyToRoot or function(root)
    if not root then
        return
    end
    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            if inst:GetAttribute("FontLock") ~= true then
                local role = inst:GetAttribute("FontRole")
                if not role then
                    role = "Regular"
                    if inst.Font == Enum.Font.GothamSemibold or inst.Font == Enum.Font.SourceSansSemibold or inst.Font == Enum.Font.ArialBold then
                        role = "Semibold"
                    elseif inst.Font == Enum.Font.GothamMedium then
                        role = "Medium"
                    end
                    inst:SetAttribute("FontRole", role)
                end
                inst.Font = State.Fonts.Resolve(role)
            end
            if inst:GetAttribute("FontClass") then
                State.Fonts.ApplyClass(inst)
            end
        end
    end
end

State.Fonts.ResolveSize = State.Fonts.ResolveSize or function(className)
    local base = (State.Fonts.Classes and State.Fonts.Classes[className]) or (State.Fonts.Classes and State.Fonts.Classes.Body) or 12
    local scale = tonumber(Config.FontScale) or 1
    scale = math.clamp(scale, 0.7, 1.5)
    return math.max(8, math.floor(base * scale + 0.5))
end

State.Fonts.ApplyClass = State.Fonts.ApplyClass or function(inst)
    if not inst or (not inst:IsA("TextLabel") and not inst:IsA("TextButton") and not inst:IsA("TextBox")) then
        return
    end
    if inst:GetAttribute("FontSizeLock") == true then
        return
    end
    local cls = inst:GetAttribute("FontClass")
    if cls then
        inst.TextSize = State.Fonts.ResolveSize(cls)
    end
end

State.Fonts.Apply = State.Fonts.Apply or function()
    State.Fonts.ApplyToRoot(State.ScreenGui)
    State.Fonts.ApplyToRoot(State.AutoBuyLogGui)
end

-- =====================================================
-- UI ROOT
-- =====================================================
pcall(function()
    local cg = game:GetService("CoreGui")
    local oldGui = cg:FindFirstChild("GardenIncrementalUI")
    if oldGui then
        oldGui:Destroy()
    end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GardenIncrementalUI"
ScreenGui.ResetOnSpawn = false

if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = game:GetService("CoreGui")
end
State.ScreenGui = ScreenGui

local function addCorner(inst, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 6)
    corner.Parent = inst
    return corner
end

local function addStroke(inst, role, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0.55
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = inst
    if role then
        registerTheme(stroke, "Color", role)
    end
    return stroke
end

local function addGradient(inst, rotation, alphaStart, alphaEnd)
    local grad = Instance.new("UIGradient")
    grad.Rotation = rotation or 90
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, alphaStart or 0),
        NumberSequenceKeypoint.new(1, alphaEnd or 0.25)
    })
    grad.Parent = inst
    return grad
end

-- =====================================================
-- UI SYSTEM
-- =====================================================
State.UI = State.UI or {}
State.UI.IconAssets = State.UI.IconAssets or {
    ArrowRight = "rbxassetid://12338895277",
    ArrowDown = "rbxassetid://12338898398",
    ArrowLeft = "rbxassetid://12338896667",
    ArrowUp = "rbxassetid://12338897538"
}
State.UI.GetHeaderButtonSize = State.UI.GetHeaderButtonSize or function(tokens)
    local t = tokens or (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {}
    local btnW = math.max(18, (t.ButtonW or 24) - 4)
    local btnH = math.max(16, (t.ButtonH or 20) - 2)
    return btnW, btnH
end
State.UI.GetAnimScale = State.UI.GetAnimScale or function(frame)
    if not frame then
        return nil
    end
    local scale = frame:FindFirstChild("AnimScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "AnimScale"
        scale.Scale = 1
        scale.Parent = frame
    end
    return scale
end
State.UI.AnimateShow = State.UI.AnimateShow or function(frame, opts)
    if not frame then
        return nil
    end
    local duration = (opts and opts.Duration) or 0.16
    local startScale = (opts and opts.StartScale) or 0.95
    local scale = State.UI.GetAnimScale(frame)
    frame.Visible = true
    if scale then
        scale.Scale = startScale
        local tween = TweenService:Create(
            scale,
            TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Scale = 1}
        )
        tween:Play()
        return tween
    end
    return nil
end
State.UI.AnimateHide = State.UI.AnimateHide or function(frame, opts)
    if not frame then
        return nil
    end
    local duration = (opts and opts.Duration) or 0.12
    local endScale = (opts and opts.EndScale) or 0.95
    local scale = State.UI.GetAnimScale(frame)
    if scale then
        local tween = TweenService:Create(
            scale,
            TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Scale = endScale}
        )
        tween:Play()
        tween.Completed:Connect(function()
            if frame and frame.Parent then
                frame.Visible = false
            end
        end)
        return tween
    end
    frame.Visible = false
    return nil
end
State.UI.BindFrameDrag = State.UI.BindFrameDrag or function(handle, frame, dragState, opts)
    if not handle or not frame or not dragState then
        return
    end
    local blockIf = opts and opts.BlockIf
    local onBegin = opts and opts.OnBegin
    local onChanged = opts and opts.OnChanged
    local onEnd = opts and opts.OnEnd
    trackConnection(handle.InputBegan:Connect(function(input)
        if not (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            return
        end
        if blockIf and blockIf() then
            return
        end
        dragState.Dragging = true
        dragState.DragStart = input.Position
        dragState.StartPos = frame.Position
        if onBegin then
            onBegin(input)
        end
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragState.Dragging = false
                if onEnd then
                    onEnd(input)
                end
            end
        end)
    end))
    trackConnection(UIS.InputChanged:Connect(function(input)
        if not dragState.Dragging then
            return
        end
        if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            return
        end
        local delta = input.Position - dragState.DragStart
        frame.Position = UDim2.new(
            dragState.StartPos.X.Scale,
            dragState.StartPos.X.Offset + delta.X,
            dragState.StartPos.Y.Scale,
            dragState.StartPos.Y.Offset + delta.Y
        )
        if onChanged then
            onChanged(delta, input)
        end
    end))
end
State.UI.BindFrameResizeBottomRight = State.UI.BindFrameResizeBottomRight or function(handle, frame, resizeState, opts)
    if not handle or not frame or not resizeState then
        return
    end
    local minW = (opts and opts.MinW) or 180
    local maxW = (opts and opts.MaxW) or 520
    local minH = (opts and opts.MinH) or 140
    local maxH = (opts and opts.MaxH) or 700
    local onChanged = opts and opts.OnChanged
    local onEnd = opts and opts.OnEnd
    trackConnection(handle.InputBegan:Connect(function(input)
        if not (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            return
        end
        resizeState.Resizing = true
        resizeState.ResizeStart = input.Position
        resizeState.ResizeStartSize = frame.Size
        if resizeState.Dragging ~= nil then
            resizeState.Dragging = false
        end
    end))
    trackConnection(UIS.InputChanged:Connect(function(input)
        if not resizeState.Resizing then
            return
        end
        if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            return
        end
        local delta = input.Position - (resizeState.ResizeStart or input.Position)
        local base = resizeState.ResizeStartSize or frame.Size
        local newW = math.clamp((base.X.Offset or minW) + delta.X, minW, maxW)
        local newH = math.clamp((base.Y.Offset or minH) + delta.Y, minH, maxH)
        frame.Size = UDim2.new(0, math.floor(newW + 0.5), 0, math.floor(newH + 0.5))
        if onChanged then
            onChanged(frame, newW, newH, input)
        end
    end))
    trackConnection(UIS.InputEnded:Connect(function(input)
        if not (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            return
        end
        if not resizeState.Resizing then
            return
        end
        resizeState.Resizing = false
        resizeState.ResizeStart = nil
        resizeState.ResizeStartSize = nil
        if onEnd then
            onEnd(frame, input)
        end
    end))
end
State.UI.BuildHeader = State.UI.BuildHeader or function(parent, opts)
    local t = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {}
    local title = opts and opts.Title or "DMSAP-HUB"
    local logo = opts and opts.Logo or nil

    local headerBar = Instance.new("Frame")
    headerBar.Size = UDim2.new(1, 0, 0, t.HeaderH or 32)
    headerBar.Position = UDim2.new(0, 0, 0, 0)
    headerBar.BorderSizePixel = 0
    headerBar.Parent = parent
    registerTheme(headerBar, "BackgroundColor3", "Panel")
    addCorner(headerBar, t.RadiusLg or 10)

    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(1, 0, 0, t.AccentH or 2)
    accentLine.Position = UDim2.new(0, 0, 0, (t.HeaderH or 32) - (t.AccentH or 2))
    accentLine.BorderSizePixel = 0
    accentLine.Parent = headerBar
    registerTheme(accentLine, "BackgroundColor3", "Accent")

    local headerPadX = t.TitlePadX or 12
    local dragFrame = Instance.new("Frame")
    dragFrame.Size = UDim2.new(1, -((t.ButtonW or 24) * 3 + (t.ButtonGap or 6) * 2 + headerPadX * 2), 0, t.HeaderH or 32)
    dragFrame.Position = UDim2.new(0, headerPadX, 0, 0)
    dragFrame.BackgroundTransparency = 1
    dragFrame.Parent = headerBar
    dragFrame.Active = true

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 0)
    pad.PaddingRight = UDim.new(0, 0)
    pad.Parent = dragFrame

    local iconSize = math.max(16, (t.HeaderH or 32) - ((t.TitlePadY or 6) * 2))
    local logoImg = Instance.new("ImageLabel")
    logoImg.Size = UDim2.new(0, iconSize, 0, iconSize)
    logoImg.Position = UDim2.new(0, 0, 0.5, -math.floor(iconSize / 2))
    logoImg.BackgroundTransparency = 1
    logoImg.BorderSizePixel = 0
    if logo then
        logoImg.Image = logo
    end
    logoImg.ScaleType = Enum.ScaleType.Fit
    logoImg.Parent = dragFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -(iconSize + (t.ContentGap or 8)), 1, 0)
    titleLabel.Position = UDim2.new(0, iconSize + (t.ContentGap or 8), 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.Font = Enum.Font.SourceSansSemibold
    titleLabel.TextSize = 16
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextYAlignment = Enum.TextYAlignment.Center
    titleLabel.Parent = dragFrame
    titleLabel:SetAttribute("FontLock", true)
    setFontClass(titleLabel, "Title")
    registerTheme(titleLabel, "TextColor3", "Text")

    return {
        Bar = headerBar,
        DragFrame = dragFrame,
        Logo = logoImg,
        Title = titleLabel,
        AccentLine = accentLine
    }
end

State.UI.BuildFooter = State.UI.BuildFooter or function(parent, opts)
    local t = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {}
    local text = opts and opts.Text or "DC: daproduction.gg"

    local footerBar = Instance.new("Frame")
    footerBar.Size = UDim2.new(1, 0, 0, t.FooterH or 32)
    footerBar.Position = UDim2.new(0, 0, 1, -(t.FooterH or 32))
    footerBar.BorderSizePixel = 0
    footerBar.Parent = parent
    registerTheme(footerBar, "BackgroundColor3", "Panel")
    addCorner(footerBar, t.RadiusLg or 10)

    local topLine = Instance.new("Frame")
    topLine.Size = UDim2.new(1, 0, 0, t.AccentH or 2)
    topLine.Position = UDim2.new(0, 0, 0, 0)
    topLine.BorderSizePixel = 0
    topLine.Parent = footerBar
    registerTheme(topLine, "BackgroundColor3", "Accent")

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, math.max(1, (t.InputPadSm or 4) - 2))
    pad.PaddingBottom = UDim.new(0, math.max(1, (t.InputPadSm or 4) - 2))
    pad.Parent = footerBar

    local credit = Instance.new("TextLabel")
    credit.Size = UDim2.new(1, -((t.TitlePadX or 12) * 3), 1, 0)
    credit.Position = UDim2.new(0, t.TitlePadX or 12, 0, 0)
    credit.BackgroundTransparency = 1
    credit.Font = Enum.Font.SourceSans
    credit.TextSize = 12
    credit.TextXAlignment = Enum.TextXAlignment.Left
    credit.TextYAlignment = Enum.TextYAlignment.Center
    credit.Text = text
    credit.Parent = footerBar
    credit:SetAttribute("FontLock", true)
    setFontClass(credit, "Small")
    registerTheme(credit, "TextColor3", "Muted")

    return {
        Bar = footerBar,
        TopLine = topLine,
        Credit = credit
    }
end

local function createLoadingUI()
    local buildStamp = os.date("%Y-%m-%d %H:%M:%S")
    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, 320, 0, 150)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.new(0.5, 0, 0.5, 0)
    card.BorderSizePixel = 0
    card.ZIndex = 101
    card.Parent = ScreenGui
    registerTheme(card, "BackgroundColor3", "Panel")
    addCorner(card, 10)
    addStroke(card, "Muted", 1, 0.7)
    local scale = Instance.new("UIScale")
    scale.Parent = card

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 24)
    title.Position = UDim2.new(0, 10, 0, 10)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamSemibold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Loading UI..."
    title.ZIndex = 102
    title.Parent = card
    setFontClass(title, "Heading")
    registerTheme(title, "TextColor3", "Text")

    local percentLabel = Instance.new("TextLabel")
    percentLabel.Size = UDim2.new(0, 60, 0, 20)
    percentLabel.Position = UDim2.new(1, -70, 0, 12)
    percentLabel.BackgroundTransparency = 1
    percentLabel.Font = Enum.Font.Gotham
    percentLabel.TextSize = 12
    percentLabel.TextXAlignment = Enum.TextXAlignment.Right
    percentLabel.Text = "0%"
    percentLabel.ZIndex = 102
    percentLabel.Parent = card
    setFontClass(percentLabel, "Small")
    registerTheme(percentLabel, "TextColor3", "Muted")

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, -20, 0, 10)
    barBg.Position = UDim2.new(0, 10, 0, 52)
    barBg.BorderSizePixel = 0
    barBg.ZIndex = 102
    barBg.Parent = card
    registerTheme(barBg, "BackgroundColor3", "Main")
    addCorner(barBg, 6)

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(0, 0, 1, 0)
    barFill.BorderSizePixel = 0
    barFill.ZIndex = 103
    barFill.Parent = barBg
    registerTheme(barFill, "BackgroundColor3", "Accent")
    addCorner(barFill, 6)

    local note = Instance.new("TextLabel")
    note.Size = UDim2.new(1, -20, 0, 30)
    note.Position = UDim2.new(0, 10, 0, 74)
    note.BackgroundTransparency = 1
    note.Font = Enum.Font.Gotham
    note.TextSize = 12
    note.TextXAlignment = Enum.TextXAlignment.Left
    note.TextWrapped = true
    note.Text = "Menyiapkan modul UI..."
    note.ZIndex = 102
    note.Parent = card
    setFontClass(note, "Small")
    registerTheme(note, "TextColor3", "Muted")

    local footerDivider = Instance.new("Frame")
    footerDivider.Size = UDim2.new(1, -20, 0, 2)
    footerDivider.Position = UDim2.new(0, 10, 1, -28)
    footerDivider.BorderSizePixel = 0
    footerDivider.ZIndex = 102
    footerDivider.Parent = card
    registerTheme(footerDivider, "BackgroundColor3", "Accent")

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, -20, 0, 18)
    footer.Position = UDim2.new(0, 10, 1, -24)
    footer.BackgroundTransparency = 1
    footer.Font = Enum.Font.Gotham
    footer.TextSize = 11
    footer.TextXAlignment = Enum.TextXAlignment.Left
    footer.Text = "Versi " .. tostring(State.Version) .. " - " .. tostring(buildStamp)
    footer.ZIndex = 102
    footer.Parent = card
    setFontClass(footer, "Small")
    registerTheme(footer, "TextColor3", "Muted")

    local percentValue = Instance.new("NumberValue")
    percentValue.Value = 0
    local activeTween = nil

    percentValue.Changed:Connect(function(v)
        local raw = math.clamp(tonumber(v) or 0, 0, 100)
        local clamped = math.clamp(math.floor(raw + 0.5), 0, 100)
        percentLabel.Text = tostring(clamped) .. "%"
        barFill.Size = UDim2.new(raw / 100, 0, 1, 0)
    end)

    return {
        Card = card,
        Scale = scale,
        Set = function(_, percent, text)
            local target = math.clamp(tonumber(percent) or 0, 0, 100)
            if text then
                note.Text = text
            end
            if activeTween then
                activeTween:Cancel()
                activeTween = nil
            end
            local delta = math.abs(target - percentValue.Value)
            if delta <= 0.05 then
                percentValue.Value = target
                return
            end
            local duration = math.clamp(delta / 100, 0.08, 0.5)
            activeTween = TweenService:Create(
                percentValue,
                TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Value = target}
            )
            activeTween:Play()
        end
    }
end

local LoadingUI = createLoadingUI()
LoadingUI:Set(2, "Menyiapkan tema...")
applyTheme(Config.Theme or "Default")

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, Config.WindowWidth or 640, 0, Config.WindowHeight or 430)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui
Main.Visible = false
Main.ClipsDescendants = true
registerTheme(Main, "BackgroundColor3", "Main")
addCorner(Main, 10)
addStroke(Main, "Muted", 1, 0.6)
addGradient(Main, 90, 0, 0.15)

local function computeUIScale()
    local cam = workspace.CurrentCamera
    if not cam then return 1 end
    local vp = cam.ViewportSize
    if not vp or vp.X <= 0 or vp.Y <= 0 then return 1 end
    local baseW, baseH = 1280, 720
    local scale = math.min(vp.X / baseW, vp.Y / baseH)
    return math.clamp(scale, 0.65, 1.15)
end

-- =====================================================
-- LAYOUT / SCALE
-- =====================================================
State.Layout = State.Layout or {}
State.Layout.RefreshTokens = State.Layout.RefreshTokens or function()
    local scale = 1
    local function px(v)
        return math.max(1, math.floor(v * scale + 0.5))
    end
    local absW = 640
    local absH = 430
    if Main and Main.AbsoluteSize then
        absW = Main.AbsoluteSize.X
        absH = Main.AbsoluteSize.Y
    end
    local tabW = math.clamp(math.floor(absW * 0.22), 140, 220)
    State.Layout.Tokens = {
        Scale = scale,
        HeaderH = px(32),
        FooterH = px(32),
        TitlePadX = px(12),
        TitlePadY = px(6),
        RowPadX = px(10),
        RowPadY = px(4),
        ContentGap = px(8),
        ToggleRadius = px(6),
        ToggleTextSize = px(9),
        ToggleTextBold = true,
        ToggleWidthScale = 1.5,
        ButtonW = px(24),
        ButtonH = px(20),
        ButtonGap = px(6),
        AccentH = px(2),
        BodyTop = px(32),
        BodyBottom = px(24),
        TabW = tabW,
        TabMin = px(140),
        TabMax = px(220),
        TabPadding = px(8),
        TabGap = px(6),
        RowH = px(30),
        RowTall = px(44),
        SliderChevronW = px(22),
        SliderChevronH = px(22),
        SliderChevronRadius = px(6),
        LabelMin = px(120),
        LabelMax = px(200),
        InputPad = px(6),
        InputPadSm = px(4),
        SliderBarH = px(8),
        SliderBarPadX = px(10),
        SliderBarTop = px(26),
        SectionPad = px(12),
        SectionGap = px(8),
        RadiusSm = px(6),
        Radius = px(8),
        RadiusLg = px(10)
    }
    return State.Layout.Tokens
end
State.Layout.GetTokens = State.Layout.GetTokens or function()
    if not State.Layout or not State.Layout.Tokens then
        return State.Layout.RefreshTokens()
    end
    return State.Layout.Tokens
end

local MainScale = Instance.new("UIScale")
MainScale.Scale = computeUIScale()
MainScale.Parent = Main
State.Layout.RefreshTokens()

if LoadingUI.Scale then
    LoadingUI.Scale.Scale = MainScale.Scale
end

trackConnection(RunService.RenderStepped:Connect(function()
    local newScale = computeUIScale()
    if math.abs(newScale - MainScale.Scale) > 0.01 then
        MainScale.Scale = newScale
        if LoadingUI.Scale then
            LoadingUI.Scale.Scale = newScale
        end
        if State.Layout and State.Layout.RefreshTokens then
            State.Layout.RefreshTokens()
        end
        if State.GridTextScaleApply then
            State.GridTextScaleApply(newScale)
        end
    end
    if State.Layout then
        local cam = workspace.CurrentCamera
        if cam then
            local vp = cam.ViewportSize
            local last = State.Layout.LastViewport
            if vp and (not last or last.X ~= vp.X or last.Y ~= vp.Y) then
                State.Layout.LastViewport = Vector2.new(vp.X, vp.Y)
                if State.MainLayout and State.MainLayout.Apply then
                    State.MainLayout.Apply()
                end
                if State.LogLayout and State.LogLayout.Apply then
                    State.LogLayout.Apply()
                end
                if State.Notify and State.Notify.UpdateLayout then
                    State.Notify.UpdateLayout()
                end
            end
        end
    end
end))

trackConnection(Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    if State.Layout and State.Layout.RefreshTokens then
        State.Layout.RefreshTokens()
    end
    if State.MainLayout and State.MainLayout.ApplyLayout then
        State.MainLayout.ApplyLayout()
    end
end))

local HeaderUI, HeaderBar, TitleBar, HeaderLogo, HeaderTitle, AccentLine
local FooterUI, FooterBar, FooterTopLine, FooterCredit
local VersionLabel, MinimizedIcon, Body, TabBar, Pages
local WindowControls, DockBtn, HideBtn, CloseBtn, ResizeBottomRight
local ResizeHandles, TabBarConstraint, TabList, TabPadding
local Minimized, Dragging, DragMoved, DragStart, StartPos, SavedSize, SavedPos, UIHidden
local setMinimized, setHidden, toggleHidden
local toggleAutoBuyLogKeybind, toggleActionAutoClickerKeybind
local function buildMainUI()
HeaderUI = State.UI.BuildHeader(Main, {Title = "DMSAP-HUB", Logo = resolveHeaderLogo()})
HeaderBar = HeaderUI.Bar
TitleBar = HeaderUI.DragFrame
HeaderLogo = HeaderUI.Logo
HeaderTitle = HeaderUI.Title
AccentLine = HeaderUI.AccentLine

FooterUI = State.UI.BuildFooter(Main, {Text = "DC: daproduction.gg"})
FooterBar = FooterUI.Bar
FooterTopLine = FooterUI.TopLine
FooterCredit = FooterUI.Credit

VersionLabel = Instance.new("TextLabel")
  VersionLabel.Size = UDim2.new(0, State.Layout.Tokens.LabelMin, 0, math.max(12, State.Layout.Tokens.RowH - State.Layout.Tokens.InputPad))
  VersionLabel.AnchorPoint = Vector2.new(0, 0.5)
  do
      local btnW = (State.UI and State.UI.GetHeaderButtonSize and select(1, State.UI.GetHeaderButtonSize(State.Layout.Tokens))) or (State.Layout.Tokens.ButtonW or 24)
      local gap = State.Layout.Tokens.ButtonGap or 6
      local padX = State.Layout.Tokens.TitlePadX or 12
      VersionLabel.Position = UDim2.new(
          1,
          -(State.Layout.Tokens.LabelMin + btnW * 3 + gap * 2 + padX + gap),
          0,
          math.floor(State.Layout.Tokens.HeaderH * 0.5)
      )
  end
VersionLabel.BackgroundTransparency = 1
VersionLabel.Font = Enum.Font.Gotham
VersionLabel.TextSize = 12
VersionLabel.TextXAlignment = Enum.TextXAlignment.Right
VersionLabel.Text = State.Version
VersionLabel.Parent = Main
VersionLabel.Active = true
registerTheme(VersionLabel, "TextColor3", "Muted")
State.ValidateVersion(VersionLabel.Text)

FooterCredit.TextSize = VersionLabel.TextSize


MinimizedIcon = Instance.new("ImageButton")
MinimizedIcon.Size = UDim2.new(1, 0, 1, 0)
MinimizedIcon.Position = UDim2.new(0, 0, 0, 0)
MinimizedIcon.BorderSizePixel = 0
MinimizedIcon.AutoButtonColor = false
MinimizedIcon.Active = true
MinimizedIcon.Visible = false
MinimizedIcon.Parent = Main
registerTheme(MinimizedIcon, "BackgroundColor3", "Panel")
MinimizedIcon.Image = ""
MinimizedIcon.ScaleType = Enum.ScaleType.Fit
MinimizedIcon.ImageTransparency = 0
addCorner(MinimizedIcon, 10)
addStroke(MinimizedIcon, "Accent", 2, 0.2)

State.MinimizedShadow = Instance.new("Frame")
State.MinimizedShadow.Size = UDim2.new(1, 8, 1, 8)
State.MinimizedShadow.Position = UDim2.new(0, -4, 0, -4)
State.MinimizedShadow.BorderSizePixel = 0
State.MinimizedShadow.BackgroundTransparency = 0.55
State.MinimizedShadow.Active = false
State.MinimizedShadow.Visible = false
State.MinimizedShadow.ZIndex = 0
State.MinimizedShadow.Parent = Main
registerTheme(State.MinimizedShadow, "BackgroundColor3", "Main")
addCorner(State.MinimizedShadow, 12)

State.MinimizedIconImage = Instance.new("ImageLabel")
State.MinimizedIconImage.Size = UDim2.new(0.7, 0, 0.7, 0)
State.MinimizedIconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
State.MinimizedIconImage.AnchorPoint = Vector2.new(0.5, 0.5)
State.MinimizedIconImage.BackgroundTransparency = 1
State.MinimizedIconImage.BorderSizePixel = 0
State.MinimizedIconImage.Image = resolveMinimizeIcon()
State.MinimizedIconImage.ScaleType = Enum.ScaleType.Fit
State.MinimizedIconImage.Parent = MinimizedIcon

Minimized = false
Dragging = false
DragMoved = false
DragStart, StartPos = nil, nil

local function setMainAnchorTopRight()
    local absPos = Main.AbsolutePosition
    local absSize = Main.AbsoluteSize
    Main.AnchorPoint = Vector2.new(1, 0)
    Main.Position = UDim2.new(0, absPos.X + absSize.X, 0, absPos.Y)
end

setMainAnchorTopRight()

Body = Instance.new("Frame")
Body.Name = "Body"
Body.Size = UDim2.new(1, 0, 1, -(State.Layout.Tokens.HeaderH + State.Layout.Tokens.FooterH))
Body.Position = UDim2.new(0, 0, 0, State.Layout.Tokens.HeaderH)
Body.BorderSizePixel = 0
Body.Parent = Main
registerTheme(Body, "BackgroundColor3", "Panel")
addCorner(Body, 8)
State.MainLayout = State.MainLayout or {}
State.MainLayout.Body = Body

ResizeHandles = {}
local function createResizeHandle(name, size, pos)
    local h = Instance.new("TextButton")
    h.Name = name
    h.Size = size
    h.Position = pos
    h.BackgroundTransparency = 0
    h.BorderSizePixel = 0
    h.Text = ""
    h.AutoButtonColor = false
    h.Parent = Main
    h.Active = true
    h.ZIndex = 20
    registerTheme(h, "BackgroundColor3", "Main")
    addCorner(h, 4)
    addStroke(h, "Muted", 1, 0.6)
    ResizeHandles[#ResizeHandles + 1] = h
    return h
end

State.UI.BuildMiniIconButton = State.UI.BuildMiniIconButton or function(opts)
    local t = (opts and opts.Tokens) or (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {}
    local parent = opts and opts.Parent or Main
    local icon = opts and opts.Icon or ""
    local style = opts and opts.IconStyle or "direct"
    local btnW = math.max(18, (t.ButtonW or 24) - 4)
    local btnH = math.max(16, (t.ButtonH or 20) - 2)
    local btn = Instance.new("ImageButton")
    btn.Size = (opts and opts.Size) or UDim2.new(0, btnW, 0, btnH)
    btn.Position = (opts and opts.Position) or UDim2.new(0, 0, 0, 0)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn:SetAttribute("FontLock", true)
    btn.Parent = parent
    registerTheme(btn, "BackgroundColor3", "Panel")
    addCorner(btn, 4)
    addStroke(btn, "Muted", 1, 0.75)

    local iconImage = nil
    if style == "child" then
        btn.Image = ""
        btn.ScaleType = Enum.ScaleType.Fit
        btn.ImageTransparency = 0
        iconImage = Instance.new("ImageLabel")
        iconImage.Size = UDim2.new(0.7, 0, 0.7, 0)
        iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
        iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
        iconImage.BackgroundTransparency = 1
        iconImage.Image = icon
        iconImage.ScaleType = Enum.ScaleType.Fit
        iconImage.Parent = btn
        registerTheme(iconImage, "ImageColor3", "Text")
        if icon == "" and opts and opts.FallbackText then
            local fallback = Instance.new("TextLabel")
            fallback.Size = UDim2.new(1, 0, 1, 0)
            fallback.BackgroundTransparency = 1
            fallback.Text = opts.FallbackText
            fallback.Font = Enum.Font.GothamBold
            fallback.TextSize = 12
            fallback.Parent = btn
            setFontClass(fallback, "Button")
            registerTheme(fallback, "TextColor3", "Text")
        end
    else
        btn.Image = icon
        btn.ScaleType = Enum.ScaleType.Fit
        btn.ImageTransparency = 0
        registerTheme(btn, "ImageColor3", "Text")
        if icon == "" and opts and opts.FallbackText then
            local fallback = Instance.new("TextLabel")
            fallback.Size = UDim2.new(1, 0, 1, 0)
            fallback.BackgroundTransparency = 1
            fallback.Text = opts.FallbackText
            fallback.Font = Enum.Font.GothamBold
            fallback.TextSize = 12
            fallback.Parent = btn
            setFontClass(fallback, "Button")
            registerTheme(fallback, "TextColor3", "Text")
        end
    end

    return btn, iconImage
end

State.UI.BuildWindowControls = State.UI.BuildWindowControls or function(opts)
    local t = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {}
    local parent = opts and opts.Parent or Main
    local footer = opts and opts.FooterBar or nil

    local btnW = math.max(18, (t.ButtonW or 24) - 4)
    local btnH = math.max(16, (t.ButtonH or 20) - 2)
    local iconBtn = State.UI.BuildMiniIconButton({
        Parent = parent,
        Tokens = t,
        Position = UDim2.new(1, -((btnW) * 3 + (t.ButtonGap or 6) * 2 + (t.TitlePadX or 12)), 0, t.TitlePadY or 6),
        Icon = COPY_ICON_ASSET,
        IconStyle = "child",
        FallbackText = "[]"
    })
    local minimize = State.UI.BuildMiniIconButton({
        Parent = parent,
        Tokens = t,
        Position = UDim2.new(1, -((btnW) * 2 + (t.ButtonGap or 6) * 1 + (t.TitlePadX or 12)), 0, t.TitlePadY or 6),
        Icon = MINIMIZE_ICON_ASSET,
        FallbackText = "-"
    })
    local close = State.UI.BuildMiniIconButton({
        Parent = parent,
        Tokens = t,
        Position = UDim2.new(1, -((btnW) + (t.TitlePadX or 12)), 0, t.TitlePadY or 6),
        Icon = CLOSE_ICON_ASSET,
        FallbackText = "x"
    })

    local resizeHandle
    if footer then
        local resizeSize = math.max(16, (t.ButtonH or 20) - 2)
        local footerPad = math.max(8, (t.TitlePadX or 12))
        resizeHandle = createResizeHandle(
            "ResizeBottomRight",
            UDim2.new(0, resizeSize, 0, resizeSize),
            UDim2.new(1, -footerPad, 0.5, 2)
        )
        resizeHandle.Parent = footer
        resizeHandle.AnchorPoint = Vector2.new(1, 0.5)

        local img = Instance.new("ImageLabel")
        img.Name = "ResizeIcon"
        img.Size = UDim2.new(1, -4, 1, -4)
        img.Position = UDim2.new(0, 2, 0, 2)
        img.BackgroundTransparency = 1
        img.BorderSizePixel = 0
        img.Image = resolveResizeIcon()
        img.ScaleType = Enum.ScaleType.Fit
        img.ZIndex = resizeHandle.ZIndex + 1
        img.Parent = resizeHandle
        registerTheme(img, "ImageColor3", "Muted")
    end

    return {
        DockBtn = iconBtn,
        HideBtn = minimize,
        CloseBtn = close,
        ResizeBottomRight = resizeHandle,
        ResizeHandles = ResizeHandles
    }
end

WindowControls = State.UI.BuildWindowControls({Parent = HeaderBar, FooterBar = FooterBar})
DockBtn = WindowControls.DockBtn
HideBtn = WindowControls.HideBtn
CloseBtn = WindowControls.CloseBtn
ResizeBottomRight = WindowControls.ResizeBottomRight

SavedSize = Main.Size
SavedPos = Main.Position
State.MainLayout = State.MainLayout or {}
State.MainLayout.Apply = State.MainLayout.Apply or function()
    if not Main or not Main.Parent then
        return
    end
    if State.Layout and State.Layout.ApplyRelative then
        State.Layout.ApplyRelative(Main, State.MainLayout)
    else
        State.MainLayout.RelativePos = nil
    end
    if State.Layout and State.Layout.ClampFrameSoft then
        State.Layout.ClampFrameSoft(Main, 8, 8)
    end
    if State.MainLayout and State.MainLayout.ApplyLayout then
        State.MainLayout.ApplyLayout()
    end
    if not Minimized then
        SavedPos = Main.Position
        if State.Layout and State.Layout.SaveRelative then
            State.Layout.SaveRelative(Main, State.MainLayout)
        end
    end
end
setMinimized = function(state)
    Minimized = state
    if Minimized then
        SavedSize = Main.Size
        local absPos = Main.AbsolutePosition
        local absSize = Main.AbsoluteSize
        SavedPos = UDim2.new(0, absPos.X + absSize.X, 0, absPos.Y)
        Main.AnchorPoint = Vector2.new(1, 0)
        Main.Position = SavedPos
        Body.Visible = false
        TitleBar.Visible = false
        HeaderBar.Visible = false
        FooterBar.Visible = false
        VersionLabel.Visible = false
        AccentLine.Visible = false
        DockBtn.Visible = false
        if HideBtn then
            HideBtn.Visible = false
        end
        CloseBtn.Visible = false
        for _, h in ipairs(ResizeHandles) do
            h.Visible = false
            h.Active = false
        end
        Main.Size = UDim2.new(0, MINIMIZED_ICON_SIZE, 0, MINIMIZED_ICON_SIZE)
        MinimizedIcon.Visible = true
        if State.MinimizedShadow then
            State.MinimizedShadow.Visible = true
        end
        if State.MainLayout and State.MainLayout.Apply then
            State.MainLayout.Apply()
        end
    else
        Body.Visible = true
        TitleBar.Visible = true
        HeaderBar.Visible = true
        FooterBar.Visible = true
        VersionLabel.Visible = true
        AccentLine.Visible = true
        DockBtn.Visible = true
        if HideBtn then
            HideBtn.Visible = true
        end
        CloseBtn.Visible = true
        for _, h in ipairs(ResizeHandles) do
            h.Visible = true
            h.Active = true
        end
        Main.AnchorPoint = Vector2.new(1, 0)
        Main.Position = SavedPos
        Main.Size = SavedSize
        MinimizedIcon.Visible = false
        if State.MinimizedShadow then
            State.MinimizedShadow.Visible = false
        end
        if State.MainLayout and State.MainLayout.Apply then
            State.MainLayout.Apply()
        end
    end
end

UIHidden = false
  setHidden = function(state)
      UIHidden = state == true
      if UIHidden then
          if State.UI and State.UI.AnimateHide then
              State.UI.AnimateHide(Main, {EndScale = 0.95, Duration = 0.14})
          else
              Main.Visible = false
          end
          if MinimizedIcon then
              MinimizedIcon.Visible = false
          end
          if State.AutoBuyLogGui and AutoBuyLogState and AutoBuyLogState.Frame then
              if State.UI and State.UI.AnimateHide then
                  State.UI.AnimateHide(AutoBuyLogState.Frame, {EndScale = 0.96, Duration = 0.12})
              else
                  AutoBuyLogState.Frame.Visible = false
              end
              AutoBuyLogState.Resizing = false
              AutoBuyLogState.ResizeStart = nil
              AutoBuyLogState.ResizeStartSize = nil
              AutoBuyLogState.UserMoved = false
              AutoBuyLogState.RelativePos = nil
          end
      else
          if State.UI and State.UI.AnimateShow then
              State.UI.AnimateShow(Main, {StartScale = 0.95, Duration = 0.18})
          else
              Main.Visible = true
          end
          if State.AutoBuyLogGui and AutoBuyLogState and AutoBuyLogState.Frame then
              if Config.AutoBuyLogEnabled == true then
                  if State.UI and State.UI.AnimateShow then
                      State.UI.AnimateShow(AutoBuyLogState.Frame, {StartScale = 0.96, Duration = 0.18})
                  else
                      AutoBuyLogState.Frame.Visible = true
                  end
              end
          end
          if Minimized then
              setMinimized(true)
          else
              setMinimized(false)
          end
      end
  end

toggleHidden = function()
    if not UIHidden then
        local keyName = getHideKeyName()
        if type(notify) == "function" then
            notify("Interface Hidden", "Tekan [" .. tostring(keyName) .. "] untuk membuka kembali", 4)
            local autoKey = getAutoBuyLogKeyName()
            local clickerKey = getActionAutoClickerKeyName()
            notify("Keybind", "Hide UI [" .. tostring(keyName) .. "] | Auto Buy Log [" .. tostring(autoKey) .. "] | Auto Clicker [" .. tostring(clickerKey) .. "]", 4)
        end
    end
    setHidden(not UIHidden)
end

toggleAutoBuyLogKeybind = nil
toggleActionAutoClickerKeybind = nil

TabBar = Instance.new("ScrollingFrame")
TabBar.Name = "TabBar"
TabBar.Size = UDim2.new(0, State.Layout.Tokens.TabW, 1, 0)
TabBar.BorderSizePixel = 0
TabBar.Parent = Body
TabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
TabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
TabBar.ScrollBarThickness = 6
TabBar.ScrollingDirection = Enum.ScrollingDirection.Y
TabBar.ClipsDescendants = true
registerTheme(TabBar, "BackgroundColor3", "Main")
addCorner(TabBar, State.Layout.Tokens.Radius)
addStroke(TabBar, "Muted", 1, 0.8)

TabBarConstraint = Instance.new("UISizeConstraint")
TabBarConstraint.MinSize = Vector2.new(State.Layout.Tokens.TabMin, 1)
TabBarConstraint.MaxSize = Vector2.new(State.Layout.Tokens.TabMax, 100000)
TabBarConstraint.Parent = TabBar

TabList = Instance.new("UIListLayout")
TabList.Padding = UDim.new(0, State.Layout.Tokens.TabGap)
TabList.SortOrder = Enum.SortOrder.LayoutOrder
TabList.Parent = TabBar

TabPadding = Instance.new("UIPadding")
TabPadding.PaddingTop = UDim.new(0, State.Layout.Tokens.TabPadding)
TabPadding.PaddingLeft = UDim.new(0, State.Layout.Tokens.TabPadding)
TabPadding.PaddingRight = UDim.new(0, State.Layout.Tokens.TabPadding)
TabPadding.PaddingBottom = UDim.new(0, State.Layout.Tokens.TabPadding)
TabPadding.Parent = TabBar

Pages = Instance.new("Frame")
Pages.Name = "Pages"
Pages.Size = UDim2.new(1, -State.Layout.Tokens.TabW, 1, 0)
Pages.Position = UDim2.new(0, State.Layout.Tokens.TabW, 0, 0)
Pages.BorderSizePixel = 0
Pages.Parent = Body
registerTheme(Pages, "BackgroundColor3", "Panel")
addCorner(Pages, State.Layout.Tokens.Radius)
State.MainLayout.TabBar = TabBar
State.MainLayout.Pages = Pages

State.MainLayout.ApplyLayout = State.MainLayout.ApplyLayout or function()
    if not (TabBar and Pages) then
        return
    end
    if State.Layout and State.Layout.RefreshTokens then
        State.Layout.RefreshTokens()
    end
    local t = State.Layout and State.Layout.Tokens or nil
    if not t then
        return
    end
    TabBar.Size = UDim2.new(0, t.TabW, 1, 0)
    Pages.Size = UDim2.new(1, -t.TabW, 1, 0)
    Pages.Position = UDim2.new(0, t.TabW, 0, 0)
    TabPadding.PaddingTop = UDim.new(0, t.TabPadding)
    TabPadding.PaddingLeft = UDim.new(0, t.TabPadding)
    TabPadding.PaddingRight = UDim.new(0, t.TabPadding)
    TabPadding.PaddingBottom = UDim.new(0, t.TabPadding)
    TabList.Padding = UDim.new(0, t.TabGap)
    if TabBarConstraint then
        TabBarConstraint.MinSize = Vector2.new(t.TabMin, 1)
        TabBarConstraint.MaxSize = Vector2.new(t.TabMax, 100000)
    end
end


end

local function bindMainUI()
    local function beginMainDrag(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            Dragging = true
            DragMoved = false
            DragStart = input.Position
            StartPos = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    Dragging = false
                    if State.Layout and State.Layout.SaveRelative then
                        State.Layout.SaveRelative(Main, State.MainLayout)
                    end
                end
            end)
        end
    end

    trackConnection(TitleBar.InputBegan:Connect(beginMainDrag))
    trackConnection(VersionLabel.InputBegan:Connect(beginMainDrag))

    trackConnection(MinimizedIcon.InputBegan:Connect(function(input)
        if not Minimized then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            Dragging = true
            DragMoved = false
            DragStart = input.Position
            StartPos = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    Dragging = false
                    if State.Layout and State.Layout.SaveRelative then
                        State.Layout.SaveRelative(Main, State.MainLayout)
                    end
                end
            end)
        end
    end))

    trackConnection(UIS.InputChanged:Connect(function(input)
        if Dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - DragStart
            if delta.Magnitude > 3 then
                DragMoved = true
            end
            Main.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + delta.X, StartPos.Y.Scale, StartPos.Y.Offset + delta.Y)
        end
    end))

    trackConnection(DockBtn.MouseButton1Click:Connect(function()
        if type(setMinimized) == "function" then
            setMinimized(not Minimized)
        end
    end))

    if HideBtn then
        trackConnection(HideBtn.MouseButton1Click:Connect(function()
            if type(toggleHidden) == "function" then
                toggleHidden()
            end
        end))
    end

    trackConnection(MinimizedIcon.MouseButton1Click:Connect(function()
        if Minimized then
            if DragMoved then
                DragMoved = false
                return
            end
            setMinimized(false)
        end
    end))

    trackConnection(CloseBtn.MouseButton1Click:Connect(function()
        confirmDialog("Konfirmasi", "Apakah anda yakin ingin keluar dari script?", function()
            cleanupAll()
        end)
    end))

    trackConnection(UIS.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        if UIS:GetFocusedTextBox() then
            return
        end
        local keyCode = nil
        if State.Keybind and State.Keybind.Resolve then
            local code = nil
            code = State.Keybind.Resolve()
            keyCode = code
        end
        if keyCode and input.KeyCode == keyCode then
            if type(toggleHidden) == "function" then
                toggleHidden()
            end
            return
        end

        local autoBuyCode = nil
        if State.Keybind and State.Keybind.ResolveAutoBuyLog then
            local code = nil
            code = State.Keybind.ResolveAutoBuyLog()
            autoBuyCode = code
        end
        if autoBuyCode and input.KeyCode == autoBuyCode then
            if type(toggleAutoBuyLogKeybind) == "function" then
                toggleAutoBuyLogKeybind()
            end
            return
        end

        local autoClickerCode = nil
        if State.Keybind and State.Keybind.ResolveAutoClicker then
            local code = nil
            code = State.Keybind.ResolveAutoClicker()
            autoClickerCode = code
        end
        if autoClickerCode and input.KeyCode == autoClickerCode then
            if type(toggleActionAutoClickerKeybind) == "function" then
                toggleActionAutoClickerKeybind()
            end
        end
    end))

    Resizing = false
    ResizeDir = nil
    ResizeStartPos = nil
    ResizeStartSize = nil
    ResizeStartMainPos = nil
    MinSize = Vector2.new(450, 320)
    ResizeClickCount = 0
    ResizeClickTime = 0
    ResizeClickHandle = nil

    local function centerMain()
        Main.Position = UDim2.new(0.5, 0, 0.5, 0)
    end

    local function beginResize(dir, input)
        if Minimized then
            return
        end
        Resizing = true
        ResizeDir = dir
        ResizeStartPos = input.Position
        ResizeStartSize = Main.Size
        ResizeStartMainPos = Main.Position
    end

    local function updateResize(input)
        if not Resizing then return end
        local delta = input.Position - ResizeStartPos
        local newSize = ResizeStartSize
        local newPos = ResizeStartMainPos

        if ResizeDir == "Left" or ResizeDir == "TopLeft" or ResizeDir == "BottomLeft" then
            local newW = math.max(MinSize.X, ResizeStartSize.X.Offset - delta.X)
            local dx = ResizeStartSize.X.Offset - newW
            newSize = UDim2.new(0, newW, newSize.Y.Scale, newSize.Y.Offset)
            newPos = UDim2.new(newPos.X.Scale, newPos.X.Offset + dx, newPos.Y.Scale, newPos.Y.Offset)
        end
        if ResizeDir == "Right" or ResizeDir == "TopRight" or ResizeDir == "BottomRight" then
            local newW = math.max(MinSize.X, ResizeStartSize.X.Offset + delta.X)
            newSize = UDim2.new(0, newW, newSize.Y.Scale, newSize.Y.Offset)
        end
        if ResizeDir == "Top" or ResizeDir == "TopLeft" or ResizeDir == "TopRight" then
            local newH = math.max(MinSize.Y, ResizeStartSize.Y.Offset - delta.Y)
            local dy = ResizeStartSize.Y.Offset - newH
            newSize = UDim2.new(newSize.X.Scale, newSize.X.Offset, 0, newH)
            newPos = UDim2.new(newPos.X.Scale, newPos.X.Offset, newPos.Y.Scale, newPos.Y.Offset + dy)
        end
        if ResizeDir == "Bottom" or ResizeDir == "BottomLeft" or ResizeDir == "BottomRight" then
            local newH = math.max(MinSize.Y, ResizeStartSize.Y.Offset + delta.Y)
            newSize = UDim2.new(newSize.X.Scale, newSize.X.Offset, 0, newH)
        end

        Main.Size = newSize
        Main.Position = newPos
    end

    local function endResize()
        if not Resizing then
            return
        end
        Resizing = false
        ResizeDir = nil
        if not Minimized and Main and Main.Size then
            Config.WindowWidth = Main.Size.X.Offset
            Config.WindowHeight = Main.Size.Y.Offset
            saveConfig()
        end
        if State.Layout and State.Layout.SaveRelative then
            State.Layout.SaveRelative(Main, State.MainLayout)
        end
    end

    local handleMap = {
        ResizeBottomRight = "BottomRight"
    }

    for _, h in ipairs(ResizeHandles) do
        trackConnection(h.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                local now = os.clock()
                if ResizeClickHandle ~= h or (now - ResizeClickTime) > 0.35 then
                    ResizeClickCount = 0
                end
                ResizeClickCount += 1
                ResizeClickTime = now
                ResizeClickHandle = h
                if ResizeClickCount >= 3 then
                    ResizeClickCount = 0
                    centerMain()
                    return
                end
                beginResize(handleMap[h.Name], input)
            end
        end))
    end

    trackConnection(UIS.InputChanged:Connect(function(input)
        if Resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateResize(input)
        end
    end))

    trackConnection(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            endResize()
            if Dragging then
                SavedPos = Main.Position
            end
        end
    end))
end

buildMainUI()
bindMainUI()

LoadingUI:Set(15, "Menyusun layout...")

local function createTabButton(text)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, State.Layout.Tokens.RowH)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 13
    btn.Text = text
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.AutoButtonColor = false
    btn.Parent = TabBar
    setFontClass(btn, "Nav")
    registerTheme(btn, "BackgroundColor3", "Main")
    registerTheme(btn, "TextColor3", "Muted")
    addCorner(btn, State.Layout.Tokens.RadiusSm)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, State.Layout.Tokens.TabPadding + State.Layout.Tokens.InputPadSm)
    pad.Parent = btn
    local indicator = Instance.new("Frame")
    indicator.Name = "ActiveIndicator"
    indicator.Size = UDim2.new(0, math.max(2, State.Layout.Tokens.InputPadSm), 1, -(State.Layout.Tokens.InputPadSm * 2 + 2))
    indicator.Position = UDim2.new(0, -State.Layout.Tokens.TabPadding, 0, State.Layout.Tokens.InputPadSm + 1)
    indicator.BorderSizePixel = 0
    indicator.Parent = btn
    indicator.Visible = false
    TabButtons[#TabButtons + 1] = btn
    return btn
end

local function createTabDivider()
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, 0, 0, State.Layout.Tokens.AccentH)
    div.BorderSizePixel = 0
    div.Parent = TabBar
    registerTheme(div, "BackgroundColor3", "Muted")
    return div
end

local function createPage()
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BorderSizePixel = 0
    page.Visible = false
    page.Parent = Pages
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.ScrollBarThickness = 6
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.ClipsDescendants = true
    registerTheme(page, "BackgroundColor3", "Panel")

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, State.Layout.Tokens.SectionGap)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, State.Layout.Tokens.SectionPad)
    padding.PaddingLeft = UDim.new(0, State.Layout.Tokens.SectionPad)
    padding.PaddingRight = UDim.new(0, State.Layout.Tokens.SectionPad)
    padding.PaddingBottom = UDim.new(0, State.Layout.Tokens.SectionPad)
    padding.Parent = page

    return page
end

-- =====================================================
-- UI BUILDERS
-- =====================================================
local function createSection(parent, title)
    local label = Instance.new("TextLabel")
    label.Name = "SliderLabel"
    label.Size = UDim2.new(1, 0, 0, math.max(18, State.Layout.Tokens.RowH - State.Layout.Tokens.InputPadSm))
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 13
    label.Text = title
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    setFontClass(label, "Heading")
    registerTheme(label, "TextColor3", "Text")
    return label
end

local function createSubSection(parent, title)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, math.max(16, State.Layout.Tokens.RowH - State.Layout.Tokens.InputPad))
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = title
    label.Parent = parent
    setFontClass(label, "Subheading")
    registerTheme(label, "TextColor3", "Muted")
    return label
end

local function createSectionBox(parent, title, key)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BorderSizePixel = 0
    container.Parent = parent
    registerTheme(container, "BackgroundColor3", "Panel")
    addCorner(container, State.Layout.Tokens.Radius)
    addStroke(container, "Muted", 1, 0.8)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, State.Layout.Tokens.SectionGap)
    pad.PaddingBottom = UDim.new(0, State.Layout.Tokens.SectionGap + State.Layout.Tokens.InputPadSm)
    pad.PaddingLeft = UDim.new(0, State.Layout.Tokens.SectionPad)
    pad.PaddingRight = UDim.new(0, State.Layout.Tokens.SectionPad)
    pad.Parent = container

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, math.max(18, State.Layout.Tokens.RowH - State.Layout.Tokens.InputPadSm))
    header.BorderSizePixel = 0
    header.BackgroundTransparency = 1
    header.Parent = container

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -(State.Layout.Tokens.ButtonW + State.Layout.Tokens.InputPadSm), 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 13
    label.Text = title
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = header
    setFontClass(label, "Heading")
    registerTheme(label, "TextColor3", "Text")

    local headerBtn = Instance.new("TextButton")
    headerBtn.Size = UDim2.new(1, -(State.Layout.Tokens.ButtonW + State.Layout.Tokens.InputPadSm), 1, 0)
    headerBtn.Position = UDim2.new(0, 0, 0, 0)
    headerBtn.BorderSizePixel = 0
    headerBtn.BackgroundTransparency = 1
    headerBtn.Text = ""
    headerBtn.AutoButtonColor = false
    headerBtn.Parent = header

    local toggleBtn = Instance.new("ImageButton")
    toggleBtn.Size = UDim2.new(0, State.Layout.Tokens.ButtonW - State.Layout.Tokens.InputPadSm, 0, State.Layout.Tokens.ButtonH)
    toggleBtn.Position = UDim2.new(1, -(State.Layout.Tokens.ButtonW - State.Layout.Tokens.InputPadSm), 0, math.max(0, State.Layout.Tokens.InputPadSm - 1))
    toggleBtn.BorderSizePixel = 0
    toggleBtn.BackgroundTransparency = 1
    toggleBtn.AutoButtonColor = false
    toggleBtn.Image = ""
    toggleBtn.ScaleType = Enum.ScaleType.Fit
    toggleBtn.Parent = header

    local toggleIcon = Instance.new("ImageLabel")
    toggleIcon.Size = UDim2.new(0.5, 0, 0.5, 0)
    toggleIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    toggleIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    toggleIcon.BackgroundTransparency = 1
    toggleIcon.Parent = toggleBtn
    registerTheme(toggleIcon, "ImageColor3", "Muted")

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.BorderSizePixel = 0
    divider.Parent = container
    registerTheme(divider, "BackgroundColor3", "Muted")

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.BackgroundTransparency = 1
    content.Parent = container

    local stack = Instance.new("UIListLayout")
    stack.Padding = UDim.new(0, State.Layout.Tokens.SectionGap)
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.Parent = container

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, State.Layout.Tokens.SectionGap)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = content

    local stateKey
    if type(key) == "string" and #key > 0 then
        stateKey = key
    else
        local parentName = parent and parent.Name or "Page"
        stateKey = parentName .. "::" .. tostring(title)
    end

    local expanded = true
    if State.Config and State.Config.Get then
        local states = State.Config.Get("SectionStates", {})
        if states[stateKey] ~= nil then
            expanded = states[stateKey] == true
        else
            states[stateKey] = expanded
            State.Config.Set("SectionStates", states)
        end
    end

    local function applyExpanded()
        content.Visible = expanded
        if State.UI and State.UI.IconAssets then
            toggleIcon.Image = expanded and State.UI.IconAssets.ArrowDown or State.UI.IconAssets.ArrowRight
        end
    end

    local function setExpanded(v)
        expanded = v == true
        if State.Config and State.Config.Get then
            local states = State.Config.Get("SectionStates", {})
            states[stateKey] = expanded
            State.Config.Set("SectionStates", states)
        end
        applyExpanded()
    end

    toggleBtn.MouseButton1Click:Connect(function()
        setExpanded(not expanded)
    end)

    headerBtn.MouseButton1Click:Connect(function()
        setExpanded(not expanded)
    end)

    applyExpanded()

    return content
end

local function createSubSectionBox(parent, title)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BorderSizePixel = 0
    container.Parent = parent
    registerTheme(container, "BackgroundColor3", "Main")
    addCorner(container, State.Layout.Tokens.Radius)
    addStroke(container, "Muted", 1, 0.85)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, State.Layout.Tokens.SectionGap)
    pad.PaddingBottom = UDim.new(0, State.Layout.Tokens.SectionGap)
    pad.PaddingLeft = UDim.new(0, State.Layout.Tokens.SectionPad - State.Layout.Tokens.InputPadSm)
    pad.PaddingRight = UDim.new(0, State.Layout.Tokens.SectionPad - State.Layout.Tokens.InputPadSm)
    pad.Parent = container

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, math.max(16, State.Layout.Tokens.RowH - State.Layout.Tokens.InputPad))
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 11
    label.Text = title
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container
    setFontClass(label, "Subheading")
    registerTheme(label, "TextColor3", "Muted")

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.BackgroundTransparency = 1
    content.Parent = container

    local stack = Instance.new("UIListLayout")
    stack.Padding = UDim.new(0, State.Layout.Tokens.InputPad)
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.Parent = container

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, State.Layout.Tokens.InputPad)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = content

    return content
end

State.UI.CreateListDropdownRow = State.UI.CreateListDropdownRow or function(parent, labelText, onToggle)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 30)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, 6)
    addStroke(frame, "Muted", 1, 0.8)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -50, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = labelText
    label.Parent = frame
    registerTheme(label, "TextColor3", "Text")

    local btn = Instance.new("ImageButton")
    btn.Size = UDim2.new(0, 30, 0, 20)
    btn.Position = UDim2.new(1, -35, 0.5, -10)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Image = ""
    btn.ScaleType = Enum.ScaleType.Fit
    btn.Parent = frame
    registerTheme(btn, "BackgroundColor3", "Panel")
    addCorner(btn, 6)

    local btnIcon = Instance.new("ImageLabel")
    btnIcon.Size = UDim2.new(0.5, 0, 0.5, 0)
    btnIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    btnIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    btnIcon.BackgroundTransparency = 1
    btnIcon.Parent = btn
    registerTheme(btnIcon, "ImageColor3", "Text")

    local enabled = true
    local expanded = false

    local function setExpanded(state)
        expanded = state and true or false
        if State.UI and State.UI.IconAssets then
            btnIcon.Image = expanded and State.UI.IconAssets.ArrowDown or State.UI.IconAssets.ArrowRight
        end
    end

    btn.MouseButton1Click:Connect(function()
        if not enabled then
            return
        end
        setExpanded(not expanded)
        if onToggle then
            onToggle(expanded)
        end
    end)

    setExpanded(false)

    return {
        SetEnabled = function(_, value)
            enabled = value and true or false
            label.TextTransparency = enabled and 0 or 0.4
            btnIcon.ImageTransparency = enabled and 0 or 0.4
        end,
        SetExpanded = function(_, value)
            setExpanded(value)
        end,
        Frame = frame,
        Label = label
    }
end

local function createParagraph(parent, title, content)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.BorderSizePixel = 0
    frame.Parent = parent
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, State.Layout.Tokens.RadiusSm)
    addStroke(frame, "Muted", 1, 0.8)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, State.Layout.Tokens.InputPad)
    pad.PaddingBottom = UDim.new(0, State.Layout.Tokens.InputPad)
    pad.PaddingLeft = UDim.new(0, State.Layout.Tokens.SectionPad - State.Layout.Tokens.InputPadSm)
    pad.PaddingRight = UDim.new(0, State.Layout.Tokens.SectionPad - State.Layout.Tokens.InputPadSm)
    pad.Parent = frame

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -(State.Layout.Tokens.ButtonW), 0, math.max(16, State.Layout.Tokens.RowH - State.Layout.Tokens.InputPad))
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.GothamSemibold
    t.TextSize = 12
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Text = title
    t.Parent = frame
    setFontClass(t, "Heading")
    registerTheme(t, "TextColor3", "Text")

    local c = Instance.new("TextLabel")
    c.Size = UDim2.new(1, 0, 0, 0)
    c.AutomaticSize = Enum.AutomaticSize.Y
    c.BackgroundTransparency = 1
    c.Font = Enum.Font.Gotham
    c.TextSize = 12
    c.TextWrapped = true
    c.TextXAlignment = Enum.TextXAlignment.Left
    c.TextYAlignment = Enum.TextYAlignment.Top
    c.Text = content
    c.Parent = frame
    setFontClass(c, "Body")
    registerTheme(c, "TextColor3", "Muted")

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, State.Layout.Tokens.InputPadSm)
    list.Parent = frame

    return {
        Destroy = function()
            frame:Destroy()
        end
    }
end

local function createInput(parent, text, flag, currentValue, callback)
    local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
        RowH = 30,
        LabelMin = 110,
        LabelMax = 180,
        RowPadX = 10,
        RowPadY = 4,
        ContentGap = 8,
        InputPad = 6,
        InputPadSm = 4,
        RadiusSm = 6
    }
    local value = currentValue or ""
    if flag and State.Config and State.Config.Get then
        local v = State.Config.Get(flag, value)
        value = tostring(v)
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, tokens.RowH)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, tokens.RadiusSm)
    addStroke(frame, "Muted", 1, 0.8)

    local framePad = Instance.new("UIPadding")
    framePad.PaddingLeft = UDim.new(0, tokens.RowPadX)
    framePad.PaddingRight = UDim.new(0, tokens.RowPadX)
    framePad.Parent = frame

    local label = Instance.new("TextLabel")
    local contentH = math.max(16, tokens.RowH - (tokens.RowPadY * 2))
    label.Size = UDim2.new(0, tokens.LabelMin, 0, contentH)
    label.Position = UDim2.new(0, 0, 0.5, 0)
    label.AnchorPoint = Vector2.new(0, 0.5)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Text = text
    label.Parent = frame
    setFontClass(label, "Body")
    registerTheme(label, "TextColor3", "Text")

    local labelConstraint = Instance.new("UISizeConstraint")
    labelConstraint.MinSize = Vector2.new(tokens.LabelMin, 0)
    labelConstraint.MaxSize = Vector2.new(tokens.LabelMax, 0)
    labelConstraint.Parent = label

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -(tokens.LabelMin + tokens.ContentGap), 0, contentH)
    box.Position = UDim2.new(0, tokens.LabelMin + tokens.ContentGap, 0.5, 0)
    box.AnchorPoint = Vector2.new(0, 0.5)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Center
    box.Text = value
    box.ClipsDescendants = true
    box.Parent = frame
    setFontClass(box, "Body")
    registerTheme(box, "BackgroundColor3", "Panel")
    registerTheme(box, "TextColor3", "Text")
    addCorner(box, tokens.RadiusSm)

    local boxPad = Instance.new("UIPadding")
    boxPad.PaddingLeft = UDim.new(0, tokens.InputPad)
    boxPad.PaddingRight = UDim.new(0, tokens.InputPad)
    boxPad.PaddingTop = UDim.new(0, math.max(1, tokens.InputPadSm - 1))
    boxPad.PaddingBottom = UDim.new(0, math.max(1, tokens.InputPadSm - 1))
    boxPad.Parent = box

    local disabled = false

    local function setValue(v, silent)
        value = v or ""
        if flag then
            Config[flag] = value
            saveConfig()
        end
        if callback and not silent then
            callback(value)
        end
    end

    box.FocusLost:Connect(function()
        if disabled then
            return
        end
        setValue(box.Text, false)
    end)

    if callback then
        callback(value)
    end

    return {
        Set = function(_, v)
            box.Text = v or ""
            setValue(box.Text, true)
        end,
        Get = function()
            return value
        end,
        SetEnabled = function(_, enabled)
            disabled = not enabled
            label.TextTransparency = disabled and 0.4 or 0
            box.TextTransparency = disabled and 0.4 or 0
            box.Active = enabled
            if box:IsA("TextBox") then
                box.TextEditable = enabled
            end
        end,
        Frame = frame,
        Box = box,
        Label = label,
        Destroy = function()
            frame:Destroy()
        end
    }
end

local function createContainer(parent, height)
    local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
        RadiusSm = 6,
        InputPad = 6
    }
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, height or 160)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, tokens.RadiusSm)
    addStroke(frame, "Muted", 1, 0.8)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, tokens.InputPad)
    pad.PaddingBottom = UDim.new(0, tokens.InputPad)
    pad.PaddingLeft = UDim.new(0, tokens.InputPad)
    pad.PaddingRight = UDim.new(0, tokens.InputPad)
    pad.Parent = frame

    return frame
end

local function createKeybindInput(parent, text, flag, currentValue, callback)
    local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
        RowH = 30,
        LabelMin = 110,
        LabelMax = 180,
        RowPadX = 10,
        RowPadY = 4,
        ContentGap = 8,
        InputPad = 6,
        InputPadSm = 4,
        RadiusSm = 6,
        ButtonW = 24
    }
    local value = currentValue or ""
    if flag and State.Config and State.Config.Get then
        local v = State.Config.Get(flag, value)
        value = tostring(v)
    end
    if #value > 1 then
        value = string.sub(value, 1, 1)
    end
    if #value == 1 then
        value = value:upper()
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, tokens.RowH)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, tokens.RadiusSm)
    addStroke(frame, "Muted", 1, 0.8)

    local framePad = Instance.new("UIPadding")
    framePad.PaddingLeft = UDim.new(0, tokens.RowPadX)
    framePad.PaddingRight = UDim.new(0, tokens.RowPadX)
    framePad.Parent = frame

    local label = Instance.new("TextLabel")
    local contentH = math.max(16, tokens.RowH - (tokens.RowPadY * 2))
    label.Size = UDim2.new(0, tokens.LabelMin, 0, contentH)
    label.Position = UDim2.new(0, 0, 0.5, 0)
    label.AnchorPoint = Vector2.new(0, 0.5)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Text = text
    label.Parent = frame
    setFontClass(label, "Body")
    registerTheme(label, "TextColor3", "Text")

    local labelConstraint = Instance.new("UISizeConstraint")
    labelConstraint.MinSize = Vector2.new(tokens.LabelMin, 0)
    labelConstraint.MaxSize = Vector2.new(tokens.LabelMax, 0)
    labelConstraint.Parent = label

    local collapsedW = math.max(28, (tokens.ButtonW or 24) + 6)
    local baseExpanded = math.max(90, tokens.LabelMin)
    local expandedW = math.max(collapsedW + 16, math.floor(baseExpanded * 0.5 + 0.5))
    local rightPad = 0
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0, collapsedW, 0, contentH)
    box.Position = UDim2.new(1, -rightPad, 0.5, 0)
    box.AnchorPoint = Vector2.new(1, 0.5)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.TextXAlignment = Enum.TextXAlignment.Center
    box.TextYAlignment = Enum.TextYAlignment.Center
    box.Text = value
    box.PlaceholderText = "Keybind..."
    box.Parent = frame
    box.MaxVisibleGraphemes = 1
    setFontClass(box, "Body")
    registerTheme(box, "BackgroundColor3", "Panel")
    registerTheme(box, "TextColor3", "Text")
    registerTheme(box, "PlaceholderColor3", "Muted")
    addCorner(box, tokens.RadiusSm)

    local boxPad = Instance.new("UIPadding")
    boxPad.PaddingLeft = UDim.new(0, tokens.InputPad)
    boxPad.PaddingRight = UDim.new(0, tokens.InputPad)
    boxPad.PaddingTop = UDim.new(0, math.max(1, tokens.InputPadSm - 1))
    boxPad.PaddingBottom = UDim.new(0, math.max(1, tokens.InputPadSm - 1))
    boxPad.Parent = box

    local disabled = false
    local activeTween
    local function tweenBox(targetW)
        if activeTween then
            activeTween:Cancel()
        end
        activeTween = TweenService:Create(
            box,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                Size = UDim2.new(0, targetW, 0, contentH),
                Position = UDim2.new(1, -rightPad, 0.5, 0)
            }
        )
        activeTween:Play()
    end

    local function setValue(v, silent)
        value = v or ""
        if #value > 1 then
            value = string.sub(value, 1, 1)
        end
        if #value == 1 then
            value = value:upper()
        end
        box.Text = value
        if flag then
            Config[flag] = value
            saveConfig()
        end
        if callback and not silent then
            callback(value, false)
        end
    end

    local prevValue = value
    local suppressFocusLost = false
    box:GetPropertyChangedSignal("Text"):Connect(function()
        if disabled then
            return
        end
        if #box.Text > 1 then
            box.Text = string.sub(box.Text, 1, 1)
        end
        if #box.Text == 1 then
            box.Text = box.Text:upper()
            suppressFocusLost = true
            setValue(box.Text, false)
            box:ReleaseFocus()
        end
    end)

    box.Focused:Connect(function()
        if disabled then
            return
        end
        prevValue = value
        box.Text = ""
        tweenBox(expandedW)
        box.PlaceholderText = "Keybind..."
    end)

    box.FocusLost:Connect(function()
        if disabled then
            return
        end
        if suppressFocusLost then
            suppressFocusLost = false
            tweenBox(collapsedW)
            return
        end
        local nextValue = box.Text
        if nextValue == "" then
            box.Text = prevValue
            value = prevValue
        else
            setValue(nextValue, false)
        end
        tweenBox(collapsedW)
    end)

    if callback then
        callback(value, true)
    end

    return {
        Set = function(_, v)
            setValue(v, true)
        end,
        Get = function()
            return value
        end,
        SetEnabled = function(_, enabled)
            disabled = not enabled
            label.TextTransparency = disabled and 0.4 or 0
            box.TextTransparency = disabled and 0.4 or 0
            box.Active = enabled
            if box:IsA("TextBox") then
                box.TextEditable = enabled
            end
        end,
        Frame = frame,
        Box = box,
        Label = label,
        Destroy = function()
            frame:Destroy()
        end
    }
end

State.UI.BuildScrollList = State.UI.BuildScrollList or function(parent, opts)
    local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
        RowH = 30,
        InputPad = 6,
        InputPadSm = 4
    }
    local height = (opts and opts.Height) or 180
    local titleText = (opts and opts.Title) or "Logs"
    local titleClass = (opts and opts.TitleClass) or "Subheading"
    local titleHeight = (opts and opts.TitleHeight) or math.max(16, (tokens.RowH or 30) - (tokens.InputPadSm or 4))
    local gap = (opts and opts.TitleGap) or (tokens.InputPadSm or 4)
    local listPadding = (opts and opts.ListPadding) or (tokens.InputPadSm or 6)
    local container = createContainer(parent, height)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, titleHeight)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamSemibold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = titleText
    title.Parent = container
    setFontClass(title, titleClass)
    registerTheme(title, "TextColor3", "Text")

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -(titleHeight + gap))
    scroll.Position = UDim2.new(0, 0, 0, titleHeight + gap)
    scroll.BorderSizePixel = 0
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollBarThickness = 6
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.ClipsDescendants = true
    scroll.Parent = container
    registerTheme(scroll, "BackgroundColor3", "Panel")

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, listPadding)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = scroll

    local function updateCanvas()
        scroll.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + listPadding * 2)
    end
    if trackConnection then
        trackConnection(list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas))
    else
        list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
    end
    updateCanvas()

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, listPadding)
    pad.PaddingBottom = UDim.new(0, listPadding)
    pad.PaddingLeft = UDim.new(0, listPadding)
    pad.PaddingRight = UDim.new(0, listPadding)
    pad.Parent = scroll

    return {
        Container = container,
        Title = title,
        Scroll = scroll,
        List = list,
        Padding = pad,
        TitleHeight = titleHeight,
        ListPadding = listPadding
    }
end

local function createButton(parent, text, callback)
    local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
        RowH = 30,
        RowPadX = 10,
        RowPadY = 4,
        RadiusSm = 6
    }
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, tokens.RowH)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.Text = text
    btn.AutoButtonColor = false
    btn.Parent = parent
    setFontClass(btn, "Button")
    registerTheme(btn, "BackgroundColor3", "Main")
    registerTheme(btn, "TextColor3", "Text")
    addCorner(btn, tokens.RadiusSm)

    local btnPad = Instance.new("UIPadding")
    btnPad.PaddingLeft = UDim.new(0, tokens.RowPadX)
    btnPad.PaddingRight = UDim.new(0, tokens.RowPadX)
    btnPad.PaddingTop = UDim.new(0, math.max(1, tokens.RowPadY - 2))
    btnPad.PaddingBottom = UDim.new(0, math.max(1, tokens.RowPadY - 2))
    btnPad.Parent = btn

    local disabled = false

    btn.MouseButton1Click:Connect(function()
        if disabled then
            return
        end
        if callback then
            callback()
        end
    end)

    return {
        Button = btn,
        Frame = btn,
        SetEnabled = function(_, enabled)
            disabled = not enabled
            btn.TextTransparency = disabled and 0.4 or 0
        end,
        Destroy = function()
            btn:Destroy()
        end
    }
end

local function createToggle(parent, text, flag, currentValue, callback)
    local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
        RowH = 30,
        ButtonW = 40,
        ButtonH = 20,
        RowPadX = 10,
        RowPadY = 4,
        ContentGap = 8,
        InputPadSm = 4,
        RadiusSm = 6,
        ToggleRadius = 6,
        ToggleTextSize = 9,
        ToggleTextBold = true,
        ToggleWidthScale = 1.5
    }
    local toggleW = math.floor(tokens.ButtonW * (tokens.ToggleWidthScale or 1))
    local state = currentValue
    if flag and State.Config and State.Config.Get then
        state = State.Config.Get(flag, state)
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, tokens.RowH)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, tokens.RadiusSm)
    addStroke(frame, "Muted", 1, 0.8)

    local framePad = Instance.new("UIPadding")
    framePad.PaddingLeft = UDim.new(0, tokens.RowPadX)
    framePad.PaddingRight = UDim.new(0, tokens.RowPadX)
    framePad.PaddingTop = UDim.new(0, tokens.RowPadY)
    framePad.PaddingBottom = UDim.new(0, tokens.RowPadY)
    framePad.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -(toggleW + tokens.ContentGap), 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text
    label.Parent = frame
    setFontClass(label, "Body")
    registerTheme(label, "TextColor3", "Text")

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, toggleW, 0, tokens.ButtonH)
    btn.Position = UDim2.new(1, -toggleW, 0.5, -math.floor(tokens.ButtonH / 2))
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = frame
    addCorner(btn, tokens.ToggleRadius > 0 and tokens.ToggleRadius or math.max(6, math.floor(tokens.ButtonH / 2)))

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, tokens.ButtonH - (tokens.InputPadSm * 2), 0, tokens.ButtonH - (tokens.InputPadSm * 2))
    knob.Position = UDim2.new(0, tokens.InputPadSm, 0.5, -(tokens.ButtonH - (tokens.InputPadSm * 2)) / 2)
    knob.BorderSizePixel = 0
    knob.Parent = btn
    addCorner(knob, math.max(6, math.floor((tokens.ButtonH - (tokens.InputPadSm * 2)) / 2)))
    registerTheme(knob, "BackgroundColor3", "Text")

    local disabled = false

    local function render()
        if state then
            btn.BackgroundColor3 = (Themes[Config.Theme] or Themes.Default).Accent
            knob.BackgroundColor3 = (Themes[Config.Theme] or Themes.Default).Text
            knob.Position = UDim2.new(1, -knob.Size.X.Offset - tokens.InputPadSm, 0.5, -knob.Size.Y.Offset / 2)
        else
            btn.BackgroundColor3 = (Themes[Config.Theme] or Themes.Default).Panel
            knob.BackgroundColor3 = (Themes[Config.Theme] or Themes.Default).Muted
            knob.Position = UDim2.new(0, tokens.InputPadSm, 0.5, -knob.Size.Y.Offset / 2)
        end
    end

    local function setState(val, silent)
        state = val
        if flag and State.Config and State.Config.Set then
            State.Config.Set(flag, val)
        end
        render()
        if callback and not silent then
            callback(val)
        end
    end

    btn.MouseButton1Click:Connect(function()
        if disabled then
            return
        end
        setState(not state, false)
    end)

    render()
    ToggleRenders[#ToggleRenders + 1] = render
    if callback then
        callback(state)
    end

    return {
        Set = function(_, v)
            setState(v, true)
        end,
        Get = function()
            return state
        end,
        SetEnabled = function(_, enabled)
            disabled = not enabled
            label.TextTransparency = disabled and 0.4 or 0
            btn.BackgroundTransparency = disabled and 0.4 or 0
            knob.BackgroundTransparency = disabled and 0.4 or 0
        end,
        Frame = frame,
        Button = btn,
        Label = label,
        Destroy = function()
            frame:Destroy()
        end
    }
end

State.UI.EnhanceSliderWithChevrons = State.UI.EnhanceSliderWithChevrons or function(slider, opts)
    if not slider or not slider.Frame then
        return nil
    end
    local t = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {}
    local frame = slider.Frame
    local label = slider.Label
    local bar = slider.Bar
    local step = (opts and opts.Step) or 0.1
    local minV = (opts and opts.Min) or 0
    local maxV = (opts and opts.Max) or 1
    local onStep = (opts and opts.OnStep) or nil

    if frame:FindFirstChild("ChevronLeft") then
        return {
            Left = frame:FindFirstChild("ChevronLeft"),
            Right = frame:FindFirstChild("ChevronRight")
        }
    end

    local chevronW = math.max(18, t.SliderChevronW or 22)
    local chevronH = math.max(18, t.SliderChevronH or 22)
    local gap = math.max(2, t.InputPadSm or 4)
    local barY = math.max(
        (t.RowPadY or 4) + (chevronH - (t.SliderBarH or 8)),
        (t.SliderBarTop or 26)
    )

    if label then
        label.Position = UDim2.new(0, 0, 0, 0)
        label.Size = UDim2.new(1, 0, 0, math.max(16, (t.RowTall or 44) - (t.SliderBarTop or 26)))
    end

    if bar then
        bar.Position = UDim2.new(0, chevronW + gap, 0, barY)
        bar.Size = UDim2.new(
            1,
            -(chevronW * 2 + gap * 2),
            0,
            t.SliderBarH or 8
        )
    end

    local leftBtn = Instance.new("ImageButton")
    leftBtn.Name = "ChevronLeft"
    leftBtn.Size = UDim2.new(0, chevronW, 0, chevronH)
    leftBtn.Position = UDim2.new(0, 0, 0, barY - math.floor((chevronH - (t.SliderBarH or 8)) / 2))
    leftBtn.BorderSizePixel = 0
    leftBtn.AutoButtonColor = false
    leftBtn.Image = ""
    leftBtn.ScaleType = Enum.ScaleType.Fit
    leftBtn.Parent = frame
    registerTheme(leftBtn, "BackgroundColor3", "Panel")
    addCorner(leftBtn, t.SliderChevronRadius or 6)

    local leftIcon = Instance.new("ImageLabel")
    leftIcon.Size = UDim2.new(0.5, 0, 0.5, 0)
    leftIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    leftIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    leftIcon.BackgroundTransparency = 1
    leftIcon.Parent = leftBtn
    leftIcon.Image = (State.UI and State.UI.IconAssets and State.UI.IconAssets.ArrowLeft) or ""
    registerTheme(leftIcon, "ImageColor3", "Text")

    local rightBtn = Instance.new("ImageButton")
    rightBtn.Name = "ChevronRight"
    rightBtn.Size = UDim2.new(0, chevronW, 0, chevronH)
    rightBtn.Position = UDim2.new(1, -chevronW, 0, barY - math.floor((chevronH - (t.SliderBarH or 8)) / 2))
    rightBtn.BorderSizePixel = 0
    rightBtn.AutoButtonColor = false
    rightBtn.Image = ""
    rightBtn.ScaleType = Enum.ScaleType.Fit
    rightBtn.Parent = frame
    registerTheme(rightBtn, "BackgroundColor3", "Panel")
    addCorner(rightBtn, t.SliderChevronRadius or 6)

    local rightIcon = Instance.new("ImageLabel")
    rightIcon.Size = UDim2.new(0.5, 0, 0.5, 0)
    rightIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    rightIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    rightIcon.BackgroundTransparency = 1
    rightIcon.Parent = rightBtn
    rightIcon.Image = (State.UI and State.UI.IconAssets and State.UI.IconAssets.ArrowRight) or ""
    registerTheme(rightIcon, "ImageColor3", "Text")

    local function stepValue(delta)
        local current = (slider.Get and slider:Get()) or minV
        local value = math.clamp((tonumber(current) or minV) + delta, minV, maxV)
        if slider.SetValue then
            slider:SetValue(value, false)
        elseif slider.Set then
            slider:Set(value)
        end
        if onStep then
            onStep(value)
        end
    end

    leftBtn.MouseButton1Click:Connect(function()
        stepValue(-step)
    end)
    rightBtn.MouseButton1Click:Connect(function()
        stepValue(step)
    end)

    return {
        Left = leftBtn,
        Right = rightBtn
    }
end

local function createSlider(parent, text, flag, rangeMin, rangeMax, currentValue, callback, decimals, formatFn)
    local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
        RowTall = 44,
        SliderBarH = 8,
        SliderBarPadX = 10,
        SliderBarTop = 26,
        RowPadX = 10,
        RowPadY = 4,
        RadiusSm = 6,
        InputPadSm = 4
    }
    local value = currentValue
    if flag and State.Config and State.Config.Get then
        value = State.Config.Get(flag, value)
    end

    local sliderRowH = math.max(tokens.RowTall, (tokens.RowPadY * 2) + (tokens.SliderChevronH or 22))
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, sliderRowH)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, tokens.RadiusSm)
    addStroke(frame, "Muted", 1, 0.8)

    local framePad = Instance.new("UIPadding")
    framePad.PaddingLeft = UDim.new(0, tokens.RowPadX)
    framePad.PaddingRight = UDim.new(0, tokens.RowPadX)
    framePad.Parent = frame

    local function formatValue(v)
        if formatFn then
            local ok, res = pcall(formatFn, v)
            if ok and res ~= nil then
                return tostring(res)
            end
        end
        if type(decimals) == "number" then
            local d = math.clamp(math.floor(decimals + 0.5), 0, 6)
            return string.format("%." .. tostring(d) .. "f", v)
        end
        return tostring(v)
    end

    local labelH = math.max(16, sliderRowH - (tokens.SliderBarH + tokens.RowPadY * 2 + 4))
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, labelH)
    label.Position = UDim2.new(0, 0, 0, tokens.RowPadY)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Text = text .. ": " .. formatValue(value)
    label.Parent = frame
    setFontClass(label, "Body")
    registerTheme(label, "TextColor3", "Text")

    local bar = Instance.new("Frame")
    bar.Name = "SliderBar"
    bar.Size = UDim2.new(1, 0, 0, tokens.SliderBarH)
    bar.Position = UDim2.new(0, 0, 0, sliderRowH - tokens.RowPadY - tokens.SliderBarH)
    bar.BorderSizePixel = 0
    bar.Parent = frame
    bar.Active = true
    registerTheme(bar, "BackgroundColor3", "Panel")
    addCorner(bar, tokens.RadiusSm)

    local fill = Instance.new("Frame")
    fill.Name = "SliderFill"
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    registerTheme(fill, "BackgroundColor3", "Accent")
    addCorner(fill, tokens.RadiusSm)

    local function setValue(v, silent)
        value = math.clamp(v, rangeMin, rangeMax)
        label.Text = text .. ": " .. formatValue(value)
        fill.Size = UDim2.new((value - rangeMin) / (rangeMax - rangeMin), 0, 1, 0)
        if flag and State.Config and State.Config.Set then
            State.Config.Set(flag, value)
        end
        if callback and not silent then
            callback(value)
        end
    end

    local dragging = false
    local disabled = false
    bar.InputBegan:Connect(function(input)
        if disabled then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local pos = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
            setValue(rangeMin + (rangeMax - rangeMin) * pos, false)
        end
    end)

    trackConnection(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local pos = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
            setValue(rangeMin + (rangeMax - rangeMin) * pos, false)
        end
    end))

    trackConnection(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    setValue(value, true)
    if callback then
        callback(value)
    end

    local sliderObj = {
        Set = function(_, v)
            setValue(v, true)
        end,
        SetValue = function(_, v, silent)
            setValue(v, silent == true)
        end,
        Get = function()
            return value
        end,
        SetEnabled = function(_, enabled)
            disabled = not enabled
            label.TextTransparency = disabled and 0.4 or 0
            bar.BackgroundTransparency = disabled and 0.4 or 0
            fill.BackgroundTransparency = disabled and 0.4 or 0
        end,
        Frame = frame,
        Label = label,
        Bar = bar,
        Fill = fill,
        Destroy = function()
            frame:Destroy()
        end
    }

    local step = 1
    if type(decimals) == "number" and decimals > 0 then
        step = 1 / (10 ^ math.min(6, math.max(1, math.floor(decimals + 0.5))))
    end
    State.UI.EnhanceSliderWithChevrons(sliderObj, {
        Min = rangeMin,
        Max = rangeMax,
        Step = step
    })

    return sliderObj
end

-- =====================================================
-- AUTO BUY LOG UI (SEPARATE WINDOW)
-- =====================================================
local AutoBuyLogState = {
    Enabled = false,
    ActiveGroups = {},
    ActivePotions = {},
    ActiveDeposits = {},
    ActiveActions = {},
    GroupData = {},
    PotionData = {},
    DepositData = {},
    ActionData = {},
    GroupUI = {},
    ActiveItem = {},
    LastActive = {},
    SkippedMaxed = {},
    ScreenGui = nil,
    Frame = nil,
    Content = nil,
    CountLabel = nil,
    CloseBtn = nil,
    ToggleControl = nil,
    Dragging = false,
    DragStart = nil,
    StartPos = nil,
    Resizing = false,
    ResizeStart = nil,
    ResizeStartSize = nil,
    UserMoved = false,
    LastPosition = nil,
    MinRefreshInterval = 0.25,
    NextRefreshAt = 0,
    RefreshQueued = false,
    UpdateToken = 0,
    LastStructureSignature = "",
    BuiltOnce = false,
    PotionUI = {},
    ActionUI = {},
    DepositUI = {}
}

AutoBuyLogState.FormatRatioX = AutoBuyLogState.FormatRatioX or function(ownNum, depositNum, ownRaw, depositRaw)
    local function toSimpleNumberString(raw)
        if raw == nil then
            return ""
        end
        return tostring(raw):lower():gsub("%s+", ""):gsub(",", ".")
    end
    local function getMagnitude(raw, num)
        local n = tonumber(num)
        if type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge then
            if n < 0 then
                return nil
            end
            if n == 0 then
                return -math.huge
            end
            return math.log10(n)
        end
        local text = toSimpleNumberString(raw)
        if text == "" then
            return nil
        end
        local plainNum = tonumber(text)
        if type(plainNum) == "number" and plainNum == plainNum and plainNum ~= math.huge and plainNum ~= -math.huge then
            if plainNum < 0 then
                return nil
            end
            if plainNum == 0 then
                return -math.huge
            end
            return math.log10(plainNum)
        end
        local mantissaText, expText, expSuffix = text:match("^([%+%-]?%d*%.?%d+)[eE]([%+%-]?%d*%.?%d+)([kmb]?)$")
        if not mantissaText then
            return nil
        end
        local mantissa = tonumber(mantissaText)
        local expBase = tonumber(expText)
        if type(mantissa) ~= "number" or type(expBase) ~= "number" then
            return nil
        end
        if mantissa < 0 then
            return nil
        end
        if mantissa == 0 then
            return -math.huge
        end
        local expScale = 1
        if expSuffix == "k" then
            expScale = 1e3
        elseif expSuffix == "m" then
            expScale = 1e6
        elseif expSuffix == "b" then
            expScale = 1e9
        end
        return math.log10(mantissa) + (expBase * expScale)
    end

    local own = tonumber(ownNum)
    local deposit = tonumber(depositNum)
    local ratio = nil
    if type(own) == "number" and own == own and own ~= math.huge and own ~= -math.huge
        and type(deposit) == "number" and deposit == deposit and deposit ~= math.huge and deposit ~= -math.huge
        and deposit > 0 then
        ratio = own / deposit
    else
        local ownMag = getMagnitude(ownRaw, ownNum)
        local depoMag = getMagnitude(depositRaw, depositNum)
        if type(ownMag) == "number" and type(depoMag) == "number" then
            if ownMag == -math.huge then
                ratio = 0
            else
                local logRatio = ownMag - depoMag
                if logRatio < -320 then
                    ratio = 0
                elseif logRatio <= 308 then
                    ratio = 10 ^ logRatio
                else
                    ratio = nil
                end
            end
        end
    end

    if type(ratio) ~= "number" or ratio ~= ratio then
        return "-"
    end
    if ratio == math.huge or ratio == -math.huge then
        return "-"
    end
    if ratio == 0 then
        return "0x"
    end
    if math.abs(ratio) >= 1e6 then
        local s = string.format("%.1e", ratio)
        local mantissa, exp = s:match("^([%-%d%.]+)e([%+%-]?%d+)$")
        if mantissa and exp then
            local expNum = tonumber(exp)
            if expNum then
                return mantissa .. "e" .. tostring(expNum) .. "x"
            end
        end
        return s .. "x"
    end

    local absRatio = math.abs(ratio)
    local decimals = 2
    if absRatio >= 100 then
        decimals = 0
    elseif absRatio >= 10 then
        decimals = 1
    elseif absRatio >= 1 then
        decimals = 2
    elseif absRatio >= 0.1 then
        decimals = 3
    else
        decimals = 4
    end

    local out = string.format("%." .. tostring(decimals) .. "f", ratio)
    out = out:gsub("%.?0+$", "")
    if out == "-0" then
        out = "0"
    end
    return out .. "x"
end

-- =====================================================
-- LAYOUT / SCALE
-- =====================================================
State.Layout = State.Layout or {}
State.Layout.GetViewport = State.Layout.GetViewport or function()
    local cam = workspace.CurrentCamera
    if cam then
        return cam.ViewportSize
    end
    return Vector2.new(0, 0)
end

State.Layout.GetInset = State.Layout.GetInset or function()
    local inset = Vector2.new(0, 0)
    pcall(function()
        local gs = game:GetService("GuiService")
        local v = gs:GetGuiInset()
        if typeof(v) == "Vector2" then
            inset = v
        end
    end)
    return inset
end

State.Layout.GetScale = State.Layout.GetScale or function()
    local vp = State.Layout.GetViewport and State.Layout.GetViewport() or Vector2.new(0, 0)
    if vp.X <= 0 or vp.Y <= 0 then
        return 1
    end
    local baseW, baseH = 1280, 720
    local scale = math.min(vp.X / baseW, vp.Y / baseH)
    return math.clamp(scale, 0.65, 1.15)
end

State.Layout.ApplyScale = State.Layout.ApplyScale or function(frame)
    if not frame then
        return
    end
    local scale = State.Layout.GetScale and State.Layout.GetScale() or 1
    local uiScale = frame:FindFirstChild("UIScale")
    if not uiScale then
        uiScale = Instance.new("UIScale")
        uiScale.Name = "UIScale"
        uiScale.Parent = frame
    end
    uiScale.Scale = scale
end

State.Layout.SaveRelative = State.Layout.SaveRelative or function(frame, stateTable)
    if not frame or not frame.Parent or not stateTable then
        return
    end
    local vp = State.Layout.GetViewport and State.Layout.GetViewport() or Vector2.new(0, 0)
    if vp.X <= 0 or vp.Y <= 0 then
        return
    end
    local absPos = frame.AbsolutePosition or Vector2.new(0, 0)
    local absSize = frame.AbsoluteSize or Vector2.new(0, 0)
    local anchor = frame.AnchorPoint or Vector2.new(0, 0)
    local anchorPos = Vector2.new(
        absPos.X + absSize.X * anchor.X,
        absPos.Y + absSize.Y * anchor.Y
    )
    local sx = math.clamp(anchorPos.X / vp.X, 0, 1)
    local sy = math.clamp(anchorPos.Y / vp.Y, 0, 1)
    stateTable.RelativePos = Vector2.new(sx, sy)
end

State.Layout.ApplyRelative = State.Layout.ApplyRelative or function(frame, stateTable)
    if not frame or not stateTable then
        return
    end
    local rel = stateTable.RelativePos
    if not rel then
        return
    end
    frame.Position = UDim2.new(rel.X, 0, rel.Y, 0)
end

State.Layout.ClampFrame = State.Layout.ClampFrame or function(frame, marginX, marginY)
    if not frame or not frame.Parent then
        return
    end
    local viewport = State.Layout.GetViewport and State.Layout.GetViewport() or Vector2.new(0, 0)
    if viewport.X <= 0 or viewport.Y <= 0 then
        return
    end
    local inset = State.Layout.GetInset and State.Layout.GetInset() or Vector2.new(0, 0)
    local absSize = frame.AbsoluteSize
    local w = (absSize and absSize.X and absSize.X > 0) and absSize.X or (frame.Size.X.Offset or 0)
    local h = (absSize and absSize.Y and absSize.Y > 0) and absSize.Y or (frame.Size.Y.Offset or 0)
    local absPos = frame.AbsolutePosition or Vector2.new(0, 0)
    local x = absPos.X or 0
    local y = absPos.Y or 0
    local mx = marginX or 0
    local my = marginY or 0
    local minX = inset.X + mx
    local minY = inset.Y + my
    local maxX = viewport.X - mx - w
    local maxY = viewport.Y - my - h
    if maxX < minX then
        maxX = minX
    end
    if maxY < minY then
        maxY = minY
    end
    local newX = math.clamp(x, minX, maxX)
    local newY = math.clamp(y, minY, maxY)
    local anchor = frame.AnchorPoint or Vector2.new(0, 0)
    frame.Position = UDim2.new(0, newX + w * anchor.X, 0, newY + h * anchor.Y)
end

State.Layout.ClampFrameSoft = State.Layout.ClampFrameSoft or function(frame, marginX, marginY)
    if not frame or not frame.Parent then
        return
    end
    local viewport = State.Layout.GetViewport and State.Layout.GetViewport() or Vector2.new(0, 0)
    if viewport.X <= 0 or viewport.Y <= 0 then
        return
    end
    local inset = State.Layout.GetInset and State.Layout.GetInset() or Vector2.new(0, 0)
    local absSize = frame.AbsoluteSize
    local w = (absSize and absSize.X and absSize.X > 0) and absSize.X or (frame.Size.X.Offset or 0)
    local h = (absSize and absSize.Y and absSize.Y > 0) and absSize.Y or (frame.Size.Y.Offset or 0)
    local absPos = frame.AbsolutePosition or Vector2.new(0, 0)
    local x = absPos.X or 0
    local y = absPos.Y or 0
    local mx = marginX or 0
    local my = marginY or 0
    local minX = inset.X
    local minY = inset.Y
    local maxX = viewport.X - w
    local maxY = viewport.Y - h
    local newX = x
    local newY = y

    if x < (minX - mx) then
        newX = minX
    elseif x > (maxX + mx) then
        newX = maxX
    end

    if y < (minY - my) then
        newY = minY
    elseif y > (maxY + my) then
        newY = maxY
    end

    local anchor = frame.AnchorPoint or Vector2.new(0, 0)
    frame.Position = UDim2.new(0, newX + w * anchor.X, 0, newY + h * anchor.Y)
end

State.LogLayout = State.LogLayout or {}
State.LogLayout.Width = State.LogLayout.Width or (Config.AutoBuyLogWidth or 200)
State.LogLayout.MarginX = State.LogLayout.MarginX or 12
State.LogLayout.MarginY = State.LogLayout.MarginY or State.LogLayout.MarginX
State.LogLayout.Gap = State.LogLayout.Gap or 8

State.LogLayout.GetViewport = State.LogLayout.GetViewport or function()
    if State.Layout and State.Layout.GetViewport then
        return State.Layout.GetViewport()
    end
    return Vector2.new(0, 0)
end

State.LogLayout.Apply = State.LogLayout.Apply or function()
    local auto = AutoBuyLogState
    if not auto then
        return
    end

    local viewport = State.LogLayout.GetViewport and State.LogLayout.GetViewport() or Vector2.new(0, 0)
    if viewport.X <= 0 or viewport.Y <= 0 then
        return
    end

    local inset = (State.Layout and State.Layout.GetInset and State.Layout.GetInset()) or Vector2.new(0, 0)

    local usableWidth = math.max(0, viewport.X - inset.X)
    local usableHeight = math.max(0, viewport.Y - inset.Y)

    local width = State.LogLayout.Width or 280
    local marginX = State.LogLayout.MarginX or State.LogLayout.Margin or 12
    local marginY = State.LogLayout.MarginY or State.LogLayout.Margin or 12
    local gap = State.LogLayout.Gap or 8
    local scale = (State.Layout and State.Layout.GetScale and State.Layout.GetScale()) or 1

    local autoFrame = auto and auto.Frame or nil

    if autoFrame then
        autoFrame.Size = UDim2.new(0, width, autoFrame.Size.Y.Scale, autoFrame.Size.Y.Offset)
    end
    if State.Layout and State.Layout.ApplyScale then
        if autoFrame then
            State.Layout.ApplyScale(autoFrame)
        end
    end

    local autoVisible = autoFrame and autoFrame.Visible
    if not autoVisible then
        return
    end

    local baseX = math.max(marginX, usableWidth - (width * scale) - marginX)

    local function getHeight(frame)
        if not frame then
            return 0
        end
        local abs = frame.AbsoluteSize.Y
        if abs and abs > 0 then
            return abs
        end
        return frame.Size.Y.Offset or 0
    end

    if autoVisible and auto.UserMoved and State.Layout and State.Layout.ApplyRelative and auto.RelativePos then
        State.Layout.ApplyRelative(autoFrame, auto)
    elseif autoVisible and not auto.UserMoved then
        local autoH = getHeight(autoFrame)
        autoFrame.Position = UDim2.new(0, baseX, 0, usableHeight - autoH - marginY)
    end

    if State.Layout and State.Layout.ClampFrame then
        if autoFrame and auto.UserMoved then
            State.Layout.ClampFrame(autoFrame, marginX, marginY)
        end
    end
end

local destroyAutoBuyLogUI
local updateAutoBuyLogUI

local function autoBuyLogSortedKeys(map)
    local out = {}
    if type(map) ~= "table" then
        return out
    end
    for k in pairs(map) do
        out[#out + 1] = k
    end
    table.sort(out, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return out
end

local function autoBuyLogStructureSignature()
    local parts = {}

    local activeGroupKeys = autoBuyLogSortedKeys(AutoBuyLogState.ActiveGroups)
    for _, groupKey in ipairs(activeGroupKeys) do
        parts[#parts + 1] = "G:" .. groupKey
        local data = AutoBuyLogState.GroupData[groupKey]
        if type(data) == "table" then
            local enabledShops = autoBuyLogSortedKeys(data.ShopEnabled or {})
            for _, shopKey in ipairs(enabledShops) do
                if data.ShopEnabled and data.ShopEnabled[shopKey] then
                    parts[#parts + 1] = "S:" .. groupKey .. ":" .. shopKey
                    local itemMap = data.ItemEnabled and data.ItemEnabled[shopKey]
                    local enabledItems = autoBuyLogSortedKeys(itemMap or {})
                    for _, itemName in ipairs(enabledItems) do
                        if itemMap and itemMap[itemName] then
                            parts[#parts + 1] = "I:" .. groupKey .. ":" .. shopKey .. ":" .. itemName
                        end
                    end
                end
            end
        end
    end

    local activePotionKeys = autoBuyLogSortedKeys(AutoBuyLogState.ActivePotions)
    for _, key in ipairs(activePotionKeys) do
        parts[#parts + 1] = "P:" .. key
    end

    local activeDepositKeys = autoBuyLogSortedKeys(AutoBuyLogState.ActiveDeposits)
    for _, key in ipairs(activeDepositKeys) do
        local info = AutoBuyLogState.ActiveDeposits[key]
        local itemParts = {}
        local items = type(info) == "table" and info.Items or nil
        if type(items) == "table" and #items > 0 then
            for _, entry in ipairs(items) do
                local itemName = tostring((entry and entry.Name) or "-")
                itemParts[#itemParts + 1] = itemName
            end
        else
            itemParts[#itemParts + 1] = tostring((info and info.ItemName) or "-")
        end
        parts[#parts + 1] = "D:" .. key .. ":" .. table.concat(itemParts, ",")
    end

    local activeActionKeys = autoBuyLogSortedKeys(AutoBuyLogState.ActiveActions)
    for _, key in ipairs(activeActionKeys) do
        parts[#parts + 1] = "A:" .. key
    end

    return table.concat(parts, "|")
end

local function autoBuyLogNeedsComplexRebuild()
    local complexActions = {
        HellAutoDropper = true,
        Event500KAutoUpgradeTree = true,
        GardenAutoUpgradeTree = true,
        DesertAutoUpgradePointsTree = true,
        DesertAutoUpgradeBetterPointsTree = true
    }
    for key in pairs(AutoBuyLogState.ActiveActions or {}) do
        if complexActions[tostring(key)] then
            return true
        end
    end
    return false
end

local function refreshAutoBuyLogDynamicValues()
    for groupKey in pairs(AutoBuyLogState.ActiveGroups or {}) do
        if AutoBuyLogState.UpdateGroupActiveIndicator then
            AutoBuyLogState.UpdateGroupActiveIndicator(groupKey)
        end
        if AutoBuyLogState.RefreshGroupValues then
            AutoBuyLogState.RefreshGroupValues(groupKey)
        end
    end

    for potionKey, info in pairs(AutoBuyLogState.ActivePotions or {}) do
        local row = AutoBuyLogState.PotionUI and AutoBuyLogState.PotionUI[potionKey]
        if row and row.Label and row.Label.Parent then
            row.Label.Text = tostring(info.Name or info.Key or "Potion Shop") .. " | (" .. tostring(info.Success or 0) .. ")"
        end
    end

    for depositKey, info in pairs(AutoBuyLogState.ActiveDeposits or {}) do
        local section = AutoBuyLogState.DepositUI and AutoBuyLogState.DepositUI[depositKey]
        if section and section.Header and section.Header.Parent then
            section.Header.Text = tostring(info.Name or info.Key or "Deposit")
        end
        local rows = section and section.RowsByItem or nil
        if rows and type(rows) == "table" then
            local itemTotals = type(info.ItemTotals) == "table" and info.ItemTotals or {}
            local items = type(info.Items) == "table" and info.Items or {}
            local hasItems = false

            for _, entry in ipairs(items) do
                local itemName = tostring((entry and entry.Name) or "-")
                local row = rows[itemName]
                if row and row.Detail and row.Detail.Parent then
                    if row.Label and row.Label.Parent then
                        row.Label.Text = itemName
                    end
                    local ownNum = tonumber(entry and entry.OwnNum)
                    local depositNum = tonumber(entry and entry.DepositNum)
                    local itemTotal = tonumber(itemTotals[itemName]) or 0
                    row.Detail.Text = AutoBuyLogState.BuildDepositItemDetailText(
                        ownNum,
                        depositNum,
                        itemTotal,
                        entry and entry.OwnRaw or nil,
                        entry and entry.DepositRaw or nil
                    )
                    hasItems = true
                end
            end

            if (not hasItems) and section.PrimaryRow and section.PrimaryRow.Detail and section.PrimaryRow.Detail.Parent then
                local itemName = tostring(info.ItemName or "-")
                if section.PrimaryRow.Label and section.PrimaryRow.Label.Parent then
                    section.PrimaryRow.Label.Text = itemName
                end
                local ownNum = tonumber(info.OwnNum)
                local depositNum = tonumber(info.DepositNum)
                local itemTotal = tonumber(itemTotals[itemName]) or tonumber(info.Success) or 0
                section.PrimaryRow.Detail.Text = AutoBuyLogState.BuildDepositItemDetailText(
                    ownNum,
                    depositNum,
                    itemTotal,
                    info.OwnRaw,
                    info.DepositRaw
                )
            end
        end
    end

    for actionKey, info in pairs(AutoBuyLogState.ActiveActions or {}) do
        local row = AutoBuyLogState.ActionUI and AutoBuyLogState.ActionUI[actionKey]
        if row and row.Label and row.Label.Parent then
            row.Label.Text = tostring(info.Name or info.Key or "Action")
            if row.Detail and row.Detail.Parent then
                local showTotalClick = tostring(info.Key or "") == "GardenAutoClickFallTree"
                local detailText = tostring(info.DetailText or "")
                if showTotalClick then
                    row.Detail.Text = "Total Click: " .. tostring(tonumber(info.Success) or 0)
                else
                    row.Detail.Text = detailText
                end
            end
        end
    end
end

local function getActiveAutoBuyCount()
    local n = 0
    for _ in pairs(AutoBuyLogState.ActiveGroups) do
        n += 1
    end
    for _ in pairs(AutoBuyLogState.ActivePotions) do
        n += 1
    end
    for _ in pairs(AutoBuyLogState.ActiveDeposits) do
        n += 1
    end
    for _ in pairs(AutoBuyLogState.ActiveActions) do
        n += 1
    end
    return n
end

destroyAutoBuyLogUI = function()
    AutoBuyLogState.UpdateToken = (tonumber(AutoBuyLogState.UpdateToken) or 0) + 1
    AutoBuyLogState.RefreshQueued = false
    AutoBuyLogState.NextRefreshAt = 0
    AutoBuyLogState.LastStructureSignature = ""
    AutoBuyLogState.BuiltOnce = false
    AutoBuyLogState.PotionUI = {}
    AutoBuyLogState.ActionUI = {}
    AutoBuyLogState.DepositUI = {}
    if AutoBuyLogState.ScreenGui and AutoBuyLogState.ScreenGui.Parent then
        AutoBuyLogState.ScreenGui:Destroy()
    end
    AutoBuyLogState.ScreenGui = nil
    AutoBuyLogState.Frame = nil
    AutoBuyLogState.Content = nil
    AutoBuyLogState.CountLabel = nil
    AutoBuyLogState.CloseBtn = nil
    AutoBuyLogState.GroupUI = {}
    AutoBuyLogState.LastActive = {}
    AutoBuyLogState.Resizing = false
    AutoBuyLogState.ResizeStart = nil
    AutoBuyLogState.ResizeStartSize = nil
    AutoBuyLogState.UserMoved = false
    AutoBuyLogState.RelativePos = nil
    AutoBuyLogState.LastPosition = nil
    if State.LogLayout and State.LogLayout.Apply then
        State.LogLayout.Apply()
    end
end

local function setAutoBuyLogToggle(value)
    Config.AutoBuyLogEnabled = value == true
    saveConfig()
    if AutoBuyLogState.ToggleControl and AutoBuyLogState.ToggleControl.Set then
        AutoBuyLogState.ToggleControl:Set(Config.AutoBuyLogEnabled)
    end
end

toggleAutoBuyLogKeybind = function()
    local nextValue = not Config.AutoBuyLogEnabled
    setAutoBuyLogToggle(nextValue)
    if nextValue then
        updateAutoBuyLogUI()
    else
        destroyAutoBuyLogUI()
    end
end

local function createAutoBuyLogUI()
    if AutoBuyLogState.ScreenGui and AutoBuyLogState.Frame then
        return
    end

    local logGui = Instance.new("ScreenGui")
    logGui.Name = "GardenIncrementalAutoBuyLog"
    logGui.ResetOnSpawn = false
    if gethui then
        logGui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(logGui)
        logGui.Parent = game:GetService("CoreGui")
    else
        logGui.Parent = game:GetService("CoreGui")
    end

    local startW = math.clamp(math.floor((tonumber(Config.AutoBuyLogWidth) or 200) + 0.5), 180, 520)
    local startH = math.clamp(math.floor((tonumber(Config.AutoBuyLogHeight) or 300) + 0.5), 140, 700)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, startW, 0, startH)
    frame.AnchorPoint = Vector2.new(0, 0)
    frame.Position = UDim2.new(0, 40, 0, 40)
    frame.BorderSizePixel = 0
    frame.Parent = logGui
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, 10)
    addStroke(frame, "Muted", 1, 0.6)
    addGradient(frame, 90, 0, 0.15)
    if State.Layout and State.Layout.ApplyScale then
        State.Layout.ApplyScale(frame)
    end
    if State.LogLayout then
        State.LogLayout.Width = startW
    end

    local logTokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {}
    local logBtnW = math.max(18, (logTokens.ButtonW or 24) - 4)
    local logBtnH = math.max(16, (logTokens.ButtonH or 20) - 2)
    local logBtnY = math.max(2, math.floor((26 - logBtnH) / 2))

    local titleBar = Instance.new("TextLabel")
    titleBar.Size = UDim2.new(1, -(logBtnW + 50), 0, 26)
    titleBar.Position = UDim2.new(0, 10, 0, 0)
    titleBar.BackgroundTransparency = 1
    titleBar.Font = Enum.Font.GothamSemibold
    titleBar.TextSize = 13
    titleBar.TextXAlignment = Enum.TextXAlignment.Left
    titleBar.Text = "Automation Log"
    titleBar.Parent = frame
    titleBar.Active = true
    setFontClass(titleBar, "Heading")
    registerTheme(titleBar, "TextColor3", "Text")

    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(0, 40, 0, 18)
    countLabel.Position = UDim2.new(1, -(logBtnW + 46), 0, 4)
    countLabel.BackgroundTransparency = 1
    countLabel.Font = Enum.Font.Gotham
    countLabel.TextSize = 12
    countLabel.TextXAlignment = Enum.TextXAlignment.Right
    countLabel.Text = "0"
    countLabel.Parent = frame
    setFontClass(countLabel, "Small")
    registerTheme(countLabel, "TextColor3", "Muted")

    local closeBtn = State.UI.BuildMiniIconButton({
        Parent = frame,
        Tokens = logTokens,
        Size = UDim2.new(0, logBtnW, 0, logBtnH),
        Position = UDim2.new(1, -(logBtnW + 6), 0, logBtnY),
        Icon = CLOSE_ICON_ASSET,
        FallbackText = "x"
    })

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 2)
    line.Position = UDim2.new(0, 0, 0, 26)
    line.BorderSizePixel = 0
    line.Parent = frame
    registerTheme(line, "BackgroundColor3", "Accent")

    local content = Instance.new("ScrollingFrame")
    content.Size = UDim2.new(1, 0, 1, -36)
    content.Position = UDim2.new(0, 0, 0, 32)
    content.BorderSizePixel = 0
    content.BackgroundTransparency = 1
    content.ScrollBarThickness = 4
    content.ScrollingDirection = Enum.ScrollingDirection.Y
    content.CanvasSize = UDim2.new(0, 0, 0, 0)
    content.Parent = frame

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 6)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = content

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = content

    trackConnection(list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        content.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 8)
    end))

    trackConnection(closeBtn.MouseButton1Click:Connect(function()
        setAutoBuyLogToggle(false)
        destroyAutoBuyLogUI()
    end))

    if State.UI and State.UI.BindFrameDrag then
        State.UI.BindFrameDrag(titleBar, frame, AutoBuyLogState, {
            BlockIf = function()
                return AutoBuyLogState.Resizing == true
            end,
            OnChanged = function(delta)
                if delta.X ~= 0 or delta.Y ~= 0 then
                    AutoBuyLogState.UserMoved = true
                end
                AutoBuyLogState.LastPosition = frame.Position
            end,
            OnEnd = function()
                if State.Layout and State.Layout.SaveRelative then
                    State.Layout.SaveRelative(frame, AutoBuyLogState)
                end
            end
        })
    end

    local resizeHandle = Instance.new("TextButton")
    resizeHandle.Name = "ResizeBottomRight"
    resizeHandle.Size = UDim2.new(0, 16, 0, 16)
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.Position = UDim2.new(1, -4, 1, -4)
    resizeHandle.BorderSizePixel = 0
    resizeHandle.Text = ""
    resizeHandle.AutoButtonColor = false
    resizeHandle.ZIndex = 5
    resizeHandle.Parent = frame
    registerTheme(resizeHandle, "BackgroundColor3", "Main")
    addCorner(resizeHandle, 4)
    addStroke(resizeHandle, "Muted", 1, 0.6)

    local resizeIcon = Instance.new("ImageLabel")
    resizeIcon.Name = "ResizeIcon"
    resizeIcon.Size = UDim2.new(1, -4, 1, -4)
    resizeIcon.Position = UDim2.new(0, 2, 0, 2)
    resizeIcon.BackgroundTransparency = 1
    resizeIcon.BorderSizePixel = 0
    resizeIcon.Image = resolveResizeIcon()
    resizeIcon.ScaleType = Enum.ScaleType.Fit
    resizeIcon.ZIndex = resizeHandle.ZIndex + 1
    resizeIcon.Parent = resizeHandle
    registerTheme(resizeIcon, "ImageColor3", "Muted")

    if State.UI and State.UI.BindFrameResizeBottomRight then
        State.UI.BindFrameResizeBottomRight(resizeHandle, frame, AutoBuyLogState, {
            MinW = 180,
            MaxW = 520,
            MinH = 140,
            MaxH = 700,
            OnChanged = function()
                if State.LogLayout then
                    State.LogLayout.Width = frame.Size.X.Offset
                end
                if State.LogLayout and State.LogLayout.Apply then
                    State.LogLayout.Apply()
                end
            end,
            OnEnd = function()
                local w = math.clamp(frame.Size.X.Offset, 180, 520)
                local h = math.clamp(frame.Size.Y.Offset, 140, 700)
                Config.AutoBuyLogWidth = w
                Config.AutoBuyLogHeight = h
                if State.LogLayout then
                    State.LogLayout.Width = w
                end
                saveConfig()
                if State.LogLayout and State.LogLayout.Apply then
                    State.LogLayout.Apply()
                end
            end
        })
    end

    AutoBuyLogState.ScreenGui = logGui
    AutoBuyLogState.Frame = frame
    AutoBuyLogState.Content = content
    AutoBuyLogState.CountLabel = countLabel
    AutoBuyLogState.CloseBtn = closeBtn
    State.AutoBuyLogGui = logGui

    task.delay(0, function()
        if State.LogLayout and State.LogLayout.Apply then
            State.LogLayout.Apply()
        end
    end)
end

local function autoBuyLogReadNumeric(node)
    if not node then
        return nil
    end
    local ok, raw = pcall(function()
        return node.Value
    end)
    if not ok then
        return nil
    end
    return tonumber(raw)
end

local function autoBuyLogCandidateList(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and #v > 0 then
            out[#out + 1] = v
        end
    end
    return out
end

local function autoBuyLogResolveFolder(parent, names)
    if not parent or type(names) ~= "table" then
        return nil, nil
    end
    for _, name in ipairs(names) do
        if type(name) == "string" and #name > 0 then
            local child = parent:FindFirstChild(name)
            if child then
                return child, name
            end
        end
    end
    return nil, nil
end

local function autoBuyLogResolveUpgradeLevel(shop, itemName)
    if not LP or not shop or type(itemName) ~= "string" then
        return nil
    end
    local upgrades = LP:FindFirstChild("Upgrades")
    if not upgrades then
        return nil
    end
    local itemMeta = shop.MetaByItem and shop.MetaByItem[itemName] or nil
    local folder, _ = autoBuyLogResolveFolder(
        upgrades,
        autoBuyLogCandidateList(
            shop.UpgradeFolderName,
            shop.ModuleName,
            itemMeta and itemMeta.CostCurrency or nil,
            shop.CurrencyName,
            shop.ShopName,
            shop.Key
        )
    )
    if not folder then
        return nil
    end
    local levelNode = folder:FindFirstChild(itemName)
    if not levelNode and type(itemName) == "string" then
        local targetName = string.lower(itemName)
        for _, child in ipairs(folder:GetChildren()) do
            if string.lower(tostring(child.Name)) == targetName then
                levelNode = child
                break
            end
        end
    end
    local level = autoBuyLogReadNumeric(levelNode)
    if type(level) == "number" then
        return math.max(0, math.floor(level + 0.5))
    end
    return nil
end

local function autoBuyLogResolveCurrencyAmount(shop, itemName)
    if not LP or not shop then
        return nil
    end
    local currencyRoot = LP:FindFirstChild("Currency")
    if not currencyRoot then
        return nil
    end
    local itemMeta = shop.MetaByItem and shop.MetaByItem[itemName] or nil
    local folder, _ = autoBuyLogResolveFolder(
        currencyRoot,
        autoBuyLogCandidateList(
            itemMeta and itemMeta.CostCurrency or nil,
            shop.CurrencyName,
            shop.ShopName,
            shop.Key
        )
    )
    if not folder then
        return nil
    end
    local amountFolder = folder:FindFirstChild("Amount")
    if not amountFolder then
        return nil
    end
    local amountNode = amountFolder:FindFirstChild("1")
    if not amountNode then
        local children = amountFolder:GetChildren()
        if #children > 0 then
            amountNode = children[1]
        end
    end
    return autoBuyLogReadNumeric(amountNode)
end

local function autoBuyLogToSci1(value)
    local num = tonumber(value)
    if type(num) ~= "number" or num ~= num then
        return tostring(value or "?")
    end
    if num == math.huge or num == -math.huge then
        return tostring(value or "?")
    end
    if num == 0 then
        return "0"
    end

    local function truncateDecimals(v, decimals)
        local d = tonumber(decimals) or 0
        if d < 0 then
            d = 0
        end
        local factor = 10 ^ d
        if v >= 0 then
            return math.floor(v * factor) / factor
        end
        return math.ceil(v * factor) / factor
    end

    local absNum = math.abs(num)
    local expNum = math.floor(math.log10(absNum))
    local mantissa = num / (10 ^ expNum)
    local mantissaTrunc = truncateDecimals(mantissa, 1)

    if mantissaTrunc >= 10 or mantissaTrunc <= -10 then
        mantissaTrunc = mantissaTrunc / 10
        expNum = expNum + 1
    end

    local mantissaText = string.format("%.1f", mantissaTrunc)
    if mantissaText == "-0.0" then
        mantissaText = "0.0"
    end
    return mantissaText .. "e" .. tostring(expNum)
end

local function autoBuyLogFormatRawFallback(raw)
    if raw == nil then
        return "?"
    end
    local text = tostring(raw)
    local compact = text:gsub("%s+", "")
    local sign, mantissaText, expText, expSuffix = compact:match("^([%+%-]?)(%d*%.?%d+)[eE]([%+%-]?%d*%.?%d+)([kmbKMB]?)$")
    if not mantissaText then
        return text
    end

    local intPart, fracPart = mantissaText:match("^(%d*)%.?(%d*)$")
    if intPart == nil then
        return text
    end
    if intPart == "" then
        intPart = "0"
    end
    fracPart = fracPart or ""
    local firstFrac = fracPart:sub(1, 1)
    if firstFrac == "" then
        firstFrac = "0"
    end

    local expOut = expText
    local expNum = tonumber(expText)
    if expNum then
        expOut = tostring(expNum)
    end
    return sign .. intPart .. "." .. firstFrac .. "e" .. expOut .. string.lower(expSuffix or "")
end

local function autoBuyLogFormatNumber(value)
    local num = tonumber(value)
    if type(num) ~= "number" or num ~= num then
        return "?"
    end
    if num == 0 then
        return "0"
    end
    local sci = autoBuyLogToSci1(num)
    local absNum = math.abs(num)
    local suffixes = {
        {1e3, "K"},
        {1e6, "M"},
        {1e9, "B"},
        {1e12, "T"},
        {1e15, "Qd"},
        {1e18, "Qn"},
        {1e21, "Sx"},
        {1e24, "Sp"},
        {1e27, "Oc"},
        {1e30, "No"},
        {1e33, "De"},
        {1e36, "UDe"},
        {1e39, "DDe"},
        {1e42, "TDe"},
        {1e45, "QdDe"},
        {1e48, "QnDe"},
        {1e51, "SxDe"},
        {1e54, "SpDe"},
        {1e57, "OcDe"},
        {1e60, "NoDe"},
        {1e63, "VgDe"}
    }
    local function formatPlain(n)
        local absN = math.abs(n)
        local decimals = 0
        if absN < 10 then
            decimals = 2
        elseif absN < 100 then
            decimals = 1
        end
        local out = string.format("%." .. tostring(decimals) .. "f", n)
        out = out:gsub("%.?0+$", "")
        if out == "-0" then
            out = "0"
        end
        return out
    end
    if absNum < 1000 then
        return formatPlain(num) .. " (" .. sci .. ")"
    end
    local chosen = nil
    for i = #suffixes, 1, -1 do
        if absNum >= suffixes[i][1] then
            chosen = suffixes[i]
            break
        end
    end
    if not chosen then
        return formatPlain(num) .. " (" .. sci .. ")"
    end
    local scaled = num / chosen[1]
    local absScaled = math.abs(scaled)
    local decimals = 0
    if absScaled < 10 then
        decimals = 2
    elseif absScaled < 100 then
        decimals = 1
    end
    local out = string.format("%." .. tostring(decimals) .. "f", scaled)
    out = out:gsub("%.?0+$", "")
    return out .. tostring(chosen[2]) .. " (" .. sci .. ")"
end

local function autoBuyLogGetItemInfo(shop, itemName)
    local itemMeta = shop and shop.MetaByItem and shop.MetaByItem[itemName] or nil
    if not itemMeta and shop and type(itemName) == "string" and type(shop.MetaByItem) == "table" then
        local function normalizeItemName(text)
            if type(text) ~= "string" then
                return ""
            end
            return string.lower(text):gsub("[^%w]", "")
        end
        local targetNorm = normalizeItemName(itemName)
        if #targetNorm > 0 then
            for key, meta in pairs(shop.MetaByItem) do
                if normalizeItemName(key) == targetNorm then
                    itemMeta = meta
                    break
                end
            end
        end
    end
    local level = autoBuyLogResolveUpgradeLevel(shop, itemName)
    local maxLevel = itemMeta and itemMeta.MaxLevel or nil
    local maxed = false
    if type(level) == "number" and type(maxLevel) == "number" and level >= maxLevel then
        maxed = true
    end
    local cost = nil
    if itemMeta and type(itemMeta.CostFn) == "function" and not maxed then
        local nextLevel = (level or 0) + 1
        local ok, value = pcall(itemMeta.CostFn, nextLevel)
        if ok and type(value) == "number" then
            cost = value
        end
    end
    return {
        Level = level,
        MaxLevel = maxLevel,
        Cost = cost,
        Maxed = maxed
    }
end

local function autoBuyLogBuildDetailText(shop, itemName, forcedMaxed)
    local info = autoBuyLogGetItemInfo(shop, itemName)
    if forcedMaxed or info.Maxed then
        return "maxed", true
    end
    local levelText = type(info.Level) == "number" and tostring(info.Level) or "?"
    local costText = type(info.Cost) == "number" and autoBuyLogFormatNumber(info.Cost) or "?"
    return "Lv " .. levelText .. " | Cost " .. costText, false
end

local function autoBuyLogSetRowDetail(rowInfo, detailText, compact)
    if not rowInfo or not rowInfo.Row or not rowInfo.Label then
        return
    end
    local row = rowInfo.Row
    local label = rowInfo.Label
    local detail = rowInfo.Detail
    if compact then
        row.Size = UDim2.new(1, 0, 0, 22)
        label.Size = UDim2.new(1, -16, 1, 0)
        label.Position = UDim2.new(0, 14, 0, 0)
        label.TextYAlignment = Enum.TextYAlignment.Center
        if detail then
            detail.Visible = false
            detail.Text = ""
        end
    else
        row.Size = UDim2.new(1, 0, 0, 34)
        label.Size = UDim2.new(1, -16, 0, 16)
        label.Position = UDim2.new(0, 14, 0, 2)
        label.TextYAlignment = Enum.TextYAlignment.Top
        if detail then
            detail.Visible = true
            detail.Text = detailText or ""
        end
    end
end

local function rebuildAutoBuyLogContent()
    if not AutoBuyLogState.Content then
        return
    end
    for _, child in ipairs(AutoBuyLogState.Content:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local groups = {}
    for _, info in pairs(AutoBuyLogState.ActiveGroups) do
        groups[#groups + 1] = info
    end
    table.sort(groups, function(a, b)
        return tostring(a.Name) < tostring(b.Name)
    end)

    AutoBuyLogState.GroupUI = {}
    AutoBuyLogState.LastActive = {}
    AutoBuyLogState.PotionUI = {}
    AutoBuyLogState.ActionUI = {}
    AutoBuyLogState.DepositUI = {}

    local hasSection = false
    local function addSectionTitle(text)
        if hasSection then
            local spacer = Instance.new("Frame")
            spacer.Size = UDim2.new(1, 0, 0, 6)
            spacer.BorderSizePixel = 0
            spacer.BackgroundTransparency = 1
            spacer.Parent = AutoBuyLogState.Content
        end
        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 20)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamSemibold
        title.TextSize = 12
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = text
        title.Parent = AutoBuyLogState.Content
        setFontClass(title, "Heading")
        registerTheme(title, "TextColor3", "Text")
        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, 0, 0, 1)
        line.BorderSizePixel = 0
        line.Parent = AutoBuyLogState.Content
        registerTheme(line, "BackgroundColor3", "Muted")
        hasSection = true
    end

    if #groups > 0 then
        addSectionTitle("Auto Buy Shop")
    end

    for i, info in ipairs(groups) do
        local groupKey = info.Key
        local data = AutoBuyLogState.GroupData[groupKey] or {}
        local shops = data.Shops or {}
        local shopEnabled = data.ShopEnabled or {}
        local itemEnabled = data.ItemEnabled or {}

        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, 0)
        section.AutomaticSize = Enum.AutomaticSize.Y
        section.BorderSizePixel = 0
        section.Parent = AutoBuyLogState.Content
        registerTheme(section, "BackgroundColor3", "Panel")
        addCorner(section, 8)
        addStroke(section, "Muted", 1, 0.8)

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 22)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamSemibold
    header.TextSize = 12
    header.TextXAlignment = Enum.TextXAlignment.Left
    local headerText = tostring(info.Name or "AutoBuy")
    if info.Name == "Auto Buy Shop" and info.Key then
        headerText = tostring(info.Key)
    end
    header.Text = headerText
    header.Parent = section
    setFontClass(header, "Heading")
    registerTheme(header, "TextColor3", "Text")

        local body = Instance.new("Frame")
        body.Size = UDim2.new(1, 0, 0, 0)
        body.AutomaticSize = Enum.AutomaticSize.Y
        body.BorderSizePixel = 0
        body.BackgroundTransparency = 1
        body.Parent = section

        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 4)
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Parent = body

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 2)
        pad.PaddingBottom = UDim.new(0, 4)
        pad.PaddingLeft = UDim.new(0, 2)
        pad.PaddingRight = UDim.new(0, 2)
        pad.Parent = body

        AutoBuyLogState.GroupUI[groupKey] = {
            Frame = section,
            Scroll = body,
            Rows = {},
            ShopLabels = {}
        }

        local sectionList = Instance.new("UIListLayout")
        sectionList.Padding = UDim.new(0, 6)
        sectionList.SortOrder = Enum.SortOrder.LayoutOrder
        sectionList.Parent = section

        local sectionPad = Instance.new("UIPadding")
        sectionPad.PaddingTop = UDim.new(0, 6)
        sectionPad.PaddingBottom = UDim.new(0, 6)
        sectionPad.PaddingLeft = UDim.new(0, 6)
        sectionPad.PaddingRight = UDim.new(0, 6)
        sectionPad.Parent = section

        local addedAny = false
        for _, shop in ipairs(shops) do
            local shopKey = shop.Key
            if shopEnabled[shopKey] then
                local shopLabel = Instance.new("TextLabel")
                shopLabel.Size = UDim2.new(1, 0, 0, 20)
                shopLabel.BackgroundTransparency = 1
                shopLabel.Font = Enum.Font.GothamSemibold
                shopLabel.TextSize = 10
                shopLabel.TextXAlignment = Enum.TextXAlignment.Left
                local shopCurrency = autoBuyLogResolveCurrencyAmount(shop, nil)
                local shopCurrencyText = autoBuyLogFormatNumber(shopCurrency)
                shopLabel.Text = tostring(shop.DisplayName or shopKey or "Shop") .. "  (" .. shopCurrencyText .. ")"
                shopLabel.Parent = body
                setFontClass(shopLabel, "Tiny")
                registerTheme(shopLabel, "TextColor3", "Muted")
                AutoBuyLogState.GroupUI[groupKey].ShopLabels[shopKey] = {
                    Label = shopLabel,
                    Shop = shop
                }

                AutoBuyLogState.GroupUI[groupKey].Rows[shopKey] = AutoBuyLogState.GroupUI[groupKey].Rows[shopKey] or {}

                for _, item in ipairs(shop.Items or {}) do
                    if itemEnabled[shopKey] and itemEnabled[shopKey][item] then
                        local row = Instance.new("Frame")
                        row.Size = UDim2.new(1, 0, 0, 22)
                        row.BorderSizePixel = 0
                        row.Parent = body
                        registerTheme(row, "BackgroundColor3", "Main")
                        addCorner(row, 6)
                        addStroke(row, "Muted", 1, 0.6)

                        local indicator = Instance.new("Frame")
                        indicator.Size = UDim2.new(0, 6, 1, -6)
                        indicator.Position = UDim2.new(0, 4, 0, 3)
                        indicator.BorderSizePixel = 0
                        indicator.Visible = false
                        indicator.Parent = row
                        registerTheme(indicator, "BackgroundColor3", "Accent")
                        addCorner(indicator, 3)

                        local label = Instance.new("TextLabel")
                        label.Size = UDim2.new(1, -16, 1, 0)
                        label.Position = UDim2.new(0, 14, 0, 0)
                        label.BackgroundTransparency = 1
                        label.Font = Enum.Font.Gotham
                        label.TextSize = 11
                        label.TextWrapped = true
                        label.TextXAlignment = Enum.TextXAlignment.Left
                        label.TextYAlignment = Enum.TextYAlignment.Center
                        label.Text = tostring(item)
                        label.Parent = row
                        setFontClass(label, "Small")
                        registerTheme(label, "TextColor3", "Text")

                        local detail = Instance.new("TextLabel")
                        detail.Size = UDim2.new(1, -16, 0, 14)
                        detail.Position = UDim2.new(0, 14, 0, 18)
                        detail.BackgroundTransparency = 1
                        detail.Font = Enum.Font.Gotham
                        detail.TextSize = 9
                        detail.TextWrapped = true
                        detail.TextXAlignment = Enum.TextXAlignment.Left
                        detail.TextYAlignment = Enum.TextYAlignment.Top
                        detail.Text = ""
                        detail.Parent = row
                        setFontClass(detail, "Tiny")
                        registerTheme(detail, "TextColor3", "Muted")

                        local skipped = AutoBuyLogState.SkippedMaxed[groupKey]
                            and AutoBuyLogState.SkippedMaxed[groupKey][shopKey]
                            and AutoBuyLogState.SkippedMaxed[groupKey][shopKey][item]
                        local detailText, maxedByLevel = autoBuyLogBuildDetailText(shop, item, skipped == true)
                        local rowInfo = {
                            Row = row,
                            Indicator = indicator,
                            Label = label,
                            Detail = detail,
                            Shop = shop,
                            Item = item
                        }
                        autoBuyLogSetRowDetail(rowInfo, detailText, maxedByLevel == true)
                        if maxedByLevel then
                            skipped = true
                        end
                        if AutoBuyLogState.ApplyRowStyle then
                            AutoBuyLogState.ApplyRowStyle(row, skipped)
                        end

                        AutoBuyLogState.GroupUI[groupKey].Rows[shopKey][item] = rowInfo
                        addedAny = true
                    end
                end
            end
        end

        if not addedAny then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 20)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 11
            empty.TextXAlignment = Enum.TextXAlignment.Left
            empty.Text = "Tidak ada item aktif"
            empty.Parent = body
            setFontClass(empty, "Small")
            registerTheme(empty, "TextColor3", "Muted")
        end

        if i < #groups then
            local spacerTop = Instance.new("Frame")
            spacerTop.Size = UDim2.new(1, 0, 0, 6)
            spacerTop.BorderSizePixel = 0
            spacerTop.BackgroundTransparency = 1
            spacerTop.Parent = AutoBuyLogState.Content

            local div = Instance.new("Frame")
            div.Size = UDim2.new(1, 0, 0, 1)
            div.BorderSizePixel = 0
            div.Parent = AutoBuyLogState.Content
            registerTheme(div, "BackgroundColor3", "Muted")

            local spacerBottom = Instance.new("Frame")
            spacerBottom.Size = UDim2.new(1, 0, 0, 6)
            spacerBottom.BorderSizePixel = 0
            spacerBottom.BackgroundTransparency = 1
            spacerBottom.Parent = AutoBuyLogState.Content
        end
    end

    for _, info in ipairs(groups) do
        if AutoBuyLogState.UpdateGroupActiveIndicator then
            AutoBuyLogState.UpdateGroupActiveIndicator(info.Key)
        end
        if AutoBuyLogState.RefreshGroupValues then
            AutoBuyLogState.RefreshGroupValues(info.Key)
        end
    end

    local potionEntries = {}
    for _, info in pairs(AutoBuyLogState.ActivePotions) do
        potionEntries[#potionEntries + 1] = info
    end
    table.sort(potionEntries, function(a, b)
        return tostring(a.Name) < tostring(b.Name)
    end)

    if #potionEntries > 0 then
        addSectionTitle("Auto Buy Potion")
    end

    for _, info in ipairs(potionEntries) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 22)
        row.BorderSizePixel = 0
        row.Parent = AutoBuyLogState.Content
        registerTheme(row, "BackgroundColor3", "Main")
        addCorner(row, 6)
        addStroke(row, "Muted", 1, 0.6)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -12, 1, 0)
        label.Position = UDim2.new(0, 6, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = tostring(info.Name or info.Key or "Potion Shop") .. " | (" .. tostring(info.Success or 0) .. ")"
        label.Parent = row
        setFontClass(label, "Small")
        registerTheme(label, "TextColor3", "Text")
        AutoBuyLogState.PotionUI[info.Key or info.Name or tostring(#AutoBuyLogState.PotionUI + 1)] = {
            Label = label
        }
    end

    local depositEntries = {}
    for _, info in pairs(AutoBuyLogState.ActiveDeposits) do
        depositEntries[#depositEntries + 1] = info
    end
    table.sort(depositEntries, function(a, b)
        return tostring(a.Name) < tostring(b.Name)
    end)

    if #depositEntries > 0 then
        addSectionTitle("Auto Deposit")
    end

    for _, info in ipairs(depositEntries) do
        local depositKey = tostring(info.Key or info.Name or "Deposit")
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, 0)
        section.AutomaticSize = Enum.AutomaticSize.Y
        section.BorderSizePixel = 0
        section.Parent = AutoBuyLogState.Content
        registerTheme(section, "BackgroundColor3", "Panel")
        addCorner(section, 8)
        addStroke(section, "Muted", 1, 0.8)

        local sectionList = Instance.new("UIListLayout")
        sectionList.Padding = UDim.new(0, 6)
        sectionList.SortOrder = Enum.SortOrder.LayoutOrder
        sectionList.Parent = section

        local sectionPad = Instance.new("UIPadding")
        sectionPad.PaddingTop = UDim.new(0, 6)
        sectionPad.PaddingBottom = UDim.new(0, 6)
        sectionPad.PaddingLeft = UDim.new(0, 6)
        sectionPad.PaddingRight = UDim.new(0, 6)
        sectionPad.Parent = section

        local header = Instance.new("TextLabel")
        header.Size = UDim2.new(1, 0, 0, 22)
        header.BackgroundTransparency = 1
        header.Font = Enum.Font.GothamSemibold
        header.TextSize = 12
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Text = tostring(info.Name or info.Key or "Deposit")
        header.Parent = section
        setFontClass(header, "Heading")
        registerTheme(header, "TextColor3", "Text")
        AutoBuyLogState.DepositUI[depositKey] = {
            Header = header,
            RowsByItem = {},
            PrimaryRow = nil
        }

        local body = Instance.new("Frame")
        body.Size = UDim2.new(1, 0, 0, 0)
        body.AutomaticSize = Enum.AutomaticSize.Y
        body.BorderSizePixel = 0
        body.BackgroundTransparency = 1
        body.Parent = section

        local bodyList = Instance.new("UIListLayout")
        bodyList.Padding = UDim.new(0, 4)
        bodyList.SortOrder = Enum.SortOrder.LayoutOrder
        bodyList.Parent = body

        local bodyPad = Instance.new("UIPadding")
        bodyPad.PaddingTop = UDim.new(0, 2)
        bodyPad.PaddingBottom = UDim.new(0, 4)
        bodyPad.PaddingLeft = UDim.new(0, 2)
        bodyPad.PaddingRight = UDim.new(0, 2)
        bodyPad.Parent = body

        local itemTotals = type(info.ItemTotals) == "table" and info.ItemTotals or {}
        local items = type(info.Items) == "table" and info.Items or {}
        local added = false

        local function createDepositItemRow(itemName, ownNum, depositNum, totalNum, ownRaw, depositRaw)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 0)
            row.AutomaticSize = Enum.AutomaticSize.Y
            row.BorderSizePixel = 0
            row.Parent = body
            registerTheme(row, "BackgroundColor3", "Main")
            addCorner(row, 6)
            addStroke(row, "Muted", 1, 0.6)

            local indicator = Instance.new("Frame")
            indicator.Size = UDim2.new(0, 6, 1, -6)
            indicator.Position = UDim2.new(0, 4, 0, 3)
            indicator.BorderSizePixel = 0
            indicator.Parent = row
            registerTheme(indicator, "BackgroundColor3", "Accent")
            addCorner(indicator, 3)

            local textWrap = Instance.new("Frame")
            textWrap.Size = UDim2.new(1, -16, 0, 0)
            textWrap.Position = UDim2.new(0, 14, 0, 2)
            textWrap.AutomaticSize = Enum.AutomaticSize.Y
            textWrap.BackgroundTransparency = 1
            textWrap.BorderSizePixel = 0
            textWrap.Parent = row

            local textLayout = Instance.new("UIListLayout")
            textLayout.Padding = UDim.new(0, 1)
            textLayout.SortOrder = Enum.SortOrder.LayoutOrder
            textLayout.Parent = textWrap

            local textPad = Instance.new("UIPadding")
            textPad.PaddingTop = UDim.new(0, 0)
            textPad.PaddingBottom = UDim.new(0, 2)
            textPad.Parent = textWrap

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 0, 0)
            label.AutomaticSize = Enum.AutomaticSize.Y
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Gotham
            label.TextSize = 11
            label.TextWrapped = true
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Top
            label.Text = tostring(itemName or "-")
            label.Parent = textWrap
            setFontClass(label, "Small")
            registerTheme(label, "TextColor3", "Text")

            local detail = Instance.new("TextLabel")
            detail.Size = UDim2.new(1, 0, 0, 0)
            detail.AutomaticSize = Enum.AutomaticSize.Y
            detail.BackgroundTransparency = 1
            detail.Font = Enum.Font.Gotham
            detail.TextSize = 9
            detail.TextWrapped = true
            detail.TextXAlignment = Enum.TextXAlignment.Left
            detail.TextYAlignment = Enum.TextYAlignment.Top
            detail.Text = AutoBuyLogState.BuildDepositItemDetailText(ownNum, depositNum, totalNum, ownRaw, depositRaw)
            detail.Parent = textWrap
            setFontClass(detail, "Tiny")
            registerTheme(detail, "TextColor3", "Muted")

            return {
                Row = row,
                Label = label,
                Detail = detail
            }
        end

        for _, entry in ipairs(items) do
            local itemName = tostring((entry and entry.Name) or "-")
            local ownNum = tonumber(entry and entry.OwnNum)
            local depositNum = tonumber(entry and entry.DepositNum)
            local itemTotal = tonumber(itemTotals[itemName]) or 0
            local rowInfo = createDepositItemRow(
                itemName,
                ownNum,
                depositNum,
                itemTotal,
                entry and entry.OwnRaw or nil,
                entry and entry.DepositRaw or nil
            )
            AutoBuyLogState.DepositUI[depositKey].RowsByItem[itemName] = rowInfo
            added = true
        end

        if not added then
            local itemName = tostring(info.ItemName or "-")
            local ownNum = tonumber(info.OwnNum)
            local depositNum = tonumber(info.DepositNum)
            local itemTotal = tonumber(itemTotals[itemName]) or tonumber(info.Success) or 0
            local rowInfo = createDepositItemRow(itemName, ownNum, depositNum, itemTotal, info.OwnRaw, info.DepositRaw)
            AutoBuyLogState.DepositUI[depositKey].RowsByItem[itemName] = rowInfo
            AutoBuyLogState.DepositUI[depositKey].PrimaryRow = rowInfo
            added = true
        end

        if not added then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 20)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 11
            empty.TextXAlignment = Enum.TextXAlignment.Left
            empty.Text = "Tidak ada item aktif"
            empty.Parent = body
            setFontClass(empty, "Small")
            registerTheme(empty, "TextColor3", "Muted")
        end
    end

    local autoDropperInfo = AutoBuyLogState.ActiveActions["HellAutoDropper"]
    if autoDropperInfo then
        addSectionTitle("Auto Dropper")

        local emberRow = Instance.new("Frame")
        emberRow.Size = UDim2.new(1, 0, 0, 22)
        emberRow.BorderSizePixel = 0
        emberRow.Parent = AutoBuyLogState.Content
        registerTheme(emberRow, "BackgroundColor3", "Main")
        addCorner(emberRow, 6)
        addStroke(emberRow, "Muted", 1, 0.6)

        local emberLabel = Instance.new("TextLabel")
        emberLabel.Size = UDim2.new(1, -12, 1, 0)
        emberLabel.Position = UDim2.new(0, 6, 0, 0)
        emberLabel.BackgroundTransparency = 1
        emberLabel.Font = Enum.Font.Gotham
        emberLabel.TextSize = 11
        emberLabel.TextXAlignment = Enum.TextXAlignment.Left
        emberLabel.Text = "Ember: " .. tostring(autoBuyLogFormatNumber(autoDropperInfo.Ember))
        emberLabel.Parent = emberRow
        setFontClass(emberLabel, "Small")
        registerTheme(emberLabel, "TextColor3", "Text")

        local items = type(autoDropperInfo.Items) == "table" and autoDropperInfo.Items or {}
        table.sort(items, function(a, b)
            local ia = tonumber(a and a.Index) or tonumber(a and a.Key and tostring(a.Key):match("(%d+)")) or 999
            local ib = tonumber(b and b.Index) or tonumber(b and b.Key and tostring(b.Key):match("(%d+)")) or 999
            if ia == ib then
                return tostring(a and a.Name) < tostring(b and b.Name)
            end
            return ia < ib
        end)

        for _, item in ipairs(items) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 34)
            row.BorderSizePixel = 0
            row.Parent = AutoBuyLogState.Content
            registerTheme(row, "BackgroundColor3", "Main")
            addCorner(row, 6)
            addStroke(row, "Muted", 1, 0.6)

            local indicator = Instance.new("Frame")
            indicator.Size = UDim2.new(0, 6, 1, -6)
            indicator.Position = UDim2.new(0, 4, 0, 3)
            indicator.BorderSizePixel = 0
            indicator.Visible = tostring(item.Key or "") == tostring(autoDropperInfo.ActiveKey or "")
            indicator.Parent = row
            registerTheme(indicator, "BackgroundColor3", "Accent")
            addCorner(indicator, 3)

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -16, 0, 16)
            label.Position = UDim2.new(0, 14, 0, 2)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Gotham
            label.TextSize = 11
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Top
            label.Text = tostring(item.Name or item.Label or item.Key or "Dropper")
            label.Parent = row
            setFontClass(label, "Small")
            registerTheme(label, "TextColor3", "Text")

            local levelText = type(item.Level) == "number" and tostring(item.Level) or "?"
            local maxLevelText = type(item.MaxLevel) == "number" and tostring(item.MaxLevel) or "?"
            local costText = item.Maxed and "maxed" or tostring(autoBuyLogFormatNumber(item.Cost))
            local detail = Instance.new("TextLabel")
            detail.Size = UDim2.new(1, -16, 0, 14)
            detail.Position = UDim2.new(0, 14, 0, 18)
            detail.BackgroundTransparency = 1
            detail.Font = Enum.Font.Gotham
            detail.TextSize = 9
            detail.TextXAlignment = Enum.TextXAlignment.Left
            detail.TextYAlignment = Enum.TextYAlignment.Top
            detail.Text = "Lv " .. tostring(levelText) .. "/" .. tostring(maxLevelText) .. " | Cost: " .. tostring(costText)
            detail.Parent = row
            setFontClass(detail, "Tiny")
            registerTheme(detail, "TextColor3", "Muted")
        end
    end

    local function renderAutoUpgradeTreePanel(autoUpgradeTreeInfo)
        if not autoUpgradeTreeInfo then
            return
        end

        local panel = Instance.new("Frame")
        panel.Size = UDim2.new(1, 0, 0, 0)
        panel.AutomaticSize = Enum.AutomaticSize.Y
        panel.BorderSizePixel = 0
        panel.Parent = AutoBuyLogState.Content
        registerTheme(panel, "BackgroundColor3", "Main")
        addCorner(panel, 6)
        addStroke(panel, "Muted", 1, 0.6)

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 6)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.Parent = panel

        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 3)
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Parent = panel

        local titleRow = Instance.new("Frame")
        titleRow.Size = UDim2.new(1, 0, 0, 0)
        titleRow.AutomaticSize = Enum.AutomaticSize.Y
        titleRow.BackgroundTransparency = 1
        titleRow.BorderSizePixel = 0
        titleRow.Parent = panel
        local titleRowList = Instance.new("UIListLayout")
        titleRowList.FillDirection = Enum.FillDirection.Horizontal
        titleRowList.HorizontalAlignment = Enum.HorizontalAlignment.Left
        titleRowList.SortOrder = Enum.SortOrder.LayoutOrder
        titleRowList.Padding = UDim.new(0, 4)
        titleRowList.Parent = titleRow

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(0.62, -4, 0, 14)
        title.AutomaticSize = Enum.AutomaticSize.None
        title.LayoutOrder = 1
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.Gotham
        title.TextSize = 11
        title.TextWrapped = false
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextYAlignment = Enum.TextYAlignment.Top
        title.Text = tostring(autoUpgradeTreeInfo.Name or "Auto Upgrade 500K Tree")
        title.Parent = titleRow
        setFontClass(title, "Small")
        registerTheme(title, "TextColor3", "Text")

        local titleCurrency = Instance.new("TextLabel")
        titleCurrency.Size = UDim2.new(0.38, 0, 0, 14)
        titleCurrency.AutomaticSize = Enum.AutomaticSize.None
        titleCurrency.LayoutOrder = 2
        titleCurrency.BackgroundTransparency = 1
        titleCurrency.Font = Enum.Font.Gotham
        titleCurrency.TextSize = 9
        titleCurrency.TextWrapped = false
        titleCurrency.TextXAlignment = Enum.TextXAlignment.Right
        titleCurrency.TextYAlignment = Enum.TextYAlignment.Top
        local currencyText = tostring(autoUpgradeTreeInfo.CurrencyText or "-")
        titleCurrency.Text = "| " .. tostring(currencyText)
        titleCurrency.Parent = titleRow
        setFontClass(titleCurrency, "Tiny")
        registerTheme(titleCurrency, "TextColor3", "Muted")

        local divider1 = Instance.new("TextLabel")
        divider1.Size = UDim2.new(1, 0, 0, 0)
        divider1.AutomaticSize = Enum.AutomaticSize.Y
        divider1.BackgroundTransparency = 1
        divider1.Font = Enum.Font.Gotham
        divider1.TextSize = 9
        divider1.TextWrapped = true
        divider1.TextXAlignment = Enum.TextXAlignment.Left
        divider1.TextYAlignment = Enum.TextYAlignment.Top
        divider1.Text = "----------------"
        divider1.Parent = panel
        setFontClass(divider1, "Tiny")
        registerTheme(divider1, "TextColor3", "Muted")

        local detail = Instance.new("TextLabel")
        detail.Size = UDim2.new(1, 0, 0, 0)
        detail.AutomaticSize = Enum.AutomaticSize.Y
        detail.BackgroundTransparency = 1
        detail.Font = Enum.Font.Gotham
        detail.TextSize = 9
        detail.TextWrapped = true
        detail.TextXAlignment = Enum.TextXAlignment.Left
        detail.TextYAlignment = Enum.TextYAlignment.Top
        detail.Text = tostring(autoUpgradeTreeInfo.DetailText or "-")
        detail.Parent = panel
        setFontClass(detail, "Tiny")
        registerTheme(detail, "TextColor3", "Muted")
    end

    local autoUpgrade500KInfo = AutoBuyLogState.ActiveActions["Event500KAutoUpgradeTree"]
    local autoUpgradeGardenInfo = AutoBuyLogState.ActiveActions["GardenAutoUpgradeTree"]
    local autoUpgradePointsInfo = AutoBuyLogState.ActiveActions["DesertAutoUpgradePointsTree"]
    local autoUpgradeBetterPointsInfo = AutoBuyLogState.ActiveActions["DesertAutoUpgradeBetterPointsTree"]
    if autoUpgrade500KInfo or autoUpgradeGardenInfo or autoUpgradePointsInfo or autoUpgradeBetterPointsInfo then
        addSectionTitle("Auto Upgrade Tree")
        renderAutoUpgradeTreePanel(autoUpgrade500KInfo)
        renderAutoUpgradeTreePanel(autoUpgradeGardenInfo)
        renderAutoUpgradeTreePanel(autoUpgradePointsInfo)
        renderAutoUpgradeTreePanel(autoUpgradeBetterPointsInfo)
    end

    local actionEntries = {}
    for _, info in pairs(AutoBuyLogState.ActiveActions) do
        local key = tostring(info and info.Key or "")
        if key ~= "HellAutoDropper"
            and key ~= "Event500KAutoUpgradeTree"
            and key ~= "GardenAutoUpgradeTree"
            and key ~= "DesertAutoUpgradePointsTree"
            and key ~= "DesertAutoUpgradeBetterPointsTree" then
            actionEntries[#actionEntries + 1] = info
        end
    end
    table.sort(actionEntries, function(a, b)
        return tostring(a.Name) < tostring(b.Name)
    end)

    if #actionEntries > 0 then
        addSectionTitle("Action")
    end

    for _, info in ipairs(actionEntries) do
        local showTotalClick = tostring(info.Key or "") == "GardenAutoClickFallTree"
        local detailText = tostring(info.DetailText or "")
        local showDetailText = #detailText > 0
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, (showTotalClick or showDetailText) and 34 or 22)
        row.BorderSizePixel = 0
        row.Parent = AutoBuyLogState.Content
        registerTheme(row, "BackgroundColor3", "Main")
        addCorner(row, 6)
        addStroke(row, "Muted", 1, 0.6)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -12, 0, (showTotalClick or showDetailText) and 16 or 22)
        label.Position = UDim2.new(0, 6, 0, 1)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Text = tostring(info.Name or info.Key or "Action")
        label.Parent = row
        setFontClass(label, "Small")
        registerTheme(label, "TextColor3", "Text")

        if showTotalClick or showDetailText then
            local detail = Instance.new("TextLabel")
            detail.Size = UDim2.new(1, -12, 0, 14)
            detail.Position = UDim2.new(0, 6, 0, 18)
            detail.BackgroundTransparency = 1
            detail.Font = Enum.Font.Gotham
            detail.TextSize = 9
            detail.TextXAlignment = Enum.TextXAlignment.Left
            detail.TextYAlignment = Enum.TextYAlignment.Top
            if showTotalClick then
                detail.Text = "Total Click: " .. tostring(tonumber(info.Success) or 0)
            else
                detail.Text = detailText
            end
            detail.Parent = row
            setFontClass(detail, "Tiny")
            registerTheme(detail, "TextColor3", "Muted")
            AutoBuyLogState.ActionUI[info.Key or info.Name or tostring(#AutoBuyLogState.ActionUI + 1)] = {
                Label = label,
                Detail = detail
            }
        else
            AutoBuyLogState.ActionUI[info.Key or info.Name or tostring(#AutoBuyLogState.ActionUI + 1)] = {
                Label = label,
                Detail = nil
            }
        end
    end
end

updateAutoBuyLogUI = function()
    local interval = tonumber(AutoBuyLogState.MinRefreshInterval) or 0.25
    if interval < 0.05 then
        interval = 0.05
    end
    local now = os.clock()
    local nextAt = tonumber(AutoBuyLogState.NextRefreshAt) or 0
    if now < nextAt then
        if not AutoBuyLogState.RefreshQueued then
            AutoBuyLogState.RefreshQueued = true
            local token = tonumber(AutoBuyLogState.UpdateToken) or 0
            task.delay(math.max(0.02, nextAt - now), function()
                if (tonumber(AutoBuyLogState.UpdateToken) or 0) ~= token then
                    return
                end
                AutoBuyLogState.RefreshQueued = false
                updateAutoBuyLogUI()
            end)
        end
        return
    end
    AutoBuyLogState.RefreshQueued = false
    AutoBuyLogState.NextRefreshAt = now + interval

    local activeCount = getActiveAutoBuyCount()
      if not Config.AutoBuyLogEnabled or activeCount == 0 then
          if AutoBuyLogState.Frame then
              if State.UI and State.UI.AnimateHide then
                  State.UI.AnimateHide(AutoBuyLogState.Frame, {EndScale = 0.96, Duration = 0.12})
              else
                  AutoBuyLogState.Frame.Visible = false
              end
          end
          AutoBuyLogState.Resizing = false
          AutoBuyLogState.ResizeStart = nil
          AutoBuyLogState.ResizeStartSize = nil
          AutoBuyLogState.UserMoved = false
          AutoBuyLogState.RelativePos = nil
          AutoBuyLogState.LastPosition = nil
          if State.LogLayout and State.LogLayout.Apply then
              State.LogLayout.Apply()
          end
          return
      end

      createAutoBuyLogUI()
      if AutoBuyLogState.Frame then
          if State.UI and State.UI.AnimateShow then
              State.UI.AnimateShow(AutoBuyLogState.Frame, {StartScale = 0.96, Duration = 0.18})
          else
              AutoBuyLogState.Frame.Visible = true
          end
      end
    if AutoBuyLogState.CountLabel then
        AutoBuyLogState.CountLabel.Text = tostring(activeCount)
    end

    local signature = autoBuyLogStructureSignature()
    local needsComplex = autoBuyLogNeedsComplexRebuild()
    local shouldRebuild = needsComplex
        or (AutoBuyLogState.BuiltOnce ~= true)
        or (signature ~= (AutoBuyLogState.LastStructureSignature or ""))

    if shouldRebuild then
        rebuildAutoBuyLogContent()
        AutoBuyLogState.LastStructureSignature = signature
        AutoBuyLogState.BuiltOnce = true
    else
        refreshAutoBuyLogDynamicValues()
    end

    if State.LogLayout and State.LogLayout.Apply then
        State.LogLayout.Apply()
    end
end

local function setAutoBuyGroupActive(groupKey, displayName, enabled, shops, shopEnabled, itemEnabled)
    if enabled then
        AutoBuyLogState.ActiveGroups[groupKey] = {Key = groupKey, Name = displayName or groupKey}
        AutoBuyLogState.GroupData[groupKey] = AutoBuyLogState.GroupData[groupKey] or {}
        AutoBuyLogState.GroupData[groupKey].Key = groupKey
        AutoBuyLogState.GroupData[groupKey].Name = displayName or groupKey
        AutoBuyLogState.GroupData[groupKey].Shops = shops or AutoBuyLogState.GroupData[groupKey].Shops or {}
        AutoBuyLogState.GroupData[groupKey].ShopEnabled = shopEnabled or AutoBuyLogState.GroupData[groupKey].ShopEnabled or {}
        AutoBuyLogState.GroupData[groupKey].ItemEnabled = itemEnabled or AutoBuyLogState.GroupData[groupKey].ItemEnabled or {}
    else
        AutoBuyLogState.ActiveGroups[groupKey] = nil
        AutoBuyLogState.ActiveItem[groupKey] = nil
        AutoBuyLogState.LastActive[groupKey] = nil
        AutoBuyLogState.SkippedMaxed[groupKey] = nil
    end
    updateAutoBuyLogUI()
end

local function setAutoBuyPotionActive(potionKey, displayName, enabled)
    if not potionKey then
        return
    end
    if enabled then
        local data = AutoBuyLogState.PotionData[potionKey] or {}
        data.Key = potionKey
        data.Name = displayName or potionKey
        data.Success = tonumber(data.Success) or 0
        AutoBuyLogState.PotionData[potionKey] = data
        AutoBuyLogState.ActivePotions[potionKey] = data
    else
        AutoBuyLogState.ActivePotions[potionKey] = nil
    end
    updateAutoBuyLogUI()
end

AutoBuyLogState.SetActionActive = AutoBuyLogState.SetActionActive or function(actionKey, displayName, enabled)
    if not actionKey then
        return
    end
    if enabled then
        local data = AutoBuyLogState.ActionData[actionKey] or {}
        data.Key = actionKey
        data.Name = displayName or actionKey
        data.Success = tonumber(data.Success) or 0
        AutoBuyLogState.ActionData[actionKey] = data
        AutoBuyLogState.ActiveActions[actionKey] = data
    else
        AutoBuyLogState.ActiveActions[actionKey] = nil
    end
    updateAutoBuyLogUI()
end

AutoBuyLogState.AddActionCount = AutoBuyLogState.AddActionCount or function(actionKey, amount, forceRefresh)
    if not actionKey then
        return
    end
    local data = AutoBuyLogState.ActionData[actionKey] or {
        Key = actionKey,
        Name = actionKey,
        Success = 0
    }
    local add = tonumber(amount) or 0
    if add <= 0 then
        return
    end
    data.Success = (tonumber(data.Success) or 0) + add
    AutoBuyLogState.ActionData[actionKey] = data
    if AutoBuyLogState.ActiveActions[actionKey] then
        AutoBuyLogState.ActiveActions[actionKey] = data
        if forceRefresh ~= false then
            updateAutoBuyLogUI()
        end
    end
end

AutoBuyLogState.BuildDepositDetailText = AutoBuyLogState.BuildDepositDetailText or function(info)
    if type(info) ~= "table" then
        return "-"
    end
    local lines = {}
    local items = type(info.Items) == "table" and info.Items or nil
    local totalText = tostring(tonumber(info.Success) or 0)
    local itemTotals = type(info.ItemTotals) == "table" and info.ItemTotals or nil
    if not items or #items == 0 then
        local itemName = tostring(info.ItemName or "-")
        local ownNum = tonumber(info.OwnNum)
        local depositNum = tonumber(info.DepositNum)
        local ownText = autoBuyLogFormatNumber(ownNum)
        local depositText = autoBuyLogFormatNumber(depositNum)
        if ownText == "?" and info.OwnRaw ~= nil then
            ownText = autoBuyLogFormatRawFallback(info.OwnRaw)
        end
        if depositText == "?" and info.DepositRaw ~= nil then
            depositText = autoBuyLogFormatRawFallback(info.DepositRaw)
        end
        local ratioText = "-"
        if type(ownNum) == "number" and type(depositNum) == "number" and depositNum > 0 then
            ratioText = AutoBuyLogState.FormatRatioX(ownNum, depositNum, info.OwnRaw, info.DepositRaw)
        elseif info.OwnRaw ~= nil or info.DepositRaw ~= nil then
            ratioText = AutoBuyLogState.FormatRatioX(ownNum, depositNum, info.OwnRaw, info.DepositRaw)
        end
        local itemTotal = itemTotals and tonumber(itemTotals[itemName]) or nil
        local rowTotalText = tostring(itemTotal or totalText)
        lines[#lines + 1] = tostring(itemName)
        lines[#lines + 1] = "Own: " .. tostring(ownText) .. " | Deposit: " .. tostring(depositText)
        lines[#lines + 1] = tostring(ratioText) .. " | Total: " .. tostring(rowTotalText)
        return table.concat(lines, "\n")
    end
    for i, entry in ipairs(items) do
        local itemName = tostring((entry and entry.Name) or "-")
        local itemTotal = itemTotals and tonumber(itemTotals[itemName]) or nil
        local rowTotalText = tostring(itemTotal or totalText)
        local ownNum = tonumber(entry and entry.OwnNum)
        local depositNum = tonumber(entry and entry.DepositNum)
        local ownText = autoBuyLogFormatNumber(ownNum)
        local depositText = autoBuyLogFormatNumber(depositNum)
        if ownText == "?" and entry and entry.OwnRaw ~= nil then
            ownText = autoBuyLogFormatRawFallback(entry.OwnRaw)
        end
        if depositText == "?" and entry and entry.DepositRaw ~= nil then
            depositText = autoBuyLogFormatRawFallback(entry.DepositRaw)
        end
        local ratioText = "-"
        if type(ownNum) == "number" and type(depositNum) == "number" and depositNum > 0 then
            ratioText = AutoBuyLogState.FormatRatioX(ownNum, depositNum, entry and entry.OwnRaw or nil, entry and entry.DepositRaw or nil)
        elseif (entry and entry.OwnRaw ~= nil) or (entry and entry.DepositRaw ~= nil) then
            ratioText = AutoBuyLogState.FormatRatioX(ownNum, depositNum, entry and entry.OwnRaw or nil, entry and entry.DepositRaw or nil)
        end
        lines[#lines + 1] = tostring(itemName)
        lines[#lines + 1] = "Own: " .. tostring(ownText) .. " | Deposit: " .. tostring(depositText)
        lines[#lines + 1] = tostring(ratioText) .. " | Total: " .. tostring(rowTotalText)
        if i < #items then
            lines[#lines + 1] = ""
        end
    end
    return table.concat(lines, "\n")
end

AutoBuyLogState.BuildDepositItemDetailText = AutoBuyLogState.BuildDepositItemDetailText or function(ownNum, depositNum, totalNum, ownRaw, depositRaw)
    local ratioText = "-"
    if type(ownNum) == "number" and type(depositNum) == "number" and depositNum > 0 then
        ratioText = AutoBuyLogState.FormatRatioX(ownNum, depositNum, ownRaw, depositRaw)
    elseif ownRaw ~= nil or depositRaw ~= nil then
        ratioText = AutoBuyLogState.FormatRatioX(ownNum, depositNum, ownRaw, depositRaw)
    end
    local ownText = autoBuyLogFormatNumber(ownNum)
    local depositText = autoBuyLogFormatNumber(depositNum)
    if ownText == "?" and ownRaw ~= nil then
        ownText = autoBuyLogFormatRawFallback(ownRaw)
    end
    if depositText == "?" and depositRaw ~= nil then
        depositText = autoBuyLogFormatRawFallback(depositRaw)
    end
    local totalText = tostring(tonumber(totalNum) or 0)
    return "Own: " .. tostring(ownText)
        .. " | Deposit: " .. tostring(depositText)
        .. "\n"
        .. tostring(ratioText)
        .. " | Total: "
        .. tostring(totalText)
end

AutoBuyLogState.SetDepositActive = AutoBuyLogState.SetDepositActive or function(depositKey, displayName, enabled)
    if not depositKey then
        return
    end
    if enabled then
        local data = AutoBuyLogState.DepositData[depositKey] or {}
        data.Key = depositKey
        data.Name = displayName or depositKey
        data.Success = tonumber(data.Success) or 0
        data.ItemName = data.ItemName or "-"
        AutoBuyLogState.DepositData[depositKey] = data
        AutoBuyLogState.ActiveDeposits[depositKey] = data
    else
        AutoBuyLogState.ActiveDeposits[depositKey] = nil
    end
    updateAutoBuyLogUI()
end

AutoBuyLogState.UpdateDepositProgress = AutoBuyLogState.UpdateDepositProgress or function(depositKey, patch, forceRefresh)
    if not depositKey then
        return
    end
    local data = AutoBuyLogState.DepositData[depositKey] or {
        Key = depositKey,
        Name = depositKey,
        Success = 0,
        ItemName = "-"
    }
    if type(patch) == "table" then
        for k, v in pairs(patch) do
            data[k] = v
        end
    end
    data.Success = tonumber(data.Success) or 0
    AutoBuyLogState.DepositData[depositKey] = data
    if AutoBuyLogState.ActiveDeposits[depositKey] then
        AutoBuyLogState.ActiveDeposits[depositKey] = data
        if forceRefresh ~= false then
            updateAutoBuyLogUI()
        end
    end
end

local function addAutoBuyPotionSuccess(potionKey, amount)
    if not potionKey then
        return
    end
    local data = AutoBuyLogState.PotionData[potionKey] or {Key = potionKey, Name = potionKey, Success = 0}
    local add = tonumber(amount) or 0
    if add <= 0 then
        return
    end
    data.Success = (tonumber(data.Success) or 0) + add
    AutoBuyLogState.PotionData[potionKey] = data
    if AutoBuyLogState.ActivePotions[potionKey] then
        AutoBuyLogState.ActivePotions[potionKey] = data
        updateAutoBuyLogUI()
    end
end

State.AutoBuyScheduler = State.AutoBuyScheduler or {}
State.AutoBuyScheduler.Active = State.AutoBuyScheduler.Active or {}
State.AutoBuyScheduler.Order = State.AutoBuyScheduler.Order or {}
State.AutoBuyScheduler.Index = State.AutoBuyScheduler.Index or 1
State.AutoBuyScheduler.LastClick = State.AutoBuyScheduler.LastClick or 0
State.AutoBuyScheduler.Conn = State.AutoBuyScheduler.Conn or nil

local function autoBuySchedulerStart()
    if State.AutoBuyScheduler.Conn then
        return
    end
    State.AutoBuyScheduler.Conn = RunService.Heartbeat:Connect(function()
        local order = State.AutoBuyScheduler.Order
        local total = #order
        if total == 0 then
            return
        end
        local now = os.clock()
        if now - State.AutoBuyScheduler.LastClick < getGlobalClickCooldown("AutoBuyGlobal") then
            return
        end
        for _ = 1, total do
            local key = order[State.AutoBuyScheduler.Index]
            State.AutoBuyScheduler.Index += 1
            if State.AutoBuyScheduler.Index > total then
                State.AutoBuyScheduler.Index = 1
            end
            local entry = State.AutoBuyScheduler.Active[key]
            if entry and entry.Step then
                local fired = entry.Step()
                if fired then
                    State.AutoBuyScheduler.LastClick = now
                    break
                end
            end
        end
        if #order ~= total and State.AutoBuyScheduler.Index > #order then
            State.AutoBuyScheduler.Index = 1
        end
    end)
    trackConnection(State.AutoBuyScheduler.Conn)
end

local function autoBuySchedulerStopIfEmpty()
    if #State.AutoBuyScheduler.Order > 0 then
        return
    end
    if State.AutoBuyScheduler.Conn then
        State.AutoBuyScheduler.Conn:Disconnect()
        State.AutoBuyScheduler.Conn = nil
    end
    State.AutoBuyScheduler.Index = 1
end

local function autoBuySchedulerRegister(key, entry)
    if not key or not entry then
        return
    end
    State.AutoBuyScheduler.Active[key] = entry
    local found = false
    for _, k in ipairs(State.AutoBuyScheduler.Order) do
        if k == key then
            found = true
            break
        end
    end
    if not found then
        State.AutoBuyScheduler.Order[#State.AutoBuyScheduler.Order + 1] = key
    end
    autoBuySchedulerStart()
end

local function autoBuySchedulerUnregister(key)
    if not key then
        return
    end
    State.AutoBuyScheduler.Active[key] = nil
    for i = #State.AutoBuyScheduler.Order, 1, -1 do
        if State.AutoBuyScheduler.Order[i] == key then
            table.remove(State.AutoBuyScheduler.Order, i)
        end
    end
    autoBuySchedulerStopIfEmpty()
end

State.ResolveMaxedMatches = function(lowerMsg, items)
    if type(lowerMsg) ~= "string" or type(items) ~= "table" then
        return {}
    end
    local matches = {}
    for _, entry in ipairs(items) do
        local itemName = entry and entry.Item
        if type(itemName) == "string" then
            local lowerItem = string.lower(itemName)
            if string.find(lowerMsg, lowerItem, 1, true) then
                matches[#matches + 1] = {
                    Key = entry.Key,
                    Item = itemName,
                    Lower = lowerItem,
                    Len = #lowerItem
                }
            end
        end
    end
    if #matches <= 1 then
        return matches
    end
    table.sort(matches, function(a, b)
        return (a.Len or 0) > (b.Len or 0)
    end)
    local accepted = {}
    for _, m in ipairs(matches) do
        local covered = false
        for _, a in ipairs(accepted) do
            if a.Lower and m.Lower and string.find(a.Lower, m.Lower, 1, true) then
                covered = true
                break
            end
        end
        if not covered then
            accepted[#accepted + 1] = m
        end
    end
    return accepted
end

AutoBuyLogState.UpdateGroupActiveIndicator = function(groupKey)
    local ui = AutoBuyLogState.GroupUI[groupKey]
    if not ui or not ui.Rows then
        return
    end

    local last = AutoBuyLogState.LastActive[groupKey]
    if last and ui.Rows[last.Shop] and ui.Rows[last.Shop][last.Item] then
        local row = ui.Rows[last.Shop][last.Item]
        if row.Indicator then
            row.Indicator.Visible = false
        end
    end

    local active = AutoBuyLogState.ActiveItem[groupKey]
    if active and ui.Rows[active.Shop] and ui.Rows[active.Shop][active.Item] then
        local row = ui.Rows[active.Shop][active.Item]
        if row.Indicator then
            row.Indicator.Visible = true
        end
    end

    AutoBuyLogState.LastActive[groupKey] = active
end

AutoBuyLogState.RefreshGroupValues = function(groupKey)
    local groupUI = AutoBuyLogState.GroupUI[groupKey]
    if not groupUI then
        return
    end
    if groupUI.ShopLabels then
        for _, entry in pairs(groupUI.ShopLabels) do
            if entry and entry.Label and entry.Label.Parent and entry.Shop then
                local amount = autoBuyLogResolveCurrencyAmount(entry.Shop, nil)
                entry.Label.Text = tostring(entry.Shop.DisplayName or entry.Shop.Key or "Shop") .. "  (" .. autoBuyLogFormatNumber(amount) .. ")"
            end
        end
    end
    if groupUI.Rows then
        local skippedGroup = AutoBuyLogState.SkippedMaxed[groupKey] or {}
        for shopKey, items in pairs(groupUI.Rows) do
            for itemName, rowInfo in pairs(items) do
                if rowInfo and rowInfo.Detail and rowInfo.Detail.Parent and rowInfo.Shop then
                    local skipped = skippedGroup[shopKey] and skippedGroup[shopKey][itemName] or false
                    local detailText, maxedByLevel = autoBuyLogBuildDetailText(rowInfo.Shop, itemName, skipped == true)
                    autoBuyLogSetRowDetail(rowInfo, detailText, maxedByLevel == true)
                    if maxedByLevel and AutoBuyLogState.SetItemSkipped then
                        AutoBuyLogState.SetItemSkipped(groupKey, shopKey, itemName, true)
                    end
                end
            end
        end
    end
end

AutoBuyLogState.SetActiveItem = function(groupKey, shopKey, itemName)
    if not groupKey or not shopKey or not itemName then
        return
    end
    AutoBuyLogState.ActiveItem[groupKey] = {Shop = shopKey, Item = itemName}
    if AutoBuyLogState.RefreshGroupValues then
        AutoBuyLogState.RefreshGroupValues(groupKey)
    end
    if AutoBuyLogState.UpdateGroupActiveIndicator then
        AutoBuyLogState.UpdateGroupActiveIndicator(groupKey)
    end
end

AutoBuyLogState.ApplyRowStyle = function(row, skipped)
    if not row then
        return
    end
    local theme = getTheme(Config.Theme)
    if skipped then
        row.BackgroundColor3 = theme.Skip or theme.Main
    else
        row.BackgroundColor3 = theme.Main
    end
end

AutoBuyLogState.ApplySkipStyles = function(groupKey)
    local theme = getTheme(Config.Theme)
    local function applyRow(row, skipped)
        if not row then
            return
        end
        row.BackgroundColor3 = skipped and (theme.Skip or theme.Main) or theme.Main
    end

    local function isSkipped(gk, sk, name)
        return AutoBuyLogState.SkippedMaxed[gk]
            and AutoBuyLogState.SkippedMaxed[gk][sk]
            and AutoBuyLogState.SkippedMaxed[gk][sk][name]
            or false
    end

    if groupKey then
        local ui = AutoBuyLogState.GroupUI[groupKey]
        if not ui or not ui.Rows then
            return
        end
        for shopKey, items in pairs(ui.Rows) do
            for itemName, rowInfo in pairs(items) do
                applyRow(rowInfo and rowInfo.Row, isSkipped(groupKey, shopKey, itemName))
            end
        end
        return
    end

    for gk, ui in pairs(AutoBuyLogState.GroupUI) do
        if ui and ui.Rows then
            for shopKey, items in pairs(ui.Rows) do
                for itemName, rowInfo in pairs(items) do
                    applyRow(rowInfo and rowInfo.Row, isSkipped(gk, shopKey, itemName))
                end
            end
        end
    end
end

AutoBuyLogState.SetItemSkipped = function(groupKey, shopKey, itemName, skipped)
    if not groupKey or not shopKey or not itemName then
        return
    end
    if skipped then
        AutoBuyLogState.SkippedMaxed[groupKey] = AutoBuyLogState.SkippedMaxed[groupKey] or {}
        AutoBuyLogState.SkippedMaxed[groupKey][shopKey] = AutoBuyLogState.SkippedMaxed[groupKey][shopKey] or {}
        AutoBuyLogState.SkippedMaxed[groupKey][shopKey][itemName] = true
    elseif AutoBuyLogState.SkippedMaxed[groupKey] and AutoBuyLogState.SkippedMaxed[groupKey][shopKey] then
        AutoBuyLogState.SkippedMaxed[groupKey][shopKey][itemName] = nil
    end

    local ui = AutoBuyLogState.GroupUI[groupKey]
    if ui and ui.Rows and ui.Rows[shopKey] and ui.Rows[shopKey][itemName] then
        AutoBuyLogState.ApplyRowStyle(ui.Rows[shopKey][itemName].Row, skipped)
        if ui.Rows[shopKey][itemName].Detail then
            local rowInfo = ui.Rows[shopKey][itemName]
            local detailText, maxedByLevel = autoBuyLogBuildDetailText(rowInfo.Shop, itemName, skipped == true)
            autoBuyLogSetRowDetail(rowInfo, detailText, maxedByLevel == true)
        end
    end
end

AutoBuyLogState.ClearSkippedGroup = function(groupKey)
    if not groupKey then
        return
    end
    AutoBuyLogState.SkippedMaxed[groupKey] = nil
    if AutoBuyLogState.ApplySkipStyles then
        AutoBuyLogState.ApplySkipStyles(groupKey)
    end
end

ToggleRenders[#ToggleRenders + 1] = function()
    if AutoBuyLogState and AutoBuyLogState.ApplySkipStyles then
        AutoBuyLogState.ApplySkipStyles()
    end
end

State.AutoBuyShop = State.AutoBuyShop or {}
State.AutoBuyShop.Helpers = State.AutoBuyShop.Helpers or {}
State.AutoBuyShop.Helpers.GetNumericValueFromNode = State.AutoBuyShop.Helpers.GetNumericValueFromNode or function(node)
    if not node then
        return nil
    end
    if node:IsA("NumberValue") or node:IsA("IntValue") or node:IsA("BoolValue") then
        return tonumber(node.Value)
    end
    if node:IsA("StringValue") then
        return tonumber(node.Value)
    end
    local ok, raw = pcall(function()
        return node.Value
    end)
    if ok then
        return tonumber(raw)
    end
    return nil
end
State.AutoBuyShop.Helpers.TryResolveFolder = State.AutoBuyShop.Helpers.TryResolveFolder or function(parent, names)
    if not parent or type(names) ~= "table" then
        return nil
    end
    for _, name in ipairs(names) do
        if type(name) == "string" and #name > 0 then
            local child = parent:FindFirstChild(name)
            if child then
                return child, name
            end
        end
    end
    return nil
end
State.AutoBuyShop.Helpers.GetUpgradeModuleRoot = State.AutoBuyShop.Helpers.GetUpgradeModuleRoot or function()
    local ok, root = pcall(function()
        return game:GetService("ReplicatedStorage").Shared.Modules.UpgradeModule
    end)
    if ok and root then
        return root
    end
    return nil
end
State.AutoBuyShop.Helpers.NormalizeModuleKey = State.AutoBuyShop.Helpers.NormalizeModuleKey or function(text)
    if type(text) ~= "string" then
        return ""
    end
    local out = string.lower(text)
    out = out:gsub("%s+[Ss][Hh][Oo][Pp]$", "")
    out = out:gsub("[^%w]", "")
    return out
end
State.AutoBuyShop.Helpers.ResolveUpgradeModule = State.AutoBuyShop.Helpers.ResolveUpgradeModule or function(shop)
    if not shop then
        return nil
    end
    if shop.ModuleScript and shop.ModuleScript:IsA("ModuleScript") then
        return shop.ModuleScript
    end
    local root = State.AutoBuyShop.Helpers.GetUpgradeModuleRoot()
    if not root then
        return nil
    end

    local moduleNameCandidates = {
        shop.ModuleName,
        shop.ShopName,
        shop.Key,
        shop.DisplayName,
        shop.CurrencyName
    }
    for _, candidate in ipairs(moduleNameCandidates) do
        if type(candidate) == "string" and #candidate > 0 then
            local moduleScript = root:FindFirstChild(candidate)
            if moduleScript and moduleScript:IsA("ModuleScript") then
                return moduleScript
            end
        end
    end

    if type(shop.ShopName) == "string" then
        local trimmed = shop.ShopName:gsub("%s+[Ss][Hh][Oo][Pp]$", "")
        if #trimmed > 0 then
            local moduleScript = root:FindFirstChild(trimmed)
            if moduleScript and moduleScript:IsA("ModuleScript") then
                return moduleScript
            end
        end
    end

    local normalizedTargets = {}
    for _, candidate in ipairs(moduleNameCandidates) do
        local norm = State.AutoBuyShop.Helpers.NormalizeModuleKey(candidate)
        if #norm > 0 then
            normalizedTargets[norm] = true
        end
    end
    for _, child in ipairs(root:GetChildren()) do
        if child:IsA("ModuleScript") then
            local childNorm = State.AutoBuyShop.Helpers.NormalizeModuleKey(child.Name)
            if normalizedTargets[childNorm] then
                return child
            end
        end
    end
    return nil
end
State.AutoBuyShop.Helpers.IsModuleRequireBlocked = State.AutoBuyShop.Helpers.IsModuleRequireBlocked or function(moduleScript)
    if not moduleScript or not moduleScript:IsA("ModuleScript") then
        return false
    end

    local moduleName = tostring(moduleScript.Name or "")
    if moduleName == "Plutite" or moduleName == "Sunite" then
        return true
    end

    local fullName = ""
    pcall(function()
        fullName = tostring(moduleScript:GetFullName() or "")
    end)
    fullName = string.lower(fullName)
    if string.find(fullName, "upgrademodule.plutite", 1, true) or string.find(fullName, "upgrademodule.sunite", 1, true) then
        return true
    end

    return false
end
State.AutoBuyShop.Helpers.ResolveItemMeta = State.AutoBuyShop.Helpers.ResolveItemMeta or function(shop, itemName)
    if not shop or type(itemName) ~= "string" then
        return nil, itemName
    end
    local byItem = shop.MetaByItem
    if type(byItem) ~= "table" then
        return nil, itemName
    end
    local direct = byItem[itemName]
    if direct then
        return direct, itemName
    end
    local target = State.AutoBuyShop.Helpers.NormalizeModuleKey(itemName)
    if #target == 0 then
        return nil, itemName
    end
    for key, meta in pairs(byItem) do
        if State.AutoBuyShop.Helpers.NormalizeModuleKey(key) == target then
            return meta, key
        end
    end
    return nil, itemName
end
State.AutoBuyShop.Helpers.ApplyKnownModuleCostFallback = State.AutoBuyShop.Helpers.ApplyKnownModuleCostFallback or function(shop)
    if not shop or type(shop.ShopName) ~= "string" then
        return false
    end

    local fallbackByShop = {
        Plutite = {
            Currency = "Plutite",
            Items = {
                {Name = "Infinite Plutite", Order = 5, Max = 300, Base = 1, Growth = 10},
                {Name = "Infinite Neptunite", Order = 10, Max = 450, Base = 1, Growth = 4.641588833612778},
                {Name = "Infinite Uranite", Order = 15, Max = 600, Base = 3.1622776601683795, Growth = 3.1622776601683795},
                {Name = "Infinite Saturnite", Order = 20, Max = 750, Base = 25.1188643233974, Growth = 2.51188643233974},
                {Name = "Infinite Jupiterite", Order = 25, Max = 900, Base = 21.544346900318835, Growth = 2.154434690031884},
                {Name = "Infinite Mercuryte", Order = 30, Max = 1050, Base = 19.306977292991117, Growth = 1.9306977292991119},
                {Name = "Infinite Venusite", Order = 35, Max = 1200, Base = 10, Growth = 1.77827941931902},
                {Name = "Infinite Marsite", Order = 40, Max = 1350, Base = 100, Growth = 1.668100537080129},
                {Name = "Infinite Moonlite", Order = 45, Max = 1500, Base = 1000, Growth = 1.584893192461617},
                {Name = "Infinite Dirtite", Order = 50, Max = 2250, Base = 10000, Growth = 1.35956391227848}
            }
        },
        Sunite = {
            Currency = "Sunite",
            Items = {
                {Name = "Infinite Sunite", Order = 2, Max = 300, Base = 1, Growth = 10},
                {Name = "Infinite Plutite", Order = 5, Max = 600, Base = 10, Growth = 3.1622776601683795},
                {Name = "Infinite Neptunite", Order = 10, Max = 900, Base = 10, Growth = 2.15443469897739},
                {Name = "Infinite Uranite", Order = 15, Max = 1200, Base = 10, Growth = 1.77827941},
                {Name = "Infinite Saturnite", Order = 20, Max = 1500, Base = 10, Growth = 1.5848931921},
                {Name = "Infinite Jupiterite", Order = 25, Max = 2100, Base = 10, Growth = 1.389495941},
                {Name = "Infinite Mercuryte", Order = 30, Max = 2700, Base = 10, Growth = 1.2915496651},
                {Name = "Infinite Venusite", Order = 35, Max = 3600, Base = 10, Growth = 1.211527659},
                {Name = "Infinite Marsite", Order = 40, Max = 4500, Base = 10, Growth = 1.165914401},
                {Name = "Infinite Moonlite", Order = 45, Max = 6000, Base = 10, Growth = 1.122018454},
                {Name = "Infinite Dirtite", Order = 50, Max = 7500, Base = 10, Growth = 1.0964781961},
                {Name = "Rune Bulk", Order = 55, Max = 5, Base = 1, Growth = 100}
            }
        }
    }

    local spec = fallbackByShop[shop.ShopName]
    if not spec or type(spec.Items) ~= "table" then
        return false
    end

    shop.MetaByItem = shop.MetaByItem or {}
    if not shop.CurrencyName then
        shop.CurrencyName = spec.Currency or shop.CurrencyName
    end

    local applied = false
    for _, def in ipairs(spec.Items) do
        if type(def) == "table" and type(def.Name) == "string" and #def.Name > 0 then
            local base = tonumber(def.Base)
            local growth = tonumber(def.Growth)
            local maxLevel = tonumber(def.Max)
            if type(base) == "number" and type(growth) == "number" and base > 0 and growth > 0 then
                if not shop.MetaByItem[def.Name] or type(shop.MetaByItem[def.Name].CostFn) ~= "function" then
                    shop.MetaByItem[def.Name] = {
                        Order = tonumber(def.Order) or 999999,
                        CostCurrency = spec.Currency or shop.CurrencyName or shop.ShopName or shop.Key,
                        MaxLevel = maxLevel and math.floor(maxLevel) or nil,
                        CostFn = function(level)
                            local lvl = tonumber(level)
                            if type(lvl) ~= "number" then
                                lvl = 1
                            end
                            lvl = math.max(0, math.floor(lvl + 0.5))
                            local ok, value = pcall(function()
                                return base * (growth ^ lvl)
                            end)
                            if ok and type(value) == "number" and value == value then
                                return value
                            end
                            return nil
                        end
                    }
                    applied = true
                end
            end
        end
    end

    if type(shop.Items) ~= "table" then
        shop.Items = {}
    end
    local itemSet = {}
    for _, name in ipairs(shop.Items) do
        if type(name) == "string" and #name > 0 then
            itemSet[name] = true
        end
    end
    for name in pairs(shop.MetaByItem) do
        if type(name) == "string" and #name > 0 and not itemSet[name] then
            shop.Items[#shop.Items + 1] = name
            itemSet[name] = true
        end
    end
    table.sort(shop.Items, function(a, b)
        local oa = shop.MetaByItem[a] and shop.MetaByItem[a].Order or 999999
        local ob = shop.MetaByItem[b] and shop.MetaByItem[b].Order or 999999
        if oa == ob then
            return tostring(a) < tostring(b)
        end
        return oa < ob
    end)
    return applied
end
State.AutoBuyShop.Helpers.BuildShopMetaFromModule = State.AutoBuyShop.Helpers.BuildShopMetaFromModule or function(shop)
    if not shop then
        return false
    end
    local moduleScript = State.AutoBuyShop.Helpers.ResolveUpgradeModule(shop)
    if not moduleScript then
        return false
    end
    if State.AutoBuyShop.Helpers.IsModuleRequireBlocked(moduleScript) then
        local moduleName = tostring(moduleScript.Name or "?")
        if State.Log and State.Log.Debug then
            State.Log.Debug("AutoBuyShop: skip require blocked module", moduleName)
        end
        return false
    end
    local ok, data = pcall(require, moduleScript)
    if not ok or type(data) ~= "table" then
        return false
    end

    local list = {}
    local byItem = {}
    local firstCostCurrency = nil
    for itemName, meta in pairs(data) do
        if type(itemName) == "string" and type(meta) == "table" then
            local costFn = meta.Cost
            if type(costFn) == "function" then
                local order = tonumber(meta.Order) or 999999
                local costCurrency = type(meta._Cost) == "string" and meta._Cost or nil
                if not firstCostCurrency and costCurrency then
                    firstCostCurrency = costCurrency
                end
                local maxLevel = nil
                local okCost, _, maxCount = pcall(costFn, 1)
                if okCost and type(maxCount) == "number" then
                    maxLevel = math.floor(maxCount)
                end
                list[#list + 1] = itemName
                byItem[itemName] = {
                    Order = order,
                    CostCurrency = costCurrency,
                    MaxLevel = maxLevel,
                    CostFn = costFn
                }
            end
        end
    end

    if #list == 0 then
        return false
    end

    table.sort(list, function(a, b)
        local oa = byItem[a] and byItem[a].Order or 999999
        local ob = byItem[b] and byItem[b].Order or 999999
        if oa == ob then
            return tostring(a) < tostring(b)
        end
        return oa < ob
    end)

    shop.Items = list
    shop.ModuleName = moduleScript.Name
    shop.MetaByItem = byItem
    if not shop.CurrencyName then
        shop.CurrencyName = firstCostCurrency or shop.ShopName or shop.Key
    end
    if not shop.UpgradeFolderName then
        shop.UpgradeFolderName = shop.ModuleName
    end
    return true
end
State.AutoBuyShop.Helpers.BuildShopMetaFallback = State.AutoBuyShop.Helpers.BuildShopMetaFallback or function(shop)
    if not shop then
        return
    end
    shop.MetaByItem = shop.MetaByItem or {}
    local fallbackOrder = 0
    for _, itemName in ipairs(shop.Items or {}) do
        if not shop.MetaByItem[itemName] then
            fallbackOrder += 1
            shop.MetaByItem[itemName] = {
                Order = fallbackOrder,
                CostCurrency = shop.CurrencyName or shop.ShopName or shop.Key,
                MaxLevel = nil,
                CostFn = nil
            }
        end
    end
    if not shop.CurrencyName then
        shop.CurrencyName = shop.ShopName or shop.Key
    end
    if not shop.UpgradeFolderName then
        shop.UpgradeFolderName = shop.ShopName or shop.Key
    end
end

local function setupAutoBuyGroup(section, opts)
    if not opts or type(opts) ~= "table" then
        return
    end

    local shops = opts.Shops or {}
    if #shops == 0 then
        return
    end

    local function setControlsEnabled(controls, enabled)
        for _, ctrl in ipairs(controls) do
            if ctrl and ctrl.SetEnabled then
                ctrl:SetEnabled(enabled)
            end
        end
    end

    local createListDropdownRow = State.UI.CreateListDropdownRow
    local helpers = State.AutoBuyShop.Helpers
    local getNumericValueFromNode = helpers.GetNumericValueFromNode
    local tryResolveFolder = helpers.TryResolveFolder
    local resolveItemMeta = helpers.ResolveItemMeta
    local buildShopMetaFromModule = helpers.BuildShopMetaFromModule
    local applyKnownModuleCostFallback = helpers.ApplyKnownModuleCostFallback
    local buildShopMetaFallback = helpers.BuildShopMetaFallback

    local groupKey = opts.GroupKey or opts.Key or opts.DisplayName or "AutoBuyGroup"
    Config.AutoBuyGroups = Config.AutoBuyGroups or {}
    local group = Config.AutoBuyGroups[groupKey] or {}
    Config.AutoBuyGroups[groupKey] = group

    group.UseUpgradeAll = group.UseUpgradeAll ~= nil and group.UseUpgradeAll or true
    group.SkipMaxed = group.SkipMaxed ~= nil and group.SkipMaxed or true
    group.Shops = group.Shops or {}
    group.Items = group.Items or {}
    group.Enabled = group.Enabled == true

    local shopByKey = {}
    local autoLoadModuleData = opts.UseModuleData ~= false
    for _, shop in ipairs(shops) do
        shop.Key = shop.Key or shop.ShopName or shop.DisplayName
        shop.DisplayName = shop.DisplayName or shop.ShopName or shop.Key
        local loadedByModule = false
        if autoLoadModuleData then
            loadedByModule = buildShopMetaFromModule(shop) == true
        end
        if not loadedByModule then
            applyKnownModuleCostFallback(shop)
        end
        buildShopMetaFallback(shop)
        shopByKey[shop.Key] = shop
        if group.Shops[shop.Key] == nil then
            group.Shops[shop.Key] = false
        end
        group.Items[shop.Key] = group.Items[shop.Key] or {}
        for _, item in ipairs(shop.Items or {}) do
            if group.Items[shop.Key][item] == nil then
                group.Items[shop.Key][item] = true
            end
        end
    end

    saveConfig()

    local function normalizeShopKeys(value)
        if type(value) == "string" then
            return {value}
        end
        if type(value) == "table" then
            local list = {}
            for _, key in ipairs(value) do
                if type(key) == "string" then
                    list[#list + 1] = key
                end
            end
            if #list > 0 then
                return list
            end
        end
        return nil
    end

    local resetPromptCfg = opts.ResetMaxedOnPrompt
    local resetPromptMatch = nil
    local resetPromptShopKeys = nil
    local resetPromptOnReset = nil
    if type(resetPromptCfg) == "table" then
        if type(resetPromptCfg.Match) == "string" then
            resetPromptMatch = string.lower(resetPromptCfg.Match)
        end
        resetPromptShopKeys = normalizeShopKeys(resetPromptCfg.ShopKey)
        if type(resetPromptCfg.OnReset) == "function" then
            resetPromptOnReset = resetPromptCfg.OnReset
        end
    end

    local resetPopupCfg = opts.ResetMaxedOnPopup
    local resetPopupMatches = nil
    local resetPopupShopKeys = nil
    local resetPopupOnReset = nil
    if type(resetPopupCfg) == "table" then
        if type(resetPopupCfg.Match) == "string" then
            resetPopupMatches = {string.lower(resetPopupCfg.Match)}
        elseif type(resetPopupCfg.Match) == "table" then
            local list = {}
            for _, value in ipairs(resetPopupCfg.Match) do
                if type(value) == "string" and #value > 0 then
                    list[#list + 1] = string.lower(value)
                end
            end
            if #list > 0 then
                resetPopupMatches = list
            end
        end
        resetPopupShopKeys = normalizeShopKeys(resetPopupCfg.ShopKey)
        if type(resetPopupCfg.OnReset) == "function" then
            resetPopupOnReset = resetPopupCfg.OnReset
        end
    end

    local enabled = group.Enabled == true
    local useUpgradeAll = group.UseUpgradeAll == true
    local skipMaxedEnabled = group.SkipMaxed == true
    local itemEnabled = group.Items
    local shopEnabled = group.Shops
    local maxed = {}
    local promptConn = nil
    local popupConn = nil
    local shopIndex = 1
    local itemIndex = {}

    local function getShopFireArgs(shop, itemName, itemCtx)
        if not shop or not itemName then
            return nil
        end
        local remoteItemName = itemName
        if type(itemCtx) == "table" and type(itemCtx.RemoteItemName) == "string" and #itemCtx.RemoteItemName > 0 then
            remoteItemName = itemCtx.RemoteItemName
        end
        if shop.SpecialAction == "MachinePartUpgrade" then
            local isUpgrade = not useUpgradeAll
            return "MachinePartUpgrade", remoteItemName, isUpgrade
        end
        local action = useUpgradeAll and "UpgradeAll" or "Upgrade"
        local shopArg = shop.RemoteShopName or shop.ShopName or shop.Key
        return action, shopArg, remoteItemName
    end

    local function resetShopMaxed(shopKey)
        local shop = shopByKey[shopKey]
        if not shop then
            return
        end
        maxed[shopKey] = nil
        itemIndex[shopKey] = 1
        if AutoBuyLogState.SetItemSkipped then
            for _, item in ipairs(shop.Items or {}) do
                AutoBuyLogState.SetItemSkipped(groupKey, shopKey, item, false)
            end
        end
    end

    local function argsHasMatch(args, match, depth)
        if not match or type(args) ~= "table" then
            return false
        end
        depth = depth or 0
        if depth > 4 then
            return false
        end
        for _, v in pairs(args) do
            if type(v) == "string" then
                local lower = string.lower(v)
                if string.find(lower, match, 1, true) then
                    return true
                end
            elseif type(v) == "table" then
                if argsHasMatch(v, match, depth + 1) then
                    return true
                end
            end
        end
        return false
    end

    local function attachPromptListener()
        if promptConn then
            return
        end
        local ok, remote = pcall(function()
            return game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.PromptNotification
        end)
        if not ok or not remote or not remote:IsA("RemoteEvent") then
            return
        end
        promptConn = remote.OnClientEvent:Connect(function(_, msg)
            if not enabled then
                return
            end
            if type(msg) ~= "string" then
                return
            end
            local lower = string.lower(msg)
            if resetPromptMatch and string.find(lower, resetPromptMatch, 1, true) then
                if resetPromptShopKeys then
                    for _, key in ipairs(resetPromptShopKeys) do
                        resetShopMaxed(key)
                    end
                end
                if resetPromptOnReset then
                    pcall(resetPromptOnReset)
                end
                return
            end
            if not string.find(lower, "already reached max upgrade", 1, true) then
                return
            end
            local candidates = {}
            for _, shop in ipairs(shops) do
                local key = shop.Key
                for _, item in ipairs(shop.Items or {}) do
                    candidates[#candidates + 1] = {Key = key, Item = item}
                end
            end
            local resolved = State.ResolveMaxedMatches and State.ResolveMaxedMatches(lower, candidates) or {}
            for _, entry in ipairs(resolved) do
                local key = entry.Key
                local item = entry.Item
                if key and item then
                    maxed[key] = maxed[key] or {}
                    maxed[key][item] = true
                    if AutoBuyLogState.SetItemSkipped then
                        AutoBuyLogState.SetItemSkipped(groupKey, key, item, true)
                    end
                end
            end
        end)
        trackConnection(promptConn)
    end

    local function attachPopupListener()
        if popupConn or not resetPopupMatches then
            return
        end
        local ok, remote = pcall(function()
            return game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.PopUp
        end)
        if not ok or not remote or not remote:IsA("RemoteEvent") then
            return
        end
        popupConn = remote.OnClientEvent:Connect(function(...)
            if not enabled then
                return
            end
            local args = {...}
            local matched = false
            for _, match in ipairs(resetPopupMatches) do
                if argsHasMatch(args, match) then
                    matched = true
                    break
                end
            end
            if matched then
                if resetPopupShopKeys then
                    for _, key in ipairs(resetPopupShopKeys) do
                        resetShopMaxed(key)
                    end
                end
                if resetPopupOnReset then
                    pcall(resetPopupOnReset)
                end
            end
        end)
        trackConnection(popupConn)
    end

    local function detachPromptListener()
        if promptConn then
            promptConn:Disconnect()
            promptConn = nil
        end
    end

    local function detachPopupListener()
        if popupConn then
            popupConn:Disconnect()
            popupConn = nil
        end
    end

    local function resolveUpgradeNode(shop, itemName, itemMeta)
        if not LP then
            return nil, itemMeta, itemName
        end
        local resolvedMeta, resolvedItemName = resolveItemMeta(shop, itemName)
        if not itemMeta then
            itemMeta = resolvedMeta
        end
        local upgrades = LP:FindFirstChild("Upgrades")
        if not upgrades then
            return nil, itemMeta, resolvedItemName or itemName
        end
        local folderCandidates = {
            shop and shop.UpgradeFolderName or nil,
            shop and shop.ModuleName or nil,
            itemMeta and itemMeta.CostCurrency or nil,
            shop and shop.CurrencyName or nil,
            shop and shop.ShopName or nil,
            shop and shop.Key or nil
        }
        local folder = nil
        if shop and shop.UpgradeFolderResolved and shop.UpgradeFolderResolved.Parent == upgrades then
            folder = shop.UpgradeFolderResolved
        else
            folder = tryResolveFolder(upgrades, folderCandidates)
            if folder and shop then
                shop.UpgradeFolderResolved = folder
            end
        end
        if not folder then
            return nil, itemMeta, resolvedItemName or itemName
        end
        local node = folder:FindFirstChild(resolvedItemName or itemName)
        if not node and type(itemName) == "string" then
            local targetName = string.lower(itemName)
            for _, child in ipairs(folder:GetChildren()) do
                if string.lower(tostring(child.Name)) == targetName then
                    node = child
                    break
                end
            end
        end
        if not node then
            return nil, itemMeta, resolvedItemName or itemName
        end
        return node, itemMeta, node.Name
    end

    local function resolveUpgradeLevel(shop, itemName, itemMeta)
        local node = nil
        node, itemMeta = resolveUpgradeNode(shop, itemName, itemMeta)
        if not node then
            return nil
        end
        local v = getNumericValueFromNode(node)
        if type(v) == "number" then
            return math.max(0, math.floor(v + 0.5))
        end
        return nil
    end

    local function resolveCurrencyAmount(shop, itemMeta)
        if not LP then
            return nil, nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        if not currencyRoot then
            return nil, nil
        end
        local currencyCandidates = {
            itemMeta and itemMeta.CostCurrency or nil,
            shop and shop.CurrencyName or nil,
            shop and shop.ShopName or nil,
            shop and shop.Key or nil
        }
        local folder, resolvedName = tryResolveFolder(currencyRoot, currencyCandidates)
        if not folder then
            return nil, nil
        end
        local amountFolder = folder:FindFirstChild("Amount")
        if not amountFolder then
            return nil, resolvedName
        end
        local valueNode = amountFolder:FindFirstChild("1")
        if not valueNode then
            local children = amountFolder:GetChildren()
            if #children > 0 then
                valueNode = children[1]
            end
        end
        local amount = getNumericValueFromNode(valueNode)
        return amount, resolvedName
    end

    local function getItemCostByLevel(itemMeta, nextLevel)
        if not itemMeta or type(itemMeta.CostFn) ~= "function" then
            return nil
        end
        local ok, value = pcall(itemMeta.CostFn, nextLevel)
        if ok and type(value) == "number" then
            return value
        end
        return nil
    end

    local function revalidateShopMaxed(shopKey)
        local shop = shopByKey[shopKey]
        if not shop then
            return
        end
        maxed[shopKey] = maxed[shopKey] or {}
        for _, name in ipairs(shop.Items or {}) do
            local itemMeta = nil
            itemMeta = select(1, resolveItemMeta(shop, name))
            local level = resolveUpgradeLevel(shop, name, itemMeta)
            local isMax = itemMeta and itemMeta.MaxLevel and level and level >= itemMeta.MaxLevel
            if isMax then
                maxed[shopKey][name] = true
            else
                maxed[shopKey][name] = nil
            end
            if AutoBuyLogState.SetItemSkipped then
                AutoBuyLogState.SetItemSkipped(groupKey, shopKey, name, isMax == true)
            end
        end
        if next(maxed[shopKey]) == nil then
            maxed[shopKey] = nil
        end
    end

    local function revalidateAllShops()
        for _, shop in ipairs(shops) do
            if shop and shop.Key then
                revalidateShopMaxed(shop.Key)
            end
        end
    end

    local function getNextItem()
        local totalShops = #shops
        for _ = 1, totalShops do
            local shop = shops[shopIndex]
            shopIndex += 1
            if shopIndex > totalShops then
                shopIndex = 1
            end

            local key = shop.Key
            if shopEnabled[key] then
                local list = shop.Items or {}
                local idx = itemIndex[key] or 1
                for _ = 1, #list do
                    local name = list[idx]
                    idx += 1
                    if idx > #list then
                        idx = 1
                    end
                    if itemEnabled[key] and itemEnabled[key][name] then
                            local itemMeta = nil
                            local node = nil
                            local remoteItemName = name
                            node, itemMeta, remoteItemName = resolveUpgradeNode(shop, name)
                            local level = nil
                            if node then
                                local rawLevel = getNumericValueFromNode(node)
                                if type(rawLevel) == "number" then
                                    level = math.max(0, math.floor(rawLevel + 0.5))
                                end
                            end
                            local reachedMaxByLevel = false
                            if itemMeta and itemMeta.MaxLevel and level and level >= itemMeta.MaxLevel then
                                reachedMaxByLevel = true
                        end
                        if reachedMaxByLevel then
                            maxed[key] = maxed[key] or {}
                            maxed[key][name] = true
                            if AutoBuyLogState.SetItemSkipped then
                                AutoBuyLogState.SetItemSkipped(groupKey, key, name, true)
                            end
                        end
                            if (not skipMaxedEnabled or not (maxed[key] and maxed[key][name])) and not reachedMaxByLevel then
                                local nextLevel = (level or 0) + 1
                                local cost = getItemCostByLevel(itemMeta, nextLevel)
                                local currencyAmount, currencyName = resolveCurrencyAmount(shop, itemMeta)
                                if type(cost) ~= "number" or type(currencyAmount) ~= "number" or currencyAmount >= cost then
                                    itemIndex[key] = idx
                                    return shop, name, {
                                        RemoteItemName = remoteItemName,
                                        CurrencyName = currencyName,
                                        CurrencyBefore = currencyAmount
                                    }
                            end
                        end
                    end
                end
                itemIndex[key] = idx
            end
        end
        return nil
    end

    local container = createSubSectionBox(section, opts.DisplayName or "Auto Buy Shop")
    local childControls = {}

    local function addControl(ctrl)
        childControls[#childControls + 1] = ctrl
        return ctrl
    end

    local uiReady = false

    local waitCurrencyState = {
        Active = false,
        Since = 0,
        Timeout = 1.2,
        CurrencyName = nil,
        Before = nil
    }

    State.AutoBuyRuntime = State.AutoBuyRuntime or {}
    State.AutoBuyRuntime[groupKey] = {
        RevalidateShop = revalidateShopMaxed,
        RevalidateAll = revalidateAllShops,
        ResetShopMaxed = resetShopMaxed
    }
    if State.CleanupRegistry and State.CleanupRegistry.Register then
        State.CleanupRegistry.Register(function()
            if State.AutoBuyRuntime then
                State.AutoBuyRuntime[groupKey] = nil
            end
        end)
    end

    local function applyEnabledState(value)
        enabled = value == true
        group.Enabled = enabled
        saveConfig()
        setControlsEnabled(childControls, enabled)
        setAutoBuyGroupActive(groupKey, opts.DisplayName or groupKey, enabled, shops, shopEnabled, itemEnabled)
        if enabled then
            shopIndex = 1
            itemIndex = {}
            maxed = {}
            revalidateAllShops()
            if AutoBuyLogState.ClearSkippedGroup then
                AutoBuyLogState.ClearSkippedGroup(groupKey)
            end
            waitCurrencyState.Active = false
            attachPromptListener()
            attachPopupListener()
            autoBuySchedulerRegister(groupKey, {
                Step = function()
                    if not enabled then
                        return false
                    end
                    if waitCurrencyState.Active then
                        local updated = nil
                        if waitCurrencyState.CurrencyName then
                            local amount, resolvedName = resolveCurrencyAmount({
                                CurrencyName = waitCurrencyState.CurrencyName
                            }, {
                                CostCurrency = waitCurrencyState.CurrencyName
                            })
                            if resolvedName and resolvedName == waitCurrencyState.CurrencyName then
                                updated = amount
                            end
                        end
                        if type(updated) == "number" and type(waitCurrencyState.Before) == "number" and math.abs(updated - waitCurrencyState.Before) > 1e-9 then
                            waitCurrencyState.Active = false
                        elseif (os.clock() - waitCurrencyState.Since) >= waitCurrencyState.Timeout then
                            waitCurrencyState.Active = false
                        else
                            return false
                        end
                    end
                    local remote = nil
                    if opts.GetRemote then
                        remote = opts.GetRemote()
                    elseif getMainRemote then
                        remote = getMainRemote()
                    end
                    if not remote then
                        return false
                    end
                    local shop, itemName, itemCtx = getNextItem()
                    if shop and itemName then
                        local a1, a2, a3 = getShopFireArgs(shop, itemName, itemCtx)
                        if a1 then
                            pcall(function()
                                remote:FireServer(a1, a2, a3)
                            end)
                            if itemCtx and itemCtx.CurrencyName and type(itemCtx.CurrencyBefore) == "number" then
                                waitCurrencyState.Active = true
                                waitCurrencyState.Since = os.clock()
                                waitCurrencyState.CurrencyName = itemCtx.CurrencyName
                                waitCurrencyState.Before = itemCtx.CurrencyBefore
                            else
                                waitCurrencyState.Active = false
                            end
                        end
                        if AutoBuyLogState.SetActiveItem then
                            AutoBuyLogState.SetActiveItem(groupKey, shop.Key, itemName)
                        end
                        return true
                    end
                    return false
                end
            })
        else
            autoBuySchedulerUnregister(groupKey)
            detachPromptListener()
            detachPopupListener()
            waitCurrencyState.Active = false
        end
    end

    local enabledToggle = createToggle(container, "On/Off", nil, enabled, function(v)
        if not uiReady then
            return
        end
        applyEnabledState(v)
    end)

    addControl(createToggle(container, opts.ModeToggleName or "Mode: Upgrade All", nil, useUpgradeAll, function(v)
        useUpgradeAll = v == true
        group.UseUpgradeAll = useUpgradeAll
        saveConfig()
    end))

    addControl(createToggle(container, "Skip Maxed Items", nil, skipMaxedEnabled, function(v)
        skipMaxedEnabled = v == true
        group.SkipMaxed = skipMaxedEnabled
        saveConfig()
    end))

    local listContainer
    addControl(createListDropdownRow(container, "Item List", function(open)
        if listContainer then
            listContainer.Visible = open
        end
    end))

    local listContent = createSubSectionBox(container, "Item List")
    listContainer = listContent.Parent
    listContainer.Visible = false

    local function addListDivider(parent)
        local div = Instance.new("Frame")
        div.Size = UDim2.new(1, 0, 0, 1)
        div.BorderSizePixel = 0
        div.Parent = parent
        registerTheme(div, "BackgroundColor3", "Muted")
        return div
    end

    for i, shop in ipairs(shops) do
        local shopKey = shop.Key
        local shopCtrl = createToggle(listContent, shop.DisplayName, nil, shopEnabled[shopKey], function(v)
            shopEnabled[shopKey] = v == true
            group.Shops[shopKey] = shopEnabled[shopKey]
            saveConfig()
            if enabled then
                setAutoBuyGroupActive(groupKey, opts.DisplayName or groupKey, enabled, shops, shopEnabled, itemEnabled)
            end
        end)
        if shopCtrl and shopCtrl.Label then
            shopCtrl.Label.Font = Enum.Font.GothamSemibold
            shopCtrl.Label.TextSize = 12
        end
        addControl(shopCtrl)

        for _, item in ipairs(shop.Items or {}) do
            addControl(createToggle(listContent, item, nil, itemEnabled[shopKey][item], function(v)
                itemEnabled[shopKey][item] = v == true
                group.Items[shopKey][item] = itemEnabled[shopKey][item]
                saveConfig()
                if enabled then
                    setAutoBuyGroupActive(groupKey, opts.DisplayName or groupKey, enabled, shops, shopEnabled, itemEnabled)
                end
            end))
        end

        if i < #shops then
            addListDivider(listContent)
        end
    end

    setControlsEnabled(childControls, enabled)
    uiReady = true
    applyEnabledState(enabled)
end

local function createDropdown(parent, text, flag, options, currentOption, callback)
    local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
        RowH = 30,
        RowPadX = 10,
        RowPadY = 4,
        ContentGap = 8,
        RadiusSm = 6
    }
    local selected = currentOption
    if flag and State.Config and State.Config.Get then
        selected = State.Config.Get(flag, selected)
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.BorderSizePixel = 0
    frame.Parent = parent
    registerTheme(frame, "BackgroundColor3", "Main")
    addCorner(frame, tokens.RadiusSm)
    addStroke(frame, "Muted", 1, 0.8)

    local stack = Instance.new("UIListLayout")
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.Padding = UDim.new(0, tokens.InputPadSm or 4)
    stack.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, tokens.RowH)
    btn.BackgroundTransparency = 1
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.TextYAlignment = Enum.TextYAlignment.Center
    btn.AutoButtonColor = false
    btn.Text = text .. ": " .. tostring(selected)
    btn.Parent = frame
    setFontClass(btn, "Body")
    registerTheme(btn, "TextColor3", "Text")

    local btnPad = Instance.new("UIPadding")
    btnPad.PaddingLeft = UDim.new(0, tokens.RowPadX)
    btnPad.PaddingRight = UDim.new(0, tokens.RowPadX)
    btnPad.PaddingTop = UDim.new(0, tokens.RowPadY)
    btnPad.PaddingBottom = UDim.new(0, tokens.RowPadY)
    btnPad.Parent = btn

    local list = Instance.new("Frame")
    list.Size = UDim2.new(1, 0, 0, 0)
    list.BorderSizePixel = 0
    list.Visible = false
    list.Parent = frame
    registerTheme(list, "BackgroundColor3", "Panel")
    addCorner(list, tokens.RadiusSm)

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, tokens.InputPadSm or 4)
    listLayout.Parent = list

    local function setSelected(v, silent)
        selected = v
        btn.Text = text .. ": " .. tostring(selected)
        if flag and State.Config and State.Config.Set then
            State.Config.Set(flag, v)
        end
        if callback and not silent then
            callback(v)
        end
    end

    for _, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, math.max(22, tokens.RowH - 6))
        optBtn.BorderSizePixel = 0
        optBtn.Font = Enum.Font.Gotham
        optBtn.TextSize = 12
        optBtn.Text = tostring(opt)
        optBtn.TextXAlignment = Enum.TextXAlignment.Left
        optBtn.TextYAlignment = Enum.TextYAlignment.Center
        optBtn.AutoButtonColor = false
        optBtn.Parent = list
        setFontClass(optBtn, "Small")
        registerTheme(optBtn, "BackgroundColor3", "Main")
        registerTheme(optBtn, "TextColor3", "Text")
        addCorner(optBtn, tokens.RadiusSm)

        local optPad = Instance.new("UIPadding")
        optPad.PaddingLeft = UDim.new(0, tokens.RowPadX)
        optPad.PaddingRight = UDim.new(0, tokens.RowPadX)
        optPad.PaddingTop = UDim.new(0, math.max(1, tokens.RowPadY - 1))
        optPad.PaddingBottom = UDim.new(0, math.max(1, tokens.RowPadY - 1))
        optPad.Parent = optBtn

        optBtn.MouseButton1Click:Connect(function()
            list.Visible = false
            setSelected(opt, false)
        end)
    end

    local function updateListSize()
        if list.Visible then
            list.Size = UDim2.new(1, 0, 0, #options * 26)
        else
            list.Size = UDim2.new(1, 0, 0, 0)
        end
    end

    btn.MouseButton1Click:Connect(function()
        list.Visible = not list.Visible
        updateListSize()
    end)

    updateListSize()

    setSelected(selected, true)
    if callback then
        callback(selected)
    end

    return {
        Set = function(_, v)
            setSelected(v, true)
        end,
        Get = function()
            return selected
        end,
        Destroy = function()
            frame:Destroy()
        end
    }
end

local function createTab(name)
    local tabButton = createTabButton(name)
    local page = createPage()
    page.Name = "Page_" .. tostring(name)

    local function setActive()
        for _, child in ipairs(Pages:GetChildren()) do
            if child:IsA("GuiObject") then
                child.Visible = false
            end
        end
        page.Visible = true

        ActiveTabButton = tabButton
        applyTheme(Config.Theme or "Default")
    end

    tabButton.MouseButton1Click:Connect(setActive)

    return {
        Show = setActive,
        GetPage = function()
            return page
        end,
        CreateSection = function(_, title)
            return createSection(page, title)
        end,
        CreateSubSection = function(_, title)
            return createSubSection(page, title)
        end,
        CreateParagraph = function(_, opts)
            return createParagraph(page, opts.Title, opts.Content)
        end,
        CreateInput = function(_, opts)
            return createInput(page, opts.Name, opts.Flag, opts.CurrentValue, opts.Callback)
        end,
        CreateKeybindInput = function(_, opts)
            return createKeybindInput(page, opts.Name, opts.Flag, opts.CurrentValue, opts.Callback)
        end,
        CreateContainer = function(_, height)
            return createContainer(page, height)
        end,
        CreateButton = function(_, opts)
            return createButton(page, opts.Name, opts.Callback)
        end,
        CreateToggle = function(_, opts)
            return createToggle(page, opts.Name, opts.Flag, opts.CurrentValue, opts.Callback)
        end,
        CreateSlider = function(_, opts)
            return createSlider(
                page,
                opts.Name,
                opts.Flag,
                opts.Range[1],
                opts.Range[2],
                opts.CurrentValue,
                opts.Callback,
                opts.Decimals,
                opts.Format
            )
        end,
        CreateDropdown = function(_, opts)
            return createDropdown(page, opts.Name, opts.Flag, opts.Options, opts.CurrentOption, opts.Callback)
        end
    }
end

-- =====================================================
-- NOTIFY
-- =====================================================
State.Notify = State.Notify or {}
State.Notify.Margin = State.Notify.Margin or 8
State.Notify.MarginX = State.Notify.MarginX or State.Notify.Margin
State.Notify.MarginY = State.Notify.MarginY or 2
State.Notify.Width = State.Notify.Width or 260
State.Notify.MinWidth = State.Notify.MinWidth or 180
State.Notify.MinHeight = State.Notify.MinHeight or 44
State.Notify.MaxHeightRatio = State.Notify.MaxHeightRatio or 0.5
State.Notify.Counter = State.Notify.Counter or 0

State.Notify.EnsureContainer = State.Notify.EnsureContainer or function()
    if State.Notify.Container and State.Notify.Container.Parent then
        return
    end
    local container = Instance.new("ScrollingFrame")
    container.Name = "NotifyContainer"
    container.Size = UDim2.new(0, State.Notify.Width, 0, 0)
    container.Position = UDim2.new(1, -(State.Notify.Width + (State.Notify.MarginX or State.Notify.Margin)), 0, (State.Notify.MarginY or State.Notify.Margin))
    container.AnchorPoint = Vector2.new(0, 0)
    container.BorderSizePixel = 0
    container.BackgroundTransparency = 1
    container.ScrollBarThickness = 4
    container.ScrollingDirection = Enum.ScrollingDirection.Y
    container.CanvasSize = UDim2.new(0, 0, 0, 0)
    container.Parent = ScreenGui
    container.Active = true
    if State.Layout and State.Layout.ApplyScale then
        State.Layout.ApplyScale(container)
    end

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 8)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = container
    trackConnection(list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if State.Notify and State.Notify.UpdateLayout then
            State.Notify.UpdateLayout()
        end
    end))

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 0)
    pad.PaddingBottom = UDim.new(0, 0)
    pad.PaddingLeft = UDim.new(0, 0)
    pad.PaddingRight = UDim.new(0, 0)
    pad.Parent = container

    State.Notify.Container = container
    State.Notify.List = list
end

State.Notify.UpdateLayout = State.Notify.UpdateLayout or function()
    local container = State.Notify.Container
    local list = State.Notify.List
    if not container or not list then
        return
    end
    if State.Layout and State.Layout.ApplyScale then
        State.Layout.ApplyScale(container)
    end
    local vp = (State.Layout and State.Layout.GetViewport and State.Layout.GetViewport()) or Vector2.new(0, 0)
    local inset = (State.Layout and State.Layout.GetInset and State.Layout.GetInset()) or Vector2.new(0, 0)
    local scale = (State.Layout and State.Layout.GetScale and State.Layout.GetScale()) or 1
    local marginX = State.Notify.MarginX or State.Notify.Margin or 8
    local marginY = State.Notify.MarginY or State.Notify.Margin or 2
    local baseWidth = State.Notify.Width or 260
    local minWidth = State.Notify.MinWidth or 180
    local maxWidth = math.max(minWidth, math.floor((vp.X * 0.36) / math.max(0.1, scale)))
    local width = math.clamp(baseWidth, minWidth, maxWidth)
    local maxH = math.floor(vp.Y * (State.Notify.MaxHeightRatio or 0.5))
    local contentH = list.AbsoluteContentSize.Y
    local height = math.max(0, math.min(contentH, maxH))
    container.Size = UDim2.new(0, width, 0, height)
    container.CanvasSize = UDim2.new(0, 0, 0, contentH)
    State.Notify.LastWidth = width
    State.Notify.LastScale = scale
    local topInset = (ScreenGui and ScreenGui.IgnoreGuiInset) and inset.Y or 0
    local x = math.max(marginX, vp.X - (width * scale) - marginX)
    container.Position = UDim2.new(0, x, 0, marginY + topInset)
end

  local function notify(title, content, duration)
      if State.Notify and State.Notify.EnsureContainer then
          State.Notify.EnsureContainer()
      end
      local notif = Instance.new("Frame")
    notif.Size = UDim2.new(1, 0, 0, 0)
    notif.AutomaticSize = Enum.AutomaticSize.Y
    notif.Position = UDim2.new(0, 0, 0, 0)
    notif.BorderSizePixel = 0
    notif.Parent = State.Notify.Container or ScreenGui
    registerTheme(notif, "BackgroundColor3", "Main")
    addCorner(notif, 8)
    addStroke(notif, "Muted", 1, 0.8)
    State.Notify.Counter = (State.Notify.Counter or 0) + 1
    notif.LayoutOrder = State.Notify.Counter

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = notif

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 18)
    header.BackgroundTransparency = 1
    header.Parent = notif

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -24, 1, 0)
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.GothamSemibold
    t.TextSize = 12
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Text = title
    t.Parent = header
    setFontClass(t, "Heading")
    registerTheme(t, "TextColor3", "Text")

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 20, 0, 18)
    closeBtn.Position = UDim2.new(1, -20, 0, 0)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "x"
    closeBtn.AutoButtonColor = false
    closeBtn.Font = Enum.Font.GothamSemibold
    closeBtn.TextSize = 11
    closeBtn.Parent = header
    setFontClass(closeBtn, "Small")
    registerTheme(closeBtn, "BackgroundColor3", "Panel")
    registerTheme(closeBtn, "TextColor3", "Text")
    addCorner(closeBtn, 4)

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, 0, 0, 2)
    divider.BorderSizePixel = 0
    divider.Parent = notif
    registerTheme(divider, "BackgroundColor3", "Accent")

    local c = Instance.new("TextLabel")
    c.Size = UDim2.new(1, 0, 0, 0)
    c.AutomaticSize = Enum.AutomaticSize.Y
    c.BackgroundTransparency = 1
    c.Font = Enum.Font.Gotham
    c.TextSize = 12
    c.TextWrapped = true
    c.TextXAlignment = Enum.TextXAlignment.Left
    c.TextYAlignment = Enum.TextYAlignment.Top
    c.Text = content
    c.Parent = notif
    setFontClass(c, "Body")
      registerTheme(c, "TextColor3", "Muted")

      local list = Instance.new("UIListLayout")
      list.Padding = UDim.new(0, 6)
      list.SortOrder = Enum.SortOrder.LayoutOrder
      list.Parent = notif

    local minSize = Instance.new("UISizeConstraint")
    local minW = State.Notify.MinWidth or 180
    local maxW = State.Notify.LastWidth or State.Notify.Width or 260
    if maxW > 0 then
        minW = math.min(minW, maxW)
    end
    minSize.MinSize = Vector2.new(minW, State.Notify.MinHeight or 44)
    minSize.Parent = notif

      local closing = false
      local function closeNotify()
          if closing then
              return
          end
          closing = true
          if State.UI and State.UI.AnimateHide then
              local tween = State.UI.AnimateHide(notif, {EndScale = 0.92, Duration = 0.12})
              if tween then
                  tween.Completed:Connect(function()
                      if notif and notif.Parent then
                          notif:Destroy()
                          if State.Notify and State.Notify.UpdateLayout then
                              State.Notify.UpdateLayout()
                          end
                      end
                  end)
                  return
              end
          end
          if notif and notif.Parent then
              notif:Destroy()
              if State.Notify and State.Notify.UpdateLayout then
                  State.Notify.UpdateLayout()
              end
          end
      end

      closeBtn.MouseButton1Click:Connect(closeNotify)

      task.delay(duration or 4, closeNotify)

      if State.UI and State.UI.AnimateShow then
          State.UI.AnimateShow(notif, {StartScale = 0.92, Duration = 0.18})
      end
      if State.Notify and State.Notify.UpdateLayout then
          State.Notify.UpdateLayout()
      end
  end

State.UI.Notify = State.UI.Notify or {}
State.UI.Notify.Show = State.UI.Notify.Show or notify
State.UI.Notify.EnsureContainer = State.UI.Notify.EnsureContainer or function()
    if State.Notify and State.Notify.EnsureContainer then
        State.Notify.EnsureContainer()
    end
end
State.UI.Notify.UpdateLayout = State.UI.Notify.UpdateLayout or function()
    if State.Notify and State.Notify.UpdateLayout then
        State.Notify.UpdateLayout()
    end
end

State.UI.Dialog = State.UI.Dialog or {}
State.UI.Dialog.Confirm = State.UI.Dialog.Confirm or function(title, content, onConfirm)
    local dialog = Instance.new("Frame")
    local vp = (State.Layout and State.Layout.GetViewport and State.Layout.GetViewport()) or Vector2.new(0, 0)
    local scale = (State.Layout and State.Layout.GetScale and State.Layout.GetScale()) or 1
    local baseW = 320
    local minW = 220
    local maxW = math.max(minW, math.floor((vp.X * 0.7) / math.max(0.1, scale)))
    local width = math.clamp(baseW, minW, maxW)
    dialog.Size = UDim2.new(0, width, 0, 0)
    dialog.AutomaticSize = Enum.AutomaticSize.Y
    dialog.Position = UDim2.new(0.5, -math.floor(width / 2), 0.5, 0)
    dialog.BorderSizePixel = 0
    dialog.Parent = ScreenGui
    dialog.ZIndex = 200
    dialog.Active = true
    if State.Layout and State.Layout.ApplyScale then
        State.Layout.ApplyScale(dialog)
    end
    registerTheme(dialog, "BackgroundColor3", "Main")
    addCorner(dialog, 10)
    addStroke(dialog, "Muted", 1, 0.6)
    addGradient(dialog, 90, 0, 0.15)

    local titleBar = Instance.new("TextLabel")
    titleBar.Size = UDim2.new(1, -20, 0, 28)
    titleBar.Position = UDim2.new(0, 10, 0, 0)
    titleBar.BackgroundTransparency = 1
    titleBar.Font = Enum.Font.GothamSemibold
    titleBar.TextSize = 14
    titleBar.TextXAlignment = Enum.TextXAlignment.Left
    titleBar.Text = title or "Konfirmasi"
    titleBar.ZIndex = 201
    titleBar.Parent = dialog
    titleBar.Active = true
    setFontClass(titleBar, "Heading")
    registerTheme(titleBar, "TextColor3", "Text")

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 2)
    line.Position = UDim2.new(0, 0, 0, 28)
    line.BorderSizePixel = 0
    line.Parent = dialog
    registerTheme(line, "BackgroundColor3", "Accent")

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, 0, 0, 0)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.Position = UDim2.new(0, 0, 0, 32)
    body.BackgroundTransparency = 1
    body.Parent = dialog

    local c = Instance.new("TextLabel")
    c.Size = UDim2.new(1, 0, 0, 0)
    c.AutomaticSize = Enum.AutomaticSize.Y
    c.BackgroundTransparency = 1
    c.Font = Enum.Font.Gotham
    c.TextSize = 12
    c.TextWrapped = true
    c.TextXAlignment = Enum.TextXAlignment.Left
    c.TextYAlignment = Enum.TextYAlignment.Top
    c.Text = content
    c.ZIndex = 201
    c.Parent = body
    setFontClass(c, "Body")
    registerTheme(c, "TextColor3", "Muted")

    local btnRow = Instance.new("Frame")
    btnRow.Size = UDim2.new(1, 0, 0, 28)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = body
    btnRow.LayoutOrder = 2

    local yesControl = createButton(btnRow, "Keluar", function()
        if dialog then
            dialog:Destroy()
        end
        if onConfirm then
            onConfirm()
        end
    end)
    local btnYes = yesControl.Button
    btnYes.Size = UDim2.new(0.5, -6, 1, 0)
    btnYes.Position = UDim2.new(0, 0, 0, 0)
    btnYes.ZIndex = 201
    registerTheme(btnYes, "BackgroundColor3", "Main")

    local noControl = createButton(btnRow, "Batal", function()
        if dialog then
            dialog:Destroy()
        end
    end)
    local btnNo = noControl.Button
    btnNo.Size = UDim2.new(0.5, -6, 1, 0)
    btnNo.Position = UDim2.new(0.5, 6, 0, 0)
    btnNo.ZIndex = 201
    registerTheme(btnNo, "BackgroundColor3", "Main")

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.Parent = body

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = body

    local dragging = false
    local dragStart = nil
    local startPos = nil

    local function beginDrag(input)
        dragging = true
        dragStart = input.Position
        startPos = dialog.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end

    trackConnection(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            beginDrag(input)
        end
    end))

    trackConnection(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            dialog.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end))
end
confirmDialog = State.UI.Dialog.Confirm

-- =====================================================
-- TABS
-- =====================================================
local teleportWithData
local function buildTabsUI()
LoadingUI:Set(35, "Membuat tab utama...")
local HomeTab = createTab("Home")

HomeTab:CreateSection("Home")

do
    HomeTab:CreateParagraph({
        Title = "Informasi Script",
        Content = table.concat({
            "Ringkas",
            "Garden Incremental UI",
            "Versi: " .. tostring(State.Version),
            "Fokus: Teleport, Auto Buy, Automation, Log/Spy, dan Utility.",
            "",
            "Cara Pakai",
            "- Pilih tab sesuai kebutuhan.",
            "- Aktifkan fitur lalu cek notify untuk status.",
            "- Atur tema, font, dan click speed di Settings.",
            "",
            "Catatan",
            "- Auto Reload butuh executor yang mendukung queue_on_teleport.",
            "- Resize UI lewat ikon kanan bawah."
        }, "\n")
    })
end

-- =====================================================
-- PLAYER TAB
-- =====================================================
LoadingUI:Set(45, "Menambahkan modul player...")
local PlayerTab = createTab("Player")
PlayerTab:CreateSection("Movement")

local InfiniteJump = false

State.Movement = State.Movement or {}
State.Movement.Input = State.Movement.Input or { Keys = {}, Bound = false }
State.Movement.GetHumanoid = State.Movement.GetHumanoid or function()
    if not (LP and LP.Character) then
        return nil
    end
    return LP.Character:FindFirstChildOfClass("Humanoid")
end
State.Movement.GetRoot = State.Movement.GetRoot or function()
    if not (LP and LP.Character) then
        return nil
    end
    return LP.Character:FindFirstChild("HumanoidRootPart")
end

State.Movement.Fly = State.Movement.Fly or {
    Enabled = false,
    Speed = Config.FlySpeed or 60,
    Inertia = Config.FlyInertia or 0.15,
    BV = nil,
    BG = nil,
    Conn = nil,
    Vel = Vector3.new()
}

State.Movement.Fly.SetSpeed = State.Movement.Fly.SetSpeed or function(value)
    local speed = math.floor((tonumber(value) or 0) + 0.5)
    if speed < 0 then
        speed = 0
    end
    State.Movement.Fly.Speed = speed
    Config.FlySpeed = speed
    return speed
end

State.Movement.Fly.SetInertia = State.Movement.Fly.SetInertia or function(value)
    local inertia = tonumber(value) or 0
    inertia = math.clamp(inertia, 0, 1)
    State.Movement.Fly.Inertia = inertia
    Config.FlyInertia = inertia
    return inertia
end

State.Movement.Fly.Stop = State.Movement.Fly.Stop or function()
    State.Movement.Fly.Enabled = false
    if State.Movement.Fly.Conn then
        State.Movement.Fly.Conn:Disconnect()
        State.Movement.Fly.Conn = nil
    end
    if State.Movement.Fly.BV then
        State.Movement.Fly.BV:Destroy()
        State.Movement.Fly.BV = nil
    end
    if State.Movement.Fly.BG then
        State.Movement.Fly.BG:Destroy()
        State.Movement.Fly.BG = nil
    end
    State.Movement.Fly.Vel = Vector3.new()
end

State.Movement.Fly.Start = State.Movement.Fly.Start or function()
    if State.Movement.Fly.Enabled then
        return
    end
    local hrp = State.Movement.GetRoot()
    if not hrp then
        return
    end
    State.Movement.Fly.Enabled = true

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bv.P = 1250
    bv.Velocity = Vector3.new()
    bv.Parent = hrp
    State.Movement.Fly.BV = bv

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bg.P = 4000
    bg.D = 600
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp
    State.Movement.Fly.BG = bg

    State.Movement.Fly.Vel = Vector3.new()
    State.Movement.Fly.Conn = RunService.Heartbeat:Connect(function(dt)
        if not State.Movement.Fly.Enabled then
            return
        end
        local cam = workspace.CurrentCamera
        if not cam then
            return
        end

        local input = State.Movement.Input.Keys
        local move = Vector3.new()
        if input.W then move = move + cam.CFrame.LookVector end
        if input.S then move = move - cam.CFrame.LookVector end
        if input.A then move = move - cam.CFrame.RightVector end
        if input.D then move = move + cam.CFrame.RightVector end
        if input.Space then move = move + cam.CFrame.UpVector end
        if input.Ctrl then move = move - cam.CFrame.UpVector end
        if move.Magnitude > 0 then
            move = move.Unit
        end

        local target = move * (State.Movement.Fly.Speed or 60)
        local alpha = math.clamp(1 - (State.Movement.Fly.Inertia or 0), 0.05, 1)
        State.Movement.Fly.Vel = State.Movement.Fly.Vel:Lerp(target, alpha)
        bv.Velocity = State.Movement.Fly.Vel
        bg.CFrame = cam.CFrame
    end)
    trackConnection(State.Movement.Fly.Conn)
end

State.Movement.NoClip = State.Movement.NoClip or { Enabled = false, Conn = nil, CharConn = nil }
State.Movement.NoClip.Apply = State.Movement.NoClip.Apply or function()
    if not State.Movement.NoClip.Enabled then
        return
    end
    local char = LP and LP.Character
    if not char then
        return
    end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if part:GetAttribute("GI_NoClip_Orig") == nil then
                part:SetAttribute("GI_NoClip_Orig", part.CanCollide == true)
            end
            part.CanCollide = false
        end
    end
end

State.Movement.NoClip.Stop = State.Movement.NoClip.Stop or function()
    State.Movement.NoClip.Enabled = false
    if State.Movement.NoClip.Conn then
        State.Movement.NoClip.Conn:Disconnect()
        State.Movement.NoClip.Conn = nil
    end
    local char = LP and LP.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                local orig = part:GetAttribute("GI_NoClip_Orig")
                if orig ~= nil then
                    part.CanCollide = orig and true or false
                    part:SetAttribute("GI_NoClip_Orig", nil)
                end
            end
        end
    end
end

State.Movement.NoClip.Start = State.Movement.NoClip.Start or function()
    if State.Movement.NoClip.Enabled then
        return
    end
    State.Movement.NoClip.Enabled = true
    State.Movement.NoClip.Apply()
    if not State.Movement.NoClip.Conn then
        State.Movement.NoClip.Conn = RunService.Stepped:Connect(function()
            State.Movement.NoClip.Apply()
        end)
        trackConnection(State.Movement.NoClip.Conn)
    end
end

State.Movement.Freecam = State.Movement.Freecam or {
    Enabled = false,
    Speed = Config.FreecamSpeed or 1.6,
    Conn = nil,
    MouseConn = nil,
    Prev = nil,
    Yaw = 0,
    Pitch = 0,
    CFrame = nil
}

State.Movement.Freecam.SetSpeed = State.Movement.Freecam.SetSpeed or function(value)
    local speed = tonumber(value) or 0
    if speed < 0 then
        speed = 0
    end
    State.Movement.Freecam.Speed = speed
    Config.FreecamSpeed = speed
    return speed
end

State.Movement.Freecam.Stop = State.Movement.Freecam.Stop or function()
    State.Movement.Freecam.Enabled = false
    if State.Movement.Freecam.Conn then
        State.Movement.Freecam.Conn:Disconnect()
        State.Movement.Freecam.Conn = nil
    end
    if State.Movement.Freecam.MouseConn then
        State.Movement.Freecam.MouseConn:Disconnect()
        State.Movement.Freecam.MouseConn = nil
    end
    local cam = workspace.CurrentCamera
    if cam and State.Movement.Freecam.Prev then
        cam.CameraType = State.Movement.Freecam.Prev.Type
        cam.CameraSubject = State.Movement.Freecam.Prev.Subject
        cam.CFrame = State.Movement.Freecam.Prev.CFrame
    end
    UIS.MouseBehavior = Enum.MouseBehavior.Default
    UIS.MouseIconEnabled = true
    State.Movement.Freecam.Prev = nil
end

State.Movement.Freecam.Start = State.Movement.Freecam.Start or function()
    if State.Movement.Freecam.Enabled then
        return
    end
    local cam = workspace.CurrentCamera
    if not cam then
        return
    end
    State.Movement.Freecam.Enabled = true
    State.Movement.Freecam.Prev = {
        Type = cam.CameraType,
        Subject = cam.CameraSubject,
        CFrame = cam.CFrame
    }
    cam.CameraType = Enum.CameraType.Scriptable
    State.Movement.Freecam.CFrame = cam.CFrame
    local look = cam.CFrame.LookVector
    State.Movement.Freecam.Yaw = math.atan2(-look.X, -look.Z)
    State.Movement.Freecam.Pitch = math.asin(math.clamp(look.Y, -1, 1))

    UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
    UIS.MouseIconEnabled = false

    State.Movement.Freecam.MouseConn = UIS.InputChanged:Connect(function(input)
        if not State.Movement.Freecam.Enabled then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local dx = input.Delta.X
            local dy = input.Delta.Y
            State.Movement.Freecam.Yaw = State.Movement.Freecam.Yaw - (dx * 0.0025)
            State.Movement.Freecam.Pitch = State.Movement.Freecam.Pitch - (dy * 0.0025)
            State.Movement.Freecam.Pitch = math.clamp(State.Movement.Freecam.Pitch, -1.5, 1.5)
        end
    end)
    trackConnection(State.Movement.Freecam.MouseConn)

    State.Movement.Freecam.Conn = RunService.RenderStepped:Connect(function(dt)
        if not State.Movement.Freecam.Enabled then
            return
        end
        local input = State.Movement.Input.Keys
        local move = Vector3.new()
        if input.W then move = move + Vector3.new(0, 0, -1) end
        if input.S then move = move + Vector3.new(0, 0, 1) end
        if input.A then move = move + Vector3.new(-1, 0, 0) end
        if input.D then move = move + Vector3.new(1, 0, 0) end
        if input.Space then move = move + Vector3.new(0, 1, 0) end
        if input.Ctrl then move = move + Vector3.new(0, -1, 0) end
        if move.Magnitude > 0 then
            move = move.Unit
        end

        local base = State.Movement.Freecam.CFrame
        local rot = CFrame.Angles(0, State.Movement.Freecam.Yaw, 0) * CFrame.Angles(State.Movement.Freecam.Pitch, 0, 0)
        local step = rot:VectorToWorldSpace(move) * (State.Movement.Freecam.Speed or 1.6) * (dt * 60)
        State.Movement.Freecam.CFrame = CFrame.new(base.Position + step) * rot
        cam.CFrame = State.Movement.Freecam.CFrame
    end)
    trackConnection(State.Movement.Freecam.Conn)
end

State.Movement.AirWalk = State.Movement.AirWalk or { Enabled = false, Part = nil, Conn = nil }
State.Movement.AirWalk.Start = State.Movement.AirWalk.Start or function()
    if State.Movement.AirWalk.Enabled then
        return
    end
    State.Movement.AirWalk.Enabled = true
    if not State.Movement.AirWalk.Part then
        local p = Instance.new("Part")
        p.Name = "GI_AirWalk"
        p.Anchored = true
        p.CanCollide = true
        p.Size = Vector3.new(6, 1, 6)
        p.Transparency = 1
        p.Parent = workspace
        State.Movement.AirWalk.Part = p
    end
    if not State.Movement.AirWalk.Conn then
        State.Movement.AirWalk.Conn = RunService.Heartbeat:Connect(function()
            if not State.Movement.AirWalk.Enabled then
                return
            end
            local hrp = State.Movement.GetRoot()
            if hrp and State.Movement.AirWalk.Part then
                State.Movement.AirWalk.Part.CFrame = hrp.CFrame * CFrame.new(0, -3.5, 0)
            end
        end)
        trackConnection(State.Movement.AirWalk.Conn)
    end
end

State.Movement.AirWalk.Stop = State.Movement.AirWalk.Stop or function()
    State.Movement.AirWalk.Enabled = false
    if State.Movement.AirWalk.Conn then
        State.Movement.AirWalk.Conn:Disconnect()
        State.Movement.AirWalk.Conn = nil
    end
    if State.Movement.AirWalk.Part then
        State.Movement.AirWalk.Part:Destroy()
        State.Movement.AirWalk.Part = nil
    end
end

State.Movement.WallHop = State.Movement.WallHop or { Enabled = false, Cooldown = 0, Power = 45, Push = 18 }
State.Movement.AirJump = State.Movement.AirJump or { Enabled = false, Cooldown = 0 }
State.Movement.AutoJump = State.Movement.AutoJump or { Enabled = false, Conn = nil }

State.Movement.AutoJump.Start = State.Movement.AutoJump.Start or function()
    if State.Movement.AutoJump.Enabled then
        return
    end
    State.Movement.AutoJump.Enabled = true
    State.Movement.AutoJump.Conn = RunService.Heartbeat:Connect(function()
        if not State.Movement.AutoJump.Enabled then
            return
        end
        local hum = State.Movement.GetHumanoid()
        if hum and hum.FloorMaterial ~= Enum.Material.Air then
            hum.Jump = true
        end
    end)
    trackConnection(State.Movement.AutoJump.Conn)
end

State.Movement.AutoJump.Stop = State.Movement.AutoJump.Stop or function()
    State.Movement.AutoJump.Enabled = false
    if State.Movement.AutoJump.Conn then
        State.Movement.AutoJump.Conn:Disconnect()
        State.Movement.AutoJump.Conn = nil
    end
end

State.Movement.Spinbot = State.Movement.Spinbot or { Enabled = false, Speed = Config.SpinSpeed or 180, Conn = nil, Angle = 0 }
State.Movement.Spinbot.SetSpeed = State.Movement.Spinbot.SetSpeed or function(value)
    local speed = tonumber(value) or 0
    if speed < 0 then
        speed = 0
    end
    State.Movement.Spinbot.Speed = speed
    Config.SpinSpeed = speed
    return speed
end

State.Movement.Spinbot.Start = State.Movement.Spinbot.Start or function()
    if State.Movement.Spinbot.Enabled then
        return
    end
    State.Movement.Spinbot.Enabled = true
    State.Movement.Spinbot.Angle = 0
    State.Movement.Spinbot.Conn = RunService.Heartbeat:Connect(function(dt)
        if not State.Movement.Spinbot.Enabled then
            return
        end
        local hrp = State.Movement.GetRoot()
        if hrp then
            State.Movement.Spinbot.Angle += math.rad(State.Movement.Spinbot.Speed or 180) * dt
            hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, State.Movement.Spinbot.Angle, 0)
        end
    end)
    trackConnection(State.Movement.Spinbot.Conn)
end

State.Movement.Spinbot.Stop = State.Movement.Spinbot.Stop or function()
    State.Movement.Spinbot.Enabled = false
    if State.Movement.Spinbot.Conn then
        State.Movement.Spinbot.Conn:Disconnect()
        State.Movement.Spinbot.Conn = nil
    end
end

State.Movement.Fling = State.Movement.Fling or { Enabled = false, Power = Config.FlingPower or 2500, Body = nil }
State.Movement.Fling.SetPower = State.Movement.Fling.SetPower or function(value)
    local power = tonumber(value) or 0
    if power < 0 then
        power = 0
    end
    State.Movement.Fling.Power = power
    Config.FlingPower = power
    if State.Movement.Fling.Body then
        State.Movement.Fling.Body.AngularVelocity = Vector3.new(0, power, 0)
    end
    return power
end

State.Movement.Fling.Start = State.Movement.Fling.Start or function()
    if State.Movement.Fling.Enabled then
        return
    end
    local hrp = State.Movement.GetRoot()
    if not hrp then
        return
    end
    State.Movement.Fling.Enabled = true
    local bav = Instance.new("BodyAngularVelocity")
    bav.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bav.P = 10000
    bav.AngularVelocity = Vector3.new(0, State.Movement.Fling.Power or 2500, 0)
    bav.Parent = hrp
    State.Movement.Fling.Body = bav
end

State.Movement.Fling.Stop = State.Movement.Fling.Stop or function()
    State.Movement.Fling.Enabled = false
    if State.Movement.Fling.Body then
        State.Movement.Fling.Body:Destroy()
        State.Movement.Fling.Body = nil
    end
end

State.Movement.JumpLock = State.Movement.JumpLock or {
    PowerEnabled = false,
    HeightEnabled = false,
    Power = Config.JumpPower or 50,
    Height = Config.JumpHeight or 7.2,
    Conn = nil,
    CharConn = nil
}

State.Movement.JumpLock.Apply = State.Movement.JumpLock.Apply or function()
    local hum = State.Movement.GetHumanoid()
    if not hum then
        return
    end
    if State.Movement.JumpLock.PowerEnabled then
        hum.UseJumpPower = true
        hum.JumpPower = State.Movement.JumpLock.Power
    elseif State.Movement.JumpLock.HeightEnabled then
        hum.UseJumpPower = false
        hum.JumpHeight = State.Movement.JumpLock.Height
    end
end

State.Movement.JumpLock.Start = State.Movement.JumpLock.Start or function()
    if State.Movement.JumpLock.Conn then
        return
    end
    State.Movement.JumpLock.Conn = RunService.Heartbeat:Connect(function()
        if State.Movement.JumpLock.PowerEnabled or State.Movement.JumpLock.HeightEnabled then
            State.Movement.JumpLock.Apply()
        end
    end)
    trackConnection(State.Movement.JumpLock.Conn)

    if not State.Movement.JumpLock.CharConn then
        State.Movement.JumpLock.CharConn = LP.CharacterAdded:Connect(function()
            State.Movement.JumpLock.Apply()
        end)
        trackConnection(State.Movement.JumpLock.CharConn)
    end
end

State.Movement.JumpLock.Stop = State.Movement.JumpLock.Stop or function()
    if State.Movement.JumpLock.Conn then
        State.Movement.JumpLock.Conn:Disconnect()
        State.Movement.JumpLock.Conn = nil
    end
    if State.Movement.JumpLock.CharConn then
        State.Movement.JumpLock.CharConn:Disconnect()
        State.Movement.JumpLock.CharConn = nil
    end
end

State.Movement.BindInputs = State.Movement.BindInputs or function()
    if State.Movement.Input.Bound then
        return
    end
    State.Movement.Input.Bound = true
    local keyMap = {
        [Enum.KeyCode.W] = "W",
        [Enum.KeyCode.A] = "A",
        [Enum.KeyCode.S] = "S",
        [Enum.KeyCode.D] = "D",
        [Enum.KeyCode.Space] = "Space",
        [Enum.KeyCode.LeftControl] = "Ctrl",
        [Enum.KeyCode.RightControl] = "Ctrl"
    }

    local function shouldIgnore(gameProcessed)
        if gameProcessed then
            return true
        end
        return UIS:GetFocusedTextBox() ~= nil
    end

    local inputConn = UIS.InputBegan:Connect(function(input, gameProcessed)
        if shouldIgnore(gameProcessed) then
            return
        end
        local key = keyMap[input.KeyCode]
        if key then
            State.Movement.Input.Keys[key] = true
            return
        end
        if input.KeyCode == Enum.KeyCode.N and State.Movement.UI and State.Movement.UI.NoClipToggle then
            local nextState = not (State.Movement.NoClip.Enabled == true)
            State.Movement.UI.NoClipToggle:Set(nextState)
            if nextState then
                State.Movement.NoClip.Start()
            else
                State.Movement.NoClip.Stop()
            end
        elseif input.KeyCode == Enum.KeyCode.V and State.Movement.UI and State.Movement.UI.FreecamToggle then
            local nextState = not (State.Movement.Freecam.Enabled == true)
            State.Movement.UI.FreecamToggle:Set(nextState)
            if nextState then
                State.Movement.Freecam.SetSpeed(Config.FreecamSpeed or 1.6)
                State.Movement.Freecam.Start()
            else
                State.Movement.Freecam.Stop()
            end
        end
    end)
    trackConnection(inputConn)

    local inputEnd = UIS.InputEnded:Connect(function(input)
        local key = keyMap[input.KeyCode]
        if key then
            State.Movement.Input.Keys[key] = false
        end
    end)
    trackConnection(inputEnd)
end

PlayerTab:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Flag = "InfiniteJump",
    Callback = function(Value)
        InfiniteJump = Value
    end
})

trackConnection(UIS.JumpRequest:Connect(function()
    local hum = State.Movement.GetHumanoid()
    local hrp = State.Movement.GetRoot()
    if InfiniteJump and hum then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    if State.Movement.AirJump.Enabled and hum and hum.FloorMaterial == Enum.Material.Air then
        local now = os.clock()
        if now - (State.Movement.AirJump.Cooldown or 0) > 0.15 then
            State.Movement.AirJump.Cooldown = now
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
    if State.Movement.WallHop.Enabled and hum and hrp and hum.FloorMaterial == Enum.Material.Air then
        local now = os.clock()
        if now - (State.Movement.WallHop.Cooldown or 0) > 0.2 then
            local dir = hum.MoveDirection
            if dir.Magnitude == 0 and workspace.CurrentCamera then
                dir = workspace.CurrentCamera.CFrame.LookVector
            end
            if dir.Magnitude > 0 then
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Blacklist
                params.FilterDescendantsInstances = {LP.Character}
                local hit = workspace:Raycast(hrp.Position, dir.Unit * 2.5, params)
                if hit then
                    State.Movement.WallHop.Cooldown = now
                    local vel = hrp.AssemblyLinearVelocity
                    local push = (hit.Normal * (State.Movement.WallHop.Push or 18))
                    hrp.AssemblyLinearVelocity = Vector3.new(vel.X, State.Movement.WallHop.Power or 45, vel.Z) + push
                end
            end
        end
    end
end))

State.WalkSpeedLock = State.WalkSpeedLock or {}
State.WalkSpeedLock.Enabled = State.WalkSpeedLock.Enabled or false
State.WalkSpeedLock.Target = State.WalkSpeedLock.Target or (Config.WalkSpeed or 16)
State.WalkSpeedLock.Interval = State.WalkSpeedLock.Interval or 0.1
State.WalkSpeedLock.Accum = State.WalkSpeedLock.Accum or 0
State.WalkSpeedLock.Conn = State.WalkSpeedLock.Conn or nil
State.WalkSpeedLock.PropConn = State.WalkSpeedLock.PropConn or nil
State.WalkSpeedLock.CharConn = State.WalkSpeedLock.CharConn or nil

State.WalkSpeedLock.GetHumanoid = State.WalkSpeedLock.GetHumanoid or function()
    if not (LP and LP.Character) then
        return nil
    end
    return LP.Character:FindFirstChildOfClass("Humanoid")
end

State.WalkSpeedLock.Apply = State.WalkSpeedLock.Apply or function()
    if not State.WalkSpeedLock.Enabled then
        return
    end
    local hum = State.WalkSpeedLock.GetHumanoid()
    if hum and hum.WalkSpeed ~= State.WalkSpeedLock.Target then
        hum.WalkSpeed = State.WalkSpeedLock.Target
    end
end

State.WalkSpeedLock.BindHumanoid = State.WalkSpeedLock.BindHumanoid or function(hum)
    if State.WalkSpeedLock.PropConn then
        State.WalkSpeedLock.PropConn:Disconnect()
        State.WalkSpeedLock.PropConn = nil
    end
    if hum then
        State.WalkSpeedLock.PropConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if State.WalkSpeedLock.Enabled and hum.WalkSpeed ~= State.WalkSpeedLock.Target then
                hum.WalkSpeed = State.WalkSpeedLock.Target
            end
        end)
        trackConnection(State.WalkSpeedLock.PropConn)
    end
end

State.WalkSpeedLock.SetTarget = State.WalkSpeedLock.SetTarget or function(value)
    local speed = math.floor((tonumber(value) or 0) + 0.5)
    if speed < 0 then
        speed = 0
    end
    State.WalkSpeedLock.Target = speed
    Config.WalkSpeed = speed
    if State.WalkSpeedLock.Enabled then
        State.WalkSpeedLock.Apply()
    end
    return speed
end

State.WalkSpeedLock.Start = State.WalkSpeedLock.Start or function()
    State.WalkSpeedLock.Enabled = true
    State.WalkSpeedLock.Accum = 0
    State.WalkSpeedLock.SetTarget(State.WalkSpeedLock.Target or (Config.WalkSpeed or 16))
    State.WalkSpeedLock.Apply()
    State.WalkSpeedLock.BindHumanoid(State.WalkSpeedLock.GetHumanoid())

    if not State.WalkSpeedLock.CharConn then
        State.WalkSpeedLock.CharConn = LP.CharacterAdded:Connect(function()
            if not State.WalkSpeedLock.Enabled then
                return
            end
            State.WalkSpeedLock.BindHumanoid(State.WalkSpeedLock.GetHumanoid())
            State.WalkSpeedLock.Apply()
        end)
        trackConnection(State.WalkSpeedLock.CharConn)
    end

    if not State.WalkSpeedLock.Conn then
        State.WalkSpeedLock.Conn = RunService.Heartbeat:Connect(function(dt)
            if not State.WalkSpeedLock.Enabled then
                return
            end
            State.WalkSpeedLock.Accum += dt
            if State.WalkSpeedLock.Accum >= State.WalkSpeedLock.Interval then
                State.WalkSpeedLock.Accum = 0
                State.WalkSpeedLock.Apply()
            end
        end)
        trackConnection(State.WalkSpeedLock.Conn)
    end
end

State.WalkSpeedLock.Stop = State.WalkSpeedLock.Stop or function()
    State.WalkSpeedLock.Enabled = false
    if State.WalkSpeedLock.Conn then
        State.WalkSpeedLock.Conn:Disconnect()
        State.WalkSpeedLock.Conn = nil
    end
    if State.WalkSpeedLock.CharConn then
        State.WalkSpeedLock.CharConn:Disconnect()
        State.WalkSpeedLock.CharConn = nil
    end
    if State.WalkSpeedLock.PropConn then
        State.WalkSpeedLock.PropConn:Disconnect()
        State.WalkSpeedLock.PropConn = nil
    end
end

local WalkSpeedSlider
PlayerTab:CreateToggle({
    Name = "Enable WalkSpeed",
    CurrentValue = false,
    Flag = "WalkSpeedEnabled",
    Callback = function(Value)
        if WalkSpeedSlider and WalkSpeedSlider.SetEnabled then
            WalkSpeedSlider:SetEnabled(Value)
        end
        if Value then
            State.WalkSpeedLock.SetTarget(Config.WalkSpeed or 16)
            State.WalkSpeedLock.Start()
        else
            State.WalkSpeedLock.SetTarget(16)
            local hum = State.WalkSpeedLock.GetHumanoid()
            if hum then
                hum.WalkSpeed = 16
            end
            State.WalkSpeedLock.Stop()
        end
    end
})

WalkSpeedSlider = PlayerTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {0, 300},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Decimals = 0,
    Callback = function(Value)
        if not Config.WalkSpeedEnabled then
            return
        end
        local speed = State.WalkSpeedLock.SetTarget(Value)
        if WalkSpeedSlider and WalkSpeedSlider.SetValue and speed ~= Value then
            WalkSpeedSlider:SetValue(speed, true)
        end
    end
})

if WalkSpeedSlider and WalkSpeedSlider.SetEnabled then
    WalkSpeedSlider:SetEnabled(Config.WalkSpeedEnabled == true)
end

if Config.WalkSpeedEnabled then
    State.WalkSpeedLock.SetTarget(Config.WalkSpeed or 16)
    State.WalkSpeedLock.Start()
end

PlayerTab:CreateSection("Advanced Movement")
State.Movement.UI = State.Movement.UI or {}

State.Movement.UI.FlyToggle = PlayerTab:CreateToggle({
    Name = "Fly",
    CurrentValue = false,
    Flag = "FlyEnabled",
    Callback = function(Value)
        if Value then
            State.Movement.Fly.SetSpeed(Config.FlySpeed or 60)
            State.Movement.Fly.SetInertia(Config.FlyInertia or 0.15)
            State.Movement.Fly.Start()
        else
            State.Movement.Fly.Stop()
        end
    end
})

State.Movement.UI.FlySpeed = PlayerTab:CreateSlider({
    Name = "Fly Speed",
    Range = {1, 300},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 60,
    Flag = "FlySpeed",
    Decimals = 0,
    Callback = function(Value)
        State.Movement.Fly.SetSpeed(Value)
    end
})

State.Movement.UI.FlyInertia = PlayerTab:CreateSlider({
    Name = "Fly Inertia",
    Range = {0, 1},
    Increment = 0.05,
    Suffix = "",
    CurrentValue = 0.15,
    Flag = "FlyInertia",
    Decimals = 2,
    Callback = function(Value)
        State.Movement.Fly.SetInertia(Value)
    end
})

State.Movement.UI.NoClipToggle = PlayerTab:CreateToggle({
    Name = "No Clip (N)",
    CurrentValue = false,
    Flag = "NoClip",
    Callback = function(Value)
        if Value then
            State.Movement.NoClip.Start()
        else
            State.Movement.NoClip.Stop()
        end
    end
})

State.Movement.UI.FreecamToggle = PlayerTab:CreateToggle({
    Name = "Freecam (V)",
    CurrentValue = false,
    Flag = "Freecam",
    Callback = function(Value)
        if Value then
            State.Movement.Freecam.SetSpeed(Config.FreecamSpeed or 1.6)
            State.Movement.Freecam.Start()
        else
            State.Movement.Freecam.Stop()
        end
    end
})

State.Movement.UI.FreecamSpeed = PlayerTab:CreateSlider({
    Name = "Freecam Speed",
    Range = {0.2, 10},
    Increment = 0.1,
    Suffix = "x",
    CurrentValue = 1.6,
    Flag = "FreecamSpeed",
    Decimals = 1,
    Callback = function(Value)
        State.Movement.Freecam.SetSpeed(Value)
    end
})

State.Movement.UI.AirWalkToggle = PlayerTab:CreateToggle({
    Name = "Air Walk",
    CurrentValue = false,
    Flag = "AirWalk",
    Callback = function(Value)
        if Value then
            State.Movement.AirWalk.Start()
        else
            State.Movement.AirWalk.Stop()
        end
    end
})

State.Movement.UI.WallHopToggle = PlayerTab:CreateToggle({
    Name = "Wall Hop",
    CurrentValue = false,
    Flag = "WallHop",
    Callback = function(Value)
        State.Movement.WallHop.Enabled = Value == true
    end
})

State.Movement.UI.AutoJumpToggle = PlayerTab:CreateToggle({
    Name = "Auto Jump",
    CurrentValue = false,
    Flag = "AutoJump",
    Callback = function(Value)
        if Value then
            State.Movement.AutoJump.Start()
        else
            State.Movement.AutoJump.Stop()
        end
    end
})

State.Movement.UI.AirJumpToggle = PlayerTab:CreateToggle({
    Name = "Air Jump",
    CurrentValue = false,
    Flag = "AirJump",
    Callback = function(Value)
        State.Movement.AirJump.Enabled = Value == true
    end
})

State.Movement.UI.SpinbotToggle = PlayerTab:CreateToggle({
    Name = "Spinbot",
    CurrentValue = false,
    Flag = "Spinbot",
    Callback = function(Value)
        if Value then
            State.Movement.Spinbot.Start()
        else
            State.Movement.Spinbot.Stop()
        end
    end
})

State.Movement.UI.SpinSpeed = PlayerTab:CreateSlider({
    Name = "Spin Speed",
    Range = {0, 720},
    Increment = 5,
    Suffix = "deg/s",
    CurrentValue = 180,
    Flag = "SpinSpeed",
    Decimals = 0,
    Callback = function(Value)
        State.Movement.Spinbot.SetSpeed(Value)
    end
})

State.Movement.UI.FlingToggle = PlayerTab:CreateToggle({
    Name = "Fling",
    CurrentValue = false,
    Flag = "Fling",
    Callback = function(Value)
        if Value then
            State.Movement.Fling.SetPower(Config.FlingPower or 2500)
            State.Movement.Fling.Start()
        else
            State.Movement.Fling.Stop()
        end
    end
})

State.Movement.UI.FlingPower = PlayerTab:CreateSlider({
    Name = "Fling Power",
    Range = {0, 8000},
    Increment = 50,
    Suffix = "",
    CurrentValue = 2500,
    Flag = "FlingPower",
    Decimals = 0,
    Callback = function(Value)
        State.Movement.Fling.SetPower(Value)
    end
})

State.Movement.UI.JumpPowerToggle = PlayerTab:CreateToggle({
    Name = "Jump Power",
    CurrentValue = false,
    Flag = "JumpPowerEnabled",
    Callback = function(Value)
        State.Movement.JumpLock.PowerEnabled = Value == true
        if Value then
            State.Movement.JumpLock.HeightEnabled = false
            if State.Movement.UI and State.Movement.UI.JumpHeightToggle then
                State.Movement.UI.JumpHeightToggle:Set(false)
            end
        end
        State.Movement.JumpLock.Start()
        State.Movement.JumpLock.Apply()
    end
})

State.Movement.UI.JumpPower = PlayerTab:CreateSlider({
    Name = "Jump Power Value",
    Range = {0, 300},
    Increment = 1,
    Suffix = "",
    CurrentValue = 50,
    Flag = "JumpPower",
    Decimals = 0,
    Callback = function(Value)
        local v = math.floor((tonumber(Value) or 0) + 0.5)
        State.Movement.JumpLock.Power = v
        Config.JumpPower = v
        State.Movement.JumpLock.Apply()
    end
})

State.Movement.UI.JumpHeightToggle = PlayerTab:CreateToggle({
    Name = "Jump Height",
    CurrentValue = false,
    Flag = "JumpHeightEnabled",
    Callback = function(Value)
        State.Movement.JumpLock.HeightEnabled = Value == true
        if Value then
            State.Movement.JumpLock.PowerEnabled = false
            if State.Movement.UI and State.Movement.UI.JumpPowerToggle then
                State.Movement.UI.JumpPowerToggle:Set(false)
            end
        end
        State.Movement.JumpLock.Start()
        State.Movement.JumpLock.Apply()
    end
})

State.Movement.UI.JumpHeight = PlayerTab:CreateSlider({
    Name = "Jump Height Value",
    Range = {0, 50},
    Increment = 0.5,
    Suffix = "",
    CurrentValue = 7.2,
    Flag = "JumpHeight",
    Decimals = 1,
    Callback = function(Value)
        local v = tonumber(Value) or 0
        State.Movement.JumpLock.Height = v
        Config.JumpHeight = v
        State.Movement.JumpLock.Apply()
    end
})

State.Movement.BindInputs()

PlayerTab:CreateSection("Player Info")
State.Movement.PlayerInfo = State.Movement.PlayerInfo or { Paragraph = nil, Conn = nil }
State.Movement.PlayerInfo.Refresh = State.Movement.PlayerInfo.Refresh or function()
    if State.Movement.PlayerInfo.Paragraph then
        State.Movement.PlayerInfo.Paragraph:Destroy()
        State.Movement.PlayerInfo.Paragraph = nil
    end
    local hum = State.Movement.GetHumanoid()
    local hrp = State.Movement.GetRoot()
    local parts = {}
    if hum then
        parts[#parts + 1] = "Health: " .. math.floor(hum.Health + 0.5) .. " / " .. math.floor(hum.MaxHealth + 0.5)
        parts[#parts + 1] = "WalkSpeed: " .. tostring(hum.WalkSpeed)
        parts[#parts + 1] = "JumpPower: " .. tostring(hum.JumpPower)
        parts[#parts + 1] = "JumpHeight: " .. tostring(hum.JumpHeight)
        parts[#parts + 1] = "Floor: " .. tostring(hum.FloorMaterial)
        parts[#parts + 1] = "Rig: " .. tostring(hum.RigType)
    end
    if hrp then
        local pos = hrp.Position
        parts[#parts + 1] = ("Pos: %.1f, %.1f, %.1f"):format(pos.X, pos.Y, pos.Z)
        local vel = hrp.AssemblyLinearVelocity
        parts[#parts + 1] = ("Velocity: %.1f, %.1f, %.1f"):format(vel.X, vel.Y, vel.Z)
    end
    State.Movement.PlayerInfo.Paragraph = PlayerTab:CreateParagraph({
        Title = "Player Details",
        Content = (#parts > 0) and table.concat(parts, "\n") or "Data pemain tidak tersedia."
    })
end

State.Movement.PlayerInfo.Refresh()
if not State.Movement.PlayerInfo.Conn then
    State.Movement.PlayerInfo.Conn = RunService.Heartbeat:Connect(function(dt)
        State.Movement.PlayerInfo.Accum = (State.Movement.PlayerInfo.Accum or 0) + dt
        if State.Movement.PlayerInfo.Accum >= 1 then
            State.Movement.PlayerInfo.Accum = 0
            State.Movement.PlayerInfo.Refresh()
        end
    end)
    trackConnection(State.Movement.PlayerInfo.Conn)
end

if State.CleanupRegistry and State.CleanupRegistry.Register then
    State.CleanupRegistry.Register(function()
        if State.Movement then
            if State.Movement.Fly and State.Movement.Fly.Stop then
                State.Movement.Fly.Stop()
            end
            if State.Movement.NoClip and State.Movement.NoClip.Stop then
                State.Movement.NoClip.Stop()
            end
            if State.Movement.Freecam and State.Movement.Freecam.Stop then
                State.Movement.Freecam.Stop()
            end
            if State.Movement.AirWalk and State.Movement.AirWalk.Stop then
                State.Movement.AirWalk.Stop()
            end
            if State.Movement.AutoJump and State.Movement.AutoJump.Stop then
                State.Movement.AutoJump.Stop()
            end
            if State.Movement.Spinbot and State.Movement.Spinbot.Stop then
                State.Movement.Spinbot.Stop()
            end
            if State.Movement.Fling and State.Movement.Fling.Stop then
                State.Movement.Fling.Stop()
            end
            if State.Movement.JumpLock and State.Movement.JumpLock.Stop then
                State.Movement.JumpLock.Stop()
            end
        end
        if State.VisualBoost and State.VisualBoost.Stop then
            State.VisualBoost.Stop()
        end
        if State.VisualXRay and State.VisualXRay.Stop then
            State.VisualXRay.Stop()
        end
    end)
end

-- =====================================================
-- VISUAL TAB
-- =====================================================
LoadingUI:Set(55, "Menambahkan modul visual...")
local VisualTab = createTab("Visual")
VisualTab:CreateSection("Display Optimization")

local DefaultLighting = {
    FogStart = Lighting.FogStart,
    FogEnd = Lighting.FogEnd,
    Brightness = Lighting.Brightness,
    GlobalShadows = Lighting.GlobalShadows,
    ClockTime = Lighting.ClockTime,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
    EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
}

local function TogglePostFX(state)
    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("ColorCorrectionEffect") then
            v.Enabled = state
        end
    end
end

State.VisualLock = State.VisualLock or {}
State.VisualLock.Active = State.VisualLock.Active or {
    NoFog = false,
    NoFX = false,
    LowGraphics = false,
    FullBright = false
}
State.VisualLock.Conns = State.VisualLock.Conns or {}
State.VisualLock.Connected = State.VisualLock.Connected == true

State.VisualLock.Apply = State.VisualLock.Apply or function()
    if State.VisualLock.Active.NoFog then
        Lighting.FogStart = 1e5
        Lighting.FogEnd = 1e5
    end
    if State.VisualLock.Active.NoFX then
        TogglePostFX(false)
    end
    if State.VisualLock.Active.LowGraphics then
        pcall(function()
            Lighting.GlobalShadows = false
            if settings and settings().Rendering then
                settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            end
        end)
    end
    if State.VisualLock.Active.FullBright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 12
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.EnvironmentDiffuseScale = 1
        Lighting.EnvironmentSpecularScale = 0
    end
end

State.VisualBoost = State.VisualBoost or { Enabled = false, Conn = nil }
State.VisualBoost.ApplyToInstance = State.VisualBoost.ApplyToInstance or function(inst)
    if inst:IsA("BasePart") then
        if inst:GetAttribute("GI_FPSBoost_TopSurface") == nil then
            inst:SetAttribute("GI_FPSBoost_TopSurface", inst.TopSurface.Name)
            inst:SetAttribute("GI_FPSBoost_BottomSurface", inst.BottomSurface.Name)
            inst:SetAttribute("GI_FPSBoost_LeftSurface", inst.LeftSurface.Name)
            inst:SetAttribute("GI_FPSBoost_RightSurface", inst.RightSurface.Name)
            inst:SetAttribute("GI_FPSBoost_FrontSurface", inst.FrontSurface.Name)
            inst:SetAttribute("GI_FPSBoost_BackSurface", inst.BackSurface.Name)
        end
        inst.TopSurface = Enum.SurfaceType.Smooth
        inst.BottomSurface = Enum.SurfaceType.Smooth
        inst.LeftSurface = Enum.SurfaceType.Smooth
        inst.RightSurface = Enum.SurfaceType.Smooth
        inst.FrontSurface = Enum.SurfaceType.Smooth
        inst.BackSurface = Enum.SurfaceType.Smooth
    end
    if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
        if inst:GetAttribute("GI_FPSBoost_OrigEnabled") == nil then
            inst:SetAttribute("GI_FPSBoost_OrigEnabled", inst.Enabled == true)
        end
        inst.Enabled = false
        return
    end
    if inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
        if inst:GetAttribute("GI_FPSBoost_OrigEnabled") == nil then
            inst:SetAttribute("GI_FPSBoost_OrigEnabled", inst.Enabled == true)
        end
        inst.Enabled = false
        return
    end
    if inst:IsA("Decal") or inst:IsA("Texture") then
        if inst:GetAttribute("GI_FPSBoost_OrigTransparency") == nil then
            inst:SetAttribute("GI_FPSBoost_OrigTransparency", inst.Transparency)
        end
        inst.Transparency = 1
    end
end

State.VisualBoost.RestoreInstance = State.VisualBoost.RestoreInstance or function(inst)
    if inst:IsA("BasePart") then
        local top = inst:GetAttribute("GI_FPSBoost_TopSurface")
        if top ~= nil then
            local function restoreSurface(attrName, setter)
                local val = inst:GetAttribute(attrName)
                if not val then
                    return
                end
                local ok, surface = pcall(function()
                    return Enum.SurfaceType[val]
                end)
                if ok and surface then
                    setter(surface)
                end
            end

            restoreSurface("GI_FPSBoost_TopSurface", function(s) inst.TopSurface = s end)
            restoreSurface("GI_FPSBoost_BottomSurface", function(s) inst.BottomSurface = s end)
            restoreSurface("GI_FPSBoost_LeftSurface", function(s) inst.LeftSurface = s end)
            restoreSurface("GI_FPSBoost_RightSurface", function(s) inst.RightSurface = s end)
            restoreSurface("GI_FPSBoost_FrontSurface", function(s) inst.FrontSurface = s end)
            restoreSurface("GI_FPSBoost_BackSurface", function(s) inst.BackSurface = s end)

            inst:SetAttribute("GI_FPSBoost_TopSurface", nil)
            inst:SetAttribute("GI_FPSBoost_BottomSurface", nil)
            inst:SetAttribute("GI_FPSBoost_LeftSurface", nil)
            inst:SetAttribute("GI_FPSBoost_RightSurface", nil)
            inst:SetAttribute("GI_FPSBoost_FrontSurface", nil)
            inst:SetAttribute("GI_FPSBoost_BackSurface", nil)
        end
    end
    if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
        local orig = inst:GetAttribute("GI_FPSBoost_OrigEnabled")
        if orig ~= nil then
            inst.Enabled = orig and true or false
            inst:SetAttribute("GI_FPSBoost_OrigEnabled", nil)
        end
        return
    end
    if inst:IsA("Decal") or inst:IsA("Texture") then
        local origT = inst:GetAttribute("GI_FPSBoost_OrigTransparency")
        if origT ~= nil then
            inst.Transparency = origT
            inst:SetAttribute("GI_FPSBoost_OrigTransparency", nil)
        end
    end
end

State.VisualBoost.Apply = State.VisualBoost.Apply or function()
    pcall(function()
        Lighting.GlobalShadows = false
        if settings and settings().Rendering then
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end
    end)
    for _, inst in ipairs(workspace:GetDescendants()) do
        State.VisualBoost.ApplyToInstance(inst)
    end
    for _, inst in ipairs(Lighting:GetDescendants()) do
        State.VisualBoost.ApplyToInstance(inst)
    end
end

State.VisualBoost.Restore = State.VisualBoost.Restore or function()
    pcall(function()
        Lighting.GlobalShadows = DefaultLighting.GlobalShadows
        if settings and settings().Rendering then
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        end
    end)
    for _, inst in ipairs(workspace:GetDescendants()) do
        State.VisualBoost.RestoreInstance(inst)
    end
    for _, inst in ipairs(Lighting:GetDescendants()) do
        State.VisualBoost.RestoreInstance(inst)
    end
end

State.VisualBoost.Start = State.VisualBoost.Start or function()
    if State.VisualBoost.Enabled then
        return
    end
    State.VisualBoost.Enabled = true
    State.VisualBoost.Apply()
    if not State.VisualBoost.Conn then
        State.VisualBoost.Conn = game.DescendantAdded:Connect(function(inst)
            if State.VisualBoost.Enabled then
                State.VisualBoost.ApplyToInstance(inst)
            end
        end)
        trackConnection(State.VisualBoost.Conn)
    end
end

State.VisualBoost.Stop = State.VisualBoost.Stop or function()
    State.VisualBoost.Enabled = false
    if State.VisualBoost.Conn then
        State.VisualBoost.Conn:Disconnect()
        State.VisualBoost.Conn = nil
    end
    State.VisualBoost.Restore()
end

State.VisualXRay = State.VisualXRay or { Enabled = false, Conn = nil }
State.VisualXRay.ApplyToInstance = State.VisualXRay.ApplyToInstance or function(inst)
    if not inst:IsA("BasePart") then
        return
    end
    if LP and LP.Character and inst:IsDescendantOf(LP.Character) then
        return
    end
    if inst:GetAttribute("GI_XRay_OrigLTM") == nil then
        inst:SetAttribute("GI_XRay_OrigLTM", inst.LocalTransparencyModifier)
    end
    inst.LocalTransparencyModifier = 0.6
    if inst:GetAttribute("GI_XRay_OrigShadow") == nil then
        inst:SetAttribute("GI_XRay_OrigShadow", inst.CastShadow == true)
    end
    inst.CastShadow = false
end

State.VisualXRay.RestoreInstance = State.VisualXRay.RestoreInstance or function(inst)
    if not inst:IsA("BasePart") then
        return
    end
    local orig = inst:GetAttribute("GI_XRay_OrigLTM")
    if orig ~= nil then
        inst.LocalTransparencyModifier = orig
        inst:SetAttribute("GI_XRay_OrigLTM", nil)
    end
    local origShadow = inst:GetAttribute("GI_XRay_OrigShadow")
    if origShadow ~= nil then
        inst.CastShadow = origShadow and true or false
        inst:SetAttribute("GI_XRay_OrigShadow", nil)
    end
end

State.VisualXRay.Start = State.VisualXRay.Start or function()
    if State.VisualXRay.Enabled then
        return
    end
    State.VisualXRay.Enabled = true
    for _, inst in ipairs(workspace:GetDescendants()) do
        State.VisualXRay.ApplyToInstance(inst)
    end
    if not State.VisualXRay.Conn then
        State.VisualXRay.Conn = workspace.DescendantAdded:Connect(function(inst)
            if State.VisualXRay.Enabled then
                State.VisualXRay.ApplyToInstance(inst)
            end
        end)
        trackConnection(State.VisualXRay.Conn)
    end
end

State.VisualXRay.Stop = State.VisualXRay.Stop or function()
    State.VisualXRay.Enabled = false
    if State.VisualXRay.Conn then
        State.VisualXRay.Conn:Disconnect()
        State.VisualXRay.Conn = nil
    end
    for _, inst in ipairs(workspace:GetDescendants()) do
        State.VisualXRay.RestoreInstance(inst)
    end
end

State.VisualLock.UpdateConnections = State.VisualLock.UpdateConnections or function()
    local any = false
    for _, v in pairs(State.VisualLock.Active) do
        if v then
            any = true
            break
        end
    end

    if any and not State.VisualLock.Connected then
        State.VisualLock.Connected = true
        local c1 = Lighting.Changed:Connect(function()
            State.VisualLock.Apply()
        end)
        State.VisualLock.Conns[#State.VisualLock.Conns + 1] = c1
        trackConnection(c1)

        local c2 = Lighting.ChildAdded:Connect(function(child)
            if State.VisualLock.Active.NoFX then
                if child:IsA("BloomEffect") or child:IsA("BlurEffect") or child:IsA("SunRaysEffect") or child:IsA("ColorCorrectionEffect") then
                    child.Enabled = false
                end
            end
        end)
        State.VisualLock.Conns[#State.VisualLock.Conns + 1] = c2
        trackConnection(c2)
    elseif not any and State.VisualLock.Connected then
        State.VisualLock.Connected = false
        for _, conn in ipairs(State.VisualLock.Conns) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        State.VisualLock.Conns = {}
    end
end

VisualTab:CreateToggle({
    Name = "FPS Boost",
    CurrentValue = false,
    Flag = "FPSBoost",
    Callback = function(Value)
        if Value then
            State.VisualBoost.Start()
        else
            State.VisualBoost.Stop()
        end
    end
})

VisualTab:CreateToggle({
    Name = "No Fog",
    CurrentValue = false,
    Flag = "NoFog",
    Callback = function(Value)
        State.VisualLock.Active.NoFog = Value == true
        if Value then
            Lighting.FogStart = 1e5
            Lighting.FogEnd = 1e5
        else
            Lighting.FogStart = DefaultLighting.FogStart
            Lighting.FogEnd = DefaultLighting.FogEnd
        end
        State.VisualLock.UpdateConnections()
        State.VisualLock.Apply()
    end
})

VisualTab:CreateToggle({
    Name = "Disable Effects",
    CurrentValue = false,
    Flag = "NoFX",
    Callback = function(Value)
        State.VisualLock.Active.NoFX = Value == true
        TogglePostFX(not Value)
        State.VisualLock.UpdateConnections()
        State.VisualLock.Apply()
    end
})

VisualTab:CreateToggle({
    Name = "Low Graphics Mode",
    CurrentValue = false,
    Flag = "LowGraphics",
    Callback = function(Value)
        State.VisualLock.Active.LowGraphics = Value == true
        pcall(function()
            if Value then
                Lighting.GlobalShadows = false
                if settings and settings().Rendering then
                    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
                end
            else
                Lighting.GlobalShadows = DefaultLighting.GlobalShadows
                if settings and settings().Rendering then
                    settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
                end
            end
        end)
        State.VisualLock.UpdateConnections()
        State.VisualLock.Apply()
    end
})

VisualTab:CreateToggle({
    Name = "Full Bright",
    CurrentValue = false,
    Flag = "FullBright",
    Callback = function(Value)
        State.VisualLock.Active.FullBright = Value == true
        if Value then
            Lighting.Brightness = 2
            Lighting.ClockTime = 12
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.new(1, 1, 1)
            Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
            Lighting.EnvironmentDiffuseScale = 1
            Lighting.EnvironmentSpecularScale = 0
        else
            Lighting.Brightness = DefaultLighting.Brightness
            Lighting.ClockTime = DefaultLighting.ClockTime
            Lighting.GlobalShadows = DefaultLighting.GlobalShadows
            Lighting.Ambient = DefaultLighting.Ambient
            Lighting.OutdoorAmbient = DefaultLighting.OutdoorAmbient
            Lighting.EnvironmentDiffuseScale = DefaultLighting.EnvironmentDiffuseScale
            Lighting.EnvironmentSpecularScale = DefaultLighting.EnvironmentSpecularScale
        end
        State.VisualLock.UpdateConnections()
        State.VisualLock.Apply()
    end
})

VisualTab:CreateToggle({
    Name = "X-Ray",
    CurrentValue = false,
    Flag = "XRay",
    Callback = function(Value)
        if Value then
            State.VisualXRay.Start()
        else
            State.VisualXRay.Stop()
        end
    end
})

-- =====================================================
-- [HEAD] TELEPORT HELPERS
-- =====================================================
-- [FUNC] Parse camera type from enum/string
local function parseCameraType(value)
    if typeof(value) == "EnumItem" then
        return value
    end
    if type(value) == "string" then
        local name = value:gsub("Enum%.CameraType%.", "")
        local ok, item = pcall(function()
            return Enum.CameraType[name]
        end)
        if ok and item then
            return item
        end
    end
    return Enum.CameraType.Custom
end

local function teleportToPositionOnly(position)
    if not position then
        return false
    end
    if LP and LP.Character then
        local ok = pcall(function()
            LP.Character:PivotTo(CFrame.new(position))
        end)
        return ok == true
    end
    return false
end

-- [FUNC] Teleport with camera snapshot (short lock, then restore zoom range)
teleportWithData = function(data)
    if not data or not data.position then return end
    if LP.Character then
        LP.Character:PivotTo(CFrame.new(data.position))
    end
    local cam = workspace.CurrentCamera
    if cam and data.camera then
        local targetType = parseCameraType(data.camera.type)
        local targetSubject = cam.CameraSubject
        local targetFOV = data.camera.fov or 70.000
        local targetCFrame = data.camera.cframe or cam.CFrame
        local targetFocus = data.camera.focus or cam.Focus
        local targetZoom = data.camera.zoom or (targetCFrame.Position - targetFocus.Position).Magnitude
        local targetMinZoom = data.camera.min_zoom
        local targetMaxZoom = data.camera.max_zoom
        local oldMinZoom = LP.CameraMinZoomDistance
        local oldMaxZoom = LP.CameraMaxZoomDistance
        local oldCamMode = LP.CameraMode
        local restoreMinZoom = (type(targetMinZoom) == "number" and targetMinZoom) or 0.500
        local restoreMaxZoom = (type(targetMaxZoom) == "number" and targetMaxZoom) or 40.000

        cam.CameraType = Enum.CameraType.Scriptable
        cam.FieldOfView = targetFOV
        cam.CFrame = targetCFrame
        cam.Focus = targetFocus
        pcall(function()
            LP.CameraMinZoomDistance = targetZoom
            LP.CameraMaxZoomDistance = targetZoom
            LP.CameraMode = Enum.CameraMode.Classic
        end)

        local lockSeconds = 0.25
        local startTime = os.clock()
        local rsConn
        local restored = false
        local function restoreCamera()
            if restored then
                return
            end
            restored = true
            if cam then
                cam.CameraSubject = targetSubject
                cam.CameraType = targetType
            end
            task.delay(0.05, function()
                pcall(function()
                    LP.CameraMinZoomDistance = restoreMinZoom
                    LP.CameraMaxZoomDistance = restoreMaxZoom
                    LP.CameraMode = oldCamMode
                end)
            end)
        end
        rsConn = RunService.RenderStepped:Connect(function()
            if not cam then
                if rsConn then
                    rsConn:Disconnect()
                end
                restoreCamera()
                return
            end
            cam.FieldOfView = targetFOV
            cam.CFrame = targetCFrame
            cam.Focus = targetFocus
            pcall(function()
                LP.CameraMinZoomDistance = targetZoom
                LP.CameraMaxZoomDistance = targetZoom
            end)
            if (os.clock() - startTime) >= lockSeconds then
                if rsConn then
                    rsConn:Disconnect()
                end
                restoreCamera()
            end
        end)
        trackConnection(rsConn)
        task.delay(lockSeconds + 0.3, restoreCamera)
    end
end

-- =====================================================
-- [HEAD] DEV / SPY TAB
-- =====================================================
LoadingUI:Set(65, "Menambahkan modul dev...")
local DevTab = createTab("Spy / Dev")

State.DevSections = State.DevSections or {}
State.DevSections.Teleport = createSectionBox(DevTab:GetPage(), "Teleport Tools")
State.DevSections.Notify = createSectionBox(DevTab:GetPage(), "Notify Tools")
State.DevSections.CopyData = createSectionBox(DevTab:GetPage(), "Copy Data Logger")
State.DevSections.Action = createSectionBox(DevTab:GetPage(), "Action Logger")
State.DevSections.ConsoleLog = createSectionBox(DevTab:GetPage(), "Developer Console Log")

do
    local DevLogEnabled = false
    local DevLogConnection = nil
    local DevLogs = {}

    local DevLogUI = State.UI.BuildScrollList(State.DevSections.ConsoleLog, {
        Title = "Logs (Developer Console)",
        Height = 200,
        TitleClass = "Subheading"
    })
    local DevLogContainer = DevLogUI.Container
    local DevLogTitle = DevLogUI.Title
    local DevLogScroll = DevLogUI.Scroll
    local DevLogList = DevLogUI.List
    local DevLogPad = DevLogUI.Padding

    local function clearDevLogs()
        for i = #DevLogs, 1, -1 do
            if DevLogs[i].Frame then
                DevLogs[i].Frame:Destroy()
            end
            table.remove(DevLogs, i)
        end
    end

    local function addDevLogEntry(msg, msgType)
        local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
            RowH = 30,
            InputPad = 6,
            InputPadSm = 4,
            RadiusSm = 6
        }
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 0)
        frame.AutomaticSize = Enum.AutomaticSize.Y
        frame.BorderSizePixel = 0
        frame.Parent = DevLogScroll
        registerTheme(frame, "BackgroundColor3", "Main")

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, tokens.InputPadSm)
        pad.PaddingBottom = UDim.new(0, tokens.InputPadSm)
        pad.PaddingLeft = UDim.new(0, tokens.RowPadX or 8)
        pad.PaddingRight = UDim.new(0, tokens.RowPadX or 8)
        pad.Parent = frame

        local header = Instance.new("Frame")
        header.Size = UDim2.new(1, 0, 0, math.max(18, (tokens.RowH or 30) - (tokens.InputPadSm or 4)))
        header.BackgroundTransparency = 1
        header.Parent = frame

        local title = Instance.new("TextLabel")
        local copyWidth = math.max(48, (tokens.ButtonW or 24) * 2)
        title.Size = UDim2.new(1, -(copyWidth + (tokens.InputPadSm or 4)), 1, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamSemibold
        title.TextSize = 12
        title.TextXAlignment = Enum.TextXAlignment.Left
        local typeName = msgType and tostring(msgType) or "Message"
        title.Text = typeName
        title.Parent = header
        setFontClass(title, "Small")
        registerTheme(title, "TextColor3", "Text")

        local copyBtn = Instance.new("TextButton")
        copyBtn.Size = UDim2.new(0, copyWidth, 1, 0)
        copyBtn.Position = UDim2.new(1, -(copyWidth + (tokens.InputPadSm or 0)), 0, 0)
        copyBtn.BorderSizePixel = 0
        copyBtn.Font = Enum.Font.Gotham
        copyBtn.TextSize = 11
        copyBtn.Text = "Copy"
        copyBtn.AutoButtonColor = false
        copyBtn.Parent = header
        addCorner(copyBtn, tokens.RadiusSm or 6)
        setFontClass(copyBtn, "Small")
        registerTheme(copyBtn, "BackgroundColor3", "Panel")
        registerTheme(copyBtn, "TextColor3", "Text")

        local body = Instance.new("TextLabel")
        body.Size = UDim2.new(1, 0, 0, 0)
        body.AutomaticSize = Enum.AutomaticSize.Y
        body.BackgroundTransparency = 1
        body.Font = Enum.Font.Gotham
        body.TextSize = 12
        body.TextWrapped = true
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.Text = msg
        body.Parent = frame
        setFontClass(body, "Body")
        registerTheme(body, "TextColor3", "Muted")

        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, tokens.InputPadSm or 4)
        list.Parent = frame

        copyBtn.MouseButton1Click:Connect(function()
            if setclipboard then
                setclipboard(msg)
                notify("Copied", "Log disalin ke clipboard", 2)
            else
                notify("Copy Failed", "setclipboard tidak tersedia", 2)
            end
        end)

        DevLogs[#DevLogs + 1] = {Frame = frame, Text = msg, Type = msgType}
    end

    local function loadDevLogsFromBuffer()
        clearDevLogs()
        local history = getLogHistoryAll()
        for _, item in ipairs(history) do
            addDevLogEntry(item.Message, item.Type)
        end
        for _, item in ipairs(ConsoleLogBuffer) do
            addDevLogEntry(item.Message, item.Type)
        end
    end

    createToggle(State.DevSections.ConsoleLog, "Enable Logging", nil, false, function(v)
        DevLogEnabled = v
        if DevLogEnabled then
            loadDevLogsFromBuffer()
            if DevLogConnection then
                DevLogConnection:Disconnect()
            end
            DevLogConnection = trackConnection(LogService.MessageOut:Connect(function(message, msgType)
                addDevLogEntry(message, msgType)
            end))
        else
            if DevLogConnection then
                DevLogConnection:Disconnect()
                DevLogConnection = nil
            end
        end
    end)

    createButton(State.DevSections.ConsoleLog, "Clear All Logs", function()
        clearDevLogs()
        ConsoleLogBuffer = {}
    end)
end

State.NotifyTest = State.NotifyTest or {}
State.NotifyTest.Setup = State.NotifyTest.Setup or function(parent)
    State.NotifyTest.Title = State.NotifyTest.Title or "Test"
    State.NotifyTest.Content = State.NotifyTest.Content or "Ini contoh isi notify."

    local container = (State.DevSections and State.DevSections.Notify) or parent
    if not container then
        return
    end

    createParagraph(container, "Test Notify", "Rangkaian fitur untuk menguji tampilan notifikasi.")

    createInput(container, "Notify Title", nil, State.NotifyTest.Title, function(v)
        State.NotifyTest.Title = v or ""
    end)

    local notifyContentBox = Instance.new("Frame")
    notifyContentBox.Size = UDim2.new(1, 0, 0, 90)
    notifyContentBox.BorderSizePixel = 0
    notifyContentBox.Parent = container
    registerTheme(notifyContentBox, "BackgroundColor3", "Main")
    addCorner(notifyContentBox, 6)
    addStroke(notifyContentBox, "Muted", 1, 0.8)

    local notifyContentLabel = Instance.new("TextLabel")
    notifyContentLabel.Size = UDim2.new(1, 0, 0, 18)
    notifyContentLabel.Position = UDim2.new(0, 8, 0, 6)
    notifyContentLabel.BackgroundTransparency = 1
    notifyContentLabel.Font = Enum.Font.Gotham
    notifyContentLabel.TextSize = 12
    notifyContentLabel.TextXAlignment = Enum.TextXAlignment.Left
    notifyContentLabel.Text = "Notify Content"
    notifyContentLabel.Parent = notifyContentBox
    registerTheme(notifyContentLabel, "TextColor3", "Text")

    local notifyContentScroll = Instance.new("ScrollingFrame")
    notifyContentScroll.Size = UDim2.new(1, -12, 1, -28)
    notifyContentScroll.Position = UDim2.new(0, 6, 0, 24)
    notifyContentScroll.BorderSizePixel = 0
    notifyContentScroll.BackgroundTransparency = 1
    notifyContentScroll.ScrollBarThickness = 4
    notifyContentScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    notifyContentScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    notifyContentScroll.ClipsDescendants = true
    notifyContentScroll.Parent = notifyContentBox
    registerTheme(notifyContentScroll, "BackgroundColor3", "Panel")
    addCorner(notifyContentScroll, 6)

    local notifyContentInput = Instance.new("TextBox")
    notifyContentInput.Size = UDim2.new(1, -8, 0, 24)
    notifyContentInput.Position = UDim2.new(0, 4, 0, 4)
    notifyContentInput.BorderSizePixel = 0
    notifyContentInput.ClearTextOnFocus = false
    notifyContentInput.Font = Enum.Font.Gotham
    notifyContentInput.TextSize = 12
    notifyContentInput.TextXAlignment = Enum.TextXAlignment.Left
    notifyContentInput.TextYAlignment = Enum.TextYAlignment.Top
    notifyContentInput.TextWrapped = true
    notifyContentInput.MultiLine = true
    notifyContentInput.Text = State.NotifyTest.Content
    notifyContentInput.ClipsDescendants = true
    notifyContentInput.Parent = notifyContentScroll
    registerTheme(notifyContentInput, "BackgroundColor3", "Panel")
    registerTheme(notifyContentInput, "TextColor3", "Text")
    addCorner(notifyContentInput, 6)

    local notifyContentPad = Instance.new("UIPadding")
    notifyContentPad.PaddingLeft = UDim.new(0, 6)
    notifyContentPad.PaddingRight = UDim.new(0, 6)
    notifyContentPad.PaddingTop = UDim.new(0, 4)
    notifyContentPad.PaddingBottom = UDim.new(0, 4)
    notifyContentPad.Parent = notifyContentInput

    local function updateNotifyContentSize()
        local bounds = notifyContentInput.TextBounds
        local minH = math.max(24, notifyContentScroll.AbsoluteSize.Y - 8)
        local textH = (bounds and bounds.Y or 0) + 12
        local newH = math.max(minH, textH)
        notifyContentInput.Size = UDim2.new(1, -8, 0, newH)
        notifyContentScroll.CanvasSize = UDim2.new(0, 0, 0, newH + 8)
    end

    trackConnection(notifyContentInput:GetPropertyChangedSignal("Text"):Connect(function()
        updateNotifyContentSize()
        State.NotifyTest.Content = notifyContentInput.Text or ""
    end))

    trackConnection(notifyContentScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateNotifyContentSize))
    updateNotifyContentSize()

    createButton(container, "Trigger Notify (Test)", function()
        notify(State.NotifyTest.Title or "Test", State.NotifyTest.Content or "", 4)
    end)
end

State.NotifyTest.Setup(State.DevSections.Notify)

-- [SECTION] Saved Position State
local SavedPosition = nil
local SavedCamera = nil

-- [FUNC] Save current player + camera snapshot
createButton(State.DevSections.Teleport, "Save Current Position", function()
    if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
        SavedPosition = LP.Character.HumanoidRootPart.Position
        local cam = workspace.CurrentCamera
        if cam then
            local zoom = (cam.CFrame.Position - cam.Focus.Position).Magnitude
            SavedCamera = {
                CFrame = cam.CFrame,
                Focus = cam.Focus,
                FOV = cam.FieldOfView,
                Type = cam.CameraType,
                Subject = cam.CameraSubject,
                Zoom = zoom,
                MinZoom = LP.CameraMinZoomDistance,
                MaxZoom = LP.CameraMaxZoomDistance
            }
        end
        notify("Position Saved", tostring(SavedPosition), 3)
    end
end)

-- [FUNC] Teleport to saved snapshot (with short camera lock)
createButton(State.DevSections.Teleport, "Teleport to Saved Position", function()
    if SavedPosition and LP.Character then
        LP.Character:PivotTo(CFrame.new(SavedPosition))
        local cam = workspace.CurrentCamera
        if cam and SavedCamera then
            local targetType = SavedCamera.Type or cam.CameraType
            local targetSubject = SavedCamera.Subject or cam.CameraSubject
            local targetFOV = SavedCamera.FOV or cam.FieldOfView
            local targetCFrame = SavedCamera.CFrame or cam.CFrame
            local targetFocus = SavedCamera.Focus or cam.Focus
            local targetZoom = SavedCamera.Zoom
            local oldMinZoom = LP.CameraMinZoomDistance
            local oldMaxZoom = LP.CameraMaxZoomDistance

            cam.CameraType = Enum.CameraType.Scriptable
            cam.FieldOfView = targetFOV
            cam.CFrame = targetCFrame
            cam.Focus = targetFocus
            if targetZoom then
                pcall(function()
                    LP.CameraMinZoomDistance = targetZoom
                    LP.CameraMaxZoomDistance = targetZoom
                end)
            end

            local lockSeconds = 0.35
            local startTime = os.clock()
            local rsConn
            rsConn = RunService.RenderStepped:Connect(function()
                if not cam then
                    if rsConn then
                        rsConn:Disconnect()
                    end
                    return
                end
                cam.FieldOfView = targetFOV
                cam.CFrame = targetCFrame
                cam.Focus = targetFocus
                if targetZoom then
                    pcall(function()
                        LP.CameraMinZoomDistance = targetZoom
                        LP.CameraMaxZoomDistance = targetZoom
                    end)
                end
                if (os.clock() - startTime) >= lockSeconds then
                    if rsConn then
                        rsConn:Disconnect()
                    end
                    cam.CameraSubject = targetSubject
                    cam.CameraType = targetType
                    task.delay(0.1, function()
                        pcall(function()
                            LP.CameraMinZoomDistance = oldMinZoom
                            LP.CameraMaxZoomDistance = oldMaxZoom
                        end)
                    end)
                end
            end)
            trackConnection(rsConn)
        end
    end
end)

-- [SECTION] Copy Data Logger (Editable Fields)
local CopyLogFields = {
    Position = "",
    CamCFrame = "",
    CamFocus = "",
    CamFOV = "",
    CamType = "",
    CamZoom = "",
    CamMinZoom = "",
    CamMaxZoom = "",
    CamMode = ""
}

local CopyLogInputs = {}

local function setCopyLogField(key, value)
    CopyLogFields[key] = value or ""
    if CopyLogInputs[key] then
        CopyLogInputs[key]:Set(CopyLogFields[key])
    end
end

local function getCopyLogField(key)
    return (CopyLogInputs[key] and CopyLogInputs[key]:Get()) or CopyLogFields[key] or ""
end

local function parseNumber(text)
    local normalized = tostring(text):gsub(",", ".")
    return tonumber(normalized)
end

local function parseVector3(text)
    local nums = {}
    for num in tostring(text):gmatch("[-%d%.]+") do
        nums[#nums + 1] = tonumber(num)
    end
    if #nums >= 3 then
        return Vector3.new(nums[1], nums[2], nums[3])
    end
    return nil
end

local function parseCFrame(text)
    local nums = {}
    for num in tostring(text):gmatch("[-%d%.]+") do
        nums[#nums + 1] = tonumber(num)
    end
    if #nums >= 12 then
        return CFrame.new(
            nums[1], nums[2], nums[3],
            nums[4], nums[5], nums[6],
            nums[7], nums[8], nums[9],
            nums[10], nums[11], nums[12]
        )
    elseif #nums >= 3 then
        return CFrame.new(nums[1], nums[2], nums[3])
    end
    return nil
end

local function buildDataFromCopyLog()
    local pos = parseVector3(getCopyLogField("Position"))
    local camCFrame = parseCFrame(getCopyLogField("CamCFrame"))
    local camFocus = parseCFrame(getCopyLogField("CamFocus"))
    local fov = parseNumber(getCopyLogField("CamFOV"))
    local camType = parseCameraType(getCopyLogField("CamType"))
    local zoom = parseNumber(getCopyLogField("CamZoom"))
    local minZoom = parseNumber(getCopyLogField("CamMinZoom"))
    local maxZoom = parseNumber(getCopyLogField("CamMaxZoom"))

    return {
        position = pos,
        camera = {
            cframe = camCFrame,
            focus = camFocus,
            fov = fov,
            type = camType,
            zoom = zoom,
            min_zoom = minZoom,
            max_zoom = maxZoom
        }
    }
end

-- [FUNC] Copy current position to clipboard + update editable log fields
createButton(State.DevSections.CopyData, "Copy Current Position", function()
    if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
        local pos = LP.Character.HumanoidRootPart.Position
        local cam = workspace.CurrentCamera
        local camData = ""
        if cam then
            local cf = cam.CFrame
            local focus = cam.Focus
            local zoom = (cf.Position - focus.Position).Magnitude
            local cfx, cfy, cfz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
            local fx, fy, fz, fr00, fr01, fr02, fr10, fr11, fr12, fr20, fr21, fr22 = focus:GetComponents()
            camData = (
                "    {Label = \"Default\", Data = makeData(\n" ..
                "        Vector3.new(%.3f, %.3f, %.3f),\n" ..
                "        CFrame.new(%.6f, %.6f, %.6f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f),\n" ..
                "        CFrame.new(%.6f, %.6f, %.6f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f),\n" ..
                "        %.6f\n" ..
                "    )},"
            ):format(
                pos.X, pos.Y, pos.Z,
                cfx, cfy, cfz, r00, r01, r02, r10, r11, r12, r20, r21, r22,
                fx, fy, fz, fr00, fr01, fr02, fr10, fr11, fr12, fr20, fr21, fr22,
                zoom
            )
            setCopyLogField("CamCFrame", ("%.6f, %.6f, %.6f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f")
                :format(cfx, cfy, cfz, r00, r01, r02, r10, r11, r12, r20, r21, r22))
            setCopyLogField("CamFocus", ("%.6f, %.6f, %.6f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f, %.9f")
                :format(fx, fy, fz, fr00, fr01, fr02, fr10, fr11, fr12, fr20, fr21, fr22))
            setCopyLogField("CamFOV", string.format("%.3f", cam.FieldOfView))
            setCopyLogField("CamType", tostring(cam.CameraType))
            setCopyLogField("CamZoom", string.format("%.6f", zoom))
        end
        setCopyLogField("Position", string.format("%.3f, %.3f, %.3f", pos.X, pos.Y, pos.Z))
        local text = camData ~= "" and camData or ("{ position = Vector3.new(%.3f, %.3f, %.3f) }"):format(pos.X, pos.Y, pos.Z)
        if setclipboard then
            setclipboard(text)
            notify("Copied", text, 3)
        else
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
        end
    end
end)

CopyLogInputs.Position = createInput(State.DevSections.CopyData, "Position (x, y, z)", nil, CopyLogFields.Position, function(v)
    CopyLogFields.Position = v
end)
CopyLogInputs.CamCFrame = createInput(State.DevSections.CopyData, "Camera CFrame (12 nums)", nil, CopyLogFields.CamCFrame, function(v)
    CopyLogFields.CamCFrame = v
end)
CopyLogInputs.CamFocus = createInput(State.DevSections.CopyData, "Camera Focus (12 nums)", nil, CopyLogFields.CamFocus, function(v)
    CopyLogFields.CamFocus = v
end)
CopyLogInputs.CamFOV = createInput(State.DevSections.CopyData, "Camera FOV", nil, CopyLogFields.CamFOV, function(v)
    CopyLogFields.CamFOV = v
end)
CopyLogInputs.CamType = createInput(State.DevSections.CopyData, "Camera Type", nil, CopyLogFields.CamType, function(v)
    CopyLogFields.CamType = v
end)
CopyLogInputs.CamZoom = createInput(State.DevSections.CopyData, "Camera Zoom", nil, CopyLogFields.CamZoom, function(v)
    CopyLogFields.CamZoom = v
end)
CopyLogInputs.CamMinZoom = createInput(State.DevSections.CopyData, "Min Zoom", nil, CopyLogFields.CamMinZoom, function(v)
    CopyLogFields.CamMinZoom = v
end)
CopyLogInputs.CamMaxZoom = createInput(State.DevSections.CopyData, "Max Zoom", nil, CopyLogFields.CamMaxZoom, function(v)
    CopyLogFields.CamMaxZoom = v
end)
CopyLogInputs.CamMode = createInput(State.DevSections.CopyData, "Camera Mode", nil, CopyLogFields.CamMode, function(v)
    CopyLogFields.CamMode = v
end)

createButton(State.DevSections.CopyData, "Test Teleport From Fields", function()
    local data = buildDataFromCopyLog()
    if not data.position then
        notify("Test Teleport", "Position tidak valid. Format: x, y, z", 3)
        return
    end
    teleportWithData(data)
end)

do
    local ActionLoggerState = {
        Enabled = false,
        RowsBySignature = {},
        RowOrder = {},
        MaxRows = 250,
        SuppressUntil = 0
    }

    local ActionLogUI = State.UI.BuildScrollList(State.DevSections.Action, {
        Title = "Logs (Action)",
        Height = 220,
        TitleClass = "Subheading"
    })
    local ActionLogScroll = ActionLogUI.Scroll

    local function getNow()
        return os.clock()
    end

    local function canCapture()
        return ActionLoggerState.Enabled and getNow() >= (ActionLoggerState.SuppressUntil or 0)
    end

    local function safeClipboard(text)
        if setclipboard then
            setclipboard(text)
            notify("Copied", "Action disalin ke clipboard", 2)
        else
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
        end
    end

    local function sendMouseClickOnce(x, y)
        local px = tonumber(x) or 0
        local py = tonumber(y) or 0
        if VirtualInputManager and VirtualInputManager.SendMouseButtonEvent then
            local okDown = pcall(function()
                VirtualInputManager:SendMouseMoveEvent(px, py, game)
                VirtualInputManager:SendMouseButtonEvent(px, py, 0, true, game, 0)
            end)
            local okUp = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(px, py, 0, false, game, 0)
            end)
            if okDown and okUp then
                return true
            end
            okDown = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(px, py, 0, true, game, 0)
            end)
            okUp = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(px, py, 0, false, game, 0)
            end)
            if okDown and okUp then
                return true
            end
        end
        if mouse1click then
            return pcall(mouse1click)
        end
        return false
    end

    local function sendKeyOnce(keyName)
        if type(keyName) ~= "string" or #keyName == 0 then
            return false
        end
        local keyCode = Enum.KeyCode[keyName]
        if not keyCode then
            return false
        end
        if VirtualInputManager and VirtualInputManager.SendKeyEvent then
            local okDown = pcall(function()
                VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
            end)
            local okUp = pcall(function()
                VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
            end)
            return okDown and okUp
        end
        return false
    end

    local function buildCopyText(entry)
        if not entry then
            return ""
        end
        if entry.Kind == "Key" then
            return ("Action = Key | KeyCode = %s"):format(tostring(entry.KeyCode or "Unknown"))
        end
        if entry.Kind == "Click" then
            local posText = tostring(entry.ScreenX or 0) .. ", " .. tostring(entry.ScreenY or 0)
            local world = entry.WorldPos
            if world then
                return ("Action = Click | Screen = (%s) | World = (%.3f, %.3f, %.3f)"):format(
                    posText,
                    world.X,
                    world.Y,
                    world.Z
                )
            end
            return ("Action = Click | Screen = (%s)"):format(posText)
        end
        return tostring(entry.Kind or "Action")
    end

    local function buildDetailText(entry)
        if not entry then
            return "-"
        end
        if entry.Kind == "Key" then
            return "Type: Keyboard | Count: " .. tostring(entry.Count or 0)
        end
        local base = "Type: Mouse Click | Count: " .. tostring(entry.Count or 0)
        local world = entry.WorldPos
        if world then
            return base .. ("\nWorld: %.3f, %.3f, %.3f"):format(world.X, world.Y, world.Z)
        end
        return base
    end

    local function buildTitle(entry)
        if not entry then
            return "Action"
        end
        if entry.Kind == "Key" then
            return "Key [" .. tostring(entry.KeyCode or "Unknown") .. "]"
        end
        return "Click [" .. tostring(entry.ScreenX or 0) .. ", " .. tostring(entry.ScreenY or 0) .. "]"
    end

    local function runAction(entry)
        if not entry then
            return
        end
        ActionLoggerState.SuppressUntil = getNow() + 0.2
        local ok = false
        if entry.Kind == "Key" then
            ok = sendKeyOnce(entry.KeyCode)
        elseif entry.Kind == "Click" then
            ok = sendMouseClickOnce(entry.ScreenX, entry.ScreenY)
        end
        if ok then
            notify("Action Run", "Aksi dieksekusi 1x", 2)
        else
            notify("Action Run", "Gagal eksekusi aksi (method tidak tersedia)", 2)
        end
    end

    local function destroyActionRow(signature)
        local rowData = ActionLoggerState.RowsBySignature[signature]
        if rowData and rowData.Frame then
            rowData.Frame:Destroy()
        end
        ActionLoggerState.RowsBySignature[signature] = nil
        for i = #ActionLoggerState.RowOrder, 1, -1 do
            if ActionLoggerState.RowOrder[i] == signature then
                table.remove(ActionLoggerState.RowOrder, i)
            end
        end
    end

    local function renderRow(rowData)
        if not rowData or not rowData.Entry then
            return
        end
        if rowData.Title then
            rowData.Title.Text = buildTitle(rowData.Entry)
        end
        if rowData.Detail then
            rowData.Detail.Text = buildDetailText(rowData.Entry)
        end
    end

    local function createActionRow(signature, entry)
        local tokens = (State.Layout and State.Layout.GetTokens and State.Layout.GetTokens()) or {
            RowH = 30,
            InputPad = 6,
            InputPadSm = 4,
            RadiusSm = 6,
            ButtonW = 24
        }
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 0)
        frame.AutomaticSize = Enum.AutomaticSize.Y
        frame.BorderSizePixel = 0
        frame.Parent = ActionLogScroll
        registerTheme(frame, "BackgroundColor3", "Main")
        addCorner(frame, tokens.RadiusSm or 6)
        addStroke(frame, "Muted", 1, 0.7)

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, tokens.InputPadSm or 4)
        pad.PaddingBottom = UDim.new(0, tokens.InputPadSm or 4)
        pad.PaddingLeft = UDim.new(0, tokens.InputPad or 6)
        pad.PaddingRight = UDim.new(0, tokens.InputPad or 6)
        pad.Parent = frame

        local header = Instance.new("Frame")
        header.Size = UDim2.new(1, 0, 0, math.max(18, (tokens.RowH or 30) - (tokens.InputPadSm or 4)))
        header.BackgroundTransparency = 1
        header.Parent = frame

        local buttonW = math.max(46, ((tokens.ButtonW or 24) * 2))
        local runBtn = Instance.new("TextButton")
        runBtn.Size = UDim2.new(0, buttonW, 1, 0)
        runBtn.Position = UDim2.new(1, -(buttonW * 2 + (tokens.InputPadSm or 4)), 0, 0)
        runBtn.BorderSizePixel = 0
        runBtn.Text = "Run"
        runBtn.Font = Enum.Font.Gotham
        runBtn.TextSize = 11
        runBtn.AutoButtonColor = false
        runBtn.Parent = header
        setFontClass(runBtn, "Small")
        registerTheme(runBtn, "BackgroundColor3", "Panel")
        registerTheme(runBtn, "TextColor3", "Text")
        addCorner(runBtn, tokens.RadiusSm or 6)

        local copyBtn = Instance.new("TextButton")
        copyBtn.Size = UDim2.new(0, buttonW, 1, 0)
        copyBtn.Position = UDim2.new(1, -buttonW, 0, 0)
        copyBtn.BorderSizePixel = 0
        copyBtn.Text = "Copy"
        copyBtn.Font = Enum.Font.Gotham
        copyBtn.TextSize = 11
        copyBtn.AutoButtonColor = false
        copyBtn.Parent = header
        setFontClass(copyBtn, "Small")
        registerTheme(copyBtn, "BackgroundColor3", "Panel")
        registerTheme(copyBtn, "TextColor3", "Text")
        addCorner(copyBtn, tokens.RadiusSm or 6)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -((buttonW * 2) + (tokens.InputPadSm or 4) + 2), 1, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamSemibold
        title.TextSize = 12
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = header
        setFontClass(title, "Small")
        registerTheme(title, "TextColor3", "Text")

        local detail = Instance.new("TextLabel")
        detail.Size = UDim2.new(1, 0, 0, 0)
        detail.AutomaticSize = Enum.AutomaticSize.Y
        detail.BackgroundTransparency = 1
        detail.Font = Enum.Font.Gotham
        detail.TextSize = 11
        detail.TextWrapped = true
        detail.TextXAlignment = Enum.TextXAlignment.Left
        detail.TextYAlignment = Enum.TextYAlignment.Top
        detail.Parent = frame
        setFontClass(detail, "Small")
        registerTheme(detail, "TextColor3", "Muted")

        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, tokens.InputPadSm or 4)
        list.Parent = frame

        local rowData = {
            Signature = signature,
            Entry = entry,
            Frame = frame,
            Title = title,
            Detail = detail
        }
        ActionLoggerState.RowsBySignature[signature] = rowData
        ActionLoggerState.RowOrder[#ActionLoggerState.RowOrder + 1] = signature

        copyBtn.MouseButton1Click:Connect(function()
            safeClipboard(buildCopyText(rowData.Entry))
        end)
        runBtn.MouseButton1Click:Connect(function()
            runAction(rowData.Entry)
        end)

        renderRow(rowData)
        return rowData
    end

    local function trimRowsIfNeeded()
        while #ActionLoggerState.RowOrder > (ActionLoggerState.MaxRows or 250) do
            local oldSignature = table.remove(ActionLoggerState.RowOrder, 1)
            if oldSignature then
                local oldRow = ActionLoggerState.RowsBySignature[oldSignature]
                if oldRow and oldRow.Frame then
                    oldRow.Frame:Destroy()
                end
                ActionLoggerState.RowsBySignature[oldSignature] = nil
            end
        end
    end

    local function addActionLog(signature, entryPatch)
        if type(signature) ~= "string" or #signature == 0 then
            return
        end
        local rowData = ActionLoggerState.RowsBySignature[signature]
        if rowData and rowData.Entry then
            rowData.Entry.Count = (tonumber(rowData.Entry.Count) or 0) + 1
            rowData.Entry.LastAt = getNow()
            if type(entryPatch) == "table" then
                for k, v in pairs(entryPatch) do
                    rowData.Entry[k] = v
                end
            end
            renderRow(rowData)
            return
        end

        local newEntry = {
            Count = 1,
            LastAt = getNow()
        }
        if type(entryPatch) == "table" then
            for k, v in pairs(entryPatch) do
                newEntry[k] = v
            end
        end
        createActionRow(signature, newEntry)
        trimRowsIfNeeded()
    end

    local function clearActionLogs()
        for i = #ActionLoggerState.RowOrder, 1, -1 do
            local signature = ActionLoggerState.RowOrder[i]
            destroyActionRow(signature)
        end
        ActionLoggerState.RowOrder = {}
        ActionLoggerState.RowsBySignature = {}
    end

    createToggle(State.DevSections.Action, "Enable Action Logger", "ActionLogger", false, function(v)
        ActionLoggerState.Enabled = v == true
    end)

    createButton(State.DevSections.Action, "Clear Action Logs", function()
        clearActionLogs()
    end)

    trackConnection(Mouse.Button1Down:Connect(function()
        if not canCapture() then
            return
        end
        local sx = math.floor((tonumber(Mouse and Mouse.X) or 0) + 0.5)
        local sy = math.floor((tonumber(Mouse and Mouse.Y) or 0) + 0.5)
        local signature = "Click:" .. tostring(sx) .. ":" .. tostring(sy)
        local worldPos = nil
        if Mouse and Mouse.Hit and Mouse.Hit.Position then
            worldPos = Mouse.Hit.Position
        end
        addActionLog(signature, {
            Kind = "Click",
            ScreenX = sx,
            ScreenY = sy,
            WorldPos = worldPos
        })
    end))

    trackConnection(UIS.InputBegan:Connect(function(input, gp)
        if gp or not canCapture() then
            return
        end
        if UIS:GetFocusedTextBox() then
            return
        end
        local keyCode = input and input.KeyCode or nil
        if not keyCode or keyCode == Enum.KeyCode.Unknown then
            return
        end
        local keyName = tostring(keyCode.Name or "Unknown")
        local signature = "Key:" .. keyName
        addActionLog(signature, {
            Kind = "Key",
            KeyCode = keyName
        })
    end))
end


State.DevSections.FloatConvert = createSectionBox(DevTab:GetPage(), "Float Convertion")

local function toPlainNumberString(text)
    local str = trimText(text)
    if str == "" then
        return ""
    end
    local sign, mantissa, exp = str:match("^([+-]?)(%d*%.?%d+)[eE]([+-]?%d+)$")
    if not mantissa then
        return str
    end
    local expNum = tonumber(exp) or 0
    local intPart, fracPart = mantissa:match("^(%d+)%.?(%d*)$")
    local digits = (intPart or "") .. (fracPart or "")
    local decs = #(fracPart or "")
    if expNum >= 0 then
        local shift = expNum - decs
        if shift >= 0 then
            return sign .. digits .. string.rep("0", shift)
        end
        local pos = #digits + shift
        if pos <= 0 then
            return sign .. "0." .. string.rep("0", -pos) .. digits
        end
        return sign .. digits:sub(1, pos) .. "." .. digits:sub(pos + 1)
    end
    local pos = #intPart + expNum
    if pos <= 0 then
        return sign .. "0." .. string.rep("0", -pos) .. digits
    end
    return sign .. digits:sub(1, pos) .. "." .. digits:sub(pos + 1)
end

local function normalizeDigits(text)
    local sign = ""
    local str = trimText(text)
    if str:sub(1, 1) == "-" then
        sign = "-"
        str = str:sub(2)
    elseif str:sub(1, 1) == "+" then
        str = str:sub(2)
    end
    local intPart, fracPart = str:match("^(%d*)%.?(%d*)$")
    if not intPart then
        return nil
    end
    intPart = intPart ~= "" and intPart or "0"
    fracPart = fracPart or ""
    return sign, intPart, fracPart
end

local function toScientificString(text)
    local sign, intPart, fracPart = normalizeDigits(text)
    if not sign then
        return text
    end
    local intTrim = intPart:gsub("^0+", "")
    local digits
    local exp
    if intTrim ~= "" then
        digits = intTrim .. fracPart
        exp = #intTrim - 1
    else
        local leadZeros = fracPart:match("^(0*)") or ""
        local rest = fracPart:sub(#leadZeros + 1)
        if rest == "" then
            return "0"
        end
        digits = rest
        exp = -(#leadZeros + 1)
    end
    local maxSig = 16
    if #digits > maxSig then
        local nextDigit = tonumber(digits:sub(maxSig + 1, maxSig + 1)) or 0
        digits = digits:sub(1, maxSig)
        if nextDigit >= 5 then
            local carry = 1
            local out = {}
            for i = #digits, 1, -1 do
                local d = tonumber(digits:sub(i, i)) or 0
                d = d + carry
                if d >= 10 then
                    d = d - 10
                    carry = 1
                else
                    carry = 0
                end
                out[i] = tostring(d)
            end
            if carry == 1 then
                table.insert(out, 1, "1")
                exp = exp + 1
            end
            digits = table.concat(out)
        end
    end
    local mantissa = digits:sub(1, 1)
    local rest = digits:sub(2)
    if rest ~= "" then
        mantissa = mantissa .. "." .. rest
    end
    local expStr = tostring(exp)
    return sign .. mantissa .. "e" .. expStr
end

local function toFloatNumberString(text)
    local str = trimText(text)
    if str == "" then
        return ""
    end
    if str:find("[eE]") then
        return toScientificString(toPlainNumberString(str))
    end
    return toScientificString(str)
end

local function formatGameValue(text)
    local suffixes = {"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "Dc"}
    local sign, intPart, fracPart = normalizeDigits(text)
    if not sign then
        return ""
    end
    local intTrim = intPart:gsub("^0+", "")
    local digits = intTrim ~= "" and (intTrim .. fracPart) or (fracPart:gsub("^0+", ""))
    if digits == "" then
        return "0"
    end
    local intLen = #intTrim
    if intLen == 0 then
        return "0"
    end
    local idx = math.floor((intLen - 1) / 3) + 1
    if idx > #suffixes then
        idx = #suffixes
    end
    local shift = (idx - 1) * 3
    local pos = intLen - shift
    local scaled
    if pos <= 0 then
        scaled = "0." .. string.rep("0", -pos) .. intTrim .. fracPart
    else
        local left = intTrim:sub(1, pos)
        local right = intTrim:sub(pos + 1) .. fracPart
        if right ~= "" then
            scaled = left .. "." .. right
        else
            scaled = left
        end
    end
    local sInt, sFrac = scaled:match("^(%d+)%.?(%d*)$")
    local intDigits = #sInt
    local keep = 0
    if intDigits == 1 then
        keep = 2
    elseif intDigits == 2 then
        keep = 1
    else
        keep = 0
    end
    local out = sInt
    if keep > 0 and sFrac ~= "" then
        out = out .. "." .. sFrac:sub(1, keep)
        out = out:gsub("%.?0+$", "")
    end
    return sign .. out .. suffixes[idx]
end

local FloatConvertFields = {
    Float = "",
    Value = ""
}

local FloatConvertInputs = {}
local FloatConvertGuard = false

FloatConvertInputs.Float = createInput(State.DevSections.FloatConvert, "Input Float", nil, FloatConvertFields.Float, nil)
FloatConvertInputs.Value = createInput(State.DevSections.FloatConvert, "Input Value", nil, FloatConvertFields.Value, nil)
FloatConvertInputs.GameValue = createInput(State.DevSections.FloatConvert, "Game Value", nil, "", nil)
FloatConvertInputs.GameValue:SetEnabled(false)

FloatConvertInputs.Float.Box:GetPropertyChangedSignal("Text"):Connect(function()
    if FloatConvertGuard then
        return
    end
    FloatConvertFields.Float = FloatConvertInputs.Float.Box.Text or ""
    FloatConvertGuard = true
    local converted = toPlainNumberString(FloatConvertFields.Float)
    if FloatConvertInputs.Value and FloatConvertInputs.Value.Set then
        FloatConvertInputs.Value:Set(converted)
    end
    FloatConvertFields.Value = converted
    if FloatConvertInputs.GameValue and FloatConvertInputs.GameValue.Set then
        FloatConvertInputs.GameValue:Set(formatGameValue(converted))
    end
    FloatConvertGuard = false
end)

FloatConvertInputs.Value.Box:GetPropertyChangedSignal("Text"):Connect(function()
    if FloatConvertGuard then
        return
    end
    FloatConvertFields.Value = FloatConvertInputs.Value.Box.Text or ""
    FloatConvertGuard = true
    local converted = toFloatNumberString(FloatConvertFields.Value)
    if FloatConvertInputs.Float and FloatConvertInputs.Float.Set then
        FloatConvertInputs.Float:Set(converted)
    end
    FloatConvertFields.Float = converted
    if FloatConvertInputs.GameValue and FloatConvertInputs.GameValue.Set then
        FloatConvertInputs.GameValue:Set(formatGameValue(FloatConvertFields.Value))
    end
    FloatConvertGuard = false
end)

do
    State.DevSections.RepScan = createSectionBox(DevTab:GetPage(), "ReplicatedStorage Scanner")

    local function parseKeywords(text)
        local out = {}
        for token in string.gmatch(text or "", "([^,]+)") do
            local t = string.lower(string.gsub(token, "^%s*(.-)%s*$", "%1"))
            if t ~= "" then
                out[#out + 1] = t
            end
        end
        return out
    end

    local function getPath(inst)
        if not inst then
            return ""
        end
        local ok, res = pcall(function()
            return inst:GetFullName()
        end)
        if ok and res then
            return res
        end
        return tostring(inst)
    end

    local function clearRows(list)
        if list then
            for i = #list, 1, -1 do
                if list[i] and list[i].Frame then
                    list[i].Frame:Destroy()
                end
                table.remove(list, i)
            end
        end
    end

    local function addResultRow(parent, inst, text)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 28)
        row.BorderSizePixel = 0
        row.Parent = parent
        registerTheme(row, "BackgroundColor3", "Main")
        addCorner(row, 6)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -206, 1, 0)
        label.Position = UDim2.new(0, 8, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Text = text
        label.Parent = row
        registerTheme(label, "TextColor3", "Text")

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 54, 0, 20)
        btn.Position = UDim2.new(1, -198, 0.5, -10)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 11
        btn.Text = "Copy"
        btn.AutoButtonColor = false
        btn.Parent = row
        registerTheme(btn, "BackgroundColor3", "Panel")
        registerTheme(btn, "TextColor3", "Text")
        addCorner(btn, 6)

        local btnDecompileOld = Instance.new("TextButton")
        btnDecompileOld.Size = UDim2.new(0, 62, 0, 20)
        btnDecompileOld.Position = UDim2.new(1, -140, 0.5, -10)
        btnDecompileOld.BorderSizePixel = 0
        btnDecompileOld.Font = Enum.Font.GothamSemibold
        btnDecompileOld.TextSize = 10
        btnDecompileOld.Text = "Old"
        btnDecompileOld.AutoButtonColor = false
        btnDecompileOld.Parent = row
        registerTheme(btnDecompileOld, "BackgroundColor3", "Panel")
        registerTheme(btnDecompileOld, "TextColor3", "Text")
        addCorner(btnDecompileOld, 6)

        local btnDecompileNew = Instance.new("TextButton")
        btnDecompileNew.Size = UDim2.new(0, 62, 0, 20)
        btnDecompileNew.Position = UDim2.new(1, -74, 0.5, -10)
        btnDecompileNew.BorderSizePixel = 0
        btnDecompileNew.Font = Enum.Font.GothamSemibold
        btnDecompileNew.TextSize = 10
        btnDecompileNew.Text = "New"
        btnDecompileNew.AutoButtonColor = false
        btnDecompileNew.Parent = row
        registerTheme(btnDecompileNew, "BackgroundColor3", "Panel")
        registerTheme(btnDecompileNew, "TextColor3", "Text")
        addCorner(btnDecompileNew, 6)

        btn.MouseButton1Click:Connect(function()
            if setclipboard then
                setclipboard(text)
                notify("Copied", "Path disalin", 2)
            else
                notify("Copy Failed", "setclipboard tidak tersedia", 2)
            end
        end)

        local function setButtonEnabled(button, enabled)
            if not button then
                return
            end
            button.AutoButtonColor = enabled == true
            button.TextTransparency = enabled and 0 or 0.4
            button.BackgroundTransparency = enabled and 0 or 0.4
        end

        local function resolveDecompileOld()
            local env = (getgenv and getgenv()) or _G
            if type(env) ~= "table" then
                env = _G
            end
            local fn = rawget(env, "decompile") or decompile
            if type(fn) == "function" then
                return fn
            end
            return nil
        end

        local function resolveDecompileNew()
            local env = (getgenv and getgenv()) or _G
            if type(env) ~= "table" then
                env = _G
            end
            local candidates = {
                rawget(env, "decompile_new"),
                rawget(env, "decompile2"),
                rawget(env, "decompilev2"),
                rawget(env, "decompiler"),
                rawget(_G, "decompile_new"),
                rawget(_G, "decompile2"),
                rawget(_G, "decompilev2"),
                rawget(_G, "decompiler")
            }
            for _, fn in ipairs(candidates) do
                if type(fn) == "function" then
                    return fn
                end
            end
            return nil
        end

        local function runDecompile(which)
            local isModule = inst and inst:IsA("ModuleScript")
            if not isModule then
                return
            end
            local resolver = which == "new" and resolveDecompileNew or resolveDecompileOld
            local decompileFn = resolver and resolver() or nil
            if type(decompileFn) ~= "function" then
                notify("Decompile", "Sumber " .. tostring(which or "?") .. " tidak tersedia", 2)
                return
            end
            local ok, res = pcall(decompileFn, inst)
            if not ok or type(res) ~= "string" then
                notify("Decompile", "Gagal decompile (" .. tostring(which or "?") .. ")", 2)
                return
            end
            if setclipboard then
                setclipboard(res)
                notify("Decompile", "Hasil " .. tostring(which or "?") .. " disalin", 2)
            else
                notify("Decompile", "setclipboard tidak tersedia", 2)
            end
        end

        local isModule = inst and inst:IsA("ModuleScript")
        setButtonEnabled(btnDecompileOld, isModule)
        setButtonEnabled(btnDecompileNew, isModule)
        btnDecompileOld.MouseButton1Click:Connect(function()
            runDecompile("old")
        end)
        btnDecompileNew.MouseButton1Click:Connect(function()
            runDecompile("new")
        end)

        return {
            Frame = row,
            Label = label,
            Button = btn,
            Decompile = btnDecompileOld,
            DecompileOld = btnDecompileOld,
            DecompileNew = btnDecompileNew
        }
    end

    local RepScanUI = State.UI.BuildScrollList(State.DevSections.RepScan, {
        Title = "Results",
        Height = 180,
        TitleClass = "Subheading"
    })

    local RepScanState = {
        Rows = {},
        Keywords = parseKeywords(Config.RepScanKeywords or ""),
        IncludeFolders = Config.RepScanIncludeFolders == true,
        IncludeRemotes = Config.RepScanIncludeRemotes == true
    }

    createInput(State.DevSections.RepScan, "Keywords (comma)", "RepScanKeywords", Config.RepScanKeywords or "", function(v)
        RepScanState.Keywords = parseKeywords(v or "")
    end)

    createToggle(State.DevSections.RepScan, "Include Folder", "RepScanIncludeFolders", Config.RepScanIncludeFolders, function(v)
        RepScanState.IncludeFolders = v == true
    end)

    createToggle(State.DevSections.RepScan, "Include Remote", "RepScanIncludeRemotes", Config.RepScanIncludeRemotes, function(v)
        RepScanState.IncludeRemotes = v == true
    end)

    createButton(State.DevSections.RepScan, "Scan ReplicatedStorage", function()
        clearRows(RepScanState.Rows)
        RepScanState.Rows = {}
        local keywords = RepScanState.Keywords
        local root = game:GetService("ReplicatedStorage")
        local descendants = root:GetDescendants()
        for i = 1, #descendants do
            local inst = descendants[i]
            local isModule = inst:IsA("ModuleScript")
            local isFolder = inst:IsA("Folder")
            local isRemote = inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst.ClassName == "UnreliableRemoteEvent"
            if isModule or (RepScanState.IncludeFolders and isFolder) or (RepScanState.IncludeRemotes and isRemote) then
                local name = string.lower(inst.Name or "")
                local path = string.lower(getPath(inst))
                local matched = (#keywords == 0)
                if not matched then
                    for _, key in ipairs(keywords) do
                        if string.find(name, key, 1, true) or string.find(path, key, 1, true) then
                            matched = true
                            break
                        end
                    end
                end
                if matched then
                    RepScanState.Rows[#RepScanState.Rows + 1] = addResultRow(RepScanUI.Scroll, inst, getPath(inst))
                end
            end
        end
    end)
end

State.DevSections.Utility = createSectionBox(DevTab:GetPage(), "Utility Logger")

State.UtilityLogger = State.UtilityLogger or {}
State.UtilityLogger.Conns = State.UtilityLogger.Conns or {}
State.UtilityLogger.RootConns = State.UtilityLogger.RootConns or {}
State.UtilityLogger.Watched = State.UtilityLogger.Watched or {}
State.UtilityLogger.WatchedAttr = State.UtilityLogger.WatchedAttr or {}
State.UtilityLogger.Logs = State.UtilityLogger.Logs or {}
State.UtilityLogger.MaxLogs = State.UtilityLogger.MaxLogs or 60
State.UtilityLogger.Names = State.UtilityLogger.Names or {}
State.UtilityLogger.Enabled = Config.UtilityLoggerEnabled == true
State.UtilityLogger.TrackValues = Config.UtilityTrackValues ~= false
State.UtilityLogger.TrackAttributes = Config.UtilityTrackAttributes ~= false
State.UtilityLogger.Groups = State.UtilityLogger.Groups or {}
State.UtilityLogger.GroupList = State.UtilityLogger.GroupList or {}
State.UtilityLogger.GroupRows = State.UtilityLogger.GroupRows or {}
State.UtilityLogger.TotalLogs = State.UtilityLogger.TotalLogs or 0
State.UtilityLogger.SelectedGroupKey = State.UtilityLogger.SelectedGroupKey or nil
State.UtilityLogger.SelectedHistoryIndex = State.UtilityLogger.SelectedHistoryIndex or nil
State.UtilityLogger.SearchMode = Config.UtilityLogSearchMode or "By Path"

State.UtilityLogger.GetInstPath = State.UtilityLogger.GetInstPath or function(inst)
    if not inst then
        return "Unknown"
    end
    local ok, res = pcall(function()
        return inst:GetFullName()
    end)
    if ok and res then
        return res
    end
    return tostring(inst)
end

State.UtilityLogger.ParseNames = State.UtilityLogger.ParseNames or function(text)
    local out = {}
    for token in string.gmatch(text or "", "([^,]+)") do
        local t = string.lower(string.gsub(token, "^%s*(.-)%s*$", "%1"))
        if t ~= "" then
            out[#out + 1] = t
        end
    end
    return out
end

State.UtilityLogger.Matches = State.UtilityLogger.Matches or function(name, inst, value)
    if not name and not value and not inst then
        return false
    end
    local list = State.UtilityLogger.Names or {}
    if #list == 0 then
        return false
    end
    local mode = State.UtilityLogger.MatchMode or "Name"
    local lower = ""
    if mode == "Value" then
        if value == nil then
            return false
        end
        lower = string.lower(tostring(value))
    elseif mode == "Full Path" then
        local path = nil
        if inst then
            local ok, res = pcall(function()
                return inst:GetFullName()
            end)
            if ok and res then
                path = res
            end
        end
        if not path then
            return false
        end
        lower = string.lower(path)
    else
        if not name then
            return false
        end
        lower = string.lower(name)
    end
    for _, token in ipairs(list) do
        if string.find(lower, token, 1, true) then
            return true
        end
    end
    return false
end

State.UtilityLogger.ClearConns = State.UtilityLogger.ClearConns or function()
    for _, conn in ipairs(State.UtilityLogger.Conns) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    State.UtilityLogger.Conns = {}
    for _, conn in ipairs(State.UtilityLogger.RootConns) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    State.UtilityLogger.RootConns = {}
    State.UtilityLogger.Watched = {}
    State.UtilityLogger.WatchedAttr = {}
end

State.UtilityLogger.GetGroupPath = State.UtilityLogger.GetGroupPath or function(inst)
    if not inst then
        return "Unknown"
    end
    local parent = inst.Parent
    if parent then
        local ok, res = pcall(function()
            return parent:GetFullName()
        end)
        if ok and res then
            return res
        end
    end
    return State.UtilityLogger.GetInstPath(inst)
end

State.UtilityLogger.GetGroupKey = State.UtilityLogger.GetGroupKey or function(kind, inst, name)
    local base = State.UtilityLogger.GetGroupPath(inst)
    if kind == "ATTR" and name then
        return "ATTR::" .. base
    elseif kind == "VALUE" then
        return "VALUE::" .. base
    end
    return "INFO::System"
end

State.UtilityLogger.GetGroupLabel = State.UtilityLogger.GetGroupLabel or function(kind, inst, name)
    local base = State.UtilityLogger.GetGroupPath(inst)
    if kind == "ATTR" and name then
        return "[ATTR] " .. base
    elseif kind == "VALUE" then
        return "[VALUE] " .. base
    end
    return "[INFO] System"
end

State.UtilityLogger.UpdateGroupCount = State.UtilityLogger.UpdateGroupCount or function(group)
    if group and group.UI and group.UI.Count then
        group.UI.Count.Text = tostring(group.Count or 0)
    end
end

State.UtilityLogger.UpdateGroupOrder = State.UtilityLogger.UpdateGroupOrder or function(group)
    if not group or not group.UI or not group.UI.Container then
        return
    end
    local ts = group.LastUpdate or 0
    local order = math.max(0, 2000000000 - math.floor(ts))
    group.UI.Container.LayoutOrder = order
end

State.UtilityLogger.EnsureHistoryEmptyLabel = State.UtilityLogger.EnsureHistoryEmptyLabel or function(group)
    if not group or not group.UI or not group.UI.HistoryFrame then
        return
    end
    if group.UI.EmptyLabel then
        group.UI.EmptyLabel:Destroy()
        group.UI.EmptyLabel = nil
    end
    if not group.Entries or next(group.Entries) == nil then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 18)
        empty.BackgroundTransparency = 1
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 11
        empty.TextXAlignment = Enum.TextXAlignment.Left
        empty.Text = "Tidak ada history"
        empty.Parent = group.UI.HistoryFrame
        registerTheme(empty, "TextColor3", "Muted")
        group.UI.EmptyLabel = empty
    end
end

State.UtilityLogger.AddHistoryRow = State.UtilityLogger.AddHistoryRow or function(group, entry)
    if not group or not group.UI or not group.UI.HistoryFrame then
        return
    end
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 22)
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Parent = group.UI.HistoryFrame
    registerTheme(row, "BackgroundColor3", "Main")
    addCorner(row, 6)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -8, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    local timeText = entry.Time and os.date("%H:%M:%S", entry.Time) or "--:--:--"
    local valueText = entry.Text ~= nil and tostring(entry.Text) or tostring(entry.Value)
    local nameText = entry.PathSuffix and tostring(entry.PathSuffix) or "Value"
    label.Text = "{" .. tostring(entry.Count or 0) .. "} | " .. timeText .. " | " .. nameText .. " = " .. valueText
    label.Parent = row
    registerTheme(label, "TextColor3", "Text")

    row.MouseButton1Click:Connect(function()
        if not setclipboard then
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
            return
        end
        local basePath = group.Path or ""
        local suffix = entry.PathSuffix or ""
        local fullPath = basePath
        if suffix ~= "" then
            fullPath = basePath .. "." .. suffix
        end
        local text = fullPath .. " = " .. tostring(valueText)
        setclipboard(text)
        notify("Copied", "Entry disalin", 2)
    end)

    group.UI.HistoryRows[#group.UI.HistoryRows + 1] = row
end

State.UtilityLogger.RebuildHistoryList = State.UtilityLogger.RebuildHistoryList or function(group)
    if not group or not group.UI or not group.UI.HistoryFrame then
        return
    end
    if group.UI.HistoryRows then
        for i = #group.UI.HistoryRows, 1, -1 do
            if group.UI.HistoryRows[i] then
                group.UI.HistoryRows[i]:Destroy()
            end
            table.remove(group.UI.HistoryRows, i)
        end
    end
    group.UI.HistoryRows = {}
    State.UtilityLogger.EnsureHistoryEmptyLabel(group)
    if group.Entries then
        local ordered = {}
        for _, entry in pairs(group.Entries) do
            ordered[#ordered + 1] = entry
        end
        table.sort(ordered, function(a, b)
            local at = a.Time or 0
            local bt = b.Time or 0
            if at == bt then
                local an = tostring(a.PathSuffix or "")
                local bn = tostring(b.PathSuffix or "")
                return an < bn
            end
            return at > bt
        end)
        for _, entry in ipairs(ordered) do
            State.UtilityLogger.AddHistoryRow(group, entry)
        end
    end
end

State.UtilityLogger.CreateGroupUI = State.UtilityLogger.CreateGroupUI or function(group)
    local ui = State.UtilityLogger.UI
    if not ui or not ui.Scroll then
        return nil
    end
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BorderSizePixel = 0
    container.BackgroundTransparency = 1
    container.Parent = ui.Scroll

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = container

    local header = Instance.new("TextButton")
    header.Size = UDim2.new(1, 0, 0, 26)
    header.BorderSizePixel = 0
    header.AutoButtonColor = false
    header.Parent = container
    registerTheme(header, "BackgroundColor3", "Main")
    addCorner(header, 6)

    local count = Instance.new("TextLabel")
    count.Size = UDim2.new(0, 28, 1, 0)
    count.Position = UDim2.new(0, 6, 0, 0)
    count.BackgroundTransparency = 1
    count.Font = Enum.Font.GothamSemibold
    count.TextSize = 12
    count.TextXAlignment = Enum.TextXAlignment.Left
    count.Text = tostring(group.Count or 0)
    count.Parent = header
    registerTheme(count, "TextColor3", "Muted")

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -40, 1, 0)
    name.Position = UDim2.new(0, 36, 0, 0)
    name.BackgroundTransparency = 1
    name.Font = Enum.Font.Gotham
    name.TextSize = 12
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Text = group.DisplayName or "Utility"
    name.Parent = header
    registerTheme(name, "TextColor3", "Text")

    local historyFrame = Instance.new("Frame")
    historyFrame.Size = UDim2.new(1, 0, 0, 0)
    historyFrame.AutomaticSize = Enum.AutomaticSize.Y
    historyFrame.BorderSizePixel = 0
    historyFrame.BackgroundTransparency = 1
    historyFrame.Visible = false
    historyFrame.Parent = container

    local historyList = Instance.new("UIListLayout")
    historyList.SortOrder = Enum.SortOrder.LayoutOrder
    historyList.Padding = UDim.new(0, 4)
    historyList.Parent = historyFrame

    local historyPad = Instance.new("UIPadding")
    historyPad.PaddingLeft = UDim.new(0, 8)
    historyPad.PaddingRight = UDim.new(0, 8)
    historyPad.Parent = historyFrame

    header.MouseButton1Click:Connect(function()
        group.Expanded = not group.Expanded
        historyFrame.Visible = group.Expanded
        if group.Expanded then
            State.UtilityLogger.RebuildHistoryList(group)
        end
        if setclipboard then
            local path = group.Path or group.DisplayName or ""
            setclipboard(path)
            notify("Copied", "Group disalin", 2)
        else
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
        end
    end)

    group.UI = {
        Container = container,
        Header = header,
        Count = count,
        Name = name,
        HistoryFrame = historyFrame,
        HistoryRows = {},
        EmptyLabel = nil
    }

    return group.UI
end

State.UtilityLogger.EnsureGroup = State.UtilityLogger.EnsureGroup or function(kind, inst, name)
    local key = State.UtilityLogger.GetGroupKey(kind, inst, name)
    local group = State.UtilityLogger.Groups[key]
    if not group then
        group = {
            Key = key,
            Kind = kind,
            Path = State.UtilityLogger.GetGroupPath(inst),
            DisplayName = State.UtilityLogger.GetGroupLabel(kind, inst, name),
            Entries = {},
            Count = 0,
            Expanded = false,
            LastUpdate = 0,
            UI = nil
        }
        State.UtilityLogger.Groups[key] = group
        State.UtilityLogger.GroupList[#State.UtilityLogger.GroupList + 1] = key
        State.UtilityLogger.GroupRows[key] = State.UtilityLogger.CreateGroupUI(group)
    end
    return group
end

State.UtilityLogger.AddLogEntry = State.UtilityLogger.AddLogEntry or function(kind, inst, name, value, textOverride)
    local group = State.UtilityLogger.EnsureGroup(kind, inst, name)
    if not group then
        return
    end
    group.Count = (group.Count or 0) + 1
    State.UtilityLogger.TotalLogs = (State.UtilityLogger.TotalLogs or 0) + 1
    group.LastUpdate = os.time()
    local entryText = textOverride
    if entryText == nil then
        entryText = (value ~= nil) and tostring(value) or "nil"
    end
    local suffix = nil
    if kind == "VALUE" and inst then
        suffix = inst.Name
    elseif kind == "ATTR" and inst and name then
        suffix = inst.Name .. "." .. tostring(name)
    end
    if suffix then
        group.Entries = group.Entries or {}
        local entry = group.Entries[suffix]
        if not entry then
            entry = {
                PathSuffix = suffix,
                Count = 0
            }
            group.Entries[suffix] = entry
        end
        entry.Count = (entry.Count or 0) + 1
        entry.Time = os.time()
        entry.Value = value
        entry.Text = entryText
    end
    State.UtilityLogger.UpdateGroupCount(group)
    State.UtilityLogger.UpdateGroupOrder(group)
    if group.Expanded then
        State.UtilityLogger.RebuildHistoryList(group)
    end
    if State.UtilityLogger.ApplyFilter then
        State.UtilityLogger.ApplyFilter()
    end
end

State.UtilityLogger.AddLog = State.UtilityLogger.AddLog or function(text)
    State.UtilityLogger.AddLogEntry("INFO", nil, "System", nil, text)
end

State.UtilityLogger.ClearLogs = State.UtilityLogger.ClearLogs or function()
    for _, group in pairs(State.UtilityLogger.Groups) do
        if group and group.UI and group.UI.Container then
            group.UI.Container:Destroy()
        end
    end
    State.UtilityLogger.Groups = {}
    State.UtilityLogger.GroupList = {}
    State.UtilityLogger.GroupRows = {}
    State.UtilityLogger.TotalLogs = 0
end

State.UtilityLogger.MatchSearch = State.UtilityLogger.MatchSearch or function(group)
    local term = tostring(State.UtilityLogger.SearchTerm or "")
    term = string.lower(term)
    if term == "" then
        return true
    end
    if not group then
        return false
    end
    local mode = State.UtilityLogger.SearchMode or "By Path"
    if mode == "By Value" then
        local entries = group.Entries
        if entries then
            for _, entry in pairs(entries) do
                local text = entry and (entry.Text ~= nil and tostring(entry.Text) or tostring(entry.Value)) or ""
                if string.find(string.lower(text), term, 1, true) then
                    return true
                end
            end
        end
        return false
    end

    local name = string.lower(tostring(group.DisplayName or ""))
    if string.find(name, term, 1, true) then
        return true
    end
    local path = string.lower(tostring(group.Path or ""))
    if string.find(path, term, 1, true) then
        return true
    end
    local entries = group.Entries
    if entries then
        for _, entry in pairs(entries) do
            local suffix = entry and entry.PathSuffix or nil
            if suffix and string.find(string.lower(tostring(suffix)), term, 1, true) then
                return true
            end
        end
    end
    return false
end

State.UtilityLogger.ApplyFilter = State.UtilityLogger.ApplyFilter or function()
    for _, key in ipairs(State.UtilityLogger.GroupList or {}) do
        local group = State.UtilityLogger.Groups and State.UtilityLogger.Groups[key] or nil
        if group and group.UI and group.UI.Container then
            group.UI.Container.Visible = State.UtilityLogger.MatchSearch(group)
        end
    end
end

State.UtilityLogger.BuildVisibleLogLines = State.UtilityLogger.BuildVisibleLogLines or function()
    local lines = {}
    for _, key in ipairs(State.UtilityLogger.GroupList or {}) do
        local group = State.UtilityLogger.Groups and State.UtilityLogger.Groups[key] or nil
        if group and group.UI and group.UI.Container and group.UI.Container.Visible then
            local entries = group.Entries
            if entries then
                local ordered = {}
                for _, entry in pairs(entries) do
                    ordered[#ordered + 1] = entry
                end
                table.sort(ordered, function(a, b)
                    local at = a.Time or 0
                    local bt = b.Time or 0
                    if at == bt then
                        local an = tostring(a.PathSuffix or "")
                        local bn = tostring(b.PathSuffix or "")
                        return an < bn
                    end
                    return at > bt
                end)
                for _, entry in ipairs(ordered) do
                    local basePath = group.Path or ""
                    local suffix = entry.PathSuffix or ""
                    local fullPath = basePath
                    if suffix ~= "" then
                        fullPath = basePath .. "." .. suffix
                    end
                    local valueText = entry.Text ~= nil and tostring(entry.Text) or tostring(entry.Value)
                    lines[#lines + 1] = fullPath .. " = " .. valueText
                end
            end
        end
    end
    return lines
end

State.UtilityLogger.CopyVisibleLogs = State.UtilityLogger.CopyVisibleLogs or function()
    if not setclipboard then
        notify("Copy Failed", "setclipboard tidak tersedia", 2)
        return
    end
    local lines = State.UtilityLogger.BuildVisibleLogLines()
    if #lines == 0 then
        notify("Copy Logs", "Tidak ada log untuk disalin", 2)
        return
    end
    setclipboard(table.concat(lines, "\n"))
    notify("Copied", "Log disalin (" .. tostring(#lines) .. ")", 2)
end

State.UtilityLogger.AttachValue = State.UtilityLogger.AttachValue or function(inst)
    if not State.UtilityLogger.TrackValues then
        return
    end
    if not inst or not inst:IsA("ValueBase") then
        return
    end
    if not State.UtilityLogger.Matches(inst.Name, inst, inst.Value) then
        return
    end
    if State.UtilityLogger.Watched[inst] then
        return
    end
    State.UtilityLogger.Watched[inst] = true
    State.UtilityLogger.AddLogEntry("VALUE", inst, nil, inst.Value)
    local conn = inst.Changed:Connect(function()
        State.UtilityLogger.AddLogEntry("VALUE", inst, nil, inst.Value)
    end)
    State.UtilityLogger.Conns[#State.UtilityLogger.Conns + 1] = conn
end

State.UtilityLogger.AttachAttributes = State.UtilityLogger.AttachAttributes or function(inst)
    if not State.UtilityLogger.TrackAttributes then
        return
    end
    if not inst then
        return
    end
    local attrs = inst:GetAttributes()
    for name, _ in pairs(attrs) do
        if State.UtilityLogger.Matches(name, inst, inst:GetAttribute(name)) then
            State.UtilityLogger.WatchedAttr[inst] = State.UtilityLogger.WatchedAttr[inst] or {}
            if not State.UtilityLogger.WatchedAttr[inst][name] then
                State.UtilityLogger.WatchedAttr[inst][name] = true
                State.UtilityLogger.AddLogEntry("ATTR", inst, name, inst:GetAttribute(name))
                local conn = inst:GetAttributeChangedSignal(name):Connect(function()
                    State.UtilityLogger.AddLogEntry("ATTR", inst, name, inst:GetAttribute(name))
                end)
                State.UtilityLogger.Conns[#State.UtilityLogger.Conns + 1] = conn
            end
        end
    end
end

State.UtilityLogger.WatchInstance = State.UtilityLogger.WatchInstance or function(inst)
    if not inst then
        return
    end
    State.UtilityLogger.AttachValue(inst)
    State.UtilityLogger.AttachAttributes(inst)
end

State.UtilityLogger.ScanRoot = State.UtilityLogger.ScanRoot or function(root)
    if not root then
        return
    end
    State.UtilityLogger.WatchInstance(root)
    for _, inst in ipairs(root:GetDescendants()) do
        State.UtilityLogger.WatchInstance(inst)
    end
end

State.UtilityLogger.AttachRoot = State.UtilityLogger.AttachRoot or function(root)
    if not root then
        return
    end
    State.UtilityLogger.ScanRoot(root)
    local conn = root.DescendantAdded:Connect(function(inst)
        State.UtilityLogger.WatchInstance(inst)
    end)
    State.UtilityLogger.RootConns[#State.UtilityLogger.RootConns + 1] = conn
end

State.UtilityLogger.Start = State.UtilityLogger.Start or function()
    State.UtilityLogger.ClearConns()
    if #State.UtilityLogger.Names == 0 then
        State.UtilityLogger.AddLog("[INFO] Isi Track Names terlebih dulu.")
    end
    State.UtilityLogger.AttachRoot(LP)
    State.UtilityLogger.AttachRoot(LP.Character)
    State.UtilityLogger.AttachRoot(LP.PlayerGui)
    local conn = LP.CharacterAdded:Connect(function()
        if State.UtilityLogger.Enabled then
            State.UtilityLogger.AttachRoot(LP.Character)
        end
    end)
    State.UtilityLogger.RootConns[#State.UtilityLogger.RootConns + 1] = conn
end

State.UtilityLogger.Stop = State.UtilityLogger.Stop or function()
    State.UtilityLogger.ClearConns()
end

State.UtilityLogger.Refresh = State.UtilityLogger.Refresh or function()
    if not State.UtilityLogger.Enabled then
        return
    end
    State.UtilityLogger.Start()
end

createParagraph(
    State.DevSections.Utility,
    "Utility Logger",
    "Logger untuk ValueObject/Attribute berdasarkan nama (pakai koma untuk banyak nama)."
)

createInput(State.DevSections.Utility, "Track Names (comma)", "UtilityTrackNames", Config.UtilityTrackNames or "", function(v)
    State.UtilityLogger.Names = State.UtilityLogger.ParseNames(v or "")
    State.UtilityLogger.Refresh()
end)

createDropdown(State.DevSections.Utility, "Match By", "UtilityTrackMode", {"Name", "Full Path", "Value"}, Config.UtilityTrackMode or "Name", function(v)
    State.UtilityLogger.MatchMode = v or "Name"
    State.UtilityLogger.Refresh()
end)

createToggle(State.DevSections.Utility, "Enable Utility Logger", "UtilityLoggerEnabled", Config.UtilityLoggerEnabled, function(v)
    State.UtilityLogger.Enabled = v == true
    if State.UtilityLogger.Enabled then
        State.UtilityLogger.Start()
    else
        State.UtilityLogger.Stop()
    end
end)

createToggle(State.DevSections.Utility, "Track ValueObjects", "UtilityTrackValues", Config.UtilityTrackValues, function(v)
    State.UtilityLogger.TrackValues = v == true
    State.UtilityLogger.Refresh()
end)

createToggle(State.DevSections.Utility, "Track Attributes", "UtilityTrackAttributes", Config.UtilityTrackAttributes, function(v)
    State.UtilityLogger.TrackAttributes = v == true
    State.UtilityLogger.Refresh()
end)

createInput(State.DevSections.Utility, "Search Log", "UtilityLogSearch", Config.UtilityLogSearch or "", function(v)
    State.UtilityLogger.SearchTerm = v or ""
    State.UtilityLogger.ApplyFilter()
end)

createDropdown(State.DevSections.Utility, "Search By", "UtilityLogSearchMode", {"By Path", "By Value"}, Config.UtilityLogSearchMode or "By Path", function(v)
    State.UtilityLogger.SearchMode = v or "By Path"
    State.UtilityLogger.ApplyFilter()
end)

State.UtilityLogger.UI = State.UtilityLogger.UI or {}
local UtilityListUI = State.UI.BuildScrollList(State.DevSections.Utility, {
    Title = "Logs (Value/Attribute) - klik grup untuk history",
    Height = 180,
    TitleClass = "Subheading"
})
State.UtilityLogger.UI.Container = UtilityListUI.Container
State.UtilityLogger.UI.Title = UtilityListUI.Title
State.UtilityLogger.UI.Scroll = UtilityListUI.Scroll
State.UtilityLogger.UI.List = UtilityListUI.List
State.UtilityLogger.UI.Pad = UtilityListUI.Padding

createButton(State.DevSections.Utility, "Clear Logs", function()
    if State.UtilityLogger.ClearLogs then
        State.UtilityLogger.ClearLogs()
    end
end)

createButton(State.DevSections.Utility, "Copy Logs", function()
    if State.UtilityLogger.CopyVisibleLogs then
        State.UtilityLogger.CopyVisibleLogs()
    end
end)

State.UtilityLogger.Names = State.UtilityLogger.ParseNames(Config.UtilityTrackNames or "")
State.UtilityLogger.MatchMode = Config.UtilityTrackMode or "Name"
State.UtilityLogger.SearchTerm = Config.UtilityLogSearch or ""
State.UtilityLogger.SearchMode = Config.UtilityLogSearchMode or "By Path"
if State.UtilityLogger.Enabled then
    State.UtilityLogger.Start()
end

State.TurtleSpy = State.TurtleSpy or {}
State.TurtleSpy.Init = State.TurtleSpy.Init or function(parent)
    local TS = State.TurtleSpy
    TS.Data = TS.Data or {}
    TS.UI = TS.UI or {}

    local data = TS.Data
    local ui = TS.UI

    data.Groups = data.Groups or {}
    data.GroupList = data.GroupList or {}
    data.GroupRows = data.GroupRows or {}
    data.IgnoreList = data.IgnoreList or {}
    data.BlockList = data.BlockList or {}
    data.Unstacked = data.Unstacked or {}
    data.SelectedGroupKey = data.SelectedGroupKey or nil
    data.SelectedHistoryIndex = data.SelectedHistoryIndex or nil

    TS.Enabled = TS.Enabled == true

    local function getThemeText()
        return (Themes[Config.Theme] or Themes.Default).Text
    end

    local function toUnicode(str)
        local codepoints = "utf8.char("
        for _, v in utf8.codes(str) do
            codepoints = codepoints .. v .. ", "
        end
        return codepoints:sub(1, -3) .. ")"
    end

    local function getFullPathOfInstance(instance)
        if not instance then
            return "nil"
        end
        local name = instance.Name
        local head = (#name > 0 and "." .. name) or "['']"

        if not instance.Parent and instance ~= game then
            return head .. " --[[ PARENTED TO NIL OR DESTROYED ]]"
        end

        if instance == game then
            return "game"
        elseif instance == workspace then
            return "workspace"
        else
            local ok, result = pcall(game.GetService, game, instance.ClassName)
            if ok and result then
                head = ':GetService("' .. instance.ClassName .. '")'
            elseif instance == LP then
                head = ".LocalPlayer"
            else
                local nonAlphaNum = name:gsub("[%w_]", "")
                local noPunct = nonAlphaNum:gsub("[%s%p]", "")
                if tonumber(name:sub(1, 1)) or (#nonAlphaNum ~= 0 and #noPunct == 0) then
                    head = '["' .. name:gsub('"', '\\"'):gsub("\\", "\\\\") .. '"]'
                elseif #nonAlphaNum ~= 0 and #noPunct > 0 then
                    head = "[" .. toUnicode(name) .. "]"
                end
            end
        end

        return getFullPathOfInstance(instance.Parent) .. head
    end

    TS.GetFullPath = TS.GetFullPath or getFullPathOfInstance

    local function buildArgsKey(args)
        local ok, res = pcall(function()
            return convertTableToString(args)
        end)
        if ok and type(res) == "string" and #res > 0 then
            return res
        end
        return tostring(args)
    end

    local function getGroupKey(remote, args, direction)
        local base
        if data.Unstacked[remote] then
            base = tostring(remote) .. "::" .. buildArgsKey(args)
        else
            base = tostring(remote)
        end
        local dir = direction or "C2S"
        return dir .. "::" .. base
    end

    local function getCallingScript()
        if type(getcallingscript) == "function" then
            local ok, res = pcall(getcallingscript)
            if ok and res then
                return res
            end
        end
        if type(getfenv) == "function" then
            local ok, env = pcall(getfenv, 0)
            if ok and type(env) == "table" then
                return rawget(env, "script")
            end
        end
        return nil
    end

    local function convertTableToString(args)
        local str = ""
        local index = 1
        local count = 0
        for _ in pairs(args) do
            count = count + 1
        end
        for i, v in pairs(args) do
            if type(i) == "string" then
                str = str .. '["' .. tostring(i) .. '"] = '
            elseif type(i) == "userdata" and typeof(i) ~= "Instance" then
                str = str .. "[" .. typeof(i) .. ".new(" .. tostring(i) .. ")] = "
            elseif type(i) == "userdata" then
                str = str .. "[" .. getFullPathOfInstance(i) .. "] = "
            end
            if v == nil then
                str = str .. "nil"
            elseif typeof(v) == "Instance" then
                str = str .. getFullPathOfInstance(v)
            elseif typeof(v) == "Vector3" then
                str = str .. ("Vector3.new(%s, %s, %s)"):format(tostring(v.X), tostring(v.Y), tostring(v.Z))
            elseif typeof(v) == "CFrame" then
                str = str .. "CFrame.new(" .. tostring(v) .. ")"
            elseif type(v) == "number" or type(v) == "function" then
                str = str .. tostring(v)
            elseif type(v) == "userdata" then
                str = str .. typeof(v) .. ".new(" .. tostring(v) .. ")"
            elseif type(v) == "string" then
                str = str .. [["]] .. v .. [["]]
            elseif type(v) == "table" then
                str = str .. "{"
                str = str .. convertTableToString(v)
                str = str .. "}"
            elseif type(v) == "boolean" then
                str = str .. (v and "true" or "false")
            else
                str = str .. tostring(v)
            end
            if count > 1 and index < count then
                str = str .. ","
            end
            index = index + 1
        end
        return str
    end

    local function setRowColor(row, state)
        if not row or not row.Name then
            return
        end
        if state == "block" then
            row.Name.TextColor3 = Color3.fromRGB(225, 177, 44)
        elseif state == "ignore" then
            row.Name.TextColor3 = Color3.fromRGB(127, 143, 166)
        else
            row.Name.TextColor3 = getThemeText()
        end
    end

    local function makeButtonRow(parentRow)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BorderSizePixel = 0
        row.BackgroundTransparency = 1
        row.Parent = parentRow

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 6)
        layout.Parent = row

        return row
    end

    local function makeRowButton(row, label, onClick)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.5, -3, 1, 0)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.Text = label
        btn.AutoButtonColor = false
        btn.Parent = row
        registerTheme(btn, "BackgroundColor3", "Main")
        registerTheme(btn, "TextColor3", "Text")
        addCorner(btn, 6)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 4)
        pad.PaddingRight = UDim.new(0, 4)
        pad.PaddingTop = UDim.new(0, 2)
        pad.PaddingBottom = UDim.new(0, 2)
        pad.Parent = btn

        local disabled = false

        btn.MouseButton1Click:Connect(function()
            if disabled then
                return
            end
            if onClick then
                onClick()
            end
        end)

        return {
            Button = btn,
            SetEnabled = function(_, enabled)
                disabled = not enabled
                btn.TextTransparency = disabled and 0.4 or 0
            end
        }
    end

    createParagraph(
        parent,
        "TurtleSpy (Remotes)",
        "Adopsi fitur TurtleSpy: daftar remote yang terpanggil, detail args, block/ignore, run/copy, dan Remote Browser."
    )

    createToggle(parent, "Enable Turtle Spy Capture", nil, TS.Enabled, function(v)
        TS.Enabled = v == true
    end)

    ui.ToggleS2C = createToggle(parent, "Data Server to Client", nil, false, function(v)
        if setRemoteHooking then
            setRemoteHooking(v == true)
        end
    end)

    ui.ToggleC2S = createToggle(parent, "Data Client to Server", nil, false, function(v)
        State.RemoteC2SEnabled = v == true
        if State.RemoteC2SEnabled then
            local ok = State.RemoteHooks and State.RemoteHooks.EnsureNamecall and State.RemoteHooks.EnsureNamecall()
            if not ok then
                State.RemoteC2SEnabled = false
                if ui.ToggleC2S and ui.ToggleC2S.Set then
                    ui.ToggleC2S:Set(false)
                end
                notify("C2S", "Namecall hook tidak tersedia.", 3)
            end
        end
    end)

    local function clearBrowserList()
        if ui.BrowserItems then
            for i = #ui.BrowserItems, 1, -1 do
                if ui.BrowserItems[i] and ui.BrowserItems[i].Frame then
                    ui.BrowserItems[i].Frame:Destroy()
                end
                table.remove(ui.BrowserItems, i)
            end
        end
        ui.BrowserItems = {}
    end

    local function refreshBrowserList()
        clearBrowserList()
        local descendants = game:GetDescendants()
        for i = 1, #descendants do
            local inst = descendants[i]
            if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst.ClassName == "UnreliableRemoteEvent" then
                local row = Instance.new("TextButton")
                row.Size = UDim2.new(1, 0, 0, 26)
                row.BorderSizePixel = 0
                row.AutoButtonColor = false
                row.Parent = ui.BrowserScroll
                registerTheme(row, "BackgroundColor3", "Main")
                addCorner(row, 6)

                local name = Instance.new("TextLabel")
                name.Size = UDim2.new(1, -50, 1, 0)
                name.Position = UDim2.new(0, 8, 0, 0)
                name.BackgroundTransparency = 1
                name.Font = Enum.Font.Gotham
                name.TextSize = 12
                name.TextXAlignment = Enum.TextXAlignment.Left
                name.Text = inst.Name
                name.Parent = row
                registerTheme(name, "TextColor3", "Text")

                local kind = Instance.new("TextLabel")
                kind.Size = UDim2.new(0, 42, 1, 0)
                kind.Position = UDim2.new(1, -46, 0, 0)
                kind.BackgroundTransparency = 1
                kind.Font = Enum.Font.GothamSemibold
                kind.TextSize = 10
                kind.TextXAlignment = Enum.TextXAlignment.Right
                kind.Text = inst:IsA("RemoteFunction") and "RF" or "RE"
                kind.Parent = row
                registerTheme(kind, "TextColor3", "Muted")

                row.MouseButton1Click:Connect(function()
                    local method = inst:IsA("RemoteFunction") and ":InvokeServer()" or ":FireServer()"
                    local path = getFullPathOfInstance(inst) .. method
                    if setclipboard then
                        setclipboard(path)
                        notify("Remote Browser", "Path disalin", 2)
                    else
                        notify("Copy Failed", "setclipboard tidak tersedia", 2)
                    end
                end)

                ui.BrowserItems[#ui.BrowserItems + 1] = {Frame = row}
            end
        end
    end

    local function copyAllRemotesGrouped()
        local events = {}
        local funcs = {}
        local descendants = game:GetDescendants()
        for i = 1, #descendants do
            local inst = descendants[i]
            if inst:IsA("RemoteFunction") then
                funcs[#funcs + 1] = inst
            elseif inst:IsA("RemoteEvent") or inst.ClassName == "UnreliableRemoteEvent" then
                events[#events + 1] = inst
            end
        end

        local lines = {}
        lines[#lines + 1] = "RemoteEvent:"
        if #events == 0 then
            lines[#lines + 1] = "(kosong)"
        else
            table.sort(events, function(a, b)
                return tostring(a:GetFullName()) < tostring(b:GetFullName())
            end)
            for _, inst in ipairs(events) do
                lines[#lines + 1] = getFullPathOfInstance(inst) .. ":FireServer()"
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "RemoteFunction:"
        if #funcs == 0 then
            lines[#lines + 1] = "(kosong)"
        else
            table.sort(funcs, function(a, b)
                return tostring(a:GetFullName()) < tostring(b:GetFullName())
            end)
            for _, inst in ipairs(funcs) do
                lines[#lines + 1] = getFullPathOfInstance(inst) .. ":InvokeServer()"
            end
        end

        if setclipboard then
            setclipboard(table.concat(lines, "\n"))
            notify("Remote Browser", "Copy All grouped berhasil", 2)
        else
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
        end
    end

    local listContainer = createContainer(parent, 220)
    ui.ListContainer = listContainer
    ui.ListTitle = Instance.new("TextLabel")
    ui.ListTitle.Size = UDim2.new(1, 0, 0, 18)
    ui.ListTitle.BackgroundTransparency = 1
    ui.ListTitle.Font = Enum.Font.GothamSemibold
    ui.ListTitle.TextSize = 12
    ui.ListTitle.TextXAlignment = Enum.TextXAlignment.Left
    ui.ListTitle.Text = "Captured Remotes (klik grup untuk history)"
    ui.ListTitle.Parent = listContainer
    registerTheme(ui.ListTitle, "TextColor3", "Text")

    ui.ListScroll = Instance.new("ScrollingFrame")
    ui.ListScroll.Size = UDim2.new(1, 0, 1, -22)
    ui.ListScroll.Position = UDim2.new(0, 0, 0, 20)
    ui.ListScroll.BorderSizePixel = 0
    ui.ListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ui.ListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ui.ListScroll.ScrollBarThickness = 6
    ui.ListScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    ui.ListScroll.ClipsDescendants = true
    ui.ListScroll.Parent = listContainer
    registerTheme(ui.ListScroll, "BackgroundColor3", "Panel")

    ui.ListLayout = Instance.new("UIListLayout")
    ui.ListLayout.Padding = UDim.new(0, 6)
    ui.ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ui.ListLayout.Parent = ui.ListScroll

    trackConnection(ui.ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ui.ListScroll.CanvasSize = UDim2.new(0, 0, 0, ui.ListLayout.AbsoluteContentSize.Y + 12)
    end))

    ui.ListPad = Instance.new("UIPadding")
    ui.ListPad.PaddingTop = UDim.new(0, 6)
    ui.ListPad.PaddingBottom = UDim.new(0, 6)
    ui.ListPad.PaddingLeft = UDim.new(0, 6)
    ui.ListPad.PaddingRight = UDim.new(0, 6)
    ui.ListPad.Parent = ui.ListScroll

    local function createListSection(labelText)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 18)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamSemibold
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = labelText
        label.Parent = ui.ListScroll
        registerTheme(label, "TextColor3", "Muted")

        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 0)
        container.AutomaticSize = Enum.AutomaticSize.Y
        container.BorderSizePixel = 0
        container.BackgroundTransparency = 1
        container.Parent = ui.ListScroll

        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 6)
        layout.Parent = container

        return {
            Label = label,
            Container = container
        }
    end

    ui.ListSectionS2C = createListSection("S2C (Server to Client)")

    local listDivider = Instance.new("Frame")
    listDivider.Size = UDim2.new(1, 0, 0, 1)
    listDivider.BorderSizePixel = 0
    listDivider.Parent = ui.ListScroll
    registerTheme(listDivider, "BackgroundColor3", "Muted")
    ui.ListSectionDivider = listDivider

    ui.ListSectionC2S = createListSection("C2S (Client to Server)")

    local detailContainer = createContainer(parent, 320)
    ui.DetailContainer = detailContainer
    ui.DetailTitle = Instance.new("TextLabel")
    ui.DetailTitle.Size = UDim2.new(1, 0, 0, 18)
    ui.DetailTitle.BackgroundTransparency = 1
    ui.DetailTitle.Font = Enum.Font.GothamSemibold
    ui.DetailTitle.TextSize = 12
    ui.DetailTitle.TextXAlignment = Enum.TextXAlignment.Left
    ui.DetailTitle.Text = "Detail Remote"
    ui.DetailTitle.Parent = detailContainer
    registerTheme(ui.DetailTitle, "TextColor3", "Text")

    ui.CodeScroll = Instance.new("ScrollingFrame")
    ui.CodeScroll.Size = UDim2.new(1, 0, 0, 60)
    ui.CodeScroll.Position = UDim2.new(0, 0, 0, 22)
    ui.CodeScroll.BorderSizePixel = 0
    ui.CodeScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ui.CodeScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
    ui.CodeScroll.ScrollBarThickness = 6
    ui.CodeScroll.ScrollingDirection = Enum.ScrollingDirection.X
    ui.CodeScroll.ClipsDescendants = true
    ui.CodeScroll.Parent = detailContainer
    registerTheme(ui.CodeScroll, "BackgroundColor3", "Panel")

    ui.CodeLabel = Instance.new("TextLabel")
    ui.CodeLabel.Size = UDim2.new(0, 0, 1, 0)
    ui.CodeLabel.AutomaticSize = Enum.AutomaticSize.X
    ui.CodeLabel.BackgroundTransparency = 1
    local okFont, codeFont = pcall(function()
        return Enum.Font.Code
    end)
    ui.CodeLabel.Font = okFont and codeFont or Enum.Font.Gotham
    ui.CodeLabel.TextSize = 12
    ui.CodeLabel.TextXAlignment = Enum.TextXAlignment.Left
    ui.CodeLabel.TextYAlignment = Enum.TextYAlignment.Top
    ui.CodeLabel.Text = "Pilih remote untuk melihat detail."
    ui.CodeLabel.Parent = ui.CodeScroll
    registerTheme(ui.CodeLabel, "TextColor3", "Text")

    local detailButtons = Instance.new("Frame")
    detailButtons.Size = UDim2.new(1, 0, 0, 210)
    detailButtons.Position = UDim2.new(0, 0, 0, 90)
    detailButtons.BorderSizePixel = 0
    detailButtons.BackgroundTransparency = 1
    detailButtons.Parent = detailContainer

    local detailLayout = Instance.new("UIListLayout")
    detailLayout.Padding = UDim.new(0, 6)
    detailLayout.SortOrder = Enum.SortOrder.LayoutOrder
    detailLayout.Parent = detailButtons

    local row1 = makeButtonRow(detailButtons)
    local btnCopyCode = makeRowButton(row1, "Copy Code", function() end)
    local btnRunCode = makeRowButton(row1, "Run Code", function() end)

    local row2 = makeButtonRow(detailButtons)
    local btnCopyScript = makeRowButton(row2, "Copy Script Path", function() end)
    local btnCopyDecompile = makeRowButton(row2, "Copy Decompiled", function() end)

    local row3 = makeButtonRow(detailButtons)
    local btnIgnore = makeRowButton(row3, "Ignore Remote", function() end)
    local btnBlock = makeRowButton(row3, "Block Remote", function() end)

    local row4 = makeButtonRow(detailButtons)
    local btnWhile = makeRowButton(row4, "While Loop", function() end)
    local btnCopyReturn = makeRowButton(row4, "Copy Return", function() end)

    local row5 = makeButtonRow(detailButtons)
    local btnUnstack = makeRowButton(row5, "Unstack Remote", function() end)
    local btnClearHistory = makeRowButton(row5, "Clear History", function() end)

    local row6 = makeButtonRow(detailButtons)
    local btnClearAll = makeRowButton(row6, "Clear All Captured", function() end)

    local browserContainer = createContainer(parent, 180)
    ui.BrowserContainer = browserContainer
    ui.BrowserTitle = Instance.new("TextLabel")
    ui.BrowserTitle.Size = UDim2.new(1, 0, 0, 18)
    ui.BrowserTitle.BackgroundTransparency = 1
    ui.BrowserTitle.Font = Enum.Font.GothamSemibold
    ui.BrowserTitle.TextSize = 12
    ui.BrowserTitle.TextXAlignment = Enum.TextXAlignment.Left
    ui.BrowserTitle.Text = "Remote Browser (klik untuk copy path)"
    ui.BrowserTitle.Parent = browserContainer
    registerTheme(ui.BrowserTitle, "TextColor3", "Text")

    ui.BrowserScroll = Instance.new("ScrollingFrame")
    ui.BrowserScroll.Size = UDim2.new(1, 0, 1, -22)
    ui.BrowserScroll.Position = UDim2.new(0, 0, 0, 20)
    ui.BrowserScroll.BorderSizePixel = 0
    ui.BrowserScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ui.BrowserScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ui.BrowserScroll.ScrollBarThickness = 6
    ui.BrowserScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    ui.BrowserScroll.ClipsDescendants = true
    ui.BrowserScroll.Parent = browserContainer
    registerTheme(ui.BrowserScroll, "BackgroundColor3", "Panel")

    ui.BrowserList = Instance.new("UIListLayout")
    ui.BrowserList.Padding = UDim.new(0, 6)
    ui.BrowserList.SortOrder = Enum.SortOrder.LayoutOrder
    ui.BrowserList.Parent = ui.BrowserScroll

    trackConnection(ui.BrowserList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ui.BrowserScroll.CanvasSize = UDim2.new(0, 0, 0, ui.BrowserList.AbsoluteContentSize.Y + 12)
    end))

    ui.BrowserPad = Instance.new("UIPadding")
    ui.BrowserPad.PaddingTop = UDim.new(0, 6)
    ui.BrowserPad.PaddingBottom = UDim.new(0, 6)
    ui.BrowserPad.PaddingLeft = UDim.new(0, 6)
    ui.BrowserPad.PaddingRight = UDim.new(0, 6)
    ui.BrowserPad.Parent = ui.BrowserScroll

    createButton(parent, "Refresh Remote Browser", function()
        refreshBrowserList()
    end)

    createButton(parent, "Copy All (Grouped)", function()
        copyAllRemotesGrouped()
    end)

    local function clearAllCaptured()
        for i = #data.GroupList, 1, -1 do
            local key = data.GroupList[i]
            local group = data.Groups[key]
            if group and group.UI and group.UI.Container then
                group.UI.Container:Destroy()
            end
            table.remove(data.GroupList, i)
        end
        data.Groups = {}
        data.GroupRows = {}
        ui.CodeLabel.Text = "Pilih remote untuk melihat detail."
        ui.DetailTitle.Text = "Detail Remote"
        data.SelectedGroupKey = nil
        data.SelectedHistoryIndex = nil
        updateDetailButtons(nil)
    end

    btnClearAll.Button.MouseButton1Click:Connect(function()
        clearAllCaptured()
    end)

    local function updateDetailButtons(remote, entry)
        local isFunc = remote and remote:IsA("RemoteFunction")
        local method = entry and entry.Method
        local isClientSignal = method == "OnClientEvent" or method == "OnClientInvoke"
        btnCopyReturn:SetEnabled(isFunc and not isClientSignal)
        btnRunCode:SetEnabled(remote ~= nil and not isClientSignal)
        btnCopyCode:SetEnabled(remote ~= nil)
        btnCopyScript:SetEnabled(remote ~= nil)
        btnCopyDecompile:SetEnabled(remote ~= nil)
        btnIgnore:SetEnabled(remote ~= nil)
        btnBlock:SetEnabled(remote ~= nil)
        btnWhile:SetEnabled(remote ~= nil and not isClientSignal)
        btnUnstack:SetEnabled(remote ~= nil)
        btnClearHistory:SetEnabled(remote ~= nil)
    end

    local function setDetail(groupKey, historyIndex)
        local group = data.Groups[groupKey]
        if not group then
            return
        end
        local entry = group.History and group.History[historyIndex]
        if not entry then
            return
        end
        local remote = group.Remote
        if not remote then
            return
        end
        data.SelectedGroupKey = groupKey
        data.SelectedHistoryIndex = historyIndex
        local methodLabel = entry.Method or (remote:IsA("RemoteFunction") and "InvokeServer" or "FireServer")
        local codeText
        if methodLabel == "OnClientEvent" then
            codeText = getFullPathOfInstance(remote) .. ".OnClientEvent (args = {" .. convertTableToString(entry.Args or {}) .. "})"
        elseif methodLabel == "OnClientInvoke" then
            codeText = getFullPathOfInstance(remote) .. ".OnClientInvoke (args = {" .. convertTableToString(entry.Args or {}) .. "})"
        else
            codeText = getFullPathOfInstance(remote) .. ":" .. methodLabel .. "(" .. convertTableToString(entry.Args or {}) .. ")"
        end
        ui.DetailTitle.Text = "Detail: " .. tostring(remote.Name)
        ui.CodeLabel.Text = codeText
        ui.CodeScroll.CanvasSize = UDim2.new(0, ui.CodeLabel.TextBounds.X + 12, 0, 0)

        if data.BlockList[remote] then
            btnBlock.Button.Text = "Unblock Remote"
            btnBlock.Button.TextColor3 = Color3.fromRGB(251, 197, 49)
        else
            btnBlock.Button.Text = "Block Remote"
            btnBlock.Button.TextColor3 = (Themes[Config.Theme] or Themes.Default).Text
        end

        if data.IgnoreList[remote] then
            btnIgnore.Button.Text = "Stop Ignore"
            btnIgnore.Button.TextColor3 = Color3.fromRGB(127, 143, 166)
        else
            btnIgnore.Button.Text = "Ignore Remote"
            btnIgnore.Button.TextColor3 = (Themes[Config.Theme] or Themes.Default).Text
        end

        if data.Unstacked[remote] then
            btnUnstack.Button.Text = "Stack Remote"
            btnUnstack.Button.TextColor3 = Color3.fromRGB(251, 197, 49)
        else
            btnUnstack.Button.Text = "Unstack Remote"
            btnUnstack.Button.TextColor3 = (Themes[Config.Theme] or Themes.Default).Text
        end

        updateDetailButtons(remote, entry)
    end

    local function getSelectedEntry()
        local key = data.SelectedGroupKey
        local idx = data.SelectedHistoryIndex
        if not key or not idx then
            return nil, nil
        end
        local group = data.Groups[key]
        if not group then
            return nil, nil
        end
        local entry = group.History and group.History[idx]
        if not entry then
            return nil, nil
        end
        return group, entry
    end

    btnCopyCode.Button.MouseButton1Click:Connect(function()
        local group, entry = getSelectedEntry()
        if not group or not entry then
            return
        end
        if setclipboard then
            setclipboard(ui.CodeLabel.Text)
            notify("Copied", "Code disalin", 2)
        else
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
        end
    end)

    btnRunCode.Button.MouseButton1Click:Connect(function()
        local group, entry = getSelectedEntry()
        if not group or not entry then
            return
        end
        local remote = group.Remote
        if not remote then
            return
        end
        local args = entry.Args or {}
        if remote:IsA("RemoteFunction") then
            pcall(function()
                remote:InvokeServer(unpack(args))
            end)
        else
            pcall(function()
                remote:FireServer(unpack(args))
            end)
        end
    end)

    btnCopyScript.Button.MouseButton1Click:Connect(function()
        local group, entry = getSelectedEntry()
        if not group or not entry then
            return
        end
        local scriptRef = entry.Script
        if not scriptRef then
            notify("Script", "Script tidak tersedia", 2)
            return
        end
        if setclipboard then
            setclipboard(getFullPathOfInstance(scriptRef))
            notify("Copied", "Script path disalin", 2)
        else
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
        end
    end)

    btnCopyDecompile.Button.MouseButton1Click:Connect(function()
        local group, entry = getSelectedEntry()
        if not group or not entry then
            return
        end
        local scriptRef = entry.Script
        if not scriptRef then
            notify("Decompile", "Script tidak tersedia", 2)
            return
        end
        if type(decompile) ~= "function" then
            notify("Decompile", "Fitur decompile tidak tersedia", 2)
            return
        end
        local ok, res = pcall(function()
            return decompile(scriptRef)
        end)
        if ok and res then
            if setclipboard then
                setclipboard(res)
                notify("Copied", "Decompile disalin", 2)
            else
                notify("Copy Failed", "setclipboard tidak tersedia", 2)
            end
        else
            notify("Decompile", "Gagal decompile", 2)
        end
    end)

    btnIgnore.Button.MouseButton1Click:Connect(function()
        local group = getSelectedEntry()
        if not group then
            return
        end
        local remote = group.Remote
        if not remote then
            return
        end
        if data.IgnoreList[remote] then
            data.IgnoreList[remote] = nil
        else
            data.IgnoreList[remote] = true
        end
        for _, g in pairs(data.Groups) do
            if g.Remote == remote and g.UI and g.UI.Header then
                if data.IgnoreList[remote] then
                    setRowColor(g.UI.Header, "ignore")
                elseif data.BlockList[remote] then
                    setRowColor(g.UI.Header, "block")
                else
                    setRowColor(g.UI.Header, "normal")
                end
            end
        end
        if data.SelectedGroupKey and data.SelectedHistoryIndex then
            setDetail(data.SelectedGroupKey, data.SelectedHistoryIndex)
        end
    end)

    btnBlock.Button.MouseButton1Click:Connect(function()
        local group = getSelectedEntry()
        if not group then
            return
        end
        local remote = group.Remote
        if not remote then
            return
        end
        if data.BlockList[remote] then
            data.BlockList[remote] = nil
        else
            data.BlockList[remote] = true
        end
        for _, g in pairs(data.Groups) do
            if g.Remote == remote and g.UI and g.UI.Header then
                if data.BlockList[remote] then
                    setRowColor(g.UI.Header, "block")
                elseif data.IgnoreList[remote] then
                    setRowColor(g.UI.Header, "ignore")
                else
                    setRowColor(g.UI.Header, "normal")
                end
            end
        end
        if data.SelectedGroupKey and data.SelectedHistoryIndex then
            setDetail(data.SelectedGroupKey, data.SelectedHistoryIndex)
        end
    end)

    btnWhile.Button.MouseButton1Click:Connect(function()
        local group, entry = getSelectedEntry()
        if not group or not entry then
            return
        end
        if setclipboard then
            setclipboard("while task.wait() do\n    " .. ui.CodeLabel.Text .. "\nend")
            notify("Copied", "While loop disalin", 2)
        else
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
        end
    end)

    btnCopyReturn.Button.MouseButton1Click:Connect(function()
        local group, entry = getSelectedEntry()
        if not group or not entry then
            return
        end
        local remote = group.Remote
        local args = entry.Args or {}
        if not (remote and remote:IsA("RemoteFunction")) then
            return
        end
        local ok, res = pcall(function()
            return remote:InvokeServer(unpack(args))
        end)
        if ok then
            if setclipboard then
                setclipboard(convertTableToString(table.pack(res)))
                notify("Copied", "Return value disalin", 2)
            else
                notify("Copy Failed", "setclipboard tidak tersedia", 2)
            end
        else
            notify("Invoke Failed", "Gagal InvokeServer", 2)
        end
    end)

    btnUnstack.Button.MouseButton1Click:Connect(function()
        local group = getSelectedEntry()
        if not group then
            return
        end
        local remote = group.Remote
        if not remote then
            return
        end
        if data.Unstacked[remote] then
            data.Unstacked[remote] = nil
        else
            data.Unstacked[remote] = true
        end
        if data.SelectedGroupKey and data.SelectedHistoryIndex then
            setDetail(data.SelectedGroupKey, data.SelectedHistoryIndex)
        end
    end)

    local function updateGroupCount(group)
        if group and group.UI and group.UI.Count then
            group.UI.Count.Text = tostring(group.Count or 0)
        end
    end

    local function ensureHistoryEmptyLabel(group)
        if not group or not group.UI or not group.UI.HistoryFrame then
            return
        end
        if group.UI.EmptyLabel then
            group.UI.EmptyLabel:Destroy()
            group.UI.EmptyLabel = nil
        end
        if not group.History or #group.History == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 18)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 11
            empty.TextXAlignment = Enum.TextXAlignment.Left
            empty.Text = "Tidak ada history"
            empty.Parent = group.UI.HistoryFrame
            registerTheme(empty, "TextColor3", "Muted")
            group.UI.EmptyLabel = empty
        end
    end

    local function addHistoryRow(group, index, entry)
        if not group or not group.UI or not group.UI.HistoryFrame then
            return
        end
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 22)
        row.BorderSizePixel = 0
        row.AutoButtonColor = false
        row.Parent = group.UI.HistoryFrame
        registerTheme(row, "BackgroundColor3", "Main")
        addCorner(row, 6)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -8, 1, 0)
        label.Position = UDim2.new(0, 8, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        local method = entry.Method or (group.IsEvent and "FireServer" or "InvokeServer")
        local timeText = entry.Time and os.date("%H:%M:%S", entry.Time) or "--:--:--"
        local dir = entry.Direction and (" (" .. tostring(entry.Direction) .. ")") or ""
        label.Text = "#" .. tostring(index) .. " " .. method .. dir .. " | " .. timeText
        label.Parent = row
        registerTheme(label, "TextColor3", "Text")

        row.MouseButton1Click:Connect(function()
            setDetail(group.Key, index)
        end)

        group.UI.HistoryRows[#group.UI.HistoryRows + 1] = row
    end

    local function rebuildHistoryList(group)
        if not group or not group.UI or not group.UI.HistoryFrame then
            return
        end
        if group.UI.HistoryRows then
            for i = #group.UI.HistoryRows, 1, -1 do
                if group.UI.HistoryRows[i] then
                    group.UI.HistoryRows[i]:Destroy()
                end
                table.remove(group.UI.HistoryRows, i)
            end
        end
        group.UI.HistoryRows = {}
        ensureHistoryEmptyLabel(group)
        if group.History then
            for i, entry in ipairs(group.History) do
                addHistoryRow(group, i, entry)
            end
        end
    end

    local function createGroupUI(group)
        local listParent = ui.ListScroll
        if group and group.Direction == "S2C" and ui.ListSectionS2C and ui.ListSectionS2C.Container then
            listParent = ui.ListSectionS2C.Container
        elseif group and group.Direction == "C2S" and ui.ListSectionC2S and ui.ListSectionC2S.Container then
            listParent = ui.ListSectionC2S.Container
        end

        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 0)
        container.AutomaticSize = Enum.AutomaticSize.Y
        container.BorderSizePixel = 0
        container.BackgroundTransparency = 1
        container.Parent = listParent

        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 4)
        layout.Parent = container

        local header = Instance.new("TextButton")
        header.Size = UDim2.new(1, 0, 0, 26)
        header.BorderSizePixel = 0
        header.AutoButtonColor = false
        header.Parent = container
        registerTheme(header, "BackgroundColor3", "Main")
        addCorner(header, 6)

        local count = Instance.new("TextLabel")
        count.Size = UDim2.new(0, 28, 1, 0)
        count.Position = UDim2.new(0, 6, 0, 0)
        count.BackgroundTransparency = 1
        count.Font = Enum.Font.GothamSemibold
        count.TextSize = 12
        count.TextXAlignment = Enum.TextXAlignment.Left
        count.Text = tostring(group.Count or 0)
        count.Parent = header
        registerTheme(count, "TextColor3", "Muted")

        local name = Instance.new("TextLabel")
        name.Size = UDim2.new(1, -74, 1, 0)
        name.Position = UDim2.new(0, 36, 0, 0)
        name.BackgroundTransparency = 1
        name.Font = Enum.Font.Gotham
        name.TextSize = 12
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.Text = group.Remote and group.Remote.Name or "Remote"
        name.Parent = header
        registerTheme(name, "TextColor3", "Text")

        local kind = Instance.new("TextLabel")
        kind.Size = UDim2.new(0, 42, 1, 0)
        kind.Position = UDim2.new(1, -46, 0, 0)
        kind.BackgroundTransparency = 1
        kind.Font = Enum.Font.GothamSemibold
        kind.TextSize = 10
        kind.TextXAlignment = Enum.TextXAlignment.Right
        kind.Text = group.IsEvent and "RE" or "RF"
        kind.Parent = header
        registerTheme(kind, "TextColor3", "Muted")

        local historyFrame = Instance.new("Frame")
        historyFrame.Size = UDim2.new(1, 0, 0, 0)
        historyFrame.AutomaticSize = Enum.AutomaticSize.Y
        historyFrame.BorderSizePixel = 0
        historyFrame.BackgroundTransparency = 1
        historyFrame.Visible = false
        historyFrame.Parent = container

        local historyList = Instance.new("UIListLayout")
        historyList.SortOrder = Enum.SortOrder.LayoutOrder
        historyList.Padding = UDim.new(0, 4)
        historyList.Parent = historyFrame

        local historyPad = Instance.new("UIPadding")
        historyPad.PaddingLeft = UDim.new(0, 8)
        historyPad.PaddingRight = UDim.new(0, 8)
        historyPad.Parent = historyFrame

        header.MouseButton1Click:Connect(function()
            group.Expanded = not group.Expanded
            historyFrame.Visible = group.Expanded
            if group.Expanded then
                rebuildHistoryList(group)
            end
        end)

        group.UI = {
            Container = container,
            Header = {Frame = header, Name = name},
            Count = count,
            Kind = kind,
            HistoryFrame = historyFrame,
            HistoryRows = {},
            EmptyLabel = nil
        }

        return group.UI
    end

    local function clearGroupHistory(group)
        if not group then
            return
        end
        group.History = {}
        group.Count = 0
        updateGroupCount(group)
        if group.UI then
            rebuildHistoryList(group)
        end
        if data.SelectedGroupKey == group.Key then
            data.SelectedHistoryIndex = nil
            ui.CodeLabel.Text = "Pilih remote untuk melihat detail."
            ui.DetailTitle.Text = "Detail Remote"
            updateDetailButtons(nil)
        end
    end

    btnClearHistory.Button.MouseButton1Click:Connect(function()
        local group = getSelectedEntry()
        if not group then
            return
        end
        clearGroupHistory(group)
    end)

    TS.AddToList = TS.AddToList or function(isEvent, remote, args, scriptRef, meta)
        if not TS.Enabled then
            return
        end
        if not remote or typeof(remote) ~= "Instance" then
            return
        end
        if data.IgnoreList[remote] then
            return
        end
        meta = meta or {}
        local methodLabel = meta.Method or (isEvent and "FireServer" or "InvokeServer")
        local direction = meta.Direction or "C2S"
        local key = getGroupKey(remote, args, direction)
        local group = data.Groups[key]
        if not group then
            group = {
                Key = key,
                Remote = remote,
                IsEvent = isEvent,
                Direction = direction,
                History = {},
                Count = 0,
                Expanded = false,
                UI = nil
            }
            data.Groups[key] = group
            data.GroupList[#data.GroupList + 1] = key
            data.GroupRows[key] = createGroupUI(group)
            if data.BlockList[remote] then
                setRowColor(group.UI.Header, "block")
            elseif data.IgnoreList[remote] then
                setRowColor(group.UI.Header, "ignore")
            end
        end

        group.Count = (group.Count or 0) + 1
        table.insert(group.History, {
            Args = args,
            Script = scriptRef,
            Time = os.time(),
            Method = methodLabel,
            Direction = direction
        })
        updateGroupCount(group)

        if group.Expanded then
            rebuildHistoryList(group)
        end
    end

    TS.HandleNamecall = TS.HandleNamecall or function(self, method, args)
        if not TS.Enabled then
            return true
        end
        if typeof(self) ~= "Instance" then
            return true
        end
        local class = self.ClassName
        if method == "FireServer" and (class == "RemoteEvent" or class == "UnreliableRemoteEvent") then
            if data.BlockList[self] and type(checkcaller) == "function" and not checkcaller() then
                return false
            end
            if data.IgnoreList[self] then
                return true
            end
            TS.AddToList(true, self, args, getCallingScript())
        elseif method == "InvokeServer" and class == "RemoteFunction" then
            if data.BlockList[self] and type(checkcaller) == "function" and not checkcaller() then
                return false
            end
            if data.IgnoreList[self] then
                return true
            end
            TS.AddToList(false, self, args, getCallingScript())
        end
        return true
    end

    updateDetailButtons(nil)
end

State.DevSections.TurtleSpy = createSectionBox(DevTab:GetPage(), "TurtleSpy")
State.TurtleSpy.Init(State.DevSections.TurtleSpy)

State.RemoteHooks = State.RemoteHooks or {}
State.RemoteHooks.EnsureNamecall = State.RemoteHooks.EnsureNamecall or function()
    if State.Hooked then
        return true
    end
    if not (hookfunction and getrawmetatable and setreadonly and newcclosure) then
        return false
    end
    local mt = getrawmetatable(game)
    setreadonly(mt, false)

    local old = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if State.RemoteC2SEnabled and NamecallLogHandler then
            local ok, res = pcall(NamecallLogHandler, self, method, args)
            if ok and res == false then
                return nil
            end
        end
        return old(self, ...)
    end)
    State.Mt = mt
    State.OldNamecall = old
    State.Hooked = true
    setreadonly(mt, true)
    return true
end

NamecallLogHandler = function(self, method, args)
    local allow = true
    if allow and State.TurtleSpy and State.TurtleSpy.HandleNamecall then
        local ok, res = pcall(State.TurtleSpy.HandleNamecall, self, method, args)
        if ok and res == false then
            allow = false
        end
    end
    return allow
end

local function hookRemote(obj)
    if obj:IsA("RemoteEvent") or obj.ClassName == "UnreliableRemoteEvent" then
        local conn = obj.OnClientEvent:Connect(function(...)
            if State.TurtleSpy and State.TurtleSpy.AddToList then
                State.TurtleSpy.AddToList(true, obj, {...}, nil, {Method = "OnClientEvent", Direction = "S2C"})
            end
        end)
        State.RemoteConnections[#State.RemoteConnections + 1] = conn
    end
    if obj:IsA("RemoteFunction") then
        if State.RemoteInvokeOld[obj] == nil then
            State.RemoteInvokeOld[obj] = true
        end
        pcall(function()
            obj.OnClientInvoke = function(...)
                if State.TurtleSpy and State.TurtleSpy.AddToList then
                    State.TurtleSpy.AddToList(false, obj, {...}, nil, {Method = "OnClientInvoke", Direction = "S2C"})
                end
            end
        end)
    end
end

setRemoteHooking = function(enabled)
    if enabled then
        if State.RemoteHookEnabled then
            return
        end
        State.RemoteHookEnabled = true
        local descendants = game:GetDescendants()
        local total = #descendants
        for i = 1, total do
            pcall(hookRemote, descendants[i])
        end
        if State.RemoteHookConn then
            State.RemoteHookConn:Disconnect()
        end
        State.RemoteHookConn = game.DescendantAdded:Connect(function(inst)
            pcall(hookRemote, inst)
        end)
        trackConnection(State.RemoteHookConn)
    else
        if not State.RemoteHookEnabled then
            return
        end
        State.RemoteHookEnabled = false
        if State.RemoteHookConn then
            State.RemoteHookConn:Disconnect()
            State.RemoteHookConn = nil
        end
        for _, conn in ipairs(State.RemoteConnections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        State.RemoteConnections = {}
        for obj, oldFn in pairs(State.RemoteInvokeOld) do
            pcall(function()
                if oldFn == true then
                    obj.OnClientInvoke = nil
                else
                    obj.OnClientInvoke = oldFn
                end
            end)
        end
        State.RemoteInvokeOld = {}
    end
end

-- =====================================================

-- =====================================================
-- =====================================================
-- [HEAD] SETTINGS TAB
-- =====================================================
LoadingUI:Set(75, "Menambahkan pengaturan UI...")
local SettingsTab = createTab("Settings")
SettingsTab:CreateSection("UI Settings")

SettingsTab:CreateDropdown({
    Name = "Theme",
    Options = {"Default", "Dark", "Light", "Ocean", "Mint", "Sunset", "Aurora"},
    CurrentOption = "Default",
    Flag = "Theme",
    Callback = function(Theme)
        Config.Theme = Theme
        applyTheme(Theme)
        saveConfig()
    end
})

SettingsTab:CreateDropdown({
    Name = "Font",
    Options = {"ChakraPetch", "Cinzel", "Gotham", "SourceSans", "Arial", "Code", "Roboto", "RobotoMono", "Montserrat", "Oswald", "TitilliumWeb", "Ubuntu", "Nunito"},
    CurrentOption = "ChakraPetch",
    Flag = "Font",
    Callback = function(fontName)
        Config.Font = fontName
        if State.Fonts and State.Fonts.Apply then
            State.Fonts.Apply()
        end
        saveConfig()
    end
})

SettingsTab:CreateSlider({
    Name = "Font Size Scale",
    Range = {0.7, 1.5},
    CurrentValue = Config.FontScale or 1.0,
    Decimals = 2,
    Format = function(v)
        return string.format("%.2fx", v)
    end,
    Callback = function(v)
        Config.FontScale = tonumber(v) or 1.0
        if State.Fonts and State.Fonts.Apply then
            State.Fonts.Apply()
        end
        saveConfig()
    end
})

SettingsTab:CreateSection("Setup General Feautred")
do
    local function applyAutoBuyClickSpeed(v)
        local value = math.clamp(tonumber(v) or 0.6, 0.1, 5)
        Config.AutoBuyClickSpeed = value
        setGlobalClickCooldown("AutoBuyGlobal", value)
        saveConfig()
        return value
    end

    local function applyAutoDepositRequiredMultiplier(v)
        local value = setAutoDepositRequiredMultiplier(v)
        Config.AutoDepositRequiredMultiplier = value
        saveConfig()
        return value
    end

    local AutoBuyClickSlider = SettingsTab:CreateSlider({
        Name = "Auto Buy Click Speed",
        Range = {0.1, 5},
        CurrentValue = Config.AutoBuyClickSpeed or 0.6,
        Decimals = 1,
        Format = function(v)
            return string.format("%.1f sec", v)
        end,
        Callback = function(v)
            applyAutoBuyClickSpeed(v)
        end
    })

    if AutoBuyClickSlider and AutoBuyClickSlider.SetValue then
        AutoBuyClickSlider:SetValue(Config.AutoBuyClickSpeed or 0.6, true)
    end

    local AutoDepositMultiplierSlider = SettingsTab:CreateSlider({
        Name = "Auto Deposit Required Multiplier",
        Range = {0, 30},
        CurrentValue = Config.AutoDepositRequiredMultiplier or 1,
        Decimals = 1,
        Format = function(v)
            return string.format("%.1fx", v)
        end,
        Callback = function(v)
            applyAutoDepositRequiredMultiplier(v)
        end
    })

    if AutoDepositMultiplierSlider and AutoDepositMultiplierSlider.SetValue then
        AutoDepositMultiplierSlider:SetValue(Config.AutoDepositRequiredMultiplier or 1, true)
    end
end

SettingsTab:CreateSection("Keybind")
do
    local keybindState = {}
    local function setupKeybindInput(def)
        if type(def) ~= "table" then
            return
        end
        local flag = def.Flag
        local defaultName = def.Default
        local displayName = def.Name
        keybindState[flag] = keybindState[flag] or {}
        keybindState[flag].Last = State.Keybind.GetName(flag, defaultName)

        local control = nil
        control = SettingsTab:CreateKeybindInput({
            Name = displayName,
            Flag = flag,
            CurrentValue = Config[flag] or defaultName,
            Callback = function(v, isInit)
                if isInit then
                    local normalizedInit = State.Keybind.Normalize(v) or keybindState[flag].Last or defaultName
                    keybindState[flag].Last = normalizedInit
                    if control and control.Set then
                        control:Set(normalizedInit)
                    end
                    return
                end

                local ok, normalized, reason, conflict = State.Keybind.AssignUnique(flag, v, defaultName)
                if ok then
                    keybindState[flag].Last = normalized
                    if control and control.Set then
                        control:Set(normalized)
                    end
                    notify("Keybind", displayName .. " diset ke [" .. tostring(normalized) .. "]", 3)
                    return
                end

                local fallback = keybindState[flag].Last or defaultName
                if control and control.Set then
                    control:Set(fallback)
                end
                if reason == "conflict" and conflict then
                    local conflictLabel = State.Keybind.GetLabel(conflict.Flag, conflict.Label)
                    notify("Keybind", "Key [" .. tostring(normalized) .. "] sudah dipakai oleh " .. tostring(conflictLabel), 4)
                else
                    notify("Keybind", "Key tidak valid. Contoh: K, RightShift, F1", 4)
                end
            end
        })
    end

    setupKeybindInput({Name = "Hide UI", Flag = "HideKeybind", Default = "K"})
    setupKeybindInput({Name = "Auto Buy Log", Flag = "AutoBuyLogKeybind", Default = "["})
    setupKeybindInput({Name = "Auto Clicker", Flag = "ActionAutoClickerKeybind", Default = "G"})
end

updateAutoBuyLogUI()

SettingsTab:CreateSection("Auto Reload")
SettingsTab:CreateParagraph({
    Title = "Info",
    Content = "Gunakan salah satu sumber. Prioritas: Source > URL > File. Fitur ini membutuhkan queue_on_teleport dari executor."
})

local AutoReloadUIReady = false
local function notifyAutoReloadResult(ok, reason)
    if ok then
        notify("Auto Reload", "Queued untuk teleport berikutnya", 3)
        return
    end
    if reason == "missing" then
        notify("Auto Reload", "Sumber script belum diisi", 3)
    elseif reason == "noqueue" then
        notify("Auto Reload", "queue_on_teleport tidak tersedia", 3)
    elseif reason == "disabled" then
        notify("Auto Reload", "Auto Reload masih OFF", 3)
    elseif reason == "file_missing" then
        notify("Auto Reload", "File path tidak ditemukan", 3)
    elseif reason == "file_no_read" then
        notify("Auto Reload", "readfile tidak tersedia", 3)
    elseif reason == "file_read_fail" then
        notify("Auto Reload", "Gagal membaca file", 3)
    end
end

SettingsTab:CreateToggle({
    Name = "Auto Reload on Reconnect",
    Flag = "AutoReloadEnabled",
    CurrentValue = Config.AutoReloadEnabled,
    Callback = function(v)
        if not AutoReloadUIReady then
            return
        end
        if v then
            local ok, reason = applyAutoReloadQueue()
            notifyAutoReloadResult(ok, reason)
        end
    end
})

SettingsTab:CreateInput({
    Name = "Source (raw)",
    Flag = "AutoReloadSource",
    CurrentValue = Config.AutoReloadSource,
    Callback = function()
        if not AutoReloadUIReady then
            return
        end
        if Config.AutoReloadEnabled then
            applyAutoReloadQueue()
        end
    end
})

SettingsTab:CreateInput({
    Name = "URL",
    Flag = "AutoReloadUrl",
    CurrentValue = Config.AutoReloadUrl,
    Callback = function()
        if not AutoReloadUIReady then
            return
        end
        if Config.AutoReloadEnabled then
            applyAutoReloadQueue()
        end
    end
})

SettingsTab:CreateInput({
    Name = "File Path",
    Flag = "AutoReloadFile",
    CurrentValue = Config.AutoReloadFile,
    Callback = function()
        if not AutoReloadUIReady then
            return
        end
        if Config.AutoReloadEnabled then
            applyAutoReloadQueue()
        end
    end
})

SettingsTab:CreateButton({
    Name = "Queue Now (Test)",
    Callback = function()
        local ok, reason = applyAutoReloadQueue()
        notifyAutoReloadResult(ok, reason)
    end
})

AutoReloadUIReady = true

createTabDivider()
State.Tabs = State.Tabs or {}
State.Tabs.RuneLocation = createTab("Fast Teleport")
State.Tabs.Stat = createTab("Stat")
State.Tabs.Action = createTab("Action")

local function createVirtualButtonRow(parent, items)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.BorderSizePixel = 0
    row.Parent = parent
    row.BackgroundTransparency = 1

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = row

    State.GridTextConstraints = State.GridTextConstraints or {}
    State.GridTextScaleApply = State.GridTextScaleApply or function(scale)
        local s = tonumber(scale) or 1
        for _, entry in ipairs(State.GridTextConstraints) do
            local clamp = entry.Clamp
            if clamp and clamp.Parent then
                local maxSize = math.max(6, math.floor(entry.BaseMax * s + 0.5))
                local minSize = math.max(6, math.floor(entry.BaseMin * s + 0.5))
                if maxSize < minSize then
                    minSize = maxSize
                end
                clamp.MaxTextSize = maxSize
                clamp.MinTextSize = minSize
            end
        end
    end

    for _, item in ipairs(items) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1 / 3, -4, 1, 0)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.Text = tostring(item.Label)
        btn.TextScaled = true
        btn.TextWrapped = true
        btn.AutoButtonColor = false
        btn.Parent = row
        registerTheme(btn, "BackgroundColor3", "Main")
        registerTheme(btn, "TextColor3", "Text")
        addCorner(btn, 6)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 4)
        pad.PaddingRight = UDim.new(0, 4)
        pad.PaddingTop = UDim.new(0, 2)
        pad.PaddingBottom = UDim.new(0, 2)
        pad.Parent = btn

        local sizeClamp = Instance.new("UITextSizeConstraint")
        sizeClamp.MinTextSize = 8
        sizeClamp.MaxTextSize = btn.TextSize
        sizeClamp.Parent = btn
        State.GridTextConstraints[#State.GridTextConstraints + 1] = {
            Clamp = sizeClamp,
            BaseMin = sizeClamp.MinTextSize,
            BaseMax = sizeClamp.MaxTextSize
        }
        if State.GridTextScaleApply and MainScale then
            State.GridTextScaleApply(MainScale.Scale)
        end

        btn.MouseButton1Click:Connect(function()
            local list = item and item.Cycle or nil
            if type(list) == "table" and #list > 0 then
                item.Index = (item.Index or 0) + 1
                if item.Index > #list then
                    item.Index = 1
                end
                teleportWithData(list[item.Index])
                return
            end
            teleportWithData(item.Data)
        end)
    end
end

local function createVirtualGrid(parent, list)
    local items = {}
    for i = 1, #list do
        items[#items + 1] = list[i]
        if #items == 3 or i == #list then
            createVirtualButtonRow(parent, items)
            items = {}
        end
    end
end

local function initRuneLocationTab()
    if not State.Tabs or not State.Tabs.RuneLocation then
        return
    end
    if State.RuneLocationInitialized then
        return
    end
    State.RuneLocationInitialized = true

    local tab = State.Tabs.RuneLocation
    local page = tab:GetPage()

    local worldOrder = {
        "Forest",
        "Winter",
        "Desert",
        "Mines",
        "Cyber",
        "Ocean",
        "Mushroom World",
        "Space World",
        "Heaven World",
        "Hell World",
        "500K Event",
        "Halloween",
        "Thanksgiving",
        "3M Event",
        "Christmas Event",
        "5M Event",
        "Valentine Event"
    }

    local function cleanWorldName(name)
        local out = tostring(name or "")
        out = out:gsub("%s*World%s*$", "")
        out = out:gsub("%s*Event%s*$", "")
        return out
    end

    local function isEventWorld(name)
        local n = tostring(name or "")
        if string.find(n, "Event", 1, true) then
            return true
        end
        return n == "Halloween" or n == "Thanksgiving"
    end

    local worldList = {}
    local eventList = {}
    for _, worldName in ipairs(worldOrder) do
        local runeList = State.RuneTeleportData[worldName] or {}
        local baseName = cleanWorldName(worldName)
        local total = #runeList
        for i, item in ipairs(runeList) do
            local suffix = (total > 1) and (" Rune " .. tostring(i)) or " Rune"
            local entry = {
                Label = tostring(baseName) .. suffix,
                Data = item.Data
            }
            if isEventWorld(worldName) then
                eventList[#eventList + 1] = entry
            else
                worldList[#worldList + 1] = entry
            end
        end
    end

    local section = createSectionBox(page, "Rune Teleport")
    local worldSub = createSubSectionBox(section, "World Rune")
    local eventSub = createSubSectionBox(section, "Event Rune")

    if #worldList == 0 then
        createParagraph(worldSub, "World Rune", "Tidak ada rune untuk World.")
    else
        createVirtualGrid(worldSub, worldList)
    end

    if #eventList == 0 then
        createParagraph(eventSub, "Event Rune", "Tidak ada rune untuk Event.")
    else
        createVirtualGrid(eventSub, eventList)
    end

    local potionSection = createSectionBox(page, "Potion Shop")
    local potionList = {
        {Label = "Cyber Shop (Cyber)", Data = makeData(
            Vector3.new(5754.847, 15.482, 2.240),
            CFrame.new(5740.769043, 23.500961, 14.060647, 0.643061757, 0.255947262, -0.721777439, 0.000000000, 0.942496657, 0.334215790, 0.765814364, -0.214921400, 0.606083512),
            CFrame.new(5754.846680, 16.982416, 2.239594, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504065
        )},
        {Label = "Potion Shop (3M)", Data = makeData(
            Vector3.new(-294.845, 15.991, 2070.316),
            CFrame.new(-310.442261, 28.236837, 2065.660645, -0.286014646, 0.527920187, -0.799684823, 0.000000000, 0.834547877, 0.550935388, 0.958225250, 0.157575592, -0.238692909),
            CFrame.new(-294.845215, 17.491394, 2070.316162, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504005
        )},
        {Label = "Trick or Treat", Data = makeData(
            Vector3.new(-1858.588, 24.202, -2152.789),
            CFrame.new(-1880.230103, 36.479126, -2158.660645, -0.261842459, 0.418060958, -0.869864047, 0.000000000, 0.901310205, 0.433174133, 0.965110600, 0.113423377, -0.236001298),
            CFrame.new(-1858.587891, 25.701752, -2152.788818, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880020
        )},
        {Label = "Claim", Data = makeData(
            Vector3.new(-5294.780, 9.663, -30.830),
            CFrame.new(-5306.954102, 17.276363, -30.306751, 0.042931765, 0.447980076, -0.893012166, 0.000000000, 0.893836260, 0.448393494, 0.999077976, -0.019250324, 0.038373969),
            CFrame.new(-5294.779785, 11.163379, -30.829906, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.632911
        )}
    }
    createVirtualGrid(potionSection, potionList)

    local statSection = createSectionBox(page, "Stat Upgrade")
    local statList = {
        {Label = "Ticket Shop (Forest)", Data = makeData(
            Vector3.new(-13.439, 19.201, 85.278),
            CFrame.new(5.131074, 27.627468, 90.108078, 0.251725823, -0.328588486, 0.910309672, 0.000000000, 0.940598249, 0.339521557, -0.967798591, -0.085466340, 0.236772880),
            CFrame.new(-13.439223, 20.701237, 85.277916, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            20.399977
        )},
        {Label = "Passive Shards Shop (Winter)", Data = makeData(
            Vector3.new(1484.535, 18.098, 79.519),
            CFrame.new(1497.478760, 25.320576, 85.072540, 0.394256741, -0.345924526, 0.851409376, 0.000000000, 0.926451564, 0.376413971, -0.919000268, -0.148403749, 0.365259826),
            CFrame.new(1484.534668, 19.597879, 79.519424, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203153
        )},
        {Label = "Sacrifice (Desert)", Data = makeData(
            Vector3.new(2614.331, 14.993, 49.230),
            CFrame.new(2619.790039, 23.690708, 37.002373, -0.913122058, -0.193005964, 0.359105527, 0.000000000, 0.880837977, 0.473417908, -0.407686234, 0.432288349, -0.804312646),
            CFrame.new(2614.330566, 16.493240, 49.230499, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203174
        )},
        {Label = "Milestones (Mines)", Data = makeData(
            Vector3.new(3656.122, 14.492, -9.657),
            CFrame.new(3652.164307, 20.547853, 2.567032, 0.951381981, 0.102941677, -0.290302008, 0.000000000, 0.942498028, 0.334211707, 0.308013380, -0.317963004, 0.896675706),
            CFrame.new(3656.122070, 15.991518, -9.657419, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633096
        )},
        {Label = "Relics (Ocean)", Data = makeData(
            Vector3.new(44.049, 19.477, -2049.437),
            CFrame.new(25.760534, 27.702478, -2050.280029, -0.046050407, 0.344470203, -0.937667131, 0.000000000, 0.938662946, 0.344836026, 0.998939157, 0.015879840, -0.043225810),
            CFrame.new(44.048794, 20.976797, -2049.437012, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503998
        )},
        {Label = "Milestone (Ocean)", Data = makeData(
            Vector3.new(-12.070, 16.224, -1848.307),
            CFrame.new(-10.960073, 22.344925, -1867.223633, -0.998281598, -0.013882399, 0.056931511, 0.000000000, 0.971533477, 0.236902446, -0.058599643, 0.236495346, -0.969863892),
            CFrame.new(-12.070465, 17.724379, -1848.307373, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504034
        )},
        {Label = "Rarities (Space)", Data = makeData(
            Vector3.new(1534.464, 13.743, 2123.736),
            CFrame.new(1536.074341, 21.832954, 2112.384033, -0.990087509, -0.069984615, 0.121773958, 0.000000000, 0.867015183, 0.498281628, -0.140451923, 0.493342429, -0.858420908),
            CFrame.new(1534.463867, 15.243335, 2123.736328, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.224648
        )},
        {Label = "Milestones (Space)", Data = makeData(
            Vector3.new(1308.464, 14.000, 1896.676),
            CFrame.new(1321.018677, 19.640011, 1896.302368, -0.029771226, -0.312925488, 0.949310958, 0.000000000, 0.949731946, 0.313064277, -0.999556720, 0.009320308, -0.028274683),
            CFrame.new(1308.464355, 15.499832, 1896.676270, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.224669
        )},
        {Label = "Milestone (Hell)", Data = makeData(
            Vector3.new(1477.510, 7.417, 3821.921),
            CFrame.new(1482.308716, 17.365757, 3838.832275, 0.962025285, -0.118238114, 0.246022791, 0.000000000, 0.901312768, 0.433169246, -0.272960544, -0.416719764, 0.867085576),
            CFrame.new(1477.510254, 8.917223, 3821.920654, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503996
        )},
        {Label = "Minions (3M)", Data = makeData(
            Vector3.new(-311.161, 16.598, 2046.919),
            CFrame.new(-322.367065, 26.889526, 2058.532227, 0.719588339, 0.332193792, -0.609786689, 0.000000000, 0.878147960, 0.478389114, 0.694400847, -0.344243228, 0.631905079),
            CFrame.new(-311.160583, 18.097818, 2046.919312, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            18.377682
        )},
        {
            Label = "Boss Enemy",
            Cycle = {
                makeData(
                    Vector3.new(-2092.624, 19.919, -2027.826),
                    CFrame.new(-2076.988770, 33.313568, -2052.577881, -0.845453262, -0.201025277, 0.494770318, 0.000000000, 0.926450491, 0.376417011, -0.534049392, 0.318242997, -0.783270597),
                    CFrame.new(-2092.623535, 21.418791, -2027.826416, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    31.600105
                ),
                makeData(
                    Vector3.new(-2217.817, 19.919, -2027.757),
                    CFrame.new(-2211.418213, 29.768099, -2057.554688, -0.977711976, -0.055472907, 0.202489734, 0.000000000, 0.964462817, 0.264218599, -0.209950805, 0.258329690, -0.942966819),
                    CFrame.new(-2217.816895, 21.418791, -2027.756836, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    31.600096
                ),
                makeData(
                    Vector3.new(-2220.480, 19.919, -2260.211),
                    CFrame.new(-2228.719482, 29.595963, -2230.820068, 0.962882936, 0.069847323, -0.260725409, 0.000000000, 0.965938628, 0.258771241, 0.269919187, -0.249166414, 0.930085897),
                    CFrame.new(-2220.480469, 21.418791, -2260.210693, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    31.599941
                ),
                makeData(
                    Vector3.new(-2090.565, 19.734, -2263.877),
                    CFrame.new(-2086.972412, 32.797325, -2234.693604, 0.992502272, -0.044726547, 0.113747679, 0.000000000, 0.930640101, 0.365935594, -0.122225188, -0.363191903, 0.923662603),
                    CFrame.new(-2090.566895, 21.233759, -2263.881348, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    31.600012
                ),
                makeData(
                    Vector3.new(-2165.413, 19.919, -2141.760),
                    CFrame.new(-2171.543213, 40.356079, -2107.064209, 0.984748423, 0.082368985, -0.153250992, 0.000000000, 0.880832613, 0.473427862, 0.173984230, -0.466207355, 0.867398560),
                    CFrame.new(-2165.413086, 21.418962, -2141.760254, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    40.000107
                )
            }
        }
    }
    createVirtualGrid(statSection, statList)
end

local function initStatTab()
    if not State.Tabs or not State.Tabs.Stat then
        return
    end
    if State.StatTabInitialized then
        return
    end
    State.StatTabInitialized = true

    State.StatTab = State.StatTab or {
        RuneRows = {},
        RuneGroups = {},
        RuneSearchQuery = "",
        RuneSearchMode = "Name",
        ProfileRows = {},
        ProfileValues = {},
        RuneRealtime = false,
        ProfileRealtime = false,
        RuneConn = nil,
        ProfileConn = nil,
        RuneAccum = 0,
        ProfileAccum = 0,
        Modifiers = {
            PotionSpeed2x = false,
            PotionLuck2x = false,
            BlackHoleSpeed2x = false,
            BlackHoleLuck10x = false
        }
    }
    local statState = State.StatTab

    local tab = State.Tabs.Stat
    local page = tab:GetPage()
    local profileSection = createSectionBox(page, "Profile Stat")
    local runeSection = createSectionBox(page, "Rune")
    local runePowerRow

    local function normalizePercentText(value)
        local num = tonumber(value)
        if type(num) ~= "number" or num ~= num then
            return "?"
        end
        local out = string.format("%.2f", num)
        out = out:gsub("%.?0+$", "")
        if out == "-0" then
            out = "0"
        end
        return out
    end

    local function formatStatValue(value, isPercent)
        local num = tonumber(value)
        if type(num) ~= "number" or num ~= num then
            return "?"
        end
        if isPercent then
            return normalizePercentText(num) .. "% (" .. tostring(autoBuyLogToSci1(num)) .. ")"
        end
        return tostring(autoBuyLogFormatNumber(num))
    end

    local function formatCompactShort(value)
        local num = tonumber(value)
        if type(num) ~= "number" or num ~= num then
            return "?"
        end
        local absNum = math.abs(num)
        local sign = num < 0 and "-" or ""
        local suffixes = {
            {1e63, "VgDe"},
            {1e60, "NoDe"},
            {1e57, "OcDe"},
            {1e54, "SpDe"},
            {1e51, "SxDe"},
            {1e48, "QnDe"},
            {1e45, "QdDe"},
            {1e42, "Td"},
            {1e39, "Dd"},
            {1e36, "Ud"},
            {1e33, "De"},
            {1e30, "No"},
            {1e27, "Oc"},
            {1e24, "Sp"},
            {1e21, "Sx"},
            {1e18, "Qn"},
            {1e15, "Qd"},
            {1e12, "T"},
            {1e9, "B"},
            {1e6, "M"},
            {1e3, "k"}
        }
        for _, entry in ipairs(suffixes) do
            local base = entry[1]
            local suffix = entry[2]
            if absNum >= base then
                local scaled = absNum / base
                local decimals = 2
                if scaled >= 100 then
                    decimals = 0
                elseif scaled >= 10 then
                    decimals = 1
                end
                local out = string.format("%." .. tostring(decimals) .. "f", scaled):gsub("%.?0+$", "")
                return sign .. out .. suffix
            end
        end
        local decimals = 2
        if absNum >= 100 then
            decimals = 0
        elseif absNum >= 10 then
            decimals = 1
        end
        local out = string.format("%." .. tostring(decimals) .. "f", absNum):gsub("%.?0+$", "")
        return sign .. out
    end

    local function formatTimeChance(seconds)
        local s = tonumber(seconds)
        if type(s) ~= "number" or s ~= s or s == math.huge or s <= 0 then
            return "--"
        end
        if s < 0.01 then
            return "<0.01s"
        end
        if s < 60 then
            return string.format("%.2fs", s):gsub("%.?0+s$", "s")
        end
        local minutes = math.floor(s / 60)
        local remainingSeconds = math.floor(s % 60)
        if minutes < 60 then
            return tostring(minutes) .. "m " .. tostring(remainingSeconds) .. "s"
        end
        local hours = math.floor(minutes / 60)
        local remainingMinutes = minutes % 60
        if hours < 24 then
            return tostring(hours) .. "h " .. tostring(remainingMinutes) .. "m"
        end
        local days = math.floor(hours / 24)
        local remainingHours = hours % 24
        if days < 365 then
            return tostring(days) .. "d " .. tostring(remainingHours) .. "h"
        end
        return tostring(math.floor(days / 365)) .. "y " .. tostring(days % 365) .. "d"
    end

    local function formatPowerValue(value)
        if type(value) ~= "number" or value ~= value then
            return "--"
        end
        return tostring(autoBuyLogFormatNumber(value))
    end

    local function resolveRuneDifficulty(seconds)
        local s = tonumber(seconds)
        if type(s) ~= "number" or s ~= s or s == math.huge or s <= 0 then
            return nil
        end
        local tiers = {
            {5, "Instant", Color3.fromRGB(22, 163, 74), Color3.fromRGB(255, 255, 255)},
            {60, "Very Easy", Color3.fromRGB(74, 222, 128), Color3.fromRGB(11, 31, 18)},
            {600, "Easy", Color3.fromRGB(163, 230, 53), Color3.fromRGB(18, 36, 10)},
            {1800, "Medium", Color3.fromRGB(250, 204, 21), Color3.fromRGB(33, 26, 0)},
            {3600, "Hard", Color3.fromRGB(249, 115, 22), Color3.fromRGB(40, 16, 0)},
            {14400, "Very Hard", Color3.fromRGB(239, 68, 68), Color3.fromRGB(255, 255, 255)},
            {43200, "Extreme", Color3.fromRGB(185, 28, 28), Color3.fromRGB(255, 255, 255)},
            {86400, "Brutal", Color3.fromRGB(127, 29, 29), Color3.fromRGB(255, 255, 255)}
        }
        for _, tier in ipairs(tiers) do
            if s < tier[1] then
                return {
                    Label = tier[2],
                    Bg = tier[3],
                    Text = tier[4]
                }
            end
        end
        return {
            Label = "Impossible",
            Bg = Color3.fromRGB(17, 24, 39),
            Text = Color3.fromRGB(255, 255, 255)
        }
    end

    local function chancePercentToOneIn(chancePercent)
        local c = tonumber(chancePercent)
        if type(c) ~= "number" or c ~= c or c <= 0 then
            return nil
        end
        return 100 / c
    end

    local function resolveCaseInsensitive(parent, name)
        if not parent or type(name) ~= "string" or #name == 0 then
            return nil
        end
        local direct = parent:FindFirstChild(name)
        if direct then
            return direct
        end
        local target = string.lower(name)
        for _, child in ipairs(parent:GetChildren()) do
            if string.lower(tostring(child.Name)) == target then
                return child
            end
        end
        return nil
    end

    local function getNodeNumberByPath(pathNames)
        if not LP or type(pathNames) ~= "table" then
            return nil
        end
        local node = LP
        for _, name in ipairs(pathNames) do
            node = resolveCaseInsensitive(node, tostring(name))
            if not node then
                return nil
            end
        end
        return autoBuyLogReadNumeric(node)
    end

    local function createValueRow(parent, titleText)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BorderSizePixel = 0
        row.Parent = parent
        registerTheme(row, "BackgroundColor3", "Main")
        addCorner(row, 6)
        addStroke(row, "Muted", 1, 0.6)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -12, 0, 16)
        title.Position = UDim2.new(0, 6, 0, 2)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.Gotham
        title.TextSize = 11
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextYAlignment = Enum.TextYAlignment.Top
        title.Text = tostring(titleText)
        title.Parent = row
        setFontClass(title, "Small")
        registerTheme(title, "TextColor3", "Text")

        local value = Instance.new("TextLabel")
        value.Size = UDim2.new(1, -12, 0, 14)
        value.Position = UDim2.new(0, 6, 0, 18)
        value.BackgroundTransparency = 1
        value.Font = Enum.Font.Gotham
        value.TextSize = 9
        value.TextXAlignment = Enum.TextXAlignment.Left
        value.TextYAlignment = Enum.TextYAlignment.Top
        value.Text = "-"
        value.Parent = row
        setFontClass(value, "Tiny")
        registerTheme(value, "TextColor3", "Muted")

        return {
            Row = row,
            Title = title,
            Value = value
        }
    end

    local applyRuneFilter
    local function setRuneSearchQuery(value)
        statState.RuneSearchQuery = tostring(value or "")
        if type(applyRuneFilter) == "function" then
            applyRuneFilter()
        end
    end

    local runeSearchInput = createInput(runeSection, "Search Rune", nil, statState.RuneSearchQuery or "", function(v)
        setRuneSearchQuery(v)
    end)
    if runeSearchInput and runeSearchInput.Box and runeSearchInput.Box.GetPropertyChangedSignal then
        trackConnection(runeSearchInput.Box:GetPropertyChangedSignal("Text"):Connect(function()
            setRuneSearchQuery(runeSearchInput.Box.Text)
        end))
    end

    local function setRuneSearchMode(value)
        local v = tostring(value or "Name")
        if v ~= "Name" and v ~= "Difficulty" then
            v = "Name"
        end
        statState.RuneSearchMode = v
        if type(applyRuneFilter) == "function" then
            applyRuneFilter()
        end
    end

    createDropdown(runeSection, "Search By", nil, {"Name", "Difficulty"}, statState.RuneSearchMode or "Name", function(v)
        setRuneSearchMode(v)
    end)

    createParagraph(
        runeSection,
        "Info Difficulty",
        "Daftar difficulty: Instant, Very Easy, Easy, Medium, Hard, Very Hard, Extreme, Brutal, Impossible."
    )

    runePowerRow = createValueRow(runeSection, "Rune Power")

    local profileDefs = {
        {Key = "Rune Bulk", Path = {"Currency", "Rune Bulk", "TotalMultiplier"}, IsPercent = false},
        {Key = "Rune Luck", Path = {"Currency", "Rune Luck", "TotalMultiplier"}, IsPercent = false},
        {Key = "Rune Speed", Path = {"Currency", "Rune Speed", "TotalMultiplier"}, IsPercent = false},
        {Key = "Rune Clone", Path = {"Currency", "Rune Clone", "TotalMultiplier"}, IsPercent = false},
        {Key = "Rune Clone Chance", Path = {"Currency", "Rune Clone Chance", "TotalMultiplier"}, IsPercent = true}
    }

    for _, def in ipairs(profileDefs) do
        statState.ProfileRows[def.Key] = createValueRow(profileSection, def.Key)
    end

    local refreshRuneRows

    local function refreshProfileStats()
        for _, def in ipairs(profileDefs) do
            local row = statState.ProfileRows[def.Key]
            local rawValue = getNodeNumberByPath(def.Path)
            statState.ProfileValues[def.Key] = rawValue
            if row and row.Value and row.Value.Parent then
                row.Value.Text = formatStatValue(rawValue, def.IsPercent == true)
            end
        end
        if type(refreshRuneRows) == "function" then
            refreshRuneRows(false)
        end
    end

    local function setProfileRealtimeEnabled(enabled)
        local v = enabled == true
        statState.ProfileRealtime = v
        if not v then
            if statState.ProfileConn then
                statState.ProfileConn:Disconnect()
                statState.ProfileConn = nil
            end
            statState.ProfileAccum = 0
            return
        end
        if statState.ProfileConn then
            return
        end
        statState.ProfileConn = RunService.Heartbeat:Connect(function(dt)
            statState.ProfileAccum += dt
            if statState.ProfileAccum < 0.35 then
                return
            end
            statState.ProfileAccum = 0
            refreshProfileStats()
        end)
        trackConnection(statState.ProfileConn)
    end

    createButton(profileSection, "Refresh Stat", function()
        refreshProfileStats()
    end)
    createToggle(profileSection, "Realtime Profile Stat", nil, false, function(v)
        setProfileRealtimeEnabled(v == true)
    end)

    local multiplierSection = createSubSectionBox(profileSection, "Multipliers")
    createToggle(multiplierSection, "Potion 2x Speed", nil, statState.Modifiers.PotionSpeed2x == true, function(v)
        statState.Modifiers.PotionSpeed2x = v == true
        if type(refreshRuneRows) == "function" then
            refreshRuneRows(false)
        end
    end)
    createToggle(multiplierSection, "Potion 2x Luck", nil, statState.Modifiers.PotionLuck2x == true, function(v)
        statState.Modifiers.PotionLuck2x = v == true
        if type(refreshRuneRows) == "function" then
            refreshRuneRows(false)
        end
    end)
    createToggle(multiplierSection, "Black Hole Speed 2x", nil, statState.Modifiers.BlackHoleSpeed2x == true, function(v)
        statState.Modifiers.BlackHoleSpeed2x = v == true
        if type(refreshRuneRows) == "function" then
            refreshRuneRows(false)
        end
    end)
    createToggle(multiplierSection, "Black Hole Luck 10x", nil, statState.Modifiers.BlackHoleLuck10x == true, function(v)
        statState.Modifiers.BlackHoleLuck10x = v == true
        if type(refreshRuneRows) == "function" then
            refreshRuneRows(false)
        end
    end)
    refreshProfileStats()

    local function getRuneModuleData()
        local ok, moduleScript = pcall(function()
            return game:GetService("ReplicatedStorage").Shared.Modules.RuneModule
        end)
        if not ok or not moduleScript or not moduleScript:IsA("ModuleScript") then
            return nil
        end
        local okReq, data = pcall(require, moduleScript)
        if not okReq or type(data) ~= "table" then
            return nil
        end
        if type(data.Runes) ~= "table" then
            return nil
        end
        return data.Runes
    end

    local runeData = getRuneModuleData()
    if type(runeData) ~= "table" then
        createParagraph(runeSection, "Rune Data", "Gagal membaca ReplicatedStorage.Shared.Modules.RuneModule")
    else
        local groups = {}
        for groupName, groupInfo in pairs(runeData) do
            if type(groupName) == "string" and type(groupInfo) == "table" and type(groupInfo.Runes) == "table" then
                local isGlobalRune = tostring(groupName):match("^%s*Global%s+Rune") ~= nil
                local isShopGroup = (groupInfo.Category == "Shop") or (groupInfo.Shop == true)
                if not isGlobalRune and not isShopGroup then
                    groups[#groups + 1] = {
                        Name = groupName,
                        Data = groupInfo
                    }
                end
            end
        end
        table.sort(groups, function(a, b)
            local oa = tonumber(a.Data and a.Data.Order) or 9999
            local ob = tonumber(b.Data and b.Data.Order) or 9999
            if oa == ob then
                return tostring(a.Name) < tostring(b.Name)
            end
            return oa < ob
        end)

        local bottomGroupOrder = {
            "500K Event",
            "Ghost",
            "Spookie",
            "Thanksgiving",
            "3M Starter",
            "3M Grinder",
            "Candy",
            "Noel",
            "Kringle",
            "Yuletide",
            "5M Starter",
            "5M Advanced",
            "Heartstruck"
        }
        local groupAliases = {
            Basic = "Forest",
            Frost = "Winter",
            Sun = "Desert",
            Tunnel = "Mines",
            Cavern = "Mines",
            Lantern = "Mines",
            Energy = "Cyber",
            Waves = "Ocean",
            Capstone = "Mushroom World",
            Astryx = "Space World",
            Vornel = "Space World",
            Starlight = "Space World",
            Galaxy = "Space World",
            Heavenly = "Heaven World",
            Damnation = "Hell World",
            Aetheris = "The Garden",
            Nythera = "The Garden",
            Veydris = "The Garden",
            Ghost = "Halloween",
            Spookie = "Halloween",
            Candy = "Christmas",
            Noel = "Christmas",
            Kringle = "Christmas",
            Yuletide = "Christmas",
            Heartstruck = "Valentine"
        }
        local bottomGroupSet = {}
        for _, name in ipairs(bottomGroupOrder) do
            bottomGroupSet[name] = true
        end

        local normalGroups = {}
        local bottomGroups = {}
        for _, entry in ipairs(groups) do
            if bottomGroupSet[entry.Name] then
                bottomGroups[#bottomGroups + 1] = entry
            else
                normalGroups[#normalGroups + 1] = entry
            end
        end

        local bottomMap = {}
        for _, entry in ipairs(bottomGroups) do
            bottomMap[entry.Name] = entry
        end
        local orderedBottom = {}
        for _, name in ipairs(bottomGroupOrder) do
            local entry = bottomMap[name]
            if entry then
                orderedBottom[#orderedBottom + 1] = entry
            end
        end

        local function createRuneDivider(parent)
            local div = Instance.new("Frame")
            div.Size = UDim2.new(1, 0, 0, 1)
            div.BorderSizePixel = 0
            div.Parent = parent
            registerTheme(div, "BackgroundColor3", "Muted")
            return div
        end

        local function createRuneGroupBox(parent, title)
            local container = Instance.new("Frame")
            container.Size = UDim2.new(1, 0, 0, 0)
            container.AutomaticSize = Enum.AutomaticSize.Y
            container.BorderSizePixel = 0
            container.Parent = parent
            registerTheme(container, "BackgroundColor3", "Main")
            addCorner(container, State.Layout.Tokens.Radius)
            addStroke(container, "Muted", 1, 0.85)

            local pad = Instance.new("UIPadding")
            pad.PaddingTop = UDim.new(0, State.Layout.Tokens.SectionGap)
            pad.PaddingBottom = UDim.new(0, State.Layout.Tokens.SectionGap)
            pad.PaddingLeft = UDim.new(0, State.Layout.Tokens.SectionPad - State.Layout.Tokens.InputPadSm)
            pad.PaddingRight = UDim.new(0, State.Layout.Tokens.SectionPad - State.Layout.Tokens.InputPadSm)
            pad.Parent = container

            local stack = Instance.new("UIListLayout")
            stack.Padding = UDim.new(0, State.Layout.Tokens.InputPad)
            stack.SortOrder = Enum.SortOrder.LayoutOrder
            stack.Parent = container

            local content = Instance.new("Frame")
            content.Size = UDim2.new(1, 0, 0, 0)
            content.AutomaticSize = Enum.AutomaticSize.Y
            content.BackgroundTransparency = 1
            content.Parent = container
            content.LayoutOrder = 2

            local cellGap = State.Layout.Tokens.InputPad
            local cellOffset = math.floor((cellGap * 2) / 3)
            local grid = Instance.new("UIGridLayout")
            grid.CellPadding = UDim2.new(0, cellGap, 0, cellGap)
            grid.CellSize = UDim2.new(1 / 3, -cellOffset, 0, 128)
            grid.FillDirection = Enum.FillDirection.Horizontal
            grid.SortOrder = Enum.SortOrder.LayoutOrder
            grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
            grid.VerticalAlignment = Enum.VerticalAlignment.Top
            grid.Parent = content

            local stateKey = "Stat::Rune::" .. tostring(title)
            local expanded = true
            if State.Config and State.Config.Get then
                local states = State.Config.Get("SectionStates", {})
                if states[stateKey] ~= nil then
                    expanded = states[stateKey] == true
                else
                    states[stateKey] = expanded
                    State.Config.Set("SectionStates", states)
                end
            end

            local dropdown

            local function applyExpanded()
                if dropdown and dropdown.SetExpanded then
                    dropdown:SetExpanded(expanded)
                end
                content.Visible = expanded
            end

            local function setExpanded(v)
                expanded = v == true
                if State.Config and State.Config.Get then
                    local states = State.Config.Get("SectionStates", {})
                    states[stateKey] = expanded
                    State.Config.Set("SectionStates", states)
                end
                applyExpanded()
                if type(applyRuneFilter) == "function" then
                    applyRuneFilter()
                else
                    content.Visible = expanded
                end
            end

            if State.UI and State.UI.CreateListDropdownRow then
                dropdown = State.UI.CreateListDropdownRow(container, title, function(v)
                    setExpanded(v == true)
                end)
                if dropdown and dropdown.Frame then
                    dropdown.Frame.LayoutOrder = 1
                end
            else
                dropdown = nil
            end

            applyExpanded()

            return {
                Container = container,
                Content = content,
                Dropdown = dropdown,
                GetExpanded = function()
                    return expanded
                end,
                SetExpanded = setExpanded
            }
        end

        local function getRuneOwnValue(groupName, itemName)
            if not LP then
                return nil
            end
            local runesRoot = resolveCaseInsensitive(LP, "Runes")
            if not runesRoot then
                return nil
            end
            local groupNode = resolveCaseInsensitive(runesRoot, groupName)
            if not groupNode then
                return nil
            end
            local runesNode = resolveCaseInsensitive(groupNode, "Runes")
            if not runesNode then
                return nil
            end
            local itemNode = resolveCaseInsensitive(runesNode, itemName)
            if not itemNode then
                return nil
            end
            return autoBuyLogReadNumeric(itemNode)
        end

        statState.RuneRows = {}
        statState.RuneGroups = {}
        local getTotalPower

        local function buildGroup(groupEntry)
            local groupName = groupEntry.Name
            local groupInfo = groupEntry.Data
            local groupBox = createRuneGroupBox(runeSection, groupName)
            local groupSection = groupBox.Content
            statState.RuneGroups[groupName] = {
                Name = groupName,
                Container = groupBox.Container,
                Content = groupBox.Content,
                Dropdown = groupBox.Dropdown,
                GetExpanded = groupBox.GetExpanded,
                SetExpanded = groupBox.SetExpanded,
                Items = {}
            }
            statState.RuneRows[groupName] = statState.RuneRows[groupName] or {}
            local alias = groupAliases[groupName]
            statState.RuneGroups[groupName].Alias = alias
            if alias and groupBox.Dropdown and groupBox.Dropdown.Frame and groupBox.Dropdown.Label then
                local aliasLabel = Instance.new("TextLabel")
                aliasLabel.Name = "AliasLabel"
                aliasLabel.Size = UDim2.new(1, -50, 1, 0)
                aliasLabel.Position = UDim2.new(0, 0, 0, 0)
                aliasLabel.BackgroundTransparency = 1
                aliasLabel.Font = Enum.Font.Gotham
                aliasLabel.TextSize = 10
                aliasLabel.TextXAlignment = Enum.TextXAlignment.Left
                aliasLabel.TextYAlignment = Enum.TextYAlignment.Center
                aliasLabel.Text = "(" .. tostring(alias) .. ")"
                aliasLabel.Parent = groupBox.Dropdown.Frame
                setFontClass(aliasLabel, "Tiny")
                registerTheme(aliasLabel, "TextColor3", "Muted")
                local function updateAliasPos()
                    local base = groupBox.Dropdown.Label
                    local width = base and base.TextBounds and base.TextBounds.X or 0
                    aliasLabel.Position = UDim2.new(0, math.floor(width + 6), 0, 0)
                end
                updateAliasPos()
                if groupBox.Dropdown.Label and groupBox.Dropdown.Label.GetPropertyChangedSignal then
                    trackConnection(groupBox.Dropdown.Label:GetPropertyChangedSignal("TextBounds"):Connect(updateAliasPos))
                end
            end

            local items = {}
            for itemName, itemInfo in pairs(groupInfo.Runes or {}) do
                if type(itemName) == "string" and type(itemInfo) == "table" then
                    items[#items + 1] = {
                        Name = itemName,
                        Data = itemInfo
                    }
                end
            end
            table.sort(items, function(a, b)
                local oa = tonumber(a.Data and a.Data.Order) or 9999
                local ob = tonumber(b.Data and b.Data.Order) or 9999
                if oa == ob then
                    return tostring(a.Name) < tostring(b.Name)
                end
                return oa < ob
            end)

            for _, itemEntry in ipairs(items) do
                local itemName = itemEntry.Name
                local chanceValue = tonumber(itemEntry.Data and itemEntry.Data.chance)
                local chanceIn = chancePercentToOneIn(chanceValue)
                local boostsData = itemEntry.Data and itemEntry.Data.Boosts

                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, 0, 0, 128)
                row.BorderSizePixel = 0
                row.Parent = groupSection
                registerTheme(row, "BackgroundColor3", "Main")
                addCorner(row, 6)
                addStroke(row, "Muted", 1, 0.6)

                local itemLabel = Instance.new("TextLabel")
                itemLabel.Size = UDim2.new(1, -12, 0, 16)
                itemLabel.Position = UDim2.new(0, 6, 0, 2)
                itemLabel.BackgroundTransparency = 1
                itemLabel.Font = Enum.Font.Gotham
                itemLabel.TextSize = 11
                itemLabel.TextXAlignment = Enum.TextXAlignment.Left
                itemLabel.TextYAlignment = Enum.TextYAlignment.Top
                itemLabel.Text = tostring(itemName)
                itemLabel.Parent = row
                setFontClass(itemLabel, "Small")
                registerTheme(itemLabel, "TextColor3", "Text")

                local chanceLabel = Instance.new("TextLabel")
                chanceLabel.Size = UDim2.new(1, -12, 0, 14)
                chanceLabel.Position = UDim2.new(0, 6, 0, 18)
                chanceLabel.BackgroundTransparency = 1
                chanceLabel.Font = Enum.Font.Gotham
                chanceLabel.TextSize = 9
                chanceLabel.TextXAlignment = Enum.TextXAlignment.Left
                chanceLabel.TextYAlignment = Enum.TextYAlignment.Top
                chanceLabel.Text = "Chance: 1 in " .. tostring(formatCompactShort(chanceIn))
                chanceLabel.Parent = row
                setFontClass(chanceLabel, "Tiny")
                registerTheme(chanceLabel, "TextColor3", "Muted")

                local ownLabel = Instance.new("TextLabel")
                ownLabel.Size = UDim2.new(1, -12, 0, 14)
                ownLabel.Position = UDim2.new(0, 6, 0, 32)
                ownLabel.BackgroundTransparency = 1
                ownLabel.Font = Enum.Font.Gotham
                ownLabel.TextSize = 9
                ownLabel.TextXAlignment = Enum.TextXAlignment.Left
                ownLabel.TextYAlignment = Enum.TextYAlignment.Top
                ownLabel.Text = "Own: -"
                ownLabel.Parent = row
                setFontClass(ownLabel, "Tiny")
                registerTheme(ownLabel, "TextColor3", "Muted")

                local timeLabel = Instance.new("TextLabel")
                timeLabel.Size = UDim2.new(1, -12, 0, 14)
                timeLabel.Position = UDim2.new(0, 6, 0, 46)
                timeLabel.BackgroundTransparency = 1
                timeLabel.Font = Enum.Font.Gotham
                timeLabel.TextSize = 9
                timeLabel.TextXAlignment = Enum.TextXAlignment.Left
                timeLabel.TextYAlignment = Enum.TextYAlignment.Top
                timeLabel.Text = "Time Chance: --"
                timeLabel.Parent = row
                setFontClass(timeLabel, "Tiny")
                registerTheme(timeLabel, "TextColor3", "Muted")

                local boostDividerY = 60
                local boostAreaH = 46
                local boostAreaY = boostDividerY + 2

                local boostDivider = Instance.new("Frame")
                boostDivider.Size = UDim2.new(1, -12, 0, 1)
                boostDivider.Position = UDim2.new(0, 6, 0, boostDividerY)
                boostDivider.BorderSizePixel = 0
                boostDivider.Parent = row
                registerTheme(boostDivider, "BackgroundColor3", "Muted")

                local boostsLabel = Instance.new("TextLabel")
                boostsLabel.Size = UDim2.new(1, -12, 0, boostAreaH)
                boostsLabel.Position = UDim2.new(0, 6, 0, boostAreaY)
                boostsLabel.BackgroundTransparency = 1
                boostsLabel.Font = Enum.Font.Gotham
                boostsLabel.TextSize = 9
                boostsLabel.TextWrapped = true
                boostsLabel.TextXAlignment = Enum.TextXAlignment.Left
                boostsLabel.TextYAlignment = Enum.TextYAlignment.Top
                boostsLabel.Text = "-"
                boostsLabel.Parent = row
                setFontClass(boostsLabel, "Tiny")
                registerTheme(boostsLabel, "TextColor3", "Text")

                local function formatBoostValue(value)
                    local text = tostring(autoBuyLogFormatNumber(value))
                    return text:gsub("%s*%([^%)]+%)", "")
                end

                local boostLines = {}
                if type(boostsData) == "table" then
                    for _, entry in ipairs(boostsData) do
                        if type(entry) == "table" and #entry >= 4 and type(entry[1]) == "string" and entry[3] ~= nil then
                            local name = tostring(entry[1])
                            local per = tonumber(entry[2])
                            local maxValue = tonumber(entry[3])
                            if type(per) == "number" and type(maxValue) == "number" and per > 0 then
                                local required = maxValue / per
                                local rounded = math.floor(required + 0.5)
                                if math.abs(required - rounded) <= 1e-6 then
                                    required = rounded
                                end
                                boostLines[#boostLines + 1] =
                                    "- " .. name .. ": " .. formatBoostValue(maxValue) .. " | (" .. formatBoostValue(required) .. ")"
                            end
                        end
                    end
                end
                if #boostLines > 0 then
                    boostsLabel.Text = table.concat(boostLines, "\n")
                else
                    boostsLabel.Text = "-"
                end

                local difficultyLabel = Instance.new("TextLabel")
                difficultyLabel.Size = UDim2.new(1, -12, 0, 14)
                difficultyLabel.Position = UDim2.new(0, 6, 0, boostAreaY + boostAreaH + 2)
                difficultyLabel.AnchorPoint = Vector2.new(0, 0)
                difficultyLabel.BackgroundTransparency = 0
                difficultyLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
                difficultyLabel.Font = Enum.Font.Gotham
                difficultyLabel.TextSize = 9
                difficultyLabel.TextXAlignment = Enum.TextXAlignment.Center
                difficultyLabel.TextYAlignment = Enum.TextYAlignment.Center
                difficultyLabel.Text = "--"
                difficultyLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
                difficultyLabel.Parent = row
                setFontClass(difficultyLabel, "Tiny")
                addCorner(difficultyLabel, 4)

                statState.RuneRows[groupName][itemName] = {
                    Row = row,
                    OwnLabel = ownLabel,
                    ChanceLabel = chanceLabel,
                    TimeLabel = timeLabel,
                    DifficultyLabel = difficultyLabel,
                    Chance = chanceValue,
                    ChanceIn = chanceIn
                }
                statState.RuneGroups[groupName].Items[#statState.RuneGroups[groupName].Items + 1] = {
                    Name = itemName,
                    Row = row
                }
            end
        end

        for _, groupEntry in ipairs(normalGroups) do
            buildGroup(groupEntry)
        end

        if #orderedBottom > 0 then
            if #normalGroups > 0 then
                createRuneDivider(runeSection)
            end
            for _, groupEntry in ipairs(orderedBottom) do
                buildGroup(groupEntry)
            end
        end

        local function parseSearchTokens(text)
            local raw = tostring(text or "")
            local tokens = {}
            for part in string.gmatch(raw, "([^,]+)") do
                local cleaned = tostring(part):lower():gsub("^%s+", ""):gsub("%s+$", "")
                if cleaned ~= "" then
                    tokens[#tokens + 1] = cleaned
                end
            end
            if #tokens == 0 then
                local trimmed = raw:lower():gsub("^%s+", ""):gsub("%s+$", "")
                if trimmed ~= "" then
                    tokens[#tokens + 1] = trimmed
                end
            end
            return tokens
        end

        local function hasTokenMatch(label, tokens)
            if type(label) ~= "string" then
                return false
            end
            local target = tostring(label):lower()
            for _, token in ipairs(tokens) do
                if token ~= "" and target:find(token, 1, true) ~= nil then
                    return true
                end
            end
            return false
        end

        applyRuneFilter = function()
            local tokens = parseSearchTokens(statState.RuneSearchQuery or "")
            local searchActive = #tokens > 0
            local mode = tostring(statState.RuneSearchMode or "Name")
            local totalPower = nil
            if mode == "Difficulty" and getTotalPower then
                totalPower = select(1, getTotalPower())
            end

            for groupName, groupState in pairs(statState.RuneGroups or {}) do
                local groupHasMatch = false
                local groupKey = tostring(groupName)
                local groupMatch = false
                if searchActive and mode == "Name" then
                    groupMatch = hasTokenMatch(groupKey, tokens) or hasTokenMatch(groupState and groupState.Alias, tokens)
                end
                for _, item in ipairs(groupState.Items or {}) do
                    local itemMatch = true
                    if searchActive then
                        if mode == "Difficulty" then
                            itemMatch = false
                            local rowData = statState.RuneRows[groupName] and statState.RuneRows[groupName][item.Name]
                            if rowData and rowData.ChanceIn and type(totalPower) == "number" and totalPower > 0 then
                                local eta = rowData.ChanceIn / totalPower
                                local diff = resolveRuneDifficulty(eta)
                                if diff and diff.Label then
                                    itemMatch = hasTokenMatch(diff.Label, tokens)
                                end
                            end
                        else
                            local itemName = tostring(item.Name or "")
                            itemMatch = groupMatch or hasTokenMatch(itemName, tokens)
                        end
                    end
                    if item.Row and item.Row.Parent then
                        item.Row.Visible = itemMatch
                    end
                    if itemMatch then
                        groupHasMatch = true
                    end
                end
                if groupState.Container and groupState.Container.Parent then
                    groupState.Container.Visible = groupHasMatch
                end
                if groupState.Content and groupState.Content.Parent then
                    local expanded = true
                    if groupState.GetExpanded then
                        expanded = groupState.GetExpanded() == true
                    end
                    groupState.Content.Visible = groupHasMatch and (expanded or searchActive)
                end
            end
        end
        applyRuneFilter()

        getTotalPower = function()
            local bulk = tonumber(statState.ProfileValues["Rune Bulk"])
            local luck = tonumber(statState.ProfileValues["Rune Luck"])
            local speed = tonumber(statState.ProfileValues["Rune Speed"])

            if type(bulk) ~= "number" or bulk ~= bulk or bulk < 0 then
                bulk = 0
            end
            if type(luck) ~= "number" or luck ~= luck or luck < 0 then
                luck = 0
            end
            if type(speed) ~= "number" or speed ~= speed or speed <= 0 then
                speed = 0.15
            end

            if statState.Modifiers.PotionSpeed2x == true then
                bulk = bulk * 2
            end
            if statState.Modifiers.BlackHoleSpeed2x == true then
                bulk = bulk * 2
            end
            if statState.Modifiers.PotionLuck2x == true then
                luck = luck * 2
            end
            if statState.Modifiers.BlackHoleLuck10x == true then
                luck = luck * 10
            end

            local effectiveRPS = bulk / speed
            if type(effectiveRPS) ~= "number" or effectiveRPS ~= effectiveRPS or effectiveRPS < 0 then
                effectiveRPS = 0
            end
            local totalPower = effectiveRPS * luck
            if type(totalPower) ~= "number" or totalPower ~= totalPower or totalPower < 0 then
                totalPower = 0
            end
            return totalPower, effectiveRPS
        end

        refreshRuneRows = function(includeOwn)
            local updateOwn = includeOwn ~= false
            local totalPower, effectiveRPS = getTotalPower()
            if runePowerRow and runePowerRow.Value and runePowerRow.Value.Parent then
                runePowerRow.Value.Text = "RPS: " .. formatPowerValue(effectiveRPS) .. " | Total: " .. formatPowerValue(totalPower)
            end
            if type(applyRuneFilter) == "function" then
                applyRuneFilter()
            end
            for groupName, items in pairs(statState.RuneRows) do
                for itemName, rowData in pairs(items) do
                    if updateOwn and rowData and rowData.OwnLabel and rowData.OwnLabel.Parent then
                        local own = getRuneOwnValue(groupName, itemName)
                        rowData.OwnLabel.Text = "Own: " .. tostring(formatStatValue(own, false))
                    end
                    if rowData and rowData.ChanceLabel and rowData.ChanceLabel.Parent then
                        rowData.ChanceLabel.Text = "Chance: 1 in " .. tostring(formatCompactShort(rowData.ChanceIn))
                    end
                        if rowData and rowData.TimeLabel and rowData.TimeLabel.Parent then
                            local eta = nil
                            local denom = tonumber(rowData.ChanceIn)
                            if type(denom) == "number" and denom > 0 and type(totalPower) == "number" and totalPower > 0 then
                                eta = denom / totalPower
                            end
                            rowData.TimeLabel.Text = "Time Chance: " .. tostring(formatTimeChance(eta))
                            local diff = resolveRuneDifficulty(eta)
                            if rowData.DifficultyLabel and rowData.DifficultyLabel.Parent then
                                if diff then
                                    rowData.DifficultyLabel.Text = diff.Label
                                    rowData.DifficultyLabel.TextColor3 = diff.Text
                                    rowData.DifficultyLabel.BackgroundColor3 = diff.Bg
                                else
                                    rowData.DifficultyLabel.Text = "--"
                                    rowData.DifficultyLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
                                    rowData.DifficultyLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
                                end
                            end
                        end
                    end
                end
            end

        local function setRuneRealtimeEnabled(enabled)
            local v = enabled == true
            statState.RuneRealtime = v
            if not v then
                if statState.RuneConn then
                    statState.RuneConn:Disconnect()
                    statState.RuneConn = nil
                end
                statState.RuneAccum = 0
                return
            end
            if statState.RuneConn then
                return
            end
            statState.RuneConn = RunService.Heartbeat:Connect(function(dt)
                statState.RuneAccum += dt
                if statState.RuneAccum < 0.35 then
                    return
                end
                statState.RuneAccum = 0
                refreshRuneRows(true)
            end)
            trackConnection(statState.RuneConn)
        end

        createButton(runeSection, "Refresh Own Rune", function()
            refreshRuneRows(true)
        end)
        createToggle(runeSection, "Realtime Own Rune", nil, false, function(v)
            setRuneRealtimeEnabled(v == true)
        end)
        refreshRuneRows(true)
    end
end

local function initActionTab()
    if not State.Tabs or not State.Tabs.Action then
        return
    end
    if State.ActionTabInitialized then
        return
    end
    State.ActionTabInitialized = true

    local tab = State.Tabs.Action
    local page = tab:GetPage()
    local potionSection = createSectionBox(page, "Buy Potion")
    local actionSection = createSectionBox(page, "Action")
    local redeemSection = createSectionBox(page, "Redeem Codes")

    State.ActionAuto = State.ActionAuto or {}
    State.ActionAuto.Clicker = State.ActionAuto.Clicker or {
        Enabled = Config.ActionAutoClickerEnabled == true,
        Interval = 0.01,
        LastClickAt = 0,
        Conn = nil
    }
    local autoClickerState = State.ActionAuto.Clicker

    local function setAutoClickerActionLog(enabled)
        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive("ActionAutoClicker", "Auto Clicker", enabled == true)
        end
    end

    local function performAutoClick()
        if type(mouse1click) ~= "function" then
            return false
        end
        local ok = pcall(function()
            mouse1click()
        end)
        return ok == true
    end

    local function setAutoClickerEnabled(enabled, source, skipSave)
        local v = enabled == true
        local changed = autoClickerState.Enabled ~= v
        autoClickerState.Enabled = v
        autoClickerState.LastClickAt = 0
        Config.ActionAutoClickerEnabled = v
        if changed and not skipSave then
            saveConfig()
        end
        setAutoClickerActionLog(v)
        if source == "keybind" and type(notify) == "function" then
            local keyName = getActionAutoClickerKeyName()
            notify("Auto Clicker", "Status: " .. (v and "ON" or "OFF") .. " [" .. tostring(keyName) .. "]", 3)
        end
    end

    if not autoClickerState.Conn then
        autoClickerState.Conn = RunService.RenderStepped:Connect(function()
            if not autoClickerState.Enabled then
                return
            end
            local now = os.clock()
            local interval = tonumber(autoClickerState.Interval) or 0.01
            if interval < 0 then
                interval = 0
            end
            if now - (tonumber(autoClickerState.LastClickAt) or 0) < interval then
                return
            end
            autoClickerState.LastClickAt = now
            performAutoClick()
        end)
        trackConnection(autoClickerState.Conn)
    end

    createToggle(
        actionSection,
        "Auto Clicker",
        nil,
        Config.ActionAutoClickerEnabled == true,
        function(v)
            setAutoClickerEnabled(v == true, "ui", false)
        end
    )
    toggleActionAutoClickerKeybind = function()
        setAutoClickerEnabled(not autoClickerState.Enabled, "keybind", false)
    end
    setAutoClickerEnabled(Config.ActionAutoClickerEnabled == true, "init", true)

    State.ActionAuto = State.ActionAuto or {}
    State.ActionAuto.Redeem = State.ActionAuto.Redeem or {
        Enabled = Config.ActionAutoRedeemCodesEnabled == true,
        Index = 1,
        WaitingCode = nil,
        WaitingCS = false,
        WaitingSince = 0,
        RetryDelay = 1.5,
        LastAttempt = 0
    }
    local redeemState = State.ActionAuto.Redeem
    redeemState.LogUI = redeemState.LogUI or {}
    local redeemLogUI = redeemState.LogUI

    local function readBoolNode(node)
        if not node then
            return false
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return false
        end
        if type(raw) == "boolean" then
            return raw
        end
        if type(raw) == "number" then
            return raw ~= 0
        end
        if type(raw) == "string" then
            local v = string.lower(raw)
            return v == "true" or v == "1" or v == "yes"
        end
        return false
    end

    local function getRedeemRemote()
        local remote = getMainRemote and getMainRemote() or nil
        if remote then
            return remote
        end
        local ok, res = pcall(function()
            return game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
        end)
        if ok and res then
            return res
        end
        return nil
    end

    local function getExtraRoot()
        return LP and LP:FindFirstChild("EXTRA") or nil
    end

    local function isCSCodeEntered()
        local extra = getExtraRoot()
        local node = extra and extra:FindFirstChild("CSCodeEntered") or nil
        if not node then
            return false
        end
        return readBoolNode(node)
    end

    local function getCodesFolder()
        local extra = getExtraRoot()
        return extra and extra:FindFirstChild("CODES") or nil
    end

    local function isCodeRedeemed(code)
        if type(code) ~= "string" or code == "" then
            return false
        end
        local folder = getCodesFolder()
        if not folder then
            return false
        end
        local node = folder:FindFirstChild(code)
        if not node then
            return false
        end
        return readBoolNode(node)
    end

    local function fireRedeem(action, code)
        local remote = getRedeemRemote()
        if not remote then
            return false
        end
        local ok = pcall(function()
            remote:FireServer(action, code)
        end)
        return ok == true
    end

    local redeemCodes = {
        "1.4kCCU",
        "1.7kCCU",
        "1.8kCCU!!",
        "100KGROUPMEMBERS!",
        "10kFavs!",
        "10kLikes!",
        "10kMembers",
        "11kLikes",
        "11kMembers",
        "12kLovelyMembers",
        "13kLovelyMembers",
        "14kLikes",
        "14kLovelyMembers",
        "15kBelovedMembers",
        "15kFavs!",
        "15kLikes",
        "16kBelovedMembers",
        "16kLikes",
        "17kBelovedMembers",
        "17kLikes",
        "18kLikes",
        "19kLikes",
        "1MVISITS!!",
        "1kFavs",
        "2.1kCCU",
        "2.2kCCU",
        "2.3kCCU",
        "2.4kCCU",
        "2.5kCCU",
        "2.6kCCU",
        "2.7kCCU",
        "2.8kCCU",
        "2.9kCCU",
        "2026!!",
        "20kFavs!",
        "20kLikes!",
        "21kLikes!",
        "22kLikes!",
        "23kLikes!",
        "25kFavs!",
        "2MVISITS!",
        "2kCCU",
        "3.0kCCU",
        "3.1kCCU",
        "3.2kCCU",
        "30kFavs!",
        "30kGroupMembers",
        "35kFavs!",
        "40kFavs!",
        "45kFavs!",
        "500KEVENT!",
        "5kFavs!",
        "5kLikes!",
        "6kLikes!",
        "75kGroupMembers!",
        "7kLikes!",
        "8kLikes!",
        "90kGroupMembers!",
        "9kLikes!",
        "9kMembers",
        "BugFixes",
        "CYBER",
        "Christmas",
        "DelayIncremental",
        "FixAndQOL1",
        "GUILDS",
        "GardenIncIsHere",
        "GoFish",
        "HALLOWEEN",
        "HELL",
        "MerryChristmas",
        "MushroomsAreHere",
        "NEWUPDATE!",
        "Nooblax",
        "Release",
        "Soon500kEvent",
        "SorryBigDelay",
        "SorryForShutdowns",
        "SorryShutdown1",
        "SorryShutdown10",
        "SorryShutdown11",
        "SorryShutdown12",
        "SorryShutdown2",
        "SorryShutdown3",
        "SorryShutdown4",
        "SorryShutdown5",
        "SorryShutdown6",
        "SorryShutdown7",
        "SorryShutdown8",
        "SorryShutdown9",
        "SorryShutdownBcNoobConnorAndRandomErrors",
        "Space",
        "THEGARDENISREAL",
        "ThanksGivingABitLate",
        "UpgradeTreeIsHere",
        "VALENTINE"
    }

    local function copyRedeemCode(value)
        if type(value) ~= "string" or value == "" then
            return false
        end
        if setclipboard then
            setclipboard(value)
            if type(notify) == "function" then
                notify("Copied", "Code disalin ke clipboard", 2)
            end
            return true
        end
        if type(notify) == "function" then
            notify("Copy Failed", "setclipboard tidak tersedia", 2)
        end
        return false
    end

    local function clearRedeemLogRows()
        if not redeemLogUI.Scroll then
            return
        end
        for _, child in ipairs(redeemLogUI.Scroll:GetChildren()) do
            if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
                if child.Name == "RedeemLogRow" or child.Name == "RedeemLogEmpty" then
                    child:Destroy()
                end
            end
        end
    end

    local function createRedeemLogRow(parent, code)
        local row = Instance.new("TextButton")
        row.Name = "RedeemLogRow"
        row.Size = UDim2.new(1, 0, 0, 24)
        row.BorderSizePixel = 0
        row.AutoButtonColor = false
        row.Text = ""
        row.Parent = parent
        registerTheme(row, "BackgroundColor3", "Main")
        addCorner(row, 6)
        addStroke(row, "Muted", 1, 0.7)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -48, 1, 0)
        label.Position = UDim2.new(0, 8, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = tostring(code)
        label.Parent = row
        setFontClass(label, "Small")
        registerTheme(label, "TextColor3", "Text")

        local copyLabel = Instance.new("TextLabel")
        copyLabel.Size = UDim2.new(0, 40, 1, 0)
        copyLabel.Position = UDim2.new(1, -44, 0, 0)
        copyLabel.BackgroundTransparency = 1
        copyLabel.Font = Enum.Font.GothamSemibold
        copyLabel.TextSize = 10
        copyLabel.TextXAlignment = Enum.TextXAlignment.Right
        copyLabel.Text = "Copy"
        copyLabel.Parent = row
        setFontClass(copyLabel, "Tiny")
        registerTheme(copyLabel, "TextColor3", "Muted")

        row.MouseButton1Click:Connect(function()
            copyRedeemCode(code)
        end)

        return row
    end

    local function refreshRedeemLog()
        if not redeemLogUI.Scroll then
            return
        end
        clearRedeemLogRows()

        local missing = {}
        for _, code in ipairs(redeemCodes) do
            if not isCodeRedeemed(code) then
                missing[#missing + 1] = code
            end
        end
        table.sort(missing, function(a, b)
            return tostring(a) < tostring(b)
        end)

        if #missing == 0 then
            local empty = Instance.new("TextLabel")
            empty.Name = "RedeemLogEmpty"
            empty.Size = UDim2.new(1, 0, 0, 20)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 11
            empty.TextXAlignment = Enum.TextXAlignment.Left
            empty.Text = "Semua code sudah redeemed"
            empty.Parent = redeemLogUI.Scroll
            setFontClass(empty, "Small")
            registerTheme(empty, "TextColor3", "Muted")
            return
        end

        for _, code in ipairs(missing) do
            createRedeemLogRow(redeemLogUI.Scroll, code)
        end
    end

    local function areAllCodesRedeemed()
        if not isCSCodeEntered() then
            return false
        end
        for _, code in ipairs(redeemCodes) do
            if not isCodeRedeemed(code) then
                return false
            end
        end
        return true
    end

    local function setRedeemEnabled(enabled, reason)
        redeemState.Enabled = enabled == true
        Config.ActionAutoRedeemCodesEnabled = redeemState.Enabled
        saveConfig()
        if redeemState.Toggle and redeemState.Toggle.Set then
            redeemState.Toggle:Set(redeemState.Enabled)
        end
        if not redeemState.Enabled then
            redeemState.WaitingCode = nil
            redeemState.WaitingCS = false
            redeemState.WaitingSince = 0
        end
        if redeemState.Enabled then
            redeemState.Index = 1
            redeemState.LastAttempt = 0
            autoBuySchedulerRegister("ActionAutoRedeemCodes", {
                Step = function()
                    if not redeemState.Enabled then
                        return false
                    end
                    if not LP then
                        return false
                    end
                    local now = os.clock()
                    if not isCSCodeEntered() then
                        if redeemState.WaitingCS then
                            if isCSCodeEntered() then
                                redeemState.WaitingCS = false
                                redeemState.WaitingSince = 0
                            elseif (now - (redeemState.WaitingSince or 0)) >= (redeemState.RetryDelay or 1.5) then
                                redeemState.WaitingCS = false
                                redeemState.WaitingSince = 0
                            end
                            return false
                        end
                        if fireRedeem("RedeemCSCode", "GHOULAXO-HXSNTEHL-TKALEG") then
                            redeemState.WaitingCS = true
                            redeemState.WaitingSince = now
                            return true
                        end
                        return false
                    end

                    if redeemState.WaitingCode then
                        if isCodeRedeemed(redeemState.WaitingCode) then
                            redeemState.WaitingCode = nil
                            redeemState.WaitingSince = 0
                        elseif (now - (redeemState.WaitingSince or 0)) >= (redeemState.RetryDelay or 1.5) then
                            redeemState.WaitingCode = nil
                            redeemState.WaitingSince = 0
                        end
                        return false
                    end

                    local total = #redeemCodes
                    if total == 0 then
                        return false
                    end
                    for _ = 1, total do
                        local idx = redeemState.Index or 1
                        local code = redeemCodes[idx]
                        idx += 1
                        if idx > total then
                            idx = 1
                        end
                        redeemState.Index = idx
                        if code and not isCodeRedeemed(code) then
                            if fireRedeem("RedeemCode", code) then
                                redeemState.WaitingCode = code
                                redeemState.WaitingSince = now
                                return true
                            end
                            return false
                        end
                    end

                    if areAllCodesRedeemed() then
                        setRedeemEnabled(false, "done")
                    end
                    return false
                end
            })
        else
            autoBuySchedulerUnregister("ActionAutoRedeemCodes")
            if reason == "done" then
                if type(notify) == "function" then
                    notify("Redeem Codes", "All codes redeemed", 3)
                end
            end
        end
    end

    redeemState.Toggle = createToggle(
        redeemSection,
        "Auto Redeem Codes",
        nil,
        redeemState.Enabled,
        function(v)
            if v == true and areAllCodesRedeemed() then
                setRedeemEnabled(false, "done")
                return
            end
            setRedeemEnabled(v == true, "ui")
        end
    )
    local redeemLogSection = createSubSectionBox(redeemSection, "Redeem Code Log")
    createButton(redeemLogSection, "Refresh Log", function()
        refreshRedeemLog()
    end)
    local redeemLogList = State.UI.BuildScrollList(redeemLogSection, {
        Title = "Kode yang belum true",
        TitleClass = "Subheading",
        Height = 170
    })
    redeemLogUI.Scroll = redeemLogList and redeemLogList.Scroll or nil
    refreshRedeemLog()
    if redeemState.Enabled and areAllCodesRedeemed() then
        setRedeemEnabled(false, "done")
    elseif redeemState.Enabled then
        setRedeemEnabled(true, "init")
    end

    local function fireUsePotion(potionId)
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return
        end
        pcall(function()
            remote:FireServer("UsePotion", potionId)
        end)
    end

    createButton(potionSection, "2x Stats", function()
        fireUsePotion(3380008624)
    end)
    createButton(potionSection, "2x Rune Luck", function()
        fireUsePotion(3377848727)
    end)
    createButton(potionSection, "2x Rune Speed", function()
        fireUsePotion(3377851382)
    end)
    createButton(potionSection, "2x Tier Luck", function()
        fireUsePotion(3407405853)
    end)
    createButton(potionSection, "2x Tier Speed", function()
        fireUsePotion(3407406202)
    end)
    createButton(potionSection, "2x Damage", function()
        fireUsePotion(3420155640)
    end)
    createButton(potionSection, "2x Roll Luck", function()
        fireUsePotion(3432283021)
    end)

    local potionShopSection = createSectionBox(page, "Buy Potion in Shop")
    local function fireBuyPotionShop(action, index)
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return
        end
        pcall(function()
            remote:FireServer(action, index)
        end)
    end

    State.ActionAuto = State.ActionAuto or {}
    State.ActionAuto.Potion = State.ActionAuto.Potion or {}
    local actionPotion = State.ActionAuto.Potion
    actionPotion.PriceMaps = actionPotion.PriceMaps or {}

    local function resolveChildByNames(parent, names)
        if not parent or type(names) ~= "table" then
            return nil
        end
        for _, name in ipairs(names) do
            if type(name) == "string" and #name > 0 then
                local child = parent:FindFirstChild(name)
                if child then
                    return child
                end
            end
        end
        return nil
    end

    local function readNumberChild(parent, names)
        local node = resolveChildByNames(parent, names)
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        return tonumber(raw)
    end

    local function readStringChild(parent, names)
        local node = resolveChildByNames(parent, names)
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        if type(raw) == "string" then
            return raw
        end
        return tostring(raw)
    end

    local function getCurrencyAmount(currencyName)
        if not LP or type(currencyName) ~= "string" then
            return nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        local currencyFolder = currencyRoot and currencyRoot:FindFirstChild(currencyName)
        local amountFolder = currencyFolder and currencyFolder:FindFirstChild("Amount")
        local amountNode = amountFolder and amountFolder:FindFirstChild("1")
        if not amountNode and amountFolder then
            local children = amountFolder:GetChildren()
            if #children > 0 then
                amountNode = children[1]
            end
        end
        if not amountNode then
            return nil
        end
        local ok, raw = pcall(function()
            return amountNode.Value
        end)
        if not ok then
            return nil
        end
        return tonumber(raw)
    end

    local function normalizePotionName(name)
        if type(name) ~= "string" then
            return nil
        end
        local out = string.lower(name)
        out = out:gsub("%s+", " ")
        out = out:gsub("^%s+", "")
        out = out:gsub("%s+$", "")
        return out
    end

    local function resolvePotionModule(shopKey)
        local rs = game:GetService("ReplicatedStorage")
        local shared = rs:FindFirstChild("Shared")
        local modules = shared and shared:FindFirstChild("Modules")
        if not modules then
            return nil
        end
        if shopKey == "CyberPotionShop" then
            local extra = modules:FindFirstChild("Extra")
            if not extra then
                return nil
            end
            return resolveChildByNames(extra, {"CyberShop", "Cyber Shop"})
        end
        if shopKey == "ThreeMPotionShop" then
            local events = modules:FindFirstChild("Events")
            if not events then
                return nil
            end
            return resolveChildByNames(events, {"3M Shop", "_3MShop", "3MShop"})
        end
        return nil
    end

    local function getPotionPriceMap(shopKey)
        if actionPotion.PriceMaps[shopKey] then
            return actionPotion.PriceMaps[shopKey]
        end
        local map = {}
        local moduleScript = resolvePotionModule(shopKey)
        if moduleScript and moduleScript:IsA("ModuleScript") then
            local ok, list = pcall(require, moduleScript)
            if ok and type(list) == "table" then
                for _, entry in ipairs(list) do
                    if type(entry) == "table" then
                        local price = tonumber(entry.price)
                        local names = {
                            normalizePotionName(entry.name),
                            normalizePotionName(entry.potionName)
                        }
                        for _, n in ipairs(names) do
                            if n and price then
                                map[n] = price
                            end
                        end
                    end
                end
            end
        end
        actionPotion.PriceMaps[shopKey] = map
        return map
    end

    local function getPotionItemsRoot(shopState)
        if not LP then
            return nil
        end
        if shopState and shopState.Key == "CyberPotionShop" then
            local extra = LP:FindFirstChild("EXTRA")
            local cyber = extra and resolveChildByNames(extra, {"CYBERSHOP", "CyberShop", "Cyber Shop"})
            return cyber and resolveChildByNames(cyber, {"items", "Items"})
        end
        if shopState and shopState.Key == "ThreeMPotionShop" then
            local events = LP:FindFirstChild("Events")
            local event3m = events and resolveChildByNames(events, {"_3MEvent", "3MEvent"})
            return event3m and resolveChildByNames(event3m, {"items", "Items"})
        end
        return nil
    end

    local function getPotionItemData(shopState, index)
        local root = getPotionItemsRoot(shopState)
        if not root then
            return nil
        end
        local item = root:FindFirstChild(tostring(index))
        if not item then
            return nil
        end
        local stock = readNumberChild(item, {"stock", "Stock"})
        local name = readStringChild(item, {"name", "Name"})
        local price = readNumberChild(item, {"price", "Price"})
        return {
            Stock = stock,
            Name = name,
            Price = price
        }
    end

    local function updatePotionSuccessByStock(shopState)
        if not shopState or not shopState.LastStocks then
            return
        end
        for i = 1, 3 do
            local itemData = getPotionItemData(shopState, i)
            local stock = itemData and tonumber(itemData.Stock) or nil
            local last = shopState.LastStocks[i]
            if type(last) == "number" and type(stock) == "number" and stock < last then
                addAutoBuyPotionSuccess(shopState.LogKey, last - stock)
            end
            if type(stock) == "number" then
                shopState.LastStocks[i] = stock
            end
        end
    end

    local function getPotionCost(shopState, itemName, fallbackPrice)
        local norm = normalizePotionName(itemName)
        local priceMap = getPotionPriceMap(shopState.Key)
        if norm and priceMap[norm] then
            return priceMap[norm]
        end
        return tonumber(fallbackPrice)
    end

    local function findPotionBuyIndex(shopState)
        if not shopState then
            return nil
        end
        local currencyAmount = getCurrencyAmount(shopState.CurrencyName)
        if type(currencyAmount) ~= "number" then
            return nil
        end
        local nextIdx = tonumber(shopState.NextIndex) or 1
        for _ = 1, 3 do
            local idx = nextIdx
            nextIdx += 1
            if nextIdx > 3 then
                nextIdx = 1
            end
            local itemData = getPotionItemData(shopState, idx)
            local stock = itemData and tonumber(itemData.Stock) or nil
            if type(stock) == "number" and stock > 0 then
                local cost = getPotionCost(shopState, itemData.Name, itemData.Price)
                if type(cost) == "number" and currencyAmount >= cost then
                    shopState.NextIndex = nextIdx
                    return idx
                end
            end
        end
        shopState.NextIndex = nextIdx
        return nil
    end

    local function setPotionShopEnabled(shopState, enabled)
        if not shopState then
            return
        end
        shopState.Enabled = enabled == true
        if shopState.ConfigKey then
            Config[shopState.ConfigKey] = shopState.Enabled
            saveConfig()
        end
        if shopState.Enabled then
            shopState.NextIndex = 1
            shopState.LastStocks = {}
            AutoBuyLogState.PotionData[shopState.LogKey] = {
                Key = shopState.LogKey,
                Name = shopState.DisplayName,
                Success = 0
            }
            setAutoBuyPotionActive(shopState.LogKey, shopState.DisplayName, true)
            autoBuySchedulerRegister(shopState.SchedulerKey, {
                Step = function()
                    if not shopState.Enabled then
                        return false
                    end
                    updatePotionSuccessByStock(shopState)
                    local idx = findPotionBuyIndex(shopState)
                    if not idx then
                        return false
                    end
                    fireBuyPotionShop(shopState.Action, idx)
                    return true
                end
            })
        else
            autoBuySchedulerUnregister(shopState.SchedulerKey)
            setAutoBuyPotionActive(shopState.LogKey, shopState.DisplayName, false)
        end
    end

    local cyberPotionState = {
        Key = "CyberPotionShop",
        DisplayName = "Cyber Shop",
        LogKey = "AutoPotionCyber",
        SchedulerKey = "AutoPotionCyber",
        Action = "BuyItemCyberShop",
        CurrencyName = "Tickets",
        ConfigKey = "ActionPotionCyberEnabled",
        Enabled = Config.ActionPotionCyberEnabled == true,
        NextIndex = 1,
        LastStocks = {}
    }
    local threeMPotionState = {
        Key = "ThreeMPotionShop",
        DisplayName = "3M Shop",
        LogKey = "AutoPotion3M",
        SchedulerKey = "AutoPotion3M",
        Action = "BuyItem3MShop",
        CurrencyName = "Super Tickets",
        ConfigKey = "ActionPotion3MEnabled",
        Enabled = Config.ActionPotion3MEnabled == true,
        NextIndex = 1,
        LastStocks = {}
    }
    State.ActionAuto.Claim = State.ActionAuto.Claim or {
        Interval = 0.35,
        RepositionInterval = 0.75,
        TrickOrTreat = {
            Enabled = Config.ActionClaimTrickOrTreatEnabled == true,
            ConfigKey = "ActionClaimTrickOrTreatEnabled",
            OwnerKey = "ActionClaimTrickOrTreat",
            LogName = "Auto Claim TrickOrTreat",
            TargetPosition = Vector3.new(-1858.588, 24.202, -2152.789),
            LastTeleport = 0,
            Accum = 0,
            SavedPivot = nil,
            Teleporting = false,
            Conn = nil
        },
        SantaGift = {
            Enabled = Config.ActionClaimSantaGiftEnabled == true,
            ConfigKey = "ActionClaimSantaGiftEnabled",
            OwnerKey = "ActionClaimSantaGift",
            LogName = "Auto Claim SantaGift",
            TargetPosition = Vector3.new(-5294.780, 9.663, -30.830),
            LastTeleport = 0,
            Accum = 0,
            SavedPivot = nil,
            Teleporting = false,
            Conn = nil
        }
    }
    local actionClaim = State.ActionAuto.Claim

    local function readBoolChild(parent, names)
        local node = resolveChildByNames(parent, names)
        if not node then
            return false
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return false
        end
        if type(raw) == "boolean" then
            return raw
        end
        if type(raw) == "number" then
            return raw ~= 0
        end
        if type(raw) == "string" then
            local v = string.lower(raw)
            return v == "true" or v == "1" or v == "yes"
        end
        return false
    end

    local function getCurrentPivot()
        if not LP or not LP.Character then
            return nil
        end
        local ok, pivot = pcall(function()
            return LP.Character:GetPivot()
        end)
        if ok and pivot then
            return pivot
        end
        local hrp = LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            return hrp.CFrame
        end
        return nil
    end

    local function restoreClaimPosition(state)
        if not state then
            return
        end
        if state.SavedPivot and LP and LP.Character then
            pcall(function()
                LP.Character:PivotTo(state.SavedPivot)
            end)
        end
        state.Teleporting = false
        state.SavedPivot = nil
        state.LastTeleport = 0
        if State.AutomationTeleport and State.AutomationTeleport.Release then
            State.AutomationTeleport.Release(state.OwnerKey)
        end
    end

    local function teleportClaim(state, force)
        if not state or not LP or not LP.Character then
            return false
        end
        local now = os.clock()
        local minGap = tonumber(actionClaim.RepositionInterval) or 0.75
        if not force and (now - (state.LastTeleport or 0)) < minGap then
            return false
        end
        if State.AutomationTeleport and State.AutomationTeleport.TryAcquire and not State.AutomationTeleport.TryAcquire(state.OwnerKey) then
            return false
        end
        if not state.SavedPivot then
            state.SavedPivot = getCurrentPivot()
        end
        local ok = pcall(function()
            LP.Character:PivotTo(CFrame.new(state.TargetPosition))
        end)
        if ok then
            state.Teleporting = true
            state.LastTeleport = now
            return true
        end
        if State.AutomationTeleport and State.AutomationTeleport.Release then
            State.AutomationTeleport.Release(state.OwnerKey)
        end
        return false
    end

    local function canClaimTrickOrTreat()
        if not LP then
            return false
        end
        local events = LP:FindFirstChild("Events")
        local halloween = events and events:FindFirstChild("HalloweenEvent")
        local trick = halloween and halloween:FindFirstChild("TrickOrTreat")
        return readBoolChild(trick, {"canClaim"})
    end

    local function canClaimSantaGift()
        if not LP then
            return false
        end
        local events = LP:FindFirstChild("Events")
        local christmas = events and events:FindFirstChild("ChristmasEvent")
        return readBoolChild(christmas, {"SantaGift_CanClaim"})
    end

    local function setAutoClaimEnabled(state, enabled, canClaimFn)
        if not state then
            return
        end
        state.Enabled = enabled == true
        if state.ConfigKey then
            Config[state.ConfigKey] = state.Enabled
            saveConfig()
        end
        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive(state.OwnerKey, state.LogName, state.Enabled)
        end
        if state.Enabled then
            if state.Conn then
                state.Conn:Disconnect()
            end
            state.Accum = 0
            state.Conn = RunService.Heartbeat:Connect(function(dt)
                state.Accum = (state.Accum or 0) + (dt or 0)
                if state.Accum < (tonumber(actionClaim.Interval) or 0.35) then
                    return
                end
                state.Accum = 0
                local canClaim = canClaimFn and canClaimFn() or false
                if canClaim then
                    if not state.Teleporting then
                        teleportClaim(state, true)
                    else
                        teleportClaim(state, false)
                    end
                elseif state.Teleporting then
                    restoreClaimPosition(state)
                end
            end)
            trackConnection(state.Conn)
        else
            if state.Conn then
                state.Conn:Disconnect()
                state.Conn = nil
            end
            state.Accum = 0
            restoreClaimPosition(state)
        end
    end

    createToggle(
        potionShopSection,
        "Auto Buy Potion in Shop Cyber",
        nil,
        cyberPotionState.Enabled,
        function(v)
            setPotionShopEnabled(cyberPotionState, v == true)
        end
    )
    createToggle(
        potionShopSection,
        "Auto Buy Potion in Shop 3M",
        nil,
        threeMPotionState.Enabled,
        function(v)
            setPotionShopEnabled(threeMPotionState, v == true)
        end
    )
    createToggle(
        potionShopSection,
        "Auto Claim TrickOrTreat",
        nil,
        actionClaim.TrickOrTreat.Enabled,
        function(v)
            setAutoClaimEnabled(actionClaim.TrickOrTreat, v == true, canClaimTrickOrTreat)
        end
    )
    createToggle(
        potionShopSection,
        "Auto Claim SantaGift",
        nil,
        actionClaim.SantaGift.Enabled,
        function(v)
            setAutoClaimEnabled(actionClaim.SantaGift, v == true, canClaimSantaGift)
        end
    )

    local automationSection = createSectionBox(page, "Automation")
    setupAutoBuyGroup(automationSection, {
        GroupKey = "Action Tickets",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Tickets Mode: Upgrade All",
        Shops = {
            {
                Key = "Tickets",
                DisplayName = "Tickets",
                ShopName = "Tickets",
            },
            {
                Key = "Passive Shards",
                DisplayName = "Passive Shards",
                ShopName = "Passive Shards"
            }
        }
    })

    local runeSection = createSubSectionBox(automationSection, "Auto Rune Sacrifice")
    Config.ActionRuneSacrifice = Config.ActionRuneSacrifice or {}
    local runeCfg = Config.ActionRuneSacrifice
    runeCfg.Items = runeCfg.Items or {}
    runeCfg.Enabled = runeCfg.Enabled == true

    local runeItems = {
        "Garden Tree",
        "Frozen Core",
        "Temple God",
        "Eternal Gateway",
        "Deepest Depths",
        "Starlight Sun",
        "Nexus Entity",
        "Maerion",
        "The Deepest Sea",
        "The Darkest Sea",
        "Garden Artifact",
        "The Secret Garden",
        "Unstable Gateway",
        "Darkest Depths",
        "Supernova Star",
        "Echomycra",
        "Nebulite",
        "Eternal Eclipse",
        "Subzero",
        "Absolute Divinity"
    }
    for _, item in ipairs(runeItems) do
        if runeCfg.Items[item] == nil then
            runeCfg.Items[item] = true
        end
    end
    saveConfig()

    State.ActionAuto = State.ActionAuto or {}
    State.ActionAuto.Rune = State.ActionAuto.Rune or {
        Enabled = runeCfg.Enabled,
        Conn = nil,
        Accum = 0,
        Interval = 0.6,
        Index = 1
    }

    local function getNextRuneItem()
        for _ = 1, #runeItems do
            local idx = State.ActionAuto.Rune.Index or 1
            local name = runeItems[idx]
            idx += 1
            if idx > #runeItems then
                idx = 1
            end
            State.ActionAuto.Rune.Index = idx
            if runeCfg.Items[name] then
                return name
            end
        end
        return nil
    end

    local function fireRuneSacrifice(itemName)
        if not itemName then
            return
        end
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return
        end
        pcall(function()
            remote:FireServer("RuneSacrifice", itemName)
        end)
    end

    createToggle(runeSection, "On/Off", nil, State.ActionAuto.Rune.Enabled, function(v)
        State.ActionAuto.Rune.Enabled = v == true
        runeCfg.Enabled = State.ActionAuto.Rune.Enabled
        saveConfig()
        if State.ActionAuto.Rune.Enabled then
            if State.ActionAuto.Rune.Conn then
                State.ActionAuto.Rune.Conn:Disconnect()
            end
            State.ActionAuto.Rune.Accum = 0
            State.ActionAuto.Rune.Conn = RunService.Heartbeat:Connect(function(dt)
                State.ActionAuto.Rune.Accum += dt
                if State.ActionAuto.Rune.Accum >= State.ActionAuto.Rune.Interval then
                    State.ActionAuto.Rune.Accum = 0
                    local itemName = getNextRuneItem()
                    if itemName then
                        fireRuneSacrifice(itemName)
                    end
                end
            end)
            trackConnection(State.ActionAuto.Rune.Conn)
        else
            if State.ActionAuto.Rune.Conn then
                State.ActionAuto.Rune.Conn:Disconnect()
                State.ActionAuto.Rune.Conn = nil
            end
        end
    end)

    local listSection = createSubSectionBox(runeSection, "Item List")
    for _, item in ipairs(runeItems) do
        createToggle(listSection, item, nil, runeCfg.Items[item], function(v)
            runeCfg.Items[item] = v == true
            saveConfig()
        end)
    end

    local masterySection = createSubSectionBox(automationSection, "Auto Claim Mastery")
    State.ActionAuto = State.ActionAuto or {}
    State.ActionAuto.Mastery = State.ActionAuto.Mastery or {
        Enabled = Config.ActionAutoClaimMasteryEnabled == true,
        SchedulerKey = "ActionAutoClaimMastery",
        ActionKey = "ActionAutoClaimMastery",
        ActionName = "Auto Claim Mastery",
        Entries = nil,
        Index = 1,
        Pending = {},
        PendingTimeout = 2,
        LastRefreshAt = 0,
        RefreshInterval = 0.6,
        LastDetailSignature = "",
        LogUI = {}
    }
    local masteryState = State.ActionAuto.Mastery
    masteryState.LogUI = masteryState.LogUI or {}

    local function masteryReadNumberValue(node)
        if not node then
            return nil, nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil, nil
        end
        return raw, tonumber(raw)
    end

    local function masteryParseNumber(raw)
        local direct = tonumber(raw)
        if type(direct) == "number" and direct == direct and direct ~= math.huge and direct ~= -math.huge then
            return direct
        end
        local text = tostring(raw or "")
        if text == "" then
            return nil
        end
        text = text:gsub(",", ".")
        text = text:gsub("%s+", "")
        local num = tonumber(text)
        if type(num) == "number" and num == num and num ~= math.huge and num ~= -math.huge then
            return num
        end
        local mantissaText, expText, expSuffix = text:match("^([%+%-]?%d*%.?%d+)[eE]([%+%-]?%d*%.?%d+)([kmbKMB]?)$")
        if not mantissaText then
            return nil
        end
        local mantissa = tonumber(mantissaText)
        local exponent = tonumber(expText)
        if type(mantissa) ~= "number" or type(exponent) ~= "number" then
            return nil
        end
        local scale = 1
        local suffix = string.lower(expSuffix or "")
        if suffix == "k" then
            scale = 1e3
        elseif suffix == "m" then
            scale = 1e6
        elseif suffix == "b" then
            scale = 1e9
        end
        local out = mantissa * (10 ^ (exponent * scale))
        if out ~= out or out == math.huge or out == -math.huge then
            return nil
        end
        return out
    end

    local function masteryResolvePath(root, slashPath)
        if not root or type(slashPath) ~= "string" or slashPath == "" then
            return nil
        end
        local node = root
        for token in string.gmatch(slashPath, "[^/]+") do
            if not node then
                return nil
            end
            node = node:FindFirstChild(token)
        end
        return node
    end

    local function masteryGetModuleScript()
        local ok, scriptObj = pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local shared = rs and rs:FindFirstChild("Shared")
            local modules = shared and shared:FindFirstChild("Modules")
            local masteryModule = modules and modules:FindFirstChild("Mastery")
            if masteryModule and masteryModule:IsA("ModuleScript") then
                return masteryModule
            end
            return nil
        end)
        if ok and scriptObj then
            return scriptObj
        end
        return nil
    end

    local function masteryResolveDecompileFn()
        local env = (getgenv and getgenv()) or _G
        if type(env) ~= "table" then
            env = _G
        end
        local candidates = {
            rawget(env, "decompile"),
            rawget(env, "decompile_new"),
            rawget(env, "decompile2"),
            rawget(env, "decompilev2"),
            rawget(env, "decompiler"),
            rawget(_G, "decompile"),
            rawget(_G, "decompile_new"),
            rawget(_G, "decompile2"),
            rawget(_G, "decompilev2"),
            rawget(_G, "decompiler"),
            decompile
        }
        for _, fn in ipairs(candidates) do
            if type(fn) == "function" then
                return fn
            end
        end
        return nil
    end

    local function masteryReadModuleSource()
        if type(masteryState.SourceCache) == "string" and #masteryState.SourceCache > 0 then
            return masteryState.SourceCache
        end
        local scriptObj = masteryGetModuleScript()
        if not scriptObj then
            return nil
        end

        local sourceText = nil
        local okSource, rawSource = pcall(function()
            return scriptObj.Source
        end)
        if okSource and type(rawSource) == "string" and #rawSource > 0 then
            sourceText = rawSource
        end
        if (not sourceText or #sourceText == 0) then
            local decompileFn = masteryResolveDecompileFn()
            if type(decompileFn) == "function" then
                local okDec, dec = pcall(decompileFn, scriptObj)
                if okDec and type(dec) == "string" and #dec > 0 then
                    sourceText = dec
                end
            end
        end
        if type(sourceText) == "string" and #sourceText > 0 then
            masteryState.SourceCache = sourceText
            return sourceText
        end
        return nil
    end

    local function masteryParseOrder(raw)
        local n = masteryParseNumber(raw)
        if type(n) ~= "number" then
            return 999999
        end
        return math.floor(n + 0.5)
    end

    local function masteryBuildEntriesFromSource(sourceText)
        if type(sourceText) ~= "string" or sourceText == "" then
            return {}
        end
        local source = tostring(sourceText):gsub("\r\n", "\n")
        local reqClientByConfig = {}
        local configByTable = {}
        local stepsByTable = {}
        local orderByTable = {}

        for configName, reqClient in source:gmatch("([%w_]+)%.reqClient%s*=%s*\"([^\"]+)\"") do
            reqClientByConfig[configName] = reqClient
        end
        for tableName, configName in source:gmatch("([%w_]+)%.config%s*=%s*([%w_]+)") do
            configByTable[tableName] = configName
        end
        for tableName, orderRaw in source:gmatch("([%w_]+)%s*=%s*%{%s*order%s*=%s*([^;,%s}]+)") do
            orderByTable[tableName] = masteryParseOrder(orderRaw)
        end
        for tableName, block in source:gmatch("([%w_]+)%.steps%s*=%s*%{%{(.-)%}%}") do
            local reqs = {}
            for reqRaw in tostring(block):gmatch("req%s*=%s*([^;,%s}]+)") do
                local reqNum = masteryParseNumber(reqRaw)
                if type(reqNum) == "number" then
                    reqs[#reqs + 1] = {
                        req = reqNum
                    }
                end
            end
            stepsByTable[tableName] = reqs
        end

        local out = {}
        local seen = {}
        local function addEntry(name, reqClient, reqList, order)
            if type(name) ~= "string" or name == "" or seen[name] then
                return
            end
            if type(reqClient) ~= "string" or reqClient == "" then
                return
            end
            if type(reqList) ~= "table" or #reqList == 0 then
                return
            end
            seen[name] = true
            out[#out + 1] = {
                Name = name,
                Config = {
                    reqClient = reqClient
                },
                Steps = reqList,
                Order = tonumber(order) or 999999
            }
        end

        for name, tableName in source:gmatch("module%[\"([^\"]+)\"%]%s*=%s*([%w_]+)") do
            local cfgName = configByTable[tableName]
            local reqClient = cfgName and reqClientByConfig[cfgName] or nil
            local reqList = stepsByTable[tableName]
            addEntry(name, reqClient, reqList, orderByTable[tableName])
        end
        for name, tableName in source:gmatch("module%.([%w_]+)%s*=%s*([%w_]+)") do
            local cfgName = configByTable[tableName]
            local reqClient = cfgName and reqClientByConfig[cfgName] or nil
            local reqList = stepsByTable[tableName]
            addEntry(name, reqClient, reqList, orderByTable[tableName])
        end

        local withSentinel = source .. "\nmodule.__END__ = {}"
        for name, chunk in withSentinel:gmatch("module%[\"([^\"]+)\"%]%s*=%s*%{(.-)%}%s*module[%.%[]") do
            if not seen[name] then
                local reqClient = chunk:match("reqClient%s*=%s*\"([^\"]+)\"")
                local reqList = {}
                local stepsChunk = chunk:match("steps%s*=%s*%{%{(.-)%}%}")
                if stepsChunk then
                    for reqRaw in tostring(stepsChunk):gmatch("req%s*=%s*([^;,%s}]+)") do
                        local reqNum = masteryParseNumber(reqRaw)
                        if type(reqNum) == "number" then
                            reqList[#reqList + 1] = {
                                req = reqNum
                            }
                        end
                    end
                end
                local orderRaw = chunk:match("order%s*=%s*([^;,%s}]+)")
                addEntry(name, reqClient, reqList, masteryParseOrder(orderRaw))
            end
        end

        table.sort(out, function(a, b)
            if a.Order == b.Order then
                return tostring(a.Name) < tostring(b.Name)
            end
            return a.Order < b.Order
        end)
        return out
    end

    local function masteryBuildEntries()
        if type(masteryState.EntriesCache) == "table" then
            return masteryState.EntriesCache
        end
        local source = masteryReadModuleSource()
        local entries = masteryBuildEntriesFromSource(source)
        masteryState.EntriesCache = entries
        return entries
    end

    local function masteryGetLevel(masteryName)
        if not LP or type(masteryName) ~= "string" then
            return 0
        end
        local folder = LP:FindFirstChild("MASTERIES")
        local node = folder and folder:FindFirstChild(masteryName)
        if not node then
            return 0
        end
        local _, num = masteryReadNumberValue(node)
        if type(num) ~= "number" then
            num = masteryParseNumber(node.Value)
        end
        local lv = math.floor(tonumber(num) or 0)
        if lv < 0 then
            lv = 0
        end
        return lv
    end

    local function masteryGetOwnValue(entry)
        if type(entry) ~= "table" or type(entry.Config) ~= "table" then
            return nil, nil
        end
        local cfg = entry.Config
        if type(cfg.getReq) == "function" then
            local ok, raw = pcall(cfg.getReq, LP)
            if ok then
                return raw, masteryParseNumber(raw)
            end
        end
        if type(cfg.reqClient) == "string" and #cfg.reqClient > 0 then
            local target = masteryResolvePath(LP, cfg.reqClient)
            if target and target:IsA("ValueBase") then
                local raw, num = masteryReadNumberValue(target)
                if type(num) ~= "number" then
                    num = masteryParseNumber(raw)
                end
                return raw, num
            end
        end
        return nil, nil
    end

    local function masteryBuildStatus()
        if type(masteryState.Entries) ~= "table" then
            masteryState.Entries = masteryBuildEntries()
        end
        local list = {}
        local readyCount = 0
        local maxCount = 0
        for _, entry in ipairs(masteryState.Entries or {}) do
            local name = entry.Name
            local level = masteryGetLevel(name)
            local nextStep = entry.Steps[level + 1]
            local ownRaw, ownNum = masteryGetOwnValue(entry)
            if type(ownNum) ~= "number" then
                ownNum = masteryParseNumber(ownRaw)
            end
            local reqRaw = nextStep and nextStep.req or nil
            local reqNum = masteryParseNumber(reqRaw)
            local isMax = nextStep == nil
            local ready = false
            if not isMax and type(reqNum) == "number" and type(ownNum) == "number" and ownNum >= reqNum then
                ready = true
            end
            if ready then
                readyCount += 1
            end
            if isMax then
                maxCount += 1
            end
            list[#list + 1] = {
                Name = name,
                Level = level,
                NextLevel = level + 1,
                IsMax = isMax,
                Ready = ready,
                OwnRaw = ownRaw,
                OwnNum = ownNum,
                ReqRaw = reqRaw,
                ReqNum = reqNum
            }
        end
        return list, readyCount, maxCount
    end

    local function masteryFormatValue(num, raw)
        local text = autoBuyLogFormatNumber(num)
        if text == "?" and raw ~= nil then
            return autoBuyLogFormatRawFallback(raw)
        end
        return text
    end

    local function masteryBuildDetailText(status)
        if type(status) ~= "table" then
            return "-"
        end
        if status.IsMax then
            return "Lv " .. tostring(status.Level) .. " | max"
        end
        local ownText = masteryFormatValue(status.OwnNum, status.OwnRaw)
        local reqText = masteryFormatValue(status.ReqNum, status.ReqRaw)
        local readyText = status.Ready and "READY" or "waiting"
        return "Lv " .. tostring(status.Level) .. " -> " .. tostring(status.NextLevel)
            .. " | own: " .. tostring(ownText)
            .. " | req: " .. tostring(reqText)
            .. " | " .. tostring(readyText)
    end

    local function masteryClearRows()
        local scroll = masteryState.LogUI and masteryState.LogUI.Scroll
        if not scroll then
            return
        end
        for _, child in ipairs(scroll:GetChildren()) do
            if child:IsA("Frame") or child:IsA("TextLabel") then
                if child.Name == "MasteryRow" or child.Name == "MasteryEmptyRow" then
                    child:Destroy()
                end
            end
        end
    end

    local function masteryCreateRow(parent, status)
        local row = Instance.new("Frame")
        row.Name = "MasteryRow"
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BorderSizePixel = 0
        row.Parent = parent
        registerTheme(row, "BackgroundColor3", "Main")
        addCorner(row, 6)
        addStroke(row, "Muted", 1, 0.6)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -10, 0, 14)
        label.Position = UDim2.new(0, 5, 0, 1)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamSemibold
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Text = tostring(status.Name or "-")
        label.Parent = row
        setFontClass(label, "Small")
        registerTheme(label, "TextColor3", "Text")

        local detail = Instance.new("TextLabel")
        detail.Size = UDim2.new(1, -10, 0, 16)
        detail.Position = UDim2.new(0, 5, 0, 16)
        detail.BackgroundTransparency = 1
        detail.Font = Enum.Font.Gotham
        detail.TextSize = 9
        detail.TextXAlignment = Enum.TextXAlignment.Left
        detail.TextYAlignment = Enum.TextYAlignment.Top
        detail.Text = masteryBuildDetailText(status)
        detail.Parent = row
        setFontClass(detail, "Tiny")
        registerTheme(detail, "TextColor3", "Muted")
    end

    local function updateMasteryActionLog(statusList, readyCount, maxCount, forceRefresh)
        if not AutoBuyLogState then
            return
        end
        local data = AutoBuyLogState.ActionData[masteryState.ActionKey] or {
            Key = masteryState.ActionKey,
            Name = masteryState.ActionName,
            Success = 0
        }
        data.Key = masteryState.ActionKey
        data.Name = masteryState.ActionName
        data.Success = tonumber(data.Success) or 0

        local total = 0
        local firstNext = nil
        for _, status in ipairs(statusList or {}) do
            total += 1
            if not firstNext and not status.IsMax then
                firstNext = status
            end
        end

        local nextText = "max"
        if firstNext then
            nextText = tostring(firstNext.Name) .. " | " .. masteryBuildDetailText(firstNext)
        end
        local pendingCount = 0
        for _ in pairs(masteryState.Pending or {}) do
            pendingCount += 1
        end
        data.DetailText =
            "Ready: " .. tostring(tonumber(readyCount) or 0)
            .. " | Max: " .. tostring(tonumber(maxCount) or 0) .. "/" .. tostring(total)
            .. " | Pending: " .. tostring(pendingCount)
            .. "\n----------------"
            .. "\nNext: " .. tostring(nextText)

        local signature = tostring(data.DetailText)
        if signature == tostring(masteryState.LastDetailSignature or "") and forceRefresh ~= true then
            return
        end
        masteryState.LastDetailSignature = signature
        AutoBuyLogState.ActionData[masteryState.ActionKey] = data
        if AutoBuyLogState.ActiveActions[masteryState.ActionKey] then
            AutoBuyLogState.ActiveActions[masteryState.ActionKey] = data
            if forceRefresh ~= false then
                updateAutoBuyLogUI()
            end
        end
    end

    local function refreshMasteryRows(forceRefresh)
        local now = os.clock()
        local minInterval = tonumber(masteryState.RefreshInterval) or 0.6
        if not forceRefresh and (now - (tonumber(masteryState.LastRefreshAt) or 0)) < minInterval then
            return
        end
        masteryState.LastRefreshAt = now
        local statuses, readyCount, maxCount = masteryBuildStatus()
        masteryClearRows()

        local scroll = masteryState.LogUI and masteryState.LogUI.Scroll
        if not scroll then
            return
        end
        if #statuses == 0 then
            local empty = Instance.new("TextLabel")
            empty.Name = "MasteryEmptyRow"
            empty.Size = UDim2.new(1, 0, 0, 20)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 11
            empty.TextXAlignment = Enum.TextXAlignment.Left
            empty.Text = "Module mastery tidak ditemukan"
            empty.Parent = scroll
            setFontClass(empty, "Small")
            registerTheme(empty, "TextColor3", "Muted")
        else
            for _, status in ipairs(statuses) do
                masteryCreateRow(scroll, status)
            end
        end
        updateMasteryActionLog(statuses, readyCount, maxCount, forceRefresh == true)
    end

    local function masteryFireClaim(name)
        local remote = getMainRemote and getMainRemote() or nil
        if not remote or type(name) ~= "string" or #name == 0 then
            return false
        end
        local ok = pcall(function()
            remote:FireServer("ClaimMastery", name)
        end)
        return ok == true
    end

    local function processMasteryPending()
        local pending = masteryState.Pending or {}
        local timeout = tonumber(masteryState.PendingTimeout) or 2
        local now = os.clock()
        for masteryName, pend in pairs(pending) do
            local currentLevel = masteryGetLevel(masteryName)
            local oldLevel = tonumber(pend and pend.Level) or 0
            if currentLevel > oldLevel or (now - (tonumber(pend and pend.Since) or 0)) >= timeout then
                pending[masteryName] = nil
            end
        end
    end

    local function masteryStep()
        if masteryState.Enabled ~= true then
            return false
        end
        processMasteryPending()
        local statuses, readyCount, maxCount = masteryBuildStatus()
        local total = #statuses
        if total == 0 then
            refreshMasteryRows(false)
            return false
        end

        local idx = tonumber(masteryState.Index) or 1
        for _ = 1, total do
            local status = statuses[idx]
            idx += 1
            if idx > total then
                idx = 1
            end
            if status and status.Ready and not status.IsMax and not masteryState.Pending[status.Name] then
                if masteryFireClaim(status.Name) then
                    masteryState.Pending[status.Name] = {
                        Level = tonumber(status.Level) or 0,
                        Since = os.clock()
                    }
                    masteryState.Index = idx
                    if AutoBuyLogState and AutoBuyLogState.AddActionCount then
                        AutoBuyLogState.AddActionCount(masteryState.ActionKey, 1, false)
                    end
                    updateMasteryActionLog(statuses, readyCount, maxCount, true)
                    refreshMasteryRows(true)
                    return true
                end
                break
            end
        end
        masteryState.Index = idx
        updateMasteryActionLog(statuses, readyCount, maxCount, false)
        refreshMasteryRows(false)
        return false
    end

    local function setAutoClaimMasteryEnabled(enabled)
        masteryState.Enabled = enabled == true
        Config.ActionAutoClaimMasteryEnabled = masteryState.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive(masteryState.ActionKey, masteryState.ActionName, masteryState.Enabled)
        end

        if masteryState.Enabled then
            masteryState.Index = 1
            masteryState.Pending = {}
            autoBuySchedulerRegister(masteryState.SchedulerKey, {
                Step = masteryStep
            })
        else
            masteryState.Pending = {}
            autoBuySchedulerUnregister(masteryState.SchedulerKey)
        end
        refreshMasteryRows(true)
    end

    createToggle(masterySection, "Auto Claim Mastery", nil, masteryState.Enabled, function(v)
        setAutoClaimMasteryEnabled(v == true)
    end)
    createButton(masterySection, "Refresh Mastery Requirement", function()
        refreshMasteryRows(true)
    end)

    local masteryLogList = State.UI.BuildScrollList(masterySection, {
        Title = "Requirement Lv selanjutnya",
        TitleClass = "Subheading",
        Height = 190
    })
    masteryState.LogUI.Scroll = masteryLogList and masteryLogList.Scroll or nil
    refreshMasteryRows(true)
    if masteryState.Enabled then
        setAutoClaimMasteryEnabled(true)
    end
end

local function initWorldTabs()
    local worldProgress = {
        Start = 80,
        Finish = 86,
        Total = 18,
        Index = 0
    }
    local function stepWorld(label)
        worldProgress.Index += 1
        local ratio = worldProgress.Index / worldProgress.Total
        local pct = worldProgress.Start + (worldProgress.Finish - worldProgress.Start) * ratio
        if LoadingUI and LoadingUI.Set then
            LoadingUI:Set(pct, "Menyusun world tabs... (" .. tostring(label) .. ")")
        end
    end

createTabDivider()
State.Tabs = State.Tabs or {}
State.Tabs.Forest = createTab("Forest")
State.Tabs.Winter = createTab("Winter")
State.Tabs.Desert = createTab("Desert")
State.Tabs.Mines = createTab("Mines")
State.Tabs.Cyber = createTab("Cyber")
State.Tabs.Ocean = createTab("Ocean")
State.MushroomTab = createTab("Mushroom World")
State.Tabs.Space = createTab("Space World")
local TeleportSection = createSectionBox(State.Tabs.Space:GetPage(), "Teleport")

-- =====================================================
-- [SUBHEAD] Space World Teleport Helpers
-- =====================================================
local function createButtonRow(parent, items, onClick)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.BorderSizePixel = 0
    row.Parent = parent
    row.BackgroundTransparency = 1

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = row

    State.GridTextConstraints = State.GridTextConstraints or {}
    State.GridTextScaleApply = State.GridTextScaleApply or function(scale)
        local s = tonumber(scale) or 1
        for _, entry in ipairs(State.GridTextConstraints) do
            local clamp = entry.Clamp
            if clamp and clamp.Parent then
                local maxSize = math.max(6, math.floor(entry.BaseMax * s + 0.5))
                local minSize = math.max(6, math.floor(entry.BaseMin * s + 0.5))
                if maxSize < minSize then
                    minSize = maxSize
                end
                clamp.MaxTextSize = maxSize
                clamp.MinTextSize = minSize
            end
        end
    end

    for _, item in ipairs(items) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1 / 3, -4, 1, 0)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.Text = item.Label
        btn.TextScaled = true
        btn.TextWrapped = true
        btn.AutoButtonColor = false
        btn.Parent = row
        registerTheme(btn, "BackgroundColor3", "Main")
        registerTheme(btn, "TextColor3", "Text")
        addCorner(btn, 6)
        TeleportButtons[#TeleportButtons + 1] = btn

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 4)
        pad.PaddingRight = UDim.new(0, 4)
        pad.PaddingTop = UDim.new(0, 2)
        pad.PaddingBottom = UDim.new(0, 2)
        pad.Parent = btn

        local sizeClamp = Instance.new("UITextSizeConstraint")
        sizeClamp.MinTextSize = 8
        sizeClamp.MaxTextSize = btn.TextSize
        sizeClamp.Parent = btn
        State.GridTextConstraints[#State.GridTextConstraints + 1] = {
            Clamp = sizeClamp,
            BaseMin = sizeClamp.MinTextSize,
            BaseMax = sizeClamp.MaxTextSize
        }
        if State.GridTextScaleApply and MainScale then
            State.GridTextScaleApply(MainScale.Scale)
        end

        btn.MouseButton1Click:Connect(function()
            ActiveTeleportButton = btn
            applyTheme(Config.Theme or "Default")
            if onClick then
                onClick(item)
            end
        end)
    end
end

local function createGrid(parent, list, onClick)
    local items = {}
    for i = 1, #list do
        items[#items + 1] = list[i]
        if #items == 3 or i == #list then
            createButtonRow(parent, items, onClick)
            items = {}
        end
    end
end

local function fireWorldTeleport(worldName)
    if not worldName or worldName == "" then
        return
    end
    local remote = nil
    if getMainRemote then
        remote = getMainRemote()
    end
    if not remote then
        local ok, r = pcall(function()
            return game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
        end)
        if ok and r then
            remote = r
        end
    end
    if not remote then
        return
    end
    pcall(function()
        remote:FireServer("TeleportTo", worldName)
    end)
end

local function fireBuyArea(areaName)
    if not areaName or areaName == "" then
        return
    end
    local remote = nil
    if getMainRemote then
        remote = getMainRemote()
    end
    if not remote then
        local ok, r = pcall(function()
            return game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
        end)
        if ok and r then
            remote = r
        end
    end
    if not remote then
        return
    end
    pcall(function()
        remote:FireServer("BuyArea", areaName)
    end)
end

local function findChildCaseInsensitive(parent, name)
    if not parent or type(name) ~= "string" or #name == 0 then
        return nil
    end
    local direct = parent:FindFirstChild(name)
    if direct then
        return direct
    end
    local target = string.lower(name)
    for _, child in ipairs(parent:GetChildren()) do
        if string.lower(tostring(child.Name)) == target then
            return child
        end
    end
    return nil
end

local function readNodeNumericValue(node)
    if not node then
        return nil
    end
    local ok, raw = pcall(function()
        return node.Value
    end)
    if ok then
        return tonumber(raw)
    end
    return nil
end

local AreaTeleportMetaCache = nil
local WorldAreaCostFallback = {
    Winter = 50000000,
    Desert = 350000000000,
    Mines = 1000000000000000000,
    Cyber = 750000000000,
    Ocean = 5000000000000,
    ["Mushroom World"] = 1e+22,
    ["Space World"] = 2.5e+31,
    ["Heaven World"] = 5e+22,
    ["Hell World"] = 5e+22,
    ["The Garden"] = 2.5e+50
}
local WorldAreaCurrencyFallback = {
    Winter = "Leafs",
    Desert = "Ice",
    Mines = "Oil",
    Cyber = "Dust",
    Ocean = "Cores",
    ["Mushroom World"] = "Pearls",
    ["Space World"] = "Magic Energy",
    ["Heaven World"] = "Uranite",
    ["Hell World"] = "Divinity",
    ["The Garden"] = "Sins"
}

local function getAreaTeleportMeta(areaName)
    if type(areaName) ~= "string" or #areaName == 0 then
        return nil
    end
    if AreaTeleportMetaCache == nil then
        AreaTeleportMetaCache = {}
        local ok, moduleScript = pcall(function()
            return game:GetService("ReplicatedStorage").Shared.Modules.Extra.Teleporter
        end)
        if ok and moduleScript and moduleScript:IsA("ModuleScript") then
            local okReq, data = pcall(require, moduleScript)
            if okReq and type(data) == "table" then
                for key, entry in pairs(data) do
                    if type(key) == "string" and type(entry) == "table" then
                        AreaTeleportMetaCache[key] = {
                            Cost = tonumber(entry.cost),
                            Specs = entry.specs,
                            Event = entry.Event == true,
                            AlreadyUnlocked = entry.alreadyUnlocked == true
                        }
                    end
                end
            end
        end
    end
    return AreaTeleportMetaCache[areaName]
end

local function resolveAreaCurrencyName(areaName)
    local meta = getAreaTeleportMeta(areaName)
    local specs = meta and meta.Specs or nil
    if type(specs) == "string" and #specs > 0 then
        return specs
    end
    if type(specs) == "table" then
        local candidates = {
            specs.Name,
            specs.DisplayName,
            specs.SpecName,
            specs.gradientName
        }
        for _, name in ipairs(candidates) do
            if type(name) == "string" and #name > 0 then
                return name
            end
        end
    end
    return WorldAreaCurrencyFallback[areaName]
end

local function resolveAreaCost(areaName)
    local meta = getAreaTeleportMeta(areaName)
    local cost = meta and tonumber(meta.Cost) or nil
    if type(cost) == "number" then
        return cost
    end
    return WorldAreaCostFallback[areaName]
end

local function getAreaUnlockState(areaName)
    if not LP or type(areaName) ~= "string" or #areaName == 0 then
        return nil
    end
    local extra = LP:FindFirstChild("EXTRA")
    local areas = extra and findChildCaseInsensitive(extra, "AREAS") or nil
    local node = areas and findChildCaseInsensitive(areas, areaName) or nil
    local unlocked = nil
    if node then
        if node:IsA("BoolValue") then
            unlocked = node.Value == true
        else
            local valueNum = readNodeNumericValue(node)
            if type(valueNum) == "number" then
                unlocked = valueNum ~= 0
            end
        end
    end
    if unlocked == nil then
        local meta = getAreaTeleportMeta(areaName)
        if meta and meta.AlreadyUnlocked then
            unlocked = true
        end
    end
    return unlocked
end

local function getCurrencyAmountByName(currencyName)
    if not LP or type(currencyName) ~= "string" or #currencyName == 0 then
        return nil
    end
    local currencyRoot = LP:FindFirstChild("Currency")
    if not currencyRoot then
        return nil
    end
    local currencyFolder = findChildCaseInsensitive(currencyRoot, currencyName)
    if not currencyFolder then
        return nil
    end
    local amountFolder = findChildCaseInsensitive(currencyFolder, "Amount")
    if not amountFolder then
        return nil
    end
    local valueNode = amountFolder:FindFirstChild("1")
    if not valueNode then
        local children = amountFolder:GetChildren()
        if #children > 0 then
            valueNode = children[1]
        end
    end
    return readNodeNumericValue(valueNode)
end

local function teleportHomeSmart(areaName)
    if not areaName or areaName == "" then
        return
    end
    task.spawn(function()
        local unlocked = getAreaUnlockState(areaName)
        if unlocked == true then
            fireWorldTeleport(areaName)
            return
        end

        local cost = resolveAreaCost(areaName)
        local currencyName = resolveAreaCurrencyName(areaName)
        local amount = getCurrencyAmountByName(currencyName)
        local canBuy = false
        if type(cost) == "number" and type(amount) == "number" then
            canBuy = amount >= cost
        end

        if canBuy then
            fireBuyArea(areaName)
            return
        end

        local reasonCurrency = tostring(currencyName or "Currency")
        notify("Teleport to " .. tostring(areaName), "gagal memberi world " .. reasonCurrency .. " tidak cukup.", 5)
    end)
end

local function getPromptNotificationRemote()
    local ok, remote = pcall(function()
        return game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.PromptNotification
    end)
    if ok and remote and remote:IsA("RemoteEvent") then
        return remote
    end
    return nil
end

local function classifyPromptMessage(msg)
    if type(msg) ~= "string" then
        return nil
    end
    local lower = string.lower(msg)
    if string.find(lower, "you need to buy this area first", 1, true) then
        return "need_buy"
    end
    if (string.find(lower, "don't have enough", 1, true) or string.find(lower, "dont have enough", 1, true)) and
        string.find(lower, "to buy this area", 1, true) then
        return "not_enough"
    end
    return nil
end

local function waitPromptMessageMatch(timeoutSeconds)
    local remote = getPromptNotificationRemote()
    if not remote then
        return nil
    end
    local captured = nil
    local conn
    conn = remote.OnClientEvent:Connect(function(...)
        local args = {...}
        for _, v in ipairs(args) do
            if type(v) == "string" then
                local kind = classifyPromptMessage(v)
                if kind then
                    captured = {Kind = kind, Text = v}
                    break
                end
            end
        end
    end)
    local start = os.clock()
    local timeout = timeoutSeconds or 2.5
    while not captured and (os.clock() - start) < timeout do
        task.wait(0.05)
    end
    if conn then
        conn:Disconnect()
    end
    return captured
end

local function fireWithPromptWait(actionFn, timeoutSeconds)
    local remote = getPromptNotificationRemote()
    if not remote then
        actionFn()
        return nil
    end
    local captured = nil
    local conn
    conn = remote.OnClientEvent:Connect(function(...)
        local args = {...}
        for _, v in ipairs(args) do
            if type(v) == "string" then
                local kind = classifyPromptMessage(v)
                if kind then
                    captured = {Kind = kind, Text = v}
                    break
                end
            end
        end
    end)
    actionFn()
    local start = os.clock()
    local timeout = timeoutSeconds or 2.5
    while not captured and (os.clock() - start) < timeout do
        task.wait(0.05)
    end
    if conn then
        conn:Disconnect()
    end
    return captured
end

local function teleportHomeWithBuy(areaName)
    if not areaName or areaName == "" then
        return
    end
    task.spawn(function()
        local msg = fireWithPromptWait(function()
            fireWorldTeleport(areaName)
        end, 2.5)
        if not msg then
            return
        end
        if msg.Kind == "need_buy" then
            local buyMsg = fireWithPromptWait(function()
                fireBuyArea(areaName)
            end, 2.5)
            if buyMsg and buyMsg.Kind == "not_enough" then
                notify("Teleport to " .. areaName, "Uang tidak cukup", 5)
                return
            end
            task.wait(0.1)
            local retryMsg = fireWithPromptWait(function()
                fireWorldTeleport(areaName)
            end, 2.5)
            if retryMsg and retryMsg.Kind == "not_enough" then
                notify("Teleport to " .. areaName, "Uang tidak cukup", 5)
            end
            return
        end
        if msg.Kind == "not_enough" then
            notify("Teleport to " .. areaName, "Uang tidak cukup", 5)
        end
    end)
end

local function initWorldTeleports()
do
    local ForestTeleportSection = createSectionBox(State.Tabs.Forest:GetPage(), "Teleport")
    createButton(ForestTeleportSection, "Home", function()
        teleportHomeSmart("Forest")
    end)
    local ForestList = {
        {Label = "Reincarnation", Data = makeData(
            Vector3.new(5.688, 19.000, 22.620),
            CFrame.new(3.640704, 32.026222, -0.594986, -0.996133089, 0.038948622, -0.078752235, 0.000000000, 0.896365047, 0.443316728, 0.087857328, 0.441602468, -0.892898858),
            CFrame.new(5.688260, 20.499998, 22.620361, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            25.999973
        )},
        {Label = "Ticket Shop", Data = makeData(
            Vector3.new(-13.439, 19.201, 85.278),
            CFrame.new(5.131074, 27.627468, 90.108078, 0.251725823, -0.328588486, 0.910309672, 0.000000000, 0.940598249, 0.339521557, -0.967798591, -0.085466340, 0.236772880),
            CFrame.new(-13.439223, 20.701237, 85.277916, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            20.399977
        )},
        {Label = "Runes", Data = makeData(
            Vector3.new(-13.233, 20.099, -14.525),
            CFrame.new(-36.016521, 34.151733, 3.417183, 0.618687451, 0.312079877, -0.720993757, 0.000000000, 0.917718410, 0.397231579, 0.785637140, -0.245762199, 0.567780912),
            CFrame.new(-13.233118, 21.599215, -14.524694, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            31.600002
        )}
    }
    registerRuneLocations("Forest", ForestList)
    createGrid(ForestTeleportSection, ForestList, function(item)
        teleportWithData(item.Data)
    end)

    local ForestActionSection = createSectionBox(State.Tabs.Forest:GetPage(), "Action")
    local function fireReincarnation()
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return
        end
        pcall(function()
            remote:FireServer("Reincarnation")
        end)
    end
    createButton(ForestActionSection, "Reincarnation", function()
        fireReincarnation()
    end)

    local ForestAutomationSection = createSectionBox(State.Tabs.Forest:GetPage(), "Automation")
    local function fireLogsRankUp()
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return
        end
        pcall(function()
            remote:FireServer("LogRankUp")
        end)
    end
    createButton(ForestAutomationSection, "Rank Up Logs", function()
        fireLogsRankUp()
    end)
    setupAutoBuyGroup(ForestAutomationSection, {
        GroupKey = "Forest",
        DisplayName = "Auto Buy Shop",
        ResetMaxedOnPopup = {
            Match = {"PlantsGain", "Successfully Reached Leaf Reset"},
            ShopKey = {"Seeds"}
        },
        Shops = {
            {
                Key = "Seeds",
                DisplayName = "Seeds",
                ShopName = "Seeds",
            },
            {
                Key = "Plants",
                DisplayName = "Plants",
                ShopName = "Plants",
            },
            {
                Key = "Apples",
                DisplayName = "Apples",
                ShopName = "Apples",
            },
            {
                Key = "Leafs",
                DisplayName = "Leafs",
                ShopName = "Leafs"
            }
        }
    })

    local function readNumberValue(node)
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        return tonumber(raw)
    end

    local forestLogSection = createSubSectionBox(ForestAutomationSection, "Auto Log")
    local forestAutoLogToggle = nil
    State.ForestAutoLog = State.ForestAutoLog or {
        Enabled = Config.ForestAutoLogEnabled == true,
        OwnerKey = "ForestAutoLog",
        LogName = "Auto Log",
        Interval = 0.35,
        Accum = 0,
        Teleporting = false,
        SavedPivot = nil,
        LastTeleport = 0,
        LastAction = nil,
        Costs = nil,
        Wait = {
            Active = false,
            Target = nil,
            LevelBefore = nil,
            Since = 0,
            Timeout = 1.2
        },
        LastNotify = 0
    }

    local function readBoolValue(node)
        if not node then
            return false
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return false
        end
        if type(raw) == "boolean" then
            return raw
        end
        if type(raw) == "number" then
            return raw ~= 0
        end
        if type(raw) == "string" then
            local v = string.lower(raw)
            return v == "true" or v == "1" or v == "yes"
        end
        return false
    end

    local function getLogUnlockFlags()
        if not LP then
            return false, false, false, false
        end
        local unlocks = LP:FindFirstChild("Unlocked_Mechanic")
        return readBoolValue(unlocks and unlocks:FindFirstChild("Logs")),
            readBoolValue(unlocks and unlocks:FindFirstChild("AutoLogRankUp")),
            readBoolValue(unlocks and unlocks:FindFirstChild("AutoLogMulti")),
            readBoolValue(unlocks and unlocks:FindFirstChild("AutoLogSpeed"))
    end

    local function getLogRankLevel()
        if not LP then
            return nil
        end
        local resets = LP:FindFirstChild("Resets")
        local logs = resets and (resets:FindFirstChild("Logs") or resets:FindFirstChild("Log"))
        local n = readNumberValue(logs)
        if type(n) == "number" then
            return math.max(0, math.floor(n + 0.5))
        end
        return nil
    end

    local function getLogUpgradeLevel(name)
        if not LP or type(name) ~= "string" then
            return nil
        end
        local upgrades = LP:FindFirstChild("Upgrades")
        local logs = upgrades and upgrades:FindFirstChild("Logs")
        local node = logs and logs:FindFirstChild(name)
        local n = readNumberValue(node)
        if type(n) == "number" then
            return math.max(0, math.floor(n + 0.5))
        end
        return nil
    end

    local function getLogMultiLevel()
        return getLogUpgradeLevel("Log Multiplier")
    end

    local function getLogSpeedLevel()
        return getLogUpgradeLevel("Log Speed")
    end

    local function getLogsAmount()
        if not LP then
            return nil
        end
        local currency = LP:FindFirstChild("Currency")
        local logs = currency and currency:FindFirstChild("Logs")
        local amountFolder = logs and logs:FindFirstChild("Amount")
        local node = amountFolder and (amountFolder:FindFirstChild("1") or amountFolder:FindFirstChildWhichIsA("ValueBase"))
        if not node then
            return nil
        end
        local amount = nil
        local helpers = State.AutoBuyShop and State.AutoBuyShop.Helpers or nil
        if helpers and helpers.GetNumericValueFromNode then
            amount = helpers.GetNumericValueFromNode(node)
        end
        if type(amount) == "number" then
            return amount
        end
        return readNumberValue(node)
    end

    local function resolveLogCosts()
        if State.ForestAutoLog.Costs then
            return State.ForestAutoLog.Costs
        end
        local costs = {
            RankUp = {},
            Multi = {},
            Speed = {}
        }
        local ok, moduleScript = pcall(function()
            return game:GetService("ReplicatedStorage").Shared.Modules.LogModule
        end)
        if ok and moduleScript and moduleScript:IsA("ModuleScript") then
            local okReq, data = pcall(require, moduleScript)
            if okReq and type(data) == "table" then
                for _, entry in ipairs(data) do
                    if type(entry) == "table" and type(entry.Cost) == "table" then
                        local c = tonumber(entry.Cost[2])
                        if c then
                            costs.RankUp[#costs.RankUp + 1] = c
                        end
                    end
                end
            end
        end

        local okGain, logGainScript = pcall(function()
            return game:GetService("ReplicatedStorage").Shared.Modules.LogModule.LogGain
        end)
        if okGain and logGainScript and logGainScript:IsA("ModuleScript") then
            local okReq, data = pcall(require, logGainScript)
            if okReq and type(data) == "table" then
                local function appendCosts(entry, target)
                    if type(entry) ~= "table" or type(target) ~= "table" then
                        return
                    end
                    local costFn = entry.Cost
                    if type(costFn) ~= "function" then
                        return
                    end
                    local okFirst, _, maxCount = pcall(costFn, 1)
                    local max = tonumber(maxCount)
                    if not okFirst or not max or max <= 0 then
                        return
                    end
                    for i = 1, max do
                        local okCost, cost = pcall(costFn, i)
                        cost = tonumber(cost)
                        if okCost and cost then
                            target[#target + 1] = cost
                        end
                    end
                end
                appendCosts(data["Log Multiplier"], costs.Multi)
                appendCosts(data["Log Speed"], costs.Speed)
            end
        end

        State.ForestAutoLog.Costs = costs
        return costs
    end

    local function getNextCost(costs, level)
        if type(costs) ~= "table" or #costs == 0 then
            return nil
        end
        local lvl = tonumber(level)
        if type(lvl) ~= "number" then
            return costs[1]
        end
        lvl = math.max(0, math.floor(lvl + 0.5))
        local idx = lvl + 1
        return costs[idx]
    end

    local function getCurrentPivot()
        if not LP or not LP.Character then
            return nil
        end
        local ok, pivot = pcall(function()
            return LP.Character:GetPivot()
        end)
        if ok and pivot then
            return pivot
        end
        local hrp = LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            return hrp.CFrame
        end
        return nil
    end

    local function restoreForestAutoLogPosition()
        local auto = State.ForestAutoLog
        if not auto then
            return
        end
        if auto.SavedPivot and LP and LP.Character then
            pcall(function()
                LP.Character:PivotTo(auto.SavedPivot)
            end)
        end
        auto.Teleporting = false
        auto.SavedPivot = nil
        auto.LastTeleport = 0
        auto.LastAction = nil
        if auto.Wait then
            auto.Wait.Active = false
            auto.Wait.Target = nil
            auto.Wait.LevelBefore = nil
            auto.Wait.Since = 0
        end
        if State.AutomationTeleport and State.AutomationTeleport.Release then
            State.AutomationTeleport.Release(auto.OwnerKey)
        end
    end

    local function teleportForestAutoLog(targetName, targetPos, levelBefore)
        local auto = State.ForestAutoLog
        if not auto or not LP or not LP.Character then
            return false
        end
        local now = os.clock()
        if (now - (auto.LastTeleport or 0)) < 0.75 then
            return false
        end
        if State.AutomationTeleport and State.AutomationTeleport.TryAcquire and not State.AutomationTeleport.TryAcquire(auto.OwnerKey) then
            return false
        end
        if not auto.SavedPivot then
            auto.SavedPivot = getCurrentPivot()
        end
        local ok = pcall(function()
            LP.Character:PivotTo(CFrame.new(targetPos))
        end)
        if ok then
            auto.Teleporting = true
            auto.LastTeleport = now
            auto.LastAction = targetName
            if auto.Wait then
                auto.Wait.Active = true
                auto.Wait.Target = targetName
                auto.Wait.LevelBefore = levelBefore
                auto.Wait.Since = now
            end
            return true
        end
        if State.AutomationTeleport and State.AutomationTeleport.Release then
            State.AutomationTeleport.Release(auto.OwnerKey)
        end
        return false
    end

    local function forestAutoLogCheckTeleport()
        local auto = State.ForestAutoLog
        if not auto or not auto.Teleporting or not auto.Wait or not auto.Wait.Active then
            return false
        end
        local now = os.clock()
        local target = auto.Wait.Target
        local levelNow = nil
        if target == "Multi" then
            levelNow = getLogMultiLevel()
        elseif target == "Speed" then
            levelNow = getLogSpeedLevel()
        end
        if type(levelNow) == "number" and type(auto.Wait.LevelBefore) == "number" then
            if levelNow > auto.Wait.LevelBefore then
                restoreForestAutoLogPosition()
                return true
            end
        end
        if (now - (auto.Wait.Since or 0)) > (auto.Wait.Timeout or 1.2) then
            restoreForestAutoLogPosition()
        end
        return false
    end

    local function setForestAutoLogEnabled(enabled, silent)
        local auto = State.ForestAutoLog
        if not auto then
            return
        end
        auto.Enabled = enabled == true
        Config.ForestAutoLogEnabled = auto.Enabled
        saveConfig()
        if forestAutoLogToggle and forestAutoLogToggle.Set then
            forestAutoLogToggle:Set(auto.Enabled)
        end
        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive(auto.OwnerKey, auto.LogName, auto.Enabled)
        end
        if auto.Enabled then
            local logsUnlocked, autoRank, autoMulti, autoSpeed = getLogUnlockFlags()
            if not logsUnlocked then
                setForestAutoLogEnabled(false, true)
                return
            end
            if autoRank and autoMulti and autoSpeed then
                setForestAutoLogEnabled(false, true)
                if not silent then
                    notify("Auto Log", "Log automation is already unlocked by the system; this feature is not needed.", 5)
                end
                return
            end
            auto.Accum = 0
            autoBuySchedulerRegister(auto.OwnerKey, {
                Step = function()
                    if not auto.Enabled then
                        return false
                    end
                    local logsUnlockedNow, autoRankNow, autoMultiNow, autoSpeedNow = getLogUnlockFlags()
                    if not logsUnlockedNow then
                        setForestAutoLogEnabled(false, true)
                        return false
                    end
                    if autoRankNow and autoMultiNow and autoSpeedNow then
                        setForestAutoLogEnabled(false, true)
                        notify("Auto Log", "Log automation is already unlocked by the system; this feature is not needed.", 5)
                        return false
                    end
                    if auto.Teleporting then
                        forestAutoLogCheckTeleport()
                        return false
                    end
                    local amount = getLogsAmount()
                    if type(amount) ~= "number" then
                        return false
                    end
                    local costs = resolveLogCosts()
                    local rankCost = (not autoRankNow) and getNextCost(costs.RankUp, getLogRankLevel()) or nil
                    local multiCost = (not autoMultiNow) and getNextCost(costs.Multi, getLogMultiLevel()) or nil
                    local speedCost = (not autoSpeedNow) and getNextCost(costs.Speed, getLogSpeedLevel()) or nil

                    if rankCost and amount >= rankCost then
                        local remote = getMainRemote and getMainRemote() or nil
                        if not remote then
                            return false
                        end
                        local ok = pcall(function()
                            remote:FireServer("LogRankUp")
                        end)
                        if ok and AutoBuyLogState and AutoBuyLogState.AddActionCount then
                            AutoBuyLogState.AddActionCount(auto.OwnerKey, 1, false)
                        end
                        return ok
                    end

                    if multiCost and amount >= multiCost then
                        return teleportForestAutoLog("Multi", Vector3.new(-5.139, 18.303, -92.683), getLogMultiLevel())
                    end

                    if speedCost and amount >= speedCost then
                        return teleportForestAutoLog("Speed", Vector3.new(6.485, 18.289, -93.963), getLogSpeedLevel())
                    end

                    return false
                end
            })
        else
            autoBuySchedulerUnregister(auto.OwnerKey)
            restoreForestAutoLogPosition()
            auto.Accum = 0
        end
    end

    forestAutoLogToggle = createToggle(forestLogSection, "Auto Log", nil, State.ForestAutoLog.Enabled, function(v)
        setForestAutoLogEnabled(v == true, false)
    end)
    setForestAutoLogEnabled(State.ForestAutoLog.Enabled == true, true)

    local forestLeafSection = createSubSectionBox(ForestAutomationSection, "Auto Reset Leaf")
    State.ForestAutoLeafReset = State.ForestAutoLeafReset or {
        Enabled = false,
        Conn = nil,
        Accum = 0,
        Interval = 0.35,
        LastFire = 0,
        MinRemoteGap = 0.08,
        Costs = nil
    }

    local function resolveLeafResetCosts()
        if State.ForestAutoLeafReset.Costs and #State.ForestAutoLeafReset.Costs > 0 then
            return State.ForestAutoLeafReset.Costs
        end
        local costs = {}
        local ok, moduleData = pcall(function()
            return game:GetService("ReplicatedStorage").Shared.Modules.LeafResetModule
        end)
        if ok and moduleData and moduleData:IsA("ModuleScript") then
            local okReq, data = pcall(require, moduleData)
            if okReq and type(data) == "table" then
                for _, entry in ipairs(data) do
                    if type(entry) == "table" and type(entry.Cost) == "table" then
                        local c = tonumber(entry.Cost[2])
                        if c then
                            costs[#costs + 1] = c
                        end
                    end
                end
            end
        end
        table.sort(costs, function(a, b)
            return a < b
        end)
        State.ForestAutoLeafReset.Costs = costs
        return costs
    end

    local function getLeafAmount()
        if not LP then
            return nil
        end
        local currency = LP:FindFirstChild("Currency")
        local leafs = currency and currency:FindFirstChild("Leafs")
        local amountFolder = leafs and leafs:FindFirstChild("Amount")
        local node = amountFolder and amountFolder:FindFirstChild("1")
        if not node and amountFolder then
            local children = amountFolder:GetChildren()
            if #children > 0 then
                node = children[1]
            end
        end
        return readNumberValue(node)
    end

    local function getLeafResetLevel()
        if not LP then
            return nil
        end
        local directCandidates = {
            LP:FindFirstChild("LeafReset"),
            LP:FindFirstChild("LeafsReset"),
            LP:FindFirstChild("Leaf Reset")
        }
        for _, node in ipairs(directCandidates) do
            local n = readNumberValue(node)
            if n then
                return math.max(0, math.floor(n + 0.5))
            end
        end
        local resets = LP:FindFirstChild("Resets")
        if resets then
            local resetCandidates = {
                resets:FindFirstChild("LeafReset"),
                resets:FindFirstChild("LeafsReset"),
                resets:FindFirstChild("Leaf Reset")
            }
            for _, node in ipairs(resetCandidates) do
                local n = readNumberValue(node)
                if n then
                    return math.max(0, math.floor(n + 0.5))
                end
            end
        end
        return nil
    end

    local function canFireLeafReset(now)
        local auto = State.ForestAutoLeafReset
        if not auto then
            return false
        end
        local minGap = tonumber(auto.MinRemoteGap) or 0.08
        if (now - (auto.LastFire or 0)) < minGap then
            return false
        end
        local autoBuy = State.AutoBuyScheduler
        local autoBuyLast = autoBuy and autoBuy.LastClick or 0
        if (now - autoBuyLast) < minGap then
            return false
        end
        return true
    end

    local function shouldDoLeafReset()
        local amount = getLeafAmount()
        if type(amount) ~= "number" then
            return false, amount
        end
        local costs = resolveLeafResetCosts()
        if #costs == 0 then
            return false, amount
        end
        local level = getLeafResetLevel()
        if type(level) == "number" then
            local nextCost = costs[level + 1]
            if not nextCost then
                return false, amount
            end
            return amount >= nextCost, amount
        end
        return amount >= costs[1], amount
    end

    local function fireLeafReset()
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return false
        end
        local ok = pcall(function()
            remote:FireServer("LeafReset")
        end)
        if ok then
            State.ForestAutoLeafReset.LastFire = os.clock()
            return true
        end
        return false
    end

    createToggle(forestLeafSection, "Auto Reset Leaf", nil, State.ForestAutoLeafReset.Enabled, function(v)
        State.ForestAutoLeafReset.Enabled = v == true
        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive("ForestAutoResetLeaf", "Auto Reset Leaf", State.ForestAutoLeafReset.Enabled)
        end
        if State.ForestAutoLeafReset.Enabled then
            if State.ForestAutoLeafReset.Conn then
                State.ForestAutoLeafReset.Conn:Disconnect()
            end
            State.ForestAutoLeafReset.Accum = 0
            State.ForestAutoLeafReset.Conn = RunService.Heartbeat:Connect(function(dt)
                State.ForestAutoLeafReset.Accum += dt
                if State.ForestAutoLeafReset.Accum < State.ForestAutoLeafReset.Interval then
                    return
                end
                State.ForestAutoLeafReset.Accum = 0

                local shouldReset, amountBefore = shouldDoLeafReset()
                if not shouldReset then
                    return
                end
                local now = os.clock()
                if not canFireLeafReset(now) then
                    return
                end
                if fireLeafReset() then
                    task.delay(0.4, function()
                        if State.AutoBuyRuntime and State.AutoBuyRuntime.Forest and State.AutoBuyRuntime.Forest.RevalidateShop then
                            State.AutoBuyRuntime.Forest.RevalidateShop("Leafs")
                        end
                    end)
                end
            end)
            trackConnection(State.ForestAutoLeafReset.Conn)
        else
            if State.ForestAutoLeafReset.Conn then
                State.ForestAutoLeafReset.Conn:Disconnect()
                State.ForestAutoLeafReset.Conn = nil
            end
            State.ForestAutoLeafReset.Accum = 0
        end
    end)
end
    stepWorld("Forest")

do
    local WinterTeleportSection = createSectionBox(State.Tabs.Winter:GetPage(), "Teleport")
    createButton(WinterTeleportSection, "Home", function()
        teleportHomeSmart("Winter")
    end)
    local WinterList = {
        {Label = "Passive Shards Shop", Data = makeData(
            Vector3.new(1484.535, 18.098, 79.519),
            CFrame.new(1497.478760, 25.320576, 85.072540, 0.394256741, -0.345924526, 0.851409376, 0.000000000, 0.926451564, 0.376413971, -0.919000268, -0.148403749, 0.365259826),
            CFrame.new(1484.534668, 19.597879, 79.519424, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203153
        )},
        {Label = "Passive Roll", Data = makeData(
            Vector3.new(1516.296, 18.561, 83.984),
            CFrame.new(1503.163696, 26.569178, 79.943626, -0.294034064, 0.409156203, -0.863791168, 0.000000000, 0.903741121, 0.428079486, 0.955794930, 0.125869945, -0.265730679),
            CFrame.new(1516.296143, 20.060999, 83.983582, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203249
        )},
        {Label = "Tier Roll", Data = makeData(
            Vector3.new(1512.674, 15.997, 1.453),
            CFrame.new(1491.860840, 31.086452, 0.383994, -0.051283818, 0.545489192, -0.836547434, 0.000000000, 0.837649643, 0.546207964, 0.998684049, 0.028011629, -0.042957876),
            CFrame.new(1512.674194, 17.496799, 1.452786, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880047
        )},
        {Label = "Ice Shop", Data = makeData(
            Vector3.new(1474.930, 18.561, -98.030),
            CFrame.new(1486.628296, 25.966484, -94.269417, 0.306021839, -0.412391514, 0.858069837, 0.000000000, 0.901310682, 0.433173239, -0.952024460, -0.132560477, 0.275820762),
            CFrame.new(1474.930176, 20.060999, -98.029701, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633066
        )},
        {Label = "Milestone", Data = makeData(
            Vector3.new(1512.674, 15.997, 1.453),
            CFrame.new(1491.860840, 31.086452, 0.383994, -0.051283818, 0.545489192, -0.836547434, 0.000000000, 0.837649643, 0.546207964, 0.998684049, 0.028011629, -0.042957876),
            CFrame.new(1512.674194, 17.496799, 1.452786, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880047
        )},
        {Label = "Boss", Data = makeData(
            Vector3.new(1486.732, 18.393, -180.705),
            CFrame.new(1476.835571, 24.304148, -172.430679, 0.641454339, 0.248214230, -0.725896776, 0.000000000, 0.946211576, 0.323548943, 0.767161310, -0.207541868, 0.606951416),
            CFrame.new(1486.731812, 19.893179, -180.705292, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633101
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(1454.642, 15.610, -15.706),
            CFrame.new(1433.811646, 28.496862, -19.566528, -0.182229251, 0.465488881, -0.866090477, 0.000000000, 0.880839229, 0.473415673, 0.983256161, 0.086270183, -0.160514653),
            CFrame.new(1454.642456, 17.110479, -15.705901, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.051544
        )}
    }
    local winterTierRollData = nil
    for _, item in ipairs(WinterList) do
        if item and item.Label == "Tier Roll" then
            winterTierRollData = item.Data
            break
        end
    end
    registerRuneLocations("Winter", WinterList)
    createGrid(WinterTeleportSection, WinterList, function(item)
        teleportWithData(item.Data)
    end)

    local WinterAutomationSection = createSectionBox(State.Tabs.Winter:GetPage(), "Automation")
    setupAutoBuyGroup(WinterAutomationSection, {
        GroupKey = "Winter",
        DisplayName = "Auto Buy Shop",
        Shops = {
            {
                Key = "Ice",
                DisplayName = "Ice",
                ShopName = "Ice"
            },
            {
                Key = "Boss Shards",
                DisplayName = "Boss Shards",
                ShopName = "Boss Shards",
                ModuleName = "BossFight",
                RemoteShopName = "BossFight"
            }
        }
    })

    local winterAutoSection = createSubSectionBox(WinterAutomationSection, "Auto Snow")
    State.WinterAutoSnow = State.WinterAutoSnow or {
        Enabled = false,
        Conn = nil,
        Accum = 0,
        Interval = 0.35,
        LastFire = 0,
        MinRemoteGap = 0.08,
        TeleportingForTier = false,
        SavedPivot = nil,
        LastTierTeleport = 0,
        TierTeleportInterval = 1.0,
        TierValueBefore = nil,
        TeleportStartAt = 0,
        TierStallTimeout = 3.0
    }

    local function readNumeric(node)
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        return tonumber(raw)
    end

    local function readBool(node)
        if not node then
            return false
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return false
        end
        if type(raw) == "boolean" then
            return raw
        end
        if type(raw) == "number" then
            return raw ~= 0
        end
        if type(raw) == "string" then
            local v = string.lower(raw)
            return v == "true" or v == "1" or v == "yes"
        end
        return false
    end

    local function isWinterAreaUnlocked()
        if not LP then
            return false
        end
        local extra = LP:FindFirstChild("EXTRA")
        local areas = extra and extra:FindFirstChild("AREAS")
        local node = areas and areas:FindFirstChild("Winter")
        return readBool(node)
    end

    local function getSnowAmount()
        if not LP then
            return nil
        end
        local currency = LP:FindFirstChild("Currency")
        local snow = currency and currency:FindFirstChild("Snow")
        local amountFolder = snow and snow:FindFirstChild("Amount")
        local amountNode = amountFolder and amountFolder:FindFirstChild("1")
        if not amountNode and amountFolder then
            local children = amountFolder:GetChildren()
            if #children > 0 then
                amountNode = children[1]
            end
        end
        return readNumeric(amountNode)
    end

    local function getTierValue()
        if not LP then
            return nil
        end
        local tierRoot = LP:FindFirstChild("Tier")
        local tierNode = tierRoot and tierRoot:FindFirstChild("Tier")
        return readNumeric(tierNode)
    end

    local function getCharacterPivot()
        if not LP or not LP.Character then
            return nil
        end
        local ok, pivot = pcall(function()
            return LP.Character:GetPivot()
        end)
        if ok and pivot then
            return pivot
        end
        local hrp = LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            return hrp.CFrame
        end
        return nil
    end

    local function restoreWinterAutoSnowPosition()
        local auto = State.WinterAutoSnow
        if not auto then
            return
        end
        if auto.SavedPivot and LP and LP.Character then
            pcall(function()
                LP.Character:PivotTo(auto.SavedPivot)
            end)
        end
        auto.TeleportingForTier = false
        auto.SavedPivot = nil
        auto.LastTierTeleport = 0
        auto.TierValueBefore = nil
        auto.TeleportStartAt = 0
        if State.AutomationTeleport and State.AutomationTeleport.Release then
            State.AutomationTeleport.Release("WinterAutoSnow")
        end
    end

    local function teleportToWinterTierRoll(now, tierValue)
        local auto = State.WinterAutoSnow
        if not auto or not LP or not LP.Character then
            return false
        end
        if not winterTierRollData or not winterTierRollData.position then
            return false
        end
        if State.AutomationTeleport and State.AutomationTeleport.TryAcquire and not State.AutomationTeleport.TryAcquire("WinterAutoSnow") then
            return false
        end
        if not auto.SavedPivot then
            auto.SavedPivot = getCharacterPivot()
        end
        local ok = pcall(function()
            LP.Character:PivotTo(CFrame.new(winterTierRollData.position))
        end)
        if ok then
            auto.TeleportingForTier = true
            auto.LastTierTeleport = now or os.clock()
            auto.TeleportStartAt = now or os.clock()
            auto.TierValueBefore = tierValue
        else
            if State.AutomationTeleport and State.AutomationTeleport.Release then
                State.AutomationTeleport.Release("WinterAutoSnow")
            end
        end
        return ok
    end

    local function canFireSnowReset(now)
        local auto = State.WinterAutoSnow
        if not auto then
            return false
        end
        local minGap = tonumber(auto.MinRemoteGap) or 0.08
        if (now - (auto.LastFire or 0)) < minGap then
            return false
        end
        local autoBuy = State.AutoBuyScheduler
        local autoBuyLast = autoBuy and autoBuy.LastClick or 0
        if (now - autoBuyLast) < minGap then
            return false
        end
        return true
    end

    local function fireSnowReset()
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return false
        end
        local ok = pcall(function()
            remote:FireServer("TierReset")
        end)
        if ok then
            State.WinterAutoSnow.LastFire = os.clock()
            return true
        end
        return false
    end

    local function setWinterAutoSnowEnabled(enabled, reason)
        State.WinterAutoSnow.Enabled = enabled == true
        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive("WinterAutoSnow", "Auto Snow", State.WinterAutoSnow.Enabled)
        end
        if State.WinterAutoSnow.Enabled then
            if not isWinterAreaUnlocked() then
                State.WinterAutoSnow.Enabled = false
                if type(notify) == "function" then
                    notify("Auto Snow", "Area Locked", 3)
                end
                if State.WinterAutoSnow.Conn then
                    State.WinterAutoSnow.Conn:Disconnect()
                    State.WinterAutoSnow.Conn = nil
                end
                State.WinterAutoSnow.Accum = 0
                restoreWinterAutoSnowPosition()
                if State.WinterAutoSnow.Toggle and State.WinterAutoSnow.Toggle.Set then
                    State.WinterAutoSnow.Toggle:Set(false)
                end
                return
            end
            if State.WinterAutoSnow.Conn then
                State.WinterAutoSnow.Conn:Disconnect()
            end
            State.WinterAutoSnow.Accum = 0
            State.WinterAutoSnow.Conn = RunService.Heartbeat:Connect(function(dt)
                State.WinterAutoSnow.Accum += dt
                if State.WinterAutoSnow.Accum < State.WinterAutoSnow.Interval then
                    return
                end
                State.WinterAutoSnow.Accum = 0

                local snowAmount = getSnowAmount()
                local tierValue = getTierValue()
                if type(snowAmount) ~= "number" or type(tierValue) ~= "number" then
                    return
                end
                local now = os.clock()
                if State.WinterAutoSnow.TeleportingForTier and State.WinterAutoSnow.TierValueBefore ~= nil then
                    local timeout = tonumber(State.WinterAutoSnow.TierStallTimeout) or 3.0
                    if (now - (State.WinterAutoSnow.TeleportStartAt or 0)) >= timeout then
                        if tierValue == State.WinterAutoSnow.TierValueBefore then
                            if not isWinterAreaUnlocked() then
                                setWinterAutoSnowEnabled(false, "locked")
                                if type(notify) == "function" then
                                    notify("Auto Snow", "Area Locked", 3)
                                end
                                return
                            end
                        end
                        State.WinterAutoSnow.TeleportStartAt = now
                        State.WinterAutoSnow.TierValueBefore = tierValue
                    end
                end
                if snowAmount ~= 0 then
                    if State.WinterAutoSnow.TeleportingForTier then
                        restoreWinterAutoSnowPosition()
                    end
                    return
                end
                if tierValue <= 1 then
                    local interval = tonumber(State.WinterAutoSnow.TierTeleportInterval) or 1.0
                    if (now - (State.WinterAutoSnow.LastTierTeleport or 0)) >= interval then
                        teleportToWinterTierRoll(now, tierValue)
                    end
                    return
                end

                if State.WinterAutoSnow.TeleportingForTier then
                    restoreWinterAutoSnowPosition()
                end
                if not canFireSnowReset(now) then
                    return
                end
                fireSnowReset()
            end)
            trackConnection(State.WinterAutoSnow.Conn)
        else
            if State.WinterAutoSnow.Conn then
                State.WinterAutoSnow.Conn:Disconnect()
                State.WinterAutoSnow.Conn = nil
            end
            State.WinterAutoSnow.Accum = 0
            restoreWinterAutoSnowPosition()
        end
    end

    State.WinterAutoSnow.Toggle = createToggle(winterAutoSection, "Auto Snow", nil, State.WinterAutoSnow.Enabled, function(v)
        setWinterAutoSnowEnabled(v == true, "ui")
    end)
    if State.WinterAutoSnow.Toggle and State.WinterAutoSnow.Toggle.Set then
        State.WinterAutoSnow.Toggle:Set(State.WinterAutoSnow.Enabled)
    end
end
    stepWorld("Winter")

do
    local DesertTeleportSection = createSectionBox(State.Tabs.Desert:GetPage(), "Teleport")
    createButton(DesertTeleportSection, "Home", function()
        teleportHomeSmart("Desert")
    end)
    local DesertList = {
        {Label = "Sacrifice", Data = makeData(
            Vector3.new(2614.331, 14.993, 49.230),
            CFrame.new(2619.790039, 23.690708, 37.002373, -0.913122058, -0.193005964, 0.359105527, 0.000000000, 0.880837977, 0.473417908, -0.407686234, 0.432288349, -0.804312646),
            CFrame.new(2614.330566, 16.493240, 49.230499, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203174
        )},
        {Label = "Better Points", Data = makeData(
            Vector3.new(2559.386, 14.493, -2.146),
            CFrame.new(2546.067627, 21.795351, 2.336460, 0.318965644, 0.361703217, -0.876031816, 0.000000000, 0.924312115, 0.381637543, 0.947766304, -0.121729262, 0.294823796),
            CFrame.new(2559.386230, 15.993239, -2.145805, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203302
        )},
        {Label = "Oil Shop", Data = makeData(
            Vector3.new(2618.648, 15.210, -49.626),
            CFrame.new(2608.193604, 21.872202, -39.869930, 0.682258964, 0.248230696, -0.687680304, 0.000000000, 0.940596819, 0.339525521, 0.731110573, -0.231644332, 0.641730666),
            CFrame.new(2618.648438, 16.710327, -49.626289, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203126
        )},
        {Label = "Fossils", Data = makeData(
            Vector3.new(2645.560, 14.493, 6.615),
            CFrame.new(2630.879883, 19.511374, 4.807576, -0.122209154, 0.229672924, -0.965564787, 0.000000000, 0.972856939, 0.231407478, 0.992504358, 0.028280113, -0.118892029),
            CFrame.new(2645.559570, 15.993239, 6.615115, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203214
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(2447.432, 12.081, -8.576),
            CFrame.new(2436.589111, 22.728329, -14.044039, -0.450248271, 0.537215114, -0.713215590, 0.000000000, 0.798760056, 0.601649761, 0.892903388, 0.270891756, -0.359640360),
            CFrame.new(2447.432373, 13.581326, -8.576355, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203275
        )}
    }
    registerRuneLocations("Desert", DesertList)
    createGrid(DesertTeleportSection, DesertList, function(item)
        teleportWithData(item.Data)
    end)

    local DesertAutomationSection = createSectionBox(State.Tabs.Desert:GetPage(), "Automation")
    setupAutoBuyGroup(DesertAutomationSection, {
        GroupKey = "Desert",
        DisplayName = "Auto Buy Shop",
        Shops = {
            {
                Key = "Sand",
                DisplayName = "Sand",
                ShopName = "Sand"
            },
            {
                Key = "Oil",
                DisplayName = "Oil",
                ShopName = "Oil"
            }
        }
    })

    local desertUpgradeSection = createSubSectionBox(DesertAutomationSection, "Auto Upgrade Tree")

    local PointsTreeKeys = {
        Start = true,
        ["Points Multiplier"] = true,
        ["Point Speed Gain"] = true,
        MoreLevel_For2 = true,
        PointBooster1 = true,
        MoreSeedUpgrade1 = true,
        SeedMulti1 = true,
        CheaperCost_For6 = true,
        ["Faster Logs"] = true,
        ["Point Multiplier 2"] = true,
        ["Log Multi1"] = true,
        CheaperCost_For11 = true,
        ["Point Multiplier 3"] = true,
        PointBooster2 = true,
        InstantLeaf = true,
        MoreLeafUpgrade1 = true,
        ["Point Multiplier 4"] = true,
        MorePlantUpgrade1 = true,
        PlantBoostLeaf = true,
        GC_Boost1 = true,
        RC_Boost1 = true,
        Walkspeed1 = true,
        Unlock_Sand = true,
        ["Point Multiplier 5"] = true,
        SandMulti1 = true,
        ConversionUnlock1 = true,
        RuneLuck1 = true,
        RuneBulk1 = true,
        TierLuck1 = true,
        TierBulk1 = true,
        TierTimer1 = true,
        SandCapacityMulti1 = true,
        SandTime1 = true,
        AutoTier = true,
        SnowMulti1 = true,
        MoreSnowMilestone1 = true,
        PassiveChanceMulti1 = true,
        MoreBossUpgrade1 = true,
        IceMulti1 = true,
        ["Point Multiplier 6"] = true,
        MoreIceUpgrade1 = true,
        PointBooster3 = true,
        BossSpawnTime1 = true,
        ["Better Ice Point Formula"] = true,
        TierTimer2 = true,
        TierLuck2 = true,
        TierBulk2 = true,
        Tier_BoostIce = true,
        Unlock_BetterPoints = true
    }

    local BetterPointsTreeKeys = {
        BP_Point1 = true,
        BP_Point2 = true,
        BP_PlantsGeneration = true,
        BP_AutoApple = true,
        BP_AutoSeeds = true,
        BP_ClickTree = true,
        BP_BetterPoint1 = true,
        BP_Sand1 = true,
        BP_SandCapacity1 = true,
        BP_SandConversion1 = true,
        BP_FasterLeaf1 = true,
        BP_AutoLeafRank = true,
        BP_AutoLeafs = true,
        BP_SandSpeed1 = true,
        BP_AutoPlants = true,
        BP_LogMulti = true,
        BP_LogSpeed = true,
        BP_AutoLogRankUp = true,
        BP_BetterPoint2 = true,
        BP_BetterPoint3 = true,
        BP_Fossils1 = true,
        BP_RuneLuck1 = true,
        BP_RuneBulk1 = true,
        BP_TierLuck1 = true,
        BP_TierBulk1 = true,
        BP_Oil1 = true,
        BP_AutoOil = true
    }

    local function desertReadNumber(node)
        local helpers = State.AutoBuyShop and State.AutoBuyShop.Helpers or nil
        if helpers and helpers.GetNumericValueFromNode then
            local n = helpers.GetNumericValueFromNode(node)
            if type(n) == "number" then
                return n
            end
        end
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        local n = tonumber(raw)
        if type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge then
            return n
        end
        return nil
    end

    local function desertReadString(node)
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if ok and type(raw) == "string" and #raw > 0 then
            return raw
        end
        return nil
    end

    local function desertFindChildCaseInsensitive(parent, name)
        if not parent or type(name) ~= "string" or #name == 0 then
            return nil
        end
        local direct = parent:FindFirstChild(name)
        if direct then
            return direct
        end
        local target = string.lower(name)
        for _, child in ipairs(parent:GetChildren()) do
            if string.lower(tostring(child.Name)) == target then
                return child
            end
        end
        return nil
    end

    local function desertGetUpgradeNode(key)
        if not LP or type(key) ~= "string" or #key == 0 then
            return nil
        end
        local treeRoot = LP:FindFirstChild("UpgradeTree")
        if not treeRoot then
            return nil
        end
        return desertFindChildCaseInsensitive(treeRoot, key)
    end

    local function desertGetUpgradeAmount(key)
        local node = desertGetUpgradeNode(key)
        local amountNode = node and node:FindFirstChild("Amount")
        local amount = desertReadNumber(amountNode)
        if type(amount) == "number" then
            return math.max(0, math.floor(amount + 0.5))
        end
        return 0
    end

    local function desertIsUnlocked(key)
        local node = desertGetUpgradeNode(key)
        local unlockedNode = node and node:FindFirstChild("Unlocked")
        if not unlockedNode then
            return false
        end
        local ok, value = pcall(function()
            return unlockedNode.Value
        end)
        return ok and value == true
    end

    local function desertGetLevelLimit(key)
        local node = desertGetUpgradeNode(key)
        local special = node and node:FindFirstChild("SpecialConditions")
        local limitNode = special and special:FindFirstChild("LevelLimit")
        local limit = desertReadNumber(limitNode)
        if type(limit) == "number" and limit > 0 then
            return math.max(1, math.floor(limit + 0.5))
        end
        return nil
    end

    local function desertGetCurrencyAmount(currencyName)
        if not LP or type(currencyName) ~= "string" or #currencyName == 0 then
            return nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        if not currencyRoot then
            return nil
        end
        local currencyFolder = desertFindChildCaseInsensitive(currencyRoot, currencyName)
        if not currencyFolder then
            return nil
        end
        local amountRoot = currencyFolder:FindFirstChild("Amount")
        local amountNode = amountRoot and (amountRoot:FindFirstChild("1") or amountRoot:FindFirstChildWhichIsA("ValueBase"))
        return desertReadNumber(amountNode)
    end

    local function desertReadValueByNames(parent, names)
        if not parent or type(names) ~= "table" then
            return nil
        end
        for _, name in ipairs(names) do
            local node = desertFindChildCaseInsensitive(parent, name)
            local value = desertReadNumber(node)
            if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
                return value
            end
        end
        return nil
    end

    local function desertReadCostFromUpgradeNode(node)
        if not node then
            return nil
        end
        local direct = desertReadValueByNames(node, {"NextCost", "CurrentCost", "Cost", "Price"})
        if type(direct) == "number" and direct > 0 then
            return direct
        end

        local special = node:FindFirstChild("SpecialConditions")
        local specialCost = desertReadValueByNames(special, {"NextCost", "CurrentCost", "Cost", "Price"})
        if type(specialCost) == "number" and specialCost > 0 then
            return specialCost
        end

        local function normalizeName(text)
            local out = string.lower(tostring(text or ""))
            out = out:gsub("[%s%-%_]+", "")
            return out
        end

        local function scoreCostField(nameLower)
            if type(nameLower) ~= "string" or #nameLower == 0 then
                return nil
            end
            local blocked = {
                "decrease",
                "discount",
                "multiply",
                "multiplier",
                "reward",
                "cooldown",
                "unlock",
                "required",
                "requirement",
                "level",
                "limit",
                "max",
                "min"
            }
            for _, token in ipairs(blocked) do
                if string.find(nameLower, token, 1, true) then
                    return nil
                end
            end
            if nameLower == "nextcost" then
                return 110
            end
            if nameLower == "currentcost" then
                return 100
            end
            if nameLower == "upgradecost" then
                return 95
            end
            if nameLower == "cost" then
                return 90
            end
            if nameLower == "price" then
                return 80
            end
            if nameLower:sub(-4) == "cost" then
                return 70
            end
            if nameLower:sub(-5) == "price" then
                return 60
            end
            return nil
        end

        local bestValue = nil
        local bestScore = nil
        for _, desc in ipairs(node:GetDescendants()) do
            local parentName = normalizeName((desc.Parent and desc.Parent.Name) or "")
            if string.find(parentName, "unlock", 1, true) == nil
                and string.find(parentName, "require", 1, true) == nil
                and string.find(parentName, "level", 1, true) == nil
                and string.find(parentName, "reward", 1, true) == nil then
                local name = normalizeName(desc.Name or "")
                local score = scoreCostField(name)
                if score then
                    local value = desertReadNumber(desc)
                    if type(value) == "number" and value == value and value > 0 and value ~= math.huge and value ~= -math.huge then
                        if bestValue == nil
                            or score > bestScore
                            or (score == bestScore and value > bestValue) then
                            bestValue = value
                            bestScore = score
                        end
                    end
                end
            end
        end
        return bestValue
    end

    local function desertFormatProgressDisplay(nameOrItem, amount, maxLevel, maxLabel, cost)
        local name = "-"
        if type(nameOrItem) == "table" then
            name = tostring((nameOrItem.DisplayName or nameOrItem.Key) or "-")
        else
            name = tostring(nameOrItem or "-")
        end
        local ownText = tostring(tonumber(amount) or 0)
        local maxText = type(maxLabel) == "string" and #maxLabel > 0 and maxLabel
            or (type(maxLevel) == "number" and tostring(maxLevel) or "?")
        local costText = type(cost) == "number" and autoBuyLogFormatNumber(cost) or "?"
        return name .. " (" .. ownText .. "/" .. maxText .. ") | Cost: " .. tostring(costText)
    end

    State.DesertUpgradeTreeModuleCache = State.DesertUpgradeTreeModuleCache or {}
    local function desertGetUpgradeTreeModule(moduleName)
        if type(moduleName) ~= "string" or #moduleName == 0 then
            return nil
        end
        local cache = State.DesertUpgradeTreeModuleCache
        local cached = cache[moduleName]
        if cached ~= nil then
            return cached or nil
        end
        local ok, moduleScript = pcall(function()
            local root = game:GetService("ReplicatedStorage").Shared.Modules:FindFirstChild("UpgradeTree")
            return root and root:FindFirstChild(moduleName)
        end)
        if ok and moduleScript and moduleScript:IsA("ModuleScript") then
            local okReq, data = pcall(require, moduleScript)
            if okReq and type(data) == "table" then
                local map = {}
                for key, entry in pairs(data) do
                    if type(entry) == "table" then
                        map[key] = entry
                    end
                end
                local out = {Data = data, Map = map}
                cache[moduleName] = out
                return out
            end
        end
        cache[moduleName] = false
        return nil
    end

    local function createDesertAutoUpgrade(def)
        if type(def) ~= "table" then
            return
        end

        Config[def.ConfigFlag] = Config[def.ConfigFlag] == true
        State[def.StateKey] = State[def.StateKey] or {
            Enabled = Config[def.ConfigFlag] == true,
            OwnerKey = def.SchedulerKey,
            Cache = nil,
            LastUpgradeDisplay = "-",
            LastCheckDisplay = "-",
            PendingUpgrade = nil,
            FailedByKey = {}
        }

        local function buildCurrencyText()
            local list = type(def.CurrencyList) == "table" and def.CurrencyList or {}
            local parts = {}
            for _, currencyName in ipairs(list) do
                local amount = desertGetCurrencyAmount(currencyName)
                if type(amount) == "number" then
                    parts[#parts + 1] = tostring(currencyName) .. " " .. tostring(autoBuyLogFormatNumber(amount))
                end
            end
            if #parts == 0 then
                return "-"
            end
            return table.concat(parts, " | ")
        end

        local function buildLogUpdate(meta, forceRefresh)
            if not AutoBuyLogState then
                return
            end
            local data = AutoBuyLogState.ActionData[def.ActionKey] or {
                Key = def.ActionKey,
                Name = def.ActionName,
                Success = 0
            }
            data.Key = def.ActionKey
            data.Name = def.ActionName
            data.Success = tonumber(data.Success) or 0
            local lastUpgrade = (meta and meta.LastUpgrade) or "-"
            local lastCheck = (meta and meta.LastCheck) or "-"
            local locked = tonumber(meta and meta.Locked) or 0
            local unlocked = tonumber(meta and meta.Unlocked) or 0
            local totalItem = tonumber(meta and meta.TotalItem) or 0
            local totalMax = tonumber(meta and meta.TotalMax) or 0
            local currencyText = tostring((meta and meta.CurrencyText) or "-")
            data.CurrencyText = currencyText
            data.DetailText =
                "Last Upgrade: " .. tostring(lastUpgrade)
                .. "\n----------------"
                .. "\nLast Check: " .. tostring(lastCheck)
                .. "\n----------------"
                .. "\nLocked: " .. tostring(locked) .. " | Unlocked: " .. tostring(unlocked)
                .. "\n----------------"
                .. "\nTotal Item: " .. tostring(totalItem) .. " | Total Max: " .. tostring(totalMax)
            AutoBuyLogState.ActionData[def.ActionKey] = data
            if AutoBuyLogState.ActiveActions[def.ActionKey] then
                AutoBuyLogState.ActiveActions[def.ActionKey] = data
                if forceRefresh ~= false then
                    updateAutoBuyLogUI()
                end
            end
        end

        local function getItems(state)
            if state and type(state.Cache) == "table" and type(state.Cache.Items) == "table" and type(state.Cache.TreeRoot) == "Instance" then
                if state.Cache.TreeRoot.Parent and #state.Cache.TreeRoot:GetChildren() == (state.Cache.TreeCount or 0) then
                    return state.Cache
                end
            end
            local treeRoot = LP and LP:FindFirstChild("UpgradeTree")
            if not treeRoot then
                return nil
            end
            local items = {}
            for _, child in ipairs(treeRoot:GetChildren()) do
                if child and type(child.Name) == "string" then
                    local key = tostring(child.Name)
                    if def.KeySet[key] then
                        local displayName = desertReadString(desertFindChildCaseInsensitive(child, "DisplayName")) or key
                        local currencyName = desertReadString(desertFindChildCaseInsensitive(child, "UpgradeCurrency")) or def.DefaultCurrency
                        items[#items + 1] = {
                            Key = key,
                            DisplayName = displayName,
                            UpgradeCurrency = currencyName,
                            RuntimeNode = child
                        }
                    end
                end
            end
            table.sort(items, function(a, b)
                return tostring(a.Key) < tostring(b.Key)
            end)
            if #items == 0 then
                return state and state.Cache or nil
            end
            local cache = {
                Items = items,
                TreeRoot = treeRoot,
                TreeCount = #treeRoot:GetChildren()
            }
            if state then
                state.Cache = cache
            end
            return cache
        end

        local function processPending(state)
            if not state then
                return false, false
            end
            local pending = state.PendingUpgrade
            if type(pending) ~= "table" or type(pending.Key) ~= "string" then
                state.PendingUpgrade = nil
                return false, false
            end
            local amountNow = desertGetUpgradeAmount(pending.Key)
            local amountBefore = tonumber(pending.AmountBefore) or 0
            if type(amountNow) == "number" and amountNow > amountBefore then
                state.LastUpgradeDisplay = desertFormatProgressDisplay(
                    tostring(pending.DisplayName or pending.Key or "-"),
                    amountNow,
                    tonumber(pending.MaxLevel),
                    pending.MaxLabel,
                    tonumber(pending.Cost)
                )
                if AutoBuyLogState and AutoBuyLogState.AddActionCount then
                    AutoBuyLogState.AddActionCount(def.ActionKey, 1, false)
                end
                state.PendingUpgrade = nil
                return true, false
            end
            local now = os.clock()
            local since = tonumber(pending.Since) or now
            local timeout = tonumber(pending.Timeout) or 1.25
            if (now - since) < timeout then
                return false, true
            end
            state.PendingUpgrade = nil
            return false, false
        end

        local moduleCache = desertGetUpgradeTreeModule(def.ModuleName)

        local function resolveModuleCostAndMax(itemKey, itemAmount, runtimeNode)
            if not moduleCache or type(moduleCache.Map) ~= "table" then
                return nil, nil
            end
            local entry = moduleCache.Map[itemKey]
            if not entry or type(entry.Cost) ~= "function" then
                return nil, nil
            end
            local levelExtra = nil
            local special = runtimeNode and runtimeNode:FindFirstChild("SpecialConditions")
            levelExtra = desertReadNumber(special and special:FindFirstChild("LevelLimit"))
            local specialAmount = nil
            if type(entry.specialAmount) == "string" and #entry.specialAmount > 0 then
                specialAmount = desertGetCurrencyAmount(entry.specialAmount)
            end
            local okCost, costValue, maxCount = pcall(entry.Cost, (tonumber(itemAmount) or 0) + 1, levelExtra, specialAmount)
            if okCost then
                return tonumber(costValue), tonumber(maxCount)
            end
            return nil, nil
        end

        local function step()
            local state = State[def.StateKey]
            if not state or not state.Enabled then
                return false
            end
            local _, pendingWaiting = processPending(state)
            local moduleData = getItems(state)
            local items = moduleData and moduleData.Items or nil
            if type(items) ~= "table" or #items == 0 then
                buildLogUpdate({
                    LastUpgrade = state.LastUpgradeDisplay or "-",
                    LastCheck = state.LastCheckDisplay or "-",
                    Locked = 0,
                    Unlocked = 0,
                    TotalItem = 0,
                    TotalMax = 0,
                    CurrencyText = buildCurrencyText()
                }, true)
                return false
            end

            local locked = 0
            local unlocked = 0
            local totalMax = 0
            local totalItem = #items
            local target = nil
            local firstCheckCandidate = nil

            for _, item in ipairs(items) do
                local amount = desertGetUpgradeAmount(item.Key)
                local maxLevel = desertGetLevelLimit(item.Key)
                local cost = desertReadCostFromUpgradeNode(item.RuntimeNode)
                local moduleCost, moduleMax = resolveModuleCostAndMax(item.Key, amount, item.RuntimeNode)
                if type(moduleMax) == "number" and moduleMax > 0 then
                    maxLevel = moduleMax
                end
                local maxLabel = type(maxLevel) == "number" and tostring(maxLevel) or "?"
                local isUnlocked = desertIsUnlocked(item.Key)
                if isUnlocked then
                    unlocked += 1
                else
                    locked += 1
                end

                if type(cost) ~= "number" or cost < 0 then
                    cost = moduleCost
                end
                local isMaxed = type(maxLevel) == "number" and amount >= maxLevel
                if isMaxed then
                    totalMax += 1
                end

                if not firstCheckCandidate and isUnlocked and not isMaxed then
                    firstCheckCandidate = {
                        Item = item,
                        Amount = amount,
                        MaxLevel = maxLevel,
                        MaxLabel = maxLabel,
                        Cost = cost
                    }
                end

                if (not pendingWaiting) and (not target) and isUnlocked and (not isMaxed) and type(cost) == "number" and cost >= 0 then
                    local ownCurrency = desertGetCurrencyAmount(item.UpgradeCurrency)
                    if type(ownCurrency) == "number" and ownCurrency >= cost then
                        target = {
                            Item = item,
                            Amount = amount,
                            Cost = cost,
                            MaxLevel = maxLevel,
                            MaxLabel = maxLabel
                        }
                    end
                end
            end

            if target and target.Item then
                state.LastCheckDisplay = desertFormatProgressDisplay(target.Item, target.Amount, target.MaxLevel, target.MaxLabel, target.Cost)
            elseif type(firstCheckCandidate) == "table" and firstCheckCandidate.Item then
                state.LastCheckDisplay = desertFormatProgressDisplay(firstCheckCandidate.Item, firstCheckCandidate.Amount, firstCheckCandidate.MaxLevel, firstCheckCandidate.MaxLabel, firstCheckCandidate.Cost)
            else
                state.LastCheckDisplay = "-"
            end

            buildLogUpdate({
                LastUpgrade = state.LastUpgradeDisplay or "-",
                LastCheck = state.LastCheckDisplay or "-",
                Locked = locked,
                Unlocked = unlocked,
                TotalItem = totalItem,
                TotalMax = totalMax,
                CurrencyText = buildCurrencyText()
            }, true)

            if not target then
                return false
            end

            local remoteArg = target.Item.Key
            local remote = getMainRemote and getMainRemote() or nil
            if not remote then
                pcall(function()
                    remote = game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
                end)
            end
            if not remote then
                return false
            end
            local okFire = pcall(function()
                remote:FireServer("UpgradeTree", remoteArg)
            end)
            if okFire then
                state.PendingUpgrade = {
                    Key = tostring(target.Item.Key or ""),
                    DisplayName = tostring(target.Item.DisplayName or target.Item.Key or remoteArg),
                    AmountBefore = tonumber(target.Amount) or 0,
                    MaxLevel = tonumber(target.MaxLevel),
                    MaxLabel = target.MaxLabel,
                    Cost = tonumber(target.Cost),
                    Since = os.clock(),
                    Timeout = 1.25
                }
            end
            return okFire == true
        end

        local function setEnabled(enabled)
            local state = State[def.StateKey]
            if not state then
                return
            end
            state.Enabled = enabled == true
            Config[def.ConfigFlag] = state.Enabled
            saveConfig()

            if AutoBuyLogState and AutoBuyLogState.SetActionActive then
                AutoBuyLogState.SetActionActive(def.ActionKey, def.ActionName, state.Enabled)
            end

            if state.Enabled then
                state.LastCheckDisplay = "-"
                state.PendingUpgrade = nil
                autoBuySchedulerRegister(def.SchedulerKey, {Step = step})
                step()
            else
                state.LastCheckDisplay = "-"
                state.PendingUpgrade = nil
                autoBuySchedulerUnregister(def.SchedulerKey)
                buildLogUpdate({
                    LastUpgrade = "-",
                    LastCheck = "-",
                    Locked = 0,
                    Unlocked = 0,
                    TotalItem = 0,
                    TotalMax = 0,
                    CurrencyText = "-"
                }, true)
            end
        end

        if State.CleanupRegistry and State.CleanupRegistry.Register then
            State.CleanupRegistry.Register(function()
                autoBuySchedulerUnregister(def.SchedulerKey)
            end)
        end

        local state = State[def.StateKey]
        createToggle(desertUpgradeSection, def.ToggleLabel, nil, state.Enabled, function(v)
            setEnabled(v == true)
        end)
        setEnabled(state.Enabled == true)
    end

    createDesertAutoUpgrade({
        ConfigFlag = "DesertAutoUpgradePointsTreeEnabled",
        StateKey = "DesertAutoUpgradePointsTree",
        SchedulerKey = "DesertAutoUpgradePointsTree",
        ActionKey = "DesertAutoUpgradePointsTree",
        ActionName = "Auto Upgrade Points Tree",
        ToggleLabel = "Auto Upgrade Points Tree",
        ModuleName = "Points",
        DefaultCurrency = "Points",
        CurrencyList = {"Points", "Better Points"},
        KeySet = PointsTreeKeys
    })

    createDesertAutoUpgrade({
        ConfigFlag = "DesertAutoUpgradeBetterPointsTreeEnabled",
        StateKey = "DesertAutoUpgradeBetterPointsTree",
        SchedulerKey = "DesertAutoUpgradeBetterPointsTree",
        ActionKey = "DesertAutoUpgradeBetterPointsTree",
        ActionName = "Auto Upgrade Better Points Tree",
        ToggleLabel = "Auto Upgrade Better Points Tree",
        ModuleName = "BetterPoints",
        DefaultCurrency = "Better Points",
        CurrencyList = {"Better Points"},
        KeySet = BetterPointsTreeKeys
    })
end
    stepWorld("Desert")

do
    local MinesTeleportSection = createSectionBox(State.Tabs.Mines:GetPage(), "Teleport")
    createButton(MinesTeleportSection, "Home", function()
        teleportHomeSmart("Mines")
    end)
    local MinesList = {
        {Label = "Milestones", Data = makeData(
            Vector3.new(3656.122, 14.492, -9.657),
            CFrame.new(3652.164307, 20.547853, 2.567032, 0.951381981, 0.102941677, -0.290302008, 0.000000000, 0.942498028, 0.334211707, 0.308013380, -0.317963004, 0.896675706),
            CFrame.new(3656.122070, 15.991518, -9.657419, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633096
        )},
        {Label = "Sell ores", Data = makeData(
            Vector3.new(3653.821, 14.492, 25.575),
            CFrame.new(3655.571533, 22.648075, 13.806721, -0.989119947, -0.071829185, 0.128383145, 0.000000000, 0.872695327, 0.488265038, -0.147111058, 0.482952684, -0.863200426),
            CFrame.new(3653.821289, 15.991518, 25.574800, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633078
        )},
        {Label = "Pickaxe Shop", Data = makeData(
            Vector3.new(3692.154, 14.492, 26.067),
            CFrame.new(3682.919189, 21.123217, 17.450344, -0.682247519, 0.275205195, -0.677348137, 0.000000000, 0.926451147, 0.376415223, 0.731121302, 0.256808341, -0.632068992),
            CFrame.new(3692.153564, 15.991518, 26.067390, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633103
        )},
        {Label = "Workers Shop", Data = makeData(
            Vector3.new(3761.531, 17.880, 26.900),
            CFrame.new(3765.265381, 25.833832, 15.486748, -0.950409770, -0.147233292, 0.273940891, 0.000000000, 0.880837679, 0.473418325, -0.311000407, 0.449941397, -0.837156773),
            CFrame.new(3761.530762, 19.379683, 26.899773, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633069
        )},
        {Label = "Worker Trait", Data = makeData(
            Vector3.new(3760.204, 15.759, -8.829),
            CFrame.new(3761.437012, 22.603525, 3.652063, 0.995158315, -0.038532835, 0.090417527, 0.000000000, 0.919944584, 0.392048627, -0.098285854, -0.390150458, 0.915490329),
            CFrame.new(3760.204346, 17.258696, -8.828889, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633079
        )},
        {Label = "Minify", Data = makeData(
            Vector3.new(3801.725, 14.912, 7.956),
            CFrame.new(3792.272705, 19.865250, -1.241910, -0.697409332, 0.181542501, -0.693298340, 0.000000000, 0.967384458, 0.253312856, 0.716673076, 0.176662743, -0.674662888),
            CFrame.new(3801.724609, 16.411816, 7.955823, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633158
        )},
        {Label = "Prestige", Data = makeData(
            Vector3.new(3807.135, 14.492, -41.822),
            CFrame.new(3804.802979, 20.036755, -29.013096, 0.983824134, 0.053154033, -0.171069741, 0.000000000, 0.954963982, 0.296722144, 0.179137394, -0.291922420, 0.939516485),
            CFrame.new(3807.135254, 15.991518, -41.821598, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633091
        )},
        {Label = "Refinery", Data = makeData(
            Vector3.new(3691.123, 15.016, 132.358),
            CFrame.new(3679.385498, 23.439075, 132.763596, 0.034559265, 0.507540286, -0.860934794, 0.000000000, 0.861449420, 0.507843673, 0.999402642, -0.017550703, 0.029771056),
            CFrame.new(3691.122803, 16.515602, 132.357727, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633178
        )},
        {Label = "Pickaxe Enchants", Data = makeData(
            Vector3.new(3682.664, 16.843, 168.097),
            CFrame.new(3689.107422, 24.455635, 157.753387, -0.848791718, -0.237068459, 0.472600520, 0.000000000, 0.893845320, 0.448375523, -0.528727472, 0.380577445, -0.758688450),
            CFrame.new(3682.664307, 18.342896, 168.096649, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633136
        )},
        {Label = "Rune 1", Data = makeData(
            Vector3.new(3694.882, 15.582, -0.348),
            CFrame.new(3687.418945, 27.313175, -5.397151, -0.560342968, 0.621581197, -0.547405481, 0.000000000, 0.660909712, 0.750465572, 0.828260779, 0.420518100, -0.370336026),
            CFrame.new(3694.881836, 17.082020, -0.348331, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633117
        )},
        {Label = "Rune 2", Data = makeData(
            Vector3.new(3663.043, 15.578, 118.063),
            CFrame.new(3659.363770, 25.881180, 127.800369, 0.935447037, 0.228253171, -0.269887507, 0.000000000, 0.763544142, 0.645755649, 0.353466779, -0.604070187, 0.714255154),
            CFrame.new(3663.043213, 17.077541, 118.062874, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633091
        )},
        {Label = "Rune 3", Data = makeData(
            Vector3.new(3775.579, 15.496, 12.903),
            CFrame.new(3784.918701, 25.441692, 18.127495, 0.488156796, -0.540699899, 0.685088813, 0.000000000, 0.784971833, 0.619531572, -0.872756004, -0.302428544, 0.383189321),
            CFrame.new(3775.578857, 16.995569, 12.903443, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633062
        )}
    }
    registerRuneLocations("Mines", MinesList)
    createGrid(MinesTeleportSection, MinesList, function(item)
        teleportWithData(item.Data)
    end)

    local MinesAutomationSection = createSectionBox(State.Tabs.Mines:GetPage(), "Automation")
    local minesDepositSection = createSubSectionBox(MinesAutomationSection, "Auto Deposit Mines")
    Config.MinesAutoDepositItems = Config.MinesAutoDepositItems or {}

    local function getMinesDepositDefinitions()
        local defs = {}
        local fallback = {
            "Sandstone",
            "Lead",
            "Uranium",
            "Emerald",
            "Adamantite",
            "Ardenite",
            "Netherite",
            "Connorite",
            "Kalite",
            "0hxsnite",
            "Tehleatite",
            "Ghoulaxite"
        }
        local seen = {}

        local function addDef(name, order)
            if type(name) ~= "string" then
                return
            end
            local trimmed = name:match("^%s*(.-)%s*$")
            if type(trimmed) ~= "string" or #trimmed == 0 then
                return
            end
            if seen[trimmed] then
                return
            end
            seen[trimmed] = true
            defs[#defs + 1] = {
                Name = trimmed,
                Order = tonumber(order) or 999999
            }
        end

        local runtimeOrder = 1
        local mines = LP and LP:FindFirstChild("Mines")
        local inv = mines and mines:FindFirstChild("Inventory")
        if inv then
            local children = inv:GetChildren()
            table.sort(children, function(a, b)
                return tostring(a.Name) < tostring(b.Name)
            end)
            for _, item in ipairs(children) do
                if item and item:FindFirstChild("MilestoneDeposit") then
                    addDef(item.Name, runtimeOrder)
                    runtimeOrder += 1
                end
            end
        end

        if #defs == 0 then
            for _, name in ipairs(fallback) do
                addDef(name, #defs + 1)
            end
        end
        table.sort(defs, function(a, b)
            if a.Order == b.Order then
                return tostring(a.Name) < tostring(b.Name)
            end
            return a.Order < b.Order
        end)
        return defs
    end

    local minesDepositDefs = getMinesDepositDefinitions()
    local minesDepositCfg = Config.MinesAutoDepositItems
    for _, def in ipairs(minesDepositDefs) do
        if minesDepositCfg[def.Name] == nil then
            minesDepositCfg[def.Name] = true
        end
    end
    saveConfig()

    State.MinesAutoDeposit = State.MinesAutoDeposit or {
        Enabled = Config.MinesAutoDepositEnabled == true,
        Index = 1,
        Success = 0,
        SuccessByItem = {},
        LastItem = nil,
        LastSnapshotAt = 0,
        SnapshotSignature = "",
        Wait = {
            Active = false,
            Currency = nil,
            Before = nil,
            Since = 0,
            Timeout = 1.2
        }
    }

    local function readRawAndNumber(node)
        if not node then
            return nil, nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil, nil
        end
        return raw, tonumber(raw)
    end

    local function getMinesInventoryEntry(currencyName)
        if not LP or type(currencyName) ~= "string" then
            return nil
        end
        local mines = LP:FindFirstChild("Mines")
        local inv = mines and mines:FindFirstChild("Inventory")
        local entry = inv and inv:FindFirstChild(currencyName)
        return entry
    end

    local function shouldDepositCurrency(currencyName)
        local entry = getMinesInventoryEntry(currencyName)
        if not entry then
            return false
        end
        local amountRaw, amountNum = readRawAndNumber(entry:FindFirstChild("Amount"))
        local _, depoNum = readRawAndNumber(entry:FindFirstChild("MilestoneDeposit"))
        if type(amountNum) ~= "number" or type(depoNum) ~= "number" then
            return false
        end
        if amountNum <= 0 or depoNum <= 0 then
            return false
        end
        if amountNum >= (depoNum * getAutoDepositRequiredMultiplier()) then
            return true, amountRaw, amountNum
        end
        return false
    end

    local function buildMinesDepositSnapshot()
        local out = {}
        for _, def in ipairs(minesDepositDefs) do
            if def and minesDepositCfg[def.Name] then
                local entry = getMinesInventoryEntry(def.Name)
                local _, ownNum = readRawAndNumber(entry and entry:FindFirstChild("Amount"))
                local _, depoNum = readRawAndNumber(entry and entry:FindFirstChild("MilestoneDeposit"))
                out[#out + 1] = {
                    Name = tostring(def.Name),
                    OwnNum = ownNum,
                    DepositNum = depoNum
                }
            end
        end
        return out
    end

    local function buildMinesItemTotalsCopy()
        local out = {}
        local src = State.MinesAutoDeposit and State.MinesAutoDeposit.SuccessByItem or nil
        for k, v in pairs(src or {}) do
            out[k] = tonumber(v) or 0
        end
        return out
    end

    local function buildMinesSnapshotSignature(items)
        local parts = {}
        for _, entry in ipairs(items or {}) do
            parts[#parts + 1] = tostring(entry.Name)
                .. ":"
                .. tostring(entry.OwnNum ~= nil and entry.OwnNum or "?")
                .. ":"
                .. tostring(entry.DepositNum ~= nil and entry.DepositNum or "?")
        end
        table.sort(parts)
        return table.concat(parts, "|")
    end

    local function refreshMinesDepositLog(forceRefresh)
        if not (AutoBuyLogState and AutoBuyLogState.UpdateDepositProgress and State.MinesAutoDeposit and State.MinesAutoDeposit.Enabled) then
            return
        end
        local now = os.clock()
        if not forceRefresh and (now - (State.MinesAutoDeposit.LastSnapshotAt or 0)) < 0.35 then
            return
        end
        local items = buildMinesDepositSnapshot()
        local sig = buildMinesSnapshotSignature(items)
        if not forceRefresh and sig == State.MinesAutoDeposit.SnapshotSignature then
            State.MinesAutoDeposit.LastSnapshotAt = now
            return
        end
        State.MinesAutoDeposit.SnapshotSignature = sig
        State.MinesAutoDeposit.LastSnapshotAt = now
        AutoBuyLogState.UpdateDepositProgress("MinesAutoDeposit", {
            ItemName = State.MinesAutoDeposit.LastItem or "-",
            Items = items,
            Success = tonumber(State.MinesAutoDeposit.Success) or 0,
            ItemTotals = buildMinesItemTotalsCopy()
        })
    end

    local function minesDepositStep()
        if not State.MinesAutoDeposit or not State.MinesAutoDeposit.Enabled then
            return false
        end
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return false
        end

        local waitState = State.MinesAutoDeposit.Wait
        if waitState and waitState.Active and waitState.Currency then
            local entry = getMinesInventoryEntry(waitState.Currency)
            local _, amountNum = readRawAndNumber(entry and entry:FindFirstChild("Amount"))
            if type(amountNum) == "number" and type(waitState.Before) == "number" and math.abs(amountNum - waitState.Before) > 1e-9 then
                waitState.Active = false
            elseif (os.clock() - (waitState.Since or 0)) < (waitState.Timeout or 1.2) then
                return false
            else
                waitState.Active = false
            end
        end

        local total = #minesDepositDefs
        if total == 0 then
            return false
        end
        refreshMinesDepositLog(false)
        local idx = tonumber(State.MinesAutoDeposit.Index) or 1
        for _ = 1, total do
            local def = minesDepositDefs[idx]
            idx += 1
            if idx > total then
                idx = 1
            end
            if def and minesDepositCfg[def.Name] then
                local should, rawAmount, amountNum = shouldDepositCurrency(def.Name)
                if should then
                    local amountArg = rawAmount
                    if type(amountArg) ~= "string" and type(amountArg) ~= "number" then
                        amountArg = tostring(amountNum)
                    end
                    local ok = pcall(function()
                        remote:FireServer("DepositOre", def.Name, amountArg)
                    end)
                    if ok then
                        State.MinesAutoDeposit.Index = idx
                        State.MinesAutoDeposit.LastItem = def.Name
                        State.MinesAutoDeposit.Success = (tonumber(State.MinesAutoDeposit.Success) or 0) + 1
                        State.MinesAutoDeposit.SuccessByItem = State.MinesAutoDeposit.SuccessByItem or {}
                        State.MinesAutoDeposit.SuccessByItem[def.Name] = (tonumber(State.MinesAutoDeposit.SuccessByItem[def.Name]) or 0) + 1
                        if waitState then
                            waitState.Active = true
                            waitState.Currency = def.Name
                            waitState.Before = amountNum
                            waitState.Since = os.clock()
                        end
                        refreshMinesDepositLog(true)
                        return true
                    end
                end
            end
        end
        State.MinesAutoDeposit.Index = idx
        return false
    end

    local function setMinesAutoDepositEnabled(enabled)
        State.MinesAutoDeposit.Enabled = enabled == true
        Config.MinesAutoDepositEnabled = State.MinesAutoDeposit.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetDepositActive then
            AutoBuyLogState.SetDepositActive("MinesAutoDeposit", "Deposit Mines", State.MinesAutoDeposit.Enabled)
            if State.MinesAutoDeposit.Enabled and AutoBuyLogState.UpdateDepositProgress then
                AutoBuyLogState.UpdateDepositProgress("MinesAutoDeposit", {
                    ItemName = State.MinesAutoDeposit.LastItem or "-",
                    Items = buildMinesDepositSnapshot(),
                    Success = tonumber(State.MinesAutoDeposit.Success) or 0,
                    ItemTotals = buildMinesItemTotalsCopy()
                })
            end
        end

        if State.MinesAutoDeposit.Enabled then
            State.MinesAutoDeposit.Index = 1
            State.MinesAutoDeposit.LastSnapshotAt = 0
            State.MinesAutoDeposit.SnapshotSignature = ""
            if State.MinesAutoDeposit.Wait then
                State.MinesAutoDeposit.Wait.Active = false
                State.MinesAutoDeposit.Wait.Currency = nil
                State.MinesAutoDeposit.Wait.Before = nil
            end
            autoBuySchedulerRegister("MinesAutoDeposit", {
                Step = minesDepositStep
            })
        else
            autoBuySchedulerUnregister("MinesAutoDeposit")
            if State.MinesAutoDeposit.Wait then
                State.MinesAutoDeposit.Wait.Active = false
                State.MinesAutoDeposit.Wait.Currency = nil
                State.MinesAutoDeposit.Wait.Before = nil
            end
        end
    end

    createToggle(minesDepositSection, "Auto Deposit Mines", nil, State.MinesAutoDeposit.Enabled, function(v)
        setMinesAutoDepositEnabled(v == true)
    end)

    local minesItemListSection = createSubSectionBox(minesDepositSection, "Item List")
    for _, def in ipairs(minesDepositDefs) do
        createToggle(minesItemListSection, tostring(def.Name), nil, minesDepositCfg[def.Name], function(v)
            minesDepositCfg[def.Name] = v == true
            saveConfig()
            if State.MinesAutoDeposit and State.MinesAutoDeposit.Enabled and AutoBuyLogState and AutoBuyLogState.UpdateDepositProgress then
                refreshMinesDepositLog(true)
            end
        end)
    end
    setMinesAutoDepositEnabled(State.MinesAutoDeposit.Enabled == true)
end
    stepWorld("Mines")

do
    local CyberTeleportSection = createSectionBox(State.Tabs.Cyber:GetPage(), "Teleport")
    createButton(CyberTeleportSection, "Home", function()
        teleportHomeSmart("Cyber")
    end)
    local CyberList = {
        {Label = "Energy Shop", Data = makeData(
            Vector3.new(5526.205, 15.366, 21.824),
            CFrame.new(5543.679688, 23.797445, 27.019924, 0.285010904, -0.340665936, 0.895943940, 0.000000000, 0.934711754, 0.355406702, -0.958524227, -0.101294786, 0.266403079),
            CFrame.new(5526.205078, 16.865593, 21.823999, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504107
        )},
        {Label = "Power Shop", Data = makeData(
            Vector3.new(5598.063, 15.365, -52.749),
            CFrame.new(5591.055176, 20.625202, -34.939743, 0.930548728, 0.070598193, -0.359298080, 0.000000000, 0.981237650, 0.192802578, 0.366168320, -0.179412201, 0.913089275),
            CFrame.new(5598.062988, 16.864780, -52.748638, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504025
        )},
        {Label = "Charge Shop", Data = makeData(
            Vector3.new(5592.175, 15.363, 84.046),
            CFrame.new(5597.482910, 22.860453, 66.262512, -0.958225250, -0.087945469, 0.272157699, 0.000000000, 0.951552451, 0.307486206, -0.286014348, 0.294641048, -0.911801755),
            CFrame.new(5592.174805, 16.863241, 84.046295, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503986
        )},
        {Label = "Circuit Shop", Data = makeData(
            Vector3.new(5813.718, 15.568, 26.326),
            CFrame.new(5795.148926, 22.960747, 25.392265, -0.050235484, 0.301729023, -0.952069342, 0.000000000, 0.953272998, 0.302110463, 0.998737454, 0.015176665, -0.047888126),
            CFrame.new(5813.718262, 17.068384, 26.326275, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504168
        )},
        {Label = "Upgrade PC (Cores)", Data = makeData(
            Vector3.new(5779.062, 15.360, -44.662),
            CFrame.new(5774.031250, 23.792198, -27.139288, 0.961167812, 0.098079778, -0.257947117, 0.000000000, 0.934711456, 0.355407357, 0.275964409, -0.341606110, 0.898414671),
            CFrame.new(5779.062012, 16.860332, -44.661968, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503939
        )},
        {Label = "Tech Tree", Data = makeData(
            Vector3.new(5706.621, 101.935, -245.200),
            CFrame.new(5708.908691, 116.445381, -259.549500, -0.987525344, -0.105032779, 0.117310263, 0.000000000, 0.745017290, 0.667045176, -0.157459766, 0.658724010, -0.735723555),
            CFrame.new(5706.620605, 103.435333, -245.199951, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504005
        )},
        {Label = "Cyber Shop", Data = makeData(
            Vector3.new(5754.847, 15.482, 2.240),
            CFrame.new(5740.769043, 23.500961, 14.060647, 0.643061757, 0.255947262, -0.721777439, 0.000000000, 0.942496657, 0.334215790, 0.765814364, -0.214921400, 0.606083512),
            CFrame.new(5754.846680, 16.982416, 2.239594, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504065
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(5541.205, 15.902, 34.389),
            CFrame.new(5523.230469, 24.231348, 31.116262, -0.179136649, 0.344463736, -0.921550214, 0.000000000, 0.936702132, 0.350127339, 0.983824193, 0.062720641, -0.167797685),
            CFrame.new(5541.204590, 17.402464, 34.388988, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504190
        )}
    }
    registerRuneLocations("Cyber", CyberList)
    createGrid(CyberTeleportSection, CyberList, function(item)
        teleportWithData(item.Data)
    end)
end
    stepWorld("Cyber")

do
    local OceanTeleportSection = createSectionBox(State.Tabs.Ocean:GetPage(), "Teleport")
    createButton(OceanTeleportSection, "Home", function()
        teleportHomeSmart("Ocean")
    end)
    local OceanList = {
        {Label = "Coin Shop", Data = makeData(
            Vector3.new(-84.245, 15.909, -1909.452),
            CFrame.new(-92.179611, 26.739017, -1894.273682, 0.886207998, 0.221630886, -0.406835407, 0.000000000, 0.878148913, 0.478387415, 0.463287443, -0.423950762, 0.778222680),
            CFrame.new(-84.244690, 17.408550, -1909.452148, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504011
        )},
        {Label = "Sell Fish", Data = makeData(
            Vector3.new(-52.805, 15.910, -1894.369),
            CFrame.new(-55.200657, 27.784790, -1910.709473, -0.989423394, 0.077163368, -0.122830078, 0.000000000, 0.846773565, 0.531953573, 0.145056590, 0.526327312, -0.837817490),
            CFrame.new(-52.804977, 17.409569, -1894.368652, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504023
        )},
        {Label = "Rods Shop", Data = makeData(
            Vector3.new(-52.589, 15.910, -1918.950),
            CFrame.new(-57.254658, 24.853153, -1901.536255, 0.965928316, 0.098773256, -0.239220500, 0.000000000, 0.924309611, 0.381643951, 0.258809954, -0.368640691, 0.892816722),
            CFrame.new(-52.588902, 17.409569, -1918.949707, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503962
        )},
        {Label = "Prestige", Data = makeData(
            Vector3.new(35.145, 15.409, -1897.175),
            CFrame.new(16.789160, 20.127487, -1902.927246, -0.299031794, 0.157488123, -0.941157520, 0.000000000, 0.986286879, 0.165039822, 0.954243124, 0.049352154, -0.294931144),
            CFrame.new(35.145496, 16.908550, -1897.174927, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503994
        )},
        {Label = "Depth", Data = makeData(
            Vector3.new(-36.976, 19.489, -2056.097),
            CFrame.new(-20.304077, 27.195210, -2048.101807, 0.432391793, -0.286926121, 0.854816318, 0.000000000, 0.948020101, 0.318210751, -0.901685834, -0.137591720, 0.409916103),
            CFrame.new(-36.976414, 20.988827, -2056.096924, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504047
        )},
        {Label = "Aquarium", Data = makeData(
            Vector3.new(-27.464, 16.010, -1953.105),
            CFrame.new(-10.825624, 25.559849, -1946.877563, 0.350525141, -0.386536628, 0.853066027, 0.000000000, 0.910856903, 0.412722498, -0.936553359, -0.144669607, 0.319278210),
            CFrame.new(-27.463823, 17.510109, -1953.104736, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503990
        )},
        {Label = "Pearls Shop", Data = makeData(
            Vector3.new(-6.951, 15.910, -1950.234),
            CFrame.new(-24.716681, 24.853159, -1953.296509, -0.169855535, 0.376098603, -0.910878181, 0.000000000, 0.924309313, 0.381644309, 0.985468924, 0.064824395, -0.156999066),
            CFrame.new(-6.950912, 17.409569, -1950.234375, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504005
        )},
        {Label = "Fisherman Shop", Data = makeData(
            Vector3.new(6.584, 19.477, -2013.135),
            CFrame.new(-11.778711, 27.495384, -2013.981079, -0.046050403, 0.333863378, -0.941495955, 0.000000000, 0.942495823, 0.334217936, 0.998939097, 0.015390871, -0.043402314),
            CFrame.new(6.584225, 20.976797, -2013.134521, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504002
        )},
        {Label = "Relics", Data = makeData(
            Vector3.new(44.049, 19.477, -2049.437),
            CFrame.new(25.760534, 27.702478, -2050.280029, -0.046050407, 0.344470203, -0.937667131, 0.000000000, 0.938662946, 0.344836026, 0.998939157, 0.015879840, -0.043225810),
            CFrame.new(44.048794, 20.976797, -2049.437012, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503998
        )},
        {Label = "Enchants Rod", Data = makeData(
            Vector3.new(8.075, 15.910, -1876.339),
            CFrame.new(-1.638691, 21.601154, -1892.724243, -0.860203445, 0.109593071, -0.498035491, 0.000000000, 0.976634026, 0.214909047, 0.509950936, 0.184865505, -0.840103984),
            CFrame.new(8.074993, 17.409569, -1876.338867, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503990
        )},
        {Label = "Fisherman Traits", Data = makeData(
            Vector3.new(-7.731, 20.055, -2097.168),
            CFrame.new(-9.150262, 27.447569, -2078.629639, 0.997080326, 0.023069723, -0.072792828, 0.000000000, 0.953271985, 0.302113801, 0.076361038, -0.301231742, 0.950488567),
            CFrame.new(-7.730510, 21.555141, -2097.167969, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504002
        )},
        {Label = "Milestone", Data = makeData(
            Vector3.new(-12.070, 16.224, -1848.307),
            CFrame.new(-10.960073, 22.344925, -1867.223633, -0.998281598, -0.013882399, 0.056931511, 0.000000000, 0.971533477, 0.236902446, -0.058599643, 0.236495346, -0.969863892),
            CFrame.new(-12.070465, 17.724379, -1848.307373, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504034
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(-81.523, 16.510, -1887.714),
            CFrame.new(-95.313461, 30.093876, -1894.363037, -0.434279412, 0.558064044, -0.707082689, 0.000000000, 0.784968615, 0.619535506, 0.900778115, 0.269051522, -0.340895772),
            CFrame.new(-81.522522, 18.010454, -1887.714233, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503992
        )}
    }
    registerRuneLocations("Ocean", OceanList)
    createGrid(OceanTeleportSection, OceanList, function(item)
        teleportWithData(item.Data)
    end)

    local OceanAutomationSection = createSectionBox(State.Tabs.Ocean:GetPage(), "Automation")
    local fishDepositSection = createSubSectionBox(OceanAutomationSection, "Auto Deposit Fish")
    Config.FishAutoDepositItems = Config.FishAutoDepositItems or {}

    local function getFishDepositDefinitions()
        local defs = {}
        local fallback = {
            {Name = "Loach", Rarity = "Legendary", Order = 1},
            {Name = "Piranha", Rarity = "Legendary", Order = 2},
            {Name = "Salmon", Rarity = "Legendary", Order = 3},
            {Name = "Sweetfish", Rarity = "Legendary", Order = 4},
            {Name = "Stringfish", Rarity = "Legendary", Order = 5},
            {Name = "Popeyed", Rarity = "Mythical", Order = 6},
            {Name = "Clownfish", Rarity = "Mythical", Order = 7},
            {Name = "Extinct Piranha", Rarity = "Divine", Order = 8},
            {Name = "Golden Bass", Rarity = "Divine", Order = 9},
            {Name = "Blue Lobster", Rarity = "Divine", Order = 10}
        }
        local moduleData = nil
        local okModule, moduleScript = pcall(function()
            return game:GetService("ReplicatedStorage").Shared.Modules.Fish.FishMilestone
        end)
        if okModule and moduleScript and moduleScript:IsA("ModuleScript") then
            local okReq, reqData = pcall(require, moduleScript)
            if okReq and type(reqData) == "table" then
                moduleData = reqData
            end
        end

        if type(moduleData) == "table" then
            for name, meta in pairs(moduleData) do
                if type(name) == "string" and type(meta) == "table" then
                    defs[#defs + 1] = {
                        Name = name,
                        Rarity = tostring(meta.rarity or "Legendary"),
                        Order = tonumber(meta.order) or 999999
                    }
                end
            end
            table.sort(defs, function(a, b)
                if a.Order == b.Order then
                    return tostring(a.Name) < tostring(b.Name)
                end
                return a.Order < b.Order
            end)
        end

        if #defs == 0 then
            for _, def in ipairs(fallback) do
                defs[#defs + 1] = {
                    Name = def.Name,
                    Rarity = def.Rarity,
                    Order = def.Order
                }
            end
        end
        return defs
    end

    local fishDepositDefs = getFishDepositDefinitions()
    local fishDepositCfg = Config.FishAutoDepositItems
    for _, def in ipairs(fishDepositDefs) do
        if fishDepositCfg[def.Name] == nil then
            fishDepositCfg[def.Name] = true
        end
    end
    saveConfig()

    State.FishAutoDeposit = State.FishAutoDeposit or {
        Enabled = Config.FishAutoDepositEnabled == true,
        Index = 1,
        Success = 0,
        SuccessByItem = {},
        LastItem = nil,
        LastSnapshotAt = 0,
        SnapshotSignature = "",
        Wait = {
            Active = false,
            Currency = nil,
            Before = nil,
            Since = 0,
            Timeout = 1.2
        }
    }

    local function readRawAndNumber(node)
        if not node then
            return nil, nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil, nil
        end
        return raw, tonumber(raw)
    end

    local function getFishInventoryEntry(def)
        if not LP or type(def) ~= "table" or type(def.Name) ~= "string" then
            return nil
        end
        local fish = LP:FindFirstChild("Fish")
        local fishes = fish and fish:FindFirstChild("Fishes")
        local rarity = fishes and fishes:FindFirstChild(tostring(def.Rarity or "Legendary"))
        local entry = rarity and rarity:FindFirstChild(def.Name)
        if entry then
            return entry
        end
        for _, rarityFolder in ipairs(fishes and fishes:GetChildren() or {}) do
            local fallbackEntry = rarityFolder:FindFirstChild(def.Name)
            if fallbackEntry then
                return fallbackEntry
            end
        end
        return nil
    end

    local function shouldDepositFish(def)
        local entry = getFishInventoryEntry(def)
        if not entry then
            return false
        end
        local amountRaw, amountNum = readRawAndNumber(entry:FindFirstChild("Amount"))
        local _, depoNum = readRawAndNumber(entry:FindFirstChild("MilestoneDeposit"))
        if type(amountNum) ~= "number" or type(depoNum) ~= "number" then
            return false
        end
        if amountNum <= 0 or depoNum <= 0 then
            return false
        end
        if amountNum >= (depoNum * getAutoDepositRequiredMultiplier()) then
            return true, amountRaw, amountNum
        end
        return false
    end

    local function buildFishDepositSnapshot()
        local out = {}
        for _, def in ipairs(fishDepositDefs) do
            if def and fishDepositCfg[def.Name] then
                local entry = getFishInventoryEntry(def)
                local _, ownNum = readRawAndNumber(entry and entry:FindFirstChild("Amount"))
                local _, depoNum = readRawAndNumber(entry and entry:FindFirstChild("MilestoneDeposit"))
                out[#out + 1] = {
                    Name = tostring(def.Name),
                    OwnNum = ownNum,
                    DepositNum = depoNum
                }
            end
        end
        return out
    end

    local function buildFishItemTotalsCopy()
        local out = {}
        local src = State.FishAutoDeposit and State.FishAutoDeposit.SuccessByItem or nil
        for k, v in pairs(src or {}) do
            out[k] = tonumber(v) or 0
        end
        return out
    end

    local function buildFishSnapshotSignature(items)
        local parts = {}
        for _, entry in ipairs(items or {}) do
            parts[#parts + 1] = tostring(entry.Name)
                .. ":"
                .. tostring(entry.OwnNum ~= nil and entry.OwnNum or "?")
                .. ":"
                .. tostring(entry.DepositNum ~= nil and entry.DepositNum or "?")
        end
        table.sort(parts)
        return table.concat(parts, "|")
    end

    local function refreshFishDepositLog(forceRefresh)
        if not (AutoBuyLogState and AutoBuyLogState.UpdateDepositProgress and State.FishAutoDeposit and State.FishAutoDeposit.Enabled) then
            return
        end
        local now = os.clock()
        if not forceRefresh and (now - (State.FishAutoDeposit.LastSnapshotAt or 0)) < 0.35 then
            return
        end
        local items = buildFishDepositSnapshot()
        local sig = buildFishSnapshotSignature(items)
        if not forceRefresh and sig == State.FishAutoDeposit.SnapshotSignature then
            State.FishAutoDeposit.LastSnapshotAt = now
            return
        end
        State.FishAutoDeposit.SnapshotSignature = sig
        State.FishAutoDeposit.LastSnapshotAt = now
        AutoBuyLogState.UpdateDepositProgress("FishAutoDeposit", {
            ItemName = State.FishAutoDeposit.LastItem or "-",
            Items = items,
            Success = tonumber(State.FishAutoDeposit.Success) or 0,
            ItemTotals = buildFishItemTotalsCopy()
        })
    end

    local function fishDepositStep()
        if not State.FishAutoDeposit or not State.FishAutoDeposit.Enabled then
            return false
        end
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return false
        end

        local waitState = State.FishAutoDeposit.Wait
        if waitState and waitState.Active and waitState.Currency then
            local foundDef = nil
            for _, def in ipairs(fishDepositDefs) do
                if def.Name == waitState.Currency then
                    foundDef = def
                    break
                end
            end
            local entry = getFishInventoryEntry(foundDef or {Name = waitState.Currency, Rarity = "Legendary"})
            local _, amountNum = readRawAndNumber(entry and entry:FindFirstChild("Amount"))
            if type(amountNum) == "number" and type(waitState.Before) == "number" and math.abs(amountNum - waitState.Before) > 1e-9 then
                waitState.Active = false
            elseif (os.clock() - (waitState.Since or 0)) < (waitState.Timeout or 1.2) then
                return false
            else
                waitState.Active = false
            end
        end

        local total = #fishDepositDefs
        if total == 0 then
            return false
        end
        refreshFishDepositLog(false)
        local idx = tonumber(State.FishAutoDeposit.Index) or 1
        for _ = 1, total do
            local def = fishDepositDefs[idx]
            idx += 1
            if idx > total then
                idx = 1
            end
            if def and fishDepositCfg[def.Name] then
                local should, rawAmount, amountNum = shouldDepositFish(def)
                if should then
                    local amountArg = tonumber(amountNum) or tonumber(rawAmount)
                    if type(amountArg) ~= "number" then
                        amountArg = amountNum
                    end
                    local ok = pcall(function()
                        remote:FireServer("DepositFish", def.Name, amountArg)
                    end)
                    if ok then
                        State.FishAutoDeposit.Index = idx
                        State.FishAutoDeposit.LastItem = def.Name
                        State.FishAutoDeposit.Success = (tonumber(State.FishAutoDeposit.Success) or 0) + 1
                        State.FishAutoDeposit.SuccessByItem = State.FishAutoDeposit.SuccessByItem or {}
                        State.FishAutoDeposit.SuccessByItem[def.Name] = (tonumber(State.FishAutoDeposit.SuccessByItem[def.Name]) or 0) + 1
                        if waitState then
                            waitState.Active = true
                            waitState.Currency = def.Name
                            waitState.Before = amountNum
                            waitState.Since = os.clock()
                        end
                        refreshFishDepositLog(true)
                        return true
                    end
                end
            end
        end
        State.FishAutoDeposit.Index = idx
        return false
    end

    local function setFishAutoDepositEnabled(enabled)
        State.FishAutoDeposit.Enabled = enabled == true
        Config.FishAutoDepositEnabled = State.FishAutoDeposit.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetDepositActive then
            AutoBuyLogState.SetDepositActive("FishAutoDeposit", "Deposit Fish", State.FishAutoDeposit.Enabled)
            if State.FishAutoDeposit.Enabled and AutoBuyLogState.UpdateDepositProgress then
                AutoBuyLogState.UpdateDepositProgress("FishAutoDeposit", {
                    ItemName = State.FishAutoDeposit.LastItem or "-",
                    Items = buildFishDepositSnapshot(),
                    Success = tonumber(State.FishAutoDeposit.Success) or 0,
                    ItemTotals = buildFishItemTotalsCopy()
                })
            end
        end

        if State.FishAutoDeposit.Enabled then
            State.FishAutoDeposit.Index = 1
            State.FishAutoDeposit.LastSnapshotAt = 0
            State.FishAutoDeposit.SnapshotSignature = ""
            if State.FishAutoDeposit.Wait then
                State.FishAutoDeposit.Wait.Active = false
                State.FishAutoDeposit.Wait.Currency = nil
                State.FishAutoDeposit.Wait.Before = nil
            end
            autoBuySchedulerRegister("FishAutoDeposit", {
                Step = fishDepositStep
            })
        else
            autoBuySchedulerUnregister("FishAutoDeposit")
            if State.FishAutoDeposit.Wait then
                State.FishAutoDeposit.Wait.Active = false
                State.FishAutoDeposit.Wait.Currency = nil
                State.FishAutoDeposit.Wait.Before = nil
            end
        end
    end

    createToggle(fishDepositSection, "Auto Deposit Fish", nil, State.FishAutoDeposit.Enabled, function(v)
        setFishAutoDepositEnabled(v == true)
    end)

    local fishItemListSection = createSubSectionBox(fishDepositSection, "Item List")
    for _, def in ipairs(fishDepositDefs) do
        createToggle(fishItemListSection, tostring(def.Name), nil, fishDepositCfg[def.Name], function(v)
            fishDepositCfg[def.Name] = v == true
            saveConfig()
            if State.FishAutoDeposit and State.FishAutoDeposit.Enabled and AutoBuyLogState and AutoBuyLogState.UpdateDepositProgress then
                refreshFishDepositLog(true)
            end
        end)
    end
    setFishAutoDepositEnabled(State.FishAutoDeposit.Enabled == true)
end
    stepWorld("Ocean")

do
    local MushroomTeleportSection = createSectionBox(State.MushroomTab:GetPage(), "Teleport")
      createButton(MushroomTeleportSection, "Home", function()
          teleportHomeSmart("Mushroom World")
      end)
      local MushroomList = {
          {Label = "Home (Unofficial)", Data = makeData(
              Vector3.new(1796.507, 15.092, -1947.680),
              CFrame.new(1783.967651, 20.732552, -1946.964478, 0.056972563, 0.312557608, -0.948188841, 0.000000000,
  0.949731350, 0.313066125, 0.998375654, -0.017836180, 0.054108638),
              CFrame.new(1796.507202, 16.592346, -1947.680054, 1.000000000, 0.000000000, 0.000000000, 0.000000000,
  1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
13.224738
          )},
          {Label = "Perk", Data = makeData(
              Vector3.new(1963.915, 18.819, -1933.641),
              CFrame.new(1953.011475, 26.843781, -1937.305054, -0.318528295, 0.467683554, -0.824507058, 0.000000000,
  0.869812727, 0.493382156, 0.947913408, 0.157156169, -0.277059942),
              CFrame.new(1963.915283, 20.318949, -1933.640991, 1.000000000, 0.000000000, 0.000000000, 0.000000000,
  1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
13.224668
          )},
          {Label = "Seed Shop", Data = makeData(
              Vector3.new(1804.104, 15.092, -1968.615),
              CFrame.new(1808.584229, 24.238993, -1951.240723, 0.968319833, -0.097901441, 0.229721680, 0.000000000, 0.919941664, 0.392055333, -0.249713331, -0.379634947, 0.890797675),
              CFrame.new(1804.103760, 16.592346, -1968.614868, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.504019
          )},
          {Label = "Fungus Shop", Data = makeData(
              Vector3.new(1834.716, 15.092, -1925.022),
              CFrame.new(1819.225098, 23.627050, -1934.559326, -0.524274945, 0.307138503, -0.794230282, 0.000000000, 0.932688832, 0.360682070, 0.851549149, 0.189096570, -0.488985330),
              CFrame.new(1834.715820, 16.592308, -1925.022217, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.504013
          )},
          {Label = "Milestone", Data = makeData(
              Vector3.new(1835.331, 15.092, -1982.877),
              CFrame.new(1817.138428, 23.318024, -1984.923950, -0.111806244, 0.342675626, -0.932776928, 0.000000000, 0.938662350, 0.344837725, 0.993730068, 0.038555011, -0.104948305),
              CFrame.new(1835.331299, 16.592310, -1982.877075, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.503986
          )},
          {Label = "Spores Shop", Data = makeData(
              Vector3.new(1817.428, 18.812, -2061.365),
              CFrame.new(1830.399658, 25.783215, -2047.867188, 0.721028447, -0.194372177, 0.665084600, 0.000000000, 0.959848940, 0.280517608, -0.692905426, -0.202261180, 0.692078412),
              CFrame.new(1817.427856, 20.311998, -2061.365479, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.503992
          )},
          {Label = "Toxic Mushroom Shop", Data = makeData(
              Vector3.new(1841.913, 18.812, -2052.954),
              CFrame.new(1826.785645, 28.859879, -2061.814941, -0.505423188, 0.378164619, -0.775589466, 0.000000000, 0.898846924, 0.438262880, 0.862871647, 0.221508220, -0.454298049),
              CFrame.new(1841.912720, 20.311998, -2052.954346, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.503969
          )},
          {Label = "Glowy Crystals", Data = makeData(
              Vector3.new(1867.056, 18.812, -2085.995),
              CFrame.new(1850.763672, 28.561760, -2092.843994, -0.387506783, 0.389931649, -0.835339427, 0.000000000, 0.906138897, 0.422980428, 0.921866894, 0.163907781, -0.351134956),
              CFrame.new(1867.056152, 20.311951, -2085.995361, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.504051
          )},
          {Label = "Auras", Data = makeData(
              Vector3.new(1784.383, 18.812, -2109.326),
              CFrame.new(1801.805298, 28.361778, -2105.850830, 0.195594564, -0.404752761, 0.893262506, 0.000000000, 0.910855830, 0.412724614, -0.980684817, -0.080726691, 0.178158447),
              CFrame.new(1784.383057, 20.311998, -2109.325684, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.504051
          )},
          {Label = "Plant Plot 1", Data = makeData(
              Vector3.new(1821.934, 15.875, -1909.829),
              CFrame.new(1818.992310, 23.683229, -1925.073853, -0.981890798, 0.071312420, -0.175513402, 0.000000000, 0.926447988, 0.376422822, 0.189447656, 0.369606107, -0.909670770),
              CFrame.new(1821.933716, 17.374762, -1909.828735, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              16.758945
          )},
          {Label = "Magic Energy", Data = makeData(
              Vector3.new(1999.457, 18.319, -1941.725),
              CFrame.new(1981.025146, 24.653196, -1945.885132, -0.220177427, 0.241774350, -0.945022285, 0.000000000, 0.968796730, 0.247856781, 0.975459874, 0.054572467, -0.213307157),
              CFrame.new(1999.456909, 19.818998, -1941.724731, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.504059
          )},
          {Label = "Plant Plot 2", Data = makeData(
              Vector3.new(1834.254, 18.898, -2137.026),
              CFrame.new(1836.213867, 26.395699, -2118.570557, 0.994410932, -0.032464683, 0.100463986, 0.000000000, 0.951551020, 0.307491273, -0.105579197, -0.305772692, 0.946232677),
              CFrame.new(1834.254395, 20.398390, -2137.025879, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.504004
          )},
          {Label = "Plant Plot 3", Data = makeData(
              Vector3.new(1967.392, 19.967, -1985.897),
              CFrame.new(1960.443970, 25.010784, -1968.020874, 0.932074666, 0.065830939, -0.356234789, 0.000000000, 0.983350515, 0.181719705, 0.362266392, -0.169376329, 0.916555941),
              CFrame.new(1967.391968, 21.466524, -1985.897339, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.503960
          )},
          {Label = "Rune", Data = makeData(
              Vector3.new(1782.607, 15.685, -1934.729),
              CFrame.new(1765.799561, 26.515253, -1938.026733, -0.192512363, 0.469442606, -0.861720800, 0.000000000, 0.878146946, 0.478391111, 0.981294572, 0.092096202, -0.169054136),
              CFrame.new(1782.606567, 17.184713, -1934.729492, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
              19.504005
          )}
      }
      registerRuneLocations("Mushroom World", MushroomList)
      createGrid(MushroomTeleportSection, MushroomList, function(item)
          teleportWithData(item.Data)
      end)
  end

  do
      local MushroomFeaturedSection = createSectionBox(State.MushroomTab:GetPage(), "Featured")

      local function fireMushroomRemote(action, arg2, arg3)
          local remote = getMainRemote and getMainRemote() or nil
          if not remote then
              return
          end
          pcall(function()
              if arg2 == nil then
                  remote:FireServer(action)
              elseif arg3 == nil then
                  remote:FireServer(action, arg2)
              else
                  remote:FireServer(action, arg2, arg3)
              end
          end)
      end

      createButton(MushroomFeaturedSection, "Buy All Seed Shop", function()
          fireMushroomRemote("BuyAllSeed", "Mushrooms")
      end)

      createButton(MushroomFeaturedSection, "Sell All", function()
          fireMushroomRemote("SellPlant", "Mushrooms", "Red Mushroom")
      end)

      createButton(MushroomFeaturedSection, "Milestones Up", function()
          fireMushroomRemote("ScoreReset")
      end)

      createButton(MushroomFeaturedSection, "Glowy Crystals", function()
          fireMushroomRemote("GlowyReset")
      end)

      createButton(MushroomFeaturedSection, "Magic Energy Reset", function()
          fireMushroomRemote("ConvertCurrency", "Magic Energy")
      end)

      local function fireMushroomPlantSeed()
          local remote = getMainRemote and getMainRemote() or nil
          if not remote then
              return
          end
          local ok, plot = pcall(function()
              return workspace.__GAME_CONTENT.FarmPlot.Mushrooms[1].Plot
          end)
          if not ok or not plot then
              return
          end
          local arguments = {
              [1] = "PlantSeed",
              [2] = "Red Mushroom",
              [3] = CFrame.new(1829.5804443359375, 12.899375915527344, -1905.2508544921875, 1, 0, 0, 0, 1, 0, 0, 0, 1),
              [4] = 1,
              [5] = plot
          }
          pcall(function()
              remote:FireServer(unpack(arguments))
          end)
      end

      State.MushroomAutoPlantCollect = State.MushroomAutoPlantCollect or {
          Enabled = false,
          Conn = nil,
          Accum = 0,
          Interval = 0.35,
          Step = 1,
          PlantConns = nil,
          PlantQueue = nil,
          PlantScanIndex = 1
      }

      createToggle(MushroomFeaturedSection, "Auto Plant Collect Seed", nil, false, function(v)
          State.MushroomAutoPlantCollect.Enabled = v
          if State.MushroomAutoPlantCollect.Enabled then
              if State.MushroomAutoPlantCollect.Conn then
                  State.MushroomAutoPlantCollect.Conn:Disconnect()
              end
              if State.MushroomAutoPlantCollect.PlantConns then
                  for _, conn in ipairs(State.MushroomAutoPlantCollect.PlantConns) do
                      if conn then
                          conn:Disconnect()
                      end
                  end
              end
              State.MushroomAutoPlantCollect.PlantConns = {}
              State.MushroomAutoPlantCollect.PlantQueue = {}
              State.MushroomAutoPlantCollect.PlantScanIndex = 1
              local function enqueuePlant(plotIndex, plantId)
                  if not plotIndex or not plantId then
                      return
                  end
                  State.MushroomAutoPlantCollect.PlantQueue[#State.MushroomAutoPlantCollect.PlantQueue + 1] = {
                      Plot = plotIndex,
                      Id = plantId
                  }
              end
              local function collectOnePlant()
                  if not State.MushroomAutoPlantCollect.PlantQueue then
                      return
                  end
                  if #State.MushroomAutoPlantCollect.PlantQueue == 0 then
                      local okRoot, root = pcall(function()
                          return Players.LocalPlayer
                      end)
                      if okRoot and root then
                          local okFarm, farm = pcall(function()
                              return root:FindFirstChild("Farm")
                          end)
                          local plots = okFarm and farm and farm:FindFirstChild("Plots") or nil
                          local mushrooms = plots and plots:FindFirstChild("Mushrooms") or nil
                          if mushrooms then
                              for i = 1, 3 do
                                  local plotFolder = mushrooms:FindFirstChild(tostring(i))
                                  local currentPlants = plotFolder and plotFolder:FindFirstChild("CurrentPlants") or nil
                                  if currentPlants then
                                      for _, child in ipairs(currentPlants:GetChildren()) do
                                          enqueuePlant(i, child.Name)
                                      end
                                  end
                              end
                          end
                      end
                  end
                  local entry = table.remove(State.MushroomAutoPlantCollect.PlantQueue, 1)
                  if not entry then
                      return
                  end
                  local remote = getMainRemote and getMainRemote() or nil
                  if not remote then
                      return
                  end
                  pcall(function()
                      remote:FireServer("CollectPlant", "Mushrooms", entry.Plot, entry.Id)
                  end)
              end

              local okFarmRoot, farmRoot = pcall(function()
                  return Players.LocalPlayer
              end)
              local farm = okFarmRoot and farmRoot and farmRoot:FindFirstChild("Farm") or nil
              local plots = farm and farm:FindFirstChild("Plots") or nil
              local mushrooms = plots and plots:FindFirstChild("Mushrooms") or nil
              if mushrooms then
                  for i = 1, 3 do
                      local plotFolder = mushrooms:FindFirstChild(tostring(i))
                      local currentPlants = plotFolder and plotFolder:FindFirstChild("CurrentPlants") or nil
                      if currentPlants then
                          for _, child in ipairs(currentPlants:GetChildren()) do
                              enqueuePlant(i, child.Name)
                          end
                          local conn = currentPlants.ChildAdded:Connect(function(child)
                              enqueuePlant(i, child.Name)
                          end)
                          State.MushroomAutoPlantCollect.PlantConns[#State.MushroomAutoPlantCollect.PlantConns + 1] = conn
                      end
                  end
              end
              State.MushroomAutoPlantCollect.Accum = 0
              State.MushroomAutoPlantCollect.Step = 1
              State.MushroomAutoPlantCollect.Conn = RunService.Heartbeat:Connect(function(dt)
                  State.MushroomAutoPlantCollect.Accum += dt
                  if State.MushroomAutoPlantCollect.Accum >= State.MushroomAutoPlantCollect.Interval then
                      State.MushroomAutoPlantCollect.Accum = 0
                      if State.MushroomAutoPlantCollect.Step == 1 then
                          fireMushroomPlantSeed()
                          State.MushroomAutoPlantCollect.Step = 2
                      else
                          collectOnePlant()
                          State.MushroomAutoPlantCollect.Step = 1
                      end
                  end
              end)
              trackConnection(State.MushroomAutoPlantCollect.Conn)
          else
              if State.MushroomAutoPlantCollect.Conn then
                  State.MushroomAutoPlantCollect.Conn:Disconnect()
                  State.MushroomAutoPlantCollect.Conn = nil
              end
              if State.MushroomAutoPlantCollect.PlantConns then
                  for _, conn in ipairs(State.MushroomAutoPlantCollect.PlantConns) do
                      if conn then
                          conn:Disconnect()
                      end
                  end
                  State.MushroomAutoPlantCollect.PlantConns = nil
              end
              State.MushroomAutoPlantCollect.PlantQueue = nil
          end
      end)
  end

  State.InitMushroom = function()
      local MushroomAutomationSection = createSectionBox(State.MushroomTab:GetPage(), "Automation")
      setupAutoBuyGroup(MushroomAutomationSection, {
          GroupKey = "Mushroom World",
          DisplayName = "Auto Buy Shop",
          ModeToggleName = "Mode: Upgrade All",
          SpeedLabel = "Click Speed (sec)",
          CooldownKey = "MushroomAutoBuy",
          DefaultCooldown = 0.6,
          Shops = {
              {
                  Key = "Fungus",
                  DisplayName = "Fungus Shop",
                  ShopName = "Fungus",
              },
              {
                  Key = "Spores",
                  DisplayName = "Spores Shop",
                  ShopName = "Spores",
              }
          }
      })
  end

createButton(TeleportSection, "Home", function()
    teleportHomeSmart("Space World")
end)

local PlanetifyAutoEnabled = false
local PlanetifyAutoConn = nil
local PlanetifyAutoAccum = 0
local PlanetifyAutoInterval = 5

local function firePlanetifyUp()
    local remote = getMainRemote and getMainRemote() or nil
    if not remote then
        return
    end
    pcall(function()
        remote:FireServer("PlanetifyUp")
    end)
end

createToggle(TeleportSection, "Auto Upgrade Planetify", nil, false, function(v)
    PlanetifyAutoEnabled = v
    if PlanetifyAutoEnabled then
        if PlanetifyAutoConn then
            PlanetifyAutoConn:Disconnect()
        end
        PlanetifyAutoAccum = 0
        firePlanetifyUp()
        PlanetifyAutoConn = RunService.Heartbeat:Connect(function(dt)
            PlanetifyAutoAccum += dt
            if PlanetifyAutoAccum >= PlanetifyAutoInterval then
                PlanetifyAutoAccum = 0
                firePlanetifyUp()
            end
        end)
        trackConnection(PlanetifyAutoConn)
    else
        if PlanetifyAutoConn then
            PlanetifyAutoConn:Disconnect()
            PlanetifyAutoConn = nil
        end
    end
end)

createButton(TeleportSection, "Upgrade Planetify", function()
    firePlanetifyUp()
end)

-- [SECTION] Farming Teleports
local FarmingSection = createSubSectionBox(TeleportSection, "Farming")
local FarmingList = {
    {Label = "Off", Data = makeData(
        Vector3.new(1350.989, 14.000, 1837.671),
        CFrame.new(1348.699951, 15.408682, 1847.589722, 0.974393725, -0.002014387, -0.224839613, 0.000000000, 0.999959946, -0.008958858, 0.224848613, 0.008729455, 0.974354684),
        CFrame.new(1350.988770, 15.499881, 1837.671021, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        10.179767
    )},
    {Label = "Dirtite", Data = makeData(
        Vector3.new(1537.805, 7.117, 1847.591),
        CFrame.new(1528.735107, 11.330198, 1861.700439, 0.841190636, 0.086346850, -0.533800125, 0.000000000, 0.987168372, 0.159683138, 0.540738702, -0.134323955, 0.830396771),
        CFrame.new(1537.805054, 8.616975, 1847.590942, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        16.991276
    )},
    {Label = "Moonlite", Data = makeData(
        Vector3.new(1508.873, 8.290, 1858.007),
        CFrame.new(1518.843140, 13.063017, 1866.004150, 0.625704587, -0.193504289, 0.755678475, 0.000000000, 0.968743861, 0.248063311, -0.780060112, -0.155214354, 0.606147468),
        CFrame.new(1508.873413, 9.790308, 1858.007202, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.193076
    )},
    {Label = "Marsite", Data = makeData(
        Vector3.new(1511.441, 8.345, 1935.476),
        CFrame.new(1520.044189, 14.466647, 1944.345703, 0.717809558, -0.243914172, 0.652116001, 0.000000000, 0.936625957, 0.350330859, -0.696239471, -0.251470834, 0.672319114),
        CFrame.new(1511.440796, 9.844719, 1935.475830, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.193000
    )},
    {Label = "Venusite", Data = makeData(
        Vector3.new(1553.479, 8.388, 1936.836),
        CFrame.new(1544.007080, 13.947904, 1928.597900, -0.656242728, 0.232171014, -0.717943013, 0.000000000, 0.951485157, 0.307694733, 0.754549861, 0.201922432, -0.624405205),
        CFrame.new(1553.478882, 9.888475, 1936.835693, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.192999
    )},
    {Label = "Mercuryte", Data = makeData(
        Vector3.new(1560.474, 13.857, 2044.468),
        CFrame.new(1550.212769, 18.485125, 2036.788086, -0.599218488, 0.189828783, -0.777754605, 0.000000000, 0.971482158, 0.237112448, 0.800585508, 0.142082170, -0.582130075),
        CFrame.new(1560.473755, 15.356892, 2044.468140, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.193063
    )},
    {Label = "Jupiterite", Data = makeData(
        Vector3.new(1507.067, 13.997, 2041.918),
        CFrame.new(1514.134399, 18.913727, 2052.520752, 0.832089007, -0.143643469, 0.535718620, 0.000000000, 0.965881586, 0.258984059, -0.554642141, -0.215497792, 0.803699434),
        CFrame.new(1507.066650, 15.496941, 2041.917603, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.192964
    )},
    {Label = "Saturnite", Data = makeData(
        Vector3.new(1388.847, 14.858, 1931.079),
        CFrame.new(1398.133667, 21.941149, 1923.552612, -0.629673660, -0.328747690, 0.703872144, 0.000000000, 0.906047940, 0.423175126, -0.776859701, 0.266462237, -0.570514560),
        CFrame.new(1388.847412, 16.358183, 1931.079468, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.193089
    )},
    {Label = "Uranite", Data = makeData(
        Vector3.new(1392.464, 15.014, 1863.205),
        CFrame.new(1383.630005, 20.926165, 1871.954346, 0.703717947, 0.237600029, -0.669572532, 0.000000000, 0.942423463, 0.334422082, 0.710479498, -0.235338822, 0.663200259),
        CFrame.new(1392.463745, 16.514122, 1863.204712, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.193073
    )},
    {Label = "Neptunite", Data = makeData(
        Vector3.new(1325.698, 15.001, 1931.861),
        CFrame.new(1335.290161, 21.812218, 1939.198364, 0.607569277, -0.319782197, 0.727048099, 0.000000000, 0.915370226, 0.402613163, -0.794266641, -0.244615391, 0.556150854),
        CFrame.new(1325.698242, 16.500526, 1931.861084, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.192978
    )},
    {Label = "Plutite", Data = makeData(
        Vector3.new(1326.639, 15.021, 1862.472),
        CFrame.new(1334.038696, 19.762333, 1868.665894, 0.641903698, -0.244157791, 0.726874590, 0.000000000, 0.947950602, 0.318417430, -0.766785264, -0.204393327, 0.608493030),
        CFrame.new(1326.639282, 16.520918, 1862.471558, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        10.179779
    )},
    {Label = "Sunite", Data = makeData(
        Vector3.new(1367.133, 14.919, 1911.106),
        CFrame.new(1374.885620, 18.384340, 1904.808228, -0.630487323, -0.149821639, 0.761603057, 0.000000000, 0.981194913, 0.193019480, -0.776199579, 0.121696338, -0.618630946),
        CFrame.new(1367.132690, 16.419447, 1911.105713, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        10.179737
    )}
}
createGrid(FarmingSection, FarmingList, function(item)
    teleportWithData(item.Data)
end)

-- [SECTION] Upgrade Teleports
local UpgradesSection = createSubSectionBox(TeleportSection, "Upgrades")
local UpgradeList = {
    {Label = "Planetify", Data = makeData(
        Vector3.new(1349.213, 14.000, 1841.135),
        CFrame.new(1348.220215, 18.136295, 1850.917480, 0.994891346, 0.026145127, -0.097507425, 0.000000000, 0.965881050, 0.258986235, 0.100951798, -0.257663161, 0.960946679),
        CFrame.new(1349.212769, 15.499880, 1841.135254, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        10.179774
    )},
    {Label = "Cosmic", Data = makeData(
        Vector3.new(1342.559, 14.000, 1950.314),
        CFrame.new(1345.764282, 18.080660, 1941.003174, -0.945552766, -0.082516216, 0.314834923, 0.000000000, 0.967327535, 0.253530324, -0.325468808, 0.239726305, -0.914659202),
        CFrame.new(1342.559326, 15.499784, 1950.314209, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        10.179786
    )},
    {Label = "Light Point", Data = makeData(
        Vector3.new(1580.509, 13.182, 2086.330),
        CFrame.new(1573.286621, 17.373627, 2079.680176, -0.677312553, 0.194543391, -0.709507287, 0.000000000, 0.964403629, 0.264434695, 0.735695422, 0.179104939, -0.653202653),
        CFrame.new(1580.509277, 14.681747, 2086.329590, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        10.179769
    )},
    {Label = "Rarities", Data = makeData(
        Vector3.new(1534.464, 13.743, 2123.736),
        CFrame.new(1536.074341, 21.832954, 2112.384033, -0.990087509, -0.069984615, 0.121773958, 0.000000000, 0.867015183, 0.498281628, -0.140451923, 0.493342429, -0.858420908),
        CFrame.new(1534.463867, 15.243335, 2123.736328, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224648
    )},
    {Label = "Milestones", Data = makeData(
        Vector3.new(1308.464, 14.000, 1896.676),
        CFrame.new(1321.018677, 19.640011, 1896.302368, -0.029771226, -0.312925488, 0.949310958, 0.000000000, 0.949731946, 0.313064277, -0.999556720, 0.009320308, -0.028274683),
        CFrame.new(1308.464355, 15.499832, 1896.676270, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224669
    )}
}
createGrid(UpgradesSection, UpgradeList, function(item)
    teleportWithData(item.Data)
end)

-- [SECTION] Rune Teleports
local RunesSection = createSubSectionBox(TeleportSection, "Runes")
local RuneList = {
    {Label = "Rune 1", Data = makeData(
        Vector3.new(1578.512, 8.243, 1908.216),
        CFrame.new(1574.903687, 19.520142, 1900.074707, -0.914211333, 0.299600005, -0.272868961, 0.000000000, 0.673355281, 0.739319086, 0.405237734, 0.675893903, -0.615589023),
        CFrame.new(1578.512329, 9.742876, 1908.215698, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224710
    )},
    {Label = "Rune 2", Data = makeData(
        Vector3.new(1489.634, 14.257, 2078.613),
        CFrame.new(1499.110962, 24.800543, 2080.426758, 0.187963307, -0.671668887, 0.716610610, 0.000000000, 0.729615211, 0.683857977, -0.982176006, -0.128540203, 0.137140900),
        CFrame.new(1489.634033, 15.756733, 2078.613037, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224684
    )},
    {Label = "Rune 3", Data = makeData(
        Vector3.new(1338.119, 14.581, 1889.744),
        CFrame.new(1327.494873, 23.738945, 1887.906616, -0.170450062, 0.570582867, -0.803356767, 0.000000000, 0.815287411, 0.579056561, 0.985366344, 0.098700225, -0.138965786),
        CFrame.new(1338.119019, 16.081100, 1889.744385, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224690
    )},
    {Label = "Rune 4", Data = makeData(
        Vector3.new(1300.185, 17.058, 1874.232),
        CFrame.new(1291.605103, 24.533360, 1869.602051, -0.474915117, 0.459868014, -0.750318050, 0.000000000, 0.852603555, 0.522558510, 0.880031645, 0.248170942, -0.404914290),
        CFrame.new(1300.184937, 18.557924, 1874.232178, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        11.434922
    )}
}
registerRuneLocations("Space World", RuneList)
createGrid(RunesSection, RuneList, function(item)
    teleportWithData(item.Data)
end)
    stepWorld("Space World")

    local function addEmptyAutomation(tab)
        local section = createSectionBox(tab:GetPage(), "Automation")
        return section
    end

    addEmptyAutomation(State.Tabs.Cyber)

end

initWorldTeleports()

local function initEventTabs()
State.Tabs.Heaven = createTab("Heaven World")
State.Tabs.Hell = createTab("Hell World")
State.Tabs.Garden = createTab("The Garden")
createTabDivider()
State.Tabs.Event500K = createTab("500K Event")
State.Tabs.Halloween = createTab("Halloween")
State.Tabs.Thanksgiving = createTab("Thanksgiving")
State.Tabs.Event3M = createTab("3M Event")
State.Tabs.Christmas = createTab("Christmas Event")
State.Tabs.FiveM = createTab("5M Event")
State.Tabs.Valentine = createTab("Valentine Event")
local function getGraceRemote()
    local ok, remote = pcall(function()
        return game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
    end)
    if ok and remote then
        return remote
    end
    return nil
end
State.InitValentine = function()
    local tab = State.Tabs.Valentine
    local ValentineTeleportSection = createSectionBox(tab:GetPage(), "Teleport")
    createButton(ValentineTeleportSection, "Home", function()
        fireWorldTeleport("Valentine Event")
    end)
    local ValentineList = {
        {Label = "Hearts Shop", Data = makeData(
            Vector3.new(-2040.686, 14.117, 4049.567),
            CFrame.new(-2027.499390, 23.525322, 4056.531738, 0.467003912, -0.414262772, 0.781213045, 0.000000000, 0.883470118, 0.468487740, -0.884255290, -0.218785614, 0.412583947),
            CFrame.new(-2040.686401, 15.617151, 4049.567139, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            16.880228
        )},
        {Label = "Love Shop", Data = makeData(
            Vector3.new(-1983.894, 14.117, 4005.831),
            CFrame.new(-1988.285400, 21.079636, 4021.187500, 0.961453974, 0.088979825, -0.260170966, 0.000000000, 0.946193039, 0.323602915, 0.274966091, -0.311129302, 0.909720957),
            CFrame.new(-1983.893677, 15.617151, 4005.831299, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            16.880133
        )},
        {Label = "Heart Rank", Data = makeData(
            Vector3.new(-1972.060, 14.617, 4091.901),
            CFrame.new(-1985.925537, 22.735849, 4084.908936, -0.450254291, 0.350105762, -0.821399450, 0.000000000, 0.919922829, 0.392099440, 0.892900407, 0.176544458, -0.414199203),
            CFrame.new(-1972.060181, 16.117128, 4091.900635, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            16.880148
        )},
        {Label = "Passive", Data = makeData(
            Vector3.new(-1990.651, 14.617, 4116.184),
            CFrame.new(-1990.299805, 25.575970, 4102.207520, -0.999684215, -0.014081959, 0.020813992, 0.000000000, 0.828248203, 0.560361385, -0.025130138, 0.560184419, -0.827986658),
            CFrame.new(-1990.651123, 16.116953, 4116.184082, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            16.880188
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(-1978.654, 15.275, 4041.959),
            CFrame.new(-1978.351685, 27.382614, 4055.086914, 0.999734581, -0.014476158, 0.017920133, 0.000000000, 0.777894437, 0.628395081, -0.023036715, -0.628228307, 0.777688026),
            CFrame.new(-1978.654175, 16.775175, 4041.959473, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            16.880135
        )}
    }
    registerRuneLocations("Valentine Event", ValentineList)
    createGrid(ValentineTeleportSection, ValentineList, function(item)
        teleportWithData(item.Data)
    end)

    local ValentineAutomationSection = createSectionBox(tab:GetPage(), "Automation")
    setupAutoBuyGroup(ValentineAutomationSection, {
        GroupKey = "Valentine Event",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Mode: Upgrade All",
        SpeedLabel = "Click Speed (sec)",
        CooldownKey = "ValentineAutoBuy",
        DefaultCooldown = 0.6,
        Shops = {
            {
                Key = "Hearts",
                DisplayName = "Hearts Shop",
                ShopName = "Hearts",
            },
            {
                Key = "Love",
                DisplayName = "Love Shop",
                ShopName = "Love",
            }
        }
    })
end

do
    local HellTeleportSection = createSectionBox(State.Tabs.Hell:GetPage(), "Teleport")
    createButton(HellTeleportSection, "Home", function()
        teleportHomeSmart("Hell World")
    end)
    local DropperSection = createSubSectionBox(HellTeleportSection, "Dropper")
    local DropperList = {
        {Label = "One", Data = makeData(
            Vector3.new(1533.979, 7.918, 3798.505),
            CFrame.new(1528.418823, 23.701048, 3806.732910, 0.818755865, 0.461416394, -0.341663152, 0.000000000, 0.595084965, 0.803662837, 0.574141741, -0.658003688, 0.487229377),
            CFrame.new(1534.491089, 9.417870, 3798.073486, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772654
        )},
        {Label = "Two", Data = makeData(
            Vector3.new(1546.125, 7.925, 3792.548),
            CFrame.new(1554.241821, 22.212158, 3804.086426, 0.818145394, -0.413929135, 0.399125129, 0.000000000, 0.694116831, 0.719862461, -0.575011432, -0.588952184, 0.567888498),
            CFrame.new(1547.148315, 9.418330, 3793.993652, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772562
        )},
        {Label = "Three", Data = makeData(
            Vector3.new(1554.918, 7.851, 3783.699),
            CFrame.new(1564.829102, 22.689465, 3783.574463, 0.078451701, -0.744417369, 0.663089871, 0.000000000, 0.665139854, 0.746718824, -0.996917903, -0.058581360, 0.052181356),
            CFrame.new(1553.044312, 9.418330, 3782.646973, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772577
        )},
        {Label = "Four", Data = makeData(
            Vector3.new(1553.238, 7.918, 3773.803),
            CFrame.new(1565.648926, 22.636124, 3768.303711, -0.291043341, -0.710790098, 0.640368044, 0.000000000, 0.669344008, 0.742952645, -0.956709802, 0.216231421, -0.194808140),
            CFrame.new(1554.267944, 9.431924, 3771.765869, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772568
        )},
        {Label = "Five", Data = makeData(
            Vector3.new(1548.863, 7.825, 3762.633),
            CFrame.new(1554.781128, 22.689468, 3753.346191, -0.790159523, -0.457664937, 0.407664895, 0.000000000, 0.665139675, 0.746719003, -0.612901151, 0.590027153, -0.525566459),
            CFrame.new(1547.535889, 9.418330, 3762.686768, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772533
        )},
        {Label = "Six", Data = makeData(
            Vector3.new(1532.552, 7.725, 3757.012),
            CFrame.new(1535.961670, 23.760986, 3747.564697, -0.996751368, -0.064996175, 0.047561705, 0.000000000, 0.590538502, 0.807009518, -0.080539539, 0.804387867, -0.588620126),
            CFrame.new(1535.116333, 9.418330, 3758.026123, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772671
        )},
        {Label = "Seven", Data = makeData(
            Vector3.new(1520.252, 7.738, 3760.285),
            CFrame.new(1517.094971, 24.597157, 3754.183350, -0.824714720, 0.483011454, -0.294186234, 0.000000000, 0.520178199, 0.854057729, 0.565548956, 0.704353988, -0.428998619),
            CFrame.new(1522.323364, 9.418330, 3761.807861, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772621
        )},
        {Label = "Eight", Data = makeData(
            Vector3.new(1514.192, 7.918, 3773.101),
            CFrame.new(1503.687500, 24.370922, 3767.868896, -0.367143840, 0.786107242, -0.497233063, 0.000000000, 0.534564853, 0.845127404, 0.930164158, 0.310283333, -0.196262181),
            CFrame.new(1512.524658, 9.350810, 3771.356934, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772606
        )},
        {Label = "Nine", Data = makeData(
            Vector3.new(1513.201, 7.918, 3781.547),
            CFrame.new(1506.086426, 25.188061, 3783.824463, 0.158509895, 0.876087785, -0.455351174, 0.000000000, 0.461181700, 0.887305737, 0.987357318, -0.140646741, 0.073101871),
            CFrame.new(1514.179199, 9.418330, 3782.525146, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772608
        )},
        {Label = "Ten", Data = makeData(
            Vector3.new(1521.728, 7.918, 3792.526),
            CFrame.new(1515.554932, 22.781784, 3804.703369, 0.858068466, 0.394812584, -0.328392297, 0.000000000, 0.639473677, 0.768813014, 0.513535261, -0.659694195, 0.548712194),
            CFrame.new(1521.391357, 9.117979, 3794.951416, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772564
        )}
    }
    State.HellTeleports = State.HellTeleports or {}
    State.HellTeleports.Dropper = State.HellTeleports.Dropper or {}
    for _, item in ipairs(DropperList) do
        State.HellTeleports.Dropper[item.Label] = item.Data
    end
    createGrid(DropperSection, DropperList, function(item)
        teleportWithData(item.Data)
    end)

    local HellList = {
        {Label = "Madness Shop", Data = makeData(
            Vector3.new(1473.467, 8.418, 3875.737),
            CFrame.new(1481.869141, 21.914501, 3862.857178, -0.837532520, -0.336074769, 0.430805087, 0.000000000, 0.788460791, 0.615085125, -0.546387434, 0.515153766, -0.660361588),
            CFrame.new(1473.466675, 9.917869, 3875.736816, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503992
        )},
        {Label = "Hell Rank", Data = makeData(
            Vector3.new(1453.755, 6.917, 3839.862),
            CFrame.new(1469.700073, 13.144405, 3850.050781, 0.538469136, -0.204231873, 0.817520916, 0.000000000, 0.970183969, 0.242369920, -0.842645288, -0.130508721, 0.522414088),
            CFrame.new(1453.755127, 8.417223, 3839.861572, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504040
        )},
        {Label = "Sins Shop", Data = makeData(
            Vector3.new(1624.898, 7.417, 3854.722),
            CFrame.new(1606.193726, 18.282265, 3841.251465, -0.584383786, 0.305446982, -0.751796305, 0.000000000, 0.926453710, 0.376408517, 0.811477304, 0.219967037, -0.541404605),
            CFrame.new(1624.898438, 8.917222, 3854.721680, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880051
        )},
        {Label = "Ember Tree 1", Data = makeData(
            Vector3.new(1532.551, 6.917, 3875.136),
            CFrame.new(1532.652832, 47.809532, 3868.190430, -0.999892652, -0.014428793, 0.002544191, 0.000000000, 0.173648581, 0.984807730, -0.014651380, 0.984701991, -0.173629940),
            CFrame.new(1532.551025, 8.417223, 3875.135742, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            40.000023
        )},
        {Label = "Ember Tree 2", Data = makeData(
            Vector3.new(1532.130, 6.917, 3903.638),
            CFrame.new(1532.231689, 47.809532, 3896.693115, -0.999892652, -0.014428793, 0.002544191, 0.000000000, 0.173648581, 0.984807730, -0.014651380, 0.984701991, -0.173629940),
            CFrame.new(1532.129883, 8.417223, 3903.638428, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            40.000023
        )},
        {Label = "Curses Roll", Data = makeData(
            Vector3.new(1590.580, 7.417, 3871.864),
            CFrame.new(1602.701782, 39.813530, 3849.537598, -0.878821611, -0.368554652, 0.303051174, 0.000000000, 0.635127068, 0.772407651, -0.477150440, 0.678808510, -0.558163404),
            CFrame.new(1590.579712, 8.917223, 3871.864014, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            39.999939
        )},
        {Label = "Hell XP Shop", Data = makeData(
            Vector3.new(1558.933, 7.217, 3829.225),
            CFrame.new(1545.091797, 14.504358, 3816.761719, -0.669123828, 0.220504314, -0.709683895, 0.000000000, 0.954966068, 0.296715349, 0.743151009, 0.198539317, -0.638990462),
            CFrame.new(1558.933472, 8.717222, 3829.224609, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504013
        )},
        {Label = "Ember Milestone", Data = makeData(
            Vector3.new(1512.262, 7.017, 3813.122),
            CFrame.new(1530.427124, 12.061178, 3819.277344, 0.320935100, -0.172092095, 0.931335032, 0.000000000, 0.983353257, 0.181704029, -0.947101176, -0.058315203, 0.315592587),
            CFrame.new(1512.262329, 8.517222, 3813.122070, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504021
        )},
        {Label = "Milestone", Data = makeData(
            Vector3.new(1477.510, 7.417, 3821.921),
            CFrame.new(1482.308716, 17.365757, 3838.832275, 0.962025285, -0.118238114, 0.246022791, 0.000000000, 0.901312768, 0.433169246, -0.272960544, -0.416719764, 0.867085576),
            CFrame.new(1477.510254, 8.917223, 3821.920654, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503996
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(1521.693, 8.031, 3858.946),
            CFrame.new(1505.974731, 17.580893, 3850.665771, -0.466070175, 0.365145415, -0.805882990, 0.000000000, 0.910861850, 0.412711322, 0.884747744, 0.192352444, -0.424525559),
            CFrame.new(1521.692627, 9.531371, 3858.945801, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503998
        )}
    }
    registerRuneLocations("Hell World", HellList)
    State.HellTeleports = State.HellTeleports or {}
    for _, item in ipairs(HellList) do
        if item.Label == "Madness Shop" then
            State.HellTeleports.Madness = item.Data
        elseif item.Label == "Rune" then
            State.HellTeleports.Rune = item.Data
        end
    end
    createGrid(HellTeleportSection, HellList, function(item)
        teleportWithData(item.Data)
    end)
end

do
    local GardenTeleportSection = createSectionBox(State.Tabs.Garden:GetPage(), "Teleport")
    createButton(GardenTeleportSection, "Home", function()
        teleportHomeSmart("The Garden")
    end)
end

State.InitGarden = function()
    local tab = State.Tabs.Garden
    local GardenAutomationSection = createSectionBox(tab:GetPage(), "Automation")

    setupAutoBuyGroup(GardenAutomationSection, {
        GroupKey = "The Garden",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Mode: Upgrade All",
        SpeedLabel = "Click Speed (sec)",
        CooldownKey = "GardenAutoBuy",
        DefaultCooldown = 0.6,
        Shops = {
            {
                Key = "Fall Leaves",
                DisplayName = "Fall Leaves",
                ShopName = "Fall Leaves"
            },
            {
                Key = "Strawberries",
                DisplayName = "Strawberries",
                ShopName = "Strawberries"
            },
            {
                Key = "Flowers",
                DisplayName = "Flowers",
                ShopName = "Flowers"
            },
            {
                Key = "Honey",
                DisplayName = "Honey",
                ShopName = "Honey"
            }
        }
    })

    local upgradeTreeSection = createSubSectionBox(GardenAutomationSection, "Auto Upgrade Garden Tree")
    Config.GardenAutoUpgradeTreeEnabled = Config.GardenAutoUpgradeTreeEnabled == true

    State.GardenAutoUpgradeTree = State.GardenAutoUpgradeTree or {
        Enabled = Config.GardenAutoUpgradeTreeEnabled == true,
        OwnerKey = "GardenAutoUpgradeTree",
        Cache = nil,
        LastUpgradeDisplay = "-",
        LastCheckDisplay = "-",
        PendingUpgrade = nil,
        FailedByKey = {}
    }

    local function gardenTreeReadNumber(node)
        local helpers = State.AutoBuyShop and State.AutoBuyShop.Helpers or nil
        if helpers and helpers.GetNumericValueFromNode then
            local n = helpers.GetNumericValueFromNode(node)
            if type(n) == "number" then
                return n
            end
        end
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        local n = tonumber(raw)
        if type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge then
            return n
        end
        return nil
    end

    local function gardenTreeFindChildCaseInsensitive(parent, name)
        if not parent or type(name) ~= "string" or #name == 0 then
            return nil
        end
        local direct = parent:FindFirstChild(name)
        if direct then
            return direct
        end
        local target = string.lower(name)
        for _, child in ipairs(parent:GetChildren()) do
            if string.lower(tostring(child.Name)) == target then
                return child
            end
        end
        return nil
    end

    local function gardenTreeReadString(node)
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if ok and type(raw) == "string" and #raw > 0 then
            return raw
        end
        return nil
    end

    local function gardenTreeGetCurrencyAmount(currencyName)
        if not LP or type(currencyName) ~= "string" or #currencyName == 0 then
            return nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        if not currencyRoot then
            return nil
        end
        local currencyFolder = gardenTreeFindChildCaseInsensitive(currencyRoot, currencyName)
        if not currencyFolder then
            return nil
        end
        local amountRoot = currencyFolder:FindFirstChild("Amount")
        local amountNode = amountRoot and (amountRoot:FindFirstChild("1") or amountRoot:FindFirstChildWhichIsA("ValueBase"))
        return gardenTreeReadNumber(amountNode)
    end

    local function gardenTreeGetUpgradeNode(key)
        if not LP or type(key) ~= "string" or #key == 0 then
            return nil
        end
        local treeRoot = LP:FindFirstChild("UpgradeTree")
        if not treeRoot then
            return nil
        end
        return gardenTreeFindChildCaseInsensitive(treeRoot, key)
    end

    local function gardenTreeGetUpgradeAmount(key)
        local node = gardenTreeGetUpgradeNode(key)
        local amountNode = node and node:FindFirstChild("Amount")
        local amount = gardenTreeReadNumber(amountNode)
        if type(amount) == "number" then
            return math.max(0, math.floor(amount + 0.5))
        end
        return 0
    end

    local function gardenTreeIsUnlocked(key)
        local node = gardenTreeGetUpgradeNode(key)
        local unlockedNode = node and node:FindFirstChild("Unlocked")
        if not unlockedNode then
            return false
        end
        local ok, value = pcall(function()
            return unlockedNode.Value
        end)
        return ok and value == true
    end

    local function gardenTreeGetLevelLimit(key)
        local node = gardenTreeGetUpgradeNode(key)
        local special = node and node:FindFirstChild("SpecialConditions")
        local limitNode = special and special:FindFirstChild("LevelLimit")
        local limit = gardenTreeReadNumber(limitNode)
        if type(limit) == "number" and limit > 0 then
            return math.max(1, math.floor(limit + 0.5))
        end
        return nil
    end

    local function gardenTreeReadValueByNames(parent, names)
        if not parent or type(names) ~= "table" then
            return nil
        end
        for _, name in ipairs(names) do
            local node = gardenTreeFindChildCaseInsensitive(parent, name)
            local value = gardenTreeReadNumber(node)
            if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
                return value
            end
        end
        return nil
    end

    local function gardenTreeReadCostFromUpgradeNode(node)
        if not node then
            return nil
        end
        local direct = gardenTreeReadValueByNames(node, {"NextCost", "CurrentCost", "Cost", "Price"})
        if type(direct) == "number" and direct > 0 then
            return direct
        end

        local special = node:FindFirstChild("SpecialConditions")
        local specialCost = gardenTreeReadValueByNames(special, {"NextCost", "CurrentCost", "Cost", "Price"})
        if type(specialCost) == "number" and specialCost > 0 then
            return specialCost
        end

        local function normalizeName(text)
            local out = string.lower(tostring(text or ""))
            out = out:gsub("[%s%-%_]+", "")
            return out
        end

        local function scoreCostField(nameLower)
            if type(nameLower) ~= "string" or #nameLower == 0 then
                return nil
            end
            local blocked = {
                "decrease",
                "discount",
                "multiply",
                "multiplier",
                "reward",
                "cooldown",
                "unlock",
                "required",
                "requirement",
                "level",
                "limit",
                "max",
                "min"
            }
            for _, token in ipairs(blocked) do
                if string.find(nameLower, token, 1, true) then
                    return nil
                end
            end
            if nameLower == "nextcost" then
                return 110
            end
            if nameLower == "currentcost" then
                return 100
            end
            if nameLower == "upgradecost" then
                return 95
            end
            if nameLower == "cost" then
                return 90
            end
            if nameLower == "price" then
                return 80
            end
            if nameLower:sub(-4) == "cost" then
                return 70
            end
            if nameLower:sub(-5) == "price" then
                return 60
            end
            return nil
        end

        local bestValue = nil
        local bestScore = nil
        for _, desc in ipairs(node:GetDescendants()) do
            local parentName = normalizeName((desc.Parent and desc.Parent.Name) or "")
            if string.find(parentName, "unlock", 1, true) == nil
                and string.find(parentName, "require", 1, true) == nil
                and string.find(parentName, "level", 1, true) == nil
                and string.find(parentName, "reward", 1, true) == nil then
                local name = normalizeName(desc.Name or "")
                local score = scoreCostField(name)
                if score then
                    local value = gardenTreeReadNumber(desc)
                    if type(value) == "number" and value == value and value > 0 and value ~= math.huge and value ~= -math.huge then
                        if bestValue == nil
                            or score > bestScore
                            or (score == bestScore and value > bestValue) then
                            bestValue = value
                            bestScore = score
                        end
                    end
                end
            end
        end
        return bestValue
    end

    local function gardenTreeResolveDisplayName(key, node)
        local displayNode = node and gardenTreeFindChildCaseInsensitive(node, "DisplayName")
        if displayNode then
            local text = gardenTreeReadString(displayNode)
            if type(text) == "string" and #text > 0 then
                return text
            end
        end
        local raw = tostring(key or "")
        raw = raw:gsub("^Garden_", "")
        raw = raw:gsub("_", " ")
        raw = raw:gsub("%s+", " ")
        raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if #raw > 0 then
            return raw
        end
        return tostring(key or "-")
    end

    local function gardenTreeResolveCurrencyName(node)
        local currencyNode = node and gardenTreeFindChildCaseInsensitive(node, "UpgradeCurrency")
        local text = gardenTreeReadString(currencyNode)
        if type(text) == "string" and #text > 0 then
            return text
        end
        return "Garden Points"
    end

    local function gardenTreeFormatProgressDisplay(nameOrItem, amount, maxLevel, maxLabel, cost)
        local name = "-"
        if type(nameOrItem) == "table" then
            name = tostring((nameOrItem.DisplayName or nameOrItem.Key) or "-")
        else
            name = tostring(nameOrItem or "-")
        end
        local ownText = tostring(tonumber(amount) or 0)
        local maxText = type(maxLabel) == "string" and #maxLabel > 0 and maxLabel
            or (type(maxLevel) == "number" and tostring(maxLevel) or "?")
        local costText = type(cost) == "number" and autoBuyLogFormatNumber(cost) or "?"
        return name .. " (" .. ownText .. "/" .. maxText .. ") | Cost: " .. tostring(costText)
    end

    local function gardenTreeGetModule()
        local state = State.GardenAutoUpgradeTree
        if state and type(state.Cache) == "table" and type(state.Cache.Items) == "table" and type(state.Cache.TreeRoot) == "Instance" then
            if state.Cache.TreeRoot.Parent and #state.Cache.TreeRoot:GetChildren() == (state.Cache.TreeCount or 0) then
                return state.Cache
            end
        end

        local treeRoot = LP and LP:FindFirstChild("UpgradeTree")
        if not treeRoot then
            return nil
        end

        local items = {}
        for _, child in ipairs(treeRoot:GetChildren()) do
            if child and type(child.Name) == "string" then
                local key = tostring(child.Name)
                if string.find(key, "Garden_", 1, true) == 1 then
                    items[#items + 1] = {
                        Key = key,
                        DisplayName = gardenTreeResolveDisplayName(key, child),
                        UpgradeCurrency = gardenTreeResolveCurrencyName(child),
                        RuntimeNode = child
                    }
                end
            end
        end

        table.sort(items, function(a, b)
            return tostring(a.Key) < tostring(b.Key)
        end)

        if #items == 0 then
            return state and state.Cache or nil
        end

        local cache = {
            Items = items,
            TreeRoot = treeRoot,
            TreeCount = #treeRoot:GetChildren()
        }
        if state then
            state.Cache = cache
        end
        return cache
    end

    local function gardenTreeBuildLogUpdate(meta, forceRefresh)
        if not AutoBuyLogState then
            return
        end
        local actionKey = "GardenAutoUpgradeTree"
        local data = AutoBuyLogState.ActionData[actionKey] or {
            Key = actionKey,
            Name = "Auto Upgrade Garden Tree",
            Success = 0
        }
        data.Key = actionKey
        data.Name = "Auto Upgrade Garden Tree"
        data.Success = tonumber(data.Success) or 0

        local lastUpgrade = (meta and meta.LastUpgrade) or "-"
        local lastCheck = (meta and meta.LastCheck) or "-"
        local locked = tonumber(meta and meta.Locked) or 0
        local unlocked = tonumber(meta and meta.Unlocked) or 0
        local totalItem = tonumber(meta and meta.TotalItem) or 0
        local totalMax = tonumber(meta and meta.TotalMax) or 0
        local currencyText = tostring((meta and meta.CurrencyText) or "-")
        data.CurrencyText = currencyText
        data.DetailText =
            "Last Upgrade: " .. tostring(lastUpgrade)
            .. "\n----------------"
            .. "\nLast Check: " .. tostring(lastCheck)
            .. "\n----------------"
            .. "\nLocked: " .. tostring(locked) .. " | Unlocked: " .. tostring(unlocked)
            .. "\n----------------"
            .. "\nTotal Item: " .. tostring(totalItem) .. " | Total Max: " .. tostring(totalMax)

        AutoBuyLogState.ActionData[actionKey] = data
        if AutoBuyLogState.ActiveActions[actionKey] then
            AutoBuyLogState.ActiveActions[actionKey] = data
            if forceRefresh ~= false then
                updateAutoBuyLogUI()
            end
        end
    end

    local function gardenTreeResolveRemoteArgument(key)
        if type(key) ~= "string" then
            return nil
        end
        local out = key
        out = out:gsub("^Garden_", "")
        out = (out:gsub("^%s+", ""):gsub("%s+$", ""))
        if #out == 0 then
            return nil
        end
        return out
    end

    local function gardenTreeProcessPendingUpgrade(state)
        if not state then
            return false, false
        end
        local pending = state.PendingUpgrade
        if type(pending) ~= "table" or type(pending.Key) ~= "string" then
            state.PendingUpgrade = nil
            return false, false
        end

        local key = pending.Key
        local amountNow = gardenTreeGetUpgradeAmount(key)
        local amountBefore = tonumber(pending.AmountBefore) or 0
        if type(amountNow) == "number" and amountNow > amountBefore then
            state.LastUpgradeDisplay = gardenTreeFormatProgressDisplay(
                tostring(pending.DisplayName or pending.Key or "-"),
                amountNow,
                tonumber(pending.MaxLevel),
                pending.MaxLabel,
                tonumber(pending.Cost)
            )
            if AutoBuyLogState and AutoBuyLogState.AddActionCount then
                AutoBuyLogState.AddActionCount("GardenAutoUpgradeTree", 1, false)
            end
            if type(state.FailedByKey) ~= "table" then
                state.FailedByKey = {}
            end
            state.FailedByKey[key] = 0
            state.PendingUpgrade = nil
            return true, false
        end

        local now = os.clock()
        local since = tonumber(pending.Since) or now
        local timeout = tonumber(pending.Timeout) or 1.25
        if (now - since) < timeout then
            return false, true
        end

        state.PendingUpgrade = nil
        if type(state.FailedByKey) ~= "table" then
            state.FailedByKey = {}
        end
        local failed = tonumber(state.FailedByKey[key]) or 0
        failed += 1
        state.FailedByKey[key] = failed
        return false, false
    end

    local function gardenTreeBuildCurrencyText()
        local gardenPoints = gardenTreeGetCurrencyAmount("Garden Points")
        local grass = gardenTreeGetCurrencyAmount("Grass")
        local parts = {}
        if type(gardenPoints) == "number" then
            parts[#parts + 1] = "Garden Points " .. tostring(autoBuyLogFormatNumber(gardenPoints))
        end
        if type(grass) == "number" then
            parts[#parts + 1] = "Grass " .. tostring(autoBuyLogFormatNumber(grass))
        end
        if #parts == 0 then
            return "-"
        end
        return table.concat(parts, " | ")
    end

    local function gardenTreeAutoUpgradeStep()
        local state = State.GardenAutoUpgradeTree
        if not state or not state.Enabled then
            return false
        end
        if type(state.FailedByKey) ~= "table" then
            state.FailedByKey = {}
        end

        local _, pendingWaiting = gardenTreeProcessPendingUpgrade(state)

        local moduleData = gardenTreeGetModule()
        local items = moduleData and moduleData.Items or nil
        if type(items) ~= "table" or #items == 0 then
            gardenTreeBuildLogUpdate({
                LastUpgrade = state.LastUpgradeDisplay or "-",
                LastCheck = state.LastCheckDisplay or "-",
                Locked = 0,
                Unlocked = 0,
                TotalItem = 0,
                TotalMax = 0,
                CurrencyText = gardenTreeBuildCurrencyText()
            }, true)
            return false
        end

        local locked = 0
        local unlocked = 0
        local totalMax = 0
        local totalItem = #items
        local target = nil
        local firstCheckCandidate = nil

        for _, item in ipairs(items) do
            local amount = gardenTreeGetUpgradeAmount(item.Key)
            local maxLevel = gardenTreeGetLevelLimit(item.Key)
            local maxLabel = type(maxLevel) == "number" and tostring(maxLevel) or "?"
            local isUnlocked = gardenTreeIsUnlocked(item.Key)
            if isUnlocked then
                unlocked += 1
            else
                locked += 1
            end

            local cost = gardenTreeReadCostFromUpgradeNode(item.RuntimeNode)
            local isMaxed = type(maxLevel) == "number" and amount >= maxLevel
            if isMaxed then
                totalMax += 1
            end

            if not firstCheckCandidate and isUnlocked and not isMaxed then
                firstCheckCandidate = {
                    Item = item,
                    Amount = amount,
                    MaxLevel = maxLevel,
                    MaxLabel = maxLabel,
                    Cost = cost
                }
            end

            if (not pendingWaiting) and (not target) and isUnlocked and (not isMaxed) and type(cost) == "number" and cost > 0 then
                local ownCurrency = gardenTreeGetCurrencyAmount(item.UpgradeCurrency)
                if type(ownCurrency) == "number" and ownCurrency >= cost then
                    target = {
                        Item = item,
                        Amount = amount,
                        Cost = cost,
                        MaxLevel = maxLevel,
                        MaxLabel = maxLabel
                    }
                end
            end
        end

        if target and target.Item then
            state.LastCheckDisplay = gardenTreeFormatProgressDisplay(
                target.Item,
                target.Amount,
                target.MaxLevel,
                target.MaxLabel,
                target.Cost
            )
        elseif type(firstCheckCandidate) == "table" and firstCheckCandidate.Item then
            state.LastCheckDisplay = gardenTreeFormatProgressDisplay(
                firstCheckCandidate.Item,
                firstCheckCandidate.Amount,
                firstCheckCandidate.MaxLevel,
                firstCheckCandidate.MaxLabel,
                firstCheckCandidate.Cost
            )
        else
            state.LastCheckDisplay = "-"
        end

        gardenTreeBuildLogUpdate({
            LastUpgrade = state.LastUpgradeDisplay or "-",
            LastCheck = state.LastCheckDisplay or "-",
            Locked = locked,
            Unlocked = unlocked,
            TotalItem = totalItem,
            TotalMax = totalMax,
            CurrencyText = gardenTreeBuildCurrencyText()
        }, true)

        if not target then
            return false
        end

        local remoteArg = gardenTreeResolveRemoteArgument(target.Item.Key)
        if type(remoteArg) ~= "string" or #remoteArg == 0 then
            return false
        end

        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            pcall(function()
                remote = game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
            end)
        end
        if not remote then
            return false
        end

        local okFire = pcall(function()
            remote:FireServer("UpgradeTree", remoteArg)
        end)
        if okFire then
            state.PendingUpgrade = {
                Key = tostring(target.Item.Key or ""),
                DisplayName = tostring(target.Item.DisplayName or target.Item.Key or remoteArg),
                AmountBefore = tonumber(target.Amount) or 0,
                MaxLevel = tonumber(target.MaxLevel),
                MaxLabel = target.MaxLabel,
                Cost = tonumber(target.Cost),
                Since = os.clock(),
                Timeout = 1.25
            }
        end
        return okFire == true
    end

    local function setGardenAutoUpgradeEnabled(enabled)
        local state = State.GardenAutoUpgradeTree
        if not state then
            return
        end
        state.Enabled = enabled == true
        Config.GardenAutoUpgradeTreeEnabled = state.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive("GardenAutoUpgradeTree", "Auto Upgrade Garden Tree", state.Enabled)
        end

        if state.Enabled then
            state.LastCheckDisplay = "-"
            state.PendingUpgrade = nil
            state.FailedByKey = state.FailedByKey or {}
            autoBuySchedulerRegister("GardenAutoUpgradeTree", {
                Step = gardenTreeAutoUpgradeStep
            })
            gardenTreeAutoUpgradeStep()
        else
            state.LastCheckDisplay = "-"
            state.PendingUpgrade = nil
            autoBuySchedulerUnregister("GardenAutoUpgradeTree")
            gardenTreeBuildLogUpdate({
                LastUpgrade = "-",
                LastCheck = "-",
                Locked = 0,
                Unlocked = 0,
                TotalItem = 0,
                TotalMax = 0,
                CurrencyText = "-"
            }, true)
        end
    end

    if State.CleanupRegistry and State.CleanupRegistry.Register then
        State.CleanupRegistry.Register(function()
            autoBuySchedulerUnregister("GardenAutoUpgradeTree")
        end)
    end

    createToggle(upgradeTreeSection, "Auto Upgrade Garden Tree", nil, State.GardenAutoUpgradeTree.Enabled, function(v)
        setGardenAutoUpgradeEnabled(v == true)
    end)
    setGardenAutoUpgradeEnabled(State.GardenAutoUpgradeTree.Enabled == true)

    State.GardenAutoClickFallTree = State.GardenAutoClickFallTree or {
        Enabled = false,
        TargetPosition = Vector3.new(6544.02783203125, 202.42156982421875, 5849.58837890625),
        ClickScreenX = 1198,
        ClickScreenY = 341,
        LockData = makeData(
            Vector3.new(6532.746, 198.317, 5847.479),
            CFrame.new(6522.973145, 208.975403, 5863.204590, 0.849340975, 0.234030262, -0.473127633, 0.000000000, 0.896338880, 0.443369627, 0.527844608, -0.376571983, 0.761297345),
            CFrame.new(6532.746094, 199.817047, 5847.479004, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            20.656235
        ),
        LockOwnerKey = "GardenAutoClickFallTree",
        LockActive = false,
        LockConn = nil,
        LockMode = "Soft",
        LockTickInterval = 0.10,
        LockCameraTickInterval = 0.18,
        LockCharacterThreshold = 0.35,
        LockCameraThreshold = 0.60,
        LockFocusThreshold = 0.80,
        LockAngleThresholdDeg = 1.50,
        LastLockTickAt = 0,
        LastCameraLockAt = 0,
        SavedPivot = nil,
        SavedCamera = nil,
        ClickDetector = nil,
        LastDetectorResolveAt = 0,
        DetectorResolveInterval = 4.00,
        LastCooldownValue = nil,
        LastClickAt = 0,
        ClickInterval = 0.20,
        PendingConfirm = false,
        PendingSince = 0,
        ConfirmTimeout = 1.10,
        LastManualInputAt = 0,
        LastHoverAt = 0,
        LastManualScreenX = nil,
        LastManualScreenY = nil,
        LastManualScreenAt = 0,
        ManualScreenGrace = 8.0,
        LastClickMethod = "",
        ManualInputGrace = 0.45,
        ManualHoverGrace = 0
    }

    local fallTreeState = State.GardenAutoClickFallTree
    local schedulerKey = "GardenAutoClickFallTree"

    local function setFallTreeActionLog(enabled)
        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive("GardenAutoClickFallTree", "Auto Click Fall Tree", enabled == true)
        end
    end

    local function getFallTreeCooldownValue()
        if not LP then
            return nil
        end
        local treeFolder = LP:FindFirstChild("Garden Tree")
        if not treeFolder then
            return nil
        end
        local cooldownFolder = treeFolder:FindFirstChild("Cooldown")
        if not cooldownFolder then
            return nil
        end
        local node = cooldownFolder:FindFirstChild("2")
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        return tonumber(raw)
    end

    local function getFallTreeCurrentPivot()
        if not LP or not LP.Character then
            return nil
        end
        local ok, pivot = pcall(function()
            return LP.Character:GetPivot()
        end)
        if ok and pivot then
            return pivot
        end
        local hrp = LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            return hrp.CFrame
        end
        return nil
    end

    local function captureFallTreeCameraState()
        local cam = workspace.CurrentCamera
        if not cam or not LP then
            return nil
        end
        return {
            Type = cam.CameraType,
            Subject = cam.CameraSubject,
            CFrame = cam.CFrame,
            Focus = cam.Focus,
            FOV = cam.FieldOfView,
            MinZoom = LP.CameraMinZoomDistance,
            MaxZoom = LP.CameraMaxZoomDistance,
            CameraMode = LP.CameraMode
        }
    end

    local function applyFallTreeLockPose(forceCharacter, forceCamera)
        local lockData = fallTreeState.LockData
        if not lockData then
            return false
        end
        if not LP or not LP.Character then
            return false
        end
        local cam = workspace.CurrentCamera
        if not cam then
            return false
        end

        if not fallTreeState.SavedPivot then
            fallTreeState.SavedPivot = getFallTreeCurrentPivot()
        end
        if not fallTreeState.SavedCamera then
            fallTreeState.SavedCamera = captureFallTreeCameraState()
        end

        local didApply = false
        local targetPos = lockData.position
        local currentPivot = getFallTreeCurrentPivot()
        local characterThreshold = tonumber(fallTreeState.LockCharacterThreshold) or 0.35
        if forceCharacter == true or not currentPivot or (currentPivot.Position - targetPos).Magnitude > characterThreshold then
            local okPivot = pcall(function()
                LP.Character:PivotTo(CFrame.new(targetPos))
            end)
            if okPivot == true then
                didApply = true
            end
        end

        local zoom = tonumber(lockData.camera and lockData.camera.zoom) or 20.656235
        local fov = tonumber(lockData.camera and lockData.camera.fov) or 70
        local targetCFrame = lockData.camera and lockData.camera.cframe
        local targetFocus = lockData.camera and lockData.camera.focus
        local mode = string.lower(tostring(fallTreeState.LockMode or "Soft"))
        local softMode = mode ~= "hard"
        local now = os.clock()
        local shouldApplyCamera = forceCamera == true
        if not shouldApplyCamera then
            if (not softMode) or (now - (tonumber(fallTreeState.LastCameraLockAt) or 0) >= (tonumber(fallTreeState.LockCameraTickInterval) or 0.18)) then
                local cameraThreshold = tonumber(fallTreeState.LockCameraThreshold) or 0.60
                local focusThreshold = tonumber(fallTreeState.LockFocusThreshold) or 0.80
                local angleThresholdDeg = tonumber(fallTreeState.LockAngleThresholdDeg) or 1.50
                if cam.CameraType ~= Enum.CameraType.Scriptable then
                    shouldApplyCamera = true
                elseif math.abs((cam.FieldOfView or fov) - fov) > 0.05 then
                    shouldApplyCamera = true
                elseif typeof(targetCFrame) == "CFrame" and (cam.CFrame.Position - targetCFrame.Position).Magnitude > cameraThreshold then
                    shouldApplyCamera = true
                elseif typeof(targetFocus) == "CFrame" and (cam.Focus.Position - targetFocus.Position).Magnitude > focusThreshold then
                    shouldApplyCamera = true
                elseif typeof(targetCFrame) == "CFrame" then
                    local dot = cam.CFrame.LookVector:Dot(targetCFrame.LookVector)
                    dot = math.clamp(dot, -1, 1)
                    local angle = math.deg(math.acos(dot))
                    if angle > angleThresholdDeg then
                        shouldApplyCamera = true
                    end
                end
                if math.abs((tonumber(LP.CameraMinZoomDistance) or zoom) - zoom) > 0.05 then
                    shouldApplyCamera = true
                end
                if math.abs((tonumber(LP.CameraMaxZoomDistance) or zoom) - zoom) > 0.05 then
                    shouldApplyCamera = true
                end
            end
        end

        if shouldApplyCamera then
            local okCam = pcall(function()
                cam.CameraType = Enum.CameraType.Scriptable
                if typeof(targetCFrame) == "CFrame" then
                    cam.CFrame = targetCFrame
                end
                if typeof(targetFocus) == "CFrame" then
                    cam.Focus = targetFocus
                end
                cam.FieldOfView = fov
                LP.CameraMinZoomDistance = zoom
                LP.CameraMaxZoomDistance = zoom
            end)
            if okCam == true then
                didApply = true
                fallTreeState.LastCameraLockAt = now
            end
        end

        return didApply
    end

    local function releaseFallTreeLock()
        if fallTreeState.LockConn then
            fallTreeState.LockConn:Disconnect()
            fallTreeState.LockConn = nil
        end
        fallTreeState.LockActive = false

        if LP and LP.Character and fallTreeState.SavedPivot then
            pcall(function()
                LP.Character:PivotTo(fallTreeState.SavedPivot)
            end)
        end

        local cam = workspace.CurrentCamera
        local savedCam = fallTreeState.SavedCamera
        if cam and savedCam then
            pcall(function()
                cam.CFrame = savedCam.CFrame or cam.CFrame
                cam.Focus = savedCam.Focus or cam.Focus
                cam.FieldOfView = savedCam.FOV or cam.FieldOfView
                cam.CameraSubject = savedCam.Subject or cam.CameraSubject
                cam.CameraType = savedCam.Type or cam.CameraType
            end)
            pcall(function()
                LP.CameraMinZoomDistance = savedCam.MinZoom or LP.CameraMinZoomDistance
                LP.CameraMaxZoomDistance = savedCam.MaxZoom or LP.CameraMaxZoomDistance
                LP.CameraMode = savedCam.CameraMode or LP.CameraMode
            end)
        end

        fallTreeState.SavedPivot = nil
        fallTreeState.SavedCamera = nil
        fallTreeState.LastLockTickAt = 0
        fallTreeState.LastCameraLockAt = 0

        if State.AutomationTeleport and State.AutomationTeleport.Release then
            State.AutomationTeleport.Release(fallTreeState.LockOwnerKey)
        end
    end

    local function ensureFallTreeLock()
        if fallTreeState.LockActive and fallTreeState.LockConn then
            return true
        end
        if State.AutomationTeleport and State.AutomationTeleport.TryAcquire and not State.AutomationTeleport.TryAcquire(fallTreeState.LockOwnerKey) then
            return false
        end

        fallTreeState.LockActive = true
        applyFallTreeLockPose(true, true)
        fallTreeState.LastLockTickAt = os.clock()
        fallTreeState.LockConn = RunService.Heartbeat:Connect(function()
            if not fallTreeState.Enabled then
                return
            end
            local now = os.clock()
            local lockInterval = tonumber(fallTreeState.LockTickInterval) or 0.10
            if now - (tonumber(fallTreeState.LastLockTickAt) or 0) < lockInterval then
                return
            end
            fallTreeState.LastLockTickAt = now
            local mode = string.lower(tostring(fallTreeState.LockMode or "Soft"))
            local hardMode = mode == "hard"
            applyFallTreeLockPose(false, hardMode)
        end)
        trackConnection(fallTreeState.LockConn)
        return true
    end

    local function isFallTreeReadyNow()
        local now = os.clock()
        local minGap = tonumber(fallTreeState.ClickInterval) or 0.20
        if now - (tonumber(fallTreeState.LastClickAt) or 0) < minGap then
            return false
        end
        if fallTreeState.PendingConfirm then
            return false
        end
        local value = getFallTreeCooldownValue()
        if type(value) == "number" then
            fallTreeState.LastCooldownValue = value
            return math.abs(value) <= 1e-6
        end
        return false
    end

    local function consumeFallTreeClickConfirm(now)
        if not fallTreeState.PendingConfirm then
            local value = getFallTreeCooldownValue()
            if type(value) == "number" then
                fallTreeState.LastCooldownValue = value
            end
            return false
        end

        local value = getFallTreeCooldownValue()
        if type(value) == "number" then
            fallTreeState.LastCooldownValue = value
            if value > 1e-6 then
                fallTreeState.PendingConfirm = false
                fallTreeState.PendingSince = 0
                return true
            end
        end

        local timeout = tonumber(fallTreeState.ConfirmTimeout) or 1.10
        if now - (tonumber(fallTreeState.PendingSince) or now) >= timeout then
            fallTreeState.PendingConfirm = false
            fallTreeState.PendingSince = 0
        end
        return false
    end

    local function isMouseNearFallTree(maxDistance)
        if not Mouse or not Mouse.Target then
            return false
        end
        local target = Mouse.Target
        if not target:IsA("BasePart") then
            return false
        end
        local targetPos = fallTreeState.TargetPosition
        local dist = (target.Position - targetPos).Magnitude
        if dist <= (maxDistance or 18) then
            return true
        end
        local lowerPath = string.lower(target:GetFullName())
        return string.find(lowerPath, "fall", 1, true) ~= nil
            and string.find(lowerPath, "tree", 1, true) ~= nil
    end

    local function isFallTreeManualBusy()
        local now = os.clock()
        local inputGrace = tonumber(fallTreeState.ManualInputGrace) or 0.45
        local hoverGrace = tonumber(fallTreeState.ManualHoverGrace) or 0
        if now - (tonumber(fallTreeState.LastManualInputAt) or 0) <= inputGrace then
            return true
        end
        if hoverGrace > 0 and now - (tonumber(fallTreeState.LastHoverAt) or 0) <= hoverGrace then
            return true
        end
        return false
    end

    local function resolveFallTreeClickDetector()
        local now = os.clock()
        local refreshAfter = tonumber(fallTreeState.DetectorResolveInterval) or 4.0
        local cached = fallTreeState.ClickDetector
        if cached and cached.Parent and (now - (tonumber(fallTreeState.LastDetectorResolveAt) or 0) <= refreshAfter) then
            return cached
        end

        local targetPos = fallTreeState.TargetPosition
        local bestDetector = nil
        local bestDistance = math.huge
        local bestScore = -math.huge
        local function scoreDetector(detector, part)
            if not detector or not part then
                return -math.huge
            end
            local dist = (part.Position - targetPos).Magnitude
            if dist > 35 then
                return -math.huge
            end
            local fullName = string.lower(part:GetFullName() .. " " .. detector:GetFullName())
            local score = 0
            if string.find(fullName, "fall tree", 1, true) then
                score += 240
            end
            if string.find(fullName, "garden tree", 1, true) then
                score += 220
            end
            if string.find(fullName, "fall", 1, true) then
                score += 55
            end
            if string.find(fullName, "tree", 1, true) then
                score += 45
            end
            if string.find(fullName, "leaf", 1, true) then
                score += 18
            end
            if string.find(fullName, "click", 1, true) then
                score += 6
            end
            score += math.max(0, 35 - dist)
            return score
        end

        local okBounds, parts = pcall(function()
            return workspace:GetPartBoundsInRadius(targetPos, 30)
        end)
        if okBounds and type(parts) == "table" then
            for _, part in ipairs(parts) do
                if part and part:IsA("BasePart") then
                    local detector = part:FindFirstChildOfClass("ClickDetector")
                    if detector then
                        local dist = (part.Position - targetPos).Magnitude
                        local score = scoreDetector(detector, part)
                        if score > bestScore or (score == bestScore and dist < bestDistance) then
                            bestScore = score
                            bestDistance = dist
                            bestDetector = detector
                        end
                    end
                end
            end
        end

        if not bestDetector then
            local okDesc, descendants = pcall(function()
                return workspace:GetDescendants()
            end)
            if okDesc and type(descendants) == "table" then
                for _, inst in ipairs(descendants) do
                    if inst and inst:IsA("ClickDetector") then
                        local parent = inst.Parent
                        if parent and parent:IsA("BasePart") then
                            local dist = (parent.Position - targetPos).Magnitude
                            local score = scoreDetector(inst, parent)
                            if score > bestScore or (score == bestScore and dist < bestDistance) then
                                bestScore = score
                                bestDistance = dist
                                bestDetector = inst
                            end
                        end
                    end
                end
            end
        end

        fallTreeState.ClickDetector = bestDetector
        fallTreeState.LastDetectorResolveAt = now
        return bestDetector
    end

    local function getFallTreeScreenPoint()
        local x = math.floor((tonumber(fallTreeState.ClickScreenX) or 1198) + 0.5)
        local y = math.floor((tonumber(fallTreeState.ClickScreenY) or 341) + 0.5)
        return x, y
    end

    local function clickFallTreeWithVirtualInput()
        local sx, sy = getFallTreeScreenPoint()
        if not sx or not sy then
            return false
        end
        if not (VirtualInputManager and VirtualInputManager.SendMouseButtonEvent) then
            return false
        end

        local okDown = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(sx, sy, 0, true, game, 0)
        end)
        local okUp = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(sx, sy, 0, false, game, 0)
        end)
        if okDown and okUp then
            fallTreeState.LastClickMethod = "screen_lock_click"
            return true
        end
        return false
    end

    local function clickFallTreeWorldPoint()
        if clickFallTreeWithVirtualInput() then
            return true
        end
        local detector = resolveFallTreeClickDetector()
        if detector and fireclickdetector then
            local okFire = false
            okFire = pcall(function()
                fireclickdetector(detector)
            end) or okFire
            okFire = pcall(function()
                fireclickdetector(detector, 0)
            end) or okFire
            okFire = pcall(function()
                fireclickdetector(detector, 1)
            end) or okFire
            if okFire == true then
                fallTreeState.LastClickMethod = "click_detector"
                return true
            end
        end
        if mouse1click then
            local ok = pcall(mouse1click)
            if ok then
                fallTreeState.LastClickMethod = "mouse1click"
                return true
            end
        end
        return false
    end

    trackConnection(UIS.InputChanged:Connect(function(input)
        if not fallTreeState.Enabled then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        if isMouseNearFallTree(18) then
            fallTreeState.LastHoverAt = os.clock()
        end
    end))

    trackConnection(UIS.InputBegan:Connect(function(input, gameProcessed)
        if not fallTreeState.Enabled or gameProcessed then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        if isMouseNearFallTree(22) then
            fallTreeState.LastManualInputAt = os.clock()
            local pos = input.Position
            if pos then
                fallTreeState.LastManualScreenX = math.floor((tonumber(pos.X) or 0) + 0.5)
                fallTreeState.LastManualScreenY = math.floor((tonumber(pos.Y) or 0) + 0.5)
                fallTreeState.LastManualScreenAt = os.clock()
            end
        end
    end))

    local function setFallTreeEnabled(enabled)
        local v = enabled == true
        if fallTreeState.Enabled == v then
            if v then
                ensureFallTreeLock()
            else
                releaseFallTreeLock()
            end
            setFallTreeActionLog(v)
            return
        end
        fallTreeState.Enabled = v
        fallTreeState.LastCooldownValue = nil
        fallTreeState.LastClickAt = 0
        fallTreeState.PendingConfirm = false
        fallTreeState.PendingSince = 0
        fallTreeState.ClickDetector = nil
        fallTreeState.LastDetectorResolveAt = 0
        fallTreeState.LastManualScreenX = nil
        fallTreeState.LastManualScreenY = nil
        fallTreeState.LastManualScreenAt = 0
        fallTreeState.LastClickMethod = ""
        fallTreeState.LastLockTickAt = 0
        fallTreeState.LastCameraLockAt = 0
        Config.GardenAutoClickFallTreeEnabled = v
        saveConfig()
        setFallTreeActionLog(v)

        if v then
            ensureFallTreeLock()
            autoBuySchedulerRegister(schedulerKey, {
                Step = function()
                    if not fallTreeState.Enabled then
                        return false
                    end
                    if not ensureFallTreeLock() then
                        return false
                    end
                    local now = os.clock()
                    if consumeFallTreeClickConfirm(now) then
                        if AutoBuyLogState and AutoBuyLogState.AddActionCount then
                            AutoBuyLogState.AddActionCount("GardenAutoClickFallTree", 1)
                        end
                        return true
                    end
                    if not isFallTreeReadyNow() then
                        return false
                    end
                    local clicked = clickFallTreeWorldPoint()
                    if clicked then
                        fallTreeState.LastClickAt = now
                        fallTreeState.PendingConfirm = true
                        fallTreeState.PendingSince = now
                    end
                    return clicked == true
                end
            })
        else
            autoBuySchedulerUnregister(schedulerKey)
            releaseFallTreeLock()
        end
    end

    if State.CleanupRegistry and State.CleanupRegistry.Register then
        State.CleanupRegistry.Register(function()
            releaseFallTreeLock()
        end)
    end

    createToggle(
        GardenAutomationSection,
        "Auto Click Fall Tree",
        nil,
        Config.GardenAutoClickFallTreeEnabled == true,
        function(v)
            setFallTreeEnabled(v == true)
        end
    )
    setFallTreeEnabled(Config.GardenAutoClickFallTreeEnabled == true)
end

State.InitHell = function()
    local tab = State.Tabs.Hell
    local HellAutomationSection = createSectionBox(tab:GetPage(), "Automation")

    setupAutoBuyGroup(HellAutomationSection, {
        GroupKey = "Hell World",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Mode: Upgrade All",
        SpeedLabel = "Click Speed (sec)",
        CooldownKey = "HellAutoBuy",
        DefaultCooldown = 0.6,
        ResetMaxedOnPrompt = {
            Match = "Successfully Reached Hell Rank",
            ShopKey = {"Madness", "Hell XP"}
        },
        ResetMaxedOnPopup = {
            Match = "SinsGain",
            ShopKey = {"Madness", "Hell XP"}
        },
        Shops = {
            {
                Key = "Madness",
                DisplayName = "Madness Shop",
                ShopName = "Madness",
            },
            {
                Key = "Hell XP",
                DisplayName = "Hell XP Shop",
                ShopName = "Hell XP",
            },
            {
                Key = "Sins",
                DisplayName = "Sins Shop",
                ShopName = "Sins",
            }
        }
    })

    local hellDropperSection = createSubSectionBox(HellAutomationSection, "Auto Dropper")
    Config.HellAutoDropperEnabled = Config.HellAutoDropperEnabled == true

    State.HellAutoDropper = State.HellAutoDropper or {
        Enabled = Config.HellAutoDropperEnabled == true,
        Index = 1,
        OwnerKey = "HellAutoDropper",
        SavedPivot = nil,
        HasSavedPivot = false,
        SpecsCache = nil,
        Wait = {
            Active = false,
            DropperKey = nil,
            BeforeLevel = nil,
            Since = 0,
            Timeout = 2.2
        }
    }

    local hellDropperEntries = {
        {Label = "One", Key = "Dropper1", Index = 1},
        {Label = "Two", Key = "Dropper2", Index = 2},
        {Label = "Three", Key = "Dropper3", Index = 3},
        {Label = "Four", Key = "Dropper4", Index = 4},
        {Label = "Five", Key = "Dropper5", Index = 5},
        {Label = "Six", Key = "Dropper6", Index = 6},
        {Label = "Seven", Key = "Dropper7", Index = 7},
        {Label = "Eight", Key = "Dropper8", Index = 8},
        {Label = "Nine", Key = "Dropper9", Index = 9},
        {Label = "Ten", Key = "Dropper10", Index = 10}
    }

    local hellDropperFallbackDefs = {
        Dropper1 = {MaxLevel = 100, Cost = function(level) return 0 + level * 40000000 * 1.3 ^ level end},
        Dropper2 = {MaxLevel = 100, Cost = function(level) return 50000000000 + level * 10000000000 * 1.325 ^ level end},
        Dropper3 = {MaxLevel = 100, Cost = function(level) return 100000000000000 + level * 100000000000000 * 1.35 ^ level end},
        Dropper4 = {MaxLevel = 100, Cost = function(level) return 150000000000000000 + level * 100000000000000000 * 1.375 ^ level end},
        Dropper5 = {MaxLevel = 100, Cost = function(level) return 5e22 + level * 3.5e22 * 1.4 ^ level end},
        Dropper6 = {MaxLevel = 100, Cost = function(level) return 1e30 + level * 1e30 * 1.44 ^ level end},
        Dropper7 = {MaxLevel = 100, Cost = function(level) return 5e36 + level * 5e36 * 1.5 ^ level end},
        Dropper8 = {MaxLevel = 100, Cost = function(level) return 5e44 + level * 5e44 * 1.57 ^ level end},
        Dropper9 = {MaxLevel = 100, Cost = function(level) return 1e50 + level * 1e50 * 1.64 ^ level end},
        Dropper10 = {MaxLevel = 100, Cost = function(level) return 5e54 + level * 5e54 * 1.73 ^ level end}
    }

    local function parseCompactNumber(raw)
        local n = tonumber(raw)
        if type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge then
            return n
        end
        if type(raw) ~= "string" then
            return nil
        end

        local text = raw:lower():gsub("%s+", ""):gsub(",", ".")
        local direct = tonumber(text)
        if type(direct) == "number" and direct == direct then
            return direct
        end

        local suffixScale = {
            k = 1e3,
            m = 1e6,
            b = 1e9,
            t = 1e12
        }

        local mantissaText, expText, expSuffix = text:match("^([%+%-]?%d*%.?%d+)[eE]([%+%-]?%d*%.?%d+)([kmbt]?)$")
        if mantissaText and expText then
            local mantissa = tonumber(mantissaText)
            local exponent = tonumber(expText)
            local expMul = suffixScale[expSuffix] or 1
            if type(mantissa) == "number" and type(exponent) == "number" then
                local finalExp = exponent * expMul
                if finalExp > 308 then
                    return math.huge
                end
                if finalExp < -324 then
                    return 0
                end
                local ok, value = pcall(function()
                    return mantissa * (10 ^ finalExp)
                end)
                if ok and type(value) == "number" and value == value then
                    return value
                end
            end
        end

        local numText, suffix = text:match("^([%+%-]?%d*%.?%d+)([kmbt])$")
        if numText and suffix then
            local base = tonumber(numText)
            local mul = suffixScale[suffix]
            if type(base) == "number" and type(mul) == "number" then
                return base * mul
            end
        end
        return nil
    end

    local function readNumberValue(node)
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        return parseCompactNumber(raw)
    end

    local function getHellEmberAmount()
        if not LP then
            return nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        local ember = currencyRoot and currencyRoot:FindFirstChild("Ember")
        local amountRoot = ember and ember:FindFirstChild("Amount")
        local amountNode = amountRoot and (amountRoot:FindFirstChild("1") or amountRoot:FindFirstChildWhichIsA("ValueBase"))
        return readNumberValue(amountNode)
    end

    local function getHellDropperLevel(dropperKey)
        if not LP or type(dropperKey) ~= "string" then
            return nil
        end
        local dropperRoot = LP:FindFirstChild("DROPPERS")
        local dropper = dropperRoot and dropperRoot:FindFirstChild(dropperKey)
        local levelNode = dropper and dropper:FindFirstChild("Level")
        local levelNum = readNumberValue(levelNode)
        if type(levelNum) == "number" then
            return math.max(0, math.floor(levelNum + 0.5))
        end
        return nil
    end

    local function getHellDropperSpecs()
        local state = State.HellAutoDropper
        if state and type(state.SpecsCache) == "table" and #state.SpecsCache > 0 then
            return state.SpecsCache
        end

        local dropperDefs = nil
        local moduleScript = nil
        pcall(function()
            moduleScript = game:GetService("ReplicatedStorage").Shared.Modules["Hell World"].Droppers
        end)
        if moduleScript then
            local okModule, dropperModule = pcall(require, moduleScript)
            if okModule and type(dropperModule) == "table" and type(dropperModule.Droppers) == "table" then
                dropperDefs = dropperModule.Droppers
            end
        end

        local out = {}
        for _, entry in ipairs(hellDropperEntries) do
            local key = entry.Key
            local def = dropperDefs and dropperDefs[key] or nil
            if type(def) ~= "table" then
                def = hellDropperFallbackDefs[key]
            end
            local tpData = State.HellTeleports and State.HellTeleports.Dropper and State.HellTeleports.Dropper[entry.Label] or nil
            if type(def) == "table" and type(def.Cost) == "function" and tpData then
                out[#out + 1] = {
                    Label = entry.Label,
                    Key = key,
                    Index = entry.Index,
                    MaxLevel = tonumber(def.MaxLevel) or 100,
                    CostFn = def.Cost,
                    Data = tpData
                }
            end
        end

        if state then
            state.SpecsCache = out
        end
        return out
    end

    local function updateHellAutoDropperLog(meta, forceRefresh)
        if not AutoBuyLogState then
            return
        end
        local actionKey = "HellAutoDropper"
        local data = AutoBuyLogState.ActionData[actionKey] or {
            Key = actionKey,
            Name = "Auto Dropper",
            Success = 0
        }
        data.Key = actionKey
        data.Name = "Auto Dropper"
        data.Success = tonumber(data.Success) or 0
        if type(meta) == "table" then
            data.Ember = meta.Ember
            data.Items = type(meta.Items) == "table" and meta.Items or {}
            data.ActiveKey = meta.ActiveKey
        else
            data.Ember = nil
            data.Items = {}
            data.ActiveKey = nil
        end
        AutoBuyLogState.ActionData[actionKey] = data
        if AutoBuyLogState.ActiveActions[actionKey] then
            AutoBuyLogState.ActiveActions[actionKey] = data
            if forceRefresh ~= false then
                updateAutoBuyLogUI()
            end
        end
    end

    local function saveHellDropperPivot()
        local state = State.HellAutoDropper
        if not state or state.HasSavedPivot then
            return
        end
        if not (LP and LP.Character) then
            return
        end
        local ok, pivot = pcall(function()
            return LP.Character:GetPivot()
        end)
        if ok and pivot then
            state.SavedPivot = pivot
            state.HasSavedPivot = true
        end
    end

    local function restoreHellDropperPivot()
        local state = State.HellAutoDropper
        if not state then
            return
        end
        local pivot = state.SavedPivot
        state.SavedPivot = nil
        state.HasSavedPivot = false
        if pivot and LP and LP.Character then
            pcall(function()
                LP.Character:PivotTo(pivot)
            end)
        end
    end

    local function findNextAffordableDropper()
        local state = State.HellAutoDropper
        if not state then
            return nil, nil, nil
        end
        local specs = getHellDropperSpecs()
        local total = #specs
        if total == 0 then
            return nil, nil, {
                Ember = getHellEmberAmount(),
                Items = {},
                ActiveKey = nil
            }
        end

        local emberAmount = getHellEmberAmount()
        local emberZero = type(emberAmount) == "number" and emberAmount <= 0

        local idx = tonumber(state.Index) or 1
        if idx < 1 or idx > total then
            idx = 1
        end

        local items = {}
        local target = nil
        local levelBefore = nil
        local selectedNextIdx = nil
        local scanIdx = idx

        for _ = 1, total do
            local spec = specs[scanIdx]
            local currentIdx = scanIdx
            scanIdx += 1
            if scanIdx > total then
                scanIdx = 1
            end
            if spec and spec.Data and type(spec.CostFn) == "function" then
                local level = getHellDropperLevel(spec.Key)
                local maxLevel = tonumber(spec.MaxLevel) or 100
                local maxed = type(level) == "number" and level >= maxLevel
                local cost = nil
                local affordable = false
                if type(level) == "number" and not maxed then
                    local nextLevel = math.max(1, level + 1)
                    local okCost, nextCost = pcall(spec.CostFn, nextLevel)
                    if okCost and type(nextCost) == "number" and nextCost > 0 then
                        cost = nextCost
                        affordable = type(emberAmount) == "number" and emberAmount >= cost
                        if not target and affordable then
                            target = spec
                            levelBefore = level
                            selectedNextIdx = scanIdx
                        end
                    end
                end
                if not target and emberZero and tostring(spec.Key) == "Dropper1" and not maxed then
                    target = spec
                    levelBefore = (type(level) == "number" and level) or 0
                    selectedNextIdx = scanIdx
                end
                items[#items + 1] = {
                    Key = spec.Key,
                    Index = spec.Index,
                    Name = "Dropper " .. tostring(spec.Index or currentIdx),
                    Label = spec.Label,
                    Level = level,
                    MaxLevel = maxLevel,
                    Cost = cost,
                    Affordable = affordable,
                    Maxed = maxed
                }
            end
        end

        state.Index = selectedNextIdx or scanIdx
        return target, levelBefore, {
            Ember = emberAmount,
            Items = items,
            ActiveKey = target and target.Key or nil
        }
    end

    local function hellAutoDropperStep()
        local state = State.HellAutoDropper
        if not state or not state.Enabled then
            return false
        end
        local waitState = state.Wait
        if waitState and waitState.Active and type(waitState.DropperKey) == "string" then
            local currentLevel = getHellDropperLevel(waitState.DropperKey)
            if type(currentLevel) == "number" and type(waitState.BeforeLevel) == "number" and currentLevel > waitState.BeforeLevel then
                waitState.Active = false
                waitState.DropperKey = nil
                waitState.BeforeLevel = nil
                if AutoBuyLogState and AutoBuyLogState.AddActionCount then
                    AutoBuyLogState.AddActionCount("HellAutoDropper", 1, false)
                end
            elseif (os.clock() - (waitState.Since or 0)) < (waitState.Timeout or 2.2) then
                return false
            else
                waitState.Active = false
                waitState.DropperKey = nil
                waitState.BeforeLevel = nil
            end
        end
        if State.AutomationTeleport and State.AutomationTeleport.IsBusy and State.AutomationTeleport.IsBusy(state.OwnerKey) then
            return false
        end

        local target, levelBefore, logMeta = findNextAffordableDropper()
        updateHellAutoDropperLog(logMeta, true)
        if not target then
            return false
        end

        if State.AutomationTeleport and State.AutomationTeleport.TryAcquire and not State.AutomationTeleport.TryAcquire(state.OwnerKey) then
            return false
        end

        saveHellDropperPivot()
        local position = target and target.Data and target.Data.position or nil
        local okTeleport = teleportToPositionOnly(position)
        if State.AutomationTeleport and State.AutomationTeleport.Release then
            State.AutomationTeleport.Release(state.OwnerKey)
        end
        if okTeleport and waitState then
            waitState.Active = true
            waitState.DropperKey = target.Key
            waitState.BeforeLevel = levelBefore
            waitState.Since = os.clock()
        end
        return okTeleport == true
    end

    local function setHellAutoDropperEnabled(enabled)
        local state = State.HellAutoDropper
        if not state then
            return
        end
        state.Enabled = enabled == true
        Config.HellAutoDropperEnabled = state.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive("HellAutoDropper", "Auto Dropper", state.Enabled)
        end

        if state.Enabled then
            state.Index = 1
            if state.Wait then
                state.Wait.Active = false
                state.Wait.DropperKey = nil
                state.Wait.BeforeLevel = nil
            end
            autoBuySchedulerRegister("HellAutoDropper", {
                Step = hellAutoDropperStep
            })
            local _, _, meta = findNextAffordableDropper()
            updateHellAutoDropperLog(meta, true)
        else
            autoBuySchedulerUnregister("HellAutoDropper")
            if state.Wait then
                state.Wait.Active = false
                state.Wait.DropperKey = nil
                state.Wait.BeforeLevel = nil
            end
            if State.AutomationTeleport and State.AutomationTeleport.Release then
                State.AutomationTeleport.Release(state.OwnerKey)
            end
            updateHellAutoDropperLog(nil, true)
            restoreHellDropperPivot()
        end
    end

    if State.CleanupRegistry and State.CleanupRegistry.Register then
        State.CleanupRegistry.Register(function()
            autoBuySchedulerUnregister("HellAutoDropper")
            if State.AutomationTeleport and State.AutomationTeleport.Release and State.HellAutoDropper then
                State.AutomationTeleport.Release(State.HellAutoDropper.OwnerKey)
            end
            restoreHellDropperPivot()
        end)
    end

    createToggle(hellDropperSection, "Auto Dropper", nil, State.HellAutoDropper.Enabled, function(v)
        setHellAutoDropperEnabled(v == true)
    end)
    setHellAutoDropperEnabled(State.HellAutoDropper.Enabled == true)

    local hellRankSection = createSubSectionBox(HellAutomationSection, "Auto Hell Ranks")
    Config.HellAutoRanksEnabled = Config.HellAutoRanksEnabled == true

    State.HellAutoRanks = State.HellAutoRanks or {
        Enabled = Config.HellAutoRanksEnabled == true,
        Cache = nil,
        OwnerKey = "HellAutoRanks"
    }

    local function getHellRankModule()
        local state = State.HellAutoRanks
        if state and type(state.Cache) == "table" and #state.Cache > 0 then
            return state.Cache
        end
        local moduleScript = nil
        pcall(function()
            moduleScript = game:GetService("ReplicatedStorage").Shared.Modules["Hell World"].HellRank
        end)
        if not moduleScript then
            return nil
        end
        local okModule, rankData = pcall(require, moduleScript)
        if not okModule or type(rankData) ~= "table" then
            return nil
        end
        if state then
            state.Cache = rankData
        end
        return rankData
    end

    local function getHellRankLevel()
        if not LP then
            return 0
        end
        local resets = LP:FindFirstChild("Resets")
        local rankNode = resets and resets:FindFirstChild("Hell Rank")
        local value = readNumberValue(rankNode)
        if type(value) == "number" then
            return math.max(0, math.floor(value + 0.5))
        end
        return 0
    end

    local function getCurrencyAmountByType(typeName)
        if not LP or type(typeName) ~= "string" or #typeName == 0 then
            return nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        if not currencyRoot then
            return nil
        end
        local currencyFolder = currencyRoot:FindFirstChild(typeName)
        if not currencyFolder then
            local target = string.lower(typeName)
            for _, child in ipairs(currencyRoot:GetChildren()) do
                if string.lower(tostring(child.Name)) == target then
                    currencyFolder = child
                    break
                end
            end
        end
        if not currencyFolder then
            return nil
        end
        local amountRoot = currencyFolder:FindFirstChild("Amount")
        local amountNode = amountRoot and (amountRoot:FindFirstChild("1") or amountRoot:FindFirstChildWhichIsA("ValueBase"))
        return readNumberValue(amountNode)
    end

    local function updateHellAutoRanksLog(level, missingList, isMax, forceRefresh)
        if not AutoBuyLogState then
            return
        end
        local actionKey = "HellAutoRanks"
        local data = AutoBuyLogState.ActionData[actionKey] or {
            Key = actionKey,
            Name = "Auto Hell Ranks",
            Success = 0
        }
        data.Key = actionKey
        data.Name = "Auto Hell Ranks"
        data.Success = tonumber(data.Success) or 0
        data.Level = tonumber(level) or 0
        local reqText = "-"
        if isMax then
            reqText = "max"
        elseif type(missingList) == "table" and #missingList > 0 then
            reqText = table.concat(missingList, ", ")
        end
        data.DetailText = "Level: " .. tostring(data.Level) .. " | req:" .. tostring(reqText)
        AutoBuyLogState.ActionData[actionKey] = data
        if AutoBuyLogState.ActiveActions[actionKey] then
            AutoBuyLogState.ActiveActions[actionKey] = data
            if forceRefresh ~= false then
                updateAutoBuyLogUI()
            end
        end
    end

    local function evaluateHellRankRequirements()
        local rankModule = getHellRankModule()
        local currentLevel = getHellRankLevel()
        if type(rankModule) ~= "table" or #rankModule == 0 then
            return currentLevel, nil, {"module missing"}, false
        end
        local nextRank = rankModule[currentLevel + 1]
        if type(nextRank) ~= "table" then
            return currentLevel, nil, {}, true
        end

        local missing = {}
        local requirements = type(nextRank.Requirements) == "table" and nextRank.Requirements or {}
        for _, req in ipairs(requirements) do
            local reqType = req and req.Type
            local reqAmount = tonumber(req and req.Amount)
            if type(reqType) == "string" and #reqType > 0 then
                local ownAmount = getCurrencyAmountByType(reqType)
                if type(reqAmount) == "number" and reqAmount > 0 and type(ownAmount) == "number" and ownAmount >= reqAmount then
                    -- enough
                else
                    missing[#missing + 1] = reqType
                end
            end
        end
        return currentLevel, nextRank, missing, false
    end

    local function hellAutoRanksStep()
        local state = State.HellAutoRanks
        if not state or not state.Enabled then
            return false
        end
        local level, nextRank, missingList, isMax = evaluateHellRankRequirements()
        updateHellAutoRanksLog(level, missingList, isMax, true)
        if isMax then
            return false
        end
        if type(nextRank) ~= "table" then
            return false
        end
        if type(missingList) == "table" and #missingList > 0 then
            return false
        end

        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            pcall(function()
                remote = game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
            end)
        end
        if not remote then
            return false
        end
        local ok = pcall(function()
            remote:FireServer("HellRankUp")
        end)
        if ok and AutoBuyLogState and AutoBuyLogState.AddActionCount then
            AutoBuyLogState.AddActionCount("HellAutoRanks", 1, false)
        end
        return ok == true
    end

    local function setHellAutoRanksEnabled(enabled)
        local state = State.HellAutoRanks
        if not state then
            return
        end
        state.Enabled = enabled == true
        Config.HellAutoRanksEnabled = state.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive("HellAutoRanks", "Auto Hell Ranks", state.Enabled)
        end

        if state.Enabled then
            autoBuySchedulerRegister("HellAutoRanks", {
                Step = hellAutoRanksStep
            })
            local level, _, missingList, isMax = evaluateHellRankRequirements()
            updateHellAutoRanksLog(level, missingList, isMax, true)
        else
            autoBuySchedulerUnregister("HellAutoRanks")
            updateHellAutoRanksLog(0, {}, false, true)
        end
    end

    if State.CleanupRegistry and State.CleanupRegistry.Register then
        State.CleanupRegistry.Register(function()
            autoBuySchedulerUnregister("HellAutoRanks")
        end)
    end

    createToggle(hellRankSection, "Auto Hell Ranks", nil, State.HellAutoRanks.Enabled, function(v)
        setHellAutoRanksEnabled(v == true)
    end)
    setHellAutoRanksEnabled(State.HellAutoRanks.Enabled == true)

    local hellDepositSection = createSubSectionBox(HellAutomationSection, "Auto Deposit Hell")
    Config.HellAutoDepositItems = Config.HellAutoDepositItems or {}

    local function getHellDepositDefinitions()
        local defs = {}
        local fallback = {
            "Tehleat Head",
            "Kale Head",
            "Connor Head",
            "0hxsn Head",
            "Ghoulax Head"
        }
        local seen = {}

        local function addDef(name, order)
            if type(name) ~= "string" then
                return
            end
            local trimmed = name:match("^%s*(.-)%s*$")
            if type(trimmed) ~= "string" or #trimmed == 0 then
                return
            end
            if seen[trimmed] then
                return
            end
            seen[trimmed] = true
            defs[#defs + 1] = {
                Name = trimmed,
                Order = tonumber(order) or 999999
            }
        end

        local runtimeOrder = 1
        local milestoneRoot = LP and LP:FindFirstChild("HellMilestone")
        if milestoneRoot then
            local children = milestoneRoot:GetChildren()
            table.sort(children, function(a, b)
                return tostring(a.Name) < tostring(b.Name)
            end)
            for _, item in ipairs(children) do
                if item and item:FindFirstChild("MilestoneDeposit") then
                    addDef(item.Name, runtimeOrder)
                    runtimeOrder += 1
                end
            end
        end

        if #defs == 0 then
            for _, name in ipairs(fallback) do
                addDef(name, #defs + 1)
            end
        end
        table.sort(defs, function(a, b)
            if a.Order == b.Order then
                return tostring(a.Name) < tostring(b.Name)
            end
            return a.Order < b.Order
        end)
        return defs
    end

    local hellDepositDefs = getHellDepositDefinitions()
    local hellDepositCfg = Config.HellAutoDepositItems
    for _, def in ipairs(hellDepositDefs) do
        if hellDepositCfg[def.Name] == nil then
            hellDepositCfg[def.Name] = true
        end
    end
    saveConfig()

    State.HellAutoDeposit = State.HellAutoDeposit or {
        Enabled = Config.HellAutoDepositEnabled == true,
        Index = 1,
        Success = 0,
        SuccessByItem = {},
        LastItem = nil,
        LastSnapshotAt = 0,
        SnapshotSignature = "",
        Wait = {
            Active = false,
            Currency = nil,
            Before = nil,
            Since = 0,
            Timeout = 1.2
        }
    }

    local function readRawAndNumber(node)
        if not node then
            return nil, nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil, nil
        end
        return raw, tonumber(raw)
    end

    local function getHellCurrencyEntry(currencyName)
        if not LP or type(currencyName) ~= "string" then
            return nil, nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        local currency = currencyRoot and currencyRoot:FindFirstChild(currencyName)
        local amountRoot = currency and currency:FindFirstChild("Amount")
        local amountNode = amountRoot and (amountRoot:FindFirstChild("1") or amountRoot:FindFirstChildWhichIsA("ValueBase"))
        local milestoneRoot = LP:FindFirstChild("HellMilestone")
        local milestoneEntry = milestoneRoot and milestoneRoot:FindFirstChild(currencyName)
        return amountNode, milestoneEntry
    end

    local function shouldDepositHell(currencyName)
        local amountNode, milestoneEntry = getHellCurrencyEntry(currencyName)
        if not amountNode or not milestoneEntry then
            return false
        end
        local amountRaw, amountNum = readRawAndNumber(amountNode)
        local _, depoNum = readRawAndNumber(milestoneEntry:FindFirstChild("MilestoneDeposit"))
        if type(amountNum) ~= "number" or type(depoNum) ~= "number" then
            return false
        end
        if amountNum <= 0 or depoNum <= 0 then
            return false
        end
        if amountNum >= (depoNum * getAutoDepositRequiredMultiplier()) then
            return true, amountRaw, amountNum
        end
        return false
    end

    local function buildHellDepositSnapshot()
        local out = {}
        for _, def in ipairs(hellDepositDefs) do
            if def and hellDepositCfg[def.Name] then
                local amountNode, milestoneEntry = getHellCurrencyEntry(def.Name)
                local _, ownNum = readRawAndNumber(amountNode)
                local _, depoNum = readRawAndNumber(milestoneEntry and milestoneEntry:FindFirstChild("MilestoneDeposit"))
                out[#out + 1] = {
                    Name = tostring(def.Name),
                    OwnNum = ownNum,
                    DepositNum = depoNum
                }
            end
        end
        return out
    end

    local function buildHellItemTotalsCopy()
        local out = {}
        local src = State.HellAutoDeposit and State.HellAutoDeposit.SuccessByItem or nil
        for k, v in pairs(src or {}) do
            out[k] = tonumber(v) or 0
        end
        return out
    end

    local function buildHellSnapshotSignature(items)
        local parts = {}
        for _, entry in ipairs(items or {}) do
            parts[#parts + 1] = tostring(entry.Name)
                .. ":"
                .. tostring(entry.OwnNum ~= nil and entry.OwnNum or "?")
                .. ":"
                .. tostring(entry.DepositNum ~= nil and entry.DepositNum or "?")
        end
        table.sort(parts)
        return table.concat(parts, "|")
    end

    local function refreshHellDepositLog(forceRefresh)
        if not (AutoBuyLogState and AutoBuyLogState.UpdateDepositProgress and State.HellAutoDeposit and State.HellAutoDeposit.Enabled) then
            return
        end
        local now = os.clock()
        if not forceRefresh and (now - (State.HellAutoDeposit.LastSnapshotAt or 0)) < 0.35 then
            return
        end
        local items = buildHellDepositSnapshot()
        local sig = buildHellSnapshotSignature(items)
        if not forceRefresh and sig == State.HellAutoDeposit.SnapshotSignature then
            State.HellAutoDeposit.LastSnapshotAt = now
            return
        end
        State.HellAutoDeposit.SnapshotSignature = sig
        State.HellAutoDeposit.LastSnapshotAt = now
        AutoBuyLogState.UpdateDepositProgress("HellAutoDeposit", {
            ItemName = State.HellAutoDeposit.LastItem or "-",
            Items = items,
            Success = tonumber(State.HellAutoDeposit.Success) or 0,
            ItemTotals = buildHellItemTotalsCopy()
        })
    end

    local function hellDepositStep()
        if not State.HellAutoDeposit or not State.HellAutoDeposit.Enabled then
            return false
        end
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return false
        end

        local waitState = State.HellAutoDeposit.Wait
        if waitState and waitState.Active and waitState.Currency then
            local amountNode = getHellCurrencyEntry(waitState.Currency)
            local _, amountNum = readRawAndNumber(amountNode)
            if type(amountNum) == "number" and type(waitState.Before) == "number" and math.abs(amountNum - waitState.Before) > 1e-9 then
                waitState.Active = false
            elseif (os.clock() - (waitState.Since or 0)) < (waitState.Timeout or 1.2) then
                return false
            else
                waitState.Active = false
            end
        end

        local total = #hellDepositDefs
        if total == 0 then
            return false
        end
        refreshHellDepositLog(false)
        local idx = tonumber(State.HellAutoDeposit.Index) or 1
        for _ = 1, total do
            local def = hellDepositDefs[idx]
            idx += 1
            if idx > total then
                idx = 1
            end
            if def and hellDepositCfg[def.Name] then
                local should, rawAmount, amountNum = shouldDepositHell(def.Name)
                if should then
                    local amountArg = rawAmount
                    if type(amountArg) ~= "string" and type(amountArg) ~= "number" then
                        amountArg = tostring(amountNum)
                    end
                    local ok = pcall(function()
                        remote:FireServer("hellDeposit", def.Name, amountArg)
                    end)
                    if ok then
                        State.HellAutoDeposit.Index = idx
                        State.HellAutoDeposit.LastItem = def.Name
                        State.HellAutoDeposit.Success = (tonumber(State.HellAutoDeposit.Success) or 0) + 1
                        State.HellAutoDeposit.SuccessByItem = State.HellAutoDeposit.SuccessByItem or {}
                        State.HellAutoDeposit.SuccessByItem[def.Name] = (tonumber(State.HellAutoDeposit.SuccessByItem[def.Name]) or 0) + 1
                        if waitState then
                            waitState.Active = true
                            waitState.Currency = def.Name
                            waitState.Before = amountNum
                            waitState.Since = os.clock()
                        end
                        refreshHellDepositLog(true)
                        return true
                    end
                end
            end
        end
        State.HellAutoDeposit.Index = idx
        return false
    end

    local function setHellAutoDepositEnabled(enabled)
        State.HellAutoDeposit.Enabled = enabled == true
        Config.HellAutoDepositEnabled = State.HellAutoDeposit.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetDepositActive then
            AutoBuyLogState.SetDepositActive("HellAutoDeposit", "Deposit Hell", State.HellAutoDeposit.Enabled)
            if State.HellAutoDeposit.Enabled and AutoBuyLogState.UpdateDepositProgress then
                AutoBuyLogState.UpdateDepositProgress("HellAutoDeposit", {
                    ItemName = State.HellAutoDeposit.LastItem or "-",
                    Items = buildHellDepositSnapshot(),
                    Success = tonumber(State.HellAutoDeposit.Success) or 0,
                    ItemTotals = buildHellItemTotalsCopy()
                })
            end
        end

        if State.HellAutoDeposit.Enabled then
            State.HellAutoDeposit.Index = 1
            State.HellAutoDeposit.LastSnapshotAt = 0
            State.HellAutoDeposit.SnapshotSignature = ""
            if State.HellAutoDeposit.Wait then
                State.HellAutoDeposit.Wait.Active = false
                State.HellAutoDeposit.Wait.Currency = nil
                State.HellAutoDeposit.Wait.Before = nil
            end
            autoBuySchedulerRegister("HellAutoDeposit", {
                Step = hellDepositStep
            })
        else
            autoBuySchedulerUnregister("HellAutoDeposit")
            if State.HellAutoDeposit.Wait then
                State.HellAutoDeposit.Wait.Active = false
                State.HellAutoDeposit.Wait.Currency = nil
                State.HellAutoDeposit.Wait.Before = nil
            end
        end
    end

    createToggle(hellDepositSection, "Auto Deposit Hell", nil, State.HellAutoDeposit.Enabled, function(v)
        setHellAutoDepositEnabled(v == true)
    end)

    local hellItemListSection = createSubSectionBox(hellDepositSection, "Item List")
    for _, def in ipairs(hellDepositDefs) do
        createToggle(hellItemListSection, tostring(def.Name), nil, hellDepositCfg[def.Name], function(v)
            hellDepositCfg[def.Name] = v == true
            saveConfig()
            if State.HellAutoDeposit and State.HellAutoDeposit.Enabled and AutoBuyLogState and AutoBuyLogState.UpdateDepositProgress then
                refreshHellDepositLog(true)
            end
        end)
    end
    setHellAutoDepositEnabled(State.HellAutoDeposit.Enabled == true)

end

do
    local Event500KTeleportSection = createSectionBox(State.Tabs.Event500K:GetPage(), "Teleport")
    createButton(Event500KTeleportSection, "Home", function()
        teleportHomeWithBuy("500K Event")
    end)
    local Event500KList = {
        {Label = "Ascend", Data = makeData(
            Vector3.new(-2295.990, 25.150, -54.778),
            CFrame.new(-2290.416016, 35.197639, -71.399429, -0.948105156, -0.139349654, 0.285794318, 0.000000000, 0.898845613, 0.438265592, -0.317957103, 0.415521860, -0.852200091),
            CFrame.new(-2295.990234, 26.649710, -54.778114, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504028
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(-2276.094, 26.249, -80.425),
            CFrame.new(-2287.787842, 42.744099, -84.760132, -0.347580701, 0.720886588, -0.599591732, 0.000000000, 0.639462113, 0.768822670, 0.937650025, 0.267227918, -0.222264707),
            CFrame.new(-2276.093506, 27.748981, -80.425079, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503941
        )},
        {Label = "Tree 1", Data = makeData(
            Vector3.new(-2235.672, 26.086, -189.510),
            CFrame.new(-2242.218262, 64.155159, -174.681534, 0.914822817, 0.369211853, -0.163651317, 0.000000000, 0.405222595, 0.914218068, 0.403855354, -0.836347520, 0.370706886),
            CFrame.new(-2235.672119, 27.586439, -189.509811, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            40.000011
        )},
        {Label = "Tree 2", Data = makeData(
            Vector3.new(-2198.955, 25.151, -217.756),
            CFrame.new(-2201.445801, 65.785721, -209.863708, 0.953615010, 0.294515729, -0.062281270, 0.000000000, 0.206894591, 0.978363335, 0.301028997, -0.932981968, 0.197297782),
            CFrame.new(-2198.954590, 26.651192, -217.755615, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            39.999996
        )},
        {Label = "Tree 3", Data = makeData(
            Vector3.new(-2247.844, 25.151, -232.860),
            CFrame.new(-2249.394043, 66.043503, -226.089645, 0.974763453, 0.219848618, -0.038765401, 0.000000000, 0.173648879, 0.984807730, 0.223240137, -0.959954560, 0.169266582),
            CFrame.new(-2247.843506, 26.651192, -232.860306, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            40.000000
        )},
        {Label = "Tree 4", Data = makeData(
            Vector3.new(-2221.199, 25.987, -253.984),
            CFrame.new(-2223.045654, 66.879623, -247.288223, 0.964005291, 0.261843741, -0.046170160, 0.000000000, 0.173648342, 0.984807730, 0.265883118, -0.949359834, 0.167397916),
            CFrame.new(-2221.198730, 27.487316, -253.984146, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            40.000004
        )}
    }
    registerRuneLocations("500K Event", Event500KList)
    createGrid(Event500KTeleportSection, Event500KList, function(item)
        teleportWithData(item.Data)
    end)

    local Event500KAutomationSection = createSectionBox(State.Tabs.Event500K:GetPage(), "Automation")
    setupAutoBuyGroup(Event500KAutomationSection, {
        GroupKey = "500K Event",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Mode: Upgrade All",
        SpeedLabel = "Click Speed (sec)",
        CooldownKey = "500KEventAutoBuy",
        DefaultCooldown = 0.6,
        Shops = {
            {
                Key = "Event Shards",
                DisplayName = "Event Shards Shop",
                ShopName = "Event Shards",
            }
        }
    })

    local upgradeTreeSection = createSubSectionBox(Event500KAutomationSection, "Auto Upgrade 500K Tree")
    Config.Event500KAutoUpgradeTreeEnabled = Config.Event500KAutoUpgradeTreeEnabled == true

    State.Event500KAutoUpgradeTree = State.Event500KAutoUpgradeTree or {
        Enabled = Config.Event500KAutoUpgradeTreeEnabled == true,
        OwnerKey = "Event500KAutoUpgradeTree",
        Cache = nil,
        LastUpgradeDisplay = "-",
        LastCheckDisplay = "-",
        PendingUpgrade = nil,
        FailedByKey = {}
    }

    local Event500KStaticSpec = {
        Event1_Start = {DisplayName = "Event Tree", Max = 1},
        ["Event1_Rare Shard"] = {DisplayName = "Gain Rare Shards", Max = 1},
        Event1_Shards1 = {DisplayName = "Event Shards 1", Max = 1},
        Event1_Seeds = {DisplayName = "Event Seeds", MaxBase = 5, MaxPlusArg2 = true},
        Event1_Plants = {DisplayName = "Event Plants", MaxBase = 5, MaxPlusArg2 = true},
        Event1_Logs = {DisplayName = "Event Logs", MaxBase = 5, MaxPlusArg2 = true},
        Event1_EventLuck2 = {DisplayName = "Event Luck 2", Max = 5},
        Event1_Leafs = {DisplayName = "Event Leafs", MaxBase = 5, MaxPlusArg2 = true},
        Event1_Apples = {DisplayName = "Event Apples", Max = 10},
        ["Event1_Rune Bulk"] = {DisplayName = "Event Rune Bulk", Max = 5},
        ["Event1_Rune Luck"] = {DisplayName = "[SECRET] Rune Luck", Max = 25},
        Event1_MoreWorld1 = {DisplayName = "[SECRET] World 1 Levels", Max = 50},
        Event1_Shards2 = {DisplayName = "Event Shards 2", Max = 1},
        Event1_EventLuck1 = {DisplayName = "Event Luck 1", Max = 1},
        Event1_Snow = {DisplayName = "Event Snow", Max = 5},
        Event1_Ice = {DisplayName = "Event Ice", Max = 5},
        ["Event1_Boss Shards"] = {DisplayName = "Event Boss Shards", Max = 5},
        ["Event1_Boss Damage"] = {DisplayName = "Event Boss Damage", Max = 5},
        ["Event1_Tier Luck"] = {DisplayName = "Event Tier Luck", Max = 20},
        ["Event1_Passive Shards"] = {DisplayName = "[SECRET] Passive Shards", Max = 5},
        ["Event1_Auto Tier Timer"] = {DisplayName = "[SECRET] Auto Tier Timer", Max = 1},
        Event1_ShardCD1 = {DisplayName = "Shard Generation 1", Max = 5},
        Event1_Shards3 = {DisplayName = "Event Shards 3", Max = 2},
        Event1_Points = {DisplayName = "Event Points", Max = 5},
        ["Event1_Event Bulk"] = {DisplayName = "Event Bulk 1", Max = 10},
        Event1_Sand = {DisplayName = "Event Sand", Max = 5},
        Event1_SecretShard1 = {DisplayName = "[SECRET] Shards 1", Max = 25},
        ["Event1_Sand Capacity"] = {DisplayName = "Event Sand Capacity", Max = 10},
        ["Event1_Sand Conversion Rate"] = {DisplayName = "Event Sand Conversion Rate", Max = 10},
        Event1_Fossils = {DisplayName = "Event Fossils", Max = 10},
        ["Event1_Event Enchant"] = {DisplayName = "Event Enchant Shard", Max = 10},
        Event1_Shards4 = {DisplayName = "Event Shards 4", Max = 3},
        Event1_ShardsAdd1 = {DisplayName = "What Could Be Here?", Max = 99},
        Event1_ShardsAdd2 = {DisplayName = "Expensive...", Max = 99},
        ["Event1_Epic Shard"] = {DisplayName = "[SECRET] Gain Epic Shards", Max = 1},
        Event1_SecretShard2 = {DisplayName = "[SECRET] Shards 2", Max = 20},
        Event1_ShardsAdd3 = {DisplayName = "What Lies Ahead?", Max = 99},
        ["Event1_Event Enchant Chance"] = {DisplayName = "Event Enchant Chance", Max = 99},
        Event1_ShardsAdd4 = {DisplayName = "Could It Be?", Max = 99},
        Event1_SecretShard3 = {DisplayName = "[SECRET] Shards 3", Max = 20},
        ["Event1_Unlock Secret"] = {DisplayName = "Unlock Hidden Upgrades", MaxBase = 1, MaxPlusArg2 = true},
        Event1_ShardCD2 = {DisplayName = "Shard Generation 2", Max = 5},
        Event1_Shards5 = {DisplayName = "Event Shards 5", Max = 5},
        Event1_SecretShard4 = {DisplayName = "[SECRET] Shards 4", Max = 77},
        Event1_Shards6 = {DisplayName = "Event Shards 6", Max = 6},
        Event1_Cash = {DisplayName = "Event Cash", Max = 5},
        ["Event1_Event Bulk2"] = {DisplayName = "Event Bulk 2", Max = 10},
        Event1_Dust = {DisplayName = "Event Dust", Max = 5},
        ["Event1_Secret OreMultiplier"] = {DisplayName = "[SECRET] Ore Multiplier", Max = 10},
        ["Event1_Worker XP"] = {DisplayName = "Event Worker XP", Max = 5},
        Event1_SecretEventLuck1 = {DisplayName = "[SECRET] Event Luck", Max = 60},
        ["Event1_Pickaxe Damage"] = {DisplayName = "Event Pickaxe Damage", Max = 5},
        ["Event1_Ore Inventory"] = {DisplayName = "Event Ore Inventory", Max = 200},
        ["Event1_Secret CD1"] = {DisplayName = "[SECRET] Shard Generation 1", Max = 10},
        Event1_Shards7 = {DisplayName = "Event Shards 7", Max = 1},
        Event1_Shards8 = {DisplayName = "Event Shards 8", Max = 2},
        Event1_Shards9 = {DisplayName = "Event Shards 9", Max = 1},
        Event1_Shards10 = {DisplayName = "Event Shards 10", Max = 10},
        ["Event1_Event Enchant 2"] = {DisplayName = "Event Enchant Shard 2", Max = 1},
        Event1_ShardCD3 = {DisplayName = "Shard Generation 3", Max = 10},
        ["Event1_Legendary Shard"] = {DisplayName = "Gain Legendary Shards", Max = 1},
        ["Event1_Event Bulk3"] = {DisplayName = "Event Bulk 3", Max = 1},
        Event1_SecretEventBulk = {DisplayName = "[SECRET] Event Bulk", Max = 100}
    }

    local function event500KReadNumber(node)
        local helpers = State.AutoBuyShop and State.AutoBuyShop.Helpers or nil
        if helpers and helpers.GetNumericValueFromNode then
            local n = helpers.GetNumericValueFromNode(node)
            if type(n) == "number" then
                return n
            end
        end
        if not node then
            return nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil
        end
        local n = tonumber(raw)
        if type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge then
            return n
        end
        return nil
    end

    local function event500KFindChildCaseInsensitive(parent, name)
        if not parent or type(name) ~= "string" or #name == 0 then
            return nil
        end
        local direct = parent:FindFirstChild(name)
        if direct then
            return direct
        end
        local target = string.lower(name)
        for _, child in ipairs(parent:GetChildren()) do
            if string.lower(tostring(child.Name)) == target then
                return child
            end
        end
        return nil
    end

    local function event500KGetCurrencyAmount(currencyName)
        if not LP or type(currencyName) ~= "string" or #currencyName == 0 then
            return nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        if not currencyRoot then
            return nil
        end
        local currencyFolder = event500KFindChildCaseInsensitive(currencyRoot, currencyName)
        if not currencyFolder then
            return nil
        end
        local amountRoot = currencyFolder:FindFirstChild("Amount")
        local amountNode = amountRoot and (amountRoot:FindFirstChild("1") or amountRoot:FindFirstChildWhichIsA("ValueBase"))
        return event500KReadNumber(amountNode)
    end

    local function event500KGetUpgradeNode(key)
        if not LP or type(key) ~= "string" or #key == 0 then
            return nil
        end
        local treeRoot = LP:FindFirstChild("UpgradeTree")
        if not treeRoot then
            return nil
        end
        return event500KFindChildCaseInsensitive(treeRoot, key)
    end

    local function event500KGetUpgradeAmount(key)
        local node = event500KGetUpgradeNode(key)
        local amountNode = node and node:FindFirstChild("Amount")
        local amount = event500KReadNumber(amountNode)
        if type(amount) == "number" then
            return math.max(0, math.floor(amount + 0.5))
        end
        return 0
    end

    local function event500KIsUnlocked(key)
        local node = event500KGetUpgradeNode(key)
        local unlockedNode = node and node:FindFirstChild("Unlocked")
        if not unlockedNode then
            return false
        end
        local ok, value = pcall(function()
            return unlockedNode.Value
        end)
        return ok and value == true
    end

    local function event500KGetLevelLimit(key)
        local node = event500KGetUpgradeNode(key)
        local special = node and node:FindFirstChild("SpecialConditions")
        local limitNode = special and special:FindFirstChild("LevelLimit")
        local limit = event500KReadNumber(limitNode)
        if type(limit) == "number" and limit > 0 then
            return math.max(0, math.floor(limit + 0.5))
        end
        return nil
    end

    local function event500KReadValueByNames(parent, names)
        if not parent or type(names) ~= "table" then
            return nil
        end
        for _, name in ipairs(names) do
            local node = event500KFindChildCaseInsensitive(parent, name)
            local value = event500KReadNumber(node)
            if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
                return value
            end
        end
        return nil
    end

    local function event500KReadCostFromUpgradeNode(node)
        if not node then
            return nil
        end
        local direct = event500KReadValueByNames(node, {"NextCost", "Cost", "Price"})
        if type(direct) == "number" and direct > 0 then
            return direct
        end

        local special = node:FindFirstChild("SpecialConditions")
        local specialCost = event500KReadValueByNames(special, {"NextCost", "Cost", "Price"})
        if type(specialCost) == "number" and specialCost > 0 then
            return specialCost
        end

        local function normalizeName(text)
            local out = string.lower(tostring(text or ""))
            out = out:gsub("[%s%-%_]+", "")
            return out
        end

        local function scoreCostField(nameLower)
            if type(nameLower) ~= "string" or #nameLower == 0 then
                return nil
            end
            local blocked = {
                "decrease",
                "discount",
                "multiply",
                "multiplier",
                "reward",
                "cooldown",
                "unlock",
                "required",
                "requirement",
                "level",
                "limit",
                "max",
                "min"
            }
            for _, token in ipairs(blocked) do
                if string.find(nameLower, token, 1, true) then
                    return nil
                end
            end
            if nameLower == "nextcost" then
                return 110
            end
            if nameLower == "currentcost" then
                return 100
            end
            if nameLower == "upgradecost" then
                return 95
            end
            if nameLower == "cost" then
                return 90
            end
            if nameLower == "price" then
                return 80
            end
            if nameLower:sub(-4) == "cost" then
                return 70
            end
            if nameLower:sub(-5) == "price" then
                return 60
            end
            return nil
        end

        local bestValue = nil
        local bestScore = nil
        for _, desc in ipairs(node:GetDescendants()) do
            local parentName = normalizeName((desc.Parent and desc.Parent.Name) or "")
            if string.find(parentName, "unlock", 1, true) == nil
                and string.find(parentName, "require", 1, true) == nil
                and string.find(parentName, "level", 1, true) == nil
                and string.find(parentName, "reward", 1, true) == nil then
                local name = normalizeName(desc.Name or "")
                local score = scoreCostField(name)
                if score then
                    local value = event500KReadNumber(desc)
                    if type(value) == "number" and value == value and value > 0 and value ~= math.huge and value ~= -math.huge then
                        if bestValue == nil
                            or score > bestScore
                            or (score == bestScore and value > bestValue) then
                            bestValue = value
                            bestScore = score
                        end
                    end
                end
            end
        end
        return bestValue
    end

    local function event500KResolveDisplayName(key, node)
        local fromNode = event500KReadValueByNames(node, {"DisplayName"})
        if type(fromNode) == "number" then
            -- ignore numeric
        end
        local displayNode = node and event500KFindChildCaseInsensitive(node, "DisplayName")
        if displayNode then
            local ok, value = pcall(function()
                return displayNode.Value
            end)
            if ok and type(value) == "string" and #value > 0 then
                return value
            end
        end
        local spec = Event500KStaticSpec[tostring(key or "")]
        if type(spec) == "table" and type(spec.DisplayName) == "string" and #spec.DisplayName > 0 then
            return spec.DisplayName
        end

        local raw = tostring(key or "")
        raw = raw:gsub("^Event%d+_", "")
        raw = raw:gsub("_", " ")
        raw = raw:gsub("%s+", " ")
        raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if #raw > 0 then
            return raw
        end
        return tostring(key or "-")
    end

    local function event500KResolveMaxSpec(key, runtimeLimit)
        local spec = Event500KStaticSpec[tostring(key or "")]
        if type(spec) == "table" then
            local fixedMax = tonumber(spec.Max)
            if type(fixedMax) == "number" and fixedMax > 0 then
                local maxValue = math.max(1, math.floor(fixedMax + 0.5))
                return maxValue, tostring(maxValue)
            end
            if spec.MaxPlusArg2 == true then
                local base = tonumber(spec.MaxBase) or 0
                local baseInt = math.max(0, math.floor(base + 0.5))
                local expr = tostring(baseInt) .. "+arg2"
                if type(runtimeLimit) == "number" and runtimeLimit > 0 then
                    local maxValue = math.max(1, math.floor(baseInt + runtimeLimit + 0.5))
                    return maxValue, expr
                end
                return nil, expr
            end
        end
        if type(runtimeLimit) == "number" and runtimeLimit > 0 then
            local maxValue = math.max(1, math.floor(runtimeLimit + 0.5))
            return maxValue, tostring(maxValue)
        end
        return nil, "?"
    end

    local function event500KFormatProgressDisplay(nameOrItem, amount, maxLevel, maxLabel, cost)
        local name = "-"
        if type(nameOrItem) == "table" then
            name = tostring((nameOrItem.DisplayName or nameOrItem.Key) or "-")
        else
            name = tostring(nameOrItem or "-")
        end
        local ownText = tostring(tonumber(amount) or 0)
        local maxText = type(maxLabel) == "string" and #maxLabel > 0 and maxLabel
            or (type(maxLevel) == "number" and tostring(maxLevel) or "?")
        local costText = type(cost) == "number" and autoBuyLogFormatNumber(cost) or "?"
        return name .. " (" .. ownText .. "/" .. maxText .. ") | Cost: " .. tostring(costText)
    end

    local function event500KGetModule()
        local state = State.Event500KAutoUpgradeTree
        if state and type(state.Cache) == "table" and type(state.Cache.Items) == "table" and type(state.Cache.TreeRoot) == "Instance" then
            if state.Cache.TreeRoot.Parent and #state.Cache.TreeRoot:GetChildren() == (state.Cache.TreeCount or 0) then
                return state.Cache
            end
        end

        local treeRoot = LP and LP:FindFirstChild("UpgradeTree")
        if not treeRoot then
            return nil
        end

        local items = {}
        for _, child in ipairs(treeRoot:GetChildren()) do
            if child and type(child.Name) == "string" then
                local key = tostring(child.Name)
                if string.find(key, "Event1_", 1, true) == 1 then
                    items[#items + 1] = {
                        Key = key,
                        DisplayName = event500KResolveDisplayName(key, child),
                        UpgradeCurrency = "Event Shards",
                        Unlock = {},
                        CostFn = nil,
                        RuntimeNode = child
                    }
                end
            end
        end

        table.sort(items, function(a, b)
            return tostring(a.Key) < tostring(b.Key)
        end)

        if #items == 0 then
            return state.Cache
        end

        local cache = {
            Items = items,
            TreeRoot = treeRoot,
            TreeCount = #treeRoot:GetChildren()
        }
        if state then
            state.Cache = cache
        end
        return cache
    end

    local function event500KCheckRequirements(item)
        local missing = {}
        if type(item) ~= "table" then
            missing[#missing + 1] = "invalid item"
            return false, missing
        end

        if not event500KIsUnlocked(item.Key) then
            missing[#missing + 1] = "locked"
        end

        local unlockList = type(item.Unlock) == "table" and item.Unlock or {}
        for _, req in ipairs(unlockList) do
            if type(req) == "table" then
                local reqKey = req.UnlockUpgrade
                local reqLevel = tonumber(req.Upgrade)
                if type(reqKey) == "string" and #reqKey > 0 and type(reqLevel) == "number" then
                    local ownLevel = event500KGetUpgradeAmount(reqKey)
                    if ownLevel < reqLevel then
                        missing[#missing + 1] = tostring(reqKey)
                    end
                end
            end
        end
        return #missing == 0, missing
    end

    local function event500KBuildLogUpdate(meta, forceRefresh)
        if not AutoBuyLogState then
            return
        end
        local actionKey = "Event500KAutoUpgradeTree"
        local data = AutoBuyLogState.ActionData[actionKey] or {
            Key = actionKey,
            Name = "Auto Upgrade 500K Tree",
            Success = 0
        }
        data.Key = actionKey
        data.Name = "Auto Upgrade 500K Tree"
        data.Success = tonumber(data.Success) or 0

        local lastUpgrade = (meta and meta.LastUpgrade) or "-"
        local lastCheck = (meta and meta.LastCheck) or "-"
        local locked = tonumber(meta and meta.Locked) or 0
        local unlocked = tonumber(meta and meta.Unlocked) or 0
        local totalItem = tonumber(meta and meta.TotalItem) or 0
        local totalMax = tonumber(meta and meta.TotalMax) or 0
        local currencyText = tostring((meta and meta.CurrencyText) or "-")
        data.CurrencyText = currencyText
        data.DetailText =
            "Last Upgrade: " .. tostring(lastUpgrade)
            .. "\n----------------"
            .. "\nLast Check: " .. tostring(lastCheck)
            .. "\n----------------"
            .. "\nLocked: " .. tostring(locked) .. " | Unlocked: " .. tostring(unlocked)
            .. "\n----------------"
            .. "\nTotal Item: " .. tostring(totalItem) .. " | Total Max: " .. tostring(totalMax)

        AutoBuyLogState.ActionData[actionKey] = data
        if AutoBuyLogState.ActiveActions[actionKey] then
            AutoBuyLogState.ActiveActions[actionKey] = data
            if forceRefresh ~= false then
                updateAutoBuyLogUI()
            end
        end
    end

    local function event500KResolveRemoteArgument(key)
        if type(key) ~= "string" then
            return nil
        end
        local out = key
        out = out:gsub("^Event%d+_", "")
        if out == key then
            out = out:gsub("^[^_]+_", "")
        end
        out = (out:gsub("^%s+", ""):gsub("%s+$", ""))
        if #out == 0 then
            return nil
        end
        return out
    end

    local function event500KProcessPendingUpgrade(state)
        if not state then
            return false, false
        end
        local pending = state.PendingUpgrade
        if type(pending) ~= "table" or type(pending.Key) ~= "string" then
            state.PendingUpgrade = nil
            return false, false
        end

        local key = pending.Key
        local amountNow = event500KGetUpgradeAmount(key)
        local amountBefore = tonumber(pending.AmountBefore) or 0
        if type(amountNow) == "number" and amountNow > amountBefore then
            state.LastUpgradeDisplay = event500KFormatProgressDisplay(
                tostring(pending.DisplayName or pending.Key or "-"),
                amountNow,
                tonumber(pending.MaxLevel),
                pending.MaxLabel,
                tonumber(pending.Cost)
            )
            if AutoBuyLogState and AutoBuyLogState.AddActionCount then
                AutoBuyLogState.AddActionCount("Event500KAutoUpgradeTree", 1, false)
            end
            if type(state.FailedByKey) ~= "table" then
                state.FailedByKey = {}
            end
            state.FailedByKey[key] = 0
            state.PendingUpgrade = nil
            return true, false
        end

        local now = os.clock()
        local since = tonumber(pending.Since) or now
        local timeout = tonumber(pending.Timeout) or 1.25
        if (now - since) < timeout then
            return false, true
        end

        state.PendingUpgrade = nil
        if type(state.FailedByKey) ~= "table" then
            state.FailedByKey = {}
        end
        local failed = tonumber(state.FailedByKey[key]) or 0
        failed += 1
        state.FailedByKey[key] = failed

        return false, false
    end

    local function event500KAutoUpgradeStep()
        local state = State.Event500KAutoUpgradeTree
        if not state or not state.Enabled then
            return false
        end
        if type(state.FailedByKey) ~= "table" then
            state.FailedByKey = {}
        end

        local _, pendingWaiting = event500KProcessPendingUpgrade(state)

        local moduleData = event500KGetModule()
        local items = moduleData and moduleData.Items or nil
        if type(items) ~= "table" or #items == 0 then
            event500KBuildLogUpdate({
                LastUpgrade = state.LastUpgradeDisplay or "-",
                LastCheck = state.LastCheckDisplay or "-",
                Locked = 0,
                Unlocked = 0,
                TotalItem = 0,
                TotalMax = 0
            }, true)
            return false
        end

        local locked = 0
        local unlocked = 0
        local totalMax = 0
        local totalItem = #items
        local target = nil
        local firstCheckCandidate = nil
        local currentCurrency = event500KGetCurrencyAmount("Event Shards")
        local currentCurrencyText = type(currentCurrency) == "number" and autoBuyLogFormatNumber(currentCurrency) or "-"

        for _, item in ipairs(items) do
            local amount = event500KGetUpgradeAmount(item.Key)
            local levelLimit = event500KGetLevelLimit(item.Key)
            local okReq = false
            local reqMissing = nil
            okReq, reqMissing = event500KCheckRequirements(item)
            if okReq then
                unlocked += 1
            else
                locked += 1
            end

            local nextLevel = amount + 1
            local cost = nil
            local maxLevel = nil
            if type(item.CostFn) == "function" then
                local okCost, nextCost, nextMax = pcall(item.CostFn, nextLevel, levelLimit, LP)
                if okCost and type(nextCost) == "number" and nextCost == nextCost and nextCost > 0 then
                    cost = nextCost
                end
                if okCost and type(nextMax) == "number" and nextMax == nextMax and nextMax > 0 then
                    maxLevel = math.max(1, math.floor(nextMax + 0.5))
                end
            end
            if type(cost) ~= "number" and item.RuntimeNode then
                cost = event500KReadCostFromUpgradeNode(item.RuntimeNode)
            end
            if type(maxLevel) ~= "number" then
                local runtimeLimit = event500KGetLevelLimit(item.Key)
                if type(runtimeLimit) == "number" and runtimeLimit > 0 then
                    maxLevel = runtimeLimit
                end
            end
            local maxLabel = nil
            local specMax, specLabel = event500KResolveMaxSpec(item.Key, levelLimit)
            if type(specMax) == "number" then
                maxLevel = specMax
            end
            maxLabel = specLabel
            local isMaxed = type(maxLevel) == "number" and amount >= maxLevel
            if isMaxed then
                totalMax += 1
            end

            if not firstCheckCandidate and okReq and not isMaxed then
                firstCheckCandidate = {
                    Item = item,
                    Amount = amount,
                    MaxLevel = maxLevel,
                    MaxLabel = maxLabel,
                    Cost = cost
                }
            end

            if (not pendingWaiting) and not target and okReq and not isMaxed and type(cost) == "number" and cost > 0 then
                local ownCurrency = event500KGetCurrencyAmount(item.UpgradeCurrency)
                if type(ownCurrency) == "number" and ownCurrency >= cost then
                    target = {
                        Item = item,
                        Cost = cost,
                        Amount = amount,
                        MaxLevel = maxLevel,
                        MaxLabel = maxLabel
                    }
                end
            end
        end

        if target and target.Item then
            state.LastCheckDisplay = event500KFormatProgressDisplay(
                target.Item,
                target.Amount,
                target.MaxLevel,
                target.MaxLabel,
                target.Cost
            )
        elseif type(firstCheckCandidate) == "table" and firstCheckCandidate.Item then
            state.LastCheckDisplay = event500KFormatProgressDisplay(
                firstCheckCandidate.Item,
                firstCheckCandidate.Amount,
                firstCheckCandidate.MaxLevel,
                firstCheckCandidate.MaxLabel,
                firstCheckCandidate.Cost
            )
        else
            state.LastCheckDisplay = "-"
        end

        event500KBuildLogUpdate({
            LastUpgrade = state.LastUpgradeDisplay or "-",
            LastCheck = state.LastCheckDisplay or "-",
            Locked = locked,
            Unlocked = unlocked,
            TotalItem = totalItem,
            TotalMax = totalMax,
            CurrencyText = currentCurrencyText
        }, true)

        if not target then
            return false
        end

        local remoteArg = event500KResolveRemoteArgument(target.Item.Key)
        if type(remoteArg) ~= "string" or #remoteArg == 0 then
            return false
        end

        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            pcall(function()
                remote = game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
            end)
        end
        if not remote then
            return false
        end

        local okFire = pcall(function()
            remote:FireServer("UpgradeTree", remoteArg)
        end)
        if okFire then
            state.PendingUpgrade = {
                Key = tostring(target.Item.Key or ""),
                DisplayName = tostring(target.Item.DisplayName or target.Item.Key or remoteArg),
                AmountBefore = tonumber(target.Amount) or 0,
                MaxLevel = tonumber(target.MaxLevel),
                MaxLabel = target.MaxLabel,
                Cost = tonumber(target.Cost),
                Since = os.clock(),
                Timeout = 1.25
            }
        end
        return okFire == true
    end

    local function setEvent500KAutoUpgradeEnabled(enabled)
        local state = State.Event500KAutoUpgradeTree
        if not state then
            return
        end
        state.Enabled = enabled == true
        Config.Event500KAutoUpgradeTreeEnabled = state.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetActionActive then
            AutoBuyLogState.SetActionActive("Event500KAutoUpgradeTree", "Auto Upgrade 500K Tree", state.Enabled)
        end

        if state.Enabled then
            state.LastCheckDisplay = "-"
            state.PendingUpgrade = nil
            state.FailedByKey = state.FailedByKey or {}
            autoBuySchedulerRegister("Event500KAutoUpgradeTree", {
                Step = event500KAutoUpgradeStep
            })
            event500KAutoUpgradeStep()
        else
            state.LastCheckDisplay = "-"
            state.PendingUpgrade = nil
            autoBuySchedulerUnregister("Event500KAutoUpgradeTree")
            event500KBuildLogUpdate({
                LastUpgrade = "-",
                LastCheck = "-",
                Locked = 0,
                Unlocked = 0,
                TotalItem = 0,
                TotalMax = 0
            }, true)
        end
    end

    if State.CleanupRegistry and State.CleanupRegistry.Register then
        State.CleanupRegistry.Register(function()
            autoBuySchedulerUnregister("Event500KAutoUpgradeTree")
        end)
    end

    createToggle(upgradeTreeSection, "Auto Upgrade 500K Tree", nil, State.Event500KAutoUpgradeTree.Enabled, function(v)
        setEvent500KAutoUpgradeEnabled(v == true)
    end)
    setEvent500KAutoUpgradeEnabled(State.Event500KAutoUpgradeTree.Enabled == true)
end
    stepWorld("500K Event")

do
    local HalloweenTeleportSection = createSectionBox(State.Tabs.Halloween:GetPage(), "Teleport")
    createButton(HalloweenTeleportSection, "Home", function()
        teleportHomeWithBuy("Halloween")
    end)
    local HalloweenList = {
        {Label = "Flesh Shop", Data = makeData(
            Vector3.new(-2285.308, 19.919, -2138.265),
            CFrame.new(-2285.977295, 31.302032, -2161.088379, -0.999569833, 0.011649705, -0.026914433, 0.000000000, 0.917720020, 0.397228032, 0.029327499, 0.397057146, -0.917325258),
            CFrame.new(-2285.307617, 21.418999, -2138.265381, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.879951
        )},
        {Label = "Fleshify", Data = makeData(
            Vector3.new(-2214.776, 19.919, -2157.964),
            CFrame.new(-2232.713135, 32.622929, -2149.059326, 0.444644213, 0.437339455, -0.781681359, 0.000000000, 0.872697353, 0.488261580, 0.895707309, -0.217102692, 0.388039798),
            CFrame.new(-2214.775879, 21.418791, -2157.963623, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            22.946989
        )},
        {Label = "Sword Crafting", Data = makeData(
            Vector3.new(-2159.469, 19.924, -2234.667),
            CFrame.new(-2162.267822, 31.480072, -2214.232178, 0.990749240, 0.059472892, -0.121979445, 0.000000000, 0.898853481, 0.438249350, 0.135705605, -0.434195220, 0.890538335),
            CFrame.new(-2159.468750, 21.423563, -2234.667480, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            22.947107
        )},
        {Label = "Sword enchants", Data = makeData(
            Vector3.new(-2139.681, 19.919, -2192.644),
            CFrame.new(-2155.138184, 31.591566, -2206.213623, -0.659731865, 0.333152533, -0.673619509, 0.000000000, 0.896365285, 0.443316102, 0.751501083, 0.292469770, -0.591360748),
            CFrame.new(-2139.680664, 21.418791, -2192.643555, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            22.947048
        )},
        {Label = "Candy Corn", Data = makeData(
            Vector3.new(-1977.522, 23.558, -2207.680),
            CFrame.new(-1975.137573, 46.906532, -2174.258789, 0.997464955, -0.038867608, 0.059606303, 0.000000000, 0.837649584, 0.546207964, -0.071158990, -0.544823289, 0.835526168),
            CFrame.new(-1977.521851, 25.058212, -2207.679932, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            40.000084
        )},
        {Label = "Refined Candy Corn", Data = makeData(
            Vector3.new(-1951.021, 24.559, -2084.695),
            CFrame.new(-1941.997803, 31.781582, -2095.510010, -0.767842770, -0.241146296, 0.593519986, 0.000000000, 0.926450908, 0.376415670, -0.640638292, 0.289028049, -0.711368680),
            CFrame.new(-1951.021240, 26.058859, -2084.694824, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203297
        )},
        {Label = "Refined Candy Corn Upgrade", Data = makeData(
            Vector3.new(-1930.651, 23.358, -2101.947),
            CFrame.new(-1939.576660, 29.775299, -2111.004150, -0.712264240, 0.253161699, -0.654667020, 0.000000000, 0.932691813, 0.360674679, 0.701911449, 0.256895661, -0.664322972),
            CFrame.new(-1930.651489, 24.858192, -2101.947266, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633186
        )},
        {Label = "Mutation Roller", Data = makeData(
            Vector3.new(-1889.595, 24.002, -2126.313),
            CFrame.new(-1887.338867, 36.152672, -2148.684326, -0.994952023, -0.042958423, 0.090692058, 0.000000000, 0.903741598, 0.428078443, -0.100351758, 0.425917506, -0.899179518),
            CFrame.new(-1889.595337, 25.502079, -2126.312744, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880001
        )},
        {Label = "Trick or Treat", Data = makeData(
            Vector3.new(-1858.588, 24.202, -2152.789),
            CFrame.new(-1880.230103, 36.479126, -2158.660645, -0.261842459, 0.418060958, -0.869864047, 0.000000000, 0.901310205, 0.433174133, 0.965110600, 0.113423377, -0.236001298),
            CFrame.new(-1858.587891, 25.701752, -2152.788818, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880020
        )},
        {Label = "Candy Corn Tree", Data = makeData(
            Vector3.new(-1888.203, 23.058, -2196.563),
            CFrame.new(-1897.413696, 38.960514, -2178.486572, 0.891011178, 0.262796462, -0.370185196, 0.000000000, 0.815419376, 0.578870654, 0.453981310, -0.515780210, 0.726547837),
            CFrame.new(-1888.203491, 24.558212, -2196.562988, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.879930
        )},
        {Label = "Soul Shop", Data = makeData(
            Vector3.new(-1879.392, 26.558, -2344.654),
            CFrame.new(-1876.126343, 36.922359, -2314.498535, 0.994187653, -0.030200295, 0.103339195, 0.000000000, 0.959850967, 0.280510992, -0.107661717, -0.278880566, 0.954271853),
            CFrame.new(-1879.391846, 28.058212, -2344.653564, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            31.600039
        )},
        {Label = "Soul Tree", Data = makeData(
            Vector3.new(-1837.486, 26.558, -2334.889),
            CFrame.new(-1864.238037, 44.867821, -2334.328857, 0.020951884, 0.531832874, -0.846590102, 0.000000000, 0.846775889, 0.531949699, 0.999780416, -0.011145349, 0.017741553),
            CFrame.new(-1837.485840, 28.058212, -2334.889404, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            31.599955
        )},
        {Label = "Rune 1", Data = makeData(
            Vector3.new(-2278.916, 20.627, -2164.964),
            CFrame.new(-2297.861572, 33.444126, -2158.675781, 0.314996094, 0.468070805, -0.825643539, 0.000000000, 0.869929075, 0.493176967, 0.949092984, -0.155348822, 0.274024248),
            CFrame.new(-2278.915527, 22.127195, -2164.963867, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            22.947016
        )},
        {Label = "Rune 2", Data = makeData(
            Vector3.new(-1940.854, 23.870, -2161.581),
            CFrame.new(-1941.739624, 37.903503, -2142.379395, 0.998939037, 0.025153507, -0.038574766, 0.000000000, 0.837649822, 0.546207607, 0.046051182, -0.545628130, 0.836761177),
            CFrame.new(-1940.854492, 25.369678, -2161.580566, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            22.947010
        )}
    }
    registerRuneLocations("Halloween", HalloweenList)
    createGrid(HalloweenTeleportSection, HalloweenList, function(item)
        teleportWithData(item.Data)
    end)

    local HalloweenEnemySection = createSectionBox(State.Tabs.Halloween:GetPage(), "Enemy")
    local HalloweenEnemyList = {
        {
            Label = "Boss Enemy",
            Cycle = {
                makeData(
                    Vector3.new(-2092.624, 19.919, -2027.826),
                    CFrame.new(-2076.988770, 33.313568, -2052.577881, -0.845453262, -0.201025277, 0.494770318, 0.000000000, 0.926450491, 0.376417011, -0.534049392, 0.318242997, -0.783270597),
                    CFrame.new(-2092.623535, 21.418791, -2027.826416, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    31.600105
                ),
                makeData(
                    Vector3.new(-2217.817, 19.919, -2027.757),
                    CFrame.new(-2211.418213, 29.768099, -2057.554688, -0.977711976, -0.055472907, 0.202489734, 0.000000000, 0.964462817, 0.264218599, -0.209950805, 0.258329690, -0.942966819),
                    CFrame.new(-2217.816895, 21.418791, -2027.756836, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    31.600096
                ),
                makeData(
                    Vector3.new(-2220.480, 19.919, -2260.211),
                    CFrame.new(-2228.719482, 29.595963, -2230.820068, 0.962882936, 0.069847323, -0.260725409, 0.000000000, 0.965938628, 0.258771241, 0.269919187, -0.249166414, 0.930085897),
                    CFrame.new(-2220.480469, 21.418791, -2260.210693, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    31.599941
                ),
                makeData(
                    Vector3.new(-2090.565, 19.734, -2263.877),
                    CFrame.new(-2086.972412, 32.797325, -2234.693604, 0.992502272, -0.044726547, 0.113747679, 0.000000000, 0.930640101, 0.365935594, -0.122225188, -0.363191903, 0.923662603),
                    CFrame.new(-2090.566895, 21.233759, -2263.881348, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    31.600012
                ),
                makeData(
                    Vector3.new(-2165.413, 19.919, -2141.760),
                    CFrame.new(-2171.543213, 40.356079, -2107.064209, 0.984748423, 0.082368985, -0.153250992, 0.000000000, 0.880832613, 0.473427862, 0.173984230, -0.466207355, 0.867398560),
                    CFrame.new(-2165.413086, 21.418962, -2141.760254, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    40.000107
                )
            }
        },
        {
            Label = "10 HP",
            Cycle = {
                makeData(
                    Vector3.new(-2258.677, 19.419, -2138.837),
                    CFrame.new(-2246.477051, 36.128731, -2150.935303, -0.704145789, -0.470645428, 0.531668782, 0.000000000, 0.748770833, 0.662829041, -0.710055530, 0.466728270, -0.527243733),
                    CFrame.new(-2258.677246, 20.918791, -2138.836670, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    22.946981
                ),
                makeData(
                    Vector3.new(-2305.207, 19.419, -2149.039),
                    CFrame.new(-2286.398193, 33.015614, -2143.894043, 0.263863444, -0.508480787, 0.819648445, 0.000000000, 0.849764049, 0.527163446, -0.964560032, -0.139099166, 0.224221677),
                    CFrame.new(-2305.206787, 20.918793, -2149.039307, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    22.947113
                ),
                makeData(
                    Vector3.new(-2274.982, 19.419, -2178.434),
                    CFrame.new(-2288.335938, 34.517139, -2165.654297, 0.691394150, 0.428139031, -0.581954718, 0.000000000, 0.805498421, 0.592598081, 0.722477913, -0.409718841, 0.556916773),
                    CFrame.new(-2274.981934, 20.918791, -2178.433838, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    22.946920
                )
            }
        },
        {
            Label = "90 HP",
            Cycle = {
                makeData(
                    Vector3.new(-2252.533, 19.419, -2174.950),
                    CFrame.new(-2267.866455, 36.128735, -2182.702393, -0.451180369, 0.591530442, -0.668227494, 0.000000000, 0.748770595, 0.662829220, 0.892432690, 0.299055547, -0.337830663),
                    CFrame.new(-2252.532715, 20.918791, -2174.950195, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    22.946951
                ),
                makeData(
                    Vector3.new(-2231.636, 19.919, -2164.387),
                    CFrame.new(-2246.969727, 36.628754, -2172.139160, -0.451180369, 0.591530442, -0.668227494, 0.000000000, 0.748770595, 0.662829220, 0.892432690, 0.299055547, -0.337830663),
                    CFrame.new(-2231.635986, 21.418812, -2164.386963, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    22.946949
                ),
                makeData(
                    Vector3.new(-2244.742, 19.419, -2118.371),
                    CFrame.new(-2233.265625, 39.126701, -2126.329834, -0.569861412, -0.652032197, 0.500112057, 0.000000000, 0.608600736, 0.793476701, -0.821740806, 0.452171743, -0.346818060),
                    CFrame.new(-2244.741699, 20.918791, -2118.371338, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    22.947025
                )
            }
        },
        {
            Label = "700 HP",
            Cycle = {
                makeData(
                    Vector3.new(-2207.332, 19.419, -2097.701),
                    CFrame.new(-2213.806152, 28.429708, -2107.057617, -0.822337270, 0.313481271, -0.474858880, 0.000000000, 0.834549308, 0.550933301, 0.569000423, 0.453052998, -0.686280966),
                    CFrame.new(-2207.332275, 20.918791, -2097.701416, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633175
                ),
                makeData(
                    Vector3.new(-2231.430, 19.419, -2088.590),
                    CFrame.new(-2220.060547, 28.429712, -2088.160889, 0.037680522, -0.550542355, 0.833956480, 0.000000000, 0.834549189, 0.550933599, -0.999289870, -0.020759465, 0.031446245),
                    CFrame.new(-2231.429932, 20.918791, -2088.589600, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633072
                ),
                makeData(
                    Vector3.new(-2221.462, 19.419, -2135.914),
                    CFrame.new(-2232.647949, 28.621281, -2134.725830, 0.105579346, 0.561827600, -0.820489287, 0.000000000, 0.825100839, 0.564985394, 0.994410813, -0.059650790, 0.087113619),
                    CFrame.new(-2221.462158, 20.918791, -2135.913574, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633085
                )
            }
        },
        {
            Label = "5K HP",
            Cycle = {
                makeData(
                    Vector3.new(-2194.794, 19.419, -2163.864),
                    CFrame.new(-2190.353271, 28.557690, -2153.482422, 0.919406533, -0.220378891, 0.325767905, 0.000000000, 0.828275740, 0.560320675, -0.393308520, -0.515162468, 0.761522174),
                    CFrame.new(-2194.794434, 20.918791, -2163.864258, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633019
                ),
                makeData(
                    Vector3.new(-2207.905, 19.419, -2190.938),
                    CFrame.new(-2204.409912, 28.365398, -2201.809570, -0.952025414, -0.167152360, 0.256335050, 0.000000000, 0.837644458, 0.546215832, -0.306018889, 0.520011365, -0.797458887),
                    CFrame.new(-2207.904541, 20.918791, -2190.937744, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633084
                ),
                makeData(
                    Vector3.new(-2236.336, 19.419, -2199.881),
                    CFrame.new(-2224.794922, 28.170973, -2200.123047, -0.020951571, -0.531837761, 0.846587121, 0.000000000, 0.846773028, 0.531954527, -0.999780536, 0.011145283, -0.017741224),
                    CFrame.new(-2236.336426, 20.918791, -2199.881104, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633011
                )
            }
        },
        {
            Label = "45K HP",
            Cycle = {
                makeData(
                    Vector3.new(-2207.899, 19.419, -2062.469),
                    CFrame.new(-2201.087158, 29.243635, -2070.845215, -0.775832117, -0.385273993, 0.499648482, 0.000000000, 0.791911960, 0.610635400, -0.630939484, 0.473750561, -0.614390671),
                    CFrame.new(-2207.898926, 20.918791, -2062.469238, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633056
                ),
                makeData(
                    Vector3.new(-2180.757, 19.419, -2071.824),
                    CFrame.new(-2181.059326, 28.170982, -2060.283936, 0.999657512, 0.013920069, -0.022158127, 0.000000000, 0.846772432, 0.531955242, 0.026167745, -0.531773031, 0.846482515),
                    CFrame.new(-2180.757324, 20.918791, -2071.824219, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633181
                ),
                makeData(
                    Vector3.new(-2185.230, 19.419, -2129.082),
                    CFrame.new(-2175.940186, 29.364979, -2123.770020, 0.496360302, -0.537829638, 0.681443870, 0.000000000, 0.784968138, 0.619536161, -0.868116617, -0.307513148, 0.389627010),
                    CFrame.new(-2185.230469, 20.918791, -2129.081787, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633134
                )
            }
        },
        {
            Label = "385K HP",
            Cycle = {
                makeData(
                    Vector3.new(-2228.725, 19.419, -2057.630),
                    CFrame.new(-2218.619141, 29.955250, -2059.068115, -0.140910402, -0.656219482, 0.741296470, 0.000000000, 0.748767376, 0.662832975, -0.990022361, 0.093400061, -0.105509110),
                    CFrame.new(-2228.725342, 20.918791, -2057.629639, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633125
                ),
                makeData(
                    Vector3.new(-2192.420, 19.419, -2039.989),
                    CFrame.new(-2185.999268, 28.810690, -2049.063721, -0.816344798, -0.334339857, 0.470954448, 0.000000000, 0.815413952, 0.578878403, -0.577564895, 0.472564369, -0.665658891),
                    CFrame.new(-2192.419922, 20.918791, -2039.988647, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633188
                ),
                makeData(
                    Vector3.new(-2211.655, 19.419, -2008.097),
                    CFrame.new(-2206.555908, 28.810690, -2017.974976, -0.888621628, -0.265497416, 0.373982310, 0.000000000, 0.815413892, 0.578878403, -0.458641082, 0.514403880, -0.724594414),
                    CFrame.new(-2211.654541, 20.918791, -2008.096558, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633095
                )
            }
        },
        {
            Label = "3.25M HP",
            Cycle = {
                makeData(
                    Vector3.new(-2231.901, 19.419, -2230.503),
                    CFrame.new(-2228.343994, 28.557749, -2219.785889, 0.949092925, -0.176500261, 0.260902852, 0.000000000, 0.828272939, 0.560324967, -0.314996243, -0.531800449, 0.786107957),
                    CFrame.new(-2231.900879, 20.918791, -2230.502930, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633051
                ),
                makeData(
                    Vector3.new(-2203.733, 19.419, -2248.818),
                    CFrame.new(-2211.306152, 28.557749, -2240.442139, 0.741748571, 0.375797659, -0.555504501, 0.000000000, 0.828272939, 0.560324967, 0.670678079, -0.415620238, 0.614370227),
                    CFrame.new(-2203.732910, 20.918791, -2248.817871, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633069
                ),
                makeData(
                    Vector3.new(-2223.095, 19.419, -2284.687),
                    CFrame.new(-2226.492432, 29.955282, -2275.061279, 0.942993879, 0.220598251, -0.249196544, 0.000000000, 0.748765111, 0.662835360, 0.332810014, -0.625049710, 0.706080973),
                    CFrame.new(-2223.095215, 20.918791, -2284.687256, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633000
                )
            }
        },
        {
            Label = "30M HP",
            Cycle = {
                makeData(
                    Vector3.new(-2189.242, 19.419, -2229.958),
                    CFrame.new(-2194.424316, 27.168848, -2240.909668, -0.903928638, 0.196070403, -0.380091250, 0.000000000, 0.888721347, 0.458447754, 0.427683204, 0.414404064, -0.803340793),
                    CFrame.new(-2189.242432, 20.918791, -2229.957764, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633024
                ),
                makeData(
                    Vector3.new(-2180.613, 19.419, -2198.075),
                    CFrame.new(-2185.604492, 27.305222, -2209.037354, -0.910101473, 0.194119260, -0.366105229, 0.000000000, 0.883489609, 0.468450934, 0.414385468, 0.426337898, -0.804065168),
                    CFrame.new(-2180.613281, 20.918791, -2198.075439, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633130
                ),
                makeData(
                    Vector3.new(-2137.502, 19.419, -2222.558),
                    CFrame.new(-2147.530273, 28.747879, -2217.658447, 0.439008266, 0.515972853, -0.735556841, 0.000000000, 0.818665266, 0.574271142, 0.898483038, -0.252109766, 0.359400809),
                    CFrame.new(-2137.502441, 20.918791, -2222.558105, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633000
                )
            }
        },
        {
            Label = "250M HP",
            Cycle = {
                makeData(
                    Vector3.new(-2149.782, 19.419, -2189.356),
                    CFrame.new(-2159.362793, 28.429836, -2195.492188, -0.539349318, 0.463938832, -0.702753901, 0.000000000, 0.834543169, 0.550942540, 0.842082083, 0.297150493, -0.450110286),
                    CFrame.new(-2149.781982, 20.918791, -2189.355713, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633197
                ),
                makeData(
                    Vector3.new(-2138.045, 19.419, -2164.942),
                    CFrame.new(-2148.999268, 28.747896, -2162.804688, 0.191505298, 0.563643515, -0.803512037, 0.000000000, 0.818664193, 0.574272454, 0.981491506, -0.109976217, 0.156778544),
                    CFrame.new(-2138.044922, 20.918791, -2164.942139, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633095
                ),
                makeData(
                    Vector3.new(-2123.563, 19.419, -2201.450),
                    CFrame.new(-2117.015381, 29.121317, -2192.749023, 0.799048662, -0.361759901, 0.480261505, 0.000000000, 0.798749983, 0.601663232, -0.601266444, -0.480758190, 0.638240039),
                    CFrame.new(-2123.562744, 20.918791, -2201.450195, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633040
                )
            }
        },
        {
            Label = "1.75B HP",
            Cycle = {
                makeData(
                    Vector3.new(-2129.188, 19.419, -2136.672),
                    CFrame.new(-2123.617920, 28.105829, -2146.830078, -0.876816213, -0.253479838, 0.408584446, 0.000000000, 0.849756002, 0.527176261, -0.480825603, 0.462236702, -0.745079875),
                    CFrame.new(-2129.188232, 20.918791, -2136.672363, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633087
                ),
                makeData(
                    Vector3.new(-2152.717, 19.419, -2112.046),
                    CFrame.new(-2154.056885, 30.346006, -2129.067383, -0.996916413, 0.037928555, -0.068695322, 0.000000000, 0.875428498, 0.483347863, 0.078470513, 0.481857419, -0.872729063),
                    CFrame.new(-2152.717041, 20.918791, -2112.045654, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    40.000021
                ),
                makeData(
                    Vector3.new(-2145.851, 19.419, -2058.127),
                    CFrame.new(-2150.084473, 33.681152, -2072.255127, -0.957919359, 0.187821642, -0.217056185, 0.000000000, 0.756195247, 0.654345989, 0.287037194, 0.626810670, -0.724374175),
                    CFrame.new(-2145.851074, 20.918791, -2058.126953, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    19.503969
                )
            }
        },
        {
            Label = "15B HP",
            Cycle = {
                makeData(
                    Vector3.new(-2089.392, 19.419, -2162.511),
                    CFrame.new(-2100.067627, 30.202538, -2156.944580, 0.462377846, 0.541447937, -0.702168763, 0.000000000, 0.791905105, 0.610644281, 0.886683047, -0.282348394, 0.366159350),
                    CFrame.new(-2089.392334, 20.918791, -2162.511475, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    15.203294
                ),
                makeData(
                    Vector3.new(-2115.548, 19.419, -2176.924),
                    CFrame.new(-2111.564209, 31.123959, -2166.382568, 0.935439944, -0.237277672, 0.262014121, 0.000000000, 0.741229892, 0.671251297, -0.353485614, -0.627915263, 0.693376064),
                    CFrame.new(-2115.547607, 20.918791, -2176.924072, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    15.203165
                ),
                makeData(
                    Vector3.new(-2076.947, 19.419, -2202.903),
                    CFrame.new(-2085.948730, 28.860523, -2193.573730, 0.719590187, 0.362734884, -0.592126191, 0.000000000, 0.852717519, 0.522372425, 0.694398999, -0.375894070, 0.613607168),
                    CFrame.new(-2076.946533, 20.918791, -2202.902588, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    15.203232
                )
            }
        },
        {
            Label = "120B HP",
            Cycle = {
                makeData(
                    Vector3.new(-2107.324, 19.419, -2241.319),
                    CFrame.new(-2111.750000, 27.842493, -2230.440918, 0.926269829, 0.191392824, -0.324642897, 0.000000000, 0.861439347, 0.507860482, 0.376861036, -0.470415831, 0.797925234),
                    CFrame.new(-2107.324219, 20.918791, -2241.319092, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633043
                ),
                makeData(
                    Vector3.new(-2078.336, 19.419, -2248.928),
                    CFrame.new(-2089.214111, 28.171133, -2245.062988, 0.334803939, 0.501265705, -0.797896743, 0.000000000, 0.846765399, 0.531966686, 0.942287803, -0.178104535, 0.283500403),
                    CFrame.new(-2078.336426, 20.918789, -2248.927979, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633000
                ),
                makeData(
                    Vector3.new(-2098.147, 19.419, -2281.505),
                    CFrame.new(-2094.572754, 28.684834, -2270.885010, 0.947764993, -0.181700021, 0.262157619, 0.000000000, 0.821889400, 0.569647074, -0.318969458, -0.539891541, 0.778958023),
                    CFrame.new(-2098.146729, 20.918791, -2281.504639, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633094
                )
            }
        },
        {
            Label = "1T HP",
            Cycle = {
                makeData(
                    Vector3.new(-2080.492, 19.419, -2047.783),
                    CFrame.new(-2080.809814, 28.621496, -2059.027344, -0.999599993, 0.015979681, -0.023335664, 0.000000000, 0.825090170, 0.565001190, 0.028282562, 0.564775169, -0.824760079),
                    CFrame.new(-2080.491699, 20.918791, -2047.783325, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633079
                ),
                makeData(
                    Vector3.new(-2110.653, 19.419, -2016.738),
                    CFrame.new(-2108.893311, 29.121403, -2027.483887, -0.986857653, -0.097225048, 0.129070818, 0.000000000, 0.798744977, 0.601669788, -0.161592036, 0.593762457, -0.788247585),
                    CFrame.new(-2110.652832, 20.918791, -2016.737671, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633045
                ),
                makeData(
                    Vector3.new(-2108.735, 19.419, -2066.310),
                    CFrame.new(-2116.610840, 28.747992, -2074.218262, -0.708577931, 0.405230552, -0.577672660, 0.000000000, 0.818659306, 0.574279726, 0.705632687, 0.406921953, -0.580083787),
                    CFrame.new(-2108.735352, 20.918791, -2066.309814, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633166
                )
            }
        },
        {
            Label = "15T HP",
            Cycle = {
                makeData(
                    Vector3.new(-2117.660, 19.419, -2100.124),
                    CFrame.new(-2120.635742, 27.709517, -2088.683350, 0.967800140, 0.125383437, -0.218270510, 0.000000000, 0.867115974, 0.498106539, 0.251720130, -0.482067585, 0.839194834),
                    CFrame.new(-2117.660156, 20.918791, -2100.124268, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633146
                ),
                makeData(
                    Vector3.new(-2091.368, 19.419, -2129.343),
                    CFrame.new(-2099.360352, 29.243811, -2122.085693, 0.672246516, 0.452079922, -0.586266637, 0.000000000, 0.791901827, 0.610648572, 0.740327477, -0.410506368, 0.532353163),
                    CFrame.new(-2091.367676, 20.918791, -2129.343262, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633089
                ),
                makeData(
                    Vector3.new(-2086.756, 19.419, -2081.335),
                    CFrame.new(-2083.765625, 28.365601, -2092.356445, -0.965111077, -0.143025547, 0.219326854, 0.000000000, 0.837634504, 0.546231031, -0.261840761, 0.527173638, -0.808410347),
                    CFrame.new(-2086.755615, 20.918791, -2081.335205, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    13.633149
                )
            }
        }
    }

    local function cycleEnemyTeleport(item)
        local list = item and item.Cycle or nil
        if type(list) ~= "table" or #list == 0 then
            return
        end
        item.Index = (item.Index or 0) + 1
        if item.Index > #list then
            item.Index = 1
        end
        teleportWithData(list[item.Index])
    end

    createGrid(HalloweenEnemySection, HalloweenEnemyList, cycleEnemyTeleport)

    State.InitHalloween = function()
        local HalloweenAutomationSection = createSectionBox(State.Tabs.Halloween:GetPage(), "Automation")
        setupAutoBuyGroup(HalloweenAutomationSection, {
            GroupKey = "Halloween",
            DisplayName = "Auto Buy Shop",
            ModeToggleName = "Mode: Upgrade All",
            SpeedLabel = "Click Speed (sec)",
            CooldownKey = "HalloweenAutoBuy",
            DefaultCooldown = 0.6,
            ResetMaxedOnPrompt = {
                Match = "Flesh Has Been Consumed! Fleshify",
                ShopKey = "Flesh",
                OnReset = function()
                    notify("Auto Buy Shop", "List item Flesh Shop tereset", 3)
                end
            },
            ResetMaxedOnPopup = {
                Match = "Refined CandyGain",
                ShopKey = "Candy Corn",
                OnReset = function()
                    notify("Auto Buy Shop", "List item Candy Corn Shop tereset", 3)
                end
            },
            Shops = {
                {
                    Key = "Flesh",
                    DisplayName = "Flesh Shop",
                    ShopName = "Flesh",
                },
                {
                    Key = "Candy Corn",
                    DisplayName = "Candy Corn Shop",
                    ShopName = "Candy Corn",
                },
                {
                    Key = "Refined Candy",
                    DisplayName = "Refined Candy Shop",
                    ShopName = "Refined Candy",
                },
                {
                    Key = "Factorized Candy",
                    DisplayName = "Factorized Candy Shop",
                    ShopName = "Factorized Candy",
                }
            }
        })
    end
end

do
    local ThanksgivingTeleportSection = createSectionBox(State.Tabs.Thanksgiving:GetPage(), "Teleport")
    createButton(ThanksgivingTeleportSection, "Home", function()
        teleportHomeWithBuy("Thanksgiving")
    end)
    local ThanksgivingList = {
        {Label = "Turkey Shop", Data = makeData(
            Vector3.new(-2282.325, 15.991, 2087.762),
            CFrame.new(-2297.520020, 25.541430, 2069.781006, -0.763789833, 0.208844021, -0.610744894, 0.000000000, 0.946209133, 0.323555887, 0.645465076, 0.247128695, -0.722704887),
            CFrame.new(-2282.324707, 17.491360, 2087.761963, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880032
        )},
        {Label = "Turkey Up Damage", Data = makeData(
            Vector3.new(-2286.388, 16.206, 2068.115),
            CFrame.new(-2304.635010, 32.222630, 2059.435791, -0.429556966, 0.526895583, -0.733390629, 0.000000000, 0.812135458, 0.583468914, 0.903039694, 0.250633150, -0.348858476),
            CFrame.new(-2286.388184, 17.705923, 2068.115479, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880079
        )},
        {Label = "Pre Level", Data = makeData(
            Vector3.new(-2280.226, 16.397, 2097.637),
            CFrame.new(-2295.303467, 30.045383, 2082.013428, -0.719575763, 0.339061320, -0.606010079, 0.000000000, 0.872692823, 0.488269746, 0.694413960, 0.351347089, -0.627968609),
            CFrame.new(-2280.225830, 17.897234, 2097.637207, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880014
        )},
        {Label = "Next Level", Data = makeData(
            Vector3.new(-2287.233, 16.397, 2104.400),
            CFrame.new(-2302.310303, 30.045383, 2088.776367, -0.719575763, 0.339061320, -0.606010079, 0.000000000, 0.872692823, 0.488269746, 0.694413960, 0.351347089, -0.627968609),
            CFrame.new(-2287.232666, 17.897234, 2104.400146, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880014
        )},
        {Label = "Token Shop", Data = makeData(
            Vector3.new(-2316.901, 15.491, 2040.879),
            CFrame.new(-2323.509277, 26.616344, 2062.849609, 0.957624197, 0.111422241, -0.265595615, 0.000000000, 0.922140598, 0.386854947, 0.288020730, -0.370461643, 0.883064151),
            CFrame.new(-2316.901367, 16.991394, 2040.878906, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880032
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(-2341.132, 16.370, 2099.476),
            CFrame.new(-2354.765625, 31.576828, 2083.814697, -0.754245102, 0.361739188, -0.547959208, 0.000000000, 0.834549308, 0.550933540, 0.656593144, 0.415538937, -0.629454553),
            CFrame.new(-2341.132324, 17.869602, 2099.475586, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880079
        )}
    }
    registerRuneLocations("Thanksgiving", ThanksgivingList)
    createGrid(ThanksgivingTeleportSection, ThanksgivingList, function(item)
        teleportWithData(item.Data)
    end)

    local ThanksgivingAutomationSection = createSectionBox(State.Tabs.Thanksgiving:GetPage(), "Automation")
end
    stepWorld("Thanksgiving")

do
    local Event3MTeleportSection = createSectionBox(State.Tabs.Event3M:GetPage(), "Teleport")
    createButton(Event3MTeleportSection, "Home", function()
        teleportHomeWithBuy("3M Event")
    end)
    local Event3MList = {
        {Label = "3M Shop", Data = makeData(
            Vector3.new(-376.230, 16.793, 2042.069),
            CFrame.new(-388.213837, 25.225172, 2055.806641, 0.753568947, 0.233635798, -0.614449501, 0.000000000, 0.934710324, 0.355410486, 0.657368898, -0.267826319, 0.704368651),
            CFrame.new(-376.229614, 18.293245, 2042.068604, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504023
        )},
        {Label = "Potion Shop", Data = makeData(
            Vector3.new(-294.845, 15.991, 2070.316),
            CFrame.new(-310.442261, 28.236837, 2065.660645, -0.286014646, 0.527920187, -0.799684823, 0.000000000, 0.834547877, 0.550935388, 0.958225250, 0.157575592, -0.238692909),
            CFrame.new(-294.845215, 17.491394, 2070.316162, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.504005
        )},
        {Label = "Elevation", Data = makeData(
            Vector3.new(-308.799, 15.991, 2099.406),
            CFrame.new(-306.161530, 30.086281, 2084.749756, -0.984197199, -0.114348486, 0.135204837, 0.000000000, 0.763541162, 0.645759225, -0.177076042, 0.635554433, -0.751475036),
            CFrame.new(-308.798553, 17.491394, 2099.406494, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503975
        )},
        {Label = "Passive", Data = makeData(
            Vector3.new(-414.549, 16.794, 2074.148),
            CFrame.new(-396.920258, 23.249952, 2075.702393, 0.087842517, -0.268621266, 0.959232211, 0.000000000, 0.962954581, 0.269663692, -0.996134341, -0.023687938, 0.084588356),
            CFrame.new(-414.548767, 18.294146, 2074.147949, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            18.377722
        )},
        {Label = "Tree 1", Data = makeData(
            Vector3.new(-376.771, 16.614, 2174.095),
            CFrame.new(-376.742828, 55.848480, 2160.823242, -0.999997795, -0.001967276, 0.000691928, 0.000000000, 0.331794232, 0.943351805, -0.002085411, 0.943349719, -0.331793547),
            CFrame.new(-376.770508, 18.114405, 2174.094971, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            40.000000
        )},
        {Label = "Tree 2", Data = makeData(
            Vector3.new(-377.774, 16.614, 2208.942),
            CFrame.new(-378.372223, 51.552864, 2186.999023, -0.999629200, 0.022765476, -0.014944974, 0.000000000, 0.548788190, 0.835961521, 0.027232684, 0.835651517, -0.548584640),
            CFrame.new(-377.774414, 18.114405, 2208.942383, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            39.999989
        )},
        {Label = "Minions", Data = makeData(
            Vector3.new(-311.161, 16.598, 2046.919),
            CFrame.new(-322.367065, 26.889526, 2058.532227, 0.719588339, 0.332193792, -0.609786689, 0.000000000, 0.878147960, 0.478389114, 0.694400847, -0.344243228, 0.631905079),
            CFrame.new(-311.160583, 18.097818, 2046.919312, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            18.377682
        )},
        {Label = "Rune 1", Data = makeData(
            Vector3.new(-364.514, 16.611, 2102.254),
            CFrame.new(-380.290161, 30.746696, 2116.761719, 0.676882327, 0.373822302, -0.634103537, 0.000000000, 0.861446917, 0.507847726, 0.736091316, -0.343753159, 0.583098114),
            CFrame.new(-364.513672, 18.111444, 2102.254150, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.880047
        )},
        {Label = "Rune 2", Data = makeData(
            Vector3.new(-343.613, 16.582, 2064.344),
            CFrame.new(-359.120483, 31.317451, 2078.604736, 0.676882267, 0.391566694, -0.623302400, 0.000000000, 0.846773267, 0.531953990, 0.736091256, -0.360070229, 0.573165834),
            CFrame.new(-343.612732, 18.082438, 2064.344482, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.879929
        )}
    }
    registerRuneLocations("3M Event", Event3MList)
    createGrid(Event3MTeleportSection, Event3MList, function(item)
        teleportWithData(item.Data)
    end)

    local Event3MAutomationSection = createSectionBox(State.Tabs.Event3M:GetPage(), "Automation")
    setupAutoBuyGroup(Event3MAutomationSection, {
        GroupKey = "3M Event",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Mode: Upgrade All",
        SpeedLabel = "Click Speed (sec)",
        CooldownKey = "3MEventAutoBuy",
        DefaultCooldown = 0.6,
        Shops = {
            {
                Key = "3M Coins",
                DisplayName = "3M Coins Shop",
                ShopName = "3M Coins",
            }
        }
    })
end
    stepWorld("3M Event")

do
    local ChristmasTeleportSection = createSectionBox(State.Tabs.Christmas:GetPage(), "Teleport")
    createButton(ChristmasTeleportSection, "Home", function()
        teleportHomeWithBuy("Christmas Event")
    end)
    local ChristmasList = {
        {Label = "Candy Cane Shop", Data = makeData(
            Vector3.new(-4078.632, 14.753, -22.723),
            CFrame.new(-4065.713623, 22.292000, -17.451403, 0.377832770, -0.367797047, 0.849686980, 0.000000000, 0.917713642, 0.397243112, -0.925873935, -0.150091469, 0.346742243),
            CFrame.new(-4078.631592, 16.252632, -22.722994, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203208
        )},
        {Label = "Milk Shop", Data = makeData(
            Vector3.new(-4030.130, 14.653, 33.750),
            CFrame.new(-4024.478027, 22.738323, 21.267654, -0.910975277, -0.178671494, 0.371753365, 0.000000000, 0.901305556, 0.433183998, -0.412460983, 0.394619912, -0.821067035),
            CFrame.new(-4030.129883, 16.152540, 33.750500, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203205
        )},
        {Label = "Cookies Shop", Data = makeData(
            Vector3.new(-3950.000, 15.153, -16.744),
            CFrame.new(-3956.110352, 20.709223, -25.940693, -0.832916617, 0.190834999, -0.519453526, 0.000000000, 0.938660860, 0.344841897, 0.553398550, 0.287224561, -0.781826198),
            CFrame.new(-3950.000244, 16.653000, -16.744415, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            11.762563
        )},
        {Label = "Boss Attack", Data = makeData(
            Vector3.new(-3956.069, 15.153, -22.492),
            CFrame.new(-3969.000244, 34.169048, -34.533123, -0.681481421, 0.515227735, -0.519734144, 0.000000000, 0.710178971, 0.704021275, 0.731835485, 0.479777426, -0.483973742),
            CFrame.new(-3956.069336, 16.653000, -22.491856, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.879961
        )},
        {Label = "Damage Up", Data = makeData(
            Vector3.new(-3948.530, 15.653, -34.233),
            CFrame.new(-3961.460449, 34.669235, -46.274586, -0.681481421, 0.515227735, -0.519734144, 0.000000000, 0.710178971, 0.704021275, 0.731835485, 0.479777426, -0.483973742),
            CFrame.new(-3948.529541, 17.153187, -34.233318, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.879961
        )},
        {Label = "Christmas Rank", Data = makeData(
            Vector3.new(-3992.259, 14.653, 4.077),
            CFrame.new(-3993.103760, 22.842583, -12.366984, -0.998683393, 0.019310094, -0.047525570, 0.000000000, 0.926447392, 0.376424432, 0.051298730, 0.375928819, -0.925227523),
            CFrame.new(-3992.259033, 16.152540, 4.076718, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772608
        )},
        {Label = "Next Level", Data = makeData(
            Vector3.new(-3952.720, 15.653, -1.995),
            CFrame.new(-3955.827637, 27.301355, -7.065711, -0.852635741, 0.450792700, -0.264193535, 0.000000000, 0.505627990, 0.862751663, 0.522505760, 0.735612929, -0.431116492),
            CFrame.new(-3952.719971, 17.153187, -1.994678, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            11.762580
        )},
        {Label = "Pre Level", Data = makeData(
            Vector3.new(-3945.432, 15.653, -6.462),
            CFrame.new(-3948.539551, 27.301355, -11.533158, -0.852635741, 0.450792700, -0.264193535, 0.000000000, 0.505627990, 0.862751663, 0.522505760, 0.735612929, -0.431116492),
            CFrame.new(-3945.431885, 17.153187, -6.462125, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            11.762580
        )},
        {Label = "Christmas Tree", Data = makeData(
            Vector3.new(-4024.671, 14.653, -72.131),
            CFrame.new(-4024.057861, 37.363960, -48.716015, 0.999657154, -0.017577140, 0.019409774, 0.000000000, 0.741233408, 0.671247482, -0.026185781, -0.671017349, 0.740979195),
            CFrame.new(-4024.671143, 16.152540, -72.130959, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            31.600000
        )},
        {Label = "Rune", Data = makeData(
            Vector3.new(-4034.828, 15.620, -7.132),
            CFrame.new(-4022.731445, 23.859962, -13.408045, -0.460517138, -0.393522859, 0.795653045, 0.000000000, 0.896358073, 0.443330735, -0.887650728, 0.204161406, -0.412788332),
            CFrame.new(-4034.827881, 17.119917, -7.132341, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203171
        )},
        {Label = "Rune II", Data = makeData(
            Vector3.new(-4013.487, 15.735, -30.656),
            CFrame.new(-4012.548828, 30.235590, -18.574661, 0.996998250, -0.056637645, 0.052789222, 0.000000000, 0.681817174, 0.731522739, -0.077424310, -0.729326904, 0.679770529),
            CFrame.new(-4013.487061, 17.234526, -30.655954, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772608
        )}
    }
    local SantaHouseData = makeData(
        Vector3.new(-4078.338, 14.653, -62.542),
        CFrame.new(-4069.680664, 25.191797, -47.583694, 0.865496933, -0.232152030, 0.443869978, 0.000000000, 0.886119723, 0.463456601, -0.500914276, -0.401120275, 0.766933858),
        CFrame.new(-4078.337891, 16.152540, -62.541973, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        19.503996
    )
    local Christmas2List = {
        {Label = "Santa Rank", Data = makeData(
            Vector3.new(-5345.309, 8.863, -30.331),
            CFrame.new(-5346.076660, 15.282122, -15.965839, 0.998574734, 0.017269555, -0.050501216, 0.000000000, 0.946205258, 0.323567301, 0.053372376, -0.323106140, 0.944856524),
            CFrame.new(-5345.309082, 10.362863, -30.330683, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203191
        )},
        {Label = "Christmas Spirit Shop", Data = makeData(
            Vector3.new(-5365.947, 9.013, -23.335),
            CFrame.new(-5347.872559, 17.752674, -22.198046, 0.062781319, -0.370464027, 0.926722765, 0.000000000, 0.928554535, 0.371196270, -0.998027325, -0.023304192, 0.058295876),
            CFrame.new(-5365.947266, 10.512862, -23.335049, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503916
        )},
        {Label = "Milestone", Data = makeData(
            Vector3.new(-5279.860, 9.013, -6.832),
            CFrame.new(-5296.197266, 13.841234, -12.985852, -0.352486104, 0.175255567, -0.919260025, 0.000000000, 0.982307374, 0.187275469, 0.935817003, 0.066012003, -0.346249729),
            CFrame.new(-5279.859863, 10.512862, -6.832094, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            17.772381
        )},
        {Label = "Christmas Miracle", Data = makeData(
            Vector3.new(-5326.094, 9.263, 59.700),
            CFrame.new(-5320.421875, 16.022598, 41.795265, -0.953299105, -0.081449270, 0.290838182, 0.000000000, 0.962951541, 0.269674689, -0.302027851, 0.257080644, -0.917980850),
            CFrame.new(-5326.094238, 10.762862, 59.699566, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            19.503962
        )},
        {Label = "Gingerbread Shop", Data = makeData(
            Vector3.new(-5292.908, 9.764, 11.415),
            CFrame.new(-5288.702148, 18.611965, -1.212794, -0.948768973, -0.152724087, 0.276609242, 0.000000000, 0.875427544, 0.483349323, -0.315970421, 0.458586842, -0.830578625),
            CFrame.new(-5292.907715, 11.263508, 11.414659, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            15.203262
        )},
        {Label = "Tree 1", Data = makeData(
            Vector3.new(-5404.420, 8.763, 6.664),
            CFrame.new(-5392.407227, 28.919094, 0.526898, -0.454932183, -0.721633732, 0.521805823, 0.000000000, 0.585952282, 0.810345471, -0.890526056, 0.368652225, -0.266568571),
            CFrame.new(-5404.420410, 10.262862, 6.663990, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            23.022497
        )},
        {Label = "Tree 2", Data = makeData(
            Vector3.new(-5452.540, 8.763, 3.001),
            CFrame.new(-5434.297852, 27.170788, 2.408738, -0.032467175, -0.679220676, 0.733215630, 0.000000000, 0.733602345, 0.679579020, -0.999472737, 0.022064012, -0.023817999),
            CFrame.new(-5452.540039, 10.262862, 3.001330, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            24.879841
        )},
        {Label = "Rune 1", Data = makeData(
            Vector3.new(-5330.278, 9.921, -4.371),
            CFrame.new(-5326.450195, 17.671034, -15.866415, -0.948768973, -0.144858286, 0.280808926, 0.000000000, 0.888717949, 0.458454609, -0.315970838, 0.434967518, -0.843187928),
            CFrame.new(-5330.278320, 11.420886, -4.371168, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633033
        )},
        {Label = "Rune 2", Data = makeData(
            Vector3.new(-5312.343, 9.921, 32.681),
            CFrame.new(-5317.883301, 22.096531, 26.262596, -0.756988525, 0.511679411, -0.406389534, 0.000000000, 0.621934533, 0.783069193, 0.653428078, 0.592774391, -0.470797360),
            CFrame.new(-5312.342773, 11.420887, 32.681015, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.633156
        )},
        {Label = "Claim", Data = makeData(
            Vector3.new(-5294.780, 9.663, -30.830),
            CFrame.new(-5306.954102, 17.276363, -30.306751, 0.042931765, 0.447980076, -0.893012166, 0.000000000, 0.893836260, 0.448393494, 0.999077976, -0.019250324, 0.038373969),
            CFrame.new(-5294.779785, 11.163379, -30.829906, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            13.632911
        )}
    }
    local Christmas2TeleportMap = {}
    for _, item in ipairs(Christmas2List) do
        Christmas2TeleportMap[item.Label] = item.Data
    end
    local ChristmasTeleportAll = {}
    for _, item in ipairs(ChristmasList) do
        ChristmasTeleportAll[#ChristmasTeleportAll + 1] = item
    end
    for _, item in ipairs(Christmas2List) do
        ChristmasTeleportAll[#ChristmasTeleportAll + 1] = item
    end
    registerRuneLocations("Christmas Event", ChristmasTeleportAll)
    createGrid(ChristmasTeleportSection, ChristmasList, function(item)
        teleportWithData(item.Data)
    end)

    local ChristmasCandyList = {
        {
            Label = "Collect Candy Canes",
            Cycle = {
                makeData(
                    Vector3.new(-4031.825, 14.653, 65.365),
                    CFrame.new(-4028.194580, 28.156456, 77.958466, 0.960873246, -0.187083170, 0.204261020, 0.000000000, 0.737434864, 0.675418377, -0.276988566, -0.648991466, 0.708581388),
                    CFrame.new(-4031.824707, 16.152540, 65.365158, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772541,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4001.091, 14.653, 68.966),
                    CFrame.new(-4001.883057, 27.084419, 82.956070, 0.998402119, 0.034758434, -0.044554316, 0.000000000, 0.788450301, 0.615098596, 0.056508720, -0.614115715, 0.787190437),
                    CFrame.new(-4001.091309, 16.152540, 68.965683, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772556,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4011.665, 14.653, 48.927),
                    CFrame.new(-4004.060059, 27.475483, 60.321297, 0.831754923, -0.353682905, 0.427892625, 0.000000000, 0.770779133, 0.637102425, -0.555142939, -0.529913068, 0.641099393),
                    CFrame.new(-4011.664795, 16.152540, 48.927319, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772556,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4040.258, 14.653, 45.532),
                    CFrame.new(-4040.756348, 26.522381, 59.957531, 0.999403238, 0.020153644, -0.028051611, 0.000000000, 0.812131286, 0.583474696, 0.034540731, -0.583126485, 0.811646700),
                    CFrame.new(-4040.257812, 16.152540, 45.532490, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772562,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4010.129, 14.653, 24.989),
                    CFrame.new(-4009.638184, 30.375954, 35.634495, 0.998938084, -0.036870386, 0.027623810, 0.000000000, 0.599597216, 0.800301850, -0.046070602, -0.799452007, 0.598960638),
                    CFrame.new(-4010.129150, 16.152540, 24.989429, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772562,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4039.729, 14.653, 16.448),
                    CFrame.new(-4035.242920, 28.593372, 28.321060, 0.935440540, -0.247439668, 0.252437383, 0.000000000, 0.714140713, 0.700002253, -0.353484094, -0.654810488, 0.668036163),
                    CFrame.new(-4039.729492, 16.152540, 16.448345, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772591,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4035.685, 14.653, 6.067),
                    CFrame.new(-4030.241211, 29.423866, 16.559952, 0.887650132, -0.343883485, 0.306302845, 0.000000000, 0.665126085, 0.746731102, -0.460518509, -0.662835956, 0.590399206),
                    CFrame.new(-4035.685059, 16.152540, 6.067046, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772581,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4056.601, 14.653, -4.432),
                    CFrame.new(-4059.952393, 29.289581, 7.059162, 0.960003674, 0.206959650, -0.188575044, 0.000000000, 0.673513055, 0.739175379, 0.279987216, -0.709611058, 0.646575034),
                    CFrame.new(-4056.600830, 16.152540, -4.432133, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772583,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4064.906, 14.653, -36.179),
                    CFrame.new(-4067.577637, 29.622126, -24.896538, 0.973100781, 0.174601600, -0.150296554, 0.000000000, 0.652386427, 0.757886529, 0.230379611, -0.737499952, 0.634837866),
                    CFrame.new(-4064.906494, 16.152540, -36.179234, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772562,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4036.726, 14.653, -35.155),
                    CFrame.new(-4042.585938, 31.684830, -28.809164, 0.734684765, 0.592893660, -0.329720199, 0.000000000, 0.486020029, 0.873947680, 0.678408623, -0.642076075, 0.357071519),
                    CFrame.new(-4036.726074, 16.152540, -35.155239, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772526,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4047.565, 14.653, -51.404),
                    CFrame.new(-4052.677246, 32.190868, -45.702938, 0.744551420, 0.602424681, -0.287624538, 0.000000000, 0.430856168, 0.902420700, 0.667565227, -0.671898603, 0.320794523),
                    CFrame.new(-4047.565430, 16.152540, -51.404278, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772560,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4000.335, 14.653, -33.634),
                    CFrame.new(-3990.058105, 29.356964, -27.643087, 0.503614128, -0.641870439, 0.578251898, 0.000000000, 0.669328272, 0.742966890, -0.863928735, -0.374168634, 0.337083161),
                    CFrame.new(-4000.335205, 16.152540, -33.633919, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772610,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4017.158, 14.653, -72.661),
                    CFrame.new(-4022.586182, 27.552710, -60.153946, 0.917342246, 0.255360097, -0.305408776, 0.000000000, 0.767166853, 0.641447723, 0.398099601, -0.588427067, 0.703754485),
                    CFrame.new(-4017.158203, 16.152540, -72.661469, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772589,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4029.287, 14.653, -97.151),
                    CFrame.new(-4020.857178, 28.007839, -86.939674, 0.771173835, -0.424664378, 0.474290043, 0.000000000, 0.745007396, 0.667056203, -0.636624575, -0.514416277, 0.574530244),
                    CFrame.new(-4029.286621, 16.152540, -97.150551, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772610,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4047.995, 14.653, -90.113),
                    CFrame.new(-4039.268311, 28.664879, -80.994270, 0.722477794, -0.486759186, 0.491010666, 0.000000000, 0.710174739, 0.704025567, -0.691394210, -0.508642852, 0.513085425),
                    CFrame.new(-4047.994873, 16.152540, -90.113113, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772585,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4055.165, 14.653, -116.768),
                    CFrame.new(-4049.664062, 29.289635, -106.137321, 0.888131797, -0.339718133, 0.309537590, 0.000000000, 0.673509777, 0.739178360, -0.459588856, -0.656487823, 0.598165452),
                    CFrame.new(-4055.165283, 16.152540, -116.768257, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772549,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4039.300, 14.653, -133.587),
                    CFrame.new(-4046.116699, 29.423922, -123.930038, 0.816949308, 0.430648625, -0.383582443, 0.000000000, 0.665122509, 0.746734262, 0.576709330, -0.610044062, 0.543371499),
                    CFrame.new(-4039.299561, 16.152540, -133.587143, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772524,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4008.620, 14.653, -124.782),
                    CFrame.new(-4019.110107, 30.254818, -127.416946, -0.243605390, 0.769581795, -0.590254545, 0.000000000, 0.608588636, 0.793485999, 0.969874442, 0.193297461, -0.148255467),
                    CFrame.new(-4008.619873, 16.152540, -124.782066, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772503,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-3983.567, 14.653, -118.750),
                    CFrame.new(-3996.828369, 27.475578, -122.184448, -0.250708342, 0.616760254, -0.746158302, 0.000000000, 0.770774722, 0.637107790, 0.968062639, 0.159728244, -0.193239659),
                    CFrame.new(-3983.567139, 16.152540, -118.750084, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772627,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-3986.992, 14.653, -101.864),
                    CFrame.new(-3993.521973, 29.289637, -111.896065, -0.838094354, 0.403240561, -0.367416441, 0.000000000, 0.673509479, 0.739178538, 0.545525253, 0.619501352, -0.564464509),
                    CFrame.new(-3986.991943, 16.152540, -101.864082, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772598,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-3963.206, 14.653, -80.784),
                    CFrame.new(-3974.367432, 27.084522, -89.256180, -0.604591131, 0.489952773, -0.628025413, 0.000000000, 0.788445771, 0.615104377, 0.796535969, 0.371886641, -0.476687312),
                    CFrame.new(-3963.205811, 16.152540, -80.784225, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772564,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-3953.385, 14.653, -53.208),
                    CFrame.new(-3959.485352, 25.091934, -67.305771, -0.917750657, 0.199765518, -0.343260229, 0.000000000, 0.864293158, 0.502988517, 0.397157222, 0.461618036, -0.793205500),
                    CFrame.new(-3953.384766, 16.152540, -53.208473, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772554,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-3928.476, 14.653, -39.384),
                    CFrame.new(-3931.368896, 30.612972, -49.302696, -0.959998071, 0.227823988, -0.162787959, 0.000000000, 0.581371903, 0.813637972, 0.280006588, 0.781090856, -0.558115900),
                    CFrame.new(-3928.475830, 16.152540, -39.383545, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772549,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-3929.909, 14.653, -4.433),
                    CFrame.new(-3918.013672, 29.357002, -4.520770, -0.007341229, -0.742948949, 0.669307768, 0.000000000, 0.669325769, 0.742969036, -0.999972999, 0.005454306, -0.004913675),
                    CFrame.new(-3929.908936, 16.152540, -4.433441, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772528,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-3950.419, 14.653, 18.397),
                    CFrame.new(-3948.209473, 28.806583, 6.114761, -0.984197557, -0.126076490, 0.124337971, 0.000000000, 0.702180743, 0.711998761, -0.177074030, 0.700747430, -0.691084564),
                    CFrame.new(-3950.419189, 16.152540, 18.397104, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772551,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-3969.674, 14.653, 13.616),
                    CFrame.new(-3955.036377, 25.606949, 17.113464, 0.232416436, -0.517399311, 0.823578000, 0.000000000, 0.846765518, 0.531966507, -0.972616374, -0.123637758, 0.196802229),
                    CFrame.new(-3969.673584, 16.152540, 13.615784, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772659,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4066.687, 14.653, 45.234),
                    CFrame.new(-4058.164795, 28.876846, 54.252510, 0.726807237, -0.491745800, 0.479518026, 0.000000000, 0.698149443, 0.715952218, -0.686841667, -0.520359278, 0.507419944),
                    CFrame.new(-4066.687012, 16.152540, 45.234360, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772539,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4078.425, 14.653, 45.731),
                    CFrame.new(-4069.902832, 28.876846, 54.749313, 0.726807237, -0.491745800, 0.479518026, 0.000000000, 0.698149443, 0.715952218, -0.686841667, -0.520359278, 0.507419944),
                    CFrame.new(-4078.425049, 16.152540, 45.731159, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772541,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4107.604, 14.653, 6.567),
                    CFrame.new(-4103.614258, 32.672401, 11.766813, 0.793346763, -0.565860629, 0.224505201, 0.000000000, 0.368784934, 0.929514825, -0.608769894, -0.737427592, 0.292574376),
                    CFrame.new(-4107.604492, 16.152540, 6.567017, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772610,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4085.765, 14.653, 2.478),
                    CFrame.new(-4092.156250, 28.007896, 14.074261, 0.875806749, 0.321964085, -0.359585226, 0.000000000, 0.745004475, 0.667059422, 0.482661784, -0.584215164, 0.652480006),
                    CFrame.new(-4085.765381, 16.152540, 2.478019, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772604,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4115.053, 14.653, -13.229),
                    CFrame.new(-4107.369629, 28.664932, -3.215404, 0.793347061, -0.428591341, 0.432330936, 0.000000000, 0.710171580, 0.704028666, -0.608769715, -0.558539093, 0.563412488),
                    CFrame.new(-4115.053223, 16.152540, -13.228687, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772547,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4103.417, 14.653, -31.872),
                    CFrame.new(-4110.179199, 28.449429, -20.966389, 0.849898279, 0.364595979, -0.380450577, 0.000000000, 0.721990526, 0.691902936, 0.526946723, -0.588047087, 0.613618553),
                    CFrame.new(-4103.417480, 16.152540, -31.871964, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772615,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4121.744, 14.653, -39.508),
                    CFrame.new(-4131.856445, 27.629553, -30.459530, 0.666800499, 0.481252283, -0.569010854, 0.000000000, 0.763530791, 0.645771444, 0.745236218, -0.430600733, 0.509122729),
                    CFrame.new(-4121.743652, 16.152540, -39.507946, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772570,
                    10.180,
                    17.773
                ),
                makeData(
                    Vector3.new(-4103.093, 14.653, -59.913),
                    CFrame.new(-4113.999512, 25.091995, -49.096737, 0.704146147, 0.357152015, -0.613694310, 0.000000000, 0.864291191, 0.502991974, 0.710055113, -0.354179859, 0.608587265),
                    CFrame.new(-4103.092773, 16.152540, -59.912891, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
                    70.000,
                    Enum.CameraType.Custom,
                    17.772449,
                    10.180,
                    17.773
                )
            }
        }
    }

    local function cycleChristmasCandyTeleport(item)
        local list = item and item.Cycle or nil
        if type(list) ~= "table" or #list == 0 then
            return
        end
        item.Index = (item.Index or 0) + 1
        if item.Index > #list then
            item.Index = 1
        end
        teleportWithData(list[item.Index])
    end

    createButton(ChristmasTeleportSection, "Collect Candy Canes", function()
        cycleChristmasCandyTeleport(ChristmasCandyList[1])
    end)
    createButton(ChristmasTeleportSection, "Santa House", function()
        teleportWithData(SantaHouseData)
    end)
    local Christmas2TeleportGridOrder = {
        "Gingerbread Shop",
        "Christmas Spirit Shop",
        "Milestone",
        "Santa Rank",
        "Tree 1",
        "Tree 2",
        "Rune 1",
        "Rune 2",
        "Claim"
    }
    local Christmas2TeleportGridList = {}
    for _, label in ipairs(Christmas2TeleportGridOrder) do
        local data = Christmas2TeleportMap[label]
        if data then
            Christmas2TeleportGridList[#Christmas2TeleportGridList + 1] = {
                Label = label,
                Data = data
            }
        end
    end
    createGrid(ChristmasTeleportSection, Christmas2TeleportGridList, function(item)
        teleportWithData(item.Data)
    end)
    local miracleData = Christmas2TeleportMap["Christmas Miracle"]
    if miracleData then
        createButton(ChristmasTeleportSection, "Christmas Miracle", function()
            teleportWithData(miracleData)
        end)
    end

    State.InitChristmas = function()
        local ChristmasAutomationSection = createSectionBox(State.Tabs.Christmas:GetPage(), "Automation")

        setupAutoBuyGroup(ChristmasAutomationSection, {
            GroupKey = "Christmas Event",
            DisplayName = "Auto Buy Shop",
            ModeToggleName = "Mode: Upgrade All",
            SpeedLabel = "Click Speed (sec)",
            CooldownKey = "ChristmasAutoBuy",
            DefaultCooldown = 0.6,
            ResetMaxedOnPopup = {
                Match = "Successfully Reached Christmas Rank",
                ShopKey = "Candy Cane",
                OnReset = function()
                    notify("Auto Buy Shop", "List item Candy Cane Shop tereset", 3)
                end
            },
            Shops = {
                {
                    Key = "Candy Cane",
                    DisplayName = "Candy Cane Shop",
                    ShopName = "Candy Cane",
                },
                {
                    Key = "Milk",
                    DisplayName = "Milk Shop",
                    ShopName = "Milk",
                },
                {
                    Key = "Cookies",
                    DisplayName = "Cookies Shop",
                    ShopName = "Cookies",
                },
                {
                    Key = "Christmas Spirit",
                    DisplayName = "Christmas Spirit",
                    ShopName = "Christmas Spirit",
                },
                {
                    Key = "Gingerbread",
                    DisplayName = "Gingerbread",
                    ShopName = "Gingerbread",
                }
            }
        })
    end
end
local HeavenTeleportSection = createSectionBox(State.Tabs.Heaven:GetPage(), "Teleport")
createButton(HeavenTeleportSection, "Home", function()
    teleportHomeSmart("Heaven World")
end)
local HeavenList = {
    {Label = "Roll Rarity", Data = makeData(
        Vector3.new(-4156.508, 16.928, 2069.737),
        CFrame.new(-4155.907227, 25.840816, 2080.672119, 0.998492897, -0.030761035, 0.045449782, 0.000000000, 0.828151584, 0.560504317, -0.054880995, -0.559659600, 0.826903462),
        CFrame.new(-4156.508301, 18.428308, 2069.736572, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224702
    )},
    {Label = "Increase Grace", Data = makeData(
        Vector3.new(-4157.667, 16.971, 2029.196),
        CFrame.new(-4161.286621, 26.064939, 2039.399170, 0.942443669, 0.192010447, -0.273737073, 0.000000000, 0.818677306, 0.574253976, 0.334365040, -0.541202009, 0.771557212),
        CFrame.new(-4157.666504, 18.470596, 2029.195557, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224712
    )},
    {Label = "View Glory", Data = makeData(
        Vector3.new(-4019.002, 15.991, 2071.887),
        CFrame.new(-4032.912598, 25.722851, 2066.520996, -0.359897941, 0.450938851, -0.816778839, 0.000000000, 0.875440657, 0.483325690, 0.932991683, 0.173947915, -0.315069288),
        CFrame.new(-4019.002197, 17.491386, 2071.886963, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        17.030849
    )},
    {Label = "Increase Glory", Data = makeData(
        Vector3.new(-4010.934, 16.983, 2070.257),
        CFrame.new(-4021.764160, 25.875393, 2068.801758, -0.133189067, 0.555318534, -0.820903182, 0.000000000, 0.828282773, 0.560310483, 0.991090775, 0.074627228, -0.110318176),
        CFrame.new(-4010.933838, 18.483175, 2070.257080, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.193132
    )},
    {Label = "Transcend Rank Up", Data = makeData(
        Vector3.new(-4139.377, 15.491, 2088.698),
        CFrame.new(-4144.363770, 22.381298, 2077.699463, -0.910784006, 0.168275982, -0.377035409, 0.000000000, 0.913177013, 0.407563180, 0.412883192, 0.371202022, -0.831707001),
        CFrame.new(-4139.377441, 16.991394, 2088.698486, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224713
    )},
    {Label = "Prestige", Data = makeData(
        Vector3.new(-4153.603, 15.994, 2130.044),
        CFrame.new(-4165.019043, 22.333181, 2125.446289, -0.373537064, 0.339439780, -0.863279045, 0.000000000, 0.930643439, 0.365927339, 0.927615225, 0.136687428, -0.347629815),
        CFrame.new(-4153.602539, 17.493898, 2130.043701, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224652
    )},
    {Label = "Heaven Tree", Data = makeData(
        Vector3.new(-4151.697, 15.491, 2168.389),
        CFrame.new(-4153.026367, 24.828236, 2157.819336, -0.992188632, 0.073923253, -0.100483254, 0.000000000, 0.805503547, 0.592590809, 0.124745868, 0.587961853, -0.799211621),
        CFrame.new(-4151.697266, 16.991394, 2168.388672, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224730
    )},
    {Label = "View Divinity", Data = makeData(
        Vector3.new(-4294.839, 15.991, 2067.794),
        CFrame.new(-4283.051758, 23.287127, 2069.327881, 0.129036605, -0.434586406, 0.891338527, 0.000000000, 0.898853064, 0.438250273, -0.991639793, -0.056550328, 0.115984961),
        CFrame.new(-4294.839355, 17.491394, 2067.793945, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224633
    )},
    {Label = "Blessing", Data = makeData(
        Vector3.new(-4276.872, 15.991, 2046.210),
        CFrame.new(-4276.546387, 22.538385, 2058.429443, 0.999645293, -0.010163699, 0.024616420, 0.000000000, 0.924313784, 0.381633401, -0.026632102, -0.381498039, 0.923985958),
        CFrame.new(-4276.872070, 17.491394, 2046.209961, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        13.224747
    )},
    {Label = "Rune", Data = makeData(
        Vector3.new(-4035.115, 16.794, 2090.486),
        CFrame.new(-4028.479248, 27.137203, 2106.553223, 0.924275875, -0.173082665, 0.340230048, 0.000000000, 0.891295791, 0.453422219, -0.381725162, -0.419087231, 0.823803246),
        CFrame.new(-4035.114990, 18.293655, 2090.485840, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
        19.503902
    )}
}
registerRuneLocations("Heaven World", HeavenList)
createGrid(HeavenTeleportSection, HeavenList, function(item)
    teleportWithData(item.Data)
end)

State.InitFiveM = function()
    local FiveMTeleportSection = createSectionBox(State.Tabs.FiveM:GetPage(), "Teleport")
    createButton(FiveMTeleportSection, "Home", function()
        fireWorldTeleport("5M Event")
    end)
    local FiveMTeleportList = {
        {Label = "Clicks Shop", Data = makeData(
            Vector3.new(-42.440, 14.117, 3978.721),
            CFrame.new(-53.744595, 23.892162, 4000.623291, 0.888619244, 0.145973042, -0.434796244, 0.000000000, 0.948000312, 0.318269700, 0.458645731, -0.282820582, 0.842411220),
            CFrame.new(-42.439892, 15.617151, 3978.720703, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            25.999912
        )},
        {Label = "Clicker Tokens Shop", Data = makeData(
            Vector3.new(-7.455, 14.617, 3997.470),
            CFrame.new(-10.638369, 23.903797, 4016.054932, 0.985645175, 0.064442426, -0.156046882, 0.000000000, 0.924285829, 0.381700873, 0.168829650, -0.376221627, 0.911018014),
            CFrame.new(-7.455012, 16.117100, 3997.470215, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            20.399954
        )},
        {Label = "Milestone Up", Data = makeData(
            Vector3.new(-0.921, 14.617, 4015.551),
            CFrame.new(-16.696320, 22.391117, 4004.239990, -0.582687378, 0.249942675, -0.773307323, 0.000000000, 0.951532841, 0.307547420, 0.812696397, 0.179204002, -0.554446161),
            CFrame.new(-0.920850, 16.117149, 4015.550781, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            20.400051
        )},
        {Label = "Tree", Data = makeData(
            Vector3.new(-117.199, 14.117, 4041.364),
            CFrame.new(-104.131653, 38.049431, 4039.934570, -0.108698055, -0.857667744, 0.502584159, 0.000000000, 0.505579770, 0.862779915, -0.994074762, 0.093782499, -0.054955546),
            CFrame.new(-117.198845, 15.617151, 4041.363525, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            26.000011
        )},
        {Label = "Event Legend", Data = makeData(
            Vector3.new(-81.982, 14.117, 4101.043),
            CFrame.new(-73.793541, 22.002190, 4107.702637, 0.630943120, -0.401564479, 0.663819909, 0.000000000, 0.855626523, 0.517593920, -0.775829196, -0.326572329, 0.539851546),
            CFrame.new(-81.982422, 15.617151, 4101.042969, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            12.336031
        )},
        {Label = "Bytes Upgrade", Data = makeData(
            Vector3.new(-60.355, 14.517, 4136.737),
            CFrame.new(-51.984009, 26.749435, 4114.584473, -0.935445905, -0.145905659, 0.321951330, 0.000000000, 0.910830438, 0.412780702, -0.353470147, 0.386134028, -0.852032483),
            CFrame.new(-60.354744, 16.017138, 4136.737305, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            25.999989
        )},
        {Label = "Rune 1", Data = makeData(
            Vector3.new(-65.269, 15.275, 4062.770),
            CFrame.new(-80.431313, 31.827337, 4077.586914, 0.698918164, 0.414051235, -0.583159566, 0.000000000, 0.815377831, 0.578929305, 0.715201735, -0.404624194, 0.569882333),
            CFrame.new(-65.269165, 16.775175, 4062.770020, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            25.999973
        )},
        {Label = "Rune 2", Data = makeData(
            Vector3.new(-43.136, 15.275, 4040.341),
            CFrame.new(-54.345493, 36.385136, 4053.217285, 0.754254699, 0.495213300, -0.431119084, 0.000000000, 0.656611204, 0.754229248, 0.656581938, -0.568880975, 0.495252132),
            CFrame.new(-43.136398, 16.775175, 4040.340820, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000, 0.000000000, 0.000000000, 0.000000000, 1.000000000),
            25.999956
        )}
    }
    registerRuneLocations("5M Event", FiveMTeleportList)
    createGrid(FiveMTeleportSection, FiveMTeleportList, function(item)
        teleportWithData(item.Data)
    end)

    local FiveMActionsSection = createSectionBox(State.Tabs.FiveM:GetPage(), "5M Event Actions")
    local function fireFiveMAction(action)
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return
        end
        pcall(function()
            remote:FireServer(action)
        end)
    end

    createButton(FiveMActionsSection, "Upgrade Bytes Machine", function()
        fireFiveMAction("MachineLevelUp")
    end)

    createButton(FiveMActionsSection, "Upgrade Event Legend", function()
        fireFiveMAction("EventLegend")
    end)

    createButton(FiveMActionsSection, "Passive Roll 5M Event", function()
        fireFiveMAction("HandleAutoRoll5MEventPassive")
    end)

    local FiveMAutomationSection = createSectionBox(State.Tabs.FiveM:GetPage(), "Automation")
    setupAutoBuyGroup(FiveMAutomationSection, {
        GroupKey = "5M Event",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Mode: Upgrade All",
        SpeedLabel = "Click Speed (sec)",
        CooldownKey = "FiveMAutoBuy",
        DefaultCooldown = 0.6,
        Shops = {
            {
                Key = "Clicks",
                DisplayName = "Clicks Shop",
                ShopName = "Clicks",
            },
            {
                Key = "MachinePartUpgrade",
                DisplayName = "Machine Part Upgrade",
                ShopName = "MachinePartUpgrade",
                SpecialAction = "MachinePartUpgrade",
            }
        }
    })
end

if State.InitValentine then
    State.InitValentine()
    State.InitValentine = nil
    stepWorld("Valentine Event")
end

if State.InitHalloween then
    State.InitHalloween()
    State.InitHalloween = nil
    stepWorld("Halloween")
end

if State.InitChristmas then
    State.InitChristmas()
    State.InitChristmas = nil
    stepWorld("Christmas Event")
end

if State.InitMushroom then
    State.InitMushroom()
    State.InitMushroom = nil
    stepWorld("Mushroom World")
end

if State.InitFiveM then
    State.InitFiveM()
    State.InitFiveM = nil
    stepWorld("5M Event")
end

if State.InitHell then
    State.InitHell()
    State.InitHell = nil
    stepWorld("Hell World")
end

if State.InitGarden then
    State.InitGarden()
    State.InitGarden = nil
    stepWorld("The Garden")
end

do
    local HeavenAutomationSection = createSectionBox(State.Tabs.Heaven:GetPage(), "Automation")

    setupAutoBuyGroup(HeavenAutomationSection, {
        GroupKey = "Heaven World",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Mode: Upgrade All",
        SpeedLabel = "Click Speed (sec)",
        CooldownKey = "HeavenAutoBuy",
        DefaultCooldown = 0.6,
        ResetMaxedOnPrompt = {
            Match = "Successfully Reached Transcend",
            ShopKey = {"Grace", "Glory", "Divinity"}
        },
        Shops = {
            {
                Key = "Grace",
                DisplayName = "Grace Shop",
                ShopName = "Grace",
            },
            {
                Key = "Glory",
                DisplayName = "Glory Shop",
                ShopName = "Glory",
            },
            {
                Key = "Divinity",
                DisplayName = "Divinity Shop",
                ShopName = "Divinity",
            }
        }
    })
end
    stepWorld("Heaven World")

end

initEventTabs()

local function initSpaceAutomation()
    local AutomationSection = createSectionBox(State.Tabs.Space:GetPage(), "Automation")

    -- =====================================================
    -- [SECTION] Space World Automation
    -- =====================================================
    getMainRemote = function()
        local ok, remote = pcall(function()
            return game:GetService("ReplicatedStorage").Packages.Knit.Services.RemotesService.RE.MainRemote
        end)
        if ok and remote then
            return remote
        end
        return nil
    end

    State.SpaceAuto = State.SpaceAuto or {}
    State.SpaceAuto.Enabled = State.SpaceAuto.Enabled or false
    State.SpaceAuto.Conn = nil
    State.SpaceAuto.Accum = 0
    State.SpaceAuto.Interval = 5

    State.FireCosmicRankUp = function()
        local remote = getMainRemote()
        if not remote then
            return
        end
        pcall(function()
            remote:FireServer("CosmicRankUp")
        end)
    end

    createToggle(AutomationSection, "Auto Rank Up Cosmic", nil, false, function(v)
        State.SpaceAuto.Enabled = v
        if State.SpaceAuto.Enabled then
            if State.SpaceAuto.Conn then
                State.SpaceAuto.Conn:Disconnect()
            end
            State.SpaceAuto.Accum = 0
            State.FireCosmicRankUp()
            State.SpaceAuto.Conn = RunService.Heartbeat:Connect(function(dt)
                State.SpaceAuto.Accum += dt
                if State.SpaceAuto.Accum >= State.SpaceAuto.Interval then
                    State.SpaceAuto.Accum = 0
                    State.FireCosmicRankUp()
                end
            end)
            trackConnection(State.SpaceAuto.Conn)
        else
            if State.SpaceAuto.Conn then
                State.SpaceAuto.Conn:Disconnect()
                State.SpaceAuto.Conn = nil
            end
        end
    end)

    createButton(AutomationSection, "Rank Up Cosmic", function()
        State.FireCosmicRankUp()
    end)

    -- =====================================================
    -- [SECTION] Space World - Auto Buy Light Points Shop
    -- =====================================================
    setupAutoBuyGroup(AutomationSection, {
        GroupKey = "Space World",
        DisplayName = "Auto Buy Shop",
        ModeToggleName = "Light Points Mode: Upgrade All",
        SpeedLabel = "Light Points Click Speed (sec)",
        CooldownKey = "LightPoints",
        DefaultCooldown = 0.6,
        Shops = {
            {
                Key = "Light Points",
                DisplayName = "Light Points Shop",
                ShopName = "Light Points",
            },
            {
                Key = "Dirtite",
                DisplayName = "Dirtite Shop",
                ShopName = "Dirtite",
            },
            {
                Key = "Moonlite",
                DisplayName = "Moonlite Shop",
                ShopName = "Moonlite",
            },
            {
                Key = "Marsite",
                DisplayName = "Marsite Shop",
                ShopName = "Marsite",
            },
            {
                Key = "Venusite",
                DisplayName = "Venusite Shop",
                ShopName = "Venusite",
            },
            {
                Key = "Mercuryte",
                DisplayName = "Mercuryte Shop",
                ShopName = "Mercuryte",
            },
            {
                Key = "Jupiterite",
                DisplayName = "Jupiterite Shop",
                ShopName = "Jupiterite",
            },
            {
                Key = "Saturnite",
                DisplayName = "Saturnite Shop",
                ShopName = "Saturnite",
            },
            {
                Key = "Uranite",
                DisplayName = "Uranite Shop",
                ShopName = "Uranite",
            },
            {
                Key = "Neptunite",
                DisplayName = "Neptunite Shop",
                ShopName = "Neptunite",
            },
            {
                Key = "Plutite",
                DisplayName = "Plutite Shop",
                ShopName = "Plutite",
            },
            {
                Key = "Sunite",
                DisplayName = "Sunite Shop",
                ShopName = "Sunite",
            }
        }
    })

    local universeDepositSection = createSubSectionBox(AutomationSection, "Auto Deposit Universe")
    Config.UniverseAutoDepositItems = Config.UniverseAutoDepositItems or {}

    local function getUniverseDepositDefinitions()
        local defs = {}
        local fallback = {
            "Dirtite",
            "Moonlite",
            "Marsite",
            "Venusite",
            "Mercuryte",
            "Jupiterite",
            "Saturnite",
            "Uranite",
            "Neptunite",
            "Plutite",
            "Sunite"
        }
        local seen = {}

        local function addDef(name, order)
            if type(name) ~= "string" then
                return
            end
            local trimmed = name:match("^%s*(.-)%s*$")
            if type(trimmed) ~= "string" or #trimmed == 0 then
                return
            end
            if seen[trimmed] then
                return
            end
            seen[trimmed] = true
            defs[#defs + 1] = {
                Name = trimmed,
                Order = tonumber(order) or 999999
            }
        end

        local runtimeOrder = 1
        local milestoneRoot = LP and LP:FindFirstChild("UniverseMilestone")
        if milestoneRoot then
            local children = milestoneRoot:GetChildren()
            table.sort(children, function(a, b)
                return tostring(a.Name) < tostring(b.Name)
            end)
            for _, item in ipairs(children) do
                if item and item:FindFirstChild("MilestoneDeposit") then
                    addDef(item.Name, runtimeOrder)
                    runtimeOrder += 1
                end
            end
        end

        if #defs == 0 then
            for _, name in ipairs(fallback) do
                addDef(name, #defs + 1)
            end
        end
        table.sort(defs, function(a, b)
            if a.Order == b.Order then
                return tostring(a.Name) < tostring(b.Name)
            end
            return a.Order < b.Order
        end)
        return defs
    end

    local universeDepositDefs = getUniverseDepositDefinitions()
    local universeDepositCfg = Config.UniverseAutoDepositItems
    for _, def in ipairs(universeDepositDefs) do
        if universeDepositCfg[def.Name] == nil then
            universeDepositCfg[def.Name] = true
        end
    end
    saveConfig()

    State.UniverseAutoDeposit = State.UniverseAutoDeposit or {
        Enabled = Config.UniverseAutoDepositEnabled == true,
        Index = 1,
        Success = 0,
        SuccessByItem = {},
        LastItem = nil,
        LastSnapshotAt = 0,
        SnapshotSignature = "",
        Wait = {
            Active = false,
            Currency = nil,
            Before = nil,
            BeforeRaw = nil,
            Since = 0,
            Timeout = 1.2
        }
    }

    local function readRawAndNumber(node)
        if not node then
            return nil, nil
        end
        local ok, raw = pcall(function()
            return node.Value
        end)
        if not ok then
            return nil, nil
        end
        local num = tonumber(raw)
        if type(num) == "number" and (num == math.huge or num == -math.huge or num ~= num) then
            num = nil
        end
        return raw, num
    end

    local function toSimpleNumberString(raw)
        if raw == nil then
            return ""
        end
        return tostring(raw):lower():gsub("%s+", ""):gsub(",", ".")
    end

    local function getUniverseMagnitude(raw, num)
        if type(num) == "number" and num == num and num ~= math.huge and num ~= -math.huge then
            if num <= 0 then
                return nil
            end
            return math.log10(num)
        end

        local text = toSimpleNumberString(raw)
        if text == "" then
            return nil
        end

        local plainNum = tonumber(text)
        if type(plainNum) == "number" and plainNum == plainNum and plainNum ~= math.huge and plainNum ~= -math.huge then
            if plainNum <= 0 then
                return nil
            end
            return math.log10(plainNum)
        end

        local mantissaText, expText, expSuffix = text:match("^([%+%-]?%d*%.?%d+)[eE]([%+%-]?%d*%.?%d+)([kmb]?)$")
        if not mantissaText then
            return nil
        end
        local mantissa = tonumber(mantissaText)
        local expBase = tonumber(expText)
        if type(mantissa) ~= "number" or type(expBase) ~= "number" then
            return nil
        end
        if mantissa <= 0 then
            return nil
        end

        local expScale = 1
        if expSuffix == "k" then
            expScale = 1e3
        elseif expSuffix == "m" then
            expScale = 1e6
        elseif expSuffix == "b" then
            expScale = 1e9
        end
        local exponent = expBase * expScale
        return math.log10(mantissa) + exponent
    end

    local function shouldDepositByMagnitude(amountRaw, amountNum, depoRaw, depoNum)
        local amountMag = getUniverseMagnitude(amountRaw, amountNum)
        local depoMag = getUniverseMagnitude(depoRaw, depoNum)
        if type(amountMag) ~= "number" or type(depoMag) ~= "number" then
            return false
        end
        local mult = getAutoDepositRequiredMultiplier()
        if type(mult) ~= "number" or mult <= 0 then
            return false
        end
        local rhsMag = depoMag + math.log10(mult)
        return amountMag >= (rhsMag - 1e-12)
    end

    local function didUniverseAmountDecrease(beforeRaw, beforeNum, afterRaw, afterNum)
        local beforeMag = getUniverseMagnitude(beforeRaw, beforeNum)
        local afterMag = getUniverseMagnitude(afterRaw, afterNum)
        if type(beforeMag) == "number" and type(afterMag) == "number" then
            return afterMag < (beforeMag - 1e-12)
        end
        local b = tonumber(beforeNum)
        local a = tonumber(afterNum)
        if type(b) == "number" and b == b and b ~= math.huge and b ~= -math.huge
            and type(a) == "number" and a == a and a ~= math.huge and a ~= -math.huge then
            return a < (b - 1e-9)
        end
        if beforeRaw ~= nil and afterRaw ~= nil then
            return tostring(afterRaw) ~= tostring(beforeRaw)
        end
        return false
    end

    local function getUniverseCurrencyEntry(currencyName)
        if not LP or type(currencyName) ~= "string" then
            return nil, nil
        end
        local currencyRoot = LP:FindFirstChild("Currency")
        local currency = currencyRoot and currencyRoot:FindFirstChild(currencyName)
        local amountRoot = currency and currency:FindFirstChild("Amount")
        local amountNode = amountRoot and (amountRoot:FindFirstChild("1") or amountRoot:FindFirstChildWhichIsA("ValueBase"))
        local milestoneRoot = LP:FindFirstChild("UniverseMilestone")
        local milestoneEntry = milestoneRoot and milestoneRoot:FindFirstChild(currencyName)
        return amountNode, milestoneEntry
    end

    local function shouldDepositUniverse(currencyName)
        local amountNode, milestoneEntry = getUniverseCurrencyEntry(currencyName)
        if not amountNode or not milestoneEntry then
            return false
        end
        local amountRaw, amountNum = readRawAndNumber(amountNode)
        local depoRaw, depoNum = readRawAndNumber(milestoneEntry:FindFirstChild("MilestoneDeposit"))
        if shouldDepositByMagnitude(amountRaw, amountNum, depoRaw, depoNum) then
            return true, amountRaw, amountNum, depoRaw, depoNum
        end
        return false
    end

    local function buildUniverseDepositSnapshot()
        local out = {}
        for _, def in ipairs(universeDepositDefs) do
            if def and universeDepositCfg[def.Name] then
                local amountNode, milestoneEntry = getUniverseCurrencyEntry(def.Name)
                local ownRaw, ownNum = readRawAndNumber(amountNode)
                local depoRaw, depoNum = readRawAndNumber(milestoneEntry and milestoneEntry:FindFirstChild("MilestoneDeposit"))
                out[#out + 1] = {
                    Name = tostring(def.Name),
                    OwnNum = ownNum,
                    DepositNum = depoNum,
                    OwnRaw = ownRaw,
                    DepositRaw = depoRaw
                }
            end
        end
        return out
    end

    local function buildUniverseItemTotalsCopy()
        local out = {}
        local src = State.UniverseAutoDeposit and State.UniverseAutoDeposit.SuccessByItem or nil
        for k, v in pairs(src or {}) do
            out[k] = tonumber(v) or 0
        end
        return out
    end

    local function buildUniverseSnapshotSignature(items)
        local parts = {}
        for _, entry in ipairs(items or {}) do
            parts[#parts + 1] = tostring(entry.Name)
                .. ":"
                .. tostring(entry.OwnNum ~= nil and entry.OwnNum or "?")
                .. ":"
                .. tostring(entry.DepositNum ~= nil and entry.DepositNum or "?")
        end
        table.sort(parts)
        return table.concat(parts, "|")
    end

    local function refreshUniverseDepositLog(forceRefresh)
        if not (AutoBuyLogState and AutoBuyLogState.UpdateDepositProgress and State.UniverseAutoDeposit and State.UniverseAutoDeposit.Enabled) then
            return
        end
        local now = os.clock()
        if not forceRefresh and (now - (State.UniverseAutoDeposit.LastSnapshotAt or 0)) < 0.35 then
            return
        end
        local items = buildUniverseDepositSnapshot()
        local sig = buildUniverseSnapshotSignature(items)
        if not forceRefresh and sig == State.UniverseAutoDeposit.SnapshotSignature then
            State.UniverseAutoDeposit.LastSnapshotAt = now
            return
        end
        State.UniverseAutoDeposit.SnapshotSignature = sig
        State.UniverseAutoDeposit.LastSnapshotAt = now
        AutoBuyLogState.UpdateDepositProgress("UniverseAutoDeposit", {
            ItemName = State.UniverseAutoDeposit.LastItem or "-",
            Items = items,
            Success = tonumber(State.UniverseAutoDeposit.Success) or 0,
            ItemTotals = buildUniverseItemTotalsCopy()
        })
    end

    local function universeDepositStep()
        if not State.UniverseAutoDeposit or not State.UniverseAutoDeposit.Enabled then
            return false
        end
        local remote = getMainRemote and getMainRemote() or nil
        if not remote then
            return false
        end

        local waitState = State.UniverseAutoDeposit.Wait
        if waitState and waitState.Active and waitState.Currency then
            local amountNode = getUniverseCurrencyEntry(waitState.Currency)
            local amountRaw, amountNum = readRawAndNumber(amountNode)
            local changed = false
            if waitState.BeforeRaw ~= nil and amountRaw ~= nil and tostring(amountRaw) ~= tostring(waitState.BeforeRaw) then
                changed = true
            elseif type(amountNum) == "number" and type(waitState.Before) == "number" and math.abs(amountNum - waitState.Before) > 1e-9 then
                changed = true
            end
            if changed then
                local decreased = didUniverseAmountDecrease(waitState.BeforeRaw, waitState.Before, amountRaw, amountNum)
                waitState.Active = false
                if decreased then
                    local doneName = waitState.Currency
                    State.UniverseAutoDeposit.LastItem = doneName
                    State.UniverseAutoDeposit.Success = (tonumber(State.UniverseAutoDeposit.Success) or 0) + 1
                    State.UniverseAutoDeposit.SuccessByItem = State.UniverseAutoDeposit.SuccessByItem or {}
                    State.UniverseAutoDeposit.SuccessByItem[doneName] = (tonumber(State.UniverseAutoDeposit.SuccessByItem[doneName]) or 0) + 1
                    refreshUniverseDepositLog(true)
                end
            elseif (os.clock() - (waitState.Since or 0)) < (waitState.Timeout or 1.2) then
                return false
            else
                waitState.Active = false
            end
        end

        local total = #universeDepositDefs
        if total == 0 then
            return false
        end
        refreshUniverseDepositLog(false)
        local idx = tonumber(State.UniverseAutoDeposit.Index) or 1
        for _ = 1, total do
            local def = universeDepositDefs[idx]
            idx += 1
            if idx > total then
                idx = 1
            end
            if def and universeDepositCfg[def.Name] then
                local should, rawAmount, amountNum = shouldDepositUniverse(def.Name)
                if should then
                    local amountArg = rawAmount
                    if type(amountArg) ~= "string" and type(amountArg) ~= "number" then
                        amountArg = tostring(amountNum)
                    end
                    local ok = pcall(function()
                        remote:FireServer("universeDeposit", def.Name, amountArg)
                    end)
                    if ok then
                        State.UniverseAutoDeposit.Index = idx
                        State.UniverseAutoDeposit.LastItem = def.Name
                        if waitState then
                            waitState.Active = true
                            waitState.Currency = def.Name
                            waitState.Before = amountNum
                            waitState.BeforeRaw = rawAmount
                            waitState.Since = os.clock()
                        end
                        refreshUniverseDepositLog(true)
                        return true
                    end
                end
            end
        end
        State.UniverseAutoDeposit.Index = idx
        return false
    end

    local function setUniverseAutoDepositEnabled(enabled)
        State.UniverseAutoDeposit.Enabled = enabled == true
        Config.UniverseAutoDepositEnabled = State.UniverseAutoDeposit.Enabled
        saveConfig()

        if AutoBuyLogState and AutoBuyLogState.SetDepositActive then
            AutoBuyLogState.SetDepositActive("UniverseAutoDeposit", "Deposit Universe", State.UniverseAutoDeposit.Enabled)
            if State.UniverseAutoDeposit.Enabled and AutoBuyLogState.UpdateDepositProgress then
                AutoBuyLogState.UpdateDepositProgress("UniverseAutoDeposit", {
                    ItemName = State.UniverseAutoDeposit.LastItem or "-",
                    Items = buildUniverseDepositSnapshot(),
                    Success = tonumber(State.UniverseAutoDeposit.Success) or 0,
                    ItemTotals = buildUniverseItemTotalsCopy()
                })
            end
        end

        if State.UniverseAutoDeposit.Enabled then
            State.UniverseAutoDeposit.Index = 1
            State.UniverseAutoDeposit.LastSnapshotAt = 0
            State.UniverseAutoDeposit.SnapshotSignature = ""
            if State.UniverseAutoDeposit.Wait then
                State.UniverseAutoDeposit.Wait.Active = false
                State.UniverseAutoDeposit.Wait.Currency = nil
                State.UniverseAutoDeposit.Wait.Before = nil
                State.UniverseAutoDeposit.Wait.BeforeRaw = nil
            end
            autoBuySchedulerRegister("UniverseAutoDeposit", {
                Step = universeDepositStep
            })
        else
            autoBuySchedulerUnregister("UniverseAutoDeposit")
            if State.UniverseAutoDeposit.Wait then
                State.UniverseAutoDeposit.Wait.Active = false
                State.UniverseAutoDeposit.Wait.Currency = nil
                State.UniverseAutoDeposit.Wait.Before = nil
                State.UniverseAutoDeposit.Wait.BeforeRaw = nil
            end
        end
    end

    createToggle(universeDepositSection, "Auto Deposit Universe", nil, State.UniverseAutoDeposit.Enabled, function(v)
        setUniverseAutoDepositEnabled(v == true)
    end)

    local universeItemListSection = createSubSectionBox(universeDepositSection, "Item List")
    for _, def in ipairs(universeDepositDefs) do
        createToggle(universeItemListSection, tostring(def.Name), nil, universeDepositCfg[def.Name], function(v)
            universeDepositCfg[def.Name] = v == true
            saveConfig()
            if State.UniverseAutoDeposit and State.UniverseAutoDeposit.Enabled and AutoBuyLogState and AutoBuyLogState.UpdateDepositProgress then
                refreshUniverseDepositLog(true)
            end
        end)
    end
    setUniverseAutoDepositEnabled(State.UniverseAutoDeposit.Enabled == true)
end

initSpaceAutomation()

end

LoadingUI:Set(80, "Menyusun world tabs...")
initWorldTabs()
LoadingUI:Set(86, "Menyiapkan teleport...")
initRuneLocationTab()
initStatTab()
initActionTab()
LoadingUI:Set(90, "Menyelesaikan layout...")

-- =====================================================
-- INITIAL STATE
-- =====================================================
applyTheme(Config.Theme or "Default")
HomeTab:Show()


end

buildTabsUI()

LoadingUI:Set(92, "Menyiapkan UI...")

LoadingUI:Set(98, "Finishing...")

if State.UI and State.UI.AnimateShow then
    State.UI.AnimateShow(Main, {StartScale = 0.95, Duration = 0.2})
else
    Main.Visible = true
end
task.delay(0.1, function()
    if LoadingUI.Card then
        LoadingUI.Card:Destroy()
    end
    notify("Script Loaded", "Script berhasil", 5)
end)


