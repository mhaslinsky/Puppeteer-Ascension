# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Puppeteer is a World of Warcraft **Vanilla 1.12** unit-frames addon (formerly HealersMate) targeted at healers. There is no build, lint, or test pipeline — the addon is plain Lua + XML loaded by the WoW client. To "test", drop the repo into `<WoW>/Interface/AddOns/Puppeteer/` and `/reload` in-game (or `/console reloadui`). The user-facing slash command is `/pt`.

`Puppeteer.toc` declares `## Interface: 30300` (WotLK 3.3.5a, since the port to Ascension began) and is the authoritative load order — when adding a new file, it must be inserted in `Puppeteer.toc` at a position where its dependencies (globals, `AceLibrary` registrations, environment tables) are already defined. Order in the toc matters; alphabetical is wrong.

**Active port in progress**: this addon is mid-port from Vanilla 1.12 → 3.3.5a Project Ascension. Read `.research/SESSION-STATE.md` first for current status, then `.research/PORT-PLAN.md` for the full plan. The four `pass1..pass4.md` reports under `.research/` are background research; only re-read if a specific finding is in question. Spike addons in `.research/spike/SecureSpike/` and `MysticSpike/` are the reference implementations of the secure-template and classless-detection patterns and **must not be deleted** until Phase 5 / Phase 6 integration ships.

**PR target**: PRs always go to `mhaslinsky/Puppeteer-Ascension` (the fork, `origin`), NEVER to `OldManAlpha/Puppeteer` (upstream). When using `gh pr create`, always pass `--repo mhaslinsky/Puppeteer-Ascension` AND verify the returned URL points at `mhaslinsky/Puppeteer-Ascension/pull/N` before reporting success — `gh` has been observed creating a PR on upstream even with `--repo` set. After creating, run `gh pr list --repo OldManAlpha/Puppeteer --state open --author @me` to confirm no stray PR was opened on upstream; if one exists, close it immediately.

SavedVariables: `PTGlobalOptions`, `PTHealCache`, `PTPlayerHealCache`, `PTRoleCache` (account-wide); `PTBindings`, `PTOptions` (per-character). Changing the shape of any of these requires either a migration in the load path or a `## Version` bump with reset logic — old saved data will be deserialized into the new code.

## Big-picture architecture

**Environment-table pattern (read this first).** Almost every Lua file begins with `PTUtil.SetEnvironment(SomeNamespace)`. This calls `setfenv(2, t)` so all globals declared in the file land on `SomeNamespace` instead of `_G`, with a metatable falling back to `_G`. Consequences:
- A bare `function Foo()` inside `Puppeteer.lua` is actually `Puppeteer.Foo`, callable from Bindings.xml as `Puppeteer.HandleKeyPress(n)`.
- To reach the real `_G` you must capture it explicitly: `local _G = getfenv(0)`. You'll see this idiom at the top of nearly every file.

