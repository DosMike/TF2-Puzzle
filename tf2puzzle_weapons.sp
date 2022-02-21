#if defined _tf2puzzle_weapons
 #endinput
#endif
#define _tf2puzzle_weapons

#if !defined _tf2puzzle
 #error Please compile the main file!
#endif

//on the invalid default values:
// some stuff uses negative levels (like the physgun) as it shows positive but can mark custom weapons
// quality afaik is always positive
int EquipPlayerMelee(int client, int definitionIndex, int level=9000, int quality=-1, int attribCount=0, int customAttribIds[]={}, any customAttribVals[]={}) {
	if (!TF2EI_IsValidItemDefinition(definitionIndex))
		ThrowError("Definition index %d is invalid", definitionIndex);
	
	char class[72];
	int maxlvl;
	
	if (TF2EI_GetDefaultWeaponSlot(definitionIndex)!=TFWeaponSlot_Melee)
		ThrowError("Weapon %d (%s) uses non-melee slot!", definitionIndex, class);
	
	TF2EI_GetItemClassName(definitionIndex, class, sizeof(class));
	if (level > 255) TF2EI_GetItemLevelRange(definitionIndex, level, maxlvl);
	if (quality < 0) quality = TF2EI_GetItemQuality(definitionIndex);
	
	if (StrEqual(class, "saxxy") && !TF2EI_AdjustWeaponClassname(class, sizeof(class), TF2_GetPlayerClass(client)))
		ThrowError("Could not translate saxxy (%d) for player class %d", definitionIndex, TF2_GetPlayerClass(client));
	if (StrContains(class, "tf_weapon_")!=0 && !StrEqual(class, "saxxy"))
		ThrowError("Definition index %d (%s) is not a weapon", definitionIndex, class);
	
	int flags = FORCE_GENERATION|OVERRIDE_ITEM_DEF|OVERRIDE_ITEM_LEVEL|OVERRIDE_ITEM_QUALITY;
	if (attribCount>0) flags|=OVERRIDE_ATTRIBUTES;
	else flags|=PRESERVE_ATTRIBUTES;
	Handle weapon = TF2Items_CreateItem(flags);
	TF2Items_SetLevel(weapon, level);
	TF2Items_SetQuality(weapon, quality);
	TF2Items_SetNumAttributes(weapon, attribCount);
	for (int a; a<attribCount; a++) {
		TF2Items_SetAttribute(weapon, a, customAttribIds[a], customAttribVals[a]);
	}
	TF2Items_SetItemIndex(weapon, definitionIndex);
	TF2Items_SetClassname(weapon, class);
	
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
	int entity = TF2Items_GiveNamedItem(client, weapon);
	delete weapon;
	if (entity != INVALID_ENT_REFERENCE) {
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
	bool switchTo = (melee == INVALID_ENT_REFERENCE || active != melee); //if melee was not active switch, to holster guns
	int holsterIndex = melee == INVALID_ENT_REFERENCE 
		? INVALID_ITEM_DEFINITION
		: GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");
	if (holsterIndex == 5) return false; //this is heavy with stock fists, can't holster
	
	if ((GetClientButtons(client) & (IN_ATTACK|IN_ATTACK2))!=0) {
		//holstering while healing someone breaks the medic beam (infinite heal)
		PrintToChat(client, "[SM] You can not holster while holding attack buttons!");
		return false;
	}
	
	if (!NotifyWeaponHolster(client, holsterIndex)) return false; //was cancelled
	//copy melee into holster
	if (holsterIndex != INVALID_ITEM_DEFINITION) {
		player[client].holsteredWeapon = holsterIndex;
		player[client].holsteredMeta[0] = GetEntProp(melee, Prop_Send, "m_iEntityLevel");
		player[client].holsteredMeta[1] = GetEntProp(melee, Prop_Send, "m_iEntityQuality");
		//collect attributes. while up to 20 are supported here, we seem to only be able to restore 16 with tf2items
		int attribCount = TF2Attrib_ListDefIndices(melee, player[client].holsteredAttributeIds, sizeof(PlayerData::holsteredAttributeIds));
		if (attribCount > sizeof(PlayerData::holsteredAttributeIds))
			attribCount = sizeof(PlayerData::holsteredAttributeIds);
		for (int a; a<attribCount; a++)
			player[client].holsteredAttributeValues[a] = TF2Attrib_GetByDefIndex(melee, player[client].holsteredAttributeValues[a]);
		player[client].holsteredAttributeCount = attribCount;
	}
	//equip new melee
	int fists = EquipPlayerMelee(client, 5);
	if (fists == INVALID_ENT_REFERENCE) return false; //giving fists failed?
	if (switchTo) Client_SetActiveWeapon(client, fists);
		
	NotifyWeaponHolsterPost(client, holsterIndex);
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
	
	if ((GetClientButtons(client) & (IN_ATTACK|IN_ATTACK2))!=0) {
		//for symmetry reasons
		PrintToChat(client, "[SM] You can not unholster while holding attack buttons!");
		return;
	}
	if (!NotifyWeaponUnholster(client, player[client].holsteredWeapon))
		return; //was cancelled
	
	int restore = player[client].holsteredWeapon;
	player[client].holsteredWeapon = INVALID_ITEM_DEFINITION;
	if (restore != INVALID_ITEM_DEFINITION) {
		EquipPlayerMelee(client, restore, 
			player[client].holsteredMeta[0],
			player[client].holsteredMeta[1],
			player[client].holsteredAttributeCount,
			player[client].holsteredAttributeIds,
			player[client].holsteredAttributeValues);
	}
	NotifyWeaponUnholsterPost(client, restore, false);
}

void DropHolsteredMelee(int client) {
	if (player[client].holsteredWeapon == INVALID_ITEM_DEFINITION)
		return;
	int restore = player[client].holsteredWeapon;
	player[client].holsteredWeapon = INVALID_ITEM_DEFINITION;
	NotifyWeaponUnholsterPost(client, restore, true);
}