--- bl_pets -- panel staff (/petadmin).
---
--- LE DROIT EST REVERIFIE A CHAQUE REQUETE. La commande est reservee a
--- Config.Admin.group (ox_lib pose l'ace `command.<commande>` sur ce groupe) ;
--- le rappel `bl_pets:server:admin` controle ce meme ace avant tout, la page
--- NUI ne decide de rien.
---
--- Toute modification passe par la base PUIS par l'etat vivant (animal sorti)
--- s'il y en a un : sans ca, le tic suivant reecrirait l'ancienne valeur.
--- Chaque geste est journalise dans `bl_pets_logs`.

local A = Pets.Internal
local ACE = ('command.%s'):format(Config.Admin.command)

---@param src integer
---@return boolean
local function isStaff(src)
    return src == 0 or IsPlayerAceAllowed(src, ACE)
end

--- Identite du staff pour le journal.
local function actorOf(src)
    if src == 0 then return 'console', 'Console' end
    return A.citizenIdOf(src) or GetPlayerIdentifierByType(src, 'license') or ('src:%d'):format(src),
        GetPlayerName(src) or ('#%d'):format(src)
end

local function log(src, action, petId, citizenid, details)
    local actor, name = actorOf(src)
    Pets.Db.log({ actor = actor, actor_name = name, action = action, pet_id = petId, citizenid = citizenid, details = details })
end

--- Nom du personnage d'un joueur en ligne.
local function charName(player)
    local info = player and player.PlayerData and player.PlayerData.charinfo
    if not info then return nil end
    return ('%s %s'):format(info.firstname or '', info.lastname or '')
end

---@param citizenid string
---@return integer? source
local function onlineSource(citizenid)
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    return player and player.PlayerData and player.PlayerData.source or nil
end

local function refreshOwner(citizenid)
    local src = citizenid and onlineSource(citizenid)
    if src then TriggerClientEvent('bl_pets:client:refresh', src) end
end

local function vec(v)
    return v and { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 } or nil
end

local function round(v)
    return math.floor((tonumber(v) or 0) + 0.5)
end

--- Noms des proprietaires : en ligne d'abord, puis table `players`.
---@param citizenids string[]
---@return table<string, { name: string?, src: integer? }>
local function owners(citizenids)
    local result, missing, seen = {}, {}, {}
    for i = 1, #citizenids do
        local cid = citizenids[i]
        if cid and not seen[cid] then
            seen[cid] = true
            local player = exports.qbx_core:GetPlayerByCitizenId(cid)
            if player and player.PlayerData then
                result[cid] = { name = charName(player), src = player.PlayerData.source }
            else
                missing[#missing + 1] = cid
            end
        end
    end
    local names = Pets.Db.ownerNames(missing)
    for i = 1, #missing do
        result[missing[i]] = { name = names[missing[i]] }
    end
    return result
end

--- Animal vu par le staff : valeurs vivantes, etat, proprietaire.
local function petView(pet, ownerInfo)
    pet = A.withLive(pet)
    local def = Config.Species[pet.species]
    local entry = A.entryOf(pet.id)
    local o = ownerInfo or {}
    return {
        id = pet.id,
        name = pet.name,
        species = pet.species,
        label = def and def.label or pet.species,
        kind = def and def.kind or 'dog',
        known = def ~= nil,
        traits = pet.traits,
        health = round(pet.health),
        hunger = round(pet.hunger),
        xp = pet.xp or 0,
        state = A.stateOf(pet),
        hungry = pet.hunger < Config.HungryThreshold,
        citizenid = pet.citizenid,
        ownerName = o.name,
        ownerSrc = o.src,
        origin = pet.source,
        createdAt = pet.created_at,
        pending = entry and entry.pending or nil,
        dead = entry and entry.deadSince ~= nil or nil,
    }
end

-- Validation --------------------------------------------------------------------------

local function percent(value)
    local n = tonumber(value)
    if not n or n ~= n then return nil end
    return math.floor(math.max(0, math.min(100, n)) + 0.5)
end

--- Cible d'un don / transfert : n° de joueur en ligne ou citizenid.
---@return string? citizenid, string? err
local function resolveTarget(args)
    local id = tonumber(args.target)
    if id then
        local cid = A.citizenIdOf(id)
        if not cid then return nil, 'no_target' end
        return cid
    end
    local cid = type(args.citizenid) == 'string' and args.citizenid:gsub('%s', '') or ''
    if cid == '' or #cid > 50 or not cid:match('^[%w_%-]+$') then return nil, 'no_target' end
    -- Le citizenid doit exister (en ligne ou dans `players`).
    if onlineSource(cid) then return cid end
    if next(Pets.Db.ownerNames({ cid })) then return cid end
    return nil, 'no_target'
end

-- Operations ----------------------------------------------------------------------------

local ops = {}

function ops.overview()
    local stats = Pets.Db.stats()
    local bySpecies, byKind = {}, {}
    local total, injured, hungry = 0, 0, 0
    for i = 1, #stats.rows do
        local r = stats.rows[i]
        local n = tonumber(r.n) or 0
        bySpecies[r.species] = n
        local def = Config.Species[r.species]
        local kind = def and def.kind or 'unknown'
        byKind[kind] = (byKind[kind] or 0) + n
        total = total + n
        injured = injured + (tonumber(r.injured) or 0)
        hungry = hungry + (tonumber(r.hungry) or 0)
    end

    local out = {}
    for src, entry in pairs(A.active()) do
        local entity = A.entityOf(entry)
        local player = exports.qbx_core:GetPlayer(src)
        out[#out + 1] = {
            petId = entry.petId,
            name = entry.name,
            species = entry.species,
            health = round(entry.health),
            hunger = round(entry.hunger),
            pending = entry.pending or nil,
            dead = entry.deadSince ~= nil or nil,
            src = src,
            playerName = GetPlayerName(src),
            ownerName = charName(player),
            citizenid = entry.citizenid,
            coords = entity ~= 0 and vec(GetEntityCoords(entity)) or nil,
            bucket = entity ~= 0 and GetEntityRoutingBucket(entity) or nil,
        }
    end
    table.sort(out, function(a, b) return a.petId < b.petId end)

    local top = Pets.Db.topOwners(5)
    local cids = {}
    for i = 1, #top do cids[i] = top[i].citizenid end
    local names = owners(cids)
    local topOwners = {}
    for i = 1, #top do
        local o = names[top[i].citizenid] or {}
        topOwners[i] = { citizenid = top[i].citizenid, count = tonumber(top[i].n) or 0, name = o.name, online = o.src ~= nil }
    end

    return {
        total = total,
        owners = stats.owners,
        injured = injured,
        hungry = hungry,
        outCount = #out,
        bySpecies = bySpecies,
        byKind = byKind,
        out = out,
        topOwners = topOwners,
        logs = Pets.Db.logs(nil, 8),
    }
end

function ops.search(_, args)
    local q = type(args.q) == 'string' and args.q:sub(1, 64):gsub('^%s+', ''):gsub('%s+$', '') or ''
    local filter = {
        q = q,
        limit = Config.Admin.searchLimit,
    }

    if type(args.species) == 'string' and Config.Species[args.species] then
        filter.species = args.species
    elseif type(args.kind) == 'string' and Config.Kinds[args.kind] then
        filter.speciesIn = {}
        for key, def in pairs(Config.Species) do
            if def.kind == args.kind then filter.speciesIn[#filter.speciesIn + 1] = key end
        end
    end

    -- Recherche par nom de personnage : joueurs en ligne, puis table `players`.
    if #q >= 2 then
        local found, seen = {}, {}
        local lower = q:lower()
        for _, id in ipairs(GetPlayers()) do
            local player = exports.qbx_core:GetPlayer(tonumber(id))
            local name = charName(player)
            local cid = player and player.PlayerData and player.PlayerData.citizenid
            local pname = GetPlayerName(tonumber(id)) or ''
            if cid and ((name and name:lower():find(lower, 1, true)) or pname:lower():find(lower, 1, true) or id == q) then
                found[#found + 1] = cid
                seen[cid] = true
            end
        end
        local fromDb = Pets.Db.findOwners(q)
        for i = 1, #fromDb do
            if not seen[fromDb[i]] then found[#found + 1] = fromDb[i] end
        end
        filter.owners = found
    end

    local rows = Pets.Db.search(filter)
    local capped = #rows >= filter.limit

    -- L'etat (sorti, blesse, affame) se filtre ici : « sorti » n'existe qu'en memoire.
    local state = args.state
    local list = {}
    for i = 1, #rows do
        local pet = A.withLive(rows[i])
        local s = A.stateOf(pet)
        if not state or state == '' or state == s
            or (state == 'hungry' and pet.hunger < Config.HungryThreshold) then
            list[#list + 1] = pet
        end
    end

    local size = Config.Admin.pageSize
    local pages = math.max(1, math.ceil(#list / size))
    local page = math.max(1, math.min(pages, math.floor(tonumber(args.page) or 1)))

    local slice, cids = {}, {}
    for i = (page - 1) * size + 1, math.min(#list, page * size) do
        slice[#slice + 1] = list[i]
        cids[#cids + 1] = list[i].citizenid
    end
    local names = owners(cids)
    for i = 1, #slice do slice[i] = petView(slice[i], names[slice[i].citizenid]) end

    return { rows = slice, total = #list, page = page, pages = pages, capped = capped }
end

function ops.pet(_, args)
    local id = tonumber(args.id)
    local pet = id and Pets.Db.get(id)
    if not pet then return nil, 'not_found' end

    local view = petView(pet, owners({ pet.citizenid })[pet.citizenid])
    local entry, src = A.entryOf(pet.id)
    if entry then
        local entity = A.entityOf(entry)
        view.live = {
            src = src,
            playerName = GetPlayerName(src),
            coords = entity ~= 0 and vec(GetEntityCoords(entity)) or nil,
            bucket = entity ~= 0 and GetEntityRoutingBucket(entity) or nil,
        }
    end
    view.ownerPets = #Pets.Db.listByOwner(pet.citizenid)
    view.logs = Pets.Db.logs(pet.id, 40)
    return view
end

function ops.update(src, args)
    local id = tonumber(args.id)
    local pet = id and Pets.Db.get(id)
    if not pet then return nil, 'not_found' end
    pet = A.withLive(pet)

    local fields, before, after = {}, {}, {}

    if args.name ~= nil then
        local name, err = PetsShared.SanitizeName(args.name)
        if not name then return nil, err end
        if name ~= pet.name then fields.name = name end
    end
    if args.species ~= nil then
        if not Config.Species[args.species] then return nil, 'unknown_species' end
        if args.species ~= pet.species then fields.species = args.species end
    end
    for _, key in ipairs({ 'health', 'hunger' }) do
        if args[key] ~= nil then
            local v = percent(args[key])
            if not v then return nil, 'bad_value' end
            if v ~= round(pet[key]) then fields[key] = v end
        end
    end
    if args.xp ~= nil then
        local xp = tonumber(args.xp)
        if not xp or xp < 0 or xp > 1000000 then return nil, 'bad_value' end
        xp = math.floor(xp)
        if xp ~= pet.xp then fields.xp = xp end
    end
    if type(args.traits) == 'table' then
        local traits = {}
        for i = 1, math.min(#args.traits, 6) do
            if Config.Traits[args.traits[i]] then traits[#traits + 1] = args.traits[i] end
        end
        if json.encode(traits) ~= json.encode(pet.traits or {}) then fields.traits = traits end
    end

    if not next(fields) then return { unchanged = true } end
    for k, v in pairs(fields) do before[k], after[k] = pet[k], v end

    -- Changer d'espece change le modele : l'animal sorti rentre d'abord.
    if fields.species then A.despawnPet(pet.id, 'admin') end

    if not Pets.Db.adminUpdate(pet.id, fields) then return nil, 'db' end

    local entry, owner = A.entryOf(pet.id)
    if entry then
        if fields.name then
            entry.name = fields.name
            local entity = A.entityOf(entry)
            if entity ~= 0 then A.tagEntity(entity, owner, pet.id, fields.name, entry.species) end
        end
        if fields.health then
            entry.health = fields.health
            -- La lecture de sante du tic ne retient que les baisses ; on la
            -- suspend un tic pour qu'une hausse ne soit pas annulee.
            entry.healedAt = os.time()
            if fields.health > 0 and entry.deadSince == nil then
                TriggerClientEvent('bl_pets:client:setHealth', owner, pet.id, fields.health)
            end
        end
        if fields.hunger then
            entry.hunger = fields.hunger
            entry.hungryNotified = fields.hunger < Config.HungryThreshold
        end
        if fields.xp then entry.xp = fields.xp end
        if fields.traits then entry.traits = fields.traits end
        A.pushStats(owner, entry)
    end

    refreshOwner(pet.citizenid)
    log(src, 'update', pet.id, pet.citizenid, { before = before, after = after })
    return { changed = after }
end

function ops.dismiss(src, args)
    local id = tonumber(args.id)
    local entry, owner = A.entryOf(id or -1)
    if not entry then return nil, 'not_out' end
    A.despawnPet(id, 'admin')
    log(src, 'dismiss', id, entry.citizenid, { owner = owner })
    return true
end

function ops.dismissAll(src)
    local ids = {}
    for _, entry in pairs(A.active()) do ids[#ids + 1] = entry.petId end
    for i = 1, #ids do A.despawnPet(ids[i], 'admin') end
    log(src, 'dismiss_all', nil, nil, { count = #ids })
    return { count = #ids }
end

function ops.teleport(src, args)
    if src == 0 then return nil, 'no_player' end
    local entry = A.entryOf(tonumber(args.id) or -1)
    if not entry then return nil, 'not_out' end
    local entity = A.entityOf(entry)
    if entity == 0 then return nil, 'not_out' end
    local c = GetEntityCoords(entity)
    local ped = GetPlayerPed(src)
    if GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(entity) then
        SetPlayerRoutingBucket(src, GetEntityRoutingBucket(entity))
    end
    SetEntityCoords(ped, c.x + 1.0, c.y + 1.0, c.z, false, false, false, false)
    log(src, 'teleport', entry.petId, entry.citizenid)
    return true
end

function ops.transfer(src, args)
    local id = tonumber(args.id)
    local pet = id and Pets.Db.get(id)
    if not pet then return nil, 'not_found' end

    local citizenid, err = resolveTarget(args)
    if not citizenid then return nil, err end
    if citizenid == pet.citizenid then return nil, 'same_owner' end

    A.despawnPet(pet.id, 'admin')
    if not Pets.Db.adminUpdate(pet.id, { citizenid = citizenid }) then return nil, 'db' end

    refreshOwner(pet.citizenid)
    refreshOwner(citizenid)
    local newSrc = onlineSource(citizenid)
    if newSrc then A.notify(newSrc, ('Un animal vous a été confié : %s. /animaux'):format(pet.name), 'success') end

    log(src, 'transfer', pet.id, citizenid, { from = pet.citizenid, to = citizenid })
    return { citizenid = citizenid }
end

function ops.delete(src, args)
    local id = tonumber(args.id)
    local pet = id and Pets.Db.get(id)
    if not pet then return nil, 'not_found' end

    A.despawnPet(pet.id, 'admin')
    if not Pets.Db.delete(pet.id) then return nil, 'db' end

    refreshOwner(pet.citizenid)
    log(src, 'delete', pet.id, pet.citizenid, {
        name = pet.name, species = pet.species, health = round(pet.health), hunger = round(pet.hunger), xp = pet.xp,
    })
    return true
end

function ops.give(src, args)
    local citizenid, err = resolveTarget(args)
    if not citizenid then return nil, err end
    if type(args.species) ~= 'string' or not Config.Species[args.species] then return nil, 'unknown_species' end

    local name = nil
    if type(args.name) == 'string' and args.name ~= '' then
        local clean, nameErr = PetsShared.SanitizeName(args.name)
        if not clean then return nil, nameErr end
        name = clean
    end

    local actor, actorName = actorOf(src)
    local id, grantErr = Pets.GrantPet(citizenid, args.species, {
        source = 'admin',
        name = name,
        ignoreLimit = args.ignoreLimit == true,
        logActor = actor,
        logActorName = actorName,
    })
    if not id then return nil, grantErr end

    local target = onlineSource(citizenid)
    if target then A.notify(target, 'Vous avez un nouvel animal : /animaux', 'success') end
    return { id = id, citizenid = citizenid }
end

function ops.players()
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local player = exports.qbx_core:GetPlayer(src)
        local cid = player and player.PlayerData and player.PlayerData.citizenid
        if cid then
            list[#list + 1] = { id = src, name = GetPlayerName(src), charName = charName(player), citizenid = cid }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function ops.logs(_, args)
    return Pets.Db.logs(tonumber(args.petId), Config.Admin.logLimit)
end

-- Rappel et commande --------------------------------------------------------------------

lib.callback.register('bl_pets:server:admin', function(src, op, args)
    if not isStaff(src) then return { ok = false, err = 'forbidden' } end
    if not Pets.Ready then return { ok = false, err = 'not_ready' } end
    local fn = type(op) == 'string' and ops[op]
    if not fn then return { ok = false, err = 'unknown_action' } end

    local ok, data, err = pcall(fn, src, type(args) == 'table' and args or {})
    if not ok then
        print(('^1[bl_pets] panel staff, %s : %s^7'):format(op, tostring(data)))
        return { ok = false, err = 'error' }
    end
    if data == nil then return { ok = false, err = err or 'error' } end
    return { ok = true, data = data }
end)

lib.addCommand(Config.Admin.command, {
    help = 'Panel staff des animaux de compagnie (bl_pets)',
    restricted = Config.Admin.group,
}, function(source)
    if source <= 0 then
        print('[bl_pets] le panel staff s\'ouvre en jeu.')
        return
    end
    TriggerClientEvent('bl_pets:client:adminOpen', source)
end)
