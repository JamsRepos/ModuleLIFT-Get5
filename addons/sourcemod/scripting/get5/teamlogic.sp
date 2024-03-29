public Action Command_JoinGame(int client, const char[] command, int argc) {
  if (g_GameState == Get5State_None) {
    return Plugin_Continue;
  }

  if (client != 0 && IsClientInGame(client) && !IsFakeClient(client)) {
      CreateTimer(0.5, AssignTeamOnConnect, client);
  }

  return Plugin_Continue;
}

public Action AssignTeamOnConnect(Handle timer, int client) {
    if (IsClientInGame(client)) {
        GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
        ChangeClientTeam(client, Get5_MatchTeamToCSTeam(Get5_GetPlayerTeam(steamid)));

        if (GameRules_GetProp("m_bMatchWaitingForResume") != 0 && GameRules_GetProp("m_bFreezePeriod") == 1 || g_GameState == Get5State_Warmup)
        {
          CS_RespawnPlayer(client);
        }     
        if (Get5_MatchTeamToCSTeam(Get5_GetPlayerTeam(steamid)) == 0)
        {
          KickClient(client, "You are not authorised to play this match. Join NexusLeague.gg to play");
        }
    }
    return Plugin_Continue;
}

public void CheckClientTeam(int client) {
  MatchTeam correctTeam = GetClientMatchTeam(client);
  int csTeam = MatchTeamToCSTeam(correctTeam);
  int currentTeam = GetClientTeam(client);

  if (csTeam != currentTeam) {
    if (IsClientCoaching(client)) {
      UpdateCoachTarget(client, csTeam);
    }

    SwitchPlayerTeam(client, csTeam);
  }
}

public Action Command_JoinTeam(int client, const char[] command, int argc) {
  if (!IsAuthedPlayer(client) || argc < 1)
    return Plugin_Stop;

  // Don't do anything if not live/not in startup phase.
  if (g_GameState == Get5State_None) {
    return Plugin_Continue;
  }

  // Don't enforce team joins.
  if (!g_CheckAuthsCvar.BoolValue) {
    return Plugin_Continue;
  }

  char arg[4];
  GetCmdArg(1, arg, sizeof(arg));
  int team_to = StringToInt(arg);

  LogDebug("%L jointeam command, from %d to %d", client, GetClientTeam(client), team_to);

  // don't let someone change to a "none" team (e.g. using auto-select)
  if (team_to == CS_TEAM_NONE) {
    return Plugin_Stop;
  }

  MatchTeam correctTeam = GetClientMatchTeam(client);
  int csTeam = MatchTeamToCSTeam(correctTeam);

  LogDebug("jointeam, gamephase = %d", GetGamePhase());

  if (g_PendingSideSwap) {
    LogDebug("Blocking teamjoin due to pending swap");
    // SwitchPlayerTeam(client, csTeam);
    return Plugin_Handled;
  }

  if (csTeam == team_to) {
    return Plugin_Continue;
  }

  if (csTeam != GetClientTeam(client)) {
    // SwitchPlayerTeam(client, csTeam);
    int count = CountPlayersOnCSTeam(csTeam);

    if (count >= g_PlayersPerTeam) {
      if (!g_CoachingEnabledCvar.BoolValue) {
        KickClient(client, "%t", "TeamIsFullInfoMessage");
      } else {
        LogDebug("Forcing player %N to coach", client);
        MoveClientToCoach(client);
        Get5_Message(client, "%t", "MoveToCoachInfoMessage");
      }
    } else {
      LogDebug("Forcing player %N onto %d", client, csTeam);
      FakeClientCommand(client, "jointeam %d", csTeam);
    }

    return Plugin_Stop;
  }

  return Plugin_Stop;
}

