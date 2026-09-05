# WarMod — Woobbie & Kam x GameTech

**Version:** 1.0.0
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

## 5. Changelog

### warmod_damage_info.sp — v3.0.1 "Live match rounds only (with overtime)"

**Goal of the update:** damage info (round-end damage summary + on-death damage report) must show **only during live competitive rounds** — first half, second half **and overtime** — and stay completely silent in warmup, knife round, halftime/ready-up breaks and after the match ends.

#### What was wrong before (v3.0.0)

The plugin could only answer **2 of the 5** match lifecycle signals from the core plugin:

- It implemented `OnLiveOn3` (match went live) and `OnResetMatch` / `OnResetHalf` / `Warmod_OnMatchStart` / `Warmod_OnMatchEnd`.
- It did **NOT** implement the **`OnHalfTime`** forward — so it never really knew when a halftime break started.
- It did **NOT** implement the **`OnEndMatch`** forward — so it never really knew when the match truly ended.

To work around that, `Event_RoundEnd` **guessed** halftime and match-end from the engine scoreboard instead of using real match state:

```sourcepawn
// OLD (removed) — guessing from scores:
if (totalRounds == maxHalfRounds) { g_bHalfTime = true; return; }          // halftime guess
if (tScore > maxHalfRounds || ctScore > maxHalfRounds
    || totalRounds >= maxHalfRounds*2) { g_bMatchLive = false; return; }   // match-end guess
```

The problem: **overtime round counts exceed `wm_max_rounds`**, so those guesses fired *during overtime* and wrongly suppressed the round-end damage summary in every OT round. The on-death report survived overtime only by accident (its gate never checked scores), giving inconsistent behavior between the two display paths.

#### Change 1 — Added the missing lifecycle forwards

The plugin now listens to the real match signals broadcast by `warmod.sp` instead of guessing:

```sourcepawn
public void OnHalfTime()   // NEW — fires at the end of every half (regulation AND overtime)
{                          //         -> suppresses damage info during the break
    g_bHalfTime = true;
}

public void OnEndMatch()   // NEW — fires at full time
{                          //         -> match over, damage info blocked
    g_bMatchLive = false;
    g_bHalfTime  = false;
}
```

`OnLiveOn3` was updated (comment) to document that it fires **again at the start of every overtime period** — that is what re-enables damage info in OT, because `warmod.sp` runs a fresh LO3 countdown for each overtime half.

#### Change 2 — Removed all score-guessing from `Event_RoundEnd`

The round-end handler no longer inspects round counts / team scores at all. It now just:

1. Runs the master gate `IsAllowedToShowDamage()`.
2. Records `g_bRoundEnded = true`.
3. Schedules the 0.25 s `Timer_ShowDamage`.

Halftime / match-end suppression is instead handled automatically, because:

- `warmod.sp` calls `OnHalfTime` / `OnEndMatch` **during** round-end processing, *before* the 0.25 s timer fires;
- `Timer_ShowDamage` **re-checks** `IsAllowedToShowDamage()` when it runs — so the halftime round and the final match round are still hidden, while every live regulation **and** overtime round now correctly shows the summary.

```sourcepawn
// NEW — no more score guessing:
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsAllowedToShowDamage())
        return Plugin_Continue;

    int winnerTeam = event.GetInt("winner");
    if (winnerTeam < 2)
        return Plugin_Continue;

    // Halftime and match-end suppression is handled by the OnHalfTime()
    // and OnEndMatch() lifecycle forwards from warmod.sp (which also fire
    // for overtime periods). Timer_ShowDamage re-checks
    // IsAllowedToShowDamage() after these have run, so the summary is
    // still hidden for the halftime round / final match round while
    // remaining active during overtime.

    g_bRoundEnded = true;

    DataPack pack;
    CreateDataTimer(0.25, Timer_ShowDamage, pack);
    pack.WriteCell(winnerTeam);

    return Plugin_Continue;
}
```

#### Change 3 — Plugin metadata

- `description` → `"Displays damage info during live competitive match rounds (first half, second half and overtime)"`.
- `version` → `3.0.1`.

#### Unchanged / still works the same

- The master gate `IsAllowedToShowDamage()` logic itself (`g_bMatchLive`, `g_bHalfTime`, plus optional `Warmod_IsMatchLive` / `Warmod_IsHalfTime` natives for the WarMod Manager variant).
- Damage tracking in `Event_PlayerHurt` and the on-death report in `Event_PlayerDeath` — both already gate through the same master function, so they automatically follow the corrected state machine.
- `wm_reload_damage_colors` command and `configs/warmod_damage_colors.cfg` colors file.
- No changes were needed in `warmod.sp`, any `.cfg`, translations or `include/warmod.inc` — the core already broadcast `OnLiveOn3` / `OnHalfTime` / `OnEndMatch` at the correct moments for overtime.

#### Result

| Match phase | Round-end damage summary | On-death damage report |
|---|:---:|:---:|
| Warmup | ❌ | ❌ |
| Knife round | ❌ | ❌ |
| **1st half (live)** | ✅ | ✅ |
| Halftime break / ready-up | ❌ | ❌ |
| **2nd half (live)** | ✅ | ✅ |
| **Overtime (live)** | ✅ *(new — was broken before)* | ✅ |
| Between OT halves | ❌ | ❌ |
| Match ended / reset | ❌ | ❌ |

> **Note:** compile with the SourceMod 1.11.0 `spcomp` compiler as usual — no new includes or dependencies were introduced.

### warmod.sp — Respawn only after character selection (join-respawn rework)

**Problem:** when a player joined a team (fresh join during **warmup**, or after the automatic **half-time swap**), WarMod force-respawned them **0.5 seconds** later — while the CS:S character/class menu was still open. If the player then picked a character, that counts as a class change while alive, and CS:S kills the player for it ("suicide"). During halftime this could leave the player dead going into the second half.

