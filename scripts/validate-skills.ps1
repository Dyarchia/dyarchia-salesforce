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
# README names that are deliberately dya-prefixed without a folder under skills/.
$nonSkillTokens = @('dya-sf-skills')

# Skills whose domain has no Salesforce core API version: B2C Commerce is Demandware
# lineage, the CLI versions on its own cadence. They are exempt from the platform check.
$versionNeutralSkills = @('dya-b2c-commerce', 'dya-sf-cli')

$sharedDir = Join-Path $repoRoot 'references-shared'
$pluginManifest = Join-Path $repoRoot '.claude-plugin/plugin.json'
$marketplaceManifest = Join-Path $repoRoot '.claude-plugin/marketplace.json'
$codexManifest = Join-Path $repoRoot '.codex-plugin/plugin.json'

function Get-SharedManifest {
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    @(Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object { if ($_.EndsWith('.md')) { $_ } else { "$_.md" } } |
        Sort-Object -Unique)
}

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

# README is the single source of truth for the platform version. Everything else - every
# Platform Context heading, the badge, the plugin description - is checked against it, so a
# version bump cannot land half-applied.
$platformVersion = $null
if ($readmeText -match '(?m)^\d+ skills, all targeting \*\*(.+?)\*\*') {
    $platformVersion = $Matches[1]
}
else {
    Add-Failure "README.md has no 'N skills, all targeting **<version>**' line to read the platform version from"
}

