/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#define INVSIM_SPRAY_MATERIAL_DIRECTORY "materials/inventorysimulator/sprays"
#define INVSIM_SPRAY_MODEL_FORMAT "inventorysimulator/sprays/%d.vmt"

static StringMap g_SprayModelIndices;

void SprayModels_Initialize()
{
    delete g_SprayModelIndices;
    g_SprayModelIndices = new StringMap();

    DirectoryListing directory = OpenDirectory(
        INVSIM_SPRAY_MATERIAL_DIRECTORY,
        true
    );
    if (directory == null)
    {
        LogError(
            "Unable to open spray material directory: %s",
            INVSIM_SPRAY_MATERIAL_DIRECTORY
        );
        return;
    }

    char filename[PLATFORM_MAX_PATH];
    FileType type;
    while (directory.GetNext(filename, sizeof(filename), type))
    {
        if (type != FileType_File)
        {
            continue;
        }
        int length = strlen(filename);
        if (length <= 4 || !StrEqual(filename[length - 4], ".vmt", false))
        {
            continue;
        }
        filename[length - 4] = '\0';
        int definition = StringToInt(filename);
        if (definition <= 0)
        {
            continue;
        }

        char key[16];
        char model[96];
        char file[112];
        IntToString(definition, key, sizeof(key));
        Format(model, sizeof(model), INVSIM_SPRAY_MODEL_FORMAT, definition);
        Format(file, sizeof(file), "materials/%s", model);
        AddFileToDownloadsTable(file);
        g_SprayModelIndices.SetValue(key, PrecacheModel(model, true));
    }
    delete directory;
}

void SprayModels_Shutdown()
{
    delete g_SprayModelIndices;
    g_SprayModelIndices = null;
}

bool SprayModels_Get(
    int definition,
    char[] model,
    int modelLength,
    int &modelIndex
)
{
    if (g_SprayModelIndices == null)
    {
        return false;
    }
    char key[16];
    IntToString(definition, key, sizeof(key));
    if (!g_SprayModelIndices.GetValue(key, modelIndex))
    {
        return false;
    }
    Format(model, modelLength, INVSIM_SPRAY_MODEL_FORMAT, definition);
    return true;
}
