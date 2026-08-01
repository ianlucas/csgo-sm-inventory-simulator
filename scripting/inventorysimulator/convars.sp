/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

ConVar g_CvarUrl;
ConVar g_CvarApiKey;
ConVar g_CvarFile;
ConVar g_CvarWsEnabled;
ConVar g_CvarWsImmediately;
ConVar g_CvarWsCooldown;
ConVar g_CvarChatPrefix;
ConVar g_CvarWsUrlPrintFormat;
ConVar g_CvarWsLogin;
ConVar g_CvarPersistInventory;
ConVar g_CvarRequireInventory;
ConVar g_CvarPublicApiStatTrak;
ConVar g_CvarStatTrakIgnoreBots;
ConVar g_CvarFallbackTeam;
ConVar g_CvarMinModels;
ConVar g_CvarDebug;

void ConVars_Initialize()
{
    g_CvarUrl = CreateConVar(
        "invsim_url",
        "https://inventory.cstrike.app",
        "API URL for the Inventory Simulator service."
    );
    g_CvarApiKey = CreateConVar(
        "invsim_apikey",
        "",
        "API key for the Inventory Simulator service.",
        FCVAR_PROTECTED
    );
    g_CvarFile = CreateConVar(
        "invsim_file",
        "inventories.json",
        "Inventory data file to load when the plugin starts."
    );
    g_CvarWsEnabled = CreateConVar(
        "invsim_ws_enabled",
        "0",
        "Allow players to refresh their inventory using !ws.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_CvarWsImmediately = CreateConVar(
        "invsim_ws_immediately",
        "0",
        "Apply skin changes immediately without requiring a respawn.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_CvarWsCooldown = CreateConVar(
        "invsim_ws_cooldown",
        "30",
        "Cooldown in seconds between !ws refreshes.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_CvarChatPrefix = CreateConVar(
        "invsim_chat_prefix",
        "",
        "Prefix displayed before Inventory Simulator chat messages."
    );
    g_CvarWsUrlPrintFormat = CreateConVar(
        "invsim_ws_url_print_format",
        "{Host}",
        "URL format shown by !ws. Supports {Host} and {Url}."
    );
    g_CvarWsLogin = CreateConVar(
        "invsim_wslogin",
        "0",
        "Allow players to authenticate using !wslogin.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_CvarPersistInventory = CreateConVar(
        "invsim_persist_inventory",
        "0",
        "Keep fetched inventories after players disconnect.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_CvarRequireInventory = CreateConVar(
        "invsim_require_inventory",
        "0",
        "Keep players on the loading screen until their inventory fetch completes.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_CvarPublicApiStatTrak = CreateConVar(
        "invsim_public_api_stattrak_increment",
        "1",
        "Send keyless StatTrak increment requests to the public API when invsim_apikey is not set.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_CvarStatTrakIgnoreBots = CreateConVar(
        "invsim_stattrak_ignore_bots",
        "1",
        "Ignore StatTrak increments for bot kills.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_CvarFallbackTeam = CreateConVar(
        "invsim_fallback_team",
        "0",
        "Fall back to the other team's item when no current-team item exists.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_CvarMinModels = CreateConVar(
        "invsim_minmodels",
        "0",
        "Agent mode: 0 inventory agents, 1 map defaults, 2 SAS/Phoenix.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        2.0
    );

    g_CvarDebug = CreateConVar(
        "invsim_debug",
        "0",
        "Log detailed diagnostics about hooks and item generation.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );

    HookConVarChange(g_CvarFile, ConVars_OnFileChanged);
    HookConVarChange(
        g_CvarRequireInventory,
        ConVars_OnRequireInventoryChanged
    );
    HookConVarChange(g_CvarUrl, ConVars_OnUrlChanged);
    HookConVarChange(g_CvarApiKey, ConVars_OnApiSuspensionConVarChanged);
    HookConVarChange(
        g_CvarPublicApiStatTrak,
        ConVars_OnApiSuspensionConVarChanged
    );
}

public void ConVars_OnUrlChanged(
    ConVar convar,
    const char[] oldValue,
    const char[] newValue
)
{
    Api_ResetSuspension();
    if (StrEqual(oldValue, newValue))
    {
        return;
    }
    if (!ConVars_IsOfficialHost(newValue))
    {
        g_CvarPublicApiStatTrak.SetInt(0);
    }
}

public void ConVars_OnApiSuspensionConVarChanged(
    ConVar convar,
    const char[] oldValue,
    const char[] newValue
)
{
    Api_ResetSuspension();
}

static bool ConVars_IsOfficialHost(const char[] url)
{
    char host[128];
    int start = StrContains(url, "://");
    start = start == -1 ? 0 : start + 3;
    int written = 0;
    for (int index = start;
        url[index] != '\0' && written < sizeof(host) - 1;
        index++)
    {
        if (url[index] == '/'
            || url[index] == ':'
            || url[index] == '?'
            || url[index] == '#')
        {
            break;
        }
        host[written++] = url[index];
    }
    host[written] = '\0';
    return StrEqual(host, "inventory.cstrike.app", false);
}

public void ConVars_OnFileChanged(
    ConVar convar,
    const char[] oldValue,
    const char[] newValue
)
{
    InventoryStore_LoadStatic();
}

public void ConVars_OnRequireInventoryChanged(
    ConVar convar,
    const char[] oldValue,
    const char[] newValue
)
{
    if (!convar.BoolValue)
    {
        GameHooks_ResumeAllActivations();
    }
}

void ConVars_GetApiUrl(char[] output, int outputLength)
{
    g_CvarUrl.GetString(output, outputLength);
    int length = strlen(output);
    while (length > 0 && output[length - 1] == '/')
    {
        output[--length] = '\0';
    }
}

void ConVars_GetChatPrefix(char[] output, int outputLength)
{
    g_CvarChatPrefix.GetString(output, outputLength);
    if (output[0] != '\0')
    {
        StrCat(output, outputLength, " ");
    }
}
