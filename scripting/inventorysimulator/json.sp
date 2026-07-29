/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

bool Json_ParseEquipped(
    const char[] json,
    PlayerInventory &inventory,
    char[] error,
    int errorLength
)
{
    int cursor = 0;
    inventory = new PlayerInventory();
    if (!Json_ParseEquippedObject(
        json,
        cursor,
        inventory,
        true,
        error,
        errorLength
    ))
    {
        inventory.Destroy();
        inventory = null;
        return false;
    }
    Json_SkipWhitespace(json, cursor);
    if (json[cursor] != '\0')
    {
        Format(error, errorLength, "Unexpected data at byte %d", cursor);
        inventory.Destroy();
        inventory = null;
        return false;
    }
    return true;
}

bool Json_ParseInventoryFile(
    const char[] json,
    char[] error,
    int errorLength
)
{
    int cursor = 0;
    if (!Json_Consume(json, cursor, '{'))
    {
        strcopy(error, errorLength, "Expected root object");
        return false;
    }
    if (Json_Consume(json, cursor, '}'))
    {
        return Json_RequireEnd(json, cursor, error, errorLength);
    }

    while (json[cursor] != '\0')
    {
        if (!Json_ParseInventoryFileEntry(
            json,
            cursor,
            error,
            errorLength
        ))
        {
            return false;
        }
        if (Json_Consume(json, cursor, '}'))
        {
            return Json_RequireEnd(json, cursor, error, errorLength);
        }
        if (!Json_Consume(json, cursor, ','))
        {
            Format(error, errorLength, "Expected ',' at byte %d", cursor);
            return false;
        }
    }
    Format(error, errorLength, "Unterminated root object at byte %d", cursor);
    return false;
}

bool Json_ParseInventoryFileEntry(
    const char[] json,
    int &cursor,
    char[] error,
    int errorLength
)
{
    char steamId[32];
    if (!Json_ReadString(json, cursor, steamId, sizeof(steamId))
        || !Json_Consume(json, cursor, ':'))
    {
        Format(error, errorLength, "Invalid SteamID at byte %d", cursor);
        return false;
    }

    PlayerInventory inventory = new PlayerInventory();
    if (!Json_ParseEquippedObject(
        json,
        cursor,
        inventory,
        false,
        error,
        errorLength
    ))
    {
        inventory.Destroy();
        return false;
    }
    InventoryStore_SetStatic(steamId, inventory);
    return true;
}

bool Json_ReadTopLevelString(
    const char[] json,
    const char[] wantedProperty,
    char[] output,
    int outputLength
)
{
    int cursor = 0;
    if (!Json_Consume(json, cursor, '{'))
    {
        return false;
    }

    char property[64];
    while (!Json_Consume(json, cursor, '}'))
    {
        if (!Json_ReadString(json, cursor, property, sizeof(property))
            || !Json_Consume(json, cursor, ':'))
        {
            return false;
        }
        if (StrEqual(property, wantedProperty))
        {
            return Json_ReadNullableString(json, cursor, output, outputLength);
        }
        if (!Json_SkipValue(json, cursor)
            || (!Json_Consume(json, cursor, ',')
                && !Json_Consume(json, cursor, '}')))
        {
            return false;
        }
        if (json[cursor - 1] == '}')
        {
            break;
        }
    }
    return false;
}

