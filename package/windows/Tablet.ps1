param([ValidateSet('Stage','Arm','Restore','Check')][string]$Action='Check')
$ErrorActionPreference='Stop'
$stage='C:\GalaxyBookTest'
$stock='C:\AndroidOS'
function Check-Hashes($folder,$manifest) {
    foreach($line in Get-Content -LiteralPath $manifest) {
        if($line -notmatch '^([0-9a-f]{64})  ([a-zA-Z0-9_.-]+)$'){throw 'Invalid checksum manifest.'}
        $expected=$Matches[1]; $file=Join-Path $folder $Matches[2]
        if((Get-FileHash -LiteralPath $file).Hash -ne $expected){throw "Checksum mismatch: $file"}
    }
}
function Native($program,$arguments) {
    $result=& $program @arguments 2>&1
    if($LASTEXITCODE -ne 0){throw "$program failed: $result"}
    return ($result -join [Environment]::NewLine)
}
function Check-Base {
    if($env:SystemDrive -ne 'C:'){throw 'The verified installation uses C:.'}
    if((Get-CimInstance Win32_ComputerSystem).Model -notmatch 'Galaxy Book 12 LTE'){throw 'Unexpected tablet model.'}
    Check-Hashes $stock (Join-Path $PSScriptRoot 'stock.sha256')
    Check-Hashes $PSScriptRoot (Join-Path $PSScriptRoot 'payload.sha256')
}
if($Action -in 'Stage','Check') {
    Check-Base
    if($Action -eq 'Check'){Write-Output 'Package and installed base hashes verified.'; return}
    if(Test-Path -LiteralPath $stage){throw "$stage already exists. Your existing files have been preserved."}
    if((Get-PSDrive C).Free -lt 6GB){throw 'At least 6 GiB free on C: is needed.'}
    $pending=Join-Path 'C:\' ('GalaxyBookStage-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $pending | Out-Null
    foreach($name in 'kernel','initrd.img','payload.sha256','stock.sha256'){
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $pending
    }
    Copy-Item -LiteralPath "$stock\system.efs" -Destination $pending
    $stream=[IO.File]::OpenRead((Join-Path $PSScriptRoot 'data.img.gz'))
    try {
        $gz=[IO.Compression.GZipStream]::new($stream,[IO.Compression.CompressionMode]::Decompress)
        $dest=[IO.File]::Create((Join-Path $pending 'data.img'))
        try {$gz.CopyTo($dest)} finally {$dest.Dispose();$gz.Dispose()}
    } finally {$stream.Dispose()}
    if((Get-Item "$pending\data.img").Length -ne 2GB){throw 'Test data image size mismatch.'}
    if((Get-FileHash "$pending\system.efs").Hash -ne '8b0c68d88f8e9bf189ba8707328082ab8412c3e557c1f605ff5e43dbe4300572'){throw 'Staged system image verification failed.'}
    [IO.File]::WriteAllText("$pending\stage.key",[guid]::NewGuid().ToString('N'))
    [IO.Directory]::Move($pending,$stage)
    Write-Output "Staged $stage. Boot settings have not been changed."
    return
}
function Read-BootManager {Native 'bcdedit.exe' @('/enum','{fwbootmgr}')}
function Install-GrubConfig($source,$cfg,$expected) {
    $incoming=$cfg+'.gb-new'
    $previous=$cfg+'.gb-previous'
    if((Test-Path $incoming) -or (Test-Path $previous)){throw 'A previous EFI update needs recovery. Windows remains the firmware default.'}
    Copy-Item -LiteralPath $source -Destination $incoming
    if((Get-FileHash $incoming).Hash -ne $expected){throw 'EFI copy checksum mismatch.'}
    $hadConfig=Test-Path $cfg
    if($hadConfig){[IO.File]::Move($cfg,$previous)}
    try {[IO.File]::Move($incoming,$cfg)} catch {
        if($hadConfig){[IO.File]::Move($previous,$cfg)}
        throw
    }
    if((Get-FileHash $cfg).Hash -ne $expected){throw 'EFI configuration verification failed.'}
    if($hadConfig){Remove-Item -LiteralPath $previous}
}
$part=Get-Partition -DriveLetter C
$disk=Get-Disk -Number $part.DiskNumber
if($disk.BusType -ne 'SATA' -or $disk.PartitionStyle -ne 'GPT' -or !$disk.IsBoot -or !$disk.IsSystem){throw 'Expected the Windows system and EFI partition on the same internal SATA GPT SSD.'}
$letters=[Environment]::GetLogicalDrives()
$letter=@('S','T','U','V','W','Y','Z') | Where-Object {$letters -notcontains ($_+':\')} | Select-Object -First 1
if(!$letter){throw 'No unused drive letter for the EFI partition.'}
$drive=$letter+':'
$null=Native 'mountvol.exe' @($drive,'/S')
try {
    if((Get-Partition -DriveLetter $letter).DiskNumber -ne $disk.Number){throw 'EFI disk mismatch.'}
    $cfg="$drive\EFI\Boot\grub.cfg"
    $bak="$stage\original-grub.cfg"
    $state="$stage\boot-state.json"
    if($Action -eq 'Restore') {
        if(!(Test-Path $state)){Write-Output 'No saved test boot state.';return}
        $s=Get-Content $state -Raw | ConvertFrom-Json
        if((Get-FileHash $bak).Hash -ne $s.original){throw 'GRUB backup checksum mismatch.'}
        foreach($suffix in '.gb-new','.gb-previous') {
            $temp=$cfg+$suffix
            if(Test-Path $temp){
                if((Get-FileHash $temp).Hash -notin @($s.original,$s.test)){throw "Unexpected EFI recovery file: $temp"}
                Remove-Item -LiteralPath $temp
            }
        }
        $manager=Read-BootManager
        if($manager -match ('(?im)^\s*bootsequence\s+'+[regex]::Escape($s.entry)+'\s*$')){
            $null=Native 'bcdedit.exe' @('/deletevalue','{fwbootmgr}','bootsequence')
        }
        if(Test-Path $cfg){
            $hash=(Get-FileHash $cfg).Hash
            if($hash -ne $s.original -and $hash -ne $s.test){throw 'EFI configuration has changed independently. Backup retained.'}
        }
        Install-GrubConfig $bak $cfg $s.original
        if((Get-FileHash $cfg).Hash -ne $s.original){throw 'Restore verification failed.'}
        Remove-Item -LiteralPath $state
        Write-Output 'Original GRUB configuration restored and verified. Backup retained.'
        return
    }
    if(Test-Path $state){throw 'Use Restore before another one-time test.'}
    Check-Base
    foreach($name in 'kernel','initrd.img'){
        if((Get-FileHash "$stage\$name").Hash -ne (Get-FileHash "$PSScriptRoot\$name").Hash){throw "Staged $name differs from package."}
    }
    if((Get-FileHash "$stage\system.efs").Hash -ne (Get-FileHash "$stock\system.efs").Hash){throw 'Staged system image mismatch.'}
    if((Get-Item "$stage\data.img").Length -ne 2GB){throw 'Missing staged data image.'}
    if(Confirm-SecureBootUEFI){throw 'Secure Boot is enabled.'}
    $volume=Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='C:'"
    $conversion=Invoke-CimMethod -InputObject $volume -MethodName GetConversionStatus
    if($conversion.ReturnValue -ne 0 -or $conversion.ConversionStatus -ne 0){throw 'C: must already be fully decrypted. No encryption settings were changed.'}
    $manager=Read-BootManager
    if($manager -notmatch '(?im)^\s*displayorder\s+\{bootmgr\}\s*$' -or $manager -match '(?im)^\s*bootsequence\s+'){throw 'Windows must be the first firmware entry, with no pending one-time boot.'}
    $entries=(Native 'bcdedit.exe' @('/enum','firmware')) -split '(?:\r?\n\s*){2,}'
    $windows=@($entries | Where-Object {$_ -match '(?im)^\s*identifier\s+\{bootmgr\}\s*$'})
    if($windows.Count -ne 1 -or $windows[0] -notmatch '(?im)^\s*device\s+(partition=[^\r\n]+?)\s*$'){throw 'Could not identify the Windows EFI device.'}
    $deviceLine='(?im)^\s*device\s+'+[regex]::Escape($Matches[1].Trim())+'\s*$'
    $ids=@(foreach($block in $entries){
        if($block -match $deviceLine -and $block -match '(?im)^\s*path\s+\\EFI\\Boot\\(?:grubx64|bootx64)\.efi\s*$' -and $block -match '(?im)^\s*identifier\s+(\{[0-9a-f-]{36}\})\s*$'){$Matches[1]}
    })
    if($ids.Count -ne 1){throw 'Could not uniquely identify the existing Android EFI loader.'}
    if((Get-Content $cfg -Raw) -notmatch '/AndroidOS/kernel'){throw 'Unexpected existing GRUB configuration.'}
    if((Read-Host 'Remove the SD card, save your work, then type TEST to arm one boot') -cne 'TEST'){throw 'Test cancelled.'}
    $key=(Get-Content "$stage\stage.key" -Raw).Trim()
    if($key -notmatch '^[a-f0-9]{32}$'){throw 'Invalid stage key.'}
    $num=[int]$part.PartitionNumber
    $script=@'
if regexp --set=1:disk '^\(([^,)]+),gpt[0-9]+\)' "$cmdpath"; then
  set root=($disk,gptPARTNUM)
  if [ -f /GalaxyBookTest/stage.key ]; then
    linux /GalaxyBookTest/kernel root=/dev/ram0 SRC=GalaxyBookTest GBROOT=/dev/sdaPARTNUM GBKEY=STAGEKEY panic=10
    initrd /GalaxyBookTest/initrd.img
    boot
  fi
fi
reboot
'@
    $script=$script.Replace('PARTNUM',"$num").Replace('STAGEKEY',$key).Replace([string][char]13,"")
    $testFile="$stage\test-grub.cfg"
    [IO.File]::WriteAllText($testFile,$script+[char]10,[Text.Encoding]::ASCII)
    Copy-Item -LiteralPath $cfg -Destination $bak -Force
    $original=(Get-FileHash $cfg).Hash; $test=(Get-FileHash $testFile).Hash
    if((Get-FileHash $bak).Hash -ne $original){throw 'EFI backup failed.'}
    @{original=$original;test=$test;entry=$ids[0]} | ConvertTo-Json | Set-Content -LiteralPath $state
    try {
        Install-GrubConfig $testFile $cfg $test
        if((Get-FileHash $cfg).Hash -ne $test){throw 'EFI test configuration verification failed.'}
        $null=Native 'bcdedit.exe' @('/set','{fwbootmgr}','bootsequence',$ids[0])
    } catch {
        if((Test-Path $cfg) -and (Get-FileHash $cfg).Hash -eq $test){Install-GrubConfig $bak $cfg $original}
        throw
    }
    Write-Output 'One test boot is armed. Use Windows Restart when ready. Restore cancels it.'
} finally {$null=Native 'mountvol.exe' @($drive,'/D')}

