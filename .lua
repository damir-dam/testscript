local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/damir-dam/librarya/refs/heads/main/.lua"))()

-- Create the main window
local window = Library.new("Waypoint System", "WaypointConfig")

-- Set toggle key
window:SetToggleKey(Enum.KeyCode.RightControl)

-- Variables
local fpsBoostEnabled = false
local fpsOriginalSettings = {}
local fpsOriginalAssets = {}
local waypoints = {}
local waypointParts = {}
local running = false
local currentWaypointIndex = 1
local tweenSpeed = 16
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local tweenService = game:GetService("TweenService")
local currentTween = nil
local autoWalkThread = nil
local antiGravityForce = nil
local waitingInAir = false
local autoSpawnWaypoints = false
local spawnInterval = 0.5
local autoSpawnThread = nil
local managedWaypointIndex = nil
local managedWaypointColor = Color3.fromRGB(0, 255, 0)
local normalWaypointColor = Color3.fromRGB(255, 0, 0)
local defaultWaypointColor = Color3.fromRGB(255, 0, 0)

--------------------------------------------------
-- FPS BOOST FUNCTIONS
--------------------------------------------------

local function applyFPSBoost()

    fpsOriginalSettings.QualityLevel =
        settings():GetService("RenderSettings").QualityLevel

    settings():GetService("RenderSettings").QualityLevel = 1

    local lighting = game:GetService("Lighting")

    fpsOriginalSettings.GlobalShadows = lighting.GlobalShadows
    fpsOriginalSettings.Brightness = lighting.Brightness
    fpsOriginalSettings.FogEnd = lighting.FogEnd

    lighting.GlobalShadows = false
    lighting.Brightness = 1
    lighting.FogEnd = 1e10

    for _, obj in pairs(game:GetDescendants()) do

        if obj:IsA("ParticleEmitter")
        or obj:IsA("Trail")
        or obj:IsA("Beam")
        or obj:IsA("Smoke")
        or obj:IsA("Fire") then
            fpsOriginalAssets[obj] = obj.Enabled
            obj.Enabled = false
        end

        if obj:IsA("Texture") then
            fpsOriginalAssets[obj] = obj.Texture
            obj.Texture = ""
        end

        if obj:IsA("Decal") then
            fpsOriginalAssets[obj] = obj.Texture
            obj.Texture = ""
        end

        if obj:IsA("BasePart") then
            fpsOriginalAssets[obj] = {
                Material = obj.Material,
                Reflectance = obj.Reflectance
            }
            obj.Material = Enum.Material.Plastic
            obj.Reflectance = 0
        end
    end
end


local function restoreFPSBoost()

    if fpsOriginalSettings.QualityLevel then
        settings():GetService("RenderSettings").QualityLevel =
            fpsOriginalSettings.QualityLevel
    end

    local lighting = game:GetService("Lighting")

    lighting.GlobalShadows = fpsOriginalSettings.GlobalShadows or true
    lighting.Brightness = fpsOriginalSettings.Brightness or 2
    lighting.FogEnd = fpsOriginalSettings.FogEnd or 100000

    for obj, data in pairs(fpsOriginalAssets) do
        if obj and obj.Parent then

            if typeof(data) == "boolean" then
                obj.Enabled = data
            elseif typeof(data) == "string" then
                obj.Texture = data
            elseif typeof(data) == "table" then
                obj.Material = data.Material
                obj.Reflectance = data.Reflectance
            end
        end
    end

    fpsOriginalAssets = {}
end

-- Функция для создания визуального маркера
local function createWaypointVisual(position, index, waitTime, isManaged)
    local part = Instance.new("Part")
    part.Name = "Waypoint_" .. index
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(1.7, 1.7, 1.7)
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.ForceField
    part.Transparency = 0.3
    
    if isManaged then
        part.Color = managedWaypointColor
    else
        part.Color = normalWaypointColor
    end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "WaypointInfo"
    billboard.Size = UDim2.new(0, 100, 0, 40)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 100
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.Parent = part
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "Text"
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextStrokeTransparency = 0
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.TextSize = 14
    textLabel.Text = index .. (waitTime and waitTime > 0 and "\nwait(" .. waitTime .. ")" or "")
    textLabel.Parent = billboard
    
    part.Parent = workspace
    return part
end

-- Функция обновления визуалов
local function updateWaypointVisuals()
    for _, part in pairs(waypointParts) do
        if part and part.Parent then
            part:Destroy()
        end
    end
    waypointParts = {}
    
    for i, waypoint in ipairs(waypoints) do
        local isManaged = (i == managedWaypointIndex)
        local part = createWaypointVisual(waypoint.position, i, waypoint.waitTime, isManaged)
        table.insert(waypointParts, part)
    end
end

-- Функция для управления waypoint (Manage)
local function manageWaypoint(index)
    if index < 1 or index > #waypoints then
        print("Ошибка: Waypoint #" .. index .. " не существует!")
        return false
    end
    
    if managedWaypointIndex then
        normalWaypointColor = defaultWaypointColor
        managedWaypointIndex = nil
    end
    
    managedWaypointIndex = index
    normalWaypointColor = Color3.fromRGB(255, 0, 0)
    updateWaypointVisuals()
    print("Управление waypoint #" .. index .. " включено (зеленый)")
    return true
end

-- Функция для снятия управления waypoint (Unmanage)
local function unmanageWaypoint()
    if not managedWaypointIndex then
        print("Нет управляемого waypoint")
        return false
    end
    
    normalWaypointColor = defaultWaypointColor
    managedWaypointIndex = nil
    updateWaypointVisuals()
    print("Управление waypoint снято")
    return true
end

-- Функция для замены позиции управляемого waypoint
local function replaceManagedWaypoint()
    if not managedWaypointIndex then
        print("Ошибка: Нет управляемого waypoint для замены!")
        return false
    end
    
    local newPosition = root.Position
    local oldPosition = waypoints[managedWaypointIndex].position
    
    waypoints[managedWaypointIndex].position = newPosition
    updateWaypointVisuals()
    
    print(string.format("Waypoint #%d перемещен:", managedWaypointIndex))
    print("Старая позиция: " .. tostring(oldPosition))
    print("Новая позиция: " .. tostring(newPosition))
    return true
end

-- Функция для добавления waypoint с учетом управляемого
local function addWaypointWithManagement()
    local position = root.Position
    
    if managedWaypointIndex then
        replaceManagedWaypoint()
        unmanageWaypoint()
        return "replaced"
    else
        table.insert(waypoints, { position = position, waitTime = 0 })
        updateWaypointVisuals()
        return "added"
    end
end

-- Функция для создания антигравитационной силы
local function createAntiGravity()
    if not antiGravityForce or not antiGravityForce.Parent then
        antiGravityForce = Instance.new("BodyForce")
        antiGravityForce.Name = "AntiGravity"
        antiGravityForce.Force = Vector3.new(0, workspace.Gravity * root.AssemblyMass, 0)
        antiGravityForce.Parent = root
    end
    return antiGravityForce
end

-- Функция для удаления антигравитационной силы
local function removeAntiGravity()
    if antiGravityForce and antiGravityForce.Parent then
        antiGravityForce:Destroy()
        antiGravityForce = nil
    end
end

-- Функция для проверки, находится ли вейпоинт в воздухе
local function isWaypointInAir(position)
    local ray = Ray.new(position + Vector3.new(0, 10, 0), Vector3.new(0, -1000, 0))
    local part, hitPosition = workspace:FindPartOnRayWithIgnoreList(ray, {character})
    
    if not part or (position.Y - hitPosition.Y) > 5 then
        return true
    end
    return false
end

local function holdInAir(position, duration)
    if not running or not character or not root then return end
    
    waitingInAir = true
    root.Anchored = true -- Полная остановка физики
    
    local startTime = tick()
    while tick() - startTime < duration and running do
        task.wait(0.1)
    end
    
    root.Anchored = false
    waitingInAir = false
