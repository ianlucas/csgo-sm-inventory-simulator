/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#include "attribute_list.h"

#include <stddef.h>
#include <stdint.h>

namespace
{
#pragma pack(push, 4)
struct EconItemAttribute
{
    void *vtable;
    uint16_t definitionIndex;
    uint16_t definitionIndexPadding;
    float value;
    float initialValue;
    int refundableCurrency;
    bool setBonus;
    uint8_t tailPadding[3];
};

struct AttributeVector
{
    EconItemAttribute *memory;
    int allocationCount;
    int growSize;
    int size;
    EconItemAttribute *debugElements;
};

struct AttributeList
{
    void *vtable;
    AttributeVector attributes;
    void *manager;
};

struct AttributeDefinition
{
    void *vtable;
    void *keyValues;
    uint16_t definitionIndex;
};
#pragma pack(pop)

static_assert(sizeof(void *) == 4, "Inventory Simulator targets 32-bit CSGO");
static_assert(
    sizeof(EconItemAttribute) == 24,
    "Unexpected CEconItemAttribute layout"
);
static_assert(
    offsetof(EconItemAttribute, definitionIndex) == 4,
    "Unexpected CEconItemAttribute definition-index offset"
);
static_assert(
    offsetof(EconItemAttribute, value) == 8,
    "Unexpected CEconItemAttribute value offset"
);
static_assert(
    offsetof(EconItemAttribute, setBonus) == 20,
    "Unexpected CEconItemAttribute set-bonus offset"
);
static_assert(sizeof(AttributeVector) == 20, "Unexpected CUtlVector layout");
static_assert(
    offsetof(AttributeVector, size) == 12,
    "Unexpected CUtlVector count offset"
);
static_assert(sizeof(AttributeList) == 28, "Unexpected CAttributeList layout");
static_assert(
    offsetof(AttributeList, attributes) == 4,
    "Unexpected CAttributeList vector offset"
);
static_assert(
    offsetof(AttributeDefinition, definitionIndex) == 8,
    "Unexpected attribute-definition index offset"
);

#if defined(_WIN32)
#define INVSIM_MEMBER_CALL __thiscall
#else
#define INVSIM_MEMBER_CALL
#endif

using SetAttributeByNameFn = void (INVSIM_MEMBER_CALL *)(
    AttributeList *,
    const char *,
    float
);
using GetItemSchemaFn = void *(*)();
using GetAttributeDefinitionByNameFn =
    AttributeDefinition *(INVSIM_MEMBER_CALL *)(void *, const char *);
using InsertAttributeFn = int (INVSIM_MEMBER_CALL *)(
    AttributeVector *,
    int,
    const EconItemAttribute *
);

#undef INVSIM_MEMBER_CALL

SourceMod::IGameConfig *g_AttributeGameConfig = nullptr;
SetAttributeByNameFn g_SetAttributeByName = nullptr;
GetItemSchemaFn g_GetItemSchema = nullptr;
GetAttributeDefinitionByNameFn g_GetAttributeDefinitionByName = nullptr;
InsertAttributeFn g_InsertAttribute = nullptr;
void *g_ItemSchema = nullptr;
int g_ItemSchemaAdjustment = 0;

bool ResolveSignature(
    const char *name,
    void **address,
    char *error,
    size_t maxlength
)
{
    if (g_AttributeGameConfig->GetMemSig(name, address)
        && *address != nullptr)
    {
        return true;
    }

    smutils->Format(
        error,
        maxlength,
        "Missing gamedata signature \"%s\"",
        name
    );
    return false;
}

void *GetItemSchema()
{
    if (g_ItemSchema == nullptr && g_GetItemSchema != nullptr)
    {
        uint8_t *itemSystem = static_cast<uint8_t *>(g_GetItemSchema());
        if (itemSystem != nullptr)
        {
            g_ItemSchema = itemSystem + g_ItemSchemaAdjustment;
        }
    }
    return g_ItemSchema;
}

cell_t SetAttributeByNameFallback(
    SourcePawn::IPluginContext *context,
    AttributeList *attributeList,
    const char *attributeName,
    float value
)
{
    void *itemSchema = GetItemSchema();
    if (itemSchema == nullptr)
    {
        return context->ThrowNativeError("GetItemSchema returned null");
    }

    AttributeDefinition *definition = g_GetAttributeDefinitionByName(
        itemSchema,
        attributeName
    );
    if (definition == nullptr)
    {
        return 0;
    }

    AttributeVector &attributes = attributeList->attributes;
    if (attributes.size < 0
        || attributes.allocationCount < attributes.size
        || (attributes.size != 0 && attributes.memory == nullptr))
    {
        return context->ThrowNativeError(
            "CAttributeList contains an invalid CUtlVector"
        );
    }

    for (int index = 0; index < attributes.size; index++)
    {
        EconItemAttribute &attribute = attributes.memory[index];
        if (!attribute.setBonus
            && attribute.definitionIndex == definition->definitionIndex)
        {
            attribute.value = value;
            return 0;
        }
    }

    EconItemAttribute attribute = {};
    attribute.definitionIndex = definition->definitionIndex;
    attribute.value = value;
    attribute.initialValue = value;

    g_InsertAttribute(&attributes, attributes.size, &attribute);
    return 0;
}
}

