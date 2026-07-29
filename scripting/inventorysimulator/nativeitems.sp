/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#define ECON_ITEM_VIEW_SIZE 512
#define ECON_VIEW_DEFINITION_INDEX 84
#define ECON_VIEW_ENTITY_QUALITY 88
#define ECON_VIEW_ENTITY_LEVEL 92
#define ECON_VIEW_ITEM_ID 96
#define ECON_VIEW_ITEM_ID_HIGH 104
#define ECON_VIEW_ITEM_ID_LOW 108
#define ECON_VIEW_ACCOUNT_ID 112
#define ECON_VIEW_INITIALIZED 124
#define ECON_VIEW_ATTRIBUTE_LIST 128
#define ECON_VIEW_NETWORKED_ATTRIBUTES 156
#define ECON_VIEW_CUSTOM_NAME 184

GameData g_InventoryGameData;
Handle g_CallGetItemSchema;
Handle g_CallGetDefinitionByName;
Handle g_CallEconItemViewConstructor;
Handle g_CallEconItemViewDestructor;
Handle g_CallEconItemViewInit;
Handle g_CallGiveDefaultWearables;
Handle g_CallEquipWearableItem;
Handle g_CallGetDefinitionByIndex;
Handle g_CallStringSet;
Handle g_CallSendInventoryUpdateEvent;

Address g_ItemSchema;
int g_PlayerInventoryMemberOffset;
int g_ItemDefinitionIndexOffset;
int g_ItemDefinitionLoadoutSlotOffset;
int g_ItemDefinitionPlayerModelOffset;
int g_ItemDefinitionVoicePrefixOffset;
int g_PlayerVoicePrefixOffset;
int g_NextGeneratedItemIdLow;

Address g_ItemViewAddresses[MAXPLAYERS + 1][2][INVSIM_LOADOUT_SLOT_COUNT];
int g_ItemViewStatTrak[MAXPLAYERS + 1][2][INVSIM_LOADOUT_SLOT_COUNT];
StringMap g_ItemViewHashes[MAXPLAYERS + 1];
int g_ClientMaterialCacheGenerations[MAXPLAYERS + 1];

void NativeItems_Initialize()
{
    g_InventoryGameData = new GameData(INVSIM_GAMEDATA);
    if (g_InventoryGameData == null)
    {
        SetFailState("Unable to load gamedata/%s.txt.", INVSIM_GAMEDATA);
    }

    g_ItemDefinitionIndexOffset = NativeItems_RequireOffset(
        "ItemDefinitionIndex"
    );
    g_ItemDefinitionLoadoutSlotOffset = NativeItems_RequireOffset(
        "ItemDefinitionLoadoutSlot"
    );
    g_ItemDefinitionPlayerModelOffset = NativeItems_RequireOffset(
        "ItemDefinitionPlayerModel"
    );
    g_ItemDefinitionVoicePrefixOffset = NativeItems_RequireOffset(
        "ItemDefinitionVoicePrefix"
    );
    g_PlayerVoicePrefixOffset = NativeItems_RequireOffset("PlayerVoicePrefix");

    int extractionOffset = NativeItems_RequireOffset(
        "PlayerInventoryOffsetInBuyCommand"
    );
    Address buyCommand = g_InventoryGameData.GetAddress(
        "HandleCommand_Buy_Internal"
    );
    if (buyCommand == Address_Null)
    {
        SetFailState("Unable to resolve HandleCommand_Buy_Internal.");
    }
    g_PlayerInventoryMemberOffset = LoadFromAddress(
        buyCommand + view_as<Address>(extractionOffset),
        NumberType_Int32
    );

    g_CallGetItemSchema = NativeItems_CreateStaticCall(
        "GetItemSchema",
        SDKType_PlainOldData
    );
    g_CallGetDefinitionByName = NativeItems_CreateRawVirtualCall(
        NativeItems_RequireOffset("GetItemDefinitionByName"),
        SDKType_PlainOldData,
        SDKType_String,
        SDKPass_Pointer
    );
    g_CallEconItemViewConstructor = NativeItems_CreateRawVoidSignatureCall(
        "CEconItemView::CEconItemView"
    );
    g_CallEconItemViewDestructor = NativeItems_CreateRawVoidSignatureCall(
        "CEconItemView::~CEconItemView"
    );
    g_CallEconItemViewInit = NativeItems_CreateRawInitCall();
    g_CallGiveDefaultWearables = NativeItems_CreateRawVoidSignatureCall(
        "CCSPlayer::GiveDefaultWearables"
    );
    g_CallEquipWearableItem = NativeItems_CreateRawSlotCall(
        "CCSPlayer::EquipWearableItemInLoadoutSlot"
    );
    g_CallGetDefinitionByIndex = NativeItems_CreateDefinitionByIndexCall();
    g_CallStringSet = NativeItems_CreateStringSetCall();
    g_CallSendInventoryUpdateEvent = NativeItems_CreateRawVoidVirtualCall(
        NativeItems_RequireOffset("SendInventoryUpdateEvent")
    );

    g_ItemSchema = view_as<Address>(SDKCall(g_CallGetItemSchema));
    int schemaAdjustment = NativeItems_RequireOffset(
        "GetItemSchemaReturnAdjustment"
    );
    g_ItemSchema += view_as<Address>(schemaAdjustment);
    if (g_ItemSchema == Address_Null)
    {
        SetFailState("GetItemSchema returned a null address.");
    }

    g_NextGeneratedItemIdLow = INVSIM_GENERATED_ITEM_ID_LOW;
    NativeItems_RegisterProbe();
    for (int client = 1; client <= MaxClients; client++)
    {
        NativeItems_ResetClientCache(client);
    }
}