public void MoveClientToCoach(int client) {
  LogDebug("MoveClientToCoach %L", client);
  MatchTeam matchTeam = GetClientMatchTeam(client);
  if (matchTeam != MatchTeam_Team1 && matchTeam != MatchTeam_Team2) {
    return;
  }

  if (!g_CoachingEnabledCvar.BoolValue) {
    return;
  }

  int csTeam = MatchTeamToCSTeam(matchTeam);

  if (g_PendingSideSwap) {
    LogDebug("Blocking coach move due to pending swap");
    // SwitchPlayerTeam(client, CS_TEAM_SPECTATOR);
    // UpdateCoachTarget( client, csTeam);
    return;
  }

  char teamString[4];
  CSTeamString(csTeam, teamString, sizeof(teamString));

  // If we're in warmup or a freezetime we use the in-game
  // coaching command. Otherwise we manually move them to spec
  // and set the coaching target.
  if (!InWarmup() && !InFreezeTime()) {
    // TODO: this needs to be tested more thoroughly,
    // it might need to be done in reverse order (?)
    LogDebug("Moving %L directly to coach slot", client);
    SwitchPlayerTeam(client, CS_TEAM_SPECTATOR);
    UpdateCoachTarget(client, csTeam);
  } else {
    LogDebug("Moving %L indirectly to coach slot via coach cmd", client);
    g_MovingClientToCoach[client] = true;
    FakeClientCommand(client, "coach %s", teamString);
    g_MovingClientToCoach[client] = false;
  }
}

public Action Command_SmCoach(int client, int args) {
  if (g_GameState == Get5State_None) {
    return Plugin_Continue;
  }

  if (!g_CoachingEnabledCvar.BoolValue) {
    return Plugin_Handled;
  }

  MoveClientToCoach(client);
  return Plugin_Handled;
}

public Action Command_Coach(int client, const char[] command, int argc) {
  if (g_GameState == Get5State_None) {
    return Plugin_Continue;
  }

  if (!g_CoachingEnabledCvar.BoolValue) {
    return Plugin_Handled;
  }

  if (!IsAuthedPlayer(client)) {
    return Plugin_Stop;
  }

  if (InHalftimePhase()) {
    return Plugin_Stop;
  }

  if (g_MovingClientToCoach[client] || !g_CheckAuthsCvar.BoolValue) {
    LogDebug("Command_Coach: %L, letting pass-through", client);
    return Plugin_Continue;
  }

  MoveClientToCoach(client);
  return Plugin_Stop;
}

public MatchTeam GetClientMatchTeam(int client) {
  if (!g_CheckAuthsCvar.BoolValue) {
    return CSTeamToMatchTeam(GetClientTeam(client));
  } else {
    char auth[AUTH_LENGTH];
    if (GetAuth(client, auth, sizeof(auth))) {
      return GetAuthMatchTeam(auth);
    } else {
      KickClient(client, "You are not authorised to play this match. Join NexusLeague.gg to play");
      return MatchTeam_TeamNone;
    }
  }
}

public int MatchTeamToCSTeam(MatchTeam t) {
  if (t == MatchTeam_Team1) {
    return g_TeamSide[MatchTeam_Team1];
  } else if (t == MatchTeam_Team2) {
    return g_TeamSide[MatchTeam_Team2];
  } else if (t == MatchTeam_TeamSpec) {
    return CS_TEAM_SPECTATOR;
  } else {
    return CS_TEAM_NONE;
  }
}

public MatchTeam CSTeamToMatchTeam(int csTeam) {
  if (csTeam == g_TeamSide[MatchTeam_Team1]) {
    return MatchTeam_Team1;
  } else if (csTeam == g_TeamSide[MatchTeam_Team2]) {
    return MatchTeam_Team2;
  } else if (csTeam == CS_TEAM_SPECTATOR) {
    return MatchTeam_TeamSpec;
  } else {
    return MatchTeam_TeamNone;
  }
}

