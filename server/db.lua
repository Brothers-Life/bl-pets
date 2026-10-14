--- bl_pets -- persistance (table `bl_pets`, propriete de cette ressource).
---
--- LA SEQUENCE DE SCHEMA EST UNIQUE ET SOUS pcall. Une erreur au CHARGEMENT
--- d'un fichier serveur fait disparaitre tous les exports declares apres elle
--- dans ce fichier -- et la boutique appelle GrantPet a l'aveugle. Rien ici ne
--- peut donc lever au chargement : la requete part dans un thread, son echec
--- est journalise, et `Pets.Ready` reste faux (les exports repondent alors
--- `nil, 'not_ready'` au lieu de lever).

Pets = Pets or {}
Pets.Ready = false
Pets.Db = {}

local SCHEMA = {
    [[
        CREATE TABLE IF NOT EXISTS `bl_pets` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `species` VARCHAR(32) NOT NULL,
            `name` VARCHAR(64) NOT NULL,
            `traits` LONGTEXT NULL,
            `health` TINYINT UNSIGNED NOT NULL DEFAULT 100,
            `hunger` TINYINT UNSIGNED NOT NULL DEFAULT 100,
            `xp` INT UNSIGNED NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `source` VARCHAR(32) NOT NULL DEFAULT 'admin',
            PRIMARY KEY (`id`),
            KEY `idx_bl_pets_citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Journal du panel staff (/petadmin) et des adoptions.
    [[
        CREATE TABLE IF NOT EXISTS `bl_pets_logs` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `actor` VARCHAR(64) NOT NULL,
            `actor_name` VARCHAR(100) NULL,
            `action` VARCHAR(32) NOT NULL,
            `pet_id` INT UNSIGNED NULL,
            `citizenid` VARCHAR(50) NULL,
            `details` TEXT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_bl_pets_logs_pet` (`pet_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
}

CreateThread(function()
    local ok, err = pcall(function()
        for i = 1, #SCHEMA do
            MySQL.query.await(SCHEMA[i])
        end
    end)

    if ok then
        Pets.Ready = true
    else
        print(('^1[bl_pets] creation du schema impossible : %s^7'):format(tostring(err)))
    end
end)

--- Attend la fin de la sequence de schema (au plus `timeoutMs`).
---@param timeoutMs integer?
---@return boolean
function Pets.AwaitReady(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while not Pets.Ready and GetGameTimer() < deadline do
        Wait(100)
    end
    return Pets.Ready
end

--- Ligne SQL -> animal (traits decodes, nombres normalises).
---@param row table?
---@return table?
local function decode(row)
    if not row then return nil end

    local traits = {}
    if type(row.traits) == 'string' and row.traits ~= '' then
        local ok, value = pcall(json.decode, row.traits)
        if ok and type(value) == 'table' then traits = value end
    end

    return {
        id = tonumber(row.id),
        citizenid = row.citizenid,
        species = row.species,
        name = row.name,
        traits = traits,
        health = tonumber(row.health) or 100,
        hunger = tonumber(row.hunger) or 100,
        xp = tonumber(row.xp) or 0,
        created_at = row.created_at,
        source = row.source,
    }
end

local COLUMNS = 'id, citizenid, species, name, traits, health, hunger, xp, created_at, source'

---@param id integer
---@return table?
function Pets.Db.get(id)
    local ok, row = pcall(MySQL.single.await,
        ('SELECT %s FROM bl_pets WHERE id = ?'):format(COLUMNS), { id })
    if not ok then
        print(('^1[bl_pets] lecture de l\'animal %s : %s^7'):format(id, tostring(row)))
        return nil
    end
    return decode(row)
end

---@param citizenid string
---@return table[]
function Pets.Db.listByOwner(citizenid)
    local ok, rows = pcall(MySQL.query.await,
        ('SELECT %s FROM bl_pets WHERE citizenid = ? ORDER BY id'):format(COLUMNS), { citizenid })
    if not ok or type(rows) ~= 'table' then return {} end

    local list = {}
    for i = 1, #rows do list[i] = decode(rows[i]) end
    return list
end

---@param citizenid string
---@return integer
function Pets.Db.countByOwner(citizenid)
    local ok, count = pcall(MySQL.scalar.await,
        'SELECT COUNT(*) FROM bl_pets WHERE citizenid = ?', { citizenid })
    return ok and tonumber(count) or 0
end

---@param pet table { citizenid, species, name, traits, source }
---@return integer?
function Pets.Db.insert(pet)
    local ok, id = pcall(MySQL.insert.await,
        'INSERT INTO bl_pets (citizenid, species, name, traits, health, hunger, source) VALUES (?, ?, ?, ?, 100, 100, ?)',
        { pet.citizenid, pet.species, pet.name, json.encode(pet.traits or {}), pet.source })
    if not ok then
        print(('^1[bl_pets] adoption impossible : %s^7'):format(tostring(id)))
        return nil
    end
    return tonumber(id)
end

---@param id integer
---@param health number
---@param hunger number
---@param xp number?
---@param wait boolean? attendre la fin (false a l'arret de la ressource)
function Pets.Db.saveStats(id, health, hunger, xp, wait)
    -- -1 et non nil pour « xp inchange » : un nil au milieu de la liste la
    -- transforme en map msgpack et la requete echoue.
    local query = 'UPDATE bl_pets SET health = ?, hunger = ?, xp = COALESCE(NULLIF(?, -1), xp) WHERE id = ?'
    local params = {
        math.floor(math.max(0, math.min(100, health)) + 0.5),
        math.floor(math.max(0, math.min(100, hunger)) + 0.5),
        xp and math.floor(xp) or -1,
        id,
    }

    if wait then
        local ok, err = pcall(MySQL.update.await, query, params)
        if not ok then print(('^1[bl_pets] sauvegarde de %s : %s^7'):format(id, tostring(err))) end
        return ok
    end

    MySQL.update(query, params)
    return true
end

---@param id integer
---@param name string
---@return boolean
function Pets.Db.rename(id, name)
    -- Le nombre de lignes n'est pas teste : renommer a l'identique en rend 0
    -- selon le mode de comptage du serveur MySQL, sans etre un echec.
    local ok, err = pcall(MySQL.update.await, 'UPDATE bl_pets SET name = ? WHERE id = ?', { name, id })
    if not ok then print(('^1[bl_pets] renommage de %s : %s^7'):format(id, tostring(err))) end
    return ok
end

-- Panel staff ---------------------------------------------------------------------------
-- Toutes les requetes sont parametrees ; les seuls morceaux de SQL assembles
-- sont des listes de `?` et des noms de colonnes constants.

--- Liste de `?` pour un IN (...).
local function marks(n)
    return ('?, '):rep(n - 1) .. '?'
end

--- Recherche staff. `q` : n° d'animal, nom, citizenid, ou citizenids des
--- proprietaires dont le nom correspond (`owners`, resolus avant).
---@param f table { q = string?, species = string?, kinds = string[]?, owners = string[]?, limit = integer }
---@return table[]
function Pets.Db.search(f)
    local where, params = {}, {}

    if f.species then
        where[#where + 1] = 'species = ?'
        params[#params + 1] = f.species
    elseif f.speciesIn and #f.speciesIn > 0 then
        where[#where + 1] = ('species IN (%s)'):format(marks(#f.speciesIn))
        for i = 1, #f.speciesIn do params[#params + 1] = f.speciesIn[i] end
    end

    if f.q and f.q ~= '' then
        local like = '%' .. f.q:gsub('[%%_\\]', '\\%0') .. '%'
        local any = { 'name LIKE ?', 'citizenid LIKE ?' }
        params[#params + 1] = like
        params[#params + 1] = like
        if tonumber(f.q) then
            any[#any + 1] = 'id = ?'
            params[#params + 1] = tonumber(f.q)
        end
        if f.owners and #f.owners > 0 then
            any[#any + 1] = ('citizenid IN (%s)'):format(marks(#f.owners))
            for i = 1, #f.owners do params[#params + 1] = f.owners[i] end
        end
        where[#where + 1] = '(' .. table.concat(any, ' OR ') .. ')'
    end

    params[#params + 1] = f.limit or 500
    local sql = ('SELECT %s FROM bl_pets %s ORDER BY id DESC LIMIT ?'):format(COLUMNS,
        #where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or '')

    local ok, rows = pcall(MySQL.query.await, sql, params)
    if not ok or type(rows) ~= 'table' then
        if not ok then print(('^1[bl_pets] recherche staff : %s^7'):format(tostring(rows))) end
        return {}
    end
    local list = {}
    for i = 1, #rows do list[i] = decode(rows[i]) end
    return list
end

--- Chiffres globaux : par espece, total, blesses, affames, proprietaires.
---@return table { rows = { { species, count, injured, hungry } }, owners = integer }
function Pets.Db.stats()
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT species, COUNT(*) AS n,
               SUM(health <= ?) AS injured,
               SUM(hunger < ?) AS hungry
        FROM bl_pets GROUP BY species
    ]], { Config.InjuredThreshold, Config.HungryThreshold })
    local okOwners, owners = pcall(MySQL.scalar.await, 'SELECT COUNT(DISTINCT citizenid) FROM bl_pets')
    return {
        rows = ok and type(rows) == 'table' and rows or {},
        owners = okOwners and tonumber(owners) or 0,
    }
end

--- Proprietaires les mieux pourvus.
function Pets.Db.topOwners(limit)
    local ok, rows = pcall(MySQL.query.await,
        'SELECT citizenid, COUNT(*) AS n FROM bl_pets GROUP BY citizenid ORDER BY n DESC LIMIT ?', { limit or 5 })
    return ok and type(rows) == 'table' and rows or {}
end

--- Modification staff d'un animal. Seules les colonnes de la liste blanche
--- passent ; les valeurs sont deja validees par server/admin.lua.
local EDITABLE = { name = true, species = true, health = true, hunger = true, xp = true, traits = true, citizenid = true }

---@param id integer
---@param fields table
---@return boolean
function Pets.Db.adminUpdate(id, fields)
    local set, params = {}, {}
    for column, value in pairs(fields) do
        if EDITABLE[column] then
            set[#set + 1] = ('`%s` = ?'):format(column)
            params[#params + 1] = column == 'traits' and json.encode(value) or value
        end
    end
    if #set == 0 then return true end
    params[#params + 1] = id
    local ok, err = pcall(MySQL.update.await, ('UPDATE bl_pets SET %s WHERE id = ?'):format(table.concat(set, ', ')), params)
    if not ok then print(('^1[bl_pets] modification staff de %s : %s^7'):format(id, tostring(err))) end
    return ok
end

---@param id integer
---@return boolean
function Pets.Db.delete(id)
    local ok, err = pcall(MySQL.update.await, 'DELETE FROM bl_pets WHERE id = ?', { id })
    if not ok then print(('^1[bl_pets] suppression de %s : %s^7'):format(id, tostring(err))) end
    return ok
end

--- Noms de personnages (table `players` de qbx_core). Sans cette table, ou en
--- cas d'erreur : table vide, le panel affiche alors les citizenid.
---@param citizenids string[]
---@return table<string, string>
function Pets.Db.ownerNames(citizenids)
    local names = {}
    if #citizenids == 0 then return names end
    local ok, rows = pcall(MySQL.query.await,
        ('SELECT citizenid, charinfo FROM players WHERE citizenid IN (%s)'):format(marks(#citizenids)), citizenids)
    if not ok or type(rows) ~= 'table' then return names end
    for i = 1, #rows do
        local okInfo, info = pcall(json.decode, rows[i].charinfo or '')
        if okInfo and type(info) == 'table' then
            names[rows[i].citizenid] = ('%s %s'):format(info.firstname or '', info.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
        end
    end
    return names
end

--- Citizenids dont le nom de personnage contient `q` (recherche staff).
---@param q string
---@return string[]
function Pets.Db.findOwners(q)
    local like = '%' .. q:gsub('[%%_\\]', '\\%0') .. '%'
    local ok, rows = pcall(MySQL.query.await,
        'SELECT citizenid FROM players WHERE charinfo LIKE ? LIMIT 100', { like })
    local list = {}
    if ok and type(rows) == 'table' then
        for i = 1, #rows do list[#list + 1] = rows[i].citizenid end
    end
    return list
end

---@param entry table { actor, actor_name, action, pet_id, citizenid, details }
function Pets.Db.log(entry)
    MySQL.insert('INSERT INTO bl_pets_logs (actor, actor_name, action, pet_id, citizenid, details) VALUES (?, ?, ?, ?, ?, ?)', {
        tostring(entry.actor or 'console'):sub(1, 64),
        entry.actor_name and tostring(entry.actor_name):sub(1, 100) or nil,
        tostring(entry.action):sub(1, 32),
        entry.pet_id,
        entry.citizenid,
        entry.details and json.encode(entry.details) or nil,
    })
end

---@param petId integer?
---@param limit integer
---@return table[]
function Pets.Db.logs(petId, limit)
    local sql = 'SELECT id, created_at, actor, actor_name, action, pet_id, citizenid, details FROM bl_pets_logs'
    local params = {}
    if petId then
        sql = sql .. ' WHERE pet_id = ?'
        params[1] = petId
    end
    params[#params + 1] = limit or 100
    local ok, rows = pcall(MySQL.query.await, sql .. ' ORDER BY id DESC LIMIT ?', params)
    if not ok or type(rows) ~= 'table' then return {} end
    for i = 1, #rows do
        local okD, d = pcall(json.decode, rows[i].details or '')
        rows[i].details = okD and d or nil
    end
    return rows
end
