#include <sourcemod>
#include <get5>
#include <SteamWorks>
#include <smjansson>
#include <cstrike>
#include <sdktools>
#include <socket>

char g_sMatchID[38];
//ArrayList g_Players;
char g_sTeamName[4][128];

Database g_Database;
bool g_ClientReady[MAXPLAYERS + 1];         // Whether clients are marked ready.

ConVar g_MatchType;

Handle g_hSocket;
ConVar g_CVServerIp;
ConVar g_CVWebsocketPass;
ConVar g_CVLeagueID;

int g_connectTimer = 300;

StringMap g_NameMap;

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
	//Hook Event
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_changename", Event_NameChange);
	//HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("announce_phase_end", Event_Halftime);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_connect_full", Event_PlayerConnect);

	//Create ArrayList
	//g_Players = new ArrayList(32);

	//Register Cmd Listeners
	AddCommandListener(Listener_Pause, "sm_pause");
	AddCommandListener(Listener_Stop, "sm_stop");
	AddCommandListener(Listener_Stop, "sm_get5");
	AddCommandListener(Listener_Stop, "kill");
	//Create ConVar
	CreateConVar("sm_loadmatch_version", PLUGIN_VERSION, "Keeps track of version for stuff", FCVAR_PROTECTED);
	g_CVServerIp = CreateConVar("sqlmatch_websocket_ip", "127.0.0.1", "IP to connect to for sending match end messages.", FCVAR_PROTECTED);
	g_CVWebsocketPass = CreateConVar("sqlmatch_websocket_pass", "jf8u689shgfds", "pass for websocket");
	g_MatchType = CreateConVar("sm_matchtype", "5v5", "The match type which we are loading and checking the connection for.");
	AutoExecConfig(true, "loadmatch");

	g_hSocket = SocketCreate(SOCKET_TCP, OnSocketError);

	//Set Socket Options
	SocketSetOption(g_hSocket, SocketReuseAddr, 1);
	SocketSetOption(g_hSocket, SocketKeepAlive, 1);
	SocketSetOption(g_hSocket, DebugMode, 1); // Put socket into debug mode

	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();

	CreateTimer(1.0, Timer_ConnectionTimer, _, TIMER_REPEAT);
	CreateTimer(15.0, Timer_PlayerCount, _, TIMER_REPEAT);
	Database.Connect(SQL_InitialConnection, "sql_matches");

	g_NameMap = new StringMap();
}

public void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(Frame_PlayerConnect, event.GetInt("userid"));
}

public void CheckPlayerCount()
{
	if (Get5_GetGameState() == Get5State_None) {
		return;
	}

	char matchtype[32];
	GetConVarString(g_MatchType, matchtype, sizeof(matchtype));

	if (Get5_GetGameState() == Get5State_Warmup)
	{
		if (IsEveryoneReady()) 
		{
			PrintToChatAll("%s All players have connected. Match will start in 15 seconds.", ChatTag);
			EndWarmup(15);
			CreateTimer(10.0, Timer_StartMatch);
			return;
		}
		else
		{
			int playersonTerrorist = GetRealTeamCount(CS_TEAM_T);
			int playersOnCT = GetRealTeamCount(CS_TEAM_CT);
			int playersOnServer = playersonTerrorist+playersOnCT; 
			LogMessage("The amount of players in server are Terrorist: %i and CT: %i", playersonTerrorist, playersOnCT);
			if (StrEqual(matchtype, "5v5"))
			{
				PrintToChatAll("%s Waiting for %i more players to join the match...", ChatTag, 10 - playersOnServer);
			}

			if (StrEqual(matchtype, "2v2"))
			{
				PrintToChatAll("%s Waiting for %i more players to join the match...", ChatTag, 4 - playersOnServer);
			}

			if (StrEqual(matchtype, "1v1"))
			{
				PrintToChatAll("%s Waiting for %i more players to join the match...", ChatTag, 2 - playersOnServer);
			}
		}
	}
	return;
}

public void Frame_PlayerConnect(any data)
{
	int client = GetClientOfUserId(view_as<int>(data));
	if (client)
	{
		CheckPlayerCount();
	}
}

void ConnectRelay()
{	
	if (!SocketIsConnected(g_hSocket))
	{
		char sHost[32];
		g_CVServerIp.GetString(sHost, sizeof(sHost));
		SocketConnect(g_hSocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, sHost, 8888);
	}
	else
		PrintToServer("Socket is already connected?");
}

public Action Timer_Reconnect(Handle timer)
{
	ConnectRelay();
}

