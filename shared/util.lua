--- bl_pets -- fonctions pures partagees (client + serveur).
---
--- Le client s'en sert pour refuser tot (pas d'aller-retour pour un nom trop
--- long) ; le SERVEUR les rejoue toujours : c'est lui qui fait foi.

PetsShared = {}

--- Messages affiches au joueur pour chaque code d'erreur renvoye par le serveur.
PetsShared.Errors = {
    not_ready = 'Les animaux ne sont pas encore disponibles, réessayez dans un instant.',
    no_player = 'Personnage introuvable.',
    not_found = 'Animal introuvable.',
    not_owner = "Cet animal ne vous appartient pas.",
    unknown_species = 'Espèce inconnue.',
    limit = "Vous avez déjà trop d'animaux.",
    injured = "Votre animal est blessé : soignez-le avant de le sortir.",
    already_out = 'Cet animal est déjà sorti.',
    busy = 'Votre animal arrive, patientez.',
    not_out = "Cet animal n'est pas sorti.",
    too_far = 'Votre animal est trop loin.',
    hungry = 'Votre animal a trop faim pour faire des tours.',
    no_trick = "Cet animal ne sait pas faire ça.",
    no_item = "Vous n'avez pas l'objet nécessaire.",
    wrong_item = 'Cet objet ne convient pas.',
    full = "Votre animal n'a plus faim.",
    healthy = "Votre animal est en pleine forme.",
    cooldown = 'Doucement, laissez-le respirer.',
    name_invalid = 'Nom invalide.',
    name_length = ('Le nom doit faire entre %d et %d caractères.'):format(Config.NameMin, Config.NameMax),
    name_chars = 'Lettres, chiffres, espaces, tirets et apostrophes uniquement.',
    unknown_action = 'Action inconnue.',
    spawn_failed = "Votre animal n'a pas pu venir.",
    db = 'Erreur de sauvegarde, réessayez.',
    -- Panel staff.
    forbidden = 'Réservé au staff.',
    bad_value = 'Valeur invalide.',
    no_target = 'Joueur ou citizenid introuvable.',
    same_owner = 'Cet animal appartient déjà à ce joueur.',
    error = 'Erreur serveur (voir la console).',
}

---@param code string?
---@return string
function PetsShared.ErrorText(code)
    return PetsShared.Errors[code or ''] or code or 'Refusé.'
end

--- Un point de code est-il admis dans un nom ?
--- ASCII : lettres, chiffres, espace, tiret, apostrophe. Au-dela : les lettres
--- latines accentuees (U+00C0 a U+024F) sauf × et ÷.
---@param cp integer
---@return boolean
local function allowedCodepoint(cp)
    if cp >= 48 and cp <= 57 then return true end   -- 0-9
    if cp >= 65 and cp <= 90 then return true end   -- A-Z
    if cp >= 97 and cp <= 122 then return true end  -- a-z
    if cp == 32 or cp == 45 or cp == 39 then return true end
    return cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7
end

--- Nettoie et valide un nom d'animal.
---@param raw any
---@return string? name, string? err
function PetsShared.SanitizeName(raw)
    if type(raw) ~= 'string' then return nil, 'name_invalid' end

    -- Espaces multiples ecrases, bords retires. Les parentheses gardent la
    -- seule chaine de gsub (il rend aussi un compte).
    local name = (raw:gsub('%s+', ' '))
    name = (name:gsub('^ ', ''))
    name = (name:gsub(' $', ''))

    -- utf8.len rend nil sur un octet invalide : utf8.codes ne levera donc pas.
    local length = utf8.len(name)
    if not length then return nil, 'name_invalid' end
    if length < Config.NameMin or length > Config.NameMax then return nil, 'name_length' end

    local hasLetter = false
    for _, cp in utf8.codes(name) do
        if not allowedCodepoint(cp) then return nil, 'name_chars' end
        if (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) or cp >= 0xC0 then
            hasLetter = true
        end
    end

    if not hasLetter then return nil, 'name_chars' end

    return name
end

--- Libelles des traits, dans l'ordre.
---@param traits string[]?
---@return string
function PetsShared.TraitsText(traits)
    local labels = {}
    for i = 1, #(traits or {}) do
        labels[#labels + 1] = Config.Traits[traits[i]] or traits[i]
    end
    return #labels > 0 and table.concat(labels, ', ') or '—'
end

--- Le tour est-il permis pour l'espece ?
---@param species string
---@param trick string
---@return table? spec
function PetsShared.TrickSpec(species, trick)
    local def = Config.Species[species]
    return def and def.tricks and def.tricks[trick] or nil
end

--- Libelle d'un tour pour une espece (« Aboyer » / « Miauler » / « Hurler »).
---@param species string
---@param trick string
---@return string
function PetsShared.TrickLabel(species, trick)
    local spec = PetsShared.TrickSpec(species, trick)
    if spec and spec.label then return spec.label end
    if trick == 'speak' then
        local def = Config.Species[species]
        return Config.SpeakLabels[def and def.kind or 'dog'] or Config.TrickLabels.speak
    end
    return Config.TrickLabels[trick] or trick
end

--- Etat lisible.
PetsShared.StateLabels = {
    out = 'Sorti',
    stored = 'À la maison',
    injured = 'À soigner',
}
