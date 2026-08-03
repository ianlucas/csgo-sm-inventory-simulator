/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

static bool g_SpraysInitialized;
static ArrayList g_SprayEntities;

// Final CSGO graffiti inventory items store one of these legacy palette IDs.
// items_game.txt defines them as sRGB hex colors.
static const int g_SprayLegacyTintRgb[20] =
{
    0xFFFFFF,
    0x874444, 0xB14D4D, 0xB87148, 0x8F7D5D, 0xAE833D,
    0xD4C95B, 0x789D53, 0x417A4A, 0x488F80, 0xA6C4A5,
    0x6BA5B2, 0x4E7FA9, 0x4C5B98, 0xAF92DF, 0x6E4F9F,
    0xBA68B2, 0x9D567A, 0xE4CCD5, 0xC1C1C1
};

// Earlier experimental builds also support Valve's packed procedural HSV
// representation. Its low byte selects one of these HSV subspaces.
static const int g_SprayTintDefinitions[11][15] =
{
    {180, 180, 180, 0, 0, 0, 0, 0, 0, 100, 100, 100, 100, 100, 100},
    {158, 174, 190, 50, 60, 40, 90, 90, 90, 60, 60, 60, 90, 90, 90},
    {348, 358, 368, 78, 80, 70, 90, 90, 90, 48, 50, 50, 82, 80, 80},
    {18, 28, 38, 74, 72, 70, 94, 92, 90, 58, 78, 74, 84, 92, 98},
    {48, 54, 61, 40, 40, 40, 92, 92, 92, 82, 82, 82, 98, 98, 98},
    {108, 129, 150, 40, 50, 54, 90, 90, 90, 60, 60, 58, 90, 90, 90},
    {207, 223, 238, 70, 40, 50, 90, 90, 90, 60, 50, 70, 100, 80, 100},
    {258, 272, 289, 50, 40, 40, 90, 80, 80, 60, 60, 60, 100, 90, 80},
    {308, 340, 372, 20, 20, 20, 67, 50, 64, 84, 80, 86, 98, 98, 98},
    {68, 78, 94, 50, 50, 50, 92, 90, 90, 62, 70, 80, 98, 98, 98},
    {0, 180, 360, 2, 2, 2, 7, 7, 7, 90, 90, 90, 97, 97, 97}
};

void Sprays_Initialize()
{
    if (!g_CvarSprayEnabled.BoolValue || g_SpraysInitialized)
    {
        return;
    }
    if (g_SprayEntities == null)
    {
        g_SprayEntities = new ArrayList();
    }
    SprayModels_Initialize();
    PrecacheScriptSound("SprayCan.Shake");
    PrecacheScriptSound("SprayCan.Paint");
    g_SpraysInitialized = true;
}

void Sprays_OnMapStart()
{
    g_SpraysInitialized = false;
    if (g_SprayEntities != null)
    {
        g_SprayEntities.Clear();
    }
    Sprays_Initialize();
}

void Sprays_Shutdown()
{
    Sprays_RemoveAll();
    SprayModels_Shutdown();
    delete g_SprayEntities;
    g_SprayEntities = null;
}

void Sprays_RemoveAll()
{
    if (g_SprayEntities == null)
    {
        return;
    }
    for (int index = 0; index < g_SprayEntities.Length; index++)
    {
        int entity = EntRefToEntIndex(g_SprayEntities.Get(index));
        if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
        {
            RemoveEntity(entity);
        }
    }
    g_SprayEntities.Clear();
}

Action Sprays_OnCommand(int client)
{
    Sprays_TryApply(client);
    return Plugin_Handled;
}

