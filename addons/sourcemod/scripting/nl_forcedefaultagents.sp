#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <dhooks>

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

#define MAX_SKINS_COUNT 72
#define MAX_SKIN_LENGTH 41

int TSkins_Count;
int CTSkins_Count;

char TerrorSkin[MAX_SKINS_COUNT][MAX_SKIN_LENGTH];
char TerrorArms[MAX_SKINS_COUNT][MAX_SKIN_LENGTH];
char CTerrorSkin[MAX_SKINS_COUNT][MAX_SKIN_LENGTH];
char CTerrorArms[MAX_SKINS_COUNT][MAX_SKIN_LENGTH];

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
	char file[PLATFORM_MAX_PATH];
	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	BuildPath(Path_SM, file, sizeof(file), "configs/playermodels/%s.cfg", currentMap);
	PrepareConfig(file);
}

public void PrepareConfig(const char[] file)
{
	Handle kv = CreateKeyValues("Playermodels");
	FileToKeyValues(kv, file);

	if (KvJumpToKey(kv, "Terrorists"))
	{
		char section[MAX_SKINS_COUNT];
		char skin[MAX_SKINS_COUNT];
		char arms[MAX_SKINS_COUNT];

		KvGotoFirstSubKey(kv);

		do
		{
			KvGetSectionName(kv, section, sizeof(section));
			if (KvGetString(kv, "skin", skin, sizeof(skin) && KvGetString(kv, "arms", arms, sizeof(arms))))
			{
				strcopy(TerrorSkin[TSkins_Count], sizeof(TerrorSkin[]), skin);
				strcopy(TerrorArms[TSkins_Count], sizeof(TerrorArms[]), arms);
				TSkins_Count++
				PrecacheModel(skin, true);
				PrecacheModel(arms, true)
			} 
		}
		while (KvGotoNextKey(kv))
	}
	else SetFailState("Fatal error: Missing \"Terrorists\" section!");

	KvRewind(kv);

	if (KvJumpToKey(kv, "Counter-Terrorists"))
	{
		char section[72];
		char skin[72];
		char arms[72];
		char skin_id[3];

		KvGotoFirstSubKey(kv);

		do
		{
			KvGetSectionName(kv, section, sizeof(section));
			if (KvGetString(kv, "skin", skin, sizeof(skin) && KvGetString(kv, "arms", arms, sizeof(arms))))
			{
				strcopy(CTerrorSkin[CTSkins_Count], sizeof(CTerrorSkin[]), skin);
				strcopy(CTerrorArms[CTSkins_Count], sizeof(CTerrorArms[]), arms);
				CTSkins_Count++
				PrecacheModel(skin, true);
				PrecacheModel(arms, true)
			}
		}
		while (KvGotoNextKey(kv))
	}
	else SetFailState("Fatal error: Missing \"Counter-Terrorists\" section!");

	KvRewind(kv);
	CloseHandle(kv);
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client)) return;
	
	DHookEntity(h_SetModel, true, client);
}

public MRESReturn ReModel(int client, Handle hParams)
{
	CreateTimer(0.0, SetModel, client);
	
	return MRES_Ignored;
}

public Action SetModel(Handle timer, int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;
	
	int team = GetClientTeam(client);
	
	if (team < 2) return;
    
	
	char model[128];
	GetClientModel(client, model, sizeof(model));
	
	int trandom = GetRandomInt(0, TSkins_Count  - 1);
	int ctrandom = GetRandomInt(0, CTSkins_Count - 1);

	for (int i = 0; i < sizeof(Agents); i++)
	{
		if(StrEqual(model, Agents[i]))
		{
			if (team == CS_TEAM_CT)
            {
                SetEntityModel(client, CTerrorSkin[ctrandom]);
				SetEntPropString(client, Prop_Send, "m_szArmsModel", CTerrorArms[ctrandom]);
            }
			else 
            {
                SetEntityModel(client, TerrorSkin[trandom]);
				SetEntPropString(client, Prop_Send, "m_szArmsModel", TerrorArms[trandom]);

            }
			
			break;
		}			
	}
}
