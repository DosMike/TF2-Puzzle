#if defined _tf2puzzle_gravihands
 #endinput
#endif
#define _tf2puzzle_gravihands

#if !defined _tf2puzzle
 #error Please compile the main file!
#endif

#define DUMMY_MODEL "models/class_menu/random_class_icon.mdl"
#define GRAB_DISTANCE 150.0
#define DROP_DISTANCE 200.0

#define GH_SOUND_PICKUP "weapons/physcannon/physcannon_pickup.wav"
#define GH_SOUND_DROP "weapons/physcannon/physcannon_drop.wav"
#define GH_SOUND_TOOHEAVY "weapons/physcannon/physcannon_tooheavy.wav"
#define GH_SOUND_INVALID "weapons/physcannon/physcannon_dryfire.wav"
#define GH_SOUND_THROW "weapons/physcannon/superphys_launch1.wav"
#define GH_ACTION_PICKUP 1
#define GH_ACTION_DROP 2
#define GH_ACTION_TOOHEAVY 3
#define GH_ACTION_INVALID 4
#define GH_ACTION_THROW 5

enum struct GraviPropData {
	int rotProxyEnt;
	int grabbedEnt;
	float previousEnd[3]; //allows flinging props
	float lastValid[3]; //prevent props from being dragged through walls
	bool dontCheckStartPost; //aabbs collide easily, allow pulling props out of those situations
	Collision_Group_t collisionFlags;// collisionFlags of held prop
	bool forceDropProp;
	bool blockPunt; //from spawnflags
	float grabDistance;
	float playNextAction;
	int lastAudibleAction;
	float nextPickup;
	
	void Reset() {
		this.rotProxyEnt = INVALID_ENT_REFERENCE;
		this.grabbedEnt = INVALID_ENT_REFERENCE;
		ScaleVector(this.previousEnd, 0.0);
		ScaleVector(this.lastValid, 0.0);
		this.dontCheckStartPost = false;
		this.forceDropProp = false;
		this.grabDistance = -1.0;
		this.playNextAction = 0.0;
		this.lastAudibleAction = 0;
		this.nextPickup = 0.0;
	}
}
GraviPropData GravHand[MAXPLAYERS+1];

// if we parent the entity to a dummy, we don't have to care about the offset matrix
static int getOrCreateProxyEnt(int client, float atPos[3]) {
	int ent = EntRefToEntIndex(GravHand[client].rotProxyEnt);
	if (ent == INVALID_ENT_REFERENCE) {
		ent = CreateEntityByName("prop_dynamic_override");//CreateEntityByName("info_target");
		DispatchKeyValue(ent, "model", DUMMY_MODEL);
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", 0.0);
		DispatchSpawn(ent);
		TeleportEntity(ent, atPos, NULL_VECTOR, NULL_VECTOR);
		GravHand[client].rotProxyEnt = EntIndexToEntRef(ent);
	}
	return ent;
}

public bool grabFilter(int entity, int contentsMask, int client) {
	return entity != client
		&& entity > MaxClients //never clients
		&& IsValidEntity(entity) //don't grab stale refs
		&& entity != EntRefToEntIndex(GravHand[client].rotProxyEnt) //don't grab rot proxies
		&& entity != EntRefToEntIndex(GravHand[client].grabbedEnt) //don't grab grabbed stuff
		&& GetEntPropEnt(entity, Prop_Send, "moveparent")==INVALID_ENT_REFERENCE; //never grab stuff that's parented (already)
}

//static char[] vecfmt(float vec[3]) {
//	char buf[32];
//	Format(buf, sizeof(buf), "(%.2f, %.2f, %.2f)", vec[0], vec[1], vec[2]);
//	return buf;
//}

static void computeBounds(float mins[3], float maxs[3]) {
	float v=8.0;
	//create equidistant box to keep origin of prop in world
	mins[0]=mins[1]=mins[2]= -v;
	maxs[0]=maxs[1]=maxs[2]=  v;
}

/** 
 * @param targetPoint as ray end or max distance in look direction
 * @return entity under cursor if any
 */
