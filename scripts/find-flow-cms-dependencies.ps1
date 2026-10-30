#Requires -Version 7.0
<#
.SYNOPSIS
Finds CMS content references in local Salesforce Flow metadata.
.DESCRIPTION
Scans literal contentId input parameters and emits sorted, unique DigitalExperience
manifest member elements. Does not retrieve content, deploy, or contact Salesforce.
.EXAMPLE
.\scripts\find-flow-cms-dependencies.ps1 -ProjectPath C:\Projects\Example
.EXAMPLE
.\scripts\find-flow-cms-dependencies.ps1 -ProjectPath C:\Projects\Example -FlowPath force-app\main\default\flows\Example_Activation.flow-meta.xml
.EXAMPLE
.\scripts\find-flow-cms-dependencies.ps1 -ProjectPath C:\Projects\Example -OutputPath manifest\cms-content-members.xml
#>
[CmdletBinding()]
param(
    [string] $ProjectPath = (Get-Location).Path,

    [ValidateNotNullOrEmpty()]
    [string] $FlowPath,

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
if ([string]::IsNullOrWhiteSpace($FlowPath)) {
    $FlowPath = Join-Path $projectRoot 'force-app\main\default\flows'
}
elseif (-not [IO.Path]::IsPathRooted($FlowPath)) {
    $FlowPath = Join-Path $projectRoot $FlowPath
}

if (-not (Test-Path -LiteralPath $FlowPath)) {
    throw "Flow path not found: $FlowPath"
}

$flowFiles = @(
    if (Test-Path -LiteralPath $FlowPath -PathType Leaf) {
        if ($FlowPath -notlike '*.flow-meta.xml') {
            throw 'FlowPath must name a .flow-meta.xml file or a folder of Flow metadata.'
        }
        Get-Item -LiteralPath $FlowPath
    }
    else {
        Get-ChildItem -LiteralPath $FlowPath -Recurse -File -Filter '*.flow-meta.xml'
    }
)
if ($flowFiles.Count -eq 0) {
    throw "No .flow-meta.xml files found under $FlowPath"
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    if (-not [IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path $projectRoot $OutputPath
    }
    if (Test-Path -LiteralPath $OutputPath) {
        throw "Output already exists: $OutputPath. Choose a new output file."
    }
}

$dependencies = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($flowFile in $flowFiles) {
    $flowXml = [System.Xml.XmlDocument]::new()
    $flowXml.Load($flowFile.FullName)
    $contentIdNodes = $flowXml.SelectNodes(
        "//*[local-name()='inputParameters'][*[local-name()='name']='contentId']" +
        "/*[local-name()='value']/*[local-name()='stringValue']"
    )
    foreach ($contentIdNode in $contentIdNodes) {
        $contentId = $contentIdNode.InnerText.Trim()
        $parts = @($contentId -split '--', 3)
        if ($parts.Count -ne 3 -or @($parts | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            Write-Warning "Ignoring invalid CMS contentId '$contentId' in $($flowFile.FullName)"
            continue
        }
        [void] $dependencies.Add(($parts -join '/'))
    }
}

$memberLines = @(
    $dependencies | Sort-Object | ForEach-Object {
        "<members>$([Security.SecurityElement]::Escape($_))</members>"
    }
)
if ($memberLines.Count -eq 0) {
    Write-Warning 'No supported literal CMS contentId references were found. This is not proof that the flows have no CMS dependencies.'
}
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    [void] (New-Item -Path (Split-Path -Parent $OutputPath) -ItemType Directory -Force)
    [IO.File]::WriteAllLines($OutputPath, [string[]] $memberLines, [Text.UTF8Encoding]::new($false))
    Write-Verbose "Wrote $($memberLines.Count) CMS dependencies to $OutputPath"
}
$memberLines
