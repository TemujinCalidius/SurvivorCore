// SurvivorCore Statistics Server Communication Script
// Description: Handles communication between player meters and the statistics server
// Author: Temujin Calidius
// Date: April 2025
// Version: 1.0

integer COMM_CHANNEL = 67890; // Default channel for meter and HUD communication

// Shortened parameter names mapping
// UUID = ID (UUID)
// LastSeen = LS (Last Seen)
// Health = H (Health)
// Stamina = S (Stamina)
// Hunger = F (Food/Hunger)
// Thirst = T (Thirst)
// Infection = I (Infection)
// Role = R (Role)

default {
    state_entry() {
        llListen(COMM_CHANNEL, "", NULL_KEY, ""); // Listen for messages on the communication channel

        // Convert all existing player prims to short format
        integer totalPrims = llGetNumberOfPrims();
        for (integer i = 2; i <= totalPrims; i++) {
            string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);

            // Check if this is a player data prim (has UUID)
            if (llSubStringIndex(desc, "UUID=") != -1) {
                // Convert to short format
                list data = llParseString2List(desc, [";", "="], []);
                string shortDesc = "";

                integer j;
                integer length = llGetListLength(data);

                for (j = 0; j < length; j += 2) {
                    string keyName = llList2String(data, j);
                    string value = llList2String(data, j + 1);

                    // Convert to shortened keys
                    if (keyName == "UUID") keyName = "ID";
                    else if (keyName == "LastSeen") keyName = "LS";
                    else if (keyName == "Health") keyName = "H";
                    else if (keyName == "Stamina") keyName = "S";
                    else if (keyName == "Hunger") keyName = "F";
                    else if (keyName == "Thirst") keyName = "T";
                    else if (keyName == "Infection") keyName = "I";
                    else if (keyName == "Role") keyName = "R";

                    // Add to short description
                    shortDesc += keyName + "=" + value + ";";
                }

                // Remove trailing semicolon
                shortDesc = llDeleteSubString(shortDesc, -1, -1);

                llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, shortDesc]);
                llOwnerSay("Converted prim " + (string)i + " to short format: " + shortDesc);
            }
        }
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

                // Check if the player's UUID is in the description (check both formats)
                if (llSubStringIndex(desc, "ID=" + (string)playerKey) != -1 || 
                    llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) {

                    // Convert to long format for backward compatibility with meters
                    string longDesc = desc;
                    if (llSubStringIndex(desc, "ID=") != -1) {
                        // Convert from short to long format
                        list data = llParseString2List(desc, [";", "="], []);
                        longDesc = "";

                        integer j;
                        integer length = llGetListLength(data);

                        for (j = 0; j < length; j += 2) {
                            string keyName = llList2String(data, j);
                            string value = llList2String(data, j + 1);

                            // Convert from shortened keys
                            if (keyName == "ID") keyName = "UUID";
                            else if (keyName == "LS") keyName = "LastSeen";
                            else if (keyName == "H") keyName = "Health";
                            else if (keyName == "S") keyName = "Stamina";
                            else if (keyName == "F") keyName = "Hunger";
                            else if (keyName == "T") keyName = "Thirst";
                            else if (keyName == "I") keyName = "Infection";
                            else if (keyName == "R") keyName = "Role";

                            // Add to long description
                            longDesc += keyName + "=" + value + ";";
                        }

                        // Remove trailing semicolon
                        longDesc = llDeleteSubString(longDesc, -1, -1);
                    }

                    // Send the description back to the specified channel
                    llRegionSay(responseChannel, "Stats|" + longDesc);
                    return;
                }
            }

            // If no prim is found, notify the requesting script
            llOwnerSay("RequestStats: No matching prim found for UUID: " + (string)playerKey);
            llRegionSay(responseChannel, "Error|PrimNotFound");
        } 
        // HEALTH COMMANDS
        else if (command == "ReduceHealth" || command == "RestoreHealth") {
            // Get amount and player key
            float amount = (float)llList2String(parts, 1);
            key playerKey = llList2Key(parts, 2);

            // For ReduceHealth, make the amount negative
            if (command == "ReduceHealth") {
                amount = -amount;
            }

            // Find the player's prim
            integer totalPrims = llGetNumberOfPrims();
            for (integer i = 2; i <= totalPrims; i++) {
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);
                string statKey = "Health";
                string shortStatKey = "H";

                // Check for both formats
                if ((llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) || 
                    (llSubStringIndex(desc, "ID=" + (string)playerKey) != -1)) {

                    // Determine if we're using short or long format
                    integer isShortFormat = (llSubStringIndex(desc, "ID=") != -1);
                    list data = llParseString2List(desc, [";", "="], []);

                    // Find the health index based on format
                    integer statIndex;
                    if (isShortFormat) {
                        statIndex = llListFindList(data, [shortStatKey]) + 1;
                    } else {
                        statIndex = llListFindList(data, [statKey]) + 1;
                    }

                    if (statIndex > 0) {
                        float currentValue = (float)llList2String(data, statIndex);
                        float newValue = currentValue + amount;

                        // Cap values between 0 and 100
                        if (newValue > 100.0) newValue = 100.0;
                        if (newValue < 0.0) newValue = 0.0;

                        // Update the stat value in the list
                        data = llListReplaceList(data, [(string)newValue], statIndex, statIndex);

                        // Reconstruct the description string
                        string updatedDesc = "";
                        integer dataLength = llGetListLength(data);
                        for (integer j = 0; j < dataLength; j += 2) {
                            updatedDesc += llList2String(data, j) + "=" + llList2String(data, j + 1) + ";";
                        }

                        // Remove the trailing semicolon
                        updatedDesc = llDeleteSubString(updatedDesc, -1, -1);

                        // Update the prim description
                        llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, updatedDesc]);

                        // Convert to long format for the meter if using short format
                        string responseDesc = updatedDesc;
                        if (isShortFormat) {
                            // Convert from short to long format
                            list respData = llParseString2List(updatedDesc, [";", "="], []);
                            responseDesc = "";

                            integer k;
                            integer respLength = llGetListLength(respData);

                            for (k = 0; k < respLength; k += 2) {
                                string keyName = llList2String(respData, k);
                                string value = llList2String(respData, k + 1);

                                // Convert from shortened keys
                                if (keyName == "ID") keyName = "UUID";
                                else if (keyName == "LS") keyName = "LastSeen";
                                else if (keyName == "H") keyName = "Health";
                                else if (keyName == "S") keyName = "Stamina";
                                else if (keyName == "F") keyName = "Hunger";
                                else if (keyName == "T") keyName = "Thirst";
                                else if (keyName == "I") keyName = "Infection";
                                else if (keyName == "R") keyName = "Role";

                                // Add to long description
                                responseDesc += keyName + "=" + value + ";";
                            }

                            // Remove trailing semicolon
                            responseDesc = llDeleteSubString(responseDesc, -1, -1);
                        }

                        // Notify the meter of the updated stats
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Stats|" + responseDesc);

                        // Debug message
                        string actionText = (amount > 0) ? "Increased" : "Decreased";
                        llOwnerSay(actionText + " Health by " + (string)llFabs(amount) + " for " + llKey2Name(playerKey));
                        return;
                    } else {
                        llOwnerSay("Error: Health stat not found for player " + llKey2Name(playerKey));
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Error|StatNotFound|Health");
                        return;
                    }
                }
            }

            // If no prim is found
            llOwnerSay("UpdateStat: No matching prim found for UUID: " + (string)playerKey);
            llRegionSayTo(playerKey, COMM_CHANNEL, "Error|PrimNotFound");
        }
        // HUNGER COMMANDS
        else if (command == "RestoreHunger" || command == "ReduceHunger") {
            // Get amount and player key
            float amount = (float)llList2String(parts, 1);
            key playerKey = llList2Key(parts, 2);

            // For ReduceHunger, make the amount negative
            if (command == "ReduceHunger") {
                amount = -amount;
            }

            // Find the player's prim
            integer totalPrims = llGetNumberOfPrims();
            for (integer i = 2; i <= totalPrims; i++) {
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);
                string statKey = "Hunger";
                string shortStatKey = "F";

                // Check for both formats
                if ((llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) || 
                    (llSubStringIndex(desc, "ID=" + (string)playerKey) != -1)) {

                    // Determine if we're using short or long format
                    integer isShortFormat = (llSubStringIndex(desc, "ID=") != -1);
                    list data = llParseString2List(desc, [";", "="], []);

                    // Find the hunger index based on format
                    integer statIndex;
                    if (isShortFormat) {
                        statIndex = llListFindList(data, [shortStatKey]) + 1;
                    } else {
                        statIndex = llListFindList(data, [statKey]) + 1;
                    }

                    if (statIndex > 0) {
                        float currentValue = (float)llList2String(data, statIndex);
                        float newValue = currentValue + amount;

                        // Cap values between 0 and 100
                        if (newValue > 100.0) newValue = 100.0;
                        if (newValue < 0.0) newValue = 0.0;

                        // Update the stat value in the list
                        data = llListReplaceList(data, [(string)newValue], statIndex, statIndex);

                        // Reconstruct the description string
                        string updatedDesc = "";
                        integer dataLength = llGetListLength(data);
                        for (integer j = 0; j < dataLength; j += 2) {
                            updatedDesc += llList2String(data, j) + "=" + llList2String(data, j + 1) + ";";
                        }

                        // Remove the trailing semicolon
                        updatedDesc = llDeleteSubString(updatedDesc, -1, -1);

                        // Update the prim description
                        llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, updatedDesc]);

                        // Convert to long format for the meter if using short format
                        string responseDesc = updatedDesc;
                        if (isShortFormat) {
                            // Convert from short to long format
                            list respData = llParseString2List(updatedDesc, [";", "="], []);
                            responseDesc = "";

                            integer k;
                            integer respLength = llGetListLength(respData);

                            for (k = 0; k < respLength; k += 2) {
                                string keyName = llList2String(respData, k);
                                string value = llList2String(respData, k + 1);

                                // Convert from shortened keys
                                if (keyName == "ID") keyName = "UUID";
                                else if (keyName == "LS") keyName = "LastSeen";
                                else if (keyName == "H") keyName = "Health";
                                else if (keyName == "S") keyName = "Stamina";
                                else if (keyName == "F") keyName = "Hunger";
                                else if (keyName == "T") keyName = "Thirst";
                                else if (keyName == "I") keyName = "Infection";
                                else if (keyName == "R") keyName = "Role";

                                // Add to long description
                                responseDesc += keyName + "=" + value + ";";
                            }

                            // Remove trailing semicolon
                            responseDesc = llDeleteSubString(responseDesc, -1, -1);
                        }

                        // Notify the meter of the updated stats
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Stats|" + responseDesc);

                        // Debug message
                        string actionText = (amount > 0) ? "Increased" : "Decreased";
                        llOwnerSay(actionText + " Hunger by " + (string)llFabs(amount) + " for " + llKey2Name(playerKey));
                        return;
                    } else {
                        llOwnerSay("Error: Hunger stat not found for player " + llKey2Name(playerKey));
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Error|StatNotFound|Hunger");
                        return;
                    }
                }
            }

            // If no prim is found
            llOwnerSay("UpdateStat: No matching prim found for UUID: " + (string)playerKey);
            llRegionSayTo(playerKey, COMM_CHANNEL, "Error|PrimNotFound");
        }
        // THIRST COMMANDS
        else if (command == "RestoreThirst" || command == "ReduceThirst") {
            // Get amount and player key
            float amount = (float)llList2String(parts, 1);
            key playerKey = llList2Key(parts, 2);

            // For ReduceThirst, make the amount negative
            if (command == "ReduceThirst") {
                amount = -amount;
            }

            // Find the player's prim
            integer totalPrims = llGetNumberOfPrims();
            for (integer i = 2; i <= totalPrims; i++) {
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);
                string statKey = "Thirst";
                string shortStatKey = "T";

                // Check for both formats
                if ((llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) || 
                    (llSubStringIndex(desc, "ID=" + (string)playerKey) != -1)) {

                    // Determine if we're using short or long format
                    integer isShortFormat = (llSubStringIndex(desc, "ID=") != -1);
                    list data = llParseString2List(desc, [";", "="], []);

                    // Find the thirst index based on format
                    integer statIndex;
                    if (isShortFormat) {
                        statIndex = llListFindList(data, [shortStatKey]) + 1;
                    } else {
                        statIndex = llListFindList(data, [statKey]) + 1;
                    }

                    if (statIndex > 0) {
                        float currentValue = (float)llList2String(data, statIndex);
                        float newValue = currentValue + amount;

                        // Cap values between 0 and 100
                        if (newValue > 100.0) newValue = 100.0;
                        if (newValue < 0.0) newValue = 0.0;

                        // Update the stat value in the list
                        data = llListReplaceList(data, [(string)newValue], statIndex, statIndex);

                        // Reconstruct the description string
                        string updatedDesc = "";
                        integer dataLength = llGetListLength(data);
                        for (integer j = 0; j < dataLength; j += 2) {
                            updatedDesc += llList2String(data, j) + "=" + llList2String(data, j + 1) + ";";
                        }

                        // Remove the trailing semicolon
                        updatedDesc = llDeleteSubString(updatedDesc, -1, -1);

                        // Update the prim description
                        llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, updatedDesc]);

                        // Convert to long format for the meter if using short format
                        string responseDesc = updatedDesc;
                        if (isShortFormat) {
                            // Convert from short to long format
                            list respData = llParseString2List(updatedDesc, [";", "="], []);
                            responseDesc = "";

                            integer k;
                            integer respLength = llGetListLength(respData);

                            for (k = 0; k < respLength; k += 2) {
                                string keyName = llList2String(respData, k);
                                string value = llList2String(respData, k + 1);

                                // Convert from shortened keys
                                if (keyName == "ID") keyName = "UUID";
                                else if (keyName == "LS") keyName = "LastSeen";
                                else if (keyName == "H") keyName = "Health";
                                else if (keyName == "S") keyName = "Stamina";
                                else if (keyName == "F") keyName = "Hunger";
                                else if (keyName == "T") keyName = "Thirst";
                                else if (keyName == "I") keyName = "Infection";
                                else if (keyName == "R") keyName = "Role";

                                // Add to long description
                                responseDesc += keyName + "=" + value + ";";
                            }

                            // Remove trailing semicolon
                            responseDesc = llDeleteSubString(responseDesc, -1, -1);
                        }

                        // Notify the meter of the updated stats
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Stats|" + responseDesc);

                        // Debug message
                        string actionText = (amount > 0) ? "Increased" : "Decreased";
                        llOwnerSay(actionText + " Thirst by " + (string)llFabs(amount) + " for " + llKey2Name(playerKey));
                        return;
                    } else {
                        llOwnerSay("Error: Thirst stat not found for player " + llKey2Name(playerKey));
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Error|StatNotFound|Thirst");
                        return;
                    }
                }
            }

            // If no prim is found
            llOwnerSay("UpdateStat: No matching prim found for UUID: " + (string)playerKey);
            llRegionSayTo(playerKey, COMM_CHANNEL, "Error|PrimNotFound");
        }
        // STAMINA COMMANDS
        else if (command == "RestoreStamina" || command == "ReduceStamina") {
            // Get amount and player key
            float amount = (float)llList2String(parts, 1);
            key playerKey = llList2Key(parts, 2);

            // For ReduceStamina, make the amount negative
            if (command == "ReduceStamina") {
                amount = -amount;
            }

            // Find the player's prim
            integer totalPrims = llGetNumberOfPrims();
            for (integer i = 2; i <= totalPrims; i++) {
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);
                string statKey = "Stamina";
                string shortStatKey = "S";

                // Check for both formats
                if ((llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) || 
                    (llSubStringIndex(desc, "ID=" + (string)playerKey) != -1)) {

                    // Determine if we're using short or long format
                    integer isShortFormat = (llSubStringIndex(desc, "ID=") != -1);
                    list data = llParseString2List(desc, [";", "="], []);

                    // Find the stamina index based on format
                    integer statIndex;
                    if (isShortFormat) {
                        statIndex = llListFindList(data, [shortStatKey]) + 1;
                    } else {
                        statIndex = llListFindList(data, [statKey]) + 1;
                    }

                    if (statIndex > 0) {
                        float currentValue = (float)llList2String(data, statIndex);
                        float newValue = currentValue + amount;

                        // Cap values between 0 and 100
                        if (newValue > 100.0) newValue = 100.0;
                        if (newValue < 0.0) newValue = 0.0;

                        // Update the stat value in the list
                        data = llListReplaceList(data, [(string)newValue], statIndex, statIndex);

                        // Reconstruct the description string
                        string updatedDesc = "";
                        integer dataLength = llGetListLength(data);
                        for (integer j = 0; j < dataLength; j += 2) {
                            updatedDesc += llList2String(data, j) + "=" + llList2String(data, j + 1) + ";";
                        }

                        // Remove the trailing semicolon
                        updatedDesc = llDeleteSubString(updatedDesc, -1, -1);

                        // Update the prim description
                        llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, updatedDesc]);

                        // Convert to long format for the meter if using short format
                        string responseDesc = updatedDesc;
                        if (isShortFormat) {
                            // Convert from short to long format
                            list respData = llParseString2List(updatedDesc, [";", "="], []);
                            responseDesc = "";

                            integer k;
                            integer respLength = llGetListLength(respData);

                            for (k = 0; k < respLength; k += 2) {
                                string keyName = llList2String(respData, k);
                                string value = llList2String(respData, k + 1);

                                // Convert from shortened keys
                                if (keyName == "ID") keyName = "UUID";
                                else if (keyName == "LS") keyName = "LastSeen";
                                else if (keyName == "H") keyName = "Health";
                                else if (keyName == "S") keyName = "Stamina";
                                else if (keyName == "F") keyName = "Hunger";
                                else if (keyName == "T") keyName = "Thirst";
                                else if (keyName == "I") keyName = "Infection";
                                else if (keyName == "R") keyName = "Role";

                                // Add to long description
                                responseDesc += keyName + "=" + value + ";";
                            }

                            // Remove trailing semicolon
                            responseDesc = llDeleteSubString(responseDesc, -1, -1);
                        }

                        // Notify the meter of the updated stats
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Stats|" + responseDesc);

                        // Debug message
                        string actionText = (amount > 0) ? "Increased" : "Decreased";
                        llOwnerSay(actionText + " Stamina by " + (string)llFabs(amount) + " for " + llKey2Name(playerKey));
                        return;
                    } else {
                        llOwnerSay("Error: Stamina stat not found for player " + llKey2Name(playerKey));
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Error|StatNotFound|Stamina");
                        return;
                    }
                }
            }

            // If no prim is found
            llOwnerSay("UpdateStat: No matching prim found for UUID: " + (string)playerKey);
            llRegionSayTo(playerKey, COMM_CHANNEL, "Error|PrimNotFound");
        }
        // INFECTION COMMANDS - UPDATED
        else if (command == "ReduceInfection" || command == "IncreaseInfection" || command == "CureInfection") {
            // Get amount and player key
            float amount = (float)llList2String(parts, 1);
            key playerKey = llList2Key(parts, 2);

            // Determine the operation based on command
            if (command == "ReduceInfection") {
                // amount stays positive (reduction)
            } else if (command == "IncreaseInfection") {
                // For increasing infection, make the amount negative
                amount = -amount;
            } else if (command == "CureInfection") {
                // For complete cure, set a large amount to ensure it goes to zero
                amount = 999.0; // This will ensure infection goes to 0
            }

            // Find the player's prim
            integer totalPrims = llGetNumberOfPrims();
            for (integer i = 2; i <= totalPrims; i++) {
                string desc = llGetLinkPrimitiveParams(i, [PRIM_DESC]);
                string statKey = "Infection";
                string shortStatKey = "I";

                // Check for both formats
                if ((llSubStringIndex(desc, "UUID=" + (string)playerKey) != -1) || 
                    (llSubStringIndex(desc, "ID=" + (string)playerKey) != -1)) {

                    // Determine if we're using short or long format
                    integer isShortFormat = (llSubStringIndex(desc, "ID=") != -1);
                    list data = llParseString2List(desc, [";", "="], []);

                    // Find the infection index based on format
                    integer statIndex;
                    if (isShortFormat) {
                        statIndex = llListFindList(data, [shortStatKey]) + 1;
                    } else {
                        statIndex = llListFindList(data, [statKey]) + 1;
                    }

                    if (statIndex > 0) {
                        float currentValue = (float)llList2String(data, statIndex);
                        float newValue;

                        if (command == "CureInfection") {
                            // Complete cure sets infection to 0
                            newValue = 0.0;
                        } else {
                            // For ReduceInfection, we subtract the amount (positive amount)
                            // For IncreaseInfection, we add the absolute value (negative amount becomes positive)
                            newValue = currentValue - amount;
                        }

                        // Cap values between 0 and 100
                        if (newValue > 100.0) newValue = 100.0;
                        if (newValue < 0.0) newValue = 0.0;

                        // Update the stat value in the list
                        data = llListReplaceList(data, [(string)newValue], statIndex, statIndex);

                        // Reconstruct the description string
                        string updatedDesc = "";
                        integer dataLength = llGetListLength(data);
                        for (integer j = 0; j < dataLength; j += 2) {
                            updatedDesc += llList2String(data, j) + "=" + llList2String(data, j + 1) + ";";
                        }

                        // Remove the trailing semicolon
                        updatedDesc = llDeleteSubString(updatedDesc, -1, -1);

                        // Update the prim description
                        llSetLinkPrimitiveParamsFast(i, [PRIM_DESC, updatedDesc]);

                        // Convert to long format for the meter if using short format
                        string responseDesc = updatedDesc;
                        if (isShortFormat) {
                            // Convert from short to long format
                            list respData = llParseString2List(updatedDesc, [";", "="], []);
                            responseDesc = "";

                            integer k;
                            integer respLength = llGetListLength(respData);

                            for (k = 0; k < respLength; k += 2) {
                                string keyName = llList2String(respData, k);
                                string value = llList2String(respData, k + 1);

                                // Convert from shortened keys
                                if (keyName == "ID") keyName = "UUID";
                                else if (keyName == "LS") keyName = "LastSeen";
                                else if (keyName == "H") keyName = "Health";
                                else if (keyName == "S") keyName = "Stamina";
                                else if (keyName == "F") keyName = "Hunger";
                                else if (keyName == "T") keyName = "Thirst";
                                else if (keyName == "I") keyName = "Infection";
                                else if (keyName == "R") keyName = "Role";

                                // Add to long description
                                responseDesc += keyName + "=" + value + ";";
                            }

                            // Remove trailing semicolon
                            responseDesc = llDeleteSubString(responseDesc, -1, -1);
                        }

                        // Notify the meter of the updated stats
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Stats|" + responseDesc);

                        // Send appropriate message to player
                        if (command == "CureInfection" || newValue == 0.0) {
                            llRegionSayTo(playerKey, 0, "You have been completely cured of infection!");
                        } else if (command == "ReduceInfection") {
                            llRegionSayTo(playerKey, 0, "Your infection has been reduced to " + (string)((integer)newValue) + "%");
                        } else {
                            llRegionSayTo(playerKey, 0, "Your infection has increased to " + (string)((integer)newValue) + "%");
                        }

                        // Debug message
                        string actionText;
                        if (command == "CureInfection") {
                            actionText = "Cured";
                        } else if (command == "ReduceInfection") {
                            actionText = "Reduced";
                        } else {
                            actionText = "Increased";
                        }

                        llOwnerSay(actionText + " Infection for " + llKey2Name(playerKey) + " - Now at " + (string)((integer)newValue) + "%");
                        return;
                    } else {
                        llOwnerSay("Error: Infection stat not found for player " + llKey2Name(playerKey));
                        llRegionSayTo(playerKey, COMM_CHANNEL, "Error|StatNotFound|Infection");
                        return;
                    }
                }
            }

            // If no prim is found
            llOwnerSay("UpdateStat: No matching prim found for UUID: " + (string)playerKey);
            llRegionSayTo(playerKey, COMM_CHANNEL, "Error|PrimNotFound");
        }
    }
}