static void Sprays_TryApply(int client)
{
    if (!g_CvarSprayEnabled.BoolValue
        || client < 1
        || !IsClientInGame(client)
        || IsFakeClient(client))
    {
        return;
    }
    if (!IsPlayerAlive(client))
    {
        InventorySimulator_PrintSimple(client, "SprayAlive");
        return;
    }

    int tint;
    int graffitiDef;
    char sprayModel[128];
    int sprayModelIndex = -1;
    PlayerInventory inventory;
    InventoryItem graffiti;
    int itemIndex;
    if (!InventorySimulator_GetClientInventory(client, inventory)
        || !inventory.GetSingleItem(
            InventoryItem_Graffiti,
            graffiti,
            itemIndex
        )
        || !graffiti.hasDef)
    {
        InventorySimulator_PrintSimple(client, "SprayMissing");
        return;
    }
    graffitiDef = graffiti.def;
    if (!SprayModels_Get(
        graffitiDef,
        sprayModel,
        sizeof(sprayModel),
        sprayModelIndex
    ))
    {
        InventorySimulator_PrintSimple(client, "SprayUnsupported");
        return;
    }
    tint = graffiti.hasTint ? graffiti.tint : 0;

    int remaining = g_CvarSprayCooldown.IntValue
        - (GetTime() - g_PlayerStates[client].sprayUsedAt);
    if (g_PlayerStates[client].sprayUsedAt > 0
        && remaining > 0)
    {
        InventorySimulator_PrintNumber(client, "SprayCooldown", remaining);
        return;
    }
    if (sprayModelIndex <= 0)
    {
        InventorySimulator_PrintSimple(client, "SprayUnavailable");
        return;
    }

    float eyePosition[3];
    float eyeAngles[3];
    float direction[3];
    float endPosition[3];
    GetClientEyePosition(client, eyePosition);
    GetClientEyeAngles(client, eyeAngles);
    GetAngleVectors(eyeAngles, direction, NULL_VECTOR, NULL_VECTOR);
    ScaleVector(direction, INVSIM_SPRAY_DISTANCE);
    AddVectors(eyePosition, direction, endPosition);

    Handle trace = TR_TraceRayFilterEx(
        eyePosition,
        endPosition,
        MASK_SOLID_BRUSHONLY,
        RayType_EndPoint,
        Sprays_TraceFilter,
        client
    );
    bool hit = TR_DidHit(trace);
    float planeNormal[3];
    if (hit)
    {
        TR_GetEndPosition(endPosition, trace);
        TR_GetPlaneNormal(trace, planeNormal);
    }
    delete trace;
    if (!hit)
    {
        InventorySimulator_PrintSimple(client, "SprayNoSurface");
        return;
    }

    float color[3];
    int srgb;
    Sprays_TintToLinearRgb(tint, color, srgb);
    int sprite = Sprays_CreateTintedSprite(
        endPosition,
        planeNormal,
        srgb,
        sprayModel
    );
    if (sprite == -1)
    {
        InventorySimulator_PrintSimple(client, "SprayUnavailable");
        return;
    }

    EmitGameSoundToClient(client, "SprayCan.Shake");
    EmitGameSoundToClient(client, "SprayCan.Paint");
    g_PlayerStates[client].sprayUsedAt = GetTime();
    Sprays_ConsumeCharge(client, inventory, graffiti, itemIndex);
}