void NativeItems_Shutdown()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        NativeItems_ClearClient(client);
        delete g_ItemViewHashes[client];
        g_ItemViewHashes[client] = null;
    }

    delete g_CallStringSet;
    delete g_CallGetDefinitionByIndex;
    delete g_CallSendInventoryUpdateEvent;
    delete g_CallEquipWearableItem;
    delete g_CallGiveDefaultWearables;
    delete g_CallEconItemViewInit;
    delete g_CallEconItemViewDestructor;
    delete g_CallEconItemViewConstructor;
    delete g_CallGetDefinitionByName;
    delete g_CallGetItemSchema;
    delete g_InventoryGameData;
}

void NativeItems_RegisterProbe()
{
    RegServerCmd(
        "invsim_probe",
        NativeItems_ProbeCommand,
        "Scan item definition memory for the default loadout slot offset."
    );
    RegServerCmd(
        "invsim_probeagent",
        NativeItems_ProbeAgentCommand,
        "Dump the string fields of the agent item definition."
    );
    RegServerCmd(
        "invsim_dumpitems",
        NativeItems_DumpItemsCommand,
        "Report the econ networked values of every live player weapon."
    );
}

int NativeItems_ReadProp(int entity, const char[] property)
{
    if (!HasEntProp(entity, Prop_Send, property))
    {
        return -1;
    }
    return GetEntProp(entity, Prop_Send, property);
}

bool NativeItems_ReadDefinitionString(
    Address pointer,
    Address reference,
    char[] output,
    int outputLength
)
{
    output[0] = '\0';
    int delta = view_as<int>(pointer) - view_as<int>(reference);
    if (pointer == Address_Null || delta < -0x2000000 || delta > 0x2000000)
    {
        return false;
    }

    for (int index = 0; index < outputLength - 1; index++)
    {
        int character = LoadFromAddress(
            pointer + view_as<Address>(index),
            NumberType_Int8
        );
        if (character == 0)
        {
            output[index] = '\0';
            return index > 2;
        }
        if (character < 32 || character > 126)
        {
            return false;
        }
        output[index] = character;
    }
    output[outputLength - 1] = '\0';
    return true;
}

public Action NativeItems_ProbeAgentCommand(int args)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }

        PlayerInventory inventory;
        if (!InventorySimulator_GetClientInventory(client, inventory))
        {
            continue;
        }

        InventoryItem item;
        int itemIndex;
        if (!inventory.GetItemForSlot(
            GetClientTeam(client),
            view_as<int>(Loadout_ClothingAppearance),
            0,
            g_CvarFallbackTeam.BoolValue,
            g_CvarMinModels.IntValue,
            item,
            itemIndex
        ))
        {
            PrintToServer("[invsim] client %d has no agent", client);
            continue;
        }

        Address definition = NativeItems_GetDefinitionByIndex(item.def);
        PrintToServer(
            "[invsim] client %d agent def=%d definition=0x%X",
            client,
            item.def,
            definition
        );
        if (definition == Address_Null)
        {
            continue;
        }

        Address reference = view_as<Address>(LoadFromAddress(
            definition + view_as<Address>(0x1D0),
            NumberType_Int32
        ));
        char text[160];
        for (int offset = 0x100; offset <= 0x400; offset += 4)
        {
            Address pointer = view_as<Address>(LoadFromAddress(
                definition + view_as<Address>(offset),
                NumberType_Int32
            ));
            if (NativeItems_ReadDefinitionString(
                pointer,
                reference,
                text,
                sizeof(text)
            ))
            {
                PrintToServer("[invsim]   +0x%X -> %s", offset, text);
            }
        }
    }
    return Plugin_Handled;
}

