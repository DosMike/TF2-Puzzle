#if defined _tf2puzzle_mapsupport
 #endinput
#endif
#define _tf2puzzle_mapsupport

#if !defined _tf2puzzle
 #error Please compile the main file!
#endif

enum struct OutputInfo {
	char output[64];
	char target[128];
	// input will always be "TF2Puzzle", that's how we id it's addressed to us
	char action[256]; // this is our actual command. the TF2Puzzle prefix already removed
	float delay;
	bool once;
	bool fired; //"runtime" pair for once 
}
enum struct EntityInfo {
	int hammerId;
	int entRef;
	int numOutputs;
	int startIndex;
}

ArrayList listOutputs;
ArrayList listEntityOutput;

void InitOutputCache() {
	if (listOutputs==null) listOutputs = new ArrayList(sizeof(OutputInfo));
	else listOutputs.Clear();
	if (listEntityOutput==null) listEntityOutput = new ArrayList(sizeof(EntityInfo));
	listEntityOutput.Clear();
}

/** @return true if changed */
bool ScanOutputs(char[] mapEntities) {
	InitOutputCache();
	
	char hammerId[128];
	char output[256];
	char parameters[1024];
	EntityInfo entityInfo;
	OutputInfo outputInfo;
	entityInfo.entRef = INVALID_ENT_REFERENCE;
	
	Regex hammerExp = new Regex("\"hammerid\" \"([0-9]+)\"");
	Regex outputExp = new Regex("\"(On[A-Z]\\w*)\" \"([^\"]+)\"");
	
	for (int current, next; (next = FindCharInString(mapEntities[current], '}')) != -1; current += (next + 2) ) {
		// get entity keyvalues
		char[] buffer = new char[next + 1];
		strcopy(buffer, next + 1, mapEntities[current]);
		
		// get hammerid
		if (hammerExp.Match(buffer) <= 0) continue;
		
		hammerExp.GetSubString(1, hammerId, sizeof(hammerId));
		entityInfo.hammerId = StringToInt(hammerId);
		entityInfo.numOutputs = 0;
		
		// get outputs
		for (int i = 0; outputExp.Match(buffer[i]) > 0; i += outputExp.MatchOffset()) {
			outputExp.GetSubString(1, output, sizeof(output));
			outputExp.GetSubString(2, parameters, sizeof(parameters));
			
			char splitParameters[5][256];
			ExplodeString(parameters, ",", splitParameters, sizeof(splitParameters), sizeof(splitParameters[]));
			
			if (StrEqual(splitParameters[1], "tf2puzzle", false) //starting the param with tf2puzzle is our signal to parse
			&& strlen(splitParameters[2])>1) { //ensure there's a custom action
				strcopy(outputInfo.output, sizeof(OutputInfo::output), output);
				strcopy(outputInfo.target, sizeof(OutputInfo::target), splitParameters[0]);
				strcopy(outputInfo.action, sizeof(OutputInfo::action), splitParameters[2]);
				outputInfo.delay = StringToFloat(splitParameters[3]);
				outputInfo.once = StringToInt(splitParameters[4]) > 0;
				
				listOutputs.PushArray(outputInfo);
				entityInfo.numOutputs++;
			}
		}
		
		if (entityInfo.numOutputs) {
			entityInfo.startIndex = listOutputs.Length - entityInfo.numOutputs;
			listEntityOutput.PushArray(entityInfo);
		}
	}
	int lumpsize=strlen(mapEntities);
	PrintToServer("[TF2Puzzle] Lump Info: %d/2097152 (%.2f%%)", lumpsize, lumpsize/20971.52);
	delete hammerExp;
	delete outputExp;
}

void AttachOutputHooks() {
	EntityInfo entityInfo;
	OutputInfo outputInfo;
	ArrayList hookedOutputs = new ArrayList(ByteCountToCells(128));
	for (int at; at<listEntityOutput.Length; at++) {
		listEntityOutput.GetArray(at, entityInfo);
		int edict = Edict_FindByHammerId(entityInfo.hammerId);
		listEntityOutput.Set(at, EntIndexToEntRef(edict), EntityInfo::entRef);
		if (!IsValidEntity(edict)) continue;
		int out = entityInfo.startIndex;
		int last = out + entityInfo.numOutputs;
		hookedOutputs.Clear();
		for (; out<last; out++) {
			listOutputs.GetArray(out, outputInfo);
			if (hookedOutputs.FindString(outputInfo.output)==-1) {
				hookedOutputs.PushString(outputInfo.output);
//				PrintToServer("[TF2Puzzle] Hooked %s on hammerId %d / ent %d", outputInfo.output, entityInfo.hammerId, entityInfo.entRef);
				HookSingleEntityOutput(edict, outputInfo.output, EntityOutputHandler);
			}
		}
	}
}