static int Sprays_CreateTintedSprite(
    const float surfacePosition[3],
    const float surfaceNormal[3],
    int srgb,
    const char[] sprayModel
)
{
    int sprite = CreateEntityByName("env_sprite_oriented");
    if (sprite == -1)
    {
        return -1;
    }

    DispatchKeyValue(sprite, "model", sprayModel);
    DispatchKeyValue(sprite, "rendermode", "1");
    DispatchKeyValue(sprite, "renderamt", "255");
    DispatchKeyValue(sprite, "scale", "48");
    DispatchSpawn(sprite);

    if (HasEntProp(sprite, Prop_Send, "m_bWorldSpaceScale"))
    {
        SetEntProp(sprite, Prop_Send, "m_bWorldSpaceScale", 1);
    }
    SetEntityRenderColor(
        sprite,
        (srgb >> 16) & 0xFF,
        (srgb >> 8) & 0xFF,
        srgb & 0xFF,
        255
    );
    SetEntProp(sprite, Prop_Send, "m_nBrightness", 0);
    SetEntPropFloat(sprite, Prop_Send, "m_flBrightnessTime", 0.0);

    float position[3];
    position[0] = surfacePosition[0] + surfaceNormal[0] * 0.2;
    position[1] = surfacePosition[1] + surfaceNormal[1] * 0.2;
    position[2] = surfacePosition[2] + surfaceNormal[2] * 0.2;
    float facingNormal[3];
    facingNormal[0] = -surfaceNormal[0];
    facingNormal[1] = -surfaceNormal[1];
    facingNormal[2] = -surfaceNormal[2];
    float angles[3];
    // View the sprite from its back face to correct its horizontal mirroring.
    // Negating the complete trace normal preserves the exact surface plane;
    // adding 180 degrees of world yaw would tilt non-vertical placements.
    GetVectorAngles(facingNormal, angles);
    TeleportEntity(sprite, position, angles, NULL_VECTOR);

    int entityRef = EntIndexToEntRef(sprite);
    g_SprayEntities.Push(entityRef);
    CreateTimer(0.1, Sprays_OnFadeIn, entityRef, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(
        INVSIM_SPRAY_FADE_START,
        Sprays_OnFadeOut,
        entityRef,
        TIMER_FLAG_NO_MAPCHANGE
    );
    CreateTimer(
        INVSIM_SPRAY_TOTAL_DURATION,
        Sprays_OnExpire,
        entityRef,
        TIMER_FLAG_NO_MAPCHANGE
    );

    return sprite;
}

public Action Sprays_OnFadeIn(Handle timer, any entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
    {
        return Plugin_Stop;
    }
    SetEntPropFloat(
        entity,
        Prop_Send,
        "m_flBrightnessTime",
        INVSIM_SPRAY_APPLY_DURATION - 0.1
    );
    SetEntProp(entity, Prop_Send, "m_nBrightness", 255);
    return Plugin_Stop;
}

public Action Sprays_OnFadeOut(Handle timer, any entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
    {
        return Plugin_Stop;
    }
    SetEntPropFloat(
        entity,
        Prop_Send,
        "m_flBrightnessTime",
        INVSIM_SPRAY_TOTAL_DURATION - INVSIM_SPRAY_FADE_START
    );
    SetEntProp(entity, Prop_Send, "m_nBrightness", 0);
    return Plugin_Stop;
}

public Action Sprays_OnExpire(Handle timer, any entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
    {
        RemoveEntity(entity);
    }
    if (g_SprayEntities != null)
    {
        int index = g_SprayEntities.FindValue(entityRef);
        if (index >= 0)
        {
            g_SprayEntities.Erase(index);
        }
    }
    return Plugin_Stop;
}

static void Sprays_ConsumeCharge(
    int client,
    PlayerInventory inventory,
    InventoryItem graffiti,
    int itemIndex
)
{
    if (!graffiti.hasCharges)
    {
        return;
    }

    graffiti.charges--;
    if (graffiti.hasUid)
    {
        Api_SendSprayConsume(g_PlayerStates[client].steamId, graffiti.uid);
    }
    if (graffiti.charges <= 0)
    {
        inventory.ClearGraffiti();
        InventorySimulator_PrintSimple(client, "SprayChargesEmpty");
        return;
    }

    inventory.SaveItemAt(itemIndex, graffiti);
    InventorySimulator_PrintNumber(client, "SprayCharges", graffiti.charges);
}

void Sprays_OnUsePressed(int client)
{
    if (!IsPlayerAlive(client) || Sprays_IsUseBusy(client))
    {
        return;
    }
    delete g_PlayerStates[client].sprayUseTimer;
    g_PlayerStates[client].sprayUseTimer = CreateTimer(
        0.1,
        Sprays_OnUseTimer,
        GetClientSerial(client),
        TIMER_FLAG_NO_MAPCHANGE
    );
}

public Action Sprays_OnUseTimer(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (client == 0)
    {
        return Plugin_Stop;
    }
    g_PlayerStates[client].sprayUseTimer = null;
    if (!Sprays_IsUseBusy(client))
    {
        Sprays_TryApply(client);
    }
    return Plugin_Stop;
}

static bool Sprays_IsUseBusy(int client)
{
    if (HasEntProp(client, Prop_Send, "m_bIsDefusing")
        && GetEntProp(client, Prop_Send, "m_bIsDefusing") != 0)
    {
        return true;
    }

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return false;
    }
    char classname[32];
    GetEntityClassname(weapon, classname, sizeof(classname));
    return StrEqual(classname, "weapon_c4")
        && HasEntProp(weapon, Prop_Send, "m_bStartedArming")
        && GetEntProp(weapon, Prop_Send, "m_bStartedArming") != 0;
}

