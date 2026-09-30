<#
  SERVIDOR DAS GAVETAS - QG LUTERUEL TECH
  Mini servidor local (so aceita conexoes do proprio PC) que:
    - entrega o painel gavetas.html  -> http://127.0.0.1:8792/
    - abre a gaveta clicada no Explorador de Arquivos
    - abre os atalhos (sites) no navegador padrao
    - informa se o HD esta conectado e quantos arquivos ha em cada gaveta
  Acha sozinho a pasta "QG LUTERUEL TECH" em qualquer unidade (a letra do HD pode mudar).
#>
param(
    [int]$Porta = 8792,
    [string]$Raiz = '',       # opcional: caminho fixo da pasta QG
    [switch]$Simular          # teste: nao abre janelas, so registra
)
$ErrorActionPreference = 'Stop'
$pastaApp = $PSScriptRoot
$arqHtml  = Join-Path $pastaApp 'gavetas.html'
$nomeQG   = 'QG LUTERUEL TECH'
$sep      = [IO.Path]::DirectorySeparatorChar
$hostsOk  = @("127.0.0.1:$Porta", "localhost:$Porta")

function Achar-QG {
    if ($Raiz) { if (Test-Path -LiteralPath $Raiz -PathType Container) { return (Resolve-Path -LiteralPath $Raiz).ProviderPath.TrimEnd('\', '/') } return $null }
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $d.IsReady) { continue }
            $p = Join-Path $d.RootDirectory.FullName $nomeQG
            if ([IO.Directory]::Exists($p)) { return $p }
        } catch { }
    }
    return $null
}

# ---------- contagem de arquivos em segundo plano ----------
$estado = [hashtable]::Synchronized(@{ Contagem = @{}; Total = $null; Quando = [datetime]::MinValue; Rodando = $false; RaizContada = '' })
function Iniciar-Contagem([string]$raizQG) {
    if ($estado.Rodando) { return }
    $estado.Rodando = $true
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($r, $est)
        $res = @{}; $tn = 0; $tb = [int64]0
        try {
            $pilha = New-Object System.Collections.Generic.Stack[string]
            $pilha.Push($r)
            while ($pilha.Count) {
                $d = $pilha.Pop()
                $n = 0; $b = [int64]0
                try {
                    $di = New-Object IO.DirectoryInfo $d
                    foreach ($f in $di.EnumerateFiles()) { $n++; $b += $f.Length }
                    foreach ($s in $di.EnumerateDirectories()) {
                        if (-not ($s.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $pilha.Push($s.FullName) }
                    }
                } catch { }
                $tn += $n; $tb += $b
                if ($d.Length -gt $r.Length) {
                    $partes = $d.Substring($r.Length).Trim('\', '/') -split '[\\/]'
                    $k = ''
                    for ($i = 0; $i -lt [Math]::Min(3, $partes.Count); $i++) {
                        if ($i -eq 0) { $k = $partes[0] } else { $k = $k + '\' + $partes[$i] }
                        if (-not $res.ContainsKey($k)) { $res[$k] = @{ n = 0; b = [int64]0 } }
                        $res[$k].n += $n; $res[$k].b += $b
                    }
                }
            }
        } catch { }
        $est.Contagem = $res; $est.Total = @{ n = $tn; b = $tb }
        $est.Quando = Get-Date; $est.RaizContada = $r; $est.Rodando = $false
    }).AddArgument($raizQG).AddArgument($estado)
    [void]$ps.BeginInvoke()
}

# ---------- HTTP minimo ----------
function Responder($stream, [int]$cod, [string]$tipo, [byte[]]$corpo) {
    $txt = @{ 200 = 'OK'; 400 = 'Bad Request'; 403 = 'Forbidden'; 404 = 'Not Found'; 500 = 'Internal Server Error' }[$cod]
    $cab = "HTTP/1.1 $cod $txt`r`nContent-Type: $tipo`r`nContent-Length: $($corpo.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n"
    $b = [Text.Encoding]::ASCII.GetBytes($cab)
    $stream.Write($b, 0, $b.Length); if ($corpo.Length) { $stream.Write($corpo, 0, $corpo.Length) }
}
function Json($stream, [int]$cod, $obj) {
    Responder $stream $cod 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 5 -Compress)))
}
function Parametro([string]$query, [string]$nome) {
    foreach ($par in $query.TrimStart('?').Split('&')) {
        $i = $par.IndexOf('=')
        if ($i -gt 0 -and $par.Substring(0, $i) -eq $nome) { return [Uri]::UnescapeDataString($par.Substring($i + 1).Replace('+', ' ')) }
    }
    return $null
}
function Log([string]$m) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m) }

