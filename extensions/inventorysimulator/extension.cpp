/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#include "extension.h"
#include "attribute_list.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

namespace
{
constexpr uint32_t kInvalidHTTPRequest = 0;
constexpr uint64_t kInvalidAPICall = 0;
constexpr int kHTTPRequestCompletedCallback = 2101;
constexpr uint32_t kMaximumResponseBytes = 262144;
constexpr uint32_t kMaximumRequestBodyBytes = 65536;
constexpr uint32_t kMaximumAllocationBytes = 4096;
constexpr int kMaximumPendingRequests = 128;
constexpr int kMaximumAllocations = 16384;

#if defined(_WIN32)
constexpr const char *kSteamLibraryPath = "../bin/steam_api.dll";
constexpr const char *kSteamLibraryName = "steam_api.dll";
#else
constexpr const char *kSteamLibraryPath = "../bin/libsteam_api.so";
constexpr const char *kSteamLibraryName = "libsteam_api.so";
#endif

using SteamInterface = void;
using HTTPRequestHandle = uint32_t;
using SteamAPICall = uint64_t;

using GetSteamInterfaceFn = SteamInterface *(*)();
using CreateHTTPRequestFn = HTTPRequestHandle (*)(
    SteamInterface *,
    int,
    const char *
);
using SetHTTPRequestNetworkTimeoutFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle,
    uint32_t
);
using SetHTTPRequestHeaderFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle,
    const char *,
    const char *
);
using SetHTTPRequestRawBodyFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle,
    const char *,
    uint8_t *,
    uint32_t
);
using SetHTTPRequestUserAgentFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle,
    const char *
);
using SetHTTPRequestAbsoluteTimeoutFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle,
    uint32_t
);
using SendHTTPRequestFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle,
    SteamAPICall *
);
using GetHTTPResponseBodySizeFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle,
    uint32_t *
);
using GetHTTPResponseBodyDataFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle,
    uint8_t *,
    uint32_t
);
using ReleaseHTTPRequestFn = bool (*)(
    SteamInterface *,
    HTTPRequestHandle
);
using IsAPICallCompletedFn = bool (*)(
    SteamInterface *,
    SteamAPICall,
    bool *
);
using GetAPICallResultFn = bool (*)(
    SteamInterface *,
    SteamAPICall,
    void *,
    int,
    int,
    bool *
);

#if defined(_WIN32)
#pragma pack(push, 8)
#else
#pragma pack(push, 4)
#endif

struct HTTPRequestCompleted
{
    HTTPRequestHandle request;
    uint64_t context;
    bool requestSuccessful;
    int statusCode;
    uint32_t bodySize;
};

#pragma pack(pop)

#if defined(_WIN32)
static_assert(
    sizeof(HTTPRequestCompleted) == 32,
    "Unexpected Windows Steam HTTP callback layout"
);
#else
static_assert(
    sizeof(HTTPRequestCompleted) == 24,
    "Unexpected Linux Steam HTTP callback layout"
);
#endif

struct PendingRequest
{
    bool occupied;
    int requestId;
    HTTPRequestHandle request;
    SteamAPICall call;
    SourceMod::IPlugin *owner;
    SourcePawn::IPluginFunction *callback;
    cell_t data;
};

struct OwnedAllocation
{
    void *memory;
    SourceMod::IPlugin *owner;
};

SourceMod::ILibrary *g_SteamLibrary = nullptr;
SteamInterface *g_SteamHTTP = nullptr;
SteamInterface *g_SteamUtils = nullptr;

