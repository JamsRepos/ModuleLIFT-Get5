#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <SteamWorks>
#include <smjansson>
#include <get5>
#include <socket>

#pragma semicolon 1
#pragma newdecls required

#define PREFIX		"[SM]"

Database g_Database = null;

int g_iShotsFired[MAXPLAYERS + 1] = 0;
int g_iShotsHit[MAXPLAYERS + 1] = 0;
int g_iHeadshots[MAXPLAYERS + 1] = 0;
int g_iMatchID;

bool g_bLoadMatchAvailable;
bool g_alreadySwapped;

Handle g_hSocket;

ConVar g_CVSiteURL;
ConVar g_CVEmbedColour;
ConVar g_CVEmbedAvatar;
ConVar g_CVServerIp;
ConVar g_CVWebsocketPass;

ArrayList ga_sWinningPlayers;
ArrayList ga_iEndMatchVotesT;
ArrayList ga_iEndMatchVotesCT;

/*enum AllowedTeamStatus
{
	NOT_AUTHORIZED = 0,
	TEAM_SPEC,
	TEAM_T,
	TEAM_CT,
	TEAM_ANY
};

AllowedTeamStatus g_eAllowedTeam[MAXPLAYERS + 1] = NOT_AUTHORIZED;*/

public Plugin myinfo = 
{
	name = "SQL Matches",
	author = "DN.H | The Doggy",
	description = "Sends match stats for the current match to a database",
	version = "1.3.1",
	url = "DistrictNine.Host"
};

public void OnPluginStart()
{

    Database.Connect(AttemptMySQLConnection, "sql_matches"); /* This has changed  */
	//Create Timer
	// CreateTimer(1.0, AttemptMySQLConnection);

	//Hook Events
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("weapon_fire", Event_WeaponFired);
	HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("announce_phase_end", Event_HalfTime); /* This has changed  */

	//ConVars
	g_CVSiteURL = CreateConVar("sm_site_url", "", "Website url for viewing scores", FCVAR_PROTECTED);
	g_CVEmbedColour = CreateConVar("sm_embed_color", "16741688", "Color to use for webhook (Must be decimal value)", FCVAR_PROTECTED);
	g_CVEmbedAvatar = CreateConVar("sm_embed_avatar", "https://i.imgur.com/Y0J4yzv.png", "Avatar to use for webhook", FCVAR_PROTECTED);
	g_CVServerIp = CreateConVar("sqlmatch_websocket_ip", "127.0.0.1", "IP to connect to for sending match end messages.", FCVAR_PROTECTED);
	g_CVWebsocketPass = CreateConVar("sqlmatch_websocket_pass", "jf8u689shgfds", "pass for websocket");
	
	//Initalize ArrayLists
	ga_sWinningPlayers = new ArrayList(64);
	ga_iEndMatchVotesT = new ArrayList();
	ga_iEndMatchVotesCT = new ArrayList();

	//Register Command
	RegConsoleCmd("sm_gg", Command_EndMatch, "Ends the match once everyone on the team has used it.");

	//Register Command Listeners
	/*AddCommandListener(Command_JoinTeam, "jointeam");
	AddCommandListener(Command_JoinTeam, "joingame");*/

	//Create Socket
	g_hSocket = SocketCreate(SOCKET_TCP, OnSocketError);

	//Set Socket Options
	SocketSetOption(g_hSocket, SocketReuseAddr, 1);
	SocketSetOption(g_hSocket, SocketKeepAlive, 1);

	//Connect Socket
	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();
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
	PrintToServer("Successfully Connected");
}

public int OnSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
{
	PrintToServer(receiveData);
}

public void OnMapStart()
{
	ga_iEndMatchVotesT.Clear();
	ga_iEndMatchVotesCT.Clear();

	if(Get5_GetGameState() == Get5State_Live)
		ServerCommand("get5_endmatch");
}

public void ResetVars(int Client)
{
	if(!IsValidClient(Client)) return;
	g_iShotsFired[Client] = 0;
	g_iShotsHit[Client] = 0;
	g_iHeadshots[Client] = 0;
}

/* This has changed */
public void AttemptMySQLConnection(Database db, const char[] error, any data)
{
    if (db == null)
    {
        SetFailState("Could not connect to db: %s", error);
        return;
    }
    g_Database = db;
}

