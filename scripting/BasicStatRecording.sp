#pragma semicolon 1

bool DEBUG = false;

#define PLUGIN_AUTHOR "SZOKOZ/EXE KL & PandahChan"
#define PLUGIN_VERSION "0.00"

#include "BasicStatRecording.inc"
#include "get5.inc"
#include <cstrike>
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

#define STRING(%1) %1,sizeof(%1)
#define ISEMPTY(%1) (%1[0] == '\0')

// char CREATE_TABLE[] = "CREATE TABLE IF NOT EXISTS `statistics`"...
// "("...
// "`steamid` VARCHAR(64) NOT NULL, "...
// "`ip` VARBINARY(16) NOT NULL, "...
// "`name` VARCHAR(32) NOT NULL, "...
// "`kills` INT NOT NULL DEFAULT 0, "...
// "`deaths` INT NOT NULL DEFAULT 0, "...
// "`assists` INT NOT NULL DEFAULT 0, "...
// "`3k` INT NOT NULL DEFAULT 0, "...
// "`4k` INT NOT NULL DEFAULT 0, "...
// "`5k` INT NOT NULL DEFAULT 0, "...
// "`shots` INT NOT NULL DEFAULT 0, "...
// "`hits` INT NOT NULL DEFAULT 0, "...
// "`headshots` INT NOT NULL DEFAULT 0, "...
// "`roundswon` INT NOT NULL DEFAULT 0, "...
// "`roundslost` INT NOT NULL DEFAULT 0, "...
// "`wins` INT NOT NULL DEFAULT 0, "...
// "`ties` INT NOT NULL DEFAULT 0, "...
// "`losses` INT NOT NULL DEFAULT 0, "...
// "`points` INT NOT NULL DEFAULT 0, "...
// "`lastconnect` INT NOT NULL, "...
// "`totaltime` FLOAT NOT NULL DEFAULT 1.0, "...
// "`region` VARCHAR(32) NOT NULL DEFAULT N/A, "...
// "PRIMARY KEY(`steamid`)"...
// ")"...
// "ENGINE = InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;";

char Q_INSERT_PLAYER[] = "INSERT INTO `statistics`"...
" (`steamid`,`ip`,`name`,`lastconnect`)"...
" VALUES ('%s','%s','%s',%d) ON DUPLICATE KEY UPDATE `ip`='%s', `name`='%s', `lastconnect`=%d, `region`='%s'";

char Q_UPDATE_PLAYER[] = "UPDATE `statistics` SET `ip`='%s', `name`='%s', `kills`=kills+%d, `deaths`=deaths+%d,"...
" `assists`=assists+%d, `3k`=3k+%d, `4k`=4k+%d, `5k`=5k+%d, `shots`=shots+%d, `hits`=hits+%d, `headshots`=headshots+%d, "...
"`roundswon`=roundswon+%d, `roundslost`=roundslost+%d,"...
" `wins`=wins+%d, `losses`=losses+%d, `ties`=ties+%d, "...
"`points`=points+%d, `lastconnect`=%d, `totaltime`=totaltime+%d WHERE `steamid` = '%s'";

char Q_GET_PLAYER[] = "SELECT * FROM `statistics` WHERE `steamid` = '%s'";

ArrayList g_hQueuedQueries = null;
Database g_hThreadedDb = null;

char g_iNextHitgroup[MAXPLAYERS+1];
int g_iPlayTime[MAXPLAYERS+1] = 0;

ConVar g_serverRegion;



methodmap QueuedQuery < StringMap
{
	public QueuedQuery(const char[] steamid64)
	{
		StringMap queryData = new StringMap();
		queryData.SetString("id", steamid64);
		
		return view_as<QueuedQuery>(queryData);
	}
	
	public int getValue(const char[] key)
	{
		int value;
		if (this.GetValue(key, value))
		{
			return value;
		}
		
		return -1;
	}
	
	public bool getString(const char[] key)
	{
		char buffer[255];
		return this.GetString(key, STRING(buffer));
	}
}

