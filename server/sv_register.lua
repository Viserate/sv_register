print('^2[SanctusVoid]^7 Script Registration System is Active!')

-- sv_register: script registration and lifecycle management
local Config = Config
local RegisteredScripts = {}  -- { [scriptName] = { id, name, version, registerDate, lastRegistered, shouldBypass } }
local PendingScripts = {}     -- { [scriptName] = { registerTime, timeout } }
local PlayerPermissions = {}  -- { [playerId] = permissionLevel }
local DatabaseReady = false

-- Get database connection from global variable or config
local function getConnectionString()
    if _G.mysql_connection_string then
        return _G.mysql_connection_string
    end
    return nil
end

local function logDebug(msg)
    if Config.DebugLogging then
        print('^2[sv_register]^0 ' .. msg)
    end
end

-- ===== PERMISSION SYSTEM =====
local function getPlayerIdentifiers(playerId)
    local identifiers = {}
    for i = 0, GetNumPlayerIdentifiers(playerId) - 1 do
        local id = GetPlayerIdentifier(playerId, i)
        identifiers[id] = true
    end
    return identifiers
end

local function getPlayerPermissionLevel(playerId)
    if not playerId or playerId == 0 then return 'none' end

    -- Get player identifiers
    local steamId = GetPlayerIdentifier(playerId, 0)
    local license = nil
    for i = 0, GetNumPlayerIdentifiers(playerId) - 1 do
        local id = GetPlayerIdentifier(playerId, i)
        if id and string.match(id, '^license:') then
            license = id
            break
        end
    end

    -- Check database permissions first (Steam ID priority)
    if steamId and exports and exports.oxmysql then
        local dbRank = nil
        local queryReady = false
        exports.oxmysql:execute(
            'SELECT rank_name FROM sv_register_player_perms WHERE identifier = ? LIMIT 1',
            { steamId },
            function(result)
                if result and result[1] then
                    dbRank = result[1].rank_name
                end
                queryReady = true
            end
        )
        -- Wait briefly for result
        local waitTime = 0
        while not queryReady and waitTime < 500 do
            Wait(10)
            waitTime = waitTime + 10
        end
        if dbRank then
            return dbRank
        end
    end

    -- Default rank if no DB entry
    return 'none'
end

local function hasCommandPermission(playerId, commandName)
    local rankName = getPlayerPermissionLevel(playerId)
    
    -- Use global permission config from shared_script
    if not PermissionConfig or not PermissionConfig.Ranks then
        return false
    end
    
    local rank = PermissionConfig.Ranks[rankName]
    if not rank then
        return false
    end
    
    -- Check if rank has 'all' permission
    if rank.permissions then
        for _, perm in ipairs(rank.permissions) do
            if perm == 'all' then
                return true
            end
        end
    end
    
    -- Check specific command permission
    local requiredPerms = PermissionConfig.CommandPermissions[commandName]
    if requiredPerms then
        for _, reqPerm in ipairs(requiredPerms) do
            if rank.permissions then
                for _, perm in ipairs(rank.permissions) do
                    if perm == reqPerm then
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

