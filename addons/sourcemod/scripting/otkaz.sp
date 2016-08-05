#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <updater>
#tryinclude <jail_control> // INC FILES: http://goo.gl/rpxYc2
#tryinclude <tf2jail> // https://goo.gl/NR2JUk
#tryinclude <warden> // https://goo.gl/EVQ4Pi
#tryinclude <jwp> // https://goo.gl/PggNYM

#pragma semicolon 1
//Force 1.7 syntax
#pragma newdecls required

#define PLUGIN_VERSION "1.4.0"
#define MAX_REASON_SIZE 85
#define DEBUG 0
#define UPDATE_URL "http://updater.tibari.ru/otkaz/updatefile.txt"

ConVar g_hEnabled;

Menu g_hMenu;
Menu g_hCmdMenu;
Panel OtkazStatusPanel;

bool g_bEnabled;
bool g_bBlockotkaz[MAXPLAYERS+1] = false;
bool g_bEnableOwnReason;
bool g_bChatWait[MAXPLAYERS+1] = false;

//PLUGINS BOOL's
bool g_bWardenPlugin[4];

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
	CreateConVar("sm_otkaz_version", PLUGIN_VERSION, "Version of Otkaz", FCVAR_NOTIFY|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_DONTRECORD);
	g_hEnabled = CreateConVar("sm_otkaz_enabled", "1", "Включение/Выключение плагина.", FCVAR_REPLICATED, true, 0.0, true, 1.0);
	
	g_hEnabled.AddChangeHook(OnCvarChange);
	
	g_aClients = new ArrayList(MaxClients+1);
	g_aNames = new ArrayList(MAX_NAME_LENGTH);
	g_aReasons = new ArrayList(85);
	g_aTimes = new ArrayList(1);
	
	if (GetEngineVersion() == Engine_CSGO || GetEngineVersion() == Engine_CSS)
		HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	else if (GetEngineVersion() == Engine_TF2)
		HookEvent("teamplay_round_start", OnRoundStart, EventHookMode_PostNoCopy);
	
	g_bEnabled = true;
	
	RegConsoleCmd("sm_wotkaz", Command_OtkazView, "View otkaz menu");
	
	LoadTranslations("otkaz.phrases");
	
	CreateCustomCfg(ConfigPath);
	
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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("warden_iswarden");
	MarkNativeAsOptional("JWP_IsWarden");
	MarkNativeAsOptional("Jail_IsClientCommander");
	MarkNativeAsOptional("TF2Jail_IsWarden");
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	g_bWardenPlugin[0] = LibraryExists("warden");
	g_bWardenPlugin[1] = LibraryExists("jail_control");
	g_bWardenPlugin[2] = LibraryExists("tf2jail");
	g_bWardenPlugin[3] = LibraryExists("jwp");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public int Updater_OnPluginUpdated()
{
	LogMessage("Plugin updated. Old version %s. Now reloading...");
	ReloadPlugin();
}