end

-- Старая функция добавления waypoint
local function addWaypoint()
    return addWaypointWithManagement() == "added"
end

-- Функция удаления всех маршрутных точек
local function removeAllWaypoints()
    running = false
    waitingInAir = false
    autoSpawnWaypoints = false
    managedWaypointIndex = nil
    normalWaypointColor = defaultWaypointColor
    
    if autoWalkThread then
        coroutine.close(autoWalkThread)
        autoWalkThread = nil
    end
    
    if autoSpawnThread then
        coroutine.close(autoSpawnThread)
        autoSpawnThread = nil
    end
    
    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end
    
    removeAntiGravity()
    waypoints = {}
    updateWaypointVisuals()
    currentWaypointIndex = 1
    
    if humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
    end
    
    if autoSpawnToggle then
        autoSpawnToggle:SetValue(false)
    end
    
    print("Все waypoints удалены")
end

-- Функция удаления последней маршрутной точки
local function removeLastWaypoint()
    if #waypoints > 0 then
        if managedWaypointIndex == #waypoints then
            unmanageWaypoint()
        end
        table.remove(waypoints, #waypoints)
        updateWaypointVisuals()
        print("Последний waypoint удален")
    end
end

local function goToWaypointTween(index)
    if not running or #waypoints == 0 or not waypoints[index] then return false end
    local waypoint = waypoints[index]
    local targetPos = waypoint.position
    
    local gyro = root:FindFirstChild("WaypointGyro")
    if not gyro then
        gyro = Instance.new("BodyGyro")
        gyro.Name = "WaypointGyro"
        gyro.Parent = root
    end

    gyro.P = 20000
    gyro.D = 500
    gyro.MaxTorque = Vector3.new(400000, 400000, 400000)
    
    humanoid.AutoRotate = false 
    -- Оставляем стандартное состояние для работы коллизии (стен)
    humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)

    local reached = false
    while running and not reached do
        local currentPos = root.Position
        local distance = (targetPos - currentPos).Magnitude
        
        -- Если почти дошли (0.5 студа для точности)
        if distance < 0.5 then 
            reached = true
            break
        end

        -- ВЫЧИСЛЯЕМ ФИКСИРОВАННЫЙ ШАГ (скорость * время)
        local deltaTime = task.wait()
        local direction = (targetPos - currentPos).Unit
        local moveStep = direction * (tweenSpeed * deltaTime)

        -- Двигаем через CFrame, чтобы игнорировать трение, но оставляем Velocity для коллизии
        if distance > moveStep.Magnitude then
            root.CFrame = root.CFrame + moveStep
        else
            root.CFrame = CFrame.new(targetPos) -- Доводка в центр
            reached = true
        end
        
        -- Поворот
        local lookTarget = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
        if (lookTarget - root.Position).Magnitude > 0.1 then
            gyro.CFrame = CFrame.new(root.Position, lookTarget)
        end
        
        -- Обнуляем физическую скорость, чтобы персонажа не "выстреливало"
        root.Velocity = Vector3.new(0, 0, 0)
    end
    
    return reached
end

local function goToWaypoint(index)
    if not running or #waypoints == 0 or not waypoints[index] then return end
    local waypoint = waypoints[index]

    local reached = goToWaypointTween(index)

    if running and reached then
        if waypoint.waitTime and waypoint.waitTime > 0 then
            root.CFrame = CFrame.new(waypoint.position)
            root.Velocity = Vector3.new(0,0,0)
            
            root.Anchored = true
            
            local startWait = tick()
            -- Цикл ожидания, который можно прервать выключением Toggle
            while tick() - startWait < waypoint.waitTime and running do
                task.wait(0.1)
            end
            
            root.Anchored = false
        end
    end
end

local function startAutoWalk()
    if running or #waypoints == 0 then return end
    running = true
    
    autoWalkThread = coroutine.create(function()
        while running and #waypoints > 0 do
            for i = 1, #waypoints do
                if not running or #waypoints == 0 then break end
                currentWaypointIndex = i
                
                if not root:FindFirstChild("WaypointGyro") then
                    local g = Instance.new("BodyGyro")
                    g.Name = "WaypointGyro"
                    g.P = 10000
                    g.MaxTorque = Vector3.new(400000, 400000, 400000)
                    g.CFrame = root.CFrame
                    g.Parent = root
                end

                -- Теперь всё ожидание происходит внутри этой функции один раз
                goToWaypoint(i)
            end
            task.wait()
        end
        stopAutoWalk()
    end)
    coroutine.resume(autoWalkThread)
end

local function stopAutoWalk()
    running = false
    waitingInAir = false
    
    if root then
        root.Anchored = false -- ГЛАВНЫЙ ФИКС: размораживаем принудительно
    end
    
    if root:FindFirstChild("WaypointGyro") then
        root.WaypointGyro:Destroy()
    end
    
    humanoid.AutoRotate = true 
    
    if autoWalkThread then
        coroutine.close(autoWalkThread)
        autoWalkThread = nil
    end
    
    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end

    removeAntiGravity()
    
    if humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
    end
    root.Velocity = Vector3.new(0, 0, 0)
end

-- Function to set wait time for specific waypoint
local function setWaitTime(waypointIndex, waitTime)
    if waypoints[waypointIndex] then
        waypoints[waypointIndex].waitTime = tonumber(waitTime) or 0
        updateWaypointVisuals()
    end
end

-- Function to copy waypoints to clipboard
local function copyWaypoints()
    if #waypoints == 0 then
        return ""
    end
    
    local waypointData = {}
    for i, waypoint in ipairs(waypoints) do
        table.insert(waypointData, {
            x = waypoint.position.X,
            y = waypoint.position.Y,
            z = waypoint.position.Z,
            wait = waypoint.waitTime or 0
        })
    end
    
    local copyText = "-- Waypoints Data (with wait times)\n"
    copyText = copyText .. "local waypointsData = {\n"
    
    for i, data in ipairs(waypointData) do
        local waitText = data.wait > 0 and string.format(" -- wait: %.1fs", data.wait) or ""
        copyText = copyText .. string.format(" {position = Vector3.new(%.2f, %.2f, %.2f), waitTime = %.1f},%s\n",
            data.x, data.y, data.z, data.wait, waitText)
    end
    
    copyText = copyText .. "}\n\n"
    copyText = copyText .. "-- JSON format for sharing:\n"
    local jsonString = game:GetService("HttpService"):JSONEncode(waypointData)
    copyText = copyText .. jsonString
    
    setclipboard(copyText)
    return copyText
end

-- Function to load waypoints from string
local function loadWaypointsFromString(inputString)
    local success = false
    
    local jsonSuccess, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(inputString)
    end)
    
    if jsonSuccess and type(data) == "table" then
        removeAllWaypoints()
        for i, waypoint in ipairs(data) do
            if waypoint.x and waypoint.y and waypoint.z then
                table.insert(waypoints, {
                    position = Vector3.new(waypoint.x, waypoint.y, waypoint.z),
                    waitTime = waypoint.wait or waypoint.waitTime or 0
                })
            end
        end
        updateWaypointVisuals()
        success = true
    else
        local luaTableMatch = inputString:match("waypointsData%s*=%s*%{([^}]+)%}")
        if luaTableMatch then
            removeAllWaypoints()
            local lines = {}
            for line in inputString:gmatch("[^\r\n]+") do
                table.insert(lines, line)
            end
            
            for _, line in ipairs(lines) do
                local x, y, z = line:match("Vector3%.new%(([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%)")
                local waitTime = line:match("waitTime%s*=%s*([%-%d%.]+)")
                
                if x and y and z then
                    table.insert(waypoints, {
                        position = Vector3.new(tonumber(x), tonumber(y), tonumber(z)),
                        waitTime = tonumber(waitTime) or 0
                    })
                end
            end
            updateWaypointVisuals()
            success = true
        else
            removeAllWaypoints()
            for line in inputString:gmatch("[^\r\n]+") do
                local x, y, z, wait = line:match("([%-%d%.]+)[,%s]+([%-%d%.]+)[,%s]+([%-%d%.]+)[%s%(]wait%s:")
                
                if not x then
                    x, y, z = line:match("([%-%d%.]+)[,%s]+([%-%d%.]+)[,%s]+([%-%d%.]+)")
                end
                
                if x and y and z then
                    table.insert(waypoints, {
                        position = Vector3.new(tonumber(x), tonumber(y), tonumber(z)),
                        waitTime = tonumber(wait) or 0
                    })
                end
            end
            
            if #waypoints > 0 then
                updateWaypointVisuals()
                success = true
            end
        end
    end
    
    return success
