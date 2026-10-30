#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('data360-smoke-' + [guid]::NewGuid().ToString('N'))
[void] (New-Item -Path $scratch -ItemType Directory)
$state = @{
    Calls = [System.Collections.Generic.List[object]]::new()
    Requests = [System.Collections.Generic.List[object]]::new()
    Failure = ''
    LogStatus = 'SUCCESS'
    Selections = 0
    Checks = 0
    Done = $true
}

function Assert {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    $state.Checks++
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $Message)
    $caught = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        $caught = $true
    }
    Assert $caught "Expected error containing '$Message'."
}

function sf {
    $arguments = @($args)
    $state.Calls.Add($arguments)
    $global:LASTEXITCODE = 0
    $command = $arguments[0..2] -join ' '
    if ($state.Failure -eq $command) {
        $global:LASTEXITCODE = 1
        return '{"status":1}'
    }
    switch ($command) {
        'org display --target-org' {
            return '{"result":{"instanceUrl":"https://example.invalid","apiVersion":"66.0","username":"example@example.invalid","id":"00D000000000001AAA"}}'
        }
        'org auth show-access-token' {
            return '{"result":{"accessToken":"mock-token-not-a-credential"}}'
        }
        'project retrieve start' {
            return (@{ status = 0; result = @{ done = $state.Done; success = $state.Done } } | ConvertTo-Json)
        }
        'project deploy start' { return '{"status":0,"result":{"done":true,"success":true}}' }
        'org list --json' {
            return '{"result":{"nonScratchOrgs":[{"username":"target@example.invalid","alias":"target-sandbox","connectedStatus":"Connected","instanceUrl":"https://example.invalid"}]}}'
        }
        default { throw "Unexpected mocked CLI command: $command" }
    }
}

function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $ContentType, $Body)
    Assert ($Headers.Authorization -eq 'Bearer mock-token-not-a-credential') 'REST uses an in-memory bearer token.'
    $state.Requests.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body })
    if ($Uri -like '*/manifest') {
        return [pscustomobject]@{
            dataKitMembers = @(
                [pscustomobject]@{ entityName = 'CustomObject'; developerName = @('Z__dlm', 'A__dlm', 'A__dlm') }
            )
        }
    }
    if ($Method -eq 'Post') { return [pscustomobject]@{ submitted = $true } }
    if ($Uri -like '*/query?*') {
        return [pscustomobject]@{
            records = @(
                foreach ($name in 'Stream', 'Graph', 'Segment', 'Identity') {
                    [pscustomobject]@{
                        ComponentName = $name
                        ComponentType = 'Example'
                        DeploymentStatus = $state.LogStatus
                        DeploymentError = ''
                        LastModifiedDate = '2026-01-01T00:00:00Z'
                    }
                }
            )
        }
    }
    throw "Unexpected mocked REST URI: $Uri"
}

function Read-Host {
    param($Prompt)
    $state.Selections++
    return '1'
}

