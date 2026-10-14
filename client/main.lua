--- bl_pets -- l'animal sorti : apparition, suivi, vehicule, tours, disparition.
---
--- Le serveur cree l'entite (ped reseau), le client en prend le controle et
--- l'anime ; il ne decide de rien. Les
--- ordres arrivent du serveur (`bl_pets:client:order`) apres sa verification,
--- qu'ils viennent du menu, d'ox_target, d'un objet ou de la boutique.
---
--- AUCUNE BOUCLE PAR IMAGE ICI. Le suivi tourne a Config.Follow.refreshMs et
--- n'existe que tant qu'un animal est sorti. Seul le nom au-dessus de la tete
--- (client/nametag.lua) dessine par image, et seulement a courte distance.

PetClient = {
    ---@type table? l'animal sorti { id, species, name, ped, netId, mode, health, hunger, vehicle, seat }
    pet = nil,
    spawning = false,
}

local function notify(message, kind)
    exports.qbx_core:Notify(message, kind or 'inform')
end
PetClient.Notify = notify

--- Groupe de relation des animaux : compagnons du joueur, dans les deux sens.
--- Sans lui, un puma ou un coyote de script peut charger le premier passant.
local _, REL_GROUP = AddRelationshipGroup('BL_PETS')
SetRelationshipBetweenGroups(0, REL_GROUP, joaat('PLAYER'))
SetRelationshipBetweenGroups(0, joaat('PLAYER'), REL_GROUP)

--- Ordre au serveur, resultat notifie en cas de refus. A appeler dans un thread.
---@param petId integer
---@param action string
---@param data any
---@return boolean ok, any value
function PetClient.Act(petId, action, data)
    local result = lib.callback.await('bl_pets:server:action', false, petId, action, data)
    if not result or not result.ok then
        notify(PetsShared.ErrorText(result and result.err), 'error')
        return false
    end
    return true, result.value
end

--- Meme chose, sans bloquer l'appelant (menus, ox_target).
function PetClient.ActAsync(petId, action, data, onDone)
    CreateThread(function()
        local ok, value = PetClient.Act(petId, action, data)
        if onDone then onDone(ok, value) end
    end)
end

--- Position au sol a cote d'une entite.
---@return vector3
local function groundBeside(entity, offsetX, offsetY)
    local c = GetOffsetFromEntityInWorldCoords(entity, offsetX, offsetY, 0.0)
    local found, z = GetGroundZFor3dCoord(c.x, c.y, c.z + 1.0, false)
    return vec3(c.x, c.y, found and z or (c.z - 1.0))
end

local function ownerIsDead()
    local metadata = QBX and QBX.PlayerData and QBX.PlayerData.metadata
    if metadata and metadata.isdead then return true end
    return IsEntityDead(cache.ped)
end

-- Nettoyage -----------------------------------------------------------------------------

--- Oublie l'animal cote client et supprime l'entite si elle existe encore.
--- Le serveur la supprime aussi : les deux sont sans danger.
function PetClient.CleanupLocal()
    local pet = PetClient.pet
    if not pet then return end
    PetClient.pet = nil

    if PetTarget then PetTarget.remove(pet.ped) end

    if DoesEntityExist(pet.ped) then
        if IsEntityAttached(pet.ped) then DetachEntity(pet.ped, true, false) end
        SetEntityAsMissionEntity(pet.ped, true, true)
        DeleteEntity(pet.ped)
    end
end

-- Modes ---------------------------------------------------------------------------------

local function setMode(pet, mode)
    pet.mode = mode
    pet.task = nil
    pet.trickToken = nil
    if mode == 'stay' and DoesEntityExist(pet.ped) and not pet.vehicle then
        ClearPedTasks(pet.ped)
    end
    -- La tablette (client/tablet.lua) affiche le mode courant.
    TriggerEvent('bl_pets:client:modeChanged')
end

local function playAnim(ped, dict, clip, flag)
    local ok = pcall(lib.requestAnimDict, dict, 3000)
    if not ok then return false end
    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, flag or 1, 0, false, false, false)
    return true
end

