fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bl_pets'
description 'bl_pets -- animaux de compagnie (appel, suivi, tours, soins, faim)'
version '1.1.0'
author 'Brothers Life'

-- Contrat avec bl_premiumshop : SPEC §10 (bl_premiumshop/docs/SPEC.md),
-- exports serveur GrantPet / GetPets / PetAction / Species.
--
-- ox_target n'est PAS une dependance, a dessein : sans lui, la tablette
-- /animaux reste complete. bl_ui non plus : la tablette (html/) est autonome,
-- feuilles de style et polices comprises (copies locales, voir index.html).
dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/util.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua',
    'client/target.lua',
    'client/nametag.lua',
    -- Tablette « Mes animaux » (remplace le menu bl_ui le 2026-10-11).
    'client/tablet.lua',
    -- Panel staff /petadmin (meme page NUI que la tablette).
    'client/admin.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/admin.js',
    'html/admin.css',
    -- Images des especes (captures du jeu, html/img/species/<cle>.jpg) ; sources : CREDITS.md.
    'html/img/species/*.jpg',
    -- DA du serveur : copies locales des feuilles de tablette (voir index.html).
    'html/css/*.css',
    'html/bl/*.css',
    'html/fonts/*.woff2',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/main.lua',
    -- Panel staff (/petadmin) : apres main.lua, dont il lit Pets.Internal.
    'server/admin.lua',
    -- EN DERNIER, et seul dans son fichier : voir son en-tete.
    'server/exports.lua',
}

-- Sans cette option, `_ENV.MySQL` d'@oxmysql/lib/MySQL.lua n'est pas visible
-- entre les scripts serveur de la ressource (meme motif que qbx-itemmanager).
use_experimental_fxv2_oal 'yes'