static int pew(int client, float targetPoint[3]) {
	float eyePos[3], eyeAngles[3];
	GetClientEyePosition(client, eyePos);
	GetClientEyeAngles(client, eyeAngles);
	Handle trace = TR_TraceRayFilterEx(eyePos, eyeAngles, MASK_SOLID, RayType_Infinite, grabFilter, client);
	int cursor = INVALID_ENT_REFERENCE;
	if(TR_DidHit(trace)) {
		float vecTarget[3];
		TR_GetEndPosition(vecTarget, trace);
		
		float maxdistance = (EntRefToEntIndex(GravHand[client].grabbedEnt)==INVALID_ENT_REFERENCE) ? GRAB_DISTANCE : GravHand[client].grabDistance;
		float distance = GetVectorDistance(eyePos, vecTarget);
		if(distance > maxdistance) {
			float fwrd[3];
			GetAngleVectors(eyeAngles, fwrd, NULL_VECTOR, NULL_VECTOR);
			NormalizeVector(fwrd, fwrd);
			ScaleVector(fwrd, maxdistance);
			AddVectors(eyePos, fwrd, targetPoint);
		} else {
			targetPoint = vecTarget;
		}
		
		int entity = TR_GetEntityIndex(trace);
		if (entity>0 && distance <= GRAB_DISTANCE) {
			char cn[64];
			GetEntityClassname(entity, cn, sizeof(cn));
			cursor = entity;
		}
	}
	CloseHandle(trace);
	return cursor;
}

static bool movementCollides(int client, float endpos[3], bool onlyTarget) {
	//check if prop would collide at target position
	float offset[3], from[3], to[3], mins[3], maxs[3];
	int grabbed = EntRefToEntIndex(GravHand[client].grabbedEnt);
	if (grabbed == INVALID_ENT_REFERENCE) ThrowError("%L is not currently grabbing anything", client);
	//get movement
	SubtractVectors(endpos, GravHand[client].lastValid, offset);
	Entity_GetAbsOrigin(grabbed, from);
	AddVectors(from, offset, to);
	if (onlyTarget) {
		from[0]=to[0]-0.1;
		from[1]=to[1]-0.1;
		from[2]=to[2]-0.1;
	}
	computeBounds(mins, maxs);
	//trace it
	Handle trace = TR_TraceHullFilterEx(from, to, mins, maxs, MASK_SOLID, grabFilter, client);
	bool result = TR_DidHit(trace);
	delete trace;
	return result;
}

bool clientCmdHoldProp(int client, int &buttons, float velocity[3], float angles[3]) {
//	float yawAngle[3];
//	yawAngle[1] = angles[1];
	int activeWeapon = Client_GetActiveWeapon(client);
	int defIndex = (activeWeapon == INVALID_ENT_REFERENCE) ? INVALID_ITEM_DEFINITION : GetEntProp(activeWeapon, Prop_Send, "m_iItemDefinitionIndex");
	if (defIndex == 5 && (buttons & IN_ATTACK2) && !GravHand[client].forceDropProp) {
		float clientTime = GetClientTime(client);
		if (GetEntPropFloat(activeWeapon, Prop_Send, "m_flNextPrimaryAttack") - clientTime < 0.1) {
			SetEntPropFloat(activeWeapon, Prop_Send, "m_flNextPrimaryAttack", clientTime + 1.0);
			SetEntPropFloat(activeWeapon, Prop_Send, "m_flNextSecondaryAttack", clientTime + 1.0);
		}
		if (GravHand[client].nextPickup - clientTime > 0) return false;
		
		int grabbed = EntRefToEntIndex(GravHand[client].grabbedEnt);
		//grabbing
		if (grabbed == INVALID_ENT_REFERENCE) { //try to pick up cursorEnt
			return TryPickupCursorEnt(client, angles);
		}
		ThinkHeldProp(client, grabbed, buttons, angles);
		return true;
	} else { //drop anything held
		return ForceDropItem(client, buttons & IN_ATTACK && GravHand[client].forceDropProp, velocity, angles);
	}
}

