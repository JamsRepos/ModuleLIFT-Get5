![DNH Logo](https://camo.githubusercontent.com/742c455547018630cf337754b6e93a16e880dbd2/68747470733a2f2f63646e2e646973636f72646170702e636f6d2f6174746163686d656e74732f3433353630313839363836323930383433372f3533383532363832363139323936313533362f6e626664666864666864686468642e706e67)

## Status
- Get5 - Newly Forked.
- Pausing system rewritten to allow 3 different styles of pause systems.

## Planned Features
  - Remove ready system, start once all players join.
  - Remove vetos, just load the correct map. 
  - Official Matchmaking.
  - Official SM 1.10 Support.

## Pause System
This section will discuss about the Pause system which is a bit different from the default Get5 pausing system.

This pause system has 3 modes:
- Get5 default pausing: This pause system works very similar to the Get5 original pause system with "Fixed time" pauses. 
This will use the current cvars set. Please see [Get5](https://github.com/splewis/get5), if you are having issues understanding
how this pause system works.

- Valve pausing system: This pause system will use the pause vote which is default within panorama and requires players to vote on if they want to pause or not, this will then use default server settings. The CVars needed to tweak are as follows:
``sv_allow_votes 1`` **Must be enabled**
``mp_team_timeout_time`` - This value is how long the time which you want to set on the server.
``mp_team_timeout_max`` - This is how many timeouts a player can have **Per match**

- Faceit pausing system: This pause system was supposed to be designed within Get5 originally but it didn't work correctly, so it was revamped. This pause system requires tweaking of the ``get5_max_pause_time``. This is how long a player can pause in the match.

To use this system you will need to edit the ``get5_pause_mode`` within the config to either "Faceit", "Valve" or if left blank will default to Get5 pausing mode. 
