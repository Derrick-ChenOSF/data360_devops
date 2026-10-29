#Requires -Version 7.0
<#
.SYNOPSIS
Creates a normalized text copy for comparison; does not deploy or compare it.
.EXAMPLE
.\scripts\compare-data-kit-manifests.ps1 -Path C:\Temp\retrieved -Replacements @('Example_Production', 'Example')
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Path,

    [string] $OutputPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Replacements
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Replacements.Count % 2 -ne 0) {
    throw 'Replacements must contain pairs of find/replace values.'
}
for ($i = 0; $i -lt $Replacements.Count; $i += 2) {
    if ([string]::IsNullOrEmpty($Replacements[$i])) {
        throw 'Find values cannot be empty.'
    }
}

function Get-NormalizedText {
    param([AllowEmptyString()][string] $Text)
    for ($i = 0; $i -lt $Replacements.Count; $i += 2) {
        $Text = $Text.Replace($Replacements[$i], $Replacements[$i + 1])
    }
    return $Text
}

$sourceItem = Get-Item -LiteralPath $Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = $sourceItem.FullName.TrimEnd('\', '/') + '.normalized'
}
$outputFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$sourceFullPath = $sourceItem.FullName.TrimEnd('\', '/')
if (
    $outputFullPath.Equals($sourceFullPath, [StringComparison]::OrdinalIgnoreCase) -or
    ($sourceItem.PSIsContainer -and $outputFullPath.StartsWith(
        $sourceFullPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase
    ))
) {
    throw 'OutputPath must be separate from the source, not equal to or inside it.'
}
if (Test-Path -LiteralPath $outputFullPath) {
    throw "Output already exists: $outputFullPath. Choose a new output path."
}

$files = @(
    if ($sourceItem.PSIsContainer) {
        Get-ChildItem -LiteralPath $sourceItem.FullName -Recurse -File
    }
    else {
        $sourceItem
    }
)
$destinations = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$plan = foreach ($file in $files) {
    $destination = $outputFullPath
    if ($sourceItem.PSIsContainer) {
        $relative = [IO.Path]::GetRelativePath($sourceItem.FullName, $file.FullName)
        $normalized = Get-NormalizedText $relative
        $destination = [IO.Path]::GetFullPath((Join-Path $outputFullPath $normalized))
        if (-not $destination.StartsWith(
            $outputFullPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "A replacement would write outside the output folder: $normalized"
        }
    }
    if (-not $destinations.Add($destination)) {
        throw "Multiple source files map to the same output: $destination"
    }
    [pscustomobject]@{ Source = $file.FullName; Destination = $destination }
}

if ($sourceItem.PSIsContainer) {
    [void] (New-Item -Path $outputFullPath -ItemType Directory)
}
foreach ($entry in $plan) {
    [void] (New-Item -Path (Split-Path -Parent $entry.Destination) -ItemType Directory -Force)
    $text = [IO.File]::ReadAllText($entry.Source)
    [IO.File]::WriteAllText($entry.Destination, (Get-NormalizedText $text), [Text.UTF8Encoding]::new($false))
}
Write-Host "Normalized $($files.Count) file(s) written to: $outputFullPath"
Write-Host 'Compare this copy using your editor or git diff --no-index. It is not a deployment copy.'
