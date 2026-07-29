/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

enum struct StickerItem
{
    int def;
    int slot;

    bool hasWear;
    float wear;

    void Reset()
    {
        this.def = 0;
        this.slot = 0;
        this.hasWear = false;
        this.wear = 0.0;
    }
}

enum struct InventoryItem
{
    bool hasDef;
    int def;

    char hash[INVSIM_MAX_HASH];

    bool hasMusicId;
    int musicId;

    char nametag[INVSIM_MAX_NAMETAG];

    bool hasPaint;
    int paint;

    bool hasSeed;
    int seed;

    bool hasStatTrak;
    int stattrak;


    bool hasUid;
    int uid;

    bool hasWear;
    float wear;

    ArrayList stickers;

    void Reset()
    {
        this.hasDef = false;
        this.def = 0;
        this.hash[0] = '\0';
        this.hasMusicId = false;
        this.musicId = 0;
        this.nametag[0] = '\0';
        this.hasPaint = false;
        this.paint = 0;
        this.hasSeed = false;
        this.seed = 0;
        this.hasStatTrak = false;
        this.stattrak = -1;
        this.hasUid = false;
        this.uid = 0;
        this.hasWear = false;
        this.wear = 0.0;
        this.stickers = null;
    }

    void Destroy()
    {
        delete this.stickers;
        this.stickers = null;
    }

    bool IsSameAs(const InventoryItem other)
    {
        return StrEqual(this.hash, other.hash);
    }
}

enum struct CachedItemView
{
    Address address;
    char hash[INVSIM_MAX_HASH];
    int stattrak;

    void Reset()
    {
        this.address = Address_Null;
        this.hash[0] = '\0';
        this.stattrak = -1;
    }
}

enum struct PlayerState
{
    bool fetching;
    bool authenticating;
    bool loadedFromFile;
    int fetchGeneration;
    int wsUpdatedAt;
    Address inventoryAddress;
    Address pendingActivation;
    bool activationScheduled;
    char steamId[32];

    void Reset()
    {
        this.fetching = false;
        this.authenticating = false;
        this.loadedFromFile = false;
        this.fetchGeneration = 0;
        this.wsUpdatedAt = 0;
        this.inventoryAddress = Address_Null;
        this.pendingActivation = Address_Null;
        this.activationScheduled = false;
        this.steamId[0] = '\0';
    }
}
