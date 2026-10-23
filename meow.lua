local rs = game:GetService("RunService")
if not rs:IsClient() then
    return
end

local p = game:GetService("Players")
local uis = game:GetService("UserInputService")
local http = game:GetService("HttpService")
local sg = game:GetService("StarterGui")
local player = p.LocalPlayer
if not player then
    return
end

local environment = _G
if type(getgenv) == "function" then
    local valid, sharedEnvironment = pcall(getgenv)
    if valid and type(sharedEnvironment) == "table" then
        environment = sharedEnvironment
    end
end

local previous = rawget(environment, "MoonCameraControls") or rawget(environment, "MoonCameraControls")
if type(previous) == "table" and type(previous.cleanup) == "function" then
    pcall(previous.cleanup)
end

local state = {
    active = true,
    firstPerson = false,
    extendedZoom = false,
    maxDistance = 320,
    fov = 75,
    sensitivity = 0.23,
    cursorFree = false,
    allowJump = false,
    yaw = 0,
    pitch = 0,
    cameraController = nil,
    inputController = nil,
    zoomEntry = nil,
    savedZoom = nil,
    savedForward = nil,
    savedRight = nil,
    savedCameraType = nil,
    savedFov = nil,
    savedMouseBehavior = nil,
    savedMouseIcon = nil,
    hidden = {},
    jumpStates = {},
    connections = {},
    window = nil,
    firstPersonToggle = nil
}

local function notify(message)
    pcall(function()
        sg:SetCore("SendNotification", {
            Title = "Moon",
            Text = tostring(message),
            Duration = 5
        })
    end)
end

local function direction()
    return Vector3.new(-math.sin(state.yaw), 0, -math.cos(state.yaw))
end

local function right()
    local forward = direction()
    return Vector3.new(-forward.Z, 0, forward.X)
end

local function currentParts()
    local character = player.Character
    if not character or not character.Parent then
        return nil, nil, nil, nil
    end
    return character, character:FindFirstChild("HumanoidRootPart"), character:FindFirstChild("Head"), character:FindFirstChildOfClass("Humanoid")
end

local function pose()
    local character, root, head = currentParts()
    if not character or not root then
        return nil
    end
    local position = head and head.Position or root.Position + Vector3.new(0, 1.55, 0)
    return CFrame.new(position) * CFrame.fromOrientation(state.pitch, state.yaw, 0)
end

local function restoreAppearance()
    for part, value in pairs(state.hidden) do
        if part and part.Parent then
            pcall(function()
                part.LocalTransparencyModifier = value
            end)
        end
        state.hidden[part] = nil
    end
end

local function hideHead()
    local character = player.Character
    if not character then
        return
    end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and (part.Name == "Head" or part:FindFirstAncestorWhichIsA("Accessory")) then
            if state.hidden[part] == nil then
                state.hidden[part] = part.LocalTransparencyModifier
            end
            part.LocalTransparencyModifier = 1
        end
    end
end

local function restoreJump()
    for humanoid, enabled in pairs(state.jumpStates) do
        if humanoid and humanoid.Parent then
            pcall(function()
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
            end)
        end
        state.jumpStates[humanoid] = nil
    end
end

