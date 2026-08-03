/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Ian Lucas. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#define INVENTORY_KEY_ITEMS "__items"
#define INVENTORY_KEY_AGENTS "__agents"
#define INVENTORY_KEY_CT_WEAPONS "__ct_weapons"
#define INVENTORY_KEY_GLOVES "__gloves"
#define INVENTORY_KEY_KNIVES "__knives"
#define INVENTORY_KEY_T_WEAPONS "__t_weapons"
#define INVENTORY_KEY_COLLECTIBLE "__collectible"
#define INVENTORY_KEY_MUSIC_KIT "__music_kit"
#define INVENTORY_KEY_GRAFFITI "__graffiti"

methodmap PlayerInventory < StringMap
{
    public PlayerInventory()
    {
        StringMap inventory = new StringMap();
        inventory.SetValue(INVENTORY_KEY_ITEMS, new ArrayList(sizeof(InventoryItem)));
        inventory.SetValue(INVENTORY_KEY_AGENTS, new StringMap());
        inventory.SetValue(INVENTORY_KEY_CT_WEAPONS, new StringMap());
        inventory.SetValue(INVENTORY_KEY_GLOVES, new StringMap());
        inventory.SetValue(INVENTORY_KEY_KNIVES, new StringMap());
        inventory.SetValue(INVENTORY_KEY_T_WEAPONS, new StringMap());
        inventory.SetValue(INVENTORY_KEY_COLLECTIBLE, -1);
        inventory.SetValue(INVENTORY_KEY_MUSIC_KIT, -1);
        inventory.SetValue(INVENTORY_KEY_GRAFFITI, -1);
        return view_as<PlayerInventory>(inventory);
    }

    public void Destroy()
    {
        if (this == null)
        {
            return;
        }

        ArrayList items = this.Items();
        InventoryItem item;
        for (int index = 0; index < items.Length; index++)
        {
            items.GetArray(index, item, sizeof(item));
            item.Destroy();
        }

        delete items;
        delete this.Map(INVENTORY_KEY_AGENTS);
        delete this.Map(INVENTORY_KEY_CT_WEAPONS);
        delete this.Map(INVENTORY_KEY_GLOVES);
        delete this.Map(INVENTORY_KEY_KNIVES);
        delete this.Map(INVENTORY_KEY_T_WEAPONS);
        delete view_as<StringMap>(this);
    }

    public int AddItem(InventoryItem item)
    {
        ArrayList items = this.Items();
        int index = items.Length;
        items.PushArray(item, sizeof(item));
        return index;
    }

    public void SetMappedItem(
        InventoryItemKind kind,
        int key,
        InventoryItem item
    )
    {
        int index = this.AddItem(item);
        char mapKey[16];
        IntToString(key, mapKey, sizeof(mapKey));
        this.MapForKind(kind).SetValue(mapKey, index);
    }

    public void SetWeapon(int team, int def, InventoryItem item)
    {
        int index = this.AddItem(item);
        char mapKey[16];
        IntToString(def, mapKey, sizeof(mapKey));
        StringMap weapons = team == INVSIM_TEAM_T
            ? this.Map(INVENTORY_KEY_T_WEAPONS)
            : this.Map(INVENTORY_KEY_CT_WEAPONS);
        weapons.SetValue(mapKey, index);
    }

    public void SetSingleItem(InventoryItemKind kind, InventoryItem item)
    {
        int index = this.AddItem(item);
        switch (kind)
        {
            case InventoryItem_Collectible:
            {
                this.SetValue(INVENTORY_KEY_COLLECTIBLE, index);
            }
            case InventoryItem_MusicKit:
            {
                this.SetValue(INVENTORY_KEY_MUSIC_KIT, index);
            }
            case InventoryItem_Graffiti:
            {
                this.SetValue(INVENTORY_KEY_GRAFFITI, index);
            }
        }
    }

    public bool GetItemAt(int index, InventoryItem item)
    {
        ArrayList items = this.Items();
        if (index < 0 || index >= items.Length)
        {
            return false;
        }

        items.GetArray(index, item, sizeof(item));
        return true;
    }

    public void SaveItemAt(int index, InventoryItem item)
    {
        this.Items().SetArray(index, item, sizeof(item));
    }

    public bool GetMappedItem(
        InventoryItemKind kind,
        int key,
        InventoryItem item,
        int &index
    )
    {
        char mapKey[16];
        IntToString(key, mapKey, sizeof(mapKey));
        if (!this.MapForKind(kind).GetValue(mapKey, index))
        {
            index = -1;
            return false;
        }

        return this.GetItemAt(index, item);
    }

    public bool GetSingleItem(
        InventoryItemKind kind,
        InventoryItem item,
        int &index
    )
    {
        switch (kind)
        {
            case InventoryItem_Collectible:
            {
                this.GetValue(INVENTORY_KEY_COLLECTIBLE, index);
            }
            case InventoryItem_MusicKit:
            {
                this.GetValue(INVENTORY_KEY_MUSIC_KIT, index);
            }
            case InventoryItem_Graffiti:
            {
                this.GetValue(INVENTORY_KEY_GRAFFITI, index);
            }
            default:
            {
                index = -1;
            }
        }
        return this.GetItemAt(index, item);
    }

    public void ClearGraffiti()
    {
        this.SetValue(INVENTORY_KEY_GRAFFITI, -1);
    }

    public bool GetKnife(
        int team,
        bool fallback,
        InventoryItem item,
        int &index
    )
    {
        if (this.GetMappedItem(InventoryItem_Knife, team, item, index))
        {
            return true;
        }
        return fallback && this.GetMappedItem(
            InventoryItem_Knife,
            InventorySimulator_ToggleTeam(team),
            item,
            index
        );
    }

    public bool GetGloves(
        int team,
        bool fallback,
        InventoryItem item,
        int &index
    )
    {
        if (this.GetMappedItem(InventoryItem_Glove, team, item, index))
        {
            return true;
        }
        return fallback && this.GetMappedItem(
            InventoryItem_Glove,
            InventorySimulator_ToggleTeam(team),
            item,
            index
        );
    }

    public bool GetWeapon(
        int team,
        int def,
        bool fallback,
        InventoryItem item,
        int &index
    )
    {
        if (this.GetWeaponForTeam(team, def, item, index))
        {
            return true;
        }
        return fallback && this.GetWeaponForTeam(
            InventorySimulator_ToggleTeam(team),
            def,
            item,
            index
        );
    }

    public bool GetItemForSlot(
        int team,
        int slot,
        int def,
        bool fallback,
        int minModels,
        InventoryItem item,
        int &index
    )
    {
        if (slot >= view_as<int>(Loadout_Melee)
            && slot <= view_as<int>(Loadout_LastEquipment))
        {
            if (slot == view_as<int>(Loadout_Melee))
            {
                return this.GetKnife(team, fallback, item, index);
            }
            return this.GetWeapon(team, def, fallback, item, index);
        }

        if (slot == view_as<int>(Loadout_ClothingCustomPlayer)
            || slot == view_as<int>(Loadout_ClothingAppearance))
        {
            if (minModels == INVSIM_MINMODELS_MAP)
            {
                return false;
            }
            if (minModels >= INVSIM_MINMODELS_CLASSIC)
            {
                item.Reset();
                item.hasDef = true;
                item.def = team == INVSIM_TEAM_T
                    ? INVSIM_AGENT_PHOENIX
                    : INVSIM_AGENT_SAS;
                Format(item.hash, sizeof(item.hash), "minmodel:%d", item.def);
                index = -1;
                return true;
            }
            return this.GetMappedItem(InventoryItem_Agent, team, item, index);
        }

        if (slot == view_as<int>(Loadout_ClothingHands))
        {
            return this.GetGloves(team, fallback, item, index);
        }
        if (slot == view_as<int>(Loadout_Flair0))
        {
            return this.GetSingleItem(InventoryItem_Collectible, item, index);
        }
        if (slot == view_as<int>(Loadout_MusicKit))
        {
            return this.GetSingleItem(InventoryItem_MusicKit, item, index);
        }
        return false;
    }

    public ArrayList Items()
    {
        ArrayList items;
        this.GetValue(INVENTORY_KEY_ITEMS, items);
        return items;
    }

    public StringMap Map(const char[] key)
    {
        StringMap map;
        this.GetValue(key, map);
        return map;
    }

    public StringMap MapForKind(InventoryItemKind kind)
    {
        switch (kind)
        {
            case InventoryItem_Agent:
            {
                return this.Map(INVENTORY_KEY_AGENTS);
            }
            case InventoryItem_Glove:
            {
                return this.Map(INVENTORY_KEY_GLOVES);
            }
            case InventoryItem_Knife:
            {
                return this.Map(INVENTORY_KEY_KNIVES);
            }
        }
        return this.Map(INVENTORY_KEY_CT_WEAPONS);
    }

    public bool GetWeaponForTeam(
        int team,
        int def,
        InventoryItem item,
        int &index
    )
    {
        char mapKey[16];
        IntToString(def, mapKey, sizeof(mapKey));
        StringMap weapons = team == INVSIM_TEAM_T
            ? this.Map(INVENTORY_KEY_T_WEAPONS)
            : this.Map(INVENTORY_KEY_CT_WEAPONS);
        if (!weapons.GetValue(mapKey, index))
        {
            index = -1;
            return false;
        }
        return this.GetItemAt(index, item);
    }
}
