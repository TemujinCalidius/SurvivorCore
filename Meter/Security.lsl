integer COMM_CHANNEL = 67891; // Channel for the Security Script
key playerKey; // The player's UUID
integer serverFound = FALSE; // Flag to track if a server is found
integer listenHandle; // Handle for the listener
integer isWaitingForResponse = FALSE; // Flag to track if the script is waiting for a response

// Function to check for a server
checkForServer() {
    if (isWaitingForResponse) {
        return; // Prevent multiple overlapping checks
    }

    serverFound = FALSE; // Reset server flag
    isWaitingForResponse = TRUE; // Set the waiting flag

    // Send a request to the statistics server with the Security Script's channel
    string message = "RequestStats|" + (string)playerKey + "|" + (string)COMM_CHANNEL;
    llRegionSay(67890, message);

    // Set up a listener for the communication channel
    listenHandle = llListen(COMM_CHANNEL, "", NULL_KEY, "");
}

default {
    state_entry() {
        playerKey = llGetOwner(); // Get the player's UUID
        llOwnerSay("Security Script initialized. Player UUID: " + (string)playerKey);

        // Call the function to check for a server
        checkForServer();
    }

    changed(integer change) {
        if (change & CHANGED_REGION) {
            // The avatar has entered a new region
            llOwnerSay("Region change detected. Sending ResetMeter command.");
            llMessageLinked(LINK_THIS, 0, "ResetMeter", ""); // Send ResetMeter command to the Meter Script
            checkForServer(); // Perform a server check after region change
        }
    }

    listen(integer channel, string name, key id, string message) {
        // Parse the incoming message
        list parts = llParseString2List(message, ["|"], []);
        string command = llList2String(parts, 0);

        if (command == "Stats") {
            serverFound = TRUE; // Server is present
            llListenRemove(listenHandle); // Remove the listener
            isWaitingForResponse = FALSE; // Reset the waiting flag
            llOwnerSay("Server found. Stats received.");
        } else if (command == "Error") {
            string errorMessage = llList2String(parts, 1);
            if (errorMessage == "PrimNotFound") {
                // No server found
                serverFound = FALSE;
                llListenRemove(listenHandle); // Remove the listener
                isWaitingForResponse = FALSE; // Reset the waiting flag
                llOwnerSay("Error: Prim not found. No server available.");
            }
        }
    }

    link_message(integer sender_num, integer num, string str, key id) {
        // Handle linked messages from other scripts in the same object
        if (str == "Reinitialize") {
            checkForServer(); // Re-check the server
        }
    }
}