local function playTrick(pet, trick)
    local spec = PetsShared.TrickSpec(pet.species, trick)
    if not spec or pet.vehicle or not DoesEntityExist(pet.ped) then return end

    ClearPedTasks(pet.ped)
    if spec.scenario then
        TaskStartScenarioInPlace(pet.ped, spec.scenario, 0, true)
    elseif spec.dict then
        playAnim(pet.ped, spec.dict, spec.clip, 1)
    end

    pet.mode = 'trick'
    pet.task = nil

    -- Un tour ponctuel (aboyer, hurler) rend la main tout seul.
    if spec.duration then
        local token = {}
        pet.trickToken = token
        SetTimeout(spec.duration, function()
            if PetClient.pet == pet and pet.trickToken == token and pet.mode == 'trick' then
                setMode(pet, 'follow')
            end
        end)
    end
end

--- Le joueur s'agenouille un instant (caresser, nourrir) ; l'animal le regarde.
local function interactPose(pet, duration)
    if cache.vehicle or pet.vehicle then return end
    TaskTurnPedToFaceEntity(pet.ped, cache.ped, 1500)
    TaskStartScenarioInPlace(cache.ped, 'CODE_HUMAN_MEDIC_KNEEL', 0, true)
    SetTimeout(duration, function()
        ClearPedTasks(cache.ped)
        if PetClient.pet == pet then pet.task = nil end
    end)
end

-- Vehicule ------------------------------------------------------------------------------

local SEAT_BONES = {
    [0] = 'seat_pside_f',
    [1] = 'seat_dside_r',
    [2] = 'seat_pside_r',
}

---@return integer? seat, integer? bone
local function findSeat(vehicle)
    local max = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = 0, math.min(2, max - 1) do
        if IsVehicleSeatFree(vehicle, seat) and GetPedInVehicleSeat(vehicle, seat) == 0 then
            local bone = GetEntityBoneIndexByName(vehicle, SEAT_BONES[seat])
            if bone ~= -1 then return seat, bone end
        end
    end
    return nil, nil
end

local function vehicleAllowed(rule, vehicle)
    local class = GetVehicleClass(vehicle)
    if rule.classes then
        for i = 1, #rule.classes do
            if rule.classes[i] == class then return true end
        end
        return false
    end
    return not Config.VehicleDeniedClasses[class]
end

--- Monte dans le vehicule du joueur : l'animal est ATTACHE au siege libre (voir
--- config.lua, rubrique VEHICULES), pas assis par la tache du jeu.
local function board(pet, vehicle)
    pet.refused = vehicle

    local def = Config.Species[pet.species]
    local rule = def and def.vehicle
    if not rule then
        notify(('%s ne monte pas en véhicule, il vous attend.'):format(pet.name), 'inform')
        return
    end
    if not vehicleAllowed(rule, vehicle) then
        notify(('%s ne peut pas monter dans ce véhicule.'):format(pet.name), 'inform')
        return
    end

    local seat, bone = findSeat(vehicle)
    if not seat then
        notify(('Pas de place pour %s.'):format(pet.name), 'inform')
        return
    end

    local o = rule.offset or vec3(0.0, 0.0, 0.2)
    ClearPedTasksImmediately(pet.ped)
    AttachEntityToEntity(pet.ped, vehicle, bone, o.x, o.y, o.z, 0.0, 0.0, 0.0,
        false, false, false, true, 2, true)
    if rule.anim then playAnim(pet.ped, rule.anim.dict, rule.anim.clip, 1) end

    pet.vehicle, pet.seat = vehicle, seat
end

local function unboard(pet)
    local vehicle, seat = pet.vehicle, pet.seat
    pet.vehicle, pet.seat, pet.task = nil, nil, nil

    if not DoesEntityExist(pet.ped) then return end
    DetachEntity(pet.ped, true, true)
    ClearPedTasksImmediately(pet.ped)

    -- Du cote de son siege si le vehicule existe encore, sinon derriere le joueur.
    local pos
    if vehicle and DoesEntityExist(vehicle) then
        pos = groundBeside(vehicle, seat == 1 and -1.8 or 1.8, seat == 0 and 0.4 or -0.8)
    else
        pos = groundBeside(cache.ped, 0.0, -1.5)
    end
    SetEntityCoords(pet.ped, pos.x, pos.y, pos.z, false, false, false, false)
end

-- Suivi ---------------------------------------------------------------------------------

