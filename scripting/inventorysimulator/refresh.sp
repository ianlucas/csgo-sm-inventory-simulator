/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

enum RefreshWeaponSwitchStage
{
    RefreshWeaponSwitch_None,
    RefreshWeaponSwitch_SelectReplacement,
    RefreshWeaponSwitch_SelectAlternate,
    RefreshWeaponSwitch_SelectReplacementAgain
};

int g_PendingActiveWeapons[MAXPLAYERS + 1];
int g_PendingAlternateWeapons[MAXPLAYERS + 1];
RefreshWeaponSwitchStage g_PendingWeaponSwitchStages[MAXPLAYERS + 1];

void Refresh_ApplyInventory(
    int client,
    bool restoring = false,
    PlayerInventory previousInventory = null
)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    PlayerInventory inventory;
    bool hasInventory = InventorySimulator_GetClientInventory(client, inventory);
    int team = GetClientTeam(client);

    InventoryItem glove;
    InventoryItem previousGlove;
    int itemIndex;
    bool hasGlove = hasInventory && inventory.GetGloves(
        team,
        g_CvarFallbackTeam.BoolValue,
        glove,
        itemIndex
    );
    bool hadGlove = previousInventory != null
        && previousInventory.GetGloves(
            team,
            g_CvarFallbackTeam.BoolValue,
            previousGlove,
            itemIndex
        );
    if (restoring
        || Refresh_ItemsChanged(hasGlove, glove, hadGlove, previousGlove))
    {
        if (!hasGlove)
        {
            NativeItems_ForgetItemView(
                client,
                team,
                view_as<int>(Loadout_ClothingHands)
            );
        }
        NativeItems_RefreshWearables(client);
    }

    InventoryItem agent;
    InventoryItem previousAgent;
    bool hasAgent = hasInventory && inventory.GetItemForSlot(
        team,
        view_as<int>(Loadout_ClothingAppearance),
        0,
        g_CvarFallbackTeam.BoolValue,
        g_CvarMinModels.IntValue,
        agent,
        itemIndex
    );
    bool hadAgent = previousInventory != null
        && previousInventory.GetItemForSlot(
            team,
            view_as<int>(Loadout_ClothingAppearance),
            0,
            g_CvarFallbackTeam.BoolValue,
            g_CvarMinModels.IntValue,
            previousAgent,
            itemIndex
        );
    if (restoring
        || Refresh_ItemsChanged(hasAgent, agent, hadAgent, previousAgent))
    {
        if (!hasAgent)
        {
            NativeItems_ForgetItemView(
                client,
                team,
                view_as<int>(Loadout_ClothingAppearance)
            );
        }
        CS_UpdateClientModel(client);
        NativeItems_ApplyAgentModel(client);
    }

    g_PendingActiveWeapons[client] = 0;
    g_PendingAlternateWeapons[client] = 0;
    g_PendingWeaponSwitchStages[client] = RefreshWeaponSwitch_None;
    bool activeWeaponNeedsStickerSwitch = false;
    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    int ownerXuid[2];
    StringToInt64(g_PlayerStates[client].steamId, ownerXuid);
    for (int slot = CS_SLOT_PRIMARY; slot <= CS_SLOT_KNIFE; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon <= MaxClients || !IsValidEntity(weapon))
        {
            continue;
        }

        InventoryItem item;
        InventoryItem previousItem;
        bool hasItem = Refresh_GetSimulatedItem(
            client,
            weapon,
            inventory,
            hasInventory,
            item
        );
        bool hadItem = Refresh_GetSimulatedItem(
            client,
            weapon,
            previousInventory,
            previousInventory != null,
            previousItem
        );
        if (!restoring
            && !Refresh_ItemsChanged(
                hasItem,
                item,
                hadItem,
                previousItem
            ))
        {
            continue;
        }
        if (!HasEntProp(
                weapon,
                Prop_Send,
                "m_OriginalOwnerXuidLow"
            )
            || GetEntProp(
                weapon,
                Prop_Send,
                "m_OriginalOwnerXuidLow"
            ) != ownerXuid[0])
        {
            continue;
        }

        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));
        Address definition = NativeItems_GetDefinitionByName(classname);
        int loadoutSlot = NativeItems_GetLoadoutSlot(definition);
        int definitionIndex = HasEntProp(
            weapon,
            Prop_Send,
            "m_iItemDefinitionIndex"
        )
            ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")
            : 0;
        if (!restoring && !hasItem)
        {
            NativeItems_ForgetItemView(client, team, loadoutSlot);
        }
        int clip = -1;
        int reserve = -1;
        if (HasEntProp(weapon, Prop_Send, "m_iClip1"))
        {
            clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
        }
        if (HasEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount"))
        {
            reserve = GetEntProp(
                weapon,
                Prop_Send,
                "m_iPrimaryReserveAmmoCount"
            );
        }
        bool wasActive = weapon == activeWeapon;

        RemovePlayerItem(client, weapon);
        AcceptEntityInput(weapon, "KillHierarchy");

        GameHooks_SetForcedDefinition(client, definitionIndex);
        int replacement = GivePlayerItem(client, classname);
        GameHooks_SetForcedDefinition(client, 0);
        if (replacement <= MaxClients || !IsValidEntity(replacement))
        {
            continue;
        }
        if (clip >= 0 && HasEntProp(replacement, Prop_Send, "m_iClip1"))
        {
            SetEntProp(replacement, Prop_Send, "m_iClip1", clip);
        }
        if (reserve >= 0
            && HasEntProp(
                replacement,
                Prop_Send,
                "m_iPrimaryReserveAmmoCount"
            ))
        {
            SetEntProp(
                replacement,
                Prop_Send,
                "m_iPrimaryReserveAmmoCount",
                reserve
            );
        }
        if (wasActive)
        {
            g_PendingActiveWeapons[client] = EntIndexToEntRef(replacement);
            activeWeaponNeedsStickerSwitch = !restoring
                && (Refresh_ItemHasStickers(hasItem, item)
                    || Refresh_ItemHasStickers(hadItem, previousItem));
        }
    }

    if (g_PendingActiveWeapons[client] != 0)
    {
        if (activeWeaponNeedsStickerSwitch)
        {
            int replacement = EntRefToEntIndex(
                g_PendingActiveWeapons[client]
            );
            int alternate = Refresh_FindAlternateWeapon(client, replacement);
            if (alternate > MaxClients && IsValidEntity(alternate))
            {
                g_PendingAlternateWeapons[client] =
                    EntIndexToEntRef(alternate);
            }
        }
        g_PendingWeaponSwitchStages[client] =
            RefreshWeaponSwitch_SelectReplacement;
        RequestFrame(Refresh_OnActiveWeaponFrame, GetClientSerial(client));
    }
}