GetSteamInterfaceFn g_GetSteamHTTP = nullptr;
GetSteamInterfaceFn g_GetSteamUtils = nullptr;
CreateHTTPRequestFn g_CreateHTTPRequest = nullptr;
SetHTTPRequestNetworkTimeoutFn g_SetNetworkTimeout = nullptr;
SetHTTPRequestHeaderFn g_SetHeader = nullptr;
SetHTTPRequestRawBodyFn g_SetRawBody = nullptr;
SetHTTPRequestUserAgentFn g_SetUserAgent = nullptr;
SetHTTPRequestAbsoluteTimeoutFn g_SetAbsoluteTimeout = nullptr;
SendHTTPRequestFn g_SendHTTPRequest = nullptr;
GetHTTPResponseBodySizeFn g_GetBodySize = nullptr;
GetHTTPResponseBodyDataFn g_GetBodyData = nullptr;
ReleaseHTTPRequestFn g_ReleaseHTTPRequest = nullptr;
IsAPICallCompletedFn g_IsAPICallCompleted = nullptr;
GetAPICallResultFn g_GetAPICallResult = nullptr;

PendingRequest g_Requests[kMaximumPendingRequests];
OwnedAllocation g_Allocations[kMaximumAllocations];
int g_NextRequestId = 1;
bool g_ShuttingDown = false;

void ClearRequest(PendingRequest &request)
{
    request.occupied = false;
    request.requestId = 0;
    request.request = kInvalidHTTPRequest;
    request.call = kInvalidAPICall;
    request.owner = nullptr;
    request.callback = nullptr;
    request.data = 0;
}

void ReleaseRequest(PendingRequest &request)
{
    if (request.occupied
        && request.request != kInvalidHTTPRequest
        && g_SteamHTTP != nullptr
        && g_ReleaseHTTPRequest != nullptr)
    {
        g_ReleaseHTTPRequest(g_SteamHTTP, request.request);
    }
    ClearRequest(request);
}

void ReleaseRequestsForPlugin(SourceMod::IPlugin *plugin)
{
    for (int index = 0; index < kMaximumPendingRequests; index++)
    {
        if (g_Requests[index].occupied
            && (plugin == nullptr || g_Requests[index].owner == plugin))
        {
            ReleaseRequest(g_Requests[index]);
        }
    }
}

void ReleaseAllocationsForPlugin(SourceMod::IPlugin *plugin)
{
    for (int index = 0; index < kMaximumAllocations; index++)
    {
        if (g_Allocations[index].memory != nullptr
            && (plugin == nullptr || g_Allocations[index].owner == plugin))
        {
            free(g_Allocations[index].memory);
            g_Allocations[index].memory = nullptr;
            g_Allocations[index].owner = nullptr;
        }
    }
}

bool EnsureSteamInterfaces()
{
    if (g_SteamHTTP == nullptr && g_GetSteamHTTP != nullptr)
    {
        g_SteamHTTP = g_GetSteamHTTP();
    }
    if (g_SteamUtils == nullptr && g_GetSteamUtils != nullptr)
    {
        g_SteamUtils = g_GetSteamUtils();
    }
    return g_SteamHTTP != nullptr && g_SteamUtils != nullptr;
}

SourceMod::IPlugin *FindOwningPlugin(
    SourcePawn::IPluginContext *context
)
{
#if SMINTERFACE_EXTENSIONAPI_VERSION >= 9
    return plsys->FindPluginByContext(context);
#else
    return plsys->FindPluginByContext(context->GetContext());
#endif
}

PendingRequest *FindFreeRequest()
{
    for (int index = 0; index < kMaximumPendingRequests; index++)
    {
        if (!g_Requests[index].occupied)
        {
            return &g_Requests[index];
        }
    }
    return nullptr;
}

int NextRequestId()
{
    if (g_NextRequestId <= 0)
    {
        g_NextRequestId = 1;
    }
    return g_NextRequestId++;
}

