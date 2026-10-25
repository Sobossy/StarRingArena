. (Join-Path $PSScriptRoot 'tools\common.ps1')
Ensure-Godot
# Explicit editor launcher requested by the user; visible editor is intentional.
Start-Process -FilePath $GodotEditor -ArgumentList @('--editor','--path',('"' + $ProjectRoot + '"')) -WorkingDirectory $ProjectRoot
