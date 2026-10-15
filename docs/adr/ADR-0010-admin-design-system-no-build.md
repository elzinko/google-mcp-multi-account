# ADR-0010 — A design system for the admin, with no framework and no build

**TL;DR.** The admin builds its HTML by gluing text strings together, with no
"component" layer and no spacing/typography scale. To turn it into a system without betraying the
"zero dependency / 100% local" constraint, we lay four building blocks, from the bottom
up: (1) **CSS tokens** for scales, (2) an ``html`` `` function that **escapes by
default** plus a thin set of vanilla **component functions**, (3) a **micro-router**
that formalizes views, (4) a reusable **list/thumbnails toggle**. We roll out
screen by screen, pilot = the Sessions page.

Status: **proposed** (2026-08-30). Visual specs live in
`docs/design/design-system-admin.md`; this ADR carries the structure.

## Context

The entire front end fits in `admin/index.html` (~1960 lines: `<style>`, HTML, vanilla JS).
Rendering goes through `render*()` functions that **concatenate strings** set as
`innerHTML`. A strong project constraint: no bundler, no front-end npm, everything
local. Colors are already CSS variables (light/dark); the rest (spacing,
typography, radii) is hard-coded and drifts.

Five structural facts make a "pro" polish pass painful:

1. **Rendering by concatenation** → manual escaping (`esc()`, `attr()`), to be recalled at
   every sheet; one miss = injection.
2. **No component layer**: the same chip / badge / avatar is rewritten in 4
   functions. Only two helpers (`lockChip`, `portChip`) are extracted — proof
   that the pattern is useful, and that it is missing everywhere else.
3. **No scale token**: 13 font sizes, ~10 radii, ad hoc paddings.
   No single "button" to turn to tighten the visual rhythm.
4. **View mixed with rendering**: `VIEW` is reassigned *inside* the `render*()` functions. Rendering has the
   side effect of navigating. Sessions is already a hand-coded exception (early-return,
   dedicated timer and diff).
5. **Nested modals** → resume flags (`zonesResumePolicy`…) to reopen the parent
   modal.

The padlock countdown already patches `textContent` in place instead of re-rendering, so as
not to destroy the DOM: the team knows that re-rendering breaks focus/scroll and hand-codes
the exception.

## Decision

Four building blocks, dependencies pointing downward (a page depends on components and
tokens; never the reverse).

1. **CSS scale tokens.** Extend `:root`: `--sp-*`, `--fs-*`, `--r-*`, `--fw-*`,
   `--elev-*`. Theme-neutral → the dark block redefines **only** colors.

2. **``html`` `` + component functions.** A *tagged template* (~15 lines) that escapes
   every interpolation by default, with an explicit marker for fragments that are already
   safe. It eliminates the "I forgot `esc()`" class of bug. On top of it, a `ui.*` module of
   **pure string→string** functions (`chip`, `badge`, `card`, `avatar`,
   `iconBtn`, `pageHeader`) — hence testable under `node`, without jsdom.

3. **Micro-router.** Extract `go(mode, params)` which sets `VIEW`, calls `syncChrome`,
   and dispatches to the right `render*`. The `render*` functions stop mutating `VIEW`. A per-route poll
   registry replaces the three ad hoc loops. Rule: *a surface is a **page**
   if it has its own data flow / refresh cadence; otherwise it is a
   **modal**.* Pages = list, detail, sessions, and **Setup** (candidate for promotion).

4. **List/thumbnails toggle.** A *page* concern, not an item concern: `VIEW.layout`
   persisted in `localStorage`, the page chooses between `accountRow()` and `accountCard()`
   over the same view-model. Wired into the page header, not into the item renderer.

Sequence: foundations (tokens) → component layer → screen by screen, pilot = Sessions.

## Options considered

- **Native Web Components (`customElements`) for everything** — *rejected for now*. Real
  encapsulation and surgical updates, but an oversized paradigm shift
  for a single-dev POC. **Reserved** for the 2 widgets truly penalized by re-rendering
  (countdown padlock, session card) *if* the pain persists after P1.
- **`<template>` + `cloneNode`** — *rejected*. Automatic escaping via `textContent`, but verbose
  imperative filling that composes poorly for lists/variants and clashes with the
  "innerHTML replaced wholesale" model.
- **Micro-framework via CDN (lit-html, Alpine, Preact)** — *rejected*. Directly violates
  "zero dependency / no front-end npm".

## Consequences

- **+** A single place for the visual rhythm: the "pro" pass becomes an edit of
  variables.
- **+** Escaping stops being a diffuse risk (``html`` `` by default).
- **+** Screen-by-screen migration, no big bang; each slice shippable on its own.
- **−** Bootstrap cost (tokens + helpers) before any visible gain.
- **−** Discipline to maintain: no color/spacing outside a token. Safeguard: grep in
  review.

**Risks & safeguards.** Dark theme: invariant "the dark block redefines only colors".
Reduced-motion: do not animate in JS. `<dialog>` focus: a small modal-stack
manager removes the resume flags. **No layout shift** (the
real danger): before a full re-render, capture/restore `document.activeElement` and
do not re-render while a modal is open above the list. Tests: the front end
is **not** covered (`scripts/test.sh` tests the API only); a light safety net = run the
pure functions (including ``html`` `` and `ui.*`) under `node` in `test.sh`, with an
injection test `"><script>`. Playwright deferred (adds a browser, oversized).
