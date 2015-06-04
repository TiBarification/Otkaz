#include <sourcemod>
#include <cstrike>
#include <sdktools>
#undef REQUIRE_PLUGIN
#tryinclude <jail_control>
#tryinclude <tf2jail>
#tryinclude <warden>

#pragma semicolon 1
//Force 1.7 syntax
#pragma newdecls required

#define PLUGIN_VERSION "1.3.3"
#define PREFIX "\x01[\x03Отказ\x01]\x03 "
#define MAX_REASON_SIZE 85
#define DEBUG 0

ConVar g_hEnabled;
ConVar g_hRoundUse;
ConVar g_hColor;
ConVar g_hMenuTime;
ConVar g_hChatCommands;

Menu g_hMenu;
Menu g_hCmdMenu;
Panel OtkazStatusPanel;

bool g_bEnabled;
bool g_bBlockotkaz[MAXPLAYERS+1] = false;

//PLUGINS BOOL's
bool g_bWarden;
bool g_bJailControl;
bool g_bTF2Jail;

int g_iRoundUse;
int g_iRoundUsed[MAXPLAYERS+1];
int g_iMenuTime;
int g_iNumCmds;

char Reasons[26] = "configs/otkaz_reasons.txt";
char g_cChatCmds[16][32];
char g_cColor[3][4];

enum
{
	ID = 0,
	NAME,
	REASON,
	TIME,
	SIZE
}

enum Target
{
	INDEX
}

int g_iTarget[MAXPLAYERS+1][Target];

Handle g_hData = null;

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
	g_hRoundUse = CreateConVar("sm_otkaz_per_round", "3", "Сколько отказов доступно за раунд.", FCVAR_PLUGIN, true, 0.0);
	g_hColor = CreateConVar("sm_otkaz_player_color", "30 20 40", "RGB цвет в который красить игрока. 0 - off", FCVAR_PLUGIN);
	g_hMenuTime = CreateConVar("sm_otkaz_menu_time", "20", "Сколько секунд активно меню игрока.", FCVAR_PLUGIN, true, 0.0);
	g_hChatCommands = CreateConVar("sm_otkaz_cmds", "!otkaz,!отказ,отказ", "Команды вызова меню отказа(каждая команда после запятой)", FCVAR_NONE);
	//Needed to add HOOKS after this -^
	
	g_hEnabled.AddChangeHook(OnCvarChange);
	g_hRoundUse.AddChangeHook(OnCvarChange);
	g_hColor.AddChangeHook(OnCvarChange);
	g_hMenuTime.AddChangeHook(OnCvarChange);
	g_hChatCommands.AddChangeHook(OnCvarChange);
	
	g_hData = CreateArray(125);
	
	AutoExecConfig(true, "otkaz");
	
	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_death", OnPlayerDeath);
	
	g_bEnabled = true;
	
	RegConsoleCmd("sm_wotkaz", Command_OtkazView, "View otkaz menu");
	
	PrintToServer("Engine Version : %s |Plugin Version: %s", GetEngineVersion(), PLUGIN_VERSION);
	
	CreateCustomCfg(Reasons);
	
	LoadTranslations("otkaz.phrases");
	
	OtkazMenuInitialized();
}

public void OnConfigsExecuted()
{
	char cBuffer[512];
	g_bEnabled = g_hEnabled.BoolValue;
	g_iMenuTime = g_hMenuTime.IntValue;
	g_iRoundUse = g_hRoundUse.IntValue;
	GetConVarString(g_hColor, cBuffer, sizeof(cBuffer));
	ExplodeString(cBuffer, " ", g_cColor, sizeof(g_cColor), sizeof(g_cColor[]));
	GetConVarString(g_hChatCommands, cBuffer, sizeof(cBuffer));
	g_iNumCmds = ExplodeString(cBuffer, ",", g_cChatCmds, sizeof(g_cChatCmds), sizeof(g_cChatCmds[]));
}

public void OnCvarChange(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	char sConVarName[64];
	hConVar.GetName(sConVarName, sizeof(sConVarName));
	
	if (StrEqual("sm_otkaz_enabled", sConVarName))
	{
		if (g_bEnabled != hConVar.BoolValue)
			g_bEnabled = hConVar.BoolValue;
	}
	else if (StrEqual("sm_otkaz_per_round", sConVarName))
		g_iRoundUse = StringToInt(sNewValue);
	else if (StrEqual("sm_otkaz_player_color", sConVarName))
		ExplodeString(sNewValue, " ", g_cColor, sizeof(g_cColor), sizeof(g_cColor[]));
	else if (StrEqual("sm_otkaz_menu_time", sConVarName))
		g_iMenuTime = StringToInt(sNewValue);
	else if (StrEqual("sm_otkaz_cmds", sConVarName))
		ExplodeString(sNewValue, ",", g_cChatCmds, sizeof(g_cChatCmds), sizeof(g_cChatCmds[]));
}

