local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

-- Конфигурация
local outJson = "tdx/upgradent.json"

-- Удаляем старый файл
if isfile and isfile(outJson) and delfile then
    pcall(delfile, outJson)
end

local recordedActions = {}

-- Создание папок
if makefolder then
    pcall(makefolder, "tdx")
end

--==============================================================================
--=                           HELPER FUNCTIONS                                 =
--==============================================================================

local function getUpgradeShopCredits()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return 0 end
    
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    
    local upgradeShopScreen = interface:FindFirstChild("UpgradeShopScreen")
    if not upgradeShopScreen then return 0 end
    
    local creditsButton = upgradeShopScreen:FindFirstChild("CreditsButton")
    if not creditsButton then return 0 end
    
    local textLabel = creditsButton:FindFirstChild("TextLabel")
    if not textLabel or not textLabel:IsA("TextLabel") then return 0 end
    
    local creditsStr = tostring(textLabel.Text):match("%d+")
    return tonumber(creditsStr) or 0
end

local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("❌ Write error:", err)
        else
            print("📝 Saved:", path, "| Total:", #recordedActions)
        end
    end
end

local function updateJsonFile()
    if not HttpService then return end
    local jsonLines = {}
    for i, entry in ipairs(recordedActions) do
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            if i < #recordedActions then
                jsonStr = jsonStr .. ","
            end
            table.insert(jsonLines, jsonStr)
        end
    end
    local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
    safeWriteFile(outJson, finalJson)
end

--==============================================================================
--=                           HOOK SYSTEM                                      =
--==============================================================================

local function handleRemote(towerType, upgradeType)
    print("🛒 Detected:", towerType, "-", upgradeType)
    
    local creditsBefore = getUpgradeShopCredits()
    
    -- Записываем сразу
    local entry = {
        UpgradeShopTower = towerType,
        UpgradeShopType = upgradeType,
        UpgradeShopCost = 0,
        Timestamp = os.time()
    }
    
    table.insert(recordedActions, entry)
    updateJsonFile()
    
    -- Пытаемся вычислить стоимость
    task.spawn(function()
        task.wait(0.3)
        local creditsAfter = getUpgradeShopCredits()
        local cost = creditsBefore - creditsAfter
        
        if cost > 0 then
            local lastEntry = recordedActions[#recordedActions]
            if lastEntry and lastEntry.UpgradeShopTower == towerType and lastEntry.UpgradeShopType == upgradeType then
                lastEntry.UpgradeShopCost = cost
                updateJsonFile()
                print("💰 Cost calculated:", cost, "credits")
            end
        end
    end)
end

local function setupHooks()
    if not hookmetamethod or not checkcaller or not getnamecallmethod then
        warn("❌ Executor doesn't support required hooks!")
        return
    end
    
    print("✅ Setting up hooks...")
    
    -- Hook ТОЛЬКО namecall
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        -- Проверяем что это наш remote
        if method == "InvokeServer" and self.Name == "UpgradeShopOperationRequest" then
            -- Логируем БЕЗ блокировки
            if not checkcaller() then
                local towerType, upgradeType = args[1], args[2]
                if typeof(towerType) == "string" and typeof(upgradeType) == "string" then
                    task.spawn(function()
                        handleRemote(towerType, upgradeType)
                    end)
                end
            end
        end
        
        -- ВАЖНО: всегда вызываем оригинальную функцию
        return oldNamecall(self, ...)
    end)
    
    print("✅ Hooks installed!")
end

--==============================================================================
--=                           INITIALIZATION                                   =
--==============================================================================

setupHooks()

print("🎬 UPGRADE SHOP LOGGER STARTED!")
print("📁 Logging to:", outJson)
print("🔍 Waiting for UpgradeShop operations...")
print("⚠️ Script will NOT block your upgrades!")