methodmap PlayerStatsTracker < StringMap
{
	//Consider making the keys the same name as db columns. Allows for easier specific insertion and update to db.
	public PlayerStatsTracker(int id)
	{
		if (!VALIDPLAYER(id) && !DEBUG)
		{
			return null;
		}
		
		StringMap playerstats = new StringMap();
		char id64[32];
		char ipaddress[32];
		char playername[32];
		char region[32];

		if (!GetClientAuthId(id, AuthId_SteamID64, STRING(id64)))
		{
			if (DEBUG)
			{
				Format(STRING(id64), "BOT_%d", id);
			}
			else
			{
				Format(STRING(id64), "INVALID_%d", id);
			}
			
		}

		GetConVarString(g_serverRegion, region, sizeof(region));

		GetClientIP(id, STRING(ipaddress));
		GetClientName(id, STRING(playername));
		playerstats.SetValue("uid", GetClientUserId(id));
		playerstats.SetString("id64", id64);
		playerstats.SetString("ip", ipaddress);
		playerstats.SetString("ign", playername);
		playerstats.SetValue("kills", 0);
		playerstats.SetValue("deaths", 0);
		playerstats.SetValue("assists", 0);
		playerstats.SetValue("triplekill", 0);
		playerstats.SetValue("quadrakill", 0);
		playerstats.SetValue("pentakill", 0);
		playerstats.SetValue("roundswon", 0);
		playerstats.SetValue("roundslost", 0);
		playerstats.SetValue("matcheswon", 0);
		playerstats.SetValue("matcheslost", 0);
		playerstats.SetValue("matchestied", 0);
		playerstats.SetValue("shots", 0);
		playerstats.SetValue("hits", 0);
		playerstats.SetValue("headshots", 0);
		playerstats.SetValue("points", 0);
		playerstats.SetValue("lastconnect", GetTime());
		playerstats.SetValue("totaltime", 0);
		playerstats.SetString("region", region);
		
		return view_as<PlayerStatsTracker>(playerstats);
	}
	
	public bool isValidPlayer()
	{
		char id64[32];
		this.GetString("id64", STRING(id64));
		
		return !(StrContains(id64, "BOT") != -1 || StrContains(id64, "INVALID") != -1);
	}
	
	public bool isPlayersStats(int userid)
	{
		int uid = 0;
		this.GetValue("uid", uid);
		if (uid == userid)
		{
			return true;
		}
		
		return false;
	}
	
	public void setTripleKill()
	{
		this.SetValue("triplekill", 1);
	}
	
	public void setQuadraKill()
	{
		this.SetValue("quadrakill", 1);
	}
	
	public void setPentaKill()
	{
		this.SetValue("pentakill", 1);
	}
	
	public void incrementKills()
	{
		int kills = 0;
		this.GetValue("kills", kills);
		switch(kills)
		{
			case 2:
			{
				this.setTripleKill();
			}
			case 3:
			{
				this.setQuadraKill();
			}
			case 4:
			{
				this.setPentaKill();
			}
			
		}
		this.SetValue("kills", ++kills);
	}
	
	public void incrementDeaths()
	{
		int deaths = 0;
		this.GetValue("deaths", deaths);
		this.SetValue("deaths", ++deaths);
	}
	
	public void incrementAssists()
	{
		int assists = 0;
		this.GetValue("assists", assists);
		this.SetValue("assists", ++assists);
	}
	
	public void incrementRoundsWon()
	{
		int roundsWon = 0;
		this.GetValue("roundswon", roundsWon);
		this.SetValue("roundswon", ++roundsWon);
	}
	
	public void incrementRoundsLost()
	{
		int roundsLost = 0;
		this.GetValue("roundslost", roundsLost);
		this.SetValue("roundslost", ++roundsLost);
	}
	
	public void incrementMatchesWon()
	{
		int matchesWon = 0;
		this.GetValue("matcheswon", matchesWon);
		this.SetValue("matcheswon", ++matchesWon);
	}
	
	public void incrementMatchesLost()
	{
		int matchesLost = 0;
		this.GetValue("matcheslost", matchesLost);
		this.SetValue("matcheslost", ++matchesLost);
	}
	
	public void incrementMatchesTied()
	{
		int matchesTied = 0;
		this.GetValue("matchestied", matchesTied);
		this.SetValue("matchestied", ++matchesTied);
	}
	
	public void incrementShots(int shotsFired)
	{
		int shots = 0;
		this.GetValue("shots", shots);
		this.SetValue("shots", shots+shotsFired);
	}
	
	public void incrementHits()
	{
		int hits = 0;
		this.GetValue("hits", hits);
		this.SetValue("hits", ++hits);
	}
	
	public void incrementHeadshots()
	{
		int headshots = 0;
		this.GetValue("headshots", headshots);
		this.SetValue("headshots", ++headshots);
	}
	
	public void addPoints(int pointsToAdd)
	{
		int points = 0;
		this.GetValue("points", points);
		this.SetValue("points", points + pointsToAdd);
	}
	
	public void resetStats()
	{
		this.SetValue("kills", 0);
		this.SetValue("deaths", 0);
		this.SetValue("assists", 0);
		this.SetValue("triplekill", 0);
		this.SetValue("quadrakill", 0);
		this.SetValue("pentakill", 0);
		this.SetValue("roundswon", 0);
		this.SetValue("roundslost", 0);
		this.SetValue("matcheswon", 0);
		this.SetValue("matcheslost", 0);
		this.SetValue("matchestied", 0);
		this.SetValue("shots", 0);
		this.SetValue("hits", 0);
		this.SetValue("headshots", 0);
		this.SetValue("points", 0);
		this.SetValue("connectiontime", 0);
	}
	
	public void insertToDb(bool close)
	{
		char formattedQuery[1024];
		char id64[32];
		char ipaddress[32];
		char playername[32];
		int lastconnect;
		char region[32];
		DataPack dp = new DataPack();
		this.GetString("id64", STRING(id64));
		this.GetString("ip", STRING(ipaddress));
		this.GetString("ign", STRING(playername));
		this.GetValue("lastconnect", lastconnect);
		this.GetString("region", STRING(region));
		dp.WriteCell(close);
		dp.WriteCell(this);
		
		g_hThreadedDb.Format(STRING(formattedQuery), Q_INSERT_PLAYER, id64, ipaddress, playername, lastconnect, 
			ipaddress, playername, lastconnect, region);
		g_hThreadedDb.Query(insertcb, formattedQuery, dp);
	}
	
	public void updateToDb(bool close)
	{
		char formattedQuery[1024];
		char id64[32];
		char ipaddress[32];
		char playername[32];
		int kills, deaths, assists, triplekill, quadrakill, pentakill, roundswon, roundslost, matcheswon, matcheslost, matchestied, shots, hits, headshots, 
		points, lastconnect, time;
		DataPack dp = new DataPack();
		this.GetString("id64", STRING(id64));
		this.GetString("ip", STRING(ipaddress));
		this.GetString("ign", STRING(playername));
		this.GetValue("kills", kills);
		this.GetValue("deaths", deaths);
		this.GetValue("assists", assists);
		this.GetValue("triplekill", triplekill);
		this.GetValue("quadrakill", quadrakill);
		this.GetValue("pentakill", pentakill);
		this.GetValue("roundswon", roundswon);
		this.GetValue("roundslost", roundslost);
		this.GetValue("matcheswon", matcheswon);
		this.GetValue("matcheslost", matcheslost);
		this.GetValue("matchestied", matchestied);
		this.GetValue("shots", shots);
		this.GetValue("hits", hits);
		this.GetValue("headshots", headshots);
		this.GetValue("points", points);
		this.GetValue("lastconnect", lastconnect);
		this.GetValue("time", time);
		
		dp.WriteCell(close);
		dp.WriteCell(this);
		
		int uid; this.GetValue("uid", uid);
		int client = GetClientOfUserId(uid);
		if (close)
		{
			if (client != INVALID_ENT_REFERENCE && !(StrContains(id64, "BOT") != -1 || StrContains(id64, "INVALID") != -1))
			{
				time = g_iPlayTime[client];
				PrintToServer("Time on server: %i", time);
			}
		}
		
		g_hThreadedDb.Format(STRING(formattedQuery), Q_UPDATE_PLAYER, ipaddress, playername, kills, 
			deaths, assists, triplekill, quadrakill, pentakill, shots, hits, headshots, 
			roundswon, roundslost, matcheswon, matcheslost, matchestied, points, lastconnect, time, id64);
		PrintToServer("%s", formattedQuery);
		g_hThreadedDb.Query(updatecb, formattedQuery, dp);
	}
	
	public void importFromDb(bool close)
	{
		char formattedQuery[1024];
		char id64[32];
		DataPack dp = new DataPack();
		this.GetString("id64", STRING(id64));
		dp.WriteCell(close);
		dp.WriteCell(this);
		
		g_hThreadedDb.Format(STRING(formattedQuery), Q_GET_PLAYER, id64);
		g_hThreadedDb.Query(importcb, formattedQuery, dp, DBPrio_High);
	}
	
}

