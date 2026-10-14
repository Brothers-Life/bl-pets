--- bl_pets -- tablette « Mes animaux » (NUI html/), commande, et les objets
--- ox_inventory.
---
--- Remplace le menu bl_ui (client/menu.lua, retire le 2026-10-11) : meme
--- chemin pour chaque ordre -- PetAction cote serveur, qui fait foi. La
--- tablette n'affiche que ce que le serveur renvoie (bl_pets:server:list) et
--- les valeurs vivantes de l'animal sorti (PetClient.pet).
---
--- Maquette validee : resources/tools/preview/pets-tablette.html.

PetTablet = {}

local isOpen = false
local focusPetId = nil

--- Libelles de traits, dans l'ordre.
local function traitLabels(traits)
    local list = {}
    for i = 1, #(traits or {}) do
        list[#list + 1] = Config.Traits[traits[i]] or traits[i]
    end
    return list
end

local TRICK_ORDER = { 'sit', 'lie', 'beg', 'speak' }

local function tricksOf(species)
    local list = {}
    for i = 1, #TRICK_ORDER do
        local key = TRICK_ORDER[i]
        list[#list + 1] = {
            key = key,
            label = PetsShared.TrickLabel(species, key),
            known = PetsShared.TrickSpec(species, key) ~= nil,
        }
    end
    return list
end

local function vehicleText(def)
    if not def or def.vehicle == false then return 'Jamais' end
    if def.vehicle.classes then return 'SUV, tout-terrain, camionnettes' end
    return 'Oui'
end

local function itemCount(name)
    local ok, count = pcall(function() return exports.ox_inventory:Search('count', name) end)
    return ok and (count or 0) or 0
end

local function itemsPayload()
    local food = {}
    for i = 1, #Config.FoodOrder do
        local name = Config.FoodOrder[i]
        local def = Config.Items[name]
        if def then
            food[#food + 1] = {
                name = name, label = def.label, hunger = def.hunger or 0, health = def.health or 0,
                count = itemCount(name),
            }
        end
    end

    local heal
    for name, def in pairs(Config.Items) do
        if def.kind == 'heal' then
            heal = { name = name, label = def.label, health = def.health or 100, count = itemCount(name) }
            break
        end
    end

    return { food = food, heal = heal }
end

--- Liste du serveur + valeurs vivantes de l'animal sorti. A appeler dans un thread.
local function buildPayload()
    local data = lib.callback.await('bl_pets:server:list', false) or {}
    local out = PetClient.pet

    local pets = {}
    for i = 1, #(data.pets or {}) do
        local p = data.pets[i]
        local def = Config.Species[p.species]
        local live = out and out.id == p.id
        pets[#pets + 1] = {
            id = p.id,
            name = p.name,
            species = p.species,
            label = p.label,
            kind = p.kind,
            kindLabel = Config.Kinds[p.kind] or p.kind,
            health = live and math.floor(out.health + 0.5) or p.health,
            hunger = live and math.floor(out.hunger + 0.5) or p.hunger,
            xp = p.xp or 0,
            state = p.state,
            mode = live and out.mode or nil,
            inVehicle = live and out.vehicle ~= nil or false,
            traits = traitLabels(p.traits),
            adoptedAt = p.created_at,
            tricks = tricksOf(p.species),
            vehicle = vehicleText(def),
        }
    end

    return {
        ready = data.ready ~= false,
        pets = pets,
        max = data.max or Config.MaxPetsPerCharacter,
        items = itemsPayload(),
        rules = {
            injured = Config.InjuredThreshold,
            hungry = Config.HungryThreshold,
            nameMin = Config.NameMin,
            nameMax = Config.NameMax,
            interact = Config.InteractDistance,
        },
    }
end

local pushing, again = false, false

--- Renvoie l'etat complet a la page si elle est ouverte. Une demande arrivee
--- pendant un envoi en relance un apres lui (sinon elle serait perdue).
local function push()
    if not isOpen then return end
    if pushing then again = true return end
    pushing = true
    CreateThread(function()
        repeat
            again = false
            local payload = buildPayload()
            if isOpen then SendNUIMessage({ action = 'data', data = payload }) end
        until not again or not isOpen
        pushing = false
    end)
end
PetTablet.Push = push

function PetTablet.Open(petId)
    focusPetId = tonumber(petId)
    CreateThread(function()
        local payload = buildPayload()
        isOpen = true
        SendNUIMessage({ action = 'open', data = payload, focus = focusPetId })
        SetNuiFocus(true, true)
    end)
end

function PetTablet.Close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb)
    PetTablet.Close()
    cb(true)
