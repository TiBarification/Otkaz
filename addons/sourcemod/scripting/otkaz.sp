#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <updater>
#tryinclude <jail_control>
#tryinclude <tf2jail>
#tryinclude <warden>
#tryinclude <jwp>

#pragma semicolon 1
//Force 1.7 syntax
#pragma newdecls required

#define PLUGIN_VERSION "1.3.8"
#define PREFIX "\x01[\x03Отказ\x01]\x03 "
#define MAX_REASON_SIZE 85
#define DEBUG 0
#define UPDATE_URL "http://updater.tibari.ru/otkaz/updatefile.txt"

ConVar g_hEnabled;

Menu g_hMenu;
Menu g_hCmdMenu;
Panel OtkazStatusPanel;

bool g_bEnabled;
bool g_bBlockotkaz[MAXPLAYERS+1] = false;

//PLUGINS BOOL's
bool g_bWarden, g_bJailControl, g_bTF2Jail, g_bWardenPro;

int g_iRoundUse;
int g_iRoundUsed[MAXPLAYERS+1];
int g_iMenuTime;
int g_iNumCmds;

int g_iGlobTime;

char ConfigPath[36] = "addons/sourcemod/configs/otkaz.txt";
char g_cChatCmds[16][32];
char g_cColor[4][4];

enum State
{
	ConfigStateNone = 0,
	ConfigStateConfig,
	ConfigStateReasons
}

enum Target
{
	INDEX
}

int g_iTarget[MAXPLAYERS+1][Target];

ArrayList g_aClients, g_aNames, g_aReasons, g_aTimes;
// This is config state. DON'T TOUCH!
State ConfigState;

public Plugin myinfo =
{
	name = "JailBreak Otkaz",
	description = "Command for T, that allow to abort commands comander.",
	author = "White Wolf",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/doctor_white"
};

public void OnPluginStart()
{
	CreateConVar("sm_otkaz_version", PLUGIN_VERSION, "Version of Otkaz", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_DONTRECORD);
	g_hEnabled = CreateConVar("sm_otkaz_enabled", "1", "Включение/Выключение плагина.", FCVAR_PLUGIN|FCVAR_REPLICATED, true, 0.0, true, 1.0);
	
	g_hEnabled.AddChangeHook(OnCvarChange);
	
	g_aClients = new ArrayList(MaxClients+1);
	g_aNames = new ArrayList(MAX_NAME_LENGTH);
	g_aReasons = new ArrayList(85);
	g_aTimes = new ArrayList(48);
	
	if (GetEngineVersion() == Engine_CSGO || GetEngineVersion() == Engine_CSS)
		HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	else if (GetEngineVersion() == Engine_TF2)
		HookEvent("teamplay_round_start", OnRoundStart, EventHookMode_PostNoCopy);
	
	g_bEnabled = true;
	
	RegConsoleCmd("sm_wotkaz", Command_OtkazView, "View otkaz menu");
	
	PrintToServer("Engine Version : %d |Plugin Version: %s", GetEngineVersion(), PLUGIN_VERSION);
	
	CreateCustomCfg(ConfigPath);
	
	LoadTranslations("otkaz.phrases");
	
	
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnConfigsExecuted()
{
	g_bEnabled = g_hEnabled.BoolValue;
}

public void OnCvarChange(ConVar cvar, const char[] oldValue, const char[] newValue)
{
	if (cvar == g_hEnabled)
	{
		if (g_bEnabled != cvar.BoolValue)
			g_bEnabled = cvar.BoolValue;
	}
}

public void OnAllPluginsLoaded()
{
	g_bWarden = LibraryExists("warden");
	g_bJailControl = LibraryExists("jail_control");
	g_bTF2Jail = LibraryExists("tf2jail");
	g_bWardenPro = LibraryExists("jwp");
}

public void OnLibraryAdded(const char[] name)
{
	g_bWarden = StrEqual(name, "warden");
	g_bJailControl = StrEqual(name, "jail_control");
	g_bTF2Jail = StrEqual(name, "tf2jail");
	g_bWardenPro = StrEqual(name, "jwp");
	
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public int Updater_OnPluginUpdated()
{
	LogMessage("Plugin updated. Old version %s. Now reloading...");
	ReloadPlugin();
}

public void OnLibraryRemoved(const char[] name)
{
	g_bWarden = StrEqual(name, "warden");
	g_bJailControl = StrEqual(name, "jail_control");
	g_bTF2Jail = StrEqual(name, "tf2jail");
	g_bWardenPro = StrEqual(name, "jwp");
}

public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iRoundUsed[i] = 0;
		g_bBlockotkaz[i] = false;
		//If exists then
		Clear_OtkazHistory();
		g_iGlobTime = GetTime();
	}
}