public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bChatWait[i] = false;
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
	g_bChatWait[iClient] = false;
	
	RemoveClientFromMenu(iClient);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(!g_bEnabled)
		return Plugin_Stop;
	
	if(client && IsClientInGame(client))
	{
		if (!g_iNumCmds) PrintToChat(client, "\x01%t %t", "Otkaz Prefix", "Otkaz Commands Error");
		else
		{
			if (g_bChatWait[client])
			{
				if (GetClientTeam(client) == 2 && IsPlayerAlive(client))
				{
					char cReason[85];
					strcopy(cReason, sizeof(cReason), sArgs);
					StripQuotes(cReason);
					TrimString(cReason);
					ProceedOtkaz(client, cReason);
				}
				g_bChatWait[client] = false;
			}
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
									PrintToChat(client, "\x01%t %t", "Otkaz Prefix", "Round Use", g_iRoundUse);
									return Plugin_Stop;
								}
								else
									g_hMenu.Display(client, g_iMenuTime);
							}
							else
							{
								PrintToChat(client, "\x01%t %t", "Otkaz Prefix", "Must be Alive");
								return Plugin_Stop;
							}
						}
						else
						{
							PrintToChat(client, "\x01%t %t", "Otkaz Prefix", "Only Prisoner");
							return Plugin_Stop;
						}
					}
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Command_OtkazView(int client, int args)
{
	if (g_bEnabled && client && !IsFakeClient(client) && IsClientInGame(client))
	{
		if (!g_iNumCmds) PrintToChat(client, "\x01%t %t", "Otkaz Prefix", "Otkaz Commands Error");
		else
		{
			#if DEBUG
				PrintToChatAll("Jail Control = %i, Warden = %i, Jail Warden Pro = %i, g_bTF2Jail = %i", g_bWardenPlugin[1], g_bWardenPlugin[0], g_bWardenPlugin[3], g_bWardenPlugin[2]);
			#endif
			CmdOtkazMenu(client);
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
				
				menu.GetItem(iSlot, cReason, sizeof(cReason));
				
				if (g_bEnableOwnReason && !strcmp(cReason, "own"))
				{
					g_bChatWait[client] = true;
					PrintToChat(client, "\x01%t \x03%t", "Otkaz Prefix", "Enter Own Otkaz");
					return;
				}
				
				ProceedOtkaz(client, cReason);
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
	if ((g_bWardenPlugin[0] && warden_iswarden(client)) || (g_bWardenPlugin[2] && TF2Jail_IsWarden(client)) || (g_bWardenPlugin[3] && JWP_IsWarden(client)) || (g_bWardenPlugin[1] && Jail_IsClientCommander(client)))
	{
		int iSize = g_aClients.Length;
		#if DEBUG
			PrintToChatAll("iSize = %i", iSize);
		#endif
		if (!iSize)
			PrintToChat(client, "\x01%t %t", "Otkaz Prefix", "No Players");
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
	else
		PrintToChat(client, "\x01%t \x03%t", "Otkaz Prefix", "Only Warden");
}

public int MenuHandler_CmdOtkazMenu(Menu menu, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_Cancel:
		{
			if (g_bWardenPlugin[3] && JWP_IsWarden(client))
				JWP_ShowMainMenu(client);
		}
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
	char cLangText[256];
	
	Menu hMenu = new Menu(MenuHandler_CmdOtkazDetailMenu);
	
	//Menu Title
	g_aNames.GetString(g_iTarget[client][INDEX], cLangText, sizeof(cLangText));
	Format(cLangText, sizeof(cLangText), "%t", "Otkaz Details", cLangText);
	hMenu.SetTitle(cLangText);
	//Reason
	g_aReasons.GetString(g_iTarget[client][INDEX], cLangText, sizeof(cLangText));
	Format(cLangText, sizeof(cLangText), "%t", "Reason", cLangText);
	hMenu.AddItem("Reason", cLangText);
	//Time
	FormatTime(cLangText, sizeof(cLangText), "%M:%S", g_aTimes.Get(g_iTarget[client][INDEX]));
	Format(cLangText, sizeof(cLangText), "%t", "Reason Time", cLangText);
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
				
				PrintToChatAll("\x01%t \x03%t", "Otkaz Prefix", "Notify Otkaz Finished", client, iTarget);
				
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
	if (!g_aClients.Length) return;
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
			char cLangTitle[52];
			FormatEx(cLangTitle, sizeof(cLangTitle), "%t", "Reason Select");
			g_hMenu.SetTitle(cLangTitle);
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
			else if (!strcmp("OwnReasons", key, false))
			{
				if (value[0])
					g_bEnableOwnReason = view_as<bool>(StringToInt(value));
				else
					g_bEnableOwnReason = false;
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
	if (ConfigState == ConfigStateReasons)
	{
		if (g_bEnableOwnReason)
		{
			char lang[26];
			FormatEx(lang, sizeof(lang), "%t", "Own Reason Menu");
			g_hMenu.AddItem("own", lang);
		}
		ConfigState = ConfigStateNone;
	}
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

void ProceedOtkaz(int client, const char[] cReason)
{
	char buffer[1024];
	PrintToChatAll("\x01%t \x04%t", "Otkaz Prefix", "Chat Notify", client, cReason);
	
	//Block otkaz for those who wanna flood
	g_bBlockotkaz[client] = true;
	
	//As request we're adding waiting Menu
	OtkazStatusPanel = new Panel();
	// char cLangText[86];
	FormatEx(buffer, sizeof(buffer), "%t", "Otkaz Status");
	OtkazStatusPanel.SetTitle(buffer);
	FormatEx(buffer, sizeof(buffer), "%t", "Otkaz Status Text1");
	OtkazStatusPanel.DrawText(buffer);
	FormatEx(buffer, sizeof(buffer), "%t", "Otkaz Status Text2");
	OtkazStatusPanel.DrawText(buffer);
	
	
	FormatEx(buffer, sizeof(buffer), "%t", "Reason", cReason);
	OtkazStatusPanel.DrawItem(buffer);
	g_aReasons.PushString(buffer);
	
	//Get current time and put in char
	ConVar cvar_FreezeTime = FindConVar("mp_freezetime"); // Freezetime convar
	int temptime = GetTime() - g_iGlobTime - cvar_FreezeTime.IntValue;
	FormatTime(buffer, sizeof(buffer), "%M:%S", temptime);
	
	//Get Full String and put in char
	Format(buffer, sizeof(buffer), "%t", "Reason Time", buffer);
	OtkazStatusPanel.DrawText(buffer);
	OtkazStatusPanel.Send(client, OtkazStatusPanel_Handler, 5);
	
	//At First
	GetClientName(client, buffer, sizeof(buffer));
	g_aClients.Push(client);
	g_aNames.PushString(buffer);
	g_aTimes.Push(temptime);
}