/* This has changed */
public void Get5_OnGameStateChanged(Get5State oldState, Get5State newState)
{
	if(oldState == Get5State_GoingLive && newState == Get5State_Live)
	{
		char sQuery[1024], sMap[64];
		GetCurrentMap(sMap, sizeof(sMap));
		for(int i = 1; i <= MaxClients; i++)
			if(IsValidClient(i, true))
				ResetVars(i);
        
        int teamIndex_T = -1, teamIndex_CT = -1;

        int index = -1;
        while ((index = FindEntityByClassname(index, "cs_team_manager")) != -1)
        {
            int teamNum = GetEntProp(index, Prop_Send, "m_iTeamNum");
            if (teamNum == CS_TEAM_T)
            {
                teamIndex_T = index;
            }
            else if (teamNum == CS_TEAM_CT)
            {
                teamIndex_CT = index;
            }
        }
   
        char teamName_T[32];
        GetEntPropString(teamIndex_T, Prop_Send, "m_szClanTeamname", teamName_T, 32);
        char teamName_CT[32];
        GetEntPropString(teamIndex_CT, Prop_Send, "m_szClanTeamname", teamName_CT, 32);

		int ip[4];
		char pieces[4][8], sIP[32], sPort[32];
		FindConVar("hostport").GetString(sPort, sizeof(sPort));
		SteamWorks_GetPublicIP(ip);

		IntToString(ip[0], pieces[0], sizeof(pieces[]));
		IntToString(ip[1], pieces[1], sizeof(pieces[]));
		IntToString(ip[2], pieces[2], sizeof(pieces[]));
		IntToString(ip[3], pieces[3], sizeof(pieces[]));
		Format(sIP, sizeof(sIP), "%s.%s.%s.%s:%s", pieces[0], pieces[1], pieces[2], pieces[3], sPort);


		Format(sQuery, sizeof(sQuery), "INSERT INTO sql_matches_scoretotal (team_t, team_ct,team_1_name,team_2_name, map, live, server) VALUES (%i, %i,'%s','%s', '%s', 1, '%s');", CS_GetTeamScore(CS_TEAM_T), CS_GetTeamScore(CS_TEAM_CT),teamName_T,teamName_CT, sMap, sIP);
		g_Database.Query(SQL_InitialInsert, sQuery);
		UpdatePlayerStats();
	}
}

public void SQL_InitialInsert(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "SELECT LAST_INSERT_ID() as ID;");
	g_Database.Query(SQL_MatchIDQuery, sQuery);
}
public void SQL_MatchIDQuery(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("Fetching Match ID Failed due to Error: %s");
		LogError("Fetching Match ID Failed due to Error: %s");
		return;
	}

	if(!results.FetchRow()) 
	{
		LogError("Retrieving Match ID returned no rows.");
		return;
	}

	int iCol;
	results.FieldNameToNum("ID", iCol);
	g_iMatchID = results.FetchInt(iCol);
	ServerCommand("tv_record %i", g_iMatchID);
}

public void Get5_OnMapResult(const char[] map, MatchTeam mapWinner, int team1Score, int team2Score, int mapNumber)
{
	static float fTime;
	if(GetGameTime() - fTime < 1.0) return;
	fTime = GetGameTime();

	UpdatePlayerStats();
	UpdateMatchStats();
	SendReport();
	
	CreateTimer(10.0, Timer_KickEveryoneEnd); // Delay kicking everyone so they can see the chat message and so the plugin has time to update their stats

	char sData[1024], sPort[16], sQuery[1024], sEncodedData[1024], sIP[32], sPass[128];
	int ip[4];
	FindConVar("hostport").GetString(sPort, sizeof(sPort));
	SteamWorks_GetPublicIP(ip);
	Format(sIP, sizeof(sIP), "%i.%i.%i.%i:%s", ip[0], ip[1], ip[2], ip[3], sPort);
	g_CVWebsocketPass.GetString(sPass, sizeof(sPass));

	Handle jsonObj = json_object();
	json_object_set_new(jsonObj, "type", json_integer(1));
	json_object_set_new(jsonObj, "server", json_string(sIP));
	json_object_set_new(jsonObj, "matchid", json_integer(g_iMatchID));
	json_object_set_new(jsonObj, "pass", json_string(sPass));
	json_dump(jsonObj, sData, sizeof(sData), 0, false, false, true);
	CloseHandle(jsonObj);
	
	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();

	SocketSend(g_hSocket, sData, sizeof(sData));

	/* {"type":1,"server":"ip:port","matchid": "135"} */

	Format(sQuery, sizeof(sQuery), "UPDATE sql_matches_scoretotal SET live=0 WHERE server='%s' AND live=1;", sIP);
	g_Database.Query(SQL_GenericQuery, sQuery);
}

