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
   ══════════════════════════════════════════════════════════════════════ */

(() => {
    const RES = 'bl_pets';
    const $ = (id) => document.getElementById(id);

    const ICON = { dog: '🐕', cat: '🐈', wild: '🐺' };
    const SPECIES_ICON = { puma: '🐆', panther: '🐆', pug: '🐶', westy: '🐶', poodle: '🐩', cat_black: '🐈‍⬛' };
    const TRICK_ICON = { sit: '🪑', lie: '💤', beg: '🙏', speak: '🔊' };
    const FOOD_ICON = { pet_wetfood: '🥫', pet_kibble: '🥣' };
    const STATE = { out: ['Sorti', 'ok'], stored: ['À la maison', null], injured: ['À soigner', 'danger'] };
    const TABS = [['apercu', 'Aperçu'], ['ordres', 'Ordres'], ['soins', 'Soins'], ['identite', 'Identité']];
    const HOME_SVG = '<svg viewBox="0 0 24 24" fill="none"><path d="M4 11l8-6.5 8 6.5V20a1 1 0 01-1 1h-4.5v-6h-5v6H5a1 1 0 01-1-1v-9z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>';
    const CLOSE_SVG = '<svg viewBox="0 0 24 24" fill="none"><path d="M6 6l12 12M18 6L6 18" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';

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

    const icon = (p) => SPECIES_ICON[p.species] || ICON[p.kind] || '🐾';
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
            <div class="rail-mark">🐾</div>
            <button type="button" class="rail-tab ${view.page === 'home' ? 'active' : ''}" data-home>${HOME_SVG}<span class="n">Accueil</span></button>
            ${model.pets.length ? `<div class="rail-sep">Compagnons</div>${pets}` : ''}
            <div class="rail-spacer"></div>
            <button type="button" class="rail-tab rail-close" data-close>${CLOSE_SVG}<span class="n">Fermer</span></button>`;
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
        const rows = model.pets.map((p) => `
            <button type="button" class="rw-link" data-pet="${p.id}">
                <span class="rw-ic">${icon(p)}</span>
                <span class="rw-t"><b>${esc(p.name)}</b><span>${esc(p.label)} · niveau ${level(p.xp).n}</span></span>
                ${mini('Santé', p.health, injuredAt())}${mini('Satiété', p.hunger, hungryAt() - 1)}
                ${stateChip(p)}<span class="chev">›</span>
            </button>`).join('');
        return `${head}${kpis}${banner}${section('Mes compagnons', rows)}`;
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

        return `<div class="pg-h">
                <span class="pet-av">${icon(p)}</span>
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
            return tile(`trick:${t.key}`, t.label, TRICK_ICON[t.key] || '✨',
                { disabled: !out || !t.known || hungry(p) || p.inVehicle, hint });
        }).join('');
        return section('Déplacement', `<div class="tiles">
                ${tile('follow', 'Suivre', '👣', { on: out && p.mode === 'follow', disabled: !out, hint: off })}
                ${tile('stay', 'Rester', '✋', { on: out && p.mode === 'stay', disabled: !out, hint: off })}
                ${tile('pet', 'Caresser', '🤚', { disabled: !out, hint: off || '+1 XP' })}
                ${out ? tile('dismiss', 'Rentrer', '🏠', { hint: 'À la maison' })
                      : tile('call', 'Appeler', '📣', { disabled: injured, hint: injured ? 'À soigner' : 'Il vous rejoint' })}
            </div>`)
            + section('Tours', `<div class="tiles">${tricks}</div>`, hungry(p) ? 'Un animal affamé refuse les tours.' : null);
    }

    function tabSoins(p) {
        const out = p.state === 'out';
        const injured = p.state === 'injured';
        const food = (model.items.food || []).map((it) => {
            const effect = [`+${it.hunger} % de satiété`, it.health ? `+${it.health} % de santé` : null].filter(Boolean).join(', ');
            return `<div class="rw"><span class="rw-ic">${FOOD_ICON[it.name] || '🍖'}</span>
                <div class="rw-t"><b>${esc(it.label)}</b><span>${esc(effect)}</span></div>
                <div class="rw-c"><span class="count">x${it.count}</span>
                ${button('Nourrir', { disabled: !out || it.count === 0 || p.hunger >= 98, act: `feed:${it.name}` })}</div></div>`;
        }).join('');
        const feed = section('Nourrir', food,
            out ? `À moins de ${rules().interact ?? 4} m de lui.` : 'Sortez votre animal pour le nourrir.');

        const kit = model.items.heal;
        const heal = kit ? section('Soigner', `<div class="rw"><span class="rw-ic">🩹</span>
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
            document.body.hidden = false;
            tickClock();
            clearInterval(clockTimer);
            // L'heure ne tourne que tablette ouverte.
            clockTimer = setInterval(tickClock, 15000);
            render();
        } else if (msg.action === 'data') {
            model = msg.data || model;
            if (!document.body.hidden) render();
        } else if (msg.action === 'close') {
            document.body.hidden = true;
            clearInterval(clockTimer);
        }
    });
})();
