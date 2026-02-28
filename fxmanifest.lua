fx_version 'cerulean'
games { 'gta5' }

author 'SanctusVoid'
description 'sv_register — script registration and lifecycle management system'
version '1.0.0'

shared_script 'config/config.lua'
shared_script 'config/permission-config.lua'
server_script 'server/sv_register.lua'
client_script 'client/*.lua'

-- Exports:
--  - RegisterScript(scriptName, version) — called by other scripts to register
--  - GetRegisteredScripts() — returns table of registered scripts

-- Events:
--  - sv_register:scriptRegistered — fired when a script registers
--  - sv_register:scriptStopped — fired when a script is auto-stopped (unregistered/timeout)
