/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

DynamicHook g_HookGiveNamedItem;
DynamicDetour g_DetourGetItemInLoadout;
DynamicDetour g_DetourActivatePlayer;
Handle g_CallActivatePlayer;
int g_GiveNamedItemHookIds[MAXPLAYERS + 1];
int g_ForcedDefinitions[MAXPLAYERS + 1];
int g_GameClientUserIdOffset;
Address g_ResumingActivation;

void GameHooks_Initialize()
{
    g_GameClientUserIdOffset = NativeItems_RequireOffset("GameClientUserId");
    Address activatePlayer = g_InventoryGameData.GetAddress(
        "CGameClient::ActivatePlayer"
    );
    if (activatePlayer == Address_Null)
    {
        SetFailState("Unable to resolve CGameClient::ActivatePlayer.");
    }
    g_CallActivatePlayer = NativeItems_CreateRawVoidSignatureCall(
        "CGameClient::ActivatePlayer"
    );
    g_DetourActivatePlayer = new DynamicDetour(
        activatePlayer,
        CallConv_THISCALL,
        ReturnType_Void,
        ThisPointer_Address
    );
    if (!g_DetourActivatePlayer.Enable(
        Hook_Pre,
        GameHooks_OnActivatePlayerPre
    ))
    {
        SetFailState("Unable to detour CGameClient::ActivatePlayer.");
    }

    int giveNamedItemOffset = NativeItems_RequireOffset("GiveNamedItem");

    g_HookGiveNamedItem = new DynamicHook(
        giveNamedItemOffset,
        HookType_Entity,
        ReturnType_CBaseEntity,
        ThisPointer_CBaseEntity
    );
    g_HookGiveNamedItem.AddParam(HookParamType_CharPtr);
    g_HookGiveNamedItem.AddParam(HookParamType_Int);
    g_HookGiveNamedItem.AddParam(HookParamType_Int);
    g_HookGiveNamedItem.AddParam(HookParamType_Bool);
    g_HookGiveNamedItem.AddParam(HookParamType_VectorPtr);

    Address getItemInLoadout = g_InventoryGameData.GetAddress(
        "CCSPlayerInventory::GetItemInLoadout"
    );
    if (getItemInLoadout == Address_Null)
    {
        SetFailState("Unable to resolve CCSPlayerInventory::GetItemInLoadout.");
    }
    g_DetourGetItemInLoadout = new DynamicDetour(
        getItemInLoadout,
        CallConv_THISCALL,
        ReturnType_Int,
        ThisPointer_Address
    );
    g_DetourGetItemInLoadout.AddParam(HookParamType_Int);
    g_DetourGetItemInLoadout.AddParam(HookParamType_Int);
    if (!g_DetourGetItemInLoadout.Enable(
        Hook_Post,
        GameHooks_OnGetItemInLoadoutPost
    ))
    {
        SetFailState("Unable to detour CCSPlayerInventory::GetItemInLoadout.");
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        g_GiveNamedItemHookIds[client] = INVALID_HOOK_ID;
    }
}

void GameHooks_Shutdown()
{
    if (g_DetourActivatePlayer != null)
    {
        g_DetourActivatePlayer.Disable(
            Hook_Pre,
            GameHooks_OnActivatePlayerPre
        );
    }
    if (g_DetourGetItemInLoadout != null)
    {
        g_DetourGetItemInLoadout.Disable(
            Hook_Post,
            GameHooks_OnGetItemInLoadoutPost
        );
    }
    GameHooks_ResumeAllActivations();

    for (int client = 1; client <= MaxClients; client++)
    {
        GameHooks_UnhookClient(client);
    }
    delete g_HookGiveNamedItem;
    delete g_DetourGetItemInLoadout;
    delete g_DetourActivatePlayer;
    delete g_CallActivatePlayer;
}

public MRESReturn GameHooks_OnActivatePlayerPre(Address gameClient)
{
    if (!g_CvarRequireInventory.BoolValue
        || gameClient == Address_Null
        || gameClient == g_ResumingActivation)
    {
        return MRES_Ignored;
    }

    int userId = LoadFromAddress(
        gameClient + view_as<Address>(g_GameClientUserIdOffset),
        NumberType_Int32
    );
    int client = GetClientOfUserId(userId);
    if (client == 0 || IsFakeClient(client))
    {
        return MRES_Ignored;
    }

    if (g_PlayerStates[client].steamId[0] == '\0')
    {
        InventorySimulator_CaptureSteamId(client);
    }

    PlayerInventory inventory;
    if (InventorySimulator_GetClientInventory(client, inventory))
    {
        return MRES_Ignored;
    }

    g_PlayerStates[client].pendingActivation = gameClient;
    if (g_PlayerStates[client].steamId[0] != '\0'
        && !g_PlayerStates[client].fetching)
    {
        Api_FetchInventory(client, false);
    }
    return MRES_Supercede;
}

