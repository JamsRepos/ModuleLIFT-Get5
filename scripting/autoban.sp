#include <get5>
#include <sdkhooks>
#include <sdktools>
#include <SteamWorks>
#include <socket>
#include <base64>
#include <smjansson>

float g_fTeamDamage[MAXPLAYERS + 1];

int g_iButtonTime[MAXPLAYERS + 1];
int g_iTeamKills[MAXPLAYERS + 1];
int g_iRetryTimes[MAXPLAYERS + 1];
int g_iMatchStartTime;

bool g_bLate;
bool g_bBanned[MAXPLAYERS + 1];

Database g_Database = null;

enum BanReason 
{
	REASON_OTHER = -1,
	REASON_AFK,
	REASON_LEAVE,
	REASON_DAMAGE
};

BanReason g_eBanReason[MAXPLAYERS + 1];

ConVar g_hCVFallbackTime;
ConVar g_hCVServerIp;
ConVar g_hCVPackageKey;

Handle g_hSocket;

public Plugin myinfo = 
{
	name = "Auto Match Ban",
	author = "DN.H | The Doggy",
	description = "Ban Noobs",
	version = "1.0.0",
	url = "DistrictNine.Host"
};

public void ResetVars(int Client)
{
	g_fTeamDamage[Client] = 0.0;
	g_iButtonTime[Client] = 0;
	g_iTeamKills[Client] = 0;
	g_iRetryTimes[Client] = 0;
	g_bBanned[Client] = false;
	g_eBanReason[Client] = REASON_OTHER;
}

public void OnMapStart()
{
	g_iMatchStartTime = 0;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if(late)
		g_bLate = true;

	return APLRes_Success;
}

public void OnPluginStart()
{
	//Create Timer
	CreateTimer(1.0, AttemptMySQLConnection);

	//Hook Event
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_death", Event_PlayerDeath);

	//Create ConVar
	g_hCVFallbackTime = CreateConVar("sm_autoban_fallback_time", "120", "Time a player should be banned for if MySQL ban fails.");
	g_hCVServerIp = CreateConVar("sm_autoban_websocket_ip", "127.0.0.1", "IP to connect to for sending ban messages.");
	g_hCVPackageKey = CreateConVar("sm_autoban_package_key", "idk something", "a package key or something idk ward doesnt tell me anything :(");

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
		g_hCVServerIp.GetString(sHost, sizeof(sHost));
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

public Action AttemptMySQLConnection(Handle timer)
{
	if (g_Database != null)
	{
		delete g_Database;
		g_Database = null;
	}
	
	char sFolder[32];
	GetGameFolderName(sFolder, sizeof(sFolder));
	if (SQL_CheckConfig("auto_ban"))
	{
		PrintToServer("Initalizing Connection to MySQL Database");
		Database.Connect(SQL_InitialConnection, "auto_ban");
	}
	else
		LogError("Database Error: No Database Config Found! (%s/addons/sourcemod/configs/databases.cfg)", sFolder);

	return Plugin_Stop;
}

public void SQL_InitialConnection(Database db, const char[] sError, int data)
{
	if (db == null)
	{
		LogMessage("Database Error: %s", sError);
		CreateTimer(10.0, AttemptMySQLConnection);
		return;
	}
	
	char sDriver[16];
	db.Driver.GetIdentifier(sDriver, sizeof(sDriver));
	if (StrEqual(sDriver, "mysql", false)) LogMessage("MySQL Database: connected");
	
	g_Database = db;
	CreateAndVerifySQLTables();
}

public void CreateAndVerifySQLTables()
{
	char sQuery[1024] = "";
	StrCat(sQuery, 1024, "CREATE TABLE IF NOT EXISTS get5_matchbans (");
	StrCat(sQuery, 1024, "id INTEGER NOT NULL AUTO_INCREMENT, ");
	StrCat(sQuery, 1024, "steamid VARCHAR(64) NOT NULL, ");
	StrCat(sQuery, 1024, "discordid VARCHAR(128), ");
	StrCat(sQuery, 1024, "reason TEXT NOT NULL, ");
	StrCat(sQuery, 1024, "timestamp VARCHAR(128), ");
	StrCat(sQuery, 1024, "active INTEGER NOT NULL, ");
	StrCat(sQuery, 1024, "PRIMARY KEY(id));");
	g_Database.Query(SQL_GenericQuery, sQuery);

	if(g_bLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
				CreateTimer(0.1, Timer_CheckBan, GetClientUserId(i));
			}
		}
	}
}

public Action Timer_CheckBan(Handle hTimer, int userID)
{
	int Client = GetClientOfUserId(userID);
	if(!IsValidClient(Client)) return Plugin_Stop;

	CheckBanStatus(Client);
	return Plugin_Stop;
}