public void EntityOutputHandler(const char[] output, int caller, int activator, float delay) {
	//caller is the entity generating the output
	//the passed delay is poopoo
	
//	PrintToServer("[TF2Puzzle] Triggered output %s on hammerId %i by %i", output, Entity_GetHammerId(caller), activator);
	int at = listEntityOutput.FindValue(EntIndexToEntRef(caller), EntityInfo::entRef);
	if (at < 0) return;
	EntityInfo entityInfo;
	OutputInfo outputInfo;
	listEntityOutput.GetArray(at, entityInfo);
	int out = entityInfo.startIndex;
	int last = out + entityInfo.numOutputs;
	for (; out<last; out++) {
		listOutputs.GetArray(out, outputInfo);
		if (StrEqual(outputInfo.output, output)) {
			if (outputInfo.once && outputInfo.fired) continue;
			listOutputs.Set(out, true, OutputInfo::fired);
			int target = ResolveOutputTargetString(outputInfo.target, caller, activator);
			if (outputInfo.delay > 0) {
				DataPack data = new DataPack();
				data.WriteCell(caller);
				data.WriteCell(activator);
				data.WriteCell(target);
				data.WriteString(outputInfo.action);
				CreateTimer(outputInfo.delay, RunCustomOutputDelayed, data, TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE);
			} else {
				RunCustomOutput(caller, activator, target, outputInfo.action);
			}
		}
	}
}

static int ResolveOutputTargetString(const char[] target, int caller, int activator) {
	if (StrEqual(target, "!activator")) return activator;
	else if (StrEqual(target, "!self") || StrEqual(target, "!caller")) return caller;
	else return Entity_FindByName(target);
}

Action RunCustomOutputDelayed(Handle timer, Handle data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int caller = pack.ReadCell();
	int activator = pack.ReadCell();
	int target = pack.ReadCell();
	char action[256];
	pack.ReadString(action, sizeof(action));
	RunCustomOutput(caller, activator, target, action);
	return Plugin_Stop;
}

void RunCustomOutput(int caller, int activator, int target, const char[] action) {
	if (StrEqual(action, "strip", false)) {
		if (IsValidClient(target)) {
			TF2_RemoveAllWeapons(target);
			EquipPlayerMelee(target, 5);
		}
	} else if (StrEqual(action, "regenerate", false)) {
		if (IsValidClient(target)) {
			TF2_RegeneratePlayer(target);
		}
	} else if (StrEqual(action, "resetcooldowns", false)) {
		if (IsValidClient(target) && IsPlayerAlive(target)) {
			SetEntPropFloat(target, Prop_Send, "m_flEnergyDrinkMeter", 100.0);
			SetEntPropFloat(target, Prop_Send, "m_flHypeMeter", 100.0);
			SetEntPropFloat(target, Prop_Send, "m_flChargeMeter", 100.0);
			SetEntPropFloat(target, Prop_Send, "m_flCloakMeter", 100.0);
			SetEntPropFloat(target, Prop_Send, "m_flStealthNextChangeTime", GetGameTime());
//			SetEntPropFloat(target, Prop_Send, "m_flChargeLevel", 1.0);
			SetEntPropFloat(target, Prop_Send, "m_flRageMeter", 100.0);
			SetEntPropFloat(target, Prop_Send, "m_flNextRageEarnTime", GetGameTime());
			SetEntPropFloat(target, Prop_Send, "m_flKartNextAvailableBoost", GetGameTime());
		}
	} else if (StrContains(action, "stripwhitelist ", false)==0) {
		if (IsValidClient(target)) {
			UnholsterMelee(target);
			char whiteclass[16][64];
			int clz=ExplodeString(action[15], " ", whiteclass, sizeof(whiteclass), sizeof(whiteclass[]));
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
					weapon = Client_GetWeaponBySlot(target, slot);
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
						EquipPlayerMelee(target, 5);
						if (switchto==-1) switchto=2;
					} else TF2_RemoveWeaponSlot(target, slot);
				}
			}
			if (switchto!=-1) {
				Client_SetActiveWeapon(target, Client_GetWeaponBySlot(target, switchto));
			}
		}
	} else if (StrContains(action, "createvehicle ", false)==0) {
		if (IsValidEntity(target)) {
			char buffer[4];
			if (!depVehicles) {
				PrintToServer("[TF2Puzzle] Map Error: CreateVehicle output fired without Mikusch/source-vehicles");
			} else if (GetVehicleName(action[14], buffer, sizeof(buffer))) { //check vehicle exists
				float origin[3], angles[3];
				Entity_GetAbsOrigin(target, origin);
				Entity_GetAbsAngles(target, angles);
				Vehicle.Create(action[14], origin, angles);
			} else {
				PrintToServer("[TF2Puzzle] Map Error: Tried to create vehicle with unknown id '%s'");
			}
		}
	} else {
		PrintToServer("[TF2Puzzle] Map Error: Unknown TF2Puzzle Output '%s' from hammerId %i, triggered by %N", action, Entity_GetHammerId(caller), activator);
	}
}