void InvokeRequestCallback(
    PendingRequest &request,
    bool transportSuccess,
    int statusCode,
    const char *body,
    const char *error
)
{
    SourcePawn::IPluginFunction *callback = request.callback;
    int requestId = request.requestId;
    cell_t data = request.data;

    ReleaseRequest(request);

    if (callback == nullptr || !callback->IsRunnable())
    {
        return;
    }

    callback->PushCell(requestId);
    callback->PushCell(transportSuccess ? 1 : 0);
    callback->PushCell(statusCode);
    callback->PushString(body != nullptr ? body : "");
    callback->PushString(error != nullptr ? error : "");
    callback->PushCell(data);

    int result = callback->Execute(nullptr);
    if (result != SP_ERROR_NONE)
    {
        smutils->LogError(
            myself,
            "HTTP callback for request %d failed with SourcePawn error %d",
            requestId,
            result
        );
    }
}

void CompleteRequest(PendingRequest &request)
{
    bool callFailed = false;
    if (!g_IsAPICallCompleted(g_SteamUtils, request.call, &callFailed))
    {
        return;
    }

    HTTPRequestCompleted completed = {};
    bool resultFailed = callFailed;
    bool gotResult = !callFailed && g_GetAPICallResult(
        g_SteamUtils,
        request.call,
        &completed,
        sizeof(completed),
        kHTTPRequestCompletedCallback,
        &resultFailed
    );

    if (!gotResult || resultFailed)
    {
        InvokeRequestCallback(
            request,
            false,
            0,
            "",
            "Steam API call failed"
        );
        return;
    }

    int statusCode = completed.statusCode;
    if (!completed.requestSuccessful)
    {
        InvokeRequestCallback(
            request,
            false,
            statusCode,
            "",
            "Steam HTTP transport failed"
        );
        return;
    }

    uint32_t bodySize = 0;
    if (!g_GetBodySize(g_SteamHTTP, request.request, &bodySize))
    {
        InvokeRequestCallback(
            request,
            false,
            statusCode,
            "",
            "Unable to read HTTP response size"
        );
        return;
    }
    if (bodySize > kMaximumResponseBytes)
    {
        InvokeRequestCallback(
            request,
            false,
            statusCode,
            "",
            "HTTP response exceeds 256 KiB"
        );
        return;
    }

    char *body = static_cast<char *>(malloc(bodySize + 1));
    if (body == nullptr)
    {
        InvokeRequestCallback(
            request,
            false,
            statusCode,
            "",
            "Unable to allocate HTTP response buffer"
        );
        return;
    }

    bool bodyRead = bodySize == 0 || g_GetBodyData(
        g_SteamHTTP,
        request.request,
        reinterpret_cast<uint8_t *>(body),
        bodySize
    );
    body[bodySize] = '\0';

    if (!bodyRead)
    {
        free(body);
        InvokeRequestCallback(
            request,
            false,
            statusCode,
            "",
            "Unable to read HTTP response body"
        );
        return;
    }

    InvokeRequestCallback(request, true, statusCode, body, "");
    free(body);
}

void OnGameFrame(bool simulating)
{
    (void)simulating;
    if (g_ShuttingDown || !EnsureSteamInterfaces())
    {
        return;
    }

    for (int index = 0; index < kMaximumPendingRequests; index++)
    {
        if (g_Requests[index].occupied)
        {
            CompleteRequest(g_Requests[index]);
        }
    }
}

