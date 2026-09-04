#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientmod>
#include <clientmod/multicolors>

// Game verification flag and match state
bool g_bMatchLive = false;
bool g_bHalfTime = false;
bool g_bRoundEnded = false;

// Damage and hit storage
int g_iDamageDealt[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_iHitsDealt[MAXPLAYERS + 1][MAXPLAYERS + 1];

// Colors loaded from configs/warmod_damage_colors.cfg
char g_sColLg[16];
char g_sColW[16];
char g_sColT[16];
char g_sColCT[16];

// Optional native bindings to WarMod Manager
native bool Warmod_IsMatchLive();
native bool Warmod_IsHalfTime();

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("Warmod_IsMatchLive");
    MarkNativeAsOptional("Warmod_IsHalfTime");
    return APLRes_Success;
}

public Plugin myinfo =
{
    name = "Warmod damage info",
    author = "Woobbie",
    description = "Displays damage info only during live competitive matches",
    version = "3.0.1",
    url = "https://github.com/Woobb1e"
};

public void OnPluginStart()
{
    // Dedicated CS:S v34 verification
    char game[32];
    GetGameFolderName(game, sizeof(game));
    if (!StrEqual(game, "cstrike", false))
        SetFailState("This plugin is designed for Counter-Strike: Source v34 (cstrike) only.");

    g_bMatchLive = false;
    g_bHalfTime = false;
    g_bRoundEnded = false;

    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("round_start", Event_RoundStart);

    LoadDamageColors();
    RegConsoleCmd("wm_reload_damage_colors", Command_ReloadDamageColors);
}

public void OnMapStart()
{
    // Reset all flags to blocked state on map start (warmup/knife)
    g_bMatchLive = false;
    g_bHalfTime = false;
    g_bRoundEnded = false;

    for (int i = 1; i <= MAXPLAYERS; i++)
    {
        for (int j = 1; j <= MAXPLAYERS; j++)
        {
            g_iDamageDealt[i][j] = 0;
            g_iHitsDealt[i][j] = 0;
        }
    }
}

// -------------------------------------------------------------------
// WarMod lifecycle hooks - direct state control
// -------------------------------------------------------------------
public void OnLiveOn3()
{
    // Match goes live (Lo3 finished)
    g_bMatchLive = true;
    g_bHalfTime = false;
}

public void OnResetMatch()
{
    // Match cancelled or reset
    g_bMatchLive = false;
    g_bHalfTime = false;
}

public void OnResetHalf()
{
    // Half was reset - treat as halftime swap
    g_bHalfTime = true;
}

public void Warmod_OnMatchStart(const int[] players, int numPlayers)
{
    // WarMod Manager: match started
    g_bMatchLive = true;
    g_bHalfTime = false;
}

public void Warmod_OnMatchEnd(int winnerTeam, const int[] winPlayers, int numWinPlayers, const int[] loosePlayers, int numLoosePlayers)
{
    // WarMod Manager: match ended
    g_bMatchLive = false;
    g_bHalfTime = false;
}

// -------------------------------------------------------------------
// Master gate - strictly blocked by default
// -------------------------------------------------------------------
bool IsAllowedToShowDamage()
{
    // Warmup, knife duel, practice - not live
    if (!g_bMatchLive)
        return false;

    // Halftime swap - suppressed
    if (g_bHalfTime)
        return false;

    // Extra safety: check WarMod Manager natives if available
    if (GetFeatureStatus(FeatureType_Native, "Warmod_IsMatchLive") == FeatureStatus_Available)
    {
        if (!Warmod_IsMatchLive())
            return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "Warmod_IsHalfTime") == FeatureStatus_Available)
    {
        if (Warmod_IsHalfTime())
            return false;
    }

    return true;
}

