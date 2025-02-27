integer SHORT_INTERVAL = 10; // Short interval for detecting avatars (in seconds)
list detectedUUIDs; // List to store detected UUIDs

// Function to detect avatars and store their UUIDs
detectAvatars() {
    list agents = llGetAgentList(AGENT_LIST_REGION, []); // Get a list of all avatars in the region
    integer count = llGetListLength(agents);

    if (count > 0) {
        for (integer i = 0; i < count; i++) {
            key avatarKey = llList2Key(agents, i); // Get the UUID of the avatar

            // Check if the UUID is already in the list
            if (llListFindList(detectedUUIDs, [avatarKey]) == -1) {
                // Add the UUID to the list if it's not already there
                detectedUUIDs += [avatarKey];
            }
        }
    }
}

default {
    state_entry() {
        llSetTimerEvent(SHORT_INTERVAL); // Start the short interval timer
    }

    timer() {
        detectAvatars(); // Call the detectAvatars function every 10 seconds
    }

    link_message(integer sender_num, integer num, string message, key id) {
        if (message == "RequestUUIDs") {
            // Send the list of detected UUIDs to the other script
            llMessageLinked(LINK_THIS, 0, "UUIDs|" + llList2CSV(detectedUUIDs), NULL_KEY);
        } else if (message == "ClearUUIDs") {
            // Clear the list of detected UUIDs
            detectedUUIDs = [];
        }
    }
}