public MatchTeam GetAuthMatchTeam(const char[] steam64) {
  if (g_GameState == Get5State_None) {
    return MatchTeam_TeamNone;
  }

  if (g_InScrimMode) {
    return IsAuthOnTeam(steam64, MatchTeam_Team1) ? MatchTeam_Team1 : MatchTeam_Team2;
  }

  for (int i = 0; i < view_as<int>(MatchTeam_Count); i++) {
    MatchTeam team = view_as<MatchTeam>(i);
    if (IsAuthOnTeam(steam64, team)) {
      return team;
    }
  }
  return MatchTeam_TeamNone;
}

stock int CountPlayersOnCSTeam(int team, int exclude = -1) {
  int count = 0;
  for (int i = 1; i <= MaxClients; i++) {
    if (i != exclude && IsAuthedPlayer(i) && GetClientTeam(i) == team) {
      count++;
    }
  }
  return count;
}

stock int CountPlayersOnMatchTeam(MatchTeam team, int exclude = -1) {
  int count = 0;
  for (int i = 1; i <= MaxClients; i++) {
    if (i != exclude && IsAuthedPlayer(i) && GetClientMatchTeam(i) == team) {
      count++;
    }
  }
  return count;
}

public Action Event_OnPlayerTeam(Event event, const char[] name, bool dontBroadcast) {
  return Plugin_Continue;
}

// Returns the match team a client is the captain of, or MatchTeam_None.
public MatchTeam GetCaptainTeam(int client) {
  if (client == GetTeamCaptain(MatchTeam_Team1)) {
    return MatchTeam_Team1;
  } else if (client == GetTeamCaptain(MatchTeam_Team2)) {
    return MatchTeam_Team2;
  } else {
    return MatchTeam_TeamNone;
  }
}

public int GetTeamCaptain(MatchTeam team) {
  // If not forcing auths, take the 1st client on the team.
  if (!g_CheckAuthsCvar.BoolValue) {
    for (int i = 1; i <= MaxClients; i++) {
      if (IsAuthedPlayer(i) && GetClientMatchTeam(i) == team) {
        return i;
      }
    }
    return -1;
  }

  // For consistency, always take the 1st auth on the list.
  ArrayList auths = GetTeamAuths(team);
  char buffer[AUTH_LENGTH];
  for (int i = 0; i < auths.Length; i++) {
    auths.GetString(i, buffer, sizeof(buffer));
    int client = AuthToClient(buffer);
    if (IsAuthedPlayer(client)) {
      return client;
    }
  }
  return -1;
}

public int GetNextTeamCaptain(int client) {
  if (client == g_VetoCaptains[MatchTeam_Team1]) {
    return g_VetoCaptains[MatchTeam_Team2];
  } else {
    return g_VetoCaptains[MatchTeam_Team1];
  }
}

public ArrayList GetTeamAuths(MatchTeam team) {
  return g_TeamAuths[team];
}

public bool IsAuthOnTeam(const char[] auth, MatchTeam team) {
  return GetTeamAuths(team).FindString(auth) >= 0;
}

public void SetStartingTeams() {
  int mapNumber = GetMapNumber();
  if (mapNumber >= g_MapSides.Length || g_MapSides.Get(mapNumber) == SideChoice_KnifeRound) {
    g_TeamSide[MatchTeam_Team1] = TEAM1_STARTING_SIDE;
    g_TeamSide[MatchTeam_Team2] = TEAM2_STARTING_SIDE;
  } else {
    if (g_MapSides.Get(mapNumber) == SideChoice_Team1CT) {
      g_TeamSide[MatchTeam_Team1] = CS_TEAM_CT;
      g_TeamSide[MatchTeam_Team2] = CS_TEAM_T;
    } else {
      g_TeamSide[MatchTeam_Team1] = CS_TEAM_T;
      g_TeamSide[MatchTeam_Team2] = CS_TEAM_CT;
    }
  }

  g_TeamStartingSide[MatchTeam_Team1] = g_TeamSide[MatchTeam_Team1];
  g_TeamStartingSide[MatchTeam_Team2] = g_TeamSide[MatchTeam_Team2];
}

