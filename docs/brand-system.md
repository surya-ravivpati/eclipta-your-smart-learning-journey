# Eclipta brand system

Single source of truth for type and the logo lockup. If you're adding a
surface, reference these roles — never re-declare a font stack or
reassemble the logo by hand.

## Color spine

Canonical primitives live in `src/styles.css` `:root` as `--brand-*`
(bg, ink, dim, fog, line, line-2, flash, accent, accent-base). Cinematic
scopes (`.cf`, `.ab`, `.btt`, Progress, Trophy Road) alias these — change
the brand once, it propagates everywhere.

- `--brand-bg` `#04050a` — the one Eclipta black.
- `--brand-accent` `oklch(0.82 0.12 235)` — cinematic azure (large display).
- `--brand-accent-base` `oklch(0.58 0.17 252)` — app interactive accent
  (also `--primary`/`--accent`/`--ring`). `--neon-purple` is a deprecated
  alias of `--accent`; prefer the `accent`/`primary` Tailwind colors.
- Pink / cyan / gold are **functional** cues (you-vs-foe, glows), not brand
  chrome — keep them scoped to battles/effects.
- `--tier-diamond` sits at hue ~215 (icy), deliberately off the 235–252
  brand-blue band so "Diamond" rank ≠ brand accent.

## Type roles

One signature, each supporting role assigned by purpose. Defined once in
`src/styles.css` `@theme` (so they also emit `font-*` utilities) and
referenced by every scope.

| Token | Utility | Face | Role |
|-------|---------|------|------|
| `--font-display` | `font-display` | **RobotHeroes** → Space Grotesk | Signature: brand & app headings |
| `--font-cinematic` | `font-cinematic` | **Archivo** (webfont) | Editorial hero / long-form display (landing, About, Compass, Luna session, Progress/Trophy body) |
| `--font-serif` | `font-serif` | **Instrument Serif** *italic* | Emotional accent / emphasis |
| `--font-shout` | `font-shout` | **Bebas Neue** | Condensed stat / big-number shout (battle HUD, Progress, Trophy Road, Luna name) |
| `--font-body` | `font-body` | **Inter** | Body copy |
| `--font-mono` | `font-mono` | **JetBrains Mono** | Labels, numerics, the wordmark |

Why two display faces: RobotHeroes is a small, decorative, limited-glyph
`.ttf` — perfect as a punchy signature, wrong for long cinematic copy.
Archivo is webfont-loaded so the heroes render the same off-Mac (the old
`Helvetica Neue` literal was a system-only font that fell back to Arial).

**Rule:** the same *role* must never drift between faces across surfaces.
If a new scope needs a heading, it uses `--font-display`/`font-display` —
not a fresh font stack.

## Logo lockup

Use `<BrandLockup>` (`src/components/BrandLockup.tsx`) — the only
sanctioned way to render the mark + wordmark.

- **Wordmark face:** JetBrains Mono, uppercase, `0.3em` tracking (the mono
  voice — RobotHeroes can't carry a lowercase wordmark reliably).
- **Sizes:** `sm` (22px mark) · `md` (30) · `lg` (44) · `xl` (72). The mark
  never renders below `MIN_MARK` = 18px.
- **Clear space:** pass `clearSpace` to reserve ½ the mark height on all
  sides.
- **Variants:** `full` (mark + wordmark), `mark` (icon only), `mono-light`
  (white, for imagery/inverted), `mono-dark` (black, for light surfaces).

```tsx
<BrandLockup size="sm" />                    // nav / footer
<BrandLockup size="xl" variant="mark" />     // hero mark
<BrandLockup variant="mono-light" />         // over a photo
```

The favicon is a separate square crop at `public/favicon.png` (cache-busted
via `?v=` in `__root.tsx`).
