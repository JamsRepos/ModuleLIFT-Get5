#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, SDK_OnTakeDamage);
}

public Action SDK_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	// Invalid attackers or self damage
	if (attacker < 1 || attacker > MaxClients || attacker == victim || inflictor < 1)
	{
		return Plugin_Continue;
	}
	
	// Handle friendly fire
	if (GetClientTeam(attacker) == GetClientTeam(victim))
	{
		char inflictorClass[64];
		if (GetEdictClassname(inflictor, inflictorClass, sizeof(inflictorClass)))
		{
			// Allow C4 damage
			if (StrEqual(inflictorClass, "planted_c4"))
			{
				return Plugin_Continue;
			}
			
			// Allow incendiary damage
			if (StrEqual(inflictorClass, "inferno"))
			{
				return Plugin_Continue;
			}
		}

		damage = 0.0;
		damagetype |= DMG_PREVENT_PHYSICS_FORCE;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}	
