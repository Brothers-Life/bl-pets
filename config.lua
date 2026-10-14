--- bl_pets -- reglages. Partage client + serveur.
---
--- Tout ce qui se regle sans toucher au code est ici : especes, tours permis
--- par espece, vitesses de faim, objets. Le serveur fait foi : une valeur
--- changee ici ne prend effet qu'apres `restart bl_pets`.

Config = {}

Config.MaxPetsPerCharacter = 10

-- Nom : longueur en CARACTERES (pas en octets), lettres latines accentuees,
-- chiffres, espace, tiret, apostrophe. Voir PetsShared.SanitizeName.
Config.NameMin = 2
Config.NameMax = 20

-- Sante et satiete sont des pourcentages 0-100.
--   - sante <= InjuredThreshold : l'animal est « a soigner » et ne sort plus ;
--   - satiete < HungryThreshold : il suit au pas et refuse les tours.
Config.InjuredThreshold = 15
Config.HungryThreshold = 25

-- Cadence du tic serveur (faim, lecture de la sante, sauvegarde).
Config.TickSeconds = 60
-- Perte de sante par tic quand la satiete est a 0. 0 = la faim ne blesse pas.
Config.StarvingHealthLoss = 0

-- Le proprietaire mort depuis plus longtemps que ca : l'animal rentre.
Config.OwnerDeadDespawnSeconds = 45
-- L'animal mort reste visible ce temps-la avant de disparaitre.
Config.PetDeadDespawnSeconds = 8
-- Un appel sans enregistrement du client au bout de ce delai est abandonne.
Config.SpawnTimeoutSeconds = 20

-- Distance max (m) joueur <-> animal pour nourrir / soigner / caresser.
Config.InteractDistance = 4.0
-- Delai entre deux caresses qui rapportent de l'experience.
Config.PetCooldownSeconds = 30
-- Delai minimum entre deux ordres « lourds » d'un meme joueur (appeler,
-- rentrer, renommer) : chacun ecrit en base ou cree une entite.
Config.ActionCooldownMs = 1500

-- PANEL STAFF (/petadmin). La commande est reservee au groupe ci-dessous
-- (ace `command.petadmin`, posee par ox_lib) ; chaque requete du panel
-- revérifie ce droit cote serveur.
Config.Admin = {
    command = 'petadmin',
    group = 'group.admin',
    -- Lignes max renvoyees par une recherche (au-dela : affiner).
    searchLimit = 500,
    -- Taille d'une page de la liste des animaux.
    pageSize = 25,
    -- Entrees du journal affichees.
    logLimit = 150,
}

Config.Follow = {
    -- Decalage par rapport au joueur (x = droite, y = devant).
    offset = vec3(0.7, -1.2, 0.0),
    walkSpeed = 1.0,
    runSpeed = 2.0,
    -- Au-dela, l'animal court pour rattraper.
    runDistance = 6.0,
    stopRange = 1.2,
    -- Au-dela, il est replace derriere le joueur (fondu). Jamais pendant que
    -- le joueur est en vehicule : il attend, et le rejoint a la descente.
    teleportDistance = 35.0,
    -- Cadence de la boucle de suivi (ms). Pas une boucle par image.
    refreshMs = 750,
    -- Rayon dans lequel l'animal monte quand le joueur entre dans un vehicule.
    boardDistance = 12.0,
    -- En mode tour, l'animal reprend le suivi si le joueur s'eloigne d'autant.
    trickBreakDistance = 12.0,
}

Config.NameTag = {
    distance = 8.0,
    -- Recherche des animaux proches (ms). Le dessin par image ne tourne QUE
    -- quand un animal est dans le rayon.
    scanMs = 750,
}

-- Objets ox_inventory (declares dans ox_inventory/data/items.lua, banniere
-- « AJOUT LOCAL (hors upstream) bl_pets »). Le serveur retire l'objet lui-meme
-- apres ses verifications : consume = 0 cote ox_inventory.
Config.Items = {
    pet_kibble = { kind = 'food', label = 'Croquettes', hunger = 35, health = 0 },
    pet_wetfood = { kind = 'food', label = 'Pâtée', hunger = 60, health = 5 },
    pet_vetkit = { kind = 'heal', label = 'Trousse vétérinaire', health = 100 },
}
-- Ordre de preference quand on nourrit sans preciser l'objet (ox_target).
Config.FoodOrder = { 'pet_wetfood', 'pet_kibble' }