public void AddMapScore() {
  int currentMapNumber = GetMapNumber();

  g_TeamScoresPerMap.Set(currentMapNumber, CS_GetTeamScore(MatchTeamToCSTeam(MatchTeam_Team1)),
                         view_as<int>(MatchTeam_Team1));

  g_TeamScoresPerMap.Set(currentMapNumber, CS_GetTeamScore(MatchTeamToCSTeam(MatchTeam_Team2)),
                         view_as<int>(MatchTeam_Team2));
}

public int GetMapScore(int mapNumber, MatchTeam team) {
  return g_TeamScoresPerMap.Get(mapNumber, view_as<int>(team));
}

public bool HasMapScore(int mapNumber) {
  return GetMapScore(mapNumber, MatchTeam_Team1) != 0 ||
         GetMapScore(mapNumber, MatchTeam_Team2) != 0;
}

public int GetMapNumber() {
  return g_TeamSeriesScores[MatchTeam_Team1] + g_TeamSeriesScores[MatchTeam_Team2] +
         g_TeamSeriesScores[MatchTeam_TeamNone];
}

public bool AddPlayerToTeam(const char[] auth, MatchTeam team, const char[] name) {
  char steam64[AUTH_LENGTH];
  ConvertAuthToSteam64(auth, steam64);

  if (GetAuthMatchTeam(steam64) == MatchTeam_TeamNone) {
    GetTeamAuths(team).PushString(steam64);
    Get5_SetPlayerName(auth, name);
    return true;
  } else {
    return false;
  }
}

public bool RemovePlayerFromTeams(const char[] auth) {
  char steam64[AUTH_LENGTH];
  ConvertAuthToSteam64(auth, steam64);

  for (int i = 0; i < view_as<int>(MatchTeam_Count); i++) {
    MatchTeam team = view_as<MatchTeam>(i);
    int index = GetTeamAuths(team).FindString(steam64);
    if (index >= 0) {
      GetTeamAuths(team).Erase(index);
      int target = AuthToClient(steam64);
      if (IsAuthedPlayer(target) && !g_InScrimMode) {
        KickClient(target, "%t", "YourAreNotAPlayerInfoMessage");
      }
      return true;
    }
  }
  return false;
}

public void LoadPlayerNames() {
  KeyValues namesKv = new KeyValues("Names");
  int numNames = 0;
  LOOP_TEAMS(team) {
    char id[AUTH_LENGTH + 1];
    char name[MAX_NAME_LENGTH + 1];
    ArrayList ids = GetTeamAuths(team);
    for (int i = 0; i < ids.Length; i++) {
      ids.GetString(i, id, sizeof(id));
      if (g_PlayerNames.GetString(id, name, sizeof(name)) && !StrEqual(name, "") &&
          !StrEqual(name, KEYVALUE_STRING_PLACEHOLDER)) {
        namesKv.SetString(id, name);
        numNames++;
      }
    }
  }

  if (numNames > 0) {
    char nameFile[] = "get5_names.txt";
    DeleteFile(nameFile);
    if (namesKv.ExportToFile(nameFile)) {
      ServerCommand("sv_load_forced_client_names_file %s", nameFile);
    } else {
      LogError("Failed to write names keyvalue file to %s", nameFile);
    }
  }

  delete namesKv;
}

public void SwapScrimTeamStatus(int client) {
  // If we're in any team -> remove from any team list.
  // If we're not in any team -> add to team1.
  char auth[AUTH_LENGTH];
  if (GetAuth(client, auth, sizeof(auth))) {
    bool alreadyInList = RemovePlayerFromTeams(auth);
    if (!alreadyInList) {
      char steam64[AUTH_LENGTH];
      ConvertAuthToSteam64(auth, steam64);
      GetTeamAuths(MatchTeam_Team1).PushString(steam64);
    }
  }
  CheckClientTeam(client);
}