bool Json_ParseEquippedObject(
    const char[] json,
    int &cursor,
    PlayerInventory inventory,
    bool validateItemDefinitions,
    char[] error,
    int errorLength
)
{
    if (!Json_Consume(json, cursor, '{'))
    {
        Format(error, errorLength, "Expected inventory object at byte %d", cursor);
        return false;
    }
    if (Json_Consume(json, cursor, '}'))
    {
        return true;
    }

    char property[32];
    while (json[cursor] != '\0')
    {
        if (!Json_ReadString(json, cursor, property, sizeof(property))
            || !Json_Consume(json, cursor, ':'))
        {
            Format(error, errorLength, "Invalid inventory property at byte %d", cursor);
            return false;
        }
        if (!Json_ParseEquippedProperty(
            json,
            cursor,
            inventory,
            property,
            validateItemDefinitions,
            error,
            errorLength
        ))
        {
            return false;
        }
        if (Json_Consume(json, cursor, '}'))
        {
            return true;
        }
        if (!Json_Consume(json, cursor, ','))
        {
            Format(error, errorLength, "Expected ',' at byte %d", cursor);
            return false;
        }
    }
    Format(error, errorLength, "Unterminated inventory object at byte %d", cursor);
    return false;
}

bool Json_ParseEquippedProperty(
    const char[] json,
    int &cursor,
    PlayerInventory inventory,
    const char[] property,
    bool validateItemDefinitions,
    char[] error,
    int errorLength
)
{
    if (StrEqual(property, "agents"))
    {
        return Json_ParseItemMap(
            json,
            cursor,
            inventory,
            InventoryItem_Agent,
            0,
            validateItemDefinitions,
            error,
            errorLength
        );
    }
    if (StrEqual(property, "ctWeapons"))
    {
        return Json_ParseItemMap(
            json,
            cursor,
            inventory,
            InventoryItem_Weapon,
            INVSIM_TEAM_CT,
            validateItemDefinitions,
            error,
            errorLength
        );
    }
    if (StrEqual(property, "gloves"))
    {
        return Json_ParseItemMap(
            json,
            cursor,
            inventory,
            InventoryItem_Glove,
            0,
            validateItemDefinitions,
            error,
            errorLength
        );
    }
    if (StrEqual(property, "knives"))
    {
        return Json_ParseItemMap(
            json,
            cursor,
            inventory,
            InventoryItem_Knife,
            0,
            validateItemDefinitions,
            error,
            errorLength
        );
    }
    if (StrEqual(property, "tWeapons"))
    {
        return Json_ParseItemMap(
            json,
            cursor,
            inventory,
            InventoryItem_Weapon,
            INVSIM_TEAM_T,
            validateItemDefinitions,
            error,
            errorLength
        );
    }
    if (StrEqual(property, "collectible"))
    {
        return Json_ParseSingleItem(
            json,
            cursor,
            inventory,
            InventoryItem_Collectible,
            validateItemDefinitions,
            error,
            errorLength
        );
    }
    if (StrEqual(property, "musicKit"))
    {
        return Json_ParseSingleItem(
            json,
            cursor,
            inventory,
            InventoryItem_MusicKit,
            validateItemDefinitions,
            error,
            errorLength
        );
    }
    if (!Json_SkipValue(json, cursor))
    {
        Format(error, errorLength, "Invalid value for \"%s\"", property);
        return false;
    }
    return true;
}

bool Json_ParseSingleItem(
    const char[] json,
    int &cursor,
    PlayerInventory inventory,
    InventoryItemKind kind,
    bool validateItemDefinitions,
    char[] error,
    int errorLength
)
{
    Json_SkipWhitespace(json, cursor);
    if (Json_ConsumeLiteral(json, cursor, "null"))
    {
        return true;
    }

    InventoryItem item;
    if (!Json_ParseItem(json, cursor, item, error, errorLength))
    {
        return false;
    }
    if (validateItemDefinitions && Json_HasUnknownItemDefinition(item))
    {
        item.Destroy();
        return true;
    }
    inventory.SetSingleItem(kind, item);
    return true;
}

