// WARNING
// IF YOU USE THIS CODE IN IT'S CURRENT STATE THEN YOU ARE LITERALLY RETARDED
// JAM IF YOU ARE READING THIS. DO NOT COMPILE THIS CODE
// YOU WILL BE RETARDED TO DO THIS
// THIS IS NO JOKE
// <3 YOU REALLY

#include <get5>
#include <sdkhooks>
#include <sdktools>
#include <SteamWorks>
#include <socket>
#include <smjansson>

public Plugin myinfo = 
{
    name = "NexusLeague.gg Ban System",
    author = "PandahChan",
    description = "Custom Ban System similar to FaceIT",
    version = "1.0.0",
    url = "https://github.com/LubricantJam/ModuleLIFT-Get5"
}

ConVar g_hCVFallbackTime;
ConVar g_hCVReconnectTime;
ConVar g_hCVServerIp;
ConVar g_hCVPackageKey;

Handle g_hSocket;

Handle g_aPlayerID;
Handle g_aPlayerTime;
Handle g_aPlayerName;

public void OnPluginStart()
{
    // MySQL Stuff
    CreateTimer(1.0, AttemptMySQLConnection);

    // Convar creation
    g_hCVFallbackTime = CreateConVar("sm_autoban_fallback_time", "1440", "Time a player should be banned for if MySQL Ban fails.");
    g_hCVReconnectTime = CreateConVar("sm_autoban_reconnect_time", "300", "Time a player has to reconnect to the server to avoid ban.");
    g_hCVServerIp = CreateConVar("sm_autoban_websocket_ip", "127.0.0.1", "IP to connect to for sending ban messages.");
	g_hCVPackageKey = CreateConVar("sm_autoban_package_key", "idk something", "a package key or something idk ward doesnt tell me anything :(");

	g_aPlayerId = CreateArray(64);
	g_aPlayerTime = CreateArray();
	g_aPlayerName = CreateArray(128);

    // Socket stuff - Doggy's Code
    g_hSocket = SocketCreate(SOCKET_TCP, OnSocketError);
    SocketSetOption(g_hSocket, SocketReuseAddr, 1);
	SocketSetOption(g_hSocket, SocketKeepAlive, 1);

    if (!SocketIsConnected(g_hSocket))
        ConnectRelay();
	
	CreateTimer(1.0, Timer_CheckBan, _, TIMER_REPEAT);
}

public void OnMapStart()
{
    ResetInformation();
}

public void ResetInformation()
{
    // TODO: Reset information here.
}

public Action Timer_CheckBan(Handle timer)
{
	int size = GetArraySize(g_aPlayerTime);

	if (size == 0) return;

	char steamid[64], name[128];

	for (int i = 0; i < size; i++)
	{
		if (GetTime() > GetArrayCell(g_aPlayerTime, i) + g_hCVReconnectTime.IntValue)
		{
			BanPlayer(i);
		}
	}
}

// Doggy's Ban Player code
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

	char sData[2048], sPort[16], sPackageKey[128], sIP[32];
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

	Format(sQuery, sizeof(sQuery), "INSERT INTO bans (steamid, reason, active) VALUES ('%s', '%s', 1);", sSteamID, sReason);
	g_Database.Query(SQL_InsertBan, sQuery, steamPack);

	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();

	SocketSend(g_hSocket, sData, sizeof(sData));
}

// Socket stuff - Doggy's Code
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

// MySQL Stuff - Doggy's Code
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