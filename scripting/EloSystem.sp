#pragma semicolon 1

bool DEBUG = false;

#define PLUGIN_AUTHOR "SZOKOZ/EXE KL"
#define PLUGIN_VERSION "0.00"

#include <sourcemod>
#include <sdktools>
#include "BasicStatRecording.inc"
#include "get5.inc"

#pragma newdecls required

//bool g_bBSREnabled;
char g_szSqlError[256];
char g_sz_INSERT_PLAYER[] = "INSERT IGNORE INTO `player_elo`"...
" (`steamid`) VALUES ('%s')";
char g_sz_UPDATE_PLAYER[] = "UPDATE `player_elo` SET `elo`=elo+%d, `matches`=matches+1 WHERE `steamid` = '%s'";
char g_sz_GET_PLAYER[] = "SELECT * FROM `player_elo` WHERE `steamid` = '%s'";

char g_sz_INSERT_PLAYER_PREP[] = "INSERT IGNORE INTO `player_elo`"...
" (`steamid`) VALUES (?)";
char g_sz_UPDATE_PLAYER_PREP[] = "UPDATE `player_elo` SET `elo`=elo+?, `matches`=matches+1 WHERE `steamid` = ?";
char g_sz_GET_PLAYER_PREP[] = "SELECT * FROM `player_elo` WHERE `steamid` = ?";

int roundCounter;

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
DBStatement g_hInsertNewEntry;
DBStatement g_hUpdateElo;
DBStatement g_hGetElo;

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
	name = "EloSystem",
	author = PLUGIN_AUTHOR,
	description = "Ranking system for matchmaking.",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	
}
	
public void OnPluginStart()
{
	g_hThreadedDb = SQL_Connect("EloSys", true, g_szSqlError, sizeof(g_szSqlError));
	if (g_hThreadedDb == null)
	{
		SetFailState(g_szSqlError);
	}
	
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
	
	g_hInsertNewEntry = SQL_PrepareQuery(g_hThreadedDb, g_sz_INSERT_PLAYER_PREP, g_szSqlError, sizeof(g_szSqlError));
	if (g_hInsertNewEntry == null)
	{
		LogError("%s", g_szSqlError);
	}
	g_hUpdateElo = SQL_PrepareQuery(g_hThreadedDb, g_sz_UPDATE_PLAYER_PREP, g_szSqlError, sizeof(g_szSqlError));
	if (g_hUpdateElo == null)
	{
		LogError("%s", g_szSqlError);
	}
	g_hGetElo = SQL_PrepareQuery(g_hThreadedDb, g_sz_GET_PLAYER_PREP, g_szSqlError, sizeof(g_szSqlError));
	if (g_hGetElo == null)
	{
		LogError("%s", g_szSqlError);
	}
	AutoExecConfig(true);
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
	Format(query, sizeof(query), CREATE_TABLE, g_cvDefaultElo.IntValue);
	if (!SQL_FastQuery(g_hThreadedDb, query))
	{
		SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError));
		LogError("%s", g_szSqlError);
	}
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

	if (enemyRemaining == 2)
	{
		g_hPlayer[client].addToEloGain(g_cvEloPerOneVsTwo.IntValue);
	}
	else if (enemyRemaining == 3)
	{
		g_hPlayer[client].addToEloGain(g_cvEloPerOneVsThree.IntValue);
	}
	else if (enemyRemaining == 4)
	{
		g_hPlayer[client].addToEloGain(g_cvEloPerOneVsFour.IntValue);
	}
	else if (enemyRemaining == 5)
	{
		g_hPlayer[client].addToEloGain(g_cvEloPerOneVsFive.IntValue);
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
	LogMessage("ON SERIES RESULT CALLED");
	MatchTeam seriesLoser = seriesWinner == MatchTeam_Team2 ? MatchTeam_Team1:MatchTeam_Team2;

	int winningTeamCount;
	int losingTeamCount;
	int winningTeamAvgElo;
	int losingTeamAvgElo;

	if (!hasCalculated)
	{
	
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
			
			int currentElo, matchesPlayed;
			GetPlayerFromTable(auth, currentElo, matchesPlayed);
			player.SetValue("currentelo", currentElo);
			player.SetValue("matchesplayed", matchesPlayed);

			if (team == seriesWinner)
			{
				winningTeamAvgElo += currentElo;
				LogMessage("Series Winner Average Elo %i", winningTeamAvgElo);
				LogMessage("Series Winner Current Elo %i", currentElo);
				winningTeamCount++;
			}
			else if (team == seriesLoser)
			{
				losingTeamAvgElo += currentElo;
				LogMessage("Series Winner Average Elo %i", losingTeamAvgElo);
				LogMessage("Series Winner Current Elo %i", currentElo);
				losingTeamCount++;
			}
		}
		
		winningTeamAvgElo /= winningTeamCount;
		losingTeamAvgElo /= losingTeamCount;

		LogMessage("Winning Team Average Elo is %i", winningTeamAvgElo);
		LogMessage("Losing Team Average Elo is %i", losingTeamAvgElo);
		LogMessage("Winning Team Count is %i", winningTeamCount);
		LogMessage("Losing Team Count is %i", losingTeamCount);
		
		for (int i = 1; i <= MaxClients; i++)
		{
			PlayerEloMap player = g_hPlayer[i];
			if (player == null)
			{
				continue;
			}
			
			MatchTeam team = player.GetTeam();
			int playerElo, playerMatches;
			player.GetValue("currentelo", playerElo);
			LogMessage("Current Player elo %i", playerElo);
			player.GetValue("matchesplayed", playerMatches);
			LogMessage("Current Matches %i", playerMatches);

			if (team == seriesWinner)
			{
				if (playerMatches < g_cvPreliminaryMatchCount.IntValue)
				{
					player.addToEloGain(g_cvPreliminaryMatchEloGain.IntValue);
				}
				else
				{
					int eloValue = calculateEloGain(playerElo, winningTeamAvgElo, true);
					LogMessage("[WINNER] The elo value is: %i", eloValue);
					player.addToEloGain(calculateEloGain(playerElo, winningTeamAvgElo, true));
				}
			}
			else if (team == seriesLoser)
			{
				if (playerMatches < g_cvPreliminaryMatchCount.IntValue)
				{
					player.addToEloGain(-g_cvPreliminaryMatchEloGain.IntValue);
				}
				else
				{
					int eloValue = calculateEloGain(playerElo, winningTeamAvgElo, true);
					LogMessage("[LOSER] The elo value is: %i", eloValue);
					player.addToEloGain(calculateEloGain(playerElo, losingTeamAvgElo, false));
				}
			}
			
			UpdatePlayerInTable(player);
			hasCalculated = true;
		}
	}
	else
	{
		return;
	}
}

