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

- Replace the two `href="#"` placeholders in `index.html` with the real
  repository URL (the header link and the "Source on GitHub" button).
- Add an `og:image` if you want link previews; there is none yet because
  there are no screenshots.
- The device rendering in the hero is built from the same design tokens as
  the app — it is a rendering, not a screenshot. Swap it for real captures
  once the app has run on a device you can screenshot.

## Theming

`styles.css` carries all four Catppuccin flavours as custom-property sets
selected by `:root[data-flavor]`, and all fourteen accents by
`:root[data-accent]`. `theme.js` sets those attributes and remembers the
choice in `localStorage`, defaulting to Latte for visitors whose system is in
light mode and Mocha otherwise.

Because the whole page reads from those variables, adding a flavour means
adding one block to the top of the stylesheet and one entry to the `FLAVORS`
array — nothing else changes.
