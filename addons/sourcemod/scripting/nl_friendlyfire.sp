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
	if (attacker == 0 || attacker > MaxClients || victim == attacker || GetClientTeam(victim) != GetClientTeam(attacker))
		return Plugin_Continue;

	if ((damagetype & DMG_BURN) == DMG_BURN)
		return Plugin_Continue;
	
	if ((client>=1) && (client<=MaxClients) && (attacker>=1) && (attacker<=MaxClients) && (attacker==inflictor)) 
		SetEntPropFloat(victim, Prop_Send, "m_flVelocityModifier", 1.0); 
		return Plugin_Handled;
	
	damage = 0.0;
	return Plugin_Changed;
}