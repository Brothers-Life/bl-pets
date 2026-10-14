--- bl_pets -- panel staff (/petadmin), cote client.
---
--- Simple relais : la page (html/admin.js) envoie { op, args } au callback NUI
--- `admin`, qui passe au rappel serveur `bl_pets:server:admin`. C'est le
--- serveur qui verifie le droit staff a chaque requete ; ouvrir la page a la
--- main (evenement local) ne donne acces a rien.
---
--- Meme page NUI que la tablette « Mes animaux » (html/index.html) : une seule
--- des deux est ouverte a la fois.

PetAdmin = {}

local isOpen = false

local TRICK_ORDER = { 'sit', 'lie', 'beg', 'speak' }

--- Catalogue des especes et regles, envoye une fois a l'ouverture : la page
--- n'a pas a connaitre config.lua.
local function meta()
    local species = {}
    for key, def in pairs(Config.Species) do
        local tricks = {}
        for i = 1, #TRICK_ORDER do
            local trick = TRICK_ORDER[i]
            if PetsShared.TrickSpec(key, trick) then
                tricks[#tricks + 1] = PetsShared.TrickLabel(key, trick)
            end
        end
        local vehicle = 'Jamais'
        if def.vehicle then
            vehicle = def.vehicle.classes and 'SUV, tout-terrain, camionnettes' or 'Oui'
        end
        species[#species + 1] = {
            key = key,
            label = def.label,
            model = def.model,
            kind = def.kind,
            kindLabel = Config.Kinds[def.kind] or def.kind,
            hungerPerMinute = def.hungerPerMinute or 1.0,
            traits = def.traits or {},
            tricks = tricks,
            vehicle = vehicle,
        }
    end
    table.sort(species, function(a, b) return a.label < b.label end)

    local kinds = {}
    for i = 1, #Config.KindOrder do
        local k = Config.KindOrder[i]
        kinds[#kinds + 1] = { key = k, label = Config.Kinds[k] or k }
    end

    return {
        species = species,
        kinds = kinds,
        traits = Config.Traits,
        me = GetPlayerServerId(PlayerId()),
        rules = {
            injured = Config.InjuredThreshold,
            hungry = Config.HungryThreshold,
            nameMin = Config.NameMin,
            nameMax = Config.NameMax,
            maxPets = Config.MaxPetsPerCharacter,
        },
    }
end

--- Nom de rue d'une position (le serveur n'a pas ces natives).
local function streetOf(coords)
    if type(coords) ~= 'table' or not coords.x then return nil end
    local street, cross = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local name = GetStreetNameFromHashKey(street)
    if cross and cross ~= 0 then
        name = ('%s / %s'):format(name, GetStreetNameFromHashKey(cross))
    end
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    if zone and zone ~= 'NULL' then name = ('%s, %s'):format(name, zone) end
    return name
end

function PetAdmin.IsOpen()
    return isOpen
end

function PetAdmin.Open()
    if PetTablet and PetTablet.IsOpen() then PetTablet.Close() end
    isOpen = true
    SendNUIMessage({ action = 'adminOpen', meta = meta() })
    SetNuiFocus(true, true)
end

function PetAdmin.Close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('bl_pets:client:adminOpen', PetAdmin.Open)

RegisterNUICallback('adminClose', function(_, cb)
    PetAdmin.Close()
    cb(true)
end)

RegisterNUICallback('admin', function(body, cb)
    local op = body and body.op
    if not isOpen or type(op) ~= 'string' then
        cb({ ok = false, err = PetsShared.ErrorText('unknown_action') })
        return
    end

    CreateThread(function()
        local result = lib.callback.await('bl_pets:server:admin', false, op, body.args or {}) or {}
        if not result.ok then
            cb({ ok = false, err = PetsShared.ErrorText(result.err) })
            return
        end

        local data = result.data
        if op == 'overview' and type(data) == 'table' then
            for i = 1, #(data.out or {}) do data.out[i].street = streetOf(data.out[i].coords) end
        elseif op == 'pet' and type(data) == 'table' and data.live then
            data.live.street = streetOf(data.live.coords)
        end
        cb({ ok = true, data = data })
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
