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

## Using the existing retrieval helper

Some projects have a helper named `retrieve-data-cloud-data-kit.ps1`. It obtains the Data Kit member list, writes a manifest, retrieves metadata, and offers cleanup and validation.

**That helper is not bundled with this reference repository.** The following notes describe the version these practices came from; check your project's copy before running it.

- It retrieves from the Salesforce CLI's default org.
- It replaces `manifest\<DeveloperName>-data-kit-package.xml`.
- Pressing Enter at either optional prompt skips that step.
- Its `-OutputDir` option changes the retrieval destination, but cleanup and validation still use the standard project locations. Avoid that combination unless the helper has been updated.
- The reviewed copy used `******` as its authorization header instead of the retrieved token. A maintainer must fix and test that before use. Never paste a token into source code.

For a reviewed, working copy, set the source default from inside your project, then retrieve without automatic cleanup or validation:

```powershell
sf config set target-org=source-sandbox
.\scripts\retrieve-data-cloud-data-kit.ps1 -DevName "Example_Kit" -SkipCleanup $true -SkipValidation $true
```

Setting the default affects later commands that do not explicitly name an org. Prefer explicit `--target-org` values in manual commands.

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

Some projects use `compare-data-kit-manifests.ps1` to make names consistent for comparison. Despite its name, the reviewed version creates a renamed/rewritten copy; it does not produce a comparison report by itself.

Keep normalization separate from deployable metadata. Inspect both paths first: the helper removes an existing output folder before recreating it. Never set its output path to your original source folder.

Next: [Validate and deploy](validate-and-deploy.md).