/*public Action Command_JoinTeam(int Client, char[] sCommand, int iArgs)
{
	if(!IsValidClient(Client)) return Plugin_Handled;

	if(Get5_GetGameState() == Get5State_GoingLive) return Plugin_Handled;

	if(Get5_GetGameState() != Get5State_Live) return Plugin_Continue;

	if(g_eAllowedTeam[Client] == NOT_AUTHORIZED)
	{
		PrintToChat(Client, "%s Your team authorization status is still loading. Please try again in a moment.", PREFIX);
		return Plugin_Handled;
	}

	if(GetClientTeam(Client) == 1 || GetClientTeam(Client) == 2 || GetClientTeam(Client) == 3) return Plugin_Handled;

	char sTeamName[32];
	GetCmdArg(1, sTeamName, sizeof(sTeamName)); // Get Team Name
	int iTeam = StringToInt(sTeamName);

	if(iTeam == 0 && g_eAllowedTeam[Client] != TEAM_ANY) // Auto join
		return Plugin_Handled;
	else if(iTeam == 1 && (g_eAllowedTeam[Client] != TEAM_ANY && g_eAllowedTeam[Client] != TEAM_SPEC))
		return Plugin_Handled;
	else if(iTeam == 2 && (g_eAllowedTeam[Client] != TEAM_ANY && g_eAllowedTeam[Client] != TEAM_T))
		return Plugin_Handled;
	else if(iTeam == 3 && (g_eAllowedTeam[Client] != TEAM_ANY && g_eAllowedTeam[Client] != TEAM_CT))
		return Plugin_Handled;
	else
	{
		CS_SwitchTeam(Client, iTeam);
		return Plugin_Continue;
	}
}

public Action Command_JoinGame(int Client, char[] sCommand, int iArgs)
{
	return Plugin_Handled;
}*/

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	UpdatePlayerStats(false, GetClientOfUserId(event.GetInt("userid")));
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	UpdateMatchStats(true);
	UpdatePlayerStats();
	CheckSurrenderVotes();
}

