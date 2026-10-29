#Requires -Version 7.0
<#
.SYNOPSIS
Deploys the runtime components of a metadata-installed Salesforce Data Kit.

.DESCRIPTION
Reads the Data Kit deployment order from local metadata and submits supported components to the target org.
Uses the Connect REST API, which supports DataStreamBundle and the other component types generated here.

.EXAMPLE
.\scripts\deploy-data-kit-components.ps1 -TargetOrg target-sandbox -DataKitName Example_Kit -WhatIf

.EXAMPLE
.\scripts\deploy-data-kit-components.ps1 -TargetOrg target-sandbox -DataKitName Example_Kit -Wait

.EXAMPLE
.\scripts\deploy-data-kit-components.ps1 -TargetOrg target-sandbox -DataKitName Example_Kit -Namespace ExampleNamespace -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $TargetOrg,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')]
    [string] $DataKitName,

    [string] $ProjectPath = (Get-Location).Path,

    [ValidateNotNullOrEmpty()]
    [string] $DataSpace = 'default',

    [string] $Namespace,

    [ValidateRange(61, 99)]
    [int] $ApiVersion = 66,

    [switch] $Wait,

    [ValidateRange(5, 300)]
    [int] $PollSeconds = 15,

    [ValidateRange(1, 240)]
    [int] $WaitMinutes = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'sfdx-project.json') -PathType Leaf)) {
    throw "Salesforce project configuration not found in '$projectRoot'."
}
$kitDefinitionPath = Join-Path $projectRoot (
    'force-app\main\default\dataPackageKitDefinitions\' + $DataKitName + '.dataPackageKitDefinition-meta.xml'
)

if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
    throw 'Salesforce CLI was not found. Install it with: npm install --global @salesforce/cli@latest'
}

if (-not (Test-Path $kitDefinitionPath -PathType Leaf)) {
    throw "Data Kit definition not found at $kitDefinitionPath"
}

function Get-QualifiedName {
    param([Parameter(Mandatory)][string] $Name)

    if ([string]::IsNullOrWhiteSpace($Namespace) -or $Name.StartsWith("$Namespace`__")) {
        return $Name
    }

    return "$Namespace`__$Name"
}

function Invoke-SalesforceRestMethod {
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post')][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        [object] $Body
    )

    $parameters = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = @{
            Authorization = "Bearer $accessToken"
            Accept        = 'application/json'
        }
        ContentType = 'application/json'
    }
    if ($null -ne $Body) {
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    return Invoke-RestMethod @parameters
}

Write-Host "Reading target org '$TargetOrg'..."
$orgDisplayOutput = & sf org display --target-org $TargetOrg --json
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read target org '$TargetOrg'."
}

$orgDisplay = ($orgDisplayOutput -join [Environment]::NewLine) | ConvertFrom-Json
$instanceUrl = [string] $orgDisplay.result.instanceUrl
$orgId = [string] $orgDisplay.result.id
$orgUsername = [string] $orgDisplay.result.username
if (
    [string]::IsNullOrWhiteSpace($instanceUrl) -or
    [string]::IsNullOrWhiteSpace($orgId) -or
    [string]::IsNullOrWhiteSpace($orgUsername)
) {
    throw 'Salesforce CLI did not return the instance URL, org ID, and username.'
}


$orgTokenOutput = & sf org auth show-access-token -o $TargetOrg --json -p
if ($LASTEXITCODE -ne 0) {
    throw "Unable to retrieve an access token for '$TargetOrg'."
}
$accessToken = [string] (($orgTokenOutput -join [Environment]::NewLine) | ConvertFrom-Json).result.accessToken
if ([string]::IsNullOrWhiteSpace($accessToken)) {
    throw "Salesforce CLI did not return an access token for '$TargetOrg'."
}

[xml] $kitXml = Get-Content $kitDefinitionPath -Raw
$deploymentOrderNode = $kitXml.SelectSingleNode(
    "/*[local-name()='DataPackageKitDefinition']/*[local-name()='deploymentOrder']"
)
if (-not $deploymentOrderNode -or [string]::IsNullOrWhiteSpace($deploymentOrderNode.InnerText)) {
    throw "Data Kit '$DataKitName' does not define a deployment order."
}

$deploymentOrder = $deploymentOrderNode.InnerText | ConvertFrom-Json
$qualifiedKitName = Get-QualifiedName $DataKitName
$crmOrgId = $orgId.Substring(0, [Math]::Min(15, $orgId.Length))
$components = [System.Collections.Generic.List[object]]::new()
$expectedComponentNames = [System.Collections.Generic.List[string]]::new()
$unsupportedComponents = [System.Collections.Generic.List[string]]::new()