--- Replace l'animal derriere le joueur, en fondu (pas de saut a l'ecran).
local function softTeleport(pet)
    if pet.teleporting then return end
    pet.teleporting = true

    CreateThread(function()
        local ped = pet.ped
        for alpha = 204, 0, -51 do
            SetEntityAlpha(ped, alpha, false)
            Wait(40)
        end
        if DoesEntityExist(ped) then
            local pos = groundBeside(cache.ped, 0.0, -2.0)
            SetEntityCoords(ped, pos.x, pos.y, pos.z, false, false, false, false)
            for alpha = 51, 255, 51 do
                SetEntityAlpha(ped, alpha, false)
                Wait(40)
            end
            ResetEntityAlpha(ped)
        end
        pet.task = nil
        pet.teleporting = false
    end)
end

local function follow(pet, distance)
    local f = Config.Follow
    local hungry = pet.hunger < Config.HungryThreshold

    -- Affame : il suit au pas, de plus loin, et ne court jamais.
    local speed = (distance > f.runDistance and not hungry) and f.runSpeed or f.walkSpeed
    local stop = f.stopRange + (hungry and 1.0 or 0.0)
    local now = GetGameTimer()

    local stalled = GetEntitySpeed(pet.ped) < 0.2 and distance > stop + 2.0
        and now - (pet.taskAt or 0) > 3000

    if pet.task ~= speed or stalled then
        local o = f.offset
        TaskFollowToOffsetOfEntity(pet.ped, cache.ped, o.x, o.y - (hungry and 1.0 or 0.0), o.z,
            speed, -1, stop, true)
        pet.task = speed
        pet.taskAt = now
    end
end

--- Un pas de la boucle de suivi.
local function step(pet)
    local ped = pet.ped

    if not DoesEntityExist(ped) then
        TriggerServerEvent('bl_pets:server:lost', pet.id)
        PetClient.CleanupLocal()
        return
    end

    if IsEntityDead(ped) then
        if not pet.dead then
            pet.dead = true
            if pet.vehicle then unboard(pet) end
            if PetTarget then PetTarget.remove(ped) end
            TriggerServerEvent('bl_pets:server:petDied', pet.id)
        end
        return
    end

    if ownerIsDead() then
        pet.ownerDeadSince = pet.ownerDeadSince or GetGameTimer()
        if not pet.ownerDeadSent
            and GetGameTimer() - pet.ownerDeadSince > Config.OwnerDeadDespawnSeconds * 1000 then
            pet.ownerDeadSent = true
            TriggerServerEvent('bl_pets:server:ownerDead')
        end
        return
    end
    pet.ownerDeadSince, pet.ownerDeadSent = nil, nil

    -- Vehicule : monter avec le joueur, descendre avec lui.
    local vehicle = cache.vehicle
    if vehicle and vehicle ~= 0 then
        if pet.vehicle and pet.vehicle ~= vehicle then unboard(pet) end
        if not pet.vehicle and pet.mode == 'follow' and pet.refused ~= vehicle then
            local distance = #(GetEntityCoords(ped) - GetEntityCoords(cache.ped))
            if distance <= Config.Follow.boardDistance then board(pet, vehicle) end
        end
        -- Pas de suivi ni de teleportation pendant que le joueur conduit.
        return
    end
    pet.refused = nil
    if pet.vehicle then unboard(pet) end

    local distance = #(GetEntityCoords(ped) - GetEntityCoords(cache.ped))

    if pet.mode == 'follow' then
        if distance > Config.Follow.teleportDistance then
            softTeleport(pet)
        else
            follow(pet, distance)
        end
    elseif pet.mode == 'trick' and distance > Config.Follow.trickBreakDistance then
        setMode(pet, 'follow')
    end
end

local function followLoop(pet)
    CreateThread(function()
        while PetClient.pet == pet do
            Wait(Config.Follow.refreshMs)
            if PetClient.pet ~= pet then break end
            step(pet)
        end
    end)
end

-- Apparition ----------------------------------------------------------------------------

local function setupPed(ped, def, health)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedRelationshipGroupHash(ped, REL_GROUP)
    SetPedKeepTask(ped, true)

    -- Sante : 100 = mort pour un ped, donc 0..100 % -> 100..200.
    SetEntityMaxHealth(ped, 200)
    SetEntityHealth(ped, 100 + math.max(1, math.floor(health)))

    if def.variation then
        local v = def.variation
        SetPedComponentVariation(ped, v.component, v.drawable, v.texture, 0)
    else
        SetPedDefaultComponentVariation(ped)
    end
end

