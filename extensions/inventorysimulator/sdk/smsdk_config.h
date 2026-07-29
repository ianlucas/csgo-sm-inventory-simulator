/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#ifndef INVENTORY_SIMULATOR_SMSDK_CONFIG_H
#define INVENTORY_SIMULATOR_SMSDK_CONFIG_H

#define SMEXT_CONF_NAME          "Inventory Simulator"
#define SMEXT_CONF_DESCRIPTION   "HTTP and native item bridge"
#define SMEXT_CONF_VERSION       "1.0.0"
#define SMEXT_CONF_AUTHOR        "Ian Lucas"
#define SMEXT_CONF_URL           "https://inventory.cstrike.app"
#define SMEXT_CONF_LOGTAG        "INVSIM"
#define SMEXT_CONF_LICENSE       "MIT"
#define SMEXT_CONF_DATESTRING    __DATE__
#define SMEXT_LINK(name) SDKExtension *g_pExtensionIface = name;
#define SMEXT_ENABLE_LIBSYS
#define SMEXT_ENABLE_PLUGINSYS
#define SMEXT_ENABLE_GAMECONF
#endif
