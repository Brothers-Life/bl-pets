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
