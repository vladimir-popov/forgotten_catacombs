const Command = enum {
    /// This command means that nothing happened, and run loop should be continued
    CMD_NOTHING,
    /// Run a new game
    CMD_NEW_GAME,
    /// Move the player on one room left
    CMD_MV_LEFT,
    /// Move the player on one room up
    CMD_MV_UP,
    /// Move the player on one room right
    CMD_MV_RIGHT,
    /// Move the player on one room down
    CMD_MV_DOWN,
    /// Put the game on pause and show menu
    CMD_PAUSE,
    /// Close the current menu or map and continue the game
    CMD_CONTINUE,
    /// Exit from the game
    CMD_EXIT,
    /// Command to wait a special command from user
    CMD_CMD,
    /// Command to show the map
    CMD_SHOW_MAP,
    /// Show keys settings menu
    CMD_SHOW_KEYS_SETTINGS,
    /// Cheat to show whole labyrinth
    CMD_SHOW_ALL,
};