bool g_bDbReady;

Handle g_hOnKill;
Handle g_hOnDeath;
Handle g_hOnAssist;
Handle g_hOnRoundWon;
Handle g_hOnPlayerRoundWon;
Handle g_hOnRoundLost;
Handle g_hOnPlayerRoundLost;
Handle g_hOnShotFired;
Handle g_hOnPlayerHit;
Handle g_hOnHeadShot;
PlayerStatsTracker g_hPlayers[MAXPLAYERS];

public Plugin myinfo = 
{
	name = "Basic Player Stats", 
	author = PLUGIN_AUTHOR, 
	description = "Records stats of players during game play.", 
	version = PLUGIN_VERSION, 
	url = "szokoz.eu"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("Basic Player Stats");
	
	g_hOnKill = CreateGlobalForward("OnKill", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnDeath = CreateGlobalForward("OnDeath", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnAssist = CreateGlobalForward("OnAssist", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnRoundWon = CreateGlobalForward("OnRoundWon", ET_Ignore, Param_Cell);
	g_hOnPlayerRoundWon = CreateGlobalForward("OnPlayerRoundWon", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnRoundLost = CreateGlobalForward("OnRoundLost", ET_Ignore, Param_Cell);
	g_hOnPlayerRoundLost = CreateGlobalForward("OnPlayerRoundLost", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnShotFired = CreateGlobalForward("OnShotFired", ET_Ignore, Param_Cell, Param_Cell, Param_String);
	g_hOnPlayerHit = CreateGlobalForward("OnPlayerHit", ET_Ignore, Param_Cell, Param_Cell, Param_Float);
	g_hOnHeadShot = CreateGlobalForward("OnHeadShot", ET_Ignore, Param_Cell, Param_Cell);
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hQueuedQueries = new ArrayList();
	Database.Connect(OnDbConnect, "BasicPlayerStats-DEV");

	g_serverRegion = CreateConVar("sm_region", "N/A", "Which region the players are playing on. NA = North America, EU= Europe, OCE = Ocenaic");
	AutoExecConfig(true, "stats");
	HookEvent("weapon_fire", Event_PlayerShoot);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_end", Event_RoundEnd);
}

public void OnDbConnect(Database db, const char[] error, any data)
{
	if (db == null)
	{
		LogError("Database failure: %s", error);
	}
	else
	{
		// db.Query(createtablecb, CREATE_TABLE);
		g_hThreadedDb = db;
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (!VALIDPLAYER(client) && !DEBUG)
	{
		return;
	}
	
	if (DEBUG)
	{
		PrintToServer("OnClientPostAdminCheck -> %d", client);
	}
	
	g_hPlayers[client] = new PlayerStatsTracker(client);
	g_hPlayers[client].insertToDb(false);
	CreateTimer(1.0, PlayTimeTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action PlayTimeTimer(Handle timer) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)){
			++g_iPlayTime[i];
		}
	}
}

public void OnClientDisconnect(int client)
{
	if (!VALIDPLAYER(client) && !DEBUG)
	{
		return;
	}
	
	if (DEBUG)
	{
		PrintToServer("OnClientDisconnect -> %d", client);
	}
	
	if (g_hPlayers[client] == null)
	{
		return;
	}
	g_hPlayers[client].updateToDb(true);
	//SDKUnhook(client, SDKHook_FireBulletsPost, FireBulletsPost);
	// SDKUnhook(client, SDKHook_TraceAttackPost, TraceAttackPost);
	delete g_hPlayers[client];
	
}

// This works fine.
public Action Event_PlayerShoot(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	char weaponname[32];
	event.GetString("weapon", STRING(weaponname));
	if (client && (VALIDPLAYER(client) || DEBUG))
	{
		int uid = GetClientUserId(client);
		if (g_hPlayers[client] != null && g_hPlayers[client].isPlayersStats(uid))
		{
			g_hPlayers[client].incrementShots(1);
			Call_StartForward(g_hOnShotFired);
			Call_PushCell(client);
			Call_PushCell(1);
			Call_PushString(weaponname);
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Client %d fired a shot.", client);
			}
			
		}
	}
	return Plugin_Continue;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)  {
	int victimid = event.GetInt("userid");
	int attackerid = event.GetInt("attacker");
	int assisterid = event.GetInt("assister");
	int victim = GetClientOfUserId(victimid);
	int attacker = GetClientOfUserId(attackerid);
	int assister = GetClientOfUserId(assisterid);

	int hitgroup = GetEventInt(event, "hitgroup");

	if (attacker && (VALIDPLAYER(attacker) || DEBUG))
	{
		int aid = GetClientUserId(attacker);
		if (g_hPlayers[attacker] != null && g_hPlayers[attacker].isPlayersStats(aid))
		{
			g_hPlayers[attacker].incrementHits();
			Call_StartForward(g_hOnPlayerHit);
			Call_PushCell(victim);
			Call_PushCell(attacker);
			//Call_PushFloat(damage);
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Attacker %d hit victim %d.", attacker, victim);
			}
			
			if (GetClientHealth(victim) <= 0 && hitgroup == 1)
			{
				g_hPlayers[attacker].incrementHeadshots();
				Call_StartForward(g_hOnHeadShot);
				Call_PushCell(victim);
				Call_PushCell(attacker);
				Call_Finish();
				
				if (DEBUG)
				{
					PrintToServer("Attacker %d headshot victim %d.", attacker, victim);
				}
				
			}
		}
	}
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victimid = event.GetInt("userid");
	int attackerid = event.GetInt("attacker");
	int assisterid = event.GetInt("assister");
	int victim = GetClientOfUserId(victimid);
	int attacker = GetClientOfUserId(attackerid);
	int assister = GetClientOfUserId(assisterid);
	
	if (victim && (VALIDPLAYER(victim) || DEBUG) && g_hPlayers[victim] != null && g_hPlayers[victim].isPlayersStats(victimid))
	{
		g_hPlayers[victim].incrementDeaths();
		Call_StartForward(g_hOnDeath);
		Call_PushCell(victim);
		Call_PushCell(attacker);
		Call_PushCell(assister);
		Call_Finish();
		
		if (DEBUG)
		{
			PrintToServer("Victim %d died.", victim);
		}
		
	}
	
	if (attacker && (VALIDPLAYER(attacker) || DEBUG) && g_hPlayers[attacker] != null && g_hPlayers[attacker].isPlayersStats(attackerid))
	{
		g_hPlayers[attacker].incrementKills();
		Call_StartForward(g_hOnKill);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_PushCell(event.GetBool("headshot"));
		Call_Finish();
		
		if (DEBUG)
		{
			PrintToServer("Attacker %d killed victim %d.", attacker, victim);
		}
		
	}
	
	if (assister && (VALIDPLAYER(assister) || DEBUG) && g_hPlayers[assister] != null && g_hPlayers[assister].isPlayersStats(assisterid))
	{
		g_hPlayers[assister].incrementAssists();
		Call_StartForward(g_hOnAssist);
		Call_PushCell(assister);
		Call_PushCell(victim);
		Call_Finish();
		
		if (DEBUG)
		{
			PrintToServer("Assister %d assisted in the death of victim %d.", assister, victim);
		}
		
	}
	
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	int team = event.GetInt("winner");
	int otherTeam = (team == 2) ? 3 : 2;
	Call_StartForward(g_hOnRoundWon);
	Call_PushCell(team);
	Call_Finish();
	Call_StartForward(g_hOnRoundLost);
	Call_PushCell(otherTeam);
	Call_Finish();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!VALIDPLAYER(i) && !DEBUG)
		{
			continue;
		}
		
		if (g_hPlayers[i] == null)
		{
			continue;
		}
		
		int clientteam;
		if ((clientteam = GetClientTeam(i)) == team)
		{
			g_hPlayers[i].incrementRoundsWon();
			Call_StartForward(g_hOnPlayerRoundWon);
			Call_PushCell(i);
			Call_PushCell(team);
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Client %d on Team %d won.", i, team);
			}
			
		}
		else if (clientteam == otherTeam)
		{
			g_hPlayers[i].incrementRoundsLost();
			Call_StartForward(g_hOnPlayerRoundLost);
			Call_PushCell(i);
			Call_PushCell(otherTeam);
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Client %d on Team %d lost.", i, otherTeam);
			}
			
		}
		else
		{
			if (DEBUG)
			{
				PrintToServer("Client %d can't win or lose coz they aren't on a team!", i);
			}
			
		}
		g_hPlayers[i].updateToDb(false);
		g_hPlayers[i].resetStats();
	}
	
	return Plugin_Continue;
}