public void OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return;
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
	
	RemoveClientFromMenu(iClient);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(!g_bEnabled)
		return Plugin_Stop;
	
	if(client && IsClientInGame(client))
	{
		if (!g_iNumCmds) PrintToChat(client, "%s%t", PREFIX, "Otkaz Commands Error");
		else
		{
			for (int i = 0; i < g_iNumCmds; i++)
			{
				if (StrEqual(sArgs, g_cChatCmds[i], true)) // If !Otkaz and !otkaz different items we set 3 argument to true
				{
					if(GetClientTeam(client) == 2)
					{
						if(IsPlayerAlive(client))
						{
							if (g_bBlockotkaz[client])
							{
								OtkazStatusPanel.Send(client, OtkazStatusPanel_Handler, MENU_TIME_FOREVER);
								return Plugin_Stop;
							}
							else if (g_iRoundUse && g_iRoundUsed[client] >= g_iRoundUse)
							{
								PrintToChat(client, "%s%t", PREFIX, "Round Use", g_iRoundUse);
								return Plugin_Stop;
							}
							else if (!g_iMenuTime)
								g_hMenu.Display(client, MENU_TIME_FOREVER);
							else
								g_hMenu.Display(client, g_iMenuTime);
						}
						else
						{
							PrintToChat(client, "%s%t", PREFIX, "Must be Alive");
							return Plugin_Stop;
						}
					}
					else
					{
						PrintToChat(client, "%s%t", PREFIX, "Only Prisoner");
						return Plugin_Stop;
					}
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Command_OtkazView(int client, int args)
{
	if (!IsFakeClient(client) && IsClientInGame(client) && g_bEnabled)
	{
		if (!g_iNumCmds) PrintToChat(client, "%s%t", PREFIX, "Otkaz Commands Error");
		else if (GetEngineVersion() == Engine_CSS || GetEngineVersion() == Engine_CSGO)
		{
			#if DEBUG
				PrintToChatAll("g_bJailControl = %i, g_bWarden = %i, g_bTF2Jail = %i", g_bJailControl, g_bWarden, g_bTF2Jail);
				CmdOtkazMenu(client);
			#else
			if (g_bWarden && warden_iswarden(client))
				CmdOtkazMenu(client);
			else if (g_bWardenPro && JWP_IsWarden(client))
				CmdOtkazMenu(client);
			else if (g_bJailControl && Jail_IsClientCommander(client))
				CmdOtkazMenu(client);
			else
				PrintToChat(client, "%s%t", PREFIX, "Only Warden");
			#endif
		}
		else if (GetEngineVersion() == Engine_TF2)
		{
			if (g_bTF2Jail && TF2Jail_IsWarden(client))
				CmdOtkazMenu(client);
			else
				PrintToChat(client, "%s%t", PREFIX, "Only Warden");
		}
	}

	return Plugin_Handled;
}

public int OtkazMenuHandler(Menu menu, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (client && IsClientInGame(client) && IsPlayerAlive(client))
			{
				g_iRoundUsed[client]++;
				if(g_cColor[0][0] && g_cColor[1][0] && g_cColor[2][0] && g_cColor[3][0])
				{
					SetEntityRenderMode(client, RENDER_TRANSCOLOR);
					SetEntityRenderColor(client, StringToInt(g_cColor[0]), StringToInt(g_cColor[1]), StringToInt(g_cColor[2]), StringToInt(g_cColor[3]));
				}
				char cReason[85];
				char cFullReason[256];
				char cTime[48];
				char cTimebuff[128];
				char cName[MAX_NAME_LENGTH];
				
				menu.GetItem(iSlot, cReason, sizeof(cReason));
				char cChatNotify[1024];
				FormatEx(cChatNotify, sizeof(cChatNotify), "%t", "Chat Notify", client, cReason);
				PrintToChatAll("%s\x04%s", PREFIX, cChatNotify);
				
				//Block otkaz for those who wanna flood
				g_bBlockotkaz[client] = true;
				
				//As request we're adding waiting Menu
				OtkazStatusPanel = new Panel();
				char cLangText[86];
				FormatEx(cLangText, sizeof(cLangText), "%t", "Otkaz Status");
				OtkazStatusPanel.SetTitle(cLangText);
				FormatEx(cLangText, sizeof(cLangText), "%t", "Otkaz Status Text1");
				OtkazStatusPanel.DrawText(cLangText);
				FormatEx(cLangText, sizeof(cLangText), "%t", "Otkaz Status Text2");
				OtkazStatusPanel.DrawText(cLangText);
				
				
				FormatEx(cFullReason, sizeof(cFullReason), "%t", "Reason", cReason);
				OtkazStatusPanel.DrawItem(cFullReason);
				
				//Get current time and put in char
				int temptime = GetTime() - g_iGlobTime;
				FormatTime(cTime, sizeof(cTime), "%M:%S", temptime);
				
				//Get Full String and put in char
				FormatEx(cTimebuff, sizeof(cTimebuff), "%t", "Reason Time", cTime);
				OtkazStatusPanel.DrawText(cTimebuff);
				OtkazStatusPanel.Send(client, OtkazStatusPanel_Handler, 5);
				
				//At First
				GetClientName(client, cName, sizeof(cName));
				g_aClients.Push(client);
				g_aNames.PushString(cName);
				g_aReasons.PushString(cReason);
				g_aTimes.Push(temptime);
			}
		}
	}
}

//Emit some effects of menu for panel, I don't know why I did it.
public int OtkazStatusPanel_Handler(Menu panel, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_Select: EmitSoundToClient(client, "buttons/button14.wav");
		case MenuAction_End: EmitSoundToClient(client, "buttons/combine_button7.wav");
	}
}

void CmdOtkazMenu(int client)
{
	int iSize = g_aClients.Length;
	#if DEBUG
		PrintToChatAll("iSize = %i", iSize);
	#endif
	if (!iSize)
		PrintToChat(client, "%s%t", PREFIX, "No Players");
	else
	{
		g_hCmdMenu = new Menu(MenuHandler_CmdOtkazMenu);
		char cName[MAX_NAME_LENGTH];
		char cIndex[5];
		
		FormatEx(cName, sizeof(cName), "%t", "Active Otkazes");
		g_hCmdMenu.SetTitle(cName);
		
		for (int i=iSize-1; i>=0; --i) //FRESH Otkaz'es will be at first point
		{
			g_aNames.GetString(i, cName, sizeof(cName));
			
			IntToString(i, cIndex, sizeof(cIndex));
			g_hCmdMenu.AddItem(cIndex, cName);
		}
		
		g_hCmdMenu.Display(client, MENU_TIME_FOREVER);
	}
}

public int MenuHandler_CmdOtkazMenu(Menu menu, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_End: menu.Close();
		case MenuAction_Select:
		{
			char cIndex[5];
			menu.GetItem(iSlot, cIndex, sizeof(cIndex));
			g_iTarget[client][INDEX] = StringToInt(cIndex);
			
			CmdOtkazDetailMenu(client);
		}
	}
}

