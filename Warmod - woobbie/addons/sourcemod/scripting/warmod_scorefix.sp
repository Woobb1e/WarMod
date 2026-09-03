#pragma semicolon 1
#include <sourcemod>
#include <sdktools>

new g_iSavedKills[MAXPLAYERS + 1];
new g_iSavedDeaths[MAXPLAYERS + 1];
new bool:g_bPendingRestore = false;

public Plugin:myinfo = {
	name = "WarMod Scorefix",
	author = "Woobbie",
	description = "Fixes player / bot score wiping after LO3 restarts in CS:S v34",
	version = "1.0.0",
	url = ""
};

forward OnHalfTime();
forward OnLiveOn3();
forward OnResetMatch();

public OnHalfTime()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			g_iSavedKills[i] = GetEntProp(i, Prop_Data, "m_iFrags");
			g_iSavedDeaths[i] = GetEntProp(i, Prop_Data, "m_iDeaths");
		}
	}
	g_bPendingRestore = true;
}

public OnLiveOn3()
{
	if (g_bPendingRestore)
	{
		CreateTimer(5.0, Timer_RestoreScores, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:Timer_RestoreScores(Handle:timer)
{
	if (g_bPendingRestore)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				SetEntProp(i, Prop_Data, "m_iFrags", g_iSavedKills[i]);
				SetEntProp(i, Prop_Data, "m_iDeaths", g_iSavedDeaths[i]);
			}
		}
		g_bPendingRestore = false;
	}
	return Plugin_Stop;
}

public OnResetMatch()
{
	g_bPendingRestore = false;
	for (new i = 1; i <= MaxClients; i++)
	{
		g_iSavedKills[i] = 0;
		g_iSavedDeaths[i] = 0;
	}
}