bool Json_ParseItemMap(
    const char[] json,
    int &cursor,
    PlayerInventory inventory,
    InventoryItemKind kind,
    int weaponTeam,
    bool validateItemDefinitions,
    char[] error,
    int errorLength
)
{
    Json_SkipWhitespace(json, cursor);
    if (Json_ConsumeLiteral(json, cursor, "null"))
    {
        return true;
    }
    if (!Json_Consume(json, cursor, '{'))
    {
        Format(error, errorLength, "Expected item map at byte %d", cursor);
        return false;
    }
    if (Json_Consume(json, cursor, '}'))
    {
        return true;
    }

    char key[24];
    while (json[cursor] != '\0')
    {
        if (!Json_ReadString(json, cursor, key, sizeof(key))
            || !Json_Consume(json, cursor, ':'))
        {
            Format(error, errorLength, "Invalid item map entry at byte %d", cursor);
            return false;
        }

        InventoryItem item;
        if (!Json_ParseItem(json, cursor, item, error, errorLength))
        {
            return false;
        }

        int numericKey;
        if (!Json_ParseMapKey(key, numericKey))
        {
            Format(error, errorLength, "Invalid numeric item key \"%s\"", key);
            item.Destroy();
            return false;
        }
        if (validateItemDefinitions && Json_HasUnknownItemDefinition(item))
        {
            item.Destroy();
        }
        else if (kind == InventoryItem_Weapon)
        {
            inventory.SetWeapon(weaponTeam, numericKey, item);
        }
        else
        {
            inventory.SetMappedItem(kind, numericKey, item);
        }

        if (Json_Consume(json, cursor, '}'))
        {
            return true;
        }
        if (!Json_Consume(json, cursor, ','))
        {
            Format(error, errorLength, "Expected ',' at byte %d", cursor);
            return false;
        }
    }
    Format(error, errorLength, "Unterminated item map at byte %d", cursor);
    return false;
}

bool Json_HasUnknownItemDefinition(InventoryItem item)
{
    return item.hasDef && !NativeItems_HasDefinitionByIndex(item.def);
}

bool Json_ParseItem(
    const char[] json,
    int &cursor,
    InventoryItem item,
    char[] error,
    int errorLength
)
{
    item.Reset();
    if (!Json_Consume(json, cursor, '{'))
    {
        Format(error, errorLength, "Expected item at byte %d", cursor);
        return false;
    }
    if (Json_Consume(json, cursor, '}'))
    {
        return true;
    }

    char property[32];
    while (json[cursor] != '\0')
    {
        if (!Json_ReadString(json, cursor, property, sizeof(property))
            || !Json_Consume(json, cursor, ':'))
        {
            Format(error, errorLength, "Invalid item property at byte %d", cursor);
            item.Destroy();
            return false;
        }

        if (StrEqual(property, "def"))
        {
            item.hasDef = Json_ReadNullableInt(json, cursor, item.def);
        }
        else if (StrEqual(property, "hash"))
        {
            if (!Json_ReadNullableString(
                json,
                cursor,
                item.hash,
                sizeof(item.hash)
            ))
            {
                item.hash[0] = '\0';
            }
        }
        else if (StrEqual(property, "musicId"))
        {
            item.hasMusicId = Json_ReadNullableInt(json, cursor, item.musicId);
        }
        else if (StrEqual(property, "nametag"))
        {
            if (!Json_ReadNullableString(
                json,
                cursor,
                item.nametag,
                sizeof(item.nametag)
            ))
            {
                item.nametag[0] = '\0';
            }
        }
        else if (StrEqual(property, "paint"))
        {
            item.hasPaint = Json_ReadNullableInt(json, cursor, item.paint);
        }
        else if (StrEqual(property, "seed"))
        {
            item.hasSeed = Json_ReadNullableInt(json, cursor, item.seed);
        }
        else if (StrEqual(property, "stattrak"))
        {
            item.hasStatTrak = Json_ReadNullableInt(json, cursor, item.stattrak);
        }
        else if (StrEqual(property, "stickers"))
        {
            if (!Json_ParseStickers(json, cursor, item, error, errorLength))
            {
                item.Destroy();
                return false;
            }
        }
        else if (StrEqual(property, "uid"))
        {
            item.hasUid = Json_ReadNullableInt(json, cursor, item.uid);
        }
        else if (StrEqual(property, "wear"))
        {
            item.hasWear = Json_ReadNullableFloat(json, cursor, item.wear);
        }
        else if (!Json_SkipValue(json, cursor))
        {
            Format(error, errorLength, "Invalid item value \"%s\"", property);
            item.Destroy();
            return false;
        }

        if (Json_Consume(json, cursor, '}'))
        {
            if (item.hash[0] == '\0')
            {
                Json_CreateFallbackItemHash(item);
            }
            return true;
        }
        if (!Json_Consume(json, cursor, ','))
        {
            Format(error, errorLength, "Expected ',' at byte %d", cursor);
            item.Destroy();
            return false;
        }
    }
    Format(error, errorLength, "Unterminated item at byte %d", cursor);
    item.Destroy();
    return false;
}

