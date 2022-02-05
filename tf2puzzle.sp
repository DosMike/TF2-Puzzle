#if defined _tf2puzzle
 #endinput
#endif
#define _tf2puzzle

//generic includes
#include <clients>
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <regex>

//generic dependencies
#include <smlib>
#include "morecolors.inc"
#include <vphysics>

//game specific includes
#include <tf2>
#include <tf2_stocks>

//game specific dependencies
#include <tf2items>
#include <tf2attributes>

//game specific dependencies (optional)
#undef REQUIRE_PLUGIN
#include <vehicles>
// we primarily compile with tf2 econ data, but can optionally fall back to tf2idb
#include <tf_econ_data>
#tryinclude <tf2idb>
#define REQUIRE_PLUGIN

#pragma newdecls required
#pragma semicolon 1
//we require more heap in order to be able to parse the bsp lump. value is not yet optimized
#pragma dynamic 0x200000

#define PLUGIN_VERSION "22w05c"

public Plugin myinfo = {
	name = "[TF2] Puzzle",
	author = "reBane",
	description = "Utility to make puzzle maps work",
	version = PLUGIN_VERSION,
	url = "N/A"
}

// puzzle maps require being able to pick up props;
// so this plugin implements a disarmed state (having only fists)
// and handling prop_physics enabled states and inputs for when players try
// and pick them up.
// some puzzles might also require vehicles, so i recommend installing the
// vehicle plugin to make those work.
// in addition to moving prop and vehicles, this plugin also manages teams and
// team damage; to be more precise all players are forced into one team and
// player vs player damage is disabled.
// this plugin is also designed to run along normal maps for e.g. friendly
// servers, so unless the map name contains "_puzzle_", the team and damage 
// management is disabled

// note on how holstering works:
// basically, when you holster, the melee weapon is stripped and
// replaced with heavy's fists. that's a stock weapon so valve should be fine.
// additionally fists don't have a model, which is exactly what you want for
// "unarmed". the downside is, that heavies with stock melee can not use that
// as weapon.
// unholstering will regenerate the melee weapon with stock properties. this
// will nuke warpaints, attachments, decals from objectors, etc and probably 
// remove all custom attributes, but this is the easiest way

#define INVALID_ITEM_DEFINITION -1

bool bPuzzleMap;
enum struct PlayerData {
	float timeSpawned;
	bool handledDeath;
	int holsteredWeapon;
	
	void Reset() {
		this.timeSpawned     = 0.0;
		this.handledDeath    = false;
		this.holsteredWeapon = INVALID_ITEM_DEFINITION;
	}
}
PlayerData player[MAXPLAYERS+1];
bool depVehicles;
bool depTFEconData;
bool depTF2IDB;

//global structures and data defined, include submodules
#include "tf2puzzle_econwrapper.sp"
#include "tf2puzzle_weapons.sp"
#include "tf2puzzle_gravihands.sp"
#include "tf2puzzle_mapsupport.sp"

public void OnPluginStart() {
	
	RegConsoleCmd("sm_hands", Command_Holster, "Put away weapons");
	RegConsoleCmd("sm_holster", Command_Holster, "Put away weapons");
	
	HookEvent("player_death", OnClientDeathPost);
	HookEvent("teamplay_round_start", OnMapEntitiesRefreshed);
	HookEvent("teamplay_restart_round", OnMapEntitiesRefreshed);
	
	InitOutputCache();
	
	for (int client=1; client<=MaxClients; client++) {
		if (!IsValidClient(client)) continue;
		OnClientConnected(client);
		AttachClientHooks(client);
	}
}

public void OnAllPluginsLoaded() {
	depVehicles = LibraryExists("vehicles");
	depTFEconData = LibraryExists("tf_econ_data");
	depTF2IDB = LibraryExists("tf2idb");
	if (!depTFEconData && !depTF2IDB) {
		PrintToServer("[TF2Puzzle] No supported item plugin was detected after all plugins loaded! This plugin will akt broken!");
	}
}
public void OnLibraryAdded(const char[] name) {
	bool econ, hadEcon = depTFEconData||depTF2IDB;
	if (StrEqual(name, "vehicles")) depVehicles = true;
	else if (StrEqual(name, "tf_econ_data")) { econ = true; depTFEconData = true; }
	else if (StrEqual(name, "tf2idb")) { econ = true; depTF2IDB = true; }
	if (econ && !hadEcon) {
		PrintToServer("[TF2Puzzle] Item plugin was detected again!");
	}
}
public void OnLibraryRemoved(const char[] name) {
	bool econ;
	if (StrEqual(name, "vehicles")) depVehicles = false;
	else if (StrEqual(name, "tf_econ_data")) { econ = true; depTFEconData = false; }
	else if (StrEqual(name, "tf2idb")) { econ = true; depTF2IDB = false; }
	if (econ && !depTFEconData && !depTF2IDB) {
		PrintToServer("[TF2Puzzle] All supported item plugins were unloaded! This plugin will akt broken!");
	}
}

