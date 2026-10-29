#Requires -Version 7.0
<#
.SYNOPSIS
Retrieves a Data Kit, with optional local cleanup and deployment checking.
.EXAMPLE
.\scripts\retrieve-data-cloud-data-kit.ps1 -SourceOrg source-sandbox -DevName Example_Kit -ProjectPath C:\Projects\Example -SkipCleanup $true -SkipValidation $true
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')]
    [string] $DevName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $SourceOrg,

    [string] $ProjectPath = (Get-Location).Path,

    [ValidateRange(1, 120)]
    [int] $WaitMinutes = 60,

    [switch] $IgnoreConflicts,
    [string] $OutputDir,

    [Nullable[bool]] $SkipCleanup,
    [Nullable[bool]] $SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Check = [char] 8730
$Cross = [char] 10008

$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
$projectConfigPath = Join-Path $projectRoot 'sfdx-project.json'
$manifestPath = Join-Path $projectRoot "manifest\$DevName-data-kit-package.xml"

if (-not (Test-Path $projectConfigPath -PathType Leaf)) {
    throw "Salesforce project configuration not found at $projectConfigPath"
}

if ($OutputDir -and ($SkipCleanup -ne $true -or $SkipValidation -ne $true)) {
    throw 'With OutputDir, explicitly set -SkipCleanup $true -SkipValidation $true. Review and validate the alternate folder separately.'
}

if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
    throw 'Salesforce CLI was not found. Install it with: npm install --global @salesforce/cli@latest'
}

Write-Host "Reading source org '$SourceOrg'..."
$orgDisplayOutput = & sf org display --target-org $SourceOrg --json
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read source org '$SourceOrg'. Check your Salesforce CLI login."
}

$orgDisplay = ($orgDisplayOutput -join [Environment]::NewLine) | ConvertFrom-Json
$instanceUrl = $orgDisplay.result.instanceUrl
$apiVersion = $orgDisplay.result.apiVersion
$orgUsername = $orgDisplay.result.username

if (
    [string]::IsNullOrWhiteSpace($instanceUrl) -or
    [string]::IsNullOrWhiteSpace($apiVersion) -or
    [string]::IsNullOrWhiteSpace($orgUsername)
) {
    throw 'Salesforce CLI did not return the instance URL, API version, and username for the source org.'
}

Write-Host "Source org: $orgUsername"
Write-Host "Instance URL: $instanceUrl"
Write-Host "API version: $apiVersion"

$orgTokenOutput = & sf org auth show-access-token --target-org $orgUsername --json -p
if ($LASTEXITCODE -ne 0) {
    throw "Unable to retrieve an access token for '$orgUsername'."
}
$accessToken = ($orgTokenOutput -join [Environment]::NewLine) | ConvertFrom-Json
$accessToken = $accessToken.result.accessToken

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    throw 'Failed to retrieve access token for the source org.'
}
Write-Host "$Check Access token retrieved." -ForegroundColor Green

$encodedDevName = [Uri]::EscapeDataString($DevName)
$endpoint = "$instanceUrl/services/data/v$apiVersion/ssot/datakit/$encodedDevName/manifest"

Write-Host "Fetching Data Kit manifest for '$DevName'..."
$dataKitManifest = Invoke-RestMethod -Method Get -Uri $endpoint -Headers @{
    Authorization = "Bearer $accessToken"
    Accept        = 'application/json'
}

$dataKitMembers = @($dataKitManifest.dataKitMembers)
if ($dataKitMembers.Count -eq 0) {
    throw "The Data Kit '$DevName' contains no metadata members."
}

$membersByType = @{}
foreach ($item in $dataKitMembers) {
    $entityName = [string] $item.entityName
    $developerNames = @($item.developerName)
    if ([string]::IsNullOrWhiteSpace($entityName) -or $developerNames.Count -eq 0) {
        throw 'Each dataKitMembers item must have an entityName and a non-empty developerName array.'
    }

    if (-not $membersByType.ContainsKey($entityName)) {
        $membersByType[$entityName] = @{}
    }

    foreach ($developerName in $developerNames) {
        if (-not [string]::IsNullOrWhiteSpace($developerName)) {
            $membersByType[$entityName][[string] $developerName] = $true
        }
    }
}

$xmlSettings = [System.Xml.XmlWriterSettings]::new()
$xmlSettings.Indent = $true
$xmlSettings.IndentChars = '    '
$xmlSettings.Encoding = [System.Text.UTF8Encoding]::new($false)

[void] (New-Item -Path (Split-Path -Parent $manifestPath) -ItemType Directory -Force)
$xmlWriter = [System.Xml.XmlWriter]::Create($manifestPath, $xmlSettings)
try {
    $namespace = 'http://soap.sforce.com/2006/04/metadata'
    $xmlWriter.WriteStartDocument()
    $xmlWriter.WriteStartElement('Package', $namespace)

    foreach ($entityName in @($membersByType.Keys | Sort-Object)) {
        $xmlWriter.WriteStartElement('types', $namespace)
        foreach ($developerName in @($membersByType[$entityName].Keys | Sort-Object)) {
            $xmlWriter.WriteElementString('members', $namespace, $developerName)
        }
        $xmlWriter.WriteElementString('name', $namespace, $entityName)
        $xmlWriter.WriteEndElement()
    }

    $xmlWriter.WriteElementString('version', $namespace, $apiVersion)
    $xmlWriter.WriteEndElement()
    $xmlWriter.WriteEndDocument()
}
finally {
    $xmlWriter.Dispose()
}

