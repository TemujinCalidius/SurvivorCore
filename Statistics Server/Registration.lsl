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
            if (isPlayerRegistered(playerKey)) {
                // Notify the player they are already registered
                llInstantMessage(playerKey, "You are already registered, " + playerName + "!");
                return;
            }

            // Assign a pre-rezzed prim to the player
            if (assignUnassignedPrim(playerKey, playerName)) {
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

// Check if a player is already registered
integer isPlayerRegistered(key playerKey) {
    integer totalPrims = llGetNumberOfPrims();
    for (integer i = 2; i <= totalPrims; i++) { // Start from link 2 (skip root prim)
        string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);

        // Check if the player's key is already in the description
        if (llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) {
            return TRUE; // Player is already registered
        }
    }
    return FALSE; // Player is not registered
}

// Assign an unassigned prim to a player
integer assignUnassignedPrim(key playerKey, string playerName) {
    integer totalPrims = llGetNumberOfPrims();
    for (integer i = 2; i <= totalPrims; i++) { // Start from link 2 (skip root prim)
        string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);

        // Check if the prim is unassigned (empty description)
        if (desc == "") {
            // Assign the prim to the player
            llSetLinkPrimitiveParamsFast(i, [
                PRIM_DESC, "UUID=" + (string)playerKey + ";LastSeen=0;Health=100;Stamina=100;Hunger=0;Thirst=0;Infection=0;Role=Survivor",
                PRIM_NAME, playerName // Set the prim's name to the player's name
            ]);

            // Update floating text
            updateFloatingText(i, playerName);

            return TRUE; // Prim assigned successfully
        }
    }
    return FALSE; // No available prims
}

// Update floating text on the assigned prim
updateFloatingText(integer linkNum, string playerName) {
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_TEXT, playerName, <0, 1, 0>, 1.0 // Green text for the username (default)
    ]);
}