RegisterNetEvent('bl_pets:client:spawn', function(data)
    if type(data) ~= 'table' then return end

    local def = Config.Species[data.species]
    if PetClient.spawning or not def then
        TriggerServerEvent('bl_pets:server:spawnFailed', data.id)
        return
    end

    PetClient.spawning = true
    -- Le serveur a deja fait rentrer le precedent : on finit le menage ici.
    PetClient.CleanupLocal()

    -- Le SERVEUR a cree le ped (lockdown `relaxed` du bucket 0 : un ped de
    -- script cree par un client y est refuse). On attend qu'il nous parvienne,
    -- puis on en prend le controle pour l'animer.
    local netId = data.netId
    local function fail()
        PetClient.spawning = false
        notify(PetsShared.ErrorText('spawn_failed'), 'error')
        TriggerServerEvent('bl_pets:server:spawnFailed', data.id)
    end

    local deadline = GetGameTimer() + 5000
    while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < deadline do Wait(50) end
    local ped = NetworkDoesNetworkIdExist(netId) and NetToPed(netId) or 0
    if ped == 0 or not DoesEntityExist(ped) then return fail() end

    while not NetworkHasControlOfEntity(ped) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(ped)
        Wait(50)
    end
    if not NetworkHasControlOfEntity(ped) then return fail() end

    setupPed(ped, def, data.health or 100)

    -- Le proprietaire garde la main : onesync_forceMigration est actif sur ce
    -- serveur, et un animal migre chez un autre joueur ne recevrait plus nos
    -- taches.
    SetNetworkIdCanMigrate(netId, false)

    local ok = lib.callback.await('bl_pets:server:register', false, data.id, netId)
    PetClient.spawning = false

    if not ok then
        notify(PetsShared.ErrorText('spawn_failed'), 'error')
        TriggerServerEvent('bl_pets:server:spawnFailed', data.id)
        return
    end

    local pet = {
        id = data.id,
        species = data.species,
        name = data.name,
        traits = data.traits,
        health = data.health or 100,
        hunger = data.hunger or 100,
        ped = ped,
        netId = netId,
        mode = 'follow',
    }
    PetClient.pet = pet

    if PetTarget then PetTarget.add(pet) end
    followLoop(pet)

    notify(('%s vous rejoint.'):format(pet.name), 'success')
    TriggerEvent('bl_pets:client:refresh')
end)

local DESPAWN_MESSAGES = {
    dismiss = '%s rentre à la maison.',
    owner_dead = '%s est rentré à la maison.',
    lost = "%s s'est perdu, il est rentré à la maison.",
    admin = '%s a été rentré à la maison par le staff.',
}

RegisterNetEvent('bl_pets:client:despawned', function(petId, reason)
    local pet = PetClient.pet
    if not pet or pet.id ~= petId then return end

    PetClient.CleanupLocal()

    local message = DESPAWN_MESSAGES[reason]
    if message then notify(message:format(pet.name), 'inform') end
    TriggerEvent('bl_pets:client:refresh')
end)

RegisterNetEvent('bl_pets:client:stats', function(petId, health, hunger)
    local pet = PetClient.pet
    if not pet or pet.id ~= petId then return end
    pet.health, pet.hunger = health, hunger
end)

RegisterNetEvent('bl_pets:client:setHealth', function(petId, health)
    local pet = PetClient.pet
    if not pet or pet.id ~= petId then return end
    pet.health = health
    if DoesEntityExist(pet.ped) and not IsEntityDead(pet.ped) then
        SetEntityHealth(pet.ped, 100 + math.max(1, math.floor(health)))
    end
end)

RegisterNetEvent('bl_pets:client:order', function(petId, action, arg)
    local pet = PetClient.pet
    if not pet or pet.id ~= petId or not DoesEntityExist(pet.ped) then return end

    if action == 'follow' then
        setMode(pet, 'follow')
        notify(('%s vous suit.'):format(pet.name), 'inform')
    elseif action == 'stay' then
        setMode(pet, 'stay')
        notify(('%s ne bouge plus.'):format(pet.name), 'inform')
    elseif action == 'trick' then
        playTrick(pet, arg)
    elseif action == 'eat' then
        interactPose(pet, 2500)
        notify(('%s mange avec appétit.'):format(pet.name), 'success')
    elseif action == 'pet' then
        interactPose(pet, 3500)
    end
end)

-- Fin de session ------------------------------------------------------------------------

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PetClient.CleanupLocal()
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    PetClient.CleanupLocal()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    PetClient.CleanupLocal()
end)
