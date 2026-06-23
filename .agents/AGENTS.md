# Workspace Rules

## Launching the Game
- Always launch the Playdate Simulator by executing `Source\run_game.ps1` inside a PowerShell shell. 
- The script has been configured to use the Windows Task Scheduler (`schtasks`) to launch the Playdate Simulator as a detached process. This ensures that the simulator process is not terminated by Windows Job Object limits when the parent PowerShell command finishes.
- Never run `PlaydateSimulator.exe` directly via standard PowerShell execution or `Start-Process` from within background execution environments, as they will get killed as soon as the execution step completes.
