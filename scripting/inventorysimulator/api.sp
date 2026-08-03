/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

enum ApiRequestKind
{
    ApiRequest_Fetch,
    ApiRequest_SignIn,
    ApiRequest_StatTrak,
    ApiRequest_Spray
};

static bool g_ApiSuspended;
static StringMap g_StatTrakBuckets;
static StringMap g_SprayBuckets;

void Api_ResetSuspension()
{
    g_ApiSuspended = false;
}

static bool Api_ConsumeStatTrakToken(const char[] steamId, int uid)
{
    if (g_StatTrakBuckets == null)
    {
        g_StatTrakBuckets = new StringMap();
    }

    char key[80];
    Format(key, sizeof(key), "%s:%d", steamId, uid);

    float now = GetEngineTime();
    float bucket[2]; // tokens, updatedAt
    if (!g_StatTrakBuckets.GetArray(key, bucket, sizeof(bucket)))
    {
        bucket[0] = INVSIM_STATTRAK_RATE_LIMIT_CAPACITY;
        bucket[1] = now;
    }

    float elapsed = now - bucket[1];
    bucket[0] += elapsed / INVSIM_STATTRAK_RATE_LIMIT_REFILL_INTERVAL;
    if (bucket[0] > INVSIM_STATTRAK_RATE_LIMIT_CAPACITY)
    {
        bucket[0] = INVSIM_STATTRAK_RATE_LIMIT_CAPACITY;
    }
    bucket[1] = now;

    bool consumed = bucket[0] >= 1.0;
    if (consumed)
    {
        bucket[0] -= 1.0;
    }
    g_StatTrakBuckets.SetArray(key, bucket, sizeof(bucket));
    return consumed;
}

static bool Api_ConsumeSprayToken(const char[] steamId, int uid)
{
    if (g_SprayBuckets == null)
    {
        g_SprayBuckets = new StringMap();
    }

    char key[80];
    Format(key, sizeof(key), "%s:%d", steamId, uid);

    float now = GetEngineTime();
    float bucket[2];
    if (!g_SprayBuckets.GetArray(key, bucket, sizeof(bucket)))
    {
        bucket[0] = INVSIM_SPRAY_RATE_LIMIT_CAPACITY;
        bucket[1] = now;
    }

    float elapsed = now - bucket[1];
    bucket[0] += elapsed / INVSIM_SPRAY_RATE_LIMIT_REFILL_INTERVAL;
    if (bucket[0] > INVSIM_SPRAY_RATE_LIMIT_CAPACITY)
    {
        bucket[0] = INVSIM_SPRAY_RATE_LIMIT_CAPACITY;
    }
    bucket[1] = now;

    bool consumed = bucket[0] >= 1.0;
    if (consumed)
    {
        bucket[0] -= 1.0;
    }
    g_SprayBuckets.SetArray(key, bucket, sizeof(bucket));
    return consumed;
}

void Api_FetchInventory(int client, bool force, int attempt = 1)
{
    if (!IsClientConnected(client) || IsFakeClient(client))
    {
        return;
    }

    if (attempt == 1)
    {
        if (g_PlayerStates[client].fetching)
        {
            return;
        }

        PlayerInventory existing;
        bool fromFile;
        if (!force
            && InventoryStore_Get(
                g_PlayerStates[client].steamId,
                existing,
                fromFile
            ))
        {
            g_PlayerStates[client].loadedFromFile = fromFile;
            InventorySimulator_OnInventoryReady(client, false, true);
            return;
        }

        g_PlayerStates[client].fetching = true;
        g_PlayerStates[client].fetchGeneration++;
        InventorySimulator_SetInventoryWait(client, true);
    }

    char baseUrl[INVSIM_MAX_URL];
    char url[INVSIM_MAX_URL];
    ConVars_GetApiUrl(baseUrl, sizeof(baseUrl));
    Format(
        url,
        sizeof(url),
        "%s/api/equipped/v5/%s.json",
        baseUrl,
        g_PlayerStates[client].steamId
    );

    DataPack context = new DataPack();
    context.WriteCell(ApiRequest_Fetch);
    context.WriteCell(GetClientSerial(client));
    context.WriteCell(g_PlayerStates[client].fetchGeneration);
    context.WriteCell(attempt);
    context.WriteCell(force);

    int requestId = InvSim_HTTPRequest(
        InvSimHttp_Get,
        url,
        "",
        Api_OnResponse,
        context
    );
    if (requestId <= 0)
    {
        delete context;
        Api_HandleFetchFailure(
            client,
            g_PlayerStates[client].fetchGeneration,
            attempt,
            force,
            "request setup failed"
        );
    }
}

