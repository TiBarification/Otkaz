#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <protobuf>

#pragma semicolon 1
//Force 1.7 syntax
#pragma newdecls required

#define PLUGIN_VERSION "1.3"
#define PREFIX "\x04[\x03Отказ\x04]\x03 "

ConVar g_hEnabled;
ConVar g_hRoundUse;
ConVar g_hColor;
ConVar g_hMenuTime;
ConVar g_hChatCommands;

Handle g_hOtkaz_Timer[MAXPLAYERS+1];
Menu g_hMenu = null;

bool g_bEnabled;

int g_iRoundUse;
int g_iRoundUsed[MAXPLAYERS+1];
int g_iColor;
int g_iMenuTime;
int g_iNumCmds;

char Reasons[26] = "configs/otkaz_reasons.ini";
char g_cChatCmds[16][32];

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
	CreateConVar("sm_otkaz_version", PLUGIN_VERSION, "Version of Otkaz", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_SPONLY|FCVAR_REPLICATED);
	g_hEnabled = CreateConVar("sm_otkaz_enabled", "1", "Включение/Выключение плагина.", FCVAR_PLUGIN|FCVAR_REPLICATED|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	g_hRoundUse = CreateConVar("sm_otkaz_per_round", "3", "Сколько отказов доступно за раунд.", FCVAR_PLUGIN|FCVAR_DONTRECORD, true, 0.0);
	g_hColor = CreateConVar("sm_otkaz_player_color", "1", "Красить игрока в синий цвет, когда он пишет отказ?", FCVAR_PLUGIN|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	g_hMenuTime = CreateConVar("sm_otkaz_menu_time", "20", "Сколько секунд активно меню игрока.", FCVAR_PLUGIN|FCVAR_DONTRECORD, true, 0.0);
	g_hChatCommands = CreateConVar("sm_otkaz_cmds", "!otkaz,!отказ,отказ", "Команды вызова меню отказа(каждая команда после запятой)", FCVAR_NONE);
	//Needed to add HOOKS after this -^
	
	g_hEnabled.AddChangeHook(OnCvarChange);
	g_hRoundUse.AddChangeHook(OnCvarChange);
	g_hColor.AddChangeHook(OnCvarChange);
	g_hMenuTime.AddChangeHook(OnCvarChange);
	g_hChatCommands.AddChangeHook(OnCvarChange);
	
	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	
	g_bEnabled = true;
	
	CreateCustomCfg(Reasons);
	
	OtkazMenuInitialized();
}

public void OnConfigsExecuted()
{
	char cBuffer[512];
	g_bEnabled = g_hEnabled.BoolValue;
	g_iMenuTime = g_hMenuTime.IntValue;
	g_iRoundUse = g_hRoundUse.IntValue;
	g_iColor = g_hColor.IntValue;
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
		g_iColor = StringToInt(sNewValue);
	else if (StrEqual("sm_otkaz_menu_time", sConVarName))
		g_iMenuTime = StringToInt(sNewValue);
	else if (StrEqual("sm_otkaz_cmds", sConVarName))
		g_iNumCmds = ExplodeString(sNewValue, ",", g_cChatCmds, sizeof(g_cChatCmds), sizeof(g_cChatCmds[]));
}

public void OnRoundStart(Handle event, const char[] name, bool donBroadcast)
{
	if (!g_bEnabled)
		return;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iRoundUsed[i] = 0;
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
			if (StrEqual(command, g_cChatCmds[i], false))
			{
				if(GetClientTeam(client) == 2)
				{
					if(IsPlayerAlive(client))
					{
						if (g_iRoundUse && g_iRoundUsed[client] >= g_iRoundUse)
						{
							PrintToChat(client, "%sВы не можете использовать отказ больше чем %i раз(а).", PREFIX, g_iRoundUse);
							return Plugin_Stop;
						}
						else if (!g_iMenuTime)
						{
							g_hMenu.Display(client, MENU_TIME_FOREVER);
							return Plugin_Stop;
						}
						else
						{
							g_hMenu.Display(client, g_iMenuTime);
							return Plugin_Stop;
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

void OtkazMenuInitialized()
{
	Handle oprfile = OpenFile("addons/sourcemod/configs/otkaz_reasons.ini", "r");
	if (oprfile == null)
	{
		PrintToServer("Не удалось открыть файл addons/sourcemod/configs/otkaz_reasons.ini");
		return;
	}
	g_hMenu = new Menu(OtkazMenuHandler);
	char StR[85];
	SetMenuTitle(g_hMenu, "Выберите причину отказа:\n \n");
	while (!IsEndOfFile(oprfile) && ReadFileLine(oprfile, StR, sizeof(StR)))
	{
		g_hMenu.AddItem(StR, StR);
	}
	CloseHandle(oprfile);
	g_hMenu.ExitButton = true;
}

public int OtkazMenuHandler(Handle menu, MenuAction action, int client, int iSlot)
{
	if (action == MenuAction_Select)
	{
		g_iRoundUsed[client]++;
		if(g_iColor)
		{
			SetEntityRenderColor(client, 30, 20, 40, 255);
			g_hOtkaz_Timer[client] = CreateTimer(5.0, TimedColoring, client);
		}
		char Reason[85];
		GetMenuItem(menu, iSlot, Reason, sizeof(Reason));
		PrintToChatAll("%s\x04%N\x03 написал отказ. Причина: \x04%s", PREFIX, client, Reason);
	}
	else if(action == MenuAction_End)
	{
		return;
	}
}

public void OnClientDisconnect(int client)
{
	if (g_hOtkaz_Timer[client] != null)
	{
		KillTimer(g_hOtkaz_Timer[client]);
		g_hOtkaz_Timer[client] = null;
	}
}

public Action TimedColoring(Handle timer, any client)
{
	SetEntityRenderColor(client, 255, 255, 255, 255);
	g_hOtkaz_Timer[client] = null;
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