/*
public void FireBulletsPost(int client, int shots, const char[] weaponname)
{
	PrintToServer("Do You Even Flex?");
	if (client && (VALIDPLAYER(client) || DEBUG))
	{
		int uid = GetClientUserId(client);
		if (g_hPlayers[client] != null && g_hPlayers[client].isPlayersStats(uid))
		{
			g_hPlayers[client].incrementShots(shots);
			Call_StartForward(g_hOnShotFired);
			Call_PushCell(client);
			Call_PushCell(shots);
			Call_PushString(weaponname);
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Client %d fired a shot.", client);
			}
			
		}
	}
}
*/
	// public void TraceAttackPost(int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup)
	// {
	// 	if (attacker && (VALIDPLAYER(attacker) || DEBUG))
	// 	{
	// 		hitgroup = g_iNextHitgroup[victim];
	// 		int aid = GetClientUserId(attacker);
	// 		if (g_hPlayers[attacker] != null && g_hPlayers[attacker].isPlayersStats(aid))
	// 		{
	// 			g_hPlayers[attacker].incrementHits();
	// 			Call_StartForward(g_hOnPlayerHit);
	// 			Call_PushCell(victim);
	// 			Call_PushCell(attacker);
	// 			Call_PushFloat(damage);
	// 			Call_Finish();
				
	// 			if (DEBUG)
	// 			{
	// 				PrintToServer("Attacker %d hit victim %d.", attacker, victim);
	// 			}
				
	// 			if (GetClientHealth(victim) <= 0 && hitgroup == 1)
	// 			{
	// 				g_hPlayers[attacker].incrementHeadshots();
	// 				Call_StartForward(g_hOnHeadShot);
	// 				Call_PushCell(victim);
	// 				Call_PushCell(attacker);
	// 				Call_Finish();
					
	// 				if (DEBUG)
	// 				{
	// 					PrintToServer("Attacker %d headshot victim %d.", attacker, victim);
	// 				}
					
	// 			}
	// 		}
	// 	}
	// }

