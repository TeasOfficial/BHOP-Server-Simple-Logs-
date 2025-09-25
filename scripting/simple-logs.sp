#include <sourcemod>
#include <sdktools>
#include <morecolors>
#include <geoip>
#include <shavit/core>
#include <shavit/wr>
#include <logging>

public Plugin myinfo = 
{
    name = "BHOP Server Simple Logs",
    author = "Picrisol45",
    description = "Record logs for a BunnyHop server (only supports shavit timer)",
    version = "1.01",
    url = ""
};

char gS_Mapname[64];

/*- - - - - Messages that you didnt want to be sent to log - - - - -*/
char g_BlockMessages[][] = 
{
    "!r",   // "!r" and "/r" is recommended to add otherwise it will fill up your log files.
    "/r"
};
/*
// Prefixes we don't want to log (disabled for now)
char g_BlockPrefix[][] =
{
     "!"
};
*/

public void OnPluginStart()
{
    HookEvent("player_connect", Event_PlayerConnect, EventHookMode_Pre);
    //HookEvent("player_connect_client", Event_PlayerConnectClient, EventHookMode_Pre);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

    AddCommandListener(OnPlayerSay, "say");
    AddCommandListener(OnPlayerSay, "say_team");
}

public Action OnLogAction(Handle source, Identity ident, int client, int target, const char[] message)
{
    PrintToServer("[OnLogAction] msg: %s", message);
    return Plugin_Continue; // 继续默认日志
}

// Simple log writer(automatically update files based on date)
stock void WriteLog(const char[] format, any ...)
{
    char logfile[PLATFORM_MAX_PATH];
    char timestr[32];
    FormatTime(logfile, sizeof(logfile), "addons/sourcemod/logs/server_%Y-%m-%d.log");
    FormatTime(timestr, sizeof(timestr), "%H:%M:%S");

    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 2);

    LogToFileEx(logfile, "%s", buffer);
}

// Logs when player switches team
public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientInGame(client))
        return;

    int oldTeam = event.GetInt("oldteam");
    int newTeam = event.GetInt("team");

    // Only log spectator <-> player team switches
    bool oldSpec = (oldTeam == 1);
    bool newSpec = (newTeam == 1);

    if (oldSpec == newSpec) // No actual team change, ignore
        return;

    char playerName[64], steamID[32];
    GetClientName(client, playerName, sizeof(playerName));
    GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID));

    char logMsg[256];
    if (newSpec)
    {
        Format(logMsg, sizeof(logMsg), "[Team] \"%s <%s>\" joined the Spectators", playerName, steamID);
    }
    else
    {
        Format(logMsg, sizeof(logMsg), "[Team] \"%s <%s>\" joined the Bhoppers", playerName, steamID);
    }

    WriteLog(logMsg);
}

// Logs when map changes
public void OnMapStart()
{
    GetCurrentMap(gS_Mapname, sizeof(gS_Mapname));
    
    WriteLog("- - - - - >>> Map changed to: %s <<< - - - - -", gS_Mapname);
}

void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
    char name[MAX_NAME_LENGTH];
    char styleName[64];
    char steamID[32];

    GetClientName(client, name, sizeof(name));
    GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID));
    Shavit_GetStyleStrings(newstyle, sStyleName, styleName, sizeof(styleName));

    WriteLog("[→] %s <%s> have chosen the style \"%s\"", name, steamID, styleName);
}


void Shavit_OnTrackChanged(int client, int oldtrack, int newtrack)
{
    char name[MAX_NAME_LENGTH];
    char steamID[32];
    char trackName[16];

    GetClientName(client, name, sizeof(name));
    GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID));

    (newtrack == 0)  ? strcopy(trackName, sizeof(trackName), "Main") : Format(trackName, sizeof(trackName), "Bonus %d", newtrack);

    WriteLog("[→] %s <%s> have chosen to play track \"%s\"", name, steamID, trackName);

}

// Logs when players finished map(only support shavit timer)(FirstCompletion/Personal Best/Server Record/Not PB/Practice Mode)
public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    char name[MAX_NAME_LENGTH];
    char steamID[32];
    char trackName[16];
    char prefix[32];
    char styleName[64]; // style strings
    float SRTime, PB_Diff, SR_Diff;

    SRTime = Shavit_GetTimeForRank(style, 1, track);

    PB_Diff = time - oldtime;
    SR_Diff = time - SRTime;

    Shavit_GetStyleStrings(style, sStyleName, styleName, sizeof(styleName));

    // Detect if it's Main or Bonus track
    (track == 0)  ? strcopy(trackName, sizeof(trackName), "Main") : Format(trackName, sizeof(trackName), "Bonus %d", track);

    GetClientName(client, name, sizeof(name));
    GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID));

    // Add + sign if the diff is positive
    char PB_DiffSign[2], SR_DiffSign[2];
    strcopy(PB_DiffSign, sizeof(PB_DiffSign), (PB_Diff >= 0.0) ? "+" : "");
    strcopy(SR_DiffSign, sizeof(SR_DiffSign), (SR_Diff >= 0.0) ? "+" : "");

    // Build PB and SR time diff strings
    char SR_DiffStr[32], PB_DiffStr[32];
    if (SRTime != 0.0)
        Format(SR_DiffStr, sizeof(SR_DiffStr), "%s%.3f", SR_DiffSign, SR_Diff);
    else
        strcopy(SR_DiffStr, sizeof(SR_DiffStr), "N/A");

    if (oldtime != 0.0)
        Format(PB_DiffStr, sizeof(PB_DiffStr), "%s%.3f", PB_DiffSign, PB_Diff);
    else
        strcopy(PB_DiffStr, sizeof(PB_DiffStr), "N/A");

    // Determine prefix based on run result
    if (Shavit_IsPracticeMode(client))
        strcopy(prefix, sizeof(prefix), "[Practice]");
    else if (oldtime == 0.0)
        strcopy(prefix, sizeof(prefix), "[FirstCompletion]");
    else if (time < SRTime)
        strcopy(prefix, sizeof(prefix), "[SR]");
    else if (time >= SRTime && time < oldtime)
        strcopy(prefix, sizeof(prefix), "[PB]");
    else
        strcopy(prefix, sizeof(prefix), "");

    // Build final log line
    char msg[256];
    Format(msg, sizeof(msg),
        "%s %s <%s> finished %s [%s] - %s | Time: %.3f (SR: %s, PB: %s) | Jumps: %d | Strafes: %d | Sync: %.2f%% | Old Best: %.3f s | MaxVel: %.1f",
        prefix, name, steamID, gS_Mapname, trackName, styleName, time,
        SR_DiffStr, PB_DiffStr,
        jumps, strafes, (sync >= 0.0 ? sync : -1.0), oldtime, maxvel);

    WriteLog(msg);
}

