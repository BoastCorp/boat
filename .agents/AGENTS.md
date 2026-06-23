# Workspace Rules

## Launching the Game
- Always launch the Playdate Simulator by executing `Source\run_game.ps1` inside a PowerShell shell. 
- The script has been configured to use the Windows Task Scheduler (`schtasks`) to launch the Playdate Simulator as a detached process. This ensures that the simulator process is not terminated by Windows Job Object limits when the parent PowerShell command finishes.
- Never run `PlaydateSimulator.exe` directly via standard PowerShell execution or `Start-Process` from within background execution environments, as they will get killed as soon as the execution step completes.

## Codebase Architecture
The game code has been modularized from a single monolithic file into the following components within the `Source/` directory:

- [config.lua](file:///c:/g/boat/Source/config.lua): Holds static configuration values, parameters, boundary coordinates, and other constants.
- [state.lua](file:///c:/g/boat/Source/state.lua): Houses the global mutable `State` table, which serves as the single source of truth for game variables (e.g. `State.money`, `State.boat`, `State.fish`).
- [input.lua](file:///c:/g/boat/Source/input.lua): Contains the input handling system, mapping button presses to actions depending on the active game screen (e.g. `handleDockInput`, `handleUpgradeInput`).
- [physics.lua](file:///c:/g/boat/Source/physics.lua): Contains collision detection, ray-casting calculations, boundary checking, and the core physical updates (`updatePhysics()`) for the boat and wake.
- [entities.lua](file:///c:/g/boat/Source/entities.lua): Manages spawning and behavior of active gameplay entities (waves, fish, littleguy).
- [ui.lua](file:///c:/g/boat/Source/ui.lua): Encapsulates all menu and overlay drawing logic (dock screens, upgrade screens, music screen, secret menu).
- [main.lua](file:///c:/g/boat/Source/main.lua): The central entry point. Loads shared assets (fonts, images), imports modules, handles top-level rendering, and orchestrates the main update loop (`playdate.update()`).

Use this structure when adding new features or fixing bugs to maintain modularity.