void Json_CreateFallbackItemHash(InventoryItem item)
{
    int hash = -2128831035;
    Json_HashCell(hash, item.hasDef);
    Json_HashCell(hash, item.def);
    Json_HashCell(hash, item.hasMusicId);
    Json_HashCell(hash, item.musicId);
    Json_HashString(hash, item.nametag);
    Json_HashCell(hash, item.hasPaint);
    Json_HashCell(hash, item.paint);
    Json_HashCell(hash, item.hasSeed);
    Json_HashCell(hash, item.seed);
    Json_HashCell(hash, item.hasStatTrak);
    Json_HashCell(hash, item.stattrak);
    Json_HashCell(hash, item.hasUid);
    Json_HashCell(hash, item.uid);
    Json_HashCell(hash, item.hasWear);
    Json_HashCell(hash, view_as<int>(item.wear));

    int stickerCount = item.stickers == null ? -1 : item.stickers.Length;
    Json_HashCell(hash, stickerCount);
    StickerItem sticker;
    for (int index = 0; index < stickerCount; index++)
    {
        item.stickers.GetArray(index, sticker, sizeof(sticker));
        Json_HashCell(hash, sticker.def);
        Json_HashCell(hash, sticker.slot);
        Json_HashCell(hash, sticker.hasWear);
        Json_HashCell(hash, view_as<int>(sticker.wear));
    }

    Format(item.hash, sizeof(item.hash), "local:%08x", hash);
}

void Json_HashCell(int &hash, int value)
{
    hash = (hash ^ value) * 16777619;
}

void Json_HashString(int &hash, const char[] value)
{
    for (int index = 0; value[index] != '\0'; index++)
    {
        Json_HashCell(hash, value[index]);
    }
    Json_HashCell(hash, 0);
}

bool Json_ParseStickers(
    const char[] json,
    int &cursor,
    InventoryItem item,
    char[] error,
    int errorLength
)
{
    Json_SkipWhitespace(json, cursor);
    if (Json_ConsumeLiteral(json, cursor, "null"))
    {
        return true;
    }
    if (!Json_Consume(json, cursor, '['))
    {
        Format(error, errorLength, "Expected sticker array at byte %d", cursor);
        return false;
    }

    item.stickers = new ArrayList(sizeof(StickerItem));
    if (Json_Consume(json, cursor, ']'))
    {
        return true;
    }

    while (json[cursor] != '\0')
    {
        StickerItem sticker;
        sticker.Reset();
        if (!Json_ParseSticker(json, cursor, sticker, error, errorLength))
        {
            return false;
        }
        item.stickers.PushArray(sticker, sizeof(sticker));

        if (Json_Consume(json, cursor, ']'))
        {
            return true;
        }
        if (!Json_Consume(json, cursor, ','))
        {
            Format(error, errorLength, "Expected ',' at byte %d", cursor);
            return false;
        }
    }
    Format(error, errorLength, "Unterminated sticker array at byte %d", cursor);
    return false;
}

