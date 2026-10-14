# bl_pets — animaux de compagnie

Animaux achetés dans `bl_premiumshop` (contrat : `bl_premiumshop/docs/SPEC.md` §10) ou donnés par le staff. Un seul animal sorti à la fois par joueur.

## Installation

1. La ressource est dans `[standalone]`, démarrée par `ensure [standalone]`. Elle dépend de `qbx_core`, `ox_lib`, `oxmysql` et `ox_inventory`. `ox_target` est utilisé s'il tourne, sans être déclaré en dépendance. La tablette (`html/`) est autonome : seule sa police vient de `bl_ui`.
2. La table `bl_pets` se crée seule au démarrage (`CREATE TABLE IF NOT EXISTS`).
3. Les objets ox_inventory : les ajouter à la fin de `[ox]/ox_inventory/data/items.lua`, avant la dernière `}`. Le fichier est en **CRLF** et en **lecture seule** pour le compte SFTP de l'agent. Ensuite, `restart ox_inventory`, puis `restart bl_pets`.

```lua
	-- AJOUT LOCAL (hors upstream) bl_pets : nourriture et soins des animaux de
	-- compagnie ([standalone]/bl_pets). consume = 0 : c'est le serveur de bl_pets
	-- qui retire l'objet apres ses verifications (animal a soi, sorti, proche,
	-- pas rassasie). Satiete et soin rendus : bl_pets/config.lua (Config.Items).
	['pet_kibble'] = {
		label = 'Croquettes',
		description = 'Un sachet de croquettes pour votre animal. À utiliser près de lui.',
		weight = 500, stack = true, close = true, consume = 0,
		client = { export = 'bl_pets.useFood' },
	},
	['pet_wetfood'] = {
		label = 'Pâtée',
		description = 'Une barquette de pâtée, plus nourrissante que les croquettes.',
		weight = 400, stack = true, close = true, consume = 0,
		client = { export = 'bl_pets.useFood' },
	},
	['pet_vetkit'] = {
		label = 'Trousse vétérinaire',
		description = 'Soigne un animal blessé, même rentré à la maison.',
		weight = 800, stack = true, close = true, consume = 0,
		client = { export = 'bl_pets.useVetKit' },
	},
```

Si un objet est modifié dans qbx-itemmanager, il faut garder son bloc `client.export`. Au démarrage, le client écrit un avertissement dans F8 quand ce bloc manque.

## Commandes

| Commande | Effet |
|---|---|
| `/animaux` | Ouvre ou ferme la tablette « Mes animaux ». Pas de raccourci clavier : commande seulement. Échap ferme. |
| `/givepet <id> <espèce>` | Staff (`group.admin`) : donne un animal au personnage connecté. |

Espèces : `husky`, `retriever`, `shepherd`, `rottweiler`, `pug`, `poodle`, `westy`, `cat_black`, `cat_tabby`, `coyote`, `puma`, `panther`. Elles se règlent dans `config.lua` : modèle, tours permis, véhicule, vitesse de la faim et traits.

## En jeu

- **Tablette** (`html/`, maquette : `resources/tools/preview/pets-tablette.html`) : vue d'ensemble des animaux, puis une fiche par animal en 4 onglets (Aperçu, Ordres, Soins, Identité). Elle se met à jour en direct (tic serveur, arrivée, rentrée).
- **ox_target** sur son propre animal : Ouvrir la fiche, Caresser, Nourrir, Soigner, Suivre, Rester, les tours, Rentrer.
- **Véhicule** : l'animal qui suit monte avec le joueur s'il y a une place passager libre et que son espèce l'accepte. Puma et panthère ne montent jamais. Le coyote monte seulement dans un SUV, un tout-terrain ou une camionnette. Il descend en même temps que le joueur.
- **Faim** : la satiété baisse seulement quand l'animal est sorti. En dessous de 25 %, l'animal suit au pas et refuse les tours.
- **Santé** : un animal à 15 % ou moins (ou mort en jeu) est « à soigner ». Il ne peut plus sortir tant qu'il n'a pas reçu une trousse vétérinaire (depuis le menu, même s'il est rentré).
- **Disparition** : l'animal rentre quand on le demande, à la déconnexion, au changement de personnage et après 45 s de mort du propriétaire. Au restart de la ressource, les animaux restés dans le monde sont retrouvés par leur statebag `blPet` et supprimés.

## Apparition (2026-10-11)

Le **serveur** crée le ped (`handlers.call`), le client en prend ensuite le contrôle. Le bucket 0 est en lockdown `relaxed`, qui bloque les entités de script créées par un client : un `CreatePed` réseau côté client restait visible chez lui seul, puis disparaissait.

## Exports

Serveur (les signatures suivent le SPEC §10 : ne pas les modifier) :

```lua
exports.bl_pets:GrantPet(citizenid, species, { source = 'premium', name = nil }) -- -> petId | nil, err
exports.bl_pets:GetPets(citizenid)   -- -> { { id, species, name, traits, health, hunger, state = 'out'|'stored'|'injured', xp, label, kind } }
exports.bl_pets:PetAction(source, petId, action, data) -- -> ok, err
--   action : call, dismiss, rename ({ name = '...' }), follow, stay,
--            trick ({ trick = 'sit'|'lie'|'beg'|'speak' }), feed ({ item = 'pet_kibble' }), heal, pet
exports.bl_pets:Species()            -- -> { [species] = { label, model, kind, traits, tricks, vehicle } }
```

Les codes d'erreur (`injured`, `not_owner`, `limit`...) et leurs messages en français sont dans `shared/util.lua` (`PetsShared.Errors`).

Client :

```lua
exports.bl_pets:OpenMenu(petId?)  -- ouvre la tablette, directement sur un animal si petId est donné
```
