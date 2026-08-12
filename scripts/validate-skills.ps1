#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $SourceRoot = 'skills',
    [string] $OutputRoot = 'dist',
    [int] $SkillMdWarnBytes = 20480
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot $SourceRoot
$outputDir = Join-Path $repoRoot $OutputRoot
$readme = Join-Path $repoRoot 'README.md'

$script:errors = [System.Collections.Generic.List[string]]::new()
$script:warnings = [System.Collections.Generic.List[string]]::new()

function Add-Failure { param([string] $Message) $script:errors.Add($Message) }
function Add-Warning { param([string] $Message) $script:warnings.Add($Message) }

$invocationClause = 'Load only when the user explicitly invokes this skill by name'
$nonSkillTokens = @('decimatio-salesforce', 'decimatio-skill-authoring')

function Get-Frontmatter {
    param([Parameter(Mandatory)] [string] $Path)

    $text = Get-Content -LiteralPath $Path -Raw
    if ($text -notmatch '(?s)\A---\r?\n(.*?)\r?\n---\r?\n') {
        return $null
    }
    $block = $Matches[1]

    $name = if ($block -match '(?m)^name:\s*(\S+)\s*$') { $Matches[1] } else { $null }
    $description = if ($block -match '(?ms)^description:\s*(.+?)(?=\r?\n[A-Za-z_-]+:\s|\z)') {
        ($Matches[1] -replace '\s+', ' ').Trim()
    }
    else { $null }

    [pscustomobject]@{ Name = $name; Description = $description }
}

function Get-StreamHash {
    param([Parameter(Mandatory)] [System.IO.Stream] $Stream)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        [System.BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

if (-not (Test-Path -LiteralPath $sourceDir)) {
    Write-Host "FAIL  source root not found: $sourceDir" -ForegroundColor Red
    exit 1
}

$skills = Get-ChildItem -LiteralPath $sourceDir -Directory |
    Select-Object -ExpandProperty Name | Sort-Object

if (-not $skills) {
    Write-Host "FAIL  no skill folders under $sourceDir" -ForegroundColor Red
    exit 1
}

$readmeText = if (Test-Path -LiteralPath $readme) { Get-Content -LiteralPath $readme -Raw } else { '' }
if (-not $readmeText) { Add-Failure 'README.md is missing or empty' }

foreach ($name in $skills) {
    $src = Join-Path $sourceDir $name
    $skillMd = Join-Path $src 'SKILL.md'

    if (-not (Test-Path -LiteralPath $skillMd)) {
        Add-Failure "$name : no SKILL.md"
        continue
    }

    $fm = Get-Frontmatter -Path $skillMd
    if ($null -eq $fm) {
        Add-Failure "$name : SKILL.md has no YAML frontmatter block"
    }
    else {
        if (-not $fm.Name) {
            Add-Failure "$name : frontmatter has no 'name' key"
        }
        elseif ($fm.Name -ne $name) {
            Add-Failure "$name : frontmatter name '$($fm.Name)' does not match folder"
        }

        if (-not $fm.Description) {
            Add-Failure "$name : frontmatter has no 'description' key"
        }
        elseif ($fm.Description -notlike "*$invocationClause*") {
            Add-Failure "$name : description is missing the explicit-invocation clause"
        }
    }

    $skillMdBytes = (Get-Item -LiteralPath $skillMd).Length
    if ($skillMdBytes -gt $SkillMdWarnBytes) {
        Add-Warning ("{0} : SKILL.md is {1:N0} bytes (over {2:N0}) - consider moving detail to references/" -f
            $name, $skillMdBytes, $SkillMdWarnBytes)
    }

    if ($readmeText -and $readmeText -notmatch [regex]::Escape($name)) {
        Add-Failure "$name : not listed in README.md"
    }

    $bundle = Join-Path $outputDir "$name.skill"
    if (-not (Test-Path -LiteralPath $bundle)) {
        Add-Failure "$name : no bundle at $OutputRoot/$name.skill"
        continue
    }

    $sourceFiles = @{}
    $prefixLength = $src.Length + 1
    foreach ($file in Get-ChildItem -LiteralPath $src -Recurse -File) {
        $rel = $file.FullName.Substring($prefixLength) -replace '\\', '/'
        $sourceFiles["$name/$rel"] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($bundle)
    try {
        $seen = @{}
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }

            if ($entry.FullName.Contains('\')) {
                Add-Failure "$name : bundle entry uses backslashes: $($entry.FullName)"
                continue
            }
            if (-not $entry.FullName.StartsWith("$name/")) {
                Add-Failure "$name : bundle entry not rooted at '$name/': $($entry.FullName)"
                continue
            }

            $stream = $entry.Open()
            try { $seen[$entry.FullName] = Get-StreamHash -Stream $stream }
            finally { $stream.Dispose() }
        }

        foreach ($key in $sourceFiles.Keys) {
            if (-not $seen.ContainsKey($key)) {
                Add-Failure "$name : bundle is stale, missing $key - rebuild it"
            }
            elseif ($seen[$key] -ne $sourceFiles[$key]) {
                Add-Failure "$name : bundle is stale, content differs for $key - rebuild it"
            }
        }
        foreach ($key in $seen.Keys) {
            if (-not $sourceFiles.ContainsKey($key)) {
                Add-Failure "$name : bundle carries a file no longer in source: $key - rebuild it"
            }
        }
    }
    finally { $zip.Dispose() }
}

if ($readmeText) {
    $mentioned = [regex]::Matches($readmeText, 'decimatio-[a-z0-9-]+') |
        ForEach-Object { $_.Value } | Sort-Object -Unique
    foreach ($token in $mentioned) {
        if ($token -in $skills) { continue }
        if ($token -in $nonSkillTokens) { continue }
        if ($token -like '*.skill') { continue }
        Add-Warning "README.md references '$token', which is not a skill folder"
    }
}

foreach ($w in $script:warnings) { Write-Host "WARN  $w" -ForegroundColor Yellow }
foreach ($e in $script:errors) { Write-Host "FAIL  $e" -ForegroundColor Red }

$summary = "{0} skill(s) checked - {1} error(s), {2} warning(s)" -f
    $skills.Count, $script:errors.Count, $script:warnings.Count

if ($script:errors.Count -gt 0) {
    Write-Host $summary -ForegroundColor Red
    exit 1
}

Write-Host "OK    $summary" -ForegroundColor Green
exit 0
