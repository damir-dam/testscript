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
    Name = "🚀 ЗАГРУЗИТЬ (ЛЮБОЙ ФОРМАТ)",
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
 {position = Vector3.new(-182.50, -67.35, -459.11), waitTime = 0.0},
 {position = Vector3.new(-176.69, -72.30, -427.96), waitTime = 0.0},
 {position = Vector3.new(-173.28, -79.57, -429.62), waitTime = 0.0},
 {position = Vector3.new(-170.84, -86.82, -430.60), waitTime = 0.0},
 {position = Vector3.new(-164.05, -93.93, -439.48), waitTime = 0.0},
 {position = Vector3.new(-156.64, -103.16, -447.10), waitTime = 0.0},
 {position = Vector3.new(-155.01, -99.15, -484.24), waitTime = 0.0},
 {position = Vector3.new(-164.29, -99.66, -502.99), waitTime = 0.0},
 {position = Vector3.new(-184.42, -102.83, -507.12), waitTime = 0.0},
 {position = Vector3.new(-190.46, -103.22, -505.00), waitTime = 0.0},
 {position = Vector3.new(-195.12, -103.23, -496.80), waitTime = 0.0},
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
 {position = Vector3.new(22.19, -99.00, -383.44), waitTime = 0.7}, -- wait: 0.7s
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
 {position = Vector3.new(-116.47, -35.04, -153.29), waitTime = 29.0}, -- wait: 29.0s
}