void UpdatePlayerStats(bool allPlayers = true, int Client = 0)
{
	if(Get5_GetGameState() != Get5State_Live) return;

	char sQuery[1024], sName[64], sSteamID[64], sTeamName[64];
	int iEnt, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore;
	iEnt = FindEntityByClassname(-1, "cs_player_manager");

	if(allPlayers)
	{
		Transaction txn_UpdateStats = new Transaction();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i, true)) continue;

			iTeam = GetEntProp(iEnt, Prop_Send, "m_iTeam", _, i);
			iAlive = GetEntProp(iEnt, Prop_Send, "m_bAlive", _, i);
			iPing = GetEntProp(iEnt, Prop_Send, "m_iPing", _, i);
			iAccount = GetEntProp(i, Prop_Send, "m_iAccount");
			iKills = GetEntProp(iEnt, Prop_Send, "m_iKills", _, i);
			iAssists = GetEntProp(iEnt, Prop_Send, "m_iAssists", _, i);
			iDeaths = GetEntProp(iEnt, Prop_Send, "m_iDeaths", _, i);
			iMVPs = GetEntProp(iEnt, Prop_Send, "m_iMVPs", _, i);
			iScore = GetEntProp(iEnt, Prop_Send, "m_iScore", _, i);

			GetClientName(i, sName, sizeof(sName));
			g_Database.Escape(sName, sName, sizeof(sName));

			GetClientAuthId(i, AuthId_SteamID64, sSteamID, sizeof(sSteamID));

			int len = 0;
			len += Format(sQuery[len], sizeof(sQuery) - len, "INSERT IGNORE INTO sql_matches_tet (match_id, name, steamid, team, alive, ping, account, kills, assists, deaths, mvps, score, disconnected, shots_fired, shots_hit, headshots) ");
			len += Format(sQuery[len], sizeof(sQuery) - len, "VALUES (LAST_INSERT_ID(), '%s', '%s', %i, %i, %i, %i, %i, %i, %i, %i, %i, 0, %i, %i, %i) ", sName, sSteamID, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore, g_iShotsFired[i], g_iShotsHit[i], g_iHeadshots[i], sTeamName);
			len += Format(sQuery[len], sizeof(sQuery) - len, "ON DUPLICATE KEY UPDATE name='%s', team=%i, alive=%i, ping=%i, account=%i, kills=%i, assists=%i, deaths=%i, mvps=%i, score=%i, disconnected=0, shots_fired=%i, shots_hit=%i, headshots=%i;", sName, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore, g_iShotsFired[i], g_iShotsHit[i], g_iHeadshots[i]);	
			txn_UpdateStats.AddQuery(sQuery);
		}
		g_Database.Execute(txn_UpdateStats, SQL_TranSuccess, SQL_TranFailure);
		return;
	}

	if(!IsValidClient(Client, true)) return;

	iTeam = GetEntProp(iEnt, Prop_Send, "m_iTeam", _, Client);
	iAlive = GetEntProp(iEnt, Prop_Send, "m_bAlive", _, Client);
	iPing = GetEntProp(iEnt, Prop_Send, "m_iPing", _, Client);
	iAccount = GetEntProp(Client, Prop_Send, "m_iAccount");
	iKills = GetEntProp(iEnt, Prop_Send, "m_iKills", _, Client);
	iAssists = GetEntProp(iEnt, Prop_Send, "m_iAssists", _, Client);
	iDeaths = GetEntProp(iEnt, Prop_Send, "m_iDeaths", _, Client);
	iMVPs = GetEntProp(iEnt, Prop_Send, "m_iMVPs", _, Client);
	iScore = GetEntProp(iEnt, Prop_Send, "m_iScore", _, Client);

	GetClientName(Client, sName, sizeof(sName));
	//Get5_GetTeamName(GetClientTeam(Client), sTeamName, sizeof(sTeamName));

	g_Database.Escape(sName, sName, sizeof(sName));
	

	GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID));

	int len = 0;
	len += Format(sQuery[len], sizeof(sQuery) - len, "INSERT IGNORE INTO sql_matches (match_id, name, steamid, team, alive, ping, account, kills, assists, deaths, mvps, score, disconnected, shots_fired, shots_hit, headshots) ");
	len += Format(sQuery[len], sizeof(sQuery) - len, "VALUES (LAST_INSERT_ID(), '%s', '%s', %i, %i, %i, %i, %i, %i, %i, %i, %i, 0, %i, %i, %i) ", sName, sSteamID, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore, g_iShotsFired[Client], g_iShotsHit[Client], g_iHeadshots[Client]);
	len += Format(sQuery[len], sizeof(sQuery) - len, "ON DUPLICATE KEY UPDATE name='%s', team=%i, alive=%i, ping=%i, account=%i, kills=%i, assists=%i, deaths=%i, mvps=%i, score=%i, disconnected=0, shots_fired=%i, shots_hit=%i, headshots=%i;", sName, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore, g_iShotsFired[Client], g_iShotsHit[Client], g_iHeadshots[Client]);	
    g_Database.Query(SQL_GenericQuery, sQuery);
}

public void SQL_TranSuccess(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{
	PrintToServer("Transaction Successful");
}

public void SQL_TranFailure(Database db, any data, int numQueries, const char[] sError, int failIndex, any[] queryData)
{
	LogError("Transaction Failed! Error: %s. During Query: %i", sError, failIndex);
}

void UpdateMatchStats(bool duringMatch = false)
{
	if(duringMatch && Get5_GetGameState() != Get5State_Live) return;

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "UPDATE sql_matches_scoretotal SET team_t=%i, team_ct=%i, live=%i WHERE match_id=LAST_INSERT_ID();", CS_GetTeamScore(CS_TEAM_T), CS_GetTeamScore(CS_TEAM_CT), Get5_GetGameState() == Get5State_Live);
	g_Database.Query(SQL_GenericQuery, sQuery);
}