void StartReconnectTimer()
{
	if (SocketIsConnected(g_hSocket))
		SocketDisconnect(g_hSocket);
		
	CreateTimer(10.0, Timer_Reconnect);
}

public int OnSocketDisconnected(Handle socket, any arg)
{	
	StartReconnectTimer();
	
	PrintToServer("Socket disconnected");
}

public int OnSocketError(Handle socket, int errorType, int errorNum, any ary)
{
	StartReconnectTimer();
	
	LogError("Socket error %i (errno %i)", errorType, errorNum);
}

public int OnSocketConnected(Handle socket, any arg)
{	
	PrintToServer("Socket Successfully Connected");
}

public int OnSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
{
	PrintToServer(receiveData);
}

/* Core calculations */

public int FloatToInt(float fValue) {
	char cValue[300];
	FloatToString(fValue, cValue, sizeof(cValue));
	return StringToInt(cValue);
}

stock float GetWarmupStartTime()
{
	return GameRules_GetPropFloat("m_fWarmupPeriodStart");
}

stock float GetWarmupEndTime()
{
	return (GetWarmupStartTime() + GetConVarFloat(FindConVar("mp_warmuptime")));
}

stock float GetWarmupLeftTime()
{
	return (GetWarmupEndTime() - GetGameTime());
}

stock int GetRealClientCount() {
  int clients = 0;
  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i)) {
      clients++;
    }
  }
  return clients;
}

/* Initialise Warmup */
stock void StartWarmup(int warmupTime = 60) {
  ServerCommand("mp_do_warmup_period 1");
  ServerCommand("mp_warmuptime %d", warmupTime);
  ServerCommand("mp_warmup_start");
}

stock void EndWarmup(int time = 0) {
  if (time == 0) {
    ServerCommand("mp_warmup_end");
  } else {
    ServerCommand("mp_warmup_pausetimer 0");
    ServerCommand("mp_warmuptime %d", time);
  }
}

/* "Ready" system */
stock bool IsPlayer(int client) {
  return IsClientInGame(client) && !IsFakeClient(client);
}

public void SetClientReady(int client, bool ready) {
  g_ClientReady[client] = ready;
}

stock int GetRealTeamCount(int team)
{
    int number = 0;
    for (int i=1; i<=MaxClients; i++)
    {
        if (IsPlayer(i) && GetClientTeam(i) == team) 
            number++;
    }
    return number;
}  

public bool IsEveryoneReady() {
	char matchtype[32];
	GetConVarString(g_MatchType, matchtype, sizeof(matchtype));
	if (StrEqual(matchtype, "5v5"))
	{
		if (GetRealTeamCount(CS_TEAM_CT) == 5 && GetRealTeamCount(CS_TEAM_T) == 5) return true;	
	}

	else if (StrEqual(matchtype, "1v1"))
	{
		if (GetRealTeamCount(CS_TEAM_CT) == 1 && GetRealTeamCount(CS_TEAM_T) == 1) return true;
	}

	else if (StrEqual(matchtype, "2v2"))
	{
		if (GetRealTeamCount(CS_TEAM_CT) == 2 && GetRealTeamCount(CS_TEAM_T) == 2) return true; 
	}
	
	return false;
}

public void Event_NameChange(Event event, char[] name, bool dontBroadcast)
{
	int Client = GetClientOfUserId(event.GetInt("userid"));
	char sSteam[64], sOldName[MAX_NAME_LENGTH], sName[64];

	if(GetClientAuthId(Client, AuthId_SteamID64, sSteam, sizeof(sSteam)))
	{
		if(g_NameMap.GetString(sSteam, sName, sizeof(sName)))
		{
			if(GetClientName(Client, sOldName, sizeof(sOldName)))
			{
				if(!StrEqual(sOldName, sName))
				{
					UnhookEvent("player_changename", Event_NameChange);
					SetClientName(Client, sSteam);
					SetClientName(Client, sName);
					HookEvent("player_changename", Event_NameChange);
					return;
				}
			}
		}
	}
}

public void Event_RoundEnd(Event event, char[] name, bool dontBroadcast)
{
	LoadPlayerDiscordNames();
	FireNameChangeEvent(true);
}

// Need to look at merging Timer_ConnectionTimer and Timer_PlayerCount.
public Action Timer_ConnectionTimer(Handle timer) {
	if (Get5_GetGameState() == Get5State_None) {
		return Plugin_Continue;
	}

	if (Get5_GetGameState() <= Get5State_Warmup && Get5_GetGameState() != Get5State_None) {
    	if (GetRealClientCount() < 1) {
      		StartWarmup(g_connectTimer);
    	}
  	}

	if (Get5_GetGameState() == Get5State_Warmup) {
		if (!IsEveryoneReady()) {
			CheckWaitingTimes();
		}
	}
	return Plugin_Continue;
}

