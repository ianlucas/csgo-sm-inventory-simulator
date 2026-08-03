/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#pragma semicolon 1
#pragma newdecls required
#pragma dynamic 300000

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <dhooks>
#include <inventorysimulator>

#include "inventorysimulator/constants.sp"
#include "inventorysimulator/models.sp"

PlayerState g_PlayerStates[MAXPLAYERS + 1];

#include "inventorysimulator/playerinventory.sp"
#include "inventorysimulator/json.sp"
#include "inventorysimulator/convars.sp"
#include "inventorysimulator/inventorystore.sp"
#include "inventorysimulator/nativeitems.sp"
#include "inventorysimulator/gamehooks.sp"
#include "inventorysimulator/refresh.sp"
#include "inventorysimulator/spraymodels.sp"
#include "inventorysimulator/sprays.sp"
#include "inventorysimulator/api.sp"
#include "inventorysimulator/commands.sp"
#include "inventorysimulator/gameevents.sp"

public Plugin myinfo =
{
    name = "Inventory Simulator",
    author = "Ian Lucas",
    description = "Inventory Simulator (inventory.cstrike.app)",
    version = INVSIM_VERSION,
    url = "https://inventory.cstrike.app"
};

public void OnPluginStart()
{
    if (GetEngineVersion() != Engine_CSGO)
    {
        SetFailState("Inventory Simulator only supports Counter-Strike: Global Offensive.");
    }

    LoadTranslations("inventorysimulator.phrases");
    ConVars_Initialize();
    InventoryStore_Initialize();
    NativeItems_Initialize();
    GameHooks_Initialize();
    Commands_Initialize();
    GameEvents_Initialize();
    Sprays_Initialize();

    for (int client = 1; client <= MaxClients; client++)
    {
        g_PlayerStates[client].Reset();
        if (IsClientConnected(client)
            && !IsFakeClient(client)
            && InventorySimulator_CaptureSteamId(client))
        {
            InventorySimulator_InitializeClient(client);
        }
    }
}

public void OnMapStart()
{
    Sprays_OnMapStart();
}

public void OnPluginEnd()
{
    Sprays_Shutdown();
    GameHooks_Shutdown();
    Refresh_RestoreAllClients();
    NativeItems_Shutdown();
    InventoryStore_Shutdown();
}

public Action OnPlayerRunCmd(
    int client,
    int &buttons,
    int &impulse,
    float velocity[3],
    float angles[3],
    int &weapon,
    int &subtype,
    int &commandNumber,
    int &tickCount,
    int &randomSeed,
    int mouse[2]
)
{
    if (client < 1 || client > MaxClients || IsFakeClient(client))
    {
        return Plugin_Continue;
    }

    bool usePressed = (buttons & IN_USE) != 0
        && (g_PlayerStates[client].sprayLastButtons & IN_USE) == 0;
    g_PlayerStates[client].sprayLastButtons = buttons;
    if (usePressed
        && g_CvarSprayEnabled.BoolValue
        && g_CvarSprayOnUse.BoolValue)
    {
        Sprays_OnUsePressed(client);
    }
    return Plugin_Continue;
}

public void OnClientConnected(int client)
{
    g_PlayerStates[client].Reset();
}

public void OnClientAuthorized(int client, const char[] auth)
{
    if (IsFakeClient(client) || !InventorySimulator_CaptureSteamId(client))
    {
        return;
    }

    InventorySimulator_InitializeClient(client);
}

bool InventorySimulator_CaptureSteamId(int client)
{
    char steamId[32];
    if (!GetClientAuthId(
            client,
            AuthId_SteamID64,
            steamId,
            sizeof(steamId),
            true
        )
        && !GetClientAuthId(
            client,
            AuthId_SteamID64,
            steamId,
            sizeof(steamId),
            false
        ))
    {
        return false;
    }

    if (steamId[0] == '\0' || StrEqual(steamId, "0"))
    {
        return false;
    }

    strcopy(
        g_PlayerStates[client].steamId,
        sizeof(g_PlayerStates[].steamId),
        steamId
    );
    return true;
}

