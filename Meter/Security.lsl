integer COMM_CHANNEL = 67891; // Channel for the Security Script
key playerKey; // The player's UUID
integer serverFound = FALSE; // Flag to track if a server is found
integer isRegistered = FALSE; // Flag to track if the player is registered
float SERVER_TIMEOUT = 5.0; // Timeout in seconds to wait for a server response
integer listenHandle; // Handle for the listener
integer isWaitingForResponse = FALSE; // Flag to track if the script is waiting for a response

// Function to check for a server
checkForServer() {
    if (isWaitingForResponse) {
        llOwnerSay("[Security Script] Already waiting for a response. Ignoring new server check request.");
        return; // Prevent multiple overlapping checks
    }

    serverFound = FALSE; // Reset server flag
    isRegistered = FALSE; // Reset registration flag
    isWaitingForResponse = TRUE; // Set the waiting flag

    // Send a request to the statistics server with the Security Script's channel
    string message = "RequestStats|" + (string)playerKey + "|" + (string)COMM_CHANNEL;
    llOwnerSay("[Security Script] Sending message to stats server: " + message); // Debug message
    llRegionSay(67890, message);

    // Set up a listener for the communication channel
    listenHandle = llListen(COMM_CHANNEL, "", NULL_KEY, "");

    // Start a timer to wait for a response
    llSetTimerEvent(SERVER_TIMEOUT);
}

default {
    state_entry() {
        playerKey = llGetOwner(); // Get the player's UUID

        // Call the function to check for a server
        checkForServer();
    }

    changed(integer change) {
        if (change & CHANGED_REGION) {
            // The avatar has entered a new region
            llOwnerSay("[Security Script] Region changed. Checking for server...");
            checkForServer(); // Call the function here
        }
    }

    listen(integer channel, string name, key id, string message) {
        llOwnerSay("[Security Script] Received message on channel " + (string)channel + ": " + message);

        // Parse the incoming message
        list parts = llParseString2List(message, ["|"], []);
        string command = llList2String(parts, 0);

        if (command == "Stats") {
            serverFound = TRUE; // Server is present
            llSetTimerEvent(0.0); // Stop the timeout timer
            llListenRemove(listenHandle); // Remove the listener
            isWaitingForResponse = FALSE; // Reset the waiting flag

            string description = llList2String(parts, 1);

            // Parse the description to check if the player's UUID matches
            list data = llParseString2List(description, [";", "="], []);
            string uuid = llList2String(data, llListFindList(data, ["UUID"]) + 1);

            if (uuid == (string)playerKey) {
                isRegistered = TRUE; // Player is registered
                llMessageLinked(LINK_THIS, 0, "Stats|" + description, ""); // Notify the meter script with updated stats
                llOwnerSay("[Security Script] Player is registered with the statistics server.");
            } else {
                isRegistered = FALSE; // Player is not registered
                llMessageLinked(LINK_THIS, 0, "NotRegistered", ""); // Notify the meter script
                llOwnerSay("[Security Script] Player is not registered with the statistics server.");
            }
        } else if (command == "Error") {
            string errorMessage = llList2String(parts, 1);
            if (errorMessage == "PrimNotFound") {
                // Player is not registered
                isRegistered = FALSE;
                llSetTimerEvent(0.0); // Stop the timeout timer
                llListenRemove(listenHandle); // Remove the listener
                isWaitingForResponse = FALSE; // Reset the waiting flag
                llMessageLinked(LINK_THIS, 0, "NotRegistered", ""); // Notify the meter script
                llOwnerSay("[Security Script] No matching prim found for UUID.");
            }
        }
    }

    link_message(integer sender_num, integer num, string str, key id) {
        // Handle linked messages from other scripts in the same object
        if (str == "Reinitialize") {
            llOwnerSay("[Security Script] Reinitialize message received via linked message. Checking for server...");
            checkForServer(); // Re-check the server
        }
    }

    timer() {
        // Timeout occurred, no response from the server
        if (!serverFound) {
            llListenRemove(listenHandle); // Remove the listener
            llMessageLinked(LINK_THIS, 0, "NoServer", ""); // Notify the meter script to hide floating text
            llOwnerSay("[Security Script] No statistics server detected in this region.");
        }
        isWaitingForResponse = FALSE; // Reset the waiting flag
        llSetTimerEvent(0.0); // Stop the timer
    }
}
