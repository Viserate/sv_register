# SV_Register

SV_Register is a lightweight rank and identity management system for FiveM servers.

It centralizes player rank storage and structured role handling for SV ecosystem resources. Designed to remove hardcoded rank logic from individual scripts, SV_Register provides a clean, scalable backend for role-based systems.

This resource focuses strictly on rank and identity structure. It does not handle permissions enforcement by itself.

---

## ✨ Features

- Centralized rank storage
- Structured role registration system
- Database-backed persistence
- Framework agnostic
- Lightweight and modular design
- Built for SV ecosystem resources

---

## 🎯 Purpose

Many FiveM servers hardcode rank logic into every script.  
This creates:

- Duplicate logic
- Difficult updates
- Inconsistent role handling
- Poor scalability

SV_Register solves that by:

- Acting as a single source of truth for ranks
- Standardizing how scripts check rank data
- Reducing repeated backend logic
- Supporting future scalability

---

## 🗄️ Database

SV_Register stores rank and player registration data in MySQL.

Ensure your database is properly configured before starting the resource.

---

## 🔌 Dependencies

- MySQL (oxmysql recommended)
- SV_Compat (recommended for ecosystem consistency)

Framework independent. No ESX/QBCore requirement.

---

## 📦 Installation

1. Place the folder in your `resources` directory  
2. Import the provided SQL file into your database  
3. Add to your `server.cfg`:

```cfg
ensure sv_register
```

4. Restart server  

---

## 🧠 How It Works

SV_Register:

- Registers players into a structured system
- Stores their assigned rank
- Allows other resources to query rank data
- Maintains consistent role structure across SV resources

Other scripts can query rank information through exports rather than managing their own rank tables.

---

## 🔁 Example Usage

Example export call from another resource:

```lua
local rank = exports['sv_register']:getPlayerRank(source)

if rank == "developer" then
    -- Do something
end
```

---

## 🛠️ Designed For

- Servers using the SV ecosystem
- Developers who want centralized rank logic
- Projects focused on modular architecture
- Long-term scalable server builds
