// =========================================================================
// Definitions & Constants
// =========================================================================

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

#define PLUGIN_VERSION  "1.2.6"
#define MODE_WARMOD     0
#define MODE_MIX        1
#define DISC_5V5        0
#define DISC_2V2        1
#define DISC_1V1        2
#define ROUNDS_15       0
#define ROUNDS_12       1
#define ROUNDS_9        2
#define ROUNDS_6        3

// =========================================================================
// Global Variables
// =========================================================================

int     g_iMode;
int     g_iDiscipline;
int     g_iRounds;

char    g_sConfigPath[PLATFORM_MAX_PATH];


// =========================================================================
// Plugin Information
// =========================================================================

public Plugin myinfo = {
    name        = "WarMod Manager - Menu",
    author      = "Woobbie",
    description = "Match type menu for WarMod",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/Woobb1e"
};

// =========================================================================
// Standard Callbacks (Plugin Start)
// =========================================================================

public void OnPluginStart() {
    LoadTranslations("warmod_manager/menus");

    BuildConfigPath();
    LoadSettings();

    RegAdminCmd("sm_warmix", Cmd_Warmix, ADMFLAG_CUSTOM1, "Open WarMod Manager menu");
    RegConsoleCmd("warmix", Cmd_Warmix, "Open WarMod Manager menu");
    RegAdminCmd("sm_warmix_mode", Cmd_AdminMode, ADMFLAG_CUSTOM1, "Set match mode (0=WarMod, 1=Mix)");
    RegAdminCmd("sm_warmix_disc", Cmd_AdminDiscipline, ADMFLAG_CUSTOM1, "Set discipline (0=5v5, 1=2v2, 2=1v1)");
    RegAdminCmd("sm_warmix_rounds", Cmd_AdminRounds, ADMFLAG_CUSTOM1, "Set rounds (0=MR15, 1=MR12, 2=MR9, 3=MR6)");
    RegAdminCmd("sm_warmix_loadcfg", Cmd_ReloadConfig, ADMFLAG_CUSTOM1, "Reload settings from config file");
    RegAdminCmd("sm_warmix_save", Cmd_SaveConfig, ADMFLAG_CUSTOM1, "Save current settings to config file");
    RegAdminCmd("sm_warmix_status", Cmd_ShowStatus, ADMFLAG_CUSTOM1, "Show current saved settings");
}

// =========================================================================
// Commands (!warmix - Admin Only)
// =========================================================================

public Action Cmd_Warmix(int client, int args) {
    if (!IsValidClient(client)) {
        return Plugin_Handled;
    }
    if (!CheckCommandAccess(client, "sm_warmix", ADMFLAG_CUSTOM1, true)) {
        ReplyToCommand(client, "%t", "No_Permission");
        return Plugin_Handled;
    }
    ShowMainMenu(client);
    return Plugin_Handled;
}

// =========================================================================
// Menu Functions (Main Menu Display)
// =========================================================================

void ShowMainMenu(int client) {
    Menu menu = new Menu(MainMenuHandler, MENU_ACTIONS_ALL);

    char sTitle[128];
    Format(sTitle, sizeof(sTitle), "%T", "Menu_Title", client);
    menu.SetTitle(sTitle);
    menu.ExitButton = true;

    char sItem[64];
    char sValue[32];

    if (g_iMode == MODE_WARMOD)
        Format(sValue, sizeof(sValue), "%T", "Menu_Mode_WarMod", client);
    else
        Format(sValue, sizeof(sValue), "%T", "Menu_Mode_Mix", client);
    Format(sItem, sizeof(sItem), "%T: %s", "Menu_Mode", client, sValue);
    menu.AddItem("mode", sItem);

    if (g_iDiscipline == DISC_5V5)
        Format(sValue, sizeof(sValue), "5v5");
    else if (g_iDiscipline == DISC_2V2)
        Format(sValue, sizeof(sValue), "2v2");
    else
        Format(sValue, sizeof(sValue), "1v1");
    Format(sItem, sizeof(sItem), "%T: %s", "Menu_Discipline", client, sValue);
    menu.AddItem("discipline", sItem);

    if (g_iRounds == ROUNDS_15)
        Format(sValue, sizeof(sValue), "15");
    else if (g_iRounds == ROUNDS_12)
        Format(sValue, sizeof(sValue), "12");
    else if (g_iRounds == ROUNDS_9)
        Format(sValue, sizeof(sValue), "9");
    else
        Format(sValue, sizeof(sValue), "6");
    Format(sItem, sizeof(sItem), "%T: %s", "Menu_Rounds", client, sValue);
    menu.AddItem("rounds", sItem);

    Format(sValue, sizeof(sValue), "%T", "Menu_StartListen", client);
    menu.AddItem("listen", sValue);

    menu.Display(client, 30);
}

// =========================================================================
// Menu Handler (Selection Cycling & Start Listen)
// =========================================================================

