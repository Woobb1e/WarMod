#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <clientmod>
#include <clientmod/multicolors>

// Optional native bindings to WarMod Manager
native bool:Warmod_IsMatchLive();
native bool:Warmod_IsHalfTime();

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    MarkNativeAsOptional("Warmod_IsMatchLive");
    MarkNativeAsOptional("Warmod_IsHalfTime");
    return APLRes_Success;
}

// Damage and hit storage arrays
new g_iDamageDealt[MAXPLAYERS + 1][MAXPLAYERS + 1];
new g_iHitsDealt[MAXPLAYERS + 1][MAXPLAYERS + 1];

// Flag to prevent duplicate messages when the last player dies
new bool:g_bRoundEnded = false;

// Color variables (loaded from configs/warmod_damage_colors.cfg)
new String:g_sColLg[16];
new String:g_sColW[16];
new String:g_sColT[16];
new String:g_sColCT[16];

public Plugin:myinfo = {
    name = "Warmod damage info",
    author = "Woobbie",
    description = "Displays damage info only during live competitive matches",
    version = "2.9",
    url = "https://github.com/Woobb1e"
};

public OnPluginStart()
{
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("round_start", Event_RoundStart);

    // Load color configuration and register reload command
    LoadDamageColors();
    RegConsoleCmd("wm_reload_damage_colors", Command_ReloadDamageColors);
}

// Track damage and hit counts during the round (only if match is live)
public Action:Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsInWarmup()) return Plugin_Continue;

    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    new damage = GetEventInt(event, "dmg_health");

    if (attacker > 0 && attacker <= MaxClients && victim > 0 && victim <= MaxClients && attacker != victim)
    {
        if (GetClientTeam(attacker) != GetClientTeam(victim))
        {
            g_iDamageDealt[attacker][victim] += damage;
            g_iHitsDealt[attacker][victim]++;
        }
    }
    return Plugin_Continue;
}

// On player death: buffer the message to verify if the round ends
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsInWarmup()) return Plugin_Continue;

    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim) && !IsFakeClient(victim))
    {
        if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && attacker != victim)
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

// Timer to print death damage (aborts during warmup or if round ended)
public Action:Timer_ShowDeathDamage(Handle:timer, DataPack pack)
{
    if (g_bRoundEnded || IsInWarmup()) return Plugin_Stop;

    pack.Reset();
    new victim = pack.ReadCell();
    new attacker = pack.ReadCell();

    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim) && !IsFakeClient(victim))
    {
        if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
        {
            new d_Dealt = g_iDamageDealt[victim][attacker];
            new h_Dealt = g_iHitsDealt[victim][attacker];
            new d_Taken = g_iDamageDealt[attacker][victim];
            new h_Taken = g_iHitsDealt[attacker][victim];

            new String:sEnemyName[32], String:sEnemyCol[16];
            GetClientName(attacker, sEnemyName, sizeof(sEnemyName));
            GetTeamColor(GetClientTeam(attacker), sEnemyCol, sizeof(sEnemyCol));

            new iEnemyHp = IsPlayerAlive(attacker) ? GetEntProp(attacker, Prop_Send, "m_iHealth") : 0;
            if (iEnemyHp < 0) iEnemyHp = 0;

            CPrintToChat(victim, "%s[%s%d %s/ %s%d %shits] to [%s%d %s/ %s%d %shits] - %s%s %s[%s%d%s HP]",
                g_sColW, g_sColLg, d_Dealt, g_sColW, g_sColLg, h_Dealt, g_sColW, 
                g_sColLg, d_Taken, g_sColW, g_sColLg, h_Taken, g_sColW, 
                sEnemyCol, sEnemyName, g_sColW, g_sColLg, iEnemyHp, g_sColW);
        }
    }
    return Plugin_Stop;
}

// Load color config and reload command
public LoadDamageColors()
{
    decl String:path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/warmod_damage_colors.cfg");

    new Handle:kv = CreateKeyValues("warmod_damage_colors");
    if (FileToKeyValues(kv, path))
    {
        decl String:tmp[32];
        if (KvGetString(kv, "col_lg", tmp, sizeof(tmp))) strcopy(g_sColLg, sizeof(g_sColLg), tmp); else strcopy(g_sColLg, sizeof(g_sColLg), "{#90EE90}");
        if (KvGetString(kv, "col_w", tmp, sizeof(tmp))) strcopy(g_sColW, sizeof(g_sColW), tmp); else strcopy(g_sColW, sizeof(g_sColW), "{#FFFFFF}");
        if (KvGetString(kv, "col_t", tmp, sizeof(tmp))) strcopy(g_sColT, sizeof(g_sColT), tmp); else strcopy(g_sColT, sizeof(g_sColT), "{#FF4040}");
        if (KvGetString(kv, "col_ct", tmp, sizeof(tmp))) strcopy(g_sColCT, sizeof(g_sColCT), tmp); else strcopy(g_sColCT, sizeof(g_sColCT), "{#4080FF}");
        CloseHandle(kv);
    }
    else
    {
        strcopy(g_sColLg, sizeof(g_sColLg), "{#90EE90}");
        strcopy(g_sColW, sizeof(g_sColW), "{#FFFFFF}");
        strcopy(g_sColT, sizeof(g_sColT), "{#FF4040}");
        strcopy(g_sColCT, sizeof(g_sColCT), "{#4080FF}");
    }
}

