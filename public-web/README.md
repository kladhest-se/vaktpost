# public-web

The project site. Plain HTML, CSS and one small script — no build step, no
dependencies, no fonts or analytics loaded from anywhere else. Serve the
directory as-is.

```sh
python3 -m http.server -d public-web 8000
```

For GitHub Pages, point the Pages source at this directory on your default
branch. Nothing else is needed.

## Before publishing

- Add the canonical public repository URL when it has been chosen. The current
  page contains no placeholder or dead source link.
- Add an `og:image` when a public release image is available.
- The device rendering in the hero is built from the same design tokens as
  the app. It is a rendering, not a product screenshot.
- Keep the version 0.1 feature and deferred-scope lists aligned with the root
  `README.md` before publishing.

## Theming

`styles.css` carries all four Catppuccin flavours as custom-property sets
selected by `:root[data-flavor]`, and all fourteen accents by
`:root[data-accent]`. `theme.js` sets those attributes and remembers the
choice in `localStorage`, defaulting to Latte for visitors whose system is in
light mode and Mocha otherwise.

Because the whole page reads from those variables, adding a flavour means
adding one block to the top of the stylesheet and one entry to the `FLAVORS`
array — nothing else changes.
