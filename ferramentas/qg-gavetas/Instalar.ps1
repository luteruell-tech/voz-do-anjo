<#
  Instala (ou atualiza) o servidor das gavetas:
  - copia os arquivos para %LOCALAPPDATA%\QG-Gavetas
  - faz o servidor ligar sozinho quando o Windows inicia (sem janela)
  - liga agora e abre o painel no navegador
  Use -Remover para desinstalar.
#>
param([switch]$Remover)
$ErrorActionPreference = 'Stop'
$dest    = Join-Path $env:LOCALAPPDATA 'QG-Gavetas'
$atalho  = Join-Path ([Environment]::GetFolderPath('Startup')) 'QG Gavetas.lnk'

# para o servidor que estiver rodando
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ServidorGavetas.ps1*' } |
    ForEach-Object { [void](Invoke-CimMethod -InputObject $_ -MethodName Terminate) }

if ($Remover) {
    if (Test-Path -LiteralPath $atalho) { Remove-Item -LiteralPath $atalho -Force }
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Write-Host 'Servidor das gavetas removido.' -ForegroundColor Green
    exit
}

[void](New-Item -ItemType Directory -Force -Path $dest)
foreach ($f in 'ServidorGavetas.ps1', 'gavetas.html') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination $dest -Force
    Unblock-File -LiteralPath (Join-Path $dest $f)
}
$ps1 = Join-Path $dest 'ServidorGavetas.ps1'
$vbs = Join-Path $dest 'iniciar.vbs'
$cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $ps1 + '""'
Set-Content -LiteralPath $vbs -Encoding ASCII -Value ('CreateObject("WScript.Shell").Run "' + $cmd + '", 0, False')

$sh  = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($atalho)
$lnk.TargetPath  = Join-Path $env:WINDIR 'System32\wscript.exe'
$lnk.Arguments   = '"' + $vbs + '"'
$lnk.Description = 'Servidor das gavetas - QG LUTERUEL TECH'
$lnk.Save()

Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + $vbs + '"')
Start-Sleep -Seconds 2
Start-Process 'http://127.0.0.1:8792/'
Write-Host ''
Write-Host 'Pronto! Servidor instalado e ligado.' -ForegroundColor Green
Write-Host 'Painel: http://127.0.0.1:8792/' -ForegroundColor Cyan
Write-Host 'Agora arraste o arquivo QG-Gavetas-Lively.zip para dentro do Lively Wallpaper.'
