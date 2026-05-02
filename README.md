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
> | 3 — combat-log + auras + heal prediction | 🟡 partial | `UnitAura` migration (durations native); `AuraTracker.lua` retired; native 3.3.5a `Cooldown` frame integration. Still pending: combat-log (CLEU) consumer, LibHealComm-4.0 heal-prediction wire-up, CastIcon/SpellLine sweep |
> | 4 — roster / threat / GUID consolidation | ⏳ | |
> | 5 — secure click-cast integration | ⏳ | Architecture proven (Phase 0.5); integration not started — click-cast currently blocked by 3.3.5a's protected-frame system |
> | 6 — Ascension classless / Mystic specifics | ⏳ | |
> | 7 — cleanup, docs, distribution | ⏳ | |
>
> ### Known limitations during port
> - **Click-to-cast is blocked** until Phase 5 ships secure-template integration. Frames render and aggro detection works, but clicking a unit frame to cast a spell triggers WoW's "Interface action failed because of an AddOn" popup.
> - **Heal prediction is offline** until Phase 3 wires up LibHealComm-4.0. The HealComm-1.0 dependency was removed in Phase 2b without a replacement.
> - **Multi-focus is feature-cut** for v2.0. Native 3.3.5a `focus` is single-slot; a multi-focus equivalent would require separate macro-by-name workarounds with limitations.
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
