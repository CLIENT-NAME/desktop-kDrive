<#
.SYNOPSIS
    Crawls RawAssets/**/*.svg, extracts <path d="..."> data from each file,
    and generates a WinUI ResourceDictionary XAML with x:String entries.

.PARAMETER RawAssetsDir
    Path to the RawAssets folder (absolute or relative to the script).

.PARAMETER OutputFile
    Path to the generated XAML file (absolute or relative to the script).
#>
param(
    [Parameter(Mandatory)][string] $RawAssetsDir,
    [Parameter(Mandatory)][string] $OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve relative paths against the script's own directory, not the shell's CWD
if (-not [System.IO.Path]::IsPathRooted($RawAssetsDir)) {
    $RawAssetsDir = Join-Path $PSScriptRoot $RawAssetsDir
}
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
    $OutputFile = Join-Path $PSScriptRoot $OutputFile
}
$RawAssetsDir = [System.IO.Path]::GetFullPath($RawAssetsDir)
$OutputFile   = [System.IO.Path]::GetFullPath($OutputFile)

# ── Helpers ────────────────────────────────────────────────────────────────────
$keyPrefix = 'Infomaniak.Ressources'

function Get-ResourceKey([System.IO.FileInfo] $file, [string] $baseDir) {
    # Relative path from RawAssets root, without extension
    $rel = $file.FullName.Substring($baseDir.Length).TrimStart('\', '/')
    $noExt = [System.IO.Path]::ChangeExtension($rel, $null).TrimEnd('.')

    # Replace directory separators with dots and prepend prefix
    return "$keyPrefix.$($noExt.Replace('\', '.').Replace('/', '.'))"
}

function Get-SvgPathData([string] $svgPath) {
    [xml] $svg = Get-Content -LiteralPath $svgPath -Raw
    $ns = New-Object System.Xml.XmlNamespaceManager($svg.NameTable)
    $ns.AddNamespace('svg', 'http://www.w3.org/2000/svg')

    # Collect all <path d="..."> — works for both namespaced and non-namespaced SVGs
    $paths = $svg.SelectNodes('//svg:path/@d', $ns)
    if ($null -eq $paths -or $paths.Count -eq 0) {
        # Fallback: no namespace
        $paths = $svg.SelectNodes('//path/@d')
    }

    $data = @($paths | ForEach-Object { $_.Value }) -join ' '
    return $data
}

function Escape-Xml([string] $s) {
    return $s `
        -replace '&', '&amp;' `
        -replace '"', '&quot;' `
        -replace '<', '&lt;' `
        -replace '>', '&gt;'
}

# ── Main ───────────────────────────────────────────────────────────────────────

if (-not (Test-Path $RawAssetsDir)) {
    Write-Error "RawAssets directory not found: $RawAssetsDir"
    exit 1
}

$outDir = Split-Path $OutputFile
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$svgFiles = Get-ChildItem -Path $RawAssetsDir -Filter '*.svg' -Recurse | Sort-Object FullName

Write-Host "GenerateSvgResources: found $($svgFiles.Count) SVG file(s) in '$RawAssetsDir'"

$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine('<!-- AUTO-GENERATED — DO NOT EDIT. Re-generated at every build from RawAssets/. -->')
$null = $sb.AppendLine('<ResourceDictionary')
$null = $sb.AppendLine('    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"')
$null = $sb.AppendLine('    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">')
$null = $sb.AppendLine()

foreach ($file in $svgFiles) {
    $key  = Get-ResourceKey $file $RawAssetsDir
    $data = Get-SvgPathData  $file.FullName

    if ([string]::IsNullOrWhiteSpace($data)) {
        Write-Warning "  Skipping '$($file.Name)': no <path d='...'> found."
        continue
    }

    $escapedData = Escape-Xml $data
    $null = $sb.AppendLine("    <!-- $($file.FullName.Substring($RawAssetsDir.Length).TrimStart('\','/')) -->")
    $null = $sb.AppendLine("    <x:String x:Key=`"$key`">$escapedData</x:String>")
    $null = $sb.AppendLine()
}

$null = $sb.AppendLine('</ResourceDictionary>')

[System.IO.File]::WriteAllText($OutputFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "GenerateSvgResources: written '$OutputFile'"

# ── Validate: ensure all $keyPrefix.* references are defined ──────

$stylesDir = Join-Path $PSScriptRoot 'Styles'
$escapedPrefix = [regex]::Escape($keyPrefix)

# Collect all defined resource keys from XAML dictionaries under Styles/
$definedKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$dictFiles = Get-ChildItem -Path $stylesDir -Filter '*.xaml' -Recurse
foreach ($dict in $dictFiles) {
    $dictContent = Get-Content -LiteralPath $dict.FullName -Raw
    $matches = [regex]::Matches($dictContent, "x:Key=`"($escapedPrefix\.[^`"]+)`"")
    foreach ($m in $matches) {
        $null = $definedKeys.Add($m.Groups[1].Value)
    }
}

# Scan all XAML and CS files in the project for references to $keyPrefix.*
$projectDir = $PSScriptRoot
$allSourceFiles = Get-ChildItem -Path $projectDir -Include '*.xaml','*.cs' -Recurse |
    Where-Object { $_.FullName -notmatch '\\obj\\' -and $_.FullName -notmatch '\\bin\\' }

$missingKeys = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$referencedKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $allSourceFiles) {
    # Skip the generated file itself and dictionary files under Styles/
    if ($file.FullName -like "$stylesDir*") { continue }

    $content = Get-Content -LiteralPath $file.FullName -Raw
    # Match in XAML: {StaticResource ...} / {ThemeResource ...}
    # Match in CS: string literals containing the key
    $refs = [regex]::Matches($content, "$escapedPrefix\.[A-Za-z0-9._-]+")
    foreach ($ref in $refs) {
        $key = $ref.Value.Trim()
        $null = $referencedKeys.Add($key)
        if (-not $definedKeys.Contains($key)) {
            $null = $missingKeys.Add($key)
        }
    }
}

# Warn about defined keys that are never referenced
$unusedKeys = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($defined in $definedKeys) {
    if (-not $referencedKeys.Contains($defined)) {
        $null = $unusedKeys.Add($defined)
    }
}
if ($unusedKeys.Count -gt 0) {
    Write-Warning "GenerateSvgResources: $($unusedKeys.Count) $keyPrefix.* key(s) defined but never referenced:"
    foreach ($k in $unusedKeys) {
        Write-Warning "  - $k"
    }
}

if ($missingKeys.Count -gt 0) {
    Write-Host "GenerateSvgResources: $($missingKeys.Count) referenced $keyPrefix.* key(s) not found in any Styles/ dictionary:"
    foreach ($k in $missingKeys) {
        Write-Host "  - $k"
    }
    Write-Warning "GenerateSvgResources: validation failed - missing resource keys (see above)."
    exit 1
}
else {
    Write-Host "GenerateSvgResources: all $keyPrefix.* references are defined. OK"
}