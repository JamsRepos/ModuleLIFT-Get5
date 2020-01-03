#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <dhooks>


#define LEGACY_MODELS_PATH          "models/player/custom_player/legacy/"

// Valve Agents models list
char Agents[][] = {
"models/player/custom_player/legacy/tm_phoenix_varianth.mdl",
"models/player/custom_player/legacy/tm_phoenix_variantg.mdl",
"models/player/custom_player/legacy/tm_phoenix_variantf.mdl",
"models/player/custom_player/legacy/tm_leet_varianti.mdl",
"models/player/custom_player/legacy/tm_leet_variantg.mdl",
"models/player/custom_player/legacy/tm_leet_varianth.mdl",
"models/player/custom_player/legacy/tm_balkan_variantj.mdl",
"models/player/custom_player/legacy/tm_balkan_varianti.mdl",
"models/player/custom_player/legacy/tm_balkan_varianth.mdl",
"models/player/custom_player/legacy/tm_balkan_variantg.mdl",
"models/player/custom_player/legacy/tm_balkan_variantf.mdl",
"models/player/custom_player/legacy/ctm_st6_variantm.mdl",
"models/player/custom_player/legacy/ctm_st6_varianti.mdl",
"models/player/custom_player/legacy/ctm_st6_variantg.mdl",
"models/player/custom_player/legacy/ctm_sas_variantf.mdl",
"models/player/custom_player/legacy/ctm_fbi_varianth.mdl",
"models/player/custom_player/legacy/ctm_fbi_variantg.mdl",
"models/player/custom_player/legacy/ctm_fbi_variantb.mdl",
"models/player/custom_player/legacy/tm_leet_variantf.mdl",
"models/player/custom_player/legacy/ctm_fbi_variantf.mdl",
"models/player/custom_player/legacy/ctm_st6_variante.mdl",
"models/player/custom_player/legacy/ctm_st6_variantk.mdl"
};

char g_aMapArms[2][128];
ArrayList g_aMapTModels = null;
ArrayList g_aMapCTModels = null;

char g_sCurrentMap[PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
	name = "Default Agents",
	author = "PandahChan",
	description = "Why did valve not set this as a CVar grr..",
	version = "1.0",
	url = ""
};

Handle h_SetModel;

public void OnPluginStart()
{
	Handle h_GameConf;
	
	h_GameConf = LoadGameConfigFile("sdktools.games");
	if(h_GameConf == INVALID_HANDLE)
    {
        SetFailState("Gamedata file sdktools.games.txt is missing.");
    }

	int i_Offset = GameConfGetOffset(h_GameConf, "SetEntityModel");
	CloseHandle(h_GameConf);

	if(i_Offset == -1)
    {
        SetFailState("Gamedata is missing the \"SetEntityModel\" offset.");
    }
		
	h_SetModel = DHookCreate(i_Offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, ReModel);
	DHookAddParam(h_SetModel, HookParamType_CharPtr);
}

public void OnMapStart()
{
	GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
	GetMapConfig();
}

public void OnMapEnd()
{
	DestroyArrayList(g_aMapTModels);
	DestroyArrayList(g_aMapCTModels);

	strcopy(g_aMapArms[0], sizeof(g_aMapArms[]), "");
	strcopy(g_aMapArms[1], sizeof(g_aMapArms[]), "");
}

public void DestroyArrayList(ArrayList &array)
{
    if (array != null && array != INVALID_HANDLE) {
        delete array;
    }
}

public void GetMapConfig()
{
	if (!FileExists("gamemodes_server.txt"))
	{
		LogError("Something fucked up.");
		return;
	}

	bool inError = false;

	KeyValues kvCustom = new KeyValues("GameModes_Server.txt");
	kvCustom.ImportFromFile("gamemodes_server.txt");

	if (!kvCustom.JumpToKey("maps") || !kvCustom.JumpToKey(g_sCurrentMap))
		inError = true;

	if (!kvCustom.JumpToKey("original"))
		inError = true;

	if (inError)
	{
		_GetMapConfig_Done(false);
		return;
	}

	g_aMapTModels = new ArrayList(128);
	g_aMapCTModels = new ArrayList(128);

	kvCustom.GetString("t_arms", g_aMapArms[0], sizeof(g_aMapArms[]));
	GetKvKeysToArrayList(kvCustom, "t_models", g_aMapTModels);

	kvCustom.GetString("ct_arms", g_aMapArms[1], sizeof(g_aMapArms[]));
	GetKvKeysToArrayList(kvCustom, "ct_models", g_aMapCTModels);

	delete kvCustom;

	_GetMapConfig_Done(true);
}

