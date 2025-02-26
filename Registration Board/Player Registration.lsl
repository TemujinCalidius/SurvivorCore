default {
    touch_start(integer num) {
        key player = llDetectedKey(0); // Get the avatar's key
        string playerName = llDetectedName(0); // Get the avatar's name

        // Send registration request to the data server
        llRegionSay(12345, "Register|" + (string)player + "|" + playerName);

        // Notify the player directly
        llSay(0, "Registration request sent, " + playerName + ".");
    }
}