end

-- Function to generate random waypoints
local function generateRandomWaypoints()
    removeAllWaypoints()
    local basePos = root.Position
    local currentY = basePos.Y
    
    for i = 1, 20 do
        local randomOffset = Vector3.new(
            math.random(-50, 50),
            math.random(-10, 20),
            math.random(-50, 50)
        )
        
        local newPos = Vector3.new(
            basePos.X + randomOffset.X,
            basePos.Y + randomOffset.Y,
            basePos.Z + randomOffset.Z
        )
        
        table.insert(waypoints, {
            position = newPos,
            waitTime = 0
        })
    end
    
    updateWaypointVisuals()
    
    print("=== Random Waypoint Positions ===")
    for i, waypoint in ipairs(waypoints) do
        print(string.format('Waypoint %d: Vector3.new(%.2f, %.2f, %.2f)',
            i, waypoint.position.X, waypoint.position.Y, waypoint.position.Z))
    end
    print("=== Copy the above positions ===")
    copyWaypoints()
end

-- Function to auto spawn waypoints
local function toggleAutoSpawn(interval)
    if autoSpawnWaypoints and autoSpawnThread then
        coroutine.close(autoSpawnThread)
        autoSpawnThread = nil
    end
    
    if interval > 0 then
        autoSpawnWaypoints = true
        spawnInterval = interval
        autoSpawnThread = coroutine.create(function()
            while autoSpawnWaypoints do
                addWaypoint()
                task.wait(spawnInterval)
            end
        end)
        coroutine.resume(autoSpawnThread)
    else
        autoSpawnWaypoints = false
    end
end

-- Create sections
local WaypointSection = window:CreateSection("Waypoint System")

-- Create tab
local WaypointTab = WaypointSection:CreateTab("Waypoints", "rbxassetid://10709790982")