try {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter *.ps1) {
        $tokens = $null
        $parseErrors = $null
        [void] [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        Assert ($parseErrors.Count -eq 0) "$($file.Name) parses."
    }

    $cms = Join-Path $root 'scripts\find-flow-cms-dependencies.ps1'
    $cmsProject = Join-Path $scratch 'cms-project'
    $flows = Join-Path $cmsProject 'force-app\main\default\flows'
    [void] (New-Item -Path (Join-Path $flows 'nested') -ItemType Directory -Force)
    $flowA = Join-Path $flows 'Example.flow-meta.xml'
    $flowB = Join-Path $flows 'nested\Other.flow-meta.xml'
    $flowXml = @'
<Flow xmlns="http://soap.sforce.com/2006/04/metadata">
  <actionCalls>
    <inputParameters><name>contentId</name><value><stringValue>marketing--Workspace.sfdc_cms__email--MC2</stringValue></value></inputParameters>
    <inputParameters><name>contentId</name><value><stringValue>marketing--Workspace.sfdc_cms__email--MC1&amp;x</stringValue></value></inputParameters>
    <inputParameters><name>contentId</name><value><stringValue>marketing--Workspace.sfdc_cms__email--MC2</stringValue></value></inputParameters>
    <inputParameters><name>otherInput</name><value><stringValue>marketing--Workspace--Ignored</stringValue></value></inputParameters>
    <inputParameters><name>contentId</name><value><elementReference>DynamicContent</elementReference></value></inputParameters>
  </actionCalls>
</Flow>
'@
    [IO.File]::WriteAllText($flowA, $flowXml)
    [IO.File]::WriteAllText($flowB, '<Flow><inputParameters><name>contentId</name><value><stringValue> marketing--Workspace--MC3--suffix </stringValue></value></inputParameters></Flow>')
    $membersFile = Join-Path $cmsProject 'manifest\cms-members.xml'
    $cmsMembers = @(& $cms -ProjectPath $cmsProject -OutputPath 'manifest\cms-members.xml')
    Assert ($cmsMembers.Count -eq 3) 'CMS scan recurses and deduplicates.'
    Assert ($cmsMembers[0] -eq '<members>marketing/Workspace.sfdc_cms__email/MC1&amp;x</members>') 'CMS members are sorted and XML-escaped.'
    Assert ($cmsMembers[2] -eq '<members>marketing/Workspace/MC3--suffix</members>') 'CMS conversion trims values and splits into only three parts.'
    Assert (((Get-Content -LiteralPath $membersFile) -join "`n") -eq ($cmsMembers -join "`n")) 'CMS output file matches pipeline output.'
    $singleMembers = @(& $cms -ProjectPath $cmsProject -FlowPath 'force-app\main\default\flows\Example.flow-meta.xml')
    Assert ($singleMembers.Count -eq 2) 'CMS single-file scan ignores other inputs and dynamic references.'
    Assert ([IO.File]::ReadAllText($flowA) -eq $flowXml) 'CMS scan leaves Flow files unchanged.'
    Assert-Throws { & $cms -ProjectPath $cmsProject -OutputPath 'manifest\cms-members.xml' } 'Output already exists'
    $emptyFlows = Join-Path $scratch 'empty-flows'
    [void] (New-Item -Path $emptyFlows -ItemType Directory)
    Assert-Throws { & $cms -FlowPath $emptyFlows } 'No .flow-meta.xml files'
    Assert-Throws { & $cms -ProjectPath $cmsProject -FlowPath missing } 'Flow path not found'
    Assert-Throws { & $cms -FlowPath $membersFile } 'must name a .flow-meta.xml'
    $invalidFlow = Join-Path $flows 'Invalid.flow-meta.xml'
    [IO.File]::WriteAllText($invalidFlow, '<Flow><inputParameters><name>contentId</name><value><stringValue>marketing----MC1</stringValue></value></inputParameters></Flow>')
    $cmsWarnings = @()
    $invalidMembers = @(& $cms -FlowPath $invalidFlow -WarningVariable cmsWarnings -WarningAction SilentlyContinue)
    Assert ($invalidMembers.Count -eq 0 -and $cmsWarnings.Count -eq 2) 'Invalid CMS IDs are excluded with explicit warnings.'
    [IO.File]::WriteAllText($invalidFlow, '<Flow/>')
    $cmsWarnings = @()
    $emptyMembers = @(& $cms -FlowPath $invalidFlow -WarningVariable cmsWarnings -WarningAction SilentlyContinue)
    Assert ($emptyMembers.Count -eq 0 -and $cmsWarnings.Count -eq 1) 'No supported CMS references produces a warning.'
    [IO.File]::WriteAllText($invalidFlow, '<Flow>')
    $xmlFailed = $false
    try { & $cms -FlowPath $invalidFlow | Out-Null } catch { $xmlFailed = $true }
    Assert $xmlFailed 'Malformed Flow XML fails explicitly.'

    $normalize = Join-Path $root 'scripts\compare-data-kit-manifests.ps1'
    $source = Join-Path $scratch 'source'
    [void] (New-Item -Path $source -ItemType Directory)
    [IO.File]::WriteAllText((Join-Path $source 'Old.xml'), 'Old $1 OLD')
    [IO.File]::WriteAllText((Join-Path $source 'empty.xml'), '')
    $output = Join-Path $scratch 'normalized'
    & $normalize -Path $source -OutputPath $output -Replacements @('Old', 'New', '$1', '$2')
    Assert ([IO.File]::ReadAllText((Join-Path $output 'New.xml')) -eq 'New $2 OLD') 'Literal, ordered, case-sensitive replacement.'
    Assert ([IO.File]::ReadAllText((Join-Path $source 'Old.xml')) -eq 'Old $1 OLD') 'Original stays unchanged.'
    Assert ((Get-Item -LiteralPath (Join-Path $output 'empty.xml')).Length -eq 0) 'Empty files are preserved.'
    Assert-Throws { & $normalize -Path $source -OutputPath $output -Replacements @('Old', 'New') } 'Output already exists'
    Assert-Throws { & $normalize -Path $source -OutputPath $source -Replacements @('Old', 'New') } 'separate from the source'
    Assert-Throws { & $normalize -Path $source -OutputPath (Join-Path $source 'inside') -Replacements @('Old', 'New') } 'separate from the source'
    Assert-Throws { & $normalize -Path $source -Replacements @('Old') } 'pairs'
    [IO.File]::WriteAllText((Join-Path $source 'New.xml'), 'collision')
    Assert-Throws { & $normalize -Path $source -Replacements @('Old', 'New') } 'same output'
    Assert (-not (Test-Path -LiteralPath "$source.normalized")) 'Collision is caught before output is created.'
    Assert-Throws { & $normalize -Path $source -Replacements @('Old.xml', '..\escaped.xml') } 'outside the output folder'
    $single = Join-Path $scratch 'single.xml'
    & $normalize -Path (Join-Path $source 'Old.xml') -OutputPath $single -Replacements @('Old', 'New')
    Assert ([IO.File]::ReadAllText($single) -eq 'New $1 OLD') 'Single-file normalization works.'
    Push-Location $scratch
    try {
        & $normalize -Path $single -OutputPath 'relative.xml' -Replacements @('New', 'Again')
        Assert ([IO.File]::ReadAllText((Join-Path $scratch 'relative.xml')) -eq 'Again $1 OLD') 'Relative output follows the PowerShell working folder.'
    }
    finally {
        Pop-Location
    }

    $project = Join-Path $scratch 'project'
    [void] (New-Item -Path $project -ItemType Directory)
    [IO.File]::WriteAllText((Join-Path $project 'sfdx-project.json'), '{"packageDirectories":[{"path":"force-app","default":true}]}')
    $retrieve = Join-Path $root 'scripts\retrieve-data-cloud-data-kit.ps1'
    $retrieveOptions = @{
        ProjectPath = $project; SourceOrg = 'source-sandbox'; DevName = 'Example_Kit'
        SkipCleanup = $true; SkipValidation = $true
    }
    & $retrieve @retrieveOptions | Out-Null
    $manifestPath = Join-Path $project 'manifest\Example_Kit-data-kit-package.xml'
    [xml] $manifest = Get-Content -LiteralPath $manifestPath -Raw
    $members = @($manifest.Package.types.members)
    Assert (($members -join ',') -eq 'A__dlm,Z__dlm') 'Manifest members are sorted and deduplicated.'
    $retrieveCall = @($state.Calls | Where-Object { $_[0] -eq 'project' -and $_[1] -eq 'retrieve' })[-1]
    Assert ($retrieveCall -contains 'example@example.invalid') 'Retrieval targets the resolved source username.'
    Assert-Throws {
        & $retrieve -ProjectPath $project -SourceOrg source-sandbox -DevName Example_Kit -OutputDir alternate
    } 'With OutputDir'
    & $retrieve @retrieveOptions -OutputDir alternate | Out-Null
    $retrieveCall = @($state.Calls | Where-Object { $_[0] -eq 'project' -and $_[1] -eq 'retrieve' })[-1]
    Assert ($retrieveCall -contains '--output-dir' -and $retrieveCall -contains 'alternate') 'Alternate output is passed to the CLI.'
    $state.Failure = 'org auth show-access-token'
    Assert-Throws { & $retrieve @retrieveOptions } 'Unable to retrieve an access token'
    $state.Failure = 'project retrieve start'
    Assert-Throws { & $retrieve @retrieveOptions } 'Metadata retrieval failed'
    $state.Failure = ''
    $state.Done = $false
    Assert-Throws { & $retrieve @retrieveOptions } 'Retrieval did not finish successfully'
    $state.Done = $true

    $objects = Join-Path $project 'force-app\main\default\objects\Example__dlm'
    [void] (New-Item -Path (Join-Path $objects 'fields') -ItemType Directory -Force)
    [IO.File]::WriteAllText((Join-Path $objects 'Example__dlm.object-meta.xml'), '<CustomObject><mktDataModelAttributes><isSqlDmo>true</isSqlDmo></mktDataModelAttributes></CustomObject>')
    [IO.File]::WriteAllText((Join-Path $objects 'fields\KQ_Test.field-meta.xml'), '<CustomField/>')
    [IO.File]::WriteAllText((Join-Path $objects 'fields\Keep.field-meta.xml'), '<CustomField><fullName>Keep</fullName><type>Lookup</type></CustomField>')
    [IO.File]::WriteAllText((Join-Path $objects 'fields\Remove.field-meta.xml'), '<CustomField><fullName>Remove</fullName><type>Lookup</type></CustomField>')
    [IO.File]::WriteAllText((Join-Path $objects 'fields\Untyped.field-meta.xml'), '<CustomField><fullName>Untyped</fullName></CustomField>')
    $relationships = Join-Path $project 'force-app\main\default\fieldSrcTrgtRelationships'
    [void] (New-Item -Path $relationships -ItemType Directory)
    [IO.File]::WriteAllText((Join-Path $relationships 'Keep.fieldSrcTrgtRelationship-meta.xml'), '<FieldSrcTrgtRelationship><lookupFieldName>Example__dlm.Keep</lookupFieldName></FieldSrcTrgtRelationship>')
    & $retrieve -ProjectPath $project -SourceOrg source-sandbox -DevName Example_Kit -SkipCleanup $false -SkipValidation $false | Out-Null
    Assert (-not (Test-Path -LiteralPath (Join-Path $objects 'fields\KQ_Test.field-meta.xml'))) 'Cleanup removes KQ files.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $objects 'fields\Remove.field-meta.xml'))) 'Cleanup removes unmatched Lookup.'
    Assert (Test-Path -LiteralPath (Join-Path $objects 'fields\Keep.field-meta.xml')) 'Cleanup keeps matched Lookup.'
    Assert (Test-Path -LiteralPath (Join-Path $objects 'fields\Untyped.field-meta.xml')) 'Cleanup handles fields without a type.'
    Assert ((Get-Content -LiteralPath (Join-Path $objects 'Example__dlm.object-meta.xml') -Raw) -notmatch 'isSqlDmo') 'Cleanup removes isSqlDmo.'
    $validation = @($state.Calls | Where-Object { $_[0] -eq 'project' -and $_[1] -eq 'deploy' })[-1]
    Assert ($validation -contains '--dry-run' -and $validation -contains 'target-sandbox') 'Validation uses a dry run and selected target.'

    $deploy = Join-Path $root 'scripts\deploy-data-kit-components.ps1'
    $definitionDir = Join-Path $project 'force-app\main\default\dataPackageKitDefinitions'
    [void] (New-Item -Path $definitionDir -ItemType Directory)
    $definition = Join-Path $definitionDir 'Example_Kit.dataPackageKitDefinition-meta.xml'
    $kitXml = '<DataPackageKitDefinition><deploymentOrder>{"sequence":[{"type":"DataStream","devName":"Stream"},{"type":"DataGraph","devName":"Graph"},{"type":"MarketSegment","devName":"Segment"},{"type":"IdentityResolution","devName":"Identity"}]}</deploymentOrder></DataPackageKitDefinition>'
    [IO.File]::WriteAllText($definition, $kitXml)
    $deployOptions = @{ ProjectPath = $project; TargetOrg = 'target-sandbox'; DataKitName = 'Example_Kit' }
    $state.Requests.Clear()
    & $deploy @deployOptions -WhatIf | Out-Null
    Assert ($state.Requests.Count -eq 0) 'WhatIf never submits or polls.'
    & $deploy @deployOptions -Namespace ExampleNamespace -DataSpace custom -Confirm:$false | Out-Null
    $post = $state.Requests[0]
    $payload = $post.Body | ConvertFrom-Json
    Assert ($payload.components.Count -eq 4) 'All four supported component types are submitted.'
    Assert ($post.Uri -like '*ExampleNamespace__Example_Kit?*dataspace=custom') 'Namespace and data space reach the endpoint.'
    Assert ($payload.components[0].config.bundleConfig.orgId -eq '00D000000000001') 'CRM org ID uses the target 15-character ID.'
    Assert ($payload.components[0].config.bundleName -eq 'ExampleNamespace__Stream') 'Namespace reaches component configuration.'
    $state.Requests.Clear()
    & $deploy @deployOptions -Wait -Confirm:$false | Out-Null
    Assert ($state.Requests.Count -eq 2) 'Wait submits once and reads successful component logs.'
    $state.LogStatus = 'FAILED'
    Assert-Throws { & $deploy @deployOptions -Wait -Confirm:$false } 'component deployment failed'
    [IO.File]::WriteAllText($definition, $kitXml.Replace('"DataStream"', '"Unsupported"'))
    $state.Requests.Clear()
    Assert-Throws { & $deploy @deployOptions -Confirm:$false } 'Nothing was submitted'
    Assert ($state.Requests.Count -eq 0) 'Unsupported entries cannot cause partial submission.'
    Write-Host "PASS: $($state.Checks) checks. No real Salesforce commands or requests were made." -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
