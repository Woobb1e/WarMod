#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

// =========================================================================
// Definitions & Constants
// =========================================================================
#define PLUGIN_VERSION      "1.2.6"
#define WM_STATUS_LIVE_1    5
#define WM_STATUS_LIVE_2    8
#define WM_STATUS_OT_MIN    11

enum HostnameState {
    STATE_WARMUP,
    STATE_LIVE,
    STATE_HALFTIME,
    STATE_OVERTIME,
    STATE_END
}

// =========================================================================
// Global Variables (Handles, Booleans, Strings)
// =========================================================================
ConVar g_cvHostnameInfo;
ConVar g_cvMaxPlayers;
ConVar g_cvHostname;
ConVar g_cvWarModStatus;

bool   g_bEnabled;
bool   g_bIsUpdating;

char   g_sBaseHostname[256];
char   g_sLastHostname[256];

HostnameState g_CurrentState;

// =========================================================================
// Plugin Information
// =========================================================================
public Plugin myinfo = {
    name        = "WarMod Manager - Hostname",
    author      = "Woobbie",
    description = "Dynamic server hostname for WarMod match states",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/Woobb1e"
};

// =========================================================================
// Standard Callbacks (Plugin Start/End, Map Start)
// =========================================================================
public void OnPluginStart() {
    LoadTranslations("warmod_manager/hostname");

    g_cvHostnameInfo = CreateConVar("wm_hostname_info", "1", "Enable/disable dynamic hostname", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvHostname     = FindConVar("hostname");
    g_cvMaxPlayers   = FindConVar("wm_max_players");
    g_cvWarModStatus = FindConVar("wm_status");

    g_bEnabled = g_cvHostnameInfo.BoolValue;

    if (g_cvHostname != null) {
        g_cvHostname.GetString(g_sBaseHostname, sizeof(g_sBaseHostname));
        g_cvHostname.AddChangeHook(OnHostnameConVarChanged);
    }

    g_cvHostnameInfo.AddChangeHook(OnPluginEnableChanged);
    g_cvMaxPlayers.AddChangeHook(OnMaxPlayersChanged);

    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end",   Event_RoundEnd);
}

public void OnMapStart() {
    g_CurrentState = STATE_WARMUP;
    RequestHostnameUpdate();
}

public void OnPluginEnd() {
    if (g_bEnabled && g_cvHostname != null) {
        g_cvHostname.SetString(g_sBaseHostname);
    }
}

// =========================================================================
// Client Connection Callbacks
// =========================================================================
public void OnClientPutInServer(int client) {
    RequestHostnameUpdate();
}

public void OnClientDisconnect(int client) {
    RequestHostnameUpdate();
}

// =========================================================================
// WarMod Specific Callbacks (Forwards)
// =========================================================================
public void OnLiveOn3() {
    g_CurrentState = STATE_LIVE;
    RequestHostnameUpdate();
}

public void OnHalfTime() {
    g_CurrentState = STATE_HALFTIME;
    RequestHostnameUpdate();
}

public void OnEndMatch() {
    CreateTimer(3.0, Timer_SetMatchEndState, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnResetMatch() {
    g_CurrentState = STATE_WARMUP;
    RequestHostnameUpdate();
}

// =========================================================================
// Timers & Event Handlers
// =========================================================================
public Action Timer_SetMatchEndState(Handle timer) {
    g_CurrentState = STATE_END;
    RequestHostnameUpdate();
    return Plugin_Stop;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    if (g_CurrentState == STATE_END) {
        g_CurrentState = STATE_WARMUP;
    }
    RequestHostnameUpdate();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    RequestHostnameUpdate();
}

// =========================================================================
// ConVar Change Handlers
// =========================================================================
public void OnPluginEnableChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    g_bEnabled = convar.BoolValue;
    if (!g_bEnabled && g_cvHostname != null) {
        g_cvHostname.SetString(g_sBaseHostname);
    } else {
        RequestHostnameUpdate();
    }
}

public void OnHostnameConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (g_bIsUpdating) return;
    strcopy(g_sBaseHostname, sizeof(g_sBaseHostname), newValue);
    RequestHostnameUpdate();
}

public void OnMaxPlayersChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    // Discipline changed (5v5/2v2/1v1) -> refresh [Waiting: N] instantly
    RequestHostnameUpdate();
}

// =========================================================================
// Core Logic Functions (The Engines)
// =========================================================================
int GetRealPlayerCount() {
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            count++;
        }
    }
    return count;
}

void RequestHostnameUpdate() {
    if (!g_bEnabled || g_cvHostname == null) return;

    char suffix[128];
    char scoreFormat[32];
    int currentStatus = (g_cvWarModStatus != null) ? g_cvWarModStatus.IntValue : 0;

    switch (g_CurrentState) {
        case STATE_WARMUP: {
            int count    = GetRealPlayerCount();
            int required = (g_cvMaxPlayers != null) ? g_cvMaxPlayers.IntValue : 10;
            int needed   = required - count;
            if (needed < 0) {
                needed = 0;
            }
            if (count >= required)
                Format(suffix, sizeof(suffix), " %T", "Hostname_Full", LANG_SERVER);
            else
                Format(suffix, sizeof(suffix), " %T", "Hostname_Waiting", LANG_SERVER, needed);
        }
        case STATE_LIVE: {
            int tScore = GetTeamScore(2);
            int ctScore = GetTeamScore(3);
            Format(scoreFormat, sizeof(scoreFormat), "%T", "Hostname_Score", LANG_SERVER, tScore, ctScore);
            if (currentStatus >= WM_STATUS_OT_MIN)
                Format(suffix, sizeof(suffix), " %T %s", "Hostname_Overtime", LANG_SERVER, scoreFormat);
            else
                Format(suffix, sizeof(suffix), " %s", scoreFormat);
        }
        case STATE_HALFTIME: {
            Format(suffix, sizeof(suffix), " %T", "Hostname_HalfTime", LANG_SERVER);
        }
        case STATE_END: {
            Format(suffix, sizeof(suffix), " %T", "Hostname_End", LANG_SERVER);
        }
        default: {
            int needed = ((g_cvMaxPlayers != null) ? g_cvMaxPlayers.IntValue : 10) - GetRealPlayerCount();
            if (needed < 0) {
                needed = 0;
            }
            Format(suffix, sizeof(suffix), " %T", "Hostname_Waiting", LANG_SERVER, needed);
        }
    }

    char finalHostname[512];
    Format(finalHostname, sizeof(finalHostname), "%s%s", g_sBaseHostname, suffix);

    if (!StrEqual(finalHostname, g_sLastHostname, false)) {
        g_bIsUpdating = true;
        g_cvHostname.SetString(finalHostname);
        g_bIsUpdating = false;
        strcopy(g_sLastHostname, sizeof(g_sLastHostname), finalHostname);
    }
}