public void CheckBanStatus(int Client)
{
	if(g_Database == null) return;

	if(!IsValidClient(Client)) return;

	char sSteamID[64];
	if(!GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID)) && g_iRetryTimes[Client] < 5)
	{
		g_iRetryTimes[Client]++;
		LogMessage("Failed to get SteamID for player %N, retrying in 30 seconds.", Client);
		CreateTimer(30.0, Timer_CheckBan, GetClientUserId(Client));
	}
	else if(g_iRetryTimes[Client] >= 5)
	{
		LogError("Failed to get SteamID for player %N 5 times, kicking player instead.", Client);
		g_bBanned[Client] = true;
		KickClient(Client, "Failed to get your SteamID");
	}

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "SELECT active, reason FROM get5_matchbans WHERE steamid='%s';", sSteamID);
	g_Database.Query(SQL_SelectBan, sQuery, GetClientUserId(Client));
}

public void SQL_SelectBan(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	if(!results.FetchRow()) return;

	int Client = GetClientOfUserId(data);
	if(!IsValidClient(Client)) return;

	do
	{
		int activeCol, reasonCol, active;
		results.FieldNameToNum("active", activeCol);
		active = results.FetchInt(activeCol);

		if(active != 1) continue;

		char sReason[128];
		results.FieldNameToNum("reason", reasonCol);
		results.FetchString(reasonCol, sReason, sizeof(sReason));
		g_bBanned[Client] = true;
		KickClient(Client, sReason);
	} while(results.FetchRow());
}

public void BanPlayer(int Client)
{
	if(!IsValidClient(Client)) return;

	if(g_bBanned[Client]) return;

	char sSteamID[64], sQuery[1024], sReason[128], sSmallReason[16];
	if(!GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID)))
	{
		LogError("BanPlayer(): Unable to get player %N's SteamID, trying to ban player via SM natives instead.", Client);
		if(!BanClient(Client, g_hCVFallbackTime.IntValue, BANFLAG_AUTO, "Fallback ban", "Fallback ban"))
			LogError("BanPlayer(): Failed to ban player %N via SM natives :(", Client);
		return;
	}

	switch(g_eBanReason[Client])
	{
		case REASON_AFK: Format(sSmallReason, sizeof(sSmallReason), "AFK");
		case REASON_LEAVE: Format(sSmallReason, sizeof(sSmallReason), "Left Match");
		case REASON_DAMAGE: Format(sSmallReason, sizeof(sSmallReason), "Team Damage");
		default: Format(sSmallReason, sizeof(sSmallReason), "Something");
	}

	DataPack steamPack = new DataPack();
	steamPack.WriteString(sSteamID);

	g_bBanned[Client] = true;
	Format(sReason, sizeof(sReason), "Automatic %s Ban", sSmallReason);
	KickClient(Client, sReason);

	char sData[512], sPort[16], sEncodedData[512], sPackageKey[128], sIP[32];
	int ip[4];
	FindConVar("hostport").GetString(sPort, sizeof(sPort));
	SteamWorks_GetPublicIP(ip);
	g_hCVPackageKey.GetString(sPackageKey, sizeof(sPackageKey));
	Format(sIP, sizeof(sIP), "%i.%i.%i.%i:%s", ip[0], ip[1], ip[2], ip[3], sPort);

	Handle jsonObj = json_object();
	json_object_set_new(jsonObj, "type", json_integer(2));
	json_object_set_new(jsonObj, "server", json_string(sIP));
	json_object_set_new(jsonObj, "steamid", json_string(sSteamID));
	json_object_set_new(jsonObj, "reason", json_string(sReason));
	json_object_set_new(jsonObj, "pass", json_string(sPackageKey));
	json_dump(jsonObj, sData, sizeof(sData), 0, false, false, true);
	CloseHandle(jsonObj);

	EncodeBase64(sEncodedData, sizeof(sEncodedData), sData);
	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();

	SocketSend(g_hSocket, sEncodedData, sizeof(sEncodedData));

	/* {"type":2,"server":"ip:port","steamid":steamid64,"reason":"ban reason here", "pass": "package_key"} */

	Format(sQuery, sizeof(sQuery), "INSERT INTO get5_matchbans (steamid, reason, active) VALUES ('%s', '%s', 1);", sSteamID, sReason);
	g_Database.Query(SQL_InsertBan, sQuery, steamPack);
}

public void SQL_InsertBan(Database db, DBResultSet results, const char[] sError, DataPack data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);

		char sSteamID[64];
		data.Reset();
		data.ReadString(sSteamID, sizeof(sSteamID));
		LogError("SQL_InsertBan(): Failed to insert ban for SteamID %s, trying to ban via SM natives instead.", sSteamID);
		if(!BanIdentity(sSteamID, g_hCVFallbackTime.IntValue, BANFLAG_AUTHID, "Fallback ban"))
			LogError("SQL_InsertBan(): Failed to ban SteamID %s via SM natives :(", sSteamID);
		return;
	}
}

