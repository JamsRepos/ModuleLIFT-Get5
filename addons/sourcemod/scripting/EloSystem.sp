#pragma semicolon 1

bool DEBUG = false;

#define PLUGIN_AUTHOR "DN.H | PandahChan"
#define PLUGIN_VERSION "0.00"

#include <sourcemod>
#include <sdktools>
#include "BasicStatRecording.inc"
#include "get5.inc"

#pragma newdecls required

//bool g_bBSREnabled;
char g_sz_INSERT_PLAYER[] = "INSERT IGNORE INTO `player_elo`"...
" (`steamid`, `elo`) VALUES ('%s', '%i')";
char g_sz_UPDATE_PLAYER[] = "UPDATE `player_elo` SET `elo`=elo+%d, `matches`=matches+1 WHERE `steamid` = '%s'";
char g_sz_GET_PLAYER[] = "SELECT * FROM `player_elo` WHERE `steamid` = '%s'";

ConVar g_cvDefaultElo;
ConVar g_cvEloPerKill;
ConVar g_cvEloPerDeath;
ConVar g_cvEloPerAssist;
ConVar g_cvEloPerMVP;
ConVar g_cvEloHeadShotKillBonus;
ConVar g_cvEloPerBombExplosion;
ConVar g_cvEloPerBombDisarm;
ConVar g_cvPreliminaryMatchCount;
ConVar g_cvPreliminaryMatchEloGain;
ConVar g_cvEloPerOneVsTwo;
ConVar g_cvEloPerOneVsThree;
ConVar g_cvEloPerOneVsFour;
ConVar g_cvEloPerOneVsFive;
Database g_hThreadedDb;

// Scrappy fix before I modify get5_endmatch
bool hasCalculated = false;

methodmap PlayerEloMap < StringMap
{
	public PlayerEloMap(const char[] id64)
	{
		StringMap map = new StringMap();
		map.SetString("id64", id64);
		map.SetValue("elogain", 0);
		return view_as<PlayerEloMap>(map);
	}
	
	public void GetId64(char[] id64, int size)
	{
		this.GetString("id64", id64, size);
	}
	
	public int GetEloGain()
	{
		int eloGain;
		this.GetValue("elogain", eloGain);
		return eloGain;
	}

	public int GetMatchesPlayed()
	{
		int matchesplayed;
		this.GetValue("matchesplayed", matchesplayed);
		return matchesplayed;
	}
	
	public void addToEloGain(int elo)
	{
		int eloGain;
		this.GetValue("elogain", eloGain);
		this.SetValue("elogain", eloGain + elo);
	}
	
	public MatchTeam GetTeam()
	{
		MatchTeam team;
		this.GetValue("team", team);
		return team;
	}
	
	public void SetTeam(MatchTeam team)
	{
		this.SetValue("team", team);
	}
}

PlayerEloMap g_hPlayer[MAXPLAYERS];

public Plugin myinfo = 
{
	name = "Elo System",
	author = PLUGIN_AUTHOR,
	description = "Ranking system for matchmaking.",
	version = PLUGIN_VERSION,
	url = "DistrictNine.Host"
};

// literally doing nothing
// public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
// {
	
// }
	
public void OnPluginStart()
{
	Database.Connect(SQL_OnConnect, "EloSys");
	
	g_cvDefaultElo = CreateConVar("EloSys_DefaultElo", "600", "Default elo new players start with.");
	g_cvEloPerKill = CreateConVar("EloSys_EloPerKill", "2", "Elo gained per kill.");
	g_cvEloPerDeath = CreateConVar("EloSys_EloPerDeath", "-2", "Elo gained per death.");
	g_cvEloPerAssist = CreateConVar("EloSys_EloPerAssist", "1", "Elo gained per assist.");
	g_cvEloPerMVP = CreateConVar("EloSys_EloPerMVPs", "2", "Elo gained per MVP.");
	g_cvEloPerOneVsTwo = CreateConVar("EloSys_EloPerOneVsTwo", "0", "Elo gained per 1vs2");
	g_cvEloPerOneVsThree = CreateConVar("EloSys_EloPerOneVsThree", "1", "Elo gained per 1vs3");
	g_cvEloPerOneVsFour = CreateConVar("EloSys_EloPerOneVsFour", "2", "Elo gained per 1vs4");
	g_cvEloPerOneVsFive = CreateConVar("EloSys_EloPerOneVsFive", "4", "Elo gained per 1vs5");
	g_cvEloHeadShotKillBonus = CreateConVar("EloSys_HeadShotKillBonus", "0", "Bonus elo gained for a headshot kill.");
	g_cvEloPerBombExplosion = CreateConVar("EloSys_EloPerBombExplode", "0", "Elo gained for successful bomb explosion.");
	g_cvEloPerBombDisarm = CreateConVar("EloSys_EloPerBombDisarm", "0", "Elo gained for successfully disarming bomb.");
	g_cvPreliminaryMatchCount = CreateConVar("EloSys_PreliminaryMatchCount", "10", "Preliminary matches to play until a player is ranked.");
	g_cvPreliminaryMatchEloGain = CreateConVar("EloSys_PrelimMatchEloGain", "125", "Elo amount gained or lost per preliminary match.");
	
	AutoExecConfig(true);
}