-- Section 4: Copy/Paste System
WaypointTab:CreateButton({
    Name = "Place Waypoints",
    Callback = function()
        -- 1. Очистка
        stopAutoWalk()
        if autoWalkToggle then autoWalkToggle:SetValue(false) end
        removeAllWaypoints()

        -- 2. ВСТАВЛЯЙ СЮДА СВОЙ ТЕКСТ (хоть в столбик, хоть в строку)
        local rawText = [[
-- Waypoints Data (with wait times)
local waypointsData = {
 {position = Vector3.new(-142.17, -34.43, -171.42), waitTime = 1.8}, -- wait: 1.8s
 {position = Vector3.new(-128.09, -34.09, -188.91), waitTime = 0.0},
 {position = Vector3.new(-120.60, -24.94, -195.87), waitTime = 1.8}, -- wait: 1.8s
 {position = Vector3.new(-120.76, -19.36, -198.05), waitTime = 0.0},
 {position = Vector3.new(-115.74, -3.76, -210.01), waitTime = 0.0},
 {position = Vector3.new(-94.77, -3.00, -234.34), waitTime = 0.0},
 {position = Vector3.new(-67.87, -3.00, -246.48), waitTime = 0.0},
 {position = Vector3.new(-7.19, -3.00, -261.32), waitTime = 0.0},
 {position = Vector3.new(69.77, -3.00, -264.90), waitTime = 0.0},
 {position = Vector3.new(129.48, -3.21, -268.54), waitTime = 0.0},
 {position = Vector3.new(142.71, -3.29, -267.13), waitTime = 0.0},
 {position = Vector3.new(153.58, -3.47, -261.69), waitTime = 0.0},
 {position = Vector3.new(173.90, -3.17, -249.79), waitTime = 0.0},
 {position = Vector3.new(218.12, -3.00, -199.52), waitTime = 0.0},
 {position = Vector3.new(247.56, -3.00, -145.65), waitTime = 0.0},
 {position = Vector3.new(256.18, -2.46, -113.38), waitTime = 0.0},
 {position = Vector3.new(307.36, -11.17, -60.68), waitTime = 0.0},
 {position = Vector3.new(319.16, -11.40, -43.42), waitTime = 0.0},
 {position = Vector3.new(347.59, -12.06, 0.42), waitTime = 0.0},
 {position = Vector3.new(372.64, -11.44, 45.88), waitTime = 0.0},
 {position = Vector3.new(396.64, -11.01, 91.50), waitTime = 0.0},
 {position = Vector3.new(417.85, -3.00, 135.94), waitTime = 0.0},
 {position = Vector3.new(431.87, -3.00, 170.63), waitTime = 0.0},
 {position = Vector3.new(434.66, -3.00, 177.99), waitTime = 0.0},
 {position = Vector3.new(440.24, -3.00, 180.25), waitTime = 0.0},
 {position = Vector3.new(446.19, -3.00, 209.31), waitTime = 0.0},
 {position = Vector3.new(445.23, -3.19, 225.13), waitTime = 0.0},
 {position = Vector3.new(452.75, 6.74, 227.55), waitTime = 0.0},
 {position = Vector3.new(456.41, 11.94, 236.67), waitTime = 1.8}, -- wait: 1.8s
 {position = Vector3.new(472.75, 16.50, 199.77), waitTime = 0.0},
 {position = Vector3.new(478.46, 11.90, 149.47), waitTime = 1.6}, -- wait: 1.6s
 {position = Vector3.new(484.20, -11.42, 105.83), waitTime = 0.0},
 {position = Vector3.new(521.16, -11.61, 15.95), waitTime = 0.0},
 {position = Vector3.new(553.80, -11.08, -24.67), waitTime = 0.0},
 {position = Vector3.new(591.10, -11.06, -61.43), waitTime = 0.0},
 {position = Vector3.new(626.37, -8.14, -99.80), waitTime = 0.0},
 {position = Vector3.new(661.05, -3.53, -137.55), waitTime = 0.0},
 {position = Vector3.new(669.71, 8.80, -148.51), waitTime = 0.0},
 {position = Vector3.new(674.25, 22.90, -156.83), waitTime = 0.0},
 {position = Vector3.new(685.31, 32.54, -177.03), waitTime = 0.0},
 {position = Vector3.new(710.10, 24.99, -204.65), waitTime = 1.8}, -- wait: 1.8s
 {position = Vector3.new(719.13, 26.02, -217.47), waitTime = 0.0},
 {position = Vector3.new(726.43, 22.42, -248.08), waitTime = 0.0},
 {position = Vector3.new(719.32, 25.65, -284.40), waitTime = 0.0},
 {position = Vector3.new(707.34, 33.24, -309.27), waitTime = 0.0},
 {position = Vector3.new(694.24, 38.10, -314.47), waitTime = 0.0},
 {position = Vector3.new(688.08, 44.19, -312.89), waitTime = 0.0},
 {position = Vector3.new(681.10, 57.58, -333.48), waitTime = 0.0},
 {position = Vector3.new(685.18, 74.15, -363.20), waitTime = 0.0},
 {position = Vector3.new(679.00, 77.96, -387.01), waitTime = 2.0}, -- wait: 2.0s
 {position = Vector3.new(655.02, 62.79, -380.18), waitTime = 0.0},
 {position = Vector3.new(628.67, 52.13, -371.98), waitTime = 0.0},
 {position = Vector3.new(591.94, 27.54, -362.05), waitTime = 0.0},
 {position = Vector3.new(582.76, 15.03, -354.73), waitTime = 0.0},
 {position = Vector3.new(586.98, 12.33, -352.45), waitTime = 0.0},
 {position = Vector3.new(591.30, 7.13, -350.20), waitTime = 0.0},
 {position = Vector3.new(592.92, -2.52, -349.53), waitTime = 0.0},
 {position = Vector3.new(614.01, -7.75, -361.08), waitTime = 2.2}, -- wait: 2.2s
 {position = Vector3.new(627.44, -7.37, -383.56), waitTime = 2.2}, -- wait: 2.2s
 {position = Vector3.new(584.49, 0.30, -390.75), waitTime = 0.0},
 {position = Vector3.new(553.44, 11.79, -395.00), waitTime = 0.0},
 {position = Vector3.new(516.73, 7.85, -418.26), waitTime = 0.0},
 {position = Vector3.new(439.74, -11.80, -436.32), waitTime = 0.0},
 {position = Vector3.new(317.02, -11.56, -492.37), waitTime = 0.0},
 {position = Vector3.new(268.01, -11.26, -509.73), waitTime = 0.0},
 {position = Vector3.new(218.77, -11.90, -522.97), waitTime = 0.0},
 {position = Vector3.new(169.58, -4.11, -536.75), waitTime = 0.0},
 {position = Vector3.new(118.46, -3.00, -549.04), waitTime = 0.0},
 {position = Vector3.new(66.97, -10.96, -551.97), waitTime = 0.0},
 {position = Vector3.new(14.67, -8.61, -554.96), waitTime = 0.0},
 {position = Vector3.new(-37.30, -3.00, -559.61), waitTime = 0.0},
 {position = Vector3.new(-88.93, -3.00, -569.28), waitTime = 0.0},
 {position = Vector3.new(-136.96, 3.48, -586.95), waitTime = 0.0},
 {position = Vector3.new(-185.35, 5.00, -607.08), waitTime = 0.0},
 {position = Vector3.new(-206.64, 12.66, -622.02), waitTime = 2.2}, -- wait: 2.2s
 {position = Vector3.new(-209.19, 6.73, -614.39), waitTime = 0.0},
 {position = Vector3.new(-300.93, -3.02, -603.51), waitTime = 0.0},
 {position = Vector3.new(-378.45, -6.31, -606.76), waitTime = 0.0},
 {position = Vector3.new(-396.41, -22.88, -602.11), waitTime = 0.0},
 {position = Vector3.new(-405.63, -30.02, -571.49), waitTime = 0.0},
 {position = Vector3.new(-405.29, -36.47, -558.41), waitTime = 0.0},
 {position = Vector3.new(-387.65, -43.25, -551.86), waitTime = 0.0},
 {position = Vector3.new(-375.67, -43.73, -558.70), waitTime = 2.0}, -- wait: 2.0s
 {position = Vector3.new(-331.80, -47.33, -567.65), waitTime = 0.0},
 {position = Vector3.new(-316.65, -48.70, -568.45), waitTime = 0.0},
 {position = Vector3.new(-292.06, -56.85, -566.69), waitTime = 0.0},
 {position = Vector3.new(-257.24, -55.80, -556.48), waitTime = 0.0},
 {position = Vector3.new(-222.23, -59.09, -544.08), waitTime = 0.0},
 {position = Vector3.new(-192.62, -63.29, -541.81), waitTime = 0.0},
 {position = Vector3.new(-172.34, -63.39, -567.02), waitTime = 0.0},
 {position = Vector3.new(-180.49, -64.21, -608.34), waitTime = 0.0},
 {position = Vector3.new(-198.56, -62.15, -623.69), waitTime = 2.2}, -- wait: 2.2s
 {position = Vector3.new(-177.39, -63.35, -596.42), waitTime = 0.0},
 {position = Vector3.new(-173.78, -63.19, -558.42), waitTime = 0.0},
 {position = Vector3.new(-170.41, -63.88, -541.20), waitTime = 0.0},
 {position = Vector3.new(-166.88, -63.09, -502.88), waitTime = 0.0},
 {position = Vector3.new(-177.20, -66.46, -466.42), waitTime = 0.0},
 {position = Vector3.new(-168.88, -67.64, -464.13), waitTime = 0.0},
 {position = Vector3.new(-165.75, -79.83, -464.19), waitTime = 0.0},
 {position = Vector3.new(-160.75, -97.96, -470.18), waitTime = 0.0},
 {position = Vector3.new(-160.00, -98.97, -484.17), waitTime = 0.0},
 {position = Vector3.new(-161.94, -100.22, -499.85), waitTime = 0.0},
 {position = Vector3.new(-173.72, -101.24, -504.41), waitTime = 0.0},
 {position = Vector3.new(-179.45, -102.25, -503.96), waitTime = 0.0},
 {position = Vector3.new(-186.70, -103.21, -501.82), waitTime = 0.0},
 {position = Vector3.new(-190.46, -103.45, -497.89), waitTime = 0.0},
 {position = Vector3.new(-192.43, -103.00, -483.81), waitTime = 0.0},
 {position = Vector3.new(-191.65, -103.78, -459.64), waitTime = 2.2}, -- wait: 2.2s
 {position = Vector3.new(-193.34, -103.23, -497.81), waitTime = 0.0},
 {position = Vector3.new(-179.90, -102.98, -506.38), waitTime = 0.0},
 {position = Vector3.new(-162.37, -100.16, -500.11), waitTime = 0.0},
 {position = Vector3.new(-147.52, -102.87, -490.59), waitTime = 0.0},
 {position = Vector3.new(-142.84, -96.97, -490.44), waitTime = 0.0},
 {position = Vector3.new(-130.05, -103.00, -488.87), waitTime = 0.0},
 {position = Vector3.new(-121.58, -103.00, -478.98), waitTime = 0.0},
 {position = Vector3.new(-79.36, -103.00, -475.12), waitTime = 0.0},
 {position = Vector3.new(-41.24, -103.00, -453.57), waitTime = 0.0},
 {position = Vector3.new(1.79, -103.00, -425.30), waitTime = 0.0},
 {position = Vector3.new(19.58, -99.16, -403.40), waitTime = 0.0},
 {position = Vector3.new(23.33, -99.00, -377.83), waitTime = 0.0},
 {position = Vector3.new(45.49, -99.18, -359.19), waitTime = 2.2}, -- wait: 2.2s
 {position = Vector3.new(22.19, -99.00, -383.44), waitTime = 0.0},
 {position = Vector3.new(13.55, -102.05, -413.85), waitTime = 0.0},
 {position = Vector3.new(-43.06, -103.48, -393.17), waitTime = 0.0},
 {position = Vector3.new(-89.14, -103.00, -356.08), waitTime = 0.0},
 {position = Vector3.new(-107.86, -102.92, -340.73), waitTime = 0.0},
 {position = Vector3.new(-123.95, -90.92, -286.27), waitTime = 0.0},
 {position = Vector3.new(-159.60, -85.38, -304.09), waitTime = 0.0},
 {position = Vector3.new(-162.74, -79.49, -316.68), waitTime = 0.0},
 {position = Vector3.new(-181.33, -79.34, -314.76), waitTime = 0.0},
 {position = Vector3.new(-209.83, -76.82, -308.67), waitTime = 0.0},
 {position = Vector3.new(-228.68, -79.34, -304.84), waitTime = 0.0},
 {position = Vector3.new(-262.89, -79.00, -346.57), waitTime = 0.0},
 {position = Vector3.new(-296.23, -76.90, -366.04), waitTime = 2.2}, -- wait: 2.2s
 {position = Vector3.new(-254.81, -77.57, -337.87), waitTime = 0.0},
 {position = Vector3.new(-234.43, -79.05, -308.82), waitTime = 0.0},
 {position = Vector3.new(-228.88, -81.70, -264.52), waitTime = 0.0},
 {position = Vector3.new(-239.37, -84.12, -242.11), waitTime = 2.0}, -- wait: 2.0s
 {position = Vector3.new(-232.10, -95.02, -232.06), waitTime = 0.0},
 {position = Vector3.new(-219.59, -98.37, -214.83), waitTime = 0.0},
 {position = Vector3.new(-211.24, -95.58, -172.60), waitTime = 0.0},
 {position = Vector3.new(-272.77, -95.13, -114.63), waitTime = 0.0},
 {position = Vector3.new(-305.23, -95.16, -75.56), waitTime = 0.0},
 {position = Vector3.new(-336.40, -91.02, -47.84), waitTime = 2.0}, -- wait: 2.0s
 {position = Vector3.new(-324.84, -87.78, -95.42), waitTime = 0.0},
 {position = Vector3.new(-317.70, -84.38, -109.74), waitTime = 0.0},
 {position = Vector3.new(-302.48, -75.21, -101.97), waitTime = 0.0},
 {position = Vector3.new(-288.67, -71.79, -94.34), waitTime = 0.0},
 {position = Vector3.new(-239.42, -71.66, -74.63), waitTime = 2.2}, -- wait: 2.2s
 {position = Vector3.new(-261.46, -72.43, -75.07), waitTime = 0.0},
 {position = Vector3.new(-264.46, -76.18, -72.65), waitTime = 0.0},
 {position = Vector3.new(-268.09, -90.10, -72.27), waitTime = 0.0},
 {position = Vector3.new(-265.66, -95.65, -76.61), waitTime = 0.0},
 {position = Vector3.new(-237.69, -93.87, -120.35), waitTime = 0.0},
 {position = Vector3.new(-206.25, -95.01, -124.74), waitTime = 0.0},
 {position = Vector3.new(-152.04, -95.18, -84.48), waitTime = 0.0},
 {position = Vector3.new(-114.44, -95.64, -57.43), waitTime = 0.0},
 {position = Vector3.new(-76.34, -95.18, -29.56), waitTime = 0.0},
 {position = Vector3.new(-51.61, -94.88, -22.01), waitTime = 0.0},
 {position = Vector3.new(-26.98, -93.12, -5.24), waitTime = 2.0}, -- wait: 2.0s
 {position = Vector3.new(-47.66, -94.82, -22.79), waitTime = 0.0},
 {position = Vector3.new(-65.99, -91.53, -50.03), waitTime = 0.0},
 {position = Vector3.new(-65.59, -82.18, -70.32), waitTime = 0.0},
 {position = Vector3.new(-59.26, -77.12, -76.40), waitTime = 0.0},
 {position = Vector3.new(-30.20, -75.00, -58.51), waitTime = 0.0},
 {position = Vector3.new(-23.07, -76.13, -41.10), waitTime = 0.0},
 {position = Vector3.new(10.04, -75.00, -37.14), waitTime = 0.0},
 {position = Vector3.new(4.51, -81.60, -75.82), waitTime = 1.8}, -- wait: 1.8s
 {position = Vector3.new(5.84, -76.25, -95.41), waitTime = 0.0},
 {position = Vector3.new(17.82, -72.74, -107.09), waitTime = 0.0},
 {position = Vector3.new(35.06, -75.00, -118.85), waitTime = 0.0},
 {position = Vector3.new(60.09, -75.20, -133.56), waitTime = 0.0},
 {position = Vector3.new(78.74, -72.99, -121.64), waitTime = 0.0},
 {position = Vector3.new(73.74, -50.59, -63.31), waitTime = 0.0},
 {position = Vector3.new(52.88, -40.07, -53.42), waitTime = 0.0},
 {position = Vector3.new(3.02, -36.63, -92.84), waitTime = 0.0},
 {position = Vector3.new(-34.52, -35.52, -125.86), waitTime = 0.0},
 {position = Vector3.new(-116.47, -35.04, -153.29), waitTime = 12.0}, -- wait: 12.0s
}

-- JSON format for sharing:
[{"y":-34.43000030517578,"x":-142.1699981689453,"wait":1.8,"z":-171.4199981689453},{"y":-34.09000015258789,"x":-128.08999633789063,"wait":0,"z":-188.91000366210938},{"y":-24.940000534057618,"x":-120.5999984741211,"wait":1.8,"z":-195.8699951171875},{"y":-19.360000610351564,"x":-120.76000213623047,"wait":0,"z":-198.0500030517578},{"y":-3.759999990463257,"x":-115.73999786376953,"wait":0,"z":-210.00999450683595},{"y":-3,"x":-94.7699966430664,"wait":0,"z":-234.33999633789063},{"y":-3,"x":-67.87000274658203,"wait":0,"z":-246.47999572753907},{"y":-3,"x":-7.190000057220459,"wait":0,"z":-261.32000732421877},{"y":-3,"x":69.7699966430664,"wait":0,"z":-264.8999938964844},{"y":-3.2100000381469728,"x":129.47999572753907,"wait":0,"z":-268.5400085449219},{"y":-3.2899999618530275,"x":142.7100067138672,"wait":0,"z":-267.1300048828125},{"y":-3.4700000286102297,"x":153.5800018310547,"wait":0,"z":-261.69000244140627},{"y":-3.1700000762939455,"x":173.89999389648438,"wait":0,"z":-249.7899932861328},{"y":-3,"x":218.1199951171875,"wait":0,"z":-199.52000427246095},{"y":-3,"x":247.55999755859376,"wait":0,"z":-145.64999389648438},{"y":-2.4600000381469728,"x":256.17999267578127,"wait":0,"z":-113.37999725341797},{"y":-11.170000076293946,"x":307.3599853515625,"wait":0,"z":-60.68000030517578},{"y":-11.399999618530274,"x":319.1600036621094,"wait":0,"z":-43.41999816894531},{"y":-12.0600004196167,"x":347.5899963378906,"wait":0,"z":0.41999998688697817},{"y":-11.4399995803833,"x":372.6400146484375,"wait":0,"z":45.880001068115237},{"y":-11.010000228881836,"x":396.6400146484375,"wait":0,"z":91.5},{"y":-3,"x":417.8500061035156,"wait":0,"z":135.94000244140626},{"y":-3,"x":431.8699951171875,"wait":0,"z":170.6300048828125},{"y":-3,"x":434.6600036621094,"wait":0,"z":177.99000549316407},{"y":-3,"x":440.239990234375,"wait":0,"z":180.25},{"y":-3,"x":446.19000244140627,"wait":0,"z":209.30999755859376},{"y":-3.190000057220459,"x":445.2300109863281,"wait":0,"z":225.1300048828125},{"y":6.739999771118164,"x":452.75,"wait":0,"z":227.5500030517578},{"y":11.9399995803833,"x":456.4100036621094,"wait":1.8,"z":236.6699981689453},{"y":16.5,"x":472.75,"wait":0,"z":199.77000427246095},{"y":11.899999618530274,"x":478.4599914550781,"wait":1.6,"z":149.47000122070313},{"y":-11.420000076293946,"x":484.20001220703127,"wait":0,"z":105.83000183105469},{"y":-11.609999656677246,"x":521.1599731445313,"wait":0,"z":15.949999809265137},{"y":-11.079999923706055,"x":553.7999877929688,"wait":0,"z":-24.670000076293947},{"y":-11.0600004196167,"x":591.0999755859375,"wait":0,"z":-61.43000030517578},{"y":-8.140000343322754,"x":626.3699951171875,"wait":0,"z":-99.80000305175781},{"y":-3.5299999713897707,"x":661.0499877929688,"wait":0,"z":-137.5500030517578},{"y":8.800000190734864,"x":669.7100219726563,"wait":0,"z":-148.50999450683595},{"y":22.899999618530275,"x":674.25,"wait":0,"z":-156.8300018310547},{"y":32.540000915527347,"x":685.3099975585938,"wait":0,"z":-177.02999877929688},{"y":24.989999771118165,"x":710.0999755859375,"wait":1.8,"z":-204.64999389648438},{"y":26.020000457763673,"x":719.1300048828125,"wait":0,"z":-217.47000122070313},{"y":22.420000076293947,"x":726.4299926757813,"wait":0,"z":-248.0800018310547},{"y":25.649999618530275,"x":719.3200073242188,"wait":0,"z":-284.3999938964844},{"y":33.2400016784668,"x":707.3400268554688,"wait":0,"z":-309.2699890136719},{"y":38.099998474121097,"x":694.239990234375,"wait":0,"z":-314.4700012207031},{"y":44.189998626708987,"x":688.0800170898438,"wait":0,"z":-312.8900146484375},{"y":57.58000183105469,"x":681.0999755859375,"wait":0,"z":-333.4800109863281},{"y":74.1500015258789,"x":685.1799926757813,"wait":0,"z":-363.20001220703127},{"y":77.95999908447266,"x":679,"wait":2,"z":-387.010009765625},{"y":62.790000915527347,"x":655.02001953125,"wait":0,"z":-380.17999267578127},{"y":52.130001068115237,"x":628.6699829101563,"wait":0,"z":-371.9800109863281},{"y":27.540000915527345,"x":591.9400024414063,"wait":0,"z":-362.04998779296877},{"y":15.029999732971192,"x":582.760009765625,"wait":0,"z":-354.7300109863281},{"y":12.329999923706055,"x":586.97998046875,"wait":0,"z":-352.45001220703127},{"y":7.130000114440918,"x":591.2999877929688,"wait":0,"z":-350.20001220703127},{"y":-2.5199999809265138,"x":592.9199829101563,"wait":0,"z":-349.5299987792969},{"y":-7.75,"x":614.010009765625,"wait":2.2,"z":-361.0799865722656},{"y":-7.369999885559082,"x":627.4400024414063,"wait":2.2,"z":-383.55999755859377},{"y":0.30000001192092898,"x":584.489990234375,"wait":0,"z":-390.75},{"y":11.789999961853028,"x":553.4400024414063,"wait":0,"z":-395},{"y":7.849999904632568,"x":516.72998046875,"wait":0,"z":-418.260009765625},{"y":-11.800000190734864,"x":439.739990234375,"wait":0,"z":-436.32000732421877},{"y":-11.5600004196167,"x":317.0199890136719,"wait":0,"z":-492.3699951171875},{"y":-11.260000228881836,"x":268.010009765625,"wait":0,"z":-509.7300109863281},{"y":-11.899999618530274,"x":218.77000427246095,"wait":0,"z":-522.969970703125},{"y":-4.110000133514404,"x":169.5800018310547,"wait":0,"z":-536.75},{"y":-3,"x":118.45999908447266,"wait":0,"z":-549.0399780273438},{"y":-10.960000038146973,"x":66.97000122070313,"wait":0,"z":-551.969970703125},{"y":-8.609999656677246,"x":14.670000076293946,"wait":0,"z":-554.9600219726563},{"y":-3,"x":-37.29999923706055,"wait":0,"z":-559.6099853515625},{"y":-3,"x":-88.93000030517578,"wait":0,"z":-569.280029296875},{"y":3.4800000190734865,"x":-136.9600067138672,"wait":0,"z":-586.9500122070313},{"y":5,"x":-185.35000610351563,"wait":0,"z":-607.0800170898438},{"y":12.65999984741211,"x":-206.63999938964845,"wait":2.2,"z":-622.02001953125},{"y":6.730000019073486,"x":-209.19000244140626,"wait":0,"z":-614.3900146484375},{"y":-3.0199999809265138,"x":-300.92999267578127,"wait":0,"z":-603.510009765625},{"y":-6.309999942779541,"x":-378.45001220703127,"wait":0,"z":-606.760009765625},{"y":-22.8799991607666,"x":-396.4100036621094,"wait":0,"z":-602.1099853515625},{"y":-30.020000457763673,"x":-405.6300048828125,"wait":0,"z":-571.489990234375},{"y":-36.470001220703128,"x":-405.2900085449219,"wait":0,"z":-558.4099731445313},{"y":-43.25,"x":-387.6499938964844,"wait":0,"z":-551.8599853515625},{"y":-43.72999954223633,"x":-375.6700134277344,"wait":2,"z":-558.7000122070313},{"y":-47.33000183105469,"x":-331.79998779296877,"wait":0,"z":-567.6500244140625},{"y":-48.70000076293945,"x":-316.6499938964844,"wait":0,"z":-568.4500122070313},{"y":-56.849998474121097,"x":-292.05999755859377,"wait":0,"z":-566.6900024414063},{"y":-55.79999923706055,"x":-257.239990234375,"wait":0,"z":-556.47998046875},{"y":-59.09000015258789,"x":-222.22999572753907,"wait":0,"z":-544.0800170898438},{"y":-63.290000915527347,"x":-192.6199951171875,"wait":0,"z":-541.8099975585938},{"y":-63.38999938964844,"x":-172.33999633789063,"wait":0,"z":-567.02001953125},{"y":-64.20999908447266,"x":-180.49000549316407,"wait":0,"z":-608.3400268554688},{"y":-62.150001525878909,"x":-198.55999755859376,"wait":2.2,"z":-623.6900024414063},{"y":-63.349998474121097,"x":-177.38999938964845,"wait":0,"z":-596.4199829101563},{"y":-63.189998626708987,"x":-173.77999877929688,"wait":0,"z":-558.4199829101563},{"y":-63.880001068115237,"x":-170.41000366210938,"wait":0,"z":-541.2000122070313},{"y":-63.09000015258789,"x":-166.8800048828125,"wait":0,"z":-502.8800048828125},{"y":-66.45999908447266,"x":-177.1999969482422,"wait":0,"z":-466.4200134277344},{"y":-67.63999938964844,"x":-168.8800048828125,"wait":0,"z":-464.1300048828125},{"y":-79.83000183105469,"x":-165.75,"wait":0,"z":-464.19000244140627},{"y":-97.95999908447266,"x":-160.75,"wait":0,"z":-470.17999267578127},{"y":-98.97000122070313,"x":-160,"wait":0,"z":-484.1700134277344},{"y":-100.22000122070313,"x":-161.94000244140626,"wait":0,"z":-499.8500061035156},{"y":-101.23999786376953,"x":-173.72000122070313,"wait":0,"z":-504.4100036621094},{"y":-102.25,"x":-179.4499969482422,"wait":0,"z":-503.9599914550781},{"y":-103.20999908447266,"x":-186.6999969482422,"wait":0,"z":-501.82000732421877},{"y":-103.44999694824219,"x":-190.4600067138672,"wait":0,"z":-497.8900146484375},{"y":-103,"x":-192.42999267578126,"wait":0,"z":-483.80999755859377},{"y":-103.77999877929688,"x":-191.64999389648438,"wait":2.2,"z":-459.6400146484375},{"y":-103.2300033569336,"x":-193.33999633789063,"wait":0,"z":-497.80999755859377},{"y":-102.9800033569336,"x":-179.89999389648438,"wait":0,"z":-506.3800048828125},{"y":-100.16000366210938,"x":-162.3699951171875,"wait":0,"z":-500.1099853515625},{"y":-102.87000274658203,"x":-147.52000427246095,"wait":0,"z":-490.5899963378906},{"y":-96.97000122070313,"x":-142.83999633789063,"wait":0,"z":-490.44000244140627},{"y":-103,"x":-130.0500030517578,"wait":0,"z":-488.8699951171875},{"y":-103,"x":-121.58000183105469,"wait":0,"z":-478.9800109863281},{"y":-103,"x":-79.36000061035156,"wait":0,"z":-475.1199951171875},{"y":-103,"x":-41.2400016784668,"wait":0,"z":-453.57000732421877},{"y":-103,"x":1.7899999618530274,"wait":0,"z":-425.29998779296877},{"y":-99.16000366210938,"x":19.579999923706056,"wait":0,"z":-403.3999938964844},{"y":-99,"x":23.329999923706056,"wait":0,"z":-377.8299865722656},{"y":-99.18000030517578,"x":45.4900016784668,"wait":2.2,"z":-359.19000244140627},{"y":-99,"x":22.190000534057618,"wait":0,"z":-383.44000244140627},{"y":-102.05000305175781,"x":13.550000190734864,"wait":0,"z":-413.8500061035156},{"y":-103.4800033569336,"x":-43.060001373291019,"wait":0,"z":-393.1700134277344},{"y":-103,"x":-89.13999938964844,"wait":0,"z":-356.0799865722656},{"y":-102.91999816894531,"x":-107.86000061035156,"wait":0,"z":-340.7300109863281},{"y":-90.91999816894531,"x":-123.94999694824219,"wait":0,"z":-286.2699890136719},{"y":-85.37999725341797,"x":-159.60000610351563,"wait":0,"z":-304.0899963378906},{"y":-79.48999786376953,"x":-162.74000549316407,"wait":0,"z":-316.67999267578127},{"y":-79.33999633789063,"x":-181.3300018310547,"wait":0,"z":-314.760009765625},{"y":-76.81999969482422,"x":-209.8300018310547,"wait":0,"z":-308.6700134277344},{"y":-79.33999633789063,"x":-228.67999267578126,"wait":0,"z":-304.8399963378906},{"y":-79,"x":-262.8900146484375,"wait":0,"z":-346.57000732421877},{"y":-76.9000015258789,"x":-296.2300109863281,"wait":2.2,"z":-366.0400085449219},{"y":-77.56999969482422,"x":-254.80999755859376,"wait":0,"z":-337.8699951171875},{"y":-79.05000305175781,"x":-234.42999267578126,"wait":0,"z":-308.82000732421877},{"y":-81.69999694824219,"x":-228.8800048828125,"wait":0,"z":-264.5199890136719},{"y":-84.12000274658203,"x":-239.3699951171875,"wait":2,"z":-242.11000061035157},{"y":-95.0199966430664,"x":-232.10000610351563,"wait":0,"z":-232.05999755859376},{"y":-98.37000274658203,"x":-219.58999633789063,"wait":0,"z":-214.8300018310547},{"y":-95.58000183105469,"x":-211.24000549316407,"wait":0,"z":-172.60000610351563},{"y":-95.12999725341797,"x":-272.7699890136719,"wait":0,"z":-114.62999725341797},{"y":-95.16000366210938,"x":-305.2300109863281,"wait":0,"z":-75.55999755859375},{"y":-91.0199966430664,"x":-336.3999938964844,"wait":2,"z":-47.84000015258789},{"y":-87.77999877929688,"x":-324.8399963378906,"wait":0,"z":-95.41999816894531},{"y":-84.37999725341797,"x":-317.70001220703127,"wait":0,"z":-109.73999786376953},{"y":-75.20999908447266,"x":-302.4800109863281,"wait":0,"z":-101.97000122070313},{"y":-71.79000091552735,"x":-288.6700134277344,"wait":0,"z":-94.33999633789063},{"y":-71.66000366210938,"x":-239.4199981689453,"wait":2.2,"z":-74.62999725341797},{"y":-72.43000030517578,"x":-261.4599914550781,"wait":0,"z":-75.06999969482422},{"y":-76.18000030517578,"x":-264.4599914550781,"wait":0,"z":-72.6500015258789},{"y":-90.0999984741211,"x":-268.0899963378906,"wait":0,"z":-72.2699966430664},{"y":-95.6500015258789,"x":-265.6600036621094,"wait":0,"z":-76.61000061035156},{"y":-93.87000274658203,"x":-237.69000244140626,"wait":0,"z":-120.3499984741211},{"y":-95.01000213623047,"x":-206.25,"wait":0,"z":-124.73999786376953},{"y":-95.18000030517578,"x":-152.0399932861328,"wait":0,"z":-84.4800033569336},{"y":-95.63999938964844,"x":-114.44000244140625,"wait":0,"z":-57.43000030517578},{"y":-95.18000030517578,"x":-76.33999633789063,"wait":0,"z":-29.559999465942384},{"y":-94.87999725341797,"x":-51.61000061035156,"wait":0,"z":-22.010000228881837},{"y":-93.12000274658203,"x":-26.979999542236329,"wait":2,"z":-5.239999771118164},{"y":-94.81999969482422,"x":-47.65999984741211,"wait":0,"z":-22.790000915527345},{"y":-91.52999877929688,"x":-65.98999786376953,"wait":0,"z":-50.029998779296878},{"y":-82.18000030517578,"x":-65.58999633789063,"wait":0,"z":-70.31999969482422},{"y":-77.12000274658203,"x":-59.2599983215332,"wait":0,"z":-76.4000015258789},{"y":-75,"x":-30.200000762939454,"wait":0,"z":-58.5099983215332},{"y":-76.12999725341797,"x":-23.06999969482422,"wait":0,"z":-41.099998474121097},{"y":-75,"x":10.039999961853028,"wait":0,"z":-37.13999938964844},{"y":-81.5999984741211,"x":4.510000228881836,"wait":1.8,"z":-75.81999969482422},{"y":-76.25,"x":5.840000152587891,"wait":0,"z":-95.41000366210938},{"y":-72.73999786376953,"x":17.81999969482422,"wait":0,"z":-107.08999633789063},{"y":-75,"x":35.060001373291019,"wait":0,"z":-118.8499984741211},{"y":-75.19999694824219,"x":60.09000015258789,"wait":0,"z":-133.55999755859376},{"y":-72.98999786376953,"x":78.73999786376953,"wait":0,"z":-121.63999938964844},{"y":-50.59000015258789,"x":73.73999786376953,"wait":0,"z":-63.310001373291019},{"y":-40.06999969482422,"x":52.880001068115237,"wait":0,"z":-53.41999816894531},{"y":-36.630001068115237,"x":3.0199999809265138,"wait":0,"z":-92.83999633789063},{"y":-35.52000045776367,"x":-34.52000045776367,"wait":0,"z":-125.86000061035156},{"y":-35.040000915527347,"x":-116.47000122070313,"wait":12,"z":-153.2899932861328}]
        ]]

        -- 3. УМНЫЙ ПАРСИНГ
        local count = 0
        
        -- Ищем JSON (даже если он разбит на много строк)
        local jsonPart = rawText:match("(%[.*%])") 
        if not jsonPart then
            -- Если скобки на разных строках, пробуем захватить всё от [ до ]
            jsonPart = rawText:match("%[(.+)%]")
            if jsonPart then jsonPart = "[" .. jsonPart .. "]" end
        end

        if jsonPart then
            local success, data = pcall(function()
                return game:GetService("HttpService"):JSONDecode(jsonPart)
            end)
            
            if success and type(data) == "table" then
                for _, wp in ipairs(data) do
                    table.insert(waypoints, {
                        position = Vector3.new(tonumber(wp.x), tonumber(wp.y), tonumber(wp.z)),
                        waitTime = tonumber(wp.wait) or 0
                    })
                    count = count + 1
                end
            end
        end

        -- 4. Если JSON не нашелся или кривой, ищем через Vector3.new в тексте
        if count == 0 then
            for x, y, z in rawText:gmatch("Vector3%.new%s*%(%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%)") do
                -- Пытаемся найти waitTime в той же строке
                local currentLine = rawText:match("Vector3%.new%("..x..".-waitTime%s*=%s*([%-%d%.]+)")
                table.insert(waypoints, {
                    position = Vector3.new(tonumber(x), tonumber(y), tonumber(z)),
                    waitTime = tonumber(currentLine) or 0
                })
                count = count + 1
            end
        end

        updateWaypointVisuals()
        warn("✅ Loaded Waypoints: " .. count)
    end
})
--------------------------------------------------
-- FPS BOOST SECTION
--------------------------------------------------

