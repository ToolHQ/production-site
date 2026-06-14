Write-Host "Shutting down WSL..."
wsl --shutdown

$paths = @(
    "C:\Users\dnorio\Ubuntu\ext4.vhdx",
    "C:\Users\dnorio\AppData\Local\Docker\wsl\data\ext4.vhdx"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Write-Host "Shrinking $path..."
        $script = "select vdisk file=`"$path`"`nattach vdisk readonly`ncompact vdisk`ndetach vdisk"
        $script | diskpart
    }
}
Write-Host "Done!"
Pause