end)

--- Un ordre de la tablette. Le refus est rendu a la page (message en ligne),
--- pas en notification : le joueur regarde la tablette, pas le coin d'ecran.
RegisterNUICallback('action', function(body, cb)
    local petId = tonumber(body and body.petId)
    local action = body and body.action
    if not petId or type(action) ~= 'string' then
        cb({ ok = false, err = PetsShared.ErrorText('unknown_action') })
        return
    end

    CreateThread(function()
        local result = lib.callback.await('bl_pets:server:action', false, petId, action, body.data)
        local ok = result and result.ok
        cb({ ok = ok == true, err = not ok and PetsShared.ErrorText(result and result.err) or nil })
        -- L'ordre « call » rafraichit aussi a l'arrivee (bl_pets:client:refresh).
        if ok then push() end
    end)
end)

-- Rafraichissements pousses par le reste de la ressource (arrivee, rentree,
-- soin en base) et par le tic serveur (sante, satiete).
RegisterNetEvent('bl_pets:client:refresh', push)
AddEventHandler('bl_pets:client:modeChanged', push)
RegisterNetEvent('bl_pets:client:stats', function()
    -- client/main.lua met a jour PetClient.pet dans son propre gestionnaire ;
    -- on attend la fin de la frame pour lire la nouvelle valeur.
    SetTimeout(0, push)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)

-- Ouverture -----------------------------------------------------------------------------

-- Commande seulement, aucun raccourci clavier (choix du serveur).
RegisterCommand('animaux', function()
    if isOpen then PetTablet.Close() else PetTablet.Open() end
end, false)

exports('OpenMenu', function(petId)
    PetTablet.Open(petId)
end)

-- Objets ox_inventory -------------------------------------------------------------------
--
-- Appeles par ox_inventory (client.export dans data/items.lua) avec
-- (data, slot). consume = 0 : c'est le SERVEUR qui retire l'objet apres ses
-- verifications (animal a soi, sorti, proche, pas rassasie...).

local function nearOwnPet()
    local pet = PetClient.pet
    if not pet or pet.dead or not DoesEntityExist(pet.ped) then return nil, 'not_out' end
    if #(GetEntityCoords(pet.ped) - GetEntityCoords(cache.ped)) > Config.InteractDistance then
        return nil, 'too_far'
    end
    return pet
end

exports('useFood', function(data)
    local name = data and data.name
    local pet, err = nearOwnPet()
    if not pet then
        PetClient.Notify(PetsShared.ErrorText(err), 'error')
        return
    end
    PetClient.ActAsync(pet.id, 'feed', { item = name })
end)

exports('useVetKit', function()
    local pet = nearOwnPet()
    if pet then
        PetClient.ActAsync(pet.id, 'heal')
        return
    end

    -- Pas d'animal sorti a cote : on soigne depuis la tablette (un animal « a
    -- soigner » ne peut justement pas sortir).
    PetClient.Notify("Choisissez l'animal à soigner.", 'inform')
    PetTablet.Open()
end)

--- Les objets pointent-ils encore vers nous ? qbx-itemmanager peut remplacer
--- la definition entiere d'un objet sans son bloc `client` (voir le meme
--- controle dans bl_instances/client/furniture.lua) : l'objet devient inerte
--- sans erreur. On le dit au demarrage plutot que de le decouvrir a l'usage.
CreateThread(function()
    Wait(5000)
    local expected = {
        pet_kibble = 'bl_pets.useFood',
        pet_wetfood = 'bl_pets.useFood',
        pet_vetkit = 'bl_pets.useVetKit',
    }
    for name, export in pairs(expected) do
        local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
        local declared = ok and item and item.client and item.client.export
        if declared ~= export then
            print(('^3[bl_pets] l\'objet « %s » ne pointe pas vers %s (client.export = %s).^7')
                :format(name, export, tostring(declared)))
        end
    end
end)
