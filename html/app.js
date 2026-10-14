/* ══════════════════════════════════════════════════════════════════════
   bl_pets — tablette « Mes animaux ».

   La page n'a AUCUNE logique de jeu : elle affiche l'etat que pousse
   client/tablet.lua (messages `open` / `data` / `close`) et renvoie chaque
   geste au callback NUI `action`, qui passe par PetAction cote serveur. Un
   refus revient en message (`err`), affiche en notification de tablette.

   Grisages (tour inconnu, animal affame, pas sorti...) : confort seulement,
   le serveur rejoue tout.

   Balisage : charte des tablettes (rail vertical, barre du haut .ghead) et
   mise en page « reglages de telephone » des reglages du HUD (.sx / .rw).

   La meme page sert au panel staff (admin.js) : `body[data-mode]` dit qui
   l'occupe, et chaque script ignore les clics quand ce n'est pas son tour.
   Les outils communs (echappement, photos, icones) sont exposes dans
   window.BLP pour admin.js.
   ══════════════════════════════════════════════════════════════════════ */

(() => {
    const RES = 'bl_pets';
    const $ = (id) => document.getElementById(id);

    // Icones au trait (24 x 24, couleur du texte). Les animaux, eux, ont
    // leur photo : img/species/<espece>.jpg (voir petImg).
    const svg = (d, extra = '') => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"${extra}>${d}</svg>`;
    const ICONS = {
        home: svg('<path d="M4 11l8-6.5 8 6.5V20a1 1 0 01-1 1h-4.5v-6h-5v6H5a1 1 0 01-1-1v-9z"/>'),
        close: svg('<path d="M6 6l12 12M18 6L6 18"/>'),
        paw: '<svg viewBox="0 0 24 24" fill="currentColor"><ellipse cx="6" cy="10" rx="2.1" ry="2.7"/><ellipse cx="10" cy="6" rx="2.1" ry="2.8"/><ellipse cx="14.5" cy="6" rx="2.1" ry="2.8"/><ellipse cx="18.4" cy="10" rx="2.1" ry="2.7"/><path d="M12.2 11.2c2.6 0 5.4 3.6 5.4 6.2 0 1.9-1.4 2.6-2.8 2.6-1.1 0-1.7-.6-2.6-.6s-1.6.6-2.7.6c-1.4 0-2.7-.7-2.7-2.6 0-2.6 2.8-6.2 5.4-6.2z"/></svg>',
        follow: svg('<path d="M5 12h13M13 6l6 6-6 6"/>'),
        stay: svg('<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>'),
        pet: svg('<path d="M12 20s-7-4.4-7-10a4 4 0 017-2.6A4 4 0 0119 10c0 5.6-7 10-7 10z"/>'),
        call: svg('<path d="M4 10v4h3l5 4V6L7 10H4z"/><path d="M16 9a4 4 0 010 6M18.5 6.5a7.5 7.5 0 010 11"/>'),
        sit: svg('<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>'),
        lie: svg('<path d="M20 14.5A8 8 0 019.5 4 8 8 0 1020 14.5z"/>'),
        beg: svg('<path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/>'),
        speak: svg('<path d="M4 10v4h3l5 4V6L7 10H4z"/><path d="M16 9.5a3.5 3.5 0 010 5"/>'),
        food: svg('<path d="M3 11h18a9 9 0 01-18 0zM8 7c0-1.5 1-2 1-3.5M12 7c0-1.5 1-2 1-3.5M16 7c0-1.5 1-2 1-3.5"/>'),
        kit: svg('<rect x="3.5" y="6.5" width="17" height="13" rx="2"/><path d="M9 6.5V4.5h6v2M12 10v6M9 13h6"/>'),
    };
    const TRICK_ICON = { sit: ICONS.sit, lie: ICONS.lie, beg: ICONS.beg, speak: ICONS.speak };
    const STATE = { out: ['Sorti', 'ok'], stored: ['À la maison', null], injured: ['À soigner', 'danger'] };
    const TABS = [['apercu', 'Aperçu'], ['ordres', 'Ordres'], ['soins', 'Soins'], ['identite', 'Identité']];
    const isMine = () => document.body.dataset.mode !== 'admin';

    let model = { pets: [], max: 10, items: { food: [], heal: null }, rules: {} };
    let view = { page: 'home', petId: null, tab: 'apercu' };
    let busy = false;
    let clockTimer = null;

    // ── Outils ────────────────────────────────────────────────────────────

    function esc(value) {
        return String(value ?? '').replace(/[&<>"']/g, (c) => (
            { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    function post(name, body) {
        return fetch(`https://${RES}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {}),
        }).then((r) => r.json()).catch(() => ({ ok: false, err: 'Pas de réponse du jeu.' }));
    }

    function toast(message, isError) {
        const el = document.createElement('div');
        el.className = 'toast' + (isError ? ' error' : '');
        el.textContent = message;
        $('toastHost').appendChild(el);
        setTimeout(() => el.remove(), 2600);
    }

    // Photo d'une espece. Sans fichier (espece ajoutee sans photo), l'image se
    // retire et la patte dessinee en fond de .ph reste visible.
    const petImg = (species, cls = '') => `<span class="ph ${cls}">${ICONS.paw}<img src="img/species/${encodeURIComponent(species || '')}.jpg" alt="" loading="lazy" onerror="this.remove()"></span>`;
    const icon = (p) => petImg(p.species);
    // Niveau d'affichage seulement : 50 XP par niveau (le serveur ne compte que l'XP).
    const level = (xp) => ({ n: Math.floor((xp || 0) / 50) + 1, pct: ((xp || 0) % 50) * 2 });
    const chip = (label, tone) => `<span class="chip ${tone ? `chip-${tone}` : ''}">${tone ? '<i></i>' : ''}${esc(label)}</span>`;
    const stateChip = (p) => { const [l, t] = STATE[p.state] || [p.state]; return chip(l, t === 'danger' ? 'warn' : t); };
    const button = (label, { tone = 'primary', disabled, act } = {}) =>
        `<button type="button" class="btn btn-${tone}" ${disabled ? 'disabled' : ''} ${act ? `data-act="${esc(act)}"` : ''}>${esc(label)}</button>`;
    const rules = () => model.rules || {};
    const injuredAt = () => rules().injured ?? 15;
    const hungryAt = () => rules().hungry ?? 25;
    const hungry = (p) => p.hunger < hungryAt();
    const current = () => model.pets.find((p) => p.id === view.petId);
    const tone = (v, low) => (v <= low ? 'danger' : (v < 40 ? 'warn' : ''));
    const pct = (v) => Math.max(0, Math.min(100, Math.round(v)));

    const gauge = (value, low, cls) => `<span class="gauge"><i><u class="${cls || tone(value, low)}" style="width:${pct(value)}%"></u></i><b>${pct(value)} %</b></span>`;
    const mini = (label, value, low) => `<span class="mini"><span>${esc(label)}<b>${pct(value)} %</b></span><i><u class="${tone(value, low)}" style="width:${pct(value)}%"></u></i></span>`;
    const row = (title, sub, control) => `<div class="rw"><div class="rw-t"><b>${esc(title)}</b>${sub ? `<span>${esc(sub)}</span>` : ''}</div><div class="rw-c">${control}</div></div>`;
    const section = (title, body, note) => `<div class="sx">${title ? `<h4>${esc(title)}</h4>` : ''}<div class="sx-list">${body}</div>${note ? `<p class="sx-note">${esc(note)}</p>` : ''}</div>`;

    function dateFr(ms) {
        const n = Number(ms);
        if (!n) return '—';
        return new Date(n).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' });
    }

    function tickClock() {
        const d = new Date();
        $('clock').textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    }

    // ── Cadre : rail et barre du haut ─────────────────────────────────────

    function renderRail() {
        const pets = model.pets.map((p) => `
            <button type="button" class="rail-tab ${view.page === 'pet' && view.petId === p.id ? 'active' : ''}" data-pet="${p.id}">
                <span class="ico">${icon(p)}</span><span class="n">${esc(p.name)}</span>
                <span class="rail-dot ${esc(p.state)}"></span>
            </button>`).join('');
        $('rail').innerHTML = `
            <div class="rail-mark">${ICONS.paw}</div>
            <button type="button" class="rail-tab ${view.page === 'home' ? 'active' : ''}" data-home>${ICONS.home}<span class="n">Accueil</span></button>
            ${model.pets.length ? `<div class="rail-sep">Compagnons</div>${pets}` : ''}
            <div class="rail-spacer"></div>
            <button type="button" class="rail-tab rail-close" data-close>${ICONS.close}<span class="n">Fermer</span></button>`;
    }

    function renderHead() {
        const p = view.page === 'pet' ? current() : null;
        const tabLabel = p ? (TABS.find(([k]) => k === view.tab) || TABS[0])[1] : null;
        $('crumb').innerHTML = p
            ? `<span>Mes animaux</span><i>/</i><b class="is-parent">${esc(p.name)}</b><i>/</i><b>${esc(tabLabel)}</b>`
            : '<span>Mes animaux</span><i>/</i><b>Accueil</b>';
        const out = model.pets.find((x) => x.state === 'out');
        const tag = $('outTag');
        tag.hidden = !out;
        tag.className = 'ghead-tag' + (out ? ' is-out' : '');
        tag.innerHTML = out ? `<i></i>${esc(out.name)} est avec vous` : '';
    }

    // ── Accueil ───────────────────────────────────────────────────────────

    function renderHome() {
        const head = `<div class="pg-h"><div class="pg-h-t"><h2>Mes animaux</h2>
            <p>Vos compagnons, leur santé et leur faim. Un seul animal sort à la fois.</p></div></div>`;
        if (!model.pets.length) {
            return `${head}<div class="sx-list empty-pets"><b>Aucun animal</b><span>Les animaux de compagnie s'adoptent dans la boutique.</span></div>`;
        }
        const out = model.pets.find((p) => p.state === 'out');
        const injured = model.pets.filter((p) => p.state === 'injured').length;
        const starving = model.pets.filter((p) => hungry(p));
        const kpis = `<div class="kpis">
            <div class="kpi kpi-sm"><span class="kpi-label">Animaux</span><span class="kpi-value">${model.pets.length} / ${model.max}</span></div>
            <div class="kpi kpi-sm"><span class="kpi-label">Avec vous</span><span class="kpi-value">${out ? esc(out.name) : '—'}</span></div>
            <div class="kpi kpi-sm"><span class="kpi-label">À soigner</span><span class="kpi-value">${injured}</span>
                ${injured ? '<span class="kpi-hint is-danger">Trousse vétérinaire</span>' : ''}</div>
        </div>`;
        const banner = starving.length
            ? `<div class="banner"><b>${starving.length === 1 ? `${esc(starving[0].name)} a faim` : `${starving.length} animaux ont faim`}</b>Un animal affamé suit au pas et refuse les tours.</div>`
            : '';
        const cards = model.pets.map((p) => `
            <button type="button" class="pet-card ${p.state === 'out' ? 'is-out' : ''} ${p.state === 'injured' ? 'is-injured' : ''}" data-pet="${p.id}">
                ${petImg(p.species, 'pet-card-ph')}
                <span class="pet-card-state">${stateChip(p)}</span>
                <span class="pet-card-body">
                    <b>${esc(p.name)}</b>
                    <span class="pet-card-sub">${esc(p.label)} · niveau ${level(p.xp).n}</span>
                    <span class="pet-card-gauges">${mini('Santé', p.health, injuredAt())}${mini('Satiété', p.hunger, hungryAt() - 1)}</span>
                </span>
            </button>`).join('');
        return `${head}${kpis}${banner}<div class="sx"><h4>Mes compagnons</h4><div class="pet-cards">${cards}</div></div>`;
    }

    // ── Fiche ─────────────────────────────────────────────────────────────

    function renderPet(p) {
        const out = p.state === 'out';
        const injured = p.state === 'injured';
        const main = out
            ? button('Rentrer', { tone: 'quiet', act: 'dismiss' })
            : button('Appeler', { disabled: injured, act: 'call' });
        const tabs = TABS.map(([k, l]) => `<button type="button" class="${view.tab === k ? 'is-active' : ''}" data-tab="${k}">${l}</button>`).join('');
        const body = ({ apercu: tabApercu, ordres: tabOrdres, soins: tabSoins, identite: tabIdentite })[view.tab] || tabApercu;

        return `<div class="pg-h pg-h-pet">
                ${petImg(p.species, 'pet-av')}
                <div class="pg-h-t"><h2>${esc(p.name)}</h2>
                    <p>${stateChip(p)} ${esc(p.label)} · ${esc(p.kindLabel)} · niveau ${level(p.xp).n}</p></div>
                ${main}
            </div>
            ${injured ? `<div class="banner danger"><b>Gravement blessé</b>Il ne peut plus sortir. Soignez-le avec une trousse vétérinaire (onglet Soins), même à la maison.</div>` : ''}
            <div class="seg">${tabs}</div>
            ${body(p)}`;
    }

    function tabApercu(p) {
        const l = level(p.xp);
        const known = (p.tricks || []).filter((t) => t.known).length;
        return section('État',
                row('Santé', p.health <= injuredAt() ? 'À soigner : il ne sort plus.' : null, gauge(p.health, injuredAt()))
                + row('Satiété', hungry(p) ? 'Affamé : il suit au pas et refuse les tours.' : 'Baisse seulement quand il est sorti.', gauge(p.hunger, hungryAt() - 1))
                + row(`Niveau ${l.n}`, `${p.xp} XP · caresses : +1 XP`, gauge(l.pct, -1, 'accent')))
            + section('Fiche',
                row('Espèce', null, `<span>${esc(p.label)} (${esc(p.kindLabel)})</span>`)
                + row('Caractère', null, `<span class="chips">${(p.traits || []).map((t) => chip(t)).join('') || '—'}</span>`)
                + row('Adopté le', null, `<span>${dateFr(p.adoptedAt)}</span>`)
                + row('En voiture', 'Il monte s\'il y a une place passager libre.', `<span>${esc(p.vehicle)}</span>`)
                + row('Tours connus', null, `<span>${known} / ${(p.tricks || []).length}</span>`));
    }

    function tile(act, label, ic, { on, disabled, hint } = {}) {
        return `<button type="button" class="tile ${on ? 'on' : ''}" data-act="${esc(act)}" ${disabled ? 'disabled' : ''}>
            <span class="tile-ic">${ic}</span><b>${esc(label)}</b><span>${esc(hint || '')}</span></button>`;
    }

    function tabOrdres(p) {
        const out = p.state === 'out';
        const injured = p.state === 'injured';
        const off = out ? '' : "Sortez-le d'abord";
        const tricks = (p.tricks || []).map((t) => {
            const hint = !t.known ? 'Ne sait pas faire'
                : !out ? off
                : p.inVehicle ? 'Pas en voiture'
                : hungry(p) ? 'A trop faim' : '';
            return tile(`trick:${t.key}`, t.label, TRICK_ICON[t.key] || ICONS.beg,
                { disabled: !out || !t.known || hungry(p) || p.inVehicle, hint });
        }).join('');
        return section('Déplacement', `<div class="tiles">
                ${tile('follow', 'Suivre', ICONS.follow, { on: out && p.mode === 'follow', disabled: !out, hint: off })}
                ${tile('stay', 'Rester', ICONS.stay, { on: out && p.mode === 'stay', disabled: !out, hint: off })}
                ${tile('pet', 'Caresser', ICONS.pet, { disabled: !out, hint: off || '+1 XP' })}
                ${out ? tile('dismiss', 'Rentrer', ICONS.home, { hint: 'À la maison' })
                      : tile('call', 'Appeler', ICONS.call, { disabled: injured, hint: injured ? 'À soigner' : 'Il vous rejoint' })}
            </div>`)
            + section('Tours', `<div class="tiles">${tricks}</div>`, hungry(p) ? 'Un animal affamé refuse les tours.' : null);
    }

    function tabSoins(p) {
        const out = p.state === 'out';
        const injured = p.state === 'injured';
        const food = (model.items.food || []).map((it) => {
            const effect = [`+${it.hunger} % de satiété`, it.health ? `+${it.health} % de santé` : null].filter(Boolean).join(', ');
            return `<div class="rw"><span class="rw-ic">${ICONS.food}</span>
                <div class="rw-t"><b>${esc(it.label)}</b><span>${esc(effect)}</span></div>
                <div class="rw-c"><span class="count">x${it.count}</span>
                ${button('Nourrir', { disabled: !out || it.count === 0 || p.hunger >= 98, act: `feed:${it.name}` })}</div></div>`;
        }).join('');
        const feed = section('Nourrir', food,
            out ? `À moins de ${rules().interact ?? 4} m de lui.` : 'Sortez votre animal pour le nourrir.');

        const kit = model.items.heal;
        const heal = kit ? section('Soigner', `<div class="rw"><span class="rw-ic">${ICONS.kit}</span>
                <div class="rw-t"><b>${esc(kit.label)}</b><span>Santé à ${kit.health} %</span></div>
                <div class="rw-c"><span class="count">x${kit.count}</span>
                ${button('Soigner', { tone: injured ? 'primary' : 'quiet', disabled: kit.count === 0 || p.health >= 100, act: 'heal' })}</div></div>`,
            'La trousse marche aussi quand il est à la maison.') : '';

        // Blesse : le soin passe devant, c'est la seule chose qui le debloque.
        return injured ? heal + feed : feed + heal;
    }

    function tabIdentite(p) {
        const r = rules();
        return section('Nom', `<div class="rw"><div class="inline-form">
                <input class="field-input" id="nameInput" maxlength="${r.nameMax ?? 20}" value="${esc(p.name)}">
                ${button('Enregistrer', { act: 'rename' })}</div></div>`,
            `${r.nameMin ?? 2} à ${r.nameMax ?? 20} caractères : lettres, chiffres, espace, tiret, apostrophe.`);
    }

    function render() {
        const p = current();
        if (view.page === 'pet' && !p) view = { page: 'home', petId: null, tab: 'apercu' };
        renderRail();
        renderHead();
        // Le champ de nom en cours de saisie ne doit pas etre ecrase par un
        // rafraichissement du tic serveur.
        const typing = document.activeElement && document.activeElement.id === 'nameInput'
            ? document.activeElement.value : null;
        const pet = current();
        $('view').innerHTML = view.page === 'pet' && pet ? renderPet(pet) : renderHome();
        if (typing !== null && $('nameInput')) {
            $('nameInput').value = typing;
            $('nameInput').focus();
        }
    }

    // ── Gestes ────────────────────────────────────────────────────────────

    async function act(action, arg) {
        const p = current();
        if (!p || busy) return;
        let data = null;
        if (action === 'trick') data = { trick: arg };
        if (action === 'feed') data = { item: arg };
        if (action === 'rename') {
            const name = ($('nameInput').value || '').trim();
            if (!name) return toast('Nom invalide.', true);
            data = { name };
        }

        busy = true;
        $('view').classList.add('busy');
        const res = await post('action', { petId: p.id, action, data });
        busy = false;
        $('view').classList.remove('busy');

        if (!res || !res.ok) return toast((res && res.err) || 'Refusé.', true);
        if (action === 'rename') toast('Nom enregistré.');
        // Le reste du retour passe par les notifications du jeu et par le
        // rafraichissement que pousse client/tablet.lua.
    }

    document.addEventListener('click', (e) => {
        if (!isMine()) return;
        if (e.target.closest('[data-close]')) return post('close');
        const petBtn = e.target.closest('[data-pet]');
        if (petBtn) { view = { page: 'pet', petId: Number(petBtn.dataset.pet), tab: 'apercu' }; return render(); }
        if (e.target.closest('[data-home]')) { view = { page: 'home', petId: null, tab: 'apercu' }; return render(); }
        const tabBtn = e.target.closest('[data-tab]');
        if (tabBtn) { view.tab = tabBtn.dataset.tab; return render(); }
        const a = e.target.closest('[data-act]');
        if (a && !a.disabled) {
            const [action, arg] = a.dataset.act.split(':');
            act(action, arg);
        }
    });

    document.addEventListener('keydown', (e) => {
        if (!isMine()) return;
        if (e.key === 'Escape') post('close');
        if (e.key === 'Enter' && document.activeElement && document.activeElement.id === 'nameInput') act('rename');
    });

    window.addEventListener('message', (e) => {
        const msg = e.data || {};
        if (msg.action === 'open') {
            model = msg.data || model;
            view = msg.focus && model.pets.some((p) => p.id === msg.focus)
                ? { page: 'pet', petId: msg.focus, tab: 'apercu' }
                : { page: 'home', petId: null, tab: 'apercu' };
            document.body.dataset.mode = 'player';
            document.body.hidden = false;
            tickClock();
            clearInterval(clockTimer);
            // L'heure ne tourne que tablette ouverte.
            clockTimer = setInterval(tickClock, 15000);
            render();
        } else if (msg.action === 'data') {
            model = msg.data || model;
            if (!document.body.hidden && isMine()) render();
        } else if (msg.action === 'close') {
            document.body.hidden = true;
            clearInterval(clockTimer);
        }
    });

    window.BLP = { esc, post, toast, petImg, ICONS, chip, mini, gauge, dateFr, tickClock };
})();