public void Get5_OnSeriesResult(MatchTeam seriesWinner, int team1MapScore, int team2MapScore)
{
	MatchTeam seriesLoser = seriesWinner == MatchTeam_Team2 ? MatchTeam_Team1:MatchTeam_Team2;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!VALIDPLAYER(i) && !DEBUG)
		{
			continue;
		}
		
		if (g_hPlayers[i] == null)
		{
			continue;
		}
		
		char auth[32];
		if (!g_hPlayers[i].GetString("id64", STRING(auth)))
		{
			continue;
		}
		
		MatchTeam team = Get5_GetPlayerTeam(auth);
		if (team == seriesWinner)
		{
			g_hPlayers[i].incrementMatchesWon();
		}
		else if (team == seriesLoser)
		{
			g_hPlayers[i].incrementMatchesLost();
		}
		
		g_hPlayers[i].addPoints(CS_GetClientContributionScore(i));
		g_hPlayers[i].updateToDb(true);
	}
}

public Action Timer_ClosePlayerStats(Handle timer, any data)
{
	//delete view_as<Handle>(data);
}

public void createtablecb(Database db, DBResultSet results, const char[] error, any data)
{
	if (!ISEMPTY(error))
	{
		LogError(error);
		return;
	}
	
	g_bDbReady = true;
}