void CmdOtkazDetailMenu(int client)
{
	char cName[MAX_NAME_LENGTH];
	char cReason[MAX_REASON_SIZE];
	int iTime;
	char cTime[48];
	char cLangText[256];
	
	
	g_aNames.GetString(g_iTarget[client][INDEX], cName, sizeof(cName));
	g_aReasons.GetString(g_iTarget[client][INDEX], cReason, sizeof(cReason));
	iTime = g_aTimes.Get(g_iTarget[client][INDEX]);
	
	Menu hMenu = new Menu(MenuHandler_CmdOtkazDetailMenu);
	
	//Menu Title
	FormatEx(cLangText, sizeof(cLangText), "%t", "Otkaz Details", cName);
	hMenu.SetTitle(cLangText);
	//Reason
	FormatEx(cLangText, sizeof(cLangText), "%t", "Reason", cReason);
	hMenu.AddItem("Reason", cLangText);
	//Time
	FormatTime(cTime, sizeof(cTime), "%H:%M:%S", iTime);
	FormatEx(cLangText, sizeof(cLangText), "%t", "Reason Time", cTime);
	hMenu.AddItem("Time", cLangText);
	//Spacer
	hMenu.AddItem("", "", ITEMDRAW_SPACER);
	//Finish
	FormatEx(cLangText, sizeof(cLangText), "%t", "Finish Otkaz");
	hMenu.AddItem("Finish", cLangText);
	
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_CmdOtkazDetailMenu(Menu menu, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_End: menu.Close();
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack)
				CmdOtkazMenu(client);
		}
		case MenuAction_Select:
		{
			if (iSlot < 3) CmdOtkazDetailMenu(client);
			else
			{
				int iTarget = g_aClients.Get(g_iTarget[client][INDEX]);
				
				PrintToChatAll("%s%t", PREFIX, "Notify Otkaz Finished", client, iTarget);
				
				//Set Default Color to iTarget
				SetEntityRenderMode(iTarget, RENDER_TRANSCOLOR);
				SetEntityRenderColor(iTarget, 255, 255, 255, 255);
				
				g_bBlockotkaz[iTarget] = false;
				Otkaz_RemoveFromArray(g_iTarget[client][INDEX]);
				CmdOtkazMenu(client);
			}
		}
	}
}

