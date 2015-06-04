#if defined _warden_included
  #endinput
#endif
#define _warden_included

public SharedPlugin:__pl_warden =
{
	name = "warden",
	file = "warden.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};

/*********************************************************
 * Checks if any warden exist
 *
 * @true on match , false if not
 *********************************************************/
native warden_exist();

/*********************************************************
 * returns if client is warden
 *
 * @param client		The client to run the check on
 * @true on match, false if not		
 *********************************************************/
native warden_iswarden(client);

/*********************************************************
 * Set a client as warden
 *
 * @param client		The client to set as warden
 * @NoReturn
 *********************************************************/
native warden_set(client);

/*********************************************************
 * Removes the current warden if he exists
 *
 * @param client		The warden client to remove
 * @NoReturn	
 *********************************************************/
native warden_remove(client);

#if !defined REQUIRE_PLUGIN
public __pl_warden_SetNTVOptional()
{
	MarkNativeAsOptional("warden_exist");
	MarkNativeAsOptional("warden_iswarden");
	MarkNativeAsOptional("warden_set");
	MarkNativeAsOptional("warden_remove");
}
#endif