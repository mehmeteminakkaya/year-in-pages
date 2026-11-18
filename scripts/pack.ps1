# Builds dist/yearinpages.koplugin.zip containing the yearinpages.koplugin folder.
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "yearinpages.koplugin.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $root "yearinpages.koplugin") -DestinationPath $zip
Write-Output "Built $zip"