cell_t Native_HTTPRequest(
    SourcePawn::IPluginContext *context,
    const cell_t *params
)
{
    if (g_ShuttingDown)
    {
        return 0;
    }
    if (params[0] != 5)
    {
        return context->ThrowNativeError(
            "InvSim_HTTPRequest expects 5 parameters"
        );
    }

    int method = params[1];
    if (method != 1 && method != 3)
    {
        return context->ThrowNativeError(
            "Unsupported HTTP method %d",
            method
        );
    }

    char *url = nullptr;
    char *requestBody = nullptr;
    if (context->LocalToString(params[2], &url) != SP_ERROR_NONE
        || context->LocalToString(params[3], &requestBody) != SP_ERROR_NONE)
    {
        return 0;
    }
    if (url == nullptr
        || (strncmp(url, "https://", 8) != 0
            && strncmp(url, "http://", 7) != 0))
    {
        return context->ThrowNativeError(
            "InvSim_HTTPRequest requires an absolute HTTP(S) URL"
        );
    }

    size_t requestBodyLength = strlen(requestBody);
    if (requestBodyLength > kMaximumRequestBodyBytes)
    {
        return context->ThrowNativeError(
            "HTTP request body exceeds 64 KiB"
        );
    }

    SourcePawn::IPluginFunction *callback =
        context->GetFunctionById(params[4]);
    if (callback == nullptr)
    {
        return context->ThrowNativeError("Invalid HTTP callback");
    }

    SourceMod::IPlugin *owner = FindOwningPlugin(context);
    PendingRequest *pending = FindFreeRequest();
    if (owner == nullptr || pending == nullptr || !EnsureSteamInterfaces())
    {
        if (pending == nullptr)
        {
            smutils->LogError(
                myself,
                "Pending HTTP request limit (%d) reached",
                kMaximumPendingRequests
            );
        }
        else if (!EnsureSteamInterfaces())
        {
            smutils->LogError(
                myself,
                "Steam GameServer HTTP is not initialized"
            );
        }
        return 0;
    }

    HTTPRequestHandle request = g_CreateHTTPRequest(
        g_SteamHTTP,
        method,
        url
    );
    if (request == kInvalidHTTPRequest)
    {
        return 0;
    }

    bool configured = g_SetNetworkTimeout(g_SteamHTTP, request, 15)
        && g_SetAbsoluteTimeout(g_SteamHTTP, request, 30000)
        && g_SetHeader(
            g_SteamHTTP,
            request,
            "Accept",
            "application/json"
        )
        && g_SetUserAgent(
            g_SteamHTTP,
            request,
            "InventorySimulator/0.1"
        );

    if (configured && method == 3)
    {
        configured = g_SetRawBody(
            g_SteamHTTP,
            request,
            "application/json; charset=utf-8",
            reinterpret_cast<uint8_t *>(requestBody),
            static_cast<uint32_t>(requestBodyLength)
        );
    }

    SteamAPICall call = kInvalidAPICall;
    bool sent = configured
        && g_SendHTTPRequest(g_SteamHTTP, request, &call)
        && call != kInvalidAPICall;
    if (!sent)
    {
        g_ReleaseHTTPRequest(g_SteamHTTP, request);
        return 0;
    }

    pending->occupied = true;
    pending->requestId = NextRequestId();
    pending->request = request;
    pending->call = call;
    pending->owner = owner;
    pending->callback = callback;
    pending->data = params[5];
    return pending->requestId;
}

cell_t Native_Allocate(
    SourcePawn::IPluginContext *context,
    const cell_t *params
)
{
    if (g_ShuttingDown)
    {
        return context->ThrowNativeError(
            "Inventory Simulator bridge is shutting down"
        );
    }
    if (params[0] != 1)
    {
        return context->ThrowNativeError("InvSim_Allocate expects 1 parameter");
    }
    if (params[1] <= 0
        || static_cast<uint32_t>(params[1]) > kMaximumAllocationBytes)
    {
        return context->ThrowNativeError(
            "Allocation size %d is outside the supported range",
            params[1]
        );
    }

    int freeSlot = -1;
    for (int index = 0; index < kMaximumAllocations; index++)
    {
        if (g_Allocations[index].memory == nullptr)
        {
            freeSlot = index;
            break;
        }
    }
    if (freeSlot == -1)
    {
        return context->ThrowNativeError(
            "Native allocation limit (%d) reached",
            kMaximumAllocations
        );
    }

    SourceMod::IPlugin *owner = FindOwningPlugin(context);
    void *memory = owner != nullptr
        ? calloc(1, static_cast<size_t>(params[1]))
        : nullptr;
    if (memory == nullptr)
    {
        return context->ThrowNativeError("Unable to allocate native memory");
    }

    g_Allocations[freeSlot].memory = memory;
    g_Allocations[freeSlot].owner = owner;
    return static_cast<cell_t>(reinterpret_cast<uintptr_t>(memory));
}