public void SQL_OnConnect(Database db, const char[] error, any data)
{
	if(db == null)
	{
		SetFailState("Database Connection Error: %s", error);
	}

	g_hThreadedDb = db;
}

public void OnConfigsExecuted()
{
	char CREATE_TABLE[] = "CREATE TABLE IF NOT EXISTS `player_elo`"...
	"("...
	"`steamid` VARCHAR(64) NOT NULL, "...
	"`elo` INT NOT NULL DEFAULT %d, "...
	"`matches` INT NOT NULL DEFAULT 0, "...
	"PRIMARY KEY(`steamid`)"...
	")"...
	"ENGINE = InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;";
	
	char query[1024];
	g_hThreadedDb.Format(query, sizeof(query), CREATE_TABLE, g_cvDefaultElo.IntValue);
	g_hThreadedDb.Query(SQL_GenericQuery, query);
}

public void OnClientPostAdminCheck(int client)
{
	if (!VALIDPLAYER(client) && !DEBUG)
	{
		return;
	}
	
	char auth[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth)))
	{
		if (DEBUG)
		{
			Format(auth, sizeof(auth), "BOT_%d", client);
		}
		else
		{
			Format(auth, sizeof(auth), "INVALID_%d", client);
		}
	}
	
	InsertPlayerToTable(auth);
	if (DEBUG)
	{
		g_hPlayer[client] = new PlayerEloMap(auth);
	}
}

public void OnPlayerRoundWon(int client, int team, int enemyRemaining)
{
	if(g_hPlayer[client] == null)
	{
		PrintToServer("Client %d does not have an elo map.", client);
		return;
	}

	if (g_hPlayer[client].GetMatchesPlayed() < 10)
	{
		return;
	}

	// Untested code (but shouldn't have issues as it's just a clean up.)
	switch (enemyRemaining)
	{
		case 2:
		{
			g_hPlayer[client].addToEloGain(g_cvEloPerOneVsTwo.IntValue);
		}

		case 3:
		{
			g_hPlayer[client].addToEloGain(g_cvEloPerOneVsThree.IntValue);
		}

		case 4:
		{
			g_hPlayer[client].addToEloGain(g_cvEloPerOneVsFour.IntValue);
		}

		case 5:
		{
			g_hPlayer[client].addToEloGain(g_cvEloPerOneVsFive.IntValue);
		}
	}
}

public void OnKill(int killer, int victim, bool headshot)
{
	if (g_hPlayer[killer] == null)
	{
		if (DEBUG)
		PrintToServer("Client %d does not have an elo map.", killer);
		
		return;
	}

	if (g_hPlayer[killer].GetMatchesPlayed() < 10)
	{
		return;
	}
	
	if (headshot)
	{
		g_hPlayer[killer].addToEloGain(g_cvEloPerKill.IntValue + g_cvEloHeadShotKillBonus.IntValue);
		return;
	}
	
	g_hPlayer[killer].addToEloGain(g_cvEloPerKill.IntValue);
}

public void OnRoundMVP(int client)
{
	if (g_hPlayer[client] == null)
	{
		if (DEBUG)
		PrintToServer("Client %i does not have an elo map.", client);
		return;
	}

	if (g_hPlayer[client].GetMatchesPlayed() < 10)
	{
		return;
	}

	g_hPlayer[client].addToEloGain(g_cvEloPerMVP.IntValue);
}

public void OnDeath(int victim, int killer, int assister)
{
	if (g_hPlayer[victim] == null)
	{
		if (DEBUG)
		PrintToServer("Client %d does not have an elo map.", victim);
		
		return;
	}

	if (g_hPlayer[victim].GetMatchesPlayed() < 10)
	{
		return;
	}
	
	g_hPlayer[victim].addToEloGain(g_cvEloPerDeath.IntValue);
}

