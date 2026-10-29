# Validate and deploy

[Back to the reference index](../README.md)

## Before changing the target

- Confirm the target org's actual identity, not only its alias.
- Confirm the required Data Cloud features, permissions, data space, and connections are available.
- Review the manifest and local files you intend to deploy.
- Get your team's approval if required, especially for production.

## 1. Check without deploying

For a sandbox check, run:

```powershell
sf project deploy start --dry-run --target-org target-sandbox --manifest ".\manifest\Example_Kit-data-kit-package.xml" --wait 60
```

This does not save the proposed metadata changes. Resolve errors and repeat the check before deploying.

Salesforce CLI also provides `sf project deploy validate` for production validation. It has test requirements and is not interchangeable with every sandbox dry run. Have the project owner choose the appropriate test settings for production.

## 2. Deploy metadata

**The following command changes the target org.**

Use the same reviewed files and manifest as your successful check:

```powershell
sf project deploy start --target-org target-sandbox --manifest ".\manifest\Example_Kit-data-kit-package.xml" --wait 60
```

Save the deployment job ID in your private project notes. If the command stops waiting, that does not mean Salesforce stopped deploying.

Check an existing deployment with:

```powershell
sf project deploy report --target-org target-sandbox --job-id "YOUR_DEPLOYMENT_JOB_ID"
```

Do not resubmit a deployment just because the local wait expired.

## 3. Complete the Data Kit component setup

Metadata installation can provide templates and definitions without creating every live Data Cloud component. Follow the relevant Data Kit installation process in Salesforce and check what still needs to be created or configured.

The included [runtime component helper](../scripts/deploy-data-kit-components.ps1) submits component creation through the Connect REST API. Read its [guide and limitations](scripts.md) first.

The helper:

- Reads the local Data Kit definition's deployment order.
- Maps Data Streams, Data Graphs, Market Segments, and Identity Resolution entries to API requests.
- Assumes a CRM connector and derives the connection org ID from the target org. This is not suitable for every connection arrangement.
- Stops before submission if it finds unsupported entries.
- Can wait for component deployment logs and report failures.
- Uses the Salesforce CLI access token in memory; no token should be saved in the script.

Preview its payload first:

```powershell
& "C:\Tools\data360_devops\scripts\deploy-data-kit-components.ps1" -ProjectPath "C:\Projects\Example" -TargetOrg target-sandbox -DataKitName "Example_Kit" -WhatIf
```

`-WhatIf` avoids submitting component creation, but the helper still reads local metadata and authenticates to Salesforce.

Only after reviewing the target, payload, data space, and connector assumptions should an authorized user run:

```powershell
& "C:\Tools\data360_devops\scripts\deploy-data-kit-components.ps1" -ProjectPath "C:\Projects\Example" -TargetOrg target-sandbox -DataKitName "Example_Kit" -Wait
```

This can create live components. Keep the confirmation prompt enabled. A submission response is not proof that all components completed.

## 4. Check in Salesforce

- Are the expected components present in the correct data space?
- Are connection and field mappings correct for this environment?
- Are there failed or pending deployment entries?
- Did any component types require manual work?
- Are users able to access the intended functionality?
- Have you checked whether ingestion, refresh, or scheduled processing will start and consume resources?

Do not assume metadata deployment automatically copies business data or makes all runtime configuration usable.

## If something fails

Record the job ID, affected component, and error in private project notes. Check existing status before retrying; runtime component creation is not necessarily safe to repeat.

There is no universal rollback command for the whole process. Redeploying earlier metadata does not necessarily remove runtime components or reverse data processing.

See [Troubleshooting](troubleshooting.md).
