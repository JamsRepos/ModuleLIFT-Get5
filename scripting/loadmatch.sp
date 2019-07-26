#include <sourcemod>
#include <get5>
#include <SteamWorks>
#include <smjansson>
#include <cstrike>
#include <sdktools>


int g_iMatchID = 0;
//ArrayList g_Players;
char g_sTeamName[4][128];

Database g_Database;

#define ChatTag			"[SM]"
#define PLUGIN_VERSION	"1.1.0"

public Plugin myinfo = 
{
	name = "Load Match",
	author = "DN.H | The Doggy",
	description = "Creates Get5 Matches",
	version = PLUGIN_VERSION,
	url = "DistrictNine.Host"
};

public void OnPluginStart()
{
	Database.Connect(SQL_InitialConnection, "sql_matches");
	//Hook Event
	HookEvent("player_death", Event_PlayerDeath);
	//HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("announce_phase_end", Event_Halftime);

	//Create ArrayList
	//g_Players = new ArrayList(32);

	//Register Cmd Listeners
	AddCommandListener(Listener_Pause, "sm_pause");
	AddCommandListener(Listener_Stop, "sm_stop");
	AddCommandListener(Listener_Stop, "sm_get5");
	AddCommandListener(Listener_Stop, "kill");
	//AddCommandListener(Listener_Unpause, "sm_unpause");
	AddCommandListener(Listener_Ready, "sm_ready");

	//Create ConVar
	CreateConVar("sm_loadmatch_version", PLUGIN_VERSION, "Keeps track of version for stuff", FCVAR_PROTECTED);
}

// public Action AttemptMySQLConnection(Handle timer)
// {
// 	if (g_Database != null)
// 	{
// 		delete g_Database;
// 		g_Database = null;
// 	}
// 	Database.Connect(SQL_InitialConnection, "sql_matches");
// 	return Plugin_Stop;
// }

public void SQL_InitialConnection(Database db, const char[] sError, int data)
{
	if (db == null)
	{
		LogMessage("Database Error: %s", sError);
		return;
	}
	
	char sDriver[16];
	db.Driver.GetIdentifier(sDriver, sizeof(sDriver));
	if (StrEqual(sDriver, "mysql", false)) LogMessage("MySQL Database: connected");
	
	g_Database = db;
	int ip[4];
	char sIP[32], sPort[32], sQuery[1024];
	FindConVar("hostport").GetString(sPort, sizeof(sPort));
	SteamWorks_GetPublicIP(ip);
	Format(sIP, sizeof(sIP), "%i.%i.%i.%i:%s", ip[0], ip[1], ip[2], ip[3], sPort);
	Format(sQuery, sizeof(sQuery), "SELECT * FROM get5_matchsetup WHERE server='%s' AND status=4 ORDER BY id DESC LIMIT 1;", sIP);
	g_Database.Query(SQL_SelectSetup, sQuery);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Get5_GetTeamName", Native_Get5_GetTeamName);
	return APLRes_Success;
}

public Action Timer_StartMatch(Handle timer)
{
	PrintToChatAll("%s Match has been started.", ChatTag);
	ServerCommand("get5_forceready");
}

public void updateIPAddress(int Client)
{
	char sSteamID[64], sIP[32], sQuery[1024];
	GetClientIP(Client, sIP, sizeof(sIP));
	GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	Format(sQuery, sizeof(sQuery), "UPDATE discord_auth SET ip='%s' WHERE steamid='%s'", sIP, sSteamID);
	g_Database.Query(SQL_GenericQuery, sQuery);

}

public void OnClientPutInServer(int Client)
{
	if(!IsValidClient(Client) || Get5_GetGameState() != Get5State_Warmup) return;
	updateIPAddress(Client);
	int iCount;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i)) continue;
		iCount++;
	}

	if(iCount >= 10)
	{
		PrintToChatAll("%s All players have connected. Match will start in 30 seconds.", ChatTag);
		CreateTimer(30.0, Timer_StartMatch);
	}
	else
		PrintToChatAll("%s Waiting for %i more players to join the match...", ChatTag, 10 - iCount);
}