// Need to look at this.
public Action Timer_PlayerCount(Handle timer) {
	char matchtype[32];
	GetConVarString(g_MatchType, matchtype, sizeof(matchtype));

	if (Get5_GetGameState() == Get5State_Warmup)
	{
		if (IsEveryoneReady()) 
		{
			PrintToChatAll("%s All players have connected. Match will start in 15 seconds.", ChatTag);
			EndWarmup(15);
			CreateTimer(10.0, Timer_StartMatch);
			return Plugin_Stop;
		}
		else
		{
			int playersonTerrorist = GetRealTeamCount(CS_TEAM_T);
			int playersOnCT = GetRealTeamCount(CS_TEAM_CT);
			int playersOnServer = playersonTerrorist+playersOnCT; 
			LogMessage("The amount of players in server are Terrorist: %i and CT: %i", playersonTerrorist, playersOnCT);
			if (StrEqual(matchtype, "5v5"))
			{
				PrintToChatAll("%s Waiting for %i more players to join the match...", ChatTag, 10 - playersOnServer);
			}

			if (StrEqual(matchtype, "2v2"))
			{
				PrintToChatAll("%s Waiting for %i more players to join the match...", ChatTag, 4 - playersOnServer);
			}

			if (StrEqual(matchtype, "1v1"))
			{
				PrintToChatAll("%s Waiting for %i more players to join the match...", ChatTag, 2 - playersOnServer);
			}
		}
	}
	return Plugin_Continue;
}

static void CheckWaitingTimes() {
	//g_timeUsed++;

	if (!IsEveryoneReady() && Get5_GetGameState() != Get5State_None) {
		int timeLeft = FloatToInt(GetWarmupLeftTime());

		if (timeLeft <= 0) {
			ServerCommand("get5_endmatch");
			UpdateMatchStatus();
			for(int i = 1; i <= MaxClients; i++) {
				if(IsValidClient(i)) {
					KickClient(i, "Players did not connect in time. Match has been cancelled");
					EndMatchSocket();
				}
			}
		} else if (timeLeft <= 300 && timeLeft % 60 == 0) {
			Get5_MessageToAll("Time remaining to join the server: %i minutes.", timeLeft / 60);
		}
	}
} 

public void EndMatchSocket()
{
	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "UPDATE sql_matches_scoretotal SET live=0 WHERE match_id='%s' AND live=1;", g_sMatchID);
	g_Database.Query(SQL_GenericQuery, sQuery);

	char sData[1024], sPass[128];
	g_CVWebsocketPass.GetString(sPass, sizeof(sPass));

	Handle jsonObj = json_object();
	json_object_set_new(jsonObj, "type", json_integer(1));
	json_object_set_new(jsonObj, "match_id", json_string(g_sMatchID));
	json_object_set_new(jsonObj, "pass", json_string(sPass));
	json_dump(jsonObj, sData, sizeof(sData), 0, false, false, true);
	CloseHandle(jsonObj);

	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();

	LogMessage("Socket starting end message send...");
	SocketSend(g_hSocket, sData, sizeof(sData));
	LogMessage("Socket sending message: %s", sData);
}

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
}

public void CheckSetup()
{
	if(g_Database == null)
	{
		LogError("Database not connected.");
		return;
	}

	int ip[4];
	char sIP[32], sPort[32], sQuery[1024];
	FindConVar("hostport").GetString(sPort, sizeof(sPort));
	SteamWorks_GetPublicIP(ip);
	Format(sIP, sizeof(sIP), "%i.%i.%i.%i:%s", ip[0], ip[1], ip[2], ip[3], sPort);
	Format(sQuery, sizeof(sQuery), "SELECT `queues`.match_id, " ...
	"`queues`.team_1_name, `queues`.team_2_name, " ...
	"`queues`.team_1_flag, `queues`.team_2_flag, " ...
	"`queues`.map, `queue_players`.team, " ...
	"`queue_players`.steamid " ...
	"FROM `queues` INNER JOIN `queue_players` ON `queue_players`.match_id = `queues`.match_id WHERE server='%s' AND status=1;", sIP);
	g_Database.Query(SQL_SelectSetup, sQuery);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Get5_GetTeamName", Native_Get5_GetTeamName);
	CreateNative("GetCurrentMatchId", Native_GetCurrentMatchId);
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

public bool OnClientConnect(int Client, char[] rejectMsg, int maxLen)
{
		if(Get5_GetGameState() == Get5State_None)
		{
			CheckSetup();
		}
		return true;
}

public void OnClientAuthorized(int Client, const char[] auth)
{
	if(Get5_GetPlayerTeam(auth) != MatchTeam_TeamNone) return;

	if(StrEqual(g_sMatchID, ""))
	{
		// Retry in a few sec
		CreateTimer(5.0, Timer_RetryPlayerCheck, GetClientUserId(Client));
		return;
	}

	// Check if player is in queues table
	char sSteamID[64], sQuery[256];
	GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID))
	Format(sQuery, sizeof(sQuery), "SELECT team FROM queue_players WHERE steamid='%s' AND match_id='%s'", sSteamID, g_sMatchID);
	g_Database.Query(SQL_PlayerCheck, sQuery, GetClientUserId(Client));
}