try {
    $ouvinte = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Porta)
    $ouvinte.Start()
} catch {
    Write-Host "Porta $Porta ja esta em uso (o servidor provavelmente ja esta rodando)." -ForegroundColor Yellow
    exit 1
}
Log "Servidor das gavetas em http://127.0.0.1:$Porta/"

while ($true) {
    $cli = $ouvinte.AcceptTcpClient()
    try {
        $cli.ReceiveTimeout = 3000; $cli.SendTimeout = 3000
        $st = $cli.GetStream()
        $leitor = New-Object IO.StreamReader($st, [Text.Encoding]::ASCII, $false, 8192, $true)
        $linha = $leitor.ReadLine()
        if (-not $linha) { continue }
        $cab = @{}
        while ($true) {
            $h = $leitor.ReadLine()
            if ($null -eq $h -or $h -eq '') { break }
            $i = $h.IndexOf(':'); if ($i -gt 0) { $cab[$h.Substring(0, $i).Trim().ToLowerInvariant()] = $h.Substring($i + 1).Trim() }
        }
        $partes = $linha.Split(' ')
        if ($partes.Count -lt 2) { Responder $st 400 'text/plain' @(); continue }
        $metodo = $partes[0]; $alvo = $partes[1]
        $iq = $alvo.IndexOf('?'); $rota = $alvo; $query = ''
        if ($iq -ge 0) { $rota = $alvo.Substring(0, $iq); $query = $alvo.Substring($iq) }

        # protege contra sites externos tentando usar o servidor
        if ($hostsOk -notcontains $cab['host']) { Responder $st 403 'text/plain' @(); continue }

        if ($metodo -eq 'GET' -and ($rota -eq '/' -or $rota -eq '/index.html')) {
            Responder $st 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($arqHtml)); continue
        }
        if ($metodo -eq 'GET' -and $rota -eq '/status') {
            $qg = Achar-QG
            if (-not $qg) { Json $st 200 @{ hd = $false }; continue }
            if ($estado.RaizContada -ne $qg -or ((Get-Date) - $estado.Quando).TotalMinutes -ge 5) { Iniciar-Contagem $qg }
            $uni = ''; if ($qg -match '^[A-Za-z]:') { $uni = $qg.Substring(0, 2) }
            Json $st 200 @{ hd = $true; unidade = $uni; contando = [bool]$estado.Rodando; contagem = $estado.Contagem; total = $estado.Total }
            continue
        }
        if ($metodo -ne 'POST') { Responder $st 404 'text/plain' @(); continue }
        # POST exige o cabecalho X-QG (sites externos nao conseguem enviar sem permissao)
        if ($cab['x-qg'] -ne '1') { Json $st 403 @{ ok = $false; erro = 'Pedido recusado' }; continue }

        if ($rota -eq '/abrir') {
            $g = Parametro $query 'g'; if ($null -eq $g) { $g = '' }
            $qg = Achar-QG
            if (-not $qg) { Json $st 200 @{ ok = $false; erro = 'HD NAO CONECTADO' }; continue }
            $rel = ($g -replace '[\\/]+', [string]$sep).Trim($sep)
            if ($rel -match '(^|[\\/])\.\.([\\/]|$)' -or $rel -match ':') { Json $st 400 @{ ok = $false; erro = 'Caminho invalido' }; continue }
            $destino = $qg; if ($rel) { $destino = Join-Path $qg $rel }
            $cheio = [IO.Path]::GetFullPath($destino)
            if ($cheio -ne $qg -and -not $cheio.StartsWith($qg + $sep, [StringComparison]::OrdinalIgnoreCase)) { Json $st 400 @{ ok = $false; erro = 'Caminho invalido' }; continue }
            [void][IO.Directory]::CreateDirectory($cheio)
            Log "Abrir: $cheio"
            if (-not $Simular) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $cheio + '"') }
            Json $st 200 @{ ok = $true; pasta = $cheio }; continue
        }
        if ($rota -eq '/url') {
            $u = Parametro $query 'u'
            if (-not $u -or $u -notmatch '^https?://[^\s"]+$') { Json $st 400 @{ ok = $false; erro = 'Endereco invalido' }; continue }
            Log "Site: $u"
            if (-not $Simular) { Start-Process -FilePath $u }
            Json $st 200 @{ ok = $true }; continue
        }
        Responder $st 404 'text/plain' @()
    } catch {
        Log "Erro: $($_.Exception.Message)"
        try { Json $st 500 @{ ok = $false; erro = 'Erro interno' } } catch { }
    } finally {
        $cli.Close()
    }
}