WaypointTab:CreateSection("FPS Boost")

WaypointTab:CreateToggle({
    Name = "FPS Boost (Low Graphics)",
    Default = false,
    Flag = "FPSBoostToggle",
    Callback = function(enabled)
        fpsBoostEnabled = enabled
        
        if enabled then
            applyFPSBoost()
            print("FPS Boost Enabled")
        else
            restoreFPSBoost()
            print("FPS Boost Disabled")
        end
    end
})

-- Section для управления waypoint
WaypointTab:CreateSection("Waypoint Management")

-- Textbox для ввода номера waypoint
local manageWaypointInput = WaypointTab:CreateTextBox({
    Name = "Waypoint Number to Manage",
    Default = "",
    Placeholder = "Enter waypoint number...",
    NumbersOnly = true,
    Flag = "ManageWaypointInput",
    Callback = function(text) end
})

-- Кнопка Manage
WaypointTab:CreateButton({
    Name = "Manage Waypoint",
    Callback = function()
        local index = tonumber(manageWaypointInput:GetText())
        if index then
            manageWaypoint(index)
        else
            print("Ошибка: Введите корректный номер waypoint!")
        end
    end
})

-- Кнопка Unmanage
WaypointTab:CreateButton({
    Name = "Unmanage Waypoint",
    Callback = function()
        unmanageWaypoint()
    end
})

