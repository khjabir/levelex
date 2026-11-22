// Levelex website: navigation, install tabs, release links and the 3D guide.
// No tracking. The only outside request is GitHub's public API, to show the
// latest release's version and file sizes.

(() => {
  'use strict';

  const REPO = 'khjabir/levelex';
  const RELEASES = `https://github.com/${REPO}/releases`;

  // File names every release publishes (tool/release/build_release.sh).
  const ASSETS = {
    arm64: 'levelex-android-arm64.apk',
    armv7: 'levelex-android-armv7.apk',
    universal: 'levelex-android-universal.apk',
    ios: 'levelex-ios-unsigned.ipa',
    sums: 'SHA256SUMS.txt',
  };

  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => [...root.querySelectorAll(s)];

  // ---- Footer year --------------------------------------------------------
  $$('[data-year]').forEach((el) => (el.textContent = String(new Date().getFullYear())));

  // ---- Mobile navigation ----------------------------------------------------
  const toggle = $('.nav__toggle');
  const links = $('#nav-links');
  if (toggle && links) {
    const close = () => {
      links.classList.remove('is-open');
      toggle.setAttribute('aria-expanded', 'false');
    };
    toggle.addEventListener('click', () => {
      const open = links.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', String(open));
    });
    links.addEventListener('click', (e) => {
      if (e.target.closest('a')) close();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') close();
    });
  }

  // ---- Install tabs ---------------------------------------------------------
  const tabs = $$('[role="tab"]');
  const selectTab = (tab, focus = false) => {
    tabs.forEach((t) => {
      const selected = t === tab;
      t.setAttribute('aria-selected', String(selected));
      t.tabIndex = selected ? 0 : -1;
      const panel = document.getElementById(t.getAttribute('aria-controls'));
      if (panel) panel.hidden = !selected;
    });
    if (focus) tab.focus();
  };
  const tabFor = (panelId) => tabs.find((t) => t.getAttribute('aria-controls') === panelId);

  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', (e) => {
      const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (e.key === 'Home') selectTab(tabs[0], true);
      else if (e.key === 'End') selectTab(tabs[tabs.length - 1], true);
      else if (step) selectTab(tabs[(i + step + tabs.length) % tabs.length], true);
      else return;
      e.preventDefault();
    });
  });

  // Links to a platform's panel (hero buttons, #install-ios in the address).
  const openPanel = (id) => {
    const tab = tabFor(id);
    if (tab) selectTab(tab);
  };
  $$('a[href^="#install-"]').forEach((a) =>
    a.addEventListener('click', () => openPanel(a.getAttribute('href').slice(1))),
  );
  window.addEventListener('hashchange', () => {
    if (location.hash.startsWith('#install-')) openPanel(location.hash.slice(1));
  });
  if (location.hash.startsWith('#install-')) {
    openPanel(location.hash.slice(1));
  } else {
    // Start on the visitor's own platform.
    const ua = navigator.userAgent;
    const iOS = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
    if (iOS) openPanel('install-ios');
  }

  // ---- Copy buttons on code blocks ------------------------------------------
  $$('pre[data-copy]').forEach((pre) => {
    if (!navigator.clipboard) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy';
    button.textContent = 'Copy';
    button.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(pre.innerText.replace(/\nCopy$/, '').trim());
        button.textContent = 'Copied';
      } catch {
        button.textContent = 'Press Ctrl+C';
      }
      setTimeout(() => (button.textContent = 'Copy'), 1600);
    });
    pre.append(button);
  });

  // ---- Latest release ---------------------------------------------------------
  const megabytes = (bytes) => `${Math.round(bytes / 1e6)} MB`;

  const applyRelease = (release) => {
    const date = new Date(release.published_at).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
    $$('[data-release-version]').forEach((el) => (el.textContent = `${release.tag_name}, ${date}`));
    for (const [key, name] of Object.entries(ASSETS)) {
      const asset = (release.assets || []).find((a) => a.name === name);
      $$(`[data-asset="${key}"]`).forEach((el) => {
        if (asset) {
          el.href = asset.browser_download_url;
        } else {
          // Not in this release: send people to the release page instead.
          el.href = release.html_url;
          el.title = 'Not included in this release';
        }
      });
      $$(`[data-asset-size="${key}"]`).forEach((el) => (el.textContent = asset ? `· ${megabytes(asset.size)}` : ''));
    }
  };

  const noRelease = () => {
    $$('[data-release-version]').forEach((el) => (el.textContent = 'first release coming soon'));
    const note = $('#no-release');
    if (note) note.hidden = false;
    $$('[data-asset]').forEach((el) => {
      el.href = RELEASES;
      el.classList.add('is-unavailable');
    });
  };

  // The release list (not /releases/latest, which answers 404 until the
  // first release); the newest full release is what GitHub's
  // releases/latest/download links point at.
  fetch(`https://api.github.com/repos/${REPO}/releases?per_page=10`, {
    headers: { Accept: 'application/vnd.github+json' },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((list) => list.find((r) => !r.draft && !r.prerelease))
    .then((release) => (release ? applyRelease(release) : noRelease()))
    .catch(() => {
      // Offline or rate-limited: the static "latest release" links still work.
    });

  // ---- 3D guide -----------------------------------------------------------------
  const viewer = $('#athlete');
  const chips = $$('#clip-chips [data-clip]');
  if (!viewer || !chips.length) return;

  // Muscles each clip trains (as in the app's movement library), and a
  // camera that frames the whole movement: the target is the centre of the
  // space the body sweeps through, the distance fits it, and floor moves
  // (which lie along the z axis) are seen more from the side.
  const SIDE = 64;
  const FRONT = 26;
  const CLIPS = {
    push_up: { primary: ['chest', 'triceps'], secondary: ['shoulders', 'core'], target: '0m 0.46m 0.04m', theta: SIDE, distance: 5.2 },
    squat: { primary: ['quads', 'glutes'], secondary: ['hamstrings', 'core'], target: '0m 0.9m 0.07m', theta: FRONT + 14, distance: 5.4 },
    burpee: { primary: ['cardio', 'chest'], secondary: ['quads', 'core', 'shoulders'], target: '0m 1.15m -0.06m', theta: SIDE, distance: 7.5 },
    jumping_jack: { primary: ['cardio'], secondary: ['shoulders', 'calves'], target: '-0.08m 1.1m -0.31m', theta: FRONT, distance: 6.4 },
    lunge: { primary: ['quads', 'glutes'], secondary: ['hamstrings', 'core'], target: '0m 0.9m -0.28m', theta: SIDE, distance: 5.8 },
    mountain_climbers: { primary: ['core', 'cardio'], secondary: ['shoulders', 'quads'], target: '0m 0.42m 0.03m', theta: SIDE, distance: 5.1 },
    sit_up: { primary: ['core'], secondary: [], target: '0m 0.42m -0.18m', theta: SIDE, distance: 4.6 },
    glute_bridge: { primary: ['glutes'], secondary: ['hamstrings', 'core'], target: '0m 0.3m 0m', theta: SIDE, distance: 4.8 },
    high_knees: { primary: ['cardio'], secondary: ['quads', 'core'], target: '0m 0.95m -0.02m', theta: FRONT + 20, distance: 5.2 },
    dip: { primary: ['triceps'], secondary: ['chest', 'shoulders'], target: '0m 0.7m -0.1m', theta: SIDE, distance: 4.9 },
    squat_jump: { primary: ['quads', 'glutes', 'cardio'], secondary: ['calves'], target: '0m 1.2m 0.18m', theta: FRONT + 14, distance: 7.0 },
    plank: { primary: ['core'], secondary: ['shoulders'], target: '0m 0.26m 0.05m', theta: SIDE, distance: 5.2 },
    wall_sit: { primary: ['quads'], secondary: ['glutes'], target: '0m 0.66m -0.09m', theta: SIDE, distance: 4.5 },
  };

  // Materials of the body that belong to each muscle group.
  const MATERIALS = {
    chest: ['shirt.chest'],
    back: ['shirt.back'],
    core: ['shirt.core'],
    shoulders: ['shirt.shoulders'],
    glutes: ['shorts.glutes'],
    quads: ['quads', 'shorts.quads'],
    hamstrings: ['hamstrings', 'shorts.hamstrings'],
    biceps: ['biceps'],
    triceps: ['triceps'],
    calves: ['calves'],
  };

  const listOf = (names) => names.join(', ');

  // The brand green in linear RGB, as glTF colour factors are.
  const GREEN = [0.041, 1.0, 0.246, 1];
  const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

  const original = new Map();
  let materialsReady = false;

  const paint = (clip) => {
    if (!materialsReady) return;
    const spec = CLIPS[clip];
    // Cardio drills light their helpers fully: those are the muscles working.
    const cardio = spec.primary.includes('cardio');
    const strong = new Set(spec.primary.concat(cardio ? spec.secondary : []));
    const soft = new Set(cardio ? [] : spec.secondary);
    for (const [group, names] of Object.entries(MATERIALS)) {
      for (const name of names) {
        const material = viewer.model.materials.find((m) => m.name === name);
        const base = original.get(name);
        if (!material || !base) continue;
        const colour = strong.has(group) ? GREEN : soft.has(group) ? mix(base, GREEN, 0.45) : base;
        material.pbrMetallicRoughness.setBaseColorFactor(colour);
      }
    }
  };

  const describe = (clip) => {
    const spec = CLIPS[clip];
    const cardio = spec.primary.includes('cardio');
    const primary = $('#muscles-primary');
    const secondary = $('#muscles-secondary');
    if (primary) primary.textContent = listOf(cardio ? spec.primary.concat(spec.secondary) : spec.primary);
    const helpers = cardio ? [] : spec.secondary;
    if (secondary) secondary.textContent = listOf(helpers);
    const legend = $('#legend-secondary');
    if (legend) legend.hidden = helpers.length === 0;
  };

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const show = (clip) => {
    chips.forEach((c) => {
      const on = c.dataset.clip === clip;
      c.setAttribute('aria-checked', String(on));
      c.tabIndex = on ? 0 : -1;
    });
    const spec = CLIPS[clip];
    viewer.animationName = clip;
    viewer.cameraTarget = spec.target;
    // The field of view is vertical: on a stage taller than it is wide
    // (phones), step back so a body lying along the floor still fits.
    const box = viewer.getBoundingClientRect();
    const fit = box.height > 0 ? Math.max(1, box.height / box.width) : 1;
    viewer.cameraOrbit = `${spec.theta}deg 74deg ${(spec.distance * fit).toFixed(2)}m`;
    viewer.play({ repetitions: Infinity });
    paint(clip);
    describe(clip);
  };

  viewer.addEventListener('load', () => {
    viewer.setAttribute('data-loaded', '');
    for (const names of Object.values(MATERIALS)) {
      for (const name of names) {
        const m = viewer.model.materials.find((x) => x.name === name);
        if (m) original.set(name, [...m.pbrMetallicRoughness.baseColorFactor]);
      }
    }
    materialsReady = true;
    const current = chips.find((c) => c.getAttribute('aria-checked') === 'true');
    show(current ? current.dataset.clip : 'push_up');
    viewer.jumpCameraToGoal();
    if (reduceMotion) viewer.pause();
  });

  chips.forEach((chip, i) => {
    chip.addEventListener('click', () => show(chip.dataset.clip));
    chip.addEventListener('keydown', (e) => {
      const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
      if (!step) return;
      e.preventDefault();
      const next = chips[(i + step + chips.length) % chips.length];
      next.focus();
      show(next.dataset.clip);
    });
  });
  chips.forEach((c) => (c.tabIndex = c.getAttribute('aria-checked') === 'true' ? 0 : -1));
})();