void Api_SignIn(int client)
{
    if (g_PlayerStates[client].authenticating)
    {
        return;
    }
    g_PlayerStates[client].authenticating = true;

    char baseUrl[INVSIM_MAX_URL];
    char url[INVSIM_MAX_URL];
    char apiKey[256];
    char escapedKey[512];
    ConVars_GetApiUrl(baseUrl, sizeof(baseUrl));
    g_CvarApiKey.GetString(apiKey, sizeof(apiKey));
    Json_Escape(apiKey, escapedKey, sizeof(escapedKey));
    Format(url, sizeof(url), "%s/api/sign-in", baseUrl);

    char body[768];
    Format(
        body,
        sizeof(body),
        "{\"apiKey\":\"%s\",\"userId\":\"%s\"}",
        escapedKey,
        g_PlayerStates[client].steamId
    );

    DataPack context = new DataPack();
    context.WriteCell(ApiRequest_SignIn);
    context.WriteCell(GetClientSerial(client));
    if (InvSim_HTTPRequest(
        InvSimHttp_Post,
        url,
        body,
        Api_OnResponse,
        context
    ) <= 0)
    {
        delete context;
        g_PlayerStates[client].authenticating = false;
        InventorySimulator_PrintSimple(client, "LoginFailed");
    }
}

void Api_SendStatTrak(const char[] steamId, int uid)
{
    if (g_ApiSuspended)
    {
        return;
    }

    char apiKey[256];
    g_CvarApiKey.GetString(apiKey, sizeof(apiKey));
    bool hasApiKey = apiKey[0] != '\0';
    if (!hasApiKey)
    {
        if (!g_CvarPublicApiStatTrak.BoolValue)
        {
            return;
        }
        if (!Api_ConsumeStatTrakToken(steamId, uid))
        {
            return;
        }
    }

    char baseUrl[INVSIM_MAX_URL];
    char url[INVSIM_MAX_URL];
    ConVars_GetApiUrl(baseUrl, sizeof(baseUrl));
    Format(url, sizeof(url), "%s/api/increment-item-stattrak", baseUrl);

    char body[896];
    if (hasApiKey)
    {
        char escapedKey[512];
        Json_Escape(apiKey, escapedKey, sizeof(escapedKey));
        Format(
            body,
            sizeof(body),
            "{\"apiKey\":\"%s\",\"targetUid\":%d,\"userId\":\"%s\"}",
            escapedKey,
            uid,
            steamId
        );
    }
    else
    {
        Format(
            body,
            sizeof(body),
            "{\"targetUid\":%d,\"userId\":\"%s\"}",
            uid,
            steamId
        );
    }

    DataPack context = new DataPack();
    context.WriteCell(ApiRequest_StatTrak);
    if (InvSim_HTTPRequest(
        InvSimHttp_Post,
        url,
        body,
        Api_OnResponse,
        context
    ) <= 0)
    {
        delete context;
    }
}

void Api_SendSprayConsume(const char[] steamId, int uid)
{
    if (g_ApiSuspended)
    {
        return;
    }

    char apiKey[256];
    g_CvarApiKey.GetString(apiKey, sizeof(apiKey));
    bool hasApiKey = apiKey[0] != '\0';
    if (!hasApiKey)
    {
        if (!g_CvarPublicApiSprayConsume.BoolValue
            || !Api_ConsumeSprayToken(steamId, uid))
        {
            return;
        }
    }

    char baseUrl[INVSIM_MAX_URL];
    char url[INVSIM_MAX_URL];
    ConVars_GetApiUrl(baseUrl, sizeof(baseUrl));
    Format(url, sizeof(url), "%s/api/consume-item-spray", baseUrl);

    char body[896];
    if (hasApiKey)
    {
        char escapedKey[512];
        Json_Escape(apiKey, escapedKey, sizeof(escapedKey));
        Format(
            body,
            sizeof(body),
            "{\"apiKey\":\"%s\",\"targetUid\":%d,\"userId\":\"%s\"}",
            escapedKey,
            uid,
            steamId
        );
    }
    else
    {
        Format(
            body,
            sizeof(body),
            "{\"targetUid\":%d,\"userId\":\"%s\"}",
            uid,
            steamId
        );
    }

    DataPack context = new DataPack();
    context.WriteCell(ApiRequest_Spray);
    if (InvSim_HTTPRequest(
        InvSimHttp_Post,
        url,
        body,
        Api_OnResponse,
        context
    ) <= 0)
    {
        delete context;
    }
}

