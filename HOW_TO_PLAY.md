# How to play, and things you can change without coding

This page collects the settings you can change by editing a plain text file. The full playtest
guide (two people over the internet) is `godot/PLAYTEST.md`.

## Changing the family names

The two families' display names (the names players see in the score bar, the menus and the round and
match results) are written in **one small text file and nowhere else**:

1. Open `godot/content/family_names.cfg` in Notepad (or any text editor).
2. Edit the two lines:
   - `team_a_name=` is the family that starts in the first house (House A);
   - `team_b_name=` is the family that starts in the second house (House B).

   Write the name right after the `=` sign. No quotes are needed. Leave the left part of each line
   exactly as it is. Lines that start with `#` are notes and are ignored.
3. Save the file and start the game again. The names are read once, when the game starts.

If a name is left empty, or the file is missing, the game shows "Family A" and "Family B" instead.
The names are only for display, so two players can even have different names on their own PCs.

## Changing the jail sound

The sound a player hears when they are caught and sent to jail is **one file**:
`godot/content/sfx/jailed.ogg`. To use your own recording:

1. Save your sound as **OGG Vorbis** (`.ogg`). Mono or stereo, 44.1 kHz or 48 kHz. Keep it short,
   under about 2 seconds, with no silence at the start (it should start the moment the player is caught).
   Audacity can do this: *File → Export → Export as OGG*.
2. Name it exactly `jailed.ogg` and put it in `godot/content/sfx/`, replacing the file that is there.
3. Rebuild the game: `node autobuild/build.mjs` (it re-imports the sound first, then makes
   `build/CashGrab.exe`). Running the project from Godot picks it up without a rebuild.

If the file is missing the game simply plays no jail sound. Its volume follows the Effects slider.
