---
name: data360-datakit-deploy
description: 'Promote Salesforce Data Cloud (Data 360) DevOps Data Kits from sandbox to related environments: retrieve a kit manifest, review dependencies and publishing sequence, validate and deploy metadata, complete runtime component setup, reauthorize connectors, and verify results. Use for Data Kit DevOps deployment, sandbox-to-production promotion, DataPackageKitDefinition deploymentOrder issues, or incomplete runtime setup after metadata deployment. Excludes Standard-kit distribution, managed 2GP packaging, AppExchange, and subscriber package installation. Route governance-policy mergeback to its supported non-CLI path.'
---

# Data 360 DevOps Data Kit Deployment

## Outcome and Scope

Produce a reviewed, traceable promotion of a **DevOps Data Kit**, with separate evidence for metadata deployment and runtime readiness. For planning-only requests, produce a runbook and identify checks that have not been executed.

This skill covers in-house promotion between supported related environments, especially sandbox to production. It does not create managed packages, manage SSOT package dependencies, promote package versions, install subscriber packages, or uninstall packages. Do not apply Standard-kit packaging restrictions or naming conventions to DevOps deployments without confirming they apply.

This folder is a distributable skill artifact, not an installed customization. Do not install it or change agent discovery settings unless requested.

## 1. Establish Inputs and Route

Collect only missing inputs:

- Salesforce project path containing `sfdx-project.json`; keep customer metadata outside this reference repository.
- Source and target org aliases, actual org identities, environment types, and supported relationship/deployment connection.
- Data Kit Developer Name, confirmed **DevOps** type in the source UI, and source/target data space names and prefixes.
- Kit-specific manifest, intended component changes, connector types, target connections, and required permissions/features.
- Requested mode: plan, retrieve, validate, deploy metadata, or complete runtime setup; production approval and test requirements.

Apply these branches before running commands:

| Condition | Action |
| --- | --- |
| Customer distribution, AppExchange, Standard kit, or managed 2GP requested | Explain that a different workflow is required; do not silently convert kit types. |
| Unrelated environments or production-to-production requested | Stop promotion until the supported path is established from current Salesforce documentation. |
| Target data space differs from source | Resolve the mismatch; DevOps kits target the same data space, with matching prefix. Do not rewrite names to bypass this requirement. |
| Governance policies or tag assignments included | Use the governance branch below for those items; CLI success is not proof of policy deployment. |
| Runtime components missing after metadata deployment | Inspect existing target state, then continue at step 5; do not automatically redeploy metadata. |

Do not infer kit type solely from retrieved flags. Upstream reports `dataKitType: NONE` for some **Standard** kits; that is not evidence that a kit is DevOps. Confirm in the source org.

Verify current Salesforce documentation and installed CLI help for release-sensitive commands, supported components, and API payloads. Treat the upstream skill as guidance, not the platform contract.

## 2. Obtain the Manifest and Retrieve

1. In the source kit, review its members and dependencies. Save the Publishing Sequence in dependency order.
2. Download the kit's manifest from Data Kits. Do not substitute a broad project manifest or guess generated member names.
3. Check local changes and the retrieval destination before allowing retrieval to overwrite files.
4. Run from the Salesforce project, always naming the source org explicitly:

```powershell
sf project retrieve start --target-org source-sandbox --manifest ".\manifest\Example_Kit-data-kit-package.xml" --wait 60
```

5. Confirm retrieval completed. If it is still running, retain its job ID and check the existing job using the installed CLI's retrieval reporting command before reviewing or cleaning files.

The optional repository retrieval helper obtains the member list and writes a manifest. Read its limitations first. Start with `-SkipCleanup $true -SkipValidation $true`; it replaces the kit manifest and assumes `force-app\main\default` for subsequent processing.

## 3. Review and Prepare

Review the diff, manifest, and kit definition together:

- Verify members belong to the intended kit and dependency files are present.
- Inspect `DataPackageKitDefinition.deploymentOrder` as structured JSON inside the XML. Confirm dependencies precede consumers and the sequence matches the saved source sequence.
- The runtime sequence is not the complete metadata inventory; a DMO absent from the sequence is not automatically missing from the kit.
- Check target data space, connection references, org-specific names, field mappings, and API compatibility. Make only justified, scoped adjustments.
- Keep an original copy before cleanup. Apply changes to the deployment copy and review every deletion.

**Do not turn upstream packaging cleanup into unconditional DevOps cleanup.** Investigate standalone `objects/*/fields/KQ_*.field-meta.xml` files when a relevant deployment error or documented constraint requires it; retain embedded `keyQualifierName` in DLO metadata. Remove `isSqlDmo` only when the target API rejects it. A Lookup without local `FieldSrcTrgtRelationship` metadata can indicate incomplete retrieval; retrieve dependencies before considering deletion.