bool Json_ParseSticker(
    const char[] json,
    int &cursor,
    StickerItem sticker,
    char[] error,
    int errorLength
)
{
    if (!Json_Consume(json, cursor, '{'))
    {
        Format(error, errorLength, "Expected sticker at byte %d", cursor);
        return false;
    }
    if (Json_Consume(json, cursor, '}'))
    {
        return true;
    }

    char property[24];
    while (json[cursor] != '\0')
    {
        if (!Json_ReadString(json, cursor, property, sizeof(property))
            || !Json_Consume(json, cursor, ':'))
        {
            Format(error, errorLength, "Invalid sticker at byte %d", cursor);
            return false;
        }

        if (StrEqual(property, "def"))
        {
            Json_ReadNullableInt(json, cursor, sticker.def);
        }
        else if (StrEqual(property, "slot"))
        {
            Json_ReadNullableInt(json, cursor, sticker.slot);
        }
        else if (StrEqual(property, "wear"))
        {
            sticker.hasWear = Json_ReadNullableFloat(json, cursor, sticker.wear);
        }
        else if (!Json_SkipValue(json, cursor))
        {
            Format(error, errorLength, "Invalid sticker value at byte %d", cursor);
            return false;
        }

        if (Json_Consume(json, cursor, '}'))
        {
            return true;
        }
        if (!Json_Consume(json, cursor, ','))
        {
            Format(error, errorLength, "Expected ',' at byte %d", cursor);
            return false;
        }
    }
    Format(error, errorLength, "Unterminated sticker at byte %d", cursor);
    return false;
}

bool Json_ReadNullableInt(const char[] json, int &cursor, int &value)
{
    Json_SkipWhitespace(json, cursor);
    if (Json_ConsumeLiteral(json, cursor, "null"))
    {
        value = 0;
        return false;
    }

    char number[32];
    if (!Json_ReadNumber(json, cursor, number, sizeof(number)))
    {
        value = 0;
        return false;
    }
    value = StringToInt(number);
    return true;
}

bool Json_ReadNullableFloat(const char[] json, int &cursor, float &value)
{
    Json_SkipWhitespace(json, cursor);
    if (Json_ConsumeLiteral(json, cursor, "null"))
    {
        value = 0.0;
        return false;
    }

    char number[48];
    if (!Json_ReadNumber(json, cursor, number, sizeof(number)))
    {
        value = 0.0;
        return false;
    }
    value = StringToFloat(number);
    return true;
}

bool Json_ReadNullableString(
    const char[] json,
    int &cursor,
    char[] output,
    int outputLength
)
{
    Json_SkipWhitespace(json, cursor);
    if (Json_ConsumeLiteral(json, cursor, "null"))
    {
        output[0] = '\0';
        return false;
    }
    return Json_ReadString(json, cursor, output, outputLength);
}

bool Json_ReadString(
    const char[] json,
    int &cursor,
    char[] output,
    int outputLength
)
{
    Json_SkipWhitespace(json, cursor);
    if (json[cursor] != '"')
    {
        return false;
    }
    cursor++;

    int written = 0;
    while (json[cursor] != '\0')
    {
        int character = json[cursor++];
        if (character == '"')
        {
            output[written] = '\0';
            return true;
        }
        if (character == '\\')
        {
            character = json[cursor++];
            switch (character)
            {
                case '"', '\\', '/':
                {
                    // Already the desired character.
                }
                case 'b':
                {
                    character = 8;
                }
                case 'f':
                {
                    character = 12;
                }
                case 'n':
                {
                    character = '\n';
                }
                case 'r':
                {
                    character = '\r';
                }
                case 't':
                {
                    character = '\t';
                }
                case 'u':
                {
                    int codepoint;
                    if (!Json_ReadHexCodepoint(json, cursor, codepoint))
                    {
                        return false;
                    }
                    if (codepoint >= 0xD800 && codepoint <= 0xDBFF)
                    {
                        if (json[cursor] != '\\'
                            || json[cursor + 1] != 'u')
                        {
                            return false;
                        }
                        cursor += 2;

                        int lowSurrogate;
                        if (!Json_ReadHexCodepoint(
                                json,
                                cursor,
                                lowSurrogate
                            )
                            || lowSurrogate < 0xDC00
                            || lowSurrogate > 0xDFFF)
                        {
                            return false;
                        }
                        codepoint = 0x10000
                            + ((codepoint - 0xD800) << 10)
                            + (lowSurrogate - 0xDC00);
                    }
                    else if (codepoint >= 0xDC00 && codepoint <= 0xDFFF)
                    {
                        return false;
                    }
                    Json_AppendUtf8(output, outputLength, written, codepoint);
                    continue;
                }
                default:
                {
                    return false;
                }
            }
        }
        else if (character < 0x20)
        {
            return false;
        }
        if (written + 1 < outputLength)
        {
            output[written++] = character;
        }
    }
    return false;
}

