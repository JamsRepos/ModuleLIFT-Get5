#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1 
#pragma newdecls required

Handle g_hNewGameTimer = INVALID_HANDLE;
bool isNewGameTimer = false; 
bool g_NextRoundNewGame = false;

public Plugin myinfo = 
{
	name = "[NL] Save player info on disconnect.",
	author = "PandahChan",
	description = "Again why isn't this default?",
	version = "1.0",
	url = ""
};

public void OnPluginStart()
{
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_disconnect", Event_PlayerDisconnect);

    InitaliseDatabase();

    ClearDatabase();

    CreateTimer(1.0, SaveScores, _, TIMER_REPEAT);
}

// Database stuff.
public void InitaliseDatabase()
{
    char error[255];

    g_hDB = SQLite_UseDatabase("saveinfo", error, sizeof(error));

    if (g_hDB == INVALID_HANDLE) SetFailState("SQL error: %s", error);

    SQL_LockDatabase(g_hDB);
    SQL_FastQuery(g_hDB, "VACUUM");
    SQL_FastQuery(g_hDB, "CREATE TABLE IF NOT EXISTS nl_saveinfo (steamid TEXT PRIMARY KEY, frags SMALLINT, deaths SMALLINT, assists SMALLINT, realscore SMALLINT, timestamp INTEGER);");
    SQL_UnlockDatabase(g_hDB);
}

public void ClearDatabase(bool delay = true)
{
    if (delay) CreateTimer(0.1, ClearDBDelayed);
    else ClearDBQuery();
}

public Action ClearDBDelayed(Handle timer)
{
    ClearDBQuery();
}

public void ClearDBQuery()
{
    SQL_LockDatabase(g_hDB);
    SQL_FastQuery(g_hDB, "DELETE FROM nl_saveinfo;");
    SQL_UnlockDatabase(g_hDB);
}


public void NewMatchCommand(Handle convar, const char[] oldValue, const char[] newValue)
{
    float fTimer = StringToFloat(newValue); 

    g_hNewGameTimer = CreateTimer(fTimer - 0.1, MarkNewRoundAsNewGame);
    isNewGameTimer = true;
}

public Action MarkNewRoundAsNewGame(Handle timer)
{
    isNewGameTimer = false;
    g_NextRoundNewGame = true;
}

public Action Event_NewGameStart(Handle event, const char[] name, bool dontBroadcast)
{
    if (!g_NextRoundNewGame)
    {
        return Plugin_Continue;
    }
    g_NextRoundNewGame = false;
    ClearDatabase();   

    return Plugin_Continue;
}

public Action Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
    char szMessage[32];
    GetEventString(event, "message", szMessage, sizeof(szMessage));

    if (StrEqual(szMessage, "#Game_Commencing")) g_NextRoundNewGame = true;

    return Plugin_Continue;
}

public void OnMapStart()
{
    ClearDatabase();
}

public Action SaveAllScores(Handle timer)
{
    for (int client = 1, client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client) && IsClientAuthorized(client) && !justConnected[client])
        {
            g_iPlayerScore[client] = GetScore(client);
            g_iPlayerDeaths[client] = GetDeaths(client);
            g_iPlayerCash[client] = GetCash2(client);
            g_iPlayerAssists[client] = GetAssists(client);
            g_iPlayerRealScore[client] = GetContributionScore(client);
        }
    }

    return Plugin_Continue;
}

public void SyncDatabase()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !isFakeClient(client) && IsClientAuthorized(client))
        {
            char[] steamId[30];
            char[] query[200];

            GetClientAuthString(client, steamId, sizeof(steamId));
            int frags = GetScore(client);
            int deaths = GetDeaths(client);
            int cash = GetCash2(client);
            int assists = GetAssists(client);
            int realscore = GetContributionScore(client);

            Format(query, sizeof(query), "INSERT OR REPLACE INTO nl_saveinfo VALUES ('%s', %d, %d, %d, %d, %d, %d);", steamId, frags, deaths, cash, assists, realscore, GetTime());
            SQL_FastQuery(g_hDB, query);
        }
    }
}

public Action Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    if (!client) return Plugin_Continue;

    if (IsFakeClient(client) || !IsClientInGame(client)) return Plugin_Continue;

    if (GetEventInt(event, "team") == 1 && !justConnected[client])
    {
        InsertScoreInDB(client);
        return Plugin_Continue;
    }
    else if (GetEventInt(event, "team") > 1 && GetEventInt(event, "oldteam") < 2 && !justConnected[client])
    {
        onlyCash[client] = true;
        GetScoreFromDB(client);
    }
    else if (justConnected[client] && GetEventInt(event, "team") != 1)
    {
        justConnected[client] = false;
        GetScoreFromDB(client);
    }

    return Plugin_Continue;
}

// Kills
public int GetScore(client)
{
    return GetClientFrags(client);
}

public void SetPlayerScore(int client, int amount)
{
    SetEntProp(client, Prop_Data, "m_iFrags", amount);
}

// Deaths
public int GetDeaths(client)
{
    return GetEntProp(client, Prop_Data, "m_iDeaths");
}

public void SetClientDeaths(int client, int amount)
{
    SetEntProp(client, Prop_Data, "m_iDeaths", amount);
}

// Cash
public void SetPlayerCash(int client, int amount)
{
    SetEntData(client, g_iAccount, amount, 4, true);
}

public int GetPlayerCash(int client)
{
    return GetEntData(client, g_iAccount);
}

// Assists
public void SetPlayerAssists(int client, int amount)
{
    CS_SetClientAssists(client, amount);
}

public int GetPlayerAssists(int client)
{
    return CS_GetClientAssists(client);
}

// Contribution Score
public void SetContributionScore(int client, int amount)
{
    CS_SetClientContributionScore(client, amount);
}

public int GetContributionScore(int client)
{
    return CS_GetClientContributionScore(client);
}