public Action Command_EndMatch(int Client, int iArgs)
{
	if(!IsValidClient(Client, true) || Get5_GetGameState() != Get5State_Live) return Plugin_Handled;

	int iTeam = GetClientTeam(Client);

	if(iTeam == CS_TEAM_T)
	{
		if(CS_GetTeamScore(CS_TEAM_CT) - 8 >= CS_GetTeamScore(iTeam)) // Check if CT is 8 or more rounds ahead of T
		{
			if(ga_iEndMatchVotesT.FindValue(Client) == -1) // Check if client has already voted to surrender
			{
				ga_iEndMatchVotesT.Push(Client); // Add client to ArrayList

				int iTeamCount = GetTeamClientCount(iTeam);
				if(ga_iEndMatchVotesT.Length >= iTeamCount) // Check if we have the amount of votes needed to surrender
				{
					for(int i = 1; i <= MaxClients; i++)
					{
						if(IsValidClient(i, true) && GetClientTeam(i) == iTeam)
							PrintToChat(i, "%s Terrorists have voted to surrender. Match ending...", PREFIX);
					}

					ServerCommand("get5_endmatch"); // Force end the match
					CreateTimer(10.0, Timer_KickEveryoneSurrender); // Delay kicking everyone so they can see the chat message and so the plugin has time to update their stats
					ga_iEndMatchVotesT.Clear(); // Reset the ArrayList
				}
				else
				{
					for(int i = 1; i <= MaxClients; i++)
					{
						if(IsValidClient(i, true) && GetClientTeam(i) == iTeam)
							PrintToChat(i, "%s %N has voted to surrender, %i/%i votes needed.", PREFIX, Client, ga_iEndMatchVotesT.Length, iTeamCount);
					}
				}
			}
			else PrintToChat(Client, "%s You've already voted to surrender!", PREFIX);
		}
		else PrintToChat(Client, "%s You must be at least 8 rounds behind the enemy team to vote to surrender.", PREFIX);
	}
	else if(iTeam == CS_TEAM_CT)
	{
		if(CS_GetTeamScore(CS_TEAM_T) - 8 >= CS_GetTeamScore(iTeam)) // Check if T is 8 or more rounds ahead of CT
		{
			if(ga_iEndMatchVotesCT.FindValue(Client) == -1) // Check if client has already voted to surrender
			{
				ga_iEndMatchVotesCT.Push(Client); // Add client to ArrayList

				int iTeamCount = GetTeamClientCount(iTeam);
				if(ga_iEndMatchVotesCT.Length >= iTeamCount) // Check if we have the amount of votes needed to surrender
				{
					for(int i = 1; i <= MaxClients; i++)
					{
						if(IsValidClient(i, true))
							PrintToChat(i, "%s Counter-Terrorists have voted to surrender. Match ending...", PREFIX);
					}

					ServerCommand("get5_endmatch"); // Force end the match
					CreateTimer(10.0, Timer_KickEveryoneSurrender); // Delay kicking everyone so they can see the chat message and so the plugin has time to update their stats
					ga_iEndMatchVotesCT.Clear(); // Reset the ArrayList
				}
				else
				{
					for(int i = 1; i <= MaxClients; i++)
					{
						if(IsValidClient(i, true) && GetClientTeam(i) == iTeam)
							PrintToChat(i, "%s %N has voted to surrender, %i/%i votes needed.", PREFIX, Client, ga_iEndMatchVotesCT.Length, iTeamCount);
					}
				}
			}
			else PrintToChat(Client, "%s You've already voted to surrender!", PREFIX);
		}
		else PrintToChat(Client, "%s You must be at least 8 rounds behind the enemy team to vote to surrender.", PREFIX);
	}
	return Plugin_Handled;
}

public void CheckSurrenderVotes()
{
	int iTeamCount = GetTeamClientCount(CS_TEAM_CT);
	if(iTeamCount <= 1) return;

	if(ga_iEndMatchVotesCT.Length >= iTeamCount) // Check if we have the amount of votes needed to surrender
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i, true))
				PrintToChat(i, "%s Counter-Terrorists have voted to surrender. Match ending...", PREFIX);
		}

		ServerCommand("get5_endmatch"); // Force end the match
		Get5_OnMapResult("", MatchTeam_TeamNone, 0, 0, 0);
		CreateTimer(10.0, Timer_KickEveryoneSurrender); // Delay kicking everyone so they can see the chat message and so the plugin has time to update their stats
		ga_iEndMatchVotesCT.Clear(); // Reset the ArrayList
		return;
	}

	iTeamCount = GetTeamClientCount(CS_TEAM_T);
	if(iTeamCount <= 1) return;

	if(ga_iEndMatchVotesT.Length >= iTeamCount) // Check if we have the amount of votes needed to surrender
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i, true))
				PrintToChat(i, "%s Terrorists have voted to surrender. Match ending...", PREFIX);
		}

		ServerCommand("get5_endmatch"); // Force end the match
		CreateTimer(10.0, Timer_KickEveryoneSurrender); // Delay kicking everyone so they can see the chat message and so the plugin has time to update their stats
		ga_iEndMatchVotesT.Clear(); // Reset the ArrayList
		return;
	}
}

