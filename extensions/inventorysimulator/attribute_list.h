/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#ifndef INVENTORY_SIMULATOR_ATTRIBUTE_LIST_H
#define INVENTORY_SIMULATOR_ATTRIBUTE_LIST_H

#include "smsdk_ext.h"

bool AttributeList_OnLoad(char *error, size_t maxlength);
void AttributeList_OnUnload();

cell_t Native_SetOrAddAttributeValueByName(
    SourcePawn::IPluginContext *context,
    const cell_t *params
);

#endif