public Action NativeItems_DumpItemsCommand(int args)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)
            || IsFakeClient(client)
            || !IsPlayerAlive(client))
        {
            continue;
        }

        PrintToServer(
            "[invsim] client %d expects account id %d",
            client,
            InventorySimulator_GetAccountId(client)
        );
        for (int slot = 0; slot <= 4; slot++)
        {
            int weapon = GetPlayerWeaponSlot(client, slot);
            if (weapon <= MaxClients || !IsValidEntity(weapon))
            {
                continue;
            }

            char classname[64];
            GetEntityClassname(weapon, classname, sizeof(classname));
            PrintToServer(
                "[invsim]   %s def=%d account=%d itemid=%d/%d owner=%d/%d quality=%d paint=%d stattrak=%d",
                classname,
                NativeItems_ReadProp(weapon, "m_iItemDefinitionIndex"),
                NativeItems_ReadProp(weapon, "m_iAccountID"),
                NativeItems_ReadProp(weapon, "m_iItemIDLow"),
                NativeItems_ReadProp(weapon, "m_iItemIDHigh"),
                NativeItems_ReadProp(weapon, "m_OriginalOwnerXuidLow"),
                NativeItems_ReadProp(weapon, "m_OriginalOwnerXuidHigh"),
                NativeItems_ReadProp(weapon, "m_iEntityQuality"),
                NativeItems_ReadProp(weapon, "m_nFallbackPaintKit"),
                NativeItems_ReadProp(weapon, "m_nFallbackStatTrak")
            );
        }

        int wearables = GetEntPropArraySize(client, Prop_Send, "m_hMyWearables");
        for (int index = 0; index < wearables; index++)
        {
            int wearable = GetEntPropEnt(
                client,
                Prop_Send,
                "m_hMyWearables",
                index
            );
            if (wearable == -1 || !IsValidEntity(wearable))
            {
                continue;
            }

            char classname[64];
            GetEntityClassname(wearable, classname, sizeof(classname));
            PrintToServer(
                "[invsim]   wearable[%d] %s def=%d account=%d itemid=%d/%d paint=%d",
                index,
                classname,
                NativeItems_ReadProp(wearable, "m_iItemDefinitionIndex"),
                NativeItems_ReadProp(wearable, "m_iAccountID"),
                NativeItems_ReadProp(wearable, "m_iItemIDLow"),
                NativeItems_ReadProp(wearable, "m_iItemIDHigh"),
                NativeItems_ReadProp(wearable, "m_nFallbackPaintKit")
            );
        }
    }
    return Plugin_Handled;
}

public Action NativeItems_ProbeCommand(int args)
{
    char classnames[][] = {
        "weapon_glock",
        "weapon_c4",
        "weapon_ak47",
        "weapon_awp",
        "weapon_deagle"
    };
    int expected[] = { 2, 1, 15, 18, 6 };

    Address definitions[sizeof(expected)];
    for (int index = 0; index < sizeof(expected); index++)
    {
        definitions[index] = NativeItems_GetDefinitionByName(classnames[index]);
        PrintToServer(
            "[invsim] %s -> definition 0x%X def=%d",
            classnames[index],
            definitions[index],
            NativeItems_GetDefinitionIndex(definitions[index])
        );
        if (definitions[index] == Address_Null)
        {
            PrintToServer("[invsim] probe aborted: missing definition.");
            return Plugin_Handled;
        }
    }

    for (int offset = 0; offset <= 1020; offset += 4)
    {
        bool matches = true;
        for (int index = 0; index < sizeof(expected); index++)
        {
            if (LoadFromAddress(
                    definitions[index] + view_as<Address>(offset),
                    NumberType_Int32
                ) != expected[index])
            {
                matches = false;
                break;
            }
        }
        if (matches)
        {
            PrintToServer("[invsim] loadout slot offset (int32): %d", offset);
        }
    }

    for (int offset = 0; offset <= 1022; offset += 2)
    {
        bool matches = true;
        for (int index = 0; index < sizeof(expected); index++)
        {
            if (LoadFromAddress(
                    definitions[index] + view_as<Address>(offset),
                    NumberType_Int16
                ) != expected[index])
            {
                matches = false;
                break;
            }
        }
        if (matches)
        {
            PrintToServer("[invsim] loadout slot offset (int16): %d", offset);
        }
    }

    PrintToServer("[invsim] probe complete.");
    return Plugin_Handled;
}

