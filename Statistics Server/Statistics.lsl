integer COMM_CHANNEL_UUID = 67892; // Channel for UUID communication with UUID Handler
float TIMER_INTERVAL = 60.0; // Timer interval (1 minute for testing)
list playerUUIDs; // List to store player UUIDs

default {
    state_entry() {
        llListen(COMM_CHANNEL_UUID, "", NULL_KEY, ""); // Listen for UUID responses
        llSetTimerEvent(TIMER_INTERVAL); // Start the timer
        llOwnerSay("[Stats Script] Initialized. Timer set to 1 minute for testing.");
    }

    timer() {
        llOwnerSay("[Stats Script] Timer triggered. Sending RequestUUID to all UUID Handlers on channel 67892...");
        playerUUIDs = []; // Clear the list of player UUIDs
        llRegionSay(COMM_CHANNEL_UUID, "RequestUUID"); // Request UUIDs
    }

    listen(integer channel, string name, key id, string message) {
        llOwnerSay("[Stats Script] Received message on channel " + (string)channel + ": " + message);

        list parts = llParseString2List(message, ["|"], []);
        string command = llList2String(parts, 0);

        if (channel == COMM_CHANNEL_UUID && command == "UUID") {
            key playerKey = llList2Key(parts, 1); // Extract the player's UUID
            llOwnerSay("[Stats Script] Received UUID from UUID Handler: " + (string)playerKey);

            playerUUIDs += [playerKey]; // Add UUID to the list
            integer totalPrims = llGetNumberOfPrims();

            for (integer i = 2; i <= totalPrims; i++) { // Match UUID to linked prim descriptions
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);

                if (llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) {
                    llOwnerSay("[Stats Script] Found matching prim for player UUID: " + (string)playerKey);

                    // Update stats (same logic as before)
                    list data = llParseString2List(desc, [";", "="], []);
                    integer hungerIndex = llListFindList(data, ["Hunger"]) + 1;
                    integer thirstIndex = llListFindList(data, ["Thirst"]) + 1;
                    integer staminaIndex = llListFindList(data, ["Stamina"]) + 1;
                    integer healthIndex = llListFindList(data, ["Health"]) + 1;

                    integer hunger = (integer)llList2String(data, hungerIndex);
                    integer thirst = (integer)llList2String(data, thirstIndex);
                    integer stamina = (integer)llList2String(data, staminaIndex);
                    integer health = (integer)llList2String(data, healthIndex);

                    if (hunger < 100) hunger += 1;
                    if (thirst < 100) thirst += 1;
                    if (hunger == 100 || thirst == 100) stamina = (stamina > 0) ? stamina - 1 : 0;
                    if (stamina == 0) health = (health > 0) ? health - 1 : 0;

                    data = llListReplaceList(data, [(string)hunger], hungerIndex, hungerIndex);
                    data = llListReplaceList(data, [(string)thirst], thirstIndex, thirstIndex);
                    data = llListReplaceList(data, [(string)stamina], staminaIndex, staminaIndex);
                    data = llListReplaceList(data, [(string)health], healthIndex, healthIndex);

                    string updatedDesc = "";
                    integer dataLength = llGetListLength(data);
                    for (integer k = 0; k < dataLength; k += 2) {
                        updatedDesc += llList2String(data, k) + "=" + llList2String(data, k + 1) + ";";
                    }
                    updatedDesc = llDeleteSubString(updatedDesc, -1, -1);

                    llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, updatedDesc]);
                    llOwnerSay("[Stats Script] Updated prim description for player: " + updatedDesc);

                    // Send reinitialize command to UUID Handler
                    llRegionSay(COMM_CHANNEL_UUID, "Reinitialize|" + (string)playerKey);
                    llOwnerSay("[Stats Script] Sent reinitialize command to UUID Handler for player UUID: " + (string)playerKey);
                }
            }
        }
    }
}
