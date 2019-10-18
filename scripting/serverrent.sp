#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <SteamWorks>
#include <smjansson>
#include <get5>
#include <socket>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
	name = "Rent Inactivity",
	author = "PandahChan",
	description = "Kicks players if the server is inactive.",
	version = "1.0.0",
	url = "NexusLeague.gg"
};

public void OnPluginStart() 
{
    Handle jsonObj = json_object();
    char jData[1024];
    json_object_set_new(jsonObj, "dathost_id", json_string(dathost_id));
    json_dump(jsonObj, jData, sizeof(jData), 0, false, false, true);
    LogMessage("Created JSON is:\n%s\n", jData);
    CloseHandle(jsonObj);

}