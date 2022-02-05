#if defined _tf2puzzle_econwrapper
 #endinput
#endif
#define _tf2puzzle_econwrapper

#if !defined _tf2puzzle
 #error Please compile the main file!
#endif

//this file will wrap multiple econ plugins to give me the data i need
// preferably it will use the newer tf econ data, falling back to tf2idb

public void __pl_tf_econ_data_SetNTVOptional() {
	//dont ask... this shouldn't be necessary with the compat layer, but that
	// still has minor problems preventing me from recommending it.
	//but since econ data is confident in being the ultimate never-to-be-replaced
	// replacement, it doesn't mark it's natives optional automatically (yet?)
	MarkNativeAsOptional("TF2Econ_IsValidItemDefinition");
	MarkNativeAsOptional("TF2Econ_IsItemInBaseSet");
	MarkNativeAsOptional("TF2Econ_GetItemName");
	MarkNativeAsOptional("TF2Econ_GetLocalizedItemName");
	MarkNativeAsOptional("TF2Econ_GetItemClassName");
	MarkNativeAsOptional("TF2Econ_GetItemLoadoutSlot");
	MarkNativeAsOptional("TF2Econ_GetItemDefaultLoadoutSlot");
	MarkNativeAsOptional("TF2Econ_GetItemEquipRegionMask");
	MarkNativeAsOptional("TF2Econ_GetItemEquipRegionGroupBits");
	MarkNativeAsOptional("TF2Econ_GetItemLevelRange");
	MarkNativeAsOptional("TF2Econ_GetItemQuality");
	MarkNativeAsOptional("TF2Econ_GetItemRarity");
	MarkNativeAsOptional("TF2Econ_GetItemStaticAttributes");
	MarkNativeAsOptional("TF2Econ_GetItemDefinitionString");
	MarkNativeAsOptional("TF2Econ_GetItemList");
	MarkNativeAsOptional("TF2Econ_TranslateWeaponEntForClass");
	MarkNativeAsOptional("TF2Econ_TranslateLoadoutSlotIndexToName");
	MarkNativeAsOptional("TF2Econ_TranslateLoadoutSlotNameToIndex");
	MarkNativeAsOptional("TF2Econ_GetLoadoutSlotCount");
	MarkNativeAsOptional("TF2Econ_IsValidAttributeDefinition");
	MarkNativeAsOptional("TF2Econ_IsAttributeHidden");
	MarkNativeAsOptional("TF2Econ_IsAttributeStoredAsInteger");
	MarkNativeAsOptional("TF2Econ_GetAttributeName");
	MarkNativeAsOptional("TF2Econ_GetAttributeClassName");
	MarkNativeAsOptional("TF2Econ_GetAttributeDefinitionString");
	MarkNativeAsOptional("TF2Econ_TranslateAttributeNameToDefinitionIndex");
	MarkNativeAsOptional("TF2Econ_GetQualityName");
	MarkNativeAsOptional("TF2Econ_TranslateQualityNameToValue");
	MarkNativeAsOptional("TF2Econ_GetQualityList");
	MarkNativeAsOptional("TF2Econ_GetRarityName");
	MarkNativeAsOptional("TF2Econ_TranslateRarityNameToValue");
	MarkNativeAsOptional("TF2Econ_GetRarityList");
	MarkNativeAsOptional("TF2Econ_GetEquipRegionGroups");
	MarkNativeAsOptional("TF2Econ_GetEquipRegionMask");
	MarkNativeAsOptional("TF2Econ_GetParticleAttributeSystemName");
	MarkNativeAsOptional("TF2Econ_GetParticleAttributeList");
	MarkNativeAsOptional("TF2Econ_GetPaintKitDefinitionList");
	MarkNativeAsOptional("TF2Econ_GetMapDefinitionIndexByName");
	MarkNativeAsOptional("TF2Econ_GetItemSchemaAddress");
	MarkNativeAsOptional("TF2Econ_GetProtoDefManagerAddress");
	MarkNativeAsOptional("TF2Econ_GetItemDefinitionAddress");
	MarkNativeAsOptional("TF2Econ_GetAttributeDefinitionAddress");
	MarkNativeAsOptional("TF2Econ_GetRarityDefinitionAddress");
	MarkNativeAsOptional("TF2Econ_GetParticleAttributeAddress");
	MarkNativeAsOptional("TF2Econ_GetPaintKitDefinitionAddress");
	MarkNativeAsOptional("TF2Econ_IsValidDefinitionIndex");
	MarkNativeAsOptional("TF2Econ_GetItemSlot");
}