static bool TryPickupCursorEnt(int client, float yawAngle[3]) {
	float endpos[3], killVelocity[3];
	int cursorEnt = pew(client, endpos);
	if (cursorEnt == INVALID_ENT_REFERENCE) {
		PlayActionSound(client,GH_ACTION_INVALID);
		return false;
	}
	int rotProxy = getOrCreateProxyEnt(client, endpos);
	
	//check if cursor is a entity we can grab
	char classname[20];
	GetEntityClassname(cursorEnt, classname, sizeof(classname));
	if (StrContains(classname, "prop_physics")==0) {
		if (Entity_GetFlags(cursorEnt) & FL_FROZEN) {
			PlayActionSound(client,GH_ACTION_INVALID);
			return false;
		}
		int spawnFlags = Entity_GetSpawnFlags(cursorEnt);
		bool motion = Phys_IsMotionEnabled(cursorEnt);
		if ((spawnFlags & SF_PHYSPROP_ENABLE_ON_PHYSCANNON) && !motion) {
			Phys_EnableMotion(cursorEnt, true);
			motion = true;
		}
		if (!(spawnFlags & SF_PHYSPROP_ALWAYS_PICK_UP)) {
			if (spawnFlags & SF_PHYSPROP_PREVENT_PICKUP) {
				PlayActionSound(client,GH_ACTION_INVALID);
				return false;
			}
			if (GetEntityMoveType(cursorEnt)==MOVETYPE_NONE || !motion) {
				PlayActionSound(client,GH_ACTION_INVALID);
				return false;
			}
			if (Phys_GetMass(cursorEnt)>250.0) {
				PlayActionSound(client,GH_ACTION_TOOHEAVY);
				return false;
			}
		}
	} else if (StrContains(classname, "func_physbox")==0) {
		if (Entity_GetFlags(cursorEnt) & FL_FROZEN) {
			PlayActionSound(client,GH_ACTION_INVALID);
			return false;
		}
		int spawnFlags = Entity_GetSpawnFlags(cursorEnt);
		bool motion = Phys_IsMotionEnabled(cursorEnt);
		if ((spawnFlags & SF_PHYSBOX_ENABLE_ON_PHYSCANNON) && !motion) {
			Phys_EnableMotion(cursorEnt, true);
			motion = true;
		}
		if (!(spawnFlags & SF_PHYSBOX_ALWAYS_PICK_UP)) {
			if (spawnFlags & SF_PHYSBOX_NEVER_PICK_UP) {
				PlayActionSound(client,GH_ACTION_INVALID);
				return false;
			}
			if (GetEntityMoveType(cursorEnt)==MOVETYPE_NONE || !motion) {
				PlayActionSound(client,GH_ACTION_INVALID);
				return false;
			}
			if (Phys_GetMass(cursorEnt)>250.0) {
				PlayActionSound(client,GH_ACTION_TOOHEAVY);
				return false;
			}
		}
		GravHand[client].blockPunt = (spawnFlags & SF_PHYSBOX_NEVER_PUNT)!=0;
	} else {
		PlayActionSound(client,GH_ACTION_INVALID);
		return false;
	}
	//generate outputs
	FireEntityOutput(cursorEnt, "OnPhysGunPickup", client);
	//check if this entity is already grabbed
	for (int i=1;i<=MaxClients;i++) {
		if (cursorEnt == EntRefToEntIndex(GravHand[client].grabbedEnt)) {
			PlayActionSound(client,GH_ACTION_INVALID);
			return false;
		}
	}
	//position entities
	TeleportEntity(rotProxy, endpos, yawAngle, NULL_VECTOR);
	TeleportEntity(cursorEnt, NULL_VECTOR, NULL_VECTOR, killVelocity);
	//grab entity
	GravHand[client].grabbedEnt = EntIndexToEntRef(cursorEnt);
	float vec[3];
	GetClientEyePosition(client, vec);
	GravHand[client].grabDistance = Entity_GetDistanceOrigin(rotProxy, vec);
	//parent to make rotating easier
	SetVariantString("!activator");
	AcceptEntityInput(cursorEnt, "SetParent", rotProxy);
	//other setup
	GravHand[client].lastValid = endpos;
	GravHand[client].previousEnd = endpos;
	GravHand[client].dontCheckStartPost = movementCollides(client, endpos, true);
	GravHand[client].collisionFlags = Entity_GetCollisionGroup(cursorEnt);
	Entity_SetCollisionGroup(cursorEnt, COLLISION_GROUP_DEBRIS_TRIGGER);
	//sound
	PlayActionSound(client,GH_ACTION_PICKUP);
//	Phys_EnableCollisions(cursorEnt, false);
	return true;
}