public void Api_OnResponse(
    int requestId,
    bool transportSuccess,
    int statusCode,
    const char[] responseBody,
    const char[] error,
    any data
)
{
    DataPack context = view_as<DataPack>(data);
    context.Reset();
    ApiRequestKind kind = context.ReadCell();

    if (kind == ApiRequest_Fetch)
    {
        int client = GetClientFromSerial(context.ReadCell());
        int generation = context.ReadCell();
        int attempt = context.ReadCell();
        bool force = context.ReadCell();
        delete context;

        if (client == 0 || g_PlayerStates[client].fetchGeneration != generation)
        {
            return;
        }

        if (!transportSuccess || statusCode < 200 || statusCode >= 300)
        {
            Api_HandleFetchFailure(
                client,
                generation,
                attempt,
                force,
                error
            );
            return;
        }

        PlayerInventory inventory;
        char parseError[192];
        if (!Json_ParseEquipped(
            responseBody,
            inventory,
            parseError,
            sizeof(parseError)
        ))
        {
            Api_HandleFetchFailure(
                client,
                generation,
                attempt,
                force,
                parseError
            );
            return;
        }

        PlayerInventory oldInventory;
        bool oldInventoryFromFile;
        InventoryStore_Get(
            g_PlayerStates[client].steamId,
            oldInventory,
            oldInventoryFromFile
        );

        PlayerInventory previousCachedInventory;
        InventoryStore_SetCached(
            g_PlayerStates[client].steamId,
            inventory,
            previousCachedInventory
        );
        g_PlayerStates[client].fetching = false;
        g_PlayerStates[client].loadedFromFile = false;
        g_PlayerStates[client].wsUpdatedAt = GetTime();
        InventorySimulator_OnInventoryReady(
            client,
            force,
            true,
            oldInventory
        );
        if (previousCachedInventory != null)
        {
            previousCachedInventory.Destroy();
        }
        return;
    }

    if (kind == ApiRequest_SignIn)
    {
        int client = GetClientFromSerial(context.ReadCell());
        delete context;
        if (client == 0)
        {
            return;
        }

        g_PlayerStates[client].authenticating = false;

        char token[256];
        if (!transportSuccess
            || statusCode < 200
            || statusCode >= 300
            || !Json_ReadTopLevelString(
                responseBody,
                "token",
                token,
                sizeof(token)
            ))
        {
            InventorySimulator_PrintSimple(client, "LoginFailed");
            return;
        }

        char baseUrl[INVSIM_MAX_URL];
        char loginUrl[INVSIM_MAX_URL];
        ConVars_GetApiUrl(baseUrl, sizeof(baseUrl));
        Format(
            loginUrl,
            sizeof(loginUrl),
            "%s/api/sign-in/callback?token=%s",
            baseUrl,
            token
        );
        InventorySimulator_PrintString(client, "Login", loginUrl);
        return;
    }

    delete context;
    if (!transportSuccess || statusCode < 200 || statusCode >= 300)
    {
        if (statusCode == 401)
        {
            g_ApiSuspended = true;
        }
        LogError(
            "%s failed (HTTP %d): %s",
            kind == ApiRequest_Spray ? "Graffiti consume request" : "StatTrak update",
            statusCode,
            error
        );
    }
}

void Api_HandleFetchFailure(
    int client,
    int generation,
    int attempt,
    bool force,
    const char[] error
)
{
    if (attempt < INVSIM_HTTP_MAX_RETRIES)
    {
        DataPack retry;
        CreateDataTimer(
            0.1 * float(attempt),
            Api_OnFetchRetry,
            retry
        );
        retry.WriteCell(GetClientSerial(client));
        retry.WriteCell(generation);
        retry.WriteCell(attempt + 1);
        retry.WriteCell(force);
        return;
    }

    g_PlayerStates[client].fetching = false;
    LogError(
        "Inventory fetch for %s failed after %d attempts: %s",
        g_PlayerStates[client].steamId,
        attempt,
        error
    );
    InventorySimulator_OnInventoryReady(client, force, false);
}

public Action Api_OnFetchRetry(Handle timer, DataPack retry)
{
    retry.Reset();
    int client = GetClientFromSerial(retry.ReadCell());
    int generation = retry.ReadCell();
    int attempt = retry.ReadCell();
    bool force = retry.ReadCell();
    if (client != 0 && g_PlayerStates[client].fetchGeneration == generation)
    {
        Api_FetchInventory(client, force, attempt);
    }
    return Plugin_Stop;
}

void Json_Escape(const char[] input, char[] output, int outputLength)
{
    int written = 0;
    char escaped[8];
    for (int index = 0; input[index] != '\0'; index++)
    {
        int character = input[index];
        switch (character)
        {
            case '"', '\\':
            {
                escaped[0] = '\\';
                escaped[1] = character;
                escaped[2] = '\0';
            }
            case 8:
            {
                strcopy(escaped, sizeof(escaped), "\\b");
            }
            case 12:
            {
                strcopy(escaped, sizeof(escaped), "\\f");
            }
            case '\n':
            {
                strcopy(escaped, sizeof(escaped), "\\n");
            }
            case '\r':
            {
                strcopy(escaped, sizeof(escaped), "\\r");
            }
            case '\t':
            {
                strcopy(escaped, sizeof(escaped), "\\t");
            }
            default:
            {
                if (character < 0x20)
                {
                    Format(escaped, sizeof(escaped), "\\u%04x", character);
                }
                else
                {
                    escaped[0] = character;
                    escaped[1] = '\0';
                }
            }
        }

        int escapedLength = strlen(escaped);
        if (written + escapedLength >= outputLength)
        {
            break;
        }
        for (int offset = 0; offset < escapedLength; offset++)
        {
            output[written++] = escaped[offset];
        }
    }
    output[written] = '\0';
}