The repository cleanup helper scans the project's object folder, not only the selected kit, and has no built-in undo. Do not enable it without reviewing its scope. Comparison-normalized copies are for review, not deployment.

Record the reviewed source revision or artifact identity. Do not commit customer metadata, credentials, raw org output, or private deployment evidence to this reference repository. Do not commit or push on the user's behalf unless requested.

## 4. Validate and Deploy Metadata

Confirm target identity, dependencies, permissions, connectors, and data space before validation. Use explicit `--target-org` values; do not switch defaults as a convenience.

For a sandbox validation:

```powershell
sf project deploy start --dry-run --target-org target-sandbox --manifest ".\manifest\Example_Kit-data-kit-package.xml" --wait 60
```

For production, use `sf project deploy validate` with the reviewed manifest, explicit target, and the project's approved test settings. Do not choose `NoTestRun` or bypass tests to force a result. Confirm successful validation and required approval before production deployment; a dry run is not authorization.

Deploy exactly the reviewed files and manifest. This example changes a sandbox:

```powershell
sf project deploy start --target-org target-sandbox --manifest ".\manifest\Example_Kit-data-kit-package.xml" --wait 60
```

For production execution, follow the approved release path and test requirements. If using a validated quick deployment, verify the job, target, artifact, and eligibility instead of substituting an unrelated validation.

Retain the deployment ID in private release evidence. If waiting expires, inspect the existing job; do not resubmit:

```powershell
sf project deploy report --target-org target-sandbox --job-id "YOUR_DEPLOYMENT_JOB_ID"
```

Do not use conflict, warning, or error bypass flags to hide unresolved deployment problems. Metadata success is a gate to runtime checks, not the completion criterion.

## 5. Complete Runtime Setup

1. Inspect target Data Kits, existing components, and deployment logs. Distinguish missing, failed, pending, and already deployed components before deciding what to submit.
2. Reauthorize target connectors as needed through supported authentication. Connection configuration does not transfer credentials. Never collect secrets through chat or print access tokens.
3. Use the supported Data Kits UI deployment process or current Connect REST component deployment API. Verify component-specific payloads and dependencies before submission. Preserve dependency order; do not force package namespaces onto DevOps kit or runtime names.
4. Preview the intended kit, data space, connector mapping, and component payload. Obtain authorization before creating runtime components or starting ingestion, refresh, transforms, or scheduled processing.
5. Monitor component completion after submission. A request accepted by the API does not prove deployment succeeded.

### Optional Repository Helper

Read the linked script guide before using `deploy-data-kit-components.ps1`. Use PowerShell 7 or later and explicit `-ProjectPath`, `-TargetOrg`, and `-DataKitName`; add `-DataSpace` when needed.

- Run `-WhatIf` first. It avoids submission but still authenticates and reads local metadata.
- The helper supports CRM Data Streams, Data Graphs, Market Segments, and Identity Resolution. It stops before submission for unsupported sequence entries.
- Data Streams assume a CRM connection to the target org itself. Do not use the helper for a different source CRM org or a non-CRM connector without a separately reviewed implementation.
- Confirm its API version is supported; do not treat its default as a universal requirement.
- Keep confirmation enabled. After approving the preview, use `-Wait` to monitor rather than reporting submission as success.
- Monitoring uses kit logs updated since submission, not a unique runtime job ID. Avoid overlapping deployments of the same kit; inspect ambiguous or timed-out results in Salesforce before retrying.

Unsupported component types require their documented deployment path, not omission from the plan or invented payloads. Do not deploy only part of a dependency chain without an explicit, reviewed plan.

## Governance Mergeback Branch

The upstream reference describes governance mergeback between related environments using **DevOps** kits and supported kit/change-set mechanisms, not Salesforce CLI governance-policy deployment. Verify current support before execution and keep this branch separate from ordinary metadata CLI promotion.

- Include the relevant DLOs/DMOs; associated supported policies and tag assignments follow their supported mergeback behavior rather than being added alone.
- Check standard-tag-based policy support. Custom tags, policies using custom tags, unstructured masking, and RLS hierarchy operators require separate handling or are unsupported in the upstream guidance.
- Ensure objects referenced by RLS joins exist in the target.
- Removing governance metadata in the source does not establish deletion in the target. Track separately approved target-side work and verify the resulting access behavior.

Do not claim governance parity from a successful metadata deployment.

## 6. Verify and Report

Declare the promotion complete only when the applicable checks have evidence:

- Metadata validation and deployment completed against the intended target and reviewed artifact.
- Expected runtime components exist in the correct data space; no unresolved failed or pending entries remain.
- Connections are authorized and target mappings are correct.
- Required manual work and unsupported component paths are completed, or clearly reported as blockers.
- Functional access and applicable governance behavior are checked.
- Any authorized ingestion/transform/refresh run is verified separately from component deployment; configuration deployment does not copy business data.

Report metadata status and runtime status separately, with target, kit, data space, artifact, job IDs where available, checks performed, and unresolved actions. Use `not run`, `submitted`, `pending`, `failed`, or `verified` precisely; never report unexecuted checks as passing.

On failure, preserve sanitized diagnostics privately, isolate the failed phase, inspect existing state, repair the smallest cause, and repeat the relevant validation. Do not blindly retry runtime creation. There is no universal rollback: restoring old metadata may leave runtime components and processed data unchanged. Undeploy, deletion, and data cleanup require a separate impact review and explicit authorization; they are not routine retry steps.

## Optional Repository Resources

These links supplement the self-contained procedure when this skill remains in this repository. If distributing the skill folder alone, omit these integrations unless the referenced helpers are also available; do not assume installed paths.

| Resource | Purpose |
| --- | --- |
| [Retrieve and prepare](../../docs/retrieve-and-prepare.md) | Manifest retrieval and evidence-based cleanup precautions. |
| [Validate and deploy](../../docs/validate-and-deploy.md) | Metadata gates and runtime verification. |
| [Script guides](../../docs/scripts.md) | Exact helper parameters, assumptions, and monitoring limits. |
| [Troubleshooting](../../docs/troubleshooting.md) | Local failure triage guidance. |
| [Retrieval helper](../../scripts/retrieve-data-cloud-data-kit.ps1) | Optional manifest generation and retrieval. |
| [Runtime helper](../../scripts/deploy-data-kit-components.ps1) | Optional supported-component creation and monitoring. |

## Sources and Extraction Boundary

This is an independently worded, deployment-only synthesis of [holapancho/packaging-datacloud-skill](https://github.com/holapancho/packaging-datacloud-skill), reviewed 2026-10-30 at upstream revision `6a6e809b25d428bcb10ff8d92c60eb8c952ecde2` (Apache-2.0; [upstream license](https://github.com/holapancho/packaging-datacloud-skill/blob/6a6e809b25d428bcb10ff8d92c60eb8c952ecde2/LICENSE)). No upstream scripts or reference documents are copied into this folder.

Retained: DevOps CLI workflow, Standard/DevOps routing, governance exclusions, publishing-sequence review, runtime setup, connector reauthorization, and operational verification. Excluded: managed 2GP creation/versioning/promotion, SSOT version selection, AppExchange distribution, subscriber installation, package upgrade ancestry, and uninstall runbooks. Packaging-only observations are not generalized into DevOps requirements.

Upstream entry points:

- [DevOps CLI workflow](https://github.com/holapancho/packaging-datacloud-skill/blob/6a6e809b25d428bcb10ff8d92c60eb8c952ecde2/skills/packaging-datacloud/references/devops-cli-workflow.md)
- [Kit type distinctions](https://github.com/holapancho/packaging-datacloud-skill/blob/6a6e809b25d428bcb10ff8d92c60eb8c952ecde2/skills/packaging-datacloud/references/standard-vs-devops-data-kits.md)
- [Governance mergeback](https://github.com/holapancho/packaging-datacloud-skill/blob/6a6e809b25d428bcb10ff8d92c60eb8c952ecde2/skills/packaging-datacloud/references/governance-mergeback-devops.md)

Prefer current official sources when guidance differs:

- [Use CLI to deploy changes from a sandbox](https://developer.salesforce.com/docs/data/data-cloud-dev/guide/dc-deploy_data_kit_using_cli.html)
- [Data Kits and kit types](https://help.salesforce.com/s/articleView?id=data.c360_a_data_package_kits.htm&type=5)
- [Governance mergeback](https://help.salesforce.com/s/articleView?id=data.c360_a_mergeback_devops_datakits.htm&type=5)
- [Connect REST Data Kit deployment](https://developer.salesforce.com/docs/data/data-cloud-dev/guide/dc-deploy-data-kits-using-connect-api.html)
- [Component deployment payloads](https://developer.salesforce.com/docs/data/connectapi/guide/deploy-data-kit-payloads.html)
- [Salesforce CLI reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)

## Example Requests

- "Use this skill to plan promotion of Example_Kit from source-sandbox to production; do not deploy yet."
- "Retrieve and validate this DevOps Data Kit against target-sandbox, with cleanup disabled."
- "Metadata deployed successfully, but the kit's runtime components are missing. Inspect state and prepare the next steps."
- "Check whether the governance changes in this DevOps kit require a separate mergeback path."