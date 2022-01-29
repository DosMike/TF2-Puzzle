#if defined _tf2puzzle
 #endinput
#endif
#define _tf2puzzle

#include <clients>
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include <smlib>
#include "morecolors.inc"
#include <vphysics>

#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <tf2utils>
#include <tf2attributes>
#include <tf_econ_data>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION

public Plugin myinfo = {
	name = "[TF2] Puzzle",
	author = "reBane",
	description = "Utility to make puzzle maps work",
	version = "22w04a",
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

//global structures and data defined, include submodules
#include "tf2puzzle_weapons.sp"
#include "tf2puzzle_gravihands.sp"

public void OnPluginStart() {
	
	RegConsoleCmd("sm_hands", Command_Holster, "Put away weapons");
	RegConsoleCmd("sm_holster", Command_Holster, "Put away weapons");
	
	HookEvent("player_death", OnClientDeathPost);
//	HookEvent("post_inventory_application", OnClientInventoryRegeneratePost);
	
	for (int client=1; client<=MaxClients; client++) {
		if (!IsValidClient(client)) continue;
		OnClientConnected(client);
		AttachClientHooks(client);
	}
}

public void OnMapStart() {
	char mapname[128];
	GetCurrentMap(mapname, sizeof(mapname));
	bPuzzleMap = (StrContains(mapname, "_puzzle_")>=0);
	
	PrecacheModel(DUMMY_MODEL);
	PrecacheSound(GH_SOUND_PICKUP);
	PrecacheSound(GH_SOUND_DROP);
	PrecacheSound(GH_SOUND_INVALID);
	PrecacheSound(GH_SOUND_TOOHEAVY);
	PrecacheSound(GH_SOUND_THROW);
}

public void OnClientConnected(int client) {
	player[client].Reset();
	GravHand[client].Reset();
}

public void OnClientDisconnect(int client) {
	ForceDropItem(client);
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
	int slot = TF2Util_GetWeaponSlot(weapon);
	if (slot == TFWeaponSlot_Melee && player[client].holsteredWeapon != INVALID_ITEM_DEFINITION)
		DropHolsteredMelee(client); //melee was replaced
	return Plugin_Continue;
}

//public void OnClientInventoryRegeneratePost(Event event, const char[] name, bool dontBroadcast) {
//	// for some reason the event gets called a lot on initial join
//	int client = GetClientOfUserId(event.GetInt("userid", 0));
//	if (!IsValidClient(client,false) || TF2_GetClientTeam(client)<=TFTeam_Spectator || !IsPlayerAlive(client)) return;
//	
//}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (clientCmdHoldProp(client, buttons, angles)) {
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

public Action Command_Test(int client, int args) {
	if (!IsValidClient(client,false)) return Plugin_Handled;
	TF2_RegeneratePlayer(client);
	return Plugin_Handled;
}