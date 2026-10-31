Trivium Hub - PS2 + PS3 + PS4 in one place
===========================================

Your PS2, PS3 and PS4 games in one launcher: extract, open and play. The emulators come built in,
every game opens already set up and community fixes turn on by themselves (60 FPS in about 700 PS2
games, optimized God of War III and Bloodborne). No need to download a different emulator, port or
guide for each game.

SINGLE PACKAGE
  Trivium Hub.exe      -> the program (double-click it)
  app\ (hidden folder) -> the launcher and the bundled emulators (PCSX2, RPCS3, shadPS4)
  The whole folder is portable: you can move or copy it to another PC or an external drive.
  Keep the "app" folder next to Trivium Hub.exe.
  If Windows says "Windows protected your PC", click More info > Run anyway (the program has no paid
  digital signature). Trivium Hub.exe runs the launcher inside itself (no hidden windows, no changes
  to Windows) and never asks for administrator.

LANGUAGE
  The launcher follows the Windows language. To change it: "..." button (top right) > About and credits >
  Idioma / Language.

HOW TO USE
  The first time, the "Getting started" screen lists what is missing (emulators, PS2 BIOS, PS3
  firmware and games), each with its own button. Open it again with "..." > Getting started or F1.
  1. Open Trivium Hub.exe.
  2. Emulators come installed. To update: "..." > Emulators > Install / update all (official GitHub
     pages; saves, settings and installed games are kept).
  3. Once, in the Emulators window: choose the BIOS copied from your PS2 and install the PS3 firmware
     (PS3UPDAT.PUP, free on Sony's site).
  4. Drag your games (or a folder with all of them) into the window.
  5. Double-click a game: the game settings screen opens; adjust and click PLAY.

LIBRARY
  - Click a cover: the right panel shows the big cover, play time, last played and PLAY.
  - "Continue playing" (top): your latest games. Double-click opens them directly.
  - Remove only takes the game off the list (the file stays). "Undo" shows for a few seconds.
  - Right-click a cover: Play, Settings, Open game folder, Favorite, Change cover (any image on your
    PC), Restore original cover, Rename and Remove.
  - Favorites: star on the big cover, right-click, Ctrl+D or Square/X on the controller.
  - Sort (next to the tabs): by name, recently played, most played or last added. Your choice is saved.
  - "Covers" (bottom bar, in grid view): Small, Medium or Large. Also Ctrl + mouse wheel over the covers.
  - Games added in the last 7 days and not played yet have a "NEW" tag on the cover.
  - The library background shows the art of the selected game.
  - Controller (Xbox, or PlayStation through Steam/DS4Windows): D-pad/stick navigates, A (X on PS) or
    Start plays, Y (Triangle) opens settings, X (Square) favorites, B (Circle) clears the search,
    LB/RB change tabs.
  - Keyboard: arrows navigate, Enter plays, F2 settings, Delete removes, Ctrl+D favorite, Ctrl+F search,
    Ctrl+1..5 tabs All/Favorites/PS2/PS3/PS4, Ctrl+6 achievements, Esc clears the search,
    F1 getting started, F11 TV mode.

TV MODE ("TV mode" button, F11 or Back/Select/Share on the controller)
  - Full screen for the couch: a row of big covers with the game's art behind it.
  - Controller: left/right chooses, A (X on PS) plays, Y (Triangle) settings, X (Square) favorite,
    LB/RB change console, B (Circle) or Back exits.
  - Keyboard: arrows, Enter plays, F2 settings, F favorite, Q/E or Tab change console, Esc exits.
  - Navigation sounds: toggle with the speaker in the corner or the S key.
  - When the game closes you go back to TV mode.

SAVES ("..." > Saves)
  - Back up now: a .zip with PS2 saves (memory cards and save states), PS3 and PS4 saves, trophies and
    the library (play time, favorites and chosen covers). Good for moving to another PC.
  - Restore backup: brings saves back from a .zip. Your current saves are stored first.
  - Automatic backup after playing, once a day, in app\cache\backups (keeps the last 5).

ABOUT, DIAGNOSTICS AND UPDATES ("..." > About and credits)
  - Trivium Hub version, version of each emulator, licenses and credits (app\licencas folder).
  - Diagnostics: checks this PC (CPU, graphics card, Vulkan, disk space), the emulators, BIOS and
    firmware. "Copy" gives you a report to paste when asking for help (no passwords, no user name).
  - Check for updates: downloads the new Trivium Hub version (games, saves and settings stay as they
    are). The launcher also checks by itself once a day.
  - If the launcher closes with an error, the details are in app\cache\erros.log.

GAME SETTINGS SCREEN
  - Each game keeps its own settings. Presets for weak and strong PCs, or adjust item by item.
  - Uncheck "Show this screen before every game" to go straight to the game.
  - All games: saturation, game volume and full screen. While you play, the launcher always uses high
    CPU priority and the High Performance power plan.
  - PS2: renderer, resolution, PS2 CPU speed (EE cycle rate), MTVU, fast CD, widescreen, VSync, show FPS.
  - PS2 "60 FPS": shows up by itself for games with a community 60 FPS patch (about 700 games, e.g.
    Midnight Club 3, GTA San Andreas, Burnout 3, Kingdom Hearts) and comes turned on. Patches that need
    a faster PS2 CPU (180% or 300%) get it automatically while the game runs. Only for the matching game
    version. If the game gets slow, lower the resolution; if it looks wrong, uncheck "60 FPS".
  - Anisotropic filter (PS2 and PS3): sharper floor and wall textures at a distance. Off by default.
    shadPS4 has no such option.
  - PS2 online: empty, which means off. Sony's original servers were shut down, so type in each game
    the DNS of a community server, unrelated to Sony. Examples: 45.7.228.197 (PS2Online, ps2online.com)
    and 67.222.156.250 (PS Rewired, psrewired.com). Games, regions and DNS are listed at
    ps2online.com/list. Many games still need a specific version and a DNAS fix the launcher does not
    do for you. The first time, create a network setting inside the game and save it to the memory card.
  - PS3: renderer, resolution scale, SPU Block Size, FPS limit, Write Color Buffers, VSync, show FPS.
    (Works for folder and PKG games. PS3 ISOs use RPCS3's global settings.)
  - PS4: full screen mode, VSync, game language, skip videos, FSR, PS4 Pro mode, show FPS. The launcher
    handles the technical options (extra memory, vblank, GPU readbacks, shader cache) by itself.
  - PS4 "Skip videos and intros": turns on community patches from the official shadPS4 repository. Only
    for some games and only for the right game version.
  - God of War III Remastered: community fixes (cuesta4's shadPS4 eltutz build, which needs a CPU with
    AVX2, texture fix with +2 GB of memory, relaxed GPU readbacks) and kvicken's 120 FPS patch, the same
    set SpartanPort uses. If the game closes on opening, uncheck the community fixes.
  - Bloodborne (1.09): the performance patches chosen by Bloodborne PC, GPU readbacks "Relaxed" (fixes
    the stretched polygons) and a 60 FPS or 90 FPS option (one at a time; 90 FPS needs a strong PC and a
    90 Hz monitor). Install update 1.09 too (Add > Install PS4 PKG).
  - Trivium achievements: PS3 games, and PS4 games with no trophy file, get 10 achievements of their own
    (play time, 2 hours in a row, different days and the Trivium Platinum). They do not replace official
    trophies and use nothing from PSN or RetroAchievements.

AUTO SAVE (PS2)
  - The launcher saves the game state every 10 minutes (5, 15 or off in the game settings).
  - If the game crashes or the PC shuts down, the launcher offers to continue from the auto save the
    next time you open the game.
  - Uses save state slot 10; the previous save is kept as a backup. Not available in Hardcore mode.
  - PS3/PS4: use the game's own save (it goes straight to disk and survives a crash).

ACHIEVEMENTS TAB (PS5 style; "..." > Achievements, Ctrl+6 or RB on the controller)
  - Top: your trophy level and the totals of platinum, gold, silver and bronze.
  - Left: games with trophies and their percentage. Right: the trophies of the chosen game.
  - PS2: from your RetroAchievements account (the same as PCSX2; free). Sign in under "Accounts and
    options". Your password is not stored. Hardcore mode counts for the site ranking but disables save
    states, slow motion and cheats. Not every PS2 game has achievements.
  - PS3: native RPCS3 trophies, including platinum.
  - PS4: without your own PS4's trophy key, the tab shows the real number of trophies and their original
    images, and marks unlocks from the shadPS4 log. With internet, the launcher gets type, name and
    description from PSNine's public list and translates them through MyMemory, once per game. These
    are automatic translations, not the official names.

VOLUME WHILE PLAYING
  - Minus key lowers 10%, plus key raises 10% (numeric keypad or next to Backspace). Hold to keep going.
  - A "Volume 70%" notice shows at the top of the screen. It does not show over shadPS4 games in full
    screen, but the volume still changes.
  - Changes only the game sound (not the Windows volume) and is saved for next time.

THE LAUNCHER DETECTS BY ITSELF
  - PS2 ISO vs PS3 ISO (reads the disc header)
  - .chd .cso .zso .gz .bin .mdf .img -> PS2
  - PS3 .pkg -> installs into RPCS3 the first time, then opens directly
  - folder with PS3_GAME\USRDIR\EBOOT.BIN -> PS3
  - folder with eboot.bin + sce_sys (PS4 dump, e.g. CUSA03173) -> PS4

PS4
  - Needs a CPU with AVX and a graphics card with Vulkan 1.3. The first time a game opens it can take a
    few minutes preparing the graphics.
  - PS4 PKG: Add > Install PS4 PKG (or add the .pkg to the list and click PLAY). It installs with a
    progress bar and no emulator window. Games go to the PS4 games folder (chosen the first time),
    updates go to CUSAxxxxx-UPDATE next to the game. You need free space the size of the PKG. DLC is not
    installed by the launcher yet. If the PKG is open in a torrent program, pause it first.
  - Only unlocked PKGs (fPKG) work; PSN PKGs are encrypted. In the same window you can pick the eboot.bin
    of an already installed game to just add it to the library. Errors say why (corrupted, encrypted,
    protected folder, antivirus blocking PkgTool).
  - Use your own game dump (folder with eboot.bin, sce_module and sce_sys).

IF THE GAME CLOSES WITH AN ERROR
  - The "The game closed" screen shows the most common causes for that console, the last errors from the
    emulator and the error type.
  - "Try with safe settings" switches the game to the most compatible options and opens it again.
  - "Open log" shows the full log; "Compatibility" opens the RPCS3 / shadPS4 list for the game.
  - It also shows if the game closes less than 12 seconds after opening.

FPS TIPS
  - Start with the weak PC preset and raise the resolution while the FPS holds.
  - PS2: "-1" on the PS2 CPU speed gives a lot of FPS; "-2" only if needed (can cause bugs).
  - PS3: SPU "Mega" helps most games; check wiki.rpcs3.net for your game.
  - PS3 / PS4: the first run of each game compiles shaders; FPS improves from the second run on.

CREDITS AND LICENSES
  The emulators are open source and included unmodified: see app\licencas\CREDITOS.txt.
  Not included: BIOS, firmware, keys and games. Use only BIOS, firmware and games you own.
  PSN PS3 PKGs usually need their .rap license file in dev_hdd0\home\00000001\exdata.
  PlayStation is a trademark of Sony Interactive Entertainment. Trivium Hub is not affiliated
  with Sony or with the emulator authors.
