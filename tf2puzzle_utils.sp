#if defined _tf2puzzle_utils
 #endinput
#endif
#define _tf2puzzle_utils

#if !defined _tf2puzzle
 #error Please compile the main file!
#endif

//this abuses engine internals, but works
// if the passed value is already a ref, returns the ref
// otherwise gets the ref from the ent index
//static int SafeEntIndexToEntRef(int index) {
//	return index < 0 ? index : EntIndexToEntRef(index);
//}
//this abuses engine internals, but works
// if the passed value is already an index, returns the index
// otherwise gets the index from the ent ref
int SafeEntRefToEntIndex(int ref) {
	return ref >= 0 ? ref : EntRefToEntIndex(ref);
}


/**
 * Resets a players cooldowns: energy drink meter, hype meter, charge meter, cloak meter, stealth cooldown, rage meter, next rage earn time, kart boost cooldown
 * @error invalid client index or client not ingame
 */
void TF2PZ_ResetPlayerCooldowns(int client) {
	if (IsPlayerAlive(client)) {
		SetEntPropFloat(client, Prop_Send, "m_flEnergyDrinkMeter", 100.0);
		SetEntPropFloat(client, Prop_Send, "m_flHypeMeter", 100.0);
		SetEntPropFloat(client, Prop_Send, "m_flChargeMeter", 100.0);
		SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", 100.0);
		SetEntPropFloat(client, Prop_Send, "m_flStealthNextChangeTime", GetGameTime());
//		SetEntPropFloat(client, Prop_Send, "m_flChargeLevel", 1.0);
		SetEntPropFloat(client, Prop_Send, "m_flRageMeter", 100.0);
		SetEntPropFloat(client, Prop_Send, "m_flNextRageEarnTime", GetGameTime());
		SetEntPropFloat(client, Prop_Send, "m_flKartNextAvailableBoost", GetGameTime());
	}
}

/**
 * Strip weapons with a whitelist filter. This is usefull e.g. if you want to force trimping loadout.
 * The filter supports keeping weapon slots (numbers) and weapon classnames.
 * If the classname can be partial if it ends with '*'. (Will treat the word as prefix)
 *
 * @param client the player to strip
 * @param filter a space separated whitelist
 */
void TF2PZ_StripWeaponsFiltered(int client, const char[] filter) {
	UnholsterMelee(client);
	char whiteclass[16][64];
	//not using breakstring because we need all classnames collected for checking, saving string copyies this way
	int clz=ExplodeString(filter, " ", whiteclass, sizeof(whiteclass), sizeof(whiteclass[]));
	bool whiteslots[6];
	bool startsWith[16];
	int tmp;
	for (int c;c<clz;c++) {
		int l=strlen(whiteclass[c]);
		if (StringToIntEx(whiteclass[c], tmp)==l) {
			if (tmp < 1 || tmp > 5) continue;
			whiteslots[tmp-1] = true;
			whiteclass[c][0] = 0;
		} else if (l>1 && whiteclass[c][l-1]=='*') {
			whiteclass[c][l-1] = 0;
			startsWith[c] = true;
		}
	}
	int weapon;
	char class[64];
	int switchto=-1;
	for (int slot;slot<6;slot++) {
		bool keep;
		if (whiteslots[slot]) {
			keep = true;
		} else {
			weapon = Client_GetWeaponBySlot(client, slot);
			if (weapon == INVALID_ENT_REFERENCE) continue;
			Entity_GetClassName(weapon, class, sizeof(class));
			for (int c;c<clz;c++) {
				if (whiteclass[c][0]==0) continue;
				if (startsWith[c]) {
					keep = (StrContains(class,whiteclass[c])==0);
				} else {
					keep = (StrEqual(class,whiteclass[c]));
				}
			}
		}
		if (keep) {
			if (switchto==-1) switchto=slot;
		} else {
			if (slot == 2) {
				EquipPlayerMelee(client, 5);
				if (switchto==-1) switchto=2;
			} else TF2_RemoveWeaponSlot(client, slot);
		}
	}
	if (switchto!=-1) {
		Client_SetActiveWeapon(client, Client_GetWeaponBySlot(client, switchto));
	}
}

