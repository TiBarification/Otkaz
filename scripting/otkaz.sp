#include <sourcemod>
#include <cstrike>
#include <sdktools>

#define VERSION "1.3"
#define PREFIX "\x04[\x03Отказ\x04]\x03 "

new Handle:Enable;
new Handle:hRoundUse, iRoundUse;
new Handle:hColor;
new Handle:hMenuTime;
new Handle:otkaz_timer[MAXPLAYERS+1];
new Handle:hMenu = INVALID_HANDLE;
new iRoundUsed[MAXPLAYERS+1];
new iMenuTime;

new const String:Cmds[] = "configs/otkaz_cmds.ini";
new const String:Reasons[] = "configs/otkaz_reasons.ini";

public Plugin:myinfo =
{
	name = "JailBreak Otkaz",
	description = "Command for T, that allow to abort commands comander.",
	author = "White Wolf",
	version = VERSION,
	url = "http://arena-igr.ru"
};

public OnPluginStart()
{
	CreateConVar("sm_otkaz_version", VERSION, _, FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_SPONLY);
	Enable = CreateConVar("sm_otkaz_enable", "1", "Включение/Выключение плагина.", FCVAR_PLUGIN|FCVAR_REPLICATED|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	hRoundUse = CreateConVar("sm_otkaz_per_round", "3", "Сколько отказов доступно за раунд.", FCVAR_PLUGIN|FCVAR_DONTRECORD, true, 0.0);
	hColor = CreateConVar("sm_otkaz_player_color", "1", "Красить игрока в синий цвет, когда он пишет отказ?", FCVAR_PLUGIN|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	hMenuTime = CreateConVar("sm_otkaz_menu_time", "20", "Сколько секунд активно меню игрока.", FCVAR_PLUGIN|FCVAR_DONTRECORD, true, 0.0);
	iMenuTime = GetConVarInt(hMenuTime);
	iRoundUse = GetConVarInt(hRoundUse);
	HookConVarChange(hRoundUse, OnConVarChange);
	
	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	
	decl String:sBuffer[PLATFORM_MAX_PATH];
	decl String:sBuffer2[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sBuffer, sizeof(sBuffer), Cmds);
	BuildPath(Path_SM, sBuffer2, sizeof(sBuffer2), Reasons);
	if(!FileExists(sBuffer))
	{
		SetFailState("Не найден файл %s", sBuffer);
	}
	else if(!FileExists(sBuffer2))
	{
		SetFailState("Не найден файл %s", sBuffer2);
	}
	new Handle:hFile = OpenFile(sBuffer, "r");
	
	if(hFile != INVALID_HANDLE)
	{
		while (!IsEndOfFile(hFile) && ReadFileLine(hFile, sBuffer, sizeof(sBuffer)))
		{
			TrimString(sBuffer);
			
			if (sBuffer[0])
			{
				RegConsoleCmd(sBuffer, Reset);
			}
		}
		//SetFailState("Не удалось открыть файл %s", sBuffer);
		CloseHandle(hFile);
	}
	
	OtkazMenuInitialized();
	
	AutoExecConfig(true, "otkaz");
}

public OnConVarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	iRoundUse = StringToInt(newValue);
	iMenuTime = StringToInt(newValue);
}

public OnRoundStart(Handle:event, const String:name[], bool:donBroadcast)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		iRoundUsed[i] = 0;
	}
}

public Action:Reset(client, args)
{
	if(!GetConVarBool(Enable))
	{
		return Plugin_Continue;
	}
	if(!IsFakeClient(client) && IsClientInGame(client))
	{
		if(GetClientTeam(client) == 2)
		{
			if (iRoundUse > 0 && iRoundUsed[client] >= iRoundUse)
			{
				PrintToChat(client, "%sВы не можете использовать отказ больше чем %i раз(а).", PREFIX, iRoundUse);
				return Plugin_Handled;
			}
			if(IsPlayerAlive(client))
			{
				if (iMenuTime == 0)
				{
					DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
				}
				else
				{
					DisplayMenu(hMenu, client, iMenuTime);
				}
			}
			else
			{
				PrintToChat(client, "%sВы должны быть живы.", PREFIX);
			}
		}
		else
		{
			PrintToChat(client, "%sВы должны быть заключенным.", PREFIX);
		}
	}
	return Plugin_Handled;
}

OtkazMenuInitialized()
{
	new Handle:oprfile = OpenFile("addons/sourcemod/configs/otkaz_reasons.ini", "r");
	if (oprfile == INVALID_HANDLE)
	{
		PrintToServer("Не удалось открыть файл addons/sourcemod/configs/otkaz_reasons.ini");
		return;
	}
	hMenu = CreateMenu(OtkazMenuHandler);
	decl String:StR[85];
	SetMenuTitle(hMenu, "Выберите причину отказа:\n \n");
	while (!IsEndOfFile(oprfile) && ReadFileLine(oprfile, StR, sizeof(StR)))
	{
		AddMenuItem(hMenu, StR, StR);
	}
	CloseHandle(oprfile);
	SetMenuExitBackButton(hMenu, false);
	SetMenuExitButton(hMenu, true);
}

public OtkazMenuHandler(Handle:menu, MenuAction:action, client, iSlot)
{
	if (action == MenuAction_Select)
	{
		iRoundUsed[client]++;
		if(GetConVarBool(hColor))
		{
			SetEntityRenderColor(client, 0, 0, 255, 255);
			otkaz_timer[client] = CreateTimer(1.5, TimedColoring, client);
		}
		decl String:Reason[85];
		GetMenuItem(menu, iSlot, Reason, 85);
		PrintToChatAll("%s\x07FF0000%N\x03 написал отказ. Причина: \x070000FF%s", PREFIX, client, Reason);
	}
	else if(action == MenuAction_End)
	{
		//CloseHandle(menu);
		return;
	}
}

public OnClientDisconnect(client)
{
	if (otkaz_timer[client] != INVALID_HANDLE)
	{
		KillTimer(otkaz_timer[client]);
		otkaz_timer[client] = INVALID_HANDLE;
	}
}

public Action:TimedColoring(Handle:timer, any:client)
{
	SetEntityRenderColor(client, 255, 255, 255, 255);
	otkaz_timer[client] = INVALID_HANDLE;
}