-- Section 1: Waypoint Controls
WaypointTab:CreateSection("Waypoint Controls")

WaypointTab:CreateButton({
    Name = "Add Waypoint at Current Position",
    Callback = function()
        local result = addWaypointWithManagement()
        if result == "replaced" then
            print("Управляемый waypoint заменен!")
        else
            print("Новый waypoint добавлен!")
        end
    end
})

WaypointTab:CreateButton({
    Name = "Remove All Waypoints",
    Callback = function()
        removeAllWaypoints()
    end
})

WaypointTab:CreateButton({
    Name = "Remove Last Waypoint",
    Callback = function()
        removeLastWaypoint()
    end
})

WaypointTab:CreateButton({
    Name = "Generate 20 Random Waypoints",
    Callback = function()
        generateRandomWaypoints()
    end
})

-- Section 2: Auto Tween
WaypointTab:CreateSection("Auto Tween")

local autoWalkToggle = WaypointTab:CreateToggle({
    Name = "Auto Tween",
    Default = false,
    Flag = "AutoWalkToggle",
    Callback = function(enabled)
        if enabled then
            startAutoWalk()
        else
            stopAutoWalk()
        end
    end
})

-- Tween Speed Slider
WaypointTab:CreateSlider({
    Name = "Tween Speed",
    Min = 10,
    Max = 32,
    Default = 20,
    Flag = "TweenSpeed",
    Callback = function(value)
        tweenSpeed = value
    end
})

