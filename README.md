# WarMod — Woobbie & Kam x GameTech

**Version:** 1.3.2
**Platform:** Counter-Strike: Source **v34** dedicated server with **SourceMod 1.11.0**
**Description:** An automatic match ("warmod") system for CS:S v34 competitive servers — ready-up system, live-on-3, knife round, half-time team swap, overtime, SourceTV demo recording, score tracking and per-weapon statistics.

WarMod is built from **two SourcePawn plugins** plus a shared include:

| Plugin | File | Purpose |
|---|---|---|
| **warmod** | `warmod.sp` | The core match system (ready-up, LO3/KO3, score, overtime, admin commands, cvars) — also includes built-in score preservation across half-time team swaps |
| **warmod_damage_info** | `warmod_damage_info.sp` | Shows per-player damage dealt/taken in chat (round-end summary + on-death report) — only during **live match rounds (first half, second half and overtime)** |
| **warmod include** | `include/warmod.inc` | Shared constants, team/money helpers, stock functions and forwards |

---

## 1. How the WarMod System Works

WarMod is a **match manager**. It turns a normal CS:S server into a competitive match server by running this loop:

### The match flow (simple version)

1. **Server starts / map loads** → cfg files put the server in **warmup mode** (freezetime 0, endless round, $16000, alltalk on).
2. **Ready system** turns on (`wm_auto_ready`). A HUD shows **"Not enough players : N"** until enough people are on teams.
3. Players type **`!ready`** (or `!r`). When `wm_min_ready` players are ready → match starts.
4. **(Optional)** If `wm_auto_knife = 1`, a **knife round** happens first to decide who starts T/CT.
5. **Live on 3 (LO3)** — a 5-second countdown, the server loads the **match ruleset** (`wm_match_config`, e.g. MR15), restarts the round 3×, starts **SourceTV recording**, and opens a **match log**.
6. **First half** plays until one team hits `wm_max_rounds` (e.g. 15 in MR15).
7. **Half time** — teams **auto-swap** (`wm_auto_swap`), ready system turns back on, then **LO3 again** for the second half.
8. **Match end** — whoever has more rounds wins. If tied, **overtime** (`wm_overtime`: off / MRx / sudden death).
9. After the match: demo/log filenames get cleaned up, the **end-info panel** is shown (from `on_match_end.cfg`), and the server **returns to warmup**.

### What WarMod handles during all this

- **Ready-up system** — panels + chat commands so players confirm readiness.
- **Score tracking** — T/CT scores per half + overtime, printed at round end, synced to the scoreboard.
- **Knife round** — strip weapons to knife, winner picks side.
- **Team management** — locked teams mid-match (`wm_lock_teams`), max players, team swap at half time, team names (`wm_t`/`wm_ct`).
- **Demo & stats** — auto SourceTV demo + per-match log, optional MySQL result upload.
- **Cleanup mods** — ragdoll removal, deathcam switching, grenade/NVG blocking in warmup, help-hint removal.

### Match states (in the `wm_status` cvar)