// -------------------------------------------------------------------
// Damage tracking - only when allowed
// -------------------------------------------------------------------
public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsAllowedToShowDamage())
        return Plugin_Continue;

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int damage = event.GetInt("dmg_health");

    if (attacker > 0 && attacker <= MAXPLAYERS && victim > 0 && victim <= MAXPLAYERS && attacker != victim)
    {
        if (IsClientInGame(attacker) && IsClientInGame(victim) && GetClientTeam(attacker) != GetClientTeam(victim))
        {
            g_iDamageDealt[attacker][victim] += damage;
            g_iHitsDealt[attacker][victim]++;
        }
    }
    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsAllowedToShowDamage())
        return Plugin_Continue;

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (victim > 0 && victim <= MAXPLAYERS && IsClientInGame(victim) && !IsFakeClient(victim))
    {
        if (attacker > 0 && attacker <= MAXPLAYERS && IsClientInGame(attacker) && attacker != victim)
        {
            if (GetClientTeam(victim) != GetClientTeam(attacker))
            {
                DataPack pack;
                CreateDataTimer(0.1, Timer_ShowDeathDamage, pack);
                pack.WriteCell(victim);
                pack.WriteCell(attacker);
            }
        }
    }
    return Plugin_Continue;
}

public Action Timer_ShowDeathDamage(Handle timer, DataPack pack)
{
    if (g_bRoundEnded || !IsAllowedToShowDamage())
        return Plugin_Stop;

    pack.Reset();
    int victim = pack.ReadCell();
    int attacker = pack.ReadCell();

    if (victim <= 0 || victim > MAXPLAYERS || !IsClientInGame(victim) || IsFakeClient(victim))
        return Plugin_Stop;
    if (attacker <= 0 || attacker > MAXPLAYERS || !IsClientInGame(attacker))
        return Plugin_Stop;

    int dDealt = g_iDamageDealt[victim][attacker];
    int hDealt = g_iHitsDealt[victim][attacker];
    int dTaken = g_iDamageDealt[attacker][victim];
    int hTaken = g_iHitsDealt[attacker][victim];

    char enemyName[32];
    char enemyCol[16];
    GetClientName(attacker, enemyName, sizeof(enemyName));
    GetTeamColor(GetClientTeam(attacker), enemyCol, sizeof(enemyCol));

    int enemyHp = IsPlayerAlive(attacker) ? GetClientHealth(attacker) : 0;
    if (enemyHp < 0)
        enemyHp = 0;

    CPrintToChat(victim, "%s[%s%d %s/ %s%d %shits] to [%s%d %s/ %s%d %shits] - %s%s %s[%s%d%s HP]",
        g_sColW, g_sColLg, dDealt, g_sColW, g_sColLg, hDealt, g_sColW,
        g_sColLg, dTaken, g_sColW, g_sColLg, hTaken, g_sColW,
        enemyCol, enemyName, g_sColW, g_sColLg, enemyHp, g_sColW);

    return Plugin_Stop;
}

public void LoadDamageColors()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/warmod_damage_colors.cfg");

    KeyValues kv = new KeyValues("warmod_damage_colors");
    if (kv.ImportFromFile(path))
    {
        char tmp[32];
        if (kv.GetString("col_lg", tmp, sizeof(tmp)))
            strcopy(g_sColLg, sizeof(g_sColLg), tmp);
        else
            strcopy(g_sColLg, sizeof(g_sColLg), "{#90EE90}");

        if (kv.GetString("col_w", tmp, sizeof(tmp)))
            strcopy(g_sColW, sizeof(g_sColW), tmp);
        else
            strcopy(g_sColW, sizeof(g_sColW), "{#FFFFFF}");

        if (kv.GetString("col_t", tmp, sizeof(tmp)))
            strcopy(g_sColT, sizeof(g_sColT), tmp);
        else
            strcopy(g_sColT, sizeof(g_sColT), "{#FF4040}");

        if (kv.GetString("col_ct", tmp, sizeof(tmp)))
            strcopy(g_sColCT, sizeof(g_sColCT), tmp);
        else
            strcopy(g_sColCT, sizeof(g_sColCT), "{#4080FF}");
    }
    else
    {
        strcopy(g_sColLg, sizeof(g_sColLg), "{#90EE90}");
        strcopy(g_sColW, sizeof(g_sColW), "{#FFFFFF}");
        strcopy(g_sColT, sizeof(g_sColT), "{#FF4040}");
        strcopy(g_sColCT, sizeof(g_sColCT), "{#4080FF}");
    }
    delete kv;
}