public Action Timer_KickEveryoneSurrender(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i)) KickClient(i, "Match force ended by surrender vote");
	ServerCommand("tv_stoprecord");

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "UPDATE sql_matches_scoretotal SET live=0 WHERE match_id=LAST_INSERT_ID();");
	g_Database.Query(SQL_GenericQuery, sQuery);
	return Plugin_Stop;
}

public Action Timer_KickEveryoneEnd(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i)) KickClient(i, "Thanks for playing!\nView the match on our website for statistics");
	ServerCommand("tv_stoprecord");
	ServerCommand("get5_endmatch");
	return Plugin_Stop;
}

public void SendReport()
{
	char sSiteURL[128], sAvatarURL[128];
	g_CVSiteURL.GetString(sSiteURL, sizeof(sSiteURL));
	g_CVEmbedAvatar.GetString(sAvatarURL, sizeof(sAvatarURL));

	if(StrEqual(sSiteURL, "") || StrEqual(sAvatarURL, ""))
	{
		LogError("Missing Site Url or Embed Avatar Url.");
		return;
	}

	int iTScore = CS_GetTeamScore(CS_TEAM_T);
	int iCTScore = CS_GetTeamScore(CS_TEAM_CT);
	int iWinners = 0;

	if(iTScore == 0 && iCTScore == 0) return;
	
	bool bDraw = false;

	if(iTScore > iCTScore) iWinners = CS_TEAM_T;
	else if(iCTScore > iTScore) iWinners = CS_TEAM_CT;
	else if(iTScore == iCTScore) bDraw = true;

	Handle jRequest = json_object();
	Handle jEmbeds = json_array();
	Handle jContent = json_object();
	Handle jContentAuthor = json_object();
	
	json_object_set(jContent, "color", json_integer(g_CVEmbedColour.IntValue));

	char sWinTitle[64], sBuffer[128], sDescription[1024], sTeamName[128];
	int len = 0;

	if(g_bLoadMatchAvailable && iWinners != 0)
		//Get5_GetTeamName(iWinners, sTeamName, sizeof(sTeamName));
	
	if(bDraw) 
		Format(sWinTitle, sizeof(sWinTitle), "Match was a draw at %i:%i!", iTScore, iCTScore);
	else if(iWinners == CS_TEAM_T) 
		Format(sWinTitle, sizeof(sWinTitle), "%s just won %i-%i!", sTeamName, iTScore, iCTScore);
	else 
		Format(sWinTitle, sizeof(sWinTitle), "%s just won %i-%i!", sTeamName, iCTScore, iTScore);

	json_object_set_new(jContentAuthor, "name", json_string(sWinTitle));
	Format(sBuffer, sizeof sBuffer, "%s/scoreboard?id=%i", sSiteURL, g_iMatchID);
	json_object_set_new(jContentAuthor, "url", json_string(sBuffer));
	json_object_set_new(jContentAuthor, "icon_url", json_string(sAvatarURL));
	json_object_set_new(jContent, "author", jContentAuthor);

	if(iWinners != 0)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			char sTemp[64];
			if(IsValidClient(i))
			{
				if(GetClientTeam(i) == iWinners)
				{
					GetClientName(i, sTemp, sizeof(sTemp));
					ga_sWinningPlayers.PushString(sTemp);
				}
			}
		}

		len += Format(sDescription[len], sizeof(sDescription) - len, "\nCongratulations:\n");
		for(int i = 0; i < ga_sWinningPlayers.Length; i++)
		{
			char sName[64];
			ga_sWinningPlayers.GetString(i, sName, sizeof(sName));
			len += Format(sDescription[len], sizeof(sDescription) - len, "%s\n", sName);
		}
	}

	len += Format(sDescription[len], sizeof(sDescription) - len, "\n[View more](%s/scoreboard?id=%i)", sSiteURL, g_iMatchID);
	json_object_set_new(jContent, "description", json_string(sDescription));

	json_array_append_new(jEmbeds, jContent);
	json_object_set_new(jRequest, "username", json_string("Match Bot"));
	json_object_set_new(jRequest, "avatar_url", json_string(sAvatarURL));
	json_object_set_new(jRequest, "embeds", jEmbeds);

	char sJson[2048];
	json_dump(jRequest, sJson, sizeof sJson, 0, false, false, true);

	CloseHandle(jRequest);
}