-- Section 3: Wait System
WaypointTab:CreateSection("Wait System")

local waypointIndexInput = WaypointTab:CreateTextBox({
    Name = "Waypoint Number",
    Default = "1",
    Placeholder = "Enter waypoint number...",
    NumbersOnly = true,
    Flag = "WaypointIndexInput",
    Callback = function(text) end
})

local waitTimeInput = WaypointTab:CreateTextBox({
    Name = "Wait Time (seconds)",
    Default = "0",
    Placeholder = "Enter wait time...",
    NumbersOnly = true,
    Flag = "WaitTimeInput",
    Callback = function(text) end
})

WaypointTab:CreateButton({
    Name = "Set Wait Time",
    Callback = function()
        local index = tonumber(waypointIndexInput:GetText())
        local waitTime = tonumber(waitTimeInput:GetText())
        if index and waitTime then
            setWaitTime(index, waitTime)
        end
    end
})

-- Section 5: Auto Spawn Waypoints
WaypointTab:CreateSection("Auto Spawn Waypoints")

local autoSpawnToggle = WaypointTab:CreateToggle({
    Name = "Auto Spawn Waypoints",
    Default = false,
    Flag = "AutoSpawnToggle",
    Callback = function(enabled)
        if enabled then
            toggleAutoSpawn(spawnInterval)
        else
            autoSpawnWaypoints = false
            if autoSpawnThread then
                coroutine.close(autoSpawnThread)
                autoSpawnThread = nil
            end
        end
    end
})

