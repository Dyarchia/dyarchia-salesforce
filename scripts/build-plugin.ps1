#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $SourceRoot = 'skills',

    [string] $OutputRoot = 'dist',

    [string] $Name = 'dyarchia-salesforce'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipEpoch = [System.DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot $SourceRoot
$outputDir = Join-Path $repoRoot $OutputRoot

if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Source root not found: $sourceDir"
}
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$manifest = Join-Path $repoRoot '.claude-plugin/plugin.json'
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Host manifest not found: $manifest"
}

$included = @(
    '.claude-plugin',
    '.codex-plugin',
    $SourceRoot,
    'commands',
    'agents',
    'hooks'
)
$includedFiles = @('README.md', 'LICENSE')

$staged = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($dir in $included) {
    $full = Join-Path $repoRoot $dir
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $prefixLength = $repoRoot.Length + 1
    foreach ($file in Get-ChildItem -LiteralPath $full -Recurse -File) {
        $relative = $file.FullName.Substring($prefixLength) -replace '\\', '/'
        $item = [pscustomobject]@{ Path = $file.FullName; Entry = $relative }
        $staged.Add($item)
    }
}

foreach ($leaf in $includedFiles) {
    $full = Join-Path $repoRoot $leaf
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $item = [pscustomobject]@{ Path = $full; Entry = $leaf }
        $staged.Add($item)
    }
}

$entries = $staged | Sort-Object Entry

$dest = Join-Path $outputDir "$Name.plugin"
if (Test-Path -LiteralPath $dest) {
    Remove-Item -LiteralPath $dest -Force
}

$zip = [System.IO.Compression.ZipFile]::Open(
    $dest, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($item in $entries) {
        $entry = $zip.CreateEntry(
            $item.Entry, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $zipEpoch
        $out = $entry.Open()
        try {
            $in = [System.IO.File]::OpenRead($item.Path)
            try { $in.CopyTo($out) } finally { $in.Dispose() }
        }
        finally { $out.Dispose() }
    }
}
finally { $zip.Dispose() }

$size = (Get-Item -LiteralPath $dest).Length
Write-Host ("Built {0}.plugin - {1} file(s), {2:N0} bytes" -f $Name, $entries.Count, $size) -ForegroundColor Green
Write-Host "  $dest"