public Action Timer_RetryPlayerCheck(Handle timer, int userid)
{
	int Client = GetClientOfUserId(userid);
	if(!IsValidClient(Client) || StrEqual(g_sMatchID, "")) return Plugin_Handled;

	// Check if player is in queues table
	char sSteamID[64], sQuery[256];
	GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID))
	Format(sQuery, sizeof(sQuery), "SELECT team, steamid FROM queue_players WHERE steamid='%s' AND match_id='%s'", sSteamID, g_sMatchID);
	g_Database.Query(SQL_PlayerCheck, sQuery);
	return Plugin_Handled;
}

public void SQL_PlayerCheck(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	if(!results.FetchRow()) return;

	int teamCol, steamCol;
	results.FieldNameToNum("team", teamCol);
	results.FieldNameToNum("steamid", steamCol);

	MatchTeam team;
	if(results.FetchInt(teamCol) == 0)
		team = MatchTeam_Team1;
	else
		team = MatchTeam_Team2;

	char sSteam[64];
	results.FetchString(steamCol, sSteam, sizeof(sSteam));
	Get5_AddPlayerToTeam(sSteam, team);
}

public void OnClientPostAdminCheck(int Client)
{
	if (!IsValidClient(Client) || Get5_GetGameState() != Get5State_Warmup) return;
	
	
	// Set player name to discord name if it isn't set already
	char sSteam[64], sOldName[MAX_NAME_LENGTH], sName[64];
	if(GetClientAuthId(Client, AuthId_SteamID64, sSteam, sizeof(sSteam)))
	{
		if(g_NameMap.GetString(sSteam, sName, sizeof(sName)))
		{
			if(GetClientName(Client, sOldName, sizeof(sOldName)))
			{
				if(!StrEqual(sOldName, sName))
				{
					SetClientName(Client, sSteam);
					SetClientName(Client, sName);
				}
			}
		}
	}

	
	updateIPAddress(Client);
	SetClientReady(Client, true);
}

void FireNameChangeEvent(bool allPlayers = false, int userid = -1)
{
	if(allPlayers)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i)) continue;

			Event hSetNameEvent = CreateEvent("player_changename");
			if(hSetNameEvent == INVALID_HANDLE)
			{
				LogError("Failed to create name change event: Event isn't being hooked.");
				return;
			}

			hSetNameEvent.SetInt("userid", GetClientUserId(i));
			hSetNameEvent.Fire();
		}
		return;
	}

	if(userid == -1) return;

	Event hSetNameEvent = CreateEvent("player_changename");
	if(hSetNameEvent == INVALID_HANDLE)
	{
		LogError("Failed to create name change event: Event isn't being hooked.");
		return;
	}

	hSetNameEvent.SetInt("userid", userid);
	hSetNameEvent.Fire();
}

