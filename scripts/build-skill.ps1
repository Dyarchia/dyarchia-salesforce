#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Skill,

    [string] $SourceRoot = 'skills',

    [string] $OutputRoot = 'dist'
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

function Build-SkillBundle {
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    $src = Join-Path $sourceDir $Name
    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        throw "Skill folder not found: $src"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $src 'SKILL.md'))) {
        throw "Skill folder has no SKILL.md: $src"
    }

    $dest = Join-Path $outputDir "$Name.skill"
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Force
    }

    $prefixLength = $src.Length + 1
    $files = Get-ChildItem -LiteralPath $src -Recurse -File | Sort-Object FullName

    $zip = [System.IO.Compression.ZipFile]::Open(
        $dest, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $inner = $file.FullName.Substring($prefixLength) -replace '\\', '/'
            $entry = $zip.CreateEntry(
                "$Name/$inner", [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $zipEpoch
            $out = $entry.Open()
            try {
                $in = [System.IO.File]::OpenRead($file.FullName)
                try { $in.CopyTo($out) } finally { $in.Dispose() }
            }
            finally { $out.Dispose() }
        }
    }
    finally { $zip.Dispose() }

    [pscustomobject]@{
        Skill = $Name
        Files = $files.Count
        Bytes = (Get-Item -LiteralPath $dest).Length
    }
}

$targets = if ($Skill) {
    $Skill
}
else {
    Get-ChildItem -LiteralPath $sourceDir -Directory | Select-Object -ExpandProperty Name | Sort-Object
}

$results = foreach ($name in $targets) { Build-SkillBundle -Name $name }

$results | Format-Table -AutoSize
Write-Host "Built $($results.Count) bundle(s) into $outputDir" -ForegroundColor Green