static int Sprays_TintToLinearRgb(int tint, float color[3], int &srgb)
{
    if (tint >= 1 && tint < sizeof(g_SprayLegacyTintRgb))
    {
        srgb = g_SprayLegacyTintRgb[tint];
        color[0] = float((srgb >> 16) & 0xFF) / 255.0;
        color[1] = float((srgb >> 8) & 0xFF) / 255.0;
        color[2] = float(srgb & 0xFF) / 255.0;
        color[0] = Sprays_SrgbToLinear(color[0]);
        color[1] = Sprays_SrgbToLinear(color[1]);
        color[2] = Sprays_SrgbToLinear(color[2]);
        return tint;
    }

    int bucket = tint & 0xFF;
    if (bucket < 1 || bucket > 10)
    {
        srgb = 0xFFFFFF;
        color[0] = 1.0;
        color[1] = 1.0;
        color[2] = 1.0;
        return 0;
    }

    float hsvComponents[3];
    hsvComponents[0] = float((tint >> 8) & 0x7F) / 127.0;
    hsvComponents[1] = float((tint >> 15) & 0x7F) / 127.0;
    hsvComponents[2] = float((tint >> 22) & 0x7F) / 127.0;

    float huePercent = hsvComponents[0] * 2.0;
    int hueIndex;
    if (huePercent > 1.0)
    {
        hueIndex = 1;
        huePercent -= 1.0;
    }

    float hue = Sprays_Lerp(
        huePercent,
        float(g_SprayTintDefinitions[bucket][hueIndex]),
        float(g_SprayTintDefinitions[bucket][hueIndex + 1])
    );
    float saturationLow = Sprays_Lerp(
        huePercent,
        float(g_SprayTintDefinitions[bucket][3 + hueIndex]),
        float(g_SprayTintDefinitions[bucket][4 + hueIndex])
    );
    float saturationHigh = Sprays_Lerp(
        huePercent,
        float(g_SprayTintDefinitions[bucket][6 + hueIndex]),
        float(g_SprayTintDefinitions[bucket][7 + hueIndex])
    );
    float saturation = Sprays_Lerp(
        hsvComponents[1],
        saturationLow,
        saturationHigh
    ) / 100.0;
    float valueLow = Sprays_Lerp(
        huePercent,
        float(g_SprayTintDefinitions[bucket][9 + hueIndex]),
        float(g_SprayTintDefinitions[bucket][10 + hueIndex])
    );
    float valueHigh = Sprays_Lerp(
        huePercent,
        float(g_SprayTintDefinitions[bucket][12 + hueIndex]),
        float(g_SprayTintDefinitions[bucket][13 + hueIndex])
    );
    float brightness = Sprays_Lerp(
        hsvComponents[2],
        valueLow,
        valueHigh
    ) / 100.0;
    if (hue >= 360.0)
    {
        hue -= 360.0;
    }

    float segment = hue / 60.0;
    int segmentIndex = RoundToFloor(segment);
    float fraction = segment - float(segmentIndex);
    float p = brightness * (1.0 - saturation);
    float q = brightness * (1.0 - saturation * fraction);
    float t = brightness * (1.0 - saturation * (1.0 - fraction));
    switch (segmentIndex)
    {
        case 0:
        {
            color[0] = brightness; color[1] = t; color[2] = p;
        }
        case 1:
        {
            color[0] = q; color[1] = brightness; color[2] = p;
        }
        case 2:
        {
            color[0] = p; color[1] = brightness; color[2] = t;
        }
        case 3:
        {
            color[0] = p; color[1] = q; color[2] = brightness;
        }
        case 4:
        {
            color[0] = t; color[1] = p; color[2] = brightness;
        }
        default:
        {
            color[0] = brightness; color[1] = p; color[2] = q;
        }
    }

    srgb = (RoundToNearest(color[0] * 255.0) << 16)
        | (RoundToNearest(color[1] * 255.0) << 8)
        | RoundToNearest(color[2] * 255.0);
    color[0] = Sprays_SrgbToLinear(color[0]);
    color[1] = Sprays_SrgbToLinear(color[1]);
    color[2] = Sprays_SrgbToLinear(color[2]);
    return bucket;
}

static float Sprays_Lerp(float amount, float from, float to)
{
    return from + (to - from) * amount;
}

static float Sprays_SrgbToLinear(float value)
{
    if (value <= 0.04045)
    {
        return value / 12.92;
    }
    return Pow((value + 0.055) / 1.055, 2.4);
}

public bool Sprays_TraceFilter(int entity, int contentsMask, any client)
{
    return entity != client;
}