public void OnClientPutInServer(int client)
{
    if (!IsFakeClient(client))
    {
        InventorySimulator_InitializeClient(client);
    }
}

public void OnClientDisconnect(int client)
{
    GameHooks_UnhookClient(client);
    NativeItems_ClearClient(client);

    if (g_PlayerStates[client].steamId[0] != '\0'
        && !g_PlayerStates[client].loadedFromFile
        && !g_CvarPersistInventory.BoolValue)
    {
        InventoryStore_RemoveCached(g_PlayerStates[client].steamId);
    }
    g_PlayerStates[client].Reset();
}

void InventorySimulator_InitializeClient(int client)
{
    if (!IsClientConnected(client) || IsFakeClient(client))
    {
        return;
    }

    if (g_PlayerStates[client].steamId[0] == '\0'
        && !InventorySimulator_CaptureSteamId(client))
    {
        return;
    }

    GameHooks_HookClient(client);
    if (!g_PlayerStates[client].fetching)
    {
        Api_FetchInventory(client, false);
    }
}

int InventorySimulator_GetAccountId(int client)
{
    if (client < 1 || client > MaxClients || !IsClientConnected(client))
    {
        return 0;
    }

    int accountId = GetSteamAccountID(client, false);
    if (accountId != 0)
    {
        return accountId;
    }

    if (g_PlayerStates[client].steamId[0] == '\0')
    {
        return 0;
    }

    int steamId64[2];
    if (!StringToInt64(g_PlayerStates[client].steamId, steamId64))
    {
        return 0;
    }
    return steamId64[0];
}

bool InventorySimulator_GetClientInventory(
    int client,
    PlayerInventory &inventory
)
{
    if (client < 1
        || client > MaxClients
        || g_PlayerStates[client].steamId[0] == '\0')
    {
        inventory = null;
        return false;
    }

    bool fromFile;
    return InventoryStore_Get(
        g_PlayerStates[client].steamId,
        inventory,
        fromFile
    );
}

void InventorySimulator_OnInventoryReady(
    int client,
    bool forced,
    bool success,
    PlayerInventory previousInventory = null
)
{
    if (!IsClientConnected(client))
    {
        return;
    }

    InventorySimulator_SetInventoryWait(client, false);

    if (!success)
    {
        if (forced)
        {
            InventorySimulator_PrintSimple(client, "RefreshFailed");
        }
        return;
    }

    NativeItems_SendInventoryUpdateEvent(
        g_PlayerStates[client].inventoryAddress
    );

    if (forced)
    {
        NativeItems_InvalidateClientMaterialCache(client);
        InventorySimulator_PrintSimple(client, "RefreshCompleted");
    }
    if (forced && g_CvarWsImmediately.BoolValue)
    {
        Refresh_ApplyInventory(client, false, previousInventory);
    }
}

void InventorySimulator_SetInventoryWait(int client, bool waiting)
{
    if (waiting)
    {
        return;
    }

    GameHooks_ScheduleResumeActivation(client);
}

stock void InventorySimulator_Debug(const char[] format, any ...)
{
    if (g_CvarDebug == null || !g_CvarDebug.BoolValue)
    {
        return;
    }

    char message[512];
    VFormat(message, sizeof(message), format, 2);
    LogMessage("[debug] %s", message);
}

void InventorySimulator_PrintSimple(int client, const char[] phrase)
{
    char prefix[128];
    ConVars_GetChatPrefix(prefix, sizeof(prefix));
    PrintToChat(client, " \x04%s\x01%t", prefix, phrase);
}

void InventorySimulator_PrintString(
    int client,
    const char[] phrase,
    const char[] value
)
{
    char prefix[128];
    ConVars_GetChatPrefix(prefix, sizeof(prefix));
    PrintToChat(client, " \x04%s\x01%t", prefix, phrase, value);
}

void InventorySimulator_PrintNumber(
    int client,
    const char[] phrase,
    int value
)
{
    char prefix[128];
    ConVars_GetChatPrefix(prefix, sizeof(prefix));
    PrintToChat(client, " \x04%s\x01%t", prefix, phrase, value);
}
