--- bl_pets -- le nom au-dessus des animaux (le sien et ceux des autres).
---
--- Deux temps, pour ne JAMAIS dessiner par image sans raison :
---   1. toutes les Config.NameTag.scanMs, on cherche les animaux de compagnie
---      dans le rayon (statebag `blPet`, pose par le serveur a l'enregistrement) ;
---   2. seulement s'il y en a, on dessine a chaque image jusqu'au scan suivant.
--- Loin de tout animal, la boucle dort.

--- Modeles des especes : filtre rapide avant de lire un statebag.
local MODELS = {}
for _, def in pairs(Config.Species) do
    MODELS[joaat(def.model) & 0xFFFFFFFF] = true
end

local function scan(origin, radius)
    local found = {}
    local peds = GetGamePool('CPed')
    for i = 1, #peds do
        local ped = peds[i]
        if MODELS[GetEntityModel(ped) & 0xFFFFFFFF] and NetworkGetEntityIsNetworked(ped) then
            local coords = GetEntityCoords(ped)
            if #(coords - origin) <= radius then
                local state = Entity(ped).state.blPet
                if state and state.name and not IsEntityDead(ped) then
                    found[#found + 1] = { ped = ped, name = state.name }
                end
            end
        end
    end
    return found
end

local function drawName(ped, name)
    local c = GetEntityCoords(ped)
    SetDrawOrigin(c.x, c.y, c.z + 0.75, 0)
    SetTextFont(4)
    SetTextScale(0.0, 0.32)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(name)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    local radius = Config.NameTag.distance

    while true do
        local list = scan(GetEntityCoords(cache.ped), radius)

        if #list == 0 then
            Wait(Config.NameTag.scanMs)
        else
            local untilAt = GetGameTimer() + Config.NameTag.scanMs
            while GetGameTimer() < untilAt do
                local origin = GetEntityCoords(cache.ped)
                for i = 1, #list do
                    local entry = list[i]
                    if DoesEntityExist(entry.ped) and #(GetEntityCoords(entry.ped) - origin) <= radius then
                        drawName(entry.ped, entry.name)
                    end
                end
                Wait(0)
            end
        end
    end
end)
