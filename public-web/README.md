# public-web

The project site. One small PHP entry point, CSS, and one browser script — no
build step, framework, database, fonts, analytics, or third-party runtime
assets.

```sh
php -S 127.0.0.1:8000 -t public-web
```

For production, point a PHP-capable web server's document root at
`public-web/`. GitHub Pages cannot run the PHP entry point.

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