public void OnAssist(int assister, int victim)
{

	if (g_hPlayer[assister] == null)
	{
		if (DEBUG)
		PrintToServer("Client %d does not have an elo map.", assister);
		
		return;
	}

	if (g_hPlayer[assister].GetMatchesPlayed() < 10)
	{
		return;
	}
	
	g_hPlayer[assister].addToEloGain(g_cvEloPerAssist.IntValue);
}

public void Get5_OnGoingLive(int mapNumber)
{
	/*if (!g_bBSREnabled)
	{
		PrintToChatAll("[EloSys] Unable to start ranking system. This match will no longer affect your ranking.");
		SetFailState("[EloSys] Dependent Library 'Basic Player Stats' is not loaded.");
	}*/
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!VALIDPLAYER(i) && !DEBUG)
		{
			continue;
		}
		
		int team = GetClientTeam(i);
		if (team < 2)
		{
			continue;
		}
		
		char auth[32];
		bool isInvalid;
		if (!GetClientAuthId(i, AuthId_SteamID64, auth, sizeof(auth)))
		{
			isInvalid = true;
			if (DEBUG)
			{
				Format(auth, sizeof(auth), "BOT_%d", i);
			}
			else
			{
				Format(auth, sizeof(auth), "INVALID_%d", i);
			}
		}
		g_hPlayer[i] = new PlayerEloMap(auth);
		
		if (!isInvalid) {
			g_hPlayer[i].SetTeam(Get5_GetPlayerTeam(auth));
		} else {
			g_hPlayer[i].SetTeam(Get5_CSTeamToMatchTeam(GetClientTeam(i)));
		}

		
	}	
}

public void Get5_OnSeriesResult(MatchTeam seriesWinner, int team1MapScore, int team2MapScore)
{
	if(hasCalculated) return;

	Transaction txn_SelectElo = new Transaction();
	char sQuery[1024]; 

	for(int i = 1; i <= MaxClients; i++)
	{
		char auth[32];
		PlayerEloMap player = g_hPlayer[i];
		if (player == null)
		{
			continue;
		}
		player.GetId64(auth, sizeof(auth));

		g_hThreadedDb.Format(sQuery, sizeof(sQuery), g_sz_GET_PLAYER, auth);
		txn_SelectElo.AddQuery(sQuery, i);
	}
	g_hThreadedDb.Execute(txn_SelectElo, SQL_TranSuccessSelect, SQL_TranFailure, seriesWinner);
}

public void SQL_TranFailure(Database db, any data, int numQueries, const char[] sError, int failIndex, any[] queryData)
{
	LogError("Transaction Failed! Error: %s. During Query: %i", sError, failIndex);
}

