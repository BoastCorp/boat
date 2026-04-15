$pdc = "C:\Program Files\PlaydateSDK\bin\pdc.exe"
$sim = "C:\Program Files\PlaydateSDK\bin\PlaydateSimulator.exe"

# Clean up old build
if (Test-Path "..\boat.pdx") { Remove-Item -Recurse -Force "..\boat.pdx" }

# Build one level up so boat.pdx isn't inside the Source folder
& $pdc . "..\boat.pdx"

# If build succeeded, launch simulator
if ($LASTEXITCODE -eq 0) {
    & $sim "..\boat.pdx"
}