cell_t Native_Free(
    SourcePawn::IPluginContext *context,
    const cell_t *params
)
{
    if (params[0] != 1)
    {
        return context->ThrowNativeError("InvSim_Free expects 1 parameter");
    }

    void *memory = reinterpret_cast<void *>(
        static_cast<uintptr_t>(params[1])
    );
    if (memory == nullptr)
    {
        return 0;
    }

    SourceMod::IPlugin *owner = FindOwningPlugin(context);
    for (int index = 0; index < kMaximumAllocations; index++)
    {
        if (g_Allocations[index].memory == memory)
        {
            if (g_Allocations[index].owner != owner)
            {
                return context->ThrowNativeError(
                    "Cannot free memory owned by another plugin"
                );
            }

            free(memory);
            g_Allocations[index].memory = nullptr;
            g_Allocations[index].owner = nullptr;
            return 0;
        }
    }

    return context->ThrowNativeError(
        "Unknown or already-freed native address 0x%x",
        params[1]
    );
}

sp_nativeinfo_t g_Natives[] =
{
    {"InvSim_HTTPRequest", Native_HTTPRequest},
    {"InvSim_Allocate", Native_Allocate},
    {"InvSim_Free", Native_Free},
    {
        "InvSim_SetOrAddAttributeValueByName",
        Native_SetOrAddAttributeValueByName
    },
    {nullptr, nullptr}
};

bool ResolveSteamSymbols(char *error, size_t maxlength)
{
#define RESOLVE_STEAM_SYMBOL(variable, type, symbol)                         \
    variable = reinterpret_cast<type>(                                      \
        g_SteamLibrary->GetSymbolAddress(symbol)                             \
    );                                                                       \
    if (variable == nullptr)                                                 \
    {                                                                        \
        smutils->Format(error, maxlength, "Missing Steam API symbol %s", symbol); \
        return false;                                                        \
    }

    RESOLVE_STEAM_SYMBOL(
        g_GetSteamHTTP,
        GetSteamInterfaceFn,
        "SteamAPI_SteamGameServerHTTP_v003"
    );
    RESOLVE_STEAM_SYMBOL(
        g_GetSteamUtils,
        GetSteamInterfaceFn,
        "SteamAPI_SteamGameServerUtils_v010"
    );
    RESOLVE_STEAM_SYMBOL(
        g_CreateHTTPRequest,
        CreateHTTPRequestFn,
        "SteamAPI_ISteamHTTP_CreateHTTPRequest"
    );
    RESOLVE_STEAM_SYMBOL(
        g_SetNetworkTimeout,
        SetHTTPRequestNetworkTimeoutFn,
        "SteamAPI_ISteamHTTP_SetHTTPRequestNetworkActivityTimeout"
    );
    RESOLVE_STEAM_SYMBOL(
        g_SetHeader,
        SetHTTPRequestHeaderFn,
        "SteamAPI_ISteamHTTP_SetHTTPRequestHeaderValue"
    );
    RESOLVE_STEAM_SYMBOL(
        g_SetRawBody,
        SetHTTPRequestRawBodyFn,
        "SteamAPI_ISteamHTTP_SetHTTPRequestRawPostBody"
    );
    RESOLVE_STEAM_SYMBOL(
        g_SetUserAgent,
        SetHTTPRequestUserAgentFn,
        "SteamAPI_ISteamHTTP_SetHTTPRequestUserAgentInfo"
    );
    RESOLVE_STEAM_SYMBOL(
        g_SetAbsoluteTimeout,
        SetHTTPRequestAbsoluteTimeoutFn,
        "SteamAPI_ISteamHTTP_SetHTTPRequestAbsoluteTimeoutMS"
    );
    RESOLVE_STEAM_SYMBOL(
        g_SendHTTPRequest,
        SendHTTPRequestFn,
        "SteamAPI_ISteamHTTP_SendHTTPRequest"
    );
    RESOLVE_STEAM_SYMBOL(
        g_GetBodySize,
        GetHTTPResponseBodySizeFn,
        "SteamAPI_ISteamHTTP_GetHTTPResponseBodySize"
    );
    RESOLVE_STEAM_SYMBOL(
        g_GetBodyData,
        GetHTTPResponseBodyDataFn,
        "SteamAPI_ISteamHTTP_GetHTTPResponseBodyData"
    );
    RESOLVE_STEAM_SYMBOL(
        g_ReleaseHTTPRequest,
        ReleaseHTTPRequestFn,
        "SteamAPI_ISteamHTTP_ReleaseHTTPRequest"
    );
    RESOLVE_STEAM_SYMBOL(
        g_IsAPICallCompleted,
        IsAPICallCompletedFn,
        "SteamAPI_ISteamUtils_IsAPICallCompleted"
    );
    RESOLVE_STEAM_SYMBOL(
        g_GetAPICallResult,
        GetAPICallResultFn,
        "SteamAPI_ISteamUtils_GetAPICallResult"
    );

#undef RESOLVE_STEAM_SYMBOL
    return true;
}
}

