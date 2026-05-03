# Puppeteer (Ascension)

Unit-frames addon for healers, ported from [OldManAlpha/Puppeteer](https://github.com/OldManAlpha/Puppeteer) to **WotLK 3.3.5a / Project Ascension**. Originally HealersMate. Aims to be a viable alternative to Cell, VuhDo, or Healbot on the 3.3.5a private-server scene.

`/pt` opens the configuration menu.

<p align="left">
  <img src="https://github.com/OldManAlpha/HealersMate/raw/main/Screenshots/Party-Example.PNG" alt="Party Example" width=15%>
  <img src="https://i.imgur.com/nXSCc8F.png" alt="Raid Example" width=31%>
</p>

## Status

**v2.0 — port complete.** The addon runs on stock 3.3.5a clients with no external client mods. Tested on **Bronzebeard / Warcraft Reborn** (Project Ascension's Classic+ realm). It should work on any 3.3.5a-based Ascension realm; the classless-realm specifics (Area 52 / Conquest of Azeroth) are tracked separately — see [Roadmap](#roadmap).

If you used the original Vanilla 1.12 addon, see [What changed from 1.12](#what-changed-from-the-112-version) below.

## Features

- Health, power, marks, aggro, PvP status, and relevant buffs/debuffs for party, raid, pets, and targets
- **Secure click-cast** — bind mouse clicks, the mouse wheel, and keys (with any combination of Shift/Ctrl/Alt) to spells, macros, items, custom Lua scripts, or popup menus. Works in combat
- **Hover-to-cast keybinds** — keys cast on the unit frame the cursor is over without clicking, in or out of combat
- **Aura tracking with native countdown sweep** — buffs and debuffs from `UnitAura`, with the standard 3.3.5a `Cooldown` swirl driving the timer
- **Mystic-aware dispel highlighting** — debuff types you can dispel are colorized on every frame, including dispels granted by Mystic Enchantments (e.g. "Remove Curse" learned by a Priest will cause Curse-type debuffs to colorize). Updates on `SPELLS_CHANGED` without `/reload`
- **Self-cast incoming-heal bar** — predicts your own incoming heals on the target's bar from a learned-amount cache populated via the combat log
- **Bound-spell tooltip** — hover a frame to see your current power, every bound spell, and its mana cost
- **Roles** — assign per-player tank / healer / DPS labels for organization
- **Multi-language UI** — non-English locales supported via `locale/Locale.lua`

### Bindings

<img align="right" width="36%" src="https://i.imgur.com/KoFygXv.png">

Mouse buttons, the mouse wheel, and keys can all be bound, with any combination of Shift/Ctrl/Alt. Bindings can hold spells, macros, items, custom Lua scripts (out of combat), or popup menus that hold further bindings. The `/pt` configuration UI lets you pick a different binding set per loadout, and per-target hostility (friendly vs hostile).

<p align="left">
  <img src="https://i.imgur.com/iglcV7z.png" width=30% align="top">
  <img src="https://i.imgur.com/7iIQTkk.png" width=30% align="top">
</p>
<p align="left">
  <img src="https://i.imgur.com/VW0BAYg.png" width=30% align="top">
</p>
<p align="left">
  <img src="https://i.imgur.com/v6GWN9r.png" width=30% align="top">
  <img src="https://i.imgur.com/rOh9k9L.png" width=25% align="top">
</p>
<br clear="all">

### Spells at a glance

Hovering over a unit frame shows your power, your bindings on that target, and each spell's cost.

<p align="left">
  <img src="https://i.imgur.com/ZfChKaQ.png" width=40% align="top">
</p>

## Installation

1. Download the repository (Code → Download ZIP, or `git clone`).
2. Extract / move it into your client's add-on directory so the path is `<Ascension>/Interface/AddOns/Puppeteer/`. **The folder name must be exactly `Puppeteer`** — Ascension's loader will refuse the addon if the folder is suffixed (`Puppeteer-main`, `Puppeteer-Ascension`, etc.).
3. Launch the client and enable Puppeteer in the AddOns list. Type `/pt` in chat to open the configuration UI.

This addon coexists with ElvUI (and other unit-frame addons) — ElvUI's frames hide Puppeteer's cast bar, but there is no taint or click-cast interference between the two.

## What changed from the 1.12 version

This fork rewrites the Vanilla-only subsystems against native 3.3.5a APIs. If you used the original addon, the practical differences:

- **No SuperWoW / UnitXP SP3 / Nampower / VanillaUtils.** Those mods don't exist on 3.3.5a; the features that depended on them are either rebuilt natively (auras, aggro, click-cast) or removed.
- **Heal prediction is self-cast only.** The 3.3.5a `UNIT_SPELLCAST_*` events don't carry the cast's target, so we can only predict your own heals. A learned-amount cache (`PTHealCache` / `PTPlayerHealCache`) populates from the combat log.
- **Multi-focus is removed.** Native 3.3.5a `focus` is single-slot; the SuperWoW-only `focus2..N` token system is gone. Single-slot native focus restoration is on the v2.1 list.
- **Distance / line-of-sight indicators are removed.** Both relied on UnitXP SP3.
- **Click-cast is now secure.** Per-frame `SecureActionButton` overlays and hidden `SetBindingClick`-routed keybind buttons replace the old insecure dispatcher, so clicks and hover-key-casts work in combat without triggering taint.

### Setting caveats worth knowing

- **`Cast When (Keys)` (Key Up vs Key Down)** is honored only on the legacy insecure path. On the secure path (default) keybinds always fire on key-down — that's how Blizzard's `SetBindingClick` works, not something we can override without giving up secure-template benefits. The setting still applies to `Menu` / `Role` / `Macro` / `Script` / `Multi` binding types (which keep using the legacy dispatcher) and to the whole legacy path if you turn off `UseSecureClickCast`.
- **`Out of Range Arrow`** has coarser accuracy than the Vanilla original. Without UnitXP SP3 / SuperWoW, range checks fall back to `CheckInteractDistance`, which only resolves a fixed ~28-yd interact bracket — fine for "in range / out of range" signaling but not the fine-grained yard distance the upstream addon shows.
- **Settings GUI is blocked in combat.** Opening or staying in `/pt` while in combat would taint secure-attribute writes to the click-cast overlays, so the GUI auto-closes on `PLAYER_REGEN_DISABLED` and refuses to open while in combat. Edit bindings between pulls.
- **Various TWoW / SuperWoW Experiments are gone.** The "Mods" tab, "Set Mouseover" checkbox, "(SuperWoW) Cast Icons" experiment, "(TWoW) LFT Auto Role" checkbox, and "(TWoW) Auto Role" experiment have all been removed because their underlying client mods or addon-channel protocols don't exist on 3.3.5a.

## Roadmap

- **v2.0 (current)** — port to 3.3.5a complete. Stable for healing on Bronzebeard.
- **v2.1** — single-slot native focus restoration; possible workarounds for predicting other players' incoming heals; classless-realm support (Area 52 / CoA) once a real user surfaces there.
- **v3.0** — styling system redesign. The bespoke unit-frame implementation will be replaced with vendored [oUF](https://github.com/oUF-wow/oUF) (from the ElvUI-WotLK source), token-based theming, [LibSharedMedia-3.0](https://www.wowace.com/projects/libsharedmedia-3-0) integration, and AceDB-3.0 persistence. The current 770-line `ProfileManager.lua` preset literal and the per-property Customize tab go away in favor of declarative themes with diff-based overrides. Multi-month effort, parked until v2.0 has accumulated real raid use.

## FAQ

<details>
<summary>Click to view</summary>

| Question | Answer |
|---|---|
| **Click-casting doesn't work on some bindings in combat** | Bindings of type Menu / Role / Macro / Script / Multi still fall through to the legacy insecure dispatcher and produce "Interface action failed" inside combat. Use Spell / Target / Assist / Follow bindings for combat-critical actions. The legacy dispatcher gets cleaned up once the secure path has soaked in real raid use. |
| **My Priest doesn't have Dispel Magic / Cure Disease** | On Bronzebeard, base Priests must purchase Dispel Magic and Cure Disease from the trainer rather than learning them automatically — that's an Ascension ruleset choice, not a Puppeteer issue. Once you train them (or pick up an equivalent dispel via a Mystic Enchantment), Puppeteer detects them and colorizes the matching debuff types. |
| **Adding a binding crashes or doesn't update in combat** | The settings UI is blocked from opening (and auto-closes) inside combat to prevent secure-attribute taint. Edit bindings between pulls. |

</details>

## Credits

- [i2ichardt](https://github.com/i2ichardt) — original HealersMate author
- [OldManAlpha](https://github.com/OldManAlpha) — Puppeteer rewrite (Vanilla 1.12)
- @blondieart (Discord) — original art (top of upstream README)
- [Shagu](https://github.com/shagu) — utility functions and addon-development reference material
- The Ascension and 3.3.5a private-server addon community for the secure-template, click-cast, and oUF reference implementations that informed this port