local function applyZoom()
    local controller = state.cameraController
    local levels = controller and controller.ZOOM_LEVELS
    if type(levels) ~= "table" or #levels == 0 then
        return false
    end
    if state.extendedZoom then
        if not state.zoomEntry then
            if type(controller.zoomLevel) == "function" then
                local success, zoom = pcall(controller.zoomLevel)
                if success and type(zoom) == "number" then
                    state.savedZoom = zoom
                end
            end
            local last = levels[#levels]
            local entry = {dist = state.maxDistance, fov = last and last.fov or 22}
            table.insert(levels, entry)
            state.zoomEntry = entry
        else
            state.zoomEntry.dist = state.maxDistance
        end
        if type(controller.setZoom) == "function" then
            pcall(controller.setZoom, #levels)
        end
    elseif state.zoomEntry then
        for index = #levels, 1, -1 do
            if levels[index] == state.zoomEntry then
                table.remove(levels, index)
                break
            end
        end
        state.zoomEntry = nil
        if type(controller.setZoom) == "function" then
            pcall(controller.setZoom, math.clamp(state.savedZoom or 2, 1, #levels))
        end
        state.savedZoom = nil
    end
    return true
end

local function patchInput()
    local controller = state.cameraController
    if not controller or type(controller.forward) ~= "function" or type(controller.right) ~= "function" then
        return
    end
    if not state.savedForward then
        state.savedForward = controller.forward
        state.savedRight = controller.right
    end
    controller.forward = direction
    controller.right = right
end

local function restoreInput()
    local controller = state.cameraController
    if controller and state.savedForward then
        controller.forward = state.savedForward
        controller.right = state.savedRight
    end
    state.savedForward = nil
    state.savedRight = nil
    local input = state.inputController
    if input and type(input.setAimOverride) == "function" then
        pcall(input.setAimOverride, nil)
    end
end

local function setFirstPerson(enabled)
    enabled = enabled == true
    if state.firstPerson == enabled then
        return
    end
    state.firstPerson = enabled
    if enabled then
        local character, root = currentParts()
        if root then
            local look = root.CFrame.LookVector
            state.yaw = math.atan2(-look.X, -look.Z)
        end
        state.pitch = 0
        state.cursorFree = false
        local camera = workspace.CurrentCamera
        if camera then
            state.savedCameraType = camera.CameraType
            state.savedFov = camera.FieldOfView
        end
        state.savedMouseBehavior = uis.MouseBehavior
        state.savedMouseIcon = uis.MouseIconEnabled
        patchInput()
    else
        restoreInput()
        restoreAppearance()
        restoreJump()
        uis.MouseBehavior = state.savedMouseBehavior or Enum.MouseBehavior.Default
        if state.savedMouseIcon ~= nil then
            uis.MouseIconEnabled = state.savedMouseIcon
        end
        local camera = workspace.CurrentCamera
        if camera then
            if not state.cameraController then
                camera.CameraType = state.savedCameraType or Enum.CameraType.Custom
            end
            if state.savedFov then
                camera.FieldOfView = state.savedFov
            end
        end
        state.savedCameraType = nil
        state.savedFov = nil
    end
end

local function findControllers()
    if player:GetAttribute("ClientBooted") ~= true then
        return
    end
    local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
    if not playerScripts then
        return
    end
    for _, instance in ipairs(playerScripts:GetDescendants()) do
        if instance:IsA("ModuleScript") and instance.Parent and (instance.Name == "Camera" or instance.Name == "Input") then
            local sameFolder = instance.Parent:FindFirstChild("Camera") and instance.Parent:FindFirstChild("Input")
            if sameFolder then
                local success, module = pcall(require, instance)
                if success and type(module) == "table" then
                    if instance.Name == "Camera" and type(module.setZoom) == "function" and type(module.zoomLevel) == "function" then
                        state.cameraController = module
                    elseif instance.Name == "Input" and type(module.aimPoint) == "function" and type(module.setAimOverride) == "function" then
                        state.inputController = module
                    end
                end
            end
        end
    end
    if state.firstPerson then
        patchInput()
    end
    if state.extendedZoom then
        applyZoom()
    end
end

local lastHead = 0
local function renderFirstPerson()
    if not state.active or not state.firstPerson then
        return
    end
    local camera = workspace.CurrentCamera
    local cameraPose = pose()
    if not camera or not cameraPose then
        return
    end
    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = cameraPose
    camera.Focus = CFrame.new(cameraPose.Position + cameraPose.LookVector * 15)
    camera.FieldOfView = state.fov
    local free = state.cursorFree or uis:GetFocusedTextBox() ~= nil
    uis.MouseBehavior = free and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
    uis.MouseIconEnabled = free
    if os.clock() - lastHead >= 0.25 then
        lastHead = os.clock()
        hideHead()
    end
end

local lastAim = 0
local function inputStep()
    if not state.active or not state.firstPerson then
        return
    end
    local character, root, _, humanoid = currentParts()
    if not character or not root or not humanoid then
        return
    end
    local input = state.inputController
    if input and type(input.setAimOverride) == "function" then
        if os.clock() - lastAim >= 0.05 then
            lastAim = os.clock()
            pcall(input.setAimOverride, root.Position + direction() * 180)
        end
    else
        local move = Vector3.zero
        if uis:GetFocusedTextBox() == nil then
            if uis:IsKeyDown(Enum.KeyCode.W) then
                move += direction()
            end
            if uis:IsKeyDown(Enum.KeyCode.S) then
                move -= direction()
            end
            if uis:IsKeyDown(Enum.KeyCode.A) then
                move -= right()
            end
            if uis:IsKeyDown(Enum.KeyCode.D) then
                move += right()
            end
        end
        humanoid:Move(move.Magnitude > 1 and move.Unit or move, false)
    end
    if state.allowJump then
        if state.jumpStates[humanoid] == nil then
            state.jumpStates[humanoid] = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
        end
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        if uis:GetFocusedTextBox() == nil and uis:IsKeyDown(Enum.KeyCode.Space) then
            humanoid.Jump = true
        end
    end
end

table.insert(state.connections, uis.InputChanged:Connect(function(input)
    if not state.active or not state.firstPerson or state.cursorFree or uis:GetFocusedTextBox() then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        local rate = math.rad(state.sensitivity)
        state.yaw -= input.Delta.X * rate
        state.pitch = math.clamp(state.pitch - input.Delta.Y * rate, -1.45, 1.45)
    end
end))

table.insert(state.connections, uis.InputBegan:Connect(function(input)
    if state.firstPerson and input.KeyCode == Enum.KeyCode.LeftAlt then
        state.cursorFree = not state.cursorFree
    end
end))

table.insert(state.connections, player.CharacterAdded:Connect(function()
    restoreAppearance()
    restoreJump()
end))

table.insert(state.connections, player:GetAttributeChangedSignal("Place"):Connect(function()
    local place = player:GetAttribute("Place")
    if state.firstPerson and (place == "Menu" or place == "Transit") then
        setFirstPerson(false)
        if state.firstPersonToggle then
            pcall(function()
                state.firstPersonToggle:Set(false, true)
            end)
        end
    end
end))

rs:BindToRenderStep("MoonFirstPerson", Enum.RenderPriority.Camera.Value + 4, renderFirstPerson)
table.insert(state.connections, rs.Heartbeat:Connect(inputStep))

local function cleanup()
    if not state.active then
        return
    end
    if type(state.addonCleanup) == "function" then
        pcall(state.addonCleanup)
    end
    if type(state.visualCleanup) == "function" then
        pcall(state.visualCleanup)
    end
    setFirstPerson(false)
    state.extendedZoom = false
    applyZoom()
    state.active = false
    rs:UnbindFromRenderStep("MoonFirstPerson")
    for _, connection in ipairs(state.connections) do
        connection:Disconnect()
    end
    if state.window then
        pcall(function()
            state.window:Unload()
        end)
    end
    if rawget(environment, "MoonCameraControls") == state then
        environment.MoonCameraControls = nil
    end
end

state.cleanup = cleanup
environment.MoonCameraControls = state

task.spawn(function()
    for _ = 1, 100 do
        if not state.active then
            return
        end
        if player:GetAttribute("ClientBooted") == true then
            findControllers()
            if state.cameraController and state.inputController then
                return
            end
        end
        task.wait(0.3)
    end
end)

local function getLibrary()
    local address = "https://sirius.menu/gen2"
    local content
    if type(request) == "function" then
        local success, response = pcall(request, {Url = address, Method = "GET"})
        if success and type(response) == "table" and response.Success == true and tonumber(response.StatusCode) == 200 and type(response.Body) == "string" and #response.Body > 0 then
            content = response.Body
        end
    end
    if not content then
        local success, body = pcall(function()
            return game:HttpGet(address)
        end)
        if success and type(body) == "string" and #body > 0 then
            content = body
        else
            success, body = pcall(function()
                return http:GetAsync(address)
            end)
            if success and type(body) == "string" and #body > 0 then
                content = body
            end
        end
    end
    if not content or type(loadstring) ~= "function" then
        return nil
    end
    local success, compiled = pcall(loadstring, content)
    if not success or type(compiled) ~= "function" then
        return nil
    end
    local valid, library = pcall(compiled)
    if valid and type(library) == "table" then
        return library
    end
    return nil
end

local Rayfield = getLibrary()
if not Rayfield then
    notify("Rayfield Gen2 could not load in this execution context.")
    cleanup()
    return
end

local valid, window = pcall(function()
    return Rayfield:CreateWindow({
        name = "Moon",
        subtitle = "discord.gg/moonhub",
        sidebarLayout = true,
        theme = "cobalt",
        showName = "Moon"
    })
end)

if not valid or not window then
    notify("Rayfield Gen2 window could not be created.")
    cleanup()
    return
end

state.window = window

local tab = window:CreateTab({name = "Visual"})
tab:CreateSection({name = "Distance"})

state.zoomToggle = tab:CreateToggle({
    name = "Max Distance Zoom",
    flag = "MoonMaxZoom",
    forgetState = true,
    value = false,
    callback = function(value)
        state.extendedZoom = value == true
        if not applyZoom() then
            findControllers()
            applyZoom()
        end
    end
})

state.zoomSlider = tab:CreateSlider({
    name = "Maximum Distance",
    flag = "MoonZoomDistance",
    forgetState = true,
    range = {176, 5000},
    increment = 4,
    value = state.maxDistance,
    suffix = " studs",
    callback = function(value)
        state.maxDistance = math.clamp(tonumber(value) or 320, 176, 5000)
        if state.extendedZoom then
            applyZoom()
        end
    end
})

tab:CreateSection({name = "First Person"})

state.firstPersonToggle = tab:CreateToggle({
    name = "First Person Camera + Controls",
    flag = "MoonFirstPerson",
    forgetState = true,
    value = false,
    callback = function(value)
        setFirstPerson(value)
    end
})

state.fovSlider = tab:CreateSlider({
    name = "First Person FOV",
    range = {55, 110},
    increment = 1,
    value = state.fov,
    suffix = " deg",
    forgetState = true,
    callback = function(value)
        state.fov = tonumber(value) or 75
    end
})

state.sensitivitySlider = tab:CreateSlider({
    name = "Mouse Sensitivity",
    range = {0.08, 0.6},
    increment = 0.01,
    value = state.sensitivity,
    forgetState = true,
    callback = function(value)
        state.sensitivity = tonumber(value) or 0.23
    end
})

tab:CreateButton({
    name = "Restore Camera",
    callback = function()
        setFirstPerson(false)
        state.extendedZoom = false
        applyZoom()
        if state.zoomToggle then state.zoomToggle:Set(false, true) end
        if state.firstPersonToggle then state.firstPersonToggle:Set(false, true) end
    end
})
tab:CreateButton({
    name = "Reset All",
    callback = function()
        if type(state.resetAll) == "function" then
            state.resetAll()
        else
            cleanup()
        end
    end
})


local cs = game:GetService("CollectionService")
local ov = {
    active = true,
    root = Instance.new("Folder"),
    entries = {},
    ids = setmetatable({}, {__mode = "k"}),
    nextId = 0,
    limits = {players = 16, enemies = 55, containers = 45},
    libraryLimit = 20,
    highlights = 28,
    lib = nil,
    libTried = false,
    settings = {
        players = {enabled = false, health = true, range = 5000, color = Color3.fromRGB(70, 190, 255)},
        enemies = {enabled = false, health = true, range = 5000, color = Color3.fromRGB(255, 85, 85)},
        containers = {enabled = false, health = false, range = 3500, color = Color3.fromRGB(255, 195, 75)}
    },
    controls = {players = {}, enemies = {}, containers = {}}
}
ov.root.Name = "MoonVisuals"
ov.root.Parent = workspace

local function loadEspLibrary()
    if ov.libTried then return ov.lib end
    ov.libTried = true
    local cached = rawget(environment, "mstudio45_ESP")
    if type(cached) == "table" and type(cached.Add) == "function" and cached.Destroyed ~= true then
        ov.lib = cached
        if type(cached.GlobalConfig) == "table" then cached.GlobalConfig.Distance = false end
        return cached
    end
    local url = "https://raw.githubusercontent.com/mstudio45/MSESP/refs/heads/main/source.luau"
    local source
    if type(request) == "function" then
        local ok, result = pcall(request, {Url = url, Method = "GET"})
        if ok and type(result) == "table" and tonumber(result.StatusCode) == 200 and type(result.Body) == "string" then
            source = result.Body
        end
    end
    if not source then
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" then source = body end
    end
    if not source then
        local ok, body = pcall(function() return http:GetAsync(url) end)
        if ok and type(body) == "string" then source = body end
    end
    if type(source) ~= "string" or type(loadstring) ~= "function" then return nil end
    local ok, chunk = pcall(loadstring, source)
    if not ok or type(chunk) ~= "function" then return nil end
    local ran, result = pcall(chunk)
    if ran and type(result) == "table" and type(result.Add) == "function" then
        ov.lib = result
        if type(result.GlobalConfig) == "table" then result.GlobalConfig.Distance = false end
    end
    return ov.lib
end

local function bodyPart(target)
    if not target or not target.Parent then return nil end
    if target:IsA("BasePart") then return target end
    if target:IsA("Model") then
        local part = target:FindFirstChild("HumanoidRootPart", true) or target:FindFirstChild("Head", true) or target.PrimaryPart
        if part and part:IsA("BasePart") then return part end
        return target:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function readHealth(target, kind)
    local sources = {target}
    if target:IsA("Model") then
        for _, name in ipairs({"HumanoidRootPart", "Head", "Health", "Stats", "Attributes"}) do
            local child = target:FindFirstChild(name, true)
            if child then table.insert(sources, child) end
        end
    end
    if kind == "players" then
        local other = p:GetPlayerFromCharacter(target)
        if other then table.insert(sources, other) end
    end
    for _, object in ipairs(sources) do
        for _, keys in ipairs({{"Hp", "MaxHp"}, {"HP", "MaxHP"}, {"Health", "MaxHealth"}, {"ZombieHp", "ZombieMaxHp"}}) do
            local hp = object:GetAttribute(keys[1])
            local max = object:GetAttribute(keys[2])
            if type(hp) == "number" and type(max) == "number" and max > 0 and hp == hp then
                return math.clamp(hp, 0, max), max
            end
        end
        if object:IsA("Folder") then
            local hp = object:FindFirstChild("Hp") or object:FindFirstChild("Health")
            local max = object:FindFirstChild("MaxHp") or object:FindFirstChild("MaxHealth")
            if hp and max and (hp:IsA("NumberValue") or hp:IsA("IntValue")) and (max:IsA("NumberValue") or max:IsA("IntValue")) and max.Value > 0 then
                return math.clamp(hp.Value, 0, max.Value), max.Value
            end
        end
    end
    if kind == "players" and target:IsA("Model") then
        local humanoid = target:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.MaxHealth > 0 then
            return math.clamp(humanoid.Health, 0, humanoid.MaxHealth), humanoid.MaxHealth
        end
    end
    return nil, nil
end

local function deadEnemy(target)
    if not target or not target.Parent then return true end
    for _, object in ipairs({target, target.Parent}) do
        if object and (object:GetAttribute("Corpse") == true or object:GetAttribute("Dead") == true or object:GetAttribute("IsDead") == true or object:GetAttribute("State") == "Dead") then
            return true
        end
    end
    if target:IsA("Model") then
        local humanoid = target:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health <= 0 then return true end
    end
    local hp = readHealth(target, "enemies")
    return type(hp) == "number" and hp <= 0
end

local function lootableContainer(target)
    if not target or not target:IsDescendantOf(workspace) then return false end
    if target:GetAttribute("Looted") == true or target:GetAttribute("Empty") == true or target:GetAttribute("Depleted") == true then return false end
    local locked = target:GetAttribute("Locked")
    if locked == true or type(locked) == "string" and locked ~= "" then return false end
    if target:GetAttribute("Cargo") == true and tonumber(target:GetAttribute("CargoOwner")) ~= player.UserId then return false end
    local viable = false
    local promptSeen = false
    for _, prompt in ipairs(target:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            promptSeen = true
            local action = string.lower(tostring(prompt.ActionText))
            if prompt.Enabled and (string.find(action, "search", 1, true) or string.find(action, "loot", 1, true) or string.find(action, "rummage", 1, true) or string.find(action, "open", 1, true)) then
                viable = true
            end
        end
    end
    if promptSeen then return viable end
    return target:GetAttribute("Looted") == false
end

local function clearEntry(entry)
    if entry.esp then
        pcall(entry.esp.Destroy, entry.esp)
        entry.esp = nil
    end
    if entry.highlight then entry.highlight:Destroy() entry.highlight = nil end
    if entry.outline then entry.outline:Destroy() entry.outline = nil end
    if entry.bar then entry.bar:Destroy() entry.bar = nil end
    if entry.lootLabel then entry.lootLabel:Destroy() entry.lootLabel = nil end
end

local function zombieTypeInfo()
    if not ov.zombieDefs then
        local rep = game:GetService("ReplicatedStorage")
        local hush = rep:FindFirstChild("Hush")
        local shared = hush and hush:FindFirstChild("Shared")
        local module = shared and shared:FindFirstChild("ZombieTypes")
        if module then
            local ok, result = pcall(require, module)
            if ok and type(result) == "table" then ov.zombieDefs = result end
        end
    end
    if not ov.zombieRender then
        local scripts = player:FindFirstChildOfClass("PlayerScripts")
        local module = scripts and scripts:FindFirstChild("ZombieRender", true)
        if module and module:IsA("ModuleScript") then
            local ok, result = pcall(require, module)
            if ok and type(result) == "table" and type(result.targets) == "function" then
                ov.zombieRender = result
            end
        end
    end
    if not ov.zombieRender then return nil end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local ok, records = pcall(ov.zombieRender.targets, root.Position, ov.settings.enemies.range + 10)
    if ok and type(records) == "table" then return records end
    return nil
end

local function zombieMaximum(part, records)
    if not records or not ov.zombieDefs or not part then return nil end
    local best, bestDistance
    for _, record in ipairs(records) do
        if type(record) == "table" and typeof(record.position) == "Vector3" then
            local delta = record.position - part.Position
            local horizontal = delta.X * delta.X + delta.Z * delta.Z
            if horizontal <= 25 and math.abs(delta.Y) < 9 then
                local distance = horizontal + delta.Y * delta.Y * 0.04
                if not bestDistance or distance < bestDistance then
                    best = record.typeId
                    bestDistance = distance
                end
            end
        end
    end
    if best == nil then return nil end
    local def = if type(best) == "number" then ov.zombieDefs.byIndex and ov.zombieDefs.byIndex[best] else ov.zombieDefs.byId and ov.zombieDefs.byId[best]
    if type(def) == "table" and type(def.hp) == "number" and def.hp > 0 then return def.hp end
    return nil
end

local function espTitle(choice)
    local name
    if choice.kind == "players" then
        local other = p:GetPlayerFromCharacter(choice.target)
        name = if other then other.DisplayName else "Player"
    elseif choice.kind == "enemies" then
        name = "Enemy"
    else
        return choice.target.Name
    end
    local hp, max = readHealth(choice.target, choice.kind)
    if type(hp) == "number" and type(max) == "number" and max > 0 then
        return name .. " | HP " .. math.floor(hp + 0.5) .. "/" .. math.floor(max + 0.5)
    end
    local maximum = choice.maxHp
    return if type(maximum) == "number" then name .. " | HP ?/" .. tostring(math.floor(maximum)) else name .. " | HP ?"
end

local function useLibrary(entry, choice, color)
    if not ov.lib or ov.lib.Destroyed == true then return false end
    if entry.esp and entry.esp.Deleted == true then entry.esp = nil end
    if not entry.esp then
        local settings = {
            Name = espTitle(choice),
            Model = choice.target,
            TextModel = choice.part,
            ESPType = "Highlight",
            Color = color,
            FillColor = color,
            OutlineColor = color,
            FillTransparency = 0.89,
            OutlineTransparency = 0.08,
            MaxDistance = 100000,
            StudsOffset = Vector3.new(0, 3.3, 0),
            TextSize = 12,
            Box2D = {Enabled = false},
            Tracer = {Enabled = false},
            Arrow = {Enabled = false},
            Box3D = {Enabled = false},
            Skeleton = {Enabled = false}
        }
        local ok, result = pcall(ov.lib.Add, ov.lib, settings)
        if not ok or type(result) ~= "table" then return false end
        entry.esp = result
        if type(result.Render) == "function" then
            entry.render = result.Render
            result.Render = function() end
        end
        entry.espColor = color
    end
    local e = entry.esp
    if e.CurrentSettings then
        e.CurrentSettings.MaxDistance = 100000
        if entry.espColor ~= color then
            pcall(e.SetEveryColor, e, color, true)
            entry.espColor = color
        end
    end
    return true
end

local function ensureBillboard(entry)
    if entry.bar then return end
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local gui = Instance.new("BillboardGui")
    gui.Name = "MoonHP"
    gui.Size = UDim2.fromOffset(98, 22)
    gui.AlwaysOnTop = true
    gui.Enabled = false
    gui.MaxDistance = 100000
    gui.ResetOnSpawn = false
    gui.Parent = pg
    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = Color3.fromRGB(10, 15, 24)
    bg.BackgroundTransparency = 0.12
    bg.BorderSizePixel = 0
    bg.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = bg
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(105, 120, 145)
    stroke.Transparency = 0.3
    stroke.Thickness = 1
    stroke.Parent = bg
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Position = UDim2.fromOffset(2, 2)
    fill.Size = UDim2.fromOffset(94, 18)
    fill.BackgroundColor3 = Color3.fromRGB(65, 210, 125)
    fill.BorderSizePixel = 0
    fill.Parent = bg
    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(0, 4)
    round.Parent = fill
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 11
    label.TextStrokeTransparency = 0.48
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Text = "HP —"
    label.ZIndex = 3
    label.Parent = bg
    entry.bar = gui
    entry.barFill = fill
    entry.barLabel = label
end

local function ensureLootLabel(entry, choice, color)
    if not entry.lootLabel then
        local pg = player:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        local gui = Instance.new("BillboardGui")
        gui.Name = "MoonLootLabel"
        gui.Size = UDim2.fromOffset(154, 24)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 100000
        gui.ResetOnSpawn = false
        gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
        gui.Parent = pg
        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "Name"
        textLabel.Size = UDim2.fromScale(1, 1)
        textLabel.BackgroundTransparency = 1
        textLabel.Font = Enum.Font.GothamBold
        textLabel.TextSize = 12
        textLabel.TextStrokeTransparency = 0.28
        textLabel.TextColor3 = color
        textLabel.Parent = gui
        entry.lootLabel = gui
        entry.lootText = textLabel
    end
    entry.lootLabel.Adornee = choice.part
    entry.lootText.Text = choice.target.Name
    entry.lootText.TextColor3 = color
end

local function candidate(list, found, target, kind)
    if not target or not target:IsDescendantOf(workspace) or found[target] then return end
    local settings = ov.settings[kind]
    if not settings or not settings.enabled then return end
    if kind == "enemies" and deadEnemy(target) then return end
    if kind == "containers" and not lootableContainer(target) then return end
    local part = bodyPart(target)
    local camera = workspace.CurrentCamera
    if not camera or not part or part.Position.Y < -1000 then return end
    local own = player.Character
    local root = own and own:FindFirstChild("HumanoidRootPart")
    local reference = if root then root.Position else camera.CFrame.Position
    local distance = (reference - part.Position).Magnitude
    if distance > settings.range then return end
    if not ov.ids[target] then
        ov.nextId += 1
        ov.ids[target] = ov.nextId
    end
    table.insert(list, {target = target, part = part, kind = kind, distance = distance, id = ov.ids[target]})
    found[target] = true
end

local function scan()
    if not ov.active or not state.active then return end
    local found, choices = {}, {}
    local zombieRecords = if ov.settings.enemies.enabled then zombieTypeInfo() else nil
    if ov.settings.players.enabled then
        for _, other in ipairs(p:GetPlayers()) do
            if other ~= player and other.Character then
                candidate(choices, found, other.Character, "players")
            end
        end
    end
    if ov.settings.enemies.enabled then
        local hush = workspace:FindFirstChild("HushLocal")
        local zombies = hush and hush:FindFirstChild("Zombies")
        if zombies then
            for _, item in ipairs(zombies:GetChildren()) do
                if item:IsA("Model") then
                    candidate(choices, found, item, "enemies")
                elseif item:IsA("Folder") then
                    for _, nested in ipairs(item:GetChildren()) do
                        if nested:IsA("Model") then
                            candidate(choices, found, nested, "enemies")
                        end
                    end
                end
            end
        end
        for _, tag in ipairs({"HushEnemy", "HushZombie", "HuntEnemy", "Zombie", "Enemy"}) do
            for _, tagged in ipairs(cs:GetTagged(tag)) do
                local model = tagged:IsA("Model") and tagged or tagged:FindFirstAncestorWhichIsA("Model")
                if model and not p:GetPlayerFromCharacter(model) then
                    candidate(choices, found, model, "enemies")
                end
            end
        end
    end
    if ov.settings.containers.enabled then
        for _, item in ipairs(cs:GetTagged("HushContainer")) do
            if (item:IsA("Model") or item:IsA("BasePart")) and lootableContainer(item) then
                candidate(choices, found, item, "containers")
            end
        end
    end
    local priority = {players = 1, enemies = 2, containers = 3}
    table.sort(choices, function(a, b)
        local first = priority[a.kind] or 4
        local second = priority[b.kind] or 4
        if first ~= second then return first < second end
        if math.abs(a.distance - b.distance) > 3 then return a.distance < b.distance end
        return a.id < b.id
    end)
    local chosen = {}
    local used = {players = 0, enemies = 0, containers = 0}
    local combatIndex = 0
    for _, choice in ipairs(choices) do
        local kind = choice.kind
        if used[kind] >= ov.limits[kind] then continue end
        used[kind] += 1
        if kind ~= "containers" then combatIndex += 1 end
        chosen[choice.target] = true
        local entry = ov.entries[choice.target]
        if not entry then
            entry = {target = choice.target}
            ov.entries[choice.target] = entry
        end
        entry.kind = choice.kind
        entry.part = choice.part
        if choice.kind == "enemies" then
            entry.maxHp = zombieMaximum(choice.part, zombieRecords)
            choice.maxHp = entry.maxHp
        else
            entry.maxHp = nil
        end
        local settings = ov.settings[choice.kind]
        local libraryUsed = kind ~= "containers" and combatIndex <= ov.libraryLimit and useLibrary(entry, choice, settings.color)
        if not libraryUsed and entry.esp then
            pcall(entry.esp.Destroy, entry.esp)
            entry.esp = nil
        end
        if libraryUsed then
            if entry.highlight then entry.highlight:Destroy() entry.highlight = nil end
            if entry.outline then entry.outline:Destroy() entry.outline = nil end
        elseif kind ~= "containers" and combatIndex <= ov.highlights then
            if entry.outline then entry.outline:Destroy() entry.outline = nil end
            if not entry.highlight then
                entry.highlight = Instance.new("Highlight")
                entry.highlight.Name = "MoonHighlight"
                entry.highlight.FillTransparency = 0.88
                entry.highlight.OutlineTransparency = 0.08
                entry.highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                entry.highlight.Parent = ov.root
            end
            entry.highlight.Adornee = choice.target
            entry.highlight.FillColor = settings.color
            entry.highlight.OutlineColor = settings.color
        else
            if entry.highlight then entry.highlight:Destroy() entry.highlight = nil end
            if not entry.outline then
                entry.outline = Instance.new("SelectionBox")
                entry.outline.Name = "MoonOutline"
                entry.outline.LineThickness = 0.04
                entry.outline.SurfaceTransparency = 1
                entry.outline.Parent = ov.root
            end
            entry.outline.Adornee = choice.part
            entry.outline.Color3 = settings.color
        end
        if kind == "containers" then
            ensureLootLabel(entry, choice, settings.color)
        elseif entry.lootLabel then
            entry.lootLabel:Destroy()
            entry.lootLabel = nil
            entry.lootText = nil
        end
        if entry.kind ~= "containers" and settings.health then
            ensureBillboard(entry)
        elseif entry.bar then
            entry.bar.Enabled = false
        end
    end
    for target, entry in pairs(ov.entries) do
        if not chosen[target] then
            clearEntry(entry)
            ov.entries[target] = nil
        end
    end
end

local function updateHealth()
    for target, entry in pairs(ov.entries) do
        local settings = ov.settings[entry.kind]
        local locked = entry.kind == "containers" and target:GetAttribute("Locked")
        local invalidContainer = entry.kind == "containers" and (target:GetAttribute("Looted") == true or target:GetAttribute("Empty") == true or target:GetAttribute("Depleted") == true or locked == true or type(locked) == "string" and locked ~= "" or target:GetAttribute("Cargo") == true and tonumber(target:GetAttribute("CargoOwner")) ~= player.UserId)
        if entry.kind == "enemies" and deadEnemy(target) or invalidContainer then
            clearEntry(entry)
            ov.entries[target] = nil
        else
            if entry.esp and entry.esp.CurrentSettings and entry.kind ~= "containers" then
                entry.esp.CurrentSettings.Name = espTitle(entry)
            end
        if entry.bar then
            local enabled = settings and settings.enabled and settings.health and entry.part and entry.part.Parent
            entry.bar.Enabled = enabled == true
            if enabled then
                local head = entry.target:IsA("Model") and entry.target:FindFirstChild("Head", true)
                local anchor = if head and head:IsA("BasePart") then head else entry.part
                entry.bar.Adornee = anchor
                entry.bar.StudsOffsetWorldSpace = if anchor == head then Vector3.new(0, head.Size.Y * 0.5 + 1.2, 0) else Vector3.new(0, 4, 0)
                local hp, maximum = readHealth(entry.target, entry.kind)
                if hp and maximum and maximum > 0 then
                    local fraction = math.clamp(hp / maximum, 0, 1)
                    entry.barFill.Size = UDim2.fromOffset(math.floor(94 * fraction + 0.5), 18)
                    entry.barFill.BackgroundColor3 = Color3.fromRGB(math.floor(225 * (1 - fraction) + 30), math.floor(175 * fraction + 45), 75)
                    entry.barLabel.Text = "HP " .. math.floor(hp + 0.5) .. " / " .. math.floor(maximum + 0.5)
                else
                    entry.barFill.Size = UDim2.fromOffset(0, 18)
                    entry.barLabel.Text = if type(entry.maxHp) == "number" then "HP ? / " .. tostring(math.floor(entry.maxHp)) else "HP ?"
                end
            end
        end
        end
    end
end

tab:CreateSection({name = "Players"})
for _, definition in ipairs({{"players", "Players"}, {"enemies", "Enemies"}}) do
    local key, name = definition[1], definition[2]
    if key == "enemies" then tab:CreateSection({name = "Enemies"}) end
    local settings = ov.settings[key]
    local controls = ov.controls[key]
    controls.enabled = tab:CreateToggle({
        name = name .. " ESP",
        value = false,
        forgetState = true,
        callback = function(value)
            settings.enabled = value == true
            if value then task.spawn(loadEspLibrary) end
            scan()
            updateHealth()
        end
    })
    controls.range = tab:CreateSlider({
        name = name .. " Distance",
        range = {100, 5000},
        increment = 50,
        value = settings.range,
        suffix = " studs",
        forgetState = true,
        callback = function(value)
            settings.range = tonumber(value) or 5000
        end
    })
    controls.color = tab:CreateColorPicker({
        name = name .. " Color",
        color = settings.color,
        forgetState = true,
        callback = function(color)
            if typeof(color) == "Color3" then settings.color = color end
        end
    })
    controls.health = tab:CreateToggle({
        name = name .. " HP Bars",
        value = true,
        forgetState = true,
        callback = function(value)
            settings.health = value == true
            updateHealth()
        end
    })
end

tab:CreateSection({name = "Lootable Containers"})
local containerSetting = ov.settings.containers
ov.controls.containers.enabled = tab:CreateToggle({
    name = "Lootable Container ESP",
    value = false,
    forgetState = true,
    callback = function(value)
        containerSetting.enabled = value == true
        scan()
    end
})
ov.controls.containers.range = tab:CreateSlider({
    name = "Container Distance",
    range = {100, 5000},
    increment = 50,
    value = containerSetting.range,
    suffix = " studs",
    forgetState = true,
    callback = function(value)
        containerSetting.range = tonumber(value) or 3500
    end
})
ov.controls.containers.color = tab:CreateColorPicker({
    name = "Container Color",
    color = containerSetting.color,
    forgetState = true,
    callback = function(value)
        if typeof(value) == "Color3" then containerSetting.color = value end
    end
})

task.spawn(function()
    while state.active and ov.active do
        pcall(scan)
        task.wait(0.95)
    end
end)
task.spawn(function()
    while state.active and ov.active do
        pcall(updateHealth)
        task.wait(0.28)
    end
end)

rs:BindToRenderStep("MoonLateESP", Enum.RenderPriority.Camera.Value + 8, function()
    if not ov.active then return end
    for _, entry in pairs(ov.entries) do
        local esp = entry.esp
        if esp and not esp.Deleted and entry.render then
            local ok = pcall(entry.render, esp)
            if not ok then
                esp.Render = entry.render
                entry.render = nil
            end
        end
    end
end)

state.visualCleanup = function()
    ov.active = false
    rs:UnbindFromRenderStep("MoonLateESP")
    for target, entry in pairs(ov.entries) do
        clearEntry(entry)
        ov.entries[target] = nil
    end
    ov.root:Destroy()
end

local playerLab = {
    stamina = 100,
    jump = false,
    holdStamina = false,
    staminaUntil = 0,
    staminaBackend = "not installed",
    saved = {},
    active = true
}
local statsTab = window:CreateTab({name = "Misc"})

local function installStaminaHook()
    local registry = rawget(environment, "MoonStaminaHookV2")
    if type(registry) == "table" and registry.installed then
        registry.lab = playerLab
        registry.owner = player
        playerLab.staminaBackend = "hookmetamethod(GetAttribute)"
        return true
    end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        playerLab.staminaBackend = "hookmetamethod unavailable"
        return false
    end
    registry = {lab = playerLab, owner = player, installed = false}
    local function intercept(self, ...)
        local lab = registry.lab
        if lab and lab.active and self == registry.owner.Character and getnamecallmethod() == "GetAttribute" then
            local attribute = select(1, ...)
            if lab.holdStamina or os.clock() < lab.staminaUntil then
                if attribute == "Stamina" then
                    return lab.stamina
                end
                if attribute == "Exhausted" and lab.stamina > 1.5 then
                    return false
                end
            end
        end
        return registry.original(self, ...)
    end
    local wrapped = intercept
    if type(newcclosure) == "function" then
        local success, result = pcall(newcclosure, intercept)
        if success and type(result) == "function" then
            wrapped = result
        end
    end
    local success, original = pcall(hookmetamethod, game, "__namecall", wrapped)
    if success and type(original) == "function" then
        registry.original = original
        registry.installed = true
        environment.MoonStaminaHookV2 = registry
        playerLab.staminaBackend = "hookmetamethod(GetAttribute)"
        return true
    end
    playerLab.staminaBackend = "hookmetamethod failed"
    return false
end

local function setStamina()
    local character = player.Character
    if not character or not character.Parent then
        return false
    end
    if playerLab.saved[character] == nil then
        playerLab.saved[character] = {value = character:GetAttribute("Stamina"), exhausted = character:GetAttribute("Exhausted")}
    end
    character:SetAttribute("Stamina", playerLab.stamina)
    if playerLab.stamina > 1.5 then
        character:SetAttribute("Exhausted", false)
    end
    playerLab.staminaUntil = os.clock() + 8
    installStaminaHook()
    return true
end

local function applyJump()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or not playerLab.jump then
        return
    end
    if state.jumpStates[humanoid] == nil then
        state.jumpStates[humanoid] = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
    end
    pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        humanoid.UseJumpPower = true
        humanoid.JumpPower = 50
    end)
end

statsTab:CreateSection({name = "Stamina"})
playerLab.staminaControl = statsTab:CreateSlider({
    name = "Stamina Value",
    range = {0, 100},
    increment = 1,
    value = 100,
    forgetState = true,
    callback = function(value)
        playerLab.stamina = tonumber(value) or 100
    end
})
statsTab:CreateButton({
    name = "Set Stamina",
    callback = function()
        local success = setStamina()
        notify(if success then "Stamina applied" else "Character unavailable")
    end
})
playerLab.lockControl = statsTab:CreateToggle({
    name = "Lock Stamina",
    value = false,
    forgetState = true,
    callback = function(value)
        playerLab.holdStamina = value == true
        if value then
            setStamina()
        else
            playerLab.staminaUntil = 0
        end
    end
})
statsTab:CreateSection({name = "Movement"})
playerLab.jumpControl = statsTab:CreateToggle({
    name = "Allow Jump",
    value = false,
    forgetState = true,
    callback = function(value)
        playerLab.jump = value == true
        state.allowJump = playerLab.jump
        if playerLab.jump then
            applyJump()
        else
            restoreJump()
        end
    end
})

local labConnections = {}
table.insert(labConnections, uis.InputBegan:Connect(function(input, processed)
    if processed or not playerLab.jump or input.KeyCode ~= Enum.KeyCode.Space then
        return
    end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Jump = true
    end
end))

task.spawn(function()
    while state.active and playerLab.active do
        if playerLab.holdStamina then
            pcall(setStamina)
        end
        if playerLab.jump then
            pcall(applyJump)
        end
        task.wait(0.2)
    end
end)

state.addonCleanup = function()
    playerLab.active = false
    playerLab.holdStamina = false
    playerLab.staminaUntil = 0
    local registry = rawget(environment, "MoonStaminaHookV2")
    if type(registry) == "table" and registry.lab == playerLab then
        registry.lab = nil
    end
    for _, connection in ipairs(labConnections) do
        connection:Disconnect()
    end
    for character, saved in pairs(playerLab.saved) do
        if character and character.Parent then
            pcall(function()
                character:SetAttribute("Stamina", saved.value)
                character:SetAttribute("Exhausted", saved.exhausted)
            end)
        end
    end
    state.allowJump = false
    restoreJump()
end



local beta = {
    active = true,
    controllers = {},
    controls = {},
    settings = {
        autoSprint = false,
        lowGraphics = false,
        changeTime = false,
        clockTime = 12
    },
    connections = {},
    savedEffects = setmetatable({}, {__mode = "k"}),
    effectWatches = setmetatable({}, {__mode = "k"}),
    qualitySaved = nil,
    timeMode = nil,
    timeRefresh = 0,
    sprintState = nil,
    initialClockTime = nil,
    profile = "default"
}

local lighting = game:GetService("Lighting")
beta.settings.clockTime = math.floor(lighting.ClockTime * 2 + 0.5) / 2

local function controller(name)
    if type(beta.controllers[name]) == "table" then
        return beta.controllers[name]
    end
    if name == "Input" and state.inputController then
        beta.controllers[name] = state.inputController
        return state.inputController
    end
    local scripts = player:FindFirstChildOfClass("PlayerScripts")
    if not scripts then return nil end
    local module
    if type(getloadedmodules) == "function" then
        local ok, modules = pcall(getloadedmodules)
        if ok and type(modules) == "table" then
            for _, candidate in ipairs(modules) do
                if typeof(candidate) == "Instance" and candidate:IsA("ModuleScript") and candidate.Name == name and candidate:IsDescendantOf(scripts) then
                    module = candidate
                    break
                end
            end
        end
    end
    if not module then
        for _, candidate in ipairs(scripts:GetDescendants()) do
            if candidate:IsA("ModuleScript") and candidate.Name == name then
                module = candidate
                break
            end
        end
    end
    if not module then return nil end
    local ok, result = pcall(require, module)
    if ok and type(result) == "table" then
        beta.controllers[name] = result
        return result
    end
    return nil
end

local function activeCharacter()
    local character = player.Character
    if not character or not character.Parent or character:GetAttribute("Dead") == true or character:GetAttribute("Downed") == true then
        return nil
    end
    return character
end

local function raidReady()
    return player:GetAttribute("Place") == "Raid" and activeCharacter() ~= nil
end

local function setAutoSprint(enabled)
    beta.settings.autoSprint = enabled == true
    if not beta.settings.autoSprint and beta.sprintState ~= nil then
        local input = controller("Input")
        if input and type(input.setToggle) == "function" then
            pcall(input.setToggle, "sprint", false)
        end
        beta.sprintState = nil
    end
end

local function stepAutoSprint()
    if not beta.settings.autoSprint then return end
    local input = controller("Input")
    if not raidReady() then
        if beta.sprintState == true and input and type(input.setToggle) == "function" then
            pcall(input.setToggle, "sprint", false)
        end
        beta.sprintState = nil
        return
    end
    if not input or type(input.moveVector) ~= "function" or type(input.setToggle) ~= "function" then
        return
    end
    local ok, move = pcall(input.moveVector)
    if not ok or typeof(move) ~= "Vector3" then return end
    local character = activeCharacter()
    local stamina = character and character:GetAttribute("Stamina")
    local blocked = character and (character:GetAttribute("Exhausted") == true or character:GetAttribute("Fracture") == true)
    local aiming = type(input.isAiming) == "function" and input.isAiming()
    local sneaking = type(input.isSneaking) == "function" and input.isSneaking()
    local desired = move.Magnitude > 0.12 and not blocked and not aiming and not sneaking and (type(stamina) ~= "number" or stamina > 5)
    if beta.sprintState ~= desired then
        local changed = pcall(input.setToggle, "sprint", desired)
        if changed then beta.sprintState = desired end
    end
end

local function setLowGraphics(enabled)
    enabled = enabled == true
    beta.settings.lowGraphics = enabled
    local atmo = controller("Atmosphere")
    if enabled then
        if atmo and type(atmo.setQuality) == "function" then
            if beta.qualitySaved == nil and type(atmo.quality) == "function" then
                local ok, value = pcall(atmo.quality)
                if ok and type(value) == "number" then beta.qualitySaved = value end
            end
            pcall(atmo.setQuality, 1)
        end
    else
        for object, watch in pairs(beta.effectWatches) do
            pcall(function() watch:Disconnect() end)
            beta.effectWatches[object] = nil
        end
        for object, saved in pairs(beta.savedEffects) do
            if object and object.Parent then
                pcall(function() object.Enabled = saved end)
            end
            beta.savedEffects[object] = nil
        end
        if atmo and type(atmo.setQuality) == "function" then
            pcall(atmo.setQuality, beta.qualitySaved or "auto")
        end
        beta.qualitySaved = nil
        return
    end
    local function disableEffect(object)
        if not beta.active or not beta.settings.lowGraphics or not object.Parent then return end
        if not (object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")) then return end
        if beta.savedEffects[object] == nil then
            beta.savedEffects[object] = object.Enabled
        end
        if not beta.effectWatches[object] then
            beta.effectWatches[object] = object:GetPropertyChangedSignal("Enabled"):Connect(function()
                if beta.active and beta.settings.lowGraphics and object.Parent and object.Enabled then
                    object.Enabled = false
                end
            end)
        end
        if object.Enabled then object.Enabled = false end
    end
    for index, object in ipairs(workspace:GetDescendants()) do
        pcall(disableEffect, object)
        if index % 350 == 0 then task.wait() end
    end
end

local function effectAdded(object)
    if not beta.active or not beta.settings.lowGraphics then return end
    if object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
        if beta.savedEffects[object] == nil then beta.savedEffects[object] = object.Enabled end
        if not beta.effectWatches[object] then
            beta.effectWatches[object] = object:GetPropertyChangedSignal("Enabled"):Connect(function()
                if beta.active and beta.settings.lowGraphics and object.Parent and object.Enabled then
                    object.Enabled = false
                end
            end)
        end
        object.Enabled = false
    end
end
table.insert(beta.connections, workspace.DescendantAdded:Connect(effectAdded))

local timeHook = rawget(environment, "MoonTimePresets")
if type(timeHook) ~= "table" then
    timeHook = {installed = false, owner = nil}
    environment.MoonTimePresets = timeHook
end

local function installTimePresets()
    local rep = game:GetService("ReplicatedStorage")
    local hush = rep:FindFirstChild("Hush")
    local shared = hush and hush:FindFirstChild("Shared")
    local module = shared and shared:FindFirstChild("LightingPresets")
    if not module then return false end
    local ok, presets = pcall(require, module)
    if not ok or type(presets) ~= "table" or type(presets.resolve) ~= "function" then return false end
    if not timeHook.installed then
        timeHook.original = presets.resolve
        presets.resolve = function(...)
            local result = timeHook.original(...)
            local owner = timeHook.owner
            if owner and owner.active and owner.settings.changeTime and type(result) == "table" and type(result.Lighting) == "table" then
                result.Lighting.ClockTime = owner.settings.clockTime
            end
            return result
        end
        timeHook.installed = true
    end
    timeHook.owner = beta
    return true
end

local function timePreset(hour)
    if hour < 7 or hour >= 20 then return "Night" end
    if hour >= 17 then return "Dusk" end
    return "Day"
end

local function updateTimeMode()
    if not beta.settings.changeTime then return end
    local atmo = controller("Atmosphere")
    if atmo and type(atmo.setOverride) == "function" and installTimePresets() then
        local place = "Raid"
        local weather = "Clear"
        if type(atmo.current) == "function" then
            local ok, info = pcall(atmo.current)
            if ok and type(info) == "table" then
                if type(info.place) == "string" and info.place ~= "" then place = info.place end
                if type(info.weather) == "string" then weather = info.weather end
            end
        end
        local ok = pcall(atmo.setOverride, place, timePreset(beta.settings.clockTime), weather, 0.22)
        if ok then
            beta.timeMode = "native"
            return
        end
    end
    beta.timeMode = "fallback"
    if lighting.ClockTime ~= beta.settings.clockTime then
        lighting.ClockTime = beta.settings.clockTime
    end
end

local function setTimeOverride(enabled)
    enabled = enabled == true
    if enabled then
        if beta.timeMode == nil then
            beta.initialClockTime = lighting.ClockTime
        end
        beta.settings.changeTime = true
        updateTimeMode()
        return
    end
    beta.settings.changeTime = false
    if timeHook.owner == beta then timeHook.owner = nil end
    if beta.timeMode == "native" then
        local atmo = controller("Atmosphere")
        if atmo and type(atmo.clearOverride) == "function" then
            pcall(atmo.clearOverride, 0.35)
        end
    elseif beta.initialClockTime ~= nil then
        lighting.ClockTime = beta.initialClockTime
    end
    beta.initialClockTime = nil
    beta.timeMode = nil
end

local function normalizeProfile(value)
    local safe = tostring(value or ""):gsub("[^%w_-]", "")
    return string.sub(safe, 1, 28) ~= "" and string.sub(safe, 1, 28) or "default"
end

local function configPath()
    return "Moon_" .. normalizeProfile(beta.profile) .. ".json"
end

local function colorArray(color)
    return {math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5)}
end

local function decodeColor(value, fallback)
    if type(value) ~= "table" then return fallback end
    local red = tonumber(value[1])
    local green = tonumber(value[2])
    local blue = tonumber(value[3])
    if not red or not green or not blue then return fallback end
    return Color3.fromRGB(math.clamp(red, 0, 255), math.clamp(green, 0, 255), math.clamp(blue, 0, 255))
end

local function safelySet(control, value)
    if control and type(control.Set) == "function" then
        pcall(control.Set, control, value, true)
    end
end

local function snapshotConfig()
    local visual = {}
    for key, value in pairs(ov.settings) do
        visual[key] = {enabled = value.enabled, health = value.health, range = value.range, color = colorArray(value.color)}
    end
    return {
        version = 1,
        beta = table.clone(beta.settings),
        camera = {extendedZoom = state.extendedZoom, maxDistance = state.maxDistance, fov = state.fov, sensitivity = state.sensitivity, firstPerson = state.firstPerson},
        visual = visual,
        misc = {stamina = playerLab.stamina, holdStamina = playerLab.holdStamina, jump = playerLab.jump}
    }
end

local function applyConfig(config)
    if type(config) ~= "table" or config.version ~= 1 then return false end
    local camera = config.camera
    if type(camera) == "table" then
        state.maxDistance = math.clamp(tonumber(camera.maxDistance) or 320, 176, 5000)
        state.fov = math.clamp(tonumber(camera.fov) or 75, 55, 110)
        state.sensitivity = math.clamp(tonumber(camera.sensitivity) or 0.23, 0.08, 0.6)
        state.extendedZoom = camera.extendedZoom == true
        safelySet(state.zoomSlider, state.maxDistance)
        safelySet(state.fovSlider, state.fov)
        safelySet(state.sensitivitySlider, state.sensitivity)
        safelySet(state.zoomToggle, state.extendedZoom)
        applyZoom()
        setFirstPerson(camera.firstPerson == true)
        safelySet(state.firstPersonToggle, state.firstPerson)
    end
    if type(config.visual) == "table" then
        for name, values in pairs(config.visual) do
            local setting = ov.settings[name]
            if setting and type(values) == "table" then
                setting.enabled = values.enabled == true
                setting.health = values.health ~= false
                setting.range = math.clamp(tonumber(values.range) or 5000, 100, 5000)
                setting.color = decodeColor(values.color, setting.color)
                local controls = ov.controls and ov.controls[name]
                if controls then
                    safelySet(controls.enabled, setting.enabled)
                    safelySet(controls.health, setting.health)
                    safelySet(controls.range, setting.range)
                    safelySet(controls.color, setting.color)
                end
            end
        end
    end
    if type(config.misc) == "table" then
        playerLab.stamina = math.clamp(tonumber(config.misc.stamina) or 100, 0, 100)
        playerLab.holdStamina = config.misc.holdStamina == true
        playerLab.jump = config.misc.jump == true
        state.allowJump = playerLab.jump
        safelySet(playerLab.staminaControl, playerLab.stamina)
        safelySet(playerLab.lockControl, playerLab.holdStamina)
        safelySet(playerLab.jumpControl, playerLab.jump)
        if playerLab.holdStamina then setStamina() end
        if playerLab.jump then applyJump() else restoreJump() end
    end
    if type(config.beta) == "table" then
        local values = config.beta
        for name, original in pairs(beta.settings) do
            local value = values[name]
            if type(original) == "boolean" and type(value) == "boolean" then
                beta.settings[name] = value
                safelySet(beta.controls[name], value)
            elseif type(original) == "number" and type(value) == "number" then
                beta.settings[name] = value
                safelySet(beta.controls[name], value)
            end
        end
        beta.settings.clockTime = math.clamp(beta.settings.clockTime, 0, 24)
        setAutoSprint(beta.settings.autoSprint)
        task.spawn(setLowGraphics, beta.settings.lowGraphics)
        setTimeOverride(beta.settings.changeTime)
    end
    return true
end

local function saveConfig()
    if type(writefile) ~= "function" then
        notify("Config: writefile unavailable")
        return
    end
    local ok, data = pcall(http.JSONEncode, http, snapshotConfig())
    if not ok then
        notify("Config encoding failed")
        return
    end
    local saved = pcall(writefile, configPath(), data)
    notify(if saved then "Config saved: " .. normalizeProfile(beta.profile) else "Config save failed")
end

local function loadConfig()
    if type(readfile) ~= "function" then
        notify("Config: readfile unavailable")
        return
    end
    local success, content = pcall(readfile, configPath())
    if not success or type(content) ~= "string" then
        notify("Config not found: " .. normalizeProfile(beta.profile))
        return
    end
    local decoded, config = pcall(http.JSONDecode, http, content)
    if not decoded or not applyConfig(config) then
        notify("Config invalid")
        return
    end
    notify("Config loaded: " .. normalizeProfile(beta.profile))
end

tab:CreateSection({name = "Performance"})
beta.controls.lowGraphics = tab:CreateToggle({
    name = "Low Graphics Mode",
    value = false,
    forgetState = true,
    callback = function(value)
        task.spawn(setLowGraphics, value == true)
    end
})

tab:CreateSection({name = "Time"})
beta.controls.changeTime = tab:CreateToggle({
    name = "Change Time",
    value = false,
    forgetState = true,
    callback = setTimeOverride
})
beta.controls.clockTime = tab:CreateSlider({
    name = "Clock Time",
    range = {0, 24},
    increment = 0.5,
    value = beta.settings.clockTime,
    suffix = " h",
    forgetState = true,
    callback = function(value)
        beta.settings.clockTime = math.clamp(tonumber(value) or 12, 0, 24)
        if beta.settings.changeTime then
            updateTimeMode()
        end
    end
})

statsTab:CreateSection({name = "Movement Helpers"})
beta.controls.autoSprint = statsTab:CreateToggle({
    name = "Auto Sprint",
    value = false,
    forgetState = true,
    callback = setAutoSprint
})

statsTab:CreateSection({name = "Configurations"})
statsTab:CreateInput({
    name = "Profile Name",
    placeholder = "default",
    value = "default",
    forgetState = true,
    callback = function(value)
        beta.profile = normalizeProfile(value)
    end
})
statsTab:CreateButton({
    name = "Save Config",
    callback = saveConfig
})
statsTab:CreateButton({
    name = "Load Config",
    callback = loadConfig
})

task.spawn(function()
    local nextSprint = 0
    local nextTime = 0
    while state.active and beta.active do
        local now = os.clock()
        if now >= nextSprint then
            nextSprint = now + 0.18
            pcall(stepAutoSprint)
        end
        if now >= nextTime then
            nextTime = now + 2.5
            if beta.settings.changeTime then
                local atmo = controller("Atmosphere")
                if beta.timeMode ~= "native" then
                    pcall(updateTimeMode)
                elseif atmo and type(atmo.current) == "function" then
                    local ok, info = pcall(atmo.current)
                    if ok and type(info) == "table" and (type(info.override) ~= "table" or info.override.time ~= timePreset(beta.settings.clockTime) or info.override.place ~= info.place) then
                        pcall(updateTimeMode)
                    end
                end
            end
        end
        task.wait(0.06)
    end
end)

local oldAddonCleanup = state.addonCleanup
state.addonCleanup = function()
    beta.active = false
    setAutoSprint(false)
    setTimeOverride(false)
    setLowGraphics(false)
    for _, connection in ipairs(beta.connections) do
        connection:Disconnect()
    end
    if type(oldAddonCleanup) == "function" then
        oldAddonCleanup()
    end
end


local weaponTab = window:CreateTab({name = "Weapon"})
local wc = {
    active = true,
    accuracy = false,
    spread = false,
    autoMelee = false,
    showMeleeRange = true,
    targetRange = 850,
    targetPosition = nil,
    meleeDirection = nil,
    meleeUntil = 0,
    nextSwing = 0,
    nextHookCheck = 0,
    lastDirection = nil,
    lastShot = 0,
    library = nil
}
local retiredHooks = rawget(environment, "MoonCombatHooks")
if type(retiredHooks) == "table" then retiredHooks.current = nil end
local hooks = rawget(environment, "MoonCombatHooksV2")
if type(hooks) ~= "table" then
    hooks = {namecallInstalled = false, shotInstalled = false, pelletsInstalled = false}
    environment.MoonCombatHooksV2 = hooks
end
hooks.current = wc

local function weaponDefinitions()
    if wc.library then return wc.library end
    local rep = game:GetService("ReplicatedStorage")
    local hush = rep:FindFirstChild("Hush")
    local shared = hush and hush:FindFirstChild("Shared")
    local module = shared and shared:FindFirstChild("Weapons")
    if not module then return nil end
    local ok, value = pcall(require, module)
    if ok and type(value) == "table" then
        wc.library = value
        return value
    end
    return nil
end

local function aliveZombieTarget(origin, range)
    local zombies = controller("ZombieRender")
    if not zombies or type(zombies.targets) ~= "function" then return nil end
    local ok, entries = pcall(zombies.targets, origin, range)
    if not ok or type(entries) ~= "table" then return nil end
    local best, bestDistance
    for _, entry in pairs(entries) do
        if type(entry) == "table" and typeof(entry.position) == "Vector3" and entry.visible ~= false then
            local distance = (entry.position - origin).Magnitude
            if distance > 0.5 and distance <= range and (not bestDistance or distance < bestDistance) then
                best = entry.position
                bestDistance = distance
            end
        end
    end
    return best
end

local function zombieHead(entry)
    local position = entry.position
    if typeof(position) ~= "Vector3" then return nil end
    local cache = wc.zombieTypes
    if cache == nil then
        local rep = game:GetService("ReplicatedStorage")
        local hush = rep:FindFirstChild("Hush")
        local shared = hush and hush:FindFirstChild("Shared")
        local module = shared and shared:FindFirstChild("ZombieTypes")
        if module then
            local ok, result = pcall(require, module)
            if ok and type(result) == "table" then
                cache = result
                wc.zombieTypes = cache
            end
        end
    end
    local definition
    if type(cache) == "table" then
        if type(cache.byIndex) == "table" then
            definition = cache.byIndex[entry.typeId]
        end
        if not definition and type(cache.byId) == "table" then
            definition = cache.byId[entry.typeId]
        end
    end
    local height = if type(definition) == "table" then tonumber(definition.height) or 5.9 else 5.9
    local headY = if type(definition) == "table" then tonumber(definition.headY) or height * 0.9 else 5.35
    local offset = math.clamp(headY - height * 0.62, -0.5, 3)
    return position + Vector3.new(0, offset, 0)
end

local function shotDirection(origin, original, active)
    if typeof(origin) ~= "Vector3" then return nil end
    local zombies = controller("ZombieRender")
    if not zombies or type(zombies.targets) ~= "function" then return nil end
    local ok, entries = pcall(zombies.targets, origin, active.targetRange)
    if not ok or type(entries) ~= "table" then return nil end
    local best, position, nearest
    for _, item in pairs(entries) do
        if type(item) == "table" and typeof(item.position) == "Vector3" and item.visible ~= false then
            local head = zombieHead(item)
            local delta = head - origin
            local distance = delta.Magnitude
            if distance > 1 and distance <= active.targetRange and (not nearest or distance < nearest) then
                nearest = distance
                best = delta.Unit
                position = head
            end
        end
    end
    return best, position
end
hooks.resolveShot = shotDirection

local function refreshShotTarget()
    wc.precomputed = nil
    wc.targetPosition = nil
    local input = controller("Input")
    if not wc.active or not wc.accuracy then
        if wc.aimSet and input and type(input.setAimOverride) == "function" then
            pcall(input.setAimOverride, nil)
        end
        wc.aimSet = false
        return
    end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not input then return end
    local origin = root.Position + Vector3.new(0, 1.2, 0)
    local direction, position = shotDirection(origin, nil, wc)
    wc.precomputed = direction
    wc.targetPosition = position
    if type(input.setAimOverride) == "function" then
        if position then
            if not wc.aimSet or not wc.lastAim or (wc.lastAim - position).Magnitude > 0.2 or os.clock() - (wc.lastAimAt or 0) > 0.3 then
                local success = pcall(input.setAimOverride, position)
                if success then
                    wc.aimSet = true
                    wc.lastAim = position
                    wc.lastAimAt = os.clock()
                end
            end
        elseif wc.aimSet then
            pcall(input.setAimOverride, nil)
            wc.aimSet = false
        end
    end
end

task.spawn(function()
    while wc.active and state.active do
        pcall(refreshShotTarget)
        task.wait(0.07)
    end
end)


local weaponFx = Instance.new("Folder")
weaponFx.Name = "HushWeaponVisuals"
weaponFx.Parent = workspace
local function drawShotBeam(origin, target)
    if not wc.active or typeof(origin) ~= "Vector3" or typeof(target) ~= "Vector3" then return end
    local folder = Instance.new("Folder")
    folder.Parent = weaponFx
    local a = Instance.new("Part")
    a.Anchored = true
    a.CanCollide = false
    a.CanQuery = false
    a.CanTouch = false
    a.Transparency = 1
    a.Size = Vector3.new(0.1, 0.1, 0.1)
    a.Position = origin
    a.Parent = folder
    local b = a:Clone()
    b.Position = target
    b.Parent = folder
    local at0 = Instance.new("Attachment")
    at0.Parent = a
    local at1 = Instance.new("Attachment")
    at1.Parent = b
    local beam = Instance.new("Beam")
    beam.Attachment0 = at0
    beam.Attachment1 = at1
    beam.Width0 = 0.12
    beam.Width1 = 0.04
    beam.FaceCamera = true
    beam.Color = ColorSequence.new(Color3.fromRGB(100, 230, 255))
    beam.LightEmission = 1
    beam.Parent = folder
    game:GetService("Debris"):AddItem(folder, 0.3)
end

local function installNamecall()
    if hooks.namecallInstalled then return true end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then return false end
    local wrapper = function(self, ...)
        local active = hooks.current
        if active and active.active and getnamecallmethod() == "FireServer" and typeof(self) == "Instance" and self.ClassName == "RemoteEvent" and (self.Name == "combat.fire" or self.Name == "combat.melee") then
            local args = table.pack(...)
            local payload = args[1]
            if type(payload) == "table" then
                if self.Name == "combat.fire" and active.accuracy then
                    local modified = table.clone(payload)
                    active.lastDirection = nil
                    local direction = active.precomputed
                    if typeof(direction) == "Vector3" then
                        modified.d = direction
                        if type(modified.ay) == "number" then
                            modified.ay = math.atan2(-direction.X, -direction.Z)
                        end
                        active.lastDirection = direction
                        active.lastShot = os.clock()
                        args[1] = modified
                        return hooks.namecallOriginal(self, table.unpack(args, 1, args.n))
                    end
                elseif self.Name == "combat.melee" and active.autoMelee and active.meleeDirection and os.clock() <= active.meleeUntil then
                    local modified = table.clone(payload)
                    modified.d = active.meleeDirection
                    active.meleeDirection = nil
                    active.lastMeleeSent = os.clock()
                    args[1] = modified
                    return hooks.namecallOriginal(self, table.unpack(args, 1, args.n))
                end
            end
        end
        return hooks.namecallOriginal(self, ...)
    end
    if type(newcclosure) == "function" then
        local ok, value = pcall(newcclosure, wrapper)
        if ok and type(value) == "function" then wrapper = value end
    end
    local ok, original = pcall(hookmetamethod, game, "__namecall", wrapper)
    if ok and type(original) == "function" then
        hooks.namecallOriginal = original
        hooks.namecallInstalled = true
    end
    return hooks.namecallInstalled
end

local function installSpreadHook()
    local library = weaponDefinitions()
    if not library then return false end
    if not hooks.shotInstalled and type(library.shotDir) == "function" then
        local original = library.shotDir
        local function shotWrapper(direction, amount, seed)
            local active = hooks.current
            if active and active.active then
                if active.accuracy and active.lastDirection and os.clock() - active.lastShot < 0.3 then
                    return active.lastDirection
                end
                if active.spread and typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
                    return direction.Unit
                end
            end
            return hooks.shotOriginal(direction, amount, seed)
        end
        if type(hookfunction) == "function" then
            local ok, previous = pcall(hookfunction, original, shotWrapper)
            if ok and type(previous) == "function" then
                hooks.shotOriginal = previous
                hooks.shotInstalled = true
            end
        end
        if not hooks.shotInstalled then
            hooks.shotOriginal = original
            library.shotDir = shotWrapper
            hooks.shotInstalled = true
        end
    end
    if not hooks.pelletsInstalled and type(library.pelletDirs) == "function" then
        local original = library.pelletDirs
        local function pelletWrapper(direction, amount, count, seed)
            local active = hooks.current
            if active and active.active and active.spread and typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
                local rays = {}
                for i = 1, math.clamp(math.floor(tonumber(count) or 1), 1, 24) do
                    rays[i] = direction.Unit
                end
                return rays
            end
            return hooks.pelletsOriginal(direction, amount, count, seed)
        end
        if type(hookfunction) == "function" then
            local ok, previous = pcall(hookfunction, original, pelletWrapper)
            if ok and type(previous) == "function" then
                hooks.pelletsOriginal = previous
                hooks.pelletsInstalled = true
            end
        end
        if not hooks.pelletsInstalled then
            hooks.pelletsOriginal = original
            library.pelletDirs = pelletWrapper
            hooks.pelletsInstalled = true
        end
    end
    return hooks.shotInstalled
end

local function meleeCallbacks()
    if wc.cachedMeleeCallbacks and wc.cachedCharacter == player.Character then
        return wc.cachedMeleeCallbacks
    end
    if os.clock() < (wc.nextMeleeSearch or 0) then return nil end
    wc.nextMeleeSearch = os.clock() + 0.35
    local gun = controller("WeaponClient")
    if gun and type(gun.init) == "function" and type(debug) == "table" and type(debug.getupvalues) == "function" then
        local ok, values = pcall(debug.getupvalues, gun.init)
        if ok and type(values) == "table" then
            for name, value in pairs(values) do
                if name == "swing" and type(value) == "function" then
                    wc.cachedMeleeCallbacks = {{b = value}}
                    wc.cachedCharacter = player.Character
                    return wc.cachedMeleeCallbacks
                end
            end
        end
    end
    local input = controller("Input")
    if not input or type(input.bind) ~= "function" or type(debug) ~= "table" then return nil end
    if type(debug.getupvalues) == "function" then
        local ok, values = pcall(debug.getupvalues, input.bind)
        if ok and type(values) == "table" then
            for _, value in pairs(values) do
                if type(value) == "table" and type(value.melee) == "table" then
                    wc.cachedMeleeCallbacks = value.melee
                    wc.cachedCharacter = player.Character
                    return wc.cachedMeleeCallbacks
                end
            end
        end
    end
    if type(debug.getupvalue) == "function" then
        for index = 1, 12 do
            local ok, first, second = pcall(debug.getupvalue, input.bind, index)
            if ok then
                if type(first) == "table" and type(first.melee) == "table" then
                    wc.cachedMeleeCallbacks = first.melee
                    wc.cachedCharacter = player.Character
                    return wc.cachedMeleeCallbacks
                end
                if type(second) == "table" and type(second.melee) == "table" then
                    wc.cachedMeleeCallbacks = second.melee
                    wc.cachedCharacter = player.Character
                    return wc.cachedMeleeCallbacks
                end
            end
        end
    end
    return nil
end

local function autoMeleeStep()
    if not wc.autoMelee or not beta.active or player:GetAttribute("Place") ~= "Raid" or os.clock() < wc.nextSwing then return end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or character:GetAttribute("Dead") == true or character:GetAttribute("Downed") == true then return end
    local library = weaponDefinitions()
    if not library then return end
    local weaponId = character:GetAttribute("Weapon")
    local stats = library.SHOVE
    if type(weaponId) == "string" and type(library.stats) == "function" then
        local ok, candidate = pcall(library.stats, weaponId, character:GetAttribute("WeaponMods"))
        if ok and type(candidate) == "table" and candidate.kind == "melee" then
            stats = candidate
        end
    end
    if type(stats) ~= "table" then return end
    local stamina = character.GetAttribute(character, "Stamina")
    if character.GetAttribute(character, "Exhausted") == true or (type(stamina) == "number" and stamina < (tonumber(stats.staminaCost) or 10) * 0.5) then return end
    local range = tonumber(stats.meleeRange) or tonumber(stats.range) or 4.5
    local zombies = controller("ZombieRender")
    if not zombies or type(zombies.targets) ~= "function" then return end
    local ok, entries = pcall(zombies.targets, root.Position, range + 3)
    if not ok or type(entries) ~= "table" then return end
    local bestDirection, bestDistance
    for _, entry in pairs(entries) do
        if type(entry) == "table" and typeof(entry.position) == "Vector3" then
            local relative = entry.position - root.Position
            local planar = Vector3.new(relative.X, 0, relative.Z)
            local distance = planar.Magnitude
            if math.abs(relative.Y) <= 9 then
                local direction = if distance > 0.05 then planar.Unit else root.CFrame.LookVector
                local accepted, inRange = pcall(library.meleeInArc, stats, relative, direction, 1.2)
                if accepted and inRange and (not bestDistance or distance < bestDistance) then
                    bestDistance = distance
                    bestDirection = direction
                end
            end
        end
    end
    if not bestDirection then
        wc.meleeDirection = nil
        return
    end
    local input = controller("Input")
    if input and type(input.setAimOverride) == "function" then
        pcall(input.setAimOverride, root.Position + bestDirection * 8)
    end
    local callbacks = meleeCallbacks()
    if not callbacks then return end
    for _, entry in ipairs(callbacks) do
        if type(entry) == "table" and type(entry.b) == "function" then
            wc.meleeDirection = bestDirection
            wc.meleeUntil = os.clock() + math.max(0.5, tonumber(stats.meleeTime) or 0.8)
            local previousSent = wc.lastMeleeSent
            local success = pcall(entry.b)
            local actuallyFired = not hooks.namecallInstalled or (wc.lastMeleeSent ~= nil and wc.lastMeleeSent ~= previousSent)
            if success and actuallyFired then
                local cycle = tonumber(stats.meleeTime) or 0.9
                if type(library.meleeCycle) == "function" then
                    local valid, delayValue = pcall(library.meleeCycle, stats, stamina)
                    if valid and type(delayValue) == "number" then cycle = delayValue end
                end
                wc.nextSwing = os.clock() + 0.045
                return
            end
        end
    end
    wc.nextSwing = os.clock() + 0.065
end

weaponTab:CreateSection({name = "Shooting"})
wc.accuracyControl = weaponTab:CreateToggle({
    name = "Shot Accuracy",
    value = false,
    forgetState = true,
    callback = function(value)
        wc.accuracy = value == true
        if value and not installNamecall() then
            wc.accuracy = false
            notify("Shot Accuracy requires hookmetamethod")
        end
        if value then installSpreadHook() end
    end
})
wc.spreadControl = weaponTab:CreateToggle({
    name = "Remove Spread (Client)",
    value = false,
    forgetState = true,
    callback = function(value)
        wc.spread = value == true
        if value then
            local netReady = installNamecall()
            local localReady = installSpreadHook()
            if not netReady or not localReady then
                wc.spread = false
                notify("Remove Spread unavailable in this runtime")
            end
        end
    end
})
task.spawn(function()
    local lastGun, lastAmmo
    while state.active and wc.active do
        if wc.accuracy and typeof(wc.targetPosition) == "Vector3" then
            local gun = controller("WeaponClient")
            if gun and type(gun.state) == "function" then
                local ok, result = pcall(gun.state)
                if ok and type(result) == "table" then
                    local ammo = tonumber(result.ammo)
                    local name = result.weapon
                    if name == lastGun and ammo and lastAmmo and ammo < lastAmmo then
                        local c = player.Character
                        local root = c and c:FindFirstChild("HumanoidRootPart")
                        if root then
                            task.defer(drawShotBeam, root.Position + Vector3.new(0, 1.3, 0), wc.targetPosition)
                        end
                    end
                    lastAmmo = ammo
                    lastGun = name
                end
            end
        else
            lastGun = nil
            lastAmmo = nil
        end
        task.wait(0.07)
    end
end)

local ring = {}
local function showMeleeRing()
    if not wc.showMeleeRange then return false end
    local c = player.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local lib = weaponDefinitions()
    if not lib then return false end
    local id = c:GetAttribute("Weapon")
    local stats = lib.SHOVE
    if type(id) == "string" and id ~= "" and id ~= "fists" then
        local ok, value = pcall(lib.stats, id, c:GetAttribute("WeaponMods"))
        if not ok or type(value) ~= "table" or value.kind ~= "melee" then return false end
        stats = value
    end
    if not stats then return false end
    local radius = (tonumber(stats.meleeRange) or 4.5) + 1.1
    local center = root.Position - Vector3.new(0, 2.6, 0)
    for i = 1, 36 do
        local part = ring[i]
        if not part then
            part = Instance.new("Part")
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.CastShadow = false
            part.Material = Enum.Material.Neon
            part.Name = "MeleeRadius"
            part.Parent = weaponFx
            ring[i] = part
        end
        local a = (i - 1) * 2 * math.pi / 36
        local b = i * 2 * math.pi / 36
        local first = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
        local second = center + Vector3.new(math.cos(b) * radius, 0, math.sin(b) * radius)
        part.CFrame = CFrame.lookAt((first + second) * 0.5, second)
        part.Size = Vector3.new(0.085, 0.085, (first - second).Magnitude)
        part.Color = Color3.fromRGB(95, 220, 170)
        part.Transparency = 0.13
    end
    return true
end
task.spawn(function()
    while state.active and wc.active do
        local ok, show = pcall(showMeleeRing)
        if not ok or not show then
            for _, part in ipairs(ring) do part.Transparency = 1 end
        end
        task.wait(0.12)
    end
end)

weaponTab:CreateSection({name = "Melee"})
wc.rangeControl = weaponTab:CreateToggle({
    name = "Show Melee Range",
    value = true,
    forgetState = true,
    callback = function(value)
        wc.showMeleeRange = value == true
        if not wc.showMeleeRange then
            for _, segment in ipairs(ring) do
                segment.Transparency = 1
            end
        end
    end
})
wc.meleeControl = weaponTab:CreateToggle({
    name = "Melee Aura",
    value = false,
    forgetState = true,
    callback = function(value)
        wc.autoMelee = value == true
        wc.nextSwing = 0
        wc.meleeDirection = nil
        if not value and not wc.accuracy then
            local input = controller("Input")
            if input and type(input.setAimOverride) == "function" then
                pcall(input.setAimOverride, nil)
            end
        end
        if value then
            if not installNamecall() then
                notify("360 melee targeting requires hookmetamethod")
            end
            if not meleeCallbacks() then
                notify("Auto Melee requires initialized Input callbacks")
            end
        end
    end
})
task.spawn(function()
    while state.active and wc.active do
        pcall(autoMeleeStep)
        task.wait(0.05)
    end
end)

local previousWeaponCleanup = state.addonCleanup
state.addonCleanup = function()
    wc.active = false
    wc.accuracy = false
    wc.spread = false
    wc.autoMelee = false
    wc.meleeDirection = nil
    local input = controller("Input")
    if input and type(input.setAimOverride) == "function" then
        pcall(input.setAimOverride, nil)
    end
    weaponFx:Destroy()
    if hooks.current == wc then hooks.current = nil end
    if type(previousWeaponCleanup) == "function" then
        previousWeaponCleanup()
    end
end


state.resetAll = function()
    wc.accuracy = false
    wc.spread = false
    wc.autoMelee = false
    wc.showMeleeRange = false
    wc.targetPosition = nil
    wc.meleeDirection = nil
    wc.nextSwing = 0
    local input = controller("Input")
    if input and type(input.setAimOverride) == "function" then
        pcall(input.setAimOverride, nil)
    end
    for _, segment in ipairs(ring) do
        segment.Transparency = 1
    end
    safelySet(wc.accuracyControl, false)
    safelySet(wc.spreadControl, false)
    safelySet(wc.meleeControl, false)
    safelySet(wc.rangeControl, false)

    for key, settings in pairs(ov.settings) do
        settings.enabled = false
        settings.range = if key == "containers" then 3500 else 5000
        settings.color = if key == "players" then Color3.fromRGB(70, 190, 255) elseif key == "enemies" then Color3.fromRGB(255, 85, 85) else Color3.fromRGB(255, 195, 75)
        settings.health = key ~= "containers"
        local controls = ov.controls[key]
        if controls then
            safelySet(controls.enabled, false)
            safelySet(controls.range, settings.range)
            safelySet(controls.color, settings.color)
            safelySet(controls.health, settings.health)
        end
    end
    pcall(scan)

    playerLab.holdStamina = false
    playerLab.staminaUntil = 0
    playerLab.stamina = 100
    playerLab.jump = false
    for character, saved in pairs(playerLab.saved) do
        if character and character.Parent then
            pcall(function()
                character:SetAttribute("Stamina", saved.value)
                character:SetAttribute("Exhausted", saved.exhausted)
            end)
        end
        playerLab.saved[character] = nil
    end
    state.allowJump = false
    restoreJump()
    safelySet(playerLab.staminaControl, 100)
    safelySet(playerLab.lockControl, false)
    safelySet(playerLab.jumpControl, false)

    setAutoSprint(false)
    setTimeOverride(false)
    setLowGraphics(false)
    beta.settings.autoSprint = false
    beta.settings.changeTime = false
    beta.settings.lowGraphics = false
    beta.settings.clockTime = 12
    safelySet(beta.controls.autoSprint, false)
    safelySet(beta.controls.changeTime, false)
    safelySet(beta.controls.lowGraphics, false)
    safelySet(beta.controls.clockTime, 12)

    setFirstPerson(false)
    state.extendedZoom = false
    state.maxDistance = 320
    state.fov = 75
    state.sensitivity = 0.23
    applyZoom()
    safelySet(state.firstPersonToggle, false)
    safelySet(state.zoomToggle, false)
    safelySet(state.zoomSlider, 320)
    safelySet(state.fovSlider, 75)
    safelySet(state.sensitivitySlider, 0.23)
    notify("All Moon settings reset")
end