public Action OnLevelInit(const char[] mapName, char mapEntities[2097152]) {
	bPuzzleMap = (StrContains(mapName, "puzzle_")>=0);
	return (bPuzzleMap && ScanOutputs(mapEntities)) ? Plugin_Changed : Plugin_Continue;
}


public void OnMapStart() {
	PrecacheModel(DUMMY_MODEL);
	PrecacheSound(GH_SOUND_PICKUP);
	PrecacheSound(GH_SOUND_DROP);
	PrecacheSound(GH_SOUND_INVALID);
	PrecacheSound(GH_SOUND_TOOHEAVY);
	PrecacheSound(GH_SOUND_THROW);
}

public void OnMapEntitiesRefreshed(Event event, const char[] name, bool dontBroadcast) {
	AttachOutputHooks();
}

public void OnPluginEnd() {
	for (int i=1;i<=MaxClients;i++) {
		ForceDropItem(client);
		DropHolsteredMelee(client);
	}
}


public void OnClientConnected(int client) {
	player[client].Reset();
	GravHand[client].Reset();
}

public void OnClientDisconnect(int client) {
	ForceDropItem(client);
	player[client].Reset();
	GravHand[client].Reset();
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "player")) {
		AttachClientHooks(entity);
	}
}

void AttachClientHooks(int client) {
	SDKHook(client, SDKHook_SpawnPost, OnPlayerSpawnPost);
	SDKHook(client, SDKHook_OnTakeDamage, OnPlayerTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnPlayerTakeDamagePost);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost); //unholster on switch
	SDKHook(client, SDKHook_WeaponEquip, OnClientWeaponEquip); //drop holster if resupplied/otherwise equipped
}

public void OnPlayerSpawnPost(int client) {
	player[client].handledDeath = false;
}

public Action OnClientWeaponEquip(int client, int weapon) {
	if (!IsValidClient(client,false) || weapon == INVALID_ENT_REFERENCE) return Plugin_Continue;
	// THIS WOULD WORK BETTER WITH NOSOOPS TF2UTILS BUT I DON'T WANT TO INTRODUCE
	// ANOTHER DEPENDENCY. IF YOU THING IT'S WORTH IT, JUST INCLUDE THE PLUGIN AND 
	// SWAP COMMENTS FOR THE NEXT TWO LINES 
	//int slot = TF2Util_GetWeaponSlot(weapon);
	int slot = TF2EI_GetDefaultWeaponSlot(GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"));
	if (slot == TFWeaponSlot_Melee && player[client].holsteredWeapon != INVALID_ITEM_DEFINITION)
		DropHolsteredMelee(client); //melee was replaced
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (clientCmdHoldProp(client, buttons, vel, angles)) {
		buttons &=~ IN_ATTACK2;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action OnPlayerTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	if (IsValidClient(attacker) && victim != attacker) {
		if (weapon != INVALID_ENT_REFERENCE && GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")==5 && player[attacker].holsteredWeapon!=INVALID_ITEM_DEFINITION) {
			//this player is currently using fists, don't damage
			return Plugin_Handled;
		}
		if (bPuzzleMap) {
			//we're in a puzzle map - no pvp here
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnPlayerTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	if (GetClientHealth(victim)<=0) HandlePlayerDeath(victim);
}

public void OnClientDeathPost(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid", 0));
//	int attacker = GetClientOfUserId(event.GetInt("attacker", 0));
	HandlePlayerDeath(victim);
}

void HandlePlayerDeath(int client) {
	if (player[client].handledDeath) return;
	player[client].handledDeath = true;
	DropHolsteredMelee(client);
}

void OnClientWeaponSwitchPost(int client, int weapon) {
	if (!IsValidClient(client, false)) return;
	if (weapon != INVALID_ENT_REFERENCE && player[client].holsteredWeapon != INVALID_ITEM_DEFINITION) //no holstered weapon, always ok
		UnholsterMelee(client);
}

bool IsValidClient(int client, bool allowBots=true) {
	return ( 1<=client<=MaxClients && IsClientInGame(client) ) && ( allowBots || !IsFakeClient(client) );
}

public Action Command_Holster(int client, int args) {
	if (!IsValidClient(client,false)) return Plugin_Handled;
	if (player[client].holsteredWeapon!=INVALID_ITEM_DEFINITION) UnholsterMelee(client);
	else HolsterMelee(client);
	return Plugin_Handled;
}
