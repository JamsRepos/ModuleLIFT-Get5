#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public void OnPluginStart()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (attacker < 1 || attacker > MaxClients || attacker == victim || inflictor < 1)
		return Plugin_Continue;
	
	if (GetClientTeam(attacker) == GetClientTeam(victim))
	{
		char inflictorClass[64];
		if (GetEdictClassname(inflictor, inflictorClass, sizeof(inflictorClass)))
		{
			if (StrEqual(inflictorClass, "planted_c4"))
				return Plugin_Continue;
			
			if (StrEqual(inflictorClass, "inferno"))
				return Plugin_Continue;
		}
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// if (attacker == 0 || attacker > MaxClients || victim == attacker || GetClientTeam(victim) != GetClientTeam(attacker))
// 	return Plugin_Continue;

// if ((damagetype & DMG_BURN) == DMG_BURN)
// 	return Plugin_Continue;
	
// if ((victim>=1) && (victim<=MaxClients) && (attacker>=1) && (attacker<=MaxClients) && (attacker==inflictor)) 
// 	SetEntPropFloat(victim, Prop_Send, "m_flVelocityModifier", 1.0); 
	
// damage = 0.0;
// return Plugin_Changed;