static void ThinkHeldProp(int client, int grabbed, int buttons, float yawAngle[3]) {
	float endpos[3], killVelocity[3];
	pew(client, endpos);
	int rotProxy = getOrCreateProxyEnt(client, endpos);
	if (rotProxy != INVALID_ENT_REFERENCE && grabbed != INVALID_ENT_REFERENCE) { //holding
		if (!movementCollides(client, endpos, GravHand[client].dontCheckStartPost)) {
			if (buttons & IN_ATTACK && !GravHand[client].blockPunt) { //punt
				GravHand[client].forceDropProp = true;
				GravHand[client].nextPickup = GetClientTime(client) + 2.0;
			} else {
				GravHand[client].lastValid = endpos;
				GravHand[client].previousEnd = endpos;
				GravHand[client].dontCheckStartPost = false;
				TeleportEntity(rotProxy, endpos, yawAngle, killVelocity);
			}
		} else if (GetVectorDistance(GravHand[client].lastValid, endpos) > DROP_DISTANCE) {
			GravHand[client].forceDropProp = true;
		}
	}
}

bool ForceDropItem(int client, bool punt=false, const float dvelocity[3]=NULL_VECTOR, const float dvangles[3]=NULL_VECTOR) {
	bool didStuff = false;
	int entity;
	if ((entity = EntRefToEntIndex(GravHand[client].grabbedEnt))!=INVALID_ENT_REFERENCE) {
		float vec[3], origin[3];
		Entity_GetAbsOrigin(entity, origin);
		AcceptEntityInput(entity, "ClearParent");
		//fling
		bool didPunt;
		pew(client, vec);
		if (punt && !IsNullVector(dvangles)) { //punt
			GetAngleVectors(dvangles, vec, NULL_VECTOR, NULL_VECTOR);
			ScaleVector(vec, 100000.0/Phys_GetMass(entity));
//				AddVectors(vec, fwd, vec);
			didPunt=true;
		} else if (!movementCollides(client, vec, false)) { //throw with swing
			SubtractVectors(vec, GravHand[client].previousEnd, vec);
			ScaleVector(vec, 25.0); //give oomph
		} else {
			ScaleVector(vec, 0.0); //set 0
		}
		if (!IsNullVector(dvelocity)) AddVectors(vec, dvelocity, vec);
		TeleportEntity(entity, origin, NULL_VECTOR, vec);
		//fire output that the ent was dropped
		FireEntityOutput(entity, punt?"OnPhysGunPunt":"OnPhysGunDrop", client);
		//reset ref because we're nice
		Entity_SetCollisionGroup(entity, GravHand[client].collisionFlags);
		GravHand[client].grabbedEnt = INVALID_ENT_REFERENCE;
		didStuff = true;
		//play sound
		PlayActionSound(client,didPunt?GH_ACTION_THROW:GH_ACTION_DROP);
	}
	if ((entity = EntRefToEntIndex(GravHand[client].rotProxyEnt))!=INVALID_ENT_REFERENCE) {
		RequestFrame(killEntity, entity);
		GravHand[client].rotProxyEnt = INVALID_ENT_REFERENCE;
		didStuff = true;
	}
	GravHand[client].collisionFlags = COLLISION_GROUP_NONE;
	GravHand[client].grabDistance=0.0;
	GravHand[client].forceDropProp=false;
	return didStuff;
}

void PlayActionSound(int client, int sound) {
	float ct = GetClientTime(client);
	if (GravHand[client].lastAudibleAction != sound || GravHand[client].playNextAction - ct < 0) {
		switch (sound) {
			case GH_ACTION_PICKUP: {
				EmitSoundToAll(GH_SOUND_PICKUP);
				GravHand[client].playNextAction = ct + 1.5;
			}
			case GH_ACTION_DROP: {
				EmitSoundToAll(GH_SOUND_DROP);
				GravHand[client].playNextAction = ct + 1.5;
			}
			case GH_ACTION_TOOHEAVY: {
				EmitSoundToAll(GH_SOUND_TOOHEAVY);
				GravHand[client].playNextAction = ct + 1.5;
			}
			case GH_ACTION_INVALID: {
				EmitSoundToAll(GH_SOUND_INVALID);
				GravHand[client].playNextAction = ct + 0.5;
			}
			case GH_ACTION_THROW: {
				EmitSoundToAll(GH_SOUND_THROW);
				GravHand[client].playNextAction = ct + 0.5;
			}
			default: {
				GravHand[client].playNextAction = ct + 1.5;
			}
		}
		GravHand[client].lastAudibleAction = sound;
	}
}

static void killEntity(int entity) {
	if (IsValidEntity(entity))
		AcceptEntityInput(entity, "Kill");
}
