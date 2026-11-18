-- Seeto.SolutionZ / Bloxstrike v2.5 · 手机版（免 key）
-- 内联：14 个主模块 + Skinchanger 8 个模块；触屏兼容；「手机」页可调按钮位置、开关皮肤修改器

local __mods = {}
__mods["AntiFlash"] = function()
-- antiflash
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local FlashEffect = require(ReplicatedStorage.Components.Common.VFXLibary.FlashEffect)
local CaptureController = require(ReplicatedStorage.Controllers.CaptureController)
local Promise = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Promise"))

local AntiFlash = {
    Connections = {},
    IndicatorGui = nil,
    Initialized = false
}

local originalCaptureScreenshot = nil

function AntiFlash.init(Config)
    if AntiFlash.Initialized then return end
    AntiFlash.Initialized = true

    -- disable flash screenshot
    if not _G.__originalCaptureScreenshot then
        _G.__originalCaptureScreenshot = CaptureController.CaptureScreenshot
    end
    originalCaptureScreenshot = _G.__originalCaptureScreenshot

    CaptureController.CaptureScreenshot = function(callback)
        if Config.ANTI_FLASH_ENABLED then
            return Promise.reject("Flash snapshot burn-in disabled by AntiFlash")
        end
        return originalCaptureScreenshot(callback)
    end

    -- indicator overlay
    local indicatorGui = Instance.new("ScreenGui")
    indicatorGui.Name = "AntiFlashIndicator"
    indicatorGui.DisplayOrder = 999
    indicatorGui.IgnoreGuiInset = true
    indicatorGui.ResetOnSpawn = false

    local overlayFrame = Instance.new("Frame")
    overlayFrame.Name = "IndicatorOverlay"
    overlayFrame.Size = UDim2.new(1, 0, 1, 0)
    overlayFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    overlayFrame.BackgroundTransparency = 1
    overlayFrame.BorderSizePixel = 0
    overlayFrame.Parent = indicatorGui

    indicatorGui.Parent = PlayerGui
    AntiFlash.IndicatorGui = indicatorGui

    -- render loop
    local isFlashedPrev = false

    local renderConn = RunService.RenderStepped:Connect(function()
        if not Config.ANTI_FLASH_ENABLED then
            overlayFrame.BackgroundTransparency = 1
            return
        end

        local officialGui = PlayerGui:FindFirstChild("FlashbangEffect")
        if officialGui then
            for _, obj in ipairs(officialGui:GetDescendants()) do
                if obj:IsA("GuiObject") then
                    obj.Visible = false
                end
            end
        end

        local cc = Lighting:FindFirstChild("FlashbangColorCorrection")
        if cc then
            cc.Brightness = 0
            cc.Saturation = 0
            cc.Enabled = false
        end

        local isFlashed = FlashEffect.IsFlashed()
        if isFlashed then
            overlayFrame.BackgroundTransparency = Config.ANTI_FLASH_TRANSPARENCY or 0.85
            isFlashedPrev = true
        elseif isFlashedPrev then
            isFlashedPrev = false
            TweenService:Create(overlayFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = 1
            }):Play()
        end
    end)
    table.insert(AntiFlash.Connections, renderConn)
end

function AntiFlash.cleanup()
    if originalCaptureScreenshot then
        CaptureController.CaptureScreenshot = originalCaptureScreenshot
    end
    for _, c in ipairs(AntiFlash.Connections) do
        pcall(function() c:Disconnect() end)
    end
    AntiFlash.Connections = {}
    if AntiFlash.IndicatorGui then
        pcall(function() AntiFlash.IndicatorGui:Destroy() end)
        AntiFlash.IndicatorGui = nil
    end
    AntiFlash.Initialized = false
    _G.__originalCaptureScreenshot = nil
end

return AntiFlash

end
__mods["Bhop"] = function()
-- movement physics (bunny hop)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CharacterClass = require(ReplicatedStorage.Classes.Character)
local Buttons = require(ReplicatedStorage.MovementV2.Buttons)

local Bhop = {
    IsHoldingSpace = false,
    Connections = {},
    Initialized = false
}

local originalSampleInput = nil

function Bhop.init(Config)
    if Bhop.Initialized then return end
    Bhop.Initialized = true

    local beganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.KeyCode == Enum.KeyCode.Space then
            Bhop.IsHoldingSpace = true
        end
    end)
    table.insert(Bhop.Connections, beganConn)

    local endedConn = UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if input.KeyCode == Enum.KeyCode.Space then
            Bhop.IsHoldingSpace = false
        end
    end)
    table.insert(Bhop.Connections, endedConn)

    if not _G.__originalSampleInput then
        _G.__originalSampleInput = CharacterClass.SampleInput
    end
    originalSampleInput = _G.__originalSampleInput

    CharacterClass.SampleInput = function(self, p2)
        local sample = originalSampleInput(self, p2)
        if not sample then return sample end

        -- bhop jump logic: jump immediately upon landing
        local bhopEnabled = (Config.BHOP_ENABLED ~= false)
        local isSpaceDown = Bhop.IsHoldingSpace or UserInputService:IsKeyDown(Enum.KeyCode.Space)
        if bhopEnabled and isSpaceDown then
            local mvState = self.MovementState
            local onGround = mvState and mvState.OnGround
            if onGround then
                sample.Buttons = Buttons.with(sample.Buttons, Buttons.Jump, true)
            else
                sample.Buttons = Buttons.with(sample.Buttons, Buttons.Jump, false)
            end
        end

        return sample
    end
end

function Bhop.cleanup()
    if originalSampleInput then
        pcall(function() CharacterClass.SampleInput = originalSampleInput end)
    end
    for _, c in ipairs(Bhop.Connections) do
        pcall(function() c:Disconnect() end)
    end
    Bhop.Connections = {}
    Bhop.IsHoldingSpace = false
    Bhop.Initialized = false
    _G.__originalSampleInput = nil
end

return Bhop

end
__mods["Config"] = function()
-- config and state
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local CONFIG_FOLDER = "Bloxstrike"
local CONFIG_FILE = "Bloxstrike/config.json"

local function ensureDirectory()
    if type(makefolder) == "function" then
        if type(isfolder) == "function" then
            if not isfolder(CONFIG_FOLDER) then
                pcall(makefolder, CONFIG_FOLDER)
            end
        else
            pcall(makefolder, CONFIG_FOLDER)
        end
    end
end

local Config = {
    -- aim
    SILENT_AIM_ENABLED = true,
    KEEP_TARGET_LOCK = true,
    FOV_DEG = 13,
    FALLOFF_REF = 500,
    FOV_CIRCLE_ENABLED = true,
    FOV_CIRCLE_TRANSPARENCY = 0.34,
    FOV_CIRCLE_COLOR = Color3.fromRGB(255, 255, 255),
    BODYPART_TARGET_HL = true,
    BODYPART_HL_COLOR = Color3.fromRGB(255, 255, 0),
    TARGET_PRIORITY = "Auto",
    AIM_OCCLUSION_CHECK = false,
    WALLBANG_ENABLED = false,

    -- visuals
    ESP_ENABLED = true,
    ESP_HIGHLIGHT_ENABLED = false,
    SKELETON_ENABLED = true,
    VIEWANGLE_ENABLED = true,
    OFFSCREEN_ARROWS = true,
    OFFSCREEN_ARROW_RADIUS = 0.72,
    OFFSCREEN_ARROW_SIZE = 13,
    OFFSCREEN_ARROW_MAX_DIST = 350,
    OFFSCREEN_ARROW_FADE_DIST = 80,
    DISABLE_TEAMMATES = true,
    OCCLUSION_CHECK_ENABLED = true,
    OCCLUDED_COLOR_FACTOR = 0.45,
    SPECTATE_CHECKER_ENABLED = true,

    -- movement
    BHOP_ENABLED = true,

    -- utilities
    ANTI_FLASH_ENABLED = true,
    ANTI_FLASH_TRANSPARENCY = 0.27,

    -- weapons
    CUSTOM_RPM_ENABLED = false,
    CUSTOM_RPM_VALUE = 1018,
    FORCE_FULL_AUTO = false,

    -- skins
    AUTO_LAUNCH_SKINCHANGER = false,
    SKINS_ENABLED = true,
    KNIFE_SKINS_ENABLED = true,
    WEAPON_SKINS_ENABLED = true,
    KNIFE_MODEL = "Butterfly Knife",
    KNIFE_SKIN = "Special",
    SELECTED_WEAPON_TYPE = "AK-47",
    SELECTED_SKINS = {},
    SKIN_MODE = "Special",
    EQUIP_BUTTERFLY_KNIFE = true,

    -- keybinds
    TOGGLE_UI_KEY = Enum.KeyCode.Insert,
    TOGGLE_UI_KEY_ALT = Enum.KeyCode.RightShift,
    TOGGLE_AIM_KEY = nil,
    AIM_BIND_MODE = "Toggle",
    TOGGLE_ESP_KEY = nil,
    UNLOAD_KEY = Enum.KeyCode.P,

    -- ui state
    MENU_OPEN = true,
    WINDOW_SIZE_X = 442,
    WINDOW_SIZE_Y = 292,

    -- visual colors
    CT_COLOR = Color3.fromRGB(0, 160, 255),
    CT_OUTLINE = Color3.fromRGB(150, 220, 255),
    T_COLOR = Color3.fromRGB(255, 140, 0),
    T_OUTLINE = Color3.fromRGB(255, 220, 100),
    TARGET_COLOR = Color3.fromRGB(0, 255, 0),
    TARGET_OUTLINE = Color3.fromRGB(0, 200, 0),

    -- theme (cs2 orange)
    UI_THEME = {
        FontColor       = Color3.fromRGB(250, 250, 250),
        MainColor       = Color3.fromRGB(26, 26, 30),
        BackgroundColor = Color3.fromRGB(18, 18, 22),
        AccentColor     = Color3.fromRGB(245, 125, 25),
        OutlineColor    = Color3.fromRGB(52, 54, 62),
        RiskColor       = Color3.fromRGB(255, 60, 60)
    },

    -- runtime target state
    CurrentTargetChar = nil,
    CurrentTargetPart = nil,
    LockedTargetChar = nil,
    WaitingForM1Release = false
}

-- defaults
local DEFAULT_VALUES = {
    SILENT_AIM_ENABLED = true,
    KEEP_TARGET_LOCK = true,
    FOV_DEG = 13,
    FOV_CIRCLE_ENABLED = true,
    FOV_CIRCLE_TRANSPARENCY = 0.34,
    BODYPART_TARGET_HL = true,
    TARGET_PRIORITY = "Auto",
    AIM_OCCLUSION_CHECK = false,
    WALLBANG_ENABLED = false,
    ESP_ENABLED = true,
    SKELETON_ENABLED = true,
    VIEWANGLE_ENABLED = true,
    OFFSCREEN_ARROWS = true,
    DISABLE_TEAMMATES = true,
    OCCLUSION_CHECK_ENABLED = true,
    SPECTATE_CHECKER_ENABLED = true,
    BHOP_ENABLED = true,
    ANTI_FLASH_ENABLED = true,
    ANTI_FLASH_TRANSPARENCY = 0.27,
    CUSTOM_RPM_ENABLED = false,
    CUSTOM_RPM_VALUE = 1018,
    FORCE_FULL_AUTO = false,
    AUTO_LAUNCH_SKINCHANGER = false,
    SKINS_ENABLED = true,
    KNIFE_SKINS_ENABLED = true,
    WEAPON_SKINS_ENABLED = true,
    KNIFE_MODEL = "Butterfly Knife",
    KNIFE_SKIN = "Special",
    SELECTED_WEAPON_TYPE = "AK-47",
    SELECTED_SKINS = {},
    SKIN_MODE = "Special",
    EQUIP_BUTTERFLY_KNIFE = true,
    WINDOW_SIZE_X = 442,
    WINDOW_SIZE_Y = 292,
    TOGGLE_UI_KEY = "Insert",
    TOGGLE_UI_KEY_ALT = "RightShift",
    TOGGLE_AIM_KEY = "None",
    AIM_BIND_MODE = "Toggle",
    TOGGLE_ESP_KEY = "None",
    UNLOAD_KEY = "P"
}

Config._keysDown = {}

if not _G.__bloxstrikeInputTracked then
    _G.__bloxstrikeInputTracked = true
    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            Config._keysDown[input.KeyCode] = true
            Config._keysDown[input.KeyCode.Name] = true
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            Config._keysDown["MB1"] = true
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            Config._keysDown["MB2"] = true
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            Config._keysDown["MB3"] = true
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            Config._keysDown[input.KeyCode] = false
            Config._keysDown[input.KeyCode.Name] = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            Config._keysDown["MB1"] = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            Config._keysDown["MB2"] = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            Config._keysDown["MB3"] = false
        end
    end)
end

local InputController = nil
pcall(function()
    InputController = require(game:GetService("ReplicatedStorage").Controllers.InputController)
end)

-- aim key held check
function Config.isAimKeyHeld()
    local key = Config.TOGGLE_AIM_KEY
    if not key or key == "None" or key == "" then
        return true
    end

    -- 1. Check mouse buttons
    if key == "MB1" or key == Enum.UserInputType.MouseButton1 then
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or (Config._keysDown["MB1"] == true) then
            return true
        end
    elseif key == "MB2" or key == Enum.UserInputType.MouseButton2 then
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) or (Config._keysDown["MB2"] == true) then
            return true
        end
    elseif key == "MB3" or key == Enum.UserInputType.MouseButton3 then
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) or (Config._keysDown["MB3"] == true) then
            return true
        end
    end

    -- keycode
    if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
        if UserInputService:IsKeyDown(key) or (Config._keysDown[key] == true) or (Config._keysDown[key.Name] == true) then
            return true
        end
    end

    -- string key name
    if type(key) == "string" then
        local kc = Enum.KeyCode[key]
        if kc and UserInputService:IsKeyDown(kc) then
            return true
        end
        if (Config._keysDown[key] == true) or (kc and Config._keysDown[kc] == true) then
            return true
        end
    end

    -- InputController actions
    if InputController then
        local targetKc = (typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode) and key or (type(key) == "string" and Enum.KeyCode[key])
        if targetKc then
            local okBind, isPressed = pcall(InputController.isBindingPressed, targetKc)
            if okBind and isPressed == true then
                return true
            end
        end

        local okUps, upsList = pcall(function()
            if debug and debug.getupvalues then
                return debug.getupvalues(InputController.isActionActive)
            end
            return nil
        end)
        if okUps and type(upsList) == "table" and type(upsList[1]) == "table" then
            for _, act in pairs(upsList[1]) do
                if type(act) == "table" and act.IsActive == true and type(act.Keybinds) == "table" then
                    for _, kb in ipairs(act.Keybinds) do
                        if kb == key or (targetKc and kb == targetKc) or (typeof(kb) == "EnumItem" and kb.Name == key) then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- silent aim active check
function Config.isSilentAimActive()
    if UserInputService:GetFocusedTextBox() then
        return false
    end

    local key = Config.TOGGLE_AIM_KEY
    local hasKey = key and key ~= "None" and key ~= ""

    local mode = Config.AIM_BIND_MODE or "Toggle"
    if hasKey and mode == "Hold" then
        return Config.isAimKeyHeld()
    end

    return (Config.SILENT_AIM_ENABLED ~= false)
end

-- save settings
function Config.save()
    if type(writefile) ~= "function" then return false, "writefile not available" end

    local payload = {
        SILENT_AIM_ENABLED = Config.SILENT_AIM_ENABLED,
        KEEP_TARGET_LOCK = Config.KEEP_TARGET_LOCK,
        FOV_DEG = Config.FOV_DEG or 30,
        FOV_CIRCLE_ENABLED = Config.FOV_CIRCLE_ENABLED,
        FOV_CIRCLE_TRANSPARENCY = Config.FOV_CIRCLE_TRANSPARENCY,
        BODYPART_TARGET_HL = Config.BODYPART_TARGET_HL,
        TARGET_PRIORITY = Config.TARGET_PRIORITY or "Auto",
        AIM_OCCLUSION_CHECK = (Config.AIM_OCCLUSION_CHECK == true),
        WALLBANG_ENABLED = Config.WALLBANG_ENABLED,

        ESP_ENABLED = Config.ESP_ENABLED,
        SKELETON_ENABLED = Config.SKELETON_ENABLED,
        VIEWANGLE_ENABLED = Config.VIEWANGLE_ENABLED,
        OFFSCREEN_ARROWS = Config.OFFSCREEN_ARROWS,
        DISABLE_TEAMMATES = Config.DISABLE_TEAMMATES,
        OCCLUSION_CHECK_ENABLED = Config.OCCLUSION_CHECK_ENABLED,
        SPECTATE_CHECKER_ENABLED = Config.SPECTATE_CHECKER_ENABLED,

        BHOP_ENABLED = Config.BHOP_ENABLED,

        ANTI_FLASH_ENABLED = Config.ANTI_FLASH_ENABLED,
        ANTI_FLASH_TRANSPARENCY = Config.ANTI_FLASH_TRANSPARENCY,

        CUSTOM_RPM_ENABLED = Config.CUSTOM_RPM_ENABLED,
        CUSTOM_RPM_VALUE = Config.CUSTOM_RPM_VALUE,
        FORCE_FULL_AUTO = Config.FORCE_FULL_AUTO,
        AUTO_LAUNCH_SKINCHANGER = (Config.AUTO_LAUNCH_SKINCHANGER == true),

        SKINS_ENABLED = Config.SKINS_ENABLED,
        KNIFE_SKINS_ENABLED = Config.KNIFE_SKINS_ENABLED,
        WEAPON_SKINS_ENABLED = Config.WEAPON_SKINS_ENABLED,
        KNIFE_MODEL = Config.KNIFE_MODEL or "Butterfly Knife",
        KNIFE_SKIN = Config.KNIFE_SKIN or "Special",
        SELECTED_WEAPON_TYPE = Config.SELECTED_WEAPON_TYPE or "AK-47",
        SELECTED_SKINS = Config.SELECTED_SKINS or {},
        SKIN_MODE = Config.SKIN_MODE or "Special",
        EQUIP_BUTTERFLY_KNIFE = Config.EQUIP_BUTTERFLY_KNIFE,

        WINDOW_SIZE_X = Config.WINDOW_SIZE_X or 440,
        WINDOW_SIZE_Y = Config.WINDOW_SIZE_Y or 210,

        TOGGLE_UI_KEY = Config.TOGGLE_UI_KEY and Config.TOGGLE_UI_KEY.Name or "None",
        TOGGLE_UI_KEY_ALT = Config.TOGGLE_UI_KEY_ALT and Config.TOGGLE_UI_KEY_ALT.Name or "None",
        TOGGLE_AIM_KEY = (type(Config.TOGGLE_AIM_KEY) == "string" and Config.TOGGLE_AIM_KEY) or (Config.TOGGLE_AIM_KEY and Config.TOGGLE_AIM_KEY.Name) or "None",
        AIM_BIND_MODE = Config.AIM_BIND_MODE or "Toggle",
        TOGGLE_ESP_KEY = Config.TOGGLE_ESP_KEY and Config.TOGGLE_ESP_KEY.Name or "None",
        UNLOAD_KEY = Config.UNLOAD_KEY and Config.UNLOAD_KEY.Name or "None"
    }

    ensureDirectory()
    local ok, encoded = pcall(function() return HttpService:JSONEncode(payload) end)
    if ok and encoded then
        local writeOk, err = pcall(writefile, CONFIG_FILE, encoded)
        if writeOk then
            return true
        end
    end
    return false
end

-- load settings
function Config.load()
    if type(readfile) ~= "function" then return false end

    local exists = false
    if type(isfile) == "function" then
        exists = isfile(CONFIG_FILE)
    else
        local testOk, testData = pcall(readfile, CONFIG_FILE)
        exists = testOk and (testData ~= nil and #testData > 0)
    end

    if not exists then return false end

    local ok, raw = pcall(readfile, CONFIG_FILE)
    if not ok or not raw or #raw == 0 then return false end

    local decodeOk, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not decodeOk or type(data) ~= "table" then return false end

    for key, val in pairs(data) do
        if key == "TOGGLE_AIM_KEY" then
            if val == "None" or val == nil or val == "" then
                Config[key] = nil
            elseif val == "MB1" or val == "MB2" or val == "MB3" then
                Config[key] = val
            else
                local kc = Enum.KeyCode[val]
                Config[key] = kc or nil
            end
        elseif key == "TOGGLE_UI_KEY" or key == "TOGGLE_UI_KEY_ALT" or key == "TOGGLE_ESP_KEY" or key == "UNLOAD_KEY" then
            if val == "None" or val == nil or val == "" then
                Config[key] = nil
            else
                local kc = Enum.KeyCode[val]
                Config[key] = kc or nil
            end
        elseif key == "AIM_BIND_MODE" then
            Config.AIM_BIND_MODE = (val == "Hold") and "Hold" or "Toggle"
        elseif key == "AUTO_LAUNCH_SKINCHANGER" then
            Config.AUTO_LAUNCH_SKINCHANGER = (val == true)
        elseif key == "KNIFE_SKINS_ENABLED" then
            Config.KNIFE_SKINS_ENABLED = (val == true)
        elseif key == "WEAPON_SKINS_ENABLED" then
            Config.WEAPON_SKINS_ENABLED = (val == true)
        elseif key == "SELECTED_WEAPON_TYPE" then
            Config.SELECTED_WEAPON_TYPE = tostring(val)
        elseif key == "SELECTED_SKINS" and type(val) == "table" then
            Config.SELECTED_SKINS = val
        elseif key == "KNIFE_MODEL" then
            Config.KNIFE_MODEL = tostring(val)
        elseif key == "KNIFE_SKIN" then
            Config.KNIFE_SKIN = tostring(val)
        elseif key == "SKIN_MODE" then
            local str = tostring(val)
            Config.SKIN_MODE = (str == "Random") and "Random" or "Special"
        elseif key == "FOV_DEG" then
            Config.FOV_DEG = tonumber(val) or 30
        elseif key == "FOV_RADIUS" and not data.FOV_DEG then
            local num = tonumber(val) or 30
            Config.FOV_DEG = (num > 180) and 30 or num
        elseif key == "WINDOW_SIZE_X" or key == "WINDOW_SIZE_Y" then
            local num = tonumber(val)
            if num and num > 0 then Config[key] = num end
        elseif Config[key] ~= nil and type(Config[key]) == type(val) then
            Config[key] = val
        end
    end

    return true
end

-- reset defaults
function Config.reset()
    for key, val in pairs(DEFAULT_VALUES) do
        if key == "TOGGLE_UI_KEY" or key == "TOGGLE_UI_KEY_ALT" or key == "TOGGLE_AIM_KEY" or key == "UNLOAD_KEY" then
            local kc = Enum.KeyCode[val]
            if kc then Config[key] = kc else Config[key] = (val == "None" and nil or val) end
        else
            Config[key] = val
        end
    end
    Config.save()
end

return Config

end
__mods["DamageEngine"] = function()
-- damage calculations
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local DamageEngine = {}

local WeaponsDB = ReplicatedStorage:FindFirstChild("Database")
if WeaponsDB then WeaponsDB = WeaponsDB:FindFirstChild("Custom") end
if WeaponsDB then WeaponsDB = WeaponsDB:FindFirstChild("Weapons") end

local weaponCache = {}

function DamageEngine.getWeaponConfig(weaponName)
    if not WeaponsDB or not weaponName then return nil end
    if weaponCache[weaponName] then return weaponCache[weaponName] end
    local mod = WeaponsDB:FindFirstChild(weaponName)
    if not mod then return nil end
    local ok, cfg = pcall(require, mod)
    if ok and cfg then
        weaponCache[weaponName] = cfg
        return cfg
    end
    return nil
end

local cachedCurrentEquippedRaw = nil
local cachedParsedWeaponName = nil

function DamageEngine.getCurrentWeapon()
    local attr = LocalPlayer:GetAttribute("CurrentEquipped")
    if not attr then return nil end

    if attr == cachedCurrentEquippedRaw then
        return cachedParsedWeaponName
    end

    cachedCurrentEquippedRaw = attr

    if typeof(attr) == "string" then
        local ok, parsed = pcall(HttpService.JSONDecode, HttpService, attr)
        if ok and parsed and parsed.Name then
            cachedParsedWeaponName = parsed.Name
            return cachedParsedWeaponName
        end
    elseif typeof(attr) == "table" and attr.Name then
        cachedParsedWeaponName = attr.Name
        return cachedParsedWeaponName
    end

    cachedParsedWeaponName = nil
    return nil
end

function DamageEngine.getPlayerArmor(player)
    if not player then return "None" end
    local armorAttr = player:GetAttribute("Armor")
    if not armorAttr then return "None" end

    if typeof(armorAttr) == "string" then
        if armorAttr:find("Helmet") then
            return "Kevlar + Helmet"
        elseif armorAttr:find("Kevlar") then
            return "Kevlar"
        end
        local ok, parsed = pcall(HttpService.JSONDecode, HttpService, armorAttr)
        if ok and parsed and parsed.Type then
            return parsed.Type
        end
    elseif typeof(armorAttr) == "table" and armorAttr.Type then
        return armorAttr.Type
    end
    return "None"
end

function DamageEngine.calcDamage(weaponCfg, zone, distance, armorType, falloffRef)
    local baseDmg = weaponCfg.DamagePerPart and weaponCfg.DamagePerPart[zone]
    if not baseDmg then return 0 end

    falloffRef = falloffRef or 500
    local rangeMod = weaponCfg.RangeModifier or 1
    local rawDmg = baseDmg * (rangeMod ^ (distance / falloffRef))

    local hasArmor = (armorType == "Kevlar" or armorType == "Kevlar + Helmet")
    local hasHelmet = (armorType == "Kevlar + Helmet")

    local armorCoversZone = false
    if zone == "Head" then
        armorCoversZone = hasHelmet
    elseif zone == "Torso" or zone == "Arms" then
        armorCoversZone = hasArmor
    end

    if armorCoversZone then
        local armorPen = weaponCfg.ArmorPenetration or 1
        rawDmg = rawDmg * armorPen
    end

    return math.floor(rawDmg)
end

-- lethal part solver
function DamageEngine.getOptimalTargetPart(weaponCfg, targetChar, targetPlayer, myDistance, hp, falloffRef)
    if not weaponCfg or not weaponCfg.DamagePerPart then
        return "Head"
    end

    local armorType = DamageEngine.getPlayerArmor(targetPlayer)
    local bulletsPerShot = weaponCfg.BulletsPerShot or 1

    local pelletHeadDmg = DamageEngine.calcDamage(weaponCfg, "Head", myDistance, armorType, falloffRef)
    local pelletBodyDmg = DamageEngine.calcDamage(weaponCfg, "Torso", myDistance, armorType, falloffRef)

    local totalBodyBurst
    if bulletsPerShot > 1 then
        totalBodyBurst = pelletBodyDmg * math.floor(bulletsPerShot * 0.75)
    else
        totalBodyBurst = pelletBodyDmg
    end

    if totalBodyBurst >= hp then
        return "Torso"
    else
        return "Head"
    end
end

return DamageEngine

end
__mods["ESPManager"] = function()
-- esp manager
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local ESPManager = {}

local CharHL = require(ReplicatedStorage.Classes.CharacterHighlight)
local _G_originalUpdateState = CharHL.UpdateState
_G.__originalUpdateState = _G_originalUpdateState

local coreContainer = nil
local skeletonDrawings = {}
local occlusionCache = {}
local occlusionTime = {}

local function darkenColor(color, factor)
    factor = factor or 0.45
    return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

function ESPManager.init(Config, Utils, SkeletonRenderer)
    function CharHL.UpdateState(self, state)
        if not Config.ESP_HIGHLIGHT_ENABLED then
            if self.Highlight then
                self.Highlight.Enabled = false
            end
            self.IsEnabled = false
            return
        end
        return _G_originalUpdateState(self, state)
    end

    coreContainer = CoreGui:FindFirstChild("AG_Persistent_ESP")
    if not coreContainer then
        coreContainer = Instance.new("Folder")
        coreContainer.Name = "AG_Persistent_ESP"
        coreContainer.Parent = CoreGui
    end
    coreContainer:ClearAllChildren()

    return coreContainer
end

function ESPManager.update(Config, Utils, SkeletonRenderer)
    if Config.ESP_ENABLED == false then
        for _, drawObj in pairs(skeletonDrawings) do
            SkeletonRenderer.hide(drawObj)
        end
        return
    end

    local charsFolder = Workspace:FindFirstChild("Characters")
    if not charsFolder then
        for charInstance, drawObj in pairs(skeletonDrawings) do
            SkeletonRenderer.destroy(drawObj)
        end
        table.clear(skeletonDrawings)
        return
    end

    local myChar = Utils.getAliveCharacter(LocalPlayer)
    local seen = {}

    local function processModel(char)
        if not char or not char:IsA("Model") or char.Parent ~= charsFolder then return end
        if char.Name == LocalPlayer.Name or (myChar and char == myChar) then return end
        if char:GetAttribute("Dead") == true then return end

        local hp, maxHp = Utils.getCharacterHealth(char)
        if hp <= 0 then return end

        local p = Players:FindFirstChild(char.Name)
        local team = Utils.getTeam(p, char)
        if not team or (team ~= "Counter-Terrorists" and team ~= "CT" and team ~= "Terrorists" and team ~= "T") then
            return
        end

        local isEnemy = Utils.isEnemy(p, char)
        if Config.DISABLE_TEAMMATES and not isEnemy then
            return
        end

        seen[char] = true

        local isAimActive = (type(Config.isSilentAimActive) == "function") and Config.isSilentAimActive() or (Config.SILENT_AIM_ENABLED ~= false)
        local isTarget = isAimActive and (Config.CurrentTargetChar ~= nil) and (char == Config.CurrentTargetChar)
        local baseColor

        if isTarget then
            baseColor = Config.TARGET_COLOR
        else
            local isCT = (team == "Counter-Terrorists" or team == "CT")
            baseColor = isCT and Config.CT_COLOR or Config.T_COLOR
        end

        -- occlusion color dimming (10hz)
        local isOccluded = false
        if Config.OCCLUSION_CHECK_ENABLED then
            local now = os.clock()
            if (now - (occlusionTime[char] or 0)) > 0.1 then
                occlusionCache[char] = Utils.isTargetOccluded(char)
                occlusionTime[char] = now
            end
            isOccluded = occlusionCache[char] or false
        end

        local boneColor = isOccluded and darkenColor(baseColor, Config.OCCLUDED_COLOR_FACTOR) or baseColor

        if Config.SKELETON_ENABLED or Config.OFFSCREEN_ARROWS then
            local drawObj = skeletonDrawings[char]
            if not drawObj then
                drawObj = SkeletonRenderer.create()
                skeletonDrawings[char] = drawObj
            end

            SkeletonRenderer.render(drawObj, char, hp, maxHp, boneColor, baseColor, Config)
        else
            local drawObj = skeletonDrawings[char]
            if drawObj then
                SkeletonRenderer.hide(drawObj)
            end
        end
    end

    for _, child in ipairs(charsFolder:GetChildren()) do
        if child:IsA("Model") then
            processModel(child)
        end
    end

    -- remove dead drawings
    for charInstance, drawObj in pairs(skeletonDrawings) do
        if not seen[charInstance] then
            SkeletonRenderer.hide(drawObj)
            local hp = Utils.getCharacterHealth(charInstance)
            if not charInstance.Parent or charInstance.Parent ~= charsFolder or charInstance:GetAttribute("Dead") == true or hp <= 0 then
                SkeletonRenderer.destroy(drawObj)
                skeletonDrawings[charInstance] = nil
            end
        end
    end
end

function ESPManager.cleanup(SkeletonRenderer)
    if _G.__originalUpdateState then
        pcall(function() CharHL.UpdateState = _G.__originalUpdateState end)
    end
    if coreContainer then
        pcall(function() coreContainer:ClearAllChildren() end)
        pcall(function() coreContainer:Destroy() end)
    end

    for _, drawObj in pairs(skeletonDrawings) do
        SkeletonRenderer.destroy(drawObj)
    end
    skeletonDrawings = {}
end

return ESPManager

end
__mods["LinoriaLib"] = function()
local InputService = game:GetService('UserInputService');
local ContextActionService = game:GetService('ContextActionService');
local TextService = game:GetService('TextService');
local CoreGui = game:GetService('CoreGui');
local Teams = game:GetService('Teams');
local Players = game:GetService('Players');
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local Mouse = LocalPlayer:GetMouse();
-- ===== [mobile] 触屏兼容 shim =====
local __touchDown = false
local __touchPos = Vector2.new(0, 0)
pcall(function()
    InputService.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then
            __touchDown = true
            __touchPos = Vector2.new(i.Position.X, i.Position.Y)
        end
    end)
    InputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then __touchDown = false end
    end)
    InputService.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then
            __touchPos = Vector2.new(i.Position.X, i.Position.Y)
        end
    end)
end)
local function __isPrimary(Input)
    if not Input then return false end
    return Input.UserInputType == Enum.UserInputType.MouseButton1
        or Input.UserInputType == Enum.UserInputType.Touch
end
local function __pointerDown()
    if __touchDown then return true end
    local ok, down = pcall(function() return InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
    return ok and down
end
local function __mx() return (InputService.TouchEnabled and __touchDown) and __touchPos.X or Mouse.X end
local function __my() return (InputService.TouchEnabled and __touchDown) and __touchPos.Y or Mouse.Y end
-- ===== [mobile] shim end =====


local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);

local ScreenGui = Instance.new('ScreenGui');
ProtectGui(ScreenGui);

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
local safeParent = (type(gethui) == "function" and gethui()) or CoreGui or (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"));
ScreenGui.Parent = safeParent;

local Toggles = {};
local Options = {};

getgenv().Toggles = Toggles;
getgenv().Options = Options;

local Library = {
    Registry = {};
    RegistryMap = {};

    HudRegistry = {};

    FontColor = Color3.fromRGB(250, 250, 250);
    MainColor = Color3.fromRGB(26, 26, 30);
    BackgroundColor = Color3.fromRGB(18, 18, 22);
    AccentColor = Color3.fromRGB(245, 125, 25);
    OutlineColor = Color3.fromRGB(52, 54, 62);
    RiskColor = Color3.fromRGB(255, 60, 60),

    Black = Color3.new(0, 0, 0);
    Font = Enum.Font.Code,

    OpenedFrames = {};
    DependencyBoxes = {};

    Signals = {};
    ScreenGui = ScreenGui;
};

local RainbowStep = 0
local Hue = 0

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
    RainbowStep = RainbowStep + Delta

    if RainbowStep >= (1 / 60) then
        RainbowStep = 0

        Hue = Hue + (1 / 400);

        if Hue > 1 then
            Hue = 0;
        end;

        Library.CurrentRainbowHue = Hue;
        Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1);
    end
end))

local function GetPlayersString()
    local PlayerList = Players:GetPlayers();

    for i = 1, #PlayerList do
        PlayerList[i] = PlayerList[i].Name;
    end;

    table.sort(PlayerList, function(str1, str2) return str1 < str2 end);

    return PlayerList;
end;

local function GetTeamsString()
    local TeamList = Teams:GetTeams();

    for i = 1, #TeamList do
        TeamList[i] = TeamList[i].Name;
    end;

    table.sort(TeamList, function(str1, str2) return str1 < str2 end);
    
    return TeamList;
end;

function Library:SafeCallback(f, ...)
    if (not f) then
        return;
    end;

    if not Library.NotifyOnError then
        return f(...);
    end;

    local success, event = pcall(f, ...);

    if not success then
        local _, i = event:find(":%d+: ");

        if not i then
            return Library:Notify(event);
        end;

        return Library:Notify(event:sub(i + 1), 3);
    end;
end;

function Library:AttemptSave()
    if Library.SaveManager then
        Library.SaveManager:Save();
    end;
end;

function Library:Create(Class, Properties)
    local _Instance = Class;

    if type(Class) == 'string' then
        _Instance = Instance.new(Class);
    end;

    for Property, Value in next, Properties do
        _Instance[Property] = Value;
    end;

    return _Instance;
end;

function Library:ApplyTextStroke(Inst)
    Inst.TextStrokeTransparency = 1;

    Library:Create('UIStroke', {
        Color = Color3.new(0, 0, 0);
        Thickness = 1;
        LineJoinMode = Enum.LineJoinMode.Miter;
        Parent = Inst;
    });
end;

function Library:CreateLabel(Properties, IsHud)
    local _Instance = Library:Create('TextLabel', {
        BackgroundTransparency = 1;
        Font = Library.Font;
        TextColor3 = Library.FontColor;
        TextSize = 16;
        TextStrokeTransparency = 0;
    });

    Library:ApplyTextStroke(_Instance);

    Library:AddToRegistry(_Instance, {
        TextColor3 = 'FontColor';
    }, IsHud);

    return Library:Create(_Instance, Properties);
end;

function Library:MakeDraggable(Instance, Cutoff)
    Instance.Active = true;

    Instance.InputBegan:Connect(function(Input)
        if __isPrimary(Input) then
            local ObjPos = Vector2.new(
                __mx() - Instance.AbsolutePosition.X,
                __my() - Instance.AbsolutePosition.Y
            );

            if ObjPos.Y > (Cutoff or 40) then
                return;
            end;

            while __pointerDown() do
                Instance.Position = UDim2.new(
                    0,
                    __mx() - ObjPos.X + (Instance.Size.X.Offset * Instance.AnchorPoint.X),
                    0,
                    __my() - ObjPos.Y + (Instance.Size.Y.Offset * Instance.AnchorPoint.Y)
                );

                RenderStepped:Wait();
            end;
        end;
    end)
end;

function Library:MakeResizable(Instance, MinWidth, MinHeight, MaxWidth, MaxHeight, ResizeCallback)
    local function getMinWidth()
        if type(MinWidth) == 'function' then return MinWidth() end
        return MinWidth or 440;
    end
    local function getMinHeight()
        if type(MinHeight) == 'function' then return MinHeight() end
        return MinHeight or 210;
    end
    local function getMaxWidth()
        if type(MaxWidth) == 'function' then return MaxWidth() end
        return MaxWidth or 1200;
    end
    local function getMaxHeight()
        if type(MaxHeight) == 'function' then return MaxHeight() end
        return MaxHeight or 900;
    end

    local ResizeGrip = Library:Create('ImageButton', {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -2, 1, -2),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ZIndex = 50,
        Parent = Instance,
        AutoButtonColor = false
    });

    local Dots = {};
    local dotCoords = {
        { -3, -3 }, { -7, -3 }, { -3, -7 },
        { -11, -3 }, { -7, -7 }, { -3, -11 }
    };

    for _, coord in ipairs(dotCoords) do
        local dot = Library:Create('Frame', {
            BackgroundColor3 = Library.OutlineColor,
            BorderSizePixel = 0,
            Position = UDim2.new(1, coord[1], 1, coord[2]),
            Size = UDim2.new(0, 2, 0, 2),
            ZIndex = 51,
            Parent = ResizeGrip
        });
        table.insert(Dots, dot);
        Library:AddToRegistry(dot, {
            BackgroundColor3 = 'OutlineColor'
        });
    end

    ResizeGrip.MouseEnter:Connect(function()
        for _, dot in ipairs(Dots) do
            dot.BackgroundColor3 = Library.AccentColor;
        end
    end);

    ResizeGrip.MouseLeave:Connect(function()
        for _, dot in ipairs(Dots) do
            dot.BackgroundColor3 = Library.OutlineColor;
        end
    end);

    ResizeGrip.InputBegan:Connect(function(Input)
        if __isPrimary(Input) then
            local startMouse = Vector2.new(__mx(), __my());
            local startSize = Instance.AbsoluteSize;

            if Instance.AnchorPoint == Vector2.new(0.5, 0.5) then
                local currentAbsPos = Instance.AbsolutePosition;
                Instance.AnchorPoint = Vector2.zero;
                Instance.Position = UDim2.fromOffset(currentAbsPos.X, currentAbsPos.Y);
            end

            while __pointerDown() do
                local deltaX = __mx() - start__mx();
                local deltaY = __my() - start__my();

                local newWidth = math.clamp(startSize.X + deltaX, getMinWidth(), getMaxWidth());
                local newHeight = math.clamp(startSize.Y + deltaY, getMinHeight(), getMaxHeight());

                Instance.Size = UDim2.fromOffset(newWidth, newHeight);

                if type(ResizeCallback) == 'function' then
                    ResizeCallback(newWidth, newHeight);
                end

                RenderStepped:Wait();
            end;
        end
    end);
end;

function Library:AddToolTip(InfoStr, HoverInstance)
    local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14);
    local Tooltip = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,

        Size = UDim2.fromOffset(X + 5, Y + 4),
        ZIndex = 100,
        Parent = Library.ScreenGui,

        Visible = false,
    })

    local Label = Library:CreateLabel({
        Position = UDim2.fromOffset(3, 1),
        Size = UDim2.fromOffset(X, Y);
        TextSize = 14;
        Text = InfoStr,
        TextColor3 = Library.FontColor,
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = Tooltip.ZIndex + 1,

        Parent = Tooltip;
    });

    Library:AddToRegistry(Tooltip, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    Library:AddToRegistry(Label, {
        TextColor3 = 'FontColor',
    });

    local IsHovering = false

    HoverInstance.MouseEnter:Connect(function()
        if Library:MouseIsOverOpenedFrame() then
            return
        end

        IsHovering = true

        Tooltip.Position = UDim2.fromOffset(__mx() + 15, __my() + 12)
        Tooltip.Visible = true

        while IsHovering do
            RunService.Heartbeat:Wait()
            Tooltip.Position = UDim2.fromOffset(__mx() + 15, __my() + 12)
        end
    end)

    HoverInstance.MouseLeave:Connect(function()
        IsHovering = false
        Tooltip.Visible = false
    end)
end

function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
    HighlightInstance.MouseEnter:Connect(function()
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, Properties do
            Instance[Property] = Library[ColorIdx] or ColorIdx;

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end)

    HighlightInstance.MouseLeave:Connect(function()
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, PropertiesDefault do
            Instance[Property] = Library[ColorIdx] or ColorIdx;

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end)
end;

function Library:MouseIsOverOpenedFrame()
    for Frame, _ in next, Library.OpenedFrames do
        local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

        if __mx() >= AbsPos.X and __mx() <= AbsPos.X + AbsSize.X
            and __my() >= AbsPos.Y and __my() <= AbsPos.Y + AbsSize.Y then

            return true;
        end;
    end;
end;

function Library:IsMouseOverFrame(Frame)
    local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

    if __mx() >= AbsPos.X and __mx() <= AbsPos.X + AbsSize.X
        and __my() >= AbsPos.Y and __my() <= AbsPos.Y + AbsSize.Y then

        return true;
    end;
end;

function Library:UpdateDependencyBoxes()
    for _, Depbox in next, Library.DependencyBoxes do
        Depbox:Update();
    end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
    return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

function Library:GetTextBounds(Text, Font, Size, Resolution)
    local Bounds = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080))
    return Bounds.X, Bounds.Y
end;

function Library:GetDarkerColor(Color)
    local H, S, V = Color3.toHSV(Color);
    return Color3.fromHSV(H, S, V / 1.5);
end;
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:AddToRegistry(Instance, Properties, IsHud)
    local Idx = #Library.Registry + 1;
    local Data = {
        Instance = Instance;
        Properties = Properties;
        Idx = Idx;
    };

    table.insert(Library.Registry, Data);
    Library.RegistryMap[Instance] = Data;

    if IsHud then
        table.insert(Library.HudRegistry, Data);
    end;
end;

function Library:RemoveFromRegistry(Instance)
    local Data = Library.RegistryMap[Instance];

    if Data then
        for Idx = #Library.Registry, 1, -1 do
            if Library.Registry[Idx] == Data then
                table.remove(Library.Registry, Idx);
            end;
        end;

        for Idx = #Library.HudRegistry, 1, -1 do
            if Library.HudRegistry[Idx] == Data then
                table.remove(Library.HudRegistry, Idx);
            end;
        end;

        Library.RegistryMap[Instance] = nil;
    end;
end;

function Library:UpdateColorsUsingRegistry()
    -- TODO: Could have an 'active' list of objects
    -- where the active list only contains Visible objects.

    -- IMPL: Could setup .Changed events on the AddToRegistry function
    -- that listens for the 'Visible' propert being changed.
    -- Visible: true => Add to active list, and call UpdateColors function
    -- Visible: false => Remove from active list.

    -- The above would be especially efficient for a rainbow menu color or live color-changing.

    for Idx, Object in next, Library.Registry do
        for Property, ColorIdx in next, Object.Properties do
            if type(ColorIdx) == 'string' then
                Object.Instance[Property] = Library[ColorIdx];
            elseif type(ColorIdx) == 'function' then
                Object.Instance[Property] = ColorIdx()
            end
        end;
    end;
end;

function Library:GiveSignal(Signal)
    -- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
    table.insert(Library.Signals, Signal)
end

function Library:Unload()
    -- Unload all of the signals
    for Idx = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, Idx)
        Connection:Disconnect()
    end

     -- Call our unload callback, maybe to undo some hooks etc
    if Library.OnUnload then
        Library.OnUnload()
    end

    ScreenGui:Destroy()
end

function Library:OnUnload(Callback)
    Library.OnUnload = Callback
end

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
    if Library.RegistryMap[Instance] then
        Library:RemoveFromRegistry(Instance);
    end;
end))

local BaseAddons = {};

do
    local Funcs = {};

    function Funcs:AddColorPicker(Idx, Info)
        local ToggleLabel = self.TextLabel;
        -- local Container = self.Container;

        assert(Info.Default, 'AddColorPicker: Missing default value.');

        local ColorPicker = {
            Value = Info.Default;
            Transparency = Info.Transparency or 0;
            Type = 'ColorPicker';
            Title = type(Info.Title) == 'string' and Info.Title or 'Color picker',
            Callback = Info.Callback or function(Color) end;
        };

        function ColorPicker:SetHSVFromRGB(Color)
            local H, S, V = Color3.toHSV(Color);

            ColorPicker.Hue = H;
            ColorPicker.Sat = S;
            ColorPicker.Vib = V;
        end;

        ColorPicker:SetHSVFromRGB(ColorPicker.Value);

        local DisplayFrame = Library:Create('Frame', {
            BackgroundColor3 = ColorPicker.Value;
            BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(0, 28, 0, 14);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        -- Transparency image taken from https://github.com/matas3535/SplixPrivateDrawingLibrary/blob/main/Library.lua cus i'm lazy
        local CheckerFrame = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size = UDim2.new(0, 27, 0, 13);
            ZIndex = 5;
            Image = 'http://www.roblox.com/asset/?id=12977615774';
            Visible = not not Info.Transparency;
            Parent = DisplayFrame;
        });

        -- 1/16/23
        -- Rewrote this to be placed inside the Library ScreenGui
        -- There was some issue which caused RelativeOffset to be way off
        -- Thus the color picker would never show

        local PickerFrameOuter = Library:Create('Frame', {
            Name = 'Color';
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18),
            Size = UDim2.fromOffset(230, Info.Transparency and 271 or 253);
            Visible = false;
            ZIndex = 15;
            Parent = ScreenGui,
        });

        DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            PickerFrameOuter.Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18);
        end)

        local PickerFrameInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 16;
            Parent = PickerFrameOuter;
        });

        local Highlight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 2);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.new(0, 4, 0, 25);
            Size = UDim2.new(0, 200, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Parent = SatVibMapOuter;
        });

        local SatVibMap = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Image = 'rbxassetid://4155801252';
            Parent = SatVibMapInner;
        });

        local CursorOuter = Library:Create('ImageLabel', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Size = UDim2.new(0, 6, 0, 6);
            BackgroundTransparency = 1;
            Image = 'http://www.roblox.com/asset/?id=9619665977';
            ImageColor3 = Color3.new(0, 0, 0);
            ZIndex = 19;
            Parent = SatVibMap;
        });

        local CursorInner = Library:Create('ImageLabel', {
            Size = UDim2.new(0, CursorOuter.Size.X.Offset - 2, 0, CursorOuter.Size.Y.Offset - 2);
            Position = UDim2.new(0, 1, 0, 1);
            BackgroundTransparency = 1;
            Image = 'http://www.roblox.com/asset/?id=9619665977';
            ZIndex = 20;
            Parent = CursorOuter;
        })

        local HueSelectorOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.new(0, 208, 0, 25);
            Size = UDim2.new(0, 15, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local HueSelectorInner = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Parent = HueSelectorOuter;
        });

        local HueCursor = Library:Create('Frame', { 
            BackgroundColor3 = Color3.new(1, 1, 1);
            AnchorPoint = Vector2.new(0, 0.5);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 18;
            Parent = HueSelectorInner;
        });

        local HueBoxOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(4, 228),
            Size = UDim2.new(0.5, -6, 0, 20),
            ZIndex = 18,
            Parent = PickerFrameInner;
        });

        local HueBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18,
            Parent = HueBoxOuter;
        });

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = HueBoxInner;
        });

        local HueBox = Library:Create('TextBox', {
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);
            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
            PlaceholderText = 'Hex color',
            Text = '#FFFFFF',
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 20,
            Parent = HueBoxInner;
        });

        Library:ApplyTextStroke(HueBox);

        local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
            Position = UDim2.new(0.5, 2, 0, 228),
            Size = UDim2.new(0.5, -6, 0, 20),
            Parent = PickerFrameInner
        });

        local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild('TextBox'), {
            Text = '255, 255, 255',
            PlaceholderText = 'RGB color',
            TextColor3 = Library.FontColor
        });

        local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor;
        
        if Info.Transparency then 
            TransparencyBoxOuter = Library:Create('Frame', {
                BorderColor3 = Color3.new(0, 0, 0);
                Position = UDim2.fromOffset(4, 251);
                Size = UDim2.new(1, -8, 0, 15);
                ZIndex = 19;
                Parent = PickerFrameInner;
            });

            TransparencyBoxInner = Library:Create('Frame', {
                BackgroundColor3 = ColorPicker.Value;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 19;
                Parent = TransparencyBoxOuter;
            });

            Library:AddToRegistry(TransparencyBoxInner, { BorderColor3 = 'OutlineColor' });

            Library:Create('ImageLabel', {
                BackgroundTransparency = 1;
                Size = UDim2.new(1, 0, 1, 0);
                Image = 'http://www.roblox.com/asset/?id=12978095818';
                ZIndex = 20;
                Parent = TransparencyBoxInner;
            });

            TransparencyCursor = Library:Create('Frame', { 
                BackgroundColor3 = Color3.new(1, 1, 1);
                AnchorPoint = Vector2.new(0.5, 0);
                BorderColor3 = Color3.new(0, 0, 0);
                Size = UDim2.new(0, 1, 1, 0);
                ZIndex = 21;
                Parent = TransparencyBoxInner;
            });
        end;

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 14);
            Position = UDim2.fromOffset(5, 5);
            TextXAlignment = Enum.TextXAlignment.Left;
            TextSize = 14;
            Text = ColorPicker.Title,--Info.Default;
            TextWrapped = false;
            ZIndex = 16;
            Parent = PickerFrameInner;
        });


        local ContextMenu = {}
        do
            ContextMenu.Options = {}
            ContextMenu.Container = Library:Create('Frame', {
                BorderColor3 = Color3.new(),
                ZIndex = 14,

                Visible = false,
                Parent = ScreenGui
            })

            ContextMenu.Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.fromScale(1, 1);
                ZIndex = 15;
                Parent = ContextMenu.Container;
            });

            Library:Create('UIListLayout', {
                Name = 'Layout',
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = ContextMenu.Inner;
            });

            Library:Create('UIPadding', {
                Name = 'Padding',
                PaddingLeft = UDim.new(0, 4),
                Parent = ContextMenu.Inner,
            });

            local function updateMenuPosition()
                ContextMenu.Container.Position = UDim2.fromOffset(
                    (DisplayFrame.AbsolutePosition.X + DisplayFrame.AbsoluteSize.X) + 4,
                    DisplayFrame.AbsolutePosition.Y + 1
                )
            end

            local function updateMenuSize()
                local menuWidth = 60
                for i, label in next, ContextMenu.Inner:GetChildren() do
                    if label:IsA('TextLabel') then
                        menuWidth = math.max(menuWidth, label.TextBounds.X)
                    end
                end

                ContextMenu.Container.Size = UDim2.fromOffset(
                    menuWidth + 8,
                    ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 4
                )
            end

            DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(updateMenuPosition)
            ContextMenu.Inner.Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(updateMenuSize)

            task.spawn(updateMenuPosition)
            task.spawn(updateMenuSize)

            Library:AddToRegistry(ContextMenu.Inner, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            function ContextMenu:Show()
                self.Container.Visible = true
            end

            function ContextMenu:Hide()
                self.Container.Visible = false
            end

            function ContextMenu:AddOption(Str, Callback)
                if type(Callback) ~= 'function' then
                    Callback = function() end
                end

                local Button = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, 0, 0, 15);
                    TextSize = 13;
                    Text = Str;
                    ZIndex = 16;
                    Parent = self.Inner;
                    TextXAlignment = Enum.TextXAlignment.Left,
                });

                Library:OnHighlight(Button, Button, 
                    { TextColor3 = 'AccentColor' },
                    { TextColor3 = 'FontColor' }
                );

                Button.InputBegan:Connect(function(Input)
                    if (not __isPrimary(Input)) then
                        return
                    end

                    Callback()
                end)
            end

            ContextMenu:AddOption('Copy color', function()
                Library.ColorClipboard = ColorPicker.Value
                Library:Notify('Copied color!', 2)
            end)

            ContextMenu:AddOption('Paste color', function()
                if not Library.ColorClipboard then
                    return Library:Notify('You have not copied a color!', 2)
                end
                ColorPicker:SetValueRGB(Library.ColorClipboard)
            end)


            ContextMenu:AddOption('Copy HEX', function()
                pcall(setclipboard, ColorPicker.Value:ToHex())
                Library:Notify('Copied hex code to clipboard!', 2)
            end)

            ContextMenu:AddOption('Copy RGB', function()
                pcall(setclipboard, table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', '))
                Library:Notify('Copied RGB values to clipboard!', 2)
            end)

        end

        Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(Highlight, { BackgroundColor3 = 'AccentColor'; });
        Library:AddToRegistry(SatVibMapInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });

        Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBox, { TextColor3 = 'FontColor', });
        Library:AddToRegistry(HueBox, { TextColor3 = 'FontColor', });

        local SequenceTable = {};

        for Hue = 0, 1, 0.1 do
            table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)));
        end;

        local HueSelectorGradient = Library:Create('UIGradient', {
            Color = ColorSequence.new(SequenceTable);
            Rotation = 90;
            Parent = HueSelectorInner;
        });

        HueBox.FocusLost:Connect(function(enter)
            if enter then
                local success, result = pcall(Color3.fromHex, HueBox.Text)
                if success and typeof(result) == 'Color3' then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
                end
            end

            ColorPicker:Display()
        end)

        RgbBox.FocusLost:Connect(function(enter)
            if enter then
                local r, g, b = RgbBox.Text:match('(%d+),%s*(%d+),%s*(%d+)')
                if r and g and b then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
                end
            end

            ColorPicker:Display()
        end)

        function ColorPicker:Display()
            ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib);
            SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1);

            Library:Create(DisplayFrame, {
                BackgroundColor3 = ColorPicker.Value;
                BackgroundTransparency = ColorPicker.Transparency;
                BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
            });

            if TransparencyBoxInner then
                TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value;
                TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0);
            end;

            CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0);
            HueCursor.Position = UDim2.new(0, 0, ColorPicker.Hue, 0);

            HueBox.Text = '#' .. ColorPicker.Value:ToHex()
            RgbBox.Text = table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', ')

            Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value);
            Library:SafeCallback(ColorPicker.Changed, ColorPicker.Value);
        end;

        function ColorPicker:OnChanged(Func)
            ColorPicker.Changed = Func;
            Func(ColorPicker.Value)
        end;

        function ColorPicker:Show()
            for Frame, Val in next, Library.OpenedFrames do
                if Frame.Name == 'Color' then
                    Frame.Visible = false;
                    Library.OpenedFrames[Frame] = nil;
                end;
            end;

            PickerFrameOuter.Visible = true;
            Library.OpenedFrames[PickerFrameOuter] = true;
        end;

        function ColorPicker:Hide()
            PickerFrameOuter.Visible = false;
            Library.OpenedFrames[PickerFrameOuter] = nil;
        end;

        function ColorPicker:SetValue(HSV, Transparency)
            local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3]);

            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        function ColorPicker:SetValueRGB(Color, Transparency)
            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        SatVibMap.InputBegan:Connect(function(Input)
            if __isPrimary(Input) then
                while __pointerDown() do
                    local MinX = SatVibMap.AbsolutePosition.X;
                    local MaxX = MinX + SatVibMap.AbsoluteSize.X;
                    local MouseX = math.clamp(__mx(), MinX, MaxX);

                    local MinY = SatVibMap.AbsolutePosition.Y;
                    local MaxY = MinY + SatVibMap.AbsoluteSize.Y;
                    local MouseY = math.clamp(__my(), MinY, MaxY);

                    ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX);
                    ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY));
                    ColorPicker:Display();

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        HueSelectorInner.InputBegan:Connect(function(Input)
            if __isPrimary(Input) then
                while __pointerDown() do
                    local MinY = HueSelectorInner.AbsolutePosition.Y;
                    local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y;
                    local MouseY = math.clamp(__my(), MinY, MaxY);

                    ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY));
                    ColorPicker:Display();

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        DisplayFrame.InputBegan:Connect(function(Input)
            if __isPrimary(Input) and not Library:MouseIsOverOpenedFrame() then
                if PickerFrameOuter.Visible then
                    ColorPicker:Hide()
                else
                    ContextMenu:Hide()
                    ColorPicker:Show()
                end;
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ContextMenu:Show()
                ColorPicker:Hide()
            end
        end);

        if TransparencyBoxInner then
            TransparencyBoxInner.InputBegan:Connect(function(Input)
                if __isPrimary(Input) then
                    while __pointerDown() do
                        local MinX = TransparencyBoxInner.AbsolutePosition.X;
                        local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X;
                        local MouseX = math.clamp(__mx(), MinX, MaxX);

                        ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX));

                        ColorPicker:Display();

                        RenderStepped:Wait();
                    end;

                    Library:AttemptSave();
                end;
            end);
        end;

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if __isPrimary(Input) then
                local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize;

                if __mx() < AbsPos.X or __mx() > AbsPos.X + AbsSize.X
                    or __my() < (AbsPos.Y - 20 - 1) or __my() > AbsPos.Y + AbsSize.Y then

                    ColorPicker:Hide();
                end;

                if not Library:IsMouseOverFrame(ContextMenu.Container) then
                    ContextMenu:Hide()
                end
            end;

            if Input.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
                if not Library:IsMouseOverFrame(ContextMenu.Container) and not Library:IsMouseOverFrame(DisplayFrame) then
                    ContextMenu:Hide()
                end
            end
        end))

        ColorPicker:Display();
        ColorPicker.DisplayFrame = DisplayFrame

        Options[Idx] = ColorPicker;

        return self;
    end;

    function Funcs:AddKeyPicker(Idx, Info)
        local ParentObj = self;
        local ToggleLabel = self.TextLabel;
        local Container = self.Container;

        assert(Info.Default, 'AddKeyPicker: Missing default value.');

        local KeyPicker = {
            Value = Info.Default;
            Toggled = false;
            Mode = Info.Mode or 'Toggle'; -- Always, Toggle, Hold
            Type = 'KeyPicker';
            Callback = Info.Callback or function(Value) end;
            ChangedCallback = Info.ChangedCallback or function(New) end;

            SyncToggleState = Info.SyncToggleState or false;
        };

        if KeyPicker.SyncToggleState then
            Info.Modes = { 'Toggle' }
            Info.Mode = 'Toggle'
        end

        local PickOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(0, 28, 0, 15);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        local PickInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 7;
            Parent = PickOuter;
        });

        Library:AddToRegistry(PickInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 13;
            Text = Info.Default;
            TextWrapped = true;
            ZIndex = 8;
            Parent = PickInner;
        });

        local ModeSelectOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
            Size = UDim2.new(0, 60, 0, 45 + 2);
            Visible = false;
            ZIndex = 14;
            Parent = ScreenGui;
        });

        ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            ModeSelectOuter.Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
        end);

        local ModeSelectInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 15;
            Parent = ModeSelectOuter;
        });

        Library:AddToRegistry(ModeSelectInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ModeSelectInner;
        });

        local ContainerLabel = Library:CreateLabel({
            TextXAlignment = Enum.TextXAlignment.Left;
            Size = UDim2.new(1, 0, 0, 18);
            TextSize = 13;
            Visible = false;
            ZIndex = 110;
            Parent = Library.KeybindContainer;
        },  true);

        local Modes = Info.Modes or { 'Always', 'Toggle', 'Hold' };
        local ModeButtons = {};

        for Idx, Mode in next, Modes do
            local ModeButton = {};

            local Label = Library:CreateLabel({
                Active = false;
                Size = UDim2.new(1, 0, 0, 15);
                TextSize = 13;
                Text = Mode;
                ZIndex = 16;
                Parent = ModeSelectInner;
            });

            function ModeButton:Select()
                for _, Button in next, ModeButtons do
                    Button:Deselect();
                end;

                KeyPicker.Mode = Mode;

                Label.TextColor3 = Library.AccentColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

                ModeSelectOuter.Visible = false;
            end;

            function ModeButton:Deselect()
                KeyPicker.Mode = nil;

                Label.TextColor3 = Library.FontColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
            end;

            Label.InputBegan:Connect(function(Input)
                if __isPrimary(Input) then
                    ModeButton:Select();
                    Library:AttemptSave();
                end;
            end);

            if Mode == KeyPicker.Mode then
                ModeButton:Select();
            end;

            ModeButtons[Mode] = ModeButton;
        end;

        function KeyPicker:Update()
            if Info.NoUI then
                return;
            end;

            local State = KeyPicker:GetState();

            ContainerLabel.Text = string.format('[%s] %s (%s)', KeyPicker.Value, Info.Text, KeyPicker.Mode);

            ContainerLabel.Visible = true;
            ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor;

            Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and 'AccentColor' or 'FontColor';

            local YSize = 0
            local XSize = 0

            for _, Label in next, Library.KeybindContainer:GetChildren() do
                if Label:IsA('TextLabel') and Label.Visible then
                    YSize = YSize + 18;
                    if (Label.TextBounds.X > XSize) then
                        XSize = Label.TextBounds.X
                    end
                end;
            end;

            Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 10, 210), 0, YSize + 23)
        end;

        function KeyPicker:GetState()
            if KeyPicker.Mode == 'Always' then
                return true;
            elseif KeyPicker.Mode == 'Hold' then
                if KeyPicker.Value == 'None' then
                    return false;
                end

                local Key = KeyPicker.Value;

                if Key == 'MB1' or Key == 'MB2' then
                    return Key == 'MB1' and __pointerDown()
                        or Key == 'MB2' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2);
                else
                    return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value]);
                end;
            else
                return KeyPicker.Toggled;
            end;
        end;

        function KeyPicker:SetValue(Data)
            local Key, Mode;
            if type(Data) == 'table' then
                Key, Mode = Data[1], Data[2];
            else
                Key = tostring(Data);
            end;
            Key = Key or 'None';
            DisplayLabel.Text = Key;
            KeyPicker.Value = Key;
            if Mode and ModeButtons[Mode] then
                ModeButtons[Mode]:Select();
            end;
            KeyPicker:Update();
        end;

        function KeyPicker:OnClick(Callback)
            KeyPicker.Clicked = Callback
        end

        function KeyPicker:OnChanged(Callback)
            KeyPicker.Changed = Callback
            Callback(KeyPicker.Value)
        end

        if ParentObj.Addons then
            table.insert(ParentObj.Addons, KeyPicker)
        end

        function KeyPicker:DoClick()
            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                ParentObj:SetValue(not ParentObj.Value)
            end

            Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
            Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
        end

        local Picking = false;

        PickOuter.InputBegan:Connect(function(Input)
            if InputService.TouchEnabled then return end -- [mobile] 触屏跳过按键拾取
            if __isPrimary(Input) and not Library:MouseIsOverOpenedFrame() then
                Picking = true;
                Library.IsPickingKey = true;

                DisplayLabel.Text = '';

                local Break;
                local Text = '';

                task.spawn(function()
                    while (not Break) do
                        if Text == '...' then
                            Text = '';
                        end;

                        Text = Text .. '.';
                        DisplayLabel.Text = Text;

                        wait(0.4);
                    end;
                end);

                wait(0.2);

                local Event;
                Event = InputService.InputBegan:Connect(function(Input)
                    local Key;

                    if Input.UserInputType == Enum.UserInputType.Keyboard then
                        if Input.KeyCode == Enum.KeyCode.Backspace then
                            Key = 'None';
                        else
                            Key = Input.KeyCode.Name;
                        end;
                    elseif __isPrimary(Input) then
                        Key = 'MB1';
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
                        Key = 'MB2';
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton3 then
                        Key = 'MB3';
                    end;

                    Break = true;
                    Picking = false;
                    Library.IsPickingKey = false;

                    DisplayLabel.Text = Key or 'None';
                    KeyPicker.Value = Key or 'None';

                    Library:SafeCallback(KeyPicker.ChangedCallback, Key or 'None')
                    Library:SafeCallback(KeyPicker.Changed, Key or 'None')

                    Library:AttemptSave();

                    Event:Disconnect();
                end);
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ModeSelectOuter.Visible = true;
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if (not Picking) and (not Library.IsPickingKey) then
                local Key = KeyPicker.Value;
                if Key and Key ~= 'None' then
                    if KeyPicker.Mode == 'Toggle' then
                        if Key == 'MB1' or Key == 'MB2' or Key == 'MB3' then
                            if (Key == 'MB1' and __isPrimary(Input))
                            or (Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2)
                            or (Key == 'MB3' and Input.UserInputType == Enum.UserInputType.MouseButton3) then
                                KeyPicker.Toggled = not KeyPicker.Toggled;
                                KeyPicker:DoClick();
                            end;
                        elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                            if Input.KeyCode.Name == Key then
                                KeyPicker.Toggled = not KeyPicker.Toggled;
                                KeyPicker:DoClick();
                            end;
                        end;
                    elseif KeyPicker.Mode == 'Hold' then
                        if Key == 'MB1' or Key == 'MB2' or Key == 'MB3' then
                            if (Key == 'MB1' and __isPrimary(Input))
                            or (Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2)
                            or (Key == 'MB3' and Input.UserInputType == Enum.UserInputType.MouseButton3) then
                                KeyPicker.Toggled = true;
                                if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                                    ParentObj:SetValue(true);
                                end;
                                Library:SafeCallback(KeyPicker.Callback, true);
                                Library:SafeCallback(KeyPicker.Clicked, true);
                            end;
                        elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                            if Input.KeyCode.Name == Key then
                                KeyPicker.Toggled = true;
                                if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                                    ParentObj:SetValue(true);
                                end;
                                Library:SafeCallback(KeyPicker.Callback, true);
                                Library:SafeCallback(KeyPicker.Clicked, true);
                            end;
                        end;
                    end;
                end;

                KeyPicker:Update();
            end;

            if __isPrimary(Input) then
                local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize;

                if __mx() < AbsPos.X or __mx() > AbsPos.X + AbsSize.X
                    or __my() < (AbsPos.Y - 20 - 1) or __my() > AbsPos.Y + AbsSize.Y then

                    ModeSelectOuter.Visible = false;
                end;
            end;
        end))

        Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
            if (not Picking) and (not Library.IsPickingKey) then
                local Key = KeyPicker.Value;
                if Key and Key ~= 'None' and KeyPicker.Mode == 'Hold' then
                    if Key == 'MB1' or Key == 'MB2' or Key == 'MB3' then
                        if (Key == 'MB1' and __isPrimary(Input))
                        or (Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2)
                        or (Key == 'MB3' and Input.UserInputType == Enum.UserInputType.MouseButton3) then
                            KeyPicker.Toggled = false;
                            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                                ParentObj:SetValue(false);
                            end;
                            Library:SafeCallback(KeyPicker.Callback, false);
                            Library:SafeCallback(KeyPicker.Clicked, false);
                        end;
                    elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                        if Input.KeyCode.Name == Key then
                            KeyPicker.Toggled = false;
                            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                                ParentObj:SetValue(false);
                            end;
                            Library:SafeCallback(KeyPicker.Callback, false);
                            Library:SafeCallback(KeyPicker.Clicked, false);
                        end;
                    end;
                end;

                KeyPicker:Update();
            end;
        end))

        KeyPicker:Update();

        Options[Idx] = KeyPicker;

        return self;
    end;

    BaseAddons.__index = Funcs;
    BaseAddons.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

local BaseGroupbox = {};

do
    local Funcs = {};

    function Funcs:AddBlank(Size)
        local Groupbox = self;
        local Container = Groupbox.Container;

        Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, Size);
            ZIndex = 1;
            Parent = Container;
        });
    end;

    function Funcs:AddLabel(Text, DoesWrap)
        local Label = {};

        local Groupbox = self;
        local Container = Groupbox.Container;

        local TextLabel = Library:CreateLabel({
            Size = UDim2.new(1, -4, 0, 15);
            TextSize = 14;
            Text = Text;
            TextWrapped = DoesWrap or false,
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        if DoesWrap then
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
            TextLabel.Size = UDim2.new(1, -4, 0, Y)
        else
            Library:Create('UIListLayout', {
                Padding = UDim.new(0, 4);
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Right;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TextLabel;
            });
        end

        Label.TextLabel = TextLabel;
        Label.Container = Container;

        function Label:SetText(Text)
            TextLabel.Text = Text

            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
                TextLabel.Size = UDim2.new(1, -4, 0, Y)
            end

            Groupbox:Resize();
        end

        if (not DoesWrap) then
            setmetatable(Label, BaseAddons);
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Label;
    end;

    function Funcs:AddButton(...)
        -- TODO: Eventually redo this
        local Button = {};
        local function ProcessButtonParams(Class, Obj, ...)
            local Props = select(1, ...)
            if type(Props) == 'table' then
                Obj.Text = Props.Text
                Obj.Func = Props.Func
                Obj.DoubleClick = Props.DoubleClick
                Obj.Tooltip = Props.Tooltip
            else
                Obj.Text = select(1, ...)
                Obj.Func = select(2, ...)
            end

            assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
        end

        ProcessButtonParams('Button', Button, ...)

        local Groupbox = self;
        local Container = Groupbox.Container;

        local function CreateBaseButton(Button)
            local Outer = Library:Create('Frame', {
                BackgroundColor3 = Color3.new(0, 0, 0);
                BorderColor3 = Color3.new(0, 0, 0);
                Size = UDim2.new(1, -4, 0, 20);
                ZIndex = 5;
            });

            local Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 6;
                Parent = Outer;
            });

            local Label = Library:CreateLabel({
                Size = UDim2.new(1, 0, 1, 0);
                TextSize = 14;
                Text = Button.Text;
                ZIndex = 6;
                Parent = Inner;
            });

            Library:Create('UIGradient', {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
                });
                Rotation = 90;
                Parent = Inner;
            });

            Library:AddToRegistry(Outer, {
                BorderColor3 = 'Black';
            });

            Library:AddToRegistry(Inner, {
                BackgroundColor3 = 'MainColor';
                BorderColor3 = 'OutlineColor';
            });

            Library:OnHighlight(Outer, Outer,
                { BorderColor3 = 'AccentColor' },
                { BorderColor3 = 'Black' }
            );

            return Outer, Inner, Label
        end

        local function InitEvents(Button)
            local function WaitForEvent(event, timeout, validator)
                local bindable = Instance.new('BindableEvent')
                local connection = event:Once(function(...)

                    if type(validator) == 'function' and validator(...) then
                        bindable:Fire(true)
                    else
                        bindable:Fire(false)
                    end
                end)
                task.delay(timeout, function()
                    connection:disconnect()
                    bindable:Fire(false)
                end)
                return bindable.Event:Wait()
            end

            local function ValidateClick(Input)
                if Library:MouseIsOverOpenedFrame() then
                    return false
                end

                if (not __isPrimary(Input)) then
                    return false
                end

                return true
            end

            Button.Outer.InputBegan:Connect(function(Input)
                if not ValidateClick(Input) then return end
                if Button.Locked then return end

                if Button.DoubleClick then
                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'AccentColor' })

                    Button.Label.TextColor3 = Library.AccentColor
                    Button.Label.Text = 'Are you sure?'
                    Button.Locked = true

                    local clicked = WaitForEvent(Button.Outer.InputBegan, 0.5, ValidateClick)

                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'FontColor' })

                    Button.Label.TextColor3 = Library.FontColor
                    Button.Label.Text = Button.Text
                    task.defer(rawset, Button, 'Locked', false)

                    if clicked then
                        Library:SafeCallback(Button.Func)
                    end

                    return
                end

                Library:SafeCallback(Button.Func);
            end)
        end

        Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
        Button.Outer.Parent = Container

        InitEvents(Button)

        function Button:AddTooltip(tooltip)
            if type(tooltip) == 'string' then
                Library:AddToolTip(tooltip, self.Outer)
            end
            return self
        end


        function Button:AddButton(...)
            local SubButton = {}

            ProcessButtonParams('SubButton', SubButton, ...)

            self.Outer.Size = UDim2.new(0.5, -2, 0, 20)

            SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

            SubButton.Outer.Position = UDim2.new(1, 3, 0, 0)
            SubButton.Outer.Size = UDim2.fromOffset(self.Outer.AbsoluteSize.X - 2, self.Outer.AbsoluteSize.Y)
            SubButton.Outer.Parent = self.Outer

            function SubButton:AddTooltip(tooltip)
                if type(tooltip) == 'string' then
                    Library:AddToolTip(tooltip, self.Outer)
                end
                return SubButton
            end

            if type(SubButton.Tooltip) == 'string' then
                SubButton:AddTooltip(SubButton.Tooltip)
            end

            InitEvents(SubButton)
            return SubButton
        end

        if type(Button.Tooltip) == 'string' then
            Button:AddTooltip(Button.Tooltip)
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Button;
    end;

    function Funcs:AddDivider()
        local Groupbox = self;
        local Container = self.Container

        local Divider = {
            Type = 'Divider',
        }

        Groupbox:AddBlank(2);
        local DividerOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 5);
            ZIndex = 5;
            Parent = Container;
        });

        local DividerInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DividerOuter;
        });

        Library:AddToRegistry(DividerOuter, {
            BorderColor3 = 'Black';
        });

        Library:AddToRegistry(DividerInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Groupbox:AddBlank(9);
        Groupbox:Resize();
    end

    function Funcs:AddInput(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Textbox = {
            Value = Info.Default or '';
            Numeric = Info.Numeric or false;
            Finished = Info.Finished or false;
            Type = 'Input';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local InputLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 15);
            TextSize = 14;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        Groupbox:AddBlank(1);

        local TextBoxOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        local TextBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = TextBoxOuter;
        });

        Library:AddToRegistry(TextBoxInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:OnHighlight(TextBoxOuter, TextBoxOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, TextBoxOuter)
        end

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = TextBoxInner;
        });

        local Container = Library:Create('Frame', {
            BackgroundTransparency = 1;
            ClipsDescendants = true;

            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);

            ZIndex = 7;
            Parent = TextBoxInner;
        })

        local Box = Library:Create('TextBox', {
            BackgroundTransparency = 1;

            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromScale(5, 1),

            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
            PlaceholderText = Info.Placeholder or '';

            Text = Info.Default or '';
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;

            ZIndex = 7;
            Parent = Container;
        });

        Library:ApplyTextStroke(Box);

        function Textbox:SetValue(Text)
            if Info.MaxLength and #Text > Info.MaxLength then
                Text = Text:sub(1, Info.MaxLength);
            end;

            if Textbox.Numeric then
                if (not tonumber(Text)) and Text:len() > 0 then
                    Text = Textbox.Value
                end
            end

            Textbox.Value = Text;
            Box.Text = Text;

            Library:SafeCallback(Textbox.Callback, Textbox.Value);
            Library:SafeCallback(Textbox.Changed, Textbox.Value);
        end;

        if Textbox.Finished then
            Box.FocusLost:Connect(function(enter)
                if not enter then return end

                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end)
        else
            Box:GetPropertyChangedSignal('Text'):Connect(function()
                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end);
        end

        -- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
        -- thank you nicemike40 :)

        local function Update()
            local PADDING = 2
            local reveal = Container.AbsoluteSize.X

            if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
                -- we aren't focused, or we fit so be normal
                Box.Position = UDim2.new(0, PADDING, 0, 0)
            else
                -- we are focused and don't fit, so adjust position
                local cursor = Box.CursorPosition
                if cursor ~= -1 then
                    -- calculate pixel width of text from start to cursor
                    local subtext = string.sub(Box.Text, 1, cursor-1)
                    local width = TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

                    -- check if we're inside the box with the cursor
                    local currentCursorPos = Box.Position.X.Offset + width

                    -- adjust if necessary
                    if currentCursorPos < PADDING then
                        Box.Position = UDim2.fromOffset(PADDING-width, 0)
                    elseif currentCursorPos > reveal - PADDING - 1 then
                        Box.Position = UDim2.fromOffset(reveal-width-PADDING-1, 0)
                    end
                end
            end
        end

        task.spawn(Update)

        Box:GetPropertyChangedSignal('Text'):Connect(Update)
        Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update)
        Box.FocusLost:Connect(Update)
        Box.Focused:Connect(Update)

        Library:AddToRegistry(Box, {
            TextColor3 = 'FontColor';
        });

        function Textbox:OnChanged(Func)
            Textbox.Changed = Func;
            Func(Textbox.Value);
        end;

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        Options[Idx] = Textbox;

        return Textbox;
    end;

    function Funcs:AddToggle(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Toggle = {
            Value = Info.Default or false;
            Type = 'Toggle';

            Callback = Info.Callback or function(Value) end;
            Addons = {},
            Risky = Info.Risky,
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local ToggleOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(0, 13, 0, 13);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(ToggleOuter, {
            BorderColor3 = 'Black';
        });

        local ToggleInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        Library:AddToRegistry(ToggleInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local ToggleLabel = Library:CreateLabel({
            Size = UDim2.new(0, 216, 1, 0);
            Position = UDim2.new(1, 6, 0, 0);
            TextSize = 14;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 6;
            Parent = ToggleInner;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 4);
            FillDirection = Enum.FillDirection.Horizontal;
            HorizontalAlignment = Enum.HorizontalAlignment.Right;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ToggleLabel;
        });

        local ToggleRegion = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(0, 170, 1, 0);
            ZIndex = 8;
            Parent = ToggleOuter;
        });

        Library:OnHighlight(ToggleRegion, ToggleOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        function Toggle:UpdateColors()
            Toggle:Display();
        end;

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, ToggleRegion)
        end

        function Toggle:Display()
            ToggleInner.BackgroundColor3 = Toggle.Value and Library.AccentColor or Library.MainColor;
            ToggleInner.BorderColor3 = Toggle.Value and Library.AccentColorDark or Library.OutlineColor;

            Library.RegistryMap[ToggleInner].Properties.BackgroundColor3 = Toggle.Value and 'AccentColor' or 'MainColor';
            Library.RegistryMap[ToggleInner].Properties.BorderColor3 = Toggle.Value and 'AccentColorDark' or 'OutlineColor';
        end;

        function Toggle:OnChanged(Func)
            Toggle.Changed = Func;
            Func(Toggle.Value);
        end;

        function Toggle:SetValue(Bool)
            Bool = (not not Bool);

            Toggle.Value = Bool;
            Toggle:Display();

            for _, Addon in next, Toggle.Addons do
                if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then
                    Addon.Toggled = Bool
                    Addon:Update()
                end
            end

            Library:SafeCallback(Toggle.Callback, Toggle.Value);
            Library:SafeCallback(Toggle.Changed, Toggle.Value);
            Library:UpdateDependencyBoxes();
        end;

        ToggleRegion.InputBegan:Connect(function(Input)
            if __isPrimary(Input) and not Library:MouseIsOverOpenedFrame() then
                Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
                Library:AttemptSave();
            end;
        end);

        if Toggle.Risky then
            Library:RemoveFromRegistry(ToggleLabel)
            ToggleLabel.TextColor3 = Library.RiskColor
            Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' })
        end

        Toggle:Display();
        Groupbox:AddBlank(Info.BlankSize or 5 + 2);
        Groupbox:Resize();

        Toggle.TextLabel = ToggleLabel;
        Toggle.Container = Container;
        setmetatable(Toggle, BaseAddons);

        Toggles[Idx] = Toggle;

        Library:UpdateDependencyBoxes();

        return Toggle;
    end;

    function Funcs:AddSlider(Idx, Info)
        assert(Info.Default, 'AddSlider: Missing default value.');
        assert(Info.Text, 'AddSlider: Missing slider text.');
        assert(Info.Min, 'AddSlider: Missing minimum value.');
        assert(Info.Max, 'AddSlider: Missing maximum value.');
        assert(Info.Rounding, 'AddSlider: Missing rounding value.');

        local Slider = {
            Value = Info.Default;
            Min = Info.Min;
            Max = Info.Max;
            Rounding = Info.Rounding;
            Type = 'Slider';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        if not Info.Compact then
            Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 10);
                TextSize = 14;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        local SliderOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 13);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(SliderOuter, {
            BorderColor3 = 'Black';
        });

        local SliderInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ClipsDescendants = true;
            ZIndex = 6;
            Parent = SliderOuter;
        });

        Library:AddToRegistry(SliderInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Fill = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderColor3 = Library.AccentColorDark;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 0, 1, 0);
            ZIndex = 7;
            Parent = SliderInner;
        });

        Library:AddToRegistry(Fill, {
            BackgroundColor3 = 'AccentColor';
            BorderColor3 = 'AccentColorDark';
        });

        local HideBorderRight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.new(1, 0, 0, 0);
            Size = UDim2.new(0, 1, 1, 0);
            ZIndex = 8;
            Parent = Fill;
        });

        Library:AddToRegistry(HideBorderRight, {
            BackgroundColor3 = 'AccentColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 14;
            Text = 'Infinite';
            ZIndex = 9;
            Parent = SliderInner;
        });

        Library:OnHighlight(SliderOuter, SliderOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, SliderOuter)
        end

        function Slider:UpdateColors()
            Fill.BackgroundColor3 = Library.AccentColor;
            Fill.BorderColor3 = Library.AccentColorDark;
        end;

        function Slider:Display()
            local Suffix = Info.Suffix or '';

            if Info.Compact then
                DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix
            elseif Info.HideMax then
                DisplayLabel.Text = string.format('%s', Slider.Value .. Suffix)
            else
                DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix);
            end

            local fraction = (Slider.Max == Slider.Min) and 0 or math.clamp((Slider.Value - Slider.Min) / (Slider.Max - Slider.Min), 0, 1);
            Fill.Size = UDim2.new(fraction, 0, 1, 0);

            HideBorderRight.Visible = (fraction > 0 and fraction < 1);
        end;

        function Slider:OnChanged(Func)
            Slider.Changed = Func;
            Func(Slider.Value);
        end;

        local function Round(Value)
            if Slider.Rounding == 0 then
                return math.floor(Value + 0.5);
            end;

            return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
        end;

        function Slider:GetValueFromXOffset(X)
            local width = math.max(SliderInner.AbsoluteSize.X, 1);
            local fraction = math.clamp(X / width, 0, 1);
            return Round(Slider.Min + fraction * (Slider.Max - Slider.Min));
        end;

        function Slider:SetValue(Str)
            local Num = tonumber(Str);

            if (not Num) then
                return;
            end;

            Num = math.clamp(Num, Slider.Min, Slider.Max);

            Slider.Value = Num;
            Slider:Display();

            Library:SafeCallback(Slider.Callback, Slider.Value);
            Library:SafeCallback(Slider.Changed, Slider.Value);
        end;

        SliderInner.InputBegan:Connect(function(Input)
            if __isPrimary(Input) and not Library:MouseIsOverOpenedFrame() then
                while __pointerDown() do
                    local relX = __mx() - SliderInner.AbsolutePosition.X;
                    local nValue = Slider:GetValueFromXOffset(relX);
                    local OldValue = Slider.Value;
                    Slider.Value = nValue;

                    Slider:Display();

                    if nValue ~= OldValue then
                        Library:SafeCallback(Slider.Callback, Slider.Value);
                        Library:SafeCallback(Slider.Changed, Slider.Value);
                    end;

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        Slider:Display();
        Groupbox:AddBlank(Info.BlankSize or 6);
        Groupbox:Resize();

        Options[Idx] = Slider;

        return Slider;
    end;

    function Funcs:AddDropdown(Idx, Info)
        if Info.SpecialType == 'Player' then
            Info.Values = GetPlayersString();
            Info.AllowNull = true;
        elseif Info.SpecialType == 'Team' then
            Info.Values = GetTeamsString();
            Info.AllowNull = true;
        end;

        assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
        assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

        if (not Info.Text) then
            Info.Compact = true;
        end;

        local Dropdown = {
            Values = Info.Values;
            Value = Info.Multi and {};
            Multi = Info.Multi;
            Type = 'Dropdown';
            SpecialType = Info.SpecialType; -- can be either 'Player' or 'Team'
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local RelativeOffset = 0;

        if not Info.Compact then
            local DropdownLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 10);
                TextSize = 14;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        for _, Element in next, Container:GetChildren() do
            if not Element:IsA('UIListLayout') then
                RelativeOffset = RelativeOffset + Element.Size.Y.Offset;
            end;
        end;

        local DropdownOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(DropdownOuter, {
            BorderColor3 = 'Black';
        });

        local DropdownInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DropdownOuter;
        });

        Library:AddToRegistry(DropdownInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = DropdownInner;
        });

        local DropdownArrow = Library:Create('ImageLabel', {
            AnchorPoint = Vector2.new(0, 0.5);
            BackgroundTransparency = 1;
            Position = UDim2.new(1, -16, 0.5, 0);
            Size = UDim2.new(0, 12, 0, 12);
            Image = 'http://www.roblox.com/asset/?id=6282522798';
            ZIndex = 8;
            Parent = DropdownInner;
        });

        local ItemList = Library:CreateLabel({
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);
            TextSize = 14;
            Text = '--';
            TextXAlignment = Enum.TextXAlignment.Left;
            TextWrapped = true;
            ZIndex = 7;
            Parent = DropdownInner;
        });

        Library:OnHighlight(DropdownOuter, DropdownOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, DropdownOuter)
        end

        local MAX_DROPDOWN_ITEMS = 8;

        local ListOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            ZIndex = 20;
            Visible = false;
            Parent = ScreenGui;
        });

        local function RecalculateListPosition()
            ListOuter.Position = UDim2.fromOffset(DropdownOuter.AbsolutePosition.X, DropdownOuter.AbsolutePosition.Y + DropdownOuter.Size.Y.Offset + 1);
        end;

        local function RecalculateListSize(YSize)
            ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, YSize or (MAX_DROPDOWN_ITEMS * 20 + 2))
        end;

        RecalculateListPosition();
        RecalculateListSize();

        DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalculateListPosition);

        local ListInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListOuter;
        });

        Library:AddToRegistry(ListInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Scrolling = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            CanvasSize = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListInner;

            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',

            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Library.AccentColor,
        });

        Library:AddToRegistry(Scrolling, {
            ScrollBarImageColor3 = 'AccentColor'
        })

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 0);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Scrolling;
        });

        function Dropdown:Display()
            local Values = Dropdown.Values;
            local Str = '';

            if Info.Multi then
                for Idx, Value in next, Values do
                    if Dropdown.Value[Value] then
                        Str = Str .. Value .. ', ';
                    end;
                end;

                Str = Str:sub(1, #Str - 2);
            else
                Str = Dropdown.Value or '';
            end;

            ItemList.Text = (Str == '' and '--' or Str);
        end;

        function Dropdown:GetActiveValues()
            if Info.Multi then
                local T = {};

                for Value, Bool in next, Dropdown.Value do
                    table.insert(T, Value);
                end;

                return T;
            else
                return Dropdown.Value and 1 or 0;
            end;
        end;

        function Dropdown:BuildDropdownList()
            local Values = Dropdown.Values;
            local Buttons = {};

            for _, Element in next, Scrolling:GetChildren() do
                if not Element:IsA('UIListLayout') then
                    Element:Destroy();
                end;
            end;

            local Count = 0;

            for Idx, Value in next, Values do
                local Table = {};

                Count = Count + 1;

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Library.OutlineColor;
                    BorderMode = Enum.BorderMode.Middle;
                    Size = UDim2.new(1, -1, 0, 20);
                    ZIndex = 23;
                    Active = true,
                    Parent = Scrolling;
                });

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                    BorderColor3 = 'OutlineColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, -6, 1, 0);
                    Position = UDim2.new(0, 6, 0, 0);
                    TextSize = 14;
                    Text = Value;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    ZIndex = 25;
                    Parent = Button;
                });

                Library:OnHighlight(Button, Button,
                    { BorderColor3 = 'AccentColor', ZIndex = 24 },
                    { BorderColor3 = 'OutlineColor', ZIndex = 23 }
                );

                local Selected;

                if Info.Multi then
                    Selected = Dropdown.Value[Value];
                else
                    Selected = Dropdown.Value == Value;
                end;

                function Table:UpdateButton()
                    if Info.Multi then
                        Selected = Dropdown.Value[Value];
                    else
                        Selected = Dropdown.Value == Value;
                    end;

                    ButtonLabel.TextColor3 = Selected and Library.AccentColor or Library.FontColor;
                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
                end;

                ButtonLabel.InputBegan:Connect(function(Input)
                    if __isPrimary(Input) then
                        local Try = not Selected;

                        if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
                        else
                            if Info.Multi then
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value[Value] = true;
                                else
                                    Dropdown.Value[Value] = nil;
                                end;
                            else
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value = Value;
                                else
                                    Dropdown.Value = nil;
                                end;

                                for _, OtherButton in next, Buttons do
                                    OtherButton:UpdateButton();
                                end;
                            end;

                            Table:UpdateButton();
                            Dropdown:Display();

                            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
                            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);

                            Library:AttemptSave();
                        end;
                    end;
                end);

                Table:UpdateButton();
                Dropdown:Display();

                Buttons[Button] = Table;
            end;

            Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * 20) + 1);

            local Y = math.clamp(Count * 20, 0, MAX_DROPDOWN_ITEMS * 20) + 1;
            RecalculateListSize(Y);
        end;

        function Dropdown:SetValues(NewValues)
            if NewValues then
                Dropdown.Values = NewValues;
            end;

            Dropdown:BuildDropdownList();
        end;

        function Dropdown:OpenDropdown()
            ListOuter.Visible = true;
            Library.OpenedFrames[ListOuter] = true;
            DropdownArrow.Rotation = 180;
        end;

        function Dropdown:CloseDropdown()
            ListOuter.Visible = false;
            Library.OpenedFrames[ListOuter] = nil;
            DropdownArrow.Rotation = 0;
        end;

        function Dropdown:OnChanged(Func)
            Dropdown.Changed = Func;
            Func(Dropdown.Value);
        end;

        function Dropdown:SetValue(Val)
            if Dropdown.Multi then
                local nTable = {};

                for Value, Bool in next, Val do
                    if table.find(Dropdown.Values, Value) then
                        nTable[Value] = true
                    end;
                end;

                Dropdown.Value = nTable;
            else
                if (not Val) then
                    Dropdown.Value = nil;
                elseif table.find(Dropdown.Values, Val) then
                    Dropdown.Value = Val;
                end;
            end;

            Dropdown:BuildDropdownList();

            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);
        end;

        DropdownOuter.InputBegan:Connect(function(Input)
            if __isPrimary(Input) and not Library:MouseIsOverOpenedFrame() then
                if ListOuter.Visible then
                    Dropdown:CloseDropdown();
                else
                    Dropdown:OpenDropdown();
                end;
            end;
        end);

        InputService.InputBegan:Connect(function(Input)
            if __isPrimary(Input) then
                local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;

                if __mx() < AbsPos.X or __mx() > AbsPos.X + AbsSize.X
                    or __my() < (AbsPos.Y - 20 - 1) or __my() > AbsPos.Y + AbsSize.Y then

                    Dropdown:CloseDropdown();
                end;
            end;
        end);

        Dropdown:BuildDropdownList();
        Dropdown:Display();

        local Defaults = {}

        if type(Info.Default) == 'string' then
            local Idx = table.find(Dropdown.Values, Info.Default)
            if Idx then
                table.insert(Defaults, Idx)
            end
        elseif type(Info.Default) == 'table' then
            for _, Value in next, Info.Default do
                local Idx = table.find(Dropdown.Values, Value)
                if Idx then
                    table.insert(Defaults, Idx)
                end
            end
        elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
            table.insert(Defaults, Info.Default)
        end

        if next(Defaults) then
            for i = 1, #Defaults do
                local Index = Defaults[i]
                if Info.Multi then
                    Dropdown.Value[Dropdown.Values[Index]] = true
                else
                    Dropdown.Value = Dropdown.Values[Index];
                end

                if (not Info.Multi) then break end
            end

            Dropdown:BuildDropdownList();
            Dropdown:Display();
        end

        Groupbox:AddBlank(Info.BlankSize or 5);
        Groupbox:Resize();

        Options[Idx] = Dropdown;

        return Dropdown;
    end;

    function Funcs:AddDependencyBox()
        local Depbox = {
            Dependencies = {};
        };
        
        local Groupbox = self;
        local Container = Groupbox.Container;

        local Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, 0);
            Visible = false;
            Parent = Container;
        });

        local Frame = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 1, 0);
            Visible = true;
            Parent = Holder;
        });

        local Layout = Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Frame;
        });

        function Depbox:Resize()
            Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y);
            Groupbox:Resize();
        end;

        Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            Depbox:Resize();
        end);

        Holder:GetPropertyChangedSignal('Visible'):Connect(function()
            Depbox:Resize();
        end);

        function Depbox:Update()
            for _, Dependency in next, Depbox.Dependencies do
                local Elem = Dependency[1];
                local Value = Dependency[2];

                if Elem.Type == 'Toggle' and Elem.Value ~= Value then
                    Holder.Visible = false;
                    Depbox:Resize();
                    return;
                end;
            end;

            Holder.Visible = true;
            Depbox:Resize();
        end;

        function Depbox:SetupDependencies(Dependencies)
            for _, Dependency in next, Dependencies do
                assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.');
                assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.');
                assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.');
            end;

            Depbox.Dependencies = Dependencies;
            Depbox:Update();
        end;

        Depbox.Container = Frame;

        setmetatable(Depbox, BaseGroupbox);

        table.insert(Library.DependencyBoxes, Depbox);

        return Depbox;
    end;

    BaseGroupbox.__index = Funcs;
    BaseGroupbox.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

-- < Create other UI elements >
do
    Library.NotificationArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 0, 0, 40);
        Size = UDim2.new(0, 300, 0, 200);
        ZIndex = 100;
        Parent = ScreenGui;
    });

    Library:Create('UIListLayout', {
        Padding = UDim.new(0, 4);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = Library.NotificationArea;
    });

    local WatermarkOuter = Library:Create('Frame', {
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 100, 0, -25);
        Size = UDim2.new(0, 213, 0, 20);
        ZIndex = 200;
        Visible = false;
        Parent = ScreenGui;
    });

    local WatermarkInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.AccentColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 201;
        Parent = WatermarkOuter;
    });

    Library:AddToRegistry(WatermarkInner, {
        BorderColor3 = 'AccentColor';
    });

    local InnerFrame = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(1, 1, 1);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 202;
        Parent = WatermarkInner;
    });

    local Gradient = Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
            ColorSequenceKeypoint.new(1, Library.MainColor),
        });
        Rotation = -90;
        Parent = InnerFrame;
    });

    Library:AddToRegistry(Gradient, {
        Color = function()
            return ColorSequence.new({
                ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
                ColorSequenceKeypoint.new(1, Library.MainColor),
            });
        end
    });

    local WatermarkLabel = Library:CreateLabel({
        Position = UDim2.new(0, 5, 0, 0);
        Size = UDim2.new(1, -4, 1, 0);
        TextSize = 14;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 203;
        Parent = InnerFrame;
    });

    Library.Watermark = WatermarkOuter;
    Library.WatermarkText = WatermarkLabel;
    Library:MakeDraggable(Library.Watermark);



    local KeybindOuter = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 10, 0.5, 0);
        Size = UDim2.new(0, 210, 0, 20);
        Visible = false;
        ZIndex = 100;
        Parent = ScreenGui;
    });

    local KeybindInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = KeybindOuter;
    });

    Library:AddToRegistry(KeybindInner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    }, true);

    local ColorFrame = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 102;
        Parent = KeybindInner;
    });

    Library:AddToRegistry(ColorFrame, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    local KeybindLabel = Library:CreateLabel({
        Size = UDim2.new(1, 0, 0, 20);
        Position = UDim2.fromOffset(5, 2),
        TextXAlignment = Enum.TextXAlignment.Left,

        Text = 'Keybinds';
        ZIndex = 104;
        Parent = KeybindInner;
    });

    local KeybindContainer = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Size = UDim2.new(1, 0, 1, -20);
        Position = UDim2.new(0, 0, 0, 20);
        ZIndex = 1;
        Parent = KeybindInner;
    });

    Library:Create('UIListLayout', {
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = KeybindContainer;
    });

    Library:Create('UIPadding', {
        PaddingLeft = UDim.new(0, 5),
        Parent = KeybindContainer,
    })

    Library.KeybindFrame = KeybindOuter;
    Library.KeybindContainer = KeybindContainer;
    Library:MakeDraggable(KeybindOuter);
end;

function Library:SetWatermarkVisibility(Bool)
    Library.Watermark.Visible = Bool;
end;

function Library:SetWatermark(Text)
    local X, Y = Library:GetTextBounds(Text, Library.Font, 14);
    Library.Watermark.Size = UDim2.new(0, X + 15, 0, (Y * 1.5) + 3);
    Library:SetWatermarkVisibility(true)

    Library.WatermarkText.Text = Text;
end;

function Library:Notify(Text, Time)
    local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14);

    YSize = YSize + 7

    local NotifyOuter = Library:Create('Frame', {
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 100, 0, 10);
        Size = UDim2.new(0, 0, 0, YSize);
        ClipsDescendants = true;
        ZIndex = 100;
        Parent = Library.NotificationArea;
    });

    local NotifyInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(NotifyInner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    }, true);

    local InnerFrame = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(1, 1, 1);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 102;
        Parent = NotifyInner;
    });

    local Gradient = Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
            ColorSequenceKeypoint.new(1, Library.MainColor),
        });
        Rotation = -90;
        Parent = InnerFrame;
    });

    Library:AddToRegistry(Gradient, {
        Color = function()
            return ColorSequence.new({
                ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
                ColorSequenceKeypoint.new(1, Library.MainColor),
            });
        end
    });

    local NotifyLabel = Library:CreateLabel({
        Position = UDim2.new(0, 4, 0, 0);
        Size = UDim2.new(1, -4, 1, 0);
        Text = Text;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextSize = 14;
        ZIndex = 103;
        Parent = InnerFrame;
    });

    local LeftColor = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, -1, 0, -1);
        Size = UDim2.new(0, 3, 1, 2);
        ZIndex = 104;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(LeftColor, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, XSize + 8 + 4, 0, YSize), 'Out', 'Quad', 0.4, true);

    task.spawn(function()
        wait(Time or 5);

        pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, 0, 0, YSize), 'Out', 'Quad', 0.4, true);

        wait(0.4);

        NotifyOuter:Destroy();
    end);
end;

function Library:CreateWindow(...)
    local Arguments = { ... }
    local Config = { AnchorPoint = Vector2.zero }

    if type(...) == 'table' then
        Config = ...;
    else
        Config.Title = Arguments[1]
        Config.AutoShow = Arguments[2] or false;
    end

    if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
    if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 0 end
    if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.2 end

    if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end
    if typeof(Config.Size) ~= 'UDim2' then Config.Size = UDim2.fromOffset(440, 210) end

    if Config.Center then
        Config.AnchorPoint = Vector2.new(0.5, 0.5)
        Config.Position = UDim2.fromScale(0.5, 0.5)
    end

    local Window = {
        Tabs = {};
    };

    local Outer = Library:Create('Frame', {
        AnchorPoint = Config.AnchorPoint,
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = Config.Position,
        Size = Config.Size,
        Visible = false;
        ZIndex = 1;
        Parent = ScreenGui;
    });

    local Inner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.AccentColor;
        BorderMode = Enum.BorderMode.Inset;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 1;
        Parent = Outer;
    });

    Library:AddToRegistry(Inner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'AccentColor';
    });

    local WindowLabel = Library:CreateLabel({
        Position = UDim2.new(0, 7, 0, 0);
        Size = UDim2.new(0, 0, 0, 25);
        Text = Config.Title or '';
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 1;
        Parent = Inner;
    });

    local MainSectionOuter = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, 8, 0, 25);
        Size = UDim2.new(1, -16, 1, -33);
        ZIndex = 1;
        Parent = Inner;
    });

    Library:AddToRegistry(MainSectionOuter, {
        BackgroundColor3 = 'BackgroundColor';
        BorderColor3 = 'OutlineColor';
    });

    local MainSectionInner = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Color3.new(0, 0, 0);
        BorderMode = Enum.BorderMode.Inset;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 1;
        Parent = MainSectionOuter;
    });

    Library:AddToRegistry(MainSectionInner, {
        BackgroundColor3 = 'BackgroundColor';
    });

    local TabArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 8, 0, 8);
        Size = UDim2.new(1, -16, 0, 21);
        ZIndex = 1;
        Parent = MainSectionInner;
    });

    local TabListLayout = Library:Create('UIListLayout', {
        Padding = UDim.new(0, Config.TabPadding);
        FillDirection = Enum.FillDirection.Horizontal;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = TabArea;
    });

    local function getDynamicMinWidth()
        local contentW = TabListLayout.AbsoluteContentSize.X;
        if contentW and contentW > 0 then
            return math.max(contentW + 36, Config.MinWidth or 440);
        end
        return Config.MinWidth or 440;
    end

    Library:MakeDraggable(Outer, 25);
    Library:MakeResizable(Outer, getDynamicMinWidth, Config.MinHeight or 210, Config.MaxWidth or 1200, Config.MaxHeight or 900, Config.ResizeCallback);

    Window.Outer = Outer;

    local TabContainer = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, 8, 0, 30);
        Size = UDim2.new(1, -16, 1, -38);
        ZIndex = 2;
        Parent = MainSectionInner;
    });
    

    Library:AddToRegistry(TabContainer, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    function Window:SetWindowTitle(Title)
        WindowLabel.Text = Title;
    end;

    function Window:AddTab(Name)
        local Tab = {
            Groupboxes = {};
            Tabboxes = {};
        };

        local TabButtonWidth = Library:GetTextBounds(Name, Library.Font, 16);

        local TabButton = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            Size = UDim2.new(0, TabButtonWidth + 8 + 4, 1, 0);
            ZIndex = 1;
            Parent = TabArea;
        });

        Library:AddToRegistry(TabButton, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        local TabButtonLabel = Library:CreateLabel({
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, -1);
            Text = Name;
            ZIndex = 1;
            Parent = TabButton;
        });

        local Blocker = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 0, 1, 0);
            Size = UDim2.new(1, 0, 0, 1);
            BackgroundTransparency = 1;
            ZIndex = 3;
            Parent = TabButton;
        });

        Library:AddToRegistry(Blocker, {
            BackgroundColor3 = 'MainColor';
        });

        local TabFrame = Library:Create('Frame', {
            Name = 'TabFrame',
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Visible = false;
            ZIndex = 2;
            Parent = TabContainer;
        });

        local LeftSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 6, 0, 6);
            Size = UDim2.new(0.5, -9, 1, -12);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
            ScrollBarThickness = 2;
            ScrollBarImageColor3 = Library.AccentColor;
            ZIndex = 2;
            Parent = TabFrame;
        });

        local RightSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0.5, 3, 0, 6);
            Size = UDim2.new(0.5, -9, 1, -12);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
            ScrollBarThickness = 2;
            ScrollBarImageColor3 = Library.AccentColor;
            ZIndex = 2;
            Parent = TabFrame;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 8);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = LeftSide;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 8);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = RightSide;
        });

        for _, Side in next, { LeftSide, RightSide } do
            Library:AddToRegistry(Side, {
                ScrollBarImageColor3 = 'AccentColor'
            });
            Side:WaitForChild('UIListLayout'):GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
                Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y);
            end);
        end;

        function Tab:ShowTab()
            for _, Tab in next, Window.Tabs do
                Tab:HideTab();
            end;

            Blocker.BackgroundTransparency = 0;
            TabButton.BackgroundColor3 = Library.MainColor;
            Library.RegistryMap[TabButton].Properties.BackgroundColor3 = 'MainColor';
            TabFrame.Visible = true;
        end;

        function Tab:HideTab()
            Blocker.BackgroundTransparency = 1;
            TabButton.BackgroundColor3 = Library.BackgroundColor;
            Library.RegistryMap[TabButton].Properties.BackgroundColor3 = 'BackgroundColor';
            TabFrame.Visible = false;
        end;

        function Tab:SetLayoutOrder(Position)
            TabButton.LayoutOrder = Position;
            TabListLayout:ApplyLayout();
        end;

        function Tab:AddGroupbox(Info)
            local Groupbox = {};

            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 0, 507 + 2);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            Library:AddToRegistry(BoxOuter, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Color3.new(0, 0, 0);
                -- BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'BackgroundColor';
            });

            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 2);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'AccentColor';
            });

            local GroupboxLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 18);
                Position = UDim2.new(0, 4, 0, 2);
                TextSize = 14;
                Text = Info.Name;
                TextXAlignment = Enum.TextXAlignment.Left;
                ZIndex = 5;
                Parent = BoxInner;
            });

            local Container = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 4, 0, 20);
                Size = UDim2.new(1, -4, 1, -20);
                ZIndex = 1;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = Container;
            });

            function Groupbox:Resize()
                local Size = 0;

                for _, Element in next, Groupbox.Container:GetChildren() do
                    if (not Element:IsA('UIListLayout')) and Element.Visible then
                        Size = Size + Element.Size.Y.Offset;
                    end;
                end;

                BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
            end;

            Groupbox.Container = Container;
            setmetatable(Groupbox, BaseGroupbox);

            Groupbox:AddBlank(3);
            Groupbox:Resize();

            Tab.Groupboxes[Info.Name] = Groupbox;

            return Groupbox;
        end;

        function Tab:AddLeftGroupbox(Name)
            return Tab:AddGroupbox({ Side = 1; Name = Name; });
        end;

        function Tab:AddRightGroupbox(Name)
            return Tab:AddGroupbox({ Side = 2; Name = Name; });
        end;

        function Tab:AddTabbox(Info)
            local Tabbox = {
                Tabs = {};
            };

            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 0, 0);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            Library:AddToRegistry(BoxOuter, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Color3.new(0, 0, 0);
                -- BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'BackgroundColor';
            });

            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 2);
                ZIndex = 10;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'AccentColor';
            });

            local TabboxButtons = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 0, 0, 1);
                Size = UDim2.new(1, 0, 0, 18);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Left;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TabboxButtons;
            });

            function Tabbox:AddTab(Name)
                local Tab = {};

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Color3.new(0, 0, 0);
                    Size = UDim2.new(0.5, 0, 1, 0);
                    ZIndex = 6;
                    Parent = TabboxButtons;
                });

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Size = UDim2.new(1, 0, 1, 0);
                    TextSize = 14;
                    Text = Name;
                    TextXAlignment = Enum.TextXAlignment.Center;
                    ZIndex = 7;
                    Parent = Button;
                });

                local Block = Library:Create('Frame', {
                    BackgroundColor3 = Library.BackgroundColor;
                    BorderSizePixel = 0;
                    Position = UDim2.new(0, 0, 1, 0);
                    Size = UDim2.new(1, 0, 0, 1);
                    Visible = false;
                    ZIndex = 9;
                    Parent = Button;
                });

                Library:AddToRegistry(Block, {
                    BackgroundColor3 = 'BackgroundColor';
                });

                local Container = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    Position = UDim2.new(0, 4, 0, 20);
                    Size = UDim2.new(1, -4, 1, -20);
                    ZIndex = 1;
                    Visible = false;
                    Parent = BoxInner;
                });

                Library:Create('UIListLayout', {
                    FillDirection = Enum.FillDirection.Vertical;
                    SortOrder = Enum.SortOrder.LayoutOrder;
                    Parent = Container;
                });

                function Tab:Show()
                    for _, Tab in next, Tabbox.Tabs do
                        Tab:Hide();
                    end;

                    Container.Visible = true;
                    Block.Visible = true;

                    Button.BackgroundColor3 = Library.BackgroundColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'BackgroundColor';

                    Tab:Resize();
                end;

                function Tab:Hide()
                    Container.Visible = false;
                    Block.Visible = false;

                    Button.BackgroundColor3 = Library.MainColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'MainColor';
                end;

                function Tab:Resize()
                    local TabCount = 0;

                    for _, Tab in next, Tabbox.Tabs do
                        TabCount = TabCount + 1;
                    end;

                    for _, Button in next, TabboxButtons:GetChildren() do
                        if not Button:IsA('UIListLayout') then
                            Button.Size = UDim2.new(1 / TabCount, 0, 1, 0);
                        end;
                    end;

                    if (not Container.Visible) then
                        return;
                    end;

                    local Size = 0;

                    for _, Element in next, Tab.Container:GetChildren() do
                        if (not Element:IsA('UIListLayout')) and Element.Visible then
                            Size = Size + Element.Size.Y.Offset;
                        end;
                    end;

                    BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
                end;

                Button.InputBegan:Connect(function(Input)
                    if __isPrimary(Input) and not Library:MouseIsOverOpenedFrame() then
                        Tab:Show();
                        Tab:Resize();
                    end;
                end);

                Tab.Container = Container;
                Tabbox.Tabs[Name] = Tab;

                setmetatable(Tab, BaseGroupbox);

                Tab:AddBlank(3);
                Tab:Resize();

                -- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
                if #TabboxButtons:GetChildren() == 2 then
                    Tab:Show();
                end;

                return Tab;
            end;

            Tab.Tabboxes[Info.Name or ''] = Tabbox;

            return Tabbox;
        end;

        function Tab:AddLeftTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 1; });
        end;

        function Tab:AddRightTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 2; });
        end;

        TabButton.InputBegan:Connect(function(Input)
            if __isPrimary(Input) then
                Tab:ShowTab();
            end;
        end);

        -- This was the first tab added, so we show it by default.
        if #TabContainer:GetChildren() == 1 then
            Tab:ShowTab();
        end;

        Window.Tabs[Name] = Tab;
        return Tab;
    end;

    local ModalElement = Library:Create('TextButton', {
        BackgroundTransparency = 1;
        Size = UDim2.new(0, 0, 0, 0);
        Visible = true;
        Text = '';
        Modal = false;
        Parent = ScreenGui;
    });

    local TransparencyCache = {};
    local Toggled = false;
    local Fading = false;

    function Library:Toggle()
        if Fading then
            return;
        end;

        local FadeTime = Config.MenuFadeTime;
        Fading = true;
        Toggled = (not Toggled);
        Library.Toggled = Toggled;
        ModalElement.Modal = Toggled;

        if Toggled then
            pcall(function()
                ContextActionService:BindActionAtPriority(
                    "__linoriaMenuScrollSink",
                    function() return Enum.ContextActionResult.Sink end,
                    false,
                    Enum.ContextActionPriority.High.Value + 2000,
                    Enum.UserInputType.MouseWheel
                )
            end)

            -- A bit scuffed, but if we're going from not toggled -> toggled we want to show the frame immediately so that the fade is visible.
            Outer.Visible = true;

            task.spawn(function()
                -- TODO: add cursor fade?
                local State = InputService.MouseIconEnabled;

                local Cursor = Drawing.new('Triangle');
                Cursor.Thickness = 1;
                Cursor.Filled = true;
                Cursor.Visible = true;

                local CursorOutline = Drawing.new('Triangle');
                CursorOutline.Thickness = 1;
                CursorOutline.Filled = false;
                CursorOutline.Color = Color3.new(0, 0, 0);
                CursorOutline.Visible = true;

                while Toggled and ScreenGui.Parent do
                    InputService.MouseIconEnabled = false;

                    local mPos = InputService:GetMouseLocation();

                    Cursor.Color = Library.AccentColor;

                    Cursor.PointA = Vector2.new(mPos.X, mPos.Y);
                    Cursor.PointB = Vector2.new(mPos.X + 16, mPos.Y + 6);
                    Cursor.PointC = Vector2.new(mPos.X + 6, mPos.Y + 16);

                    CursorOutline.PointA = Cursor.PointA;
                    CursorOutline.PointB = Cursor.PointB;
                    CursorOutline.PointC = Cursor.PointC;

                    RenderStepped:Wait();
                end;

                InputService.MouseIconEnabled = State;

                Cursor:Remove();
                CursorOutline:Remove();
            end);
        else
            pcall(function()
                ContextActionService:UnbindAction("__linoriaMenuScrollSink")
            end)
        end;

        for _, Desc in next, Outer:GetDescendants() do
            local Properties = {};

            if Desc:IsA('ImageLabel') then
                table.insert(Properties, 'ImageTransparency');
                table.insert(Properties, 'BackgroundTransparency');
            elseif Desc:IsA('TextLabel') or Desc:IsA('TextBox') then
                table.insert(Properties, 'TextTransparency');
            elseif Desc:IsA('Frame') or Desc:IsA('ScrollingFrame') then
                table.insert(Properties, 'BackgroundTransparency');
            elseif Desc:IsA('UIStroke') then
                table.insert(Properties, 'Transparency');
            end;

            local Cache = TransparencyCache[Desc];

            if (not Cache) then
                Cache = {};
                TransparencyCache[Desc] = Cache;
            end;

            for _, Prop in next, Properties do
                if not Cache[Prop] then
                    Cache[Prop] = Desc[Prop];
                end;

                if Cache[Prop] == 1 then
                    continue;
                end;

                TweenService:Create(Desc, TweenInfo.new(FadeTime, Enum.EasingStyle.Linear), { [Prop] = Toggled and Cache[Prop] or 1 }):Play();
            end;
        end;

        task.wait(FadeTime);

        Outer.Visible = Toggled;

        Fading = false;
    end

    Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
        if InputService:GetFocusedTextBox() then return end
        if Library.IsPickingKey then return end

        local isCustomKey = (type(Library.ToggleKeybind) == 'table' and Library.ToggleKeybind.Type == 'KeyPicker' and Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Library.ToggleKeybind.Value and Library.ToggleKeybind.Value ~= 'None')
        local isDefaultKey = (Input.KeyCode == Enum.KeyCode.RightShift or Input.KeyCode == Enum.KeyCode.RightControl)

        if isCustomKey or isDefaultKey then
            task.spawn(Library.Toggle)
        end
    end))

    if Config.AutoShow then task.spawn(Library.Toggle) end

    Window.Holder = Outer;

    return Window;
end;

local function OnPlayerChange()
    local PlayerList = GetPlayersString();

    for _, Value in next, Options do
        if Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
            Value:SetValues(PlayerList);
        end;
    end;
end;

Players.PlayerAdded:Connect(OnPlayerChange);
Players.PlayerRemoving:Connect(OnPlayerChange);

getgenv().Library = Library
return Library
end
__mods["SilentAim"] = function()
-- silent aim and recoil hook
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SilentAim = {}

local BulletModule = require(ReplicatedStorage.Components.Weapon.Classes.Bullet)
local GetRayIgnore = require(ReplicatedStorage.Components.Common.GetRayIgnore)
local Raycast = require(ReplicatedStorage.Shared.Raycast)

local cast = Raycast.cast
local castThrough = Raycast.castThrough

local min = math.min
local rad = math.rad
local abs = math.abs

local function nativeRaycastWithSpread(self, spread)
    local ignoreList = GetRayIgnore()
    local cam = Workspace.CurrentCamera
    local vpCenter = cam.ViewportSize * 0.5
    local vpRay = cam:ViewportPointToRay(vpCenter.X, vpCenter.Y)
    spread = min(spread or 0, 69)
    local rng = Random.new(math.floor((os.clock() * 1e6) % 2147483647))
    local theta = rng:NextNumber(-math.pi, math.pi)
    local phi = rng:NextNumber(0, rad(spread * 0.5))
    local dir = vpRay.Direction
    local unitDir = (dir.Magnitude > 0) and dir.Unit or Vector3.new(0, 0, 1)
    local up = (abs(unitDir.Y) <= 0.9999) and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
    local lookVector = ((CFrame.lookAlong(Vector3.new(0, 0, 0), unitDir, up) * CFrame.Angles(0, 0, theta)) * CFrame.Angles(phi, 0, 0)).LookVector
    local origin = vpRay.Origin
    local penetration = (self.Properties and self.Properties.Penetration) or 0
    local range = (self.Properties and self.Properties.Range) or 500

    local hitData = {
        Distance = 0,
        Origin = origin,
        Direction = lookVector,
        Hits = {}
    }

    local hitInfo = cast(origin, lookVector * range, nil, ignoreList)
    if hitInfo and hitInfo.instance then
        local pos = hitInfo.position
        hitData.Distance = (pos - origin).Magnitude
        local penetrationHits = castThrough(pos + lookVector * -0.001, lookVector * (penetration + 0.001), penetration, ignoreList)
        if penetrationHits then
            for i = 1, #penetrationHits do
                local pHit = penetrationHits[i]
                if pHit.instance and pHit.material then
                    table.insert(hitData.Hits, {
                        Position = pHit.position,
                        Instance = pHit.instance,
                        Material = (pHit.material and pHit.material.Name) or tostring(pHit.material),
                        Normal = pHit.normal or Vector3.new(0, 0, 0),
                        Exit = (i % 2 == 0)
                    })
                end
            end
        end
    else
        hitData.Distance = range
    end

    return hitData
end

function SilentAim.init(Config, Utils)
    if not _G.__originalPerformRaycast then
        _G.__originalPerformRaycast = BulletModule._performRaycast
    end

    -- bullet raycast redirection
    local function silentAimPerformRaycast(self, spread)
        local targetPart = Config.CurrentTargetPart
        local active = (type(Config.isSilentAimActive) == "function") and Config.isSilentAimActive() or (Config.SILENT_AIM_ENABLED ~= false)

        if active and targetPart and targetPart.Parent and targetPart:IsDescendantOf(Workspace) then
            local char = targetPart.Parent
            if not (char:GetAttribute("Dead") == true) then
                local isOccluded = false
                if Config.AIM_OCCLUSION_CHECK then
                    if Utils and Utils.areAllHitboxesOccluded then
                        isOccluded = Utils.areAllHitboxesOccluded(char)
                    end
                end

                if not isOccluded then
                    local success, result = pcall(function()
                        local ignoreList = GetRayIgnore()
                        local cam = Workspace.CurrentCamera
                        local vpCenter = cam.ViewportSize * 0.5
                        local vpRay = cam:ViewportPointToRay(vpCenter.X, vpCenter.Y)
                        local Origin = vpRay.Origin

                        local targetPos = targetPart.Position
                        local LookVector = (targetPos - Origin).Unit
                        local totalDistance = (targetPos - Origin).Magnitude
                        local range = math.max((self.Properties and self.Properties.Range) or 500, totalDistance + 50)
                        local penetration = (self.Properties and self.Properties.Penetration) or 0

                        local hitData = {
                            Distance = totalDistance,
                            Origin = Origin,
                            Direction = LookVector,
                            Hits = {}
                        }

                        local hitInfo = cast(Origin, LookVector * range, nil, ignoreList)
                        if hitInfo and hitInfo.instance then
                            local hitPos = hitInfo.position
                            hitData.Distance = (hitPos - Origin).Magnitude

                            local penetrationHits = castThrough(hitPos + LookVector * -0.001, LookVector * (penetration + 0.001), penetration, ignoreList)
                            if penetrationHits then
                                for i = 1, #penetrationHits do
                                    local pHit = penetrationHits[i]
                                    if pHit.instance and pHit.material then
                                        table.insert(hitData.Hits, {
                                            Position = pHit.position,
                                            Instance = pHit.instance,
                                            Material = (pHit.material and pHit.material.Name) or tostring(pHit.material),
                                            Normal = pHit.normal or Vector3.new(0, 0, 0),
                                            Exit = (i % 2 == 0)
                                        })
                                    end
                                end
                            end
                        end

                        return hitData
                    end)

                    if success and result and result.Hits then
                        return result
                    end
                end
            end
        end

        if _G.__originalPerformRaycast and _G.__originalPerformRaycast ~= silentAimPerformRaycast then
            return _G.__originalPerformRaycast(self, spread)
        end
        return nativeRaycastWithSpread(self, spread)
    end

    BulletModule._performRaycast = silentAimPerformRaycast
end

function SilentAim.cleanup()
    if _G.__originalPerformRaycast then
        pcall(function() BulletModule._performRaycast = _G.__originalPerformRaycast end)
    end
    _G.__originalPerformRaycast = nil
end

return SilentAim

end
__mods["SkeletonRenderer"] = function()
-- skeleton and esp renderer
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local EPS = 0.01

local SkeletonRenderer = {}

-- r15 bone pairs
local BONE_PAIRS = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"}
}

function SkeletonRenderer.create()
    local obj = {
        Bones = {},
        ViewAngle = Drawing.new("Line"),
        HpBg = Drawing.new("Line"),
        HpFill = Drawing.new("Line"),
        NameText = Drawing.new("Text"),
        Arrow = Drawing.new("Triangle")
    }

    for i = 1, #BONE_PAIRS do
        local line = Drawing.new("Line")
        line.Thickness = 1.5
        line.ZIndex = 1
        line.Visible = false
        obj.Bones[i] = line
    end

    obj.ViewAngle.Thickness = 1.5
    obj.ViewAngle.Color = Color3.fromRGB(255, 255, 255)
    obj.ViewAngle.ZIndex = 2
    obj.ViewAngle.Visible = false

    obj.HpBg.Thickness = 4
    obj.HpBg.Color = Color3.fromRGB(15, 15, 15)
    obj.HpBg.ZIndex = 1
    obj.HpBg.Visible = false

    obj.HpFill.Thickness = 2
    obj.HpFill.ZIndex = 2
    obj.HpFill.Visible = false

    obj.NameText.Size = 13
    obj.NameText.Center = true
    obj.NameText.Outline = false
    obj.NameText.Color = Color3.fromRGB(240, 240, 240)
    obj.NameText.ZIndex = 3
    obj.NameText.Visible = false

    obj.Arrow.Filled = true
    obj.Arrow.Thickness = 1
    obj.Arrow.ZIndex = 5
    obj.Arrow.Visible = false

    return obj
end

function SkeletonRenderer.hide(drawObj)
    for i = 1, #drawObj.Bones do
        drawObj.Bones[i].Visible = false
    end
    drawObj.ViewAngle.Visible = false
    drawObj.HpBg.Visible = false
    drawObj.HpFill.Visible = false
    if drawObj.NameText then drawObj.NameText.Visible = false end
    if drawObj.Arrow then drawObj.Arrow.Visible = false end
end

function SkeletonRenderer.destroy(drawObj)
    for i = 1, #drawObj.Bones do
        pcall(function() drawObj.Bones[i]:Remove() end)
    end
    pcall(function() drawObj.ViewAngle:Remove() end)
    pcall(function() drawObj.HpBg:Remove() end)
    pcall(function() drawObj.HpFill:Remove() end)
    if drawObj.NameText then pcall(function() drawObj.NameText:Remove() end) end
    if drawObj.Arrow then pcall(function() drawObj.Arrow:Remove() end) end
end

-- line segment with near clip lerp
local function renderSegment(line, spA, spB, worldA, worldB, color, thickness)
    local za, zb = spA.Z, spB.Z

    if za > EPS and zb > EPS then
        line.From = Vector2.new(spA.X, spA.Y)
        line.To = Vector2.new(spB.X, spB.Y)
        line.Color = color
        line.Thickness = thickness or 1.5
        line.Visible = true
        return true
    elseif za <= EPS and zb <= EPS then
        line.Visible = false
        return false
    else
        local t = (za - EPS) / (za - zb)
        local clippedWorld = worldA:Lerp(worldB, t)
        local spc = Camera:WorldToViewportPoint(clippedWorld)
        local clip2D = Vector2.new(spc.X, spc.Y)

        if za > EPS then
            line.From = Vector2.new(spA.X, spA.Y)
            line.To = clip2D
        else
            line.From = clip2D
            line.To = Vector2.new(spB.X, spB.Y)
        end
        line.Color = color
        line.Thickness = thickness or 1.5
        line.Visible = true
        return true
    end
end

function SkeletonRenderer.render(drawObj, char, health, maxHealth, boneColor, baseColor, Config)
    local head = char:FindFirstChild("Head")
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or head
    if not head and not root then
        SkeletonRenderer.hide(drawObj)
        return
    end

    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    local anyVisible = false
    local skeletonEnabled = not Config or (Config.SKELETON_ENABLED ~= false)
    local viewAngleEnabled = not Config or (Config.VIEWANGLE_ENABLED ~= false)

    local partPositions = {}
    local partScreenPoints = {}

    local function getPartPoint(partName)
        local cached = partScreenPoints[partName]
        if cached ~= nil then
            return cached, partPositions[partName]
        end
        local part = char:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            local pos = part.Position
            local sp = Camera:WorldToViewportPoint(pos)
            partPositions[partName] = pos
            partScreenPoints[partName] = sp
            return sp, pos
        end
        partScreenPoints[partName] = false
        return nil, nil
    end

    -- bones
    if skeletonEnabled and head then
        for i, pair in ipairs(BONE_PAIRS) do
            local spA, posA = getPartPoint(pair[1])
            local spB, posB = getPartPoint(pair[2])
            local line = drawObj.Bones[i]

            if spA and spB and posA and posB then
                local rendered = renderSegment(line, spA, spB, posA, posB, boneColor, 1.5)

                if rendered then
                    anyVisible = true
                    if spA.Z > EPS then
                        if spA.X < minX then minX = spA.X end
                        if spA.X > maxX then maxX = spA.X end
                        if spA.Y < minY then minY = spA.Y end
                        if spA.Y > maxY then maxY = spA.Y end
                    end
                    if spB.Z > EPS then
                        if spB.X < minX then minX = spB.X end
                        if spB.X > maxX then maxX = spB.X end
                        if spB.Y < minY then minY = spB.Y end
                        if spB.Y > maxY then maxY = spB.Y end
                    end
                end
            else
                line.Visible = false
            end
        end
    else
        for i = 1, #drawObj.Bones do
            drawObj.Bones[i].Visible = false
        end
    end

    -- view angle
    if skeletonEnabled and viewAngleEnabled and head then
        local spHead, headPos = getPartPoint("Head")
        if spHead and headPos then
            local camAttr = char:GetAttribute("CameraCFrame")
            local lookVector = (typeof(camAttr) == "CFrame" and camAttr.LookVector) or head.CFrame.LookVector
            local viewEndPos = headPos + (lookVector * 3.5)
            local spEnd = Camera:WorldToViewportPoint(viewEndPos)

            renderSegment(drawObj.ViewAngle, spHead, spEnd, headPos, viewEndPos, Color3.fromRGB(255, 255, 255), 1.5)
        else
            drawObj.ViewAngle.Visible = false
        end
    else
        drawObj.ViewAngle.Visible = false
    end

    -- health bar
    local hpNum = tonumber(health) or 100
    local maxHpNum = tonumber(maxHealth) or 100
    if maxHpNum <= 0 then maxHpNum = 100 end

    if skeletonEnabled and anyVisible and hpNum > 0 and minY < maxY then
        local barX = minX - 8
        local barHeight = math.max(maxY - minY, 12)
        local fraction = math.clamp(hpNum / maxHpNum, 0.01, 1.0)

        drawObj.HpBg.From = Vector2.new(barX, minY)
        drawObj.HpBg.To = Vector2.new(barX, maxY)
        drawObj.HpBg.Visible = true

        local fillTopY = maxY - (barHeight * fraction)
        drawObj.HpFill.From = Vector2.new(barX, maxY)
        drawObj.HpFill.To = Vector2.new(barX, fillTopY)
        drawObj.HpFill.Color = Color3.fromHSV(0.33 * fraction, 1, 1)
        drawObj.HpFill.Visible = true

        -- name tag
        if drawObj.NameText then
            local midX = (minX + maxX) * 0.5
            local nameY = maxY + 4
            drawObj.NameText.Text = char.Name
            drawObj.NameText.Position = Vector2.new(midX, nameY)
            drawObj.NameText.Color = boneColor
            drawObj.NameText.Outline = false
            drawObj.NameText.Visible = true
        end
    else
        drawObj.HpBg.Visible = false
        drawObj.HpFill.Visible = false
        if drawObj.NameText then drawObj.NameText.Visible = false end
    end

    -- offscreen arrow
    local arrow = drawObj.Arrow
    local showArrows = (not Config or Config.OFFSCREEN_ARROWS ~= false)

    if showArrows and root and arrow then
        local tp = root.Position
        local dist = (tp - Camera.CFrame.Position).Magnitude
        local maxDist = (Config and Config.OFFSCREEN_ARROW_MAX_DIST) or 350
        local fadeStart = (Config and Config.OFFSCREEN_ARROW_FADE_DIST) or 80

        local headSp, headOn = head and Camera:WorldToViewportPoint(head.Position)
        local rootSp, rootOn = Camera:WorldToViewportPoint(tp)

        local isCharOnScreen = (anyVisible == true)
            or (headOn and headSp and headSp.Z > 0)
            or (rootOn and rootSp and rootSp.Z > 0)

        if isCharOnScreen or dist > maxDist then
            arrow.Visible = false
        else
            local fade = 1.0
            if dist > fadeStart then
                fade = 1.0 - ((dist - fadeStart) / (maxDist - fadeStart))
                fade = math.clamp(fade, 0, 1)
            end

            if fade < 0.04 then
                arrow.Visible = false
            else
                local vpSize = Camera.ViewportSize
                local center = vpSize * 0.5
                local rel = Camera.CFrame:PointToObjectSpace(tp)

                local dir
                if rel.Z > 0 then
                    local yawAngle = math.atan2(rel.X, -rel.Z)
                    dir = Vector2.new(math.sin(yawAngle), -math.cos(yawAngle))
                else
                    dir = Vector2.new(rel.X, -rel.Y)
                end

                if dir.Magnitude < 1e-3 then
                    dir = Vector2.new(0, 1)
                else
                    dir = dir.Unit
                end

                local perp = Vector2.new(-dir.Y, dir.X)
                local radius = math.min(center.X, center.Y) * (Config and Config.OFFSCREEN_ARROW_RADIUS or 0.72)
                local at = center + dir * radius
                local sz = (Config and Config.OFFSCREEN_ARROW_SIZE) or 13

                arrow.PointA = at + dir * sz
                arrow.PointB = at - dir * (sz * 0.45) + perp * (sz * 0.75)
                arrow.PointC = at - dir * (sz * 0.45) - perp * (sz * 0.75)
                arrow.Color = baseColor or boneColor
                arrow.Transparency = fade
                arrow.Visible = true
            end
        end
    else
        if arrow then arrow.Visible = false end
    end
end

return SkeletonRenderer

end
__mods["SpectateChecker"] = function()
-- spectator indicator
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local SpectateChecker = {}
local label = nil
local guiInstance = nil

local function getGuiParent()
    if type(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
end

function SpectateChecker.init(Config)
    if not Config.SPECTATE_CHECKER_ENABLED then return nil end

    local parent = getGuiParent()
    if not parent then return nil end

    pcall(function()
        local existing = parent:FindFirstChild("AG_SpectatorUI")
        if existing then
            existing:Destroy()
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = "AG_SpectatorUI"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 1000000
        gui.Parent = parent
        guiInstance = gui

        label = Instance.new("TextLabel")
        label.Name = "SpectatorCount"
        label.Size = UDim2.new(0, 200, 0, 24)
        label.Position = UDim2.new(0.5, -100, 0.08, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 15
        label.TextStrokeTransparency = 0.25
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.TextColor3 = Color3.fromRGB(255, 75, 75)
        label.Text = ""
        label.Visible = false
        label.Parent = gui
    end)

    return label
end

function SpectateChecker.update(Config)
    if not label or not Config.SPECTATE_CHECKER_ENABLED then return end

    pcall(function()
        local specCount = LocalPlayer:GetAttribute("Spectators") or 0
        if specCount > 0 then
            label.Visible = true
            label.Text = string.format("👁️ Spectating You: %d", specCount)
        else
            label.Visible = false
            label.Text = ""
        end
    end)
end

function SpectateChecker.cleanup()
    if guiInstance then
        pcall(function() guiInstance:Destroy() end)
        guiInstance = nil
    end
    label = nil
end

return SpectateChecker

end
__mods["TargetEngine"] = function()
-- target selection and priority
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local InputController = nil
pcall(function()
    InputController = require(ReplicatedStorage.Controllers.InputController)
end)

-- fire input check
local function isShootingHeld()
    if InputController then
        local okAct, active = pcall(InputController.isActionActive, "Fire")
        if okAct and active == true then
            return true
        end

        local okPr, pressed = pcall(InputController.isActionPressed, "Fire")
        if okPr and pressed == true then
            return true
        end
    end

    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        return true
    end

    return false
end

local TargetEngine = {}

local targetHighlight = nil

local LETHAL_HEAD_PRIORITY = {"Head", "UpperTorso", "Torso", "LowerTorso", "RightUpperArm", "LeftUpperArm", "RightUpperLeg", "LeftUpperLeg"}
local LETHAL_TORSO_PRIORITY = {"UpperTorso", "Torso", "LowerTorso", "Head", "RightUpperArm", "LeftUpperArm", "RightUpperLeg", "LeftUpperLeg"}
local RANDOM_CANDIDATES = {"Head", "UpperTorso", "LowerTorso", "RightUpperArm", "LeftUpperArm", "RightUpperLeg", "LeftUpperLeg"}

local lastScanTime = 0
local lastScannedChar = nil
local cachedChosenPart = nil
local cachedOptimalPartName = "Head"

function TargetEngine.init(Config)
    targetHighlight = Instance.new("Highlight")
    targetHighlight.Name = "AG_TargetHighlight"
    targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    targetHighlight.FillTransparency = 1
    targetHighlight.OutlineTransparency = 0
    targetHighlight.OutlineColor = Config.BODYPART_HL_COLOR or Color3.fromRGB(255, 255, 0)
    targetHighlight.Enabled = false
    targetHighlight.Parent = Workspace
end

function TargetEngine.update(Config, Utils, DamageEngine)
    local isAimActive = (type(Config.isSilentAimActive) == "function") and Config.isSilentAimActive() or (Config.SILENT_AIM_ENABLED ~= false)
    if not isAimActive then
        Config.CurrentTargetChar = nil
        Config.CurrentTargetPart = nil
        Config.LockedTargetChar = nil
        Config.WaitingForM1Release = false
        if targetHighlight and targetHighlight.Enabled then
            targetHighlight.Enabled = false
        end
        return nil, nil
    end

    local vpCenter = Camera.ViewportSize * 0.5
    local charsFolder = Workspace:FindFirstChild("Characters")
    if not charsFolder then
        Config.CurrentTargetChar = nil
        Config.CurrentTargetPart = nil
        if targetHighlight and targetHighlight.Enabled then
            targetHighlight.Enabled = false
        end
        return nil, nil
    end

    local isShooting = isShootingHeld()
    local keepLock = (Config.KEEP_TARGET_LOCK ~= false)

    if not isShooting then
        Config.WaitingForM1Release = false
        Config.LockedTargetChar = nil
    end

    local selectedChar = nil

    if keepLock and isShooting and Config.WaitingForM1Release then
        selectedChar = nil
    else
        local lockedChar = Config.LockedTargetChar
        local lockedValid = false
        local camCFrame = Camera.CFrame
        local camPos = camCFrame.Position
        local camLook = camCFrame.LookVector
        local fovLimit = Config.FOV_DEG or 30

        local function getAngleDeg(targetPos)
            local dir = targetPos - camPos
            local mag = dir.Magnitude
            if mag == 0 then return 0 end
            local dot = math.clamp(camLook:Dot(dir / mag), -1, 1)
            return math.deg(math.acos(dot))
        end

        if keepLock and lockedChar and lockedChar.Parent == charsFolder and lockedChar.Name ~= LocalPlayer.Name then
            local isDead = (lockedChar:GetAttribute("Dead") == true)
            local hp = Utils.getCharacterHealth(lockedChar)
            if not isDead and hp > 0 then
                local p = Players:FindFirstChild(lockedChar.Name)
                if Utils.isEnemy(p, lockedChar) then
                    local head = lockedChar:FindFirstChild("Head")
                    if head and head:IsA("BasePart") then
                        local angle = getAngleDeg(head.Position)
                        if fovLimit >= 180 or angle <= fovLimit then
                            lockedValid = true
                        end
                    end
                end
            end
        end

        if keepLock and isShooting and lockedValid then
            selectedChar = lockedChar
        elseif keepLock and isShooting and lockedChar and not lockedValid then
            Config.WaitingForM1Release = true
            Config.LockedTargetChar = nil
            selectedChar = nil
        else
            local bestHead = nil
            local bestChar = nil
            local bestAngle = math.huge

            for _, char in ipairs(charsFolder:GetChildren()) do
                if char:IsA("Model") and char.Parent == charsFolder and char.Name ~= LocalPlayer.Name then
                    local isDead = (char:GetAttribute("Dead") == true)
                    local hp = Utils.getCharacterHealth(char)

                    if not isDead and hp > 0 then
                        local p = Players:FindFirstChild(char.Name)
                        if Utils.isEnemy(p, char) then
                            local head = char:FindFirstChild("Head")
                            if head and head:IsA("BasePart") then
                                local angle = getAngleDeg(head.Position)
                                if (fovLimit >= 180 or angle <= fovLimit) and angle < bestAngle then
                                    bestAngle = angle
                                    bestHead = head
                                    bestChar = char
                                end
                            end
                        end
                    end
                end
            end

            selectedChar = bestChar

            if keepLock and isShooting and selectedChar then
                Config.LockedTargetChar = selectedChar
            end
        end
    end

    Config.CurrentTargetChar = selectedChar
    Config.CurrentTargetPart = nil

    local optimalPartName = "Head"

    if Config.CurrentTargetChar and Config.CurrentTargetChar.Parent == charsFolder then
        local now = os.clock()
        local priorityMode = Config.TARGET_PRIORITY or "Auto"
        local shouldRescan = (Config.CurrentTargetChar ~= lastScannedChar) or ((now - lastScanTime) > 0.08)

        if shouldRescan then
            lastScanTime = now
            lastScannedChar = Config.CurrentTargetChar

            local myChar = Utils.getAliveCharacter(LocalPlayer)
            local distance = 0
            if myChar and myChar:FindFirstChild("Head") and Config.CurrentTargetChar:FindFirstChild("Head") then
                distance = (Config.CurrentTargetChar.Head.Position - myChar.Head.Position).Magnitude
            end

            local hp = Utils.getCharacterHealth(Config.CurrentTargetChar)
            local weaponName = DamageEngine.getCurrentWeapon()
            local weaponCfg = weaponName and DamageEngine.getWeaponConfig(weaponName)
            local targetPlr = Players:FindFirstChild(Config.CurrentTargetChar.Name)

            local chosenPart = nil

            if priorityMode == "Head" then
                chosenPart = Config.CurrentTargetChar:FindFirstChild("Head")
                    or Config.CurrentTargetChar:FindFirstChild("UpperTorso")
                optimalPartName = "Head"
            elseif priorityMode == "Torso" then
                chosenPart = Config.CurrentTargetChar:FindFirstChild("UpperTorso")
                    or Config.CurrentTargetChar:FindFirstChild("Torso")
                    or Config.CurrentTargetChar:FindFirstChild("LowerTorso")
                    or Config.CurrentTargetChar:FindFirstChild("HumanoidRootPart")
                optimalPartName = "Torso"
            elseif priorityMode == "Random" then
                local validCandidates = {}
                for _, name in ipairs(RANDOM_CANDIDATES) do
                    local p = Config.CurrentTargetChar:FindFirstChild(name)
                    if p and p:IsA("BasePart") then
                        table.insert(validCandidates, p)
                    end
                end
                if #validCandidates > 0 then
                    local visibleCandidates = {}
                    for _, p in ipairs(validCandidates) do
                        if not Utils.isPartOccluded(p, Config.CurrentTargetChar) then
                            table.insert(visibleCandidates, p)
                        end
                    end
                    local pool = (#visibleCandidates > 0) and visibleCandidates or validCandidates
                    chosenPart = pool[math.random(1, #pool)]
                    optimalPartName = (chosenPart.Name == "Head") and "Head" or "Torso"
                end
            else
                local lethalPref = DamageEngine.getOptimalTargetPart(weaponCfg, Config.CurrentTargetChar, targetPlr, distance, hp, Config.FALLOFF_REF)
                local priorityList = (lethalPref == "Torso") and LETHAL_TORSO_PRIORITY or LETHAL_HEAD_PRIORITY

                for _, partName in ipairs(priorityList) do
                    local p = Config.CurrentTargetChar:FindFirstChild(partName)
                    if p and p:IsA("BasePart") then
                        if not Utils.isPartOccluded(p, Config.CurrentTargetChar) then
                            chosenPart = p
                            break
                        end
                    end
                end

                if not chosenPart then
                    if lethalPref == "Torso" then
                        chosenPart = Config.CurrentTargetChar:FindFirstChild("UpperTorso")
                            or Config.CurrentTargetChar:FindFirstChild("Torso")
                            or Config.CurrentTargetChar:FindFirstChild("LowerTorso")
                            or Config.CurrentTargetChar:FindFirstChild("Head")
                    else
                        chosenPart = Config.CurrentTargetChar:FindFirstChild("Head")
                            or Config.CurrentTargetChar:FindFirstChild("UpperTorso")
                    end
                end

                optimalPartName = (chosenPart and chosenPart.Name == "Head") and "Head" or "Torso"
            end

            cachedChosenPart = chosenPart or Config.CurrentTargetChar:FindFirstChild("Head")
            cachedOptimalPartName = optimalPartName
        end

        Config.CurrentTargetPart = cachedChosenPart or Config.CurrentTargetChar:FindFirstChild("Head")
    else
        lastScannedChar = nil
        cachedChosenPart = nil
    end

    -- target part highlight
    local isAimActive = (type(Config.isSilentAimActive) == "function") and Config.isSilentAimActive() or (Config.SILENT_AIM_ENABLED ~= false)
    local canShowTargetHl = (Config.ESP_ENABLED ~= false) and Config.BODYPART_TARGET_HL and isAimActive
    if canShowTargetHl and Config.CurrentTargetPart and Config.CurrentTargetPart:IsDescendantOf(charsFolder) then
        if targetHighlight then
            if targetHighlight.Adornee ~= Config.CurrentTargetPart then
                targetHighlight.Adornee = Config.CurrentTargetPart
            end
            if not targetHighlight.Enabled then
                targetHighlight.Enabled = true
            end
        end
    else
        if targetHighlight and targetHighlight.Enabled then
            targetHighlight.Enabled = false
        end
    end

    return Config.CurrentTargetChar, Config.CurrentTargetPart
end

function TargetEngine.cleanup()
    if targetHighlight then
        pcall(function() targetHighlight:Destroy() end)
        targetHighlight = nil
    end
end

return TargetEngine

end
__mods["UIManager"] = function()
-- ui manager
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local UIManager = {
    Initialized = false,
    Library = nil,
    Window = nil,
    Connections = {}
}

function UIManager.init(Config, Library, SkinChanger, WeaponEngine, unloadCallback)
    if type(WeaponEngine) == "function" and unloadCallback == nil then
        unloadCallback = WeaponEngine
        WeaponEngine = nil
    end

    if UIManager.Initialized then return end
    UIManager.Initialized = true
    UIManager.Library = Library

    -- apply theme
    if Config.UI_THEME then
        for prop, val in pairs(Config.UI_THEME) do
            if Library[prop] ~= nil then
                Library[prop] = val
            end
        end
    end

    -- auto save debounce
    local saveDebounce = nil
    local function queueAutoSave()
        if saveDebounce then
            task.cancel(saveDebounce)
        end
        saveDebounce = task.delay(0.35, function()
            Config.save()
            saveDebounce = nil
        end)
    end

    local function updateSetting(key, newVal)
        if Config[key] ~= newVal then
            Config[key] = newVal
            queueAutoSave()
        end
    end

    -- window
    local Window = Library:CreateWindow({
        Title = "Seeto.SolutionZ / Bloxstrike / v2.5",
        Center = true,
        AutoShow = (Config.MENU_OPEN ~= false),
        TabPadding = 6,
        MenuFadeTime = 0.2,
        Size = UDim2.fromOffset(Config.WINDOW_SIZE_X or 440, Config.WINDOW_SIZE_Y or 210),
        ResizeCallback = function(w, h)
            if Config.WINDOW_SIZE_X ~= w or Config.WINDOW_SIZE_Y ~= h then
                Config.WINDOW_SIZE_X = w
                Config.WINDOW_SIZE_Y = h
                queueAutoSave()
            end
        end
    })
    UIManager.Window = Window

    local Tabs = {
        Aim = Window:AddTab("Aim"),
        Weapons = Window:AddTab("Weapons"),
        Visuals = Window:AddTab("Visuals"),
        Movement = Window:AddTab("Movement"),
        Skins = Window:AddTab("Skins"),
        Settings = Window:AddTab("Settings")
    }

    -- aim tab
    local AimMain = Tabs.Aim:AddLeftGroupbox("Silent Aim and Targeting")

    AimMain:AddToggle("SilentAim", {
        Text = "Silent aim",
        Default = (Config.SILENT_AIM_ENABLED ~= false),
        Tooltip = "Redirects bullets directly to optimal enemy hitbox within FOV cone",
        Callback = function(Value)
            updateSetting("SILENT_AIM_ENABLED", Value)
        end
    })

    AimMain:AddToggle("KeepLock", {
        Text = "Keep target lock",
        Default = (Config.KEEP_TARGET_LOCK ~= false),
        Tooltip = "Maintains lock on current target while firing",
        Callback = function(Value)
            updateSetting("KEEP_TARGET_LOCK", Value)
        end
    })

    AimMain:AddToggle("AimOcclusionCheck", {
        Text = "Occlusion check",
        Default = (Config.AIM_OCCLUSION_CHECK == true),
        Tooltip = "Prevents bullet redirection if all hitboxes of a target are occluded behind walls",
        Callback = function(Value)
            updateSetting("AIM_OCCLUSION_CHECK", Value)
        end
    })

    AimMain:AddDropdown("TargetPriority", {
        Values = { "Auto", "Head", "Torso", "Random" },
        Default = Config.TARGET_PRIORITY or "Auto",
        Multi = false,
        Text = "Target priority",
        Tooltip = "Auto: Lethal damage calculation and occlusion scanner\nHead: Strictly headshots\nTorso: Upper and lower torso\nRandom: Random visible hitbox",
        Callback = function(Value)
            updateSetting("TARGET_PRIORITY", Value)
        end
    })

    -- weapons tab
    local WeaponFire = Tabs.Weapons:AddLeftGroupbox("Fire Rate & Trigger")
    local WeaponPen = Tabs.Weapons:AddRightGroupbox("Penetration & Wallbang")

    WeaponFire:AddToggle("CustomRpm", {
        Text = "Custom fire rate (RPM)",
        Default = (Config.CUSTOM_RPM_ENABLED == true),
        Tooltip = "Overrides the fire rate for all equipped and database weapons",
        Callback = function(Value)
            updateSetting("CUSTOM_RPM_ENABLED", Value)
            if WeaponEngine and WeaponEngine.sync then WeaponEngine.sync(Config) end
        end
    })

    WeaponFire:AddSlider("RpmSlider", {
        Text = "Fire rate (RPM)",
        Default = Config.CUSTOM_RPM_VALUE or 600,
        Min = 60,
        Max = 3000,
        Rounding = 0,
        Compact = false,
        Suffix = " RPM",
        Tooltip = "Rounds per minute. Standard rifles: ~600-800 RPM. Rapid fire: 1500-3000 RPM.",
        Callback = function(Value)
            updateSetting("CUSTOM_RPM_VALUE", Value)
            if WeaponEngine and WeaponEngine.sync then WeaponEngine.sync(Config) end
        end
    })

    WeaponFire:AddToggle("ForceFullAuto", {
        Text = "Force full auto",
        Default = (Config.FORCE_FULL_AUTO == true),
        Tooltip = "Converts all semi-automatic pistols, shotguns, and snipers to full-automatic",
        Callback = function(Value)
            updateSetting("FORCE_FULL_AUTO", Value)
            if WeaponEngine and WeaponEngine.sync then WeaponEngine.sync(Config) end
        end
    })

    WeaponPen:AddToggle("Wallbang", {
        Text = "Infinite wallbang",
        Default = (Config.WALLBANG_ENABLED == true),
        Tooltip = "Fabricates bullet hits through any wall. Requires silent aim to lock a target.",
        Callback = function(Value)
            updateSetting("WALLBANG_ENABLED", Value)
        end
    })

    WeaponPen:AddButton({
        Text = "Set all default",
        Func = function()
            if Toggles.CustomRpm then Toggles.CustomRpm:SetValue(false) end
            if Options.RpmSlider then Options.RpmSlider:SetValue(1491) end
            if Toggles.ForceFullAuto then Toggles.ForceFullAuto:SetValue(false) end
            if Toggles.Wallbang then Toggles.Wallbang:SetValue(false) end
            updateSetting("CUSTOM_RPM_ENABLED", false)
            updateSetting("CUSTOM_RPM_VALUE", 1491)
            updateSetting("FORCE_FULL_AUTO", false)
            updateSetting("WALLBANG_ENABLED", false)
            if WeaponEngine and WeaponEngine.sync then WeaponEngine.sync(Config) end
            queueAutoSave()
            Library:Notify("Weapon modifiers reset to defaults", 2)
        end,
        DoubleClick = false,
        Tooltip = "Resets all weapon modifiers (RPM, Full Auto, Wallbang) to factory defaults"
    })

    -- visuals tab
    local EspMain = Tabs.Visuals:AddLeftGroupbox("ESP Elements")
    local VisualSettings = Tabs.Visuals:AddRightGroupbox("FOV & Utilities")

    EspMain:AddToggle("EspMaster", {
        Text = "Enable ESP",
        Default = (Config.ESP_ENABLED ~= false),
        Tooltip = "Master switch to enable or disable all visual ESP features",
        Callback = function(Value)
            updateSetting("ESP_ENABLED", Value)
        end
    })

    EspMain:AddToggle("SkeletonEsp", {
        Text = "Skeleton ESP",
        Default = (Config.SKELETON_ENABLED ~= false),
        Tooltip = "Renders 3D bone skeletons and health bars on characters",
        Callback = function(Value)
            updateSetting("SKELETON_ENABLED", Value)
        end
    })

    EspMain:AddToggle("ViewAngle", {
        Text = "View angle",
        Default = (Config.VIEWANGLE_ENABLED ~= false),
        Tooltip = "Renders head look direction indicator ray",
        Callback = function(Value)
            updateSetting("VIEWANGLE_ENABLED", Value)
        end
    })

    EspMain:AddToggle("OffscreenArrows", {
        Text = "Offscreen arrows",
        Default = (Config.OFFSCREEN_ARROWS ~= false),
        Tooltip = "Directional triangle pointers for out-of-view enemies with distance fade",
        Callback = function(Value)
            updateSetting("OFFSCREEN_ARROWS", Value)
        end
    })

    EspMain:AddToggle("TargetPartHl", {
        Text = "Visualize target part",
        Default = (Config.BODYPART_TARGET_HL ~= false),
        Tooltip = "Highlights active targeted limb with yellow outline",
        Callback = function(Value)
            updateSetting("BODYPART_TARGET_HL", Value)
        end
    })

    EspMain:AddToggle("DisableTeammates", {
        Text = "Disable teammates",
        Default = (Config.DISABLE_TEAMMATES == true),
        Tooltip = "Hides ESP and offscreen arrows for friendly teammates",
        Callback = function(Value)
            updateSetting("DISABLE_TEAMMATES", Value)
        end
    })

    EspMain:AddToggle("OcclusionCheck", {
        Text = "Occlusion check",
        Default = (Config.OCCLUSION_CHECK_ENABLED ~= false),
        Tooltip = "Dims skeleton bone color when character is behind walls",
        Callback = function(Value)
            updateSetting("OCCLUSION_CHECK_ENABLED", Value)
        end
    })

    EspMain:AddToggle("SpectatorChecker", {
        Text = "Spectator counter",
        Default = (Config.SPECTATE_CHECKER_ENABLED ~= false),
        Tooltip = "HUD widget displaying players spectating your camera",
        Callback = function(Value)
            updateSetting("SPECTATE_CHECKER_ENABLED", Value)
        end
    })

    VisualSettings:AddToggle("ShowFov", {
        Text = "Show FOV circle",
        Default = (Config.FOV_CIRCLE_ENABLED ~= false),
        Tooltip = "Renders screen-center FOV boundary",
        Callback = function(Value)
            updateSetting("FOV_CIRCLE_ENABLED", Value)
        end
    })

    VisualSettings:AddSlider("FovAngle", {
        Text = "FOV angle",
        Default = Config.FOV_DEG or 30,
        Min = 1,
        Max = 180,
        Rounding = 0,
        Compact = false,
        Suffix = "°",
        Callback = function(Value)
            updateSetting("FOV_DEG", Value)
        end
    })

    VisualSettings:AddSlider("FovOpacity", {
        Text = "FOV opacity",
        Default = math.floor((Config.FOV_CIRCLE_TRANSPARENCY or 0.5) * 100),
        Min = 5,
        Max = 100,
        Rounding = 0,
        Compact = false,
        Suffix = "%",
        Callback = function(Value)
            updateSetting("FOV_CIRCLE_TRANSPARENCY", Value / 100)
        end
    })

    VisualSettings:AddToggle("AntiFlash", {
        Text = "Anti-flash",
        Default = (Config.ANTI_FLASH_ENABLED ~= false),
        Tooltip = "Neutralizes blinding white screen flashes and blindness effects",
        Callback = function(Value)
            updateSetting("ANTI_FLASH_ENABLED", Value)
        end
    })

    VisualSettings:AddSlider("FlashOpacity", {
        Text = "Flash opacity",
        Default = math.floor((Config.ANTI_FLASH_TRANSPARENCY or 0.85) * 100),
        Min = 5,
        Max = 100,
        Rounding = 0,
        Compact = false,
        Suffix = "%",
        Callback = function(Value)
            updateSetting("ANTI_FLASH_TRANSPARENCY", Value / 100)
        end
    })

    -- movement tab
    local MoveMain = Tabs.Movement:AddLeftGroupbox("Movement Physics")

    MoveMain:AddToggle("Bhop", {
        Text = "Bunny hop",
        Default = (Config.BHOP_ENABLED ~= false),
        Tooltip = "Automatic jump execution via native MovementV2 physics",
        Callback = function(Value)
            updateSetting("BHOP_ENABLED", Value)
        end
    })

    -- skins tab
    local SkinsBox = Tabs.Skins:AddLeftGroupbox("Skin Changer")
    SkinsBox:AddToggle("AutoLaunchSkinchanger", {
        Text = "Auto-launch on startup",
        Default = (Config.AUTO_LAUNCH_SKINCHANGER == true),
        Tooltip = "Automatically executes the standalone Skinchanger from GitHub when Bloxstrike is initialized",
        Callback = function(Value)
            updateSetting("AUTO_LAUNCH_SKINCHANGER", Value)
        end
    })

    SkinsBox:AddButton({
        Text = "Launch Skinchanger UI",
        Func = function()
            task.spawn(function()
                -- 1. Try local workspace files first
                if type(readfile) == "function" then
                    local localPaths = {
                        "Seeto.Solutionz-Bloxstrike-Skinchanger/init.lua",
                        "Bloxstrike-Skinchanger/init.lua"
                    }
                    for _, path in ipairs(localPaths) do
                        local okRead, content = pcall(readfile, path)
                        if okRead and content and #content > 0 then
                            local fn, loadErr = loadstring(content)
                            if fn then
                                local okExec, execErr = pcall(fn)
                                if okExec then
                                    Library:Notify("Skinchanger loaded (local)!", 2)
                                    return
                                else
                                    warn("[Bloxstrike] Local skinchanger execution error:", execErr)
                                end
                            end
                        end
                    end
                end

                -- 2. Remote GitHub with cache-busting timestamp
                Library:Notify("Fetching Skinchanger from GitHub...", 2)
                local okHttp, content = pcall(function()
                    return game:HttpGet("https://raw.githubusercontent.com/euphonee/Seeto.Solutionz-Bloxstrike-Skinchanger/main/init.lua?t=" .. tostring(os.time()))
                end)
                if okHttp and content and #content > 0 then
                    local fn, loadErr = loadstring(content)
                    if fn then
                        local okExec, execErr = pcall(fn)
                        if okExec then
                            Library:Notify("Skinchanger loaded successfully!", 2)
                            return
                        else
                            warn("[Bloxstrike] Skinchanger execution error:", execErr)
                            Library:Notify("Execution error: " .. tostring(execErr), 4)
                            return
                        end
                    end
                end

                Library:Notify("Failed to fetch skinchanger from GitHub", 4)
            end)
        end,
        DoubleClick = false,
        Tooltip = "Executes the standalone Skinchanger (local/GitHub)"
    })




    -- settings tab
    local MenuGroup = Tabs.Settings:AddLeftGroupbox("Keybinds")
    local ActionsGroup = Tabs.Settings:AddRightGroupbox("Actions")

    local defaultMenuKey = (Config.TOGGLE_UI_KEY and Config.TOGGLE_UI_KEY.Name) or "Insert"
    MenuGroup:AddLabel("Menu toggle"):AddKeyPicker("MenuKeybind", {
        Default = defaultMenuKey,
        NoUI = true,
        Text = "Menu Key",
        ChangedCallback = function(NewKey)
            local key = (NewKey ~= "None") and Enum.KeyCode[NewKey] or nil
            updateSetting("TOGGLE_UI_KEY", key)
        end
    })

    local defaultAimKey = (type(Config.TOGGLE_AIM_KEY) == "string" and Config.TOGGLE_AIM_KEY) or (Config.TOGGLE_AIM_KEY and Config.TOGGLE_AIM_KEY.Name) or "None"
    MenuGroup:AddLabel("Silent aim bind"):AddKeyPicker("AimKeybind", {
        Default = defaultAimKey,
        Mode = Config.AIM_BIND_MODE or "Hold",
        NoUI = true,
        Text = "Silent aim bind",
        ChangedCallback = function(NewKey)
            local key = nil
            if NewKey and NewKey ~= "None" then
                if NewKey == "MB1" or NewKey == "MB2" or NewKey == "MB3" then
                    key = NewKey
                else
                    key = Enum.KeyCode[NewKey] or NewKey
                end
            end
            updateSetting("TOGGLE_AIM_KEY", key)
        end
    })

    MenuGroup:AddDropdown("AimBindMode", {
        Values = { "Toggle", "Hold" },
        Default = Config.AIM_BIND_MODE or "Toggle",
        Multi = false,
        Text = "Aim bind mode",
        Tooltip = "Toggle: Press key to toggle silent aim on/off\nHold: Hold key to activate silent aim",
        Callback = function(Value)
            updateSetting("AIM_BIND_MODE", Value)
            if Options and Options.AimKeybind then
                Options.AimKeybind.Mode = Value
                Options.AimKeybind.Toggled = false
            end
        end
    })

    local defaultEspKey = (Config.TOGGLE_ESP_KEY and Config.TOGGLE_ESP_KEY.Name) or "None"
    MenuGroup:AddLabel("Master ESP bind"):AddKeyPicker("EspKeybind", {
        Default = defaultEspKey,
        NoUI = true,
        Text = "Master ESP bind",
        ChangedCallback = function(NewKey)
            local key = (NewKey ~= "None") and Enum.KeyCode[NewKey] or nil
            updateSetting("TOGGLE_ESP_KEY", key)
        end
    })

    local defaultUnloadKey = (Config.UNLOAD_KEY and Config.UNLOAD_KEY.Name) or "K"
    MenuGroup:AddLabel("Unload / Kill script"):AddKeyPicker("UnloadKeybind", {
        Default = defaultUnloadKey,
        NoUI = true,
        Text = "Kill script",
        ChangedCallback = function(NewKey)
            local key = (NewKey ~= "None") and Enum.KeyCode[NewKey] or nil
            updateSetting("UNLOAD_KEY", key)
        end
    })

    Library.ToggleKeybind = Options.MenuKeybind

    ActionsGroup:AddButton({
        Text = "Reset defaults",
        Func = function()
            Config.reset()

            if Toggles.SilentAim then Toggles.SilentAim:SetValue(Config.SILENT_AIM_ENABLED) end
            if Toggles.KeepLock then Toggles.KeepLock:SetValue(Config.KEEP_TARGET_LOCK) end
            if Toggles.AimOcclusionCheck then Toggles.AimOcclusionCheck:SetValue(Config.AIM_OCCLUSION_CHECK) end
            if Options.TargetPriority then Options.TargetPriority:SetValue(Config.TARGET_PRIORITY or "Auto") end

            if Toggles.CustomRpm then Toggles.CustomRpm:SetValue(Config.CUSTOM_RPM_ENABLED) end
            if Options.RpmSlider then Options.RpmSlider:SetValue(Config.CUSTOM_RPM_VALUE or 1491) end
            if Toggles.ForceFullAuto then Toggles.ForceFullAuto:SetValue(Config.FORCE_FULL_AUTO) end
            if Toggles.Wallbang then Toggles.Wallbang:SetValue(Config.WALLBANG_ENABLED) end

            if Toggles.EspMaster then Toggles.EspMaster:SetValue(Config.ESP_ENABLED) end
            if Toggles.SkeletonEsp then Toggles.SkeletonEsp:SetValue(Config.SKELETON_ENABLED) end
            if Toggles.ViewAngle then Toggles.ViewAngle:SetValue(Config.VIEWANGLE_ENABLED) end
            if Toggles.OffscreenArrows then Toggles.OffscreenArrows:SetValue(Config.OFFSCREEN_ARROWS) end
            if Toggles.TargetPartHl then Toggles.TargetPartHl:SetValue(Config.BODYPART_TARGET_HL) end
            if Toggles.DisableTeammates then Toggles.DisableTeammates:SetValue(Config.DISABLE_TEAMMATES) end
            if Toggles.OcclusionCheck then Toggles.OcclusionCheck:SetValue(Config.OCCLUSION_CHECK_ENABLED) end
            if Toggles.SpectateChecker then Toggles.SpectateChecker:SetValue(Config.SPECTATE_CHECKER_ENABLED) end

            if Toggles.ShowFov then Toggles.ShowFov:SetValue(Config.FOV_CIRCLE_ENABLED) end
            if Options.FovAngle then Options.FovAngle:SetValue(Config.FOV_DEG or 30) end
            if Options.FovOpacity then Options.FovOpacity:SetValue(math.floor((Config.FOV_CIRCLE_TRANSPARENCY or 0.5) * 100)) end
            if Toggles.AntiFlash then Toggles.AntiFlash:SetValue(Config.ANTI_FLASH_ENABLED) end
            if Options.FlashOpacity then Options.FlashOpacity:SetValue(math.floor((Config.ANTI_FLASH_TRANSPARENCY or 0.85) * 100)) end

            if Toggles.Bhop then Toggles.Bhop:SetValue(Config.BHOP_ENABLED) end
            if Toggles.KnifeChanger then Toggles.KnifeChanger:SetValue(Config.KNIFE_SKINS_ENABLED ~= false) end
            if Toggles.WeaponChanger then Toggles.WeaponChanger:SetValue(Config.WEAPON_SKINS_ENABLED ~= false) end
            if Options.KnifeModel then Options.KnifeModel:SetValue(Config.KNIFE_MODEL or "Butterfly Knife") end
            if Options.KnifeSkin then Options.KnifeSkin:SetValue(Config.KNIFE_SKIN or "Special") end
            if Options.WeaponType then Options.WeaponType:SetValue("AK-47") end
            if Options.WeaponSkin then Options.WeaponSkin:SetValue("Special") end
            if Options.SkinMode then Options.SkinMode:SetValue(Config.SKIN_MODE or "Special") end

            if Options.MenuKeybind then Options.MenuKeybind:SetValue("Insert") end
            if Options.AimKeybind then Options.AimKeybind:SetValue("None") end
            if Options.AimBindMode then Options.AimBindMode:SetValue("Toggle") end
            if Options.EspKeybind then Options.EspKeybind:SetValue("None") end
            if Options.UnloadKeybind then Options.UnloadKeybind:SetValue("K") end

            Config.WINDOW_SIZE_X = 440
            Config.WINDOW_SIZE_Y = 210
            if Window and Window.Outer then
                Window.Outer.Size = UDim2.fromOffset(440, 210)
            end

            queueAutoSave()
            Library:Notify("Settings reset to defaults", 2)
        end,
        DoubleClick = false,
        Tooltip = "Resets all features and sliders to factory defaults"
    })

    ActionsGroup:AddButton({
        Text = "Unload suite",
        Func = function()
            if type(unloadCallback) == "function" then
                unloadCallback()
            elseif _G.__bloxstrikeJanitor then
                _G.__bloxstrikeJanitor()
            end
        end,
        DoubleClick = true,
        Tooltip = "Double click to completely unload the suite"
    })

    -- key listeners
    local function matchesAimKey(input)
        local key = Config.TOGGLE_AIM_KEY
        if not key or key == "None" then return false end

        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key
        end

        if type(key) == "string" then
            if key == "MB1" then
                return input.UserInputType == Enum.UserInputType.MouseButton1
            elseif key == "MB2" then
                return input.UserInputType == Enum.UserInputType.MouseButton2
            elseif key == "MB3" then
                return input.UserInputType == Enum.UserInputType.MouseButton3
            elseif Enum.KeyCode[key] then
                return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode[key]
            end
        end

        return false
    end

    local bindInputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if Library and Library.IsPickingKey then return end
        if UserInputService:GetFocusedTextBox() then return end

        if matchesAimKey(input) then
            if Config.AIM_BIND_MODE == "Toggle" then
                local nextState = not Config.SILENT_AIM_ENABLED
                updateSetting("SILENT_AIM_ENABLED", nextState)
                if Toggles.SilentAim and Toggles.SilentAim.Value ~= nextState then
                    Toggles.SilentAim:SetValue(nextState)
                end
            end
        elseif Config.TOGGLE_ESP_KEY and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Config.TOGGLE_ESP_KEY then
            local nextState = not Config.ESP_ENABLED
            updateSetting("ESP_ENABLED", nextState)
            if Toggles.EspMaster and Toggles.EspMaster.Value ~= nextState then
                Toggles.EspMaster:SetValue(nextState)
            end
        end
    end)
    table.insert(UIManager.Connections, bindInputBegan)

    -- block in-game weapon switching while menu is open
    pcall(function()
        local InventoryController = require(ReplicatedStorage.Controllers.InventoryController)
        if InventoryController then
            if not _G.__originalInventoryEquip then
                _G.__originalInventoryEquip = InventoryController.equip
            end
            local origEquip = _G.__originalInventoryEquip

            if not _G.__originalInventoryEquipLocal then
                _G.__originalInventoryEquipLocal = InventoryController.equipLocal
            end
            local origEquipLocal = _G.__originalInventoryEquipLocal

            InventoryController.equip = function(slot, index, ...)
                if Library and Library.Toggled then
                    return
                end
                return origEquip(slot, index, ...)
            end

            if origEquipLocal then
                InventoryController.equipLocal = function(slot, index, ...)
                    if Library and Library.Toggled then
                        return
                    end
                    return origEquipLocal(slot, index, ...)
                end
            end
        end
    end)

    Library:Notify("Seeto.SolutionZ / Bloxstrike / v2.5 Loaded!", 3)
end

function UIManager.cleanup()
    for _, c in ipairs(UIManager.Connections) do
        pcall(function() c:Disconnect() end)
    end
    UIManager.Connections = {}

    pcall(function()
        local InventoryController = require(ReplicatedStorage.Controllers.InventoryController)
        if InventoryController then
            if _G.__originalInventoryEquip then
                InventoryController.equip = _G.__originalInventoryEquip
                _G.__originalInventoryEquip = nil
            end
            if _G.__originalInventoryEquipLocal then
                InventoryController.equipLocal = _G.__originalInventoryEquipLocal
                _G.__originalInventoryEquipLocal = nil
            end
        end
    end)

    local Library = UIManager.Library
    if Library and Library.Unload then
        pcall(function() Library:Unload() end)
    end

    UIManager.Library = nil
    UIManager.Window = nil
    UIManager.Initialized = false
end

return UIManager

end
__mods["Utils"] = function()
-- utilities
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Utils = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

function Utils.getAliveCharacter(player)
    if not player then return nil end
    local chars = Workspace:FindFirstChild("Characters")
    if not chars then return nil end
    
    local char = chars:FindFirstChild(player.Name)
    if char and char:IsA("Model") and char.Parent == chars then
        if char:GetAttribute("Dead") ~= true then
            return char
        end
    end
    return nil
end

function Utils.getTeam(player, char)
    if not char and player then
        char = Utils.getAliveCharacter(player)
    end
    if player then
        local t = player:GetAttribute("Team") or player:GetAttribute("TeamName")
        if t and (t == "Counter-Terrorists" or t == "CT" or t == "Terrorists" or t == "T") then
            return t
        end
    end
    if char then
        local t = char:GetAttribute("Team") or char:GetAttribute("TeamName")
        if t and (t == "Counter-Terrorists" or t == "CT" or t == "Terrorists" or t == "T") then
            return t
        end
        local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if head and head:IsA("BasePart") then
            local cg = head.CollisionGroup
            if cg == "Counter-Terrorists" or cg == "CT" or cg == "Terrorists" or cg == "T" then
                return cg
            end
        end
        local parent = char.Parent
        if parent and (parent.Name == "Counter-Terrorists" or parent.Name == "Terrorists") then
            return parent.Name
        end
    end
    return nil
end

function Utils.getMyTeam()
    local myChar = Utils.getAliveCharacter(LocalPlayer) or LocalPlayer.Character
    return Utils.getTeam(LocalPlayer, myChar)
end

function Utils.isEnemy(player, char)
    local myTeam = Utils.getMyTeam()
    local theirTeam = Utils.getTeam(player, char)
    if not theirTeam then return false end
    if not myTeam then return true end
    return myTeam ~= theirTeam
end

function Utils.getCharacterHealth(char)
    if not char or not char.Parent then return 0, 100 end

    local charsFolder = Workspace:FindFirstChild("Characters")
    if char.Parent ~= charsFolder and (not char.Parent.Parent or char.Parent.Parent ~= charsFolder) then
        return 0, 100
    end

    if char:GetAttribute("Dead") == true then
        return 0, 100
    end

    local hp = tonumber(char:GetAttribute("Health"))
    local maxHp = tonumber(char:GetAttribute("MaxHealth"))

    if not hp or hp <= 0 then
        local p = Players:FindFirstChild(char.Name)
        if p and p:GetAttribute("Dead") == true then
            return 0, 100
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            hp = tonumber(humanoid.Health)
            maxHp = tonumber(humanoid.MaxHealth)
        end
    end

    hp = (hp and hp > 0) and hp or 100
    maxHp = (maxHp and maxHp > 0) and maxHp or 100

    return hp, maxHp
end

local cachedMyChar = nil
local cachedCam = nil

-- occlusion check to part
function Utils.isPartOccluded(part, targetChar)
    if not part then return true end

    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local targetPos = part.Position
    local direction = targetPos - origin

    local myChar = LocalPlayer.Character
    if myChar ~= cachedMyChar or cam ~= cachedCam then
        cachedMyChar = myChar
        cachedCam = cam
        rayParams.FilterDescendantsInstances = myChar and {myChar, cam} or {cam}
    end

    local result = Workspace:Raycast(origin, direction, rayParams)
    if not result then
        return false
    end

    if result.Instance == part or (targetChar and result.Instance:IsDescendantOf(targetChar)) then
        return false
    end

    return true
end

-- occlusion check to character
function Utils.isTargetOccluded(char)
    if not char then return true end
    local part = char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso")
    return Utils.isPartOccluded(part, char)
end

local HITBOX_NAMES = {
    "Head", "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm",
    "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left Leg",
    "RightUpperLeg", "RightLowerLeg", "RightFoot", "Right Leg"
}

-- check if all hitboxes of character are occluded
function Utils.areAllHitboxesOccluded(char)
    if not char then return true end
    local foundHitbox = false
    for _, name in ipairs(HITBOX_NAMES) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            foundHitbox = true
            if not Utils.isPartOccluded(p, char) then
                return false
            end
        end
    end
    if not foundHitbox then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("BasePart") then
                if not Utils.isPartOccluded(child, char) then
                    return false
                end
            end
        end
    end
    return true
end

return Utils

end
__mods["Wallbang"] = function()
-- wallbang

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Wallbang = {
    Installed = false,
    Config = nil,
}

local origSend = nil
local localPlayer = Players.LocalPlayer

function Wallbang.init(Config)
    Wallbang.Config = Config
    if Wallbang.Installed then return end
    Wallbang.Installed = true

    local Remotes = require(ReplicatedStorage.Database.Security.Remotes)
    local ShootWeapon = Remotes.Inventory.ShootWeapon
    if not ShootWeapon then return end

    if not _G.__origShootWeaponSend then
        _G.__origShootWeaponSend = ShootWeapon.Send
    end
    origSend = _G.__origShootWeaponSend

    ShootWeapon.Send = function(packet)
        if Config.WALLBANG_ENABLED and packet and packet.Bullets then
            local targetPart = Config.CurrentTargetPart
            if targetPart and targetPart.Parent and targetPart:IsDescendantOf(Workspace) then
                local char = targetPart.Parent
                if not (char:GetAttribute("Dead") == true) and char ~= localPlayer.Character then
                    for _, bullet in ipairs(packet.Bullets) do
                        local origin = bullet.Origin
                        local targetPos = targetPart.Position
                        local direction = (targetPos - origin).Unit
                        local distToTarget = (targetPos - origin).Magnitude

                        bullet.Direction = direction

                        local entryNormal = -direction
                        bullet.Hits = {
                            {
                                Normal = entryNormal,
                                Position = targetPos + entryNormal * 0.5,
                                Instance = targetPart,
                                Distance = distToTarget,
                                Exit = false,
                                Material = "Plastic",
                            },
                            {
                                Normal = direction,
                                Position = targetPos - entryNormal * 0.5,
                                Instance = targetPart,
                                Distance = 1.0,
                                Exit = true,
                                Material = "Plastic",
                            },
                        }

                        bullet.Distance = nil
                    end
                end
            end
        end

        return origSend(packet)
    end
end

function Wallbang.cleanup()
    if origSend then
        pcall(function()
            local Remotes = require(ReplicatedStorage.Database.Security.Remotes)
            Remotes.Inventory.ShootWeapon.Send = origSend
        end)
    end
    if _G.__origShootWeaponSend then
        _G.__origShootWeaponSend = nil
    end
    origSend = nil
    Wallbang.Installed = false
end

return Wallbang

end
__mods["WeaponEngine"] = function()
-- weapon engine
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local WeaponsFolder = ReplicatedStorage:WaitForChild('Database'):WaitForChild('Custom'):WaitForChild('Weapons')

local WeaponMod = nil
pcall(function()
    WeaponMod = require(ReplicatedStorage:WaitForChild('Components'):WaitForChild('Weapon'))
end)

local InventoryController = nil
pcall(function()
    InventoryController = require(ReplicatedStorage:WaitForChild('Controllers'):WaitForChild('InventoryController'))
end)

local WeaponEngine = {
    Initialized = false,
    LoopActive = false,
    Connections = {},
    _originalConfigs = {}
}

local function cloneTable(t)
    if type(t) ~= 'table' then return t end
    local copy = {}
    for k, v in pairs(t) do
        if type(v) == 'table' then
            copy[k] = cloneTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- patch database configs
local function patchDatabaseConfig(cfg, name, Config)
    if not cfg or type(cfg) ~= 'table' then return end
    if isreadonly(cfg) then setreadonly(cfg, false) end

    local orig = WeaponEngine._originalConfigs[name] or {}

    -- custom rpm
    if Config.CUSTOM_RPM_ENABLED and Config.CUSTOM_RPM_VALUE and Config.CUSTOM_RPM_VALUE > 0 then
        cfg.FireRate = 60 / Config.CUSTOM_RPM_VALUE
    elseif orig.FireRate ~= nil then
        cfg.FireRate = orig.FireRate
    end

    -- full auto
    if Config.FORCE_FULL_AUTO then
        cfg.Automatic = true
    elseif orig.Automatic ~= nil then
        cfg.Automatic = orig.Automatic
    end

    -- fire modes
    if type(cfg.FireModes) == 'table' then
        if isreadonly(cfg.FireModes) then setreadonly(cfg.FireModes, false) end
        if type(cfg.FireModes.Primary) == 'table' then
            if isreadonly(cfg.FireModes.Primary) then setreadonly(cfg.FireModes.Primary, false) end
            if Config.CUSTOM_RPM_ENABLED and Config.CUSTOM_RPM_VALUE and Config.CUSTOM_RPM_VALUE > 0 then
                cfg.FireModes.Primary.FireRate = 60 / Config.CUSTOM_RPM_VALUE
            elseif orig.FireModes and orig.FireModes.Primary and orig.FireModes.Primary.FireRate ~= nil then
                cfg.FireModes.Primary.FireRate = orig.FireModes.Primary.FireRate
            end
            if Config.FORCE_FULL_AUTO then
                cfg.FireModes.Primary.HoldRepeat = true
            elseif orig.FireModes and orig.FireModes.Primary and orig.FireModes.Primary.HoldRepeat ~= nil then
                cfg.FireModes.Primary.HoldRepeat = orig.FireModes.Primary.HoldRepeat
            end
            table.freeze(cfg.FireModes.Primary)
        end
        if type(cfg.FireModes.Secondary) == 'table' then
            if isreadonly(cfg.FireModes.Secondary) then setreadonly(cfg.FireModes.Secondary, false) end
            if Config.CUSTOM_RPM_ENABLED and Config.CUSTOM_RPM_VALUE and Config.CUSTOM_RPM_VALUE > 0 then
                cfg.FireModes.Secondary.FireRate = 60 / Config.CUSTOM_RPM_VALUE
            elseif orig.FireModes and orig.FireModes.Secondary and orig.FireModes.Secondary.FireRate ~= nil then
                cfg.FireModes.Secondary.FireRate = orig.FireModes.Secondary.FireRate
            end
            if Config.FORCE_FULL_AUTO then
                cfg.FireModes.Secondary.HoldRepeat = true
            elseif orig.FireModes and orig.FireModes.Secondary and orig.FireModes.Secondary.HoldRepeat ~= nil then
                cfg.FireModes.Secondary.HoldRepeat = orig.FireModes.Secondary.HoldRepeat
            end
            table.freeze(cfg.FireModes.Secondary)
        end
        table.freeze(cfg.FireModes)
    end

    table.freeze(cfg)
end

-- patch live item
local function patchLiveItem(item, Config)
    if not item or type(item) ~= 'table' then return end

    local props = item.Properties
    if props and type(props) == 'table' then
        if isreadonly(props) then setreadonly(props, false) end

        local orig = WeaponEngine._originalConfigs[item.Name] or {}

        if Config.CUSTOM_RPM_ENABLED and Config.CUSTOM_RPM_VALUE and Config.CUSTOM_RPM_VALUE > 0 then
            props.FireRate = 60 / Config.CUSTOM_RPM_VALUE
        elseif orig.FireRate ~= nil then
            props.FireRate = orig.FireRate
        end

        if Config.FORCE_FULL_AUTO then
            props.Automatic = true
        elseif orig.Automatic ~= nil then
            props.Automatic = orig.Automatic
        end

        if type(props.FireModes) == 'table' then
            if isreadonly(props.FireModes) then setreadonly(props.FireModes, false) end
            if type(props.FireModes.Primary) == 'table' then
                if isreadonly(props.FireModes.Primary) then setreadonly(props.FireModes.Primary, false) end
                if Config.CUSTOM_RPM_ENABLED and Config.CUSTOM_RPM_VALUE and Config.CUSTOM_RPM_VALUE > 0 then
                    props.FireModes.Primary.FireRate = 60 / Config.CUSTOM_RPM_VALUE
                end
                if Config.FORCE_FULL_AUTO then
                    props.FireModes.Primary.HoldRepeat = true
                end
                table.freeze(props.FireModes.Primary)
            end
            if type(props.FireModes.Secondary) == 'table' then
                if isreadonly(props.FireModes.Secondary) then setreadonly(props.FireModes.Secondary, false) end
                if Config.CUSTOM_RPM_ENABLED and Config.CUSTOM_RPM_VALUE and Config.CUSTOM_RPM_VALUE > 0 then
                    props.FireModes.Secondary.FireRate = 60 / Config.CUSTOM_RPM_VALUE
                end
                if Config.FORCE_FULL_AUTO then
                    props.FireModes.Secondary.HoldRepeat = true
                end
                table.freeze(props.FireModes.Secondary)
            end
            table.freeze(props.FireModes)
        end

        table.freeze(props)
    end
end

function WeaponEngine.sync(Config)
    if not Config then return end

    -- db modules
    for _, mod in ipairs(WeaponsFolder:GetChildren()) do
        if mod:IsA('ModuleScript') then
            local ok, cfg = pcall(require, mod)
            if ok and type(cfg) == 'table' then
                patchDatabaseConfig(cfg, mod.Name, Config)
            end
        end
    end

    -- shoot upvalues
    if WeaponMod and WeaponMod.shoot and getupvalues then
        local ok, upvals = pcall(getupvalues, WeaponMod.shoot)
        if ok and type(upvals) == 'table' and type(upvals[5]) == 'table' then
            for name, w in pairs(upvals[5]) do
                if type(w) == 'table' then
                    patchDatabaseConfig(w, name, Config)
                end
            end
        end
    end

    -- inventory loadout
    if InventoryController and debug.getupvalues then
        local ok, ups = pcall(debug.getupvalues, InventoryController.getCurrentInventory)
        if ok and ups and ups[1] then
            local loadout = ups[1]
            if loadout.CurrentEquipped then
                patchLiveItem(loadout.CurrentEquipped, Config)
            end
            if loadout.Inventory then
                for _, slotData in pairs(loadout.Inventory) do
                    if slotData._items then
                        for _, item in ipairs(slotData._items) do
                            patchLiveItem(item, Config)
                        end
                    end
                end
            end
        end
    end
end

function WeaponEngine.init(Config)
    if WeaponEngine.Initialized then return end
    WeaponEngine.Initialized = true

    -- cache original configs
    for _, mod in ipairs(WeaponsFolder:GetChildren()) do
        if mod:IsA('ModuleScript') then
            local ok, cfg = pcall(require, mod)
            if ok and type(cfg) == 'table' and not WeaponEngine._originalConfigs[mod.Name] then
                WeaponEngine._originalConfigs[mod.Name] = cloneTable(cfg)
            end
        end
    end

    -- equip listener
    if InventoryController and InventoryController.OnInventoryItemEquipped then
        local conn = InventoryController.OnInventoryItemEquipped:Connect(function(slot, item)
            if type(item) == 'table' then
                patchLiveItem(item, Config)
            end
            pcall(WeaponEngine.sync, Config)
        end)
        table.insert(WeaponEngine.Connections, conn)
    end

    local charConn = game:GetService('Players').LocalPlayer.CharacterAdded:Connect(function()
        task.delay(0.25, function()
            pcall(WeaponEngine.sync, Config)
        end)
    end)
    table.insert(WeaponEngine.Connections, charConn)

    -- initial sync
    WeaponEngine.sync(Config)
end

function WeaponEngine.cleanup()
    WeaponEngine.LoopActive = false
    for _, conn in ipairs(WeaponEngine.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    WeaponEngine.Connections = {}

    -- restore original configs
    for name, orig in pairs(WeaponEngine._originalConfigs) do
        local mod = WeaponsFolder:FindFirstChild(name)
        if mod and mod:IsA('ModuleScript') then
            local ok, cfg = pcall(require, mod)
            if ok and type(cfg) == 'table' then
                if isreadonly(cfg) then setreadonly(cfg, false) end
                for k, v in pairs(orig) do
                    if type(v) == 'table' then
                        cfg[k] = cloneTable(v)
                    else
                        cfg[k] = v
                    end
                end
                table.freeze(cfg)
            end
        end
    end

    WeaponEngine.Initialized = false
end

return WeaponEngine

end
__bloxstrikeBundled = __mods
pcall(function() _G.__BloxstrikeModules = __mods end)
pcall(function() if type(getgenv) == 'function' then getgenv().__BloxstrikeModules = __mods end end)

-- ===== Skinchanger（内联，开关在「手机」页）=====
local __skin = {}
__skin["API"] = function()
-- Seeto.Solutionz / Bloxstrike Skinchanger / Public API
local API = {}

local Config = nil
local Database = nil
local Engine = nil
local KnifeCatalog = nil
local GunCatalog = nil

function API.bind(cfg, db, eng, kc, gc)
    Config = cfg
    Database = db
    Engine = eng
    if kc then KnifeCatalog = kc end
    if gc then GunCatalog = gc end
end

function API.bindCatalogs(kc, gc)
    KnifeCatalog = kc
    GunCatalog = gc
end

-- Core lifecycle
function API.init(customConfig)
    if customConfig and type(customConfig) == "table" then
        for k, v in pairs(customConfig) do
            Config[k] = v
        end
    else
        Config.load()
    end
    Engine.init(Config, Database)
end

function API.cleanup()
    Engine.cleanup()
end

-- Toggles
function API.setEnabled(enabled)
    Config.ENABLED = (enabled ~= false)
    Config.save()
    Engine.refreshActiveViewmodels(Config)
end

function API.setKnifeEnabled(enabled)
    Config.KNIFE_SKINS_ENABLED = (enabled ~= false)
    Config.save()
    Engine.refreshActiveViewmodels(Config)
end

function API.setWeaponEnabled(enabled)
    Config.WEAPON_SKINS_ENABLED = (enabled ~= false)
    Config.save()
    Engine.refreshActiveViewmodels(Config)
end

-- Knife configuration
function API.setKnife(model, skin)
    if model then
        Config.KNIFE_MODEL = model
        if skin then
            if not Config.KNIFE_SKINS then Config.KNIFE_SKINS = {} end
            Config.KNIFE_SKINS[model] = skin
            Config.KNIFE_SKIN = skin
        else
            if Config.KNIFE_SKINS and Config.KNIFE_SKINS[model] then
                Config.KNIFE_SKIN = Config.KNIFE_SKINS[model]
            end
        end
    elseif skin then
        Config.KNIFE_SKIN = skin
        local currentModel = Config.KNIFE_MODEL or "Butterfly Knife"
        if not Config.KNIFE_SKINS then Config.KNIFE_SKINS = {} end
        Config.KNIFE_SKINS[currentModel] = skin
    end
    Config.save()
    Engine.refreshActiveViewmodels(Config)
end

function API.setKnifeModel(model)
    API.setKnife(model, nil)
end

function API.setKnifeSkin(skin)
    API.setKnife(nil, skin)
end

-- Weapon configuration
function API.setWeaponSkin(weaponName, skinName, wear)
    if not weaponName then return end
    if not Config.SELECTED_SKINS then Config.SELECTED_SKINS = {} end

    if wear then
        Config.SELECTED_SKINS[weaponName] = {
            Skin = skinName or "Special",
            Wear = wear or "Factory New"
        }
    else
        Config.SELECTED_SKINS[weaponName] = skinName or "Special"
    end

    Config.save()
    Engine.refreshActiveViewmodels(Config)
end

function API.getWeaponSkin(weaponName)
    if not weaponName or not Config.SELECTED_SKINS then return nil end
    return Config.SELECTED_SKINS[weaponName]
end

-- Batch configuration methods
function API.setAllSpecial()
    if not Config.SELECTED_SKINS then Config.SELECTED_SKINS = {} end
    for _, wp in ipairs(Database.WeaponTypes) do
        Config.SELECTED_SKINS[wp] = "Special"
    end
    Config.SKIN_MODE = "Special"
    Config.save()
    Engine.refreshActiveViewmodels(Config)
end

function API.setAllRandom()
    if not Config.SELECTED_SKINS then Config.SELECTED_SKINS = {} end
    for _, wp in ipairs(Database.WeaponTypes) do
        Config.SELECTED_SKINS[wp] = "Random"
    end
    Config.SKIN_MODE = "Random"
    Config.save()
    Engine.rerollRandomSkins(Config)
end

function API.setAllDefault()
    if not Config.SELECTED_SKINS then Config.SELECTED_SKINS = {} end
    for _, wp in ipairs(Database.WeaponTypes) do
        Config.SELECTED_SKINS[wp] = "Stock"
    end
    Config.save()
    Engine.refreshActiveViewmodels(Config)
end

function API.rerollRandom()
    Engine.rerollRandomSkins(Config)
end

function API.refresh()
    Engine.refreshActiveViewmodels(Config)
end

-- Query helpers
function API.getConfig()
    return Config
end

function API.getKnifeList()
    return Database.KnifeModels
end

function API.getWeaponList()
    return Database.WeaponTypes
end

function API.getKnifeSkins(knifeModel)
    return Database.getKnifeSkinList(knifeModel or Config.KNIFE_MODEL)
end

function API.getWeaponSkins(weaponName)
    return Database.getWeaponSkinList(weaponName or Config.SELECTED_WEAPON_TYPE)
end

function API.save()
    Config.save()
end

function API.load()
    Config.load()
end

function API.resetKnifeSkins()
    Config.KNIFE_MODEL = "Default"
    Config.KNIFE_SKIN = "Stock"
    Config.KNIFE_SKINS = {}
    Config.save()
    Engine.refreshActiveViewmodels(Config)
    if KnifeCatalog and KnifeCatalog.refresh then
        pcall(KnifeCatalog.refresh)
    end
end

function API.resetWeaponSkins()
    Config.SELECTED_SKINS = {}
    Config.SKIN_MODE = "Stock"
    Config.save()
    Engine.refreshActiveViewmodels(Config)
    if GunCatalog and GunCatalog.refresh then
        pcall(GunCatalog.refresh)
    end
end

function API.reset()
    Config.reset()
    Config.save()
    Engine.refreshActiveViewmodels(Config)
    if KnifeCatalog and KnifeCatalog.refresh then
        pcall(KnifeCatalog.refresh)
    end
    if GunCatalog and GunCatalog.refresh then
        pcall(GunCatalog.refresh)
    end
end

return API

end
__skin["Config"] = function()
-- Seeto.Solutionz / Bloxstrike Skinchanger / Config
local HttpService = game:GetService("HttpService")

local Config = {
    -- Toggles
    ENABLED = true,
    KNIFE_SKINS_ENABLED = true,
    WEAPON_SKINS_ENABLED = true,

    -- Knife Customization
    KNIFE_MODEL = "Default",
    KNIFE_SKIN = "Stock",
    KNIFE_SKINS = {}, -- [knifeModelName] = "SkinName"

    -- Weapon Customization
    SKIN_MODE = "Stock", -- Global fallback: "Stock" | "Special" | "Random"
    SELECTED_WEAPON_TYPE = "AK-47",
    SELECTED_SKINS = {}, -- [weaponName] = "SkinName" or { Skin = "SkinName", Wear = "Factory New" }

    -- Keybinds & UI State
    TOGGLE_UI_KEY = Enum.KeyCode.Insert,
    UNLOAD_KEY = Enum.KeyCode.K,
    WINDOW_SIZE_X = 520,
    WINDOW_SIZE_Y = 420,

    -- Persistence
    SAVE_FILE = "Bloxstrike_Skinchanger.json"
}

local saveDebounce = nil

function Config.reset()
    Config.ENABLED = true
    Config.KNIFE_SKINS_ENABLED = true
    Config.WEAPON_SKINS_ENABLED = true
    Config.KNIFE_MODEL = "Default"
    Config.KNIFE_SKIN = "Stock"
    Config.KNIFE_SKINS = {}
    Config.SKIN_MODE = "Stock"
    Config.SELECTED_WEAPON_TYPE = "AK-47"
    Config.SELECTED_SKINS = {}
    Config.WINDOW_SIZE_X = 520
    Config.WINDOW_SIZE_Y = 420
    Config.save()
end

function Config.queueSave()
    if saveDebounce then
        task.cancel(saveDebounce)
    end
    saveDebounce = task.delay(0.35, function()
        Config.save()
        saveDebounce = nil
    end)
end

function Config.save()
    if type(writefile) ~= "function" then return end
    
    local exportData = {
        ENABLED = Config.ENABLED,
        KNIFE_SKINS_ENABLED = Config.KNIFE_SKINS_ENABLED,
        WEAPON_SKINS_ENABLED = Config.WEAPON_SKINS_ENABLED,
        KNIFE_MODEL = Config.KNIFE_MODEL,
        KNIFE_SKIN = Config.KNIFE_SKIN,
        KNIFE_SKINS = Config.KNIFE_SKINS or {},
        SKIN_MODE = Config.SKIN_MODE,
        SELECTED_WEAPON_TYPE = Config.SELECTED_WEAPON_TYPE,
        SELECTED_SKINS = Config.SELECTED_SKINS,
        WINDOW_SIZE_X = Config.WINDOW_SIZE_X or 440,
        WINDOW_SIZE_Y = Config.WINDOW_SIZE_Y or 210,
        TOGGLE_UI_KEY = Config.TOGGLE_UI_KEY and Config.TOGGLE_UI_KEY.Name or "Insert",
        UNLOAD_KEY = Config.UNLOAD_KEY and Config.UNLOAD_KEY.Name or "K"
    }

    pcall(function()
        local json = HttpService:JSONEncode(exportData)
        writefile(Config.SAVE_FILE, json)
    end)
end

function Config.load()
    if type(readfile) ~= "function" then return end

    local exists = false
    if type(isfile) == "function" then
        exists = isfile(Config.SAVE_FILE)
    else
        local okTest, dataTest = pcall(readfile, Config.SAVE_FILE)
        exists = okTest and (dataTest ~= nil and #dataTest > 0)
    end
    if not exists then return end

    pcall(function()
        local raw = readfile(Config.SAVE_FILE)
        if raw and #raw > 0 then
            local data = HttpService:JSONDecode(raw)
            if type(data) == "table" then
                if data.ENABLED ~= nil then Config.ENABLED = (data.ENABLED == true) end
                if data.KNIFE_SKINS_ENABLED ~= nil then Config.KNIFE_SKINS_ENABLED = (data.KNIFE_SKINS_ENABLED == true) end
                if data.WEAPON_SKINS_ENABLED ~= nil then Config.WEAPON_SKINS_ENABLED = (data.WEAPON_SKINS_ENABLED == true) end
                if data.KNIFE_MODEL ~= nil then Config.KNIFE_MODEL = tostring(data.KNIFE_MODEL) end
                if data.KNIFE_SKIN ~= nil then Config.KNIFE_SKIN = tostring(data.KNIFE_SKIN) end
                if type(data.KNIFE_SKINS) == "table" then
                    Config.KNIFE_SKINS = data.KNIFE_SKINS
                end
                if data.SKIN_MODE ~= nil then Config.SKIN_MODE = tostring(data.SKIN_MODE) end
                if data.SELECTED_WEAPON_TYPE ~= nil then Config.SELECTED_WEAPON_TYPE = tostring(data.SELECTED_WEAPON_TYPE) end
                if type(data.SELECTED_SKINS) == "table" then
                    Config.SELECTED_SKINS = data.SELECTED_SKINS
                end
                if data.WINDOW_SIZE_X and tonumber(data.WINDOW_SIZE_X) then
                    Config.WINDOW_SIZE_X = tonumber(data.WINDOW_SIZE_X)
                end
                if data.WINDOW_SIZE_Y and tonumber(data.WINDOW_SIZE_Y) then
                    Config.WINDOW_SIZE_Y = tonumber(data.WINDOW_SIZE_Y)
                end
                if data.TOGGLE_UI_KEY and Enum.KeyCode[data.TOGGLE_UI_KEY] then
                    Config.TOGGLE_UI_KEY = Enum.KeyCode[data.TOGGLE_UI_KEY]
                end
                if data.UNLOAD_KEY and Enum.KeyCode[data.UNLOAD_KEY] then
                    Config.UNLOAD_KEY = Enum.KeyCode[data.UNLOAD_KEY]
                end
            end
        end
    end)
end

return Config

end
__skin["Database"] = function()
-- Seeto.Solutionz / Bloxstrike Skinchanger / Database
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Database = {}

Database.KnifeModels = {
    "Default",
    "Butterfly Knife",
    "Karambit",
    "M9 Bayonet",
    "Skeleton Knife",
    "Stiletto Knife",
    "Flip Knife",
    "Gut Knife",
    "LightSaber",
    "CT Knife",
    "T Knife"
}

Database.WeaponTypes = {
    "AK-47", "AUG", "AWP", "Desert Eagle", "Dual Berettas",
    "FAMAS", "Five-SeveN", "Galil AR", "Glock-18", "M4A1-S",
    "M4A4", "MAC-10", "MAG-7", "MP9", "Negev",
    "Nova", "P250", "P90", "R8 Revolver", "SG 553",
    "SSG 08", "Sawed-Off", "Tec-9", "USP-S", "XM1014", "Zeus x27"
}

Database.WearTiers = {
    "Factory New",
    "Minimal Wear",
    "Field-Tested",
    "Well-Worn",
    "Battle-Scarred"
}

Database.TopTierSkins = {
    -- Knives
    ["Butterfly Knife"] = "Fade",
    ["Karambit"]        = "Fade",
    ["M9 Bayonet"]      = "Fade",
    ["Skeleton Knife"]  = "Fade",
    ["Stiletto Knife"]  = "Whiteout",
    ["Flip Knife"]      = "Fade",
    ["Gut Knife"]       = "Fade",
    ["LightSaber"]      = "Ren",
    ["CT Knife"]        = "Lebron James",
    ["T Knife"]         = "Vanilla",

    -- Rifles
    ["AK-47"]           = "Midas",
    ["AWP"]             = "Lore",
    ["M4A4"]            = "The Ambassador",
    ["M4A1-S"]          = "Bloggd",
    ["SSG 08"]          = "Prototype",
    ["Galil AR"]        = "Limewire",
    ["FAMAS"]           = "Wallpaper",
    ["SG 553"]          = "Cryo",
    ["AUG"]             = "Hero of Hell",

    -- Pistols
    ["Desert Eagle"]    = "Lore",
    ["Glock-18"]        = "Fade",
    ["USP-S"]           = "SpecOps",
    ["Tec-9"]           = "Vice",
    ["P250"]            = "Zen",
    ["Five-SeveN"]      = "NoMercy",
    ["Dual Berettas"]   = "Overclock",
    ["R8 Revolver"]     = "Heatseeka",

    -- SMGs and Heavy
    ["MP9"]             = "Hibiki",
    ["MAC-10"]          = "Parcel",
    ["P90"]             = "Visions",
    ["UMP-45"]          = "Primal Saber",
    ["Nova"]            = "Mecha",
    ["XM1014"]          = "BloxoBlasto",
    ["MAG-7"]           = "Ambulance",
    ["Negev"]           = "Rotary Power",
    ["Sawed-Off"]       = "Memento"
}

function Database.getSkinsFolder()
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    if assets then
        return assets:FindFirstChild("Skins")
    end
    return nil
end

function Database.isKnife(weaponName)
    if typeof(weaponName) ~= "string" then return false end
    if weaponName == "Zeus x27" or weaponName:find("Zeus") or weaponName:find("Taser") then
        return false
    end
    if weaponName == "CT Knife" or weaponName == "T Knife" or weaponName == "Butterfly Knife" or weaponName:find("Knife") or weaponName:find("Bayonet") or weaponName:find("Karambit") or weaponName == "LightSaber" then
        return true
    end
    return false
end

function Database.isExemptUtility(weaponName)
    if typeof(weaponName) ~= "string" then return false end
    if weaponName == "Zeus x27" or weaponName:find("Grenade") or weaponName == "Molotov" or weaponName == "Flashbang" or weaponName == "C4" then
        return true
    end
    return false
end

function Database.getKnifeSkinList(knifeModel)
    if not knifeModel or knifeModel == "Default" then
        return { "Default" }
    end

    local list = { "Special", "Random" }
    local skinsFolder = Database.getSkinsFolder()
    local folder = skinsFolder and skinsFolder:FindFirstChild(knifeModel)

    if folder then
        local names = {}
        for _, child in ipairs(folder:GetChildren()) do
            table.insert(names, child.Name)
        end
        table.sort(names, function(a, b)
            if a == "Vanilla" or a == "Stock" then return true end
            if b == "Vanilla" or b == "Stock" then return false end
            return a:lower() < b:lower()
        end)
        for _, name in ipairs(names) do
            table.insert(list, name)
        end
    else
        table.insert(list, "Fade")
    end

    return list
end

function Database.getWeaponSkinList(weaponName)
    if not weaponName then
        return { "Special", "Random", "Stock" }
    end

    local list = { "Special", "Random", "Stock" }
    local skinsFolder = Database.getSkinsFolder()
    local folder = skinsFolder and skinsFolder:FindFirstChild(weaponName)

    if folder then
        local names = {}
        for _, child in ipairs(folder:GetChildren()) do
            if child.Name ~= "Stock" and child.Name ~= "Vanilla" and not child.Name:find("PATTERN") and child.Name ~= "Terrorists" and child.Name ~= "Counter-Terrorists" then
                table.insert(names, child.Name)
            end
        end
        table.sort(names, function(a, b)
            return a:lower() < b:lower()
        end)
        for _, name in ipairs(names) do
            table.insert(list, name)
        end
    end

    return list
end

return Database

end
__skin["Engine"] = function()
-- Seeto.Solutionz / Bloxstrike Skinchanger / Engine
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local WeaponComponent = require(ReplicatedStorage.Classes.WeaponComponent)
local SkinsLib = require(ReplicatedStorage.Database.Components.Libraries.Skins)

local GetWeaponProperties = nil
pcall(function()
    GetWeaponProperties = require(ReplicatedStorage.Components.Common.GetWeaponProperties)
end)

local CharacterAnimator = nil
pcall(function()
    CharacterAnimator = require(ReplicatedStorage.Classes.WeaponComponent.Classes.CharacterAnimator)
end)

local Sound = nil
pcall(function()
    Sound = require(ReplicatedStorage.Classes.Sound)
end)

local InventoryController = nil
pcall(function()
    InventoryController = require(ReplicatedStorage.Controllers.InventoryController)
end)

local Database = nil
local Config = nil

local Engine = {
    Initialized = false,
    Connections = {},
    RandomCache = {},
    SelectedSkins = {}
}

local function isLocalPlayerAlive()
    local charsFolder = Workspace:FindFirstChild("Characters")
    local myChar = LocalPlayer.Character
    if not myChar or not charsFolder or myChar.Parent ~= charsFolder then
        return false
    end
    if myChar:GetAttribute("Dead") == true then
        return false
    end
    return true
end

local function isViewingLocalPlayer()
    if not isLocalPlayerAlive() then
        return false
    end
    local myChar = LocalPlayer.Character
    local subject = Camera.CameraSubject
    if not subject then
        return true
    end
    if subject == myChar or subject:IsDescendantOf(myChar) then
        return true
    end
    return false
end

function Engine.getKnifeSelection(cfg)
    cfg = cfg or Config
    if not (cfg and cfg.ENABLED ~= false and cfg.KNIFE_SKINS_ENABLED ~= false) then
        return nil, nil
    end

    local targetKnife = cfg.KNIFE_MODEL or "Butterfly Knife"
    if targetKnife == "Default" then
        return nil, nil
    end

    local skinSelection = (cfg.KNIFE_SKINS and cfg.KNIFE_SKINS[targetKnife]) or cfg.KNIFE_SKIN or "Special"
    local skinName = "Fade"
    local skinsFolder = Database.getSkinsFolder()

    if skinSelection == "Random" then
        if not Engine.RandomCache[targetKnife] then
            local folder = skinsFolder and skinsFolder:FindFirstChild(targetKnife)
            if folder then
                local validSkins = {}
                for _, s in ipairs(folder:GetChildren()) do
                    if s.Name ~= "Stock" and s.Name ~= "Vanilla" then
                        table.insert(validSkins, s.Name)
                    end
                end
                if #validSkins > 0 then
                    Engine.RandomCache[targetKnife] = validSkins[math.random(1, #validSkins)]
                else
                    Engine.RandomCache[targetKnife] = "Fade"
                end
            else
                Engine.RandomCache[targetKnife] = "Fade"
            end
        end
        skinName = Engine.RandomCache[targetKnife]
    elseif skinSelection == "Special" then
        skinName = Database.TopTierSkins[targetKnife] or "Fade"
    else
        local folder = skinsFolder and skinsFolder:FindFirstChild(targetKnife)
        if folder and folder:FindFirstChild(skinSelection) then
            skinName = skinSelection
        else
            skinName = Database.TopTierSkins[targetKnife] or "Fade"
        end
    end

    return targetKnife, skinName
end

function Engine.getValidSkin(weaponName, cfg)
    cfg = cfg or Config
    if not (cfg and cfg.ENABLED ~= false and cfg.WEAPON_SKINS_ENABLED ~= false) then
        return nil
    end

    local skinsFolder = Database.getSkinsFolder()
    if not skinsFolder or not weaponName or Database.isExemptUtility(weaponName) then
        return nil
    end

    local folder = skinsFolder:FindFirstChild(weaponName)
    if not folder then return nil end

    local custom = (cfg.SELECTED_SKINS and cfg.SELECTED_SKINS[weaponName]) or Engine.SelectedSkins[weaponName]
    local customSkinName = type(custom) == "table" and custom.Skin or custom

    if customSkinName then
        if customSkinName == "Stock" or customSkinName == "Default" or customSkinName == "Vanilla" then
            return nil
        elseif customSkinName == "Special" then
            local pref = Database.TopTierSkins[weaponName]
            if pref and folder:FindFirstChild(pref) then
                return pref, "Factory New"
            end
        elseif customSkinName == "Random" then
            if not Engine.RandomCache[weaponName] then
                local validSkins = {}
                for _, s in ipairs(folder:GetChildren()) do
                    if s.Name ~= "Stock" and s.Name ~= "Vanilla" and not s.Name:find("PATTERN") and s.Name ~= "Terrorists" and s.Name ~= "Counter-Terrorists" then
                        table.insert(validSkins, s.Name)
                    end
                end
                if #validSkins > 0 then
                    Engine.RandomCache[weaponName] = validSkins[math.random(1, #validSkins)]
                else
                    Engine.RandomCache[weaponName] = "Stock"
                end
            end
            return Engine.RandomCache[weaponName], "Factory New"
        elseif folder:FindFirstChild(customSkinName) then
            local wear = (type(custom) == "table" and custom.Wear) or "Factory New"
            return customSkinName, wear
        end
    end

    local skinMode = cfg.SKIN_MODE or "Stock"

    if skinMode == "Stock" or skinMode == "Default" then
        return nil
    elseif skinMode == "Random" then
        if not Engine.RandomCache[weaponName] then
            local validSkins = {}
            for _, s in ipairs(folder:GetChildren()) do
                if s.Name ~= "Stock" and s.Name ~= "Vanilla" and not s.Name:find("PATTERN") and s.Name ~= "Terrorists" and s.Name ~= "Counter-Terrorists" then
                    table.insert(validSkins, s.Name)
                end
            end
            if #validSkins > 0 then
                Engine.RandomCache[weaponName] = validSkins[math.random(1, #validSkins)]
            else
                Engine.RandomCache[weaponName] = "Stock"
            end
        end
        return Engine.RandomCache[weaponName], "Factory New"
    elseif skinMode == "Special" then
        local pref = Database.TopTierSkins[weaponName]
        if pref and folder:FindFirstChild(pref) then
            return pref, "Factory New"
        end
    end

    return nil
end

function Engine.applySkinToViewModel(viewmodel, weaponName, skinName, wear)
    local skinsFolder = Database.getSkinsFolder()
    if not skinsFolder or not viewmodel or not weaponName or Database.isExemptUtility(weaponName) then
        return false
    end

    local weaponFolder = skinsFolder:FindFirstChild(weaponName)
    if not weaponFolder then return false end

    local targetSkin = skinName or "Stock"
    local skin = weaponFolder:FindFirstChild(targetSkin)
    if not skin and targetSkin == "Stock" then
        skin = weaponFolder:FindFirstChild("Vanilla") or weaponFolder:GetChildren()[1]
    end
    if not skin then return false end

    local camFolder = skin:FindFirstChild("Camera") or skin
    local wearFolder = camFolder:FindFirstChild(wear or "Factory New") 
        or camFolder:FindFirstChild("Factory New")
        or camFolder:FindFirstChild("Minimal Wear")
        or camFolder:FindFirstChild("Field-Tested")
        or camFolder:GetChildren()[1]

    if not wearFolder then return false end

    pcall(function()
        for _, sa in ipairs(wearFolder:GetChildren()) do
            if sa:IsA("SurfaceAppearance") then
                local targetPart = viewmodel:FindFirstChild(sa.Name, true)
                if targetPart and (targetPart:IsA("MeshPart") or targetPart:IsA("BasePart")) then
                    local old = targetPart:FindFirstChildOfClass("SurfaceAppearance")
                    if old then pcall(function() old:Destroy() end) end

                    local clone = sa:Clone()
                    clone.Parent = targetPart
                end
            end
        end
    end)
    return true
end

function Engine.rerollRandomSkins(cfg)
    Engine.RandomCache = {}
    Engine.refreshActiveViewmodels(cfg or Config)
end

function Engine.getActiveLoadout()
    if not InventoryController then
        pcall(function()
            InventoryController = require(ReplicatedStorage.Controllers.InventoryController)
        end)
    end
    if not InventoryController then return nil end

    if type(getupvalues) == "function" then
        for _, fnName in ipairs({"getCurrentEquipped", "removeInventoryItem", "getInventorySlot", "getCurrentInventory"}) do
            local fn = InventoryController[fnName]
            if type(fn) == "function" then
                local ok, uvs = pcall(getupvalues, fn)
                if ok and type(uvs) == "table" then
                    for _, uv in pairs(uvs) do
                        if type(uv) == "table" and rawget(uv, "Inventory") then
                            return uv
                        end
                    end
                end
            end
        end
    end
    return nil
end

function Engine.updateLiveKnife(cfg)
    cfg = cfg or Config
    if not isViewingLocalPlayer() then return false end

    local ld = Engine.getActiveLoadout()
    if not ld or not ld.Inventory then return false end

    local knifeSlot = ld.Inventory[3]
    if not knifeSlot or not knifeSlot._items then return false end

    local knifeItem = knifeSlot._items[1]
    if not knifeItem then return false end

    local knifeEnabled = (cfg and cfg.ENABLED ~= false and cfg.KNIFE_SKINS_ENABLED ~= false)
    local targetKnife, knifeSkin = Engine.getKnifeSelection(cfg)

    if not knifeEnabled or not targetKnife then
        local team = LocalPlayer:GetAttribute("Team")
        targetKnife = (team == "Terrorists") and "T Knife" or "CT Knife"
        knifeSkin = "Stock"
    end

    -- If knife is already this model and skin, keep it
    if knifeItem.Name == targetKnife and knifeItem.Skin == knifeSkin then
        return true
    end

    local wasEquipped = (ld.CurrentEquipped == knifeItem) or (knifeItem.Viewmodel and knifeItem.Viewmodel.IsEquipped == true)

    -- In-place mutation: preserve Identifier and _id so the server never rejects weapon equip packets
    knifeItem.Name = targetKnife
    knifeItem.Skin = knifeSkin

    if GetWeaponProperties then
        pcall(function()
            knifeItem.Properties = GetWeaponProperties(targetKnife) or knifeItem.Properties
        end)
    end

    if knifeItem.CharacterAnimator and CharacterAnimator then
        pcall(function()
            knifeItem.CharacterAnimator:destroy()
            knifeItem.CharacterAnimator = CharacterAnimator.new(LocalPlayer, targetKnife)
        end)
    end

    if knifeItem.Viewmodel then
        local vm = knifeItem.Viewmodel
        vm.Weapon = targetKnife
        vm.CameraModelWeapon = targetKnife
        vm.Skin = knifeSkin

        if Sound and Sound.new then
            pcall(function()
                if vm.Sound then vm.Sound:destroy() end
                vm.Sound = Sound.new(targetKnife)
                if vm.Animation then
                    vm.Animation.Sound = vm.Sound
                end
            end)
        end

        local char = LocalPlayer.Character
        if char then
            pcall(function()
                vm:construct(char, knifeItem)
            end)
        end

        if wasEquipped then
            pcall(function()
                vm:equip(false)
            end)
        end
    end

    -- Fire inventory changed signals to update HUD weapon icons and names
    pcall(function()
        local ic = InventoryController or require(ReplicatedStorage.Controllers.InventoryController)
        if ic then
            if ic.OnInventoryChanged then
                ic.OnInventoryChanged:Fire(ld.Inventory)
            end
            if wasEquipped and ic.OnInventoryItemEquipped then
                ic.OnInventoryItemEquipped:Fire(3, knifeItem)
            end
        end
    end)

    return true
end

function Engine.refreshActiveViewmodels(cfg)
    cfg = cfg or Config
    if not isViewingLocalPlayer() then return end
    if not (cfg and cfg.ENABLED ~= false) then return end

    -- Live update knife model in active loadout immediately
    pcall(function()
        Engine.updateLiveKnife(cfg)
    end)

    local knifeEnabled = (cfg.KNIFE_SKINS_ENABLED ~= false)
    local weaponEnabled = (cfg.WEAPON_SKINS_ENABLED ~= false)

    for _, child in ipairs(Camera:GetChildren()) do
        if child:IsA("Model") and (child:FindFirstChild("Weapon") or child:FindFirstChild("WeaponL") or child:FindFirstChild("WeaponR")) then
            local weaponName = child.Name
            if not Database.isExemptUtility(weaponName) then
                if Database.isKnife(weaponName) then
                    if knifeEnabled then
                        local targetKnife, knifeSkin = Engine.getKnifeSelection(cfg)
                        if targetKnife and knifeSkin and weaponName == targetKnife then
                            Engine.applySkinToViewModel(child, targetKnife, knifeSkin, "Factory New")
                        else
                            Engine.applySkinToViewModel(child, weaponName, "Stock", "Factory New")
                        end
                    else
                        Engine.applySkinToViewModel(child, weaponName, "Stock", "Factory New")
                    end
                else
                    if weaponEnabled then
                        local skinName, wear = Engine.getValidSkin(weaponName, cfg)
                        if skinName then
                            Engine.applySkinToViewModel(child, weaponName, skinName, wear)
                        else
                            Engine.applySkinToViewModel(child, weaponName, "Stock", "Factory New")
                        end
                    else
                        Engine.applySkinToViewModel(child, weaponName, "Stock", "Factory New")
                    end
                end
            end
        end
    end
end

local originalWeaponNew = nil
local originalGetCameraModel = nil
local originalGetCharacterModel = nil

function Engine.init(cfg, db)
    Config = cfg
    Database = db

    if Engine.Initialized then return end
    Engine.Initialized = true

    if not _G.__originalWeaponComponentNew then
        _G.__originalWeaponComponentNew = WeaponComponent.new
    end
    originalWeaponNew = _G.__originalWeaponComponentNew

    if not _G.__originalGetCameraModel then
        _G.__originalGetCameraModel = SkinsLib.GetCameraModel
    end
    originalGetCameraModel = _G.__originalGetCameraModel

    if not _G.__originalGetCharacterModel then
        _G.__originalGetCharacterModel = SkinsLib.GetCharacterModel
    end
    originalGetCharacterModel = _G.__originalGetCharacterModel

    -- Knife component hook
    WeaponComponent.new = function(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, ...)
        local knifeEnabled = (Config.ENABLED ~= false and Config.KNIFE_SKINS_ENABLED ~= false)
        if not knifeEnabled or p1 ~= LocalPlayer or not isLocalPlayerAlive() then
            return originalWeaponNew(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, ...)
        end

        if Database.isKnife(p5, p4) then
            local targetKnife, skinName = Engine.getKnifeSelection(Config)
            if targetKnife then
                return originalWeaponNew(p1, p2, p3, p4, targetKnife, skinName, 0.001, p8, p9, p10, p11, p12, ...)
            end
        end

        return originalWeaponNew(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, ...)
    end

    -- Knife viewmodel model hook
    SkinsLib.GetCameraModel = function(weaponName, skinName, float, statTrack, nameTag, charm, stickers, team)
        local knifeEnabled = (Config.ENABLED ~= false and Config.KNIFE_SKINS_ENABLED ~= false)
        if not knifeEnabled or not isViewingLocalPlayer() then
            return originalGetCameraModel(weaponName, skinName, float, statTrack, nameTag, charm, stickers, team)
        end

        if Database.isKnife(weaponName) then
            local targetKnife, knifeSkin = Engine.getKnifeSelection(Config)
            if targetKnife then
                local model = originalGetCameraModel(targetKnife, knifeSkin, 0.001, statTrack, nameTag, charm, stickers, team)
                if model then
                    model.Name = targetKnife
                end
                return model
            end
        end

        return originalGetCameraModel(weaponName, skinName, float, statTrack, nameTag, charm, stickers, team)
    end

    SkinsLib.GetCharacterModel = function(weaponName, skinName, float, statTrack, nameTag, charm, stickers, team)
        return originalGetCharacterModel(weaponName, skinName, float, statTrack, nameTag, charm, stickers, team)
    end

    -- Real-time gun texture hook on camera child added
    local cameraConn = Camera.ChildAdded:Connect(function(child)
        local weaponEnabled = (Config.ENABLED ~= false and Config.WEAPON_SKINS_ENABLED ~= false)
        if not weaponEnabled or not isViewingLocalPlayer() then return end

        if child:IsA("Model") and (child:FindFirstChild("Weapon") or child:FindFirstChild("WeaponL") or child:FindFirstChild("WeaponR")) then
            local weaponName = child.Name
            if not Database.isExemptUtility(weaponName) and not Database.isKnife(weaponName) then
                task.defer(function()
                    task.wait(0.04)
                    local currentEnabled = (Config.ENABLED ~= false and Config.WEAPON_SKINS_ENABLED ~= false)
                    if currentEnabled and isViewingLocalPlayer() then
                        local skinName, wear = Engine.getValidSkin(weaponName, Config)
                        if skinName then
                            Engine.applySkinToViewModel(child, weaponName, skinName, wear)
                        end
                    end
                end)
            end
        end
    end)
    table.insert(Engine.Connections, cameraConn)

    -- Character & Round listener
    local function onRoundChange()
        if Config.ENABLED == false then return end
        Engine.RandomCache = {}
        task.delay(0.25, function()
            if Config.ENABLED ~= false then
                Engine.refreshActiveViewmodels(Config)
            end
        end)
    end

    local charSpawnConn = LocalPlayer.CharacterAdded:Connect(function(char)
        onRoundChange()
    end)
    table.insert(Engine.Connections, charSpawnConn)

    local nr = ReplicatedStorage:FindFirstChild("NetworkRemotes")
    if nr and nr:FindFirstChild("UI") and nr.UI:FindFirstChild("RoundWinner") then
        local roundEndConn = nr.UI.RoundWinner.OnClientEvent:Connect(function()
            onRoundChange()
        end)
        table.insert(Engine.Connections, roundEndConn)
    end

    Engine.refreshActiveViewmodels(Config)
end

function Engine.cleanup()
    for _, c in ipairs(Engine.Connections) do
        pcall(function() c:Disconnect() end)
    end
    Engine.Connections = {}

    if originalWeaponNew then
        WeaponComponent.new = originalWeaponNew
    end
    if originalGetCameraModel then
        SkinsLib.GetCameraModel = originalGetCameraModel
    end
    if originalGetCharacterModel then
        SkinsLib.GetCharacterModel = originalGetCharacterModel
    end

    originalWeaponNew = nil
    originalGetCameraModel = nil
    originalGetCharacterModel = nil
    _G.__originalWeaponComponentNew = nil
    _G.__originalGetCameraModel = nil
    _G.__originalGetCharacterModel = nil
    Engine.RandomCache = {}
    Engine.Initialized = false
end

return Engine

end
__skin["GunCatalog"] = function()
-- Seeto.Solutionz / Bloxstrike Skinchanger / GunCatalog
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SkinsLib = nil
pcall(function()
    SkinsLib = require(ReplicatedStorage.Database.Components.Libraries.Skins)
end)

local GunCatalog = {
    Initialized = false,
    CurrentView = "Models", -- "Models" | "Skins"
    ActiveGun = "AK-47",
    Connections = {},
    ViewportCleanups = {}
}

local RarityColors = {
    Special   = Color3.fromRGB(255, 215, 0),   -- Gold / Yellow
    Forbidden = Color3.fromRGB(255, 140, 0),   -- Contraband / Gold-Orange
    Red       = Color3.fromRGB(235, 75, 75),    -- Covert
    Pink      = Color3.fromRGB(211, 44, 230),   -- Classified
    Purple    = Color3.fromRGB(136, 71, 255),   -- Restricted
    Blue      = Color3.fromRGB(75, 106, 255),   -- Mil-Spec
    Stock     = Color3.fromRGB(150, 155, 165),  -- Stock / Default
}

local function getRarityColor(weaponName, skinName)
    if skinName == "Stock" or skinName == "Default" or skinName == "Vanilla" then
        return RarityColors.Stock
    end
    if skinName == "Special" or skinName == "Random" then
        return RarityColors.Special
    end
    if SkinsLib and SkinsLib.GetSkinInformation then
        local ok, info = pcall(function()
            return SkinsLib.GetSkinInformation(weaponName, skinName)
        end)
        if ok and info and info.rarity and RarityColors[info.rarity] then
            return RarityColors[info.rarity]
        end
    end
    return RarityColors.Blue
end

local function cleanupViewports()
    for _, fn in ipairs(GunCatalog.ViewportCleanups) do
        pcall(fn)
    end
    GunCatalog.ViewportCleanups = {}
end

local function setupGunViewport(viewportFrame, weaponName, skinName)
    viewportFrame:ClearAllChildren()
    if not SkinsLib then return nil end

    local model = nil
    local trySkins = { skinName, "Stock", "Vanilla", "Fade", "Midas", "Lore" }
    for _, s in ipairs(trySkins) do
        if s and s ~= "Random" and s ~= "Special" then
            local ok, m = pcall(function()
                return SkinsLib.GetCharacterModel(weaponName, s, 0.001)
            end)
            if ok and m then
                model = m
                break
            end
        end
    end

    if not model then
        pcall(function()
            model = SkinsLib.GetCharacterModel(weaponName, "Stock", 0.001)
        end)
    end

    if not model then return nil end

    local clone = nil
    local cloneOk, cloneRes = pcall(function()
        return model:Clone()
    end)
    if cloneOk and cloneRes then
        clone = cloneRes
    else
        clone = model
    end

    if not clone then return nil end
    clone.Parent = viewportFrame

    local cf, sz = clone:GetBoundingBox()
    local maxDim = math.max(sz.X, sz.Y, sz.Z, 0.5)
    -- Camera placed 40% closer (0.81 factor)
    local dist = maxDim * 0.81

    local camera = Instance.new("Camera")
    camera.FieldOfView = 50
    local camPos = cf.Position + Vector3.new(dist * 0.75, dist * 0.35, dist * 0.8)
    camera.CFrame = CFrame.new(camPos, cf.Position)
    camera.Parent = viewportFrame

    viewportFrame.CurrentCamera = camera
    viewportFrame.LightColor = Color3.fromRGB(245, 245, 255)
    viewportFrame.Ambient = Color3.fromRGB(150, 150, 160)
    viewportFrame.LightDirection = Vector3.new(-1, -1.2, -1).Unit

    -- Hover turntable rotation
    local rotConn = nil
    local isHovered = false
    local currentAngle = 0

    local function onStep(dt)
        if isHovered and clone and clone.Parent and camera and camera.Parent then
            currentAngle = currentAngle + dt * 1.8
            local rotatedOffset = CFrame.Angles(0, currentAngle, 0) * Vector3.new(dist * 0.75, dist * 0.35, dist * 0.8)
            camera.CFrame = CFrame.new(cf.Position + rotatedOffset, cf.Position)
        end
    end

    rotConn = RunService.RenderStepped:Connect(onStep)
    table.insert(GunCatalog.ViewportCleanups, function()
        if rotConn then pcall(function() rotConn:Disconnect() end) end
    end)

    return {
        setHover = function(hovered)
            isHovered = hovered
            if not hovered and camera and camera.Parent then
                camera.CFrame = CFrame.new(camPos, cf.Position)
                currentAngle = 0
            end
        end
    }
end

function GunCatalog.init(Tab, Config, API, Library, Database)
    if GunCatalog.Initialized then return end
    GunCatalog.Initialized = true

    -- Hide default Linoria dual scrolling frames
    if Tab.LeftSide then Tab.LeftSide.Visible = false end
    if Tab.RightSide then Tab.RightSide.Visible = false end

    local TabFrame = Tab.TabFrame
    if not TabFrame then return end

    -- Master Container
    local MainContainer = Library:Create('Frame', {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0, 6),
        Size = UDim2.new(1, -12, 1, -12),
        ZIndex = 2,
        Parent = TabFrame
    })

    -- 1. Gun Model Catalog View
    local ModelView = Library:Create('Frame', {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        Visible = true,
        ZIndex = 2,
        Parent = MainContainer
    })

    -- Gun View Header
    local ModelHeader = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor,
        BorderColor3 = Library.OutlineColor,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 26),
        ZIndex = 3,
        Parent = ModelView
    })
    Library:AddToRegistry(ModelHeader, {
        BackgroundColor3 = 'BackgroundColor',
        BorderColor3 = 'OutlineColor'
    })

    local ModelTitle = Library:CreateLabel({
        Position = UDim2.new(0, 8, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        Text = "Gun Models",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
        Parent = ModelHeader
    })

    local ModelHint = Library:CreateLabel({
        Position = UDim2.new(0.4, 0, 0, 0),
        Size = UDim2.new(0.6, -8, 1, 0),
        Text = "Click any gun to view and select skins",
        TextColor3 = Color3.fromRGB(160, 160, 170),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
        Parent = ModelHeader
    })

    -- Gun Grid Scroll Frame (136 x 148)
    local ModelScroll = Library:Create('ScrollingFrame', {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 32),
        Size = UDim2.new(1, 0, 1, -32),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
        TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Library.AccentColor,
        ZIndex = 3,
        Parent = ModelView
    })
    Library:AddToRegistry(ModelScroll, { ScrollBarImageColor3 = 'AccentColor' })

    local ModelGrid = Library:Create('UIGridLayout', {
        CellSize = UDim2.fromOffset(136, 148),
        CellPadding = UDim2.fromOffset(8, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = ModelScroll
    })

    ModelGrid:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
        ModelScroll.CanvasSize = UDim2.fromOffset(0, ModelGrid.AbsoluteContentSize.Y + 12)
    end)

    -- 2. Skin Catalog View
    local SkinView = Library:Create('Frame', {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        Visible = false,
        ZIndex = 2,
        Parent = MainContainer
    })

    -- Skin View Header
    local SkinHeader = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor,
        BorderColor3 = Library.OutlineColor,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 26),
        ZIndex = 3,
        Parent = SkinView
    })
    Library:AddToRegistry(SkinHeader, {
        BackgroundColor3 = 'BackgroundColor',
        BorderColor3 = 'OutlineColor'
    })

    local BackButton = Library:Create('TextButton', {
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,
        Position = UDim2.new(0, 4, 0, 3),
        Size = UDim2.new(0, 110, 0, 20),
        Text = "< Back to Guns",
        TextColor3 = Library.FontColor,
        TextSize = 12,
        Font = Library.Font,
        ZIndex = 4,
        Parent = SkinHeader
    })
    Library:AddToRegistry(BackButton, {
        BackgroundColor3 = 'MainColor',
        BorderColor3 = 'OutlineColor',
        TextColor3 = 'FontColor'
    })

    local SkinTitle = Library:CreateLabel({
        Position = UDim2.new(0, 122, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        Text = "AK-47 / Skins",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
        Parent = SkinHeader
    })

    local SkinHint = Library:CreateLabel({
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.new(0.5, -8, 1, 0),
        Text = "Left-Click: Test / Equip  |  Right-Click: Equip & Return",
        TextColor3 = Color3.fromRGB(160, 160, 170),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
        Parent = SkinHeader
    })

    -- Skin Grid Scroll Frame (136 x 148)
    local SkinScroll = Library:Create('ScrollingFrame', {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 32),
        Size = UDim2.new(1, 0, 1, -32),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
        TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Library.AccentColor,
        ZIndex = 3,
        Parent = SkinView
    })
    Library:AddToRegistry(SkinScroll, { ScrollBarImageColor3 = 'AccentColor' })

    local SkinGrid = Library:Create('UIGridLayout', {
        CellSize = UDim2.fromOffset(136, 148),
        CellPadding = UDim2.fromOffset(8, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = SkinScroll
    })

    SkinGrid:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
        SkinScroll.CanvasSize = UDim2.fromOffset(0, SkinGrid.AbsoluteContentSize.Y + 12)
    end)

    -- Forward declarations
    local renderModelCards = nil
    local renderSkinCards = nil

    local function showModelView()
        GunCatalog.CurrentView = "Models"
        SkinView.Visible = false
        ModelView.Visible = true
        renderModelCards()
    end

    local function showSkinView(weaponName)
        GunCatalog.CurrentView = "Skins"
        GunCatalog.ActiveGun = weaponName
        SkinTitle.Text = weaponName .. " / Skins"
        ModelView.Visible = false
        SkinView.Visible = true
        renderSkinCards(weaponName)
    end

    BackButton.MouseButton1Click:Connect(function()
        showModelView()
    end)

    -- Render Gun Model Cards (136 x 148)
    renderModelCards = function()
        for _, child in ipairs(ModelScroll:GetChildren()) do
            if not child:IsA('UIGridLayout') then
                child:Destroy()
            end
        end
        cleanupViewports()

        for idx, weaponName in ipairs(Database.WeaponTypes) do
            local saved = Config.SELECTED_SKINS and Config.SELECTED_SKINS[weaponName]
            local currentSkin = (type(saved) == "table" and saved.Skin) or saved
            if not currentSkin or currentSkin == "Default" then
                if Config.SKIN_MODE == "Special" then
                    currentSkin = Database.TopTierSkins[weaponName] or "Stock"
                elseif Config.SKIN_MODE == "Random" then
                    currentSkin = "Random"
                else
                    currentSkin = "Stock"
                end
            end

            local rarityColor = getRarityColor(weaponName, currentSkin)
            local isCustomEquipped = (currentSkin ~= "Stock" and currentSkin ~= "Default" and currentSkin ~= "Vanilla")

            local Card = Library:Create('TextButton', {
                BackgroundColor3 = Library.BackgroundColor,
                BorderColor3 = isCustomEquipped and Library.AccentColor or Library.OutlineColor,
                BorderMode = Enum.BorderMode.Inset,
                Size = UDim2.fromOffset(136, 148),
                LayoutOrder = idx,
                Text = "",
                AutoButtonColor = false,
                ZIndex = 4,
                Parent = ModelScroll
            })

            -- Accent indicator line at top of card
            local CardTopAccent = Library:Create('Frame', {
                BackgroundColor3 = isCustomEquipped and Library.AccentColor or Color3.fromRGB(40, 40, 45),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 0, 2),
                ZIndex = 5,
                Parent = Card
            })

            -- Rarity Gradient (smooth gradient rising from bottom third)
            local RarityGradientFrame = Library:Create('Frame', {
                BackgroundColor3 = rarityColor,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 1, 0),
                ZIndex = 4,
                Parent = Card
            })

            local Grad = Instance.new('UIGradient')
            Grad.Rotation = 90
            Grad.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.67, 1),
                NumberSequenceKeypoint.new(1, 0.3)
            })
            Grad.Parent = RarityGradientFrame

            -- 3D Viewport (Height = 100px)
            local Viewport = Library:Create('ViewportFrame', {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 2, 0, 4),
                Size = UDim2.new(1, -4, 0, 100),
                ZIndex = 5,
                Parent = Card
            })

            local vpController = setupGunViewport(Viewport, weaponName, currentSkin)

            -- Gun Title Label (25% bigger: size 15)
            local TitleLabel = Library:CreateLabel({
                Position = UDim2.new(0, 4, 0, 104),
                Size = UDim2.new(1, -8, 0, 20),
                Text = weaponName,
                TextSize = 15,
                TextColor3 = Library.FontColor,
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 6,
                Parent = Card
            })

            -- Gun Subtitle / Badge (25% bigger: size 13)
            local SubLabel = Library:CreateLabel({
                Position = UDim2.new(0, 4, 0, 126),
                Size = UDim2.new(1, -8, 0, 18),
                Text = "[" .. tostring(currentSkin) .. "]",
                TextSize = 13,
                TextColor3 = (currentSkin ~= "Stock") and Color3.fromRGB(220, 220, 230) or Color3.fromRGB(140, 140, 150),
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 6,
                Parent = Card
            })

            -- Hover effects
            Card.MouseEnter:Connect(function()
                if vpController then vpController.setHover(true) end
                Card.BorderColor3 = Color3.fromRGB(100, 105, 120)
            end)

            Card.MouseLeave:Connect(function()
                if vpController then vpController.setHover(false) end
                Card.BorderColor3 = Library.OutlineColor
            end)

            -- Click: Open Skins Catalog for this weapon
            Card.MouseButton1Click:Connect(function()
                showSkinView(weaponName)
            end)

            Card.MouseButton2Click:Connect(function()
                showSkinView(weaponName)
            end)
        end
    end

    -- Render Gun Skin Cards (136 x 148)
    renderSkinCards = function(weaponName)
        for _, child in ipairs(SkinScroll:GetChildren()) do
            if not child:IsA('UIGridLayout') then
                child:Destroy()
            end
        end
        cleanupViewports()

        local saved = Config.SELECTED_SKINS and Config.SELECTED_SKINS[weaponName]
        local activeSkin = (type(saved) == "table" and saved.Skin) or saved
        if not activeSkin or activeSkin == "Default" then
            if Config.SKIN_MODE == "Special" then
                activeSkin = Database.TopTierSkins[weaponName] or "Stock"
            elseif Config.SKIN_MODE == "Random" then
                activeSkin = "Random"
            else
                activeSkin = "Stock"
            end
        end

        local skinList = Database.getWeaponSkinList(weaponName)

        for idx, skinName in ipairs(skinList) do
            local isSelected = (activeSkin == skinName)
            local rarityColor = getRarityColor(weaponName, skinName)

            local Card = Library:Create('TextButton', {
                BackgroundColor3 = Library.BackgroundColor,
                BorderColor3 = isSelected and Library.AccentColor or Library.OutlineColor,
                BorderMode = Enum.BorderMode.Inset,
                Size = UDim2.fromOffset(136, 148),
                LayoutOrder = idx,
                Text = "",
                AutoButtonColor = false,
                ZIndex = 4,
                Parent = SkinScroll
            })

            -- Accent indicator line at top of card
            local CardTopAccent = Library:Create('Frame', {
                BackgroundColor3 = isSelected and Library.AccentColor or Color3.fromRGB(40, 40, 45),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 0, 2),
                ZIndex = 5,
                Parent = Card
            })

            -- Rarity Gradient (smooth gradient rising from bottom third)
            local RarityGradientFrame = Library:Create('Frame', {
                BackgroundColor3 = rarityColor,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 1, 0),
                ZIndex = 4,
                Parent = Card
            })

            local Grad = Instance.new('UIGradient')
            Grad.Rotation = 90
            Grad.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.67, 1),
                NumberSequenceKeypoint.new(1, 0.3)
            })
            Grad.Parent = RarityGradientFrame

            -- 3D Viewport (Height = 104px)
            local Viewport = Library:Create('ViewportFrame', {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 2, 0, 4),
                Size = UDim2.new(1, -4, 0, 104),
                ZIndex = 5,
                Parent = Card
            })

            local displaySkin = skinName
            if skinName == "Special" then
                displaySkin = Database.TopTierSkins[weaponName] or "Stock"
            elseif skinName == "Random" then
                displaySkin = "Stock"
            end

            local vpController = setupGunViewport(Viewport, weaponName, displaySkin)

            -- Skin Title Label (25% bigger: size 15)
            local TitleLabel = Library:CreateLabel({
                Position = UDim2.new(0, 4, 0, 108),
                Size = UDim2.new(1, -8, 0, 20),
                Text = skinName,
                TextSize = 15,
                TextColor3 = isSelected and Library.AccentColor or Library.FontColor,
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 6,
                Parent = Card
            })

            -- Badge Label (25% bigger: size 13)
            local SubLabel = Library:CreateLabel({
                Position = UDim2.new(0, 4, 0, 128),
                Size = UDim2.new(1, -8, 0, 18),
                Text = isSelected and "[Equipped]" or "Click to Select",
                TextSize = 13,
                TextColor3 = isSelected and Library.AccentColor or Color3.fromRGB(130, 130, 140),
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 6,
                Parent = Card
            })

            -- Hover effects
            Card.MouseEnter:Connect(function()
                if vpController then vpController.setHover(true) end
                if not isSelected then
                    Card.BorderColor3 = Color3.fromRGB(100, 105, 120)
                end
            end)

            Card.MouseLeave:Connect(function()
                if vpController then vpController.setHover(false) end
                if not isSelected then
                    Card.BorderColor3 = Library.OutlineColor
                end
            end)

            -- Left-Click: Test / Equip skin in place (remain in skin catalog)
            Card.MouseButton1Click:Connect(function()
                API.setWeaponSkin(weaponName, skinName)
                Library:Notify("Equipped " .. skinName, 1.0)
                renderSkinCards(weaponName)
            end)

            -- Right-Click: Choose skin & return to Gun Models Catalog
            Card.MouseButton2Click:Connect(function()
                API.setWeaponSkin(weaponName, skinName)
                Library:Notify("Equipped " .. weaponName .. " - " .. skinName, 1.5)
                showModelView()
            end)
        end
    end

    -- Export refresh and showModelView handlers
    GunCatalog.refresh = function()
        if GunCatalog.CurrentView == "Skins" and GunCatalog.ActiveGun then
            renderSkinCards(GunCatalog.ActiveGun)
        else
            showModelView()
        end
    end

    GunCatalog.showModelView = function()
        showModelView()
    end

    -- Initial Render
    showModelView()
end

function GunCatalog.cleanup()
    cleanupViewports()
    for _, conn in ipairs(GunCatalog.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    GunCatalog.Connections = {}
    GunCatalog.Initialized = false
end

return GunCatalog

end
__skin["KnifeCatalog"] = function()
-- Seeto.Solutionz / Bloxstrike Skinchanger / KnifeCatalog
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SkinsLib = nil
pcall(function()
    SkinsLib = require(ReplicatedStorage.Database.Components.Libraries.Skins)
end)

local KnifeCatalog = {
    Initialized = false,
    CurrentView = "Models", -- "Models" | "Skins"
    ActiveKnife = "Butterfly Knife",
    Connections = {},
    ViewportCleanups = {}
}

local RarityColors = {
    Special   = Color3.fromRGB(255, 215, 0),   -- Gold / Yellow
    Forbidden = Color3.fromRGB(255, 140, 0),   -- Contraband / Gold-Orange
    Red       = Color3.fromRGB(235, 75, 75),    -- Covert
    Pink      = Color3.fromRGB(211, 44, 230),   -- Classified
    Purple    = Color3.fromRGB(136, 71, 255),   -- Restricted
    Blue      = Color3.fromRGB(75, 106, 255),   -- Mil-Spec
    Stock     = Color3.fromRGB(150, 155, 165),  -- Stock / Default
}

local function getRarityColor(knifeModel, skinName)
    if knifeModel == "Default" or skinName == "Default" or skinName == "Stock" or skinName == "Vanilla" then
        return RarityColors.Stock
    end
    if skinName == "Special" or skinName == "Random" then
        return RarityColors.Special
    end
    if SkinsLib and SkinsLib.GetSkinInformation then
        local targetModel = knifeModel
        if targetModel == "Default" then targetModel = "CT Knife" end
        local ok, info = pcall(function()
            return SkinsLib.GetSkinInformation(targetModel, skinName or "Vanilla")
        end)
        if ok and info and info.rarity and RarityColors[info.rarity] then
            return RarityColors[info.rarity]
        end
    end
    return RarityColors.Special
end

local function cleanupViewports()
    for _, fn in ipairs(KnifeCatalog.ViewportCleanups) do
        pcall(fn)
    end
    KnifeCatalog.ViewportCleanups = {}
end

local function setupKnifeViewport(viewportFrame, knifeModelName, skinName)
    viewportFrame:ClearAllChildren()
    if not SkinsLib then return nil end

    local targetModel = knifeModelName
    if targetModel == "Default" then
        targetModel = "CT Knife"
    end

    local model = nil
    local trySkins = { skinName, "Stock", "Vanilla", "Fade", "Ren", "Lebron James" }
    for _, s in ipairs(trySkins) do
        if s and s ~= "Random" and s ~= "Special" then
            local ok, m = pcall(function()
                return SkinsLib.GetCharacterModel(targetModel, s, 0.001)
            end)
            if ok and m then
                model = m
                break
            end
        end
    end

    if not model then
        pcall(function()
            model = SkinsLib.GetCharacterModel(targetModel, "Stock", 0.001)
        end)
    end

    if not model then return nil end

    local clone = nil
    local cloneOk, cloneRes = pcall(function()
        return model:Clone()
    end)
    if cloneOk and cloneRes then
        clone = cloneRes
    else
        clone = model
    end

    if not clone then return nil end
    clone.Parent = viewportFrame

    local cf, sz = clone:GetBoundingBox()
    local maxDim = math.max(sz.X, sz.Y, sz.Z, 0.5)
    -- Camera placed 40% closer (0.81 factor vs previous 1.35)
    local dist = maxDim * 0.81

    local camera = Instance.new("Camera")
    camera.FieldOfView = 50
    local camPos = cf.Position + Vector3.new(dist * 0.75, dist * 0.35, dist * 0.8)
    camera.CFrame = CFrame.new(camPos, cf.Position)
    camera.Parent = viewportFrame

    viewportFrame.CurrentCamera = camera
    viewportFrame.LightColor = Color3.fromRGB(245, 245, 255)
    viewportFrame.Ambient = Color3.fromRGB(150, 150, 160)
    viewportFrame.LightDirection = Vector3.new(-1, -1.2, -1).Unit

    -- Hover turntable rotation
    local rotConn = nil
    local isHovered = false
    local currentAngle = 0

    local function onStep(dt)
        if isHovered and clone and clone.Parent and camera and camera.Parent then
            currentAngle = currentAngle + dt * 1.8
            local rotatedOffset = CFrame.Angles(0, currentAngle, 0) * Vector3.new(dist * 0.75, dist * 0.35, dist * 0.8)
            camera.CFrame = CFrame.new(cf.Position + rotatedOffset, cf.Position)
        end
    end

    rotConn = RunService.RenderStepped:Connect(onStep)
    table.insert(KnifeCatalog.ViewportCleanups, function()
        if rotConn then pcall(function() rotConn:Disconnect() end) end
    end)

    return {
        setHover = function(hovered)
            isHovered = hovered
            if not hovered and camera and camera.Parent then
                camera.CFrame = CFrame.new(camPos, cf.Position)
                currentAngle = 0
            end
        end
    }
end

function KnifeCatalog.init(Tab, Config, API, Library, Database)
    if KnifeCatalog.Initialized then return end
    KnifeCatalog.Initialized = true

    -- Hide default Linoria dual scrolling frames
    if Tab.LeftSide then Tab.LeftSide.Visible = false end
    if Tab.RightSide then Tab.RightSide.Visible = false end

    local TabFrame = Tab.TabFrame
    if not TabFrame then return end

    -- Master Container
    local MainContainer = Library:Create('Frame', {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0, 6),
        Size = UDim2.new(1, -12, 1, -12),
        ZIndex = 2,
        Parent = TabFrame
    })

    -- 1. Model Catalog View
    local ModelView = Library:Create('Frame', {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        Visible = true,
        ZIndex = 2,
        Parent = MainContainer
    })

    -- Model View Header
    local ModelHeader = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor,
        BorderColor3 = Library.OutlineColor,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 26),
        ZIndex = 3,
        Parent = ModelView
    })
    Library:AddToRegistry(ModelHeader, {
        BackgroundColor3 = 'BackgroundColor',
        BorderColor3 = 'OutlineColor'
    })

    local ModelTitle = Library:CreateLabel({
        Position = UDim2.new(0, 8, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        Text = "Knife Models",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
        Parent = ModelHeader
    })

    local ModelHint = Library:CreateLabel({
        Position = UDim2.new(0.4, 0, 0, 0),
        Size = UDim2.new(0.6, -8, 1, 0),
        Text = "Left-Click: Equip  |  Right-Click: View Skins",
        TextColor3 = Color3.fromRGB(160, 160, 170),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
        Parent = ModelHeader
    })

    -- Model Grid Scroll Frame (10% bigger cards: 136 x 148)
    local ModelScroll = Library:Create('ScrollingFrame', {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 32),
        Size = UDim2.new(1, 0, 1, -32),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
        TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Library.AccentColor,
        ZIndex = 3,
        Parent = ModelView
    })
    Library:AddToRegistry(ModelScroll, { ScrollBarImageColor3 = 'AccentColor' })

    local ModelGrid = Library:Create('UIGridLayout', {
        CellSize = UDim2.fromOffset(136, 148),
        CellPadding = UDim2.fromOffset(8, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = ModelScroll
    })

    ModelGrid:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
        ModelScroll.CanvasSize = UDim2.fromOffset(0, ModelGrid.AbsoluteContentSize.Y + 12)
    end)

    -- 2. Skin Catalog View
    local SkinView = Library:Create('Frame', {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        Visible = false,
        ZIndex = 2,
        Parent = MainContainer
    })

    -- Skin View Header
    local SkinHeader = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor,
        BorderColor3 = Library.OutlineColor,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 26),
        ZIndex = 3,
        Parent = SkinView
    })
    Library:AddToRegistry(SkinHeader, {
        BackgroundColor3 = 'BackgroundColor',
        BorderColor3 = 'OutlineColor'
    })

    local BackButton = Library:Create('TextButton', {
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,
        Position = UDim2.new(0, 4, 0, 3),
        Size = UDim2.new(0, 120, 0, 20),
        Text = "< Back to Models",
        TextColor3 = Library.FontColor,
        TextSize = 12,
        Font = Library.Font,
        ZIndex = 4,
        Parent = SkinHeader
    })
    Library:AddToRegistry(BackButton, {
        BackgroundColor3 = 'MainColor',
        BorderColor3 = 'OutlineColor',
        TextColor3 = 'FontColor'
    })

    local SkinTitle = Library:CreateLabel({
        Position = UDim2.new(0, 132, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        Text = "Butterfly Knife / Skins",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
        Parent = SkinHeader
    })

    local SkinHint = Library:CreateLabel({
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.new(0.5, -8, 1, 0),
        Text = "Left-Click: Test / Equip  |  Right-Click: Equip & Return",
        TextColor3 = Color3.fromRGB(160, 160, 170),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
        Parent = SkinHeader
    })

    -- Skin Grid Scroll Frame (10% bigger cards: 136 x 148)
    local SkinScroll = Library:Create('ScrollingFrame', {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 32),
        Size = UDim2.new(1, 0, 1, -32),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
        TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Library.AccentColor,
        ZIndex = 3,
        Parent = SkinView
    })
    Library:AddToRegistry(SkinScroll, { ScrollBarImageColor3 = 'AccentColor' })

    local SkinGrid = Library:Create('UIGridLayout', {
        CellSize = UDim2.fromOffset(136, 148),
        CellPadding = UDim2.fromOffset(8, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = SkinScroll
    })

    SkinGrid:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
        SkinScroll.CanvasSize = UDim2.fromOffset(0, SkinGrid.AbsoluteContentSize.Y + 12)
    end)

    -- Forward declarations
    local renderModelCards = nil
    local renderSkinCards = nil

    local function showModelView()
        KnifeCatalog.CurrentView = "Models"
        SkinView.Visible = false
        ModelView.Visible = true
        renderModelCards()
    end

    local function showSkinView(knifeModelName)
        KnifeCatalog.CurrentView = "Skins"
        KnifeCatalog.ActiveKnife = knifeModelName
        SkinTitle.Text = knifeModelName .. " / Skins"
        ModelView.Visible = false
        SkinView.Visible = true
        renderSkinCards(knifeModelName)
    end

    BackButton.MouseButton1Click:Connect(function()
        showModelView()
    end)

    -- Render Model Cards (136 x 148)
    renderModelCards = function()
        for _, child in ipairs(ModelScroll:GetChildren()) do
            if not child:IsA('UIGridLayout') then
                child:Destroy()
            end
        end
        cleanupViewports()

        local currentEquipped = Config.KNIFE_MODEL or "Default"

        for idx, modelName in ipairs(Database.KnifeModels) do
            local isSelected = (currentEquipped == modelName)

            -- Resolve skin for this model from Config.KNIFE_SKINS first
            local modelSkin = (Config.KNIFE_SKINS and Config.KNIFE_SKINS[modelName])
            if not modelSkin then
                if isSelected and Config.KNIFE_SKIN and Config.KNIFE_SKIN ~= "Stock" and Config.KNIFE_SKIN ~= "Default" then
                    modelSkin = Config.KNIFE_SKIN
                else
                    modelSkin = (modelName == "Default") and "Stock" or "Vanilla"
                end
            end

            local rarityColor = getRarityColor(modelName, modelSkin)

            local Card = Library:Create('TextButton', {
                BackgroundColor3 = Library.BackgroundColor,
                BorderColor3 = isSelected and Library.AccentColor or Library.OutlineColor,
                BorderMode = Enum.BorderMode.Inset,
                Size = UDim2.fromOffset(136, 148),
                LayoutOrder = idx,
                Text = "",
                AutoButtonColor = false,
                ZIndex = 4,
                Parent = ModelScroll
            })

            -- Accent indicator line at top of card
            local CardTopAccent = Library:Create('Frame', {
                BackgroundColor3 = isSelected and Library.AccentColor or Color3.fromRGB(40, 40, 45),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 0, 2),
                ZIndex = 5,
                Parent = Card
            })

            -- Rarity Gradient (smooth gradient rising from bottom third)
            local RarityGradientFrame = Library:Create('Frame', {
                BackgroundColor3 = rarityColor,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 1, 0),
                ZIndex = 4,
                Parent = Card
            })

            local Grad = Instance.new('UIGradient')
            Grad.Rotation = 90
            Grad.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.67, 1),
                NumberSequenceKeypoint.new(1, 0.3)
            })
            Grad.Parent = RarityGradientFrame

            -- 3D Viewport (Height = 100px)
            local Viewport = Library:Create('ViewportFrame', {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 2, 0, 4),
                Size = UDim2.new(1, -4, 0, 100),
                ZIndex = 5,
                Parent = Card
            })

            local vpController = setupKnifeViewport(Viewport, modelName, modelSkin)

            -- Knife Title Label
            local TitleLabel = Library:CreateLabel({
                Position = UDim2.new(0, 4, 0, 104),
                Size = UDim2.new(1, -8, 0, 20),
                Text = modelName,
                TextSize = 15,
                TextColor3 = isSelected and Library.AccentColor or Library.FontColor,
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 6,
                Parent = Card
            })

            -- Knife Subtitle / Badge
            local SubLabel = Library:CreateLabel({
                Position = UDim2.new(0, 4, 0, 126),
                Size = UDim2.new(1, -8, 0, 18),
                Text = isSelected and ("[" .. tostring(modelSkin) .. "]") or tostring(modelSkin),
                TextSize = 13,
                TextColor3 = isSelected and Color3.fromRGB(220, 220, 230) or Color3.fromRGB(140, 140, 150),
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 6,
                Parent = Card
            })

            -- Hover effects
            Card.MouseEnter:Connect(function()
                if vpController then vpController.setHover(true) end
                if not (Config.KNIFE_MODEL == modelName) then
                    Card.BorderColor3 = Color3.fromRGB(100, 105, 120)
                end
            end)

            Card.MouseLeave:Connect(function()
                if vpController then vpController.setHover(false) end
                if not (Config.KNIFE_MODEL == modelName) then
                    Card.BorderColor3 = Library.OutlineColor
                end
            end)

            -- Left-Click: Equip Model with its saved skin
            Card.MouseButton1Click:Connect(function()
                API.setKnife(modelName, modelSkin)
                Library:Notify("Equipped " .. modelName, 1.5)
                renderModelCards()
            end)

            -- Right-Click: Open Skins Catalog
            Card.MouseButton2Click:Connect(function()
                showSkinView(modelName)
            end)
        end
    end

    -- Render Skin Cards (136 x 148)
    renderSkinCards = function(knifeModelName)
        for _, child in ipairs(SkinScroll:GetChildren()) do
            if not child:IsA('UIGridLayout') then
                child:Destroy()
            end
        end
        cleanupViewports()

        local currentEquipped = Config.KNIFE_MODEL or "Default"
        local activeModelSkin = (Config.KNIFE_SKINS and Config.KNIFE_SKINS[knifeModelName])
        if not activeModelSkin then
            if currentEquipped == knifeModelName and Config.KNIFE_SKIN and Config.KNIFE_SKIN ~= "Stock" and Config.KNIFE_SKIN ~= "Default" then
                activeModelSkin = Config.KNIFE_SKIN
            else
                activeModelSkin = (knifeModelName == "Default") and "Stock" or "Vanilla"
            end
        end

        local skinList = Database.getKnifeSkinList(knifeModelName)

        for idx, skinName in ipairs(skinList) do
            local isSelected = (currentEquipped == knifeModelName and activeModelSkin == skinName)
            local rarityColor = getRarityColor(knifeModelName, skinName)

            local Card = Library:Create('TextButton', {
                BackgroundColor3 = Library.BackgroundColor,
                BorderColor3 = isSelected and Library.AccentColor or Library.OutlineColor,
                BorderMode = Enum.BorderMode.Inset,
                Size = UDim2.fromOffset(136, 148),
                LayoutOrder = idx,
                Text = "",
                AutoButtonColor = false,
                ZIndex = 4,
                Parent = SkinScroll
            })

            -- Accent indicator line at top of card
            local CardTopAccent = Library:Create('Frame', {
                BackgroundColor3 = isSelected and Library.AccentColor or Color3.fromRGB(40, 40, 45),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 0, 2),
                ZIndex = 5,
                Parent = Card
            })

            -- Rarity Gradient (smooth gradient rising from bottom third)
            local RarityGradientFrame = Library:Create('Frame', {
                BackgroundColor3 = rarityColor,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 1, 0),
                ZIndex = 4,
                Parent = Card
            })

            local Grad = Instance.new('UIGradient')
            Grad.Rotation = 90
            Grad.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.67, 1),
                NumberSequenceKeypoint.new(1, 0.3)
            })
            Grad.Parent = RarityGradientFrame

            -- 3D Viewport (Height = 104px)
            local Viewport = Library:Create('ViewportFrame', {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 2, 0, 4),
                Size = UDim2.new(1, -4, 0, 104),
                ZIndex = 5,
                Parent = Card
            })

            local vpController = setupKnifeViewport(Viewport, knifeModelName, skinName)

            -- Skin Title Label
            local TitleLabel = Library:CreateLabel({
                Position = UDim2.new(0, 4, 0, 108),
                Size = UDim2.new(1, -8, 0, 20),
                Text = skinName,
                TextSize = 15,
                TextColor3 = isSelected and Library.AccentColor or Library.FontColor,
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 6,
                Parent = Card
            })

            -- Badge Label
            local SubLabel = Library:CreateLabel({
                Position = UDim2.new(0, 4, 0, 128),
                Size = UDim2.new(1, -8, 0, 18),
                Text = isSelected and "[Equipped]" or "Click to Select",
                TextSize = 13,
                TextColor3 = isSelected and Library.AccentColor or Color3.fromRGB(130, 130, 140),
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 6,
                Parent = Card
            })

            -- Hover effects
            Card.MouseEnter:Connect(function()
                if vpController then vpController.setHover(true) end
                if not isSelected then
                    Card.BorderColor3 = Color3.fromRGB(100, 105, 120)
                end
            end)

            Card.MouseLeave:Connect(function()
                if vpController then vpController.setHover(false) end
                if not isSelected then
                    Card.BorderColor3 = Library.OutlineColor
                end
            end)

            -- Left-Click: Test / Equip skin in place (remain in skin catalog)
            Card.MouseButton1Click:Connect(function()
                API.setKnife(knifeModelName, skinName)
                Library:Notify("Equipped " .. skinName, 1.0)
                renderSkinCards(knifeModelName)
            end)

            -- Right-Click: Choose skin & return to Knife Models Catalog
            Card.MouseButton2Click:Connect(function()
                API.setKnife(knifeModelName, skinName)
                Library:Notify("Equipped " .. knifeModelName .. " - " .. skinName, 1.5)
                showModelView()
            end)
        end
    end

    -- Export refresh and showModelView handlers
    KnifeCatalog.refresh = function()
        if KnifeCatalog.CurrentView == "Skins" and KnifeCatalog.ActiveKnife then
            renderSkinCards(KnifeCatalog.ActiveKnife)
        else
            showModelView()
        end
    end

    KnifeCatalog.showModelView = function()
        showModelView()
    end

    -- Initial Render
    showModelView()
end

function KnifeCatalog.cleanup()
    cleanupViewports()
    for _, conn in ipairs(KnifeCatalog.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    KnifeCatalog.Connections = {}
    KnifeCatalog.Initialized = false
end

return KnifeCatalog

end
__skin["LinoriaLib"] = function()
local InputService = game:GetService('UserInputService');
local ContextActionService = game:GetService('ContextActionService');
local TextService = game:GetService('TextService');
local CoreGui = game:GetService('CoreGui');
local Teams = game:GetService('Teams');
local Players = game:GetService('Players');
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local Mouse = LocalPlayer:GetMouse();

local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);

local ScreenGui = Instance.new('ScreenGui');
ProtectGui(ScreenGui);

ScreenGui.Name = "SeetoSkinChangerGui";
ScreenGui.ResetOnSpawn = false;
ScreenGui.DisplayOrder = 100;
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
local safeParent = (LocalPlayer and (LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 2))) or (type(gethui) == "function" and gethui()) or CoreGui;
ScreenGui.Parent = safeParent;

local Toggles = {};
local Options = {};

getgenv().Toggles = Toggles;
getgenv().Options = Options;

local Library = {
    Registry = {};
    RegistryMap = {};

    HudRegistry = {};

    FontColor = Color3.fromRGB(250, 250, 250);
    MainColor = Color3.fromRGB(26, 26, 30);
    BackgroundColor = Color3.fromRGB(18, 18, 22);
    AccentColor = Color3.fromRGB(245, 125, 25);
    OutlineColor = Color3.fromRGB(52, 54, 62);
    RiskColor = Color3.fromRGB(255, 60, 60),

    Black = Color3.new(0, 0, 0);
    Font = Enum.Font.Code,

    OpenedFrames = {};
    DependencyBoxes = {};

    Signals = {};
    ScreenGui = ScreenGui;
};

local RainbowStep = 0
local Hue = 0

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
    RainbowStep = RainbowStep + Delta

    if RainbowStep >= (1 / 60) then
        RainbowStep = 0

        Hue = Hue + (1 / 400);

        if Hue > 1 then
            Hue = 0;
        end;

        Library.CurrentRainbowHue = Hue;
        Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1);
    end
end))

local function GetPlayersString()
    local PlayerList = Players:GetPlayers();

    for i = 1, #PlayerList do
        PlayerList[i] = PlayerList[i].Name;
    end;

    table.sort(PlayerList, function(str1, str2) return str1 < str2 end);

    return PlayerList;
end;

local function GetTeamsString()
    local TeamList = Teams:GetTeams();

    for i = 1, #TeamList do
        TeamList[i] = TeamList[i].Name;
    end;

    table.sort(TeamList, function(str1, str2) return str1 < str2 end);
    
    return TeamList;
end;

function Library:SafeCallback(f, ...)
    if (not f) then
        return;
    end;

    if not Library.NotifyOnError then
        return f(...);
    end;

    local success, event = pcall(f, ...);

    if not success then
        local _, i = event:find(":%d+: ");

        if not i then
            return Library:Notify(event);
        end;

        return Library:Notify(event:sub(i + 1), 3);
    end;
end;

function Library:AttemptSave()
    if Library.SaveManager then
        Library.SaveManager:Save();
    end;
end;

function Library:Create(Class, Properties)
    local _Instance = Class;

    if type(Class) == 'string' then
        _Instance = Instance.new(Class);
    end;

    for Property, Value in next, Properties do
        _Instance[Property] = Value;
    end;

    return _Instance;
end;

function Library:ApplyTextStroke(Inst)
    Inst.TextStrokeTransparency = 1;

    Library:Create('UIStroke', {
        Color = Color3.new(0, 0, 0);
        Thickness = 1;
        LineJoinMode = Enum.LineJoinMode.Miter;
        Parent = Inst;
    });
end;

function Library:CreateLabel(Properties, IsHud)
    local _Instance = Library:Create('TextLabel', {
        BackgroundTransparency = 1;
        Font = Library.Font;
        TextColor3 = Library.FontColor;
        TextSize = 16;
        TextStrokeTransparency = 0;
    });

    Library:ApplyTextStroke(_Instance);

    Library:AddToRegistry(_Instance, {
        TextColor3 = 'FontColor';
    }, IsHud);

    return Library:Create(_Instance, Properties);
end;

function Library:MakeDraggable(Instance, Cutoff)
    Instance.Active = true;

    Instance.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            local ObjPos = Vector2.new(
                Mouse.X - Instance.AbsolutePosition.X,
                Mouse.Y - Instance.AbsolutePosition.Y
            );

            if ObjPos.Y > (Cutoff or 40) then
                return;
            end;

            while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                Instance.Position = UDim2.new(
                    0,
                    Mouse.X - ObjPos.X + (Instance.Size.X.Offset * Instance.AnchorPoint.X),
                    0,
                    Mouse.Y - ObjPos.Y + (Instance.Size.Y.Offset * Instance.AnchorPoint.Y)
                );

                RenderStepped:Wait();
            end;
        end;
    end)
end;

function Library:MakeResizable(Instance, MinWidth, MinHeight, MaxWidth, MaxHeight, ResizeCallback)
    local function getMinWidth()
        if type(MinWidth) == 'function' then return MinWidth() end
        return MinWidth or 440;
    end
    local function getMinHeight()
        if type(MinHeight) == 'function' then return MinHeight() end
        return MinHeight or 210;
    end
    local function getMaxWidth()
        if type(MaxWidth) == 'function' then return MaxWidth() end
        return MaxWidth or 1200;
    end
    local function getMaxHeight()
        if type(MaxHeight) == 'function' then return MaxHeight() end
        return MaxHeight or 900;
    end

    local ResizeGrip = Library:Create('ImageButton', {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -2, 1, -2),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ZIndex = 50,
        Parent = Instance,
        AutoButtonColor = false
    });

    local Dots = {};
    local dotCoords = {
        { -3, -3 }, { -7, -3 }, { -3, -7 },
        { -11, -3 }, { -7, -7 }, { -3, -11 }
    };

    for _, coord in ipairs(dotCoords) do
        local dot = Library:Create('Frame', {
            BackgroundColor3 = Library.OutlineColor,
            BorderSizePixel = 0,
            Position = UDim2.new(1, coord[1], 1, coord[2]),
            Size = UDim2.new(0, 2, 0, 2),
            ZIndex = 51,
            Parent = ResizeGrip
        });
        table.insert(Dots, dot);
        Library:AddToRegistry(dot, {
            BackgroundColor3 = 'OutlineColor'
        });
    end

    ResizeGrip.MouseEnter:Connect(function()
        for _, dot in ipairs(Dots) do
            dot.BackgroundColor3 = Library.AccentColor;
        end
    end);

    ResizeGrip.MouseLeave:Connect(function()
        for _, dot in ipairs(Dots) do
            dot.BackgroundColor3 = Library.OutlineColor;
        end
    end);

    ResizeGrip.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            local startMouse = Vector2.new(Mouse.X, Mouse.Y);
            local startSize = Instance.AbsoluteSize;

            if Instance.AnchorPoint == Vector2.new(0.5, 0.5) then
                local currentAbsPos = Instance.AbsolutePosition;
                Instance.AnchorPoint = Vector2.zero;
                Instance.Position = UDim2.fromOffset(currentAbsPos.X, currentAbsPos.Y);
            end

            while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                local deltaX = Mouse.X - startMouse.X;
                local deltaY = Mouse.Y - startMouse.Y;

                local newWidth = math.clamp(startSize.X + deltaX, getMinWidth(), getMaxWidth());
                local newHeight = math.clamp(startSize.Y + deltaY, getMinHeight(), getMaxHeight());

                Instance.Size = UDim2.fromOffset(newWidth, newHeight);

                if type(ResizeCallback) == 'function' then
                    ResizeCallback(newWidth, newHeight);
                end

                RenderStepped:Wait();
            end;
        end
    end);
end;

function Library:AddToolTip(InfoStr, HoverInstance)
    local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14);
    local Tooltip = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,

        Size = UDim2.fromOffset(X + 5, Y + 4),
        ZIndex = 100,
        Parent = Library.ScreenGui,

        Visible = false,
    })

    local Label = Library:CreateLabel({
        Position = UDim2.fromOffset(3, 1),
        Size = UDim2.fromOffset(X, Y);
        TextSize = 14;
        Text = InfoStr,
        TextColor3 = Library.FontColor,
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = Tooltip.ZIndex + 1,

        Parent = Tooltip;
    });

    Library:AddToRegistry(Tooltip, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    Library:AddToRegistry(Label, {
        TextColor3 = 'FontColor',
    });

    local IsHovering = false

    HoverInstance.MouseEnter:Connect(function()
        if Library:MouseIsOverOpenedFrame() then
            return
        end

        IsHovering = true

        Tooltip.Position = UDim2.fromOffset(Mouse.X + 15, Mouse.Y + 12)
        Tooltip.Visible = true

        while IsHovering do
            RunService.Heartbeat:Wait()
            Tooltip.Position = UDim2.fromOffset(Mouse.X + 15, Mouse.Y + 12)
        end
    end)

    HoverInstance.MouseLeave:Connect(function()
        IsHovering = false
        Tooltip.Visible = false
    end)
end

function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
    HighlightInstance.MouseEnter:Connect(function()
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, Properties do
            Instance[Property] = Library[ColorIdx] or ColorIdx;

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end)

    HighlightInstance.MouseLeave:Connect(function()
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, PropertiesDefault do
            Instance[Property] = Library[ColorIdx] or ColorIdx;

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end)
end;

function Library:MouseIsOverOpenedFrame()
    for Frame, _ in next, Library.OpenedFrames do
        local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

        if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
            and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

            return true;
        end;
    end;
end;

function Library:IsMouseOverFrame(Frame)
    local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

    if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
        and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

        return true;
    end;
end;

function Library:UpdateDependencyBoxes()
    for _, Depbox in next, Library.DependencyBoxes do
        Depbox:Update();
    end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
    return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

function Library:GetTextBounds(Text, Font, Size, Resolution)
    local Bounds = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080))
    return Bounds.X, Bounds.Y
end;

function Library:GetDarkerColor(Color)
    local H, S, V = Color3.toHSV(Color);
    return Color3.fromHSV(H, S, V / 1.5);
end;
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:AddToRegistry(Instance, Properties, IsHud)
    local Idx = #Library.Registry + 1;
    local Data = {
        Instance = Instance;
        Properties = Properties;
        Idx = Idx;
    };

    table.insert(Library.Registry, Data);
    Library.RegistryMap[Instance] = Data;

    if IsHud then
        table.insert(Library.HudRegistry, Data);
    end;
end;

function Library:RemoveFromRegistry(Instance)
    local Data = Library.RegistryMap[Instance];

    if Data then
        for Idx = #Library.Registry, 1, -1 do
            if Library.Registry[Idx] == Data then
                table.remove(Library.Registry, Idx);
            end;
        end;

        for Idx = #Library.HudRegistry, 1, -1 do
            if Library.HudRegistry[Idx] == Data then
                table.remove(Library.HudRegistry, Idx);
            end;
        end;

        Library.RegistryMap[Instance] = nil;
    end;
end;

function Library:UpdateColorsUsingRegistry()
    -- TODO: Could have an 'active' list of objects
    -- where the active list only contains Visible objects.

    -- IMPL: Could setup .Changed events on the AddToRegistry function
    -- that listens for the 'Visible' propert being changed.
    -- Visible: true => Add to active list, and call UpdateColors function
    -- Visible: false => Remove from active list.

    -- The above would be especially efficient for a rainbow menu color or live color-changing.

    for Idx, Object in next, Library.Registry do
        for Property, ColorIdx in next, Object.Properties do
            if type(ColorIdx) == 'string' then
                Object.Instance[Property] = Library[ColorIdx];
            elseif type(ColorIdx) == 'function' then
                Object.Instance[Property] = ColorIdx()
            end
        end;
    end;
end;

function Library:GiveSignal(Signal)
    -- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
    table.insert(Library.Signals, Signal)
end

function Library:Unload()
    -- Unload all of the signals
    for Idx = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, Idx)
        Connection:Disconnect()
    end

     -- Call our unload callback, maybe to undo some hooks etc
    if Library.OnUnload then
        Library.OnUnload()
    end

    ScreenGui:Destroy()
end

function Library:OnUnload(Callback)
    Library.OnUnload = Callback
end

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
    if Library.RegistryMap[Instance] then
        Library:RemoveFromRegistry(Instance);
    end;
end))

local BaseAddons = {};

do
    local Funcs = {};

    function Funcs:AddColorPicker(Idx, Info)
        local ToggleLabel = self.TextLabel;
        -- local Container = self.Container;

        assert(Info.Default, 'AddColorPicker: Missing default value.');

        local ColorPicker = {
            Value = Info.Default;
            Transparency = Info.Transparency or 0;
            Type = 'ColorPicker';
            Title = type(Info.Title) == 'string' and Info.Title or 'Color picker',
            Callback = Info.Callback or function(Color) end;
        };

        function ColorPicker:SetHSVFromRGB(Color)
            local H, S, V = Color3.toHSV(Color);

            ColorPicker.Hue = H;
            ColorPicker.Sat = S;
            ColorPicker.Vib = V;
        end;

        ColorPicker:SetHSVFromRGB(ColorPicker.Value);

        local DisplayFrame = Library:Create('Frame', {
            BackgroundColor3 = ColorPicker.Value;
            BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(0, 28, 0, 14);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        -- Transparency image taken from https://github.com/matas3535/SplixPrivateDrawingLibrary/blob/main/Library.lua cus i'm lazy
        local CheckerFrame = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size = UDim2.new(0, 27, 0, 13);
            ZIndex = 5;
            Image = 'http://www.roblox.com/asset/?id=12977615774';
            Visible = not not Info.Transparency;
            Parent = DisplayFrame;
        });

        -- 1/16/23
        -- Rewrote this to be placed inside the Library ScreenGui
        -- There was some issue which caused RelativeOffset to be way off
        -- Thus the color picker would never show

        local PickerFrameOuter = Library:Create('Frame', {
            Name = 'Color';
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18),
            Size = UDim2.fromOffset(230, Info.Transparency and 271 or 253);
            Visible = false;
            ZIndex = 15;
            Parent = ScreenGui,
        });

        DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            PickerFrameOuter.Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18);
        end)

        local PickerFrameInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 16;
            Parent = PickerFrameOuter;
        });

        local Highlight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 2);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.new(0, 4, 0, 25);
            Size = UDim2.new(0, 200, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Parent = SatVibMapOuter;
        });

        local SatVibMap = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Image = 'rbxassetid://4155801252';
            Parent = SatVibMapInner;
        });

        local CursorOuter = Library:Create('ImageLabel', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Size = UDim2.new(0, 6, 0, 6);
            BackgroundTransparency = 1;
            Image = 'http://www.roblox.com/asset/?id=9619665977';
            ImageColor3 = Color3.new(0, 0, 0);
            ZIndex = 19;
            Parent = SatVibMap;
        });

        local CursorInner = Library:Create('ImageLabel', {
            Size = UDim2.new(0, CursorOuter.Size.X.Offset - 2, 0, CursorOuter.Size.Y.Offset - 2);
            Position = UDim2.new(0, 1, 0, 1);
            BackgroundTransparency = 1;
            Image = 'http://www.roblox.com/asset/?id=9619665977';
            ZIndex = 20;
            Parent = CursorOuter;
        })

        local HueSelectorOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.new(0, 208, 0, 25);
            Size = UDim2.new(0, 15, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local HueSelectorInner = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Parent = HueSelectorOuter;
        });

        local HueCursor = Library:Create('Frame', { 
            BackgroundColor3 = Color3.new(1, 1, 1);
            AnchorPoint = Vector2.new(0, 0.5);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 18;
            Parent = HueSelectorInner;
        });

        local HueBoxOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(4, 228),
            Size = UDim2.new(0.5, -6, 0, 20),
            ZIndex = 18,
            Parent = PickerFrameInner;
        });

        local HueBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18,
            Parent = HueBoxOuter;
        });

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = HueBoxInner;
        });

        local HueBox = Library:Create('TextBox', {
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);
            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
            PlaceholderText = 'Hex color',
            Text = '#FFFFFF',
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 20,
            Parent = HueBoxInner;
        });

        Library:ApplyTextStroke(HueBox);

        local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
            Position = UDim2.new(0.5, 2, 0, 228),
            Size = UDim2.new(0.5, -6, 0, 20),
            Parent = PickerFrameInner
        });

        local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild('TextBox'), {
            Text = '255, 255, 255',
            PlaceholderText = 'RGB color',
            TextColor3 = Library.FontColor
        });

        local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor;
        
        if Info.Transparency then 
            TransparencyBoxOuter = Library:Create('Frame', {
                BorderColor3 = Color3.new(0, 0, 0);
                Position = UDim2.fromOffset(4, 251);
                Size = UDim2.new(1, -8, 0, 15);
                ZIndex = 19;
                Parent = PickerFrameInner;
            });

            TransparencyBoxInner = Library:Create('Frame', {
                BackgroundColor3 = ColorPicker.Value;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 19;
                Parent = TransparencyBoxOuter;
            });

            Library:AddToRegistry(TransparencyBoxInner, { BorderColor3 = 'OutlineColor' });

            Library:Create('ImageLabel', {
                BackgroundTransparency = 1;
                Size = UDim2.new(1, 0, 1, 0);
                Image = 'http://www.roblox.com/asset/?id=12978095818';
                ZIndex = 20;
                Parent = TransparencyBoxInner;
            });

            TransparencyCursor = Library:Create('Frame', { 
                BackgroundColor3 = Color3.new(1, 1, 1);
                AnchorPoint = Vector2.new(0.5, 0);
                BorderColor3 = Color3.new(0, 0, 0);
                Size = UDim2.new(0, 1, 1, 0);
                ZIndex = 21;
                Parent = TransparencyBoxInner;
            });
        end;

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 14);
            Position = UDim2.fromOffset(5, 5);
            TextXAlignment = Enum.TextXAlignment.Left;
            TextSize = 14;
            Text = ColorPicker.Title,--Info.Default;
            TextWrapped = false;
            ZIndex = 16;
            Parent = PickerFrameInner;
        });


        local ContextMenu = {}
        do
            ContextMenu.Options = {}
            ContextMenu.Container = Library:Create('Frame', {
                BorderColor3 = Color3.new(),
                ZIndex = 14,

                Visible = false,
                Parent = ScreenGui
            })

            ContextMenu.Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.fromScale(1, 1);
                ZIndex = 15;
                Parent = ContextMenu.Container;
            });

            Library:Create('UIListLayout', {
                Name = 'Layout',
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = ContextMenu.Inner;
            });

            Library:Create('UIPadding', {
                Name = 'Padding',
                PaddingLeft = UDim.new(0, 4),
                Parent = ContextMenu.Inner,
            });

            local function updateMenuPosition()
                ContextMenu.Container.Position = UDim2.fromOffset(
                    (DisplayFrame.AbsolutePosition.X + DisplayFrame.AbsoluteSize.X) + 4,
                    DisplayFrame.AbsolutePosition.Y + 1
                )
            end

            local function updateMenuSize()
                local menuWidth = 60
                for i, label in next, ContextMenu.Inner:GetChildren() do
                    if label:IsA('TextLabel') then
                        menuWidth = math.max(menuWidth, label.TextBounds.X)
                    end
                end

                ContextMenu.Container.Size = UDim2.fromOffset(
                    menuWidth + 8,
                    ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 4
                )
            end

            DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(updateMenuPosition)
            ContextMenu.Inner.Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(updateMenuSize)

            task.spawn(updateMenuPosition)
            task.spawn(updateMenuSize)

            Library:AddToRegistry(ContextMenu.Inner, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            function ContextMenu:Show()
                self.Container.Visible = true
            end

            function ContextMenu:Hide()
                self.Container.Visible = false
            end

            function ContextMenu:AddOption(Str, Callback)
                if type(Callback) ~= 'function' then
                    Callback = function() end
                end

                local Button = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, 0, 0, 15);
                    TextSize = 13;
                    Text = Str;
                    ZIndex = 16;
                    Parent = self.Inner;
                    TextXAlignment = Enum.TextXAlignment.Left,
                });

                Library:OnHighlight(Button, Button, 
                    { TextColor3 = 'AccentColor' },
                    { TextColor3 = 'FontColor' }
                );

                Button.InputBegan:Connect(function(Input)
                    if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                        return
                    end

                    Callback()
                end)
            end

            ContextMenu:AddOption('Copy color', function()
                Library.ColorClipboard = ColorPicker.Value
                Library:Notify('Copied color!', 2)
            end)

            ContextMenu:AddOption('Paste color', function()
                if not Library.ColorClipboard then
                    return Library:Notify('You have not copied a color!', 2)
                end
                ColorPicker:SetValueRGB(Library.ColorClipboard)
            end)


            ContextMenu:AddOption('Copy HEX', function()
                pcall(setclipboard, ColorPicker.Value:ToHex())
                Library:Notify('Copied hex code to clipboard!', 2)
            end)

            ContextMenu:AddOption('Copy RGB', function()
                pcall(setclipboard, table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', '))
                Library:Notify('Copied RGB values to clipboard!', 2)
            end)

        end

        Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(Highlight, { BackgroundColor3 = 'AccentColor'; });
        Library:AddToRegistry(SatVibMapInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });

        Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBox, { TextColor3 = 'FontColor', });
        Library:AddToRegistry(HueBox, { TextColor3 = 'FontColor', });

        local SequenceTable = {};

        for Hue = 0, 1, 0.1 do
            table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)));
        end;

        local HueSelectorGradient = Library:Create('UIGradient', {
            Color = ColorSequence.new(SequenceTable);
            Rotation = 90;
            Parent = HueSelectorInner;
        });

        HueBox.FocusLost:Connect(function(enter)
            if enter then
                local success, result = pcall(Color3.fromHex, HueBox.Text)
                if success and typeof(result) == 'Color3' then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
                end
            end

            ColorPicker:Display()
        end)

        RgbBox.FocusLost:Connect(function(enter)
            if enter then
                local r, g, b = RgbBox.Text:match('(%d+),%s*(%d+),%s*(%d+)')
                if r and g and b then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
                end
            end

            ColorPicker:Display()
        end)

        function ColorPicker:Display()
            ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib);
            SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1);

            Library:Create(DisplayFrame, {
                BackgroundColor3 = ColorPicker.Value;
                BackgroundTransparency = ColorPicker.Transparency;
                BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
            });

            if TransparencyBoxInner then
                TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value;
                TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0);
            end;

            CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0);
            HueCursor.Position = UDim2.new(0, 0, ColorPicker.Hue, 0);

            HueBox.Text = '#' .. ColorPicker.Value:ToHex()
            RgbBox.Text = table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', ')

            Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value);
            Library:SafeCallback(ColorPicker.Changed, ColorPicker.Value);
        end;

        function ColorPicker:OnChanged(Func)
            ColorPicker.Changed = Func;
            Func(ColorPicker.Value)
        end;

        function ColorPicker:Show()
            for Frame, Val in next, Library.OpenedFrames do
                if Frame.Name == 'Color' then
                    Frame.Visible = false;
                    Library.OpenedFrames[Frame] = nil;
                end;
            end;

            PickerFrameOuter.Visible = true;
            Library.OpenedFrames[PickerFrameOuter] = true;
        end;

        function ColorPicker:Hide()
            PickerFrameOuter.Visible = false;
            Library.OpenedFrames[PickerFrameOuter] = nil;
        end;

        function ColorPicker:SetValue(HSV, Transparency)
            local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3]);

            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        function ColorPicker:SetValueRGB(Color, Transparency)
            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        SatVibMap.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local MinX = SatVibMap.AbsolutePosition.X;
                    local MaxX = MinX + SatVibMap.AbsoluteSize.X;
                    local MouseX = math.clamp(Mouse.X, MinX, MaxX);

                    local MinY = SatVibMap.AbsolutePosition.Y;
                    local MaxY = MinY + SatVibMap.AbsoluteSize.Y;
                    local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

                    ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX);
                    ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY));
                    ColorPicker:Display();

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        HueSelectorInner.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local MinY = HueSelectorInner.AbsolutePosition.Y;
                    local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y;
                    local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

                    ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY));
                    ColorPicker:Display();

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        DisplayFrame.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if PickerFrameOuter.Visible then
                    ColorPicker:Hide()
                else
                    ContextMenu:Hide()
                    ColorPicker:Show()
                end;
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ContextMenu:Show()
                ColorPicker:Hide()
            end
        end);

        if TransparencyBoxInner then
            TransparencyBoxInner.InputBegan:Connect(function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                    while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                        local MinX = TransparencyBoxInner.AbsolutePosition.X;
                        local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X;
                        local MouseX = math.clamp(Mouse.X, MinX, MaxX);

                        ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX));

                        ColorPicker:Display();

                        RenderStepped:Wait();
                    end;

                    Library:AttemptSave();
                end;
            end);
        end;

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    ColorPicker:Hide();
                end;

                if not Library:IsMouseOverFrame(ContextMenu.Container) then
                    ContextMenu:Hide()
                end
            end;

            if Input.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
                if not Library:IsMouseOverFrame(ContextMenu.Container) and not Library:IsMouseOverFrame(DisplayFrame) then
                    ContextMenu:Hide()
                end
            end
        end))

        ColorPicker:Display();
        ColorPicker.DisplayFrame = DisplayFrame

        Options[Idx] = ColorPicker;

        return self;
    end;

    function Funcs:AddKeyPicker(Idx, Info)
        local ParentObj = self;
        local ToggleLabel = self.TextLabel;
        local Container = self.Container;

        assert(Info.Default, 'AddKeyPicker: Missing default value.');

        local KeyPicker = {
            Value = Info.Default;
            Toggled = false;
            Mode = Info.Mode or 'Toggle'; -- Always, Toggle, Hold
            Type = 'KeyPicker';
            Callback = Info.Callback or function(Value) end;
            ChangedCallback = Info.ChangedCallback or function(New) end;

            SyncToggleState = Info.SyncToggleState or false;
        };

        if KeyPicker.SyncToggleState then
            Info.Modes = { 'Toggle' }
            Info.Mode = 'Toggle'
        end

        local PickOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(0, 28, 0, 15);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        local PickInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 7;
            Parent = PickOuter;
        });

        Library:AddToRegistry(PickInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 13;
            Text = Info.Default;
            TextWrapped = true;
            ZIndex = 8;
            Parent = PickInner;
        });

        local ModeSelectOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
            Size = UDim2.new(0, 60, 0, 45 + 2);
            Visible = false;
            ZIndex = 14;
            Parent = ScreenGui;
        });

        ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            ModeSelectOuter.Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
        end);

        local ModeSelectInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 15;
            Parent = ModeSelectOuter;
        });

        Library:AddToRegistry(ModeSelectInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ModeSelectInner;
        });

        local ContainerLabel = Library:CreateLabel({
            TextXAlignment = Enum.TextXAlignment.Left;
            Size = UDim2.new(1, 0, 0, 18);
            TextSize = 13;
            Visible = false;
            ZIndex = 110;
            Parent = Library.KeybindContainer;
        },  true);

        local Modes = Info.Modes or { 'Always', 'Toggle', 'Hold' };
        local ModeButtons = {};

        for Idx, Mode in next, Modes do
            local ModeButton = {};

            local Label = Library:CreateLabel({
                Active = false;
                Size = UDim2.new(1, 0, 0, 15);
                TextSize = 13;
                Text = Mode;
                ZIndex = 16;
                Parent = ModeSelectInner;
            });

            function ModeButton:Select()
                for _, Button in next, ModeButtons do
                    Button:Deselect();
                end;

                KeyPicker.Mode = Mode;

                Label.TextColor3 = Library.AccentColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

                ModeSelectOuter.Visible = false;
            end;

            function ModeButton:Deselect()
                KeyPicker.Mode = nil;

                Label.TextColor3 = Library.FontColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
            end;

            Label.InputBegan:Connect(function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                    ModeButton:Select();
                    Library:AttemptSave();
                end;
            end);

            if Mode == KeyPicker.Mode then
                ModeButton:Select();
            end;

            ModeButtons[Mode] = ModeButton;
        end;

        function KeyPicker:Update()
            if Info.NoUI then
                return;
            end;

            local State = KeyPicker:GetState();

            ContainerLabel.Text = string.format('[%s] %s (%s)', KeyPicker.Value, Info.Text, KeyPicker.Mode);

            ContainerLabel.Visible = true;
            ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor;

            Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and 'AccentColor' or 'FontColor';

            local YSize = 0
            local XSize = 0

            for _, Label in next, Library.KeybindContainer:GetChildren() do
                if Label:IsA('TextLabel') and Label.Visible then
                    YSize = YSize + 18;
                    if (Label.TextBounds.X > XSize) then
                        XSize = Label.TextBounds.X
                    end
                end;
            end;

            Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 10, 210), 0, YSize + 23)
        end;

        function KeyPicker:GetState()
            if KeyPicker.Mode == 'Always' then
                return true;
            elseif KeyPicker.Mode == 'Hold' then
                if KeyPicker.Value == 'None' then
                    return false;
                end

                local Key = KeyPicker.Value;

                if Key == 'MB1' or Key == 'MB2' then
                    return Key == 'MB1' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                        or Key == 'MB2' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2);
                else
                    return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value]);
                end;
            else
                return KeyPicker.Toggled;
            end;
        end;

        function KeyPicker:SetValue(Data)
            local Key, Mode;
            if type(Data) == 'table' then
                Key, Mode = Data[1], Data[2];
            else
                Key = tostring(Data);
            end;
            Key = Key or 'None';
            DisplayLabel.Text = Key;
            KeyPicker.Value = Key;
            if Mode and ModeButtons[Mode] then
                ModeButtons[Mode]:Select();
            end;
            KeyPicker:Update();
        end;

        function KeyPicker:OnClick(Callback)
            KeyPicker.Clicked = Callback
        end

        function KeyPicker:OnChanged(Callback)
            KeyPicker.Changed = Callback
            Callback(KeyPicker.Value)
        end

        if ParentObj.Addons then
            table.insert(ParentObj.Addons, KeyPicker)
        end

        function KeyPicker:DoClick()
            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                ParentObj:SetValue(not ParentObj.Value)
            end

            Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
            Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
        end

        local Picking = false;

        PickOuter.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                Picking = true;
                Library.IsPickingKey = true;

                DisplayLabel.Text = '';

                local Break;
                local Text = '';

                task.spawn(function()
                    while (not Break) do
                        if Text == '...' then
                            Text = '';
                        end;

                        Text = Text .. '.';
                        DisplayLabel.Text = Text;

                        wait(0.4);
                    end;
                end);

                wait(0.2);

                local Event;
                Event = InputService.InputBegan:Connect(function(Input)
                    local Key;

                    if Input.UserInputType == Enum.UserInputType.Keyboard then
                        if Input.KeyCode == Enum.KeyCode.Backspace then
                            Key = 'None';
                        else
                            Key = Input.KeyCode.Name;
                        end;
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        Key = 'MB1';
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
                        Key = 'MB2';
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton3 then
                        Key = 'MB3';
                    end;

                    Break = true;
                    Picking = false;
                    Library.IsPickingKey = false;

                    DisplayLabel.Text = Key or 'None';
                    KeyPicker.Value = Key or 'None';

                    Library:SafeCallback(KeyPicker.ChangedCallback, Key or 'None')
                    Library:SafeCallback(KeyPicker.Changed, Key or 'None')

                    Library:AttemptSave();

                    Event:Disconnect();
                end);
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ModeSelectOuter.Visible = true;
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if (not Picking) and (not Library.IsPickingKey) then
                local Key = KeyPicker.Value;
                if Key and Key ~= 'None' then
                    if KeyPicker.Mode == 'Toggle' then
                        if Key == 'MB1' or Key == 'MB2' or Key == 'MB3' then
                            if (Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1)
                            or (Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2)
                            or (Key == 'MB3' and Input.UserInputType == Enum.UserInputType.MouseButton3) then
                                KeyPicker.Toggled = not KeyPicker.Toggled;
                                KeyPicker:DoClick();
                            end;
                        elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                            if Input.KeyCode.Name == Key then
                                KeyPicker.Toggled = not KeyPicker.Toggled;
                                KeyPicker:DoClick();
                            end;
                        end;
                    elseif KeyPicker.Mode == 'Hold' then
                        if Key == 'MB1' or Key == 'MB2' or Key == 'MB3' then
                            if (Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1)
                            or (Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2)
                            or (Key == 'MB3' and Input.UserInputType == Enum.UserInputType.MouseButton3) then
                                KeyPicker.Toggled = true;
                                if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                                    ParentObj:SetValue(true);
                                end;
                                Library:SafeCallback(KeyPicker.Callback, true);
                                Library:SafeCallback(KeyPicker.Clicked, true);
                            end;
                        elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                            if Input.KeyCode.Name == Key then
                                KeyPicker.Toggled = true;
                                if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                                    ParentObj:SetValue(true);
                                end;
                                Library:SafeCallback(KeyPicker.Callback, true);
                                Library:SafeCallback(KeyPicker.Clicked, true);
                            end;
                        end;
                    end;
                end;

                KeyPicker:Update();
            end;

            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    ModeSelectOuter.Visible = false;
                end;
            end;
        end))

        Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
            if (not Picking) and (not Library.IsPickingKey) then
                local Key = KeyPicker.Value;
                if Key and Key ~= 'None' and KeyPicker.Mode == 'Hold' then
                    if Key == 'MB1' or Key == 'MB2' or Key == 'MB3' then
                        if (Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1)
                        or (Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2)
                        or (Key == 'MB3' and Input.UserInputType == Enum.UserInputType.MouseButton3) then
                            KeyPicker.Toggled = false;
                            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                                ParentObj:SetValue(false);
                            end;
                            Library:SafeCallback(KeyPicker.Callback, false);
                            Library:SafeCallback(KeyPicker.Clicked, false);
                        end;
                    elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                        if Input.KeyCode.Name == Key then
                            KeyPicker.Toggled = false;
                            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                                ParentObj:SetValue(false);
                            end;
                            Library:SafeCallback(KeyPicker.Callback, false);
                            Library:SafeCallback(KeyPicker.Clicked, false);
                        end;
                    end;
                end;

                KeyPicker:Update();
            end;
        end))

        KeyPicker:Update();

        Options[Idx] = KeyPicker;

        return self;
    end;

    BaseAddons.__index = Funcs;
    BaseAddons.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

local BaseGroupbox = {};

do
    local Funcs = {};

    function Funcs:AddBlank(Size)
        local Groupbox = self;
        local Container = Groupbox.Container;

        Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, Size);
            ZIndex = 1;
            Parent = Container;
        });
    end;

    function Funcs:AddLabel(Text, DoesWrap)
        local Label = {};

        local Groupbox = self;
        local Container = Groupbox.Container;

        local TextLabel = Library:CreateLabel({
            Size = UDim2.new(1, -4, 0, 15);
            TextSize = 14;
            Text = Text;
            TextWrapped = DoesWrap or false,
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        if DoesWrap then
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
            TextLabel.Size = UDim2.new(1, -4, 0, Y)
        else
            Library:Create('UIListLayout', {
                Padding = UDim.new(0, 4);
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Right;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TextLabel;
            });
        end

        Label.TextLabel = TextLabel;
        Label.Container = Container;

        function Label:SetText(Text)
            TextLabel.Text = Text

            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
                TextLabel.Size = UDim2.new(1, -4, 0, Y)
            end

            Groupbox:Resize();
        end

        if (not DoesWrap) then
            setmetatable(Label, BaseAddons);
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Label;
    end;

    function Funcs:AddButton(...)
        -- TODO: Eventually redo this
        local Button = {};
        local function ProcessButtonParams(Class, Obj, ...)
            local Props = select(1, ...)
            if type(Props) == 'table' then
                Obj.Text = Props.Text
                Obj.Func = Props.Func
                Obj.DoubleClick = Props.DoubleClick
                Obj.Tooltip = Props.Tooltip
            else
                Obj.Text = select(1, ...)
                Obj.Func = select(2, ...)
            end

            assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
        end

        ProcessButtonParams('Button', Button, ...)

        local Groupbox = self;
        local Container = Groupbox.Container;

        local function CreateBaseButton(Button)
            local Outer = Library:Create('Frame', {
                BackgroundColor3 = Color3.new(0, 0, 0);
                BorderColor3 = Color3.new(0, 0, 0);
                Size = UDim2.new(1, -4, 0, 20);
                ZIndex = 5;
            });

            local Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 6;
                Parent = Outer;
            });

            local Label = Library:CreateLabel({
                Size = UDim2.new(1, 0, 1, 0);
                TextSize = 14;
                Text = Button.Text;
                ZIndex = 6;
                Parent = Inner;
            });

            Library:Create('UIGradient', {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
                });
                Rotation = 90;
                Parent = Inner;
            });

            Library:AddToRegistry(Outer, {
                BorderColor3 = 'Black';
            });

            Library:AddToRegistry(Inner, {
                BackgroundColor3 = 'MainColor';
                BorderColor3 = 'OutlineColor';
            });

            Library:OnHighlight(Outer, Outer,
                { BorderColor3 = 'AccentColor' },
                { BorderColor3 = 'Black' }
            );

            return Outer, Inner, Label
        end

        local function InitEvents(Button)
            local function WaitForEvent(event, timeout, validator)
                local bindable = Instance.new('BindableEvent')
                local connection = event:Once(function(...)

                    if type(validator) == 'function' and validator(...) then
                        bindable:Fire(true)
                    else
                        bindable:Fire(false)
                    end
                end)
                task.delay(timeout, function()
                    connection:disconnect()
                    bindable:Fire(false)
                end)
                return bindable.Event:Wait()
            end

            local function ValidateClick(Input)
                if Library:MouseIsOverOpenedFrame() then
                    return false
                end

                if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                    return false
                end

                return true
            end

            Button.Outer.InputBegan:Connect(function(Input)
                if not ValidateClick(Input) then return end
                if Button.Locked then return end

                if Button.DoubleClick then
                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'AccentColor' })

                    Button.Label.TextColor3 = Library.AccentColor
                    Button.Label.Text = 'Are you sure?'
                    Button.Locked = true

                    local clicked = WaitForEvent(Button.Outer.InputBegan, 0.5, ValidateClick)

                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'FontColor' })

                    Button.Label.TextColor3 = Library.FontColor
                    Button.Label.Text = Button.Text
                    task.defer(rawset, Button, 'Locked', false)

                    if clicked then
                        Library:SafeCallback(Button.Func)
                    end

                    return
                end

                Library:SafeCallback(Button.Func);
            end)
        end

        Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
        Button.Outer.Parent = Container

        InitEvents(Button)

        function Button:AddTooltip(tooltip)
            if type(tooltip) == 'string' then
                Library:AddToolTip(tooltip, self.Outer)
            end
            return self
        end


        function Button:AddButton(...)
            local SubButton = {}

            ProcessButtonParams('SubButton', SubButton, ...)

            self.Outer.Size = UDim2.new(0.5, -2, 0, 20)

            SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

            SubButton.Outer.Position = UDim2.new(1, 3, 0, 0)
            SubButton.Outer.Size = UDim2.fromOffset(self.Outer.AbsoluteSize.X - 2, self.Outer.AbsoluteSize.Y)
            SubButton.Outer.Parent = self.Outer

            function SubButton:AddTooltip(tooltip)
                if type(tooltip) == 'string' then
                    Library:AddToolTip(tooltip, self.Outer)
                end
                return SubButton
            end

            if type(SubButton.Tooltip) == 'string' then
                SubButton:AddTooltip(SubButton.Tooltip)
            end

            InitEvents(SubButton)
            return SubButton
        end

        if type(Button.Tooltip) == 'string' then
            Button:AddTooltip(Button.Tooltip)
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Button;
    end;

    function Funcs:AddDivider()
        local Groupbox = self;
        local Container = self.Container

        local Divider = {
            Type = 'Divider',
        }

        Groupbox:AddBlank(2);
        local DividerOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 5);
            ZIndex = 5;
            Parent = Container;
        });

        local DividerInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DividerOuter;
        });

        Library:AddToRegistry(DividerOuter, {
            BorderColor3 = 'Black';
        });

        Library:AddToRegistry(DividerInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Groupbox:AddBlank(9);
        Groupbox:Resize();
    end

    function Funcs:AddInput(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Textbox = {
            Value = Info.Default or '';
            Numeric = Info.Numeric or false;
            Finished = Info.Finished or false;
            Type = 'Input';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local InputLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 15);
            TextSize = 14;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        Groupbox:AddBlank(1);

        local TextBoxOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        local TextBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = TextBoxOuter;
        });

        Library:AddToRegistry(TextBoxInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:OnHighlight(TextBoxOuter, TextBoxOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, TextBoxOuter)
        end

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = TextBoxInner;
        });

        local Container = Library:Create('Frame', {
            BackgroundTransparency = 1;
            ClipsDescendants = true;

            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);

            ZIndex = 7;
            Parent = TextBoxInner;
        })

        local Box = Library:Create('TextBox', {
            BackgroundTransparency = 1;

            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromScale(5, 1),

            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
            PlaceholderText = Info.Placeholder or '';

            Text = Info.Default or '';
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;

            ZIndex = 7;
            Parent = Container;
        });

        Library:ApplyTextStroke(Box);

        function Textbox:SetValue(Text)
            if Info.MaxLength and #Text > Info.MaxLength then
                Text = Text:sub(1, Info.MaxLength);
            end;

            if Textbox.Numeric then
                if (not tonumber(Text)) and Text:len() > 0 then
                    Text = Textbox.Value
                end
            end

            Textbox.Value = Text;
            Box.Text = Text;

            Library:SafeCallback(Textbox.Callback, Textbox.Value);
            Library:SafeCallback(Textbox.Changed, Textbox.Value);
        end;

        if Textbox.Finished then
            Box.FocusLost:Connect(function(enter)
                if not enter then return end

                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end)
        else
            Box:GetPropertyChangedSignal('Text'):Connect(function()
                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end);
        end

        -- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
        -- thank you nicemike40 :)

        local function Update()
            local PADDING = 2
            local reveal = Container.AbsoluteSize.X

            if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
                -- we aren't focused, or we fit so be normal
                Box.Position = UDim2.new(0, PADDING, 0, 0)
            else
                -- we are focused and don't fit, so adjust position
                local cursor = Box.CursorPosition
                if cursor ~= -1 then
                    -- calculate pixel width of text from start to cursor
                    local subtext = string.sub(Box.Text, 1, cursor-1)
                    local width = TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

                    -- check if we're inside the box with the cursor
                    local currentCursorPos = Box.Position.X.Offset + width

                    -- adjust if necessary
                    if currentCursorPos < PADDING then
                        Box.Position = UDim2.fromOffset(PADDING-width, 0)
                    elseif currentCursorPos > reveal - PADDING - 1 then
                        Box.Position = UDim2.fromOffset(reveal-width-PADDING-1, 0)
                    end
                end
            end
        end

        task.spawn(Update)

        Box:GetPropertyChangedSignal('Text'):Connect(Update)
        Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update)
        Box.FocusLost:Connect(Update)
        Box.Focused:Connect(Update)

        Library:AddToRegistry(Box, {
            TextColor3 = 'FontColor';
        });

        function Textbox:OnChanged(Func)
            Textbox.Changed = Func;
            Func(Textbox.Value);
        end;

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        Options[Idx] = Textbox;

        return Textbox;
    end;

    function Funcs:AddToggle(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Toggle = {
            Value = Info.Default or false;
            Type = 'Toggle';

            Callback = Info.Callback or function(Value) end;
            Addons = {},
            Risky = Info.Risky,
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local ToggleOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(0, 13, 0, 13);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(ToggleOuter, {
            BorderColor3 = 'Black';
        });

        local ToggleInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        Library:AddToRegistry(ToggleInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local ToggleLabel = Library:CreateLabel({
            Size = UDim2.new(0, 216, 1, 0);
            Position = UDim2.new(1, 6, 0, 0);
            TextSize = 14;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 6;
            Parent = ToggleInner;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 4);
            FillDirection = Enum.FillDirection.Horizontal;
            HorizontalAlignment = Enum.HorizontalAlignment.Right;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ToggleLabel;
        });

        local ToggleRegion = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(0, 170, 1, 0);
            ZIndex = 8;
            Parent = ToggleOuter;
        });

        Library:OnHighlight(ToggleRegion, ToggleOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        function Toggle:UpdateColors()
            Toggle:Display();
        end;

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, ToggleRegion)
        end

        function Toggle:Display()
            ToggleInner.BackgroundColor3 = Toggle.Value and Library.AccentColor or Library.MainColor;
            ToggleInner.BorderColor3 = Toggle.Value and Library.AccentColorDark or Library.OutlineColor;

            Library.RegistryMap[ToggleInner].Properties.BackgroundColor3 = Toggle.Value and 'AccentColor' or 'MainColor';
            Library.RegistryMap[ToggleInner].Properties.BorderColor3 = Toggle.Value and 'AccentColorDark' or 'OutlineColor';
        end;

        function Toggle:OnChanged(Func)
            Toggle.Changed = Func;
            Func(Toggle.Value);
        end;

        function Toggle:SetValue(Bool)
            Bool = (not not Bool);

            Toggle.Value = Bool;
            Toggle:Display();

            for _, Addon in next, Toggle.Addons do
                if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then
                    Addon.Toggled = Bool
                    Addon:Update()
                end
            end

            Library:SafeCallback(Toggle.Callback, Toggle.Value);
            Library:SafeCallback(Toggle.Changed, Toggle.Value);
            Library:UpdateDependencyBoxes();
        end;

        ToggleRegion.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
                Library:AttemptSave();
            end;
        end);

        if Toggle.Risky then
            Library:RemoveFromRegistry(ToggleLabel)
            ToggleLabel.TextColor3 = Library.RiskColor
            Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' })
        end

        Toggle:Display();
        Groupbox:AddBlank(Info.BlankSize or 5 + 2);
        Groupbox:Resize();

        Toggle.TextLabel = ToggleLabel;
        Toggle.Container = Container;
        setmetatable(Toggle, BaseAddons);

        Toggles[Idx] = Toggle;

        Library:UpdateDependencyBoxes();

        return Toggle;
    end;

    function Funcs:AddSlider(Idx, Info)
        assert(Info.Default, 'AddSlider: Missing default value.');
        assert(Info.Text, 'AddSlider: Missing slider text.');
        assert(Info.Min, 'AddSlider: Missing minimum value.');
        assert(Info.Max, 'AddSlider: Missing maximum value.');
        assert(Info.Rounding, 'AddSlider: Missing rounding value.');

        local Slider = {
            Value = Info.Default;
            Min = Info.Min;
            Max = Info.Max;
            Rounding = Info.Rounding;
            Type = 'Slider';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        if not Info.Compact then
            Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 10);
                TextSize = 14;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        local SliderOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 13);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(SliderOuter, {
            BorderColor3 = 'Black';
        });

        local SliderInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ClipsDescendants = true;
            ZIndex = 6;
            Parent = SliderOuter;
        });

        Library:AddToRegistry(SliderInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Fill = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderColor3 = Library.AccentColorDark;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 0, 1, 0);
            ZIndex = 7;
            Parent = SliderInner;
        });

        Library:AddToRegistry(Fill, {
            BackgroundColor3 = 'AccentColor';
            BorderColor3 = 'AccentColorDark';
        });

        local HideBorderRight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.new(1, 0, 0, 0);
            Size = UDim2.new(0, 1, 1, 0);
            ZIndex = 8;
            Parent = Fill;
        });

        Library:AddToRegistry(HideBorderRight, {
            BackgroundColor3 = 'AccentColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 14;
            Text = 'Infinite';
            ZIndex = 9;
            Parent = SliderInner;
        });

        Library:OnHighlight(SliderOuter, SliderOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, SliderOuter)
        end

        function Slider:UpdateColors()
            Fill.BackgroundColor3 = Library.AccentColor;
            Fill.BorderColor3 = Library.AccentColorDark;
        end;

        function Slider:Display()
            local Suffix = Info.Suffix or '';

            if Info.Compact then
                DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix
            elseif Info.HideMax then
                DisplayLabel.Text = string.format('%s', Slider.Value .. Suffix)
            else
                DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix);
            end

            local fraction = (Slider.Max == Slider.Min) and 0 or math.clamp((Slider.Value - Slider.Min) / (Slider.Max - Slider.Min), 0, 1);
            Fill.Size = UDim2.new(fraction, 0, 1, 0);

            HideBorderRight.Visible = (fraction > 0 and fraction < 1);
        end;

        function Slider:OnChanged(Func)
            Slider.Changed = Func;
            Func(Slider.Value);
        end;

        local function Round(Value)
            if Slider.Rounding == 0 then
                return math.floor(Value + 0.5);
            end;

            return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
        end;

        function Slider:GetValueFromXOffset(X)
            local width = math.max(SliderInner.AbsoluteSize.X, 1);
            local fraction = math.clamp(X / width, 0, 1);
            return Round(Slider.Min + fraction * (Slider.Max - Slider.Min));
        end;

        function Slider:SetValue(Str)
            local Num = tonumber(Str);

            if (not Num) then
                return;
            end;

            Num = math.clamp(Num, Slider.Min, Slider.Max);

            Slider.Value = Num;
            Slider:Display();

            Library:SafeCallback(Slider.Callback, Slider.Value);
            Library:SafeCallback(Slider.Changed, Slider.Value);
        end;

        SliderInner.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local relX = Mouse.X - SliderInner.AbsolutePosition.X;
                    local nValue = Slider:GetValueFromXOffset(relX);
                    local OldValue = Slider.Value;
                    Slider.Value = nValue;

                    Slider:Display();

                    if nValue ~= OldValue then
                        Library:SafeCallback(Slider.Callback, Slider.Value);
                        Library:SafeCallback(Slider.Changed, Slider.Value);
                    end;

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        Slider:Display();
        Groupbox:AddBlank(Info.BlankSize or 6);
        Groupbox:Resize();

        Options[Idx] = Slider;

        return Slider;
    end;

    function Funcs:AddDropdown(Idx, Info)
        if Info.SpecialType == 'Player' then
            Info.Values = GetPlayersString();
            Info.AllowNull = true;
        elseif Info.SpecialType == 'Team' then
            Info.Values = GetTeamsString();
            Info.AllowNull = true;
        end;

        assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
        assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

        if (not Info.Text) then
            Info.Compact = true;
        end;

        local Dropdown = {
            Values = Info.Values;
            Value = Info.Multi and {};
            Multi = Info.Multi;
            Type = 'Dropdown';
            SpecialType = Info.SpecialType; -- can be either 'Player' or 'Team'
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local RelativeOffset = 0;

        if not Info.Compact then
            local DropdownLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 10);
                TextSize = 14;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        for _, Element in next, Container:GetChildren() do
            if not Element:IsA('UIListLayout') then
                RelativeOffset = RelativeOffset + Element.Size.Y.Offset;
            end;
        end;

        local DropdownOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(DropdownOuter, {
            BorderColor3 = 'Black';
        });

        local DropdownInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DropdownOuter;
        });

        Library:AddToRegistry(DropdownInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = DropdownInner;
        });

        local DropdownArrow = Library:Create('ImageLabel', {
            AnchorPoint = Vector2.new(0, 0.5);
            BackgroundTransparency = 1;
            Position = UDim2.new(1, -16, 0.5, 0);
            Size = UDim2.new(0, 12, 0, 12);
            Image = 'http://www.roblox.com/asset/?id=6282522798';
            ZIndex = 8;
            Parent = DropdownInner;
        });

        local ItemList = Library:CreateLabel({
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);
            TextSize = 14;
            Text = '--';
            TextXAlignment = Enum.TextXAlignment.Left;
            TextWrapped = true;
            ZIndex = 7;
            Parent = DropdownInner;
        });

        Library:OnHighlight(DropdownOuter, DropdownOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, DropdownOuter)
        end

        local MAX_DROPDOWN_ITEMS = 8;

        local ListOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            ZIndex = 20;
            Visible = false;
            Parent = ScreenGui;
        });

        local function RecalculateListPosition()
            ListOuter.Position = UDim2.fromOffset(DropdownOuter.AbsolutePosition.X, DropdownOuter.AbsolutePosition.Y + DropdownOuter.Size.Y.Offset + 1);
        end;

        local function RecalculateListSize(YSize)
            ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, YSize or (MAX_DROPDOWN_ITEMS * 20 + 2))
        end;

        RecalculateListPosition();
        RecalculateListSize();

        DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalculateListPosition);

        local ListInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListOuter;
        });

        Library:AddToRegistry(ListInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Scrolling = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            CanvasSize = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListInner;

            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',

            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Library.AccentColor,
        });

        Library:AddToRegistry(Scrolling, {
            ScrollBarImageColor3 = 'AccentColor'
        })

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 0);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Scrolling;
        });

        function Dropdown:Display()
            local Values = Dropdown.Values;
            local Str = '';

            if Info.Multi then
                for Idx, Value in next, Values do
                    if Dropdown.Value[Value] then
                        Str = Str .. Value .. ', ';
                    end;
                end;

                Str = Str:sub(1, #Str - 2);
            else
                Str = Dropdown.Value or '';
            end;

            ItemList.Text = (Str == '' and '--' or Str);
        end;

        function Dropdown:GetActiveValues()
            if Info.Multi then
                local T = {};

                for Value, Bool in next, Dropdown.Value do
                    table.insert(T, Value);
                end;

                return T;
            else
                return Dropdown.Value and 1 or 0;
            end;
        end;

        function Dropdown:BuildDropdownList()
            local Values = Dropdown.Values;
            local Buttons = {};

            for _, Element in next, Scrolling:GetChildren() do
                if not Element:IsA('UIListLayout') then
                    Element:Destroy();
                end;
            end;

            local Count = 0;

            for Idx, Value in next, Values do
                local Table = {};

                Count = Count + 1;

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Library.OutlineColor;
                    BorderMode = Enum.BorderMode.Middle;
                    Size = UDim2.new(1, -1, 0, 20);
                    ZIndex = 23;
                    Active = true,
                    Parent = Scrolling;
                });

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                    BorderColor3 = 'OutlineColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, -6, 1, 0);
                    Position = UDim2.new(0, 6, 0, 0);
                    TextSize = 14;
                    Text = Value;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    ZIndex = 25;
                    Parent = Button;
                });

                Library:OnHighlight(Button, Button,
                    { BorderColor3 = 'AccentColor', ZIndex = 24 },
                    { BorderColor3 = 'OutlineColor', ZIndex = 23 }
                );

                local Selected;

                if Info.Multi then
                    Selected = Dropdown.Value[Value];
                else
                    Selected = Dropdown.Value == Value;
                end;

                function Table:UpdateButton()
                    if Info.Multi then
                        Selected = Dropdown.Value[Value];
                    else
                        Selected = Dropdown.Value == Value;
                    end;

                    ButtonLabel.TextColor3 = Selected and Library.AccentColor or Library.FontColor;
                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
                end;

                ButtonLabel.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        local Try = not Selected;

                        if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
                        else
                            if Info.Multi then
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value[Value] = true;
                                else
                                    Dropdown.Value[Value] = nil;
                                end;
                            else
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value = Value;
                                else
                                    Dropdown.Value = nil;
                                end;

                                for _, OtherButton in next, Buttons do
                                    OtherButton:UpdateButton();
                                end;
                            end;

                            Table:UpdateButton();
                            Dropdown:Display();

                            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
                            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);

                            Library:AttemptSave();
                        end;
                    end;
                end);

                Table:UpdateButton();
                Dropdown:Display();

                Buttons[Button] = Table;
            end;

            Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * 20) + 1);

            local Y = math.clamp(Count * 20, 0, MAX_DROPDOWN_ITEMS * 20) + 1;
            RecalculateListSize(Y);
        end;

        function Dropdown:SetValues(NewValues)
            if NewValues then
                Dropdown.Values = NewValues;
            end;

            Dropdown:BuildDropdownList();
        end;

        function Dropdown:OpenDropdown()
            ListOuter.Visible = true;
            Library.OpenedFrames[ListOuter] = true;
            DropdownArrow.Rotation = 180;
        end;

        function Dropdown:CloseDropdown()
            ListOuter.Visible = false;
            Library.OpenedFrames[ListOuter] = nil;
            DropdownArrow.Rotation = 0;
        end;

        function Dropdown:OnChanged(Func)
            Dropdown.Changed = Func;
            Func(Dropdown.Value);
        end;

        function Dropdown:SetValue(Val)
            if Dropdown.Multi then
                local nTable = {};

                for Value, Bool in next, Val do
                    if table.find(Dropdown.Values, Value) then
                        nTable[Value] = true
                    end;
                end;

                Dropdown.Value = nTable;
            else
                if (not Val) then
                    Dropdown.Value = nil;
                elseif table.find(Dropdown.Values, Val) then
                    Dropdown.Value = Val;
                end;
            end;

            Dropdown:BuildDropdownList();

            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);
        end;

        DropdownOuter.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if ListOuter.Visible then
                    Dropdown:CloseDropdown();
                else
                    Dropdown:OpenDropdown();
                end;
            end;
        end);

        InputService.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    Dropdown:CloseDropdown();
                end;
            end;
        end);

        Dropdown:BuildDropdownList();
        Dropdown:Display();

        local Defaults = {}

        if type(Info.Default) == 'string' then
            local Idx = table.find(Dropdown.Values, Info.Default)
            if Idx then
                table.insert(Defaults, Idx)
            end
        elseif type(Info.Default) == 'table' then
            for _, Value in next, Info.Default do
                local Idx = table.find(Dropdown.Values, Value)
                if Idx then
                    table.insert(Defaults, Idx)
                end
            end
        elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
            table.insert(Defaults, Info.Default)
        end

        if next(Defaults) then
            for i = 1, #Defaults do
                local Index = Defaults[i]
                if Info.Multi then
                    Dropdown.Value[Dropdown.Values[Index]] = true
                else
                    Dropdown.Value = Dropdown.Values[Index];
                end

                if (not Info.Multi) then break end
            end

            Dropdown:BuildDropdownList();
            Dropdown:Display();
        end

        Groupbox:AddBlank(Info.BlankSize or 5);
        Groupbox:Resize();

        Options[Idx] = Dropdown;

        return Dropdown;
    end;

    function Funcs:AddDependencyBox()
        local Depbox = {
            Dependencies = {};
        };
        
        local Groupbox = self;
        local Container = Groupbox.Container;

        local Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, 0);
            Visible = false;
            Parent = Container;
        });

        local Frame = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 1, 0);
            Visible = true;
            Parent = Holder;
        });

        local Layout = Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Frame;
        });

        function Depbox:Resize()
            Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y);
            Groupbox:Resize();
        end;

        Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            Depbox:Resize();
        end);

        Holder:GetPropertyChangedSignal('Visible'):Connect(function()
            Depbox:Resize();
        end);

        function Depbox:Update()
            for _, Dependency in next, Depbox.Dependencies do
                local Elem = Dependency[1];
                local Value = Dependency[2];

                if Elem.Type == 'Toggle' and Elem.Value ~= Value then
                    Holder.Visible = false;
                    Depbox:Resize();
                    return;
                end;
            end;

            Holder.Visible = true;
            Depbox:Resize();
        end;

        function Depbox:SetupDependencies(Dependencies)
            for _, Dependency in next, Dependencies do
                assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.');
                assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.');
                assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.');
            end;

            Depbox.Dependencies = Dependencies;
            Depbox:Update();
        end;

        Depbox.Container = Frame;

        setmetatable(Depbox, BaseGroupbox);

        table.insert(Library.DependencyBoxes, Depbox);

        return Depbox;
    end;

    BaseGroupbox.__index = Funcs;
    BaseGroupbox.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

-- < Create other UI elements >
do
    Library.NotificationArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 0, 0, 40);
        Size = UDim2.new(0, 300, 0, 200);
        ZIndex = 100;
        Parent = ScreenGui;
    });

    Library:Create('UIListLayout', {
        Padding = UDim.new(0, 4);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = Library.NotificationArea;
    });

    local WatermarkOuter = Library:Create('Frame', {
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 100, 0, -25);
        Size = UDim2.new(0, 213, 0, 20);
        ZIndex = 200;
        Visible = false;
        Parent = ScreenGui;
    });

    local WatermarkInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.AccentColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 201;
        Parent = WatermarkOuter;
    });

    Library:AddToRegistry(WatermarkInner, {
        BorderColor3 = 'AccentColor';
    });

    local InnerFrame = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(1, 1, 1);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 202;
        Parent = WatermarkInner;
    });

    local Gradient = Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
            ColorSequenceKeypoint.new(1, Library.MainColor),
        });
        Rotation = -90;
        Parent = InnerFrame;
    });

    Library:AddToRegistry(Gradient, {
        Color = function()
            return ColorSequence.new({
                ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
                ColorSequenceKeypoint.new(1, Library.MainColor),
            });
        end
    });

    local WatermarkLabel = Library:CreateLabel({
        Position = UDim2.new(0, 5, 0, 0);
        Size = UDim2.new(1, -4, 1, 0);
        TextSize = 14;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 203;
        Parent = InnerFrame;
    });

    Library.Watermark = WatermarkOuter;
    Library.WatermarkText = WatermarkLabel;
    Library:MakeDraggable(Library.Watermark);



    local KeybindOuter = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 10, 0.5, 0);
        Size = UDim2.new(0, 210, 0, 20);
        Visible = false;
        ZIndex = 100;
        Parent = ScreenGui;
    });

    local KeybindInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = KeybindOuter;
    });

    Library:AddToRegistry(KeybindInner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    }, true);

    local ColorFrame = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 102;
        Parent = KeybindInner;
    });

    Library:AddToRegistry(ColorFrame, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    local KeybindLabel = Library:CreateLabel({
        Size = UDim2.new(1, 0, 0, 20);
        Position = UDim2.fromOffset(5, 2),
        TextXAlignment = Enum.TextXAlignment.Left,

        Text = 'Keybinds';
        ZIndex = 104;
        Parent = KeybindInner;
    });

    local KeybindContainer = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Size = UDim2.new(1, 0, 1, -20);
        Position = UDim2.new(0, 0, 0, 20);
        ZIndex = 1;
        Parent = KeybindInner;
    });

    Library:Create('UIListLayout', {
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = KeybindContainer;
    });

    Library:Create('UIPadding', {
        PaddingLeft = UDim.new(0, 5),
        Parent = KeybindContainer,
    })

    Library.KeybindFrame = KeybindOuter;
    Library.KeybindContainer = KeybindContainer;
    Library:MakeDraggable(KeybindOuter);
end;

function Library:SetWatermarkVisibility(Bool)
    Library.Watermark.Visible = Bool;
end;

function Library:SetWatermark(Text)
    local X, Y = Library:GetTextBounds(Text, Library.Font, 14);
    Library.Watermark.Size = UDim2.new(0, X + 15, 0, (Y * 1.5) + 3);
    Library:SetWatermarkVisibility(true)

    Library.WatermarkText.Text = Text;
end;

function Library:Notify(Text, Time)
    local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14);

    YSize = YSize + 7

    local NotifyOuter = Library:Create('Frame', {
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 100, 0, 10);
        Size = UDim2.new(0, 0, 0, YSize);
        ClipsDescendants = true;
        ZIndex = 100;
        Parent = Library.NotificationArea;
    });

    local NotifyInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(NotifyInner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    }, true);

    local InnerFrame = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(1, 1, 1);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 102;
        Parent = NotifyInner;
    });

    local Gradient = Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
            ColorSequenceKeypoint.new(1, Library.MainColor),
        });
        Rotation = -90;
        Parent = InnerFrame;
    });

    Library:AddToRegistry(Gradient, {
        Color = function()
            return ColorSequence.new({
                ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
                ColorSequenceKeypoint.new(1, Library.MainColor),
            });
        end
    });

    local NotifyLabel = Library:CreateLabel({
        Position = UDim2.new(0, 4, 0, 0);
        Size = UDim2.new(1, -4, 1, 0);
        Text = Text;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextSize = 14;
        ZIndex = 103;
        Parent = InnerFrame;
    });

    local LeftColor = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, -1, 0, -1);
        Size = UDim2.new(0, 3, 1, 2);
        ZIndex = 104;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(LeftColor, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, XSize + 8 + 4, 0, YSize), 'Out', 'Quad', 0.4, true);

    task.spawn(function()
        wait(Time or 5);

        pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, 0, 0, YSize), 'Out', 'Quad', 0.4, true);

        wait(0.4);

        NotifyOuter:Destroy();
    end);
end;

function Library:CreateWindow(...)
    local Arguments = { ... }
    local Config = { AnchorPoint = Vector2.zero }

    if type(...) == 'table' then
        Config = ...;
    else
        Config.Title = Arguments[1]
        Config.AutoShow = Arguments[2] or false;
    end

    if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
    if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 0 end
    if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.2 end

    if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end
    if typeof(Config.Size) ~= 'UDim2' then Config.Size = UDim2.fromOffset(440, 210) end

    if Config.Center then
        Config.AnchorPoint = Vector2.new(0.5, 0.5)
        Config.Position = UDim2.fromScale(0.5, 0.5)
    end

    local Window = {
        Tabs = {};
    };

    local Outer = Library:Create('Frame', {
        AnchorPoint = Config.AnchorPoint,
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = Config.Position,
        Size = Config.Size,
        Visible = false;
        ZIndex = 1;
        Parent = ScreenGui;
    });

    local Inner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.AccentColor;
        BorderMode = Enum.BorderMode.Inset;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 1;
        Parent = Outer;
    });

    Library:AddToRegistry(Inner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'AccentColor';
    });

    local WindowLabel = Library:CreateLabel({
        Position = UDim2.new(0, 7, 0, 0);
        Size = UDim2.new(0, 0, 0, 25);
        Text = Config.Title or '';
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 1;
        Parent = Inner;
    });


    local MainSectionOuter = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, 8, 0, 25);
        Size = UDim2.new(1, -16, 1, -33);
        ZIndex = 1;
        Parent = Inner;
    });

    Library:AddToRegistry(MainSectionOuter, {
        BackgroundColor3 = 'BackgroundColor';
        BorderColor3 = 'OutlineColor';
    });

    local MainSectionInner = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Color3.new(0, 0, 0);
        BorderMode = Enum.BorderMode.Inset;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 1;
        Parent = MainSectionOuter;
    });

    Library:AddToRegistry(MainSectionInner, {
        BackgroundColor3 = 'BackgroundColor';
    });

    local TabArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 8, 0, 8);
        Size = UDim2.new(1, -16, 0, 21);
        ZIndex = 1;
        Parent = MainSectionInner;
    });

    local TabListLayout = Library:Create('UIListLayout', {
        Padding = UDim.new(0, Config.TabPadding);
        FillDirection = Enum.FillDirection.Horizontal;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = TabArea;
    });

    local function getDynamicMinWidth()
        local contentW = TabListLayout.AbsoluteContentSize.X;
        if contentW and contentW > 0 then
            return math.max(contentW + 36, Config.MinWidth or 440);
        end
        return Config.MinWidth or 440;
    end

    Library:MakeDraggable(Outer, 25);
    Library:MakeResizable(Outer, getDynamicMinWidth, Config.MinHeight or 210, Config.MaxWidth or 1200, Config.MaxHeight or 900, Config.ResizeCallback);

    Window.Outer = Outer;

    local TabContainer = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, 8, 0, 30);
        Size = UDim2.new(1, -16, 1, -38);
        ZIndex = 2;
        Parent = MainSectionInner;
    });
    

    Library:AddToRegistry(TabContainer, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    function Window:SetWindowTitle(Title)
        WindowLabel.Text = Title;
    end;

    function Window:AddTab(Name)
        local Tab = {
            Groupboxes = {};
            Tabboxes = {};
        };

        local TabButtonWidth = Library:GetTextBounds(Name, Library.Font, 16);

        local TabButton = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            Size = UDim2.new(0, TabButtonWidth + 8 + 4, 1, 0);
            ZIndex = 1;
            Parent = TabArea;
        });

        Library:AddToRegistry(TabButton, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        local TabButtonLabel = Library:CreateLabel({
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, -1);
            Text = Name;
            ZIndex = 1;
            Parent = TabButton;
        });

        local Blocker = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 0, 1, 0);
            Size = UDim2.new(1, 0, 0, 1);
            BackgroundTransparency = 1;
            ZIndex = 3;
            Parent = TabButton;
        });

        Library:AddToRegistry(Blocker, {
            BackgroundColor3 = 'MainColor';
        });

        local TabFrame = Library:Create('Frame', {
            Name = 'TabFrame',
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Visible = false;
            ZIndex = 2;
            Parent = TabContainer;
        });

        local LeftSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 6, 0, 6);
            Size = UDim2.new(0.5, -9, 1, -12);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
            ScrollBarThickness = 2;
            ScrollBarImageColor3 = Library.AccentColor;
            ZIndex = 2;
            Parent = TabFrame;
        });

        local RightSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0.5, 3, 0, 6);
            Size = UDim2.new(0.5, -9, 1, -12);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
            ScrollBarThickness = 2;
            ScrollBarImageColor3 = Library.AccentColor;
            ZIndex = 2;
            Parent = TabFrame;
        });

        Tab.TabFrame = TabFrame;
        Tab.LeftSide = LeftSide;
        Tab.RightSide = RightSide;

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 8);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = LeftSide;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 8);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = RightSide;
        });

        for _, Side in next, { LeftSide, RightSide } do
            Library:AddToRegistry(Side, {
                ScrollBarImageColor3 = 'AccentColor'
            });
            Side:WaitForChild('UIListLayout'):GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
                Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y);
            end);
        end;

        function Tab:ShowTab()
            for _, Tab in next, Window.Tabs do
                Tab:HideTab();
            end;

            Blocker.BackgroundTransparency = 0;
            TabButton.BackgroundColor3 = Library.MainColor;
            Library.RegistryMap[TabButton].Properties.BackgroundColor3 = 'MainColor';
            TabFrame.Visible = true;
        end;

        function Tab:HideTab()
            Blocker.BackgroundTransparency = 1;
            TabButton.BackgroundColor3 = Library.BackgroundColor;
            Library.RegistryMap[TabButton].Properties.BackgroundColor3 = 'BackgroundColor';
            TabFrame.Visible = false;
        end;

        function Tab:SetLayoutOrder(Position)
            TabButton.LayoutOrder = Position;
            TabListLayout:ApplyLayout();
        end;

        function Tab:AddGroupbox(Info)
            local Groupbox = {};

            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 0, 507 + 2);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            Library:AddToRegistry(BoxOuter, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Color3.new(0, 0, 0);
                -- BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'BackgroundColor';
            });

            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 2);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'AccentColor';
            });

            local GroupboxLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 18);
                Position = UDim2.new(0, 4, 0, 2);
                TextSize = 14;
                Text = Info.Name;
                TextXAlignment = Enum.TextXAlignment.Left;
                ZIndex = 5;
                Parent = BoxInner;
            });

            local Container = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 4, 0, 20);
                Size = UDim2.new(1, -4, 1, -20);
                ZIndex = 1;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = Container;
            });

            function Groupbox:Resize()
                local Size = 0;

                for _, Element in next, Groupbox.Container:GetChildren() do
                    if (not Element:IsA('UIListLayout')) and Element.Visible then
                        Size = Size + Element.Size.Y.Offset;
                    end;
                end;

                BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
            end;

            Groupbox.Container = Container;
            setmetatable(Groupbox, BaseGroupbox);

            Groupbox:AddBlank(3);
            Groupbox:Resize();

            Tab.Groupboxes[Info.Name] = Groupbox;

            return Groupbox;
        end;

        function Tab:AddLeftGroupbox(Name)
            return Tab:AddGroupbox({ Side = 1; Name = Name; });
        end;

        function Tab:AddRightGroupbox(Name)
            return Tab:AddGroupbox({ Side = 2; Name = Name; });
        end;

        function Tab:AddTabbox(Info)
            local Tabbox = {
                Tabs = {};
            };

            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 0, 0);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            Library:AddToRegistry(BoxOuter, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Color3.new(0, 0, 0);
                -- BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'BackgroundColor';
            });

            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 2);
                ZIndex = 10;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'AccentColor';
            });

            local TabboxButtons = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 0, 0, 1);
                Size = UDim2.new(1, 0, 0, 18);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Left;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TabboxButtons;
            });

            function Tabbox:AddTab(Name)
                local Tab = {};

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Color3.new(0, 0, 0);
                    Size = UDim2.new(0.5, 0, 1, 0);
                    ZIndex = 6;
                    Parent = TabboxButtons;
                });

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Size = UDim2.new(1, 0, 1, 0);
                    TextSize = 14;
                    Text = Name;
                    TextXAlignment = Enum.TextXAlignment.Center;
                    ZIndex = 7;
                    Parent = Button;
                });

                local Block = Library:Create('Frame', {
                    BackgroundColor3 = Library.BackgroundColor;
                    BorderSizePixel = 0;
                    Position = UDim2.new(0, 0, 1, 0);
                    Size = UDim2.new(1, 0, 0, 1);
                    Visible = false;
                    ZIndex = 9;
                    Parent = Button;
                });

                Library:AddToRegistry(Block, {
                    BackgroundColor3 = 'BackgroundColor';
                });

                local Container = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    Position = UDim2.new(0, 4, 0, 20);
                    Size = UDim2.new(1, -4, 1, -20);
                    ZIndex = 1;
                    Visible = false;
                    Parent = BoxInner;
                });

                Library:Create('UIListLayout', {
                    FillDirection = Enum.FillDirection.Vertical;
                    SortOrder = Enum.SortOrder.LayoutOrder;
                    Parent = Container;
                });

                function Tab:Show()
                    for _, Tab in next, Tabbox.Tabs do
                        Tab:Hide();
                    end;

                    Container.Visible = true;
                    Block.Visible = true;

                    Button.BackgroundColor3 = Library.BackgroundColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'BackgroundColor';

                    Tab:Resize();
                end;

                function Tab:Hide()
                    Container.Visible = false;
                    Block.Visible = false;

                    Button.BackgroundColor3 = Library.MainColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'MainColor';
                end;

                function Tab:Resize()
                    local TabCount = 0;

                    for _, Tab in next, Tabbox.Tabs do
                        TabCount = TabCount + 1;
                    end;

                    for _, Button in next, TabboxButtons:GetChildren() do
                        if not Button:IsA('UIListLayout') then
                            Button.Size = UDim2.new(1 / TabCount, 0, 1, 0);
                        end;
                    end;

                    if (not Container.Visible) then
                        return;
                    end;

                    local Size = 0;

                    for _, Element in next, Tab.Container:GetChildren() do
                        if (not Element:IsA('UIListLayout')) and Element.Visible then
                            Size = Size + Element.Size.Y.Offset;
                        end;
                    end;

                    BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
                end;

                Button.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                        Tab:Show();
                        Tab:Resize();
                    end;
                end);

                Tab.Container = Container;
                Tabbox.Tabs[Name] = Tab;

                setmetatable(Tab, BaseGroupbox);

                Tab:AddBlank(3);
                Tab:Resize();

                -- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
                if #TabboxButtons:GetChildren() == 2 then
                    Tab:Show();
                end;

                return Tab;
            end;

            Tab.Tabboxes[Info.Name or ''] = Tabbox;

            return Tabbox;
        end;

        function Tab:AddLeftTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 1; });
        end;

        function Tab:AddRightTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 2; });
        end;

        TabButton.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                Tab:ShowTab();
            end;
        end);

        -- This was the first tab added, so we show it by default.
        if #TabContainer:GetChildren() == 1 then
            Tab:ShowTab();
        end;

        Window.Tabs[Name] = Tab;
        return Tab;
    end;

    local ModalElement = Library:Create('TextButton', {
        BackgroundTransparency = 1;
        Size = UDim2.new(0, 0, 0, 0);
        Visible = true;
        Text = '';
        Modal = false;
        Parent = ScreenGui;
    });

    local TransparencyCache = {};
    local Toggled = false;
    local Fading = false;

    function Library:Toggle()
        if Fading then
            return;
        end;

        local FadeTime = Config.MenuFadeTime;
        Fading = true;
        Toggled = (not Toggled);
        Library.Toggled = Toggled;
        ModalElement.Modal = Toggled;

        if Toggled then
            pcall(function()
                ContextActionService:BindActionAtPriority(
                    "__linoriaMenuScrollSink",
                    function() return Enum.ContextActionResult.Sink end,
                    false,
                    Enum.ContextActionPriority.High.Value + 2000,
                    Enum.UserInputType.MouseWheel
                )
            end)

            -- A bit scuffed, but if we're going from not toggled -> toggled we want to show the frame immediately so that the fade is visible.
            Outer.Visible = true;

            task.spawn(function()
                -- TODO: add cursor fade?
                local State = InputService.MouseIconEnabled;

                local Cursor = Drawing.new('Triangle');
                Cursor.Thickness = 1;
                Cursor.Filled = true;
                Cursor.Visible = true;

                local CursorOutline = Drawing.new('Triangle');
                CursorOutline.Thickness = 1;
                CursorOutline.Filled = false;
                CursorOutline.Color = Color3.new(0, 0, 0);
                CursorOutline.Visible = true;

                while Toggled and ScreenGui.Parent do
                    InputService.MouseIconEnabled = false;

                    local mPos = InputService:GetMouseLocation();

                    Cursor.Color = Library.AccentColor;

                    Cursor.PointA = Vector2.new(mPos.X, mPos.Y);
                    Cursor.PointB = Vector2.new(mPos.X + 16, mPos.Y + 6);
                    Cursor.PointC = Vector2.new(mPos.X + 6, mPos.Y + 16);

                    CursorOutline.PointA = Cursor.PointA;
                    CursorOutline.PointB = Cursor.PointB;
                    CursorOutline.PointC = Cursor.PointC;

                    RenderStepped:Wait();
                end;

                InputService.MouseIconEnabled = State;

                Cursor:Remove();
                CursorOutline:Remove();
            end);
        else
            pcall(function()
                ContextActionService:UnbindAction("__linoriaMenuScrollSink")
            end)
        end;

        for _, Desc in next, Outer:GetDescendants() do
            local Properties = {};

            if Desc:IsA('ImageLabel') then
                table.insert(Properties, 'ImageTransparency');
                table.insert(Properties, 'BackgroundTransparency');
            elseif Desc:IsA('TextLabel') or Desc:IsA('TextBox') then
                table.insert(Properties, 'TextTransparency');
            elseif Desc:IsA('Frame') or Desc:IsA('ScrollingFrame') then
                table.insert(Properties, 'BackgroundTransparency');
            elseif Desc:IsA('UIStroke') then
                table.insert(Properties, 'Transparency');
            end;

            local Cache = TransparencyCache[Desc];

            if (not Cache) then
                Cache = {};
                TransparencyCache[Desc] = Cache;
            end;

            for _, Prop in next, Properties do
                if not Cache[Prop] then
                    Cache[Prop] = Desc[Prop];
                end;

                if Cache[Prop] == 1 then
                    continue;
                end;

                TweenService:Create(Desc, TweenInfo.new(FadeTime, Enum.EasingStyle.Linear), { [Prop] = Toggled and Cache[Prop] or 1 }):Play();
            end;
        end;

        task.wait(FadeTime);

        Outer.Visible = Toggled;

        Fading = false;
    end

    Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
        if InputService:GetFocusedTextBox() then return end
        if Library.IsPickingKey then return end

        local mainConfig = _G.__bloxstrikeConfig
        local isMainActive = (_G.__bloxstrikeJanitor ~= nil)

        -- Script killing / unload key check
        local unloadKey = nil
        if isMainActive and mainConfig and mainConfig.UNLOAD_KEY then
            unloadKey = mainConfig.UNLOAD_KEY
        elseif Config.UnloadKey then
            unloadKey = Config.UnloadKey
        end

        if unloadKey and Input.KeyCode == unloadKey then
            if Config.CloseCallback then
                task.spawn(Config.CloseCallback)
            else
                task.spawn(Library.Unload)
            end
            return
        end

        -- UI toggling key check
        local toggleKey = nil
        if isMainActive and mainConfig and mainConfig.TOGGLE_UI_KEY then
            toggleKey = mainConfig.TOGGLE_UI_KEY
        elseif Config.ToggleKey then
            toggleKey = Config.ToggleKey
        else
            toggleKey = Enum.KeyCode.Insert
        end

        local isCustomKey = (type(Library.ToggleKeybind) == 'table' and Library.ToggleKeybind.Type == 'KeyPicker' and Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Library.ToggleKeybind.Value and Library.ToggleKeybind.Value ~= 'None')
        local isTargetKey = (toggleKey and Input.KeyCode == toggleKey)
        local isAlwaysAvailable = (Input.KeyCode == Enum.KeyCode.RightShift or Input.KeyCode == Enum.KeyCode.RightControl)

        if isCustomKey or isTargetKey or isAlwaysAvailable then
            task.spawn(Library.Toggle)
        end
    end))

    if Config.AutoShow then task.spawn(Library.Toggle) end

    Window.Holder = Outer;

    return Window;
end;

local function OnPlayerChange()
    local PlayerList = GetPlayersString();

    for _, Value in next, Options do
        if Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
            Value:SetValues(PlayerList);
        end;
    end;
end;

Players.PlayerAdded:Connect(OnPlayerChange);
Players.PlayerRemoving:Connect(OnPlayerChange);

getgenv().Library = Library
return Library
end
__skin["UIManager"] = function()
-- Seeto.Solutionz / Bloxstrike Skinchanger / UIManager
local Database = nil
local KnifeCatalog = nil
local GunCatalog = nil

local function getDatabase()
    if Database then return Database end
    if type(readfile) == "function" then
        local paths = {
            "Seeto.Solutionz-Bloxstrike-Skinchanger/src/Database.lua",
            "Bloxstrike-Skinchanger/src/Database.lua",
            "src/Database.lua",
            "Database.lua"
        }
        for _, p in ipairs(paths) do
            local ok, content = pcall(readfile, p)
            if ok and content then
                local fn = loadstring(content)
                if fn then
                    Database = fn()
                    return Database
                end
            end
        end
    end
    local okHttp, content = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/euphonee/Seeto.Solutionz-Bloxstrike-Skinchanger/main/src/Database.lua?t=" .. tostring(os.time()))
    end)
    if okHttp and content then
        local fn = loadstring(content)
        if fn then
            Database = fn()
            return Database
        end
    end
    return nil
end

local function getKnifeCatalog()
    if KnifeCatalog then return KnifeCatalog end
    if type(readfile) == "function" then
        local paths = {
            "Seeto.Solutionz-Bloxstrike-Skinchanger/src/KnifeCatalog.lua",
            "Bloxstrike-Skinchanger/src/KnifeCatalog.lua",
            "src/KnifeCatalog.lua",
            "KnifeCatalog.lua"
        }
        for _, p in ipairs(paths) do
            local ok, content = pcall(readfile, p)
            if ok and content then
                local fn = loadstring(content)
                if fn then
                    KnifeCatalog = fn()
                    return KnifeCatalog
                end
            end
        end
    end
    local okHttp, content = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/euphonee/Seeto.Solutionz-Bloxstrike-Skinchanger/main/src/KnifeCatalog.lua?t=" .. tostring(os.time()))
    end)
    if okHttp and content then
        local fn = loadstring(content)
        if fn then
            KnifeCatalog = fn()
            return KnifeCatalog
        end
    end
    return nil
end

local function getGunCatalog()
    if GunCatalog then return GunCatalog end
    if type(readfile) == "function" then
        local paths = {
            "Seeto.Solutionz-Bloxstrike-Skinchanger/src/GunCatalog.lua",
            "Bloxstrike-Skinchanger/src/GunCatalog.lua",
            "src/GunCatalog.lua",
            "GunCatalog.lua"
        }
        for _, p in ipairs(paths) do
            local ok, content = pcall(readfile, p)
            if ok and content then
                local fn = loadstring(content)
                if fn then
                    GunCatalog = fn()
                    return GunCatalog
                end
            end
        end
    end
    local okHttp, content = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/euphonee/Seeto.Solutionz-Bloxstrike-Skinchanger/main/src/GunCatalog.lua?t=" .. tostring(os.time()))
    end)
    if okHttp and content then
        local fn = loadstring(content)
        if fn then
            GunCatalog = fn()
            return GunCatalog
        end
    end
    return nil
end

local UIManager = {
    Initialized = false,
    Library = nil,
    Window = nil,
    Tabs = {}
}

function UIManager.bindCatalog(kc, gc)
    KnifeCatalog = kc
    if gc then GunCatalog = gc end
end

function UIManager.bindCatalogs(kc, gc)
    KnifeCatalog = kc
    GunCatalog = gc
end

function UIManager.init(Config, Library, API, Db, unloadCallback)
    if type(API) == "function" and Db == nil then
        unloadCallback = API
        API = nil
        Db = nil
    elseif type(Db) == "function" and unloadCallback == nil then
        unloadCallback = Db
        Db = nil
    end

    Database = Db or Database or getDatabase()
    KnifeCatalog = KnifeCatalog or getKnifeCatalog()
    GunCatalog = GunCatalog or getGunCatalog()

    if UIManager.Initialized then return end
    UIManager.Initialized = true
    UIManager.Library = Library

    -- Apply theme if available
    if Config.UI_THEME then
        for prop, val in pairs(Config.UI_THEME) do
            if Library[prop] ~= nil then
                Library[prop] = val
            end
        end
    end

    -- Create Window (sized for catalog view)
    local defaultW = Config.WINDOW_SIZE_X or 620
    local defaultH = Config.WINDOW_SIZE_Y or 390
    if defaultW < 560 then defaultW = 620 end
    if defaultH < 340 then defaultH = 390 end

    local Window = Library:CreateWindow({
        Title = "Seeto.SolutionZ / Bloxstrike Skinchanger",
        Center = true,
        AutoShow = true,
        TabPadding = 6,
        MenuFadeTime = 0.2,
        Size = UDim2.fromOffset(defaultW, defaultH),
        MinWidth = 520,
        MinHeight = 320,
        ToggleKey = Config.TOGGLE_UI_KEY or Enum.KeyCode.Insert,
        UnloadKey = Config.UNLOAD_KEY or Enum.KeyCode.K,
        CloseCallback = unloadCallback,
        ResizeCallback = function(w, h)
            if Config.WINDOW_SIZE_X ~= w or Config.WINDOW_SIZE_Y ~= h then
                Config.WINDOW_SIZE_X = w
                Config.WINDOW_SIZE_Y = h
                if Config.queueSave then Config.queueSave() else Config.save() end
            end
        end
    })
    UIManager.Window = Window

    -- Add Tabs: Knife, Guns, Settings
    local Tabs = {
        Knife = Window:AddTab("Knife"),
        Guns = Window:AddTab("Guns"),
        Settings = Window:AddTab("Settings")
    }
    UIManager.Tabs = Tabs

    -- 1. Initialize Visual Knife Catalog in Knife Tab
    if KnifeCatalog and KnifeCatalog.init then
        KnifeCatalog.init(Tabs.Knife, Config, API, Library, Database)
    end

    -- 2. Initialize Visual Gun Catalog in Guns Tab
    if GunCatalog and GunCatalog.init then
        GunCatalog.init(Tabs.Guns, Config, API, Library, Database)
    end

    -- 3. Initialize Settings Tab with Reset Buttons
    local ResetGroup = Tabs.Settings:AddLeftGroupbox("Reset Skins")
    local MenuConfigGroup = Tabs.Settings:AddRightGroupbox("Menu & State")

    ResetGroup:AddButton({
        Text = "Reset knife skins to default",
        Func = function()
            if API and API.resetKnifeSkins then
                API.resetKnifeSkins()
            else
                Config.KNIFE_MODEL = "Default"
                Config.KNIFE_SKIN = "Stock"
                Config.KNIFE_SKINS = {}
                if Config.queueSave then Config.queueSave() else Config.save() end
                if API and API.refresh then API.refresh() end
            end
            if KnifeCatalog and KnifeCatalog.refresh then
                pcall(KnifeCatalog.refresh)
            end
            Library:Notify("Reset all knife skins to default", 2)
        end,
        DoubleClick = false,
        Tooltip = "Resets your knife model and all custom knife skins to stock appearance"
    })

    ResetGroup:AddButton({
        Text = "Reset weapon skins to default",
        Func = function()
            if API and API.resetWeaponSkins then
                API.resetWeaponSkins()
            else
                Config.SELECTED_SKINS = {}
                Config.SKIN_MODE = "Stock"
                if Config.queueSave then Config.queueSave() else Config.save() end
                if API and API.refresh then API.refresh() end
            end
            if GunCatalog and GunCatalog.refresh then
                pcall(GunCatalog.refresh)
            end
            Library:Notify("Reset all weapon skins to default", 2)
        end,
        DoubleClick = false,
        Tooltip = "Resets all gun and firearm skins to stock appearance"
    })

    MenuConfigGroup:AddLabel("Toggle UI: Insert / RightShift")
    MenuConfigGroup:AddButton({
        Text = "Unload Skinchanger",
        Func = function()
            if unloadCallback then
                unloadCallback()
            elseif Library and Library.Unload then
                Library:Unload()
            end
        end,
        DoubleClick = true,
        Tooltip = "Double-click to unload the skinchanger"
    })

    -- Focus first tab
    Tabs.Knife:ShowTab()
end

function UIManager.cleanup()
    if KnifeCatalog and KnifeCatalog.cleanup then
        pcall(KnifeCatalog.cleanup)
    end
    if GunCatalog and GunCatalog.cleanup then
        pcall(GunCatalog.cleanup)
    end
    if UIManager.Library and UIManager.Library.Unload then
        pcall(function() UIManager.Library:Unload() end)
    end
    UIManager.Initialized = false
    UIManager.Library = nil
    UIManager.Window = nil
    UIManager.Tabs = {}
end

return UIManager

end
__seetoSkinBundled = __skin
__runBloxstrikeSkin = function()
-- Seeto.Solutionz / Bloxstrike Skinchanger / Standalone Engine
-- Repository: https://github.com/euphonee/Seeto.Solutionz-Bloxstrike-Skinchanger

-- Cleanup previous instance
if _G.__seetoSkinChangerJanitor then
    pcall(_G.__seetoSkinChangerJanitor)
    _G.__seetoSkinChangerJanitor = nil
end

-- Module loader
local modules = {}
local function import(moduleName)
    if modules[moduleName] then return modules[moduleName] end
    if __seetoSkinBundled and __seetoSkinBundled[moduleName] then
        local res = __seetoSkinBundled[moduleName]()
        modules[moduleName] = res
        return res
    end

    if type(readfile) == "function" then
        local paths = {
            "Seeto.Solutionz-Bloxstrike-Skinchanger/src/" .. moduleName .. ".lua",
            "Bloxstrike-Skinchanger/src/" .. moduleName .. ".lua",
            "src/" .. moduleName .. ".lua",
            moduleName .. ".lua"
        }
        for _, path in ipairs(paths) do
            local ok, content = pcall(readfile, path)
            if ok and content then
                local fn = loadstring(content)
                if fn then
                    local res = fn()
                    modules[moduleName] = res
                    return res
                end
            end
        end
    end

    -- Remote GitHub fallback with cache-busting timestamp
    local okHttp, remoteContent = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/euphonee/Seeto.Solutionz-Bloxstrike-Skinchanger/main/src/" .. moduleName .. ".lua?t=" .. tostring(os.time()))
    end)
    if okHttp and remoteContent and #remoteContent > 0 then
        local fn = loadstring(remoteContent)
        if fn then
            local res = fn()
            modules[moduleName] = res
            return res
        end
    end

    error("[Bloxstrike Skinchanger] Failed to import module: " .. tostring(moduleName))
end

-- Imports
local Config       = import("Config")
local Database     = import("Database")
local Engine       = import("Engine")
local API          = import("API")
local KnifeCatalog = import("KnifeCatalog")
local GunCatalog   = import("GunCatalog")
local LinoriaLib   = import("LinoriaLib")
local UIManager    = import("UIManager")

-- Bind subsystems
API.bind(Config, Database, Engine, KnifeCatalog, GunCatalog)
UIManager.bindCatalogs(KnifeCatalog, GunCatalog)

-- Initialize Engine
API.init()

-- Cleanup routine
local function cleanup()
    UIManager.cleanup()
    API.cleanup()
    _G.SkinChanger = nil
    _G.__seetoSkinChangerJanitor = nil
end

-- Initialize UI with Knife catalog and gun controls
UIManager.init(Config, LinoriaLib, API, Database, cleanup)

-- Global exports
_G.SkinChanger = API
_G.__seetoSkinChangerJanitor = cleanup

print("Seeto.Solutionz / Bloxstrike Skinchanger / Initialized with Visual 3D Catalog")
return API

end
getgenv().__runBloxstrikeSkin = __runBloxstrikeSkin

-- Seeto.SolutionZ / Bloxstrike / v2.5

-- cleanup existing instances
if _G.__agScriptJanitor then pcall(_G.__agScriptJanitor) _G.__agScriptJanitor = nil end
if _G.__bloxstrikeJanitor then pcall(_G.__bloxstrikeJanitor) _G.__bloxstrikeJanitor = nil end
if _G.__shotAdvisorJanitor then pcall(_G.__shotAdvisorJanitor) _G.__shotAdvisorJanitor = nil end
if _G.__spectatorUIJanitor then pcall(_G.__spectatorUIJanitor) _G.__spectatorUIJanitor = nil end
if _G.__standaloneRCS then pcall(_G.__standaloneRCS) _G.__standaloneRCS = nil end
if _G.__passiveSuiteJanitor then pcall(_G.__passiveSuiteJanitor) _G.__passiveSuiteJanitor = nil end
if _G.__antiFlashJanitor then pcall(_G.__antiFlashJanitor) _G.__antiFlashJanitor = nil end
if _G.__bhopJanitor then pcall(_G.__bhopJanitor) _G.__bhopJanitor = nil end
if _G.__skinChangerJanitor then pcall(_G.__skinChangerJanitor) _G.__skinChangerJanitor = nil end

if _G.__originalPerformRaycast then
    local ok, b = pcall(function() return require(game:GetService("ReplicatedStorage").Components.Weapon.Classes.Bullet) end)
    if ok and b and _G.__originalPerformRaycast then
        b._performRaycast = _G.__originalPerformRaycast
    end
    _G.__originalPerformRaycast = nil
end

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = Workspace.CurrentCamera

-- module loader
local modules = {}
local function import(moduleName)
    if modules[moduleName] then return modules[moduleName] end
    if __bloxstrikeBundled and __bloxstrikeBundled[moduleName] then
        local res = __bloxstrikeBundled[moduleName]()
        modules[moduleName] = res
        return res
    end
    
    if type(readfile) == "function" then
        local paths = {
            "Bloxstrike/src/" .. moduleName .. ".lua",
            "src/" .. moduleName .. ".lua",
            moduleName .. ".lua"
        }
        for _, path in ipairs(paths) do
            local ok, content = pcall(readfile, path)
            if ok and content then
                local fn, loadErr = loadstring(content)
                if fn then
                    local res = fn()
                    modules[moduleName] = res
                    return res
                end
            end
        end
    end
    
    if _G.__BloxstrikeModules and _G.__BloxstrikeModules[moduleName] then
        local res = _G.__BloxstrikeModules[moduleName]()
        modules[moduleName] = res
        return res
    end
    
    -- remote github fallback
    local okHttp, remoteContent = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/euphonee/Seeto.SolutionZ-Bloxstrike/main/src/" .. moduleName .. ".lua")
    end)
    if okHttp and remoteContent and #remoteContent > 0 then
        local fn, loadErr = loadstring(remoteContent)
        if fn then
            local res = fn()
            modules[moduleName] = res
            return res
        end
    end

    error("[Bloxstrike] Failed to import module: " .. tostring(moduleName))
end

-- imports
local Config           = import("Config")
local Utils            = import("Utils")
local DamageEngine     = import("DamageEngine")
local SkeletonRenderer = import("SkeletonRenderer")
local TargetEngine     = import("TargetEngine")
local ESPManager       = import("ESPManager")
local SilentAim        = import("SilentAim")
local Wallbang         = import("Wallbang")
local SpectateChecker  = import("SpectateChecker")
local Bhop             = import("Bhop")
local AntiFlash        = import("AntiFlash")
local WeaponEngine     = import("WeaponEngine")
local LinoriaLib       = import("LinoriaLib")
local UIManager        = import("UIManager")

-- load config
Config.load()


getgenv().__bloxstrikeRefs = {
    Config = Config,
    Bhop = Bhop,
    UIManager = UIManager,
    Library = LinoriaLib,
}

-- setup primitives
ESPManager.init(Config, Utils, SkeletonRenderer)
SpectateChecker.init(Config)
TargetEngine.init(Config)

-- fov circle
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.5
fovCircle.NumSides = 64
fovCircle.Radius = 100
fovCircle.Filled = false
fovCircle.Transparency = Config.FOV_CIRCLE_TRANSPARENCY or 0.5
fovCircle.Color = Config.FOV_CIRCLE_COLOR or Color3.fromRGB(255, 255, 255)
fovCircle.ZIndex = 1
fovCircle.Visible = Config.FOV_CIRCLE_ENABLED

-- init subsystems
SilentAim.init(Config, Utils)
Wallbang.init(Config)
Bhop.init(Config)
AntiFlash.init(Config)
WeaponEngine.init(Config)

-- cleanup
local renderConn = nil
local keyConn = nil

local function cleanup()
    if renderConn then pcall(function() renderConn:Disconnect() end) end
    if keyConn then pcall(function() keyConn:Disconnect() end) end
    
    UIManager.cleanup()
    WeaponEngine.cleanup()
    Bhop.cleanup()
    AntiFlash.cleanup()
    SilentAim.cleanup()
    Wallbang.cleanup()
    TargetEngine.cleanup()
    ESPManager.cleanup(SkeletonRenderer)
    SpectateChecker.cleanup()
    
    pcall(function() fovCircle:Remove() end)
    
    _G.__bloxstrikeJanitor = nil
    _G.__bloxstrikeConfig = nil
end

_G.__bloxstrikeJanitor = cleanup
_G.__bloxstrikeConfig = Config

-- init ui
UIManager.init(Config, LinoriaLib, nil, WeaponEngine, cleanup)

-- auto-launch skinchanger if enabled
if Config.AUTO_LAUNCH_SKINCHANGER == true then
    task.spawn(function()
        if type(readfile) == "function" then
            local localPaths = {
                "Seeto.Solutionz-Bloxstrike-Skinchanger/init.lua",
                "Bloxstrike-Skinchanger/init.lua"
            }
            for _, path in ipairs(localPaths) do
                local okRead, content = pcall(readfile, path)
                if okRead and content and #content > 0 then
                    local fn = loadstring(content)
                    if fn then
                        local okExec = pcall(fn)
                        if okExec then return end
                    end
                end
            end
        end

        pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/euphonee/Seeto.Solutionz-Bloxstrike-Skinchanger/main/init.lua?t=" .. tostring(os.time())))()
        end)
    end)
end

-- render loop
renderConn = RunService.RenderStepped:Connect(function(dt)
    local vpCenter = Camera.ViewportSize * 0.5
    fovCircle.Position = Vector2.new(vpCenter.X, vpCenter.Y)

    -- angular fov projection
    local fovDeg = Config.FOV_DEG or 30
    if fovDeg >= 180 then
        fovCircle.Radius = math.max(Camera.ViewportSize.X, Camera.ViewportSize.Y) * 2
    else
        local camFov = math.clamp(Camera.FieldOfView, 1, 120)
        local focalLength = (Camera.ViewportSize.Y * 0.5) / math.tan(math.rad(camFov * 0.5))
        local radiusPx = focalLength * math.tan(math.rad(math.min(fovDeg, 89.5)))
        fovCircle.Radius = radiusPx
    end

    fovCircle.Color = Config.FOV_CIRCLE_COLOR
    fovCircle.Transparency = Config.FOV_CIRCLE_TRANSPARENCY
    fovCircle.Visible = (Config.FOV_CIRCLE_ENABLED ~= false) and (Config.ESP_ENABLED ~= false)

    TargetEngine.update(Config, Utils, DamageEngine)
    ESPManager.update(Config, Utils, SkeletonRenderer)
    SpectateChecker.update(Config)
end)

-- unload key listener
keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if UserInputService:GetFocusedTextBox() then return end
    if LinoriaLib and LinoriaLib.IsPickingKey then return end
    if Config.UNLOAD_KEY and input.KeyCode == Config.UNLOAD_KEY then
        cleanup()
    end
end)

print("Seeto.SolutionZ / Bloxstrike / v2.5")

-- ============================================================
-- [mobile] 手机浮层（位置在「手机」页里调）+ 皮肤修改器开关
-- ============================================================
do
    local UIS = game:GetService("UserInputService")
    local refs = getgenv().__bloxstrikeRefs or {}
    local Lib = getgenv().Library or refs.Library
    local ConfigRef = refs.Config
    local BhopRef = refs.Bhop
    local UIMan = refs.UIManager

    local DEF = {
        bs   = { x = -92, y = -78 },
        aim  = { x = -92, y = -26 },
        bhop = { x = -92, y = 26 },
    }
    local btns = {}

    local host = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    local old = host:FindFirstChild("BloxstrikeMobile")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BloxstrikeMobile"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent = host

    local function makeBtn(key, text, color)
        local b = Instance.new("TextButton")
        b.Name = "bs_" .. key
        b.Size = UDim2.fromOffset(64, 40)
        b.Position = UDim2.new(1, DEF[key].x, 0.5, DEF[key].y)
        b.BackgroundColor3 = color
        b.BackgroundTransparency = 0.15
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Text = text
        b.TextSize = 14
        b.Font = Enum.Font.GothamBold
        b.AutoButtonColor = true
        b.BorderSizePixel = 0
        b.ZIndex = 10
        b.Parent = gui
        local c = Instance.new("UICorner", b)
        c.CornerRadius = UDim.new(0, 10)
        btns[key] = b
        return b
    end

    local menuBtn = makeBtn("bs", "BS", Color3.fromRGB(245, 125, 25))
    local aimBtn  = makeBtn("aim", "AIM", Color3.fromRGB(60, 60, 70))
    local bhopBtn = makeBtn("bhop", "BHOP", Color3.fromRGB(60, 60, 70))

    menuBtn.MouseButton1Click:Connect(function()
        pcall(function() Lib:Toggle() end)
    end)

    local function bindHold(btn, onDown, onUp)
        btn.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                onDown()
                btn.BackgroundColor3 = Color3.fromRGB(245, 125, 25)
            end
        end)
        btn.InputEnded:Connect(function(i)
            onUp()
            btn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        end)
    end

    bindHold(bhopBtn, function()
        if BhopRef then BhopRef.IsHoldingSpace = true end
    end, function()
        if BhopRef then BhopRef.IsHoldingSpace = false end
    end)

    bindHold(aimBtn, function()
        if ConfigRef and ConfigRef._keysDown then ConfigRef._keysDown["MB1"] = true end
    end, function()
        if ConfigRef and ConfigRef._keysDown then ConfigRef._keysDown["MB1"] = false end
    end)

    local API = {}
    function API.setPos(key, x, y)
        local b = btns[key]
        if b then b.Position = UDim2.new(1, x, 0.5, y) end
    end
    function API.setVisible(v)
        gui.Enabled = (v ~= false)
    end
    function API.setScale(s)
        s = math.clamp(tonumber(s) or 1, 0.6, 1.6)
        for _, b in pairs(btns) do
            b.Size = UDim2.fromOffset(math.floor(64 * s), math.floor(40 * s))
            b.TextSize = math.floor(14 * s)
        end
    end
    function API.reset()
        for k, v in pairs(DEF) do API.setPos(k, v.x, v.y) end
    end
    getgenv().__bloxstrikeMobile = API

    -- ---------- 皮肤修改器 ----------
    local skinOn = false
    local function skinStart()
        local f = getgenv().__runBloxstrikeSkin
        if type(f) ~= "function" then
            if Lib and Lib.Notify then Lib:Notify("皮肤模块没加载", 3) end
            return false
        end
        local ok, err = pcall(f)
        skinOn = ok
        if Lib and Lib.Notify then
            Lib:Notify(ok and "皮肤修改器已开启" or ("皮肤修改器开启失败: " .. tostring(err)), 3)
        end
        return ok
    end
    local function skinStop()
        local j = _G.__seetoSkinChangerJanitor
        if type(j) == "function" then pcall(j) end
        _G.__seetoSkinChangerJanitor = nil
        _G.SkinChanger = nil
        skinOn = false
        if Lib and Lib.Notify then Lib:Notify("皮肤修改器已关闭", 3) end
    end

    -- ---------- 「手机」页 ----------
    local win = UIMan and UIMan.Window
    if win then
        pcall(function()
            local tab = win:AddTab("手机")

            local left = tab:AddLeftGroupbox("悬浮按钮")
            left:AddToggle("MobileDock", {
                Text = "显示悬浮按钮",
                Default = true,
                Callback = function(v) API.setVisible(v) end
            })
            left:AddSlider("MobileScale", {
                Text = "按钮大小",
                Default = 1,
                Min = 0.6,
                Max = 1.6,
                Rounding = 1,
                Callback = function(v) API.setScale(v) end
            })
            left:AddButton({
                Text = "重置按钮位置",
                Func = function()
                    API.reset()
                    local Opt = getgenv().Options or {}
                    if Opt.BtnBsX then Opt.BtnBsX:SetValue(DEF.bs.x) end
                    if Opt.BtnBsY then Opt.BtnBsY:SetValue(DEF.bs.y) end
                    if Opt.BtnAimX then Opt.BtnAimX:SetValue(DEF.aim.x) end
                    if Opt.BtnAimY then Opt.BtnAimY:SetValue(DEF.aim.y) end
                    if Opt.BtnBhopX then Opt.BtnBhopX:SetValue(DEF.bhop.x) end
                    if Opt.BtnBhopY then Opt.BtnBhopY:SetValue(DEF.bhop.y) end
                end
            })

            local pos = tab:AddRightGroupbox("按钮位置（右边距为负）")
            pos:AddSlider("BtnBsX", {Text="BS 横", Default=DEF.bs.x, Min=-800, Max=0, Rounding=0,
                Callback=function(v) API.setPos("bs", v, (getgenv().Options.BtnBsY and getgenv().Options.BtnBsY.Value) or DEF.bs.y) end})
            pos:AddSlider("BtnBsY", {Text="BS 纵", Default=DEF.bs.y, Min=-500, Max=500, Rounding=0,
                Callback=function(v) API.setPos("bs", (getgenv().Options.BtnBsX and getgenv().Options.BtnBsX.Value) or DEF.bs.x, v) end})
            pos:AddSlider("BtnAimX", {Text="AIM 横", Default=DEF.aim.x, Min=-800, Max=0, Rounding=0,
                Callback=function(v) API.setPos("aim", v, (getgenv().Options.BtnAimY and getgenv().Options.BtnAimY.Value) or DEF.aim.y) end})
            pos:AddSlider("BtnAimY", {Text="AIM 纵", Default=DEF.aim.y, Min=-500, Max=500, Rounding=0,
                Callback=function(v) API.setPos("aim", (getgenv().Options.BtnAimX and getgenv().Options.BtnAimX.Value) or DEF.aim.x, v) end})
            pos:AddSlider("BtnBhopX", {Text="BHOP 横", Default=DEF.bhop.x, Min=-800, Max=0, Rounding=0,
                Callback=function(v) API.setPos("bhop", v, (getgenv().Options.BtnBhopY and getgenv().Options.BtnBhopY.Value) or DEF.bhop.y) end})
            pos:AddSlider("BtnBhopY", {Text="BHOP 纵", Default=DEF.bhop.y, Min=-500, Max=500, Rounding=0,
                Callback=function(v) API.setPos("bhop", (getgenv().Options.BtnBhopX and getgenv().Options.BtnBhopX.Value) or DEF.bhop.x, v) end})

            local skin = tab:AddRightGroupbox("皮肤修改器")
            skin:AddToggle("SkinChangerEnable", {
                Text = "启用皮肤修改器",
                Default = false,
                Callback = function(v)
                    if v then
                        if not skinStart() then
                            local T = getgenv().Toggles
                            if T and T.SkinChangerEnable then pcall(function() T.SkinChangerEnable:SetValue(false) end) end
                        end
                    else
                        skinStop()
                    end
                end
            })
            skin:AddButton({
                Text = "关闭皮肤修改器",
                Func = function()
                    skinStop()
                    local T = getgenv().Toggles
                    if T and T.SkinChangerEnable then pcall(function() T.SkinChangerEnable:SetValue(false) end) end
                end
            })
        end)
    end

    print("[Bloxstrike] 手机浮层已加载：右侧 BS/AIM/BHOP，「手机」页可调位置与皮肤修改器")
end

return "Seeto.SolutionZ / Bloxstrike / v2.5"
