#if defined _tf2puzzle_weapons
 #endinput
#endif
#define _tf2puzzle_weapons

#if !defined _tf2puzzle
 #error Please compile the main file!
#endif

int EquipPlayerMelee(int client, int definitionIndex) {
	if (!TF2Econ_IsValidItemDefinition(definitionIndex))
		ThrowError("Definition index %d is invalid", definitionIndex);
	Handle weapon = TF2Items_CreateItem(FORCE_GENERATION|PRESERVE_ATTRIBUTES);
	char class[72];
	int minlvl, maxlvl, quality;
	TF2Econ_GetItemClassName(definitionIndex, class, sizeof(class));
	TF2Econ_GetItemLevelRange(definitionIndex, minlvl, maxlvl);
	quality = TF2Econ_GetItemQuality(definitionIndex);
	if (StrEqual(class, "saxxy") && !TF2Econ_TranslateWeaponEntForClass(class, sizeof(class), TF2_GetPlayerClass(client)))
		ThrowError("Could not translate saxxy (%d) for player class %d", definitionIndex, TF2_GetPlayerClass(client));
	if (StrContains(class, "tf_weapon_")!=0 && !StrEqual(class, "saxxy"))
		ThrowError("Definition index %d (%s) is not a weapon", definitionIndex, class);
	
	TF2Items_SetLevel(weapon, minlvl);
	TF2Items_SetQuality(weapon, quality);
	TF2Items_SetNumAttributes(weapon, 0);
	TF2Items_SetItemIndex(weapon, definitionIndex);
	TF2Items_SetClassname(weapon, class);
	
	int entity = TF2Items_GiveNamedItem(client, weapon);
	delete weapon;
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
	if (entity != INVALID_ENT_REFERENCE) {
		if (TF2Util_GetWeaponSlot(entity)!=TFWeaponSlot_Melee) {
			AcceptEntityInput(entity, "Kill");
			ThrowError("Weapon %d (%s) uses non-melee slot!", definitionIndex, class);
		}
		SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
		SetEntProp(entity, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
		EquipPlayerWeapon(client, entity);
	}
	return entity;
}

bool HolsterMelee(int client) {
	if (!IsValidClient(client, false))
		return false; //not for bots
	if (player[client].holsteredWeapon != INVALID_ITEM_DEFINITION) 
		return false; //already holstered
	int active = Client_GetActiveWeapon(client);
	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee == INVALID_ENT_REFERENCE) return false; //a-posing, haaaalp
	bool switchTo = (active != melee); //if melee was not active switch, to holster guns
	int holsterIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");
	if (holsterIndex == 5) return false; //this is heavy with stock fists, can't holster
	int fists = EquipPlayerMelee(client, 5);
	if (switchTo) Client_SetActiveWeapon(client, fists);
	player[client].holsteredWeapon = holsterIndex;
	return true;
}

void UnholsterMelee(int client) {
	//doing this immediately causes too many issues with regenerating inventories
	//an unholster as in an actual unholster will always be manual and thus
	//does not require tick precision
	RequestFrame(ActualUnholsterMelee, client);
}
void ActualUnholsterMelee(int client) {
	if (!IsValidClient(client, false))
		return; //not for bots
	if (player[client].holsteredWeapon == INVALID_ITEM_DEFINITION)
		return; //no weapon holstered
	int restore = player[client].holsteredWeapon;
	player[client].holsteredWeapon = INVALID_ITEM_DEFINITION;
	EquipPlayerMelee(client, restore);
}

void DropHolsteredMelee(int client) {
	player[client].holsteredWeapon = INVALID_ITEM_DEFINITION;
}