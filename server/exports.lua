--- bl_pets -- exports serveur (contrat SPEC §10 de bl_premiumshop).
---
--- Fichier A PART et charge en dernier, sans rien qui puisse lever au
--- chargement : une erreur au chargement supprime tous les exports declares
--- en dessous d'elle dans le meme fichier. Si server/main.lua avait plante,
--- ces exports existent quand meme et repondent `nil, 'not_ready'` au lieu
--- de faire lever la boutique.
---
--- Signatures (NE PAS CHANGER, la boutique les appelle) :
---   GrantPet(citizenid, species, opts) -> petId|nil, err
---   GetPets(citizenid) -> { { id, species, name, traits, health, hunger, state, xp, label, kind, created_at } }
---   PetAction(source, petId, action, data) -> ok, err   (call, dismiss, rename, ...)
---   Species() -> { [species] = { label, model, kind = 'dog'|'cat'|'wild'|'farm'|'bird', kindLabel,
---                                traits, traitLabels = { [cle] = libelle }, tricks, vehicle } }

local function api(name)
    return Pets and Pets[name] or nil
end

exports('GrantPet', function(citizenid, species, opts)
    local fn = api('GrantPet')
    if not fn then return nil, 'not_ready' end
    return fn(citizenid, species, opts)
end)

exports('GetPets', function(citizenid)
    local fn = api('GetPets')
    if not fn then return {} end
    return fn(citizenid)
end)

exports('PetAction', function(source, petId, action, data)
    local fn = api('PetAction')
    if not fn then return false, 'not_ready' end
    local ok, err = fn(source, petId, action, data)
    return ok, err
end)

exports('Species', function()
    local fn = api('Species')
    if not fn then return {} end
    return fn()
end)