// Logs when a player sends a chat message
public Action OnPlayerSay(int client, const char[] command, int argc)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Continue;

    char sArgs[256];
    GetCmdArgString(sArgs, sizeof(sArgs));
    StripQuotes(sArgs); // Remove quotes but keep the original message (including /)

    // Ignore blocked messages
    for (int i = 0; i < sizeof(g_BlockMessages); i++)
    {
        if (StrEqual(sArgs, g_BlockMessages[i], false))
        {
            return Plugin_Handled;
        }
    }

    char name[64];
    char steamid[64];

    GetClientName(client, name, sizeof(name));
    GetClientAuthId(client, AuthId_Steam3, steamid, sizeof(steamid));

    WriteLog("\"%s <%s>\" say: \"%s\"", name, steamid, sArgs);

    return Plugin_Continue;
}

// Logs when connect event
public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{  
    char playerName[64];
    char steamID3[32];
    char steamID2[32];
    char ip[64];
    char message_log[256];
    char Country[99];
    char Country_Code2[3];

    event.GetString("name", playerName, sizeof(playerName));
    event.GetString("networkid", steamID3, sizeof(steamID3));
    event.GetString("address", ip, sizeof(ip));

    if (StrEqual(steamID3, "BOT", false))
    {
        // Skip if it's a bot
        return Plugin_Continue;
    }

    // Handle unknown IP
    if (!GeoipCountry(ip, Country, sizeof Country))
    {
        Country = "UnknownCountry";
    }

    if (!GeoipCode2(ip, Country_Code2))
    {
        Country_Code2 = "NO";
    }

    if (!ConvertSteamID3ToSteamID2(steamID3, steamID2, sizeof(steamID2)))
    {
        strcopy(steamID2, sizeof(steamID2), steamID3);
    }

    Format(message_log, sizeof(message_log), "▲ %s <%s, %s> connected from %s (%s)", playerName, steamID2, ip, Country, Country_Code2);

    WriteLog("%s", message_log);

    return Plugin_Handled;
}

// Logs when player is fully in the server
public void OnClientPutInServer(int client)
{
    if (!IsClientInGame(client))
        return;

    // Delay message for smoother experience
    CreateTimer(1.5, Timer_SendConnectMessage, client);
}

// Timer callback
public Action Timer_SendConnectMessage(Handle timer, any client)
{
    if (!IsClientInGame(client))
        return Plugin_Stop;

    char name[MAX_NAME_LENGTH];
    char steamID[32];

    GetClientName(client, name, sizeof(name));
    GetClientAuthString(client, steamID, sizeof(steamID));

    WriteLog("▲ %s has joined.", name);

    return Plugin_Stop;
}

// Logs when player disconnect.
public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    SetEventBroadcast(event, true);
    
    char playerName[64];
    char steamID3[32];
    char steamID2[32];
    char reason[128];

    event.GetString("name", playerName, sizeof(playerName));
    event.GetString("networkid", steamID3, sizeof(steamID3));
    event.GetString("reason", reason, sizeof(reason));

    if (!ConvertSteamID3ToSteamID2(steamID3, steamID2, sizeof(steamID2)))
    {
        strcopy(steamID2, sizeof(steamID2), steamID3);
    }

    WriteLog("▼ %s <%s> disconnected. (%s)", playerName, steamID2, reason);

    return Plugin_Continue;
}

// Convert SteamID3 -> SteamID2 (quick and dirty, FUCKYOU SOURCEPAWN)
bool ConvertSteamID3ToSteamID2(const char[] steamID3, char[] steamID2, int maxlen)
{
    int length = strlen(steamID3);
    int lastColon = -1;

    for (int i = length - 1; i >= 0; i--)
    {
        if (steamID3[i] == ':')
        {
            lastColon = i;
            break;
        }
    }

    if (lastColon == -1)
        return false;

    int numLen = length - lastColon - 2; // remove ':' and ']'

    if (numLen <= 0 || numLen >= 32)
        return false;

    char idStr[32];
    for (int j = 0; j < numLen; j++)
    {
        idStr[j] = steamID3[lastColon + 1 + j];
    }
    idStr[numLen] = '\0';

    int accountID = StringToInt(idStr);

    int Y = accountID % 2;
    int Z = accountID / 2;

    Format(steamID2, maxlen, "STEAM_0:%d:%d", Y, Z);

    return true;
}
