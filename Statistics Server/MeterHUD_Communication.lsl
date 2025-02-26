integer COMM_CHANNEL = 67890; // Default channel for meter and HUD communication

default {
    state_entry() {
        llListen(COMM_CHANNEL, "", NULL_KEY, ""); // Listen for messages on the communication channel
    }

    listen(integer channel, string name, key id, string message) {
        // Parse the incoming message
        list parts = llParseString2List(message, ["|"], []);
        string command = llList2String(parts, 0);

        if (command == "RequestStats") {
            key playerKey = llList2Key(parts, 1); // Extract the player's UUID
            integer responseChannel = (integer)llList2String(parts, 2); // Extract the channel to respond to

            // Search for the player's prim
            integer totalPrims = llGetNumberOfPrims();
            for (integer i = 2; i <= totalPrims; i++) { // Start from link 2 (skip root prim)
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);

                // Check if the player's UUID is in the description
                if (llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) { // Match "UUID=value"
                    // Send the description back to the specified channel
                    llRegionSay(responseChannel, "Stats|" + desc);
                    return;
                }
            }

            // If no prim is found, notify the requesting script
            llOwnerSay("RequestStats: No matching prim found for UUID: " + (string)playerKey); // Debug message
            llRegionSay(responseChannel, "Error|PrimNotFound");
        } else if (command == "ReduceHealth") {
            // Reduce the player's health
            integer amount = (integer)llList2String(parts, 1);
            key playerKey = llList2Key(parts, 2);

            // Find the player's prim and update health
            integer totalPrims = llGetNumberOfPrims();
            for (integer i = 2; i <= totalPrims; i++) {
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);

                if (llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) { // Match "UUID=value"
                    list data = llParseString2List(desc, [";", "="], []);
                    integer healthIndex = llListFindList(data, ["Health"]) + 1;
                    integer health = (integer)llList2String(data, healthIndex);
                    health -= amount;
                    if (health < 0) health = 0;

                    // Update the health value in the list
                    data = llListReplaceList(data, [(string)health], healthIndex, healthIndex);

                    // Reconstruct the description string with "=" delimiters
                    string updatedDesc = "";
                    integer dataLength = llGetListLength(data);
                    for (integer j = 0; j < dataLength; j += 2) {
                        updatedDesc += llList2String(data, j) + "=" + llList2String(data, j + 1) + ";";
                    }

                    // Remove the trailing semicolon
                    updatedDesc = llDeleteSubString(updatedDesc, -1, -1);

                    // Update the prim description
                    llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, updatedDesc]);

                    // Notify the meter of the updated stats
                    llRegionSayTo(playerKey, COMM_CHANNEL, "Stats|" + updatedDesc);
                    return;
                }
            }

            // If no prim is found, notify the meter
            llOwnerSay("ReduceHealth: No matching prim found for UUID: " + (string)playerKey); // Debug message
            llRegionSayTo(playerKey, COMM_CHANNEL, "Error|PrimNotFound");
        }
    }
}