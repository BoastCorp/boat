$pdc = "C:\Program Files\PlaydateSDK\bin\pdc.exe"
$sim = "C:\Program Files\PlaydateSDK\bin\PlaydateSimulator.exe"

# Resolve absolute path for build output
$outputPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) "..\boat.pdx"))
Write-Host "PDC Path: $pdc"
Write-Host "SIM Path: $sim"
Write-Host "Output Path: $outputPath"

# Clean up old build
if (Test-Path $outputPath) { Remove-Item -Recurse -Force $outputPath }

# Build
& $pdc . $outputPath

# Launch simulator
Write-Host "Launching simulator..."
Stop-Process -Name PlaydateSimulator -Force -ErrorAction SilentlyContinue

$taskName = "PlaydateGameLaunch"

# Delete existing task if any
schtasks /delete /tn $taskName /f 2>&1 | Out-Null

# Create, run, and clean up the task
schtasks /create /tn $taskName /tr "'$sim' '$outputPath'" /sc ONCE /sd 01/01/2030 /st 00:00 /f 2>&1 | Out-Null
schtasks /run /tn $taskName 2>&1 | Out-Null
Start-Sleep -Seconds 1
schtasks /delete /tn $taskName /f 2>&1 | Out-Null

Write-Host "Simulator successfully launched in user session."
