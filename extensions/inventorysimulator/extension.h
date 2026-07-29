/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#ifndef INVENTORY_SIMULATOR_EXTENSION_H
#define INVENTORY_SIMULATOR_EXTENSION_H

#include "smsdk_ext.h"

class InventorySimulatorExtension final
    : public SDKExtension,
      public SourceMod::IPluginsListener
{
public:
    bool SDK_OnLoad(char *error, size_t maxlength, bool late) override;
    void SDK_OnUnload() override;

    void OnPluginWillUnload(SourceMod::IPlugin *plugin) override;
    void OnPluginUnloaded(SourceMod::IPlugin *plugin) override;
};

extern InventorySimulatorExtension g_InventorySimulatorExtension;

#endif