public Action Listener_Pause(int Client, const char[] sCommand, int argc)
{
	if(Get5_GetGameState() <= Get5State_KnifeRound) return Plugin_Stop;

	return Plugin_Continue;
}

public Action Listener_Stop(int Client, const char[] sCommand, int argc)
{
	return Plugin_Stop;
}

public Action Listener_Ready(int Client, const char[] sCommand, int argc)
{
	if(!IsValidClient(Client)) return Plugin_Handled;

	PrintToChat(Client, "%s Please wait for all players to join the match.", ChatTag);
	return Plugin_Stop;
}

// public void AttemptMySQLConnection(Database db, const char[] error, any data)
// {
//     if (db == null)
//     {
//         SetFailState("Could not connect to db: %s", error);
// 		return;
//     }

//     g_Database = db;
//     int ip[4];
// 	char sIP[32], sPort[32], sQuery[1024];
// 	FindConVar("hostport").GetString(sPort, sizeof(sPort));
// 	SteamWorks_GetPublicIP(ip);
// 	Format(sIP, sizeof(sIP), "%i.%i.%i.%i:%s", ip[0], ip[1], ip[2], ip[3], sPort);
//     Format(sQuery, sizeof(sQuery), "SELECT * FROM get5_matchsetup WHERE server='%s' AND status=4 ORDER BY id DESC LIMIT 1;", sIP);
// 	g_Database.Query(SQL_SelectSetup, sQuery);
// }