bool Json_ReadHexCodepoint(const char[] json, int &cursor, int &codepoint)
{
    codepoint = 0;
    for (int digit = 0; digit < 4; digit++)
    {
        int value = Json_HexValue(json[cursor++]);
        if (value < 0)
        {
            return false;
        }
        codepoint = (codepoint << 4) | value;
    }
    return true;
}

void Json_AppendUtf8(
    char[] output,
    int outputLength,
    int &written,
    int codepoint
)
{
    if (codepoint <= 0x7F)
    {
        if (written + 1 < outputLength)
        {
            output[written++] = codepoint;
        }
    }
    else if (codepoint <= 0x7FF)
    {
        if (written + 2 < outputLength)
        {
            output[written++] = 0xC0 | (codepoint >> 6);
            output[written++] = 0x80 | (codepoint & 0x3F);
        }
    }
    else if (codepoint <= 0xFFFF)
    {
        if (written + 3 < outputLength)
        {
            output[written++] = 0xE0 | (codepoint >> 12);
            output[written++] = 0x80 | ((codepoint >> 6) & 0x3F);
            output[written++] = 0x80 | (codepoint & 0x3F);
        }
    }
    else if (codepoint <= 0x10FFFF && written + 4 < outputLength)
    {
        output[written++] = 0xF0 | (codepoint >> 18);
        output[written++] = 0x80 | ((codepoint >> 12) & 0x3F);
        output[written++] = 0x80 | ((codepoint >> 6) & 0x3F);
        output[written++] = 0x80 | (codepoint & 0x3F);
    }
}

int Json_HexValue(int character)
{
    if (character >= '0' && character <= '9')
    {
        return character - '0';
    }
    if (character >= 'a' && character <= 'f')
    {
        return character - 'a' + 10;
    }
    if (character >= 'A' && character <= 'F')
    {
        return character - 'A' + 10;
    }
    return -1;
}

bool Json_ReadNumber(
    const char[] json,
    int &cursor,
    char[] output,
    int outputLength
)
{
    Json_SkipWhitespace(json, cursor);
    int start = cursor;
    if (json[cursor] == '-')
    {
        cursor++;
    }

    if (json[cursor] == '0')
    {
        cursor++;
        if (json[cursor] >= '0' && json[cursor] <= '9')
        {
            cursor = start;
            return false;
        }
    }
    else if (json[cursor] >= '1' && json[cursor] <= '9')
    {
        do
        {
            cursor++;
        }
        while (json[cursor] >= '0' && json[cursor] <= '9');
    }
    else
    {
        cursor = start;
        return false;
    }

    if (json[cursor] == '.')
    {
        cursor++;
        if (json[cursor] < '0' || json[cursor] > '9')
        {
            cursor = start;
            return false;
        }
        while (json[cursor] >= '0' && json[cursor] <= '9')
        {
            cursor++;
        }
    }
    if (json[cursor] == 'e' || json[cursor] == 'E')
    {
        cursor++;
        if (json[cursor] == '+' || json[cursor] == '-')
        {
            cursor++;
        }
        if (json[cursor] < '0' || json[cursor] > '9')
        {
            cursor = start;
            return false;
        }
        while (json[cursor] >= '0' && json[cursor] <= '9')
        {
            cursor++;
        }
    }

    int numberLength = cursor - start;
    if (numberLength <= 0 || numberLength >= outputLength)
    {
        cursor = start;
        return false;
    }

    for (int index = 0; index < numberLength; index++)
    {
        output[index] = json[start + index];
    }
    output[numberLength] = '\0';
    return true;
}