public void GetKvKeysToArrayList(KeyValues &kv, const char[] key, ArrayList &dest)
{
    char entity[256];

    if (kv.JumpToKey(key)) {
            
        if (kv.GotoFirstSubKey(false)) {

            do {

                kv.GetSectionName(entity, sizeof(entity));
                dest.PushString(entity);

            } while (kv.GotoNextKey(false));

            kv.GoBack();
        }

        kv.GoBack();
    }
}

public void PrecacheModelsArrayList(ArrayList &models, const char[] modelsPath)
{
    char model[256];

    for (int i = 0; i < models.Length; i++) {

        models.GetString(i, model, sizeof(model));

        if (model[0] == '\0') {
            continue;
        }

        Format(model, sizeof(model), "%s%s.mdl", modelsPath, model);

        if (!IsModelPrecached(model)) {
            PrecacheModel(model);
        }
    }
}

public void _GetMapConfig_Done(bool map)
{
    PrecacheModels(map);
    PrecacheArms(map);
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client)) return;
	
	DHookEntity(h_SetModel, true, client);
}

public void PrecacheModels(bool map)
{
    char modelsPath[64];
    Format(modelsPath, sizeof(modelsPath), "%s", LEGACY_MODELS_PATH);

    if (map) {
        PrecacheModelsArrayList(g_aMapTModels, modelsPath);
        PrecacheModelsArrayList(g_aMapCTModels, modelsPath);
    }
}

public void PrecacheModelsArray(const char[][] models, int size)
{
    for (int i = 0; i < size; i++) {

        if (models[i][0] != '\0' && !IsModelPrecached(models[i])) {
            PrecacheModel(models[i]);
        }
    }
}

public void PrecacheArms(bool map)
{
    if (map)
    	PrecacheModelsArray(g_aMapArms, sizeof(g_aMapArms));
}

public MRESReturn ReModel(int client, Handle hParams)
{
	CreateTimer(0.0, SetModel, client);
	
	return MRES_Ignored;
}

char GetClientNewRandomModel(int client)
{
	char modelPath[64];
	char model[128];
	int team = (GetClientTeam(client) == 2) ? 0 : 1;

	Format(modelPath, sizeof(modelPath), "%s", LEGACY_MODELS_PATH);

	if (team == 0)
	{
		g_aMapTModels.GetString(GetRandomInt(0, g_aMapTModels.Length - 1), model, sizeof(model));
		Format(model, sizeof(model), "%s%s.mdl", modelPath, model);
	} else if (team == 1) {
		g_aMapCTModels.GetString(GetRandomInt(0, g_aMapCTModels.Length - 1), model, sizeof(model));
		Format(model, sizeof(model), "%s%s.mdl", modelPath, model);
	}
	
	return model;
}


public void GetKvKeysToKv(KeyValues &kv, const char[] key, KeyValues &kvDest, const char[] destKey)
{
    char entity[256];

    kvDest.JumpToKey(destKey, true);

    if (kv.JumpToKey(key)) {
            
        if (kv.GotoFirstSubKey(false)) {

            do {

                kv.GetSectionName(entity, sizeof(entity));
                kvDest.SetString(entity, NULL_STRING);

            } while (kv.GotoNextKey(false));

            kv.GoBack();
        }

        kv.GoBack();
    }

    kvDest.GoBack();
}

public Action SetModel(Handle timer, int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;
	
	int team = GetClientTeam(client);
	
	if (team < 2) return;
    
	
	char model[128];
	GetClientModel(client, model, sizeof(model));
	
	for (int i = 0; i < sizeof(Agents); i++)
	{
		if(StrEqual(model, Agents[i]))
		{
			if (team == CS_TEAM_CT)
            {
                SetEntityModel(client, GetClientNewRandomModel(client));
            }
			else 
            {
                SetEntityModel(client, GetClientNewRandomModel(client));
            }
			
			break;
		}			
	}
}