$memberCount = ($membersByType.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
$relativeManifestPath = [IO.Path]::GetRelativePath($projectRoot, $manifestPath)
Write-Host "Generated $relativeManifestPath with $memberCount members."

$retrieveArguments = @(
    'project', 'retrieve', 'start',
    '--manifest', $manifestPath,
    '--target-org', $orgUsername,
    '--wait', $WaitMinutes,
    '--json'
)
if ($IgnoreConflicts) {
    $retrieveArguments += '--ignore-conflicts'
}
if ($outputDir) {
    $retrieveArguments += @('--output-dir', $outputDir)
}

Write-Host "Retrieving Data Kit metadata from '$orgUsername'..."
Push-Location $projectRoot
try {
    $retrieveOutput = & sf @retrieveArguments
    $retrieveExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

$retrieveOutput | Write-Output
if ($retrieveExitCode -ne 0) {
    throw "Metadata retrieval failed with exit code $retrieveExitCode."
}
$retrieveResult = (($retrieveOutput -join [Environment]::NewLine) | ConvertFrom-Json).result
if (-not $retrieveResult.done -or -not $retrieveResult.success) {
    throw 'Retrieval did not finish successfully. Check the job details above before cleanup or retrying.'
}
Write-Host "$Check Metadata retrieval completed successfully." -ForegroundColor Green

# Cleanup of datakit metadata files
$objectsPath = Join-Path $projectRoot 'force-app/main/default/objects'
if ($null -eq $SkipCleanup) {
    Write-Warning "Cleanup deletes and edits files across '$objectsPath', not just this Data Kit. Back up your work first."
    $CleanupChoice = Read-Host 'Run a datakit cleanup? (y/N)'
    $SkipCleanup = $CleanupChoice -notmatch '^(?i)y(?:es)?$'

}
if ((Test-Path $objectsPath -PathType Container) -and -not $SkipCleanup) {
    Write-Warning "Cleanup is modifying files across '$objectsPath'. Restore from your backup if needed."
    # Cleanup of KeyQualifier metadata files
    Write-Host "$Cross Removing undeployable KeyQualifier fields from object metadata."
    $keyQualifierFiles = @()
    $keyQualifierFiles = @(Get-ChildItem $objectsPath -Recurse -File -Filter 'KQ_*')
    $keyQualifierFiles | Remove-Item -Force
    Write-Host "Removed $($keyQualifierFiles.Count) KeyQualifier metadata files."

    # Cleanup of isSqlDmo elements unsupported by Metadata API deployment
    $isSqlDmoElementCount = 0
    $isSqlDmoFileCount = 0
    Get-ChildItem $objectsPath -Directory -Filter '*__dlm' |
        ForEach-Object {
            Get-ChildItem $_.FullName -File -Filter '*__dlm.object-meta.xml' |
                ForEach-Object {
                    $objectXml = [System.Xml.XmlDocument]::new()
                    $objectXml.PreserveWhitespace = $true
                    $objectXml.Load($_.FullName)
                    $isSqlDmoElements = @($objectXml.SelectNodes(
                        "/*[local-name()='CustomObject']/*[local-name()='mktDataModelAttributes']/*[local-name()='isSqlDmo']"
                    ))

                    if ($isSqlDmoElements.Count -gt 0) {
                        foreach ($isSqlDmoElement in $isSqlDmoElements) {
                            [void] $isSqlDmoElement.ParentNode.RemoveChild($isSqlDmoElement)
                        }
                        $objectXml.Save($_.FullName)
                        $isSqlDmoElementCount += $isSqlDmoElements.Count
                        $isSqlDmoFileCount++
                        Write-Host "$Cross Removing isSqlDmo from $($_.Name)"
                    }
                }
        }
    Write-Host "Removed $isSqlDmoElementCount isSqlDmo elements from $isSqlDmoFileCount DLM object files."

    # This checks local relationship metadata, not relationships in the org.
    $relationshipsPath = Join-Path $projectRoot 'force-app/main/default/fieldSrcTrgtRelationships'
    if (Test-Path $relationshipsPath -PathType Container) {
        $orphanedLookupFields = @()
        $relationshipLookupNames = [System.Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        Get-ChildItem $relationshipsPath -File -Filter '*.fieldSrcTrgtRelationship-meta.xml' |
            ForEach-Object {
                [xml] $relationshipXml = Get-Content $_.FullName -Raw
                $lookupFieldName = $relationshipXml.SelectSingleNode(
                    "/*[local-name()='FieldSrcTrgtRelationship']/*[local-name()='lookupFieldName']"
                )
                if ($lookupFieldName -and -not [string]::IsNullOrWhiteSpace($lookupFieldName.InnerText)) {
                    [void] $relationshipLookupNames.Add($lookupFieldName.InnerText)
                }
            }
        Get-ChildItem $objectsPath -Directory -Filter '*__dlm' |
            ForEach-Object {
                $objectName = $_.Name
                $fieldsPath = Join-Path $_.FullName 'fields'
                if (-not (Test-Path -LiteralPath $fieldsPath -PathType Container)) {
                    return
                }
                Get-ChildItem $fieldsPath -File -Filter '*.field-meta.xml' |
                    ForEach-Object {
                        [xml] $fieldXml = Get-Content $_.FullName -Raw
                        $fieldType = $fieldXml.SelectSingleNode(
                            "/*[local-name()='CustomField']/*[local-name()='type']"
                        )
                        if (-not $fieldType -or $fieldType.InnerText -ne 'Lookup') {
                            return
                        }

                        $fullName = $fieldXml.SelectSingleNode(
                            "/*[local-name()='CustomField']/*[local-name()='fullName']"
                        )
                        if (-not $fullName -or [string]::IsNullOrWhiteSpace($fullName.InnerText)) {
                            throw "Lookup field metadata is missing fullName: $($_.FullName)"
                        }

                        $qualifiedLookupName = "$objectName.$($fullName.InnerText)"
                        if (-not $relationshipLookupNames.Contains($qualifiedLookupName)) {
                            $orphanedLookupFields += $_
                            Write-Host "$Cross Removing lookup without FieldSrcTrgtRelationship: $qualifiedLookupName"
                        }
                    }
            }
        $orphanedLookupFields | Remove-Item -Force
        Write-Host "Removed $($orphanedLookupFields.Count) lookup fields without a FieldSrcTrgtRelationship."
    }
    Write-Host "$Check Data Kit metadata cleanup completed." -ForegroundColor Green
} else {
    Write-Host "Data Kit metadata cleanup skipped." -ForegroundColor Yellow
}

# Deployment validation
if ($null -eq $SkipValidation) {
    $ValidationChoice = Read-Host 'Run a deployment validation now? (y/N)'
    $SkipValidation = $ValidationChoice -notmatch '^(?i)y(?:es)?$'
}
if (-not $SkipValidation) {
    Write-Host 'Reading authenticated Salesforce orgs...'
    $orgListOutput = & sf org list --json
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to list authenticated Salesforce orgs.'
    }

    $orgList = ($orgListOutput -join [Environment]::NewLine) | ConvertFrom-Json
    $authenticatedOrgs = @(
        $orgList.result.PSObject.Properties.Value |
            ForEach-Object { @($_) } |
            Where-Object {
                $_ -and
                -not [string]::IsNullOrWhiteSpace($_.username) -and
                $_.connectedStatus -eq 'Connected'
            } |
            Sort-Object username -Unique
    )

    if ($authenticatedOrgs.Count -eq 0) {
        throw 'No authenticated Salesforce orgs are available for deployment validation.'
    }

    Write-Host 'Select the target org for deployment validation:'
    for ($index = 0; $index -lt $authenticatedOrgs.Count; $index++) {
        $org = $authenticatedOrgs[$index]
        $alias = if ([string]::IsNullOrWhiteSpace($org.alias)) { '<no alias>' } else { $org.alias }
        $status = if ([string]::IsNullOrWhiteSpace($org.connectedStatus)) { 'Unknown' } else { $org.connectedStatus }
        Write-Host "[$($index + 1)] $alias | $($org.username) | $status | $($org.instanceUrl)"
    }

    do {
        $selectionInput = Read-Host "Enter an org number (1-$($authenticatedOrgs.Count))"
        $selection = 0
        $validSelection = [int]::TryParse($selectionInput, [ref] $selection) -and
            $selection -ge 1 -and
            $selection -le $authenticatedOrgs.Count
        if (-not $validSelection) {
            Write-Host 'Invalid selection. Enter one of the listed numbers.' -ForegroundColor Yellow
        }
    } until ($validSelection)

    $selectedOrg = $authenticatedOrgs[$selection - 1]
    $targetOrg = if ([string]::IsNullOrWhiteSpace($selectedOrg.alias)) {
        $selectedOrg.username
    }
    else {
        $selectedOrg.alias
    }

    Write-Host "Validating deployment against '$targetOrg'..."
    Push-Location $projectRoot
    try {
        $validationOutput = & sf project deploy start --dry-run --target-org $targetOrg -x $manifestPath --wait $WaitMinutes --json
        $validationExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $validationOutput | Write-Output
    if ($validationExitCode -ne 0) {
        throw "Deployment validation failed with exit code $validationExitCode."
    }
    $validationResult = (($validationOutput -join [Environment]::NewLine) | ConvertFrom-Json).result
    if (-not $validationResult.done -or -not $validationResult.success) {
        throw 'Deployment validation did not finish successfully. Check the job details above.'
    }

}
else {
    Write-Host 'Deployment validation skipped.' -ForegroundColor Yellow
}