local function initDatabase()
    if not exports or not exports.oxmysql then
        print('^1[sv_register]^0 oxmysql not found')
        return false
    end

    --logDebug('Initializing database (oxmysql test)...')

    -- Test connection first
    local connected = false
    local testOk, testResult = pcall(function()
        exports.oxmysql:execute('SELECT 1', {}, function(result)
            connected = true
            --logDebug('Database connection successful')
        end)
    end)

    if not testOk then
        print('^1[sv_register]^0 Failed to connect to database: ' .. tostring(testResult))
        return false
    end

    -- Wait for connection test (max 5 seconds)
    local waitTime = 0
    while not connected and waitTime < 5000 do
        Wait(100)
        waitTime = waitTime + 100
    end

    if not connected then
        print('^1[sv_register]^0 Database connection timeout')
        return false
    end

    -- Create sv_register_logs table
    local createTableQuery = [[
        CREATE TABLE IF NOT EXISTS sv_register_logs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            script_name VARCHAR(255) NOT NULL UNIQUE,
            version VARCHAR(100),
            action VARCHAR(50),
            should_bypass TINYINT DEFAULT 0,
            registered_at TIMESTAMP NULL DEFAULT NULL,
            last_registered TIMESTAMP NULL DEFAULT NULL,
            INDEX idx_script_name (script_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]]

    local tableReady = false
    local tableOk, tableResult = pcall(function()
        exports.oxmysql:execute(createTableQuery, {}, function(result)
            tableReady = true
            DatabaseReady = true
            --logDebug('Database table initialized')
        end)
    end)

    if not tableOk then
        print('^1[sv_register]^0 Failed to create table: ' .. tostring(tableResult))
        return false
    end

    -- Wait for table creation (max 5 seconds)
    waitTime = 0
    while not tableReady and waitTime < 5000 do
        Wait(100)
        waitTime = waitTime + 100
    end

    if not tableReady then
        print('^1[sv_register]^0 Table creation timeout')
        return false
    end

    -- Create player permissions table
    local permTableQuery = [[
        CREATE TABLE IF NOT EXISTS sv_register_player_perms (
            id INT AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(255) NOT NULL UNIQUE,
            rank_name VARCHAR(100) DEFAULT 'none',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_identifier (identifier),
            INDEX idx_rank_name (rank_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]]

    local permTableReady = false
    local permTableOk, permTableResult = pcall(function()
        exports.oxmysql:execute(permTableQuery, {}, function(result)
            permTableReady = true
        end)
    end)

    if not permTableOk then
        print('^1[sv_register]^0 Failed to create permissions table: ' .. tostring(permTableResult))
        return false
    end

    -- Wait for permissions table (max 5 seconds)
    waitTime = 0
    while not permTableReady and waitTime < 5000 do
        Wait(100)
        waitTime = waitTime + 100
    end

    if not permTableReady then
        print('^1[sv_register]^0 Permissions table creation timeout')
        return false
    end

    -- Add rank_name column if it doesn't exist (for migration)
    local addColumnReady = false
    pcall(function()
        exports.oxmysql:execute([[
            ALTER TABLE sv_register_player_perms 
            ADD COLUMN IF NOT EXISTS rank_name VARCHAR(100) DEFAULT 'none'
        ]], {}, function()
            addColumnReady = true
        end)
    end)

    waitTime = 0
    while not addColumnReady and waitTime < 2000 do
        Wait(100)
        waitTime = waitTime + 100
    end

    -- Drop old permission_level column if rank_name exists
    local dropColumnReady = false
    pcall(function()
        exports.oxmysql:execute([[
            ALTER TABLE sv_register_player_perms 
            DROP COLUMN IF EXISTS permission_level
        ]], {}, function()
            dropColumnReady = true
        end)
    end)

    waitTime = 0
    while not dropColumnReady and waitTime < 2000 do
        Wait(100)
        waitTime = waitTime + 100
    end

    -- Create ranks table (no migration needed, fresh install)
    local ranksTableQuery = [[
        CREATE TABLE IF NOT EXISTS sv_register_ranks (
            id INT AUTO_INCREMENT PRIMARY KEY,
            rank_name VARCHAR(100) NOT NULL UNIQUE,
            rank_level INT NOT NULL UNIQUE,
            rank_label VARCHAR(255),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_rank_level (rank_level),
            INDEX idx_rank_name (rank_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]]

    local ranksTableReady = false
    pcall(function()
        exports.oxmysql:execute(ranksTableQuery, {}, function(result)
            ranksTableReady = true
        end)
    end)

    waitTime = 0
    while not ranksTableReady and waitTime < 5000 do
        Wait(100)
        waitTime = waitTime + 100
    end

    -- Create rank permissions table
    local rankPermsTableQuery = [[
        CREATE TABLE IF NOT EXISTS sv_register_rank_permissions (
            id INT AUTO_INCREMENT PRIMARY KEY,
            rank_id INT NOT NULL,
            permission_name VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY unique_rank_perm (rank_id, permission_name),
            FOREIGN KEY (rank_id) REFERENCES sv_register_ranks(id) ON DELETE CASCADE,
            INDEX idx_rank_id (rank_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]]

    local rankPermsTableReady = false
    pcall(function()
        exports.oxmysql:execute(rankPermsTableQuery, {}, function(result)
            rankPermsTableReady = true
        end)
    end)

    waitTime = 0
    while not rankPermsTableReady and waitTime < 5000 do
        Wait(100)
        waitTime = waitTime + 100
    end

    -- Populate default ranks from config (loaded globally via shared_script)
    if PermissionConfig and PermissionConfig.Ranks then
        print('^3[sv_register]^0 Populating default ranks...')
        local populateReady = false
        local ranksPopulated = 0
        
        for rankName, rankData in pairs(PermissionConfig.Ranks) do
            pcall(function()
                exports.oxmysql:execute([[
                    INSERT IGNORE INTO sv_register_ranks (rank_name, rank_level, rank_label)
                    VALUES (?, ?, ?)
                ]], { rankName, rankData.level or 0, rankData.label or rankName }, function(result)
                    if result and result.affectedRows > 0 then
                        ranksPopulated = ranksPopulated + 1
                    end
                    
                    -- Now insert permissions for this rank
                    if rankData.permissions then
                        for _, permission in ipairs(rankData.permissions) do
                            pcall(function()
                                exports.oxmysql:execute([[
                                    INSERT IGNORE INTO sv_register_rank_permissions (rank_id, permission_name)
                                    SELECT id, ? FROM sv_register_ranks WHERE rank_name = ?
                                ]], { permission, rankName }, function() end)
                            end)
                        end
                    end
                end)
            end)
        end
        
        Wait(1000) -- Give time for inserts
        if ranksPopulated > 0 then
            print(string.format('^2[sv_register]^0 Populated %d ranks', ranksPopulated))
        end
    end

    --logDebug('Database fully initialized and ready')
    return true
end

-- Log action to database
local function dbLog(action, scriptName, version, shouldBypass)
    if not exports then
        return
    end
    
    if not exports.oxmysql then
        return
    end

    local bypassVal = shouldBypass and 1 or 0

    -- Check if this is a heartbeat update (only update last_registered) or a new entry
    if action == 'Heartbeat' then
        -- Only update last_registered for Registered entries
        local updateQuery = 'UPDATE sv_register_logs SET last_registered = NOW() WHERE script_name = ? AND action = ?'
        
        local ok, err = pcall(function()
            exports.oxmysql:execute(updateQuery, {
                scriptName, 'Registered'
            }, function(rowsChanged)
                if Config.DebugLogging then
                    print('^2[sv_register]^0 ✓ Heartbeat updated: ' .. tostring(rowsChanged) .. ' rows')
                end
            end)
        end)
        
        if not ok then
            print('^1[sv_register]^0 ✗ Heartbeat error: ' .. tostring(err))
        end
    elseif action == 'Rogue' then
        -- Rogue entry: INSERT or UPDATE if already exists
        local insertQuery = [[INSERT INTO sv_register_logs (script_name, version, action, should_bypass, registered_at, last_registered) VALUES (?, ?, ?, ?, NULL, NULL) ON DUPLICATE KEY UPDATE version = VALUES(version), should_bypass = VALUES(should_bypass)]]

        local ok, err = pcall(function()
            exports.oxmysql:execute(insertQuery, {
                scriptName, 
                version or 'unknown', 
                action, 
                bypassVal
            }, function(rowsChanged)
                -- Silent for rogue inserts
            end)
        end)

        if not ok then
            print('^1[sv_register]^0 ✗ Rogue insert error for ' .. scriptName .. ': ' .. tostring(err))
        end
    elseif action == 'timeout_stop' then
        -- Timeout stop: just log, don't update action if already exists
        local insertQuery = [[
            INSERT INTO sv_register_logs (script_name, version, action, should_bypass, registered_at, last_registered)
            VALUES (?, ?, ?, ?, NULL, NULL)
            ON DUPLICATE KEY UPDATE version = VALUES(version), should_bypass = VALUES(should_bypass)
        ]]

        local ok, err = pcall(function()
            exports.oxmysql:execute(insertQuery, {
                scriptName,
                version or 'unknown',
                action,
                bypassVal
            }, function(rowsChanged)
                -- silent
            end)
        end)

        if not ok then
            print('^1[sv_register]^0 ✗ Timeout stop error for ' .. scriptName .. ': ' .. tostring(err))
        end
    else
        -- Registered entry: INSERT or UPDATE; if previously Rogue, promote to Registered and stamp times
        local insertQuery = [[
            INSERT INTO sv_register_logs (script_name, version, action, should_bypass, registered_at, last_registered)
            VALUES (?, ?, ?, ?, NOW(), NOW())
            ON DUPLICATE KEY UPDATE
                version = VALUES(version),
                action = VALUES(action),
                registered_at = IFNULL(registered_at, NOW()),
                last_registered = NOW(),
                should_bypass = VALUES(should_bypass)
        ]]

        local ok, err = pcall(function()
            exports.oxmysql:execute(insertQuery, {
                scriptName,
                version or 'unknown',
                action,
                bypassVal
            }, function(rowsChanged)
                -- success silent unless other logging desired
            end)
        end)

        if not ok then
            print('^1[sv_register]^0 ✗ REGISTERED INSERT ERROR: ' .. tostring(err))
        end
    end
end
-- Check if sv_core is running
local function checkSvCoreDetected()
    if Config.DisableIfSvCoreDetected then
        local resources = GetNumResources()
        for i = 0, resources - 1 do
            local resName = GetResourceByFindIndex(i)
            if resName and string.lower(resName) == 'sv_core' then
                logDebug('sv_core detected. Stopping sv_register...')
                SetTimeout(1000, function()
                    ExecuteCommand('stop sv_register')
                end)
                return true
            end
        end
    end
    return false
end

-- Register a script (called by script itself via event/export)
local function registerScript(scriptName, version)
    if not scriptName or scriptName == '' then
        return false, 'invalid_script_name'
    end

    local now = os.time()
    local uniqueId = ('%s_%d'):format(scriptName, now)
    local isFirstTime = not RegisteredScripts[scriptName]

    RegisteredScripts[scriptName] = {
        id = uniqueId,
        name = scriptName,
        version = version or 'unknown',
        action = 'Registered',
        registerDate = now,
        lastRegistered = now,
        shouldBypass = false,
    }

    if PendingScripts[scriptName] then
        PendingScripts[scriptName] = nil
    end

    print('^2[sv_register]^0 Script registered: ' .. scriptName .. ' (v' .. (version or 'unknown') .. ')')
    TriggerEvent('sv_register:scriptRegistered', scriptName, version)
    
    -- Log as "Registered" (script called the register function itself)
    if isFirstTime then
        dbLog('Registered', scriptName, version, false)
    else
        dbLog('Registered', scriptName, version, false)  -- Update last_registered only
    end
    logDebug(('Script registered: %s (v%s)'):format(scriptName, version or 'unknown'))

    return true, uniqueId
end

-- Register a script discovered by sv_register (auto-discovered, not explicitly registered)
local function registerRogueScript(scriptName)
    if not scriptName or scriptName == '' or RegisteredScripts[scriptName] then
        return false
    end

    local now = os.time()
    local uniqueId = ('%s_%d'):format(scriptName, now)

    local isBypassed = Config.BypassScripts[scriptName] == true

    RegisteredScripts[scriptName] = {
        id = uniqueId,
        name = scriptName,
        version = 'unknown',
        action = 'Rogue',
        registerDate = now,
        lastRegistered = now,
        shouldBypass = isBypassed,
        timeout = now + Config.RegistrationTimeout,
    }

    TriggerEvent('sv_register:rogueScriptFound', scriptName)
    
    -- Log as "Rogue" (discovered by sv_register, not self-registered)
    dbLog('Rogue', scriptName, 'unknown', false)

    return true, uniqueId
end

-- Update last registered timestamp only
local function updateLastRegistered(scriptName)
    local entry = RegisteredScripts[scriptName]
    if not entry then return end
    if entry.action ~= 'Registered' then return end

    entry.lastRegistered = os.time()
    -- Log as heartbeat update - only update last_registered in DB, don't log action
    dbLog('Heartbeat', scriptName, entry.version, false)
    logDebug(('Updated last_registered for: %s'):format(scriptName))
end

-- Mark script as should_bypass
local function setBypass(scriptName, bypass)
    if not RegisteredScripts[scriptName] then
        return false
    end
    
    RegisteredScripts[scriptName].shouldBypass = bypass
    
    -- Update database directly
    if exports and exports.oxmysql then
        local bypassVal = bypass and 1 or 0
        local updateOk, updateErr = pcall(function()
            exports.oxmysql:execute(
                'UPDATE sv_register_logs SET should_bypass = ? WHERE script_name = ?',
                { bypassVal, scriptName },
                function(rowsAffected)
                    if Config.DebugLogging then
                        print('^2[sv_register]^0 ✓ Bypass updated for ' .. scriptName .. ': ' .. tostring(bypass) .. ' (' .. tostring(rowsAffected) .. ' rows)')
                    end
                end
            )
        end)
        
        if not updateOk then
            print('^1[sv_register]^0 ✗ Failed to update bypass in database: ' .. tostring(updateErr))
            return false
        end
    end
    
    return true
end

local function parseBypassArg(val)
    if val == nil then return true end
    local v = tostring(val):lower()
    return v == '1' or v == 'true' or v == 'yes' or v == 'on'
end

-- Check for unregistered scripts and stop them
local LastStoppedRogue = {}

local function checkAndStopUnregistered()
    if not Config.AutoStopUnregistered then return end

    local now = os.time()
    local toStop = {}

    -- Check all running resources
    local numResources = GetNumResources()
    for i = 0, numResources - 1 do
        local resName = GetResourceByFindIndex(i)
        if resName and resName ~= 'sv_register' and GetResourceState(resName) == 'started' then
            local registered = RegisteredScripts[resName]

            if not registered then
                -- Script not registered
                if not PendingScripts[resName] then
                    PendingScripts[resName] = { registerTime = now, timeout = now + Config.RegistrationTimeout }
                    logDebug(('Added to pending: %s (timeout in %ds)'):format(resName, Config.RegistrationTimeout))
                end

                local pending = PendingScripts[resName]
                if now >= pending.timeout then
                    table.insert(toStop, resName)
                    PendingScripts[resName] = nil
                    dbLog('timeout_stop', resName, 'unknown', false)
                end
            elseif registered.shouldBypass then
                -- Script is bypassed, don't check it
                if PendingScripts[resName] then
                    PendingScripts[resName] = nil
                end
            elseif registered.action == 'Rogue' then
                registered.timeout = registered.timeout or (registered.registerDate + Config.RegistrationTimeout)
                if now >= registered.timeout then
                    table.insert(toStop, resName)
                    dbLog('timeout_stop', resName, registered.version or 'unknown', false)
                end
            else
                -- Registered scripts are trusted; do not stop them based on heartbeat age.
            end
        end
    end

    -- Stop scripts that timed out
    if #toStop > 0 then
        LastStoppedRogue = {}
        print(('^1[sv_register]^0 Stopped %d Rogue Script%s'):format(#toStop, #toStop == 1 and '' or 's'))
        for _, scriptName in ipairs(toStop) do
            StopResource(scriptName)
            TriggerEvent('sv_register:scriptStopped', scriptName, 'unregistered_timeout')
            table.insert(LastStoppedRogue, scriptName)

            -- Remove from tracking so we don't spam-stop
            RegisteredScripts[scriptName] = nil
            PendingScripts[scriptName] = nil
        end
    end
end

-- Scan and register all currently active resources
local function registerAllActiveResources()
    local numResources = GetNumResources()
    local rogueCount = 0

    for i = 0, numResources - 1 do
        local resName = GetResourceByFindIndex(i)
        if resName and resName ~= 'sv_register' and GetResourceState(resName) == 'started' then
            registerRogueScript(resName)
            rogueCount = rogueCount + 1
        end
    end
end

-- Load existing entries from database on startup
local function loadExistingEntries()
    if not exports or not exports.oxmysql then
        return
    end

    --logDebug('Loading existing database entries...')
    
    exports.oxmysql:execute(
        'SELECT script_name, version, action, should_bypass, UNIX_TIMESTAMP(registered_at) as reg_at, UNIX_TIMESTAMP(last_registered) as last_reg FROM sv_register_logs',
        {},
        function(results)
            if results then
                for _, row in ipairs(results) do
                    local regDate = row.reg_at or os.time()
                    local isRogue = (row.action == 'Rogue')
                    RegisteredScripts[row.script_name] = {
                        id = row.script_name,
                        name = row.script_name,
                        version = row.version or 'unknown',
                        action = row.action or 'Registered',
                        registerDate = isRogue and nil or regDate,
                        lastRegistered = isRogue and nil or (row.last_reg or regDate),
                        shouldBypass = row.should_bypass == 1,
                        timeout = regDate + Config.RegistrationTimeout,
                    }
                end
                --logDebug('Loaded ' .. #results .. ' existing entries from database')
            end
        end
    )
    
    -- Wait for database load to complete (max 2 seconds)
    local waitTime = 0
    while waitTime < 2000 do
        Wait(100)
        waitTime = waitTime + 100
        -- Check if we have any entries loaded
        local count = 0
        for _ in pairs(RegisteredScripts) do count = count + 1 end
        if count > 0 then
            break
        end
    end
end

-- ===== INITIALIZATION & MAIN LOOP =====
if checkSvCoreDetected() then
    logDebug('sv_core detected at startup. sv_register will not run.')
else
    -- Initialize database
    initDatabase()
    print('^2[sv_register]^0 Database connection successful')

    -- Load existing entries from database first
    loadExistingEntries()
    print('^2[sv_register]^0 Database fully initialized and ready')

    -- Register all currently active resources
    registerAllActiveResources()
    print('^2[sv_register]^0 Scanning for active resources...')
    
    -- Delay bypass count query to allow scripts to register
    SetTimeout(3000, function()
        if exports and exports.oxmysql then
            exports.oxmysql:execute(
                'SELECT COUNT(*) as count FROM sv_register_logs WHERE should_bypass = ?',
                { 1 },
                function(result)
                    if result and result[1] then
                        local bypassCount = result[1].count or 0
                        print(('^2[sv_register]^0 %d Script%s %s bypassed'):format(
                            bypassCount,
                            bypassCount == 1 and '' or 's',
                            bypassCount == 1 and 'is' or 'are'
                        ))
                    end
                end
            )
        end
    end)
    
    print('^2[sv_register]^0 sv_register initialized')

    -- Periodic check for unregistered scripts
    local checkRunning = true
    local function startPeriodicCheck()
        while checkRunning do
            Wait(Config.CheckInterval * 1000)
            checkAndStopUnregistered()
        end
    end
    CreateThread(startPeriodicCheck)

    -- Ensure timer cleanup on resource stop
    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            checkRunning = false
        end
    end)


end

-- ===== EXPORTS =====
exports('RegisterScript', function(scriptName, version)
    return registerScript(scriptName, version)
end)

-- ===== COMMANDS =====
RegisterCommand('stoppedrogue', function(source)
    if source ~= 0 then
        TriggerClientEvent('chat:addMessage', source, { args = { '^1[sv_register]', 'This command can only be run from console.' } })
        return
    end

    if not LastStoppedRogue or #LastStoppedRogue == 0 then
        print('^3[sv_register]^0 No rogue scripts have been stopped yet in this session.')
        return
    end

    print('^2[sv_register]^0 Rogue scripts stopped this session:')
    for _, name in ipairs(LastStoppedRogue) do
        print(' - ' .. name)
    end
end, false)

exports('GetRegisteredScripts', function()
    local scripts = {}
    for scriptName, data in pairs(RegisteredScripts) do
        table.insert(scripts, {
            scriptName = scriptName,
            version = data.version,
            registerDate = data.registerDate,
            lastRegistered = data.lastRegistered,
            shouldBypass = data.shouldBypass or false
        })
    end
    return scripts
end)

exports('SetBypass', function(scriptName, bypass)
    return setBypass(scriptName, bypass)
end)

-- Permission management exports
exports('GetPlayerPermissionLevel', function(playerId)
    return getPlayerPermissionLevel(playerId)
end)

exports('HasCommandPermission', function(playerId, commandName)
    return hasCommandPermission(playerId, commandName)
end)

-- Set persistent player permission by Steam ID
exports('SetPlayerPermission', function(identifier, rankName)
    if not identifier or not rankName then
        return false
    end
    
    if exports and exports.oxmysql then
        exports.oxmysql:execute(
            'INSERT INTO sv_register_player_perms (identifier, rank_name) VALUES (?, ?) ON DUPLICATE KEY UPDATE rank_name = ?',
            { identifier, rankName, rankName },
            function(result)
                -- silent
            end
        )
    end
    
    return true
end)

exports('SetPlayerSteamIDPermission', function(steamId, level)
    return exports['sv_register']:SetPlayerPermission(steamId, level)
end)

-- Set permission for a player by their player ID (for admin UI)
exports('SetPlayerPermissionByID', function(playerId, rankName)
    if not playerId or not rankName then
        return false
    end
    
    -- Get player's Steam ID
    local steamId = GetPlayerIdentifier(playerId, 0)
    if not steamId or not string.match(steamId, '^steam:') then
        return false
    end
    
    -- Use SetPlayerPermission with Steam ID
    return exports['sv_register']:SetPlayerPermission(steamId, rankName)
end)

exports('SetPlayerLicensePermission', function(license, level)
    return exports['sv_register']:SetPlayerPermission(license, level)
end)

-- ===== EVENTS =====
RegisterNetEvent('sv_register:register', function(scriptName, version)
    print('^5[sv_register]^0 [EVENT] sv_register:register triggered: ' .. tostring(scriptName) .. ', ' .. tostring(version))
    registerScript(scriptName, version)
end)

RegisterNetEvent('sv_register:heartbeat', function(scriptName)
    print('^5[sv_register]^0 [EVENT] sv_register:heartbeat triggered: ' .. tostring(scriptName))
    updateLastRegistered(scriptName)
end)

RegisterNetEvent('sv_register:setBypass', function(scriptName, bypass)
    print('^5[sv_register]^0 [EVENT] sv_register:setBypass triggered: ' .. tostring(scriptName) .. ', ' .. tostring(bypass))
end)

-- ===== ADMIN COMMANDS =====
RegisterCommand('reglist', function(source, args)
    if not hasCommandPermission(source, 'reglist') then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'You do not have permission to use this command.' }
        })
        return
    end

    print('^2' .. string.rep('=', 50) .. '^0')
    print('^2Registered Scripts:^0')
    for name, data in pairs(RegisteredScripts) do
        local status = data.shouldBypass and ' (^3BYPASS^0)' or ''
        print(('  • %s (v%s)%s'):format(name, data.version, status))
        print(('    Registered: %s | Last: %s'):format(
            os.date('%Y-%m-%d %H:%M:%S', data.registerDate),
            os.date('%Y-%m-%d %H:%M:%S', data.lastRegistered)
        ))
    end

    if next(PendingScripts) then
        print('^3Pending (timeout):^0')
        for name, data in pairs(PendingScripts) do
            local timeLeft = math.max(0, data.timeout - os.time())
            print(('  • %s (timeout in %ds)'):format(name, timeLeft))
        end
    end

    print('^2' .. string.rep('=', 50) .. '^0')
end, false)

RegisterCommand('regbypass', function(source, args)
    local hasPerm = source == 0 or hasCommandPermission(source, 'regbypass')
    if not hasPerm then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'You do not have permission to use this command.' }
        })
        return
    end

    if not args[1] then
        local msg = '^1[sv_register]^0 Usage: /regbypass <script_name> [1|0]'
        if source == 0 then print(msg) else TriggerClientEvent('chat:addMessage', source, { args = { msg } }) end
        return
    end

    local scriptName = args[1]
    local bypass = parseBypassArg(args[2])

    if not RegisteredScripts[scriptName] and bypass then
        local now = os.time()
        RegisteredScripts[scriptName] = {
            id = ('%s_bypass'):format(scriptName),
            name = scriptName,
            version = 'unknown',
            action = 'BypassManual',
            registerDate = now,
            lastRegistered = now,
            shouldBypass = true,
            timeout = now + Config.RegistrationTimeout,
        }
        PendingScripts[scriptName] = nil
        dbLog('Rogue', scriptName, 'unknown', true)
    elseif not RegisteredScripts[scriptName] and not bypass then
        local msg = ('^1[sv_register]^0 Script not found: %s'):format(scriptName)
        if source == 0 then print(msg) else TriggerClientEvent('chat:addMessage', source, { args = { msg } }) end
        return
    end

    if setBypass(scriptName, bypass) then
        local status = bypass and '^2BYPASSED^0' or '^3NOT BYPASSED^0'
        local msg = ('^2[sv_register]^0 Updated bypass for %s: %s'):format(scriptName, status)
        if source == 0 then print(msg) else TriggerClientEvent('chat:addMessage', source, { args = { msg } }) end
        if Config.DebugLogging then
            print(('[sv_register] %s marked as bypass = %s'):format(scriptName, tostring(bypass)))
        end

        if bypass then
            local state = GetResourceState(scriptName)
            if state == 'stopped' or state == 'stopping' or state == 'uninitialized' then
                local ok = pcall(StartResource, scriptName)
                if not ok then
                    ok = pcall(function() ExecuteCommand(('start %s'):format(scriptName)) end)
                end
                local startMsg = ok and ('^2[sv_register]^0 Started %s after bypass'):format(scriptName)
                                or ('^1[sv_register]^0 Failed to start %s after bypass'):format(scriptName)
                if source == 0 then print(startMsg) else TriggerClientEvent('chat:addMessage', source, { args = { startMsg } }) end
            end
        end
    else
        local msg = ('^1[sv_register]^0 Failed to set bypass for %s'):format(scriptName)
        if source == 0 then print(msg) else TriggerClientEvent('chat:addMessage', source, { args = { msg } }) end
    end
end, false)

RegisterCommand('feed', function(source, args)
    -- Player-only command
    if source == 0 then
        print('^1[sv_register]^0 This command cannot be used from console.')
        return
    end

    if not hasCommandPermission(source, 'feed') then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'You do not have permission to use this command.' }
        })
        return
    end

    -- Require a target player ID
    local targetId = tonumber(args[1])
    if not targetId then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'Usage: /feed <player_id>' }
        })
        return
    end

    local targetName = GetPlayerName(targetId)
    if not targetName then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'Target player not found.' }
        })
        return
    end

    -- Check if ESX is available
    if exports and exports['es_extended'] then
        local ok, ESX = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        
        if ok and ESX then
            local xTarget = ESX.GetPlayerFromId(targetId)
            if xTarget then
                -- Use esx_status to adjust hunger/thirst on target
                if exports['esx_status'] then
                    TriggerClientEvent('esx_status:add', targetId, 'hunger', 1000000)
                    TriggerClientEvent('esx_status:add', targetId, 'thirst', 1000000)
                end

                -- Also try basicneeds heal (sets vitals, may include thirst/hunger depending on version)
                TriggerClientEvent('esx_basicneeds:healPlayer', targetId)

                -- Feedback
                TriggerClientEvent('chat:addMessage', source, {
                    args = { '^2[sv_register]', ('Restored hunger/thirst for %s [%d].'):format(targetName, targetId) }
                })
                TriggerClientEvent('chat:addMessage', targetId, {
                    args = { '^2[sv_register]', 'Your hunger and thirst have been restored by an admin.' }
                })
            else
                TriggerClientEvent('chat:addMessage', source, {
                    args = { '^1[sv_register]', 'Failed to get target ESX player.' }
                })
            end
        else
            TriggerClientEvent('chat:addMessage', source, {
                args = { '^1[sv_register]', 'Failed to get ESX object.' }
            })
        end
    else
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'ESX not available.' }
        })
    end
