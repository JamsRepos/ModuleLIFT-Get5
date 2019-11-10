## Plugins

### Ladder Statistics
Version: 1.1.0

### Cvars
```
sm_ladder_win "1" - The amount of points to give/take when a player wins a match.
sm_ladder_tie "1" - The amount of points to give/take when a player ties a match.
sm_ladder_lose "-1" - The amount of points to give/take when a player loses a match.
sm_ladder_master "-1" - If this is set to 1 the plugin will use this server as the master server to base all other servers ladder dates by.
sm_ladder_start "yyyy-mm-dd" - The date at which the stats will start being recorded.
sm_ladder_end "yyyy-mm-dd" - The date at which the stats will stop being recorded.
sm_ladder_reset "yyyy-mm-dd" - The date at which the stats will be reset.
```

### Setup
* Create a Database inside your MySQL Server (SQLite is not supported) for the plugin to use.
* Fill out a section in your databases.cfg (example below) to define the config that the plugin should use.
```
"Databases"
{
	"driver_default"		"mysql"
	
	// When specifying "host", you may use an IP address, a hostname, or a socket file path
	
	"ladder_stats"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"ladder_statistics"
		"user"				"user"
		"pass"				"pass"
	}
}
```
* Set cvars according to your settings.
* Drag and drop the plugin into addons/sourcemod/plugins and you should be good to go!
* If there are any problems with the plugin please create an issue with all details pertaining to the problem.
---

### SQL Matches
Version: 1.3.0

### Cvars
```
sm_discord_webhook "<webhook url>" - Webhook endpoint to send match stats to.
sm_site_url "https://www.example.com" - The URL of the site that contains the scoreboard.
sm_embed_color "16741688" - The embed color the webhook message should be (Must be a decimal value!).
sm_embed_avatar "https://imgur.com/myimage.png" - The avatar that the webhook should use.
```

### Setup
* Create a Database inside your MySQL Server (SQLite is not supported) for the plugin to use.
* Fill out a section in your databases.cfg (example below) to define the config that the plugin should use.
```
"Databases"
{
	"driver_default"		"mysql"
	
	// When specifying "host", you may use an IP address, a hostname, or a socket file path
	
	"sql_matches"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"sql_matches"
		"user"				"user"
		"pass"				"pass"
	}
}
```
* SteamWorks: https://forums.alliedmods.net/showthread.php?t=229556 and SMJansson: https://forums.alliedmods.net/showthread.php?t=184604 extensions are required.
* Install Splewis's Get5 plugin from https://github.com/splewis/get5
* Drag and drop the plugin into addons/sourcemod/plugins.
* Set cvars according to your settings, for help creating a webhook see here: https://support.discordapp.com/hc/en-us/articles/228383668
* For your site URL it should be formatted as `https://www.yoururl.com`, do not put a trailing slash at the end of your URL.
* For looking up decimal color values see this website: https://www.spycolor.com.  
* If there are any problems with the plugin please create an issue with all details pertaining to the problem.
---

### Load Match
* SteamWorks: https://forums.alliedmods.net/showthread.php?t=229556 and SMJansson: https://forums.alliedmods.net/showthread.php?t=184604 extensions are required.
---

### Kento RankME
(Using this plugin till ours is completed and stable.)
https://forums.alliedmods.net/showthread.php?p=2467665