Config.Kinds = {
    dog = 'Chien',
    cat = 'Chat',
    wild = 'Sauvage',
    farm = 'Ferme',
    bird = 'Oiseau',
}

-- Ordre d'affichage des types (tablette, panel staff).
Config.KindOrder = { 'dog', 'cat', 'wild', 'farm', 'bird' }

-- Traits decoratifs. Cles ASCII (identifiants), libelles en francais.
Config.Traits = {
    loyal = 'Fidèle',
    fast = 'Rapide',
    cuddly = 'Câlin',
    playful = 'Joueur',
    lazy = 'Paresseux',
    greedy = 'Gourmand',
    brave = 'Courageux',
    shy = 'Timide',
    curious = 'Curieux',
    calm = 'Calme',
    independent = 'Indépendant',
    proud = 'Fier',
    wild = 'Sauvage',
    gentle = 'Doux',
    clever = 'Malin',
    noisy = 'Bruyant',
    agile = 'Agile',
    majestic = 'Majestueux',
    sneaky = 'Rusé',
}
Config.TraitsPerPet = 2

Config.TrickLabels = {
    sit = 'Assis',
    lie = 'Couché',
    beg = 'Faire le beau',
    speak = 'Aboyer',
}

-- TOURS PAR GABARIT. Chaque tour est soit un scenario (TaskStartScenarioInPlace),
-- soit une animation (TaskPlayAnim). Un tour absent = refuse pour l'espece, cote
-- serveur comme cote menu.
--
-- A CONFIRMER EN JEU : les scenarios WORLD_DOG_* / WORLD_CAT_* / WORLD_COYOTE_* /
-- WORLD_MOUNTAIN_LION_* sont ceux du jeu de base ; les animations
-- creatures@rottweiler@* sont celles de Chop et sont reprises pour les grands
-- chiens (meme squelette suppose). Le husky emprunte les scenarios du berger.
local function bigDog(suffix)
    return {
        sit = { scenario = 'WORLD_DOG_SITTING_' .. suffix },
        lie = { dict = 'creatures@rottweiler@amb@sleep_in_kennel@', clip = 'sleep_in_kennel' },
        beg = { dict = 'creatures@rottweiler@tricks@', clip = 'beg_loop' },
        speak = { scenario = 'WORLD_DOG_BARKING_' .. suffix, duration = 6000 },
    }
end

local SMALL_DOG = {
    sit = { scenario = 'WORLD_DOG_SITTING_SMALL' },
    speak = { scenario = 'WORLD_DOG_BARKING_SMALL', duration = 6000 },
}

-- Le chat : pas de « assis » ni de « faire le beau » dans le jeu, et aucune
-- vocalisation scriptable (PLAY_ANIMAL_VOCALIZATION ne connait que sanglier,
-- poule, chien, rottweiler et cheval). Il se couche, c'est tout.
local CAT = {
    lie = { scenario = 'WORLD_CAT_SLEEPING_GROUND' },
}

local COYOTE = {
    lie = { scenario = 'WORLD_COYOTE_REST' },
    speak = { scenario = 'WORLD_COYOTE_HOWL', duration = 7000, label = 'Hurler' },
}

local BIG_CAT = {
    lie = { scenario = 'WORLD_MOUNTAIN_LION_REST' },
}

-- Animaux sauvages et de ferme : pas d'assis ni de « faire le beau », mais
-- les scenarios du jeu de base (brouter, fouiller, picorer). Le libelle du
-- tour remplace celui de Config.TrickLabels (tablette et ox_target).
-- A CONFIRMER EN JEU : comme pour les chiens, les scenarios sont ceux que le
-- jeu pose dans le monde ; leur rendu sur un ped de script est a verifier.
local function grazer(scenario, label)
    return { lie = { scenario = scenario, label = label or 'Brouter' } }