public void Get5_OnGoingLive(int mapNumber)
{
	g_iMatchStartTime = GetTime();
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i)) continue;
		g_iButtonTime[i] = GetTime();
	}
}

public void OnClientPostAdminCheck(int Client)
{
	SDKHook(Client, SDKHook_OnTakeDamage, OnTakeDamage);
	CheckBanStatus(Client);
}

public void OnClientPutInServer(int Client)
{
	ResetVars(Client);
}

public void OnClientDisconnect(int Client)
{
	if(Get5_GetGameState() <= Get5State_GoingLive || g_bBanned[Client]) return;

	if(GetTime() - g_iMatchStartTime >= 240)
	{
		char sSteamID[64];
		if(!GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID)))
		{
			LogError("OnClientDisconnect(): Failed to get %N's SteamID, not going to add player to disconnect list.");
			return;
		}

		DataPack disconnectPack = new DataPack();
		disconnectPack.WriteString(sSteamID);
		CreateTimer(60.0, Timer_DisconnectBan, disconnectPack);
	}
}

public Action Timer_DisconnectBan(Handle hTimer, DataPack disconnectPack)
{
	char sSteamID[64];
	disconnectPack.Reset();
	disconnectPack.ReadString(sSteamID, sizeof(sSteamID));

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i)) continue;

		char sCurrentID[64];
		if(!GetClientAuthId(i, AuthId_SteamID64, sSteamID, sizeof(sSteamID))) continue;

		if(StrEqual(sSteamID, sCurrentID))
		{
			delete disconnectPack;
			return Plugin_Stop;
		}
	}

	char sData[1024], sPort[16], sEncodedData[1024], sPackageKey[128], sIP[32];
	int ip[4];
	FindConVar("hostport").GetString(sPort, sizeof(sPort));
	SteamWorks_GetPublicIP(ip);
	Format(sIP, sizeof(sIP), "%i.%i.%i.%i:%s", ip[0], ip[1], ip[2], ip[3], sPort);
	g_hCVPackageKey.GetString(sPackageKey, sizeof(sPackageKey));

	Handle jsonObj = json_object();
	json_object_set_new(jsonObj, "type", json_integer(2));
	json_object_set_new(jsonObj, "server", json_string(sIP));
	json_object_set_new(jsonObj, "steamid", json_string(sSteamID));
	json_object_set_new(jsonObj, "reason", json_string("Automatic Left Match Ban"));
	json_object_set_new(jsonObj, "pass", json_string(sPackageKey));
	json_dump(jsonObj, sData, sizeof(sData), 0, false, false, true);
	CloseHandle(jsonObj);

	EncodeBase64(sEncodedData, sizeof(sEncodedData), sData);
	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();

	SocketSend(g_hSocket, sEncodedData, sizeof(sEncodedData));

	/* {"type":2,"server":"ip:port","steamid":steamid64,"reason":"ban reason here", "pass": "package_key"} */

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "INSERT INTO get5_matchbans (steamid, reason, active) VALUES ('%s', 'Automatic Left Match Ban', 1);", sSteamID);
	g_Database.Query(SQL_InsertBan, sQuery, disconnectPack);
	return Plugin_Stop;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if(Get5_GetGameState() <= Get5State_GoingLive) return;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || g_bBanned[i]) continue;

		if(GetTime() - g_iButtonTime[i] >= 180)
		{
			g_eBanReason[i] = REASON_AFK;
			BanPlayer(i);
		}
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if(Get5_GetGameState() <= Get5State_GoingLive) return;

	int iVictim = GetClientOfUserId(event.GetInt("userid"));
	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));

	if(!IsValidClient(iVictim) || !IsValidClient(iAttacker) || g_bBanned[iAttacker]) return;

	if(GetClientTeam(iVictim) == GetClientTeam(iAttacker))
	{
		g_iTeamKills[iAttacker]++;

		if(g_iTeamKills[iAttacker] >= 3)
		{
			g_eBanReason[iAttacker] = REASON_DAMAGE;
			BanPlayer(iAttacker);
			return;
		}
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if(Get5_GetGameState() <= Get5State_GoingLive || buttons <= 0) return Plugin_Continue;
	g_iButtonTime[client] = GetTime();
	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(!IsValidClient(victim) || !IsValidClient(attacker) || Get5_GetGameState() <= Get5State_GoingLive || g_bBanned[attacker]) return Plugin_Continue;

	if(GetClientTeam(victim) == GetClientTeam(attacker))
	{
		g_fTeamDamage[attacker] += damage;

		if(g_fTeamDamage[attacker] >= 800)
		{
			g_eBanReason[attacker] = REASON_DAMAGE;
			BanPlayer(attacker);
		}
	}

	return Plugin_Continue;
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