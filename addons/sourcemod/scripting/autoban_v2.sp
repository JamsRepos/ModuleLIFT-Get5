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

// 

public void OnPluginStart()
{
    // MySQL Stuff
    CreateTimer(1.0, AttemptMySQLConnection);

    // Convar creation
    g_hCVFallbackTime = CreateConVar("sm_autoban_fallback_time", "1440", "Time a player should be banned for if MySQL Ban fails.");
    g_hCVReconnectTime = CreateConVar("sm_autoban_reconnect_time", "300", "Time a player has to reconnect to the server to avoid ban.");
    g_hCVServerIp = CreateConVar("sm_autoban_websocket_ip", "127.0.0.1", "IP to connect to for sending ban messages.");
	g_hCVPackageKey = CreateConVar("sm_autoban_package_key", "idk something", "a package key or something idk ward doesnt tell me anything :(");

    // Socket stuff - Doggy's Code
    g_hSocket = SocketCreate(SOCKET_TCP, OnSocketError);
    SocketSetOption(g_hSocket, SocketReuseAddr, 1);
	SocketSetOption(g_hSocket, SocketKeepAlive, 1);

    if (!SocketIsConnected(g_hSocket))
        ConnectRelay();
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

public void OnMapStart()
{
    ResetInformation();
}

public void ResetInformation()
{
    // TODO: Reset information here.
}

public void OnClientDisconnect()
{
    // Handle the disconnection stuff with the arrays planned.
}