(Pre-Phase-4 the metatable also fell through `PTUnitProxy` so unit functions transparently resolved SuperWoW custom units like `focus3` to their tracked GUIDs. `PTUnitProxy` and `libs/UnitProxy.lua` were deleted in Phase 4 / [PR #8](https://github.com/mhaslinsky/Puppeteer-Ascension/pull/8) along with the multi-focus feature-cut for v2.0; native unit functions now apply unmodified.)

**Capability detection is gone.** `libs/Util.lua` previously probed for vanilla-1.12 client mods at load (`SuperWoW`, `UnitXP SP3`, `Nampower`, `VanillaUtils`, `TurtleWow`) to gate optional features. Phase 4 hardcoded all five flags to literal `false` — none of those mods exist on 3.3.5a. The flags and helper functions (`IsSuperWowPresent` etc.) are still defined for legacy callers but always return `false`. Any new feature should target stock 3.3.5a Wrath / Project Ascension; do not branch on these flags expecting a mod path to fire.

**Three layers stacked on top of frames.**
1. `core/` — event wiring, command handlers, role inference, unit tracking (range/sight), binding resolution, enemy tracking. `core/EventHandler.lua` is the single registration point: `RegisterEventHandler({events...}, fn)` creates a hidden frame per registration and pushes it into `EventHandlerFrames` so they can be torn down together.
2. `PTUnitFrame.lua` + `PTUnitFrameGroup.lua` — the unit-frame widget itself (health/power bars, aura panel, role icon, target outline, fake-stats for the configurator) and the group container that arranges them. `Puppeteer.lua` owns the global registries: `AllUnitFrames`, `PTUnitFrames` (unit→[frames]), `UnitFrameGroups`. `UnitFrames(unit)` is a stateful iterator — **do not call it concurrently with itself** (the iterator state is shared and a "Collision" warning is printed).
3. `gui/` + `libs/gui/` — settings/config UI built on `PTGuiLib` (a thin component framework: Container, Button, Checkbox, Slider, Dropdown, EditBox, TabPanel, ColorSelect, etc.). `gui/Settings.lua` wires it all together; `gui/component/uf/` are unit-frame overlay widgets (CastIcon, HighlightBorder, Arrow).

**Bindings model.** `Bindings.xml` declares 24 numbered keybindings (`PUPPETEERBINDING1..24`) that all dispatch through `Puppeteer.HandleKeyPress(n)`. The mapping from binding-slot → action lives in `PTBindings.Loadouts[selected].Bindings.{Friendly,Hostile}[modifier][button]`, where `modifier` is e.g. `"Shift"`/`"Ctrl"`/`"None"` and `button` includes mouse buttons + the 24 key slots. `core/Bindings.lua` resolves these; `core/ActionBindings.lua` and `core/OverrideBindings.lua` execute them; `gui/component/SpellBindInterface.lua` and friends edit them.

**Profiles (UI layout) are being deprecated.** `Profile.lua` opens with a deprecation notice — UI profiles will be replaced by a more modular system. New layout/styling work should not deepen the profile system; ask before extending it.

**i18n.** `locale/Locale.lua` defines `Translate(str)` (aliased as `T`). `SetTranslations(table)` swaps in a non-English version; the English path is the no-op identity function. Any new user-facing string must go through `T(...)` if it's expected to be translatable. `EXPORT_MODE` in Locale.lua is a developer aid for dumping translatable strings.

**Vendored libraries (`libs/ace/`, `libs/Banzai-1.0`, `libs/HealComm-1.0`, `libs/ItemBonusLib-1.0`).** These are Vanilla-era forks pinned to specific versions. Resolve them with `AceLibrary("...")` (e.g. `AceLibrary("Compost-2.0")`, `AceLibrary("HealComm-1.0")`). Don't update them in isolation — the vanilla forks diverge from upstream and other code depends on their exact APIs.

## Conventions specific to this codebase

- Lua 5.0 / Vanilla API only: no `#tbl` (use `table.getn`), no `goto`, no `+=`, no integer/float distinction, no `string.format("%d")` on non-integers without care. Frame APIs are 1.12 — `:SetBackdrop`, `:CreateTexture`, `:RegisterEvent` with `arg1..argN` globals inside the handler (no `self, event, ...` signature).
- Compost (`AceLibrary("Compost-2.0")`) is used heavily for table pooling. When you `compost:Acquire()` a table, you must `compost:Reclaim()` it — there's a `util.CompostReclaim` helper. Leaks here will silently grow memory across reloads.
- The codebase deliberately uses globals (via the env-table pattern) instead of returning module tables. New files should follow the same pattern: declare a namespace table, call `PTUtil.SetEnvironment(namespace)`, then write top-level `function Foo()` definitions.
- `core/EnemyTracker.lua` and the Focus/custom-unit system require SuperWoW. PerfBoost's "Filter GUID Events" setting breaks them — a known issue documented in the README.