end, false)

RegisterCommand('setperm', function(source, args)
    -- Console only command
    if source ~= 0 then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'This command can only be used from console.' }
        })
        return
    end

    local targetId = tonumber(args[1])
    local rankName = args[2]

    if not targetId or not rankName then
        print('^1[sv_register]^0 Usage: setperm <player_id> <rank_name>')
        print('^3Examples:^0 setperm 1 admin, setperm 1 moderator, setperm 1 owner')
        return
    end

    local targetPlayer = GetPlayerName(targetId)
    if not targetPlayer then
        print('^1[sv_register]^0 Player not found')
        return
    end

    -- Get player identifiers (try Steam first, then license)
    local identifier = nil
    for i = 0, GetNumPlayerIdentifiers(targetId) - 1 do
        local id = GetPlayerIdentifier(targetId, i)
        if id and string.match(id, '^steam:') then
            identifier = id
            break
        end
    end

    -- Fall back to license if no Steam ID
    if not identifier then
        for i = 0, GetNumPlayerIdentifiers(targetId) - 1 do
            local id = GetPlayerIdentifier(targetId, i)
            if id and string.match(id, '^license:') then
                identifier = id
                break
            end
        end
    end

    if not identifier then
        print('^1[sv_register]^0 Could not find Steam ID or License for player')
        return
    end

    -- Set permission via export
    local success = exports['sv_register']:SetPlayerPermission(identifier, rankName)
    
    if success then
        print(string.format('^2[sv_register]^0 Set rank "%s" for player %s (%s)', rankName, targetPlayer, identifier))
    else
        print('^1[sv_register]^0 Failed to set permission')
    end
end)

RegisterCommand('reggit', function(source, args)
    if not hasCommandPermission(source, 'reggit') then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'You do not have permission to use this command.' }
        })
        return
    end

    local targetScript = args[1]
    if targetScript and RegisteredScripts[targetScript] then
        local data = RegisteredScripts[targetScript]
        print('^2' .. string.rep('=', 50) .. '^0')
        print(('Script: %s'):format(data.name))
        print(('Version: %s'):format(data.version))
        print(('Unique ID: %s'):format(data.id))
        print(('Registered: %s'):format(os.date('%Y-%m-%d %H:%M:%S', data.registerDate)))
        print(('Last Registered: %s'):format(os.date('%Y-%m-%d %H:%M:%S', data.lastRegistered)))
        print(('Should Bypass: %s'):format(tostring(data.shouldBypass)))
        print('^2' .. string.rep('=', 50) .. '^0')
    else
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[sv_register]', 'Usage: /reggit <script_name>' }
        })
    end
end, false)
