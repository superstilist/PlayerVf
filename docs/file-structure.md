# PlayerVF Web File Structure

This site deploys as plain static HTML/CSS. The wiki page has a small optional build step that converts PlayerVFDoc source files into `wiki.html`.

```text
playervf-web/
  index.html
  wiki.html
  assets/
    css/
      base.css
      downloads.css
      wiki.css
  content/
    repo-stats.json
    wiki.playervfdoc
    wiki/
      *.playervfpart
  scripts/
    build-wiki.mjs
  docs/
    file-structure.md
```

## Pages

- `index.html`: public download landing page.
- `wiki.html`: full documentation/wiki page.

## CSS

- `assets/css/base.css`: shared theme, layout shell, navigation, buttons, panels, footer, focus states.
- `assets/css/downloads.css`: download landing page layout and cards.
- `assets/css/wiki.css`: wiki page layout, table of contents, documentation cards, function index.

## Content source files

- `content/repo-stats.json`: structured repository statistics, including GitHub language byte percentages and local/site character counts.
- `content/wiki.playervfdoc`: custom wiki manifest used to generate the HTML wiki.
- `content/wiki/*.playervfpart`: section partial files included by the manifest.

## PlayerVFDoc format

`content/wiki.playervfdoc` is a small custom text format:

```text
@format PlayerVFDoc/1
@title Page title
@source path-or-url
@include wiki/overview.playervfpart

::section id "Title"
Section text or key/value lines.

::files
path => description

::photo assets/img/wiki/screenshot.png "Alt text" "Optional caption"
```

Run `node scripts/build-wiki.mjs` after editing the wiki manifest or partials. The generated `wiki.html` is the file GitHub Pages serves.