public void OnAllPluginsLoaded()
{
	g_bWarden = LibraryExists("warden");
	g_bJailControl = LibraryExists("jail_control");
	g_bTF2Jail = LibraryExists("tf2jail");
}

public void OnLibraryAdded(const char[] name)
{
	g_bWarden = StrEqual(name, "warden");
	g_bJailControl = StrEqual(name, "jail_control");
	g_bTF2Jail = StrEqual(name, "tf2jail");
}

public void OnLibraryRemoved(const char[] name)
{
	g_bWarden = StrEqual(name, "warden");
	g_bJailControl = StrEqual(name, "jail_control");
	g_bTF2Jail = StrEqual(name, "tf2jail");
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
		for (int i = 0; i < g_iNumCmds; i++)
		{
			if (StrEqual(sArgs, g_cChatCmds[i], true)) // If !Otkaz and !otkaz different items we set 3 argument to true
			{
				#if DEBUG
					PrintToChatAll("g_cChatCmds[i] = %s", g_cChatCmds[i]);
				#endif
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
						{
							g_hMenu.Display(client, MENU_TIME_FOREVER);
							return Plugin_Continue;
						}
						else
						{
							g_hMenu.Display(client, g_iMenuTime);
							return Plugin_Continue;
						}
						
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
	
	return Plugin_Continue;
}

public Action Command_OtkazView(int client, int args)
{
	if (!IsFakeClient(client) && IsClientInGame(client) )
	{
		if (GetEngineVersion() == Engine_CSS || GetEngineVersion() == Engine_CSGO)
		{
			#if DEBUG
				PrintToChatAll("g_bJailControl = %i, g_bWarden = %i, g_bTF2Jail = %i", g_bJailControl, g_bWarden, g_bTF2Jail);
				CmdOtkazMenu(client);
			#else
			if (g_bWarden && warden_iswarden(client))
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

void OtkazMenuInitialized()
{
	Handle oprfile = OpenFile("addons/sourcemod/configs/otkaz_reasons.txt", "r");
	if (oprfile == null)
	{
		PrintToServer("Не удалось открыть файл addons/sourcemod/configs/otkaz_reasons.txt");
		return;
	}
	g_hMenu = new Menu(OtkazMenuHandler);
	char StR[MAX_REASON_SIZE];
	char cLangTitle[512];
	FormatEx(cLangTitle, sizeof(cLangTitle), "%t", "Reason Select");
	g_hMenu.SetTitle(cLangTitle);
	while (!IsEndOfFile(oprfile) && ReadFileLine(oprfile, StR, sizeof(StR)))
	{
		g_hMenu.AddItem(StR, StR);
	}
	CloseHandle(oprfile);
	g_hMenu.ExitButton = true;
}

public int OtkazMenuHandler(Menu menu, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			g_iRoundUsed[client]++;
			if(GetConVarInt(g_hColor))
			{
				SetEntityRenderMode(client, RENDER_TRANSCOLOR);
				SetEntityRenderColor(client, StringToInt(g_cColor[0]), StringToInt(g_cColor[1]), StringToInt(g_cColor[2]), 255);
			}
			char cReason[85];
			char cFullReason[256];
			char cTime[48];
			char cTimebuff[128];
			char cName[MAX_NAME_LENGTH];
			
			GetMenuItem(menu, iSlot, cReason, sizeof(cReason));
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
			FormatTime(cTime, sizeof(cTime), "%H:%M:%S", GetTime());
			
			//Get Full String and put in char
			FormatEx(cTimebuff, sizeof(cTimebuff), "%t", "Reason Time", cTime);
			OtkazStatusPanel.DrawText(cTimebuff);
			OtkazStatusPanel.Send(client, OtkazStatusPanel_Handler, 5);
			
			//LOCAL Array to work with this
			Handle hArray;
			hArray = CreateArray(125, SIZE);
			
			//At First
			GetClientName(client, cName, sizeof(cName));
			SetArrayCell(hArray, ID, client); //Save client ID for some reason
			SetArrayString(hArray, NAME, cName);
			SetArrayString(hArray, REASON, cReason);
			SetArrayCell(hArray, TIME, GetTime());
			PushArrayCell(g_hData, hArray);
		}
		case MenuAction_End: return;
	}
}

//Emit some effects of menu for panel, I don't know why I did it.
public int OtkazStatusPanel_Handler(Menu panel, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			EmitSoundToClient(client, "buttons/button14.wav");
		}
		case MenuAction_End:
			EmitSoundToClient(client, "buttons/combine_button7.wav");
	}
}

void CmdOtkazMenu(int client)
{
	int iSize = GetArraySize(g_hData);
	#if DEBUG
		PrintToChatAll("iSize = %i", iSize);
	#endif
	if (iSize == 0)
		PrintToChat(client, "%s%t", PREFIX, "No Players");
	else
	{
		g_hCmdMenu = new Menu(MenuHandler_CmdOtkazMenu);
		char cTitle[128];
		char cName[MAX_NAME_LENGTH];
		char cIndex[5];
		Handle hArray;
		
		FormatEx(cTitle, sizeof(cTitle), "%t", "Active Otkazes");
		g_hCmdMenu.SetTitle(cTitle);
		
		for (int i=iSize-1; i>=0; --i) //FRESH Otkaz'es will be at first point
		{
			hArray = GetArrayCell(g_hData, i);
			GetArrayString(hArray, NAME, cName, sizeof(cName));
			FormatEx(cTitle, sizeof(cTitle), "%s", cName);
			
			IntToString(i, cIndex, sizeof(cIndex));
			g_hCmdMenu.AddItem(cIndex, cTitle);
		}
		
		g_hCmdMenu.Display(client, MENU_TIME_FOREVER);
	}
}

public int MenuHandler_CmdOtkazMenu(Menu menu, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_End: CloseHandle(menu);
		case MenuAction_Select:
		{
			char cIndex[5];
			GetMenuItem(menu, iSlot, cIndex, sizeof(cIndex));
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
	char cTime[256];
	char cLangText[256];
	Handle hArray;
	
	
	hArray = GetArrayCell(g_hData, g_iTarget[client][INDEX]);
	GetArrayString(hArray, NAME, cName, sizeof(cName));
	GetArrayString(hArray, REASON, cReason, sizeof(cReason));
	iTime = GetArrayCell(hArray, TIME);
	
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
	
	#if DEBUG
		int targetid = GetArrayCell(hArray, ID);
		PrintToChatAll("Массив 0: %i", targetid);
		PrintToChatAll("Массив 1: %s", cName);
		PrintToChatAll("Массив 2: %s", cReason);
		PrintToChatAll("Массив 3: %i", iTime);
	#endif
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_CmdOtkazDetailMenu(Menu menu, MenuAction action, int client, int iSlot)
{
	switch (action)
	{
		case MenuAction_End: CloseHandle(menu);
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack)
				CmdOtkazMenu(client);
		}
		case MenuAction_Select:
		{
			if (iSlot < 3)
			{
				CmdOtkazDetailMenu(client);
			}
			else
			{
				Handle hArray;
				hArray = GetArrayCell(g_hData, g_iTarget[client][INDEX]);
				int iTarget = GetArrayCell(hArray, ID);
				
				PrintToChatAll("%s%t", PREFIX, "Notify Otkaz Finished", client, iTarget);
				
				//Set Default Color to iTarget
				SetEntityRenderMode(iTarget, RENDER_TRANSCOLOR);
				SetEntityRenderColor(iTarget, 255, 255, 255, 255);
				
				g_bBlockotkaz[iTarget] = false;
				int iIndex = FindValueInArray(hArray, iTarget);
				if (iIndex != -1)
				{
					#if DEBUG
						PrintToChatAll("iTarget = %i", iTarget);
						PrintToChatAll("iIndex = %i", iIndex);
					#endif
					Otkaz_RemoveFromArray(iIndex);
				}
				CloseHandle(hArray);
				CmdOtkazMenu(client);
			}
		}
	}
}

public void OnClientDisconnect(int client)
{
	RemoveClientFromMenu(client);
}

stock bool RemoveClientFromMenu(int client)
{
	if (client == 0 && GetClientTeam(client) != 2) return false;
	int iSize = GetArraySize(g_hData);
	if (iSize == 0) return false;
	Handle hArray;
	int iIndex;
	for (int i=iSize-1; i>=0; --i)
		hArray = GetArrayCell(g_hData, i);
	if (GetArrayCell(hArray, ID) == client)
	{
		// Find client ID from g_hData Simple using, Thanks R1KO for this.
		// iIndex = GetArrayCell(hArray, ID);
		// PrintToChatAll("iIndex = %i", iIndex);
		iIndex = FindValueInArray(hArray, client);
		Otkaz_RemoveFromArray(iIndex);
		
		//From wiki it's CloseHandle(hArray);
		delete hArray;

		return true;
	}
	return false;
}

stock void CreateCustomCfg(const char[] Path)
{
	char sBuffer[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sBuffer, sizeof(sBuffer), Path);
	if(!FileExists(sBuffer))
	{
		SetFailState("Не найден файл %s", sBuffer);
	}
}

void Otkaz_RemoveFromArray(int iIndex)
{
	RemoveFromArray(g_hData, iIndex);
}

void Clear_OtkazHistory()
{
	ClearArray(g_hData);
}