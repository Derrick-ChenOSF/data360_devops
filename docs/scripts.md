# Script guides

[Back to the reference index](../README.md)

These are reusable copies of three existing Data Kit helpers. They have been adjusted to remove customer-specific defaults and add basic safeguards. No GitHub automation is required.

## Before using any script

1. Use **PowerShell 7 or later**, not Windows PowerShell 5.1.
2. Clone or download this repository.
3. Keep your Salesforce project separate from this reference repository.
4. Sign in with Salesforce CLI as described in [Getting started](getting-started.md).
5. Save or back up your project files. Test in a sandbox first.

The examples below assume this repository is at `C:\Tools\data360_devops` and your Salesforce project is at `C:\Projects\Example`. Replace these paths, org aliases, and Data Kit names with your own.

The retrieval and deployment helpers expect metadata under `force-app\main\default`. Projects using another package structure need adjustment before using these helpers.

## 1. Retrieve a Data Kit

Script: [retrieve-data-cloud-data-kit.ps1](../scripts/retrieve-data-cloud-data-kit.ps1)

### What it does

- Reads the Data Kit member list from the org you name.
- Creates or replaces `manifest\<DeveloperName>-data-kit-package.xml` in your Salesforce project.
- Retrieves the listed metadata.
- Optionally cleans local metadata and performs a deployment dry run against an org you select.

It does **not** deploy changes to a target org.

### Recommended first run

Retrieve only. Leave cleanup and validation for after you have reviewed the downloaded files:

```powershell
& "C:\Tools\data360_devops\scripts\retrieve-data-cloud-data-kit.ps1" -ProjectPath "C:\Projects\Example" -SourceOrg source-sandbox -DevName "Example_Kit" -SkipCleanup $true -SkipValidation $true
```

### Options

| Option | Meaning |
| --- | --- |
| `-ProjectPath` | Your Salesforce project folder. Defaults to the terminal's current folder, not this repository. |
| `-SourceOrg` | Required. Alias or username of the org to retrieve from. |
| `-DevName` | Required. Data Kit Developer Name, not its display label. |
| `-WaitMinutes` | Retrieval and dry-run wait, from 1 to 120 minutes. Default: 60. |
| `-SkipCleanup $true` | Skip cleanup. |
| `-SkipValidation $true` | Skip the deployment dry run. |
| `-IgnoreConflicts` | Allow retrieval despite local conflicts. May overwrite local work; do not use casually. |
| `-OutputDir` | Retrieve to another directory. Requires both skip options set to `$true`; check that output separately. Relative paths are relative to the Salesforce project. |

Omit the two skip options to be asked about cleanup and validation. Pressing Enter skips the relevant step. Passing `$false` instead of `$true` enables that step without asking whether to run it; validation still asks you to select an org.

### Cleanup warning

Cleanup deletes `KQ_*` files, removes `isSqlDmo` elements from DLM object metadata, and deletes Lookup fields without matching local relationship metadata.

**It scans the project's object folder, not only the current Data Kit. There is no built-in undo.** A missing relationship file can mean your retrieval is incomplete. See [preparation precautions](retrieve-and-prepare.md) before enabling it.

The optional dry run uses `sf project deploy start --dry-run`. It checks local files through the generated manifest; it is not runtime component installation or a substitute for production test planning.

## 2. Create Data Kit runtime components

Script: [deploy-data-kit-components.ps1](../scripts/deploy-data-kit-components.ps1)

### When to use it

Use this only after the Data Kit metadata is installed in the target. It reads the local kit definition and submits component creation to Salesforce.

Supported deployment-order entries:

- Data Streams, using a **CRM connector**.
- Data Graphs.
- Market Segments.
- Identity Resolution.

It is not a general installer for every Data Cloud component. If any entry is unsupported, the script stops before submitting anything.

### Preview first

```powershell
& "C:\Tools\data360_devops\scripts\deploy-data-kit-components.ps1" -ProjectPath "C:\Projects\Example" -TargetOrg target-sandbox -DataKitName "Example_Kit" -WhatIf
```

This prints the planned request without submitting it. It still authenticates to Salesforce and reads the local Data Kit definition.

**Check the CRM connection assumption:** Data Streams use the target org's ID as their CRM connection org. Do not use this helper when the intended CRM connection is a different org or the connector is not CRM.

### Submit and monitor

Only after reviewing the preview:

```powershell
& "C:\Tools\data360_devops\scripts\deploy-data-kit-components.ps1" -ProjectPath "C:\Projects\Example" -TargetOrg target-sandbox -DataKitName "Example_Kit" -Wait
```

The script asks for confirmation. This command **changes the target org** and may start data processing.

| Option | Meaning |
| --- | --- |
| `-ProjectPath` | Your Salesforce project folder; defaults to the current folder. |
| `-TargetOrg` | Required. Alias or username of the target org. |
| `-DataKitName` | Required. Local Data Kit Developer Name. |
| `-DataSpace` | Target data space API name. Default: `default`. |
| `-Namespace` | Optional package namespace. Do not add one unless your kit requires it. |
| `-ApiVersion` | Connect API major version. Default: `66` (66.0). Confirm support in your target org. |
| `-WhatIf` | Preview without submitting. |
| `-Wait` | Monitor component deployment logs after submitting. Without it, the script reports submission only. |
| `-PollSeconds` | Seconds between checks, 5 to 300. Default: 15. |
| `-WaitMinutes` | Monitoring limit, 1 to 240 minutes. Default: 60. |

Monitoring reads `DataKitDeploymentLog` entries updated since submission; it is not tied to a unique deployment job. Do not run overlapping installations of the same kit. A timeout does not cancel server-side work. Inspect Salesforce before retrying.

## 3. Make a comparison copy with consistent names

Script: [compare-data-kit-manifests.ps1](../scripts/compare-data-kit-manifests.ps1)

### What it does

Creates a separate text copy, replacing names in file contents and, for folders, relative file paths. This makes differences easier to review when environments use different naming.

Despite its historical name, it **does not run a comparison** and is **not a deployment preparation tool**.

```powershell
& "C:\Tools\data360_devops\scripts\compare-data-kit-manifests.ps1" -Path "C:\Temp\retrieved-kit" -OutputPath "C:\Temp\comparison-copy" -Replacements @('Example_Production', 'Example', 'SourceSandbox', 'TargetSandbox')
```

Values in `-Replacements` are find/replace pairs, applied in order. Matches are literal and case-sensitive, not regular expressions.

| Option | Meaning |
| --- | --- |
| `-Path` | Required. A text file or folder of text metadata files. Do not use with binary files. |
| `-OutputPath` | New output file or folder. Defaults to the source path plus `.normalized`. |
| `-Replacements` | Required. One or more pairs of find and replace values. No customer-specific defaults. |

The script refuses existing output, output inside the source, paths escaping the output folder, and duplicate output file names. Originals remain unchanged. Output text is written as UTF-8.

Compare the copy using your editor or:

```powershell
git --no-pager diff --no-index "C:\Projects\Example\force-app\main\default" "C:\Temp\comparison-copy"
```

Choose folders at the same level. Git returns exit code 1 when it finds differences; that is normal for this comparison.

## Verification and limits

Local smoke tests use temporary example files and mocked Salesforce responses. They do not authenticate to or change a Salesforce org:

```powershell
& "C:\Tools\data360_devops\tests\smoke-tests.ps1"
```

These checks do not prove compatibility with every Data Cloud org, API version, or kit. No live org deployment was performed when publishing these copies. Validate in your own sandbox before relying on them.
