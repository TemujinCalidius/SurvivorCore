integer COMM_CHANNEL = 67890; // Channel for communication with the statistics server
key playerKey; // The player's UUID
string playerName; // The player's name

integer stamina = 100; // Dynamic stamina (used for running, flying, etc.)
integer maxStamina = 100; // Maximum stamina (overall energy/fatigue from the stats server)
integer health = 100; // Current health
integer maxHealth = 100; // Maximum health
integer hunger = 0; // Current hunger
integer maxHunger = 100; // Maximum hunger
integer thirst = 0; // Current thirst
integer maxThirst = 100; // Maximum thirst
integer infection = 0; // Current infection
integer maxInfection = 100; // Maximum infection
string role = "Survivor"; // Player's role
float depletionRate = 5.0; // Stamina depletion per second
float regenerationRate = 5.0; // Stamina regeneration per second
integer isRunning = FALSE; // Flag to track running state
integer isFlying = FALSE; // Flag to track flying state
integer isExhausted = FALSE; // Flag to track exhaustion state
integer isDrainingHealth = FALSE; // Flag to track health drain state
integer isRegistered = FALSE; // Flag to track if the player is registered
integer serverFound = FALSE; // Flag to track if a server is found
integer hasNotifiedExhaustion = FALSE; // Flag to track if exhaustion notification has been sent

// Adjusted cooldown for health drain
float healthDrainCooldown = 1.0; // Time (in seconds) between health drain updates
float lastHealthDrainTime = 0.0; // Timestamp of the last health drain

// Function to check survival stats and warn the player if necessary
checkSurvivalStats() {
    if (hunger == maxHunger) {
        llOwnerSay("Warning: You are **famished**! Hunger is at maximum, and you are losing stamina. Please eat something.");
    }
    if (thirst == maxThirst) {
        llOwnerSay("Warning: You are **dehydrated**! Thirst is at maximum, and you are losing stamina. Please drink something.");
    }
    if (infection == maxInfection) {
        llOwnerSay("Warning: You are **infected**! Infection is at maximum, and you are losing stamina. Please heal yourself.");
    }
}

