. (Join-Path $PSScriptRoot 'tools\common.ps1')
Ensure-Godot
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--editor','--import')
# This is the interactive game the user explicitly opened, so its window must be visible.
Start-Process -FilePath $GodotEditor -ArgumentList @('--path',('"' + $ProjectRoot + '"')) -WorkingDirectory $ProjectRoot
