#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <clientmod>
#include <clientmod/multicolors>

// Damage statistics storage arrays
new g_iDamageDealt[MAXPLAYERS + 1][MAXPLAYERS + 1];
new g_iHitsDealt[MAXPLAYERS + 1][MAXPLAYERS + 1];

// HEX color definitions for ClientMod
#define COL_LG "{#90EE90}"  // Light green (for numbers)
#define COL_W  "{#FFFFFF}"  // White (for text)
#define COL_T  "{#FF4040}"  // Red (Terrorist)
#define COL_CT "{#4080FF}"  // Blue (Counter-Terrorist)

public Plugin:myinfo = {
	name = "Warmod damage info",
	author = "Woobbie",
	description = "",
	version = "2.0",
	url = ""
};

public OnPluginStart()
{
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("round_start", Event_RoundStart);
}

// Track damage during the round
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

// At round end
public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (IsInWarmup()) return Plugin_Continue;

	new winnerTeam = GetEventInt(event, "winner");
	
	// If no team won (draw or round cancellation) don't show anything
	if (winnerTeam < 2) return Plugin_Continue;

	// Pass winning team number to timer
	DataPack pack;
	CreateDataTimer(0.1, Timer_ShowDamage, pack);
	pack.WriteCell(winnerTeam);
	
	return Plugin_Continue;
}

public Action:Timer_ShowDamage(Handle:timer, DataPack pack)
{
	pack.Reset();
	new winnerTeam = pack.ReadCell();
	new loserTeam = (winnerTeam == 2) ? 3 : 2; // If Terrorists won, loser is CT and vice versa

	for (new i = 1; i <= MaxClients; i++)
	{
		// Primary filter: client must be in-game, not a bot, and only from the losing team
		if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != loserTeam) continue;

		for (new j = 1; j <= MaxClients; j++)
		{
			if (!IsClientInGame(j) || i == j) continue;

			// Show engagements with players from the winning team
			if (g_iDamageDealt[i][j] > 0 || g_iDamageDealt[j][i] > 0)
			{
				new d_Dealt = g_iDamageDealt[i][j];
				new h_Dealt = g_iHitsDealt[i][j];
				new d_Taken = g_iDamageDealt[j][i];
				new h_Taken = g_iHitsDealt[j][i];

				new String:sEnemyName[32], String:sEnemyCol[16];
				GetClientName(j, sEnemyName, sizeof(sEnemyName));
				GetTeamColor(GetClientTeam(j), sEnemyCol, sizeof(sEnemyCol));

				new iEnemyHp = IsPlayerAlive(j) ? GetEntProp(j, Prop_Send, "m_iHealth") : 0;
				if (iEnemyHp < 0) iEnemyHp = 0;

				// Send message to losing player only
				CPrintToChat(i, "%s[%s%d %s/ %s%d %shits] to [%s%d %s/ %s%d %shits] - %s%s %s[%s%d%s HP]",
					COL_W, COL_LG, d_Dealt, COL_W, COL_LG, h_Dealt, COL_W, 
					COL_LG, d_Taken, COL_W, COL_LG, h_Taken, COL_W, 
					sEnemyCol, sEnemyName, COL_W, COL_LG, iEnemyHp, COL_W);
			}
		}
	}
	return Plugin_Handled;
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
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

bool:IsInWarmup()
{
	new Handle:hWarmup = FindConVar("mp_warmup_period");
	if (hWarmup != INVALID_HANDLE && GetConVarInt(hWarmup) > 0)
		return true;

	new Handle:hDoWarmup = FindConVar("mp_do_warmup");
	if (hDoWarmup != INVALID_HANDLE && GetConVarBool(hDoWarmup))
		return true;

	return false;
}

stock GetTeamColor(team, String:color[], maxlen)
{
	if (team == 2) strcopy(color, maxlen, COL_T);
	else if (team == 3) strcopy(color, maxlen, COL_CT);
	else strcopy(color, maxlen, COL_W);
}