| `wm_status` | What it means |
|---|---|
| 0–4 | Warmup / no match (ready system off/on, knife pending/active) |
| 5 / 8 | **Match live** — first half / second half |
| 6 / 7 | Half-time — ready system off / ready-up for round 2 |
| 9 / 10 | Overtime half-time — ready system off / ready-up |
| 11, 12 (+ overtime# × 2) | **Overtime live** — first / second half |

---

## 2. Requirements & Setup

- **CSS v34 dedicated server** (game folder `cstrike`)
- **SourceMod 1.11.0** installed
- **ClientMod extension** (`clientmod` + `clientmod/multicolors`) — required for colored chat output (`WM_CPrintToChat` etc.). Without it the plugin will fail to load.
- `adminmenu` (ships with SourceMod) — enables the WarMod entry in the in-game admin menu.
- **Optional:** a MySQL database if you enable `wm_upload_results`.

**Install:**
1. Copy `addons/` and `cfg/` into your server root (merge with existing `addons/sourcemod/` and `cfg/`).
2. Compile the two `.sp` scripts (SourceMod `compiler/spcomp` or `scripting/compile.exe`) and place the `.smx` files in `addons/sourcemod/plugins/`.
3. Grant the WarMod admin flag to your admins (see section 5).
4. Put `exec warmod/on_server_start.cfg` in your `autoexec.cfg` (or use the supplied `cfg/autoexec.cfg`) and `exec warmod/on_map_load.cfg` in `server.cfg`.
5. Restart / change map. Type `wm_version` to confirm it loaded.
---

## 4. Commands

WarMod registers its commands as **console commands**, but they also work in **chat** with the `!` / `/` / `.` prefix, and with the `sm_` prefix.  
Example: admin command `forcestart` → usable as `forcestart`, `sm_forcestart`, `!forcestart`, `/forcestart`.

> **Admin flag note** — almost every admin command uses the **`ADMFLAG_CUSTOM1`** flag. In SourceMod 1.11 custom flag 1 is granted with the flag letter **`p`**. So in `admins.cfg` add `"p"` to the entry's flags, or add `"p"` to the `flags` array in `groups.cfg`. (`p`/`q`/`r`/`s`/`t` = custom flags 1–5; `z` = root.) The password command uses `l` (passwd).

### 4.1 Player commands (everyone)

| In chat | Aliases | Console command | Effect |
|---|---|---|---|
| `!ready` | `!rdy`, `!r` | `ready` | Mark yourself **ready** (must be on T/CT). |
| `!unready` | `!notready`, `!unrdy`, `!notrdy`, `!ur`, `!nr` | `unready` | Mark yourself **not ready**. |
| `!scores` | `!score`, `!s` | `scores` | Show the **match score** (T/CT + overtime if live). |
| `!info` | `!i` | `info` | Show the **ready-up panel** privately (if enabled). |
| `!help` | — | (stub) | Intended help command (currently no-op in code). |
| `!wm_readylist` | `!wmrl` | `wm_readylist`, `wmrl` | List every **ready / unready** player in console. |
| `!wm_cash` | — | `wm_cash` | Show your **team's money** (sorted, with weapon indicator), if `wm_round_money = 1`. |
| `!wm_version` | — | `wm_version` | Print plugin **name/version/description**. |
| `@message` | — | — | **Global admin chat** — sends the message to all players in green text. Requires the `adm` (chat) admin flag and `wm_global_chat = 1`. |
| `buy` / `jointeam` / `spectate` | — | (blocked) | Intercepted by WarMod: NVGs/grenades blocked in warmup/knife, team locked mid-match. |

### 4.2 Admin commands (`ADMFLAG_CUSTOM1` = custom flag `p`, unless noted)

| In chat | Aliases | Console | Effect |
|---|---|---|---|
| `!readyup` | `!ru` | `readyup`, `ru` | Toggle the **ReadyUp system** on/off. |
| `!readyon` | `!ron` | `readyon`, `ron` | Turn ReadyUp **on** (+ everyone unready). |
| `!readyoff` | `!roff` | `readyoff`, `roff` | Turn ReadyUp **off**. |
| `!forceallready` | `!far` | `forceallready`, `far` | Force every team player **ready** (can trigger LO3). |
| `!forceallunready` | `!faur` | `forceallunready`, `faur` | Force every team player **unready**. |
| `!lo3` | `!forcestart`, `!fs` | `lo3`, `forcestart`, `fs` | **Force Live-On-3** now (skip ready count, 5s countdown). |
| `!forceend` | `!fe` | `forceend`, `fe` | **Force end** the current match (back to warmup). |
| `!knife` | `!ko3` | `knife`, `ko3` | Start a **Knife-On-3** round (strip weapons → knife + exec knife config). |
| `!cancelknife` | `!ck` | `cancelknife`, `ck` | **Cancel the knife round** and restart the round. |
| `!notlive` | `!nl`, `!cancelhalf`, `!ch` | `notlive`, `nl`, `cancelhalf`, `ch` | Declare the **current half not live** (reset half + restart round). |
| `!cancelmatch` | `!cm` | `cancelmatch`, `cm` | **Cancel the whole match** (reset all scores → warmup). |
| `!swap` | — | `swap` | **Swap all players** to the opposite team (manual half swap). |
| `!t` / `!ct` | — | `t` / `ct` | Set the **Terrorist / CT team name** (used in score + demo/log filenames). |
| `!minready` | — | `minready` | Set or show `wm_min_ready`. |
| `!maxrounds` | — | `maxrounds` | Set or show `wm_max_rounds`. |
| `!active` | — | `active` | Toggle the `wm_active` master switch. |
| `!pwd` / `!pw` | — | `pwd`, `pw` | **`ADMFLAG_PASSWORD` (`l`)** — set or show `sv_password`. |

> With `wm_rcon_only = 1`, all the above are restricted to **RCON / server console** and return "WarMod Rcon Only" from in-game.

**Admin menu** — with `adminmenu` loaded, admins with custom-1 get a **"WarMod Commands"** category containing: Force Start, ReadyUp, Knife, Cancel Half, Cancel Match, Force All Ready/Unready, Toggle Active.
### 4.3 Console / server commands & aliases

- `wm_version` — print plugin version/description.
- `wm_readylist` / `wmrl` — list ready/unready players.
- `wm_cash`, `score` — same as the player commands above.
- From `warmod/on_server_start.cfg`:
  - `mr15` → `wm_match_config warmod/ruleset_mr15.cfg`
  - `mr9` → `wm_match_config warmod/ruleset_mr9.cfg`
  - `lo3` → `forcestart`
  - `r` → `mp_restartgame 1`
  - Map shortcuts: `d2`/`dust2` (de_dust2), `nuke`, `train`, `ferno`/`inferno`, `cbble`, `prodigy`, `temple` (de_losttemple_pro), `season`, `contra`, `tuscan`, `russka`, `mill`/`cplmill` (de_cpl_mill)

### 4.4 Command reference summary (from the source)

| Registered command | Handler | Flags | Alias(es) | Purpose |
|---|---|---|---|---|
| `score` | `ConsoleScore` | none | — | Show match score (console/chat) |
| `wm_version` | `WMVersion` | none | — | Show version |
| `say` / `say_team` | `SayChat` / `SayTeamChat` | none | — | Chat intercept: ready/scores/info/@-global-chat |
| `buy` | `RestrictBuy` | none | — | Block NVG/grenades in warmup/knife |
| `jointeam` / `spectate` | `ChooseTeam` | none | — | Lock teams / max-players mid-match |
| `wm_readylist` / `wmrl` | `ReadyList` | none | — | List readies |
| `wm_cash` | `AskTeamMoney` | none | — | Show team money |
| `notlive` / `nl` / `cancelhalf` / `ch` | `NotLive` | custom1 | 4 | Reset current half |
| `cancelmatch` / `cm` | `CancelMatch` | custom1 | 2 | Reset match |
| `readyup` / `ru` | `ReadyToggle` | custom1 | 2 | Toggle ready system |
| `t` / `ct` | `ChangeT` / `ChangeCT` | custom1 | 1 | Set team names |
| `swap` | `SwapAll` | custom1 | 1 | Swap all players |
| `pwd` / `pw` | `ChangePassword` | password | 2 | Set sv_password |
| `active` | `ActiveToggle` | custom1 | 1 | Toggle wm_active |
| `minready` | `ChangeMinReady` | custom1 | 1 | Set wm_min_ready |
| `maxrounds` | `ChangeMaxRounds` | custom1 | 1 | Set wm_max_rounds |
| `knife` / `ko3` | `KnifeOn3` | custom1 | 2 | Start knife round |
| `cancelknife` / `ck` | `CancelKnife` | custom1 | 2 | Cancel knife |
| `forceallready` / `far` | `ForceAllReady` | custom1 | 2 | Force all ready |
| `forceallunready` / `faur` | `ForceAllUnready` | custom1 | 2 | Force all unready |
| `lo3` / `forcestart` / `fs` | `ForceStart` | custom1 | 3 | Force live on 3 |
| `forceend` / `fe` | `ForceEnd` | custom1 | 2 | Force end match |
| `readyon` / `ron` | `ReadyOn` | custom1 | 2 | Ready system on |
| `readyoff` / `roff` | `ReadyOff` | custom1 | 2 | Ready system off |
| `wm_reload_damage_colors` | (damage_info plugin) | none | — | Reload damage colors config |

> **Chat prefixes:** `!` `/` `.` all work, e.g. `!r`, `/ready`, `.scores`. In `say_team` the same commands also work.

---