public void SQL_SelectSetup(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	if(!results.FetchRow()) return;

	int idCol;
	results.FieldNameToNum("id", idCol);
	int id = results.FetchInt(idCol);
	if(id <= g_iMatchID) return;

	if(g_iMatchID > 0 && Get5_GetGameState() != Get5State_None)
	{
		ServerCommand("get5_endmatch");
		UpdateMatchStatus();
	}

	g_iMatchID = id;
	int team1NameCol, team2NameCol, team1PlayersCol, team2PlayersCol, team1FlagCol, team2FlagCol, mapCol, specCol;
	results.FieldNameToNum("team_1_name", team1NameCol);
	results.FieldNameToNum("team_2_name", team2NameCol);
	results.FieldNameToNum("team_1_players", team1PlayersCol);
	results.FieldNameToNum("team_2_players", team2PlayersCol);
	results.FieldNameToNum("team_1_flag", team1FlagCol);
	results.FieldNameToNum("team_2_flag", team2FlagCol);
	results.FieldNameToNum("map", mapCol);
	results.FieldNameToNum("spectators", specCol);

	char sTeamName1[128], sTeamName2[128], sTeamPlayers1[512], sTeamPlayers2[512], sSpectators[512], sTeamFlag1[16], sTeamFlag2[16], sMap[128], sTeam1Players[5][64], sTeam2Players[5][64], sSpectatorsList[30][64];
	results.FetchString(team1NameCol, sTeamName1, sizeof(sTeamName1));
	results.FetchString(team2NameCol, sTeamName2, sizeof(sTeamName2));
	results.FetchString(team1PlayersCol, sTeamPlayers1, sizeof(sTeamPlayers1));
	results.FetchString(team2PlayersCol, sTeamPlayers2, sizeof(sTeamPlayers2));
	results.FetchString(specCol, sSpectators, sizeof(sSpectators));
	results.FetchString(team1FlagCol, sTeamFlag1, sizeof(sTeamFlag1));
	results.FetchString(team2FlagCol, sTeamFlag2, sizeof(sTeamFlag2));
	results.FetchString(mapCol, sMap, sizeof(sMap));

	if(StrEqual(sTeamPlayers1, "") || StrEqual(sTeamPlayers2, "")) return;

	Format(g_sTeamName[2], sizeof(g_sTeamName[]), "%s", sTeamName1);
	Format(g_sTeamName[3], sizeof(g_sTeamName[]), "%s", sTeamName2);

	ExplodeString(sTeamPlayers1, "-", sTeam1Players, sizeof(sTeam1Players), sizeof(sTeam1Players[]));
	ExplodeString(sTeamPlayers2, "-", sTeam2Players, sizeof(sTeam2Players), sizeof(sTeam2Players[]));
	ExplodeString(sSpectators, "-", sSpectatorsList, sizeof(sSpectatorsList), sizeof(sSpectatorsList[]));

	ArrayList Team1Players = new ArrayList(64);
	ArrayList Team2Players = new ArrayList(64);
	ArrayList Spectators = new ArrayList(64);

	for(int i = 0; i < 5; i++)
	{
		if(!StrEqual(sTeam1Players[i], ""))
			Team1Players.PushString(sTeam1Players[i]);
	}

	for(int i = 0; i < 5; i++)
	{
		if(!StrEqual(sTeam2Players[i], ""))
			Team2Players.PushString(sTeam2Players[i]);
	}

	for(int i = 0; i < 30; i++)
	{
		if(!StrEqual(sSpectatorsList[i], ""))
			Spectators.PushString(sSpectatorsList[i]);
	}

	/*for(int i = 0; i < 5; i++)
	{
		if(!StrEqual(sTeamPlayers1[i], ""))
			g_Players.PushString(sTeam1Players[i]);

		if(!StrEqual(sTeamPlayers2[i], ""))
			g_Players.PushString(sTeam2Players[i]);
	}*/

/*
	KeyValues kv = new KeyValues("Match");
	kv.SetString("matchid", id);
	kv.SetString("num_maps", "1");

	kv.JumpToKey("spectators", true);
	kv.JumpToKey("players", true);
	for(int i = 0; i < Spectators.Length; i++)
	{
		char steamID[64];
		Spectators.GetString(i, steamID, sizeof(steamID));
		kv.SetString(steamID, " ");
	}
	kv.Rewind();

	kv.JumpToKey("maplist", true);
	kv.SetString(sMap, " ");
	kv.Rewind();

	kv.JumpToKey("team1", true);
	kv.SetString("name", sTeamName1);
	kv.SetString("flag", sTeamFlag1);

	kv.JumpToKey("players", true);
	for(int i = 0; i < Team1Players.Length; i++)
	{
		char steamID[64];
		Team1Players.GetString(i, steamID, sizeof(steamID));
		kv.SetString(steamID, " ");
	}
	kv.Rewind();

	kv.JumpToKey("team2", true);
	kv.SetString("name", sTeamName2);
	kv.SetString("flag", sTeamFlag2);

	kv.JumpToKey("players", true);
	for(int i = 0; i < Team2Players.Length; i++)
	{
		char steamID[64];
		Team2Players.GetString(i, steamID, sizeof(steamID));
		kv.SetString(steamID, " ");
	}
	kv.Rewind();

	char sPath[255];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/get5_match.cfg");
	kv.ExportToFile(sPath);
	delete kv;
*/
	Handle jsonObj = json_object();
	Handle mapArray = json_array();
	Handle teamOne = json_object();
	Handle teamTwo = json_object();
	Handle teamSpectators = json_object();
	Handle teamOnePlayers = json_array();
	Handle teamTwoPlayers = json_array();
	Handle SpectatorPlayers = json_array();
	char steamID[64];

	for(int i = 0; i < Team1Players.Length; i++)
	{
		Team1Players.GetString(i, steamID, sizeof(steamID));
		json_array_append(teamOnePlayers, json_string(steamID));
	}

	for(int i = 0; i < Team2Players.Length; i++)
	{
		Team2Players.GetString(i, steamID, sizeof(steamID));
		json_array_append(teamTwoPlayers, json_string(steamID));
	}

	for(int i = 0; i < Spectators.Length; i++)
	{
		Spectators.GetString(i, steamID, sizeof(steamID));
		json_array_append(SpectatorPlayers, json_string(steamID));
	}

	json_object_set_new(teamOne, "name", json_string(sTeamName1));
	json_object_set_new(teamOne, "flag", json_string(sTeamFlag1));
	json_object_set_new(teamOne, "players", teamOnePlayers);

	json_object_set_new(teamTwo, "name", json_string(sTeamName2));
	json_object_set_new(teamTwo, "flag", json_string(sTeamFlag2));
	json_object_set_new(teamTwo, "players", teamTwoPlayers);

	json_object_set_new(teamSpectators, "players", SpectatorPlayers);

	json_object_set_new(jsonObj, "matchid", json_integer(id));
	json_object_set_new(jsonObj, "num_maps", json_integer(1));
	json_object_set_new(jsonObj, "skip_veto", json_true());
	json_array_append(mapArray, json_string(sMap));
	json_object_set_new(jsonObj, "maplist", mapArray);
	json_object_set_new(jsonObj, "team1", teamOne);
	json_object_set_new(jsonObj, "team2", teamTwo);
	json_object_set_new(jsonObj, "spectators", teamSpectators);

	char sPath[255];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/get5_match.json");
	json_dump_file(jsonObj, sPath);
	CloseHandle(jsonObj);

	if(Get5_LoadMatchConfig(sPath))
	{
		UpdateMatchStatus();
		CreateTimer(1.0, Timer_IdleCheck, _, TIMER_REPEAT);
		DeleteFile(sPath);
	}
}