public void Event_WeaponFired(Event event, const char[] name, bool dontBroadcast)
{
	int Client = GetClientOfUserId(event.GetInt("userid"));
	if(Get5_GetGameState() != Get5State_Live || !IsValidClient(Client, true)) return;

	int iWeapon = GetEntPropEnt(Client, Prop_Send, "m_hActiveWeapon");
	if(!IsValidEntity(iWeapon)) return;

	if(GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType") != -1 && GetEntProp(iWeapon, Prop_Send, "m_iClip1") != 255) g_iShotsFired[Client]++; //should filter knife and grenades
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int Client = GetClientOfUserId(event.GetInt("attacker"));
	if(Get5_GetGameState() != Get5State_Live || !IsValidClient(Client, true)) return;

	if(event.GetInt("hitgroup") >= 0)
	{
		g_iShotsHit[Client]++;
		if(event.GetInt("hitgroup") == 1) g_iHeadshots[Client]++;
	}
}

/* This has changed  */
public void Event_HalfTime(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_alreadySwapped)
    {
        char sQuery[1024];
        int teamIndex_T = -1, teamIndex_CT = -1; 

        int index = -1; 
        while ((index = FindEntityByClassname(index, "cs_team_manager")) != -1) { 
            int teamNum = GetEntProp(index, Prop_Send, "m_iTeamNum"); 
            if (teamNum == CS_TEAM_T) { 
                teamIndex_T = index; 
            } else if (teamNum == CS_TEAM_CT) { 
                teamIndex_CT = index; 
            } 
        }
        
        char teamNameOld_T[32], teamNameOld_CT[32];
        char teamNameNew_T[32], teamNameNew_CT[32];
        GetEntPropString(teamIndex_T, Prop_Send, "m_szClanTeamname", teamNameOld_T, 32);
        GetEntPropString(teamIndex_CT, Prop_Send, "m_szClanTeamname", teamNameOld_CT, 32);

        teamNameNew_T = teamNameOld_CT;
        teamNameNew_CT = teamNameOld_T;
        PrintToChatAll("teamNameNew_T: %s", teamNameNew_T);
        PrintToChatAll("teamNameNew_CT: %s", teamNameNew_CT);

        Format(sQuery, sizeof(sQuery), "UPDATE sql_matches_scoretotal_test SET team_1_name = '%s', team_2_name = '%s' WHERE match_id = LAST_INSERT_ID();", teamNameNew_T, teamNameNew_CT);
        g_Database.Query(SQL_GenericQuery, sQuery);
        g_alreadySwapped = true;
    }
}

public void OnClientDisconnect(int Client)
{
	if(IsValidClient(Client))
	{
		int iIndexT = ga_iEndMatchVotesT.FindValue(Client);
		int iIndexCT = ga_iEndMatchVotesCT.FindValue(Client);

		if(iIndexT != -1) ga_iEndMatchVotesT.Erase(iIndexT);
		if(iIndexCT != -1) ga_iEndMatchVotesCT.Erase(iIndexCT);

		UpdatePlayerStats(false, Client);

		CheckSurrenderVotes();

		ResetVars(Client);

		if(Get5_GetGameState() == Get5State_Live && IsValidClient(Client, true))
		{
			char sQuery[1024], sSteamID[64];
			GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
			Format(sQuery, sizeof(sQuery), "UPDATE sql_matches SET disconnected=1 WHERE match_id=LAST_INSERT_ID() AND steamid='%s'", sSteamID);
			g_Database.Query(SQL_GenericQuery, sQuery);
		}
	}
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

stock bool IsValidClient(int client, bool inPug = false)
{
	if (client >= 1 && 
	client <= MaxClients && 
	IsClientConnected(client) && 
	IsClientInGame(client) &&
	!IsFakeClient(client) &&
	(inPug == false || (Get5_GetGameState() == Get5State_Live && (GetClientTeam(client) == CS_TEAM_CT || GetClientTeam(client) == CS_TEAM_T))))
		return true;
	return false;
}