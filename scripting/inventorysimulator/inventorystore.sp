/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

StringMap g_CachedInventories;
StringMap g_StaticInventories;
StringMap g_StaticInventoryParseTarget;
char g_StaticInventoryJson[INVSIM_MAX_BODY];

void InventoryStore_Initialize()
{
    g_CachedInventories = new StringMap();
    g_StaticInventories = new StringMap();
    InventoryStore_LoadStatic();
}

void InventoryStore_Shutdown()
{
    InventoryStore_DestroyMap(g_CachedInventories);
    InventoryStore_DestroyMap(g_StaticInventories);
    g_CachedInventories = null;
    g_StaticInventories = null;
}

bool InventoryStore_Get(
    const char[] steamId,
    PlayerInventory &inventory,
    bool &fromFile
)
{
    if (g_CachedInventories.GetValue(steamId, inventory))
    {
        fromFile = false;
        return true;
    }
    if (g_StaticInventories.GetValue(steamId, inventory))
    {
        fromFile = true;
        return true;
    }
    inventory = null;
    fromFile = false;
    return false;
}

void InventoryStore_SetCached(
    const char[] steamId,
    PlayerInventory inventory,
    PlayerInventory &previous
)
{
    previous = null;
    g_CachedInventories.GetValue(steamId, previous);
    g_CachedInventories.SetValue(steamId, inventory, true);
}

void InventoryStore_SetStatic(
    const char[] steamId,
    PlayerInventory inventory
)
{
    StringMap target = g_StaticInventoryParseTarget != null
        ? g_StaticInventoryParseTarget
        : g_StaticInventories;
    PlayerInventory previous;
    if (target.GetValue(steamId, previous))
    {
        previous.Destroy();
    }
    target.SetValue(steamId, inventory, true);
}

void InventoryStore_RemoveCached(const char[] steamId)
{
    PlayerInventory inventory;
    if (g_CachedInventories.GetValue(steamId, inventory))
    {
        inventory.Destroy();
        g_CachedInventories.Remove(steamId);
    }
}

void InventoryStore_LoadStatic()
{
    if (g_StaticInventories == null)
    {
        return;
    }

    char filename[PLATFORM_MAX_PATH];
    g_CvarFile.GetString(filename, sizeof(filename));
    if (filename[0] == '\0')
    {
        InventoryStore_DestroyMap(g_StaticInventories);
        g_StaticInventories = new StringMap();
        return;
    }

    char path[PLATFORM_MAX_PATH];
    BuildPath(
        Path_SM,
        path,
        sizeof(path),
        "../../%s",
        filename
    );
    if (!FileExists(path))
    {
        strcopy(path, sizeof(path), filename);
    }
    if (!FileExists(path))
    {
        return;
    }

    File file = OpenFile(path, "r");
    if (file == null)
    {
        LogError("Unable to open inventory file \"%s\".", path);
        return;
    }

    g_StaticInventoryJson[0] = '\0';
    char line[4096];
    while (!file.EndOfFile() && file.ReadLine(line, sizeof(line)))
    {
        if (strlen(g_StaticInventoryJson) + strlen(line) + 1
            >= sizeof(g_StaticInventoryJson))
        {
            LogError(
                "Inventory file \"%s\" exceeds the %d-byte limit.",
                path,
                sizeof(g_StaticInventoryJson)
            );
            delete file;
            return;
        }
        StrCat(g_StaticInventoryJson, sizeof(g_StaticInventoryJson), line);
    }
    delete file;

    char error[192];
    StringMap candidate = new StringMap();
    g_StaticInventoryParseTarget = candidate;
    if (!Json_ParseInventoryFile(
        g_StaticInventoryJson,
        error,
        sizeof(error)
    ))
    {
        g_StaticInventoryParseTarget = null;
        InventoryStore_DestroyMap(candidate);
        LogError("Unable to parse \"%s\": %s.", path, error);
        return;
    }

    g_StaticInventoryParseTarget = null;
    StringMap previous = g_StaticInventories;
    g_StaticInventories = candidate;
    InventoryStore_DestroyMap(previous);
    LogMessage("Loaded static inventories from \"%s\".", path);
}

void InventoryStore_DestroyMap(StringMap inventories)
{
    if (inventories == null)
    {
        return;
    }

    StringMapSnapshot snapshot = inventories.Snapshot();
    char key[32];
    PlayerInventory inventory;
    for (int index = 0; index < snapshot.Length; index++)
    {
        snapshot.GetKey(index, key, sizeof(key));
        if (inventories.GetValue(key, inventory))
        {
            inventory.Destroy();
        }
    }
    delete snapshot;
    delete inventories;
}
