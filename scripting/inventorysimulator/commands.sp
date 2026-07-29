/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

void Commands_Initialize()
{
    RegConsoleCmd(
        "sm_ws",
        Commands_OnWs,
        "Refresh Inventory Simulator items and display the configured URL."
    );
    RegConsoleCmd(
        "sm_wslogin",
        Commands_OnWsLogin,
        "Authenticate with Inventory Simulator."
    );
}

public Action Commands_OnWs(int client, int arguments)
{
    if (client < 1 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    char url[INVSIM_MAX_URL];
    Commands_FormatPublicUrl(url, sizeof(url));
    InventorySimulator_PrintString(client, "Announce", url);

    if (!g_CvarWsEnabled.BoolValue || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    int remaining = g_CvarWsCooldown.IntValue
        - (GetTime() - g_PlayerStates[client].wsUpdatedAt);
    if (g_PlayerStates[client].wsUpdatedAt > 0 && remaining > 0)
    {
        InventorySimulator_PrintNumber(client, "RefreshCooldown", remaining);
        return Plugin_Handled;
    }
    if (g_PlayerStates[client].fetching)
    {
        InventorySimulator_PrintSimple(client, "RefreshInProgress");
        return Plugin_Handled;
    }

    Api_FetchInventory(client, true);
    InventorySimulator_PrintSimple(client, "RefreshStarted");
    return Plugin_Handled;
}

public Action Commands_OnWsLogin(int client, int arguments)
{
    if (client < 1
        || !IsClientInGame(client)
        || IsFakeClient(client)
        || !g_CvarWsLogin.BoolValue)
    {
        return Plugin_Handled;
    }

    char apiKey[256];
    g_CvarApiKey.GetString(apiKey, sizeof(apiKey));
    if (apiKey[0] == '\0')
    {
        return Plugin_Handled;
    }

    InventorySimulator_PrintSimple(client, "LoginInProgress");
    Api_SignIn(client);
    return Plugin_Handled;
}

void Commands_FormatPublicUrl(char[] output, int outputLength)
{
    char baseUrl[INVSIM_MAX_URL];
    char host[INVSIM_MAX_URL];
    char withoutScheme[INVSIM_MAX_URL];
    char format[INVSIM_MAX_URL];
    ConVars_GetApiUrl(baseUrl, sizeof(baseUrl));
    strcopy(host, sizeof(host), baseUrl);

    int scheme = StrContains(host, "://");
    if (scheme >= 0)
    {
        strcopy(withoutScheme, sizeof(withoutScheme), host[scheme + 3]);
        strcopy(host, sizeof(host), withoutScheme);
    }
    int slash = FindCharInString(host, '/');
    if (slash >= 0)
    {
        host[slash] = '\0';
    }

    g_CvarWsUrlPrintFormat.GetString(format, sizeof(format));
    strcopy(output, outputLength, format);
    ReplaceString(output, outputLength, "{Host}", host, false);
    ReplaceString(output, outputLength, "{Url}", baseUrl, false);
}