**Fix:** there is **no automatic first spawn at all** — the player only spawns **after** they have chosen their character (or naturally at the next round restart):

- `Event_Player_Team` no longer fires a one-shot 0.5s respawn. It starts a per-client loop (`StartJoinRespawn` / `Timer_JoinRespawn`) that checks every second:
  - if the player is already alive (spawned naturally, e.g. at a round restart) → stop;
  - while the CS:S netprop `m_iJoiningState` is non-zero (player still in the team/character menus) → **keep waiting, do not spawn**;
  - once the character is chosen (join state `0`) → `CS_RespawnPlayer` + money/C4/defuser strip (`Timer_SafeStrip`), then stop.
  - if the `m_iJoiningState` netprop is missing on the build, the loop never auto-spawns (safe fallback) — the player simply spawns at the next natural round restart.
- **New cvar `wm_join_respawn_wait`** (default `0` = **disabled**): purely opt-in timeout — if set (e.g. `30`), a player idling in the character menu that long is force-spawned with the default class.
- Cleanup: pending retry timers are killed in `OnClientDisconnect` and `OnMapEnd` (no stale client-index timers).
- `RespawnPlayer` itself is unchanged and still used for the instant warmup death-respawn.

**Result:**

| Scenario | Before | After |
|---|---|---|
| Join team in warmup, character menu open | Respawned at 0.5s → picking = **suicide** | Stays dead, no spawn while menu is open ✅ |
| Picks a character | (already suicided by then) | Spawned by warmod within ~1s after picking ✅ |
| Half-time swap, pick new character | Respawned → picking = **suicide** (possibly dead at LO3) | Spawned after picking, alive with chosen character ✅ |
| `m_iJoiningState` missing on build | — | Never auto-spawns → spawns at next round restart (no suicide risk) ✅ |
| Never picks a character (idle in menu) | Spawned after 0.5s with default class | Stays out until they pick (vanilla-like); only force-spawned if `wm_join_respawn_wait` is enabled |


### warmod.sp — Second half no longer auto-starts (ready-up instead)

**Problem:** at the end of the first half (and after every overtime half), WarMod automatically fired **Live on 3** after the team swap — the second half started even if players weren't back / ready.

**Fix:** new cvar **`wm_half_auto_live`** (default `0`):

- **`0` (default):** after the half-time swap the match does **not** go live automatically. Instead the **ready system is enabled** (honoring `wm_half_auto_ready`, which previously existed but was never actually implemented) and the second half starts through the normal ready-up — when enough players type `!ready`, LO3 fires via `CheckReady()`.
- **`1`:** original behavior — automatic LO3 after the swap.

This applies to all three halftime paths: regulation half time, overtime half time, and the `wm_score_mode 2` half time. Overtime **period starts** (draw → new OT period) still go live automatically.

> If both `wm_half_auto_live 0` and `wm_half_auto_ready 0`, the second half will only start via an admin `!lo3` / `!forcestart`.

### warmod.sp — Single restart at full time (warmup settings on the first restart)

**Problem:** when a match reached **full time**, two game restarts happened one after the other:

1. the natural **new round** right after the final round — still running the **live match settings** (freezetime, round time, low startmoney), because `g_live` stayed true for the 3s end-match delay;
2. ~2s later, the warmup restart (`mp_restartgame 1` inside `ApplyWarmupSettings()`) that finally loaded the **warmup settings**.

**Fix:** warmup is now applied **immediately at the end-match step**, so the **first restart already runs with warmup settings** — only **one** restart at full time:

- `Timer_DelayedEndMatch` (+3s after full time, during the round-end countdown, before the natural new round):
  - loads `on_match_end.cfg` (moved here from `ResetMatch`, because applying warmup clears the match state) with the `OnResetMatch` forward and `"match_reset"` log;
  - shows the end-match info;
  - calls `ApplyWarmupSettings(true)` → the **single** `mp_restartgame 1`, already with `mp_freezetime 0`, `mp_roundtime 9999`, `mp_buytime 9999`, `mp_startmoney 16000`;
- a new flag `g_bWarmupApplied` makes the delayed `ResetMatch(true)` (+2s) skip its own warmup restart — it only does the state cleanup (score/team reset);
- `ApplyWarmupSettings()` now takes a `bool:restart` parameter — `!notlive` / `!cancelhalf` (`ResetHalf`) still restart as before, and all other `ResetMatch` callers (cancelmatch, map end) keep the normal restart.

**Result:** full time → end info → **one restart** → warmup round with warmup settings from the very first round. No live-settings round, no double restart.

### warmod.sp + on_match_end.cfg — Dynamic demo name in the end message

The `// endinfo` lines shown at match end now support a **`{demo}` token**: it is automatically replaced with the **actual demo file recorded for that match** (e.g. `demos/2026-09-05-2147-de_dust2-teamA-vs-teamb.dem`) instead of a fixed placeholder text.

- The name shown is the **final** one (after `RenameDemos` removes the `_` "uncompleted" prefix at +15s).
- Respects `wm_save_dir` (demos folder vs. server root) and `wm_auto_record` — if recording is off, it prints `no demo recorded`.
- Everything else in the message (Discord, Website, headers, colors) stays static text — edit it freely in `cfg/warmod/on_match_end.cfg` anytime, no recompile needed (the file is re-read at every match end).



> **Tip:** you can confirm `m_iJoiningState` exists on your server build with `sm_dump_netprops netprops.txt` (look under `CCSPlayer`). If it is missing, the plugin automatically falls back to the `wm_join_respawn_wait` timeout.

