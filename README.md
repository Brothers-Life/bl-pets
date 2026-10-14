# bl_pets — animaux de compagnie

Animaux achetés dans `bl_premiumshop` (contrat : `bl_premiumshop/docs/SPEC.md` §10) ou donnés par le staff. Un seul animal sorti à la fois par joueur.

## Installation

1. La ressource est dans `[standalone]`, démarrée par `ensure [standalone]`. Elle dépend de `qbx_core`, `ox_lib`, `oxmysql` et `ox_inventory`. `ox_target` est utilisé s'il tourne, sans être déclaré en dépendance. La tablette (`html/`) est autonome : feuilles de style, polices et photos sont des copies locales.
2. Les tables `bl_pets` et `bl_pets_logs` (journal du panel staff) se créent seules au démarrage (`CREATE TABLE IF NOT EXISTS`).
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
| `/petadmin` | Staff (`group.admin`) : ouvre le panel staff des animaux. |

Espèces (26), par type :

| Type | Espèces |
|---|---|
| Chiens | `husky`, `retriever`, `shepherd`, `rottweiler`, `pug`, `poodle`, `westy` |
| Chats | `cat_black`, `cat_tabby` |
| Sauvages | `coyote`, `puma`, `panther`, `deer`, `boar`, `rabbit`, `rat`, `chimp`, `rhesus` |
| Ferme | `cow`, `pig`, `hen` |
| Oiseaux | `hawk`, `crow`, `pigeon`, `seagull`, `cormorant` |

Elles se règlent dans `config.lua` : modèle, tours permis, véhicule, vitesse de la faim et traits. Les animaux marins (dauphin, requins, baleines, raie, poisson) ne sont pas proposés : ils meurent hors de l'eau. Les oiseaux et les tours des nouvelles espèces (brouter, picorer...) sont **à confirmer en jeu**.

Chaque espèce a sa photo dans `html/img/species/<clé>.jpg` (photos Wikimedia Commons sous licence libre, auteurs et licences dans `html/img/species/CREDITS.md`). Une espèce ajoutée sans photo affiche une patte à la place.

## Panel staff (`/petadmin`)

Réservé à `Config.Admin.group` (`group.admin`). Le serveur revérifie ce droit (ace `command.petadmin`) à chaque requête du panel.

- **Tableau** : nombre d'animaux, propriétaires, sortis, à soigner, affamés ; animaux sortis en direct (propriétaire, rue, instance) avec fiche, TP et rentrée ; répartition par type, espèces les plus adoptées, plus gros propriétaires, dernières actions. Bouton « Rentrer tous les animaux ».
- **Animaux** : recherche par n°, nom, propriétaire (nom du personnage ou citizenid), filtres par type, espèce et état.
- **Fiche** : soigner, nourrir, TP, rentrer, supprimer ; modifier le nom, l'espèce, la santé, la satiété, l'XP et le caractère ; transférer à un joueur en ligne ou à un citizenid ; historique de l'animal.
- **Donner** : à un joueur en ligne ou à un citizenid hors ligne, avec nom facultatif et dépassement possible de la limite.
- **Espèces** : catalogue avec photos, tours, véhicule, faim et nombre d'adoptions.
- **Journal** : adoptions (boutique, staff) et actions du staff, dans la table `bl_pets_logs`.

Les modifications d'un animal sorti s'appliquent aussi en jeu (santé, nom au-dessus de la tête). Changer l'espèce, transférer ou supprimer fait d'abord rentrer l'animal.

## En jeu

- **Tablette** (`html/`, maquette : `resources/tools/preview/pets-tablette.html`, agrandie et passée aux photos le 2026-10-14) : vue d'ensemble des animaux en cartes avec photo, puis une fiche par animal en 4 onglets (Aperçu, Ordres, Soins, Identité). Elle se met à jour en direct (tic serveur, arrivée, rentrée).
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
exports.bl_pets:Species()            -- -> { [species] = { label, model, kind, kindLabel, traits, traitLabels, tricks, vehicle } }
--   kind : 'dog' | 'cat' | 'wild' | 'farm' | 'bird' (farm et bird ajoutés le 2026-10-14)
```

Les codes d'erreur (`injured`, `not_owner`, `limit`...) et leurs messages en français sont dans `shared/util.lua` (`PetsShared.Errors`).

Client :

```lua
exports.bl_pets:OpenMenu(petId?)  -- ouvre la tablette, directement sur un animal si petId est donné
```
