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

// default models for replace
char terroristModel[128] = "models/player/custom_player/legacy/tm_phoenix_varianta.mdl";
char ctModel[128] = "models/player/custom_player/legacy/ctm_sas_varianta.mdl";

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
	PrecacheModel(terroristModel);
	PrecacheModel(ctModel);
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
	
	for (int i = 0; i < sizeof(Agents); i++)
	{
		if(StrEqual(model, Agents[i]))
		{
			if (team == CS_TEAM_CT)
            {
                SetEntityModel(client, ctModel);
            }
			else 
            {
                SetEntityModel(client, terroristModel);
            }
			
			break;
		}			
	}
}
