<#
  ORGANIZADOR DE HD - inventario e organizacao segura
  - NADA e apagado. Lixo e duplicados vao para pastas de revisao.
  - Todo movimento e registrado e pode ser desfeito (modo Desfazer).
  Modos:
    Inventario : so le o HD e gera o relatorio (nao mexe em nada)
    Organizar  : move os arquivos conforme o plano do relatorio
    Desfazer   : devolve tudo ao lugar original (usa o ultimo registro)
    Limpar     : APAGA DE VEZ o lixo e as copias duplicadas (confere antes que o original existe)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Unidade,
    [ValidateSet('Inventario', 'Organizar', 'Desfazer', 'Limpar')][string]$Modo = 'Inventario',
    [switch]$SemConfirmacao
)

$ErrorActionPreference = 'Stop'
$sep = [IO.Path]::DirectorySeparatorChar

# ---------- Raiz ----------
$u = $Unidade.Trim().Trim('"')
if ($u -match '^[A-Za-z]:?\\?$') { $u = $u.Substring(0, 1).ToUpper() + ':\' }
if (-not (Test-Path -LiteralPath $u -PathType Container)) { throw "Unidade/pasta nao encontrada: $u" }
$raizInfo = New-Object IO.DirectoryInfo((Resolve-Path -LiteralPath $u).ProviderPath)
$raiz = $raizInfo.FullName.TrimEnd('\', '/') + $sep
if ($env:SystemDrive -and $raiz -ieq ($env:SystemDrive + '\')) { throw "Por seguranca, nao rode no disco do sistema ($raiz)." }

$dirRel  = Join-Path $raiz '_RELATORIO_HD'
$dirOrg  = Join-Path $raiz '_ORGANIZADO'
$dirLixo = Join-Path $raiz '_LIXO_REVISAR'
$dirDup  = Join-Path $raiz '_DUPLICADOS'
$pastasNossas = @('_ORGANIZADO', '_LIXO_REVISAR', '_DUPLICADOS')
$ignorar = @('$RECYCLE.BIN', 'System Volume Information', '_RELATORIO_HD', 'RECYCLER',
             '.Trashes', '.Spotlight-V100', '.fseventsd', '.TemporaryItems', 'FOUND.000')
$carimbo = Get-Date -Format 'yyyy-MM-dd_HHmmss'

function Fmt([double]$b) {
    if ($b -ge 1TB) { return ('{0:N2} TB' -f ($b / 1TB)) }
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b / 1KB)) }
    return ('{0:N0} B' -f $b)
}
function Rel([string]$p) {
    if (($p.TrimEnd('\', '/') + $sep) -ieq $raiz) { return '' }
    if ($p.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase)) { return $p.Substring($raiz.Length) }
    return $p
}
function Html([string]$s) { return [System.Net.WebUtility]::HtmlEncode($s) }
function Get-Md5([string]$caminho, [bool]$parcial) {
    $bloco = 4MB
    $fs = [IO.File]::Open($caminho, 'Open', 'Read', 'ReadWrite')
    $md5 = [Security.Cryptography.MD5]::Create()
    try {
        if (-not $parcial -or $fs.Length -le (2 * $bloco)) {
            return [BitConverter]::ToString($md5.ComputeHash($fs))
        }
        $buf = New-Object byte[] $bloco
        foreach ($pos in @(0, ($fs.Length - $bloco))) {
            [void]$fs.Seek($pos, 'Begin'); $lido = 0
            while ($lido -lt $bloco) { $n = $fs.Read($buf, $lido, $bloco - $lido); if ($n -le 0) { break }; $lido += $n }
            [void]$md5.TransformBlock($buf, 0, $lido, $null, 0)
        }
        [void]$md5.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        return [BitConverter]::ToString($md5.Hash)
    } finally { $fs.Dispose(); $md5.Dispose() }
}
function Limpar([string]$s) { return ($s -replace '[\\/:*?"<>|]', '_').Trim() }

# =====================================================================
# DESFAZER
# =====================================================================
if ($Modo -eq 'Desfazer') {
    $log = Get-ChildItem -LiteralPath $dirRel -Filter 'registro_movimentos_*.csv' -ErrorAction SilentlyContinue |
           Sort-Object Name | Select-Object -Last 1
    if (-not $log) { throw "Nenhum registro de movimentos encontrado em $dirRel" }
    Write-Host "Desfazendo com base em: $($log.Name)" -ForegroundColor Cyan
    if (-not $SemConfirmacao) {
        if ((Read-Host 'Digite SIM para devolver os arquivos ao lugar original') -ne 'SIM') { Write-Host 'Cancelado.'; exit }
    }
    $linhas = @(Import-Csv -LiteralPath $log.FullName -Delimiter ';' -Encoding UTF8)
    [array]::Reverse($linhas)
    $ok = 0; $falhas = New-Object System.Collections.Generic.List[string]
    foreach ($l in $linhas) {
        if ($l.Status -ne 'OK') { continue }
        try {
            if ($l.Tipo -eq 'PastaVaziaRemovida') {
                [void][IO.Directory]::CreateDirectory($l.Origem)
                continue
            }
            if (-not (Test-Path -LiteralPath $l.Destino)) { $falhas.Add("Nao encontrado: $($l.Destino)"); continue }
            if (Test-Path -LiteralPath $l.Origem) { $falhas.Add("Ja existe no lugar original: $($l.Origem)"); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($l.Origem))
            if ($l.Tipo -eq 'Pasta') { [IO.Directory]::Move($l.Destino, $l.Origem) } else { [IO.File]::Move($l.Destino, $l.Origem) }
            $ok++
        } catch { $falhas.Add("$($l.Destino) -> $($_.Exception.Message)") }
    }
    # remove pastas de organizacao que ficaram vazias
    foreach ($p in @($dirOrg, $dirLixo, $dirDup)) {
        if (Test-Path -LiteralPath $p) {
            Get-ChildItem -LiteralPath $p -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object { if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName } }
            if (-not (Get-ChildItem -LiteralPath $p -Force)) { Remove-Item -LiteralPath $p }
        }
    }
    Rename-Item -LiteralPath $log.FullName -NewName ($log.Name -replace '^registro_', 'DESFEITO_registro_')
    Write-Host "Itens devolvidos: $ok" -ForegroundColor Green
    if ($falhas.Count) { Write-Host "Falhas: $($falhas.Count)" -ForegroundColor Yellow; $falhas | ForEach-Object { Write-Host "  $_" } }
    exit
}

# =====================================================================
# LIMPAR (exclusao definitiva do lixo e das copias duplicadas)
# =====================================================================
if ($Modo -eq 'Limpar') {
    $ref = @{}
    foreach ($lg in @(Get-ChildItem -LiteralPath $dirRel -Filter 'registro_movimentos_*.csv' -ErrorAction SilentlyContinue)) {
        foreach ($l in (Import-Csv -LiteralPath $lg.FullName -Delimiter ';' -Encoding UTF8)) {
            if ($l.Status -eq 'OK' -and $l.Tipo -eq 'Arquivo' -and $l.PSObject.Properties['Referencia'] -and $l.Referencia) { $ref[$l.Destino] = $l.Referencia }
        }
    }
    $apagar = New-Object System.Collections.Generic.List[object]
    $fica   = New-Object System.Collections.Generic.List[object]
    if (Test-Path -LiteralPath $dirLixo) {
        foreach ($f in (Get-ChildItem -LiteralPath $dirLixo -Recurse -File -Force)) {
            $apagar.Add([pscustomobject]@{ Arquivo = $f.FullName; TamanhoBytes = [int64]$f.Length; Tamanho = Fmt $f.Length; Motivo = 'Lixo' })
        }
    }
    if (Test-Path -LiteralPath $dirDup) {
        Write-Host 'Conferindo cada copia contra o original (nome, tamanho e conteudo)...' -ForegroundColor Cyan
        foreach ($f in (Get-ChildItem -LiteralPath $dirDup -Recurse -File -Force)) {
            $r = $ref[$f.FullName]; $m = ''
            if (-not $r) { $m = 'Sem registro do original' }
            elseif (-not (Test-Path -LiteralPath $r -PathType Leaf)) { $m = 'Original nao encontrado' }
            elseif ((Get-Item -LiteralPath $r -Force).Length -ne $f.Length) { $m = 'Original com tamanho diferente' }
            else { try { if ((Get-Md5 $r $false) -ne (Get-Md5 $f.FullName $false)) { $m = 'Conteudo diferente do original' } } catch { $m = 'Erro ao ler' } }
            if ($m) { $fica.Add([pscustomobject]@{ Arquivo = $f.FullName; Motivo = $m }) }
            else { $apagar.Add([pscustomobject]@{ Arquivo = $f.FullName; TamanhoBytes = [int64]$f.Length; Tamanho = Fmt $f.Length; Motivo = 'Copia identica de: ' + (Rel $r) }) }
        }
    }
    if ($apagar.Count -eq 0) { Write-Host 'Nada para apagar.'; if ($fica.Count) { $fica | Format-Table -AutoSize } ; exit }
    [void][IO.Directory]::CreateDirectory($dirRel)
    $encCsv = $(if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' })
    $lista = Join-Path $dirRel "lista_para_apagar_$carimbo.csv"
    $apagar | Export-Csv -LiteralPath $lista -Delimiter ';' -NoTypeInformation -Encoding $encCsv
    $tl = [int64](($apagar | Where-Object { $_.Motivo -eq 'Lixo' } | Measure-Object TamanhoBytes -Sum).Sum)
    $td = [int64](($apagar | Where-Object { $_.Motivo -ne 'Lixo' } | Measure-Object TamanhoBytes -Sum).Sum)
    Write-Host ''
    Write-Host "Lixo a apagar      : $(@($apagar | Where-Object { $_.Motivo -eq 'Lixo' }).Count) arquivos ($(Fmt $tl))" -ForegroundColor Yellow
    Write-Host "Copias a apagar    : $(@($apagar | Where-Object { $_.Motivo -ne 'Lixo' }).Count) arquivos ($(Fmt $td)) - original conferido" -ForegroundColor Yellow
    Write-Host "Copias que FICAM   : $($fica.Count) (nao deu para confirmar o original)"
    Write-Host "Lista completa     : $lista" -ForegroundColor Cyan
    Write-Host 'ATENCAO: exclusao DEFINITIVA, nao da para desfazer.' -ForegroundColor Red
    if (-not $SemConfirmacao) {
        if ((Read-Host 'Digite APAGAR para confirmar') -ne 'APAGAR') { Write-Host 'Cancelado. Nada foi apagado.'; exit }
    }
    $regEx = Join-Path $dirRel "registro_exclusoes_$carimbo.csv"
    $ok = 0; $falhas = 0; $liberado = [int64]0
    $linhasEx = New-Object System.Collections.Generic.List[object]
    foreach ($x in $apagar) {
        try { Remove-Item -LiteralPath $x.Arquivo -Force; $ok++; $liberado += $x.TamanhoBytes; $st = 'APAGADO'; $er = '' }
        catch { $falhas++; $st = 'FALHA'; $er = $_.Exception.Message }
        $linhasEx.Add([pscustomobject]@{ Status = $st; Arquivo = $x.Arquivo; Tamanho = $x.Tamanho; Motivo = $x.Motivo; Erro = $er })
    }
    $linhasEx | Export-Csv -LiteralPath $regEx -Delimiter ';' -NoTypeInformation -Encoding $encCsv
    foreach ($p in @($dirLixo, $dirDup)) {
        if (Test-Path -LiteralPath $p) {
            Get-ChildItem -LiteralPath $p -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object { if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName } }
            if (-not (Get-ChildItem -LiteralPath $p -Force)) { Remove-Item -LiteralPath $p }
        }
    }
    Write-Host "Apagados: $ok | Falhas: $falhas | Espaco liberado: $(Fmt $liberado)" -ForegroundColor Green
    Write-Host "Registro: $regEx" -ForegroundColor Cyan
    exit
}

# =====================================================================
# CATEGORIAS
# =====================================================================
$cat = @{}
function Add-Cat([string]$nome, [string[]]$exts) { foreach ($e in $exts) { $cat['.' + $e] = $nome } }
Add-Cat 'Fotos'                        'jpg','jpeg','png','gif','bmp','heic','heif','webp','tif','tiff','raw','cr2','cr3','nef','arw','dng','orf','rw2','jfif'
Add-Cat 'Videos'                       'mp4','mov','avi','mkv','wmv','flv','m4v','3gp','mpg','mpeg','webm','mts','m2ts','ts','vob','divx'
Add-Cat 'Musicas_e_Audios'             'mp3','wav','flac','aac','m4a','ogg','wma','opus','amr','aiff','mid','midi'
Add-Cat 'Documentos\PDF'               'pdf'
Add-Cat 'Documentos\Textos'            'doc','docx','odt','rtf','txt','pages','md'
Add-Cat 'Documentos\Planilhas'         'xls','xlsx','xlsm','ods','csv','numbers'
Add-Cat 'Documentos\Apresentacoes'     'ppt','pptx','pps','ppsx','odp','key'
Add-Cat 'Livros'                       'epub','mobi','azw','azw3','djvu','cbr','cbz'
Add-Cat 'Compactados'                  'zip','rar','7z','tar','gz','bz2','xz','iso','img'
Add-Cat 'Instaladores'                 'exe','msi','apk','dmg','pkg','deb','appx','xapk'
Add-Cat 'Design'                       'psd','ai','cdr','svg','indd','xd','fig','sketch','eps','afphoto','afdesign'
Add-Cat 'Emails_e_Contatos'            'eml','msg','pst','ost','mbox','vcf'
Add-Cat 'Legendas'                     'srt','sub','ass','ssa','vtt'
Add-Cat 'Fontes'                       'ttf','otf','woff','woff2','fon'

$lixoNomes = @('thumbs.db', 'desktop.ini', '.ds_store', 'ehthumbs.db', 'ehthumbs_vista.db', 'icon' + [char]13)
$lixoExt   = @{ '.tmp' = 'Temporario'; '.temp' = 'Temporario'; '.crdownload' = 'Download incompleto';
                '.part' = 'Download incompleto'; '.partial' = 'Download incompleto'; '.download' = 'Download incompleto';
                '.!ut' = 'Download incompleto'; '.bc!' = 'Download incompleto'; '.lnk' = 'Atalho';
                '.log' = 'Log'; '.dmp' = 'Dump de erro'; '.chk' = 'Fragmento recuperado (CHKDSK)' }

function Motivo-Lixo([IO.FileInfo]$f) {
    $n = $f.Name.ToLower()
    if ($lixoNomes -contains $n) { return 'Arquivo de sistema/miniatura' }
    if ($n.StartsWith('._')) { return 'Resto de Mac' }
    if ($n.StartsWith('~$')) { return 'Temporario do Office' }
    $e = $f.Extension.ToLower()
    if ($lixoExt.ContainsKey($e)) { return $lixoExt[$e] }
    if ($f.Length -eq 0) { return 'Arquivo vazio (0 bytes)' }
    return ''
}

# Pastas que precisam ficar inteiras (programas, projetos, jogos, catalogos)
$marcadores = @('.git', '.svn', 'package.json', 'pom.xml', 'build.gradle', 'cmakelists.txt', 'cargo.toml',
                'composer.json', 'manage.py', 'go.mod', 'gemfile', 'manifest.db', 'autorun.inf', 'steam_api.dll', 'unins000.exe')
$marcadoresExt = @('.sln', '.csproj', '.vcxproj', '.xcodeproj', '.lrcat', '.aep', '.prproj', '.veg', '.als', '.flp', '.cpr')
function Motivo-Protegida($arqs, $dirs) {
    $dll = 0; $exe = $false
    foreach ($x in $dirs) { if ($marcadores -contains $x.Name.ToLower()) { return "contem $($x.Name)" } }
    foreach ($x in $arqs) {
        $n = $x.Name.ToLower(); $e = $x.Extension.ToLower()
        if ($marcadores -contains $n) { return "contem $($x.Name)" }
        if ($marcadoresExt -contains $e) { return "contem arquivo $e" }
        if ($e -eq '.dll') { $dll++ }
        if ($e -eq '.exe') { $exe = $true }
    }
    if ($dll -ge 3 -or ($dll -ge 1 -and $exe)) { return 'programa (exe/dll)' }
    return ''
}

# =====================================================================
# 1) VARREDURA
# =====================================================================
Write-Host "Lendo $raiz ... (pode demorar em HDs grandes)" -ForegroundColor Cyan
$arquivos   = New-Object System.Collections.Generic.List[object]
$protegidas = New-Object System.Collections.Generic.List[object]
$erros      = New-Object System.Collections.Generic.List[object]
$pilha      = New-Object System.Collections.Generic.Stack[object]
$pilha.Push(@($raizInfo, ''))
$cont = 0

while ($pilha.Count -gt 0) {
    $item = $pilha.Pop(); $d = $item[0]; $prot = $item[1]
    try { $filhos = $d.GetFileSystemInfos() }
    catch { $erros.Add([pscustomobject]@{ Caminho = $d.FullName; Erro = $_.Exception.Message }); continue }

    $subs = New-Object System.Collections.Generic.List[object]
    $arqs = New-Object System.Collections.Generic.List[object]
    foreach ($f in $filhos) {
        if ($f -is [IO.DirectoryInfo]) {
            if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($ignorar -contains $f.Name) { continue }
            $subs.Add($f)
        } else { $arqs.Add($f) }
    }

    $relD = Rel ($d.FullName.TrimEnd('\', '/') + $sep)
    $dentroNossa = $false
    foreach ($pn in $pastasNossas) { if ($relD.StartsWith($pn + $sep, [StringComparison]::OrdinalIgnoreCase)) { $dentroNossa = $true } }

    if (-not $prot -and $relD -ne '' -and -not $dentroNossa) {
        $m = Motivo-Protegida $arqs $subs
        if ($m) {
            $prot = $d.FullName
            $protegidas.Add([pscustomobject]@{ Caminho = $d.FullName; Nome = $d.Name; Motivo = $m; Tamanho = [int64]0; Arquivos = 0 })
        }
    }

    foreach ($f in $arqs) {
        $cont++
        if ($cont % 1000 -eq 0) { Write-Progress -Activity 'Lendo arquivos' -Status "$cont arquivos" }
        $e = $f.Extension.ToLower()
        $c = 'Outros'; if ($cat.ContainsKey($e)) { $c = $cat[$e] }
        $data = $f.LastWriteTime
        $arquivos.Add([pscustomobject]@{
            Caminho      = $f.FullName
            Pasta        = Rel $f.DirectoryName
            Nome         = $f.Name
            Extensao     = $e
            TamanhoBytes = [int64]$f.Length
            Tamanho      = Fmt $f.Length
            Modificado   = $data.ToString('yyyy-MM-dd HH:mm')
            Ano          = $data.Year
            Categoria    = $c
            Lixo         = $(if ($prot) { '' } else { Motivo-Lixo $f })
            PastaProtegida = $(if ($prot) { Rel $prot } else { '' })
            JaOrganizado = $dentroNossa
            Zona         = $(if ($dentroNossa) { ($relD -split '[\\/]')[0] } else { '' })
            Duplicado    = ''
            GrupoDup     = 0
            Referencia   = ''
            Acao         = ''
            Destino      = ''
        })
    }
    foreach ($s in $subs) { $pilha.Push(@($s, $prot)) }
}
Write-Progress -Activity 'Lendo arquivos' -Completed
# totais das pastas protegidas
$porProt = @{}
foreach ($g in ($arquivos | Where-Object { $_.PastaProtegida } | Group-Object PastaProtegida)) { $porProt[$g.Name] = $g.Group }
foreach ($pp in $protegidas) {
    $lst = @($porProt[(Rel $pp.Caminho)] | Where-Object { $_ })
    $pp.Arquivos = $lst.Count
    $pp.Tamanho = [int64](($lst | Measure-Object TamanhoBytes -Sum).Sum)
}
Write-Host "Arquivos encontrados: $($arquivos.Count)" -ForegroundColor Green

# =====================================================================
# 2) DUPLICADOS (mesmo conteudo, conferido por MD5)
# =====================================================================

$candidatos = $arquivos | Where-Object { -not $_.Lixo -and -not $_.PastaProtegida -and $_.TamanhoBytes -gt 0 -and
                                         $_.Zona -ne '_LIXO_REVISAR' -and $_.Zona -ne '_DUPLICADOS' } |
              Group-Object TamanhoBytes | Where-Object { $_.Count -gt 1 }
$gruposDup = New-Object System.Collections.Generic.List[object]
$gid = 0
$totalCand = @($candidatos).Count; $i = 0
foreach ($g in $candidatos) {
    $i++; if ($i % 50 -eq 0) { Write-Progress -Activity 'Procurando duplicados' -Status "$i de $totalCand grupos" -PercentComplete ([int](100 * $i / $totalCand)) }
    $h1 = @{}
    foreach ($a in $g.Group) { try { $a | Add-Member -Force NoteProperty H1 (Get-Md5 $a.Caminho $true) } catch { $a | Add-Member -Force NoteProperty H1 '' } }
    foreach ($sub in ($g.Group | Where-Object { $_.H1 } | Group-Object H1 | Where-Object { $_.Count -gt 1 })) {
        foreach ($a in $sub.Group) {
            if ($a.TamanhoBytes -le 8MB) { $a | Add-Member -Force NoteProperty H2 $a.H1 }
            else { try { $a | Add-Member -Force NoteProperty H2 (Get-Md5 $a.Caminho $false) } catch { $a | Add-Member -Force NoteProperty H2 '' } }
        }
        foreach ($real in ($sub.Group | Where-Object { $_.H2 } | Group-Object H2 | Where-Object { $_.Count -gt 1 })) {
            # mantem o original: o que ja esta organizado, depois nome sem "copia/copy/(1)", depois o mais antigo, depois caminho mais curto
            $ord = @($real.Group | Sort-Object @{ Expression = { -not $_.JaOrganizado } },
                                               @{ Expression = { [IO.Path]::GetFileNameWithoutExtension($_.Nome) -match '(?i)(c.pia|copy|\(\d+\)\s*$)' } },
                                               Modificado, @{ Expression = { $_.Caminho.Length } })
            $manter = $ord[0]; $gid++
            foreach ($o in $ord) { $o.GrupoDup = $gid }
            for ($k = 1; $k -lt $ord.Count; $k++) { $ord[$k].Duplicado = 'Copia de: ' + (Rel $manter.Caminho) }
            $gruposDup.Add([pscustomobject]@{ Id = $gid; Manter = $manter; Itens = $ord; Copias = $ord.Count - 1
                                              Tamanho = $manter.TamanhoBytes; Recuperavel = $manter.TamanhoBytes * ($ord.Count - 1) })
        }
    }
}
Write-Progress -Activity 'Procurando duplicados' -Completed

# =====================================================================
# 3) PLANO (para onde cada coisa vai)
# =====================================================================
$usados = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
function Destino-Livre([string]$alvo) {
    $dirA = [IO.Path]::GetDirectoryName($alvo)
    $base = [IO.Path]::GetFileNameWithoutExtension($alvo); $ext = [IO.Path]::GetExtension($alvo)
    $n = 1; $t = $alvo
    while ($usados.Contains($t) -or (Test-Path -LiteralPath $t)) { $n++; $t = Join-Path $dirA ("$base ($n)$ext") }
    [void]$usados.Add($t); return $t
}

$movPastas = New-Object System.Collections.Generic.List[object]
foreach ($pp in $protegidas) {
    $alvo = Destino-Livre (Join-Path (Join-Path $dirOrg 'Programas_e_Projetos') (Limpar $pp.Nome))
    $pp | Add-Member -Force NoteProperty Destino $alvo
    $movPastas.Add($pp)
}
$mapaProt = @{}; foreach ($pp in $protegidas) { $mapaProt[(Rel $pp.Caminho)] = $pp.Destino }

foreach ($a in $arquivos) {
    if ($a.JaOrganizado) { $a.Acao = 'Manter (ja organizado)'; continue }
    if ($a.PastaProtegida) { $a.Acao = 'Mover junto com a pasta protegida'; $a.Destino = $mapaProt[$a.PastaProtegida]; continue }
    if ($a.Lixo) {
        $a.Acao = 'Lixo p/ revisar'
        $a.Destino = Destino-Livre (Join-Path (Join-Path $dirLixo (Limpar $a.Lixo)) (Rel $a.Caminho)); continue
    }
    if ($a.Duplicado) {
        $a.Acao = 'Duplicado p/ revisar'
        $a.Destino = Destino-Livre (Join-Path $dirDup (Rel $a.Caminho)); continue
    }
    $alvoDir = Join-Path (Join-Path $dirOrg $a.Categoria) ([string]$a.Ano)
    if ($a.Pasta -ne '') { $alvoDir = Join-Path $alvoDir (Limpar (Split-Path $a.Pasta -Leaf)) }
    $a.Acao = 'Organizar'
    $a.Destino = Destino-Livre (Join-Path $alvoDir $a.Nome)
}

# onde o original vai ficar (usado no Limpar para conferir antes de apagar a copia)
foreach ($g in $gruposDup) {
    $fim = $g.Manter.Caminho; if ($g.Manter.Acao -eq 'Organizar') { $fim = $g.Manter.Destino }
    for ($k = 1; $k -lt $g.Itens.Count; $k++) { $g.Itens[$k].Referencia = $fim }
}

# =====================================================================
# 4) RELATORIO
# =====================================================================
[void][IO.Directory]::CreateDirectory($dirRel)
$encCsv = $(if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' })
$csvInv = Join-Path $dirRel "inventario_$carimbo.csv"
$arquivos | Select-Object Caminho, Pasta, Nome, Extensao, TamanhoBytes, Tamanho, Modificado, Ano, Categoria, Lixo,
                          PastaProtegida, Duplicado, Acao, Destino |
    Export-Csv -LiteralPath $csvInv -Delimiter ';' -NoTypeInformation -Encoding $encCsv

# planilha de duplicados: cada grupo com o que FICA e as COPIAS, com nome, tamanho, data e local
$csvDup = Join-Path $dirRel "duplicados_$carimbo.csv"
$linhasDup = foreach ($g in ($gruposDup | Sort-Object Recuperavel -Descending)) {
    foreach ($o in $g.Itens) {
        [pscustomobject]@{ Grupo = $g.Id; Situacao = $(if ($o -eq $g.Manter) { 'FICA' } else { 'COPIA' }); Nome = $o.Nome
                           Tamanho = $o.Tamanho; TamanhoBytes = $o.TamanhoBytes; Modificado = $o.Modificado
                           OndeEsta = Rel $o.Caminho; VaiPara = $(if ($o.Destino) { Rel $o.Destino } else { Rel $o.Caminho }) }
    }
}
@($linhasDup) | Export-Csv -LiteralPath $csvDup -Delimiter ';' -NoTypeInformation -Encoding $encCsv

# mesmo nome com tamanho diferente (provaveis versoes diferentes - so aviso, nao sao movidos como copia)
$versoes = @($arquivos | Where-Object { -not $_.Lixo -and -not $_.PastaProtegida -and $_.Zona -ne '_LIXO_REVISAR' -and $_.Zona -ne '_DUPLICADOS' } |
             Group-Object { $_.Nome.ToLower() } | Where-Object { @($_.Group | Select-Object -ExpandProperty TamanhoBytes -Unique).Count -gt 1 } |
             Sort-Object Count -Descending)
$csvVer = Join-Path $dirRel "mesmo_nome_tamanho_diferente_$carimbo.csv"
@(foreach ($v in $versoes) { foreach ($o in ($v.Group | Sort-Object TamanhoBytes -Descending)) {
    [pscustomobject]@{ Nome = $o.Nome; Tamanho = $o.Tamanho; TamanhoBytes = $o.TamanhoBytes; Modificado = $o.Modificado; OndeEsta = Rel $o.Caminho }
} }) | Export-Csv -LiteralPath $csvVer -Delimiter ';' -NoTypeInformation -Encoding $encCsv

$total = [int64](($arquivos | Measure-Object TamanhoBytes -Sum).Sum)
$lixos = @($arquivos | Where-Object { $_.Lixo })
$dups  = @($arquivos | Where-Object { $_.Duplicado })
$tLixo = [int64](($lixos | Measure-Object TamanhoBytes -Sum).Sum)
$tDup  = [int64](($dups | Measure-Object TamanhoBytes -Sum).Sum)

$sb = New-Object System.Text.StringBuilder
function L([string]$s) { [void]$sb.AppendLine($s) }
L '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
L '<title>Relatorio do HD</title><style>body{font-family:Segoe UI,Arial,sans-serif;margin:16px;color:#222;background:#fafafa;max-width:1100px}'
L 'h1{font-size:22px}h2{font-size:18px;margin-top:28px;border-bottom:2px solid #ddd;padding-bottom:4px}'
L '.cards{display:flex;flex-wrap:wrap;gap:10px}.card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:10px 14px;min-width:150px}'
L '.card b{display:block;font-size:20px}table{border-collapse:collapse;width:100%;background:#fff;font-size:13px}'
L 'td,th{border:1px solid #ddd;padding:5px 7px;text-align:left;vertical-align:top;word-break:break-all}th{background:#f0f0f0}'
L '.n{text-align:right;white-space:nowrap;word-break:normal}.aviso{background:#fff7d6;border:1px solid #e6c200;padding:10px;border-radius:6px}</style></head><body>'
L "<h1>Relat&oacute;rio do HD $(Html $raiz)</h1><p>Gerado em $(Get-Date -Format 'dd/MM/yyyy HH:mm') &middot; Modo: $Modo</p>"
L '<div class="cards">'
L "<div class='card'>Arquivos<b>$('{0:N0}' -f $arquivos.Count)</b></div>"
L "<div class='card'>Espa&ccedil;o usado<b>$(Fmt $total)</b></div>"
L "<div class='card'>Lixo prov&aacute;vel<b>$(Fmt $tLixo)</b>$('{0:N0}' -f $lixos.Count) arquivos</div>"
L "<div class='card'>Duplicados<b>$(Fmt $tDup)</b>$('{0:N0}' -f $dups.Count) c&oacute;pias</div>"
L "<div class='card'>Pastas protegidas<b>$($protegidas.Count)</b></div>"
L "<div class='card'>Sem acesso<b>$($erros.Count)</b></div></div>"

L '<h2>Por categoria</h2><table><tr><th>Categoria</th><th class="n">Arquivos</th><th class="n">Tamanho</th></tr>'
foreach ($g in ($arquivos | Group-Object Categoria | Sort-Object { ($_.Group | Measure-Object TamanhoBytes -Sum).Sum } -Descending)) {
    $s = ($g.Group | Measure-Object TamanhoBytes -Sum).Sum
    L "<tr><td>$(Html $g.Name)</td><td class='n'>$('{0:N0}' -f $g.Count)</td><td class='n'>$(Fmt $s)</td></tr>"
}
L '</table>'

L '<h2>Lixo prov&aacute;vel (vai para _LIXO_REVISAR, n&atilde;o &eacute; apagado)</h2><table><tr><th>Motivo</th><th class="n">Arquivos</th><th class="n">Tamanho</th></tr>'
foreach ($g in ($lixos | Group-Object Lixo | Sort-Object Count -Descending)) {
    L "<tr><td>$(Html $g.Name)</td><td class='n'>$('{0:N0}' -f $g.Count)</td><td class='n'>$(Fmt (($g.Group | Measure-Object TamanhoBytes -Sum).Sum))</td></tr>"
}
L '</table>'

L "<h2>Duplicados &mdash; $($gruposDup.Count) grupos (conte&uacute;do id&ecirc;ntico: mesmo tamanho e mesma impress&atilde;o digital MD5)</h2>"
L "<p>Lista completa na planilha <b>$(Html (Split-Path $csvDup -Leaf))</b>. Abaixo, os 300 que mais ocupam espa&ccedil;o.</p>"
L '<table><tr><th>Nome</th><th class="n">Tamanho</th><th>Data</th><th>FICA em</th><th>C&Oacute;PIAS em</th><th class="n">Libera</th></tr>'
foreach ($g in ($gruposDup | Sort-Object Recuperavel -Descending | Select-Object -First 300)) {
    $cop = (@($g.Itens | Where-Object { $_ -ne $g.Manter }) | ForEach-Object { Html ((Rel $_.Caminho) + $(if ($_.Nome -ne $g.Manter.Nome) { '  (nome diferente)' } else { '' })) }) -join '<br>'
    L "<tr><td>$(Html $g.Manter.Nome)</td><td class='n'>$($g.Manter.Tamanho)</td><td>$($g.Manter.Modificado)</td><td>$(Html (Rel $g.Manter.Caminho))</td><td>$cop</td><td class='n'>$(Fmt $g.Recuperavel)</td></tr>"
}
L '</table>'

L "<h2>Mesmo nome, tamanho diferente &mdash; $($versoes.Count) nomes (prov&aacute;veis vers&otilde;es diferentes: N&Atilde;O s&atilde;o tratados como c&oacute;pia)</h2>"
L "<p>Lista completa: <b>$(Html (Split-Path $csvVer -Leaf))</b>. Abaixo, at&eacute; 150.</p>"
L '<table><tr><th>Nome</th><th>Tamanhos e locais</th></tr>'
foreach ($v in ($versoes | Select-Object -First 150)) {
    $loc = (@($v.Group | Sort-Object TamanhoBytes -Descending) | ForEach-Object { Html ("$($_.Tamanho) | $($_.Modificado) | $(Rel $_.Caminho)") }) -join '<br>'
    L "<tr><td>$(Html $v.Group[0].Nome)</td><td>$loc</td></tr>"
}
L '</table>'

L '<h2>Pastas protegidas (programas/projetos &mdash; movidas inteiras, sem desmontar)</h2><table><tr><th>Pasta</th><th>Motivo</th><th class="n">Arquivos</th><th class="n">Tamanho</th></tr>'
foreach ($pp in ($protegidas | Sort-Object Tamanho -Descending)) {
    L "<tr><td>$(Html (Rel $pp.Caminho))</td><td>$(Html $pp.Motivo)</td><td class='n'>$($pp.Arquivos)</td><td class='n'>$(Fmt $pp.Tamanho)</td></tr>"
}
L '</table>'

L '<h2>50 maiores arquivos</h2><table><tr><th>Arquivo</th><th>Categoria</th><th class="n">Tamanho</th></tr>'
foreach ($a in ($arquivos | Sort-Object TamanhoBytes -Descending | Select-Object -First 50)) {
    L "<tr><td>$(Html (Rel $a.Caminho))</td><td>$(Html $a.Categoria)</td><td class='n'>$($a.Tamanho)</td></tr>"
}
L '</table>'

L '<h2>Extens&otilde;es n&atilde;o reconhecidas (categoria Outros)</h2><table><tr><th>Extens&atilde;o</th><th class="n">Arquivos</th><th class="n">Tamanho</th></tr>'
foreach ($g in ($arquivos | Where-Object { $_.Categoria -eq 'Outros' } | Group-Object Extensao | Sort-Object Count -Descending | Select-Object -First 40)) {
    $nm = $g.Name; if (-not $nm) { $nm = '(sem extensao)' }
    L "<tr><td>$(Html $nm)</td><td class='n'>$($g.Count)</td><td class='n'>$(Fmt (($g.Group | Measure-Object TamanhoBytes -Sum).Sum))</td></tr>"
}
L '</table>'

if ($erros.Count) {
    L '<h2>Pastas sem acesso (n&atilde;o lidas)</h2><table><tr><th>Pasta</th><th>Erro</th></tr>'
    foreach ($e in ($erros | Select-Object -First 200)) { L "<tr><td>$(Html $e.Caminho)</td><td>$(Html $e.Erro)</td></tr>" }
    L '</table>'
}
L '<h2>Como vai ficar</h2><div class="aviso"><ul>'
L '<li><b>_ORGANIZADO\Categoria\Ano\NomeDaPastaOriginal</b> &mdash; arquivos bons, separados por tipo e ano, mantendo o nome da pasta de origem.</li>'
L '<li><b>_ORGANIZADO\Programas_e_Projetos</b> &mdash; pastas de programas/projetos movidas inteiras.</li>'
L '<li><b>_LIXO_REVISAR</b> e <b>_DUPLICADOS</b> &mdash; etapa seguinte: op&ccedil;&atilde;o <b>4 - LIMPAR</b> apaga de vez, conferindo antes que o original existe e &eacute; id&ecirc;ntico.</li>'
L "<li>Planilha completa (abre no Excel): <b>$(Html (Split-Path $csvInv -Leaf))</b> &mdash; colunas A&ccedil;&atilde;o e Destino mostram o plano de cada arquivo.</li>"
L '</ul></div></body></html>'
$htmlRel = Join-Path $dirRel "relatorio_$carimbo.html"
[IO.File]::WriteAllText($htmlRel, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))

Write-Host ''
Write-Host "Total: $(Fmt $total) em $($arquivos.Count) arquivos" -ForegroundColor Green
Write-Host "Lixo provavel: $(Fmt $tLixo) | Duplicados: $(Fmt $tDup) | Pastas protegidas: $($protegidas.Count)"
Write-Host "Relatorio: $htmlRel" -ForegroundColor Cyan
Write-Host "Planilha : $csvInv" -ForegroundColor Cyan
Write-Host "Duplicados (planilha): $csvDup" -ForegroundColor Cyan

if ($Modo -eq 'Inventario') {
    try { Invoke-Item -LiteralPath $htmlRel } catch { }
    exit
}

# =====================================================================
# 5) ORGANIZAR (move; nada e apagado)
# =====================================================================
$aMover = @($arquivos | Where-Object { $_.Acao -in @('Organizar', 'Lixo p/ revisar', 'Duplicado p/ revisar') })
Write-Host ''
Write-Host "Serao movidos $($aMover.Count) arquivos e $($movPastas.Count) pastas protegidas (inteiras)." -ForegroundColor Yellow
if (-not $SemConfirmacao) {
    if ((Read-Host 'Digite SIM para organizar agora') -ne 'SIM') { Write-Host 'Cancelado. Nada foi movido.'; exit }
}

$log = Join-Path $dirRel "registro_movimentos_$carimbo.csv"
$enc = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($log, "Tipo;Status;Origem;Destino;Erro;Referencia`r`n", $enc)
function Registrar($tipo, $status, $origem, $destino, $erro, $referencia) {
    $campos = @($tipo, $status, $origem, $destino, $erro, $referencia) | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }
    [IO.File]::AppendAllText($log, ($campos -join ';') + "`r`n", $enc)
}
function Mover($tipo, $origem, $destino, $referencia) {
    try {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destino))
        if ($tipo -eq 'Pasta') { [IO.Directory]::Move($origem, $destino) } else { [IO.File]::Move($origem, $destino) }
        Registrar $tipo 'OK' $origem $destino '' $referencia
        return $true
    } catch { Registrar $tipo 'FALHA' $origem $destino $_.Exception.Message $referencia; return $false }
}

$ok = 0; $falha = 0; $i = 0
foreach ($pp in $movPastas) { if (Mover 'Pasta' $pp.Caminho $pp.Destino '') { $ok++ } else { $falha++ } }
foreach ($a in $aMover) {
    $i++; if ($i % 200 -eq 0) { Write-Progress -Activity 'Organizando' -Status "$i de $($aMover.Count)" -PercentComplete ([int](100 * $i / $aMover.Count)) }
    if (Mover 'Arquivo' $a.Caminho $a.Destino $a.Referencia) { $ok++ } else { $falha++ }
}
Write-Progress -Activity 'Organizando' -Completed

# remove pastas que ficaram vazias (registrado para poder recriar no Desfazer)
$vazias = 0
Get-ChildItem -LiteralPath $raiz -Recurse -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $r = Rel $_.FullName; $top = ($r -split '[\\/]')[0]
        -not ($pastasNossas -contains $top) -and -not ($ignorar -contains $top) -and
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } |
    Sort-Object { $_.FullName.Length } -Descending |
    ForEach-Object {
        try {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) {
                Remove-Item -LiteralPath $_.FullName
                Registrar 'PastaVaziaRemovida' 'OK' $_.FullName '' '' ''; $vazias++
            }
        } catch { }
    }

Write-Host ''
Write-Host "Movidos: $ok | Falhas: $falha | Pastas vazias removidas: $vazias" -ForegroundColor Green
Write-Host "Registro (para desfazer): $log" -ForegroundColor Cyan
if ($falha) { Write-Host 'Veja a coluna Erro no registro para os itens que falharam.' -ForegroundColor Yellow }
