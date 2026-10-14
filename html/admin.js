/* ══════════════════════════════════════════════════════════════════════
   bl_pets — panel staff (/petadmin).

   Meme page et meme chassis que la tablette « Mes animaux » (app.js) :
   `body[data-mode="admin"]` dit que c'est notre tour, et app.js ignore
   alors les clics. Nos attributs portent le prefixe `data-a-` pour ne
   jamais croiser ceux d'app.js.

   Aucune decision ici : chaque geste part au callback NUI `admin` ({ op,
   args }), relaye au serveur qui revérifie le droit staff et valide tout.
   ══════════════════════════════════════════════════════════════════════ */

(() => {
    const { esc, post, toast, petImg, ICONS, chip, mini, dateFr, tickClock } = window.BLP;
    const $ = (id) => document.getElementById(id);

    const svg = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
    const AI = {
        dash: svg('<rect x="3.5" y="3.5" width="7" height="8" rx="1.5"/><rect x="13.5" y="3.5" width="7" height="5" rx="1.5"/><rect x="13.5" y="11.5" width="7" height="9" rx="1.5"/><rect x="3.5" y="14.5" width="7" height="6" rx="1.5"/>'),
        give: svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 8v8M8 12h8"/>'),
        book: svg('<path d="M5 4.5h10.5a3 3 0 013 3V20H8a3 3 0 01-3-3V4.5z"/><path d="M5 17a3 3 0 013-3h10.5"/>'),
        logs: svg('<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>'),
        refresh: svg('<path d="M20 11a8 8 0 10-2.3 5.7M20 5v6h-6"/>'),
        tp: svg('<path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0113 0c0 5.4-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>'),
        trash: svg('<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/>'),
    };

    const PAGES = [
        ['dash', 'Tableau', AI.dash],
        ['pets', 'Animaux', ICONS.paw],
        ['give', 'Donner', AI.give],
        ['species', 'Espèces', AI.book],
        ['logs', 'Journal', AI.logs],
    ];
    const STATE = { out: ['Sorti', 'ok'], stored: ['À la maison', null], injured: ['À soigner', 'warn'] };
    const STATE_FILTERS = [['', 'Tous les états'], ['out', 'Sortis'], ['stored', 'À la maison'], ['injured', 'À soigner'], ['hungry', 'Affamés']];
    const ACTIONS = {
        grant: 'Adoption', update: 'Modification', dismiss: 'Rentré', dismiss_all: 'Tout rentré',
        teleport: 'Téléportation', transfer: 'Transfert', delete: 'Suppression',
    };
    const FIELD_LABELS = { name: 'Nom', species: 'Espèce', health: 'Santé', hunger: 'Satiété', xp: 'XP', traits: 'Caractère' };

    let meta = { species: [], kinds: [], traits: {}, rules: {} };
    let page = 'dash';
    let dash = null;
    let list = null;
    let filters = { q: '', kind: '', species: '', state: '', page: 1 };
    let pet = null;
    let players = [];
    let logs = [];
    let give = { target: '', citizenid: '', species: '', name: '', ignoreLimit: false };
    let confirm = null;
    let busy = false;
    let refreshTimer = null;
    let clockTimer = null;

    const isMine = () => document.body.dataset.mode === 'admin' && !document.body.hidden;
    const speciesOf = (key) => meta.species.find((s) => s.key === key);
    const speciesLabel = (key) => (speciesOf(key) || {}).label || key;
    const kindLabel = (key) => (meta.kinds.find((k) => k.key === key) || {}).label || key;
    const rules = () => meta.rules || {};
    const stateChip = (state) => { const [l, t] = STATE[state] || [state]; return chip(l, t); };
    const ownerText = (name, cid) => name ? `${esc(name)} <span class="mono muted">${esc(cid)}</span>` : `<span class="mono">${esc(cid)}</span>`;
    const btn = (label, attrs, tone = 'quiet', icon = '') =>
        `<button type="button" class="btn btn-${tone} btn-sm" ${attrs}>${icon}${esc(label)}</button>`;
    const section = (title, body, extra = '') => `<div class="sx ${extra}">${title ? `<h4>${esc(title)}</h4>` : ''}<div class="sx-list">${body}</div></div>`;

    function dateTime(ms) {
        const n = Number(ms);
        if (!n) return '—';
        return new Date(n).toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' });
    }

    async function call(op, args) {
        const res = await post('admin', { op, args: args || {} });
        if (!res || !res.ok) {
            toast((res && res.err) || 'Refusé.', true);
            return null;
        }
        return res.data;
    }

    // ── Cadre ─────────────────────────────────────────────────────────────

    function renderRail() {
        const active = page === 'pet' ? 'pets' : page;
        $('rail').innerHTML = `
            <div class="rail-mark admin-mark">${ICONS.paw}<span>STAFF</span></div>
            ${PAGES.map(([k, l, ic]) => `<button type="button" class="rail-tab ${active === k ? 'active' : ''}" data-a-nav="${k}">${ic}<span class="n">${l}</span></button>`).join('')}
            <div class="rail-spacer"></div>
            <button type="button" class="rail-tab rail-close" data-a-close>${ICONS.close}<span class="n">Fermer</span></button>`;
    }

    function renderHead() {
        const label = page === 'pet' && pet ? null : (PAGES.find(([k]) => k === page) || PAGES[0])[1];
        $('crumb').innerHTML = page === 'pet' && pet
            ? `<span>Staff animaux</span><i>/</i><b class="is-parent" data-a-nav="pets">Animaux</b><i>/</i><b>${esc(pet.name)} #${pet.id}</b>`
            : `<span>Staff animaux</span><i>/</i><b>${esc(label)}</b>`;
        const tag = $('outTag');
        tag.hidden = false;
        tag.className = 'ghead-tag is-staff';
        tag.innerHTML = '<i></i>Panel staff';
    }

    function render() {
        renderRail();
        renderHead();
        const body = {
            dash: renderDash, pets: renderPets, pet: renderPet, give: renderGive, species: renderSpecies, logs: renderLogs,
        }[page] || renderDash;
        $('view').innerHTML = `<div class="admin">${body()}</div>`;
    }

    function head(title, sub, actions = '') {
        return `<div class="pg-h"><div class="pg-h-t"><h2>${esc(title)}</h2>${sub ? `<p>${sub}</p>` : ''}</div>${actions}</div>`;
    }

    const loading = () => '<div class="sx-list empty-pets"><b>Chargement…</b></div>';

    // ── Tableau de bord ───────────────────────────────────────────────────

    function renderDash() {
        const actions = `<div class="a-actions">
            ${btn('Actualiser', 'data-a-op="refresh"', 'quiet', AI.refresh)}
            ${confirm === 'dismissAll'
                ? btn('Confirmer : tout rentrer', 'data-a-op="dismissAll"', 'danger')
                : btn('Rentrer tous les animaux', 'data-a-ask="dismissAll"', 'danger')}
        </div>`;
        const top = head('Tableau de bord', 'Animaux de compagnie du serveur, en direct.', actions);
        if (!dash) return top + loading();
        const d = dash;

        const kpi = (label, value, hint, tone) => `<div class="kpi"><span class="kpi-label">${label}</span><span class="kpi-value">${value}</span>${hint ? `<span class="kpi-hint ${tone ? `is-${tone}` : ''}">${hint}</span>` : ''}</div>`;
        const kpis = `<div class="a-kpis">
            ${kpi('Animaux', d.total, `${meta.species.length} espèces`)}
            ${kpi('Propriétaires', d.owners)}
            ${kpi('Sortis', d.outCount, d.outCount ? 'en ce moment' : null, d.outCount ? 'ok' : null)}
            ${kpi('À soigner', d.injured, d.injured ? 'trousse vétérinaire' : null, d.injured ? 'danger' : null)}
            ${kpi('Affamés', d.hungry, d.hungry ? `satiété < ${rules().hungry ?? 25} %` : null, d.hungry ? 'warn' : null)}
        </div>`;

        const out = (d.out || []).map((o) => `
            <div class="rw a-row">
                ${petImg(o.species, 'a-ph')}
                <div class="rw-t"><b>${esc(o.name)} <span class="muted">#${o.petId}</span></b>
                    <span>${esc(speciesLabel(o.species))} · ${ownerText(o.ownerName || o.playerName, o.citizenid)} · joueur ${o.src}</span>
                    <span class="muted">${o.street ? esc(o.street) : '—'}${o.bucket ? ` · instance ${o.bucket}` : ''}${o.pending ? ' · en route' : ''}${o.dead ? ' · mort' : ''}</span></div>
                ${mini('Santé', o.health, rules().injured ?? 15)}${mini('Satiété', o.hunger, (rules().hungry ?? 25) - 1)}
                <div class="rw-c">
                    ${btn('Fiche', `data-a-pet="${o.petId}"`)}
                    ${btn('TP', `data-a-op="teleport" data-id="${o.petId}"`, 'quiet', AI.tp)}
                    ${btn('Rentrer', `data-a-op="dismiss" data-id="${o.petId}"`, 'danger')}
                </div>
            </div>`).join('') || '<div class="rw"><div class="rw-t"><span>Aucun animal sorti.</span></div></div>';

        const kindMax = Math.max(1, ...Object.values(d.byKind || {}));
        const kinds = meta.kinds.map((k) => {
            const n = (d.byKind || {})[k.key] || 0;
            return `<button type="button" class="a-bar" data-a-kind="${esc(k.key)}"><span>${esc(k.label)}</span><i><u style="width:${Math.round(n / kindMax * 100)}%"></u></i><b>${n}</b></button>`;
        }).join('');

        const topSpecies = Object.entries(d.bySpecies || {}).sort((a, b) => b[1] - a[1]).slice(0, 6).map(([key, n]) => `
            <button type="button" class="rw-link" data-a-species="${esc(key)}">${petImg(key, 'a-ph-sm')}
                <span class="rw-t"><b>${esc(speciesLabel(key))}</b><span>${esc(kindLabel((speciesOf(key) || {}).kind))}</span></span>
                <span class="count">${n}</span></button>`).join('') || '<div class="rw"><div class="rw-t"><span>Aucun animal.</span></div></div>';

        const owners = (d.topOwners || []).map((o) => `
            <button type="button" class="rw-link" data-a-owner="${esc(o.citizenid)}">
                <span class="rw-t"><b>${o.online ? '<i class="a-online"></i>' : ''}${esc(o.name || o.citizenid)}</b><span class="mono">${esc(o.citizenid)}</span></span>
                <span class="count">${o.count}</span></button>`).join('') || '<div class="rw"><div class="rw-t"><span>—</span></div></div>';

        return `${top}${kpis}
            ${section(`Sortis maintenant (${d.outCount})`, out)}
            <div class="a-grid3">
                ${section('Par type', `<div class="a-bars">${kinds}</div>`)}
                ${section('Espèces les plus adoptées', topSpecies)}
                ${section('Plus gros propriétaires', owners)}
            </div>
            ${section('Dernières actions', logRows(d.logs || []))}`;
    }

    // ── Liste ─────────────────────────────────────────────────────────────

    function filterBar() {
        const kinds = meta.kinds.map((k) => `<option value="${esc(k.key)}" ${filters.kind === k.key ? 'selected' : ''}>${esc(k.label)}</option>`).join('');
        const species = meta.species
            .filter((s) => !filters.kind || s.kind === filters.kind)
            .map((s) => `<option value="${esc(s.key)}" ${filters.species === s.key ? 'selected' : ''}>${esc(s.label)}</option>`).join('');
        const states = STATE_FILTERS.map(([k, l]) => `<option value="${k}" ${filters.state === k ? 'selected' : ''}>${l}</option>`).join('');
        return `<div class="a-filters">
            <input class="field-input" id="aSearch" placeholder="N°, nom de l'animal, propriétaire, citizenid…" value="${esc(filters.q)}">
            <select class="field-select" id="aKind"><option value="">Tous les types</option>${kinds}</select>
            <select class="field-select" id="aSpecies"><option value="">Toutes les espèces</option>${species}</select>
            <select class="field-select" id="aState">${states}</select>
            ${btn('Rechercher', 'data-a-op="search"', 'primary')}
        </div>`;
    }

    function renderPets() {
        const top = head('Animaux', 'Tous les animaux du serveur. Cliquez sur une ligne pour ouvrir sa fiche.');
        if (!list) return top + filterBar() + loading();

        const rows = list.rows.map((p) => `
            <button type="button" class="rw-link a-row" data-a-pet="${p.id}">
                ${petImg(p.species, 'a-ph')}
                <span class="rw-t"><b>${esc(p.name)} <span class="muted">#${p.id}</span></b>
                    <span>${esc(p.label)}${p.known ? '' : ' (espèce inconnue)'} · niveau ${Math.floor((p.xp || 0) / 50) + 1}</span></span>
                <span class="rw-t a-owner"><b>${p.ownerSrc ? '<i class="a-online"></i>' : ''}${esc(p.ownerName || '—')}</b><span class="mono">${esc(p.citizenid)}</span></span>
                ${mini('Santé', p.health, rules().injured ?? 15)}${mini('Satiété', p.hunger, (rules().hungry ?? 25) - 1)}
                ${stateChip(p.state)}<span class="chev">›</span>
            </button>`).join('') || '<div class="rw"><div class="rw-t"><span>Aucun animal ne correspond.</span></div></div>';

        const pager = list.pages > 1 ? `<div class="a-pager">
            ${btn('‹ Précédent', `data-a-page="${list.page - 1}" ${list.page <= 1 ? 'disabled' : ''}`)}
            <span>Page ${list.page} / ${list.pages}</span>
            ${btn('Suivant ›', `data-a-page="${list.page + 1}" ${list.page >= list.pages ? 'disabled' : ''}`)}
        </div>` : '';

        const count = `${list.total} ${list.total > 1 ? 'animaux' : 'animal'}${list.capped ? ' (résultats limités : affinez la recherche)' : ''}`;
        return top + filterBar() + section(count, rows) + pager;
    }

    // ── Fiche ─────────────────────────────────────────────────────────────

    function renderPet() {
        if (!pet) return head('Fiche', null) + loading();
        const p = pet;
        const r = rules();
        const out = p.state === 'out';

        const actions = `<div class="a-actions">
            ${btn('Soigner', 'data-a-op="quick" data-q="heal"', 'quiet', ICONS.kit)}
            ${btn('Nourrir', 'data-a-op="quick" data-q="feed"', 'quiet', ICONS.food)}
            ${out ? btn('TP', `data-a-op="teleport" data-id="${p.id}"`, 'quiet', AI.tp) : ''}
            ${out ? btn('Rentrer', `data-a-op="dismiss" data-id="${p.id}"`, 'quiet', ICONS.home) : ''}
            ${confirm === 'delete'
                ? btn('Confirmer la suppression', 'data-a-op="delete"', 'danger', AI.trash)
                : btn('Supprimer', 'data-a-ask="delete"', 'danger', AI.trash)}
        </div>`;

        const header = `<div class="pg-h pg-h-pet">
            ${petImg(p.species, 'pet-av')}
            <div class="pg-h-t"><h2>${esc(p.name)} <span class="muted">#${p.id}</span></h2>
                <p>${stateChip(p.state)} ${chip(p.label)} ${chip(kindLabel(p.kind))} ${p.hungry ? chip('Affamé', 'warn') : ''} ${p.pending ? chip('En route', 'warn') : ''} ${p.dead ? chip('Mort en jeu', 'warn') : ''}</p>
                <p>${ownerText(p.ownerName, p.citizenid)} ${p.ownerSrc ? chip(`En ligne · joueur ${p.ownerSrc}`, 'ok') : chip('Hors ligne')}</p>
            </div>
        </div>${actions}`;

        const speciesOptions = meta.kinds.map((k) => {
            const opts = meta.species.filter((s) => s.kind === k.key)
                .map((s) => `<option value="${esc(s.key)}" ${s.key === p.species ? 'selected' : ''}>${esc(s.label)}</option>`).join('');
            return opts ? `<optgroup label="${esc(k.label)}">${opts}</optgroup>` : '';
        }).join('');
        const traits = Object.entries(meta.traits || {}).sort((a, b) => a[1].localeCompare(b[1], 'fr')).map(([k, l]) =>
            `<label class="a-check"><input type="checkbox" name="aTrait" value="${esc(k)}" ${(p.traits || []).includes(k) ? 'checked' : ''}><span>${esc(l)}</span></label>`).join('');

        const edit = section('Modifier', `<div class="a-form">
                <label class="a-field"><span>Nom</span><input class="field-input" id="aName" maxlength="${r.nameMax ?? 20}" value="${esc(p.name)}"></label>
                <label class="a-field"><span>Espèce</span><select class="field-select" id="aSpeciesEdit">${speciesOptions}</select></label>
                <label class="a-field"><span>Santé (%)</span><input class="field-input" id="aHealth" type="number" min="0" max="100" value="${p.health}"></label>
                <label class="a-field"><span>Satiété (%)</span><input class="field-input" id="aHunger" type="number" min="0" max="100" value="${p.hunger}"></label>
                <label class="a-field"><span>Expérience (XP)</span><input class="field-input" id="aXp" type="number" min="0" value="${p.xp}"></label>
            </div>
            <div class="a-traits">${traits}</div>
            <div class="a-form-foot"><span class="muted">Changer l'espèce fait rentrer l'animal s'il est sorti.</span>${btn('Enregistrer', 'data-a-op="save"', 'primary')}</div>`);

        const playerOptions = players.map((pl) => `<option value="${pl.id}">[${pl.id}] ${esc(pl.charName || pl.name)} — ${esc(pl.citizenid)}</option>`).join('');
        const owner = section('Propriétaire', `
            <div class="rw"><div class="rw-t"><b>${esc(p.ownerName || 'Nom inconnu')}</b><span class="mono">${esc(p.citizenid)}</span></div>
                <div class="rw-c"><span>${p.ownerPets} ${p.ownerPets > 1 ? 'animaux' : 'animal'} / ${r.maxPets ?? 10}</span>${btn('Ses animaux', `data-a-owner="${esc(p.citizenid)}"`)}</div></div>
            <div class="rw a-transfer"><div class="rw-t"><b>Transférer</b><span>À un joueur en ligne ou à un citizenid.</span></div>
                <div class="rw-c"><select class="field-select" id="aTransferTo"><option value="">Joueur en ligne…</option>${playerOptions}</select>
                <input class="field-input" id="aTransferCid" placeholder="ou citizenid">
                ${btn('Transférer', 'data-a-op="transfer"', 'primary')}</div></div>`);

        const live = p.live ? `
            <div class="rw"><div class="rw-t"><b>Sorti par</b></div><div class="rw-c"><span>${esc(p.live.playerName || '—')} (joueur ${p.live.src})</span></div></div>
            <div class="rw"><div class="rw-t"><b>Position</b></div><div class="rw-c"><span>${esc(p.live.street || '—')}${p.live.bucket ? ` · instance ${p.live.bucket}` : ''}</span></div></div>` : '';
        const info = section('Informations', `
            <div class="rw"><div class="rw-t"><b>Origine</b></div><div class="rw-c"><span>${esc(p.origin === 'premium' ? 'Boutique premium' : p.origin === 'admin' ? 'Staff' : p.origin || '—')}</span></div></div>
            <div class="rw"><div class="rw-t"><b>Adopté le</b></div><div class="rw-c"><span>${dateFr(p.createdAt)}</span></div></div>
            <div class="rw"><div class="rw-t"><b>Modèle</b></div><div class="rw-c"><span class="mono">${esc((speciesOf(p.species) || {}).model || '—')}</span></div></div>
            ${live}`);

        return `${header}<div class="a-grid2"><div>${edit}${owner}</div><div>${info}${section('Historique', logRows(p.logs || [], true))}</div></div>`;
    }

    // ── Donner ────────────────────────────────────────────────────────────

    function speciesGrid(selected, attr) {
        return meta.kinds.map((k) => {
            const cards = meta.species.filter((s) => s.kind === k.key).map((s) => `
                <button type="button" class="a-sp ${selected === s.key ? 'is-on' : ''}" ${attr}="${esc(s.key)}">
                    ${petImg(s.key, 'a-sp-ph')}<b>${esc(s.label)}</b></button>`).join('');
            return cards ? `<div class="a-sp-group"><h5>${esc(k.label)}</h5><div class="a-sp-grid">${cards}</div></div>` : '';
        }).join('');
    }

    function renderGive() {
        const top = head('Donner un animal', 'Le joueur le retrouve dans sa tablette (/animaux). Le don est journalisé.');
        const playerOptions = players.map((pl) => `<option value="${pl.id}" ${String(give.target) === String(pl.id) ? 'selected' : ''}>[${pl.id}] ${esc(pl.charName || pl.name)} — ${esc(pl.citizenid)}</option>`).join('');
        const sp = speciesOf(give.species);
        const form = section('Destinataire', `<div class="a-form">
                <label class="a-field"><span>Joueur en ligne</span><select class="field-select" id="aGiveTarget"><option value="">Choisir…</option>${playerOptions}</select></label>
                <label class="a-field"><span>ou citizenid (hors ligne)</span><input class="field-input" id="aGiveCid" value="${esc(give.citizenid)}" placeholder="ABC12345"></label>
                <label class="a-field"><span>Nom (facultatif)</span><input class="field-input" id="aGiveName" maxlength="${rules().nameMax ?? 20}" value="${esc(give.name)}" placeholder="${esc(sp ? sp.label : 'Nom de l\'espèce')}"></label>
            </div>
            <div class="a-form-foot">
                <label class="a-check"><input type="checkbox" id="aGiveForce" ${give.ignoreLimit ? 'checked' : ''}><span>Dépasser la limite de ${rules().maxPets ?? 10} animaux</span></label>
                ${btn(sp ? `Donner : ${sp.label}` : 'Choisissez une espèce', `data-a-op="give" ${sp ? '' : 'disabled'}`, 'primary')}
            </div>`);
        return top + form + `<div class="sx"><h4>Espèce</h4>${speciesGrid(give.species, 'data-a-give')}</div>`;
    }

    // ── Especes ───────────────────────────────────────────────────────────

    function renderSpecies() {
        const counts = (dash && dash.bySpecies) || {};
        const groups = meta.kinds.map((k) => {
            const cards = meta.species.filter((s) => s.kind === k.key).map((s) => `
                <div class="a-card">
                    ${petImg(s.key, 'a-card-ph')}
                    <div class="a-card-body">
                        <div class="a-card-title"><b>${esc(s.label)}</b><span class="count">${counts[s.key] || 0}</span></div>
                        <span class="mono muted">${esc(s.key)} · ${esc(s.model)}</span>
                        <div class="chips a-chips">${(s.tricks.length ? s.tricks : ['Aucun tour']).map((t) => chip(t)).join('')}</div>
                        <span class="muted">Véhicule : ${esc(s.vehicle)} · faim ${s.hungerPerMinute} %/min</span>
                        <div class="a-card-actions">${btn('Voir les animaux', `data-a-species="${esc(s.key)}"`)}${btn('Donner', `data-a-givesp="${esc(s.key)}"`, 'primary')}</div>
                    </div>
                </div>`).join('');
            return cards ? `<div class="sx"><h4>${esc(k.label)}</h4><div class="a-cards">${cards}</div></div>` : '';
        }).join('');
        return head('Espèces', `${meta.species.length} espèces disponibles (config.lua). Le chiffre est le nombre d'animaux adoptés.`) + groups;
    }

    // ── Journal ───────────────────────────────────────────────────────────

    function logDetails(l) {
        const d = l.details || {};
        if (l.action === 'update' && d.after) {
            return Object.keys(d.after).map((k) => {
                const fmt = (v) => (k === 'species' ? speciesLabel(v) : Array.isArray(v) ? v.map((t) => (meta.traits || {})[t] || t).join(', ') : v);
                return `${FIELD_LABELS[k] || k} : ${fmt((d.before || {})[k])} → ${fmt(d.after[k])}`;
            }).join(' · ');
        }
        if (l.action === 'grant') return `${speciesLabel(d.species)}${d.name ? ` « ${d.name} »` : ''} (${d.source || '—'})`;
        if (l.action === 'delete') return `${d.name || ''} (${speciesLabel(d.species)})`;
        if (l.action === 'transfer') return `${d.from} → ${d.to}`;
        if (l.action === 'dismiss_all') return `${d.count} animal(aux)`;
        return '';
    }

    function logRows(rows, compact) {
        if (!rows.length) return '<div class="rw"><div class="rw-t"><span>Aucune entrée.</span></div></div>';
        return rows.map((l) => `
            <div class="rw a-log">
                <span class="a-log-date mono">${dateTime(l.created_at)}</span>
                <span class="a-log-act">${chip(ACTIONS[l.action] || l.action)}</span>
                <div class="rw-t"><b>${esc(l.actor_name || l.actor)}</b><span>${esc(logDetails(l))}</span></div>
                ${!compact && l.pet_id ? btn(`#${l.pet_id}`, `data-a-pet="${l.pet_id}"`) : ''}
            </div>`).join('');
    }

    function renderLogs() {
        return head('Journal', 'Adoptions et actions du staff, les plus récentes en premier.', `<div class="a-actions">${btn('Actualiser', 'data-a-op="logs"', 'quiet', AI.refresh)}</div>`)
            + section(null, logRows(logs));
    }

    // ── Chargements ───────────────────────────────────────────────────────

    async function loadDash() {
        const d = await call('overview');
        if (d) dash = d;
        if (page === 'dash' && isMine()) render();
    }

    async function loadList() {
        list = null;
        render();
        list = await call('search', filters) || { rows: [], total: 0, page: 1, pages: 1 };
        filters.page = list.page;
        if (page === 'pets') render();
    }

    async function loadPet(id) {
        page = 'pet';
        pet = null;
        confirm = null;
        render();
        const [p, pl] = await Promise.all([call('pet', { id }), call('players')]);
        if (pl) players = pl;
        if (!p) { page = 'pets'; return render(); }
        pet = p;
        if (page === 'pet') render();
    }

    async function go(next) {
        page = next;
        confirm = null;
        clearInterval(refreshTimer);
        render();
        if (next === 'dash') {
            loadDash();
            // Le tableau se rafraichit seul tant qu'il est affiche.
            refreshTimer = setInterval(() => { if (page === 'dash' && isMine()) loadDash(); }, 10000);
        } else if (next === 'pets') {
            loadList();
        } else if (next === 'give') {
            players = await call('players') || players;
            if (page === 'give') render();
        } else if (next === 'species') {
            if (!dash) await loadDash();
            if (page === 'species') render();
        } else if (next === 'logs') {
            logs = await call('logs') || [];
            if (page === 'logs') render();
        }
    }

    function readFilters() {
        if ($('aSearch')) filters.q = $('aSearch').value.trim();
        if ($('aKind')) filters.kind = $('aKind').value;
        if ($('aSpecies')) filters.species = $('aSpecies').value;
        if ($('aState')) filters.state = $('aState').value;
    }

    function readGive() {
        if ($('aGiveTarget')) give.target = $('aGiveTarget').value;
        if ($('aGiveCid')) give.citizenid = $('aGiveCid').value.trim();
        if ($('aGiveName')) give.name = $('aGiveName').value.trim();
        if ($('aGiveForce')) give.ignoreLimit = $('aGiveForce').checked;
    }

    // ── Gestes ────────────────────────────────────────────────────────────

    async function run(op, el) {
        if (busy) return;
        const id = el && el.dataset.id ? Number(el.dataset.id) : (pet && pet.id);
        let data = null;
        busy = true;
        $('view').classList.add('busy');
        try {
            if (op === 'refresh') {
                await loadDash();
            } else if (op === 'search') {
                readFilters();
                filters.page = 1;
                await loadList();
            } else if (op === 'dismiss' || op === 'teleport') {
                data = await call(op, { id });
                if (data) toast(op === 'dismiss' ? 'Animal rentré.' : 'Téléporté.');
                if (data && op === 'teleport') post('adminClose');
            } else if (op === 'dismissAll') {
                confirm = null;
                data = await call('dismissAll');
                if (data) toast(`${data.count} animal(aux) rentré(s).`);
            } else if (op === 'quick') {
                const q = el.dataset.q;
                data = await call('update', q === 'heal' ? { id, health: 100 } : { id, hunger: 100 });
                if (data) toast(data.unchanged ? 'Déjà au maximum.' : (q === 'heal' ? 'Soigné.' : 'Nourri.'));
            } else if (op === 'save') {
                const traits = [...document.querySelectorAll('input[name="aTrait"]:checked')].map((c) => c.value);
                data = await call('update', {
                    id,
                    name: $('aName').value.trim(),
                    species: $('aSpeciesEdit').value,
                    health: Number($('aHealth').value),
                    hunger: Number($('aHunger').value),
                    xp: Number($('aXp').value),
                    traits,
                });
                if (data) toast(data.unchanged ? 'Aucun changement.' : 'Enregistré.');
            } else if (op === 'transfer') {
                const target = $('aTransferTo').value;
                const citizenid = $('aTransferCid').value.trim();
                if (!target && !citizenid) { toast('Choisissez un joueur ou un citizenid.', true); return; }
                data = await call('transfer', target ? { id, target: Number(target) } : { id, citizenid });
                if (data) toast(`Transféré à ${data.citizenid}.`);
            } else if (op === 'delete') {
                confirm = null;
                data = await call('delete', { id });
                if (data) { toast('Animal supprimé.'); pet = null; busy = false; return go('pets'); }
            } else if (op === 'give') {
                readGive();
                if (!give.target && !give.citizenid) { toast('Choisissez un joueur ou un citizenid.', true); return; }
                data = await call('give', {
                    species: give.species,
                    name: give.name || null,
                    ignoreLimit: give.ignoreLimit,
                    ...(give.target ? { target: Number(give.target) } : { citizenid: give.citizenid }),
                });
                if (data) {
                    toast(`Animal n°${data.id} donné.`);
                    give.name = '';
                    busy = false;
                    return loadPet(data.id);
                }
            } else if (op === 'logs') {
                logs = await call('logs') || logs;
            }
        } finally {
            busy = false;
            const v = $('view');
            if (v) v.classList.remove('busy');
        }

        // Etat a jour apres un geste qui a reussi.
        if (data) {
            if (page === 'pet' && pet) return loadPet(pet.id);
            if (page === 'dash') return loadDash();
        }
        if (isMine()) render();
    }

    document.addEventListener('click', (e) => {
        if (!isMine()) return;
        const t = e.target;
        const el = (sel) => t.closest(sel);
        let x;
        if (el('[data-a-close]')) return post('adminClose');
        if ((x = el('[data-a-nav]'))) return go(x.dataset.aNav);
        if ((x = el('[data-a-pet]'))) return loadPet(Number(x.dataset.aPet));
        if ((x = el('[data-a-page]')) && !x.disabled) { filters.page = Number(x.dataset.aPage); return loadList(); }
        if ((x = el('[data-a-species]'))) { filters = { q: '', kind: '', species: x.dataset.aSpecies, state: '', page: 1 }; return go('pets'); }
        if ((x = el('[data-a-kind]'))) { filters = { q: '', kind: x.dataset.aKind, species: '', state: '', page: 1 }; return go('pets'); }
        if ((x = el('[data-a-owner]'))) { filters = { q: x.dataset.aOwner, kind: '', species: '', state: '', page: 1 }; return go('pets'); }
        if ((x = el('[data-a-givesp]'))) { give.species = x.dataset.aGivesp; return go('give'); }
        if ((x = el('[data-a-give]'))) { readGive(); give.species = x.dataset.aGive; return render(); }
        if ((x = el('[data-a-ask]'))) { confirm = x.dataset.aAsk; return render(); }
        if ((x = el('[data-a-op]')) && !x.disabled) return run(x.dataset.aOp, x);
    });

    document.addEventListener('change', (e) => {
        if (!isMine()) return;
        // Le type restreint la liste des especes : on la redessine.
        if (e.target.id === 'aKind') { readFilters(); filters.species = ''; render(); }
    });

    document.addEventListener('keydown', (e) => {
        if (!isMine()) return;
        if (e.key === 'Escape') {
            if (confirm) { confirm = null; return render(); }
            return post('adminClose');
        }
        if (e.key === 'Enter' && document.activeElement && document.activeElement.id === 'aSearch') run('search');
    });

    window.addEventListener('message', (e) => {
        const msg = e.data || {};
        if (msg.action === 'adminOpen') {
            meta = msg.meta || meta;
            document.body.dataset.mode = 'admin';
            document.body.hidden = false;
            tickClock();
            clearInterval(clockTimer);
            clockTimer = setInterval(tickClock, 15000);
            go('dash');
        } else if (msg.action === 'open' || msg.action === 'close') {
            // La tablette joueur prend la page, ou tout se ferme.
            clearInterval(refreshTimer);
            clearInterval(clockTimer);
            confirm = null;
        }
    });
})();