bool AttributeList_OnLoad(char *error, size_t maxlength)
{
    char gameConfigError[256];
    if (!gameconfs->LoadGameConfigFile(
            "inventorysimulator.games",
            &g_AttributeGameConfig,
            gameConfigError,
            sizeof(gameConfigError)
        ))
    {
        smutils->Format(
            error,
            maxlength,
            "Unable to load inventorysimulator gamedata: %s",
            gameConfigError
        );
        AttributeList_OnUnload();
        return false;
    }

    void *address = nullptr;
    if (g_AttributeGameConfig->GetMemSig(
            "CAttributeList::SetOrAddAttributeValueByName",
            &address
        )
        && address != nullptr)
    {
        g_SetAttributeByName =
            reinterpret_cast<SetAttributeByNameFn>(address);
        return true;
    }

    if (!ResolveSignature(
            "GetItemSchema",
            &address,
            error,
            maxlength
        ))
    {
        AttributeList_OnUnload();
        return false;
    }
    g_GetItemSchema = reinterpret_cast<GetItemSchemaFn>(address);

    if (!ResolveSignature(
            "CEconItemSchema::GetAttributeDefinitionByName",
            &address,
            error,
            maxlength
        ))
    {
        AttributeList_OnUnload();
        return false;
    }
    g_GetAttributeDefinitionByName =
        reinterpret_cast<GetAttributeDefinitionByNameFn>(address);

    if (!ResolveSignature(
            "CUtlVector<CEconItemAttribute>::InsertBefore",
            &address,
            error,
            maxlength
        ))
    {
        AttributeList_OnUnload();
        return false;
    }
    g_InsertAttribute = reinterpret_cast<InsertAttributeFn>(address);

    if (!g_AttributeGameConfig->GetOffset(
            "GetItemSchemaReturnAdjustment",
            &g_ItemSchemaAdjustment
        ))
    {
        smutils->Format(
            error,
            maxlength,
            "Missing gamedata offset \"GetItemSchemaReturnAdjustment\""
        );
        AttributeList_OnUnload();
        return false;
    }

    return true;
}

void AttributeList_OnUnload()
{
    g_SetAttributeByName = nullptr;
    g_GetItemSchema = nullptr;
    g_GetAttributeDefinitionByName = nullptr;
    g_InsertAttribute = nullptr;
    g_ItemSchema = nullptr;
    g_ItemSchemaAdjustment = 0;

    if (g_AttributeGameConfig != nullptr)
    {
        gameconfs->CloseGameConfigFile(g_AttributeGameConfig);
        g_AttributeGameConfig = nullptr;
    }
}

cell_t Native_SetOrAddAttributeValueByName(
    SourcePawn::IPluginContext *context,
    const cell_t *params
)
{
    if (params[0] != 3)
    {
        return context->ThrowNativeError(
            "InvSim_SetOrAddAttributeValueByName expects 3 parameters"
        );
    }

    AttributeList *attributeList = reinterpret_cast<AttributeList *>(
        static_cast<uintptr_t>(params[1])
    );
    if (attributeList == nullptr)
    {
        return context->ThrowNativeError("CAttributeList is null");
    }

    char *attributeName = nullptr;
    if (context->LocalToString(params[2], &attributeName) != SP_ERROR_NONE)
    {
        return 0;
    }
    if (attributeName == nullptr)
    {
        return context->ThrowNativeError("Attribute name is null");
    }

    float value = sp_ctof(params[3]);
    if (g_SetAttributeByName != nullptr)
    {
        g_SetAttributeByName(attributeList, attributeName, value);
        return 0;
    }

    return SetAttributeByNameFallback(
        context,
        attributeList,
        attributeName,
        value
    );
}