public Action:Command_ReloadDamageColors(client, args)
{
    LoadDamageColors();
    if (client > 0) PrintToChat(client, "[Warmod] Damage colors reloaded.");
    else PrintToServer("[Warmod] Damage colors reloaded.");
    return Plugin_Handled;
}

// At round end: set flag and schedule losing team breakdown
public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsInWarmup()) return Plugin_Continue;

    new winnerTeam = GetEventInt(event, "winner");
    if (winnerTeam < 2) return Plugin_Continue;

    g_bRoundEnded = true;

    DataPack pack;
    CreateDataTimer(0.25, Timer_ShowDamage, pack);
    pack.WriteCell(winnerTeam);
    
    return Plugin_Continue;
}

// Display full opposing team breakdown individually to each losing player
public Action:Timer_ShowDamage(Handle:timer, DataPack pack)
{
    if (IsInWarmup()) return Plugin_Stop;

    pack.Reset();
    new winnerTeam = pack.ReadCell();
    new loserTeam = (winnerTeam == 2) ? 3 : 2;

    for (new i = 1; i <= MaxClients; i++)
    {
        // Filter: Losing team members only
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != loserTeam) continue;

        for (new j = 1; j <= MaxClients; j++)
        {
            // Display all players on the winning team
            if (!IsClientInGame(j) || i == j || GetClientTeam(j) != winnerTeam) continue;

            new d_Dealt = g_iDamageDealt[i][j];
            new h_Dealt = g_iHitsDealt[i][j];
            new d_Taken = g_iDamageDealt[j][i];
            new h_Taken = g_iHitsDealt[j][i];

            new String:sEnemyName[32], String:sEnemyCol[16];
            GetClientName(j, sEnemyName, sizeof(sEnemyName));
            GetTeamColor(GetClientTeam(j), sEnemyCol, sizeof(sEnemyCol));

            new iEnemyHp = IsPlayerAlive(j) ? GetEntProp(j, Prop_Send, "m_iHealth") : 0;
            if (iEnemyHp < 0) iEnemyHp = 0;

            // Send personalized report to client 'i'
            CPrintToChat(i, "%s[%s%d %s/ %s%d %shits] to [%s%d %s/ %s%d %shits] - %s%s %s[%s%d%s HP]",
                g_sColW, g_sColLg, d_Dealt, g_sColW, g_sColLg, h_Dealt, g_sColW, 
                g_sColLg, d_Taken, g_sColW, g_sColLg, h_Taken, g_sColW, 
                sEnemyCol, sEnemyName, g_sColW, g_sColLg, iEnemyHp, g_sColW);
        }
    }
    return Plugin_Handled;
}

// Reset stats at the beginning of each round
public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    g_bRoundEnded = false;

    for (new i = 1; i <= MaxClients; i++)
    {
        for (new j = 1; j <= MaxClients; j++)
        {
            g_iDamageDealt[i][j] = 0;
            g_iHitsDealt[i][j] = 0;
        }
    }
    return Plugin_Continue;
}

// Precise check for CS:S v34 WarMod: Only live competitive rounds are NOT warmup
bool:IsInWarmup()
{
    // 1. Check WarMod Manager: If match is NOT live, it is Warmup!
    if (GetFeatureStatus(FeatureType_Native, "Warmod_IsMatchLive") == FeatureStatus_Available)
    {
        if (!Warmod_IsMatchLive())
            return true;
    }

    // 2. Check WarMod Manager: If currently in Halftime, treat as warmup (suppress damage)
    if (GetFeatureStatus(FeatureType_Native, "Warmod_IsHalfTime") == FeatureStatus_Available)
    {
        if (Warmod_IsHalfTime())
            return true;
    }

    // 3. Fallback check on WarMod core ConVar
    new Handle:hWmActive = FindConVar("wm_active");
    if (hWmActive != INVALID_HANDLE && !GetConVarBool(hWmActive))
    {
        return true;
    }

    return false;
}

stock GetTeamColor(team, String:color[], maxlen)
{
    if (team == 2) strcopy(color, maxlen, g_sColT);
    else if (team == 3) strcopy(color, maxlen, g_sColCT);
    else strcopy(color, maxlen, g_sColW);
}
