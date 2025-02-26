integer COMM_CHANNEL_UUID = 67892; // Channel for UUID communication
key playerKey; // The player's UUID

default {
    state_entry() {
        playerKey = llGetOwner(); // Store the player's UUID
        llListen(COMM_CHANNEL_UUID, "", NULL_KEY, ""); // Listen for messages on the UUID channel
    }

    listen(integer channel, string name, key id, string message) {
        list parts = llParseString2List(message, ["|"], []);
        string command = llList2String(parts, 0);

        if (command == "RequestUUID") {
            llRegionSay(COMM_CHANNEL_UUID, "UUID|" + (string)playerKey);
        } else if (command == "Reinitialize") {
            string uuid = llList2String(parts, 1);
            if (uuid == (string)playerKey) {
                llMessageLinked(LINK_THIS, 0, "ResetMeter", ""); // Notify only the Meter Script to reset
            }
        }
    }
}
