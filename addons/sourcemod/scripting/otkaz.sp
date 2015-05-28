#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <jail_control>

#pragma semicolon 1
//Force 1.7 syntax
#pragma newdecls required

#define PLUGIN_VERSION "1.3.2"
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
	TIME
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
	
	g_bEnabled = true;
	
	RegConsoleCmd("sm_otkazview", Command_OtkazView, "View otkaz menu");
	
	CreateCustomCfg(Reasons);
	
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

public void OnRoundStart(Handle event, const char[] name, bool donBroadcast)
{
	if (!g_bEnabled)
		return;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iRoundUsed[i] = 0;
		//If exists then
		Clear_OtkazHistory();
	}
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
							PrintToChat(client, "%sВы не можете использовать отказ больше чем %i раз(а).", PREFIX, g_iRoundUse);
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
						PrintToChat(client, "%sВы должны быть живы.", PREFIX);
						return Plugin_Stop;
					}
				}
				else
				{
					PrintToChat(client, "%sВы должны быть заключенным.", PREFIX);
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
		if (GetClientTeam(client) == CS_TEAM_CT && Jail_IsClientCommander(client))
			CmdOtkazMenu(client);
		else
			PrintToChat(client, "%sНужно быть коммандиром", PREFIX);
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
	g_hMenu.SetTitle("Выберите причину отказа:\n \n");
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
				SetEntityRenderColor(client, StringToInt(g_cColor[0]), StringToInt(g_cColor[1]), StringToInt(g_cColor[2]), 255);
			}
			char cThatReason[85];
			char cFullReason[256];
			char cTime[48];
			char cTimebuff[128];
			char cName[MAX_NAME_LENGTH];
			
			GetMenuItem(menu, iSlot, cThatReason, sizeof(cThatReason));
			PrintToChatAll("%s\x04%N\x03 написал отказ. Причина: \x04%s", PREFIX, client, cThatReason);
			
			//Block otkaz for those who wanna flood
			g_bBlockotkaz[client] = true;
			
			//As request we're adding waiting Menu
			OtkazStatusPanel = new Panel();
			OtkazStatusPanel.SetTitle("Статус жалобы:\n");
			OtkazStatusPanel.DrawText("Вы написали жалобу, ждите рассмотрение");
			OtkazStatusPanel.DrawText("вашей жалобы командиром.");
			
			
			FormatEx(cFullReason, sizeof(cFullReason), "Причина: %s", cThatReason);
			OtkazStatusPanel.DrawItem(cFullReason);
			
			//Get current time and put in char
			FormatTime(cTime, sizeof(cTime), "%H:%M:%S", GetTime());
			
			//Get Full String and put in char
			FormatEx(cTimebuff, sizeof(cTimebuff), "Время жалобы: %s", cTime);
			OtkazStatusPanel.DrawText(cTimebuff);
			OtkazStatusPanel.Send(client, OtkazStatusPanel_Handler, 5);
			
			//LOCAL Array to work with this
			Handle hArray;
			hArray = CreateArray(125);
			
			//At First
			GetClientName(client, cName, sizeof(cName));
			PushArrayCell(hArray, client); //Save client ID for some reason
			PushArrayString(hArray, cName);
			PushArrayString(hArray, cFullReason);
			PushArrayString(hArray, cTimebuff);
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
	if (iSize == 0)
		PrintToChat(client, "%sНет игроков с отказами", PREFIX);
	else
	{
		g_hCmdMenu = new Menu(MenuHandler_CmdOtkazMenu);
		char cTitle[128];
		char cName[MAX_NAME_LENGTH];
		char cIndex[5];
		Handle hArray;
		
		FormatEx(cTitle, sizeof(cTitle), "Активные отказы");
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
	char cAReason[MAX_REASON_SIZE];
	char cTime[256];
	char cTitle[128];
	Handle hArray;
	
	
	hArray = GetArrayCell(g_hData, g_iTarget[client][INDEX]);
	GetArrayString(hArray, NAME, cName, sizeof(cName));
	GetArrayString(hArray, REASON, cAReason, sizeof(cAReason));
	GetArrayString(hArray, TIME, cTime, sizeof(cTime));
	
	Menu hMenu = new Menu(MenuHandler_CmdOtkazDetailMenu);
	
	FormatEx(cTitle, sizeof(cTitle), "Детали отказа - %s", cName);
	hMenu.SetTitle(cTitle);
	hMenu.AddItem("Reason", cAReason);
	hMenu.AddItem("Time", cTime);
	hMenu.AddItem("", "", ITEMDRAW_SPACER);
	hMenu.AddItem("Finish", "Рассмотреть отказ");
	
	#if DEBUG
		int targetid = GetArrayCell(hArray, ID);
		PrintToChatAll("Массив 0: %i", targetid);
		PrintToChatAll("Массив 1: %s", cName);
		PrintToChatAll("Массив 2: %s", cAReason);
		PrintToChatAll("Массив 3: %s", cTime);
	#endif
	SetMenuExitBackButton(hMenu, true);
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
				int iTarget = GetTargetOfOtkazPlayer(client, hArray);
				#if DEBUG
					PrintToChatAll("iTarget = %i", iTarget);
				#endif
				PrintToChatAll("%s%N рассмотрел отказ зека %N", PREFIX, client, iTarget);
				SetEntityRenderColor(iTarget, 255, 255, 255, 255);
				
				int iIndex = GetIndexOfOtkazPlayer(hArray, iTarget);
				Otkaz_RemoveFromArray(iIndex);
				CmdOtkazMenu(client);
			}
		}
	}
}

public void OnClientDisconnect(int client)
{
	Otkaz_RemoveFromArray(g_iTarget[client][INDEX]);
}

stock int GetTargetOfOtkazPlayer(int client, Handle hArray)
{
	hArray = GetArrayCell(g_hData, g_iTarget[client][INDEX]);
	int iTarget = GetArrayCell(hArray, ID);
	return iTarget;
}

int GetIndexOfOtkazPlayer(Handle hArray, int iTarget)
{
	int iIndex = FindValueInArray(hArray, iTarget);
	return iIndex;
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