int NativeItems_GetPlayerInventoryOffset()
{
    return g_PlayerInventoryMemberOffset;
}

Address NativeItems_GetDefinitionByName(const char[] classname)
{
    if (g_ItemSchema == Address_Null)
    {
        return Address_Null;
    }
    return view_as<Address>(
        SDKCall(g_CallGetDefinitionByName, g_ItemSchema, classname)
    );
}

int NativeItems_GetDefinitionIndex(Address definition)
{
    if (definition == Address_Null)
    {
        return 0;
    }
    return LoadFromAddress(
        definition + view_as<Address>(g_ItemDefinitionIndexOffset),
        NumberType_Int16
    );
}

int NativeItems_GetDefinitionIndexFromView(Address itemView)
{
    if (itemView == Address_Null)
    {
        return 0;
    }
    return LoadFromAddress(
        itemView + view_as<Address>(ECON_VIEW_DEFINITION_INDEX),
        NumberType_Int16
    );
}

void NativeItems_GetItemIdString(
    Address itemView,
    char[] output,
    int outputLength
)
{
    int itemId[2];
    itemId[0] = LoadFromAddress(
        itemView + view_as<Address>(ECON_VIEW_ITEM_ID_LOW),
        NumberType_Int32
    );
    itemId[1] = LoadFromAddress(
        itemView + view_as<Address>(ECON_VIEW_ITEM_ID_HIGH),
        NumberType_Int32
    );
    Int64ToString(itemId, output, outputLength);
}

int NativeItems_GetLoadoutSlot(Address definition)
{
    if (definition == Address_Null)
    {
        return Loadout_Invalid;
    }
    return LoadFromAddress(
        definition + view_as<Address>(g_ItemDefinitionLoadoutSlotOffset),
        NumberType_Int32
    );
}

Address NativeItems_GetOrCreate(
    int client,
    int team,
    int slot,
    InventoryItem item
)
{
    if (slot < 0 || slot >= INVSIM_LOADOUT_SLOT_COUNT)
    {
        return Address_Null;
    }

    int teamIndex = team == INVSIM_TEAM_T ? 0 : 1;
    char cacheKey[16];
    char cachedHash[INVSIM_MAX_HASH];
    Format(cacheKey, sizeof(cacheKey), "%d:%d", teamIndex, slot);
    g_ItemViewHashes[client].GetString(
        cacheKey,
        cachedHash,
        sizeof(cachedHash)
    );
    if (g_ItemViewAddresses[client][teamIndex][slot] != Address_Null
        && StrEqual(cachedHash, item.hash)
        && g_ItemViewStatTrak[client][teamIndex][slot] == item.stattrak)
    {
        return g_ItemViewAddresses[client][teamIndex][slot];
    }

    if (g_ItemViewAddresses[client][teamIndex][slot] == Address_Null)
    {
        g_ItemViewAddresses[client][teamIndex][slot] =
            InvSim_Allocate(ECON_ITEM_VIEW_SIZE);
        if (g_ItemViewAddresses[client][teamIndex][slot] == Address_Null)
        {
            LogError("Unable to allocate a CEconItemView.");
            return Address_Null;
        }
        SDKCall(
            g_CallEconItemViewConstructor,
            g_ItemViewAddresses[client][teamIndex][slot]
        );
    }

    Address itemView = g_ItemViewAddresses[client][teamIndex][slot];

    int quality = 4;
    if (slot == view_as<int>(Loadout_Melee))
    {
        quality = 3;
    }
    else if (item.hasStatTrak && item.stattrak >= 0)
    {
        quality = 9;
    }

    int accountId = InventorySimulator_GetAccountId(client);
    StoreToAddress(
        itemView + view_as<Address>(ECON_VIEW_INITIALIZED),
        0,
        NumberType_Int8
    );
    SDKCall(
        g_CallEconItemViewInit,
        itemView,
        item.def,
        quality,
        1,
        accountId
    );
    if (LoadFromAddress(
            itemView + view_as<Address>(ECON_VIEW_INITIALIZED),
            NumberType_Int8
        ) == 0)
    {
        LogError(
            "Unable to initialize CEconItemView for definition %d.",
            item.def
        );
        g_ItemViewHashes[client].Remove(cacheKey);
        g_ItemViewStatTrak[client][teamIndex][slot] = -1;
        return Address_Null;
    }

    int itemIdLow = g_NextGeneratedItemIdLow++;
    if (g_NextGeneratedItemIdLow < INVSIM_GENERATED_ITEM_ID_LOW)
    {
        g_NextGeneratedItemIdLow = INVSIM_GENERATED_ITEM_ID_LOW;
    }
    NativeItems_WriteInt(itemView, ECON_VIEW_ITEM_ID, itemIdLow);
    NativeItems_WriteInt(
        itemView,
        ECON_VIEW_ITEM_ID + 4,
        INVSIM_GENERATED_ITEM_ID_HIGH
    );
    NativeItems_WriteInt(
        itemView,
        ECON_VIEW_ITEM_ID_HIGH,
        INVSIM_GENERATED_ITEM_ID_HIGH
    );
    NativeItems_WriteInt(itemView, ECON_VIEW_ITEM_ID_LOW, itemIdLow);
    NativeItems_WriteInt(itemView, ECON_VIEW_ACCOUNT_ID, accountId);

    if (item.nametag[0] != '\0')
    {
        NativeItems_WriteString(
            itemView + view_as<Address>(ECON_VIEW_CUSTOM_NAME),
            item.nametag,
            INVSIM_MAX_NAMETAG
        );
    }

    NativeItems_ApplyItemAttributes(
        itemView,
        item,
        g_ClientMaterialCacheGenerations[client]
    );
    g_ItemViewHashes[client].SetString(cacheKey, item.hash, true);
    g_ItemViewStatTrak[client][teamIndex][slot] = item.stattrak;
    return itemView;
}

