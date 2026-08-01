--!nonstrict
--[[
	Demo stage toggles — ONE place to control what the demo places in the world.

	The demo furnishes a world so the engine has something to DO out of the box. Turn any of it
	off for a CLEAN STAGE: filming, screenshots, or building your own world on top of the engine
	without the demo's furniture in shot.

	Content DEFINITIONS (items, recipes, quests, achievements, mob types) are always registered
	regardless — so the admin plugin's pickers still list `reed_bush`, `husk`, `boar` and friends,
	and you can point your own objects at real content. These flags only control what gets PLACED
	in the world and what the player starts with.

	Set them all to false and pressing Play gives you an empty baseplate.
]]

return {
	WorldContent = true, -- the gather field (trees + reeds) and the quest post
	Mobs = true, -- the husks + the boar
	SeedInventory = true, -- the starting items, hotbar pins and worn equipment

	-- OFF by default: these are hand-test scaffolding (a labelled row of DAMAGE / FEED / POISON /
	-- BLEED prompts, plus item pickups) for exercising the stat and inventory APIs. Useful when
	-- you're working ON the engine, but they crowd the spawn area for everyone else. Flip on when
	-- you want to poke the survival systems by hand.
	TestStations = false,
}