default {
    state_entry() {
        playerKey = llGetOwner(); // Get the player's UUID
        playerName = llKey2Name(playerKey); // Get the player's name

        // Set up a listener for the communication channel
        llListen(COMM_CHANNEL, "", NULL_KEY, "");

        // Send a request to the statistics server to get the player's stats
        llRegionSay(COMM_CHANNEL, "RequestStats|" + (string)playerKey + "|" + (string)COMM_CHANNEL);

        // Start a timer to check the avatar's state
        llSetTimerEvent(1.0); // Check every second
    }

    listen(integer channel, string name, key id, string message) {
        // Parse the incoming message
        list parts = llParseString2List(message, ["|"], []);
        string command = llList2String(parts, 0);

        if (command == "Stats") {
            // The server has sent the stats
            serverFound = TRUE; // Server is present
            string description = llList2String(parts, 1);

            // Parse the description to extract stats
            list data = llParseString2List(description, [";", "="], []);
            string uuid = llList2String(data, llListFindList(data, ["UUID"]) + 1);

            // Ensure the UUID matches the player's UUID
            if (uuid == (string)playerKey) {
                health = (integer)llList2String(data, llListFindList(data, ["Health"]) + 1);

                // Correctly map the server's "Stamina" value to maxStamina
                maxStamina = (integer)llList2String(data, llListFindList(data, ["Stamina"]) + 1);

                // Keep `stamina` as the dynamic stamina, but ensure it's capped by maxStamina
                if (stamina > maxStamina) {
                    stamina = maxStamina;
                }

                hunger = (integer)llList2String(data, llListFindList(data, ["Hunger"]) + 1);
                maxHunger = 100; // Maximum hunger is fixed for now
                thirst = (integer)llList2String(data, llListFindList(data, ["Thirst"]) + 1);
                maxThirst = 100; // Maximum thirst is fixed for now
                infection = (integer)llList2String(data, llListFindList(data, ["Infection"]) + 1);
                maxInfection = 100; // Maximum infection is fixed for now
                maxHealth = 100; // Maximum health is fixed for now
                role = llList2String(data, llListFindList(data, ["Role"]) + 1);

                isRegistered = TRUE; // Player is registered

                // Check survival stats and warn the player if necessary
                checkSurvivalStats();

                // Update floating text
                updateFloatingText();
            }
        } else if (command == "Error") {
            string errorMessage = llList2String(parts, 1);
            if (errorMessage == "PrimNotFound") {
                // Player is not registered
                isRegistered = FALSE;
                serverFound = TRUE; // Server is still present, just not registered
                llSetText("Not Registered", <1, 0, 0>, 1.0); // Red text
            }
        } else if (command == "ResetMeter") {
            // Handle ResetMeter command from region-wide message
            llResetScript(); // Reset the Meter Script
        }
    }

    timer() {
        // Check if server was found
        if (!serverFound) {
            // No server found, make floating text invisible
            llSetText("", <0, 0, 0>, 0.0); // Make floating text invisible
        } else if (!isRegistered) {
            // Server is found but the player is not registered
            llSetText("Not Registered", <1, 0, 0>, 1.0); // Red text
        }

        // Prevent updates if the player is not registered or dead
        if (!isRegistered || health <= 0) {
            return; // Do nothing
        }

        integer agentInfo = llGetAgentInfo(playerKey);

        // Check if the avatar is running or flying
        isRunning = (agentInfo & AGENT_ALWAYS_RUN); // Detect running specifically
        isFlying = (agentInfo & AGENT_FLYING); // Detect flying

        if (isRunning || isFlying) {
            // Deplete stamina
            if (!isExhausted) {
                stamina -= (integer)depletionRate;
                if (stamina <= 0) {
                    stamina = 0;
                    isExhausted = TRUE;

                    // Notify the player about exhaustion
                    if (!hasNotifiedExhaustion) {
                        llOwnerSay("You are **exhausted**! Your health will now start draining unless you rest.");
                        hasNotifiedExhaustion = TRUE; // Ensure the message is sent only once per exhaustion event
                    }

                    // Start draining health if not already doing so
                    if (!isDrainingHealth) {
                        isDrainingHealth = TRUE;
                    }
                }
            }

            // Drain health if exhausted
            if (isExhausted && isDrainingHealth) {
                float currentTime = llGetUnixTime();
                if (currentTime - lastHealthDrainTime >= healthDrainCooldown) {
                    health -= 1; // Reduce health by 1
                    if (health < 0) health = 0;

                    // Notify the statistics server of health reduction
                    llRegionSay(COMM_CHANNEL, "ReduceHealth|1|" + (string)playerKey);

                    // Update the cooldown timer
                    lastHealthDrainTime = currentTime;
                }
            }
        } else {
            // Regenerate stamina if not exhausted
            if (stamina < maxStamina) {
                stamina += (integer)regenerationRate;
                if (stamina > maxStamina) {
                    stamina = maxStamina;
                }
            }

            // Reset exhaustion state when idle
            isExhausted = FALSE;
            isDrainingHealth = FALSE;
            hasNotifiedExhaustion = FALSE; // Reset the notification flag
        }

        // Update floating text
        updateFloatingText();
    }

    changed(integer change) {
        if (change & CHANGED_REGION) {
            // The avatar has entered a new region
            serverFound = FALSE;
            isRegistered = FALSE;
            llRegionSay(COMM_CHANNEL, "RequestStats|" + (string)playerKey + "|" + (string)COMM_CHANNEL);
        }
    }

    on_rez(integer start_param) {
        llResetScript(); // Reset the script when the meter is rezzed or attached
    }

    attach(key id) {
        if (id != NULL_KEY) {
            llResetScript(); // Reset the script when the meter is attached
        }
    }

    // Handle messages from the UUID Handler
    link_message(integer sender_num, integer num, string str, key id) {
        if (str == "ResetMeter") {
            llResetScript(); // Reset the Meter Script
        }
    }
}

// Update floating text on the player's meter
updateFloatingText() {
    string text;

    if (health > 0) {
        if (stamina > 0) {
            // Normal state
            text = "Health: " + (string)health + "/" + (string)maxHealth +
                   "\nStamina: " + (string)stamina + "/" + (string)maxStamina +
                   "\nHunger: " + (string)hunger + "/" + (string)maxHunger +
                   "\nThirst: " + (string)thirst + "/" + (string)maxThirst +
                   "\nInfection: " + (string)infection + "/" + (string)maxInfection +
                   "\nRole: " + role;
        } else {
            // Exhausted state
            text = "Health: " + (string)health + "/" + (string)maxHealth +
                   "\nStamina: 0/" + (string)maxStamina + " (Exhausted)" +
                   "\nHunger: " + (string)hunger + "/" + (string)maxHunger +
                   "\nThirst: " + (string)thirst + "/" + (string)maxThirst +
                   "\nInfection: " + (string)infection + "/" + (string)maxInfection +
                   "\nRole: " + role;
        }
    } else {
        // Dead state
        text = "Dead";
    }

    // Determine the text colour based on health
    vector colour;
    if (health > 50) {
        colour = <0, 1, 0>; // Green
    } else if (health > 25) {
        colour = <1, 1, 0>; // Yellow
    } else if (health > 0) {
        colour = <1, 0.5, 0>; // Orange
    } else {
        colour = <1, 0, 0>; // Red
    }

    // Set floating text with the determined colour
    llSetText(text, colour, 1.0);
}