public void SQL_TranSuccess(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{
	PrintToServer("Transaction Successful");
}

public void SQL_TranSuccessSelect(Database db, MatchTeam seriesWinner, int numQueries, DBResultSet[] results, any[] queryData)
{
	if(hasCalculated) return;

	MatchTeam seriesLoser = seriesWinner == MatchTeam_Team2 ? MatchTeam_Team1:MatchTeam_Team2;
	int winningTeamCount, losingTeamCount, winningTeamAvgElo, losingTeamAvgElo;
	char sQuery[1024];

	for(int i = 0; i < numQueries; i++)
	{
		PlayerEloMap player = g_hPlayer[queryData[i]];
		if(player == null)
			continue;

		if(!results[i].FetchRow()) continue;

		int eloCol, matchesCol;
		results[i].FieldNameToNum("elo", eloCol);
		results[i].FieldNameToNum("matches", matchesCol);

		MatchTeam team = player.GetTeam();

		int currentElo = results[i].FetchInt(eloCol);
		int matchesPlayed = results[i].FetchInt(matchesCol);
		player.SetValue("currentelo", currentElo);
		player.SetValue("matchesplayed", matchesPlayed);

		if (team == seriesWinner)
		{
			winningTeamAvgElo += currentElo;
			winningTeamCount++;
		}
		else if (team == seriesLoser)
		{
			losingTeamAvgElo += currentElo;
			losingTeamCount++;
		}
	}

	winningTeamAvgElo /= winningTeamCount;
	losingTeamAvgElo /= losingTeamCount;
	Transaction txn_UpdateElo = new Transaction();

	for (int i = 1; i <= MaxClients; i++)
	{
		PlayerEloMap player = g_hPlayer[i];
		if (player == null)
		{
			continue;
		}
		char auth[32];
		player.GetId64(auth, sizeof(auth));
			
		MatchTeam team = player.GetTeam();
		int playerElo, playerMatches;
		player.GetValue("currentelo", playerElo);
		player.GetValue("matchesplayed", playerMatches);
		if (team == seriesWinner)
		{
			if (playerMatches < g_cvPreliminaryMatchCount.IntValue)
			{
				player.addToEloGain(g_cvPreliminaryMatchEloGain.IntValue);
			}
			else
			{
				player.addToEloGain(calculateEloGain(playerElo, winningTeamAvgElo, true));
			}
		}
		else if (team == seriesLoser)
		{
			if (playerMatches > g_cvPreliminaryMatchCount.IntValue))
			{
				int eloValue = calculateEloGain(playerElo, losingTeamAvgElo, true);
				int playerNewElo = playerElo - eloValue;
				if (playerNewElo < 0)
				{
					player.SetValue("currentelo", 0);
				}
				else
				{
					player.addToEloGain(calculateEloGain(playerElo, losingTeamAvgElo, false));
				}
			}
		}
		int eloGain = player.GetEloGain();
		if (eloGain <= 0)
		{
			eloGain = 0;
		}
		Format(sQuery, sizeof(sQuery), "UPDATE `player_elo` SET `elo`=elo+%d, `matches`=matches+1 WHERE `steamid` = '%s'", eloGain, auth);
		txn_UpdateElo.AddQuery(sQuery);
		// UpdatePlayerInTable(player);
	}
	hasCalculated = true;
	g_hThreadedDb.Execute(txn_UpdateElo, SQL_TranSuccess, SQL_TranFailure);
}

void InsertPlayerToTable(const char[] auth)
{
	char query[1024];
	g_hThreadedDb.Format(query, sizeof(query), g_sz_INSERT_PLAYER, auth, g_cvDefaultElo.IntValue);
	g_hThreadedDb.Query(SQL_GenericQuery, query);
}

// void UpdatePlayerInTable(PlayerEloMap player)
// {
// 	char auth[32];
// 	player.GetId64(auth, sizeof(auth));
// 	int eloGain = player.GetEloGain();
// 	// int playerElo = player.GetValue("currentelo", playerElo); this isnt being used for anything, not sure why its defined

// 	char query[1024];
// 	g_hThreadedDb.Format(query, sizeof(query), g_sz_UPDATE_PLAYER, eloGain, auth);
// 	g_hThreadedDb.Query(SQL_GenericQuery, query);
// }

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

int calculateEloGain(int playerElo, int otherTeamAvgElo, bool playerWon)
{
	int eloDiff = playerElo - otherTeamAvgElo;
	
	//Hardcoded for testing period.
	if (playerWon)
	{
		if (eloDiff >= 200)
		{
			return 5;
		}
		else if (eloDiff >= 150)
		{
			return 10;
		}
		else if (eloDiff >= 100)
		{
			return 15;
		}
		else if (eloDiff >= 50)
		{
			return 20;
		}
		else if (eloDiff >= 0)
		{
			return 25;
		}
		else if (eloDiff >= -50)
		{
			return 30;
		}
		else if (eloDiff >= -100)
		{
			return 35;
		}
		else if (eloDiff >= -150)
		{
			return 40;
		}
		else if (eloDiff >= -200)
		{
			return 45;
		}
		else if (eloDiff >= -250)
		{
			return 50;
		}
	}
	else
	{
		if (eloDiff >= 250)
		{
			return -50;
		}
		else if (eloDiff >= 200)
		{
			return -45;
		}
		else if (eloDiff >= 150)
		{
			return -40;
		}
		else if (eloDiff >= 100)
		{
			return -35;
		}
		else if (eloDiff >= 50)
		{
			return -30;
		}
		else if (eloDiff >= 0)
		{
			return -25;
		}
		else if (eloDiff >= -50)
		{
			return -20;
		}
		else if (eloDiff >= -100)
		{
			return -15;
		}
		else if (eloDiff >= -150)
		{
			return -10;
		}
		else if (eloDiff >= -200)
		{
			return -5;
		}
	}
	
	return 0;
}

public void SQL_GenericQuery(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		LogError("MySQL Query Failed: %s", sError);
	}
}