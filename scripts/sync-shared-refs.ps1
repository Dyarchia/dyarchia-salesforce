#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Skill,

    [string] $SourceRoot = 'skills',

    [string] $SharedRoot = 'references-shared'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot $SourceRoot
$sharedDir = Join-Path $repoRoot $SharedRoot

if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Source root not found: $sourceDir"
}
if (-not (Test-Path -LiteralPath $sharedDir)) {
    throw "Shared root not found: $sharedDir"
}

function Read-SharedManifest {
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object { if ($_.EndsWith('.md')) { $_ } else { "$_.md" } } |
        Sort-Object -Unique
}

function Sync-SkillSharedRefs {
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    $src = Join-Path $sourceDir $Name
    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        throw "Skill folder not found: $src"
    }

    $manifest = @(Read-SharedManifest -Path (Join-Path $src 'shared-refs.txt'))
    $target = Join-Path $src 'references/shared'

    if ($manifest.Count -eq 0) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        return [pscustomobject]@{ Skill = $Name; Fragments = 0; Pruned = 0 }
    }

    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
    }

    foreach ($fragment in $manifest) {
        $canon = Join-Path $sharedDir $fragment
        if (-not (Test-Path -LiteralPath $canon -PathType Leaf)) {
            throw "$Name : shared-refs.txt declares '$fragment', which is not in $SharedRoot"
        }
        Copy-Item -LiteralPath $canon -Destination (Join-Path $target $fragment) -Force
    }

    $stale = Get-ChildItem -LiteralPath $target -File |
        Where-Object { $manifest -notcontains $_.Name }
    foreach ($file in $stale) {
        Remove-Item -LiteralPath $file.FullName -Force
    }

    [pscustomobject]@{
        Skill     = $Name
        Fragments = $manifest.Count
        Pruned    = @($stale).Count
    }
}

$targets = if ($Skill) {
    $Skill
}
else {
    Get-ChildItem -LiteralPath $sourceDir -Directory | Select-Object -ExpandProperty Name | Sort-Object
}

$results = foreach ($name in $targets) { Sync-SkillSharedRefs -Name $name }

$results | Where-Object { $_.Fragments -gt 0 -or $_.Pruned -gt 0 } | Format-Table -AutoSize

$total = ($results | Measure-Object -Property Fragments -Sum).Sum
Write-Host "Synced $total shared fragment(s) across $($results.Count) skill(s)" -ForegroundColor Green
