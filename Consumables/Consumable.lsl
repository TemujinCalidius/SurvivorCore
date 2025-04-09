// SurvivorCore Universal Consumable Script
// Description: Script for consumable items that affect player stats (food, drink, health, etc.)
// Author: Temujin Calidius
// Date: April 2025
// Version: 1.0

// Communication channel - must match the stats server
integer COMM_CHANNEL = 67890;

// Sound to play when consuming
string CONSUME_SOUND = "eating_sound";     // Sound to play when consuming (UUID or name)

// Internal variables
list statTypes = ["Food", "Drink", "Health", "Stamina", "Potion"];
list statValues = [0, 0, 0, 0, 0];
integer usesRemaining = 1;
string itemName;
string floatingText;
string originalDesc = "";

// Updates the floating text based on current values
updateFloatingText() {
    floatingText = itemName + "\n";

    // Add stats that this item affects
    integer i;
    integer count = llGetListLength(statTypes);
    integer hasEffects = FALSE;

    for (i = 0; i < count; i++) {
        float value = llList2Float(statValues, i);
        if (value != 0.0) {
            string statType = llList2String(statTypes, i);
            string prefix = (value > 0) ? "+" : "";
            floatingText += statType + ": " + prefix + (string)value + "\n";
            hasEffects = TRUE;
        }
    }

    if (!hasEffects) {
        floatingText += "No effects\n";
    }

    // Add uses remaining
    floatingText += "Uses: " + (string)usesRemaining;

    // Set the floating text
    llSetText(floatingText, <1.0, 1.0, 1.0>, 1.0);
}

// Parse the description to get stat values
parseDescription() {
    string desc = llGetObjectDesc();
    originalDesc = desc; // Store the original description

    list parts = llParseString2List(desc, [","], []);
    integer i;
    integer count = llGetListLength(parts);

    // Reset values
    statValues = [0, 0, 0, 0, 0];

    // Parse each part (format: "Type Value")
    for (i = 0; i < count; i++) {
        string part = llStringTrim(llList2String(parts, i), STRING_TRIM);
        list kvPair = llParseString2List(part, [" "], []);

        if (llGetListLength(kvPair) >= 2) {
            string type = llList2String(kvPair, 0);
            float value = (float)llList2String(kvPair, 1);

            // Find the index of this type in our statTypes list
            integer typeIndex = llListFindList(statTypes, [type]);
            if (typeIndex >= 0) {
                statValues = llListReplaceList(statValues, [value], typeIndex, typeIndex);
            }
        }
    }

    // Check if uses is specified in the description
    integer usesIndex = llSubStringIndex(desc, "Uses ");
    if (usesIndex >= 0) {
        string usesStr = llGetSubString(desc, usesIndex + 5, usesIndex + 10);
        list usesParts = llParseString2List(usesStr, [" ", ","], []);
        if (llGetListLength(usesParts) > 0) {
            usesRemaining = (integer)llList2String(usesParts, 0);
            if (usesRemaining <= 0) usesRemaining = 1; // Ensure at least 1 use
        }
    }
}

// Update the object description to reflect remaining uses
updateDescription() {
    string desc = originalDesc;

    // Check if Uses is already in the description
    integer usesIndex = llSubStringIndex(desc, "Uses ");

    if (usesIndex >= 0) {
        // Find where the Uses value ends (at a comma or end of string)
        integer endIndex = llSubStringIndex(llGetSubString(desc, usesIndex, -1), ",");
        if (endIndex == -1) {
            // No comma, so it's at the end of the string
            desc = llDeleteSubString(desc, usesIndex, -1) + "Uses " + (string)usesRemaining;
        } else {
            // There's a comma after the Uses value
            desc = llDeleteSubString(desc, usesIndex, usesIndex + endIndex - 1) + "Uses " + (string)usesRemaining + llGetSubString(desc, usesIndex + endIndex, -1);
        }
    } else {
        // No Uses in description, add it
        if (llStringLength(desc) > 0) {
            desc += ", ";
        }
        desc += "Uses " + (string)usesRemaining;
    }

    // Update the object description
    llSetObjectDesc(desc);
    originalDesc = desc; // Update our stored original description
}

default
{
    state_entry()
    {
        // Get the item name from the object name
        itemName = llGetObjectName();

        // Parse the description to get stat values
        parseDescription();

        // Update the floating text
        updateFloatingText();

        // Make sure the object can be touched
        llSetClickAction(CLICK_ACTION_TOUCH);
    }

    touch_start(integer total_number)
    {
        key toucherKey = llDetectedKey(0);

        // Allow anyone to use the item
        // Play consumption sound
        llPlaySound(CONSUME_SOUND, 1.0);

        // Send message to user about consuming the item
        llRegionSayTo(toucherKey, 0, "Consuming " + itemName + "...");

        // Process each stat type and send appropriate messages to the stats server
        integer i;
        integer count = llGetListLength(statTypes);

        for (i = 0; i < count; i++) {
            float value = llList2Float(statValues, i);
            if (value != 0.0) {
                string statType = llList2String(statTypes, i);

                // Determine the command based on stat type and value
                string command;

                if (statType == "Food") {
                    command = (value > 0) ? "RestoreHunger" : "ReduceHunger";
                    value = llFabs(value); // Use absolute value for the command
                } 
                else if (statType == "Drink") {
                    command = (value > 0) ? "RestoreThirst" : "ReduceThirst";
                    value = llFabs(value);
                }
                else if (statType == "Health") {
                    command = (value > 0) ? "RestoreHealth" : "ReduceHealth";
                    value = llFabs(value);
                }
                else if (statType == "Stamina") {
                    command = (value > 0) ? "RestoreStamina" : "ReduceStamina";
                    value = llFabs(value);
                }
                else if (statType == "Potion") {
                    // For potions, the value determines how much infection is reduced
                    // Positive values reduce infection, negative values would increase it (though rare)
                    if (value > 0) {
                        command = "ReduceInfection";
                    } else {
                        command = "IncreaseInfection";
                        value = llFabs(value); // Use absolute value for the command
                    }
                }

                // Send the command to the stats server
                llRegionSay(COMM_CHANNEL, command + "|" + (string)value + "|" + (string)toucherKey);
            }
        }

        // Reduce uses remaining
        usesRemaining--;

        // Update the description to reflect the new uses remaining
        updateDescription();

        // Update the floating text
        updateFloatingText();

        // Delete the item if no uses remain
        if (usesRemaining <= 0) {
            llRegionSayTo(toucherKey, 0, itemName + " has been consumed.");
            llDie();
        }
    }

    changed(integer change)
    {
        // If the name or description changes, update our values
        if (change & CHANGED_INVENTORY) {
            itemName = llGetObjectName();
            parseDescription();
            updateFloatingText();
        }
    }

    on_rez(integer start_param)
    {
        // Reset when rezzed
        itemName = llGetObjectName();
        parseDescription();
        updateFloatingText();
    }
}