public Action Timer_IdleCheck(Handle timer)
{
    if(Get5_GetGameState() == Get5State_KnifeRound) return Plugin_Stop;

    static int iTime = 0;
    iTime++;

    if(iTime >= 600)
    {
        ServerCommand("get5_endmatch");
        UpdateMatchStatus();

        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsValidClient(i))
                KickClient(i, "Players did not ready up in time");
        }
    }

    return Plugin_Continue;
}

public void Get5_OnMapResult(const char[] map, MatchTeam mapWinner, int team1Score, int team2Score, int mapNumber)
{
	UpdateMatchStatus();
}

/*public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if(Get5_GetGameState() == Get5State_None) return;

	for(int i = 0; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			char sSteam64[32];
			if(!GetClientAuthId(i, AuthId_SteamID64, sSteam64, sizeof(sSteam64))) continue;

			for(int j = 0; j < g_Players.Length; j++)
			{
				char sCurrent[32];
				g_Players.GetString(j, sCurrent, sizeof(sCurrent));
				LogMessage("g_Players.GetString(%i) = %s", j, sCurrent);

				if(StrEqual(sCurrent, sSteam64))
				{
					g_Players.Erase(j);
					if(g_Players.Length >= 1)
						PrintToChatAll("[LoadMatch] Waiting for %i more players to join the match.", g_Players.Length);
					else
					{
						PrintToChatAll("[LoadMatch] All players have joined, starting match...");
						ServerCommand("get5_forceready");
					}
				}
			}
		}
	}
}*/

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int Client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsValidClient(Client)) return;
	if (GameRules_GetProp("m_bMatchWaitingForResume") != 0 && GameRules_GetProp("m_bFreezePeriod") == 1)
		CS_RespawnPlayer(Client);

	// if(GameRules_GetProp("m_bTerroristTimeOutActive") != 0 || GameRules_GetProp("m_bCTTimeOutActive") != 0)
	// 	CS_RespawnPlayer(Client);
}

public void Event_Halftime(Event event, const char[] name, bool dontBroadcast)
{
	char oldNameT[128], oldNameCT[128];
	Format(oldNameT, sizeof(oldNameT), "%s", g_sTeamName[2]);
	Format(oldNameCT, sizeof(oldNameCT), "%s", g_sTeamName[3]);

	g_sTeamName[2] = oldNameCT;
	g_sTeamName[3] = oldNameT;
}

public void UpdateMatchStatus()
{
	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "UPDATE get5_matchsetup SET status=1 WHERE id=%i", g_iMatchID);
	g_Database.Query(SQL_GenericQuery, sQuery);
}

//generic query handler
public void SQL_GenericQuery(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}
}

stock bool IsValidClient(int client)
{
	if (client >= 1 && 
	client <= MaxClients &&
	IsClientConnected(client) &&  
	IsClientInGame(client) &&
	!IsFakeClient(client))
		return true;
	return false;
}

public int Native_Get5_GetTeamName(Handle plugin, int numParams)
{
	int team = GetNativeCell(1);
	int maxLen = GetNativeCell(3);
	if(maxLen <= 0) return 0;

	if(team < 2 || team > 3)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid team index (%d)", team);

	char[] sName = new char[maxLen];
	Format(sName, maxLen, "%s", g_sTeamName[team]);

	SetNativeString(2, sName, maxLen);
	return 1;
}