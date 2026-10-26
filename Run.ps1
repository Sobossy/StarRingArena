param([switch]$Mobile)
. (Join-Path $PSScriptRoot 'tools\common.ps1')
Ensure-Godot
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--editor','--import','--quit')
# This is the interactive game the user explicitly opened, so its window must be visible.
$launchArguments = @('--path',('"' + $ProjectRoot + '"'))
if ($Mobile) { $launchArguments += @('--resolution','720x1280','--','--mobile') }
Start-Process -FilePath $GodotEditor -ArgumentList $launchArguments -WorkingDirectory $ProjectRoot
