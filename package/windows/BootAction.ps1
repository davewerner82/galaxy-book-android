param([Parameter(Mandatory=$true)][ValidateSet('Arm','Restore')][string]$Action)
$ErrorActionPreference='Stop'
$log=Join-Path $PSScriptRoot ('last-'+$Action.ToLowerInvariant()+'.txt')
$admin=[Security.Principal.WindowsBuiltInRole]::Administrator
if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole($admin)){
    try {
        $child=Start-Process -FilePath "$PSHOME\powershell.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Action',$Action)
        exit $child.ExitCode
    } catch {
        "Windows administrator consent was unavailable: $($_.Exception.Message)" | Tee-Object -FilePath $log
        exit 1
    }
}
try {
    $lines=& (Join-Path $PSScriptRoot 'Tablet.ps1') -Action $Action
    @((Get-Date -Format o),$lines) | Set-Content -LiteralPath $log
    exit 0
} catch {
    @((Get-Date -Format o),$_.Exception.Message,$_.InvocationInfo.PositionMessage,$_.ScriptStackTrace) | Set-Content -LiteralPath $log
    exit 1
}