void NativeItems_ApplyAgentModel(int client)
{
    if (client < 1
        || client > MaxClients
        || !IsClientInGame(client)
        || !IsPlayerAlive(client))
    {
        return;
    }

    PlayerInventory inventory;
    if (!InventorySimulator_GetClientInventory(client, inventory))
    {
        return;
    }

    InventoryItem item;
    int itemIndex;
    if (!inventory.GetItemForSlot(
        GetClientTeam(client),
        view_as<int>(Loadout_ClothingAppearance),
        0,
        g_CvarFallbackTeam.BoolValue,
        g_CvarMinModels.IntValue,
        item,
        itemIndex
    ))
    {
        return;
    }

    Address definition = NativeItems_GetDefinitionByIndex(item.def);
    if (definition == Address_Null
        || NativeItems_GetLoadoutSlot(definition)
            != view_as<int>(Loadout_ClothingAppearance))
    {
        return;
    }

    Address model = view_as<Address>(LoadFromAddress(
        definition + view_as<Address>(g_ItemDefinitionPlayerModelOffset),
        NumberType_Int32
    ));
    char path[PLATFORM_MAX_PATH];
    if (!NativeItems_ReadString(model, path, sizeof(path)))
    {
        return;
    }
    if (!IsModelPrecached(path) && PrecacheModel(path, true) <= 0)
    {
        return;
    }
    SetEntityModel(client, path);

    char prefix[64];
    Address voice = view_as<Address>(LoadFromAddress(
        definition + view_as<Address>(g_ItemDefinitionVoicePrefixOffset),
        NumberType_Int32
    ));
    if (!NativeItems_ReadString(voice, prefix, sizeof(prefix)))
    {
        prefix[0] = '\0';
    }
    SDKCall(
        g_CallStringSet,
        GetEntityAddress(client)
            + view_as<Address>(g_PlayerVoicePrefixOffset),
        prefix
    );
}

bool NativeItems_ReadString(Address pointer, char[] output, int outputLength)
{
    output[0] = '\0';
    if (pointer == Address_Null)
    {
        return false;
    }

    for (int index = 0; index < outputLength - 1; index++)
    {
        int character = LoadFromAddress(
            pointer + view_as<Address>(index),
            NumberType_Int8
        );
        if (character == 0)
        {
            output[index] = '\0';
            return index > 0;
        }
        if (character < 32 || character > 126)
        {
            output[0] = '\0';
            return false;
        }
        output[index] = character;
    }
    output[outputLength - 1] = '\0';
    return true;
}

void NativeItems_RefreshWearables(int client)
{
    if (client < 1
        || client > MaxClients
        || !IsClientInGame(client)
        || !IsPlayerAlive(client))
    {
        return;
    }

    SDKCall(g_CallGiveDefaultWearables, GetEntityAddress(client));
    NativeItems_EquipWearable(client, view_as<int>(Loadout_ClothingHands));
}