void InsertPlayerToTable(const char[] auth)
{
	if (g_hInsertNewEntry == null)
	{
		DBResultSet hQuery;
		static char query[1024];
		
		Format(query, sizeof(query), g_sz_INSERT_PLAYER, auth);
		
		if ((hQuery = SQL_Query(g_hThreadedDb, query)) == null)
		{
			SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError));
			LogMessage("Debug[INSERT]: %s",g_szSqlError);
			return;
		}
		
		delete hQuery;
		return;
	}
	
	SQL_BindParamString(g_hInsertNewEntry, 0, auth, false);
	if (!SQL_Execute(g_hInsertNewEntry))
	{
		SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError));
		LogMessage("Debug[INSERT]: %s",g_szSqlError);
	}
}

void UpdatePlayerInTable(PlayerEloMap player)
{
	LogMessage("UPDATE PLAYER IN TABLE CALLED.");
	char auth[32];
	player.GetId64(auth, sizeof(auth));
	int eloGain = player.GetEloGain();
	int playerElo = player.GetValue("currentelo", playerElo);

	LogMessage("Players elo gain %i", eloGain);


	if (g_hUpdateElo == null)
	{
		DBResultSet hQuery;
		static char query[1024];
		
		Format(query, sizeof(query), g_sz_UPDATE_PLAYER, eloGain, auth);
		
		if ((hQuery = SQL_Query(g_hThreadedDb, query)) == null)
		{
			SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError));
			LogMessage("Debug[UPDATE]: %s",g_szSqlError);
			return;
		}
		
		delete hQuery;
		return;
	}
	
	SQL_BindParamInt(g_hUpdateElo, 0, eloGain);
	SQL_BindParamString(g_hUpdateElo, 1, auth, false);
	if (!SQL_Execute(g_hUpdateElo))
	{
		SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError));
		LogMessage("Debug[UPDATE]: %s", g_szSqlError);
	}
}

void GetPlayerFromTable(const char[] auth, int &elo, int &matches)
{
	if (g_hGetElo == null)
	{
		DBResultSet hQuery;
		static char query[1024];
		
		Format(query, sizeof(query), g_sz_GET_PLAYER, auth);
		
		if ((hQuery = SQL_Query(g_hThreadedDb, query)) == null)
		{
			if (SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError)))
			{
				LogError("[GET]%s", g_szSqlError);
			}
			else
			{
				LogError("[GET]Unspecified error occured.");
			}
			elo = g_cvDefaultElo.IntValue;
			matches = 0;
			return;
		}
		
		if (!SQL_FetchRow(hQuery))
		{
			if (SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError)))
			{
				LogError("[GET]%s", g_szSqlError);
			}
			else
			{
				LogError("[GET] Unspecified error occured. Rows deleted by outside actors?");
			}
			
			elo = g_cvDefaultElo.IntValue;
			matches = 0;
			return;
		}
		
		elo = SQL_FetchInt(hQuery, 1);
		matches = SQL_FetchInt(hQuery, 2);
		delete hQuery;
		return;
	}
	
	SQL_BindParamString(g_hGetElo, 0, auth, false);
	if (!SQL_Execute(g_hGetElo))
	{
		if (SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError)))
		{
			LogError("[GET]%s", g_szSqlError);
		}
		else
		{
			LogError("[GET] Unspecified error occured.");
		}
		elo = g_cvDefaultElo.IntValue;
		matches = 0;
	}
	
	if (!SQL_FetchRow(g_hGetElo))
	{
		if (SQL_GetError(g_hThreadedDb, g_szSqlError, sizeof(g_szSqlError)))
		{
			LogError("[GET]%s", g_szSqlError);
		}
		else
		{
			LogError("[GET] Unspecified error occured. Rows deleted by outside actors?");
		}
		
		elo = g_cvDefaultElo.IntValue;
		matches = 0;
		return;
	}

	elo = SQL_FetchInt(g_hGetElo, 1);
	matches = SQL_FetchInt(g_hGetElo, 2);
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