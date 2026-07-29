/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#if defined _inventorysimulator_bridge_included
    #endinput
#endif
#define _inventorysimulator_bridge_included

enum InvSimHttpMethod
{
    InvSimHttp_Get = 1,
    InvSimHttp_Post = 3
};

typeset InvSimHttpCallback
{
    function void (
        int requestId,
        bool transportSuccess,
        int statusCode,
        const char[] responseBody,
        const char[] error,
        any data
    );
}

native int InvSim_HTTPRequest(
    InvSimHttpMethod method,
    const char[] url,
    const char[] requestBody,
    InvSimHttpCallback callback,
    any data = 0
);

native Address InvSim_Allocate(int size);
native void InvSim_Free(Address memory);
native void InvSim_SetOrAddAttributeValueByName(
    Address attributeList,
    const char[] attribute,
    float value
);

public Extension __ext_inventorysimulator =
{
    name = "Inventory Simulator",
    file = "inventorysimulator.ext",
    autoload = 1,
    required = 1
};
