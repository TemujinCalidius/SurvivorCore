// SurvivorCore Registration Script
// Description: Handles player registration with the statistics server
// Author: Temujin Calidius
// Date: April 2025
// Version: 1.0

default {
    state_entry() {
        llListen(12345, "", NULL_KEY, ""); // Listen for messages on channel 12345
    }

    listen(integer channel, string name, key id, string message) {
        list parts = llParseString2List(message, ["|"], []);
        string command = llList2String(parts, 0);

        if (command == "Register") {
            key playerKey = llList2Key(parts, 1);
            string playerName = llList2String(parts, 2);

            // Check if the player is already registered
            integer totalPrims = llGetNumberOfPrims();
            integer isRegistered = FALSE;

            integer i;
            for (i = 2; i <= totalPrims && !isRegistered; i++) { // Start from link 2 (skip root prim)
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);

                // Check if the player's key is already in the description (both formats)
                if (llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1 || 
                    llSubStringIndex(desc, "ID=" + (string)playerKey) != -1) {
                    isRegistered = TRUE;
                }
            }

            if (isRegistered) {
                // Notify the player they are already registered
                llInstantMessage(playerKey, "You are already registered, " + playerName + "!");
                return;
            }

            // Assign a pre-rezzed prim to the player
            integer assigned = FALSE;

            for (i = 2; i <= totalPrims && !assigned; i++) { // Start from link 2 (skip root prim)
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);

                // Check if the prim is unassigned (empty description)
                if (desc == "") {
                    // Assign the prim to the player using shorthand format
                    llSetLinkPrimitiveParamsFast(i, [
                        PRIM_DESC, "ID=" + (string)playerKey + ";LS=0;H=100;S=100;F=0;T=0;I=0;R=Survivor",
                        PRIM_NAME, playerName // Set the prim's name to the player's name
                    ]);

                    // Update floating text
                    llSetLinkPrimitiveParamsFast(i, [
                        PRIM_TEXT, playerName, <0, 1, 0>, 1.0 // Green text for the username (default)
                    ]);

                    assigned = TRUE;
                }
            }

            if (assigned) {
                // Notify the player of successful registration
                llInstantMessage(playerKey, "Welcome, " + playerName + "! You have been successfully registered.");

                // Notify the player's meter to initialize and fetch stats
                llRegionSayTo(playerKey, 67890, "InitializeMeter");
            } else {
                // Notify the player if no prims are available
                llInstantMessage(playerKey, "Sorry, " + playerName + ", no available slots for registration.");
            }
        }
    }
}
