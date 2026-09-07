// Flavour and accent picker. The page is themed with the same tokens the app
// uses, so this is a demonstration of the product rather than site chrome.
(function () {
  const FLAVORS = [
    ['latte', 'Latte'],
    ['frappe', 'Frappé'],
    ['macchiato', 'Macchiato'],
    ['mocha', 'Mocha'],
  ];

  const ACCENTS = ['rosewater','flamingo','pink','mauve','red','maroon','peach',
                   'yellow','green','teal','sky','sapphire','blue','lavender'];

  const root = document.documentElement;
  const store = {
    get(k, fallback) {
      try { return localStorage.getItem(k) || fallback; } catch { return fallback; }
    },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
  };

  // Someone arriving in light mode should not be hit with a dark page.
  const prefersLight = window.matchMedia('(prefers-color-scheme: light)').matches;
  let flavor = store.get('flavor', prefersLight ? 'latte' : 'mocha');
  let accent = store.get('accent', 'sapphire');

  function apply() {
    root.dataset.flavor = flavor;
    root.dataset.accent = accent;

    // The header icon follows the accent, so the page shows the app icon the
    // reader is closest to picking. Six icons against fourteen accents, so
    // this maps to the nearest by hue rather than pretending to be exact.
    const ICON_FOR_ACCENT = {
      rosewater: 'coral', flamingo: 'coral', pink: 'lavender', mauve: 'lavender',
      red: 'coral', maroon: 'coral', peach: 'amber', yellow: 'amber',
      green: 'mint', teal: 'mint', sky: 'ocean', sapphire: 'ocean',
      blue: 'ocean', lavender: 'lavender',
    };
    const icon = document.getElementById('mark-icon');
    if (icon) {
      const name = ICON_FOR_ACCENT[accent] || 'coral';
      icon.src = 'icons/' + name + '.png';
    }
    for (const b of flavorButtons) b.setAttribute('aria-pressed', String(b.dataset.flavor === flavor));
    for (const b of accentButtons) b.setAttribute('aria-pressed', String(b.dataset.accent === accent));
  }

  const flavorHost = document.getElementById('flavors');
  const flavorButtons = FLAVORS.map(([id, label]) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.dataset.flavor = id;
    b.textContent = label;
    b.addEventListener('click', () => { flavor = id; store.set('flavor', id); apply(); });
    flavorHost.append(b);
    return b;
  });

  const accentHost = document.getElementById('accents');
  const accentButtons = ACCENTS.map((id) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.dataset.accent = id;
    b.style.setProperty('--swatch', `var(--${id})`);
    b.setAttribute('aria-label', id);
    b.addEventListener('click', () => { accent = id; store.set('accent', id); apply(); });
    accentHost.append(b);
    return b;
  });

  apply();
})();