InventorySimulatorExtension g_InventorySimulatorExtension;
SMEXT_LINK(&g_InventorySimulatorExtension);

bool InventorySimulatorExtension::SDK_OnLoad(
    char *error,
    size_t maxlength,
    bool late
)
{
    (void)late;
    memset(g_Requests, 0, sizeof(g_Requests));
    memset(g_Allocations, 0, sizeof(g_Allocations));
    g_ShuttingDown = false;

    if (!AttributeList_OnLoad(error, maxlength))
    {
        return false;
    }

    char steamLibraryPath[PLATFORM_MAX_PATH];
    smutils->BuildPath(
        SourceMod::Path_Game,
        steamLibraryPath,
        sizeof(steamLibraryPath),
        kSteamLibraryPath
    );
    g_SteamLibrary = libsys->OpenLibrary(
        steamLibraryPath,
        error,
        maxlength
    );
    if (g_SteamLibrary == nullptr)
    {
        g_SteamLibrary = libsys->OpenLibrary(
            kSteamLibraryName,
            error,
            maxlength
        );
        if (g_SteamLibrary == nullptr)
        {
            AttributeList_OnUnload();
            return false;
        }
    }
    if (!ResolveSteamSymbols(error, maxlength))
    {
        g_SteamLibrary->CloseLibrary();
        g_SteamLibrary = nullptr;
        AttributeList_OnUnload();
        return false;
    }

    sharesys->AddNatives(myself, g_Natives);
    sharesys->RegisterLibrary(myself, "inventorysimulator");
    plsys->AddPluginsListener(this);
    smutils->AddGameFrameHook(OnGameFrame);
    return true;
}

void InventorySimulatorExtension::SDK_OnUnload()
{
    g_ShuttingDown = true;
    smutils->RemoveGameFrameHook(OnGameFrame);
    plsys->RemovePluginsListener(this);
    ReleaseRequestsForPlugin(nullptr);
    ReleaseAllocationsForPlugin(nullptr);
    AttributeList_OnUnload();

    g_SteamHTTP = nullptr;
    g_SteamUtils = nullptr;
    if (g_SteamLibrary != nullptr)
    {
        g_SteamLibrary->CloseLibrary();
        g_SteamLibrary = nullptr;
    }
}

void InventorySimulatorExtension::OnPluginWillUnload(
    SourceMod::IPlugin *plugin
)
{
    ReleaseRequestsForPlugin(plugin);
}

void InventorySimulatorExtension::OnPluginUnloaded(
    SourceMod::IPlugin *plugin
)
{
    ReleaseRequestsForPlugin(plugin);
    ReleaseAllocationsForPlugin(plugin);
}