public Action Command_ReloadDamageColors(int client, int args)
{
    LoadDamageColors();
    if (client > 0)
        PrintToChat(client, "[Warmod] Damage colors reloaded.");
    else
        PrintToServer("[Warmod] Damage colors reloaded.");
    return Plugin_Handled;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsAllowedToShowDamage())
        return Plugin_Continue;

    int winnerTeam = event.GetInt("winner");
    if (winnerTeam < 2)
        return Plugin_Continue;

    // Direct engine score-based halftime and match end lock (CS:S v34)
    int tScore = GetTeamScore(2);
    int ctScore = GetTeamScore(3);
    int totalRounds = tScore + ctScore;

    ConVar hMaxRounds = FindConVar("wm_max_rounds");
    int maxHalfRounds = (hMaxRounds != null) ? hMaxRounds.IntValue : 15;

    // 1. Halftime Detection (15 rounds reached in MR15) -> SUPPRESS DAMAGE!
    if (totalRounds == maxHalfRounds)
    {
        g_bHalfTime = true;
        return Plugin_Continue; // Do NOT start Timer_ShowDamage
    }

    // 2. Match End Detection (Team reached 16 rounds or all 30 rounds finished) -> SUPPRESS DAMAGE!
    if (tScore > maxHalfRounds || ctScore > maxHalfRounds || totalRounds >= (maxHalfRounds * 2))
    {
        g_bMatchLive = false;
        return Plugin_Continue; // Do NOT start Timer_ShowDamage
    }

    g_bRoundEnded = true;

    DataPack pack;
    CreateDataTimer(0.25, Timer_ShowDamage, pack);
    pack.WriteCell(winnerTeam);

    return Plugin_Continue;
}

public Action Timer_ShowDamage(Handle timer, DataPack pack)
{
    if (!IsAllowedToShowDamage())
        return Plugin_Stop;

    pack.Reset();
    int winnerTeam = pack.ReadCell();
    int loserTeam = (winnerTeam == 2) ? 3 : 2;

    for (int i = 1; i <= MAXPLAYERS; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != loserTeam)
            continue;

        for (int j = 1; j <= MAXPLAYERS; j++)
        {
            if (!IsClientInGame(j) || i == j || GetClientTeam(j) != winnerTeam)
                continue;

            int dDealt = g_iDamageDealt[i][j];
            int hDealt = g_iHitsDealt[i][j];
            int dTaken = g_iDamageDealt[j][i];
            int hTaken = g_iHitsDealt[j][i];

            char enemyName[32];
            char enemyCol[16];
            GetClientName(j, enemyName, sizeof(enemyName));
            GetTeamColor(GetClientTeam(j), enemyCol, sizeof(enemyCol));

            int enemyHp = IsPlayerAlive(j) ? GetClientHealth(j) : 0;
            if (enemyHp < 0)
                enemyHp = 0;

            CPrintToChat(i, "%s[%s%d %s/ %s%d %shits] to [%s%d %s/ %s%d %shits] - %s%s %s[%s%d%s HP]",
                g_sColW, g_sColLg, dDealt, g_sColW, g_sColLg, hDealt, g_sColW,
                g_sColLg, dTaken, g_sColW, g_sColLg, hTaken, g_sColW,
                enemyCol, enemyName, g_sColW, g_sColLg, enemyHp, g_sColW);
        }
    }
    return Plugin_Stop;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bRoundEnded = false;

    for (int i = 1; i <= MAXPLAYERS; i++)
    {
        for (int j = 1; j <= MAXPLAYERS; j++)
        {
            g_iDamageDealt[i][j] = 0;
            g_iHitsDealt[i][j] = 0;
        }
    }
    return Plugin_Continue;
}

void GetTeamColor(int team, char[] color, int maxlen)
{
    if (team == 2)
        strcopy(color, maxlen, g_sColT);
    else if (team == 3)
        strcopy(color, maxlen, g_sColCT);
    else
        strcopy(color, maxlen, g_sColW);
}
