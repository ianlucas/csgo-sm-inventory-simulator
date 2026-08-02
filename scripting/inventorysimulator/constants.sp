/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#define INVSIM_VERSION "1.0.0"
#define INVSIM_GAMEDATA "inventorysimulator.games"
#define INVSIM_MAX_URL 512
#define INVSIM_MAX_BODY 262144
#define INVSIM_MAX_HASH 96
#define INVSIM_MAX_NAMETAG 64
#define INVSIM_ITEM_VIEW_SIZE 512
#define INVSIM_HTTP_MAX_RETRIES 3
// Mirrors the rate limit enforced by Inventory Simulator's public API.
#define INVSIM_STATTRAK_RATE_LIMIT_CAPACITY 50.0
#define INVSIM_STATTRAK_RATE_LIMIT_REFILL_INTERVAL 3.6
#define INVSIM_LOADOUT_SLOT_COUNT 57

#define INVSIM_MINMODELS_MAP 1
#define INVSIM_MINMODELS_CLASSIC 2

#define INVSIM_AGENT_PHOENIX 5200
#define INVSIM_AGENT_SAS 5600

#define INVSIM_TEAM_T 2
#define INVSIM_TEAM_CT 3

#define INVSIM_GENERATED_ITEM_ID_LOW 730521531
#define INVSIM_GENERATED_ITEM_ID_HIGH 15

enum LoadoutSlot
{
    Loadout_Invalid = -1,
    Loadout_Melee = 0,
    Loadout_C4 = 1,
    Loadout_FirstWeapon = 0,
    Loadout_LastWeapon = 25,
    Loadout_FirstGrenade = 26,
    Loadout_LastGrenade = 31,
    Loadout_FirstEquipment = 32,
    Loadout_LastEquipment = 37,
    Loadout_ClothingAppearance = 38,
    Loadout_ClothingTorso = 39,
    Loadout_ClothingLowerBody = 40,
    Loadout_ClothingHands = 41,
    Loadout_ClothingHat = 42,
    Loadout_ClothingFaceMask = 43,
    Loadout_ClothingEyewear = 44,
    Loadout_ClothingCustomHead = 45,
    Loadout_ClothingCustomPlayer = 46,
    Loadout_MusicKit = 54,
    Loadout_Flair0 = 55,
    Loadout_Spray0 = 56
};

enum InventoryItemKind
{
    InventoryItem_None,
    InventoryItem_Agent,
    InventoryItem_Collectible,
    InventoryItem_Glove,
    InventoryItem_Knife,
    InventoryItem_MusicKit,
    InventoryItem_Weapon
};

int InventorySimulator_ToggleTeam(int team)
{
    return team == INVSIM_TEAM_T ? INVSIM_TEAM_CT : INVSIM_TEAM_T;
}

bool InventorySimulator_IsMeleeClassname(const char[] classname)
{
    return StrContains(classname, "knife", false) != -1
        || StrContains(classname, "bayonet", false) != -1;
}
