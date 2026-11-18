# How to play, and things you can change without coding

This page collects the settings you can change by editing a plain text file. The full playtest
guide (two people over the internet) is `godot/PLAYTEST.md`.

## Changing the family names

The players name their own families. The name is shown in the score bar, the round and match
messages, the results panel and the debug HUD.

- **Online:** the lobby has one name box per family. Anyone seated on a family can type its surname
  (for example `Smith`); the game shows it as "Smith Family" (a name that already ends in "Family"
  is left as it is). The host can type their own family's name and has a **Clear** button on both
  boxes. Every player sees the change within a second, and someone who joins or reconnects gets the
  current names. Names can be changed until the host presses Start.
- **Solo:** the main menu has the same two boxes under "Team size", above "Play solo".
- **Rules for a name:** at most 16 characters; letters (accents are fine), spaces, hyphens and
  apostrophes only. Anything else (digits, symbols, emoji) is removed as you type, spaces at the
  ends are trimmed and double spaces become one.
- Typed names are not saved: they are empty each time the game starts, and a new hosted or joined
  game starts with empty boxes.

**Defaults.** A box left empty shows a default name: "Green Family" for the first family (the one in
House A, in green) and "Orange Family" for the second (House B, rust orange). The defaults are in
one small text file, `godot/content/family_names.cfg`:

1. Open it in Notepad (or any text editor).
2. Edit the text after `team_a_name=` (first family) or `team_b_name=` (second family). No quotes
   are needed. Leave the left part of each line exactly as it is; lines that start with `#` are notes.
3. Save the file and start the game again (rebuild the exe with `node autobuild/build.mjs` for the
   exe to have it).

If a line is empty, or the file is missing, the game uses "Green Family" and "Orange Family". The
defaults are read on each PC from its own file; the typed names are the same on every PC (the
host's copy wins).

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

## Cash sounds

The cash sounds are plain OGG Vorbis files in `godot/art/audio/sfx/`. Replace a file under the
same name to change a sound (keep each short, under about half a second, with no silence at the
start), then rebuild with `node autobuild/build.mjs`:

- `grab_1.ogg`, `grab_2.ogg`: picking up a bundle (a paper flutter; one of the two at random);
- `cash_1.ogg`, `cash_2.ogg`: a bundle banked at home (a soft paper thud);
- `drop.ogg`: a carrier lets go of a bundle;
- `bundle_land.ogg`: a thrown or dropped bundle hits the ground.

The sounds they replaced are kept in `godot/art/audio/sfx/retired/` (not in the exe). Their volume
follows the Effects slider.

## Changing the menu music

Music plays only around a match: in the main menu, the lobby and the results panel. It fades
out over about a second when a match starts and fades back in when the results appear; nothing
plays under the match itself. The win and lose jingles at the end of a match are separate files.
The music is **one file**: `godot/content/music/menu.ogg`. To use another track:

1. Save it as **OGG Vorbis** (`.ogg`), 44.1 kHz or 48 kHz. It plays from start to end and then
   starts again, so a track that is written to loop sounds best.
2. Name it exactly `menu.ogg` and put it in `godot/content/music/`, replacing the file that is there.
   Two other tracks are ready in `godot/content/music/candidates/`: copy one over `menu.ogg`
   (`deliberate_concealment.ogg`, `sneaking_around.ogg`; the old jazz loop is there too as
   `jazz_improvisation_loop.ogg`). Nothing in `candidates/` ships in the exe.
3. The shipped track has two seconds of silence at its end, so the game jumps back to the start at
   104.4 s. For a different track, set `MUSIC_LOOP_END` in `godot/game/audio/game_audio.gd` to `0.0`
   (play the whole file), or to the second where its sound ends.
4. Rebuild the game: `node autobuild/build.mjs`. Running the project from Godot picks it up
   without a rebuild.

If the file is missing the menu is silent. Its volume follows the Music slider.
