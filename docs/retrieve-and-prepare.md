# Retrieve and prepare a Data Kit

[Back to the reference index](../README.md)

## 1. Confirm what you are retrieving

Record:

- The source org alias.
- The Data Kit Developer Name, not just its display label.
- Where the retrieved files will be written.

A manifest lists the components to download. Use a manifest obtained for the intended Data Kit; a general project manifest might include unrelated configuration or omit required components.

## 2. Retrieve using a manifest

If you already have the correct manifest, run this from your Salesforce project:

```powershell
sf project retrieve start --target-org source-sandbox --manifest ".\manifest\Example_Kit-data-kit-package.xml" --wait 60
```

Replace the alias and manifest name. This downloads configuration to the local project; it does not deploy to another org.

Review the command result. If it reports a job still running, use the job ID and the CLI's retrieval reporting command to check it. Do not start cleanup while retrieval is incomplete.

## Using the included retrieval helper

The [retrieval helper](../scripts/retrieve-data-cloud-data-kit.ps1) obtains the Data Kit member list, writes a manifest, retrieves metadata, and offers cleanup and validation. See its [full guide](scripts.md) for parameters and precautions.

- It retrieves from the org explicitly named by `-SourceOrg`.
- It replaces `manifest\<DeveloperName>-data-kit-package.xml`.
- Pressing Enter at either optional prompt skips that step.
- With `-OutputDir`, both cleanup and validation must be explicitly skipped so they cannot accidentally use another folder.
- It reads the access token from Salesforce CLI and uses it in memory. Never paste a token into source code.

For example, retrieve without cleanup or validation:

```powershell
& "C:\Tools\data360_devops\scripts\retrieve-data-cloud-data-kit.ps1" -ProjectPath "C:\Projects\Example" -SourceOrg source-sandbox -DevName "Example_Kit" -SkipCleanup $true -SkipValidation $true
```

Replace the example paths and names with your own. The helper does not change your default org.

## 3. Review the downloaded files

Use your editor's source-control view or compare against a saved copy.

- Confirm the changes belong to the intended Data Kit.
- Check for missing dependencies and unexpected changes.
- Keep an original copy before making deployment adjustments.
- Do not use `--ignore-conflicts` just to make a warning disappear; it can overwrite local work.

## 4. Prepare only what is needed

The following are observed deployment adjustments, **not rules to apply blindly to every Data Kit**:

| Item | What to check |
| --- | --- |
| `KQ_*` field files | Some retrieved Key Qualifier metadata cannot be deployed as-is. Confirm the relevant error before removing files from the deployment copy. |
| `isSqlDmo` | Some retrieved DLM object definitions contain this element where the deployment API rejects it. Remove only the rejected element from the deployment copy when appropriate. |
| Lookup fields without a relationship file | Check for the corresponding `FieldSrcTrgtRelationship`. An absent local file may mean an incomplete retrieval, not an unused field. |
| Environment-specific names | Review source connection names, org references, namespaces, and data spaces for the target. Avoid unrestricted search-and-replace. |

The existing helper's cleanup scans `force-app\main\default\objects`, so it can affect files outside the current Data Kit. It deletes matching files and does not provide an undo step.

Its orphan-Lookup check compares against local relationship files; it does not establish whether the relationship exists elsewhere in Salesforce.

## Comparing different names

The [comparison helper](../scripts/compare-data-kit-manifests.ps1) makes names consistent in a separate copy. Despite its name, it does not produce a comparison report by itself. See the [script guide](scripts.md) for an example.

Keep normalization separate from deployable metadata. The included version refuses existing output and output inside the source; it does not delete an existing folder.

Next: [Validate and deploy](validate-and-deploy.md).