public void OnClientDisconnect(int client)
{
	RemoveClientFromMenu(client);
}

void RemoveClientFromMenu(int client)
{
	if (!client || IsFakeClient(client) || !IsClientInGame(client) || !g_aClients.Length) return;
	else
	{
		int index = g_aClients.FindValue(client);
		if (index != -1)
		{
			g_aClients.Erase(index);
			g_aNames.Erase(index);
			g_aReasons.Erase(index);
			g_aTimes.Erase(index);
		}
	}
}

stock void CreateCustomCfg(const char[] Path)
{
	if(!FileExists(Path))
	{
		LogError("[SM] File %s not found", Path);
		SetFailState("Не найден файл %s", Path);
	}
	else if (!ParseCustomCfg(Path))
	{
		LogError("[SM] Plugin is not running! Failed to parse '%s'", Path);
		SetFailState("Parse error on file '%s'", Path);
	}
}

stock bool ParseCustomCfg(const char[] file)
{
	SMCParser parser = new SMCParser();
	char error[128];
	int line = 0, col = 0;
	
	ConfigState = ConfigStateNone;
	// Create parsers
	SMC_SetReaders(parser, Config_NewSection, Config_KeyValue, Config_EndSection);
	
	// Parse the file and get the result
	SMCError result = SMC_ParseFile(parser, file, line, col);
	delete parser;
	
	if (result != SMCError_Okay)
	{
		SMC_GetErrorString(result, error, sizeof(error));
		LogError("%s on line %d, col %d, of %s", error, line, col, file);
	}
	
	return (result == SMCError_Okay);
}

public SMCResult Config_NewSection(SMCParser smc, const char[] name, bool opt_quotes)
{
	if (name[0])
	{
		if (!strcmp("Config", name, false))
			ConfigState = ConfigStateConfig;
		else if (!strcmp("Reasons", name, false))
		{
			ConfigState = ConfigStateReasons;
			g_hMenu = new Menu(OtkazMenuHandler);
			// char cLangTitle[52];
			// FormatEx(cLangTitle, sizeof(cLangTitle), "%t", "Reason Select");
			g_hMenu.SetTitle("Выберите причину отказа:");
			g_hMenu.ExitButton = true;
		}
	}
	return SMCParse_Continue;
}

public SMCResult Config_KeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	if (!key[0])
		return SMCParse_Continue;
	
	switch (ConfigState)
	{
		case ConfigStateConfig:
		{
			if (!strcmp("PerRound", key, false))
			{
				if (value[0])
				{
					g_iRoundUse = StringToInt(value);
					if (g_iRoundUse < 0) g_iRoundUse = 0;
				}
				else
					g_iRoundUse = 3;
			}
			else if (!strcmp("PlayerColor", key, false))
			{
				if (value[0])
					ExplodeString(value, " ", g_cColor, sizeof(g_cColor), sizeof(g_cColor[]));
			}
			else if (!strcmp("MenuTime", key, false))
			{
				if (value[0])
				{
					g_iMenuTime = StringToInt(value);
					if (g_iMenuTime < 0) g_iMenuTime = 0;
				}
				else
					g_iMenuTime = 20;
			}
			else if (!strcmp("Commands", key, false))
			{
				if (value[0])
					g_iNumCmds = ExplodeString(value, ",", g_cChatCmds, sizeof(g_cChatCmds), sizeof(g_cChatCmds[]));
				else
					g_iNumCmds = 0;
			}
		}
		case ConfigStateReasons:
		{
			g_hMenu.AddItem(key, value);
		}
	}
	return SMCParse_Continue;
}

public SMCResult Config_EndSection(SMCParser smc)
{
	return SMCParse_Continue;
}

void Otkaz_RemoveFromArray(int index)
{
	if (index != -1)
	{
		g_aClients.Erase(index);
		g_aNames.Erase(index);
		g_aReasons.Erase(index);
		g_aTimes.Erase(index);
	}
}

void Clear_OtkazHistory()
{
	g_aClients.Clear();
	g_aNames.Clear();
	g_aReasons.Clear();
	g_aTimes.Clear();
}