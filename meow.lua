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

local previous = rawget(environment, "HushBetaCameraControls")
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
            Title = "moon Beta",
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

rs:BindToRenderStep("HushBetaFirstPerson", Enum.RenderPriority.Camera.Value + 4, renderFirstPerson)
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
    rs:UnbindFromRenderStep("HushBetaFirstPerson")
    for _, connection in ipairs(state.connections) do
        connection:Disconnect()
    end
    if state.window then
        pcall(function()
            state.window:Unload()
        end)
    end
    if rawget(environment, "HushBetaCameraControls") == state then
        environment.HushBetaCameraControls = nil
    end
end

state.cleanup = cleanup
environment.HushBetaCameraControls = state

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
        name = "moon Beta",
        subtitle = "Visual & Misc",
        sidebarLayout = true,
        theme = "cobalt",
        showName = "moon Beta"
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
    flag = "HushBetaMaxZoom",
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

tab:CreateSlider({
    name = "Maximum Distance",
    flag = "HushBetaZoomDistance",
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
    flag = "HushBetaFirstPerson",
    forgetState = true,
    value = false,
    callback = function(value)
        setFirstPerson(value)
    end
})

tab:CreateSlider({
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

tab:CreateSlider({
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
    name = "Close",
    callback = cleanup
})


local cs = game:GetService("CollectionService")
local ov = {
    active = true,
    root = Instance.new("Folder"),
    entries = {},
    ids = setmetatable({}, {__mode = "k"}),
    nextId = 0,
    maxHighlights = 230,
    limit = 500,
    settings = {
        players = {enabled = false, health = true, range = 5000, color = Color3.fromRGB(70, 190, 255)},
        enemies = {enabled = false, health = true, range = 5000, color = Color3.fromRGB(255, 85, 85)}
    }
}
ov.root.Name = "HushBetaVisuals"
ov.root.Parent = workspace

local function bodyPart(target)
    if not target or not target.Parent then
        return nil
    end
    if target:IsA("BasePart") then
        return target
    end
    if target:IsA("Model") then
        return target.PrimaryPart or target:FindFirstChild("HumanoidRootPart", true) or target:FindFirstChild("Head", true) or target:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function readHealth(target, kind)
    for _, keys in ipairs({{"Hp", "MaxHp"}, {"Health", "MaxHealth"}}) do
        local value = target:GetAttribute(keys[1])
        local maximum = target:GetAttribute(keys[2])
        if type(value) == "number" and type(maximum) == "number" and maximum > 0 and value == value then
            return math.clamp(value, 0, maximum), maximum
        end
    end
    if kind == "players" then
        local humanoid = target:IsA("Model") and target:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.MaxHealth > 0 then
            return humanoid.Health, humanoid.MaxHealth
        end
    end
    return nil
end

local function destroyDrawing(object)
    if not object then return end
    local ok = pcall(function() object:Remove() end)
    if not ok then
        pcall(function() object:Destroy() end)
    end
end

local function clearEntry(entry)
    if entry.highlight then
        entry.highlight:Destroy()
    end
    if entry.outline then
        entry.outline:Destroy()
    end
    if entry.billboard then
        entry.billboard:Destroy()
    end
    destroyDrawing(entry.back)
    destroyDrawing(entry.fill)
end

local function candidate(list, found, target, kind, anchor)
    if not target or not target:IsDescendantOf(workspace) or found[target] then
        return
    end
    local setting = ov.settings[kind]
    if not setting.enabled then
        return
    end
    if kind == "enemies" and (target:GetAttribute("Dead") == true or target:GetAttribute("Corpse") == true) then
        return
    end
    local part = anchor or bodyPart(target)
    local camera = workspace.CurrentCamera
    if not camera or not part or part.Position.Y < -1000 then
        return
    end
    local distance = (camera.CFrame.Position - part.Position).Magnitude
    if distance > setting.range then
        return
    end
    if not ov.ids[target] then
        ov.nextId += 1
        ov.ids[target] = ov.nextId
    end
    table.insert(list, {target = target, part = part, kind = kind, distance = distance, id = ov.ids[target]})
    found[target] = true
end

local function scan()
    local found = {}
    local choices = {}
    if ov.settings.players.enabled then
        for _, other in ipairs(p:GetPlayers()) do
            local character = other.Character
            if other ~= player and character then
                candidate(choices, found, character, "players")
            end
        end
    end
    if ov.settings.enemies.enabled then
        local localFolder = workspace:FindFirstChild("HushLocal")
        local zombies = localFolder and localFolder:FindFirstChild("Zombies")
        if zombies then
            for _, instance in ipairs(zombies:GetDescendants()) do
                if instance:IsA("Model") then
                    local nested = false
                    local ancestor = instance.Parent
                    while ancestor and ancestor ~= zombies do
                        if ancestor:IsA("Model") then
                            nested = true
                            break
                        end
                        ancestor = ancestor.Parent
                    end
                    if not nested then
                        candidate(choices, found, instance, "enemies")
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
    table.sort(choices, function(a, b)
        if a.kind ~= b.kind then
            return a.kind == "players"
        end
        if math.abs(a.distance - b.distance) >= 8 then
            return a.distance < b.distance
        end
        return a.id < b.id
    end)
    local selected = {}
    for index, choice in ipairs(choices) do
        if index > ov.limit then
            break
        end
        selected[choice.target] = true
        local entry = ov.entries[choice.target]
        if not entry then
            entry = {target = choice.target}
            ov.entries[choice.target] = entry
        end
        entry.part = choice.part
        entry.kind = choice.kind
        local setting = ov.settings[choice.kind]
        if index <= ov.maxHighlights then
            if entry.outline then
                entry.outline:Destroy()
                entry.outline = nil
            end
            if not entry.highlight then
                local highlight = Instance.new("Highlight")
                highlight.Name = "HushBetaHighlight"
                highlight.FillTransparency = 0.8
                highlight.OutlineTransparency = 0
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.Adornee = choice.target
                highlight.Parent = ov.root
                entry.highlight = highlight
            end
            entry.highlight.FillColor = setting.color
            entry.highlight.OutlineColor = setting.color
        else
            if entry.highlight then
                entry.highlight:Destroy()
                entry.highlight = nil
            end
            if not entry.outline then
                local outline = Instance.new("SelectionBox")
                outline.Name = "HushBetaOutline"
                outline.AlwaysOnTop = true
                outline.LineThickness = 0.04
                outline.SurfaceTransparency = 1
                outline.Parent = ov.root
                entry.outline = outline
            end
            entry.outline.Adornee = choice.part
            entry.outline.Color3 = setting.color
        end
    end
    for target, entry in pairs(ov.entries) do
        if not selected[target] then
            clearEntry(entry)
            ov.entries[target] = nil
        end
    end
end

local function ensureBar(entry)
    if entry.back or entry.billboard then
        return
    end
    if type(Drawing) == "table" and type(Drawing.new) == "function" then
        local back, fill
        local success = pcall(function()
            back = Drawing.new("Square")
            fill = Drawing.new("Square")
            back.Filled = true
            fill.Filled = true
            back.Color = Color3.fromRGB(15, 19, 25)
            back.Transparency = 1
            fill.Transparency = 1
            back.Visible = false
            fill.Visible = false
        end)
        if success then
            entry.back = back
            entry.fill = fill
            return
        end
        destroyDrawing(back)
        destroyDrawing(fill)
    end
    local gui = Instance.new("BillboardGui")
    gui.Name = "HushBetaHP"
    gui.Size = UDim2.fromOffset(70, 11)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 2.9, 0)
    gui.AlwaysOnTop = true
    gui.Enabled = false
    gui.Adornee = entry.part
    gui.Parent = ov.root
    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BorderSizePixel = 0
    bg.BackgroundColor3 = Color3.fromRGB(15, 19, 25)
    bg.Parent = gui
    local fg = Instance.new("Frame")
    fg.Position = UDim2.fromOffset(1, 1)
    fg.Size = UDim2.new(1, -2, 1, -2)
    fg.BorderSizePixel = 0
    fg.Parent = bg
    entry.billboard = gui
    entry.billboardFill = fg
end

local function updateBars()
    local camera = workspace.CurrentCamera
    if not camera then return end
    for _, entry in pairs(ov.entries) do
        local setting = ov.settings[entry.kind]
        local hp, maximum = readHealth(entry.target, entry.kind)
        local visible = setting.health and hp ~= nil and entry.part and entry.part.Parent
        local screen, onScreen
        if visible then
            local head = entry.target:IsA("Model") and entry.target:FindFirstChild("Head", true)
            local worldPosition = head and head:IsA("BasePart") and (head.Position + Vector3.new(0, head.Size.Y / 2 + 0.6, 0)) or (entry.part.Position + Vector3.new(0, 2.7, 0))
            screen, onScreen = camera:WorldToViewportPoint(worldPosition)
            visible = onScreen and screen.Z > 0
        end
        if visible then
            ensureBar(entry)
        end
        if entry.back and entry.fill then
            if visible then
                local fraction = math.clamp(hp / maximum, 0, 1)
                local color = Color3.fromRGB(math.floor(245 * (1 - fraction)), math.floor(220 * fraction), 60)
                local pos = Vector2.new(screen.X - 27, screen.Y - 9)
                pcall(function()
                    entry.back.Position = pos
                    entry.back.Size = Vector2.new(54, 7)
                    entry.back.Visible = true
                    entry.fill.Position = pos + Vector2.new(1, 1)
                    entry.fill.Size = Vector2.new(52 * fraction, 5)
                    entry.fill.Color = color
                    entry.fill.Visible = true
                end)
            else
                pcall(function()
                    entry.back.Visible = false
                    entry.fill.Visible = false
                end)
            end
        elseif entry.billboard then
            entry.billboard.Adornee = entry.part
            entry.billboard.Enabled = visible == true
            if visible then
                local fraction = math.clamp(hp / maximum, 0, 1)
                entry.billboardFill.Size = UDim2.new(fraction, -2 * fraction, 1, -2)
                entry.billboardFill.BackgroundColor3 = Color3.fromRGB(math.floor(245 * (1 - fraction)), math.floor(220 * fraction), 60)
            end
        end
    end
end

tab:CreateSection({name = "Players"})
for _, definition in ipairs({{"players", "Players"}, {"enemies", "Enemies"}}) do
    local key = definition[1]
    local name = definition[2]
    local settings = ov.settings[key]
    if key == "enemies" then
        tab:CreateSection({name = "Enemies"})
    end
    tab:CreateToggle({
        name = name .. " ESP",
        value = false,
        forgetState = true,
        callback = function(value)
            settings.enabled = value == true
            scan()
        end
    })
    tab:CreateSlider({
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
    tab:CreateColorPicker({
        name = name .. " Color",
        color = settings.color,
        forgetState = true,
        callback = function(color)
            if typeof(color) == "Color3" then settings.color = color end
        end
    })
    tab:CreateToggle({
        name = name .. " HP Bars",
        value = true,
        forgetState = true,
        callback = function(value)
            settings.health = value == true
        end
    })
end

local renderElapsed = 0
local renderConnection = rs.RenderStepped:Connect(function(dt)
    renderElapsed += dt
    if renderElapsed >= 0.05 then
        renderElapsed = 0
        updateBars()
    end
end)
task.spawn(function()
    while state.active and ov.active do
        pcall(scan)
        task.wait(0.6)
    end
end)
state.visualCleanup = function()
    ov.active = false
    renderConnection:Disconnect()
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
    local registry = rawget(environment, "HushBetaStaminaHook")
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
        if type(checkcaller) == "function" and checkcaller() then
            return registry.original(self, ...)
        end
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
        environment.HushBetaStaminaHook = registry
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
        playerLab.saved[character] = {value = character:GetAttribute("Stamina")}
    end
    character:SetAttribute("Stamina", playerLab.stamina)
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
statsTab:CreateSlider({
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
statsTab:CreateToggle({
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
statsTab:CreateToggle({
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
    local registry = rawget(environment, "HushBetaStaminaHook")
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
            end)
        end
    end
    state.allowJump = false
    restoreJump()
end