foreach ($item in @($deploymentOrder.sequence)) {
    $developerName = [string] $item.devName
    if ([string]::IsNullOrWhiteSpace($developerName)) {
        throw 'A deployment-order entry is missing devName.'
    }
    switch ([string] $item.type) {
        'DataStream' {
            $expectedComponentNames.Add((Get-QualifiedName $developerName))
            $components.Add([ordered]@{
                type   = 'DataStreamBundle'
                config = [ordered]@{
                    connectorType = 'CRM'
                    bundleName    = Get-QualifiedName $developerName
                    forceNoRefresh = $false
                    bundleConfig  = [ordered]@{ orgId = $crmOrgId }
                }
            })
        }
        'DataGraph' {
            $expectedComponentNames.Add((Get-QualifiedName $developerName))
            $components.Add([ordered]@{
                type   = 'DataGraph'
                config = [ordered]@{
                    templateDevName = Get-QualifiedName $developerName
                    name            = $developerName
                    label           = $developerName
                }
            })
        }
        'MarketSegment' {
            $expectedComponentNames.Add((Get-QualifiedName $developerName))
            $components.Add([ordered]@{
                type   = 'MarketSegment'
                config = [ordered]@{
                    name        = Get-QualifiedName $developerName
                    dataKitName = $qualifiedKitName
                }
            })
        }
        'IdentityResolution' {
            $expectedComponentNames.Add((Get-QualifiedName $developerName))
            $components.Add([ordered]@{
                type   = 'IdentityResolution'
                config = [ordered]@{
                    dataSpaceName  = $DataSpace
                    templateDevName = Get-QualifiedName $developerName
                    dataKitDevName = $qualifiedKitName
                }
            })
        }
        default {
            $unsupportedComponents.Add("$($item.type):$developerName")
        }
    }
}

if ($components.Count -eq 0) {
    throw "No REST-deployable components were found in Data Kit '$DataKitName'."
}

$requestBody = [ordered]@{ components = @($components) }
$encodedKitName = [Uri]::EscapeDataString($qualifiedKitName)
$encodedDataSpace = [Uri]::EscapeDataString($DataSpace)
$endpoint = "$instanceUrl/services/data/v$ApiVersion.0/ssot/data-kits/$encodedKitName`?asyncMode=true&dataspace=$encodedDataSpace"

Write-Host "Target org: $orgUsername ($orgId)"
Write-Host "Data Kit: $qualifiedKitName"
Write-Host "Connect API version: $ApiVersion.0"
Write-Host "Components: $($components.Count)"
foreach ($component in $components) {
    Write-Host "  - $($component.type)"
}
if ($unsupportedComponents.Count -gt 0) {
    throw (
        'Nothing was submitted. These deployment-order entries are unsupported; use the appropriate Salesforce installation process: ' +
        ($unsupportedComponents -join ', ')
    )
}

Write-Warning 'CRM Data Streams use this target org as their connection org. Component creation may start data processing.'
if (-not $PSCmdlet.ShouldProcess($orgUsername, "Deploy components for Data Kit '$qualifiedKitName'")) {
    Write-Host 'Request payload:'
    $requestBody | ConvertTo-Json -Depth 20
    return
}

$startedAt = [DateTime]::UtcNow
Write-Host 'Submitting Data Kit component deployment...'
$response = Invoke-SalesforceRestMethod -Method Post -Uri $endpoint -Body $requestBody
$response | ConvertTo-Json -Depth 20

if (-not $Wait) {
    Write-Host 'Deployment was submitted. Use -Wait to monitor DataKitDeploymentLog.' -ForegroundColor Green
    return
}

$escapedKitName = $qualifiedKitName.Replace("'", "\'")
$startedAtSoql = $startedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
$soql = @"
SELECT ComponentName, ComponentType, DeploymentStatus, DeploymentError,
       FlowInterviewIdentifier, DataKitName, LastModifiedDate
FROM DataKitDeploymentLog
WHERE DataKitName = '$escapedKitName'
AND LastModifiedDate >= $startedAtSoql
ORDER BY LastModifiedDate DESC
"@ -replace "`r?`n", ' '
$deadline = [DateTime]::UtcNow.AddMinutes($WaitMinutes)
$terminalSuccess = @('SUCCESS', 'SUCCEEDED', 'COMPLETED', 'DEPLOYED')
$terminalFailure = @('FAILED', 'ERROR')

do {
    $queryEndpoint = "$instanceUrl/services/data/v$ApiVersion.0/query?q=$([Uri]::EscapeDataString($soql))"
    $queryResult = Invoke-SalesforceRestMethod -Method Get -Uri $queryEndpoint
    $records = @($queryResult.records)

    if ($records.Count -gt 0) {
        $records |
            Select-Object ComponentName, ComponentType, DeploymentStatus, DeploymentError, LastModifiedDate |
            Format-Table -AutoSize

        $failed = @($records | Where-Object { $terminalFailure -contains ([string] $_.DeploymentStatus).ToUpperInvariant() })
        if ($failed.Count -gt 0) {
            throw "Data Kit component deployment failed. Review DeploymentError above."
        }

        $pending = @($records | Where-Object {
            $terminalSuccess -notcontains ([string] $_.DeploymentStatus).ToUpperInvariant()
        })
        $reportedNames = @($records | ForEach-Object { [string] $_.ComponentName } | Sort-Object -Unique)
        $missingNames = @($expectedComponentNames | Where-Object {
            $expectedName = $_
            -not @($reportedNames | Where-Object {
                $_ -eq $expectedName -or $_.EndsWith("__$expectedName")
            })
        })
        if ($pending.Count -eq 0 -and $missingNames.Count -eq 0) {
            Write-Host 'All reported Data Kit deployment log entries completed successfully.' -ForegroundColor Green
            return
        }
        if ($missingNames.Count -gt 0) {
            Write-Host "Waiting for component logs: $($missingNames -join ', ')"
        }
    }
    else {
        Write-Host 'Waiting for DataKitDeploymentLog records...'
    }

    Start-Sleep -Seconds $PollSeconds
} while ([DateTime]::UtcNow -lt $deadline)

throw "Timed out after $WaitMinutes minutes while monitoring DataKitDeploymentLog. The server-side deployment can still be running."