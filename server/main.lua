--- bl_pets -- etat serveur, ordres, faim, nettoyage.
---
--- QUI FAIT FOI. Le serveur cree l'animal (voir handlers.call), le client en
--- prend le controle pour l'animer mais ne decide de rien : chaque ordre passe par PetAction, qui
--- revérifie le proprietaire (citizenid du joueur), l'etat de l'animal, la
--- distance et l'inventaire. Le client n'execute qu'apres le feu vert du
--- serveur, qui lui renvoie l'ordre par evenement -- un ordre donne depuis la
--- boutique arrive donc par le meme chemin qu'un ordre du menu.
---
--- UN SEUL ANIMAL SORTI PAR JOUEUR. `active[src]` le decrit ; `byPet[petId]`
--- est l'index inverse. Les valeurs vivantes (sante, satiete, xp) y sont
--- tenues a jour et sauvegardees a chaque tic, et a la rentree.

Pets = Pets or {}

---@type table<integer, table> [source] = animal sorti
local active = {}
---@type table<integer, integer> [petId] = source
local byPet = {}

local function speciesOf(species)
    return Config.Species[species]
end

---@param src integer
---@return string?
local function citizenIdOf(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function notify(src, message, kind)
    if src and src > 0 then
        exports.qbx_core:Notify(src, message, kind or 'inform')
    elseif src == 0 then
        print(('[bl_pets] %s'):format(message)) -- commande lancee depuis la console
    end
end

--- Les hash de modele peuvent revenir signes d'un cote et non signes de
--- l'autre : on compare les 32 bits.
local function sameHash(a, b)
    return (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF)
end

---@param entry table
---@return integer entity (0 si absente)
local function entityOf(entry)
    if not entry.netId then return 0 end
    local entity = NetworkGetEntityFromNetworkId(entry.netId)
    if entity == 0 or not DoesEntityExist(entity) then return 0 end
    return entity
end

---@param src integer
---@param entry table
---@return boolean
local function isNear(src, entry)
    local entity = entityOf(entry)
    if entity == 0 then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    -- Un metre de marge : la position serveur a un temps de retard.
    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= Config.InteractDistance + 1.0
end

--- Statebags de l'entite : `blPet` (nettoyage, nametag, ox_target) et
--- `targetLabel`, l'en-tete du menu d'ox_target (AJOUT LOCAL d'ox_target,
--- 2026-10-12 : targetHeader dans ox_target/client/main.lua).
---@param entity integer
---@param src integer
---@param petId integer
---@param name string
---@param species string
local function tagEntity(entity, src, petId, name, species)
    local def = speciesOf(species)
    Entity(entity).state:set('blPet', { id = petId, name = name, owner = src, species = species }, true)
    Entity(entity).state:set('targetLabel', {
        title = name,
        subtitle = ('Votre animal · %s'):format(def and def.label or species),
        icon = 'fa-solid fa-paw',
    }, true)
end

local function save(entry, wait)
    return Pets.Db.saveStats(entry.petId, entry.health, entry.hunger, entry.xp, wait)
end

local function pushStats(src, entry)
    TriggerClientEvent('bl_pets:client:stats', src, entry.petId, entry.health, entry.hunger)
end

--- Fait rentrer un animal sorti : sauvegarde, suppression de l'entite,
--- nettoyage des index. Idempotent. Les index ne sont effaces que s'ils
--- designent encore CETTE entree : la sauvegarde attend la base, et un nouvel
--- appel a pu reserver la place entre-temps (handlers.call).
---@param src integer
---@param entry table
---@param reason string
---@param opts table? { silent = true (joueur parti), stopping = true (arret ressource) }
local function despawnEntry(src, entry, reason, opts)
    if not entry or entry.gone then return end
    entry.gone = true
    opts = opts or {}

    if active[src] == entry then active[src] = nil end
    if byPet[entry.petId] == src then byPet[entry.petId] = nil end

    if not entry.pending then
        save(entry, not opts.stopping)
    end

    local entity = entityOf(entry)
    if entity ~= 0 then
        DeleteEntity(entity)
    end

    if not opts.silent then
        TriggerClientEvent('bl_pets:client:despawned', src, entry.petId, reason)
    end
end

--- Fait rentrer l'animal sorti de `src`, s'il y en a un.
local function despawn(src, reason, opts)
    despawnEntry(src, active[src], reason, opts)
end

--- L'animal est mort en jeu : sante a 0 (donc « a soigner »), il reste visible
--- quelques secondes puis disparait.
local function onPetDeath(src)
    local entry = active[src]
    if not entry or entry.deadSince then return end

    entry.deadSince = os.time()
    entry.health = 0
    save(entry, false)

    notify(src, ('%s est gravement blessé. Soignez-le avec une trousse vétérinaire.'):format(entry.name), 'error')

    SetTimeout(Config.PetDeadDespawnSeconds * 1000, function()
        if active[src] == entry then despawn(src, 'dead') end
    end)
end

--- Etat d'un animal pour la boutique et le menu.
---@param pet table
---@return string
local function stateOf(pet)
    if byPet[pet.id] then return 'out' end
    if pet.health <= Config.InjuredThreshold then return 'injured' end
    return 'stored'
end

--- Valeurs vivantes si l'animal est sorti, valeurs en base sinon.
local function withLive(pet)
    local src = byPet[pet.id]
    local entry = src and active[src]
    if entry then
        pet.health = entry.health
        pet.hunger = entry.hunger
        pet.xp = entry.xp
        pet.name = entry.name
    end
    return pet
end

-- API (contrat SPEC §10) -----------------------------------------------------------------

--- Liste des especes : { [species] = { label, model, kind, kindLabel, traits, traitLabels, tricks, vehicle } }.
--- Les libelles voyagent avec les cles : la boutique n'a pas a relire notre
--- config.lua pour afficher « Fidèle » au lieu de « loyal ».
function Pets.Species()
    local list = {}
    for key, def in pairs(Config.Species) do
        local tricks = {}
        for trick in pairs(def.tricks or {}) do tricks[#tricks + 1] = trick end
        local traitLabels = {}
        for _, t in ipairs(def.traits or {}) do traitLabels[t] = Config.Traits[t] or t end
        list[key] = {
            label = def.label,
            model = def.model,
            kind = def.kind,
            kindLabel = Config.Kinds[def.kind] or def.kind,
            traits = def.traits,
            traitLabels = traitLabels,
            tricks = tricks,
            vehicle = def.vehicle ~= false,
        }
    end
    return list
end

---@param citizenid string
---@return table[] { { id, species, name, traits, health, hunger, state, xp, label, kind } }
function Pets.GetPets(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return {} end
    if not Pets.AwaitReady(5000) then return {} end

    local rows = Pets.Db.listByOwner(citizenid)
    local list = {}
    for i = 1, #rows do
        local pet = withLive(rows[i])
        local def = speciesOf(pet.species)
        list[#list + 1] = {
            id = pet.id,
            species = pet.species,
            name = pet.name,
            traits = pet.traits,
            health = math.floor(pet.health + 0.5),
            hunger = math.floor(pet.hunger + 0.5),
            xp = pet.xp,
            state = stateOf(pet),
            label = def and def.label or pet.species,
            kind = def and def.kind or 'dog',
            -- Ajout (tablette) : date d'adoption, en ms depuis 1970 (oxmysql).
            created_at = pet.created_at,
        }
    end
    return list
end

--- Tire `count` traits distincts dans la liste de l'espece.
local function rollTraits(pool, count)
    local copy = {}
    for i = 1, #(pool or {}) do copy[i] = pool[i] end

    local picked = {}
    for _ = 1, math.min(count, #copy) do
        local index = math.random(1, #copy)
        picked[#picked + 1] = table.remove(copy, index)
    end
    return picked
end

---@param citizenid string
---@param species string
---@param opts table? { source = 'premium'|'admin'|..., name = string?, traits = string[]?, ignoreLimit = boolean?, logActor = string?, logActorName = string? }
---@return integer? petId, string? err
function Pets.GrantPet(citizenid, species, opts)
    opts = type(opts) == 'table' and opts or {}

    if type(citizenid) ~= 'string' or citizenid == '' then return nil, 'no_player' end
    local def = speciesOf(species)
    if not def then return nil, 'unknown_species' end
    if not Pets.AwaitReady(10000) then return nil, 'not_ready' end

    -- ignoreLimit : don du staff qui depasse volontairement la limite.
    if not opts.ignoreLimit and Pets.Db.countByOwner(citizenid) >= Config.MaxPetsPerCharacter then
        return nil, 'limit'
    end

    -- Un nom fourni mais invalide ne fait pas echouer l'adoption (l'achat est
    -- deja paye) : on retombe sur le nom de l'espece.
    local name = opts.name and PetsShared.SanitizeName(opts.name) or nil
    name = name or def.label

    local traits = nil
    if type(opts.traits) == 'table' then
        traits = {}
        for i = 1, #opts.traits do
            if Config.Traits[opts.traits[i]] then traits[#traits + 1] = opts.traits[i] end
        end
    end
    traits = traits or rollTraits(def.traits, Config.TraitsPerPet)

    local origin = type(opts.source) == 'string' and opts.source:sub(1, 32) or 'admin'

    local id = Pets.Db.insert({
        citizenid = citizenid,
        species = species,
        name = name,
        traits = traits,
        source = origin,
    })
    if not id then return nil, 'db' end

    Pets.Db.log({
        actor = opts.logActor or origin,
        actor_name = opts.logActorName,
        action = 'grant',
        pet_id = id,
        citizenid = citizenid,
        details = { species = species, name = name, source = origin },
    })

    -- Le proprietaire est en ligne : son menu se rafraichit s'il est ouvert.
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if player and player.PlayerData and player.PlayerData.source then
        TriggerClientEvent('bl_pets:client:refresh', player.PlayerData.source)
    end

    return id
end

-- Ordres -------------------------------------------------------------------------------

local ORDERS = { follow = true, stay = true }

--- Premier objet du type voulu que le joueur possede.
local function firstOwnedItem(src, order)
    for i = 1, #order do
        local name = order[i]
        if (exports.ox_inventory:GetItemCount(src, name) or 0) > 0 then return name end
    end
    return nil
end

local function healItemName()
    for name, def in pairs(Config.Items) do
        if def.kind == 'heal' then return name end
    end
    return nil
end

local handlers = {}

function handlers.call(src, pet)
    if pet.health <= Config.InjuredThreshold then return false, 'injured' end

    local previous = active[src]
    if previous then
        if previous.pending then return false, 'busy' end
        if previous.petId == pet.id then return false, 'already_out' end
    end

    local def = speciesOf(pet.species)
    if not def then return false, 'unknown_species' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'no_player' end

    local entry = {
        petId = pet.id,
        citizenid = pet.citizenid,
        species = pet.species,
        name = pet.name,
        traits = pet.traits,
        health = pet.health,
        hunger = pet.hunger,
        xp = pet.xp,
        pending = true,
        pendingSince = os.time(),
    }
    -- Un meme animal ne peut pas etre sorti par deux sessions (meme
    -- citizenid reconnecte ailleurs, par exemple).
    local holder = byPet[pet.id]

    -- Reserve AVANT tout ce qui attend (sauvegarde du precedent, creation du
    -- ped) : un second appel pendant ce temps tombe sur `busy` au lieu de
    -- creer un deuxieme ped que plus rien ne referencerait.
    active[src] = entry
    byPet[pet.id] = src

    -- Un seul animal a la fois : le precedent rentre.
    if previous then despawnEntry(src, previous, 'swap') end
    if holder and holder ~= src then despawn(holder, 'swap') end

    -- Le joueur a pu partir pendant ces sauvegardes.
    if active[src] ~= entry then return false, 'spawn_failed' end
    ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        despawnEntry(src, entry, 'spawn_failed', { silent = true })
        return false, 'no_player'
    end

    -- LE SERVEUR CREE LE PED. Le bucket 0 est en lockdown `relaxed`
    -- (qbx:bucketLockdownMode) : « Only script-owned entities created by
    -- clients are blocked ». Un CreatePed reseau cote client y est refuse --
    -- le ped reste visible chez lui seul, puis disparait. Le client en prend
    -- ensuite le controle pour l'animer (bl_pets:client:spawn).
    local heading = GetEntityHeading(ped)
    local rad = math.rad(heading)
    local c = GetEntityCoords(ped)
    -- 1,5 m derriere le joueur ; -1.0 : les coordonnees du joueur sont a hauteur
    -- de bassin, le ped se pose ensuite au sol.
    local entity = CreatePed(28, joaat(def.model), c.x + math.sin(rad) * 1.5, c.y - math.cos(rad) * 1.5,
        c.z - 1.0, heading, true, true)

    local deadline = GetGameTimer() + 2000
    while not DoesEntityExist(entity) and GetGameTimer() < deadline do Wait(0) end
    if not DoesEntityExist(entity) then
        despawnEntry(src, entry, 'spawn_failed', { silent = true })
        return false, 'spawn_failed'
    end

    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    entry.netId = NetworkGetNetworkIdFromEntity(entity)

    -- Rentree demandee pendant l'attente (deconnexion...) : despawn n'a pas pu
    -- supprimer une entite qui n'existait pas encore.
    if active[src] ~= entry then
        DeleteEntity(entity)
        return false, 'spawn_failed'
    end

    -- Statebag pose des maintenant : un arret brutal avant l'enregistrement du
    -- client laisserait sinon un ped que le nettoyage de demarrage ignore.
    tagEntity(entity, src, pet.id, pet.name, pet.species)

    TriggerClientEvent('bl_pets:client:spawn', src, {
        netId = entry.netId,
        id = pet.id,
        species = pet.species,
        name = pet.name,
        traits = pet.traits,
        health = pet.health,
        hunger = pet.hunger,
    })

    return true
end

function handlers.dismiss(src, pet)
    local entry = active[src]
    if not entry or entry.petId ~= pet.id then return false, 'not_out' end
    despawn(src, 'dismiss')
    return true
end

function handlers.rename(src, pet, data)
    local raw = type(data) == 'table' and data.name or data
    local name, err = PetsShared.SanitizeName(raw)
    if not name then return false, err end

    if not Pets.Db.rename(pet.id, name) then return false, 'db' end

    local entry = active[src]
    if entry and entry.petId == pet.id then
        entry.name = name
        local entity = entityOf(entry)
        if entity ~= 0 then
            tagEntity(entity, src, pet.id, name, entry.species)
        end
    end

    return true, nil, name
end

--- Animal sorti, vivant, a portee de l'ordre.
local function requireOut(src, pet)
    local entry = active[src]
    if not entry or entry.petId ~= pet.id or entry.pending then return nil, 'not_out' end
    if entry.deadSince then return nil, 'injured' end
    return entry
end

function handlers.order(src, pet, action)
    local entry, err = requireOut(src, pet)
    if not entry then return false, err end
    TriggerClientEvent('bl_pets:client:order', src, pet.id, action)
    return true
end

function handlers.trick(src, pet, data)
    local entry, err = requireOut(src, pet)
    if not entry then return false, err end

    local trick = type(data) == 'table' and data.trick or data
    if type(trick) ~= 'string' or not PetsShared.TrickSpec(entry.species, trick) then
        return false, 'no_trick'
    end
    if entry.hunger < Config.HungryThreshold then return false, 'hungry' end

    TriggerClientEvent('bl_pets:client:order', src, pet.id, 'trick', trick)
    return true
end

function handlers.feed(src, pet, data)
    local entry, err = requireOut(src, pet)
    if not entry then return false, err end
    if not isNear(src, entry) then return false, 'too_far' end

    local item = type(data) == 'table' and data.item or nil
    if item == nil then
        item = firstOwnedItem(src, Config.FoodOrder)
        if not item then return false, 'no_item' end
    end

    local def = Config.Items[item]
    if not def or def.kind ~= 'food' then return false, 'wrong_item' end
    if entry.hunger >= 98 then return false, 'full' end

    if (exports.ox_inventory:GetItemCount(src, item) or 0) < 1 then return false, 'no_item' end
    if not exports.ox_inventory:RemoveItem(src, item, 1) then return false, 'no_item' end

    entry.hunger = math.min(100, entry.hunger + (def.hunger or 0))
    entry.hungryNotified = entry.hunger < Config.HungryThreshold
    if (def.health or 0) > 0 then
        entry.health = math.min(100, entry.health + def.health)
        entry.healedAt = os.time()
        TriggerClientEvent('bl_pets:client:setHealth', src, pet.id, entry.health)
    end

    save(entry, false)
    pushStats(src, entry)
    TriggerClientEvent('bl_pets:client:order', src, pet.id, 'eat')
    return true
end

function handlers.heal(src, pet)
    local item = healItemName()
    if not item then return false, 'wrong_item' end

    local entry = active[src]
    local out = entry and entry.petId == pet.id and not entry.pending

    if out and not entry.deadSince and not isNear(src, entry) then return false, 'too_far' end

    local health = out and entry.health or pet.health
    if health >= 100 then return false, 'healthy' end

    if (exports.ox_inventory:GetItemCount(src, item) or 0) < 1 then return false, 'no_item' end

    local healed = math.min(100, health + (Config.Items[item].health or 100))

    if out and not entry.deadSince then
        if not exports.ox_inventory:RemoveItem(src, item, 1) then return false, 'no_item' end
        entry.health = healed
        entry.healedAt = os.time()
        save(entry, false)
        TriggerClientEvent('bl_pets:client:setHealth', src, pet.id, healed)
        pushStats(src, entry)
        return true
    end

    -- Rentre, ou mort en jeu : on fait rentrer l'entite (un ped mort ne se
    -- releve pas) et on soigne en base. La trousse n'est retiree qu'une fois
    -- la sauvegarde reussie : un echec ne doit pas la consommer.
    if out then despawn(src, 'healed') end
    local hunger = out and entry.hunger or pet.hunger
    if not Pets.Db.saveStats(pet.id, healed, hunger, nil, true) then return false, 'db' end
    if not exports.ox_inventory:RemoveItem(src, item, 1) then
        Pets.Db.saveStats(pet.id, health, hunger, nil, true)
        return false, 'no_item'
    end
    TriggerClientEvent('bl_pets:client:refresh', src)
    return true
end

function handlers.pet(src, pet)
    local entry, err = requireOut(src, pet)
    if not entry then return false, err end
    if not isNear(src, entry) then return false, 'too_far' end

    local now = os.time()
    if not entry.lastPetAt or now - entry.lastPetAt >= Config.PetCooldownSeconds then
        entry.lastPetAt = now
        entry.xp = (entry.xp or 0) + 1
    end

    TriggerClientEvent('bl_pets:client:order', src, pet.id, 'pet')
    return true
end

--- Ordres qui ecrivent en base ou creent une entite : un par joueur toutes les
--- Config.ActionCooldownMs, quel que soit l'animal (anti-boucle call/dismiss).
local THROTTLED = { call = true, dismiss = true, rename = true }
---@type table<integer, integer> [source] = GetGameTimer() du dernier ordre limite
local lastThrottled = {}

--- Point d'entree unique de TOUS les ordres (menu, ox_target, objets, boutique).
---@param source integer
---@param petId integer
---@param action string call|dismiss|rename|follow|stay|trick|feed|heal|pet
---@param data any
---@return boolean ok, string? err, any value
function Pets.PetAction(source, petId, action, data)
    local src = tonumber(source)
    petId = tonumber(petId)
    if not src or src <= 0 or not petId then return false, 'not_found' end
    if type(action) ~= 'string' then return false, 'unknown_action' end
    if not Pets.Ready then return false, 'not_ready' end

    local citizenid = citizenIdOf(src)
    if not citizenid then return false, 'no_player' end

    local pet = Pets.Db.get(petId)
    if not pet then return false, 'not_found' end
    if pet.citizenid ~= citizenid then return false, 'not_owner' end
    pet = withLive(pet)

    if THROTTLED[action] then
        local now = GetGameTimer()
        if lastThrottled[src] and now - lastThrottled[src] < (Config.ActionCooldownMs or 1500) then
            return false, 'cooldown'
        end
        lastThrottled[src] = now
    end

    if ORDERS[action] then return handlers.order(src, pet, action) end

    local handler = handlers[action]
    if not handler or action == 'order' then return false, 'unknown_action' end

    return handler(src, pet, data)
end

-- Rappels du client ---------------------------------------------------------------------

lib.callback.register('bl_pets:server:list', function(src)
    local citizenid = citizenIdOf(src)
    if not citizenid then return { pets = {}, ready = Pets.Ready } end

    local entry = active[src]
    return {
        ready = Pets.Ready,
        pets = Pets.GetPets(citizenid),
        activeId = entry and entry.petId or nil,
        max = Config.MaxPetsPerCharacter,
    }
end)

lib.callback.register('bl_pets:server:action', function(src, petId, action, data)
    local ok, err, value = Pets.PetAction(src, petId, action, data)
    return { ok = ok == true, err = err, value = value }
end)

--- Le client a pris le controle du ped cree par le serveur (handlers.call) et
--- l'a configure. On verifie que c'est bien NOTRE entite, qu'elle appartient
--- desormais a CE client, et que c'est le bon modele.
lib.callback.register('bl_pets:server:register', function(src, petId, netId)
    local entry = active[src]
    if not entry or entry.petId ~= petId or not entry.pending then return false end
    if type(netId) ~= 'number' or netId ~= entry.netId then return false end

    local entity = entityOf(entry)
    if entity == 0 then return false end

    -- Le transfert de controle demande par le client met quelques images a
    -- remonter jusqu'au serveur.
    local deadline = GetGameTimer() + 1500
    while NetworkGetEntityOwner(entity) ~= src and GetGameTimer() < deadline do Wait(50) end
    -- La rentree a pu etre demandee pendant l'attente.
    if active[src] ~= entry then return false end

    local def = speciesOf(entry.species)
    if NetworkGetEntityOwner(entity) ~= src or not sameHash(GetEntityModel(entity), GetHashKey(def.model)) then
        return false
    end

    entry.pending = false

    tagEntity(entity, src, entry.petId, entry.name, entry.species)

    return true
end)

RegisterNetEvent('bl_pets:server:spawnFailed', function(petId)
    local src = source
    local entry = active[src]
    if entry and entry.pending and entry.petId == petId then
        -- Le ped a ete cree par le serveur : despawn le supprime aussi.
        despawn(src, 'spawn_failed', { silent = true })
    end
end)

--- Le client voit son animal mort. On le revérifie sur l'entite elle-meme.
RegisterNetEvent('bl_pets:server:petDied', function(petId)
    local src = source
    local entry = active[src]
    if not entry or entry.petId ~= petId or entry.pending then return end

    local entity = entityOf(entry)
    if entity == 0 or GetEntityHealth(entity) <= 100 then
        onPetDeath(src)
    end
end)

--- Le joueur est mort depuis trop longtemps (decompte cote client).
RegisterNetEvent('bl_pets:server:ownerDead', function()
    despawn(source, 'owner_dead')
end)

--- L'entite a disparu cote client (nettoyage du jeu) : on tient les comptes.
RegisterNetEvent('bl_pets:server:lost', function(petId)
    local src = source
    local entry = active[src]
    if entry and entry.petId == petId and not entry.pending then
        despawn(src, 'lost')
    end
end)

-- Tic : faim, sante, sauvegarde ----------------------------------------------------------

--- Sante lue sur l'entite (100..max -> 0..100 %). Seules les BAISSES sont
--- retenues : un soin passe toujours par le serveur, et la lecture qui suit un
--- soin peut encore porter l'ancienne valeur (d'ou `healedAt`).
---@param entry table
---@param entity integer
local function readHealth(entry, entity)
    if entry.healedAt and os.time() - entry.healedAt < Config.TickSeconds then return end

    local max = GetEntityMaxHealth(entity)
    if not max or max <= 100 then return end

    local pct = (GetEntityHealth(entity) - 100) / (max - 100) * 100
    pct = math.max(0, math.min(100, pct))
    if pct < entry.health then entry.health = pct end
end

--- Un pas du tic pour un animal sorti.
local function tickEntry(src, entry, now)
    if entry.pending then
        if now - entry.pendingSince > Config.SpawnTimeoutSeconds then
            despawnEntry(src, entry, 'spawn_failed', { silent = true })
            notify(src, PetsShared.ErrorText('spawn_failed'), 'error')
        end
        return
    end
    if entry.deadSince then return end

    local entity = entityOf(entry)
    if entity == 0 then
        despawnEntry(src, entry, 'lost')
        return
    end

    readHealth(entry, entity)

    local def = speciesOf(entry.species)
    local loss = (def and def.hungerPerMinute or 1.0) * Config.TickSeconds / 60
    entry.hunger = math.max(0, entry.hunger - loss)

    if entry.hunger <= 0 and Config.StarvingHealthLoss > 0 then
        entry.health = math.max(0, entry.health - Config.StarvingHealthLoss)
        entry.healedAt = nil
        TriggerClientEvent('bl_pets:client:setHealth', src, entry.petId, entry.health)
    end

    if entry.hunger < Config.HungryThreshold and not entry.hungryNotified then
        entry.hungryNotified = true
        notify(src, ('%s a faim.'):format(entry.name), 'warning')
    end

    if entry.health <= 0 then
        onPetDeath(src)
    else
        save(entry, false)
        pushStats(src, entry)
    end
end

CreateThread(function()
    while true do
        Wait(Config.TickSeconds * 1000)

        -- Copie d'abord : un despawn attend la base, et un `call` peut ajouter
        -- une cle a `active` pendant ce temps -- `next` leverait alors en plein
        -- parcours. Chaque animal sous pcall : une erreur sur l'un n'arrete
        -- pas le tic pour tous.
        local list = {}
        for src, entry in pairs(active) do list[#list + 1] = { src, entry } end

        local now = os.time()
        for i = 1, #list do
            local src, entry = list[i][1], list[i][2]
            if active[src] == entry then
                local ok, err = pcall(tickEntry, src, entry, now)
                if not ok then print(('^1[bl_pets] tic de l\'animal %s : %s^7'):format(entry.petId, tostring(err))) end
            end
        end
    end
end)

-- Panel staff ---------------------------------------------------------------------------
-- server/admin.lua lit et pilote l'etat vivant par ces fonctions (les tables
-- restent locales a ce fichier).

Pets.Internal = {
    active = function() return active end,
    holderOf = function(petId) return byPet[petId] end,
    entryOf = function(petId)
        local src = byPet[petId]
        return src and active[src] or nil, src
    end,
    despawnPet = function(petId, reason)
        local src = byPet[petId]
        if src then despawn(src, reason or 'admin') end
    end,
    entityOf = entityOf,
    tagEntity = tagEntity,
    pushStats = pushStats,
    stateOf = stateOf,
    withLive = withLive,
    citizenIdOf = citizenIdOf,
    notify = notify,
}

-- Nettoyage -----------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    lastThrottled[src] = nil
    despawn(src, 'dropped', { silent = true })
end)

-- Changement de personnage / deconnexion du personnage (qbx_core).
AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
    despawn(src, 'logout', { silent = true })
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    despawn(src, 'logout', { silent = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local list = {}
    for src in pairs(active) do list[#list + 1] = src end
    for i = 1, #list do
        despawn(list[i], 'stop', { silent = true, stopping = true })
    end
end)

--- Au demarrage, les animaux d'une session precedente (arret brutal, crash)
--- sont encore dans le monde : on les retrouve par leur statebag et on les
--- supprime, sinon un `restart` les dupliquerait.
CreateThread(function()
    Wait(500)
    local peds = GetAllPeds()
    local removed = 0
    for i = 1, #peds do
        local ped = peds[i]
        if DoesEntityExist(ped) and Entity(ped).state.blPet then
            DeleteEntity(ped)
            removed = removed + 1
        end
    end
    if removed > 0 then
        print(('[bl_pets] %d animal(aux) orphelin(s) supprime(s) au demarrage.'):format(removed))
    end
end)

-- Commande staff ------------------------------------------------------------------------

lib.addCommand('givepet', {
    help = 'Donner un animal à un joueur (bl_pets)',
    params = {
        { name = 'target', type = 'playerId', help = 'ID du joueur' },
        { name = 'species', type = 'string', help = 'Espèce (husky, retriever, pug, cat_black…)' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local citizenid = citizenIdOf(args.target)
    if not citizenid then
        notify(source, PetsShared.ErrorText('no_player'), 'error')
        return
    end

    local id, err = Pets.GrantPet(citizenid, args.species, {
        source = 'admin',
        logActor = source > 0 and citizenIdOf(source) or 'console',
        logActorName = source > 0 and GetPlayerName(source) or 'Console',
    })
    if id then
        notify(source, ('Animal n°%d (%s) donné.'):format(id, args.species), 'success')
        notify(args.target, 'Vous avez un nouvel animal : /animaux', 'success')
    else
        notify(source, PetsShared.ErrorText(err), 'error')
    end
end)
