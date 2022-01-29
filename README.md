# TF2 Puzzle

I want to make puzzle/coop maps for TF2 similar to HL2DM Puzzle servers.
This requires a gravity gun in most cases to move around props, so this is the main aspect.

Players can use /hands or /holster to put away their weapons. 
This equips players with non-damaging fists (breaking heavys stock fists in the process but whatever).
Physics props below a mass of 250 can be moved around with right click and can be punted away.
It tries to fire apropriate physgun related outputs and to honor frozen and motion disabled props.

There is some additional logic being worked on for maps with `_puzzle_` in their name, but I'm still
working on that part...