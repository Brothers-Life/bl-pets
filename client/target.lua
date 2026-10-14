--- bl_pets -- ox_target sur SON animal (et seulement le sien : l'option est
--- posee sur l'entite locale par le client proprietaire, les autres joueurs
--- ne la voient pas).
---
--- ox_target n'est pas une dependance dure : sans lui, le menu /animaux reste
--- le chemin complet.

PetTarget = {}

-- Se viser soi-meme (jeu « soi-meme » d'ox_target, AJOUT LOCAL 2026-10-12) :
-- la tablette, meme sans animal sorti.
CreateThread(function()
    if GetResourceState('ox_target') ~= 'started' then return end
    exports.ox_target:addGlobalSelf({
        name = 'bl_pets:self_tablet',
        icon = 'fa-solid fa-paw',
        label = 'Mes animaux',
        onSelect = function() PetTablet.Open() end,
    })
end)

local DISTANCE = 2.5

local function targetReady()
    return GetResourceState('ox_target') == 'started'
end

local function current(entity)
    local pet = PetClient.pet
    if not pet or pet.ped ~= entity or pet.dead then return nil end
    return pet
end

local function hasItem(name)
    local ok, count = pcall(function() return exports.ox_inventory:Search('count', name) end)
    return ok and (count or 0) > 0
end

local function hasFood()
    for i = 1, #Config.FoodOrder do
        if hasItem(Config.FoodOrder[i]) then return true end
    end
    return false
end

local function act(entity, action, data)
    local pet = current(entity)
    if pet then PetClient.ActAsync(pet.id, action, data) end
end

local function trickOption(trick, icon)
    return {
        name = 'bl_pets:trick_' .. trick,
        icon = icon,
        label = Config.TrickLabels[trick],
        distance = DISTANCE,
        canInteract = function(entity)
            local pet = current(entity)
            return pet ~= nil and not pet.vehicle and PetsShared.TrickSpec(pet.species, trick) ~= nil
        end,
        onSelect = function(data) act(data.entity, 'trick', { trick = trick }) end,
    }
end

local function options()
    local list = {
        {
            name = 'bl_pets:sheet',
            icon = 'fa-solid fa-tablet-screen-button',
            label = 'Ouvrir la fiche',
            distance = DISTANCE,
            canInteract = function(entity) return current(entity) ~= nil end,
            onSelect = function(data)
                local pet = current(data.entity)
                if pet then PetTablet.Open(pet.id) end
            end,
        },
        {
            name = 'bl_pets:pet',
            icon = 'fa-solid fa-hand-holding-heart',
            label = 'Caresser',
            distance = DISTANCE,
            canInteract = function(entity) return current(entity) ~= nil end,
            onSelect = function(data) act(data.entity, 'pet') end,
        },
        {
            name = 'bl_pets:feed',
            icon = 'fa-solid fa-bowl-food',
            label = 'Nourrir',
            distance = DISTANCE,
            canInteract = function(entity) return current(entity) ~= nil and hasFood() end,
            onSelect = function(data) act(data.entity, 'feed') end,
        },
        {
            name = 'bl_pets:heal',
            icon = 'fa-solid fa-kit-medical',
            label = 'Soigner',
            distance = DISTANCE,
            canInteract = function(entity)
                local pet = current(entity)
                return pet ~= nil and pet.health < 100 and hasItem('pet_vetkit')
            end,
            onSelect = function(data) act(data.entity, 'heal') end,
        },
        {
            name = 'bl_pets:follow',
            icon = 'fa-solid fa-person-walking',
            label = 'Suivre',
            distance = DISTANCE,
            canInteract = function(entity)
                local pet = current(entity)
                return pet ~= nil and pet.mode ~= 'follow'
            end,
            onSelect = function(data) act(data.entity, 'follow') end,
        },
        {
            name = 'bl_pets:stay',
            icon = 'fa-solid fa-hand',
            label = 'Rester',
            distance = DISTANCE,
            canInteract = function(entity)
                local pet = current(entity)
                return pet ~= nil and pet.mode ~= 'stay' and not pet.vehicle
            end,
            onSelect = function(data) act(data.entity, 'stay') end,
        },
        trickOption('sit', 'fa-solid fa-dog'),
        trickOption('lie', 'fa-solid fa-bed'),
        trickOption('beg', 'fa-solid fa-star'),
    }

    -- « Parler » : le libelle depend de l'espece (Aboyer / Hurler...), on le
    -- fixe donc a la pose de l'option, qui est propre a cet animal.
    local speak = trickOption('speak', 'fa-solid fa-volume-high')
    list[#list + 1] = speak

    list[#list + 1] = {
        name = 'bl_pets:dismiss',
        icon = 'fa-solid fa-house',
        label = 'Rentrer',
        distance = DISTANCE,
        canInteract = function(entity) return current(entity) ~= nil end,
        onSelect = function(data) act(data.entity, 'dismiss') end,
    }

    return list
end

local NAMES = {
    'bl_pets:pet', 'bl_pets:feed', 'bl_pets:heal', 'bl_pets:follow', 'bl_pets:stay',
    'bl_pets:trick_sit', 'bl_pets:trick_lie', 'bl_pets:trick_beg', 'bl_pets:trick_speak',
    'bl_pets:dismiss',
}

---@param pet table
function PetTarget.add(pet)
    if not targetReady() then return end
    local list = options()
    for i = 1, #list do
        if list[i].name == 'bl_pets:trick_speak' then
            list[i].label = PetsShared.TrickLabel(pet.species, 'speak')
        end
    end
    pcall(function() exports.ox_target:addLocalEntity(pet.ped, list) end)
end

---@param ped integer
function PetTarget.remove(ped)
    if not targetReady() or not ped then return end
    pcall(function() exports.ox_target:removeLocalEntity(ped, NAMES) end)
end