if ($platformVersion) {
    if ($readmeText -match 'Salesforce%20API-(v[0-9.]+)-') {
        $badgeVersion = $Matches[1]
        if ($platformVersion -notlike "*$badgeVersion*") {
            Add-Failure "README.md badge says '$badgeVersion' but the catalogue line says '$platformVersion'"
        }
    }
    else {
        Add-Failure 'README.md has no Salesforce API version badge'
    }
}

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

    $skillMdText = Get-Content -LiteralPath $skillMd -Raw

    if ($platformVersion -and $name -notin $versionNeutralSkills) {
        $heading = "## Platform Context — $platformVersion"
        if ($skillMdText -notlike "*$heading*") {
            Add-Failure "$name : Platform Context does not declare '$platformVersion'"
        }
    }

    $refsDir = Join-Path $src 'references'
    if (Test-Path -LiteralPath $refsDir) {
        foreach ($ref in Get-ChildItem -LiteralPath $refsDir -Recurse -File) {
            if ($skillMdText -notlike "*$($ref.Name)*") {
                Add-Failure "$name : references/$($ref.Name) is never cited from SKILL.md"
            }
        }
    }
    elseif ($skillMdBytes -gt $SkillMdWarnBytes) {
        Add-Warning "$name : SKILL.md is over the ceiling and has no references/ to move detail into"
    }

    $declared = Get-SharedManifest -Path (Join-Path $src 'shared-refs.txt')
    $sharedTarget = Join-Path $refsDir 'shared'
    foreach ($fragment in $declared) {
        $canon = Join-Path $sharedDir $fragment
        $copy = Join-Path $sharedTarget $fragment
        if (-not (Test-Path -LiteralPath $canon)) {
            Add-Failure "$name : shared-refs.txt declares '$fragment', which is not in references-shared/"
        }
        elseif (-not (Test-Path -LiteralPath $copy)) {
            Add-Failure "$name : shared fragment '$fragment' is declared but not synced - run scripts/sync-shared-refs"
        }
        elseif ((Get-FileHash -Algorithm SHA256 -LiteralPath $copy).Hash -ne
                (Get-FileHash -Algorithm SHA256 -LiteralPath $canon).Hash) {
            Add-Failure "$name : shared fragment '$fragment' differs from its canon - never edit a copy, edit references-shared/ and re-sync"
        }
    }
    if (Test-Path -LiteralPath $sharedTarget) {
        foreach ($stray in Get-ChildItem -LiteralPath $sharedTarget -File) {
            if ($declared -notcontains $stray.Name) {
                Add-Failure "$name : references/shared/$($stray.Name) is not declared in shared-refs.txt - run scripts/sync-shared-refs"
            }
        }
    }

    if ($readmeText -and $readmeText -notmatch ('(?m)^- \*\*`{0}`\*\*\s*$' -f [regex]::Escape($name))) {
        Add-Failure "$name : not listed in the README.md catalogue"
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

# Every manifest repeats the platform version and the skill count in its description. Both have to
# land in all of them or fail -- the plugin description is where the count silently went stale once.
function Test-ManifestDescription {
    param([string]$Label, [string]$Description)
    if ($platformVersion -and $Description -notlike "*$platformVersion*") {
        Add-Failure "$Label description does not state '$platformVersion'"
    }
    if ($Description -match '(?i)(\d+)\s+(?:domain\s+)?(?:skills?|playbooks?)') {
        if ([int]$Matches[1] -ne $skills.Count) {
            Add-Failure ("$Label description says {0} skills, but skills/ holds {1}" -f
                $Matches[1], $skills.Count)
        }
    }
    else {
        Add-Warning "$Label description states no skill count - nothing to check it against"
    }
}

$pluginVersion = $null
if (Test-Path -LiteralPath $pluginManifest) {
    $plugin = Get-Content -LiteralPath $pluginManifest -Raw | ConvertFrom-Json
    $pluginVersion = $plugin.version
    Test-ManifestDescription '.claude-plugin/plugin.json' $plugin.description
}
else { Add-Failure '.claude-plugin/plugin.json not found' }

# The Codex manifest serves the same skills/ tree to a different host. It duplicates the name,
# version and description, so all three are checked against the Claude manifest rather than trusted.
if (Test-Path -LiteralPath $codexManifest) {
    $codex = Get-Content -LiteralPath $codexManifest -Raw | ConvertFrom-Json
    Test-ManifestDescription '.codex-plugin/plugin.json' $codex.description
    if ($pluginVersion -and $codex.version -ne $pluginVersion) {
        Add-Failure ("plugin.json version '{0}' and .codex-plugin/plugin.json version '{1}' disagree" -f
            $pluginVersion, $codex.version)
    }
    if ($plugin -and $codex.name -ne $plugin.name) {
        Add-Failure ("plugin.json name '{0}' and .codex-plugin/plugin.json name '{1}' disagree" -f
            $plugin.name, $codex.name)
    }
    if ($codex.skills -ne "./$SourceRoot/") {
        Add-Failure ".codex-plugin/plugin.json points skills at '$($codex.skills)', expected './$SourceRoot/'"
    }
}
else { Add-Failure '.codex-plugin/plugin.json not found' }

if (Test-Path -LiteralPath $marketplaceManifest) {
    $marketplace = Get-Content -LiteralPath $marketplaceManifest -Raw | ConvertFrom-Json
    $entry = $marketplace.plugins | Where-Object { $_.name -eq 'dyarchia-salesforce' }
    if (-not $entry) {
        Add-Failure ".claude-plugin/marketplace.json has no 'dyarchia-salesforce' plugin entry"
    }
    elseif ($pluginVersion -and $entry.version -ne $pluginVersion) {
        Add-Failure ("plugin.json version '{0}' and marketplace.json version '{1}' disagree" -f
            $pluginVersion, $entry.version)
    }
}
else { Add-Failure '.claude-plugin/marketplace.json not found' }

# The README asserts the skill count in four places. Each is checked against the folder count, and
# an assertion that has been reworded away is a warning rather than a silent gap.
if ($readmeText) {
    $countAssertions = @(
        @{ Pattern = '(?m)^(\d+) skills, all targeting'; Label = 'catalogue line' }
        @{ Pattern = 'skills/<br/>(\d+) skill folders';  Label = 'layout diagram, skills/' }
        @{ Pattern = 'dist/<br/>(\d+) \.skill bundles';  Label = 'layout diagram, dist/' }
        @{ Pattern = 'all (\d+) skills install in one step'; Label = 'install line' }
    )
    foreach ($assertion in $countAssertions) {
        if ($readmeText -match $assertion.Pattern) {
            if ([int]$Matches[1] -ne $skills.Count) {
                Add-Failure ("README.md {0} says {1} skills, but skills/ holds {2}" -f
                    $assertion.Label, $Matches[1], $skills.Count)
            }
        }
        else {
            Add-Warning ("README.md {0} no longer states a skill count" -f $assertion.Label)
        }
    }
}

if ($readmeText) {
    $mentioned = [regex]::Matches($readmeText, 'dya-[a-z0-9-]+') |
        ForEach-Object { $_.Value } | Sort-Object -Unique
    foreach ($token in $mentioned) {
        if ($token -in $skills) { continue }
        if ($token -in $nonSkillTokens) { continue }
        if ($token -like '*.skill') { continue }
        Add-Warning "README.md references '$token', which is not a skill folder"
    }
}

# Cross-reference graph: a backticked `dya-<name>` inside a skill is a routing handoff.
# A rename that leaves one dangling breaks the graph silently, so this is an error.
foreach ($name in $skills) {
    $skillDir = Join-Path $sourceDir $name
    $docs = Get-ChildItem -Path $skillDir -Filter '*.md' -Recurse -File |
        Where-Object { $_.FullName -notmatch '[\\/]references[\\/]shared[\\/]' }
    foreach ($doc in $docs) {
        $text = Get-Content -LiteralPath $doc.FullName -Raw
        if (-not $text) { continue }
        $cited = [regex]::Matches($text, '`(dya-[a-z0-9-]+)`') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        foreach ($token in $cited) {
            if ($token -eq $name) { continue }
            if ($token -in $skills) { continue }
            if ($token -in $nonSkillTokens) { continue }
            $rel = $doc.FullName.Substring($skillDir.Length + 1)
            Add-Failure "$name : $rel cross-references '$token', which is not a skill folder"
        }
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