public int MainMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
    switch (action) {
        case MenuAction_Select: {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));

            if (StrEqual(info, "mode")) {
                g_iMode = (g_iMode + 1) % 2;
                SaveSettings();
            } else if (StrEqual(info, "discipline")) {
                g_iDiscipline = (g_iDiscipline + 1) % 3;
                SaveSettings();

                // Apply player requirements immediately so the hostname
                // [Waiting: N] tracks the selected discipline (5v5/2v2/1v1)
                int iPlayers = (g_iDiscipline == DISC_5V5) ? 10 : ((g_iDiscipline == DISC_2V2) ? 4 : 2);
                ServerCommand("wm_max_players %d", iPlayers);
                ServerCommand("wm_min_ready %d", iPlayers);
            } else if (StrEqual(info, "rounds")) {
                g_iRounds = (g_iRounds + 1) % 4;
                SaveSettings();
            } else if (StrEqual(info, "listen")) {
                CreateTimer(0.1, Timer_ApplyAndRestart, GetClientUserId(param1), TIMER_FLAG_NO_MAPCHANGE);
                return 0;   // hide menu - no redraw
            }
            ShowMainMenu(param1);
        }
        case MenuAction_End: {
            delete menu;
        }
    }
    return 0;
}

// =========================================================================
// Timers (Apply Settings & Restart Match)
// =========================================================================

public Action Timer_ApplyAndRestart(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client)) {
        return Plugin_Stop;
    }

    char sConfigFile[64];
    int iRounds = 0;
    int iPlayers = 0;

    if (g_iRounds == ROUNDS_15) {
        iRounds = 15;
        Format(sConfigFile, sizeof(sConfigFile), "warmod/ruleset_mr15.cfg");
    } else if (g_iRounds == ROUNDS_12) {
        iRounds = 12;
        Format(sConfigFile, sizeof(sConfigFile), "warmod/ruleset_mr12.cfg");
    } else if (g_iRounds == ROUNDS_9) {
        iRounds = 9;
        Format(sConfigFile, sizeof(sConfigFile), "warmod/ruleset_mr9.cfg");
    } else {
        iRounds = 6;
        Format(sConfigFile, sizeof(sConfigFile), "warmod/ruleset_mr6.cfg");
    }

    if (g_iDiscipline == DISC_5V5)
        iPlayers = 10;
    else if (g_iDiscipline == DISC_2V2)
        iPlayers = 4;
    else
        iPlayers = 2;

    ServerCommand("wm_match_config %s", sConfigFile);
    ServerCommand("exec %s", sConfigFile);
    ServerCommand("wm_max_rounds %d", iRounds);
    ServerCommand("wm_max_players %d", iPlayers);
    ServerCommand("wm_min_ready %d", iPlayers);
    ServerCommand("mp_restartgame 1");

    char sMode[16];
    if (g_iMode == MODE_WARMOD)
        strcopy(sMode, sizeof(sMode), "WarMod");
    else
        strcopy(sMode, sizeof(sMode), "Mix");

    // Per-team discipline label (e.g. "5v5", "2v2", "1v1")
    char sDiscipline[8];
    if (g_iDiscipline == DISC_5V5)
        strcopy(sDiscipline, sizeof(sDiscipline), "5v5");
    else if (g_iDiscipline == DISC_2V2)
        strcopy(sDiscipline, sizeof(sDiscipline), "2v2");
    else
        strcopy(sDiscipline, sizeof(sDiscipline), "1v1");

    PrintToChat(client, "\x04<\x01WarMod\x04>\x01 %T", "Menu_Applied", client, sMode, sDiscipline, iRounds);
    return Plugin_Stop;
}

// =========================================================================
// Config File (Load / Save Settings)
// =========================================================================

void BuildConfigPath() {
    BuildPath(Path_SM, g_sConfigPath, sizeof(g_sConfigPath), "configs/warmod_manager/menu_settings.cfg");

    // Ensure the directory exists before writing
    char sDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sDir, sizeof(sDir), "configs/warmod_manager");
    if (!DirExists(sDir)) {
        CreateDirectory(sDir, 511);
    }
}

void LoadSettings() {
    KeyValues kv = new KeyValues("WarModManager");

    if (!kv.ImportFromFile(g_sConfigPath)) {
        // File missing -> create it with current defaults
        SaveSettings();
    } else {
        g_iMode       = kv.GetNum("mode",       MODE_WARMOD);
        g_iDiscipline = kv.GetNum("discipline", DISC_5V5);
        g_iRounds     = kv.GetNum("rounds",     ROUNDS_15);

        // Clamp to valid ranges so a bad cfg can't break the menu
        if (g_iMode < 0 || g_iMode > 1)
            g_iMode = MODE_WARMOD;
        if (g_iDiscipline < 0 || g_iDiscipline > 2)
            g_iDiscipline = DISC_5V5;
        if (g_iRounds < 0 || g_iRounds > 3)
            g_iRounds = ROUNDS_15;
    }

    delete kv;
}

