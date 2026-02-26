local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local OUT_JSON = "tdx/upgradent.json"

if isfile and isfile(OUT_JSON) and delfile then
    pcall(delfile, OUT_JSON)
end

local recordedActions = {}
if makefolder then pcall(makefolder, "tdx") end

local TDX_Shared = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local TowerUpgradeShopUtilities = nil

local loadOk, loadErr = pcall(function()
    require(TDX_Shared:WaitForChild("Enums"))
    require(TDX_Shared:WaitForChild("Types"))
    TowerUpgradeShopUtilities = require(TDX_Shared:WaitForChild("TowerUpgradeShopUtilities"))
end)

if not TowerUpgradeShopUtilities then return end

local dataHandler = nil

local function findLocalPlayerHandler()
    if not getgc then return nil end
    for _, obj in pairs(getgc(true)) do
        if type(obj) == "table"
            and rawget(obj, "IsLocalPlayer") == true
            and rawget(obj, "UpgradeShopDataHandler") ~= nil
            and type(rawget(obj, "UpgradeShopDataHandler")) == "table" then
            return obj.UpgradeShopDataHandler
        end
    end
    return nil
end

local function ensureHandler()
    if dataHandler then return dataHandler end
    dataHandler = findLocalPlayerHandler()
    return dataHandler
end

local function getUpgradeCost(tower, upgradeType)
    local handler = ensureHandler()
    if not handler then return nil end
    local ok, result = pcall(function()
        local itemData = TowerUpgradeShopUtilities.GetUpgradeShopItemDataForTower(tower, upgradeType)
        if not itemData then return nil end
        local activeData = TowerUpgradeShopUtilities.GetActiveUpgradeShopData(
            handler.TowerToUpgradeTypeToActiveUpgradeData, tower, upgradeType
        )
        if not activeData then return nil end
        return TowerUpgradeShopUtilities.GetOperationCost(activeData, itemData)
    end)
    return ok and result or nil
end

local function getCurrentLevel(tower, upgradeType)
    local handler = ensureHandler()
    if not handler then return nil end
    local ok, result = pcall(function()
        return TowerUpgradeShopUtilities.GetCurrentLevelForTowerAndType(
            handler.TowerToUpgradeTypeToActiveUpgradeData, tower, upgradeType
        )
    end)
    return ok and result or nil
end

local function getCredits()
    local handler = ensureHandler()
    return handler and handler.Credits or 0
end

local function updateJsonFile()
    if not writefile then return end
    local lines = {}
    for i, entry in ipairs(recordedActions) do
        local ok, str = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            table.insert(lines, (i < #recordedActions) and (str .. ",") or str)
        end
    end
    local json = "[\n" .. table.concat(lines, "\n") .. "\n]"
    pcall(writefile, OUT_JSON, json)
end

local function hookDataUpdate()
    local handler = ensureHandler()
    if not handler then return false end

    local mt = getmetatable(handler)
    if not mt or type(mt.DataUpdate) ~= "function" then return false end

    local originalDataUpdate = mt.DataUpdate

    local hookOk = pcall(function()
        mt.DataUpdate = function(self, tower, upgradeType, newLevel)
            if self == handler then
                local oldLevel = getCurrentLevel(tower, upgradeType) or 0
                if newLevel > oldLevel then
                    local cost = getUpgradeCost(tower, upgradeType) or 0
                    originalDataUpdate(self, tower, upgradeType, newLevel)
                    table.insert(recordedActions, {
                        UpgradeShopTower = tower,
                        UpgradeShopType = upgradeType,
                        UpgradeShopCost = cost,
                        UpgradeShopLevel = newLevel
                    })
                    updateJsonFile()
                else
                    originalDataUpdate(self, tower, upgradeType, newLevel)
                end
            else
                originalDataUpdate(self, tower, upgradeType, newLevel)
            end
        end
    end)

    return hookOk
end

task.spawn(function()
    for i = 1, 30 do
        if ensureHandler() then
            hookDataUpdate()
            return
        end
        task.wait(2)
    end
end)
