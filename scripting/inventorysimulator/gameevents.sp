/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

void GameEvents_Initialize()
{
    HookEvent("player_spawn", GameEvents_OnPlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", GameEvents_OnPlayerDeath, EventHookMode_Pre);
    HookEvent("round_mvp", GameEvents_OnRoundMvp, EventHookMode_Pre);
}

public void GameEvents_OnPlayerSpawn(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || IsFakeClient(client))
    {
        return;
    }

    InventorySimulator_InitializeClient(client);
    GameHooks_HookClient(client);
    InventorySimulator_SetInventoryWait(
        client,
        g_PlayerStates[client].fetching
    );

    RequestFrame(GameEvents_OnSpawnWearablesFrame, GetClientSerial(client));
}

public void GameEvents_OnSpawnWearablesFrame(any serial)
{
    int client = GetClientFromSerial(serial);
    if (client == 0)
    {
        return;
    }
    NativeItems_RefreshWearables(client);
}

public void GameEvents_OnPlayerDeath(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (attacker == 0
        || victim == 0
        || attacker == victim
        || IsFakeClient(attacker)
        || (IsFakeClient(victim) && g_CvarStatTrakIgnoreBots.BoolValue))
    {
        return;
    }

    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return;
    }

    int itemOffset = FindSendPropInfo("CBaseAttributableItem", "m_Item");
    if (itemOffset < 0)
    {
        return;
    }
    Address itemView = GetEntityAddress(weapon)
        + view_as<Address>(itemOffset);
    if (!NativeItems_IsGeneratedView(itemView, InventorySimulator_GetAccountId(attacker)))
    {
        return;
    }

    char eventItemId[32];
    char activeItemId[32];
    event.GetString("weapon_itemid", eventItemId, sizeof(eventItemId));
    NativeItems_GetItemIdString(
        itemView,
        activeItemId,
        sizeof(activeItemId)
    );
    if (eventItemId[0] == '\0' || !StrEqual(eventItemId, activeItemId))
    {
        return;
    }

    PlayerInventory inventory;
    if (!InventorySimulator_GetClientInventory(attacker, inventory))
    {
        return;
    }

    char weaponName[64];
    event.GetString("weapon", weaponName, sizeof(weaponName));
    InventoryItem item;
    int itemIndex;
    bool found;
    if (InventorySimulator_IsMeleeClassname(weaponName))
    {
        found = inventory.GetKnife(
            GetClientTeam(attacker),
            g_CvarFallbackTeam.BoolValue,
            item,
            itemIndex
        );
    }
    else
    {
        int definitionIndex = NativeItems_GetDefinitionIndexFromView(itemView);
        found = inventory.GetWeapon(
            GetClientTeam(attacker),
            definitionIndex,
            g_CvarFallbackTeam.BoolValue,
            item,
            itemIndex
        );
    }

    if (!found
        || itemIndex < 0
        || !item.hasStatTrak
        || item.stattrak < 0
        || !item.hasUid)
    {
        return;
    }

    item.stattrak++;
    inventory.SaveItemAt(itemIndex, item);
    NativeItems_UpdateStatTrak(itemView, item.stattrak);
    Api_SendStatTrak(g_PlayerStates[attacker].steamId, item.uid);
}

public void GameEvents_OnRoundMvp(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || IsFakeClient(client))
    {
        return;
    }

    PlayerInventory inventory;
    InventoryItem item;
    int itemIndex;
    if (!InventorySimulator_GetClientInventory(client, inventory)
        || !inventory.GetSingleItem(
            InventoryItem_MusicKit,
            item,
            itemIndex
        )
        || !item.hasStatTrak
        || item.stattrak < 0
        || !item.hasUid)
    {
        return;
    }

    item.stattrak++;
    inventory.SaveItemAt(itemIndex, item);
    event.SetInt("musickitmvps", item.stattrak);
    Api_SendStatTrak(g_PlayerStates[client].steamId, item.uid);
}
