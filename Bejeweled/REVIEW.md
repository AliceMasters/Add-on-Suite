# Bejeweled — Code Review & Bug Hunt

**Date:** 2026-09-19 (updated)
**Target:** `Bejeweled/Bejeweled.lua` + `Bejeweled.toc`
**Method:** two-layer automated QA (see `tests/`) + line-by-line WoW-API audit.

## Verdict

Two real, user-visible bugs were found and fixed — a **missing board assignment
in `Collapse()`** (the root cause of "gems don't fall" *and* the overlapping-gem
rendering) and an **icon that didn't represent its gem's colour**. Both are now
covered by an automated test that runs the actual shipped Lua. Several smaller
hardening fixes were also applied.

## The headline bug (root cause of two separate reports)

`Collapse()` refills a column by spawning new gems into the empty top cells. It
created each gem, positioned it, and animated it — but **never wrote it back into
the `board` grid** (`board[rr][c] = gem` was missing). Consequences:

- **"Gems don't fall after a match"** — after a cascade the top cells were `nil`
  in the data. New sprites appeared, but the engine's next match/collapse ran on a
  board full of holes, so the game visibly broke after a match.
- **"A gem showing the wrong thing / white gem on top of a yellow one"** — the
  orphaned sprites stayed on screen while the *next* collapse spawned fresh buttons
  over the same cells, stacking two gems in one square.

**Fix:** add `board[rr][c] = gem` in the spawn loop.

**Why the model missed it (and why that matters):** the Layer-1 Python model
passed 60,000 moves because the model contained that line — it tested *intent*,
not the shipped artifact. The Layer-2 test that loads and drives the real
`Bejeweled.lua` caught it on move 0. Both layers are kept; Layer 2 is authoritative.

## Icon didn't represent colour — FIXED

Most `INV_Misc_Gem_*` icon paths resolve to near-identical grey "uncut" crystals
on retail, and a recycled button whose new icon path doesn't cleanly load keeps
its previous texture (stale). Result: gems that didn't look like their colour.
**Fix:** vertex-tint the icon to the gem's colour in `SetGemAppearance` — even a
generic or stale texture is forced to the correct hue. Regression-guarded by the
integration test (asserts every gem's icon tint matches its colour every move).

## Other fixes this pass

| Bug | Severity | Status |
|---|---|---|
| `Collapse()` missing `board[rr][c] = gem` | **Critical** | ✅ Fixed |
| Gem icon not colour-accurate / stale on recycle | High | ✅ Fixed (vertex tint) |
| `New Game` / minimap right-click bypass `inputLocked`; stale timers hit the new board (incl. writing released gems over fresh cells) | Medium | ✅ Fixed (`gameGen` token) |
| `math.atan2` may be nil on modern client Lua | Medium | ✅ Fixed (fallback) |
| `UIErrorsFrame:AddMessage` extra args | Low | ✅ Fixed |
| Dead no-op loop in `BuildUI` | Trivial | ✅ Removed |
| Silent Lua errors in async callbacks | — | ✅ `Safe()` wrapper surfaces + unlocks |

## Automated proof (see `tests/`, runs in CI on every push)

- **Layer 1 — model fuzz:** 300 games × 200 moves = 60,000 moves, invariant
  checks after every move; special-gem scenarios. → ALL PASS.
- **Layer 2 — real-Lua integration:** the actual `Bejeweled.lua` loaded via an
  embedded Lua runtime + mock WoW API; 120 games × 150 moves = 18,000 moves,
  ~10k specials exercised, icon guard on every gem. → ALL PASS.
- **Syntax:** `Bejeweled.lua` parses clean.

## Feature completeness

8×8 board · click/drag swap · invalid-swap revert · match 3/4/5 · cascades with
combo multiplier · Flame (match-4, 3×3 detonation + chaining) · Hypercube
(match-5, clears a colour) · levels + progress bar · no-moves auto-shuffle ·
hint + idle auto-hint · sounds · saved high score · movable window · minimap
button · slash commands. **All present and verified.**

## Feature ideas (for the mini-game suite)

- L/T match-of-5 special (currently only straight 5-runs make a Hypercube).
- Special-on-special interactions (Hyper+Hyper, Flame+Flame).
- Timed/blitz mode; a proper game-over screen.
