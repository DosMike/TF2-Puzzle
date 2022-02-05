# TF2 Puzzle

I want to make puzzle/coop maps for TF2 similar to HL2DM Puzzle servers.
This requires a gravity gun in most cases to move around props, so this is the main aspect.

Clarification: The goal of this plugin is NOT to make old puzzle maps compatible with TF2!
This plugin only serves as a utility to allow puzzle style maps to be created.
( Or for a cheap GravGun if you're after that :D )

## Gravity Hands

Players can use `/hands` or `/holster` to put away their weapons. 
This equips players with non-damaging fists (breaking heavys stock fists in the process but whatever).
Physics props below a mass of 250 can be moved around with right click and can be punted away.
It tries to fire apropriate physgun related outputs and to honor frozen and motion disabled props.

Left-clicking while holding a prop will punt it, otherwise left-click is just a normal melee punch.

## Custom map logic

The second big part is custom map logic for puzzle maps (with `_puzzle_` in their name). This is required
because sometimes you want the player in a certain state and the builtins don't quite do it.

The way this is done is by adding outputs to any entity with TF2Puzzle as Command. This will print warnings
in developer mode, because those are not real outputs, but the plugin will understand them. The only problem
is that sourcemod can not handle more than 2MB of map logic to pre-parse, or it will fail to load/crash(?).
To help you keep track of this bsp lump, the plugin will print the lump size before map start.

Note on weapon stripping: The plugin always tries to give at least the gravity hands to prevent T-posing.

### `!activator,TF2Puzzle,Strip`
Take all weapons from the player

### `!activator,TF2Puzzle,Regenerate`
Silently regenerate a player like a func_regenerate, but you can filter the trigger for classes.

### `!activator,TF2Puzzle,StripWhitelist <filter>`
Same as Strip, but you can specify weapons the player can keep.
Filter is a **space** separated list of weapon class names or weapon slots.

For example if you want to filter a players inventory for trimp sections, you can use the following filter
for demomen:   
`!activator,TF2Puzzle,StripWhitelist tf_wearable tf_wearable_demoshield 3`    
The wearables in this case would be the boots, since those are the only wearables on demoman. All shields
use the same classname and the `3` allows any melee weapon.

### `!activator,TF2Puzzle,ResetCooldowns`
Reset most player cooldowns:
Energy Drink Meter, Hype Meter, Charge Meter, Cloak Meter, Rage Meter, Stealth Cooldown and Kart Boost Cooldown

### `!self,TF2Puzzle,CreateVehicle <vehicle>`
This is a synergy output that tries to interact with Mikusch/source-vehicles. If the configuration of
that vehicle plugin contains a section with the specified name, it will try to spawn the vehicle at the
target. I recommend using an `OnUserX` output for a `info_target`. Note that vehicles might be rotated by
90 deg. If you need them spawned without interaction, use a `logic_auto`s `OnMapStart`. The default
vehicles available are `hl2_jeep` and `hl2_airboat`.

## Natives and Forwards

Plugin developers get rich access to the GraviHand feature, being allowed to check when melee weapons are 
(un)holstered as well as limited control over what physics entities can be picked up.

Check the [include file](https://github.com/DosMike/TF2-Puzzle/blob/master/tf2puzzle.inc) for more info.

## Dependencies

* [VPhysics](https://forums.alliedmods.net/showthread.php?t=136350?t=136350)
* [TF2Items](https://forums.alliedmods.net/showthread.php?p=1050170?p=1050170)
* [TF2 Attributes](https://github.com/nosoop/tf2attributes)
* One of the following Item Plugins:
  * [TF Econ Data](https://github.com/nosoop/SM-TFEconData) (Not YET recommended, compat layer is a bit broken as of writing)
  * [TF2 ItemDB](https://forums.alliedmods.net/showthread.php?t=255885)
* [Source Vehicles](https://github.com/Mikusch/source-vehicles) (Optional)