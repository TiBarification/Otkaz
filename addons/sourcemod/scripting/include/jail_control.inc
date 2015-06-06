#if defined _jail_control_included
	#endinput
#endif
#define _jail_control_included

public SharedPlugin:__pl_jail_control =
{
	name = "jail_control",
	file = "jail_control.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};

/**
 **********************************************
 * СОБЫТИЯ
 **********************************************
**/

// Живой ct стал командиром.
forward Event_JailCommanderChosen(client);

// Живой ct стал ЗАМом командира.
forward Event_JailZamChosen(client);

/**
 * Командир покинул должность.
 * Если bool:himself true, то сделал это сам (выбрал опцию "покинуть пост").
 * В другом случае, он вышел с сервера или перешел в другую команду.
**/
forward Event_JailCommanderResigned(client, bool:himself);

/**
 * Командир выбрал опцию в меню
 *
 * client			- командир
 * ActionName		- действие, например, "menu_order" (все они в commander_menu.txt)
 * menu				- меню командира
 * item				- позиция опции в меню
 *
 * return:
 * Plugin_Continue	- продолжить/разрешить выполнить действие
 * Plugin_Stop		- запретить (закрытие меню)
**/
forward Action:Event_CommanderMenuSelect(client, const String:ActionName[], Handle:menu, item);

/**
 * Вызывается перед бунтом
 *
 * prisoner			- T, который бунтует
 * ct				- CT
 *
 * return:
 * Plugin_Continue	- Заключенный (prisoner) станет бунтующим
 * Plugin_Stop		- Нет
**/
forward Action:Event_JailPrisonerBuntuet(prisoner, ct);


///


/**
 **********************************************
 * ФУНКЦИИ
 **********************************************
**/

// Индекс командира
native Jail_GetCommander();

// Индекс ЗАМа
native Jail_GetZam();

// Игрок командир?
native bool:Jail_IsClientCommander(client);

// Игрок ЗАМ командира?
native bool:Jail_IsClientZam(client);

// У игрока FreeDay?
native bool:Jail_PrisonerHaveFreeday(client);

// Игрок в карцере?
native bool:Jail_PrisonerInIsolator(client);

// Бунтует?
native bool:Jail_PrisonerBuntuet(client);

// Удалить опцию из меню командира - вернет true в случае успеха
// item	- позиция опции в меню
native bool:Jail_RemoveItemFromCommanderMenu(item);

// Назначить нового ЗАМа командира.
// Можно указать 0, чтобы просто забрать права у текущего ЗАМа.
native bool:Jail_SetCommanderZam(client);

// Назначить нового командира.
// Можно указать 0, чтобы просто забрать права у текущего командира.
native bool:Jail_SetCommander(client);

#if !defined REQUIRE_PLUGIN
public __pl_jail_control_SetNTVOptional()
{
	MarkNativeAsOptional("Jail_GetCommander");
	MarkNativeAsOptional("Jail_GetZam");
	MarkNativeAsOptional("Jail_IsClientCommander");
	MarkNativeAsOptional("Jail_IsClientZam");
	MarkNativeAsOptional("Jail_PrisonerHaveFreeday");
	MarkNativeAsOptional("Jail_PrisonerInIsolator");
	MarkNativeAsOptional("Jail_PrisonerBuntuet");
	MarkNativeAsOptional("Jail_RemoveItemFromCommanderMenu");
	MarkNativeAsOptional("Jail_SetCommanderZam");
	MarkNativeAsOptional("Jail_SetCommander");
}
#endif