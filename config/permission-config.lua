-- SanctusVoid Permission Configuration
-- Rank-based permission system with inheritance support

PermissionConfig = {
    -- Define ranks with inheritance hierarchy
    Ranks = {
        ['none'] = {
            level = 0,
            label = 'No Access',
            inherits = {}, -- inherits nothing
            permissions = {},
        },
        ['viewer'] = {
            level = 1,
            label = 'Viewer',
            inherits = { 'none' },
            permissions = {
                'reglist',          -- can view registered scripts
                'view_permissions', -- can see who has permissions
            },
        },
        ['Moderator'] = {
            level = 2,
            label = 'Moderator',
            inherits = { 'viewer', 'none' },
            permissions = {
                'regbypass',        -- can bypass registration timeout
                'manage_bypass',    -- can manage bypass list
                'update_heartbeat', -- can update script heartbeat
            },
        },
        ['Lead-Moderator'] = {
            level = 3,
            label = 'Lead Moderator',
            inherits = { 'manager', 'viewer', 'none' },
            permissions = {
                'reggit',              -- can stop scripts
                'feed',                -- can restore hunger/thirst
                'manage_permissions',  -- can assign permissions
                'manage_ranks',        -- can modify rank assignments
                'view_logs',           -- can view registration logs
            },
        },
        ['Admin'] = {
            level = 4,
            label = 'Admin',
            inherits = { 'admin', 'manager', 'viewer', 'none' },
            permissions = {
                'all', -- wildcard: grants all permissions
            },
        },
        ['Lead-Admin'] = {
            level = 5,
            label = 'Lead Admin',
            inherits = { 'admin', 'manager', 'viewer', 'none' },
            permissions = {
                'all', -- wildcard: grants all permissions
            },
        },
        ['Admission'] = {
            level = 6,
            label = 'Admissions',
            inherits = { 'admin', 'manager', 'viewer', 'none' },
            permissions = {
                'all', -- wildcard: grants all permissions
            },
        },
        ['Lead-Admission'] = {
            level = 7,
            label = 'Lead Admissions',
            inherits = { 'admin', 'manager', 'viewer', 'none' },
            permissions = {
                'all', -- wildcard: grants all permissions
            },
        },
        ['Developer'] = {
            level = 8,
            label = 'Developer',
            inherits = { 'admin', 'manager', 'viewer', 'none' },
            permissions = {
                'all', -- wildcard: grants all permissions
            },
        },
        ['owner'] = {
            level = 9,
            label = 'Owner',
            inherits = { 'admin', 'manager', 'viewer', 'none' },
            permissions = {
                'all', -- wildcard: grants all permissions
            },
        },
    },

    -- Permission-to-Command mappings
    -- Which permissions are required for which commands
    CommandPermissions = {
        reglist = { 'reglist' },
        regbypass = { 'regbypass' },
        reggit = { 'reggit' },
        remperm = { 'manage_permissions' },
    },

    -- Rank assignment by identifier type
    -- Priority order: SteamID > License > ESX Job > QBCore Job > Default
    Assignments = {
        -- Steam ID assignments
        SteamID = {
            -- ['11050701234567890'] = 'admin',
            -- ['11050701234567891'] = 'manager',
        },

        -- License assignments (from license:xxx identifier)
        License = {
            -- ['license:abc123def456'] = 'viewer',
        },

        -- ESX Job assignments
        ESXJob = {
            -- ['job_name'] = { rank = 'manager', minGrade = 5 },
            -- ['police'] = { rank = 'admin', minGrade = 10 },
            -- ['judge'] = { rank = 'viewer', minGrade = 0 },
        },

        -- QBCore Job assignments
        QBCoreJob = {
            -- ['jobname'] = { rank = 'manager', minGrade = 5 },
            -- ['police'] = { rank = 'admin', minGrade = 10 },
        },
    },

    -- Default rank if no assignment found
    DefaultRank = 'none',

    -- Enable permission inheritance (recommended: true)
    EnableInheritance = true,

    -- Enable debug logging
    DebugLogging = false,
}

-- Helper function to get all permissions for a rank (including inherited)
function GetRankPermissions(rankName)
    if not PermissionConfig.Ranks[rankName] then
        return {}
    end

    local rank = PermissionConfig.Ranks[rankName]
    local permissions = {}

    -- Add own permissions
    for _, perm in ipairs(rank.permissions) do
        permissions[perm] = true
    end

    -- Add inherited permissions
    if PermissionConfig.EnableInheritance and rank.inherits then
        for _, inheritedRank in ipairs(rank.inherits) do
            local inheritedPerms = GetRankPermissions(inheritedRank)
            for perm, _ in pairs(inheritedPerms) do
                permissions[perm] = true
            end
        end
    end

    return permissions
end

-- Helper function to check if rank has permission
function RankHasPermission(rankName, permissionName)
    if not PermissionConfig.Ranks[rankName] then
        return false
    end

    local rank = PermissionConfig.Ranks[rankName]

    -- Check for wildcard
    for _, perm in ipairs(rank.permissions) do
        if perm == 'all' then
            return true
        end
    end

    -- Get all permissions (including inherited)
    local permissions = GetRankPermissions(rankName)
    return permissions[permissionName] or false
end

-- Helper function to get rank level
function GetRankLevel(rankName)
    if PermissionConfig.Ranks[rankName] then
        return PermissionConfig.Ranks[rankName].level
    end
    return 0
end

-- Helper function to get rank label
function GetRankLabel(rankName)
    if PermissionConfig.Ranks[rankName] then
        return PermissionConfig.Ranks[rankName].label
    end
    return 'Unknown'
end

-- Helper to list all available permissions
function GetAllPermissions()
    local allPerms = {}
    for rankName, rankData in pairs(PermissionConfig.Ranks) do
        for _, perm in ipairs(rankData.permissions) do
            if perm ~= 'all' then
                allPerms[perm] = true
            end
        end
    end
    return allPerms
end

return PermissionConfig