public void Refresh_OnActiveWeaponFrame(any serial)
{
    int client = GetClientFromSerial(serial);
    if (client == 0)
    {
        return;
    }

    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        Refresh_ClearPendingWeaponSwitch(client);
        return;
    }

    RefreshWeaponSwitchStage stage = g_PendingWeaponSwitchStages[client];
    if (stage == RefreshWeaponSwitch_SelectReplacement)
    {
        if (!Refresh_SelectWeapon(
            client,
            g_PendingActiveWeapons[client]
        ))
        {
            Refresh_ClearPendingWeaponSwitch(client);
            return;
        }

        if (g_PendingAlternateWeapons[client] == 0)
        {
            Refresh_ClearPendingWeaponSwitch(client);
            return;
        }
        g_PendingWeaponSwitchStages[client] =
            RefreshWeaponSwitch_SelectAlternate;
        RequestFrame(Refresh_OnActiveWeaponFrame, serial);
        return;
    }

    if (stage == RefreshWeaponSwitch_SelectAlternate)
    {
        if (!Refresh_SelectWeapon(
            client,
            g_PendingAlternateWeapons[client]
        ))
        {
            Refresh_ClearPendingWeaponSwitch(client);
            return;
        }
        g_PendingWeaponSwitchStages[client] =
            RefreshWeaponSwitch_SelectReplacementAgain;
        RequestFrame(Refresh_OnActiveWeaponFrame, serial);
        return;
    }

    if (stage == RefreshWeaponSwitch_SelectReplacementAgain)
    {
        Refresh_SelectWeapon(client, g_PendingActiveWeapons[client]);
    }
    Refresh_ClearPendingWeaponSwitch(client);
}

bool Refresh_GetSimulatedItem(
    int client,
    int weapon,
    PlayerInventory inventory,
    bool hasInventory,
    InventoryItem item
)
{
    if (!hasInventory)
    {
        return false;
    }

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));

    int itemIndex;
    if (InventorySimulator_IsMeleeClassname(classname))
    {
        return inventory.GetKnife(
            GetClientTeam(client),
            g_CvarFallbackTeam.BoolValue,
            item,
            itemIndex
        );
    }

    if (!HasEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
    {
        return false;
    }
    return inventory.GetWeapon(
        GetClientTeam(client),
        GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"),
        g_CvarFallbackTeam.BoolValue,
        item,
        itemIndex
    );
}

bool Refresh_ItemsChanged(
    bool hasItem,
    InventoryItem item,
    bool hadItem,
    InventoryItem previousItem
)
{
    if (hasItem != hadItem)
    {
        return true;
    }
    return hasItem && !item.IsSameAs(previousItem);
}

bool Refresh_ItemHasStickers(bool hasItem, InventoryItem item)
{
    return hasItem && item.stickers != null && item.stickers.Length > 0;
}

int Refresh_FindAlternateWeapon(int client, int activeWeapon)
{
    int slots[] = {
        CS_SLOT_SECONDARY,
        CS_SLOT_KNIFE,
        CS_SLOT_PRIMARY
    };
    for (int index = 0; index < sizeof(slots); index++)
    {
        int weapon = GetPlayerWeaponSlot(client, slots[index]);
        if (weapon > MaxClients
            && weapon != activeWeapon
            && IsValidEntity(weapon))
        {
            return weapon;
        }
    }
    return -1;
}

bool Refresh_SelectWeapon(int client, int reference)
{
    int weapon = EntRefToEntIndex(reference);
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return false;
    }

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    FakeClientCommand(client, "use %s", classname);
    return true;
}

void Refresh_ClearPendingWeaponSwitch(int client)
{
    g_PendingActiveWeapons[client] = 0;
    g_PendingAlternateWeapons[client] = 0;
    g_PendingWeaponSwitchStages[client] = RefreshWeaponSwitch_None;
}

void Refresh_RestoreAllClients()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client)
            && !IsFakeClient(client)
            && IsPlayerAlive(client))
        {
            Refresh_ApplyInventory(client, true);
        }
    }
}