public void OnClientDisconnect(int Client) {
	if(!IsValidClient(Client) || Get5_GetGameState() != Get5State_Warmup) return;
	SetClientReady(Client, false);
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

public void SQL_SelectSetup(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	// Game is already started
	if(Get5_GetGameState() != Get5State_None) return;

	if(!results.FetchRow()) return;
	
	int matchIdCol;
	results.FieldNameToNum("match_id", matchIdCol);
	results.FetchString(matchIdCol, g_sMatchID, sizeof(g_sMatchID));

	int team1NameCol, team2NameCol, team1FlagCol, team2FlagCol, mapCol, teamCol, steamCol;
	results.FieldNameToNum("team_1_name", team1NameCol);
	results.FieldNameToNum("team_2_name", team2NameCol);
	results.FieldNameToNum("team_1_flag", team1FlagCol);
	results.FieldNameToNum("team_2_flag", team2FlagCol);
	results.FieldNameToNum("map", mapCol);
	results.FieldNameToNum("team", teamCol);
	results.FieldNameToNum("steamid", steamCol);

	char sTeamName1[33], sTeamName2[33], sTeamFlag1[17], sTeamFlag2[17], sMap[33];
	results.FetchString(team1NameCol, sTeamName1, sizeof(sTeamName1));
	results.FetchString(team2NameCol, sTeamName2, sizeof(sTeamName2));
	results.FetchString(team1FlagCol, sTeamFlag1, sizeof(sTeamFlag1));
	results.FetchString(team2FlagCol, sTeamFlag2, sizeof(sTeamFlag2));
	results.FetchString(mapCol, sMap, sizeof(sMap));

	Format(g_sTeamName[2], sizeof(g_sTeamName[]), "%s", sTeamName1);
	Format(g_sTeamName[3], sizeof(g_sTeamName[]), "%s", sTeamName2);

	Handle jsonObj = json_object();
	Handle mapArray = json_array();
	Handle teamOne = json_object();
	Handle teamTwo = json_object();
	Handle teamOnePlayers = json_array();
	Handle teamTwoPlayers = json_array();
	char steamID[64];

	do
	{
		int team = results.FetchInt(teamCol);
		results.FetchString(steamCol, steamID, sizeof(steamID));

		if(team == 1)
			json_array_append(teamOnePlayers, json_string(steamID));
		else if(team == 2)
			json_array_append(teamTwoPlayers, json_string(steamID));
	} while(results.FetchRow());

	json_object_set_new(teamOne, "name", json_string(sTeamName1));
	json_object_set_new(teamOne, "flag", json_string(sTeamFlag1));
	json_object_set_new(teamOne, "players", teamOnePlayers);

	json_object_set_new(teamTwo, "name", json_string(sTeamName2));
	json_object_set_new(teamTwo, "flag", json_string(sTeamFlag2));
	json_object_set_new(teamTwo, "players", teamTwoPlayers);

	json_object_set_new(jsonObj, "matchid", json_string(g_sMatchID));
	json_object_set_new(jsonObj, "num_maps", json_integer(1));
	json_object_set_new(jsonObj, "skip_veto", json_true());
	json_array_append(mapArray, json_string(sMap));
	json_object_set_new(jsonObj, "maplist", mapArray);
	json_object_set_new(jsonObj, "team1", teamOne);
	json_object_set_new(jsonObj, "team2", teamTwo);

	char sPath[255];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/get5_match.json");
	json_dump_file(jsonObj, sPath);
	CloseHandle(jsonObj);

	if(Get5_LoadMatchConfig(sPath))
	{
		UpdateMatchStatus();
		DeleteFile(sPath);
		g_NameMap.Clear();
	}
	else
		LogError("Failed to load match config from file.");

	LoadPlayerDiscordNames();
}

public void LoadPlayerDiscordNames()
{
	char sQuery[256];
	Format(sQuery, sizeof(sQuery), "SELECT p.steamid, c.name FROM discord_caching c INNER JOIN discord_auth a ON c.discordid = a.discordid INNER JOIN queue_players p ON a.steamid = p.steamid AND p.match_id='%s';", g_sMatchID);
	g_Database.Query(SQL_LoadPlayerDiscordNamesCallback, sQuery);
}

public void SQL_LoadPlayerDiscordNamesCallback(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	if(!results.FetchRow()) return;

	int steamCol, nameCol;
	results.FieldNameToNum("steamid", steamCol);
	results.FieldNameToNum("name", nameCol);

	char sSteam[64], sName[64];
	do
	{
		results.FetchString(steamCol, sSteam, sizeof(sSteam));
		results.FetchString(nameCol, sName, sizeof(sName));
		// Get5_SetPlayerName(sSteam, sName);
		g_NameMap.SetString(sSteam, sName, true);
	}
	while(results.FetchRow());
}

public void Get5_OnSeriesResult(MatchTeam seriesWinner, int team1MapScore, int team2MapScore)
{
	UpdateMatchStatus();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int Client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsValidClient(Client)) return;
	if (GameRules_GetProp("m_bMatchWaitingForResume") != 0 && GameRules_GetProp("m_bFreezePeriod") == 1)
		CS_RespawnPlayer(Client);
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
	Format(sQuery, sizeof(sQuery), "UPDATE queues SET status=0 WHERE match_id='%s'", g_sMatchID);
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
	if(client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;
	return true;
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

public int Native_GetCurrentMatchId(Handle plugin, int numParams)
{
	if(StrEqual(g_sMatchID, ""))
		return ThrowNativeError(SP_ERROR_NATIVE, "Match ID is not set.");

	SetNativeString(1, g_sMatchID, sizeof(g_sMatchID));
	return 1;
}