end

local RABBIT = { lie = { scenario = 'WORLD_RABBIT_EATING', label = 'Grignoter' } }
local RAT = { lie = { scenario = 'WORLD_RATS_EATING', label = 'Grignoter' } }
local HEN = { lie = { scenario = 'WORLD_HEN_PECKING', label = 'Picorer' } }

-- Oiseaux : « assis » = se poser, « couché » = picorer. Un oiseau suit le
-- joueur au sol (TaskFollowToOffsetOfEntity) ; il peut s'envoler s'il est
-- distance, puis il est replace par la teleportation douce.
local function bird(stand, feed)
    local t = {}
    if stand then t.sit = { scenario = stand, label = 'Se poser' } end
    if feed then t.lie = { scenario = feed, label = 'Picorer' } end
    return t
end

-- Primates : aucun scenario ni animation de tour dans le jeu de base.
local PRIMATE = {}

-- VEHICULES. `vehicle = false` : l'animal ne monte jamais (il attend et
-- rejoint le joueur a la descente). Sinon :
--   classes  = liste blanche de classes (GetVehicleClass) ; nil = toutes sauf
--              Config.VehicleDeniedClasses ;
--   anim     = animation jouee une fois attache au siege (facultatif) ;
--   offset   = decalage par rapport a l'os du siege.
-- L'animal est ATTACHE au siege (AttachEntityToEntity), pas assis par la tache
-- du jeu : seuls Chop et le rottweiler ont des animations de passager.
-- A CONFIRMER EN JEU : hauteur des decalages selon le gabarit.
Config.VehicleDeniedClasses = {
    [8] = true,  -- motos
    [13] = true, -- velos
    [14] = true, -- bateaux
    [15] = true, -- helicopteres
    [16] = true, -- avions
    [21] = true, -- trains
}

local DOG_CAR = {
    anim = { dict = 'creatures@rottweiler@in_vehicle@std_car', clip = 'sit' },
    offset = vec3(0.0, 0.0, 0.25),
}
local SMALL_CAR = { offset = vec3(0.0, 0.0, 0.15) }
-- Un coyote dans un SUV, un tout-terrain ou une camionnette, pas dans une citadine.
local WILD_CAR = { classes = { 2, 9, 12 }, offset = vec3(0.0, 0.0, 0.25) }
-- Petits animaux (lapin, rat, oiseaux) : sur le siege, sans animation.
local TINY_CAR = { offset = vec3(0.0, 0.0, 0.1) }
-- Singes : partout sauf deux-roues, bateaux et aeronefs (regle par defaut).
local PRIMATE_CAR = { offset = vec3(0.0, 0.0, 0.3) }