void SaveSettings() {
    KeyValues kv = new KeyValues("WarModManager");
    kv.SetNum("mode",       g_iMode);
    kv.SetNum("discipline", g_iDiscipline);
    kv.SetNum("rounds",     g_iRounds);
    kv.ExportToFile(g_sConfigPath);
    delete kv;
}

// =========================================================================
// Admin Console Commands (Direct Settings Control)
// =========================================================================

public Action Cmd_AdminMode(int client, int args) {
    if (args < 1) {
        ReplyToCommand(client, "Usage: sm_warmix_mode <0|1>  (0 = WarMod, 1 = Mix)");
        return Plugin_Handled;
    }

    char sArg[8];
    GetCmdArg(1, sArg, sizeof(sArg));
    int iValue = StringToInt(sArg);

    if (iValue < 0 || iValue > 1) {
        ReplyToCommand(client, "Invalid mode. Use 0 (WarMod) or 1 (Mix).");
        return Plugin_Handled;
    }

    g_iMode = iValue;
    SaveSettings();
    ReplyToCommand(client, "[WarMod Manager] Mode set to %s (saved).", (iValue == MODE_WARMOD) ? "WarMod" : "Mix");
    return Plugin_Handled;
}

public Action Cmd_AdminDiscipline(int client, int args) {
    if (args < 1) {
        ReplyToCommand(client, "Usage: sm_warmix_disc <0|1|2>  (0 = 5v5, 1 = 2v2, 2 = 1v1)");
        return Plugin_Handled;
    }

    char sArg[8];
    GetCmdArg(1, sArg, sizeof(sArg));
    int iValue = StringToInt(sArg);

    if (iValue < 0 || iValue > 2) {
        ReplyToCommand(client, "Invalid discipline. Use 0 (5v5), 1 (2v2) or 2 (1v1).");
        return Plugin_Handled;
    }

    g_iDiscipline = iValue;

    // Apply player requirements immediately so the hostname tracks it too
    int iPlayers = (g_iDiscipline == DISC_5V5) ? 10 : ((g_iDiscipline == DISC_2V2) ? 4 : 2);
    ServerCommand("wm_max_players %d", iPlayers);
    ServerCommand("wm_min_ready %d", iPlayers);

    SaveSettings();
    ReplyToCommand(client, "[WarMod Manager] Discipline set to %dv%d (saved).", iPlayers / 2, iPlayers / 2);
    return Plugin_Handled;
}

public Action Cmd_AdminRounds(int client, int args) {
    if (args < 1) {
        ReplyToCommand(client, "Usage: sm_warmix_rounds <0|1|2|3>  (0 = MR15, 1 = MR12, 2 = MR9, 3 = MR6)");
        return Plugin_Handled;
    }

    char sArg[8];
    GetCmdArg(1, sArg, sizeof(sArg));
    int iValue = StringToInt(sArg);

    if (iValue < 0 || iValue > 3) {
        ReplyToCommand(client, "Invalid rounds. Use 0 (MR15), 1 (MR12), 2 (MR9) or 3 (MR6).");
        return Plugin_Handled;
    }

    g_iRounds = iValue;
    SaveSettings();

    int iRnd = (iValue == ROUNDS_15) ? 15 : (iValue == ROUNDS_12) ? 12 : (iValue == ROUNDS_9) ? 9 : 6;
    ReplyToCommand(client, "[WarMod Manager] Rounds set to MR%d (saved).", iRnd);
    return Plugin_Handled;
}

public Action Cmd_ReloadConfig(int client, int args) {
    LoadSettings();
    ReplyToCommand(client, "[WarMod Manager] Settings reloaded from config file.");
    return Plugin_Handled;
}

public Action Cmd_SaveConfig(int client, int args) {
    SaveSettings();
    ReplyToCommand(client, "[WarMod Manager] Current settings saved to config file.");
    return Plugin_Handled;
}

public Action Cmd_ShowStatus(int client, int args) {
    char sMode[16];
    strcopy(sMode, sizeof(sMode), (g_iMode == MODE_WARMOD) ? "WarMod" : "Mix");

    char sDisc[8];
    strcopy(sDisc, sizeof(sDisc), (g_iDiscipline == DISC_5V5) ? "5v5" : (g_iDiscipline == DISC_2V2) ? "2v2" : "1v1");

    int iRnd = (g_iRounds == ROUNDS_15) ? 15 : (g_iRounds == ROUNDS_12) ? 12 : (g_iRounds == ROUNDS_9) ? 9 : 6;

    ReplyToCommand(client, "[WarMod Manager] Mode: %s | Discipline: %s | Rounds: MR%d", sMode, sDisc, iRnd);
    return Plugin_Handled;
}

// =========================================================================
// Helper Functions
// =========================================================================

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}