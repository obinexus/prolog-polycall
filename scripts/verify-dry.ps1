$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$adapterPath = Join-Path $root 'src/prolog_polycall.c'
$foreignPath = Join-Path $root 'src/prolog_polycall_foreign.c'
$prologPath = Join-Path $root 'src/prolog_polycall.pl'
$forbidden = 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\('
$matches = Select-String -Path $adapterPath,$foreignPath,$prologPath -Pattern $forbidden

if ($matches) {
    $matches | ForEach-Object { Write-Error $_.Line }
    throw 'prolog-polycall must not parse configuration or implement runtime logic'
}

$adapter = Get-Content -Raw $adapterPath
$foreign = Get-Content -Raw $foreignPath
$prolog = Get-Content -Raw $prologPath
if (-not $adapter.Contains('polycall_ffi_run_config(config_path, 1)')) {
    throw 'prolog-polycall does not forward through polycall_ffi_run_config'
}
if (-not $foreign.Contains('REP_UTF8')) {
    throw 'prolog-polycall does not marshal Prolog text as UTF-8'
}
if (-not $prolog.Contains('polycall_error(Status)')) {
    throw 'prolog-polycall does not expose structured Prolog errors'
}

Write-Output 'prolog-polycall thin-adapter check: PASS'
