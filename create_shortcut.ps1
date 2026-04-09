# create_shortcut.ps1
# Creates a meso360 desktop shortcut that opens the launch dialog.
# Run once from PowerShell: .\create_shortcut.ps1

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Desktop  = [Environment]::GetFolderPath('Desktop')
$Launcher = Join-Path $RepoDir 'launch_meso360.pyw'
$Icon     = Join-Path $RepoDir 'mesonet_launcher.ico'

# Find pythonw.exe — prefers the base conda env so no console flashes on launch
$PythonW = $null

$conda = (Get-Command conda -ErrorAction SilentlyContinue)
if ($conda) {
    # conda's Scripts folder is two levels up from conda.exe in typical installs
    $CondaRoot = Split-Path -Parent (Split-Path -Parent $conda.Source)
    $candidate = Join-Path $CondaRoot 'pythonw.exe'
    if (Test-Path $candidate) { $PythonW = $candidate }
}

if (-not $PythonW) {
    $cmd = Get-Command pythonw.exe -ErrorAction SilentlyContinue
    if ($cmd) { $PythonW = $cmd.Source }
}

if (-not $PythonW) {
    Write-Error "pythonw.exe not found. Activate your base conda environment and rerun."
    exit 1
}

$WS = New-Object -ComObject WScript.Shell
$SC = $WS.CreateShortcut("$Desktop\meso360.lnk")
$SC.TargetPath       = $PythonW
$SC.Arguments        = "`"$Launcher`""
$SC.WorkingDirectory = $RepoDir
$SC.IconLocation     = "$Icon,0"
$SC.Description      = "meso360 Supervisor"
$SC.Save()

Write-Host "Shortcut created: $Desktop\meso360.lnk"
Write-Host "  -> $PythonW `"$Launcher`""