bool Json_ParseMapKey(const char[] key, int &value)
{
    if (key[0] == '\0')
    {
        return false;
    }

    for (int index = 0; key[index] != '\0'; index++)
    {
        if (key[index] < '0' || key[index] > '9')
        {
            return false;
        }
    }
    value = StringToInt(key);
    return true;
}

bool Json_RequireEnd(
    const char[] json,
    int &cursor,
    char[] error,
    int errorLength
)
{
    Json_SkipWhitespace(json, cursor);
    if (json[cursor] == '\0')
    {
        return true;
    }

    Format(error, errorLength, "Unexpected data at byte %d", cursor);
    return false;
}

bool Json_SkipValue(const char[] json, int &cursor)
{
    Json_SkipWhitespace(json, cursor);
    if (json[cursor] == '"')
    {
        char ignored[2];
        return Json_ReadString(json, cursor, ignored, sizeof(ignored));
    }
    if (json[cursor] == '{')
    {
        cursor++;
        if (Json_Consume(json, cursor, '}'))
        {
            return true;
        }
        while (json[cursor] != '\0')
        {
            char key[2];
            if (!Json_ReadString(json, cursor, key, sizeof(key))
                || !Json_Consume(json, cursor, ':')
                || !Json_SkipValue(json, cursor))
            {
                return false;
            }
            if (Json_Consume(json, cursor, '}'))
            {
                return true;
            }
            if (!Json_Consume(json, cursor, ','))
            {
                return false;
            }
        }
        return false;
    }
    if (json[cursor] == '[')
    {
        cursor++;
        if (Json_Consume(json, cursor, ']'))
        {
            return true;
        }
        while (json[cursor] != '\0')
        {
            if (!Json_SkipValue(json, cursor))
            {
                return false;
            }
            if (Json_Consume(json, cursor, ']'))
            {
                return true;
            }
            if (!Json_Consume(json, cursor, ','))
            {
                return false;
            }
        }
        return false;
    }
    if (Json_ConsumeLiteral(json, cursor, "true")
        || Json_ConsumeLiteral(json, cursor, "false")
        || Json_ConsumeLiteral(json, cursor, "null"))
    {
        return true;
    }

    char ignoredNumber[48];
    return Json_ReadNumber(json, cursor, ignoredNumber, sizeof(ignoredNumber));
}

bool Json_Consume(const char[] json, int &cursor, int expected)
{
    Json_SkipWhitespace(json, cursor);
    if (json[cursor] != expected)
    {
        return false;
    }
    cursor++;
    return true;
}

bool Json_ConsumeLiteral(
    const char[] json,
    int &cursor,
    const char[] literal
)
{
    Json_SkipWhitespace(json, cursor);
    int length = strlen(literal);
    for (int index = 0; index < length; index++)
    {
        if (json[cursor + index] != literal[index])
        {
            return false;
        }
    }
    cursor += length;
    return true;
}

void Json_SkipWhitespace(const char[] json, int &cursor)
{
    while (json[cursor] == ' '
        || json[cursor] == '\t'
        || json[cursor] == '\r'
        || json[cursor] == '\n')
    {
        cursor++;
    }
}