public void insertcb(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack dp = view_as<DataPack>(data);
	dp.Reset();
	
	bool close = view_as<bool>(dp.ReadCell());
	PlayerStatsTracker ps = view_as<PlayerStatsTracker>(dp.ReadCell());
	
	if (!ISEMPTY(error))
	{
		LogError(error);
	}
	
	if (close)
	{
		CreateTimer(1.0, Timer_ClosePlayerStats, ps);
	}
}

public void updatecb(Database db, DBResultSet results, const char[] error, any data)
{	
	DataPack dp = view_as<DataPack>(data);
	dp.Reset();
	
	bool close = view_as<bool>(dp.ReadCell());
	PlayerStatsTracker ps = view_as<PlayerStatsTracker>(dp.ReadCell());
	
	if (!ISEMPTY(error))
	{
		LogError(error);
	}
	
	if (close)
	{
		CreateTimer(1.0, Timer_ClosePlayerStats, ps);
	}
}

public void importcb(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack dp = view_as<DataPack>(data);
	dp.Reset();
	
	bool close = view_as<bool>(dp.ReadCell());
	PlayerStatsTracker ps = view_as<PlayerStatsTracker>(dp.ReadCell());
	
	if (!ISEMPTY(error))
	{
		LogError(error);
		if (close)
		{
			CreateTimer(1.0, Timer_ClosePlayerStats, ps);
			return;
		}
	}
		 
	if (results == null)
	{
		LogError("Failed to get results. results == null");
	}
	else
	{
		if (results.RowCount == 0)
		{
			LogError("No row returned for import query.");
		}
		else
		{
			results.FetchRow();
			ps.SetValue("kills", results.FetchInt(3));
			ps.SetValue("deaths", results.FetchInt(4));
			ps.SetValue("assists", results.FetchInt(5));
			ps.SetValue("shots", results.FetchInt(6));
			ps.SetValue("hits", results.FetchInt(7));
			ps.SetValue("headshots", results.FetchInt(8));
			ps.SetValue("points", results.FetchInt(9));
			PrintToServer("Imported results from db.");
		}
	}
	if (close)
	{
		CreateTimer(1.0, Timer_ClosePlayerStats, ps);
	}
}

bool VALIDPLAYER(int client)
{
	if (0 < client <= MaxClients)
	{
		if (IsClientInGame(client) && !IsClientReplay(client) && !IsClientSourceTV(client) && !IsFakeClient(client))
		{
			return true;
		}
	}
	
	return false;
} 