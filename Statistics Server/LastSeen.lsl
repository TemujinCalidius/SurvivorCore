integer LONG_INTERVAL = 86400; // Long interval for comparing and updating linked prims (in seconds, for testing)
list detectedUUIDs; // Temporary list to store UUIDs received from the short interval script

// Function to clean and extract the raw UUID from a string
string cleanUUID(string rawUUID) {
    // Remove any extra characters (e.g., "UUID: ", spaces, brackets, etc.)
    return llStringTrim(rawUUID, STRING_TRIM); // Trim any leading/trailing whitespace
}

// Function to compare and update linked prim descriptions
updateLinkedPrimDescriptions() {
    integer totalPrims = llGetNumberOfPrims();

    for (integer i = 2; i <= totalPrims; i++) { // Start from 2 to skip the root prim
        string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]); // Get the description of the linked prim
        string objectName = llGetLinkName(i); // Get the name of the linked prim
        list data = llParseString2List(desc, [";", "="], []); // Parse the description into key-value pairs

        // Find the UUID in the description
        integer uuidIndex = llListFindList(data, ["UUID"]) + 1;
        if (uuidIndex != 0) {
            string rawPrimUUID = llList2String(data, uuidIndex); // Extract the raw UUID from the description
            key primUUID = (key)cleanUUID(rawPrimUUID); // Clean and convert it to a key

            // Check if the cleaned UUID is in the detectedUUIDs list
            integer lastSeenIndex = llListFindList(data, ["LastSeen"]) + 1;
            if (lastSeenIndex != 0) {
                integer lastSeenValue = (integer)llList2String(data, lastSeenIndex);

                if (llListFindList(detectedUUIDs, [primUUID]) != -1) {
                    // UUID has been detected, set LastSeen=0
                    lastSeenValue = 0;
                    data = llListReplaceList(data, ["0"], lastSeenIndex, lastSeenIndex); // Set LastSeen to 0
                } else {
                    // UUID has not been detected, increment LastSeen
                    lastSeenValue += 1; // Increment LastSeen by 1
                    data = llListReplaceList(data, [(string)lastSeenValue], lastSeenIndex, lastSeenIndex);
                }

                // Update floating text based on LastSeen value
                if (lastSeenValue > 30) {
                    llSetLinkPrimitiveParamsFast(i, [PRIM_TEXT, objectName, <1.0, 0.0, 0.0>, 1.0]); // Red
                } else {
                    llSetLinkPrimitiveParamsFast(i, [PRIM_TEXT, objectName, <0.0, 1.0, 0.0>, 1.0]); // Green
                }
            }

            // Rebuild the updated description string
            string updatedDesc = "";
            integer dataLength = llGetListLength(data);
            for (integer k = 0; k < dataLength; k += 2) {
                updatedDesc += llList2String(data, k) + "=" + llList2String(data, k + 1) + ";";
            }
            updatedDesc = llDeleteSubString(updatedDesc, -1, -1); // Remove trailing semicolon

            // Update the linked prim's description
            llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, updatedDesc]);
        }
    }

    // Clear the detectedUUIDs list after updating all linked prims
    detectedUUIDs = [];

    // Instruct the short interval script to clear its list of detected UUIDs
    llMessageLinked(LINK_THIS, 0, "ClearUUIDs", NULL_KEY);
}

default {
    state_entry() {
        llOwnerSay("Long interval script (Prim Description Updates) started.");
        llSetTimerEvent(LONG_INTERVAL); // Start the long interval timer
    }

    timer() {
        // Request the list of detected UUIDs from the short interval script
        llMessageLinked(LINK_THIS, 0, "RequestUUIDs", NULL_KEY);
    }

    link_message(integer sender_num, integer num, string message, key id) {
        if (llSubStringIndex(message, "UUIDs|") == 0) {
            // Properly remove the "UUIDs|" prefix
            string csvUUIDs = llGetSubString(message, 6, -1); // Start from the 7th character (index 6)

            // Convert the CSV string to a list
            detectedUUIDs = llCSV2List(csvUUIDs);

            // Clean all UUIDs in the detectedUUIDs list
            integer count = llGetListLength(detectedUUIDs);
            for (integer i = 0; i < count; i++) {
                string rawUUID = llList2String(detectedUUIDs, i);
                detectedUUIDs = llListReplaceList(detectedUUIDs, [cleanUUID(rawUUID)], i, i); // Replace with cleaned UUID
            }

            updateLinkedPrimDescriptions(); // Compare and update linked prim descriptions
        }
    }
}