-- JSON format for sharing:
[{"y":-34.43000030517578,"x":-142.1699981689453,"wait":1.8,"z":-171.4199981689453},{"y":-34.09000015258789,"x":-128.08999633789063,"wait":0,"z":-188.91000366210938},{"y":-24.940000534057618,"x":-120.5999984741211,"wait":1.8,"z":-195.8699951171875},{"y":-19.360000610351564,"x":-120.76000213623047,"wait":0,"z":-198.0500030517578},{"y":-3.759999990463257,"x":-115.73999786376953,"wait":0,"z":-210.00999450683595},{"y":-3,"x":-94.7699966430664,"wait":0,"z":-234.33999633789063},{"y":-3,"x":-67.87000274658203,"wait":0,"z":-246.47999572753907},{"y":-3.000000238418579,"x":-7.193906784057617,"wait":0,"z":-261.3222351074219},{"y":-3.000000238418579,"x":69.7668685913086,"wait":0,"z":-264.8984375},{"y":-3.211099863052368,"x":129.4801025390625,"wait":0,"z":-268.5378723144531},{"y":-3.2904679775238039,"x":142.71026611328126,"wait":0,"z":-267.1348876953125},{"y":-3.4677841663360597,"x":153.58448791503907,"wait":0,"z":-261.68548583984377},{"y":-3.171844482421875,"x":173.89596557617188,"wait":0,"z":-249.79147338867188},{"y":-3.000000238418579,"x":218.12030029296876,"wait":0,"z":-199.52151489257813},{"y":-3.000000238418579,"x":247.56329345703126,"wait":0,"z":-145.64849853515626},{"y":-2.4632070064544679,"x":256.18304443359377,"wait":0,"z":-113.37638092041016},{"y":-11.16882038116455,"x":307.3553161621094,"wait":0,"z":-60.679351806640628},{"y":-11.397900581359864,"x":319.1632995605469,"wait":0,"z":-43.418243408203128},{"y":-12.061823844909668,"x":347.5921325683594,"wait":0,"z":0.4233053922653198},{"y":-11.441859245300293,"x":372.6440124511719,"wait":0,"z":45.87648010253906},{"y":-11.009708404541016,"x":396.63885498046877,"wait":0,"z":91.4955825805664},{"y":-3.000391721725464,"x":417.8527526855469,"wait":0,"z":135.94451904296876},{"y":-3.000000238418579,"x":431.8664855957031,"wait":0,"z":170.6321258544922},{"y":-3.000000238418579,"x":434.6597595214844,"wait":0,"z":177.99447631835938},{"y":-3.000000238418579,"x":440.2350158691406,"wait":0,"z":180.251953125},{"y":-3.000000238418579,"x":446.1878967285156,"wait":0,"z":209.3073272705078},{"y":-3.192939043045044,"x":445.2262878417969,"wait":0,"z":225.12713623046876},{"y":6.735305309295654,"x":452.7459411621094,"wait":0,"z":227.55291748046876},{"y":11.943338394165039,"x":456.4052734375,"wait":1.8,"z":236.66836547851563},{"y":16.499433517456056,"x":472.7525939941406,"wait":0,"z":199.77267456054688},{"y":11.903543472290039,"x":478.4586486816406,"wait":1.6,"z":149.47271728515626},{"y":-11.423736572265625,"x":484.20123291015627,"wait":0,"z":105.82853698730469},{"y":-11.60840129852295,"x":521.1630859375,"wait":0,"z":15.946290016174317},{"y":-11.077680587768555,"x":553.7958374023438,"wait":0,"z":-24.67354965209961},{"y":-11.059288024902344,"x":591.096435546875,"wait":0,"z":-61.42787170410156},{"y":-8.144018173217774,"x":626.3690795898438,"wait":0,"z":-99.80208587646485},{"y":-3.5325961112976076,"x":661.0508422851563,"wait":0,"z":-137.5524139404297},{"y":8.804997444152832,"x":669.70849609375,"wait":0,"z":-148.5086212158203},{"y":22.901493072509767,"x":674.2463989257813,"wait":0,"z":-156.8274688720703},{"y":32.54346466064453,"x":685.3113403320313,"wait":0,"z":-177.0337371826172},{"y":24.992664337158204,"x":710.0988159179688,"wait":1.8,"z":-204.65423583984376},{"y":26.024356842041017,"x":719.131591796875,"wait":0,"z":-217.47264099121095},{"y":22.422462463378908,"x":726.4271240234375,"wait":0,"z":-248.0786590576172},{"y":25.648414611816408,"x":719.3240356445313,"wait":0,"z":-284.4022216796875},{"y":33.239898681640628,"x":707.3430786132813,"wait":0,"z":-309.2666931152344},{"y":38.09931945800781,"x":694.235595703125,"wait":0,"z":-314.473876953125},{"y":44.19174575805664,"x":688.079345703125,"wait":0,"z":-312.89300537109377},{"y":57.575035095214847,"x":681.0992431640625,"wait":0,"z":-333.4767150878906},{"y":74.15034484863281,"x":685.1806640625,"wait":0,"z":-363.2015075683594},{"y":77.95716857910156,"x":678.9993896484375,"wait":2,"z":-387.0060729980469},{"y":62.78943634033203,"x":655.0240478515625,"wait":0,"z":-380.1797790527344},{"y":52.12639617919922,"x":628.671142578125,"wait":0,"z":-371.9801025390625},{"y":27.535512924194337,"x":591.9415893554688,"wait":0,"z":-362.0472717285156},{"y":15.026756286621094,"x":582.755859375,"wait":0,"z":-354.72869873046877},{"y":12.329566955566407,"x":586.9833374023438,"wait":0,"z":-352.4523010253906},{"y":7.134368419647217,"x":591.3009033203125,"wait":0,"z":-350.1965026855469},{"y":-2.5196750164031984,"x":592.9186401367188,"wait":0,"z":-349.52984619140627},{"y":-7.745516777038574,"x":614.0098876953125,"wait":2.2,"z":-361.0843811035156},{"y":-7.373986721038818,"x":627.443359375,"wait":2.2,"z":-383.55535888671877},{"y":0.30250468850135805,"x":584.4931640625,"wait":0,"z":-390.7494201660156},{"y":11.793925285339356,"x":553.4405517578125,"wait":0,"z":-395.00128173828127},{"y":7.854164123535156,"x":516.7313232421875,"wait":0,"z":-418.26336669921877},{"y":-11.800650596618653,"x":439.74139404296877,"wait":0,"z":-436.3156433105469},{"y":-11.558451652526856,"x":317.01715087890627,"wait":0,"z":-492.3699035644531},{"y":-11.255672454833985,"x":268.0101318359375,"wait":0,"z":-509.7339172363281},{"y":-11.900949478149414,"x":218.77427673339845,"wait":0,"z":-522.969482421875},{"y":-4.112170696258545,"x":169.58285522460938,"wait":0,"z":-536.7492065429688},{"y":-3.000000476837158,"x":118.45639038085938,"wait":0,"z":-549.037841796875},{"y":-10.961676597595215,"x":66.97217559814453,"wait":0,"z":-551.973876953125},{"y":-8.614070892333985,"x":14.67462158203125,"wait":0,"z":-554.962646484375},{"y":-3.000042200088501,"x":-37.300071716308597,"wait":0,"z":-559.6119384765625},{"y":-3.000000238418579,"x":-88.93019104003906,"wait":0,"z":-569.2805786132813},{"y":3.4754135608673097,"x":-136.95860290527345,"wait":0,"z":-586.9496459960938},{"y":4.999978542327881,"x":-185.34690856933595,"wait":0,"z":-607.0814208984375},{"y":12.659697532653809,"x":-206.63658142089845,"wait":2.2,"z":-622.0153198242188},{"y":6.730623722076416,"x":-209.19384765625,"wait":0,"z":-614.3889770507813},{"y":-3.016338348388672,"x":-300.9321594238281,"wait":0,"z":-603.5060424804688},{"y":-6.312055587768555,"x":-378.4496154785156,"wait":0,"z":-606.760009765625},{"y":-22.881303787231447,"x":-396.4064025878906,"wait":0,"z":-602.1128540039063},{"y":-30.023094177246095,"x":-405.62628173828127,"wait":0,"z":-571.4859008789063},{"y":-36.46782684326172,"x":-405.2904968261719,"wait":0,"z":-558.409912109375},{"y":-43.25077438354492,"x":-387.6481018066406,"wait":0,"z":-551.8556518554688},{"y":-43.73164749145508,"x":-375.6720886230469,"wait":2,"z":-558.697265625},{"y":-47.329586029052737,"x":-331.8035888671875,"wait":0,"z":-567.6485595703125},{"y":-48.7047004699707,"x":-316.6496887207031,"wait":0,"z":-568.4500122070313},{"y":-56.84750747680664,"x":-292.05975341796877,"wait":0,"z":-566.6893310546875},{"y":-55.80421447753906,"x":-257.2379150390625,"wait":0,"z":-556.4752197265625},{"y":-59.09319305419922,"x":-222.22845458984376,"wait":0,"z":-544.075439453125},{"y":-63.29042434692383,"x":-192.6230010986328,"wait":0,"z":-541.8082885742188},{"y":-63.39363479614258,"x":-172.34437561035157,"wait":0,"z":-567.0187377929688},{"y":-64.20911407470703,"x":-180.48651123046876,"wait":0,"z":-608.3361206054688},{"y":-62.14921188354492,"x":-198.5557098388672,"wait":2.2,"z":-623.6878662109375},{"y":-63.34623336791992,"x":-177.3904571533203,"wait":0,"z":-596.42431640625},{"y":-63.19350814819336,"x":-173.7780303955078,"wait":0,"z":-558.4201049804688},{"y":-63.87661361694336,"x":-170.40914916992188,"wait":0,"z":-541.2020874023438},{"y":-63.09397506713867,"x":-166.87742614746095,"wait":0,"z":-502.88348388671877},{"y":-67.35009765625,"x":-182.4958953857422,"wait":0,"z":-459.10638427734377},{"y":-72.29856872558594,"x":-176.68756103515626,"wait":0,"z":-427.9587097167969},{"y":-79.57106018066406,"x":-173.28353881835938,"wait":0,"z":-429.6185607910156},{"y":-86.82482147216797,"x":-170.83746337890626,"wait":0,"z":-430.5980224609375},{"y":-93.92610931396485,"x":-164.05413818359376,"wait":0,"z":-439.4833068847656},{"y":-103.15766143798828,"x":-156.63893127441407,"wait":0,"z":-447.0992126464844},{"y":-99.15303802490235,"x":-155.0129852294922,"wait":0,"z":-484.23565673828127},{"y":-99.66351318359375,"x":-164.28671264648438,"wait":0,"z":-502.98773193359377},{"y":-102.83038330078125,"x":-184.42022705078126,"wait":0,"z":-507.11761474609377},{"y":-103.22001647949219,"x":-190.46044921875,"wait":0,"z":-505.000732421875},{"y":-103.2288818359375,"x":-195.124755859375,"wait":0,"z":-496.8044128417969},{"y":-103.78424835205078,"x":-191.65103149414063,"wait":2.2,"z":-459.63763427734377},{"y":-103.22669219970703,"x":-193.344970703125,"wait":0,"z":-497.8055725097656},{"y":-102.98370361328125,"x":-179.8974151611328,"wait":0,"z":-506.3843994140625},{"y":-100.16232299804688,"x":-162.371337890625,"wait":0,"z":-500.112548828125},{"y":-102.87164306640625,"x":-147.52218627929688,"wait":0,"z":-490.5917663574219},{"y":-96.97248077392578,"x":-142.83822631835938,"wait":0,"z":-490.43682861328127},{"y":-103.00000762939453,"x":-130.0463409423828,"wait":0,"z":-488.8684387207031},{"y":-103.00000762939453,"x":-121.58474731445313,"wait":0,"z":-478.979248046875},{"y":-103.00000762939453,"x":-79.3589096069336,"wait":0,"z":-475.1190490722656},{"y":-103.00000762939453,"x":-41.23799514770508,"wait":0,"z":-453.56683349609377},{"y":-103.00001525878906,"x":1.7937331199645997,"wait":0,"z":-425.2991943359375},{"y":-99.15604400634766,"x":19.57880210876465,"wait":0,"z":-403.4013671875},{"y":-99.00000762939453,"x":23.32716941833496,"wait":0,"z":-377.8349609375},{"y":-99.1796875,"x":45.48797607421875,"wait":2.2,"z":-359.1908264160156},{"y":-99.00000762939453,"x":22.187225341796876,"wait":0.7,"z":-383.4379577636719},{"y":-102.05060577392578,"x":13.553324699401856,"wait":0,"z":-413.84820556640627},{"y":-103.47786712646485,"x":-43.05619812011719,"wait":0,"z":-393.16888427734377},{"y":-103.00000762939453,"x":-89.14262390136719,"wait":0,"z":-356.07952880859377},{"y":-102.91793060302735,"x":-107.85682678222656,"wait":0,"z":-340.725830078125},{"y":-90.92494201660156,"x":-123.95037078857422,"wait":0,"z":-286.2729797363281},{"y":-85.37653350830078,"x":-159.60365295410157,"wait":0,"z":-304.0931396484375},{"y":-79.48735046386719,"x":-162.74288940429688,"wait":0,"z":-316.6795654296875},{"y":-79.34274291992188,"x":-181.32566833496095,"wait":0,"z":-314.76483154296877},{"y":-76.81741333007813,"x":-209.83004760742188,"wait":0,"z":-308.6707458496094},{"y":-79.34382629394531,"x":-228.68209838867188,"wait":0,"z":-304.84075927734377},{"y":-79.0000228881836,"x":-262.8919677734375,"wait":0,"z":-346.5740661621094},{"y":-76.90382385253906,"x":-296.23065185546877,"wait":2.2,"z":-366.0355224609375},{"y":-77.57290649414063,"x":-254.81214904785157,"wait":0,"z":-337.8667907714844},{"y":-79.04808807373047,"x":-234.43209838867188,"wait":0,"z":-308.8171691894531},{"y":-81.70442199707031,"x":-228.88233947753907,"wait":0,"z":-264.5204162597656},{"y":-84.12410736083985,"x":-239.368896484375,"wait":2,"z":-242.11471557617188},{"y":-95.01972198486328,"x":-232.10292053222657,"wait":0,"z":-232.0609130859375},{"y":-98.37110137939453,"x":-219.5860137939453,"wait":0,"z":-214.82704162597657},{"y":-95.57554626464844,"x":-211.24476623535157,"wait":0,"z":-172.59503173828126},{"y":-95.13186645507813,"x":-272.7660827636719,"wait":0,"z":-114.62858581542969},{"y":-95.1604232788086,"x":-305.22930908203127,"wait":0,"z":-75.5643310546875},{"y":-91.015625,"x":-336.3992614746094,"wait":2,"z":-47.844207763671878},{"y":-87.78330993652344,"x":-324.8390808105469,"wait":0,"z":-95.41797637939453},{"y":-84.38426971435547,"x":-317.6999206542969,"wait":0,"z":-109.74083709716797},{"y":-75.21232604980469,"x":-302.4832458496094,"wait":0,"z":-101.97429656982422},{"y":-71.79252624511719,"x":-288.66680908203127,"wait":0,"z":-94.34136962890625},{"y":-71.65625762939453,"x":-239.41661071777345,"wait":2.2,"z":-74.6250228881836},{"y":-72.4268569946289,"x":-261.4601135253906,"wait":0,"z":-75.07295989990235},{"y":-76.17755889892578,"x":-264.45574951171877,"wait":0,"z":-72.64728546142578},{"y":-90.09703063964844,"x":-268.08642578125,"wait":0,"z":-72.27223205566406},{"y":-95.6498794555664,"x":-265.6581726074219,"wait":0,"z":-76.61483764648438},{"y":-93.86599731445313,"x":-237.69046020507813,"wait":0,"z":-120.35157012939453},{"y":-95.01250457763672,"x":-206.25115966796876,"wait":0,"z":-124.73576354980469},{"y":-95.17524719238281,"x":-152.03848266601563,"wait":0,"z":-84.4786376953125},{"y":-95.643310546875,"x":-114.43943786621094,"wait":0,"z":-57.430355072021487},{"y":-95.179931640625,"x":-76.3412094116211,"wait":0,"z":-29.555086135864259},{"y":-94.88179016113281,"x":-51.60871124267578,"wait":0,"z":-22.006633758544923},{"y":-93.1152572631836,"x":-26.976219177246095,"wait":2,"z":-5.239721775054932},{"y":-94.81832122802735,"x":-47.660465240478519,"wait":0,"z":-22.78992462158203},{"y":-91.52763366699219,"x":-65.9892807006836,"wait":0,"z":-50.0259895324707},{"y":-82.18412780761719,"x":-65.59212493896485,"wait":0,"z":-70.32133483886719},{"y":-77.12173461914063,"x":-59.26271438598633,"wait":0,"z":-76.39707946777344},{"y":-75.00442504882813,"x":-30.203842163085939,"wait":0,"z":-58.51171875},{"y":-76.12679290771485,"x":-23.068025588989259,"wait":0,"z":-41.10124206542969},{"y":-75.00000762939453,"x":10.044095039367676,"wait":0,"z":-37.1375732421875},{"y":-81.59669494628906,"x":4.51425313949585,"wait":1.8,"z":-75.82429504394531},{"y":-76.2455825805664,"x":5.842025279998779,"wait":0,"z":-95.41473388671875},{"y":-72.74285888671875,"x":17.821550369262697,"wait":0,"z":-107.08629608154297},{"y":-75.00000762939453,"x":35.05997085571289,"wait":0,"z":-118.84991455078125},{"y":-75.20008087158203,"x":60.09412384033203,"wait":0,"z":-133.5592498779297},{"y":-72.98748779296875,"x":78.74357604980469,"wait":0,"z":-121.64286041259766},{"y":-50.594261169433597,"x":73.73648071289063,"wait":0,"z":-63.30973815917969},{"y":-40.071224212646487,"x":52.88203430175781,"wait":0,"z":-53.41515350341797},{"y":-36.62607955932617,"x":3.0187900066375734,"wait":0,"z":-92.84034729003906},{"y":-35.519309997558597,"x":-34.520442962646487,"wait":0,"z":-125.86075592041016},{"y":-35.044837951660159,"x":-116.46876525878906,"wait":29,"z":-153.28692626953126}]
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
        warn("✅ Загружено точек: " .. count)
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
    Default = 16,
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