-- ESPECES. La cle est l'identifiant (`blpet:<cle>` dans la boutique).
--   hungerPerMinute : satiete perdue par minute SORTI (rentre, il ne perd rien) ;
--   variation       : texture du modele (SetPedComponentVariation), facultatif ;
--   traits          : tirage des traits a l'adoption.
Config.Species = {
    -- Chiens -------------------------------------------------------------------------
    husky = {
        label = 'Husky', model = 'a_c_husky', kind = 'dog', hungerPerMinute = 1.0,
        tricks = bigDog('SHEPHERD'), vehicle = DOG_CAR,
        traits = { 'loyal', 'fast', 'playful', 'independent', 'brave' },
    },
    retriever = {
        label = 'Golden retriever', model = 'a_c_retriever', kind = 'dog', hungerPerMinute = 1.0,
        tricks = bigDog('RETRIEVER'), vehicle = DOG_CAR,
        traits = { 'loyal', 'cuddly', 'playful', 'greedy', 'calm' },
    },
    shepherd = {
        label = 'Berger', model = 'a_c_shepherd', kind = 'dog', hungerPerMinute = 1.0,
        tricks = bigDog('SHEPHERD'), vehicle = DOG_CAR,
        traits = { 'loyal', 'brave', 'fast', 'proud', 'curious' },
    },
    rottweiler = {
        label = 'Rottweiler', model = 'a_c_rottweiler', kind = 'dog', hungerPerMinute = 1.1,
        tricks = bigDog('ROTTWEILER'), vehicle = DOG_CAR,
        traits = { 'loyal', 'brave', 'proud', 'greedy', 'calm' },
    },
    pug = {
        label = 'Carlin', model = 'a_c_pug', kind = 'dog', hungerPerMinute = 0.8,
        tricks = SMALL_DOG, vehicle = SMALL_CAR,
        traits = { 'cuddly', 'lazy', 'greedy', 'playful', 'shy' },
    },
    poodle = {
        label = 'Caniche', model = 'a_c_poodle', kind = 'dog', hungerPerMinute = 0.8,
        tricks = SMALL_DOG, vehicle = SMALL_CAR,
        traits = { 'proud', 'cuddly', 'curious', 'playful', 'calm' },
    },
    westy = {
        label = 'Westie', model = 'a_c_westy', kind = 'dog', hungerPerMinute = 0.8,
        tricks = SMALL_DOG, vehicle = SMALL_CAR,
        traits = { 'playful', 'curious', 'cuddly', 'brave', 'fast' },
    },

    -- Chats --------------------------------------------------------------------------
    -- Meme modele, deux robes. A CONFIRMER EN JEU : quel numero de texture
    -- correspond a quelle robe sur a_c_cat_01.
    cat_black = {
        label = 'Chat noir', model = 'a_c_cat_01', kind = 'cat', hungerPerMinute = 0.6,
        variation = { component = 0, drawable = 0, texture = 0 },
        tricks = CAT, vehicle = SMALL_CAR,
        traits = { 'independent', 'curious', 'lazy', 'shy', 'proud' },
    },
    cat_tabby = {
        label = 'Chat tigré', model = 'a_c_cat_01', kind = 'cat', hungerPerMinute = 0.6,
        variation = { component = 0, drawable = 0, texture = 1 },
        tricks = CAT, vehicle = SMALL_CAR,
        traits = { 'cuddly', 'lazy', 'curious', 'greedy', 'calm' },
    },

    -- Sauvages -----------------------------------------------------------------------
    coyote = {
        label = 'Coyote', model = 'a_c_coyote', kind = 'wild', hungerPerMinute = 1.2,
        tricks = COYOTE, vehicle = WILD_CAR,
        traits = { 'wild', 'fast', 'shy', 'independent', 'curious' },
    },
    puma = {
        label = 'Puma', model = 'a_c_mtlion', kind = 'wild', hungerPerMinute = 1.5,
        tricks = BIG_CAT, vehicle = false,
        traits = { 'wild', 'proud', 'fast', 'brave', 'independent' },
    },
    panther = {
        label = 'Panthère', model = 'a_c_panther', kind = 'wild', hungerPerMinute = 1.5,
        tricks = BIG_CAT, vehicle = false,
        traits = { 'wild', 'proud', 'calm', 'brave', 'independent' },
    },
    deer = {
        label = 'Cerf', model = 'a_c_deer', kind = 'wild', hungerPerMinute = 1.0,
        tricks = grazer('WORLD_DEER_GRAZING'), vehicle = false,
        traits = { 'wild', 'shy', 'majestic', 'calm', 'fast' },
    },
    boar = {
        label = 'Sanglier', model = 'a_c_boar', kind = 'wild', hungerPerMinute = 1.3,
        tricks = grazer('WORLD_BOAR_GRAZING', 'Fouiller'), vehicle = false,
        traits = { 'wild', 'brave', 'greedy', 'noisy', 'independent' },
    },
    rabbit = {
        label = 'Lapin', model = 'a_c_rabbit_01', kind = 'wild', hungerPerMinute = 0.5,
        tricks = RABBIT, vehicle = TINY_CAR,
        traits = { 'shy', 'cuddly', 'fast', 'curious', 'gentle' },
    },
    rat = {
        label = 'Rat', model = 'a_c_rat', kind = 'wild', hungerPerMinute = 0.4,
        tricks = RAT, vehicle = TINY_CAR,
        traits = { 'clever', 'sneaky', 'curious', 'greedy', 'agile' },
    },
    chimp = {
        label = 'Chimpanzé', model = 'a_c_chimp', kind = 'wild', hungerPerMinute = 1.1,
        tricks = PRIMATE, vehicle = PRIMATE_CAR,
        traits = { 'clever', 'playful', 'noisy', 'agile', 'curious' },
    },
    rhesus = {
        label = 'Macaque rhésus', model = 'a_c_rhesus', kind = 'wild', hungerPerMinute = 0.9,
        tricks = PRIMATE, vehicle = PRIMATE_CAR,
        traits = { 'clever', 'sneaky', 'playful', 'agile', 'noisy' },
    },

    -- Ferme --------------------------------------------------------------------------
    cow = {
        label = 'Vache', model = 'a_c_cow', kind = 'farm', hungerPerMinute = 1.4,
        tricks = grazer('WORLD_COW_GRAZING'), vehicle = false,
        traits = { 'calm', 'gentle', 'lazy', 'greedy', 'loyal' },
    },
    pig = {
        label = 'Cochon', model = 'a_c_pig', kind = 'farm', hungerPerMinute = 1.2,
        tricks = grazer('WORLD_PIG_GRAZING', 'Fouiller'), vehicle = false,
        traits = { 'greedy', 'clever', 'cuddly', 'lazy', 'noisy' },
    },
    hen = {
        label = 'Poule', model = 'a_c_hen', kind = 'farm', hungerPerMinute = 0.5,
        tricks = HEN, vehicle = TINY_CAR,
        traits = { 'noisy', 'curious', 'greedy', 'shy', 'gentle' },
    },

    -- Oiseaux ------------------------------------------------------------------------
    -- A CONFIRMER EN JEU : un oiseau de script peut s'envoler au lieu de suivre.
    hawk = {
        label = 'Faucon', model = 'a_c_chickenhawk', kind = 'bird', hungerPerMinute = 0.7,
        tricks = bird('WORLD_CHICKENHAWK_STANDING', 'WORLD_CHICKENHAWK_FEEDING'), vehicle = TINY_CAR,
        traits = { 'proud', 'majestic', 'loyal', 'fast', 'brave' },
    },
    crow = {
        label = 'Corbeau', model = 'a_c_crow', kind = 'bird', hungerPerMinute = 0.5,
        tricks = bird(nil, 'WORLD_CROW_FEEDING'), vehicle = TINY_CAR,
        traits = { 'clever', 'sneaky', 'curious', 'noisy', 'independent' },
    },
    pigeon = {
        label = 'Pigeon', model = 'a_c_pigeon', kind = 'bird', hungerPerMinute = 0.4,
        tricks = bird('WORLD_PIGEON_STANDING', 'WORLD_PIGEON_FEEDING'), vehicle = TINY_CAR,
        traits = { 'greedy', 'curious', 'calm', 'loyal', 'shy' },
    },
    seagull = {
        label = 'Mouette', model = 'a_c_seagull', kind = 'bird', hungerPerMinute = 0.5,
        tricks = bird('WORLD_SEAGULL_STANDING', 'WORLD_SEAGULL_FEEDING'), vehicle = TINY_CAR,
        traits = { 'noisy', 'greedy', 'sneaky', 'brave', 'independent' },
    },
    cormorant = {
        label = 'Cormoran', model = 'a_c_cormorant', kind = 'bird', hungerPerMinute = 0.6,
        tricks = bird('WORLD_CORMORANT_STANDING', nil), vehicle = TINY_CAR,
        traits = { 'calm', 'shy', 'proud', 'agile', 'independent' },
    },

    -- Non retenus : les animaux marins (dauphin, requins, baleines, raie,
    -- poisson) meurent hors de l'eau ; Chop (a_c_chop) double le rottweiler.
}

-- Libelle de « parler » par type, quand le tour ne porte pas le sien.
Config.SpeakLabels = {
    dog = 'Aboyer',
    cat = 'Miauler',
    wild = 'Grogner',
    farm = 'Crier',
    bird = 'Chanter',
}
