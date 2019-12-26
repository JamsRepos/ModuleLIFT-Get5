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
	HookEvent("player_hurt", Event_OnPlayerHurt);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (attacker == 0 || attacker > MaxClients || victim == attacker || GetClientTeam(victim) != GetClientTeam(attacker))
		return Plugin_Continue;

	if ((damagetype & DMG_BURN) == DMG_BURN)
		return Plugin_Continue;
	
	damage = 0.0;
	return Plugin_Changed;
}

// This should fix team attack slow down. Go away griefers.
public Action Event_OnPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int hitgroup = event.GetInt("hitgroup");
	int dmg = event.GetInt("dmg_health");
	
	if (GetClientTeam(attacker) == GetClientTeam(victim))
	{
		if (GetEntPropFloat(victim, Prop_Send, "m_flVelocityModifier") < 0.6) 
		{
			SetEntPropFloat(victim, Prop_Send, "m_flVelocityModifier", 0.6);
			return Plugin_Handled;
		}
		return Plugin_Continue;		
	}
}