/**
 * Tries to spawn a Mikusch/source-vehicles vehicle by its configuration name.
 * Default configuration entries are hl2_jeep and hl2_airboat.
 * 
 * @param entity where to spawn the vehicle (origin and angles). e.g. info_target
 * @param vehicle configuration name
 * @error if the plugin is not loaded or the vehicle configuration is missing
 */
void TF2PZ_SpawnVehicleAt(int entity, const char[] name) {
	char buffer[4];
	if (!depVehicles) {
		ThrowError("[TF2Puzzle] Something tried to TF2PZ_SpawnVehicleAt without Mikusch/source-vehicles");
	} if (GetVehicleName(name, buffer, sizeof(buffer))) { //check vehicle exists
		float origin[3], angles[3];
		Entity_GetAbsOrigin(entity, origin);
		Entity_GetAbsAngles(entity, angles);
		Vehicle.Create(name, origin, angles);
	} else {
		ThrowError("[TF2Puzzle] Something tried to create vehicle with unknown id '%s'", buffer);
	}
}

/**
 * Meant for entities that have problems keeping targeted when working with templated
 * entities. Biggest offender here: ambient_generic. The target string is only parsed
 * when Activated (map start), even though it has members for target entity and target
 * entity index. When the target is a template and respawned, the ambient_generic will
 * just stop playing because the original target entity is gone. With this you can 
 * for a new target entity to play at. Sound already playing will not update.
 * 
 * @param entity - the entity to set a new target on
 * @param newTarget - the new target for the specified entity
 * @return true if the target entity is supported
 * @error entity or target entity is invalid 
 */
bool TF2PZ_RetargetEntity(int entity, int newTarget) {
	if (!IsValidEdict(newTarget)) ThrowError("Target entity is not valid");
	char targetClass[64];
	Entity_GetClassName(entity, targetClass, sizeof(targetClass));
	if (StrEqual(targetClass, "ambient_generic")) {
		// m_sSourceEntName is the targetname from which the entity is searched
		// m_hSoundSource +0x4d4 is the EHANDLE for the target entity
		// m_nSoundSourceEntIndex +0x4d8 is the intity index (i guess for speed?)
		// at some point those members were fields, but that's no more
		// and these values are only recalculated in the entities Activate
		// iif no m_hSoundSource was set before (so on map/game load)
		// to avoid having to recreate the entity, let's hack those values
		// to a value we find by the specified output targetname
		SetEntDataEnt2(entity, 0x4D4, newTarget, true);
		SetEntData(entity, 0x4D8, newTarget, _, true);
		return true;
	}
	return false;
}
/**
 * Same as RetargetEntity, but does a targetname lookup
 * 
 * @error if entity invalid or targetname doesn't match
 */
bool TF2PZ_RetargetEntityEx(int entity, const char[] targetname) {
	int newTarget = Entity_FindByName(targetname);
	if (newTarget == INVALID_ENT_REFERENCE) {
		ThrowError("Could not find entity to retarget: %s", targetname);
	}
	return TF2PZ_RetargetEntity(entity, newTarget);
}

//used this to find the target entity offset in ambient_generic (0x4D4, 0x4D8)
//poking the code i seem to have gotten some incorrect offsets
//public Action Command_Test(int client, int args) {
//	int edict = Edict_FindByHammerId(39973);
//	if (edict < 0) return Plugin_Handled;
//	
//	for (int offset=0x100;offset < 0x0500; offset+=4) {
//		int test=GetEntDataEnt2(edict, offset);
//		if (test != INVALID_ENT_REFERENCE) {
//			char classname[64];
//			GetEntityClassname(test, classname, sizeof(classname));
//			int next = GetEntData(edict, offset+4);
//			PrintToServer("Found entity %i (%s) at offset %04X, followed by %i", test, classname, offset, next);
//		}
//	}
//	return Plugin_Handled;
//}