void NativeItems_EquipWearable(int client, int slot)
{
    if (client < 1
        || client > MaxClients
        || !IsClientInGame(client)
        || !IsPlayerAlive(client))
    {
        return;
    }
    SDKCall(g_CallEquipWearableItem, GetEntityAddress(client), slot);
}

void NativeItems_SendInventoryUpdateEvent(Address inventoryAddress)
{
    if (inventoryAddress == Address_Null)
    {
        return;
    }
    SDKCall(g_CallSendInventoryUpdateEvent, inventoryAddress);
}

void NativeItems_UpdateStatTrak(Address itemView, int stattrak)
{
    if (itemView == Address_Null)
    {
        return;
    }
    NativeItems_SetAttributeBits(itemView, "kill eater", stattrak);
    NativeItems_SetAttributeBits(itemView, "kill eater score type", 0);
}

bool NativeItems_IsGeneratedView(Address itemView, int accountId = 0)
{
    if (itemView == Address_Null)
    {
        return false;
    }

    int high = LoadFromAddress(
        itemView + view_as<Address>(ECON_VIEW_ITEM_ID_HIGH),
        NumberType_Int32
    );
    int low = LoadFromAddress(
        itemView + view_as<Address>(ECON_VIEW_ITEM_ID_LOW),
        NumberType_Int32
    );
    int owner = LoadFromAddress(
        itemView + view_as<Address>(ECON_VIEW_ACCOUNT_ID),
        NumberType_Int32
    );
    return high == INVSIM_GENERATED_ITEM_ID_HIGH
        && low >= INVSIM_GENERATED_ITEM_ID_LOW
        && (accountId == 0 || owner == accountId);
}

void NativeItems_ClearClient(int client)
{
    for (int teamIndex = 0; teamIndex < 2; teamIndex++)
    {
        for (int slot = 0; slot < INVSIM_LOADOUT_SLOT_COUNT; slot++)
        {
            if (g_ItemViewAddresses[client][teamIndex][slot] != Address_Null)
            {
                SDKCall(
                    g_CallEconItemViewDestructor,
                    g_ItemViewAddresses[client][teamIndex][slot]
                );
                InvSim_Free(g_ItemViewAddresses[client][teamIndex][slot]);
            }
            g_ItemViewAddresses[client][teamIndex][slot] = Address_Null;
            g_ItemViewStatTrak[client][teamIndex][slot] = -1;
        }
    }
    if (g_ItemViewHashes[client] != null)
    {
        g_ItemViewHashes[client].Clear();
    }
}

void NativeItems_ResetClientCache(int client)
{
    delete g_ItemViewHashes[client];
    g_ItemViewHashes[client] = new StringMap();
    g_ClientMaterialCacheGenerations[client] = 0;
    for (int teamIndex = 0; teamIndex < 2; teamIndex++)
    {
        for (int slot = 0; slot < INVSIM_LOADOUT_SLOT_COUNT; slot++)
        {
            g_ItemViewAddresses[client][teamIndex][slot] = Address_Null;
            g_ItemViewStatTrak[client][teamIndex][slot] = -1;
        }
    }
}

void NativeItems_InvalidateClientMaterialCache(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_ClientMaterialCacheGenerations[client]++;
    if (g_ClientMaterialCacheGenerations[client] <= 0)
    {
        g_ClientMaterialCacheGenerations[client] = 1;
    }
}

void NativeItems_ForgetItemView(int client, int team, int slot)
{
    if (client < 1
        || client > MaxClients
        || slot < 0
        || slot >= INVSIM_LOADOUT_SLOT_COUNT)
    {
        return;
    }

    int teamIndex = team == INVSIM_TEAM_T ? 0 : 1;
    char cacheKey[16];
    Format(cacheKey, sizeof(cacheKey), "%d:%d", teamIndex, slot);
    if (g_ItemViewHashes[client] != null)
    {
        g_ItemViewHashes[client].Remove(cacheKey);
    }
    g_ItemViewStatTrak[client][teamIndex][slot] = -1;
}

void NativeItems_ApplyItemAttributes(
    Address itemView,
    InventoryItem item,
    int materialCacheGeneration
)
{
    if (item.hasPaint)
    {
        NativeItems_SetAttributeFloat(
            itemView,
            "set item texture prefab",
            float(item.paint)
        );
    }
    if (item.hasSeed)
    {
        NativeItems_SetAttributeFloat(
            itemView,
            "set item texture seed",
            float(item.seed)
        );
    }
    if (item.hasWear)
    {
        float wear = NativeItems_GetMaterialCacheWear(
            item.wear,
            materialCacheGeneration
        );
        NativeItems_SetAttributeFloat(
            itemView,
            "set item texture wear",
            wear
        );
    }
    if (item.hasStatTrak && item.stattrak >= 0)
    {
        NativeItems_UpdateStatTrak(itemView, item.stattrak);
    }
    if (item.hasMusicId)
    {
        NativeItems_SetAttributeBits(itemView, "music id", item.musicId);
    }

    if (item.stickers == null)
    {
        return;
    }

    StickerItem sticker;
    char attribute[48];
    for (int index = 0; index < item.stickers.Length; index++)
    {
        item.stickers.GetArray(index, sticker, sizeof(sticker));
        Format(attribute, sizeof(attribute), "sticker slot %d id", sticker.slot);
        NativeItems_SetAttributeBits(itemView, attribute, sticker.def);

        if (sticker.hasWear || materialCacheGeneration > 0)
        {
            Format(
                attribute,
                sizeof(attribute),
                "sticker slot %d wear",
                sticker.slot
            );
            float wear = sticker.hasWear ? sticker.wear : 0.0;
            wear = NativeItems_GetStickerMaterialCacheWear(
                wear,
                materialCacheGeneration
            );
            NativeItems_SetAttributeFloat(itemView, attribute, wear);
        }
    }
}

float NativeItems_GetMaterialCacheWear(float wear, int generation)
{
    if (generation <= 0)
    {
        return wear;
    }

    /*
     * The client keys generated weapon and glove materials by the exact wear
     * bits. Moving one representable float per !ws gives it a new key while
     * remaining far below the six-decimal precision used to build the VMT.
     */
    int bits = view_as<int>(wear);
    if (wear > 0.0)
    {
        bits -= generation;
    }
    else
    {
        bits += generation;
    }
    return view_as<float>(bits);
}

float NativeItems_GetStickerMaterialCacheWear(float wear, int generation)
{
    if (generation <= 0)
    {
        return wear;
    }

    /*
     * Sticker material names hash wear formatted to six decimals, so a wider
     * step is required than the raw-bit nonce used by generated skin textures.
     * Move toward the middle of the valid range to avoid crossing its bounds.
     */
    float offset = float(generation) * 0.000002;
    return wear > 0.5 ? wear - offset : wear + offset;
}

void NativeItems_SetAttributeBits(
    Address itemView,
    const char[] attribute,
    int value
)
{
    NativeItems_SetAttributeFloat(
        itemView,
        attribute,
        view_as<float>(value)
    );
}

void NativeItems_SetAttributeFloat(
    Address itemView,
    const char[] attribute,
    float value
)
{
    Address attributeList = itemView
        + view_as<Address>(ECON_VIEW_ATTRIBUTE_LIST);
    InvSim_SetOrAddAttributeValueByName(attributeList, attribute, value);

    Address networkedList = itemView
        + view_as<Address>(ECON_VIEW_NETWORKED_ATTRIBUTES);
    InvSim_SetOrAddAttributeValueByName(networkedList, attribute, value);
}

void NativeItems_WriteInt(Address base, int offset, int value)
{
    StoreToAddress(
        base + view_as<Address>(offset),
        value,
        NumberType_Int32
    );
}

void NativeItems_WriteString(
    Address address,
    const char[] value,
    int maximumBytes
)
{
    int index = 0;
    while (value[index] != '\0' && index + 1 < maximumBytes)
    {
        StoreToAddress(
            address + view_as<Address>(index),
            value[index],
            NumberType_Int8
        );
        index++;
    }
    StoreToAddress(
        address + view_as<Address>(index),
        0,
        NumberType_Int8
    );
}

int NativeItems_RequireOffset(const char[] name)
{
    int offset = g_InventoryGameData.GetOffset(name);
    if (offset == -1)
    {
        SetFailState("Missing gamedata offset \"%s\".", name);
    }
    return offset;
}

Handle NativeItems_CreateStaticCall(
    const char[] signature,
    SDKType returnType
)
{
    StartPrepSDKCall(SDKCall_Static);
    if (!PrepSDKCall_SetFromConf(
        g_InventoryGameData,
        SDKConf_Signature,
        signature
    ))
    {
        SetFailState("Missing gamedata signature \"%s\".", signature);
    }
    PrepSDKCall_SetReturnInfo(returnType, SDKPass_Plain);
    Handle call = EndPrepSDKCall();
    if (call == null)
    {
        SetFailState("Unable to prepare SDKCall \"%s\".", signature);
    }
    return call;
}

Handle NativeItems_CreateRawVirtualCall(
    int virtualOffset,
    SDKType returnType,
    SDKType parameterType,
    SDKPassMethod passMethod
)
{
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetVirtual(virtualOffset);
    PrepSDKCall_AddParameter(parameterType, passMethod);
    PrepSDKCall_SetReturnInfo(returnType, SDKPass_Plain);
    Handle call = EndPrepSDKCall();
    if (call == null)
    {
        SetFailState("Unable to prepare raw virtual SDKCall %d.", virtualOffset);
    }
    return call;
}

Handle NativeItems_CreateRawVoidVirtualCall(int virtualOffset)
{
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetVirtual(virtualOffset);
    Handle call = EndPrepSDKCall();
    if (call == null)
    {
        SetFailState(
            "Unable to prepare raw void virtual SDKCall %d.",
            virtualOffset
        );
    }
    return call;
}

Handle NativeItems_CreateRawVoidSignatureCall(const char[] signature)
{
    StartPrepSDKCall(SDKCall_Raw);
    if (!PrepSDKCall_SetFromConf(
        g_InventoryGameData,
        SDKConf_Signature,
        signature
    ))
    {
        SetFailState("Missing gamedata signature \"%s\".", signature);
    }
    Handle call = EndPrepSDKCall();
    if (call == null)
    {
        SetFailState("Unable to prepare raw SDKCall \"%s\".", signature);
    }
    return call;
}

Handle NativeItems_CreateDefinitionByIndexCall()
{
    StartPrepSDKCall(SDKCall_Static);
    if (!PrepSDKCall_SetFromConf(
        g_InventoryGameData,
        SDKConf_Signature,
        "CEconItemSchema::GetItemDefinitionByIndex"
    ))
    {
        SetFailState(
            "Missing gamedata signature \"CEconItemSchema::GetItemDefinitionByIndex\"."
        );
    }
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    Handle call = EndPrepSDKCall();
    if (call == null)
    {
        SetFailState("Unable to prepare GetItemDefinitionByIndex.");
    }
    return call;
}

Address NativeItems_GetDefinitionByIndex(int definitionIndex)
{
    return view_as<Address>(SDKCall(
        g_CallGetDefinitionByIndex,
        g_ItemSchema,
        definitionIndex,
        0
    ));
}

bool NativeItems_HasDefinitionByIndex(int definitionIndex)
{
    if (g_CallGetDefinitionByIndex == null || g_ItemSchema == Address_Null)
    {
        return false;
    }
    return view_as<Address>(SDKCall(
        g_CallGetDefinitionByIndex,
        g_ItemSchema,
        definitionIndex,
        1
    )) != Address_Null;
}

Handle NativeItems_CreateStringSetCall()
{
    StartPrepSDKCall(SDKCall_Raw);
    if (!PrepSDKCall_SetFromConf(
        g_InventoryGameData,
        SDKConf_Signature,
        "CUtlString::Set"
    ))
    {
        SetFailState("Missing gamedata signature \"CUtlString::Set\".");
    }
    PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
    Handle call = EndPrepSDKCall();
    if (call == null)
    {
        SetFailState("Unable to prepare CUtlString::Set.");
    }
    return call;
}

Handle NativeItems_CreateRawSlotCall(const char[] signature)
{
    StartPrepSDKCall(SDKCall_Raw);
    if (!PrepSDKCall_SetFromConf(
        g_InventoryGameData,
        SDKConf_Signature,
        signature
    ))
    {
        SetFailState("Missing gamedata signature \"%s\".", signature);
    }
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    Handle call = EndPrepSDKCall();
    if (call == null)
    {
        SetFailState("Unable to prepare raw SDKCall \"%s\".", signature);
    }
    return call;
}

Handle NativeItems_CreateRawInitCall()
{
    StartPrepSDKCall(SDKCall_Raw);
    if (!PrepSDKCall_SetFromConf(
        g_InventoryGameData,
        SDKConf_Signature,
        "CEconItemView::Init"
    ))
    {
        SetFailState("Missing gamedata signature \"CEconItemView::Init\".");
    }
    for (int parameter = 0; parameter < 4; parameter++)
    {
        PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    }
    Handle call = EndPrepSDKCall();
    if (call == null)
    {
        SetFailState("Unable to prepare CEconItemView::Init.");
    }
    return call;
}