local spawnIntervalSlider = WaypointTab:CreateSlider({
    Name = "Spawn Interval (seconds)",
    Min = 0.01,
    Max = 10,
    Default = 0.5,
    Flag = "SpawnInterval",
    Callback = function(value)
        spawnInterval = value
        if autoSpawnWaypoints then
            toggleAutoSpawn(value)
        end
    end
})

WaypointTab:CreateButton({
    Name = "Clear Auto Spawned Waypoints",
    Callback = function()
        removeAllWaypoints()
    end
})

-- Section 6: External Scripts
WaypointTab:CreateSection("External Scripts")

-- Кнопка для загрузки скрипта
WaypointTab:CreateButton({
    Name = "Load Luarmor Universal ESP(NilHub for other functions or as you wish)",
    Callback = function()
        local success, errorMsg = pcall(function()
            loadstring(game:HttpGet("https://api.luarmor.net/files/v3/loaders/2c5f110f91165707959fc626b167e036.lua"))()
        end)
        if not success then
            warn("Failed to load Luarmor script:", errorMsg)
        end
    end
})

-- Section 4: Copy/Paste System
WaypointTab:CreateSection("Copy/Paste System")

local waypointDataInput = WaypointTab:CreateTextBox({
    Name = "Waypoint Data",
    Default = "",
    Placeholder = "Paste waypoint data here...",
    Flag = "WaypointDataInput",
    Callback = function(text) end
})

WaypointTab:CreateButton({
    Name = "📋 Copy All Waypoints (with wait times)",
    Callback = function()
        local data = copyWaypoints()
        if data ~= "" then
            waypointDataInput:SetText(data)
            print("✅ Waypoints copied to clipboard! (including wait times)")
        end
    end
})

WaypointTab:CreateButton({
    Name = "Load Waypoints",
    Callback = function()
        local data = waypointDataInput:GetText()
        if data ~= "" then
            loadWaypointsFromString(data)
            waypointDataInput:SetText("")
        end
    end
})

-- Character handling
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    root = character:WaitForChild("HumanoidRootPart")
    humanoid = character:WaitForChild("Humanoid")
    if running then
        stopAutoWalk()
        autoWalkToggle:SetValue(false)
    end
end)

game:GetService("RunService").Heartbeat:Connect(function()
    if not character or not character.Parent then
        character = player.Character
        if character then
            root = character:WaitForChild("HumanoidRootPart")
            humanoid = character:WaitForChild("Humanoid")
        end
    end
    
    if running and #waypoints == 0 then
        stopAutoWalk()
        if autoWalkToggle then
            autoWalkToggle:SetValue(false)
        end
    end
    
    if waitingInAir and root and not root.Anchored then
        root.Velocity = Vector3.new(0, 0, 0)
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
    
    if not autoSpawnWaypoints and autoSpawnThread then
        coroutine.close(autoSpawnThread)
        autoSpawnThread = nil
    end
end)

local function removeAllOldBoards()
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name == "Old Boards" then
            obj:Destroy()
        end
    end
end

removeAllOldBoards()

print("Waypoint System Loaded!")
print("Tween Speed: " .. tweenSpeed)
print("Toggle Key: RightControl")
print("Manage/Unmanage system activated!")
print("Instructions:")
print("1. Enter waypoint number in 'Waypoint Number to Manage'")
print("2. Click 'Manage Waypoint' to highlight it green")
print("3. Click 'Add Waypoint' to replace managed waypoint position")
print("4. Click 'Unmanage Waypoint' to stop managing")