static void PrintMissingPluginError() {
	//deduplicating strings here
	PrintToServer("[TF2Puzzle] Missing item plugin");
}

bool TF2EI_IsValidItemDefinition(int def) {
	if (depTFEconData)
		return TF2Econ_IsValidItemDefinition(def);
	else if (depTF2IDB)
		return TF2IDB_IsValidItemID(def);
	else {
		PrintMissingPluginError();
		return false;
	}
}

bool TF2EI_GetItemClassName(int def, char[] buffer, int length) {
	if (depTFEconData)
		return TF2Econ_GetItemClassName(def, buffer, length);
	else if (depTF2IDB)
		return TF2IDB_GetItemClass(def, buffer, length);
	else {
		PrintMissingPluginError();
		return false;
	}
}

bool TF2EI_GetItemLevelRange(int def, int& min, int& max) {
	if (depTFEconData)
		return TF2Econ_GetItemLevelRange(def, min, max);
	else if (depTF2IDB)
		return TF2IDB_GetItemLevels(def, min, max);
	else {
		PrintMissingPluginError();
		return false;
	}
}

int TF2EI_GetItemQuality(int def) {
	if (depTFEconData)
		return TF2Econ_GetItemQuality(def);
	else if (depTF2IDB)
		return view_as<int>(TF2IDB_GetItemQuality(def));
	else {
		PrintMissingPluginError();
		return 0;
	}
}

bool TF2EI_AdjustWeaponClassname(char[] className, int length, TFClassType playerClass) {
	if (depTFEconData)
		return TF2Econ_TranslateWeaponEntForClass(className, length, playerClass);
	else if (depTF2IDB) {
		if (StrEqual(className,"saxxy")) {
			//saxxys as allclass have to use the classes base melee weapon class to load the correct anims
			switch (playerClass) {
				case TFClass_Scout:    strcopy(className, length, "tf_weapon_bat");
				case TFClass_Sniper:   strcopy(className, length, "tf_weapon_club");
				case TFClass_Soldier:  strcopy(className, length, "tf_weapon_shovel");
				case TFClass_DemoMan:  strcopy(className, length, "tf_weapon_bottle");
				case TFClass_Medic:    strcopy(className, length, "tf_weapon_bonesaw");
				case TFClass_Heavy:    strcopy(className, length, "tf_weapon_fists");
				case TFClass_Pyro:     strcopy(className, length, "tf_weapon_fireaxe");
				case TFClass_Spy:      strcopy(className, length, "tf_weapon_knife");
				case TFClass_Engineer: strcopy(className, length, "tf_weapon_wrench");
				default: {
					PrintToServer("Could not resolve melee class name '%s' for player class %i", className, playerClass);
					return false;
				}
			}
			return true;
		}
		// All the fun other stuff like pistols, revolver, shotguns etc are left
		// as an exercise for the reader. I'm only interested in melee classnames.
		// And this, kids, is why we use tf econ data :)
		return true; //assume a legal melee weapon classname
	} else {
		PrintMissingPluginError();
		return false;
	}
}

/** 
 * WARNING: this method's return value will be inconsistent depending on the
 * plugin used! The only guarantee is that weapons (not unititly) from primary
 * to melee will always use 0,1,2 (just a happy shared accident).
 * DONT USE THIS FOR ANYTHING OUTSIDE OF WEAPONS!
 */
int TF2EI_GetDefaultWeaponSlot(int def) {
	if (depTFEconData)
		return TF2Econ_GetItemDefaultLoadoutSlot(def);
	else if (depTF2IDB) {
		return view_as<int>(TF2IDB_GetItemSlot(def));
	} else {
		PrintMissingPluginError();
		return false;
	}
}
