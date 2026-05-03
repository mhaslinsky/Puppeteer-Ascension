# Puppeteer-Ascension

> **Fork of [OldManAlpha/Puppeteer](https://github.com/OldManAlpha/Puppeteer) — port to WotLK 3.3.5a (Project Ascension).**
>
> This is an **in-progress port**. The upstream addon targets Vanilla 1.12 and depends on Vanilla-only client mods (SuperWoW, UnitXP SP3, Nampower) for many of its features. This fork rewrites those subsystems against native 3.3.5a APIs (`UnitAura`, `UnitThreatSituation`, `Cooldown` frames, `COMBAT_LOG_EVENT_UNFILTERED`) so the addon runs on standard WotLK clients with no external mods.
>
> ### Current port status
>
> | Phase | Status | What landed |
> |---|---|---|
> | 0 — toc bump | ✅ | `Interface: 11200 → 30300` |
> | 0.5 — secure-template spike | ✅ | Secure click-cast architecture proven via throwaway addon (`SecureSpike`) |
> | 2a — Lua 5.0→5.1 + 1.12→Wrath sweep | ✅ | `table.setn` obsolete cascade fixed; implicit `arg` table → `{...}`; UIDropDownMenu / PanelTemplates signature flips; ScrollFrame `this`-global → `(self,...)` |
> | 2b — Ace2 framework rip | ✅ | All Ace2 libs removed (AceLibrary/Locale/OO/Debug/Addon/Console/Event/Hook, Compost, Gratuity, RosterLib, Deformat, ItemBonusLib, Banzai, HealComm-1.0). Only LibStub remains. PuppeteerLib replaced with frame-based dispatcher; aggro via native `UnitThreatSituation` |
> | 3 — combat-log + auras + heal prediction | ✅ | `UnitAura` migration (native durations); `AuraTracker.lua` retired; native 3.3.5a `Cooldown` frame integration; native `UNIT_SPELLCAST_*` cast tracking; CLEU heal-amount learning into `PTHealCache`/`PTPlayerHealCache` (LibHealComm-4.0 wire-up abandoned — Ascension reassigns vanilla 3.3.5a spell IDs, breaking LibHealComm's name-keyed tables) |
> | 4 — roster / threat / GUID consolidation | ✅ | Cap flags hardcoded `false` (no SuperWoW/UnitXP/Nampower/VanillaUtils probes); `EnemyTracker.lua` / `UnitProxy.lua` / `AuraTracker.lua` deleted; `ShaguUtil.lua` pruned 224 dead lines; PTUnit dual-key collapsed to single-key (unit-id); 4 pre-existing Vanilla→Wrath script-signature port bugs fixed (CallWithThis `self=nil`, tooltip SetOwner on FontString, dropdown chevron OnClick, dropdown init callback). Net −1245 / +119 |
> | 5 — secure click-cast integration | 🟡 | Slices 1+2 shipped. **Slice 1** ([PR #10](https://github.com/mhaslinsky/Puppeteer-Ascension/pull/10)): per-frame `SecureActionButton` overlays + hidden global keybind buttons routed via `SetBindingClick`; Target/Assist/Follow + SPELL bindings dispatch securely; Menu/Role/Macro/Script/Multi fall through to insecure handler (works OOC, fails in combat). In-combat hover-key-cast on 3.3.5a now works. **Slice 2** ([PR #11](https://github.com/mhaslinsky/Puppeteer-Ascension/pull/11)): aura icon click-through via `EnableMouse(false)` on aura buttons + cursor-position polling for hover tooltips. **Slice 3+ pending**: in-combat-safe GUI attribute writes; cleanup slice (delete legacy `Apply/RemoveOverrideBindings` / `HandleKeyPress` / `Bindings.xml` numbered bindings) once secure path soaks in real raid use |
> | 6a — Bronzebeard Mystic Enchant dispel awareness | ✅ | `UpdateTrackedDebuffTypes` scans every class's dispel table against the player's spellbook so a Mystic Enchantment that grants a cross-class dispel (e.g. "Remove Curse" on a Priest) causes the corresponding debuff types to colorize. Updates on `SPELLS_CHANGED` without `/reload` |
> | 6b — Classless realm support (Area 52 / CoA) | ⏳ | Deferred until there's a real Area 52 / CoA user. Bronzebeard restricts to the Original 9 Classes with stable `UnitClass`, so the spellbook-based healer detection / spell-ID resolver / drop-`HealerClasses`-hardcode work isn't needed for that realm |
> | 7 — cleanup, docs, distribution | ⏳ | |
>
> ### Known limitations during port
> - **In-combat click-cast and hover-key-cast work** (Phase 5 / Slices 1+2). Native `[@mouseover]` macrotext routing through hidden `SecureActionButton`s, with per-frame overlays publishing the unit attribute. Bindings of type Menu / Role / Macro / Script / Multi still fall through to the legacy insecure handler — they work OOC but produce "Interface action failed" in combat (same as pre-Phase-5).
> - **Heal prediction is self-cast only.** The CLEU-based learner populates incoming-heal bars when the player casts on themselves or a damaged target; predicting incoming heals from other group members would require a target identifier in 3.3.5a's `UNIT_SPELLCAST_*` events that doesn't exist. Deferred.
> - **Multi-focus is feature-cut** for v2.0. Native 3.3.5a `focus` is single-slot, and the SuperWoW-only `focus2..N` tokens are gone with the `UnitProxy.lua` delete in Phase 4. Native single-slot focus restoration is a v2.1 follow-up.
> - **Vanilla 1.12 / SuperWoW are no longer supported targets.** All capability probes (`SuperWoW`, `UnitXPSP3`, `Nampower`, `VanillaUtils`, `TurtleWow`) are hardcoded `false` in `libs/Util.lua`. Original Vanilla-only code paths have been removed; the addon targets stock 3.3.5a Wrath / Project Ascension only.
>
> Original Vanilla 1.12 README follows below. Anything in it that depends on SuperWoW / UnitXP SP3 / Nampower / VanillaUtils is being progressively replaced with native 3.3.5a equivalents and may behave differently in this fork.

---

# Puppeteer

<img align="right" width="40%" src="https://i.imgur.com/hKjSAd5.jpeg">
Puppeteer, formerly HealersMate, is a unit frames addon for World of Warcraft Vanilla 1.12 that strives to be an alternative to modern WoW's VuhDo, Cell, or Healbot. Its features are tailored for healers, but can be a viable unit frames addon for any class and spec.

### Features
- See health, power, marks, incoming healing, mob aggro, PvP status, and relevant buffs & debuffs of your party, raid, pets, and targets
- Bind mouse clicks, the mouse wheel, and keys to spells
- See your bound spells, their cost, and available mana while hovering over frames
- Assign roles to players
- Choose from a variety of preset frame styles, with some customization, eventually to be fully customizable
- See the distance between you and other players (**[SuperWoW or UnitXP SP3 Required](#client-mods-that-enhance-puppeteer)**, otherwise only can check 28 yds)
- See when players/enemies are out of your line-of-sight (**[UnitXP SP3 Required](#client-mods-that-enhance-puppeteer)**)
- See the remaining duration of buffs and HoTs on other players (**[SuperWoW Required](#client-mods-that-enhance-puppeteer)**)
- Add players/enemies to a separate Focus group, even if they're not in your party or raid (**[SuperWoW Required](#client-mods-that-enhance-puppeteer)**)

<p align="left">
  <img src="https://github.com/OldManAlpha/HealersMate/raw/main/Screenshots/Party-Example.PNG" alt="Party Example" width=15%>
  <img src="https://i.imgur.com/nXSCc8F.png" alt="Raid Example" width=31%>
</p>
<br clear="all">

### Simple, Yet Advanced Bindings
<img align="right" width="36%" src="https://i.imgur.com/KoFygXv.png">

Puppeteer boasts the ability to bind mouse clicks, the mouse wheel, and keys to any combination of Shift/Ctrl/Alt modifiers. You can bind spells, macros, items, custom Lua scripts, and menus which contain multiple bindings. **Use the `/pt` command to open the configuration menu.**
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

### View Spells at a Glance

When hovering over a player, a tooltip is displayed showing you your current power, what spells you have bound, and their power cost.

<p align="left">
  <img src="https://i.imgur.com/ZfChKaQ.png" width=40% align="top">
</p>

### Client Mods That Enhance Puppeteer

While not required, the mods listed below will massively improve your experience with Puppeteer, and likely the game in general. Note that some vanilla servers may not allow these mods and you should check with your server to see if they do. Turtle WoW does not seem to have a problem with any of these. See [this page](https://github.com/RetroCro/TurtleWoW-Mods) for information about how to install mods.

| Mod | Enhancement |
| - | - |
| SuperWoW ([GitHub](https://github.com/balakethelock/SuperWoW)) | - Shows more accurate incoming healing, and shows incoming healing from players that do not have HealComm<br>- Track the remaining duration of many buffs and HoTs on other players<br>- Allows casting on players without doing split-second target switching<br>- Lets you see accurate distance to friendly players/NPCs<br>- Lets you set units you're hovering over as your mouseover target |
| UnitXP SP3 ([Codeberg](https://codeberg.org/konaka/UnitXP_SP3/wiki)) | Allows Puppeteer to show very accurate distance to both friendly players and enemies, and show if they're out of line-of-sight |
| Nampower ([Gitea](https://gitea.com/avitasia/nampower)) | Drastically decreases the amount of time in between casting consecutive spells  |

### Roadmap of Major Planned Features

Tentative, this could change at any time.
- [X] ~~1.0.0~~
  - ~~Overhaul bindings~~
  - ~~Lay out groundwork for GUI development~~
- [X] 1.1.0
  - ~~Support non-English clients~~
  - ~~Add Enemy frames (SuperWoW Required)~~
- [ ] 1.2.0 and/or 1.3.0
  - Cell-like unit frame customization
  - Customizable buff/debuff tracking

### FAQ & Known Issues

<details>
  <summary>Click To View</summary>

| Question/Issue | Answer |
| - | - |
| **Focus/Enemy Frames Don't Work** | If you are using the PerfBoost mod, you must turn off the `Filter GUID Events` setting. |
| **Casting on other players doesn't work** | You likely have another addon that is interfering with Puppeteer's ability to cast directly. Try disabling other addons until you find the culprit. CallOfElements is known to cause this issue. To fix it, use [this version of CallOfElements](https://github.com/MarcelineVQ/CallOfElements). |
</details>

### Credits

- [i2ichardt](https://github.com/i2ichardt) - Original HealersMate Author
- Turtle WoW Community - Answers to addon development questions
- [Shagu](https://github.com/shagu) - Utility functions, providing a wealth of research material, and general inspiration
- @blondieart (Discord) - Created the art at the top of this page