void GameHooks_ScheduleResumeActivation(int client)
{
    if (client < 1
        || client > MaxClients
        || g_PlayerStates[client].pendingActivation == Address_Null
        || g_PlayerStates[client].activationScheduled)
    {
        return;
    }

    g_PlayerStates[client].activationScheduled = true;
    RequestFrame(
        GameHooks_OnResumeActivationFrame,
        GetClientSerial(client)
    );
}

public void GameHooks_OnResumeActivationFrame(any serial)
{
    int client = GetClientFromSerial(serial);
    if (client == 0)
    {
        return;
    }

    g_PlayerStates[client].activationScheduled = false;
    GameHooks_ResumeActivation(client);
}

void GameHooks_ResumeActivation(int client)
{
    Address gameClient = g_PlayerStates[client].pendingActivation;
    g_PlayerStates[client].pendingActivation = Address_Null;
    g_PlayerStates[client].activationScheduled = false;
    if (gameClient == Address_Null || !IsClientConnected(client))
    {
        return;
    }

    g_ResumingActivation = gameClient;
    SDKCall(g_CallActivatePlayer, gameClient);
    g_ResumingActivation = Address_Null;
}

void GameHooks_ResumeAllActivations()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        GameHooks_ResumeActivation(client);
    }
}

void GameHooks_HookClient(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (g_GiveNamedItemHookIds[client] == INVALID_HOOK_ID)
    {
        g_GiveNamedItemHookIds[client] = g_HookGiveNamedItem.HookEntity(
            Hook_Pre,
            client,
            GameHooks_OnGiveNamedItemPre
        );
    }

    g_PlayerStates[client].inventoryAddress = GetEntityAddress(client)
        + view_as<Address>(NativeItems_GetPlayerInventoryOffset());
}

void GameHooks_UnhookClient(int client)
{
    if (g_GiveNamedItemHookIds[client] != INVALID_HOOK_ID)
    {
        DynamicHook.RemoveHook(g_GiveNamedItemHookIds[client]);
        g_GiveNamedItemHookIds[client] = INVALID_HOOK_ID;
    }

    g_PlayerStates[client].inventoryAddress = Address_Null;
}

public MRESReturn GameHooks_OnGiveNamedItemPre(
    int client,
    DHookReturn returnValue,
    DHookParam parameters
)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return MRES_Ignored;
    }

    char classname[64];
    parameters.GetString(1, classname, sizeof(classname));

    Address definition = NativeItems_GetDefinitionByName(classname);
    if (definition == Address_Null)
    {
        return MRES_Ignored;
    }

    int slot = NativeItems_GetLoadoutSlot(definition);
    int def = g_ForcedDefinitions[client] != 0
        ? g_ForcedDefinitions[client]
        : NativeItems_GetDefinitionIndex(definition);
    Address custom = GameHooks_SelectItemView(
        client,
        GetClientTeam(client),
        slot,
        def
    );
    if (custom == Address_Null)
    {
        return MRES_Ignored;
    }

    parameters.Set(3, view_as<int>(custom));
    return MRES_ChangedHandled;
}

public MRESReturn GameHooks_OnGetItemInLoadoutPost(
    Address inventoryAddress,
    DHookReturn returnValue,
    DHookParam parameters
)
{
    Address original = view_as<Address>(returnValue.Value);
    int client = GameHooks_FindClientByInventory(inventoryAddress);
    if (client == 0)
    {
        return MRES_Ignored;
    }

    int team = parameters.Get(1);
    int slot = parameters.Get(2);
    int def = original == Address_Null
        ? 0
        : NativeItems_GetDefinitionIndexFromView(original);
    Address custom = GameHooks_SelectItemView(client, team, slot, def);
    if (custom == Address_Null)
    {
        return MRES_Ignored;
    }

    returnValue.Value = view_as<int>(custom);
    return MRES_Override;
}

void GameHooks_SetForcedDefinition(int client, int definitionIndex)
{
    if (client >= 1 && client <= MaxClients)
    {
        g_ForcedDefinitions[client] = definitionIndex;
    }
}

Address GameHooks_SelectItemView(
    int client,
    int team,
    int slot,
    int definitionIndex
)
{
    PlayerInventory inventory;
    if (!InventorySimulator_GetClientInventory(client, inventory))
    {
        return Address_Null;
    }

    InventoryItem item;
    int itemIndex;
    if (!inventory.GetItemForSlot(
        team,
        slot,
        definitionIndex,
        g_CvarFallbackTeam.BoolValue,
        g_CvarMinModels.IntValue,
        item,
        itemIndex
    ))
    {
        return Address_Null;
    }

    if (!item.hasDef)
    {
        item.hasDef = true;
        item.def = definitionIndex;
    }
    return NativeItems_GetOrCreate(client, team, slot, item);
}

int GameHooks_FindClientByInventory(Address inventoryAddress)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_PlayerStates[client].inventoryAddress == inventoryAddress)
        {
            return client;
        }
    }
    return 0;
}
