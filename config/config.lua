-- sv_register config
Config = {}

-- Registration timeout (in seconds) — scripts must register within this time or be stopped
Config.RegistrationTimeout = 60  -- allow more time before any stop actions

-- Enable/disable auto-stopping of unregistered scripts
Config.AutoStopUnregistered = false

-- Database type: 'mysql' or 'sqlite'
Config.DatabaseType = 'mysql'

-- MySQL connection (if DatabaseType == 'mysql')
Config.MySQL = {
    Host = 'localhost',
    Port = 3306,
    Username = 'root',
    Password = 'password',
    Database = 'fivem',
}

-- SQLite file path (if DatabaseType == 'sqlite')
Config.SQLitePath = 'resources/[scripts]/[SanctusVoid]/sv_register/data.db'

-- Check interval for registration timeout (in seconds)
Config.CheckInterval = 10

-- List of scripts that should always bypass registration (set should_bypass = 1 in database)
Config.BypassScripts = {}

-- If sv_core is detected, should sv_register disable itself?
Config.DisableIfSvCoreDetected = true

-- Enable logging to console
Config.DebugLogging = false

-- ===== PERMISSION SYSTEM =====
-- Custom permission levels (0 = no access, 1 = view only, 2 = manage bypass, 3 = full admin)
Config.Permissions = {
    -- Permission levels: 0 (none), 1 (viewer), 2 (manager), 3 (admin)
    DefaultLevel = 0,  -- Default permission level for unknown players

    -- Steam IDs with specific permissions (use 'steam:xxxxx' format)
    SteamIDPermissions = {
        -- ['steam:110000112345678'] = 3,  -- Example: Full admin
    },

    -- License IDs with specific permissions (use 'license:xxxxx' format)
    LicensePermissions = {
        -- ['license:abc123def456'] = 2,  -- Example: Manager
    },

    -- ESX job-based permissions (if ESX is available)
    -- { job = 'jobname', grade = minimumGrade, permissionLevel = level }
    ESXJobPermissions = {
        { job = 'admin', grade = 0, permissionLevel = 3 },
        { job = 'boss', grade = 0, permissionLevel = 2 },
    },

    -- QBCore job-based permissions (if QBCore is available)
    QBCoreJobPermissions = {
        { job = 'admin', grade = 0, permissionLevel = 3 },
        { job = 'police', grade = 3, permissionLevel = 2 },
    },

    -- Command permissions (which permission level is required for each command)
    CommandPermissions = {
        reglist = 1,    -- 1+ = viewer
        regbypass = 2,  -- 2+ = manager
        reggit = 1,     -- 1+ = viewer
    },
}

-- Command descriptions for help
Config.CommandDescriptions = {
    reglist = 'List all registered and pending scripts',
    regbypass = 'Set bypass status for a script',
    reggit = 'Get detailed info on a registered script',
}
