# Find CMS content needed by Marketing Cloud Next flows

[Back to the reference index](../README.md) | [Other script guides](scripts.md)

Script: [find-flow-cms-dependencies.ps1](../scripts/find-flow-cms-dependencies.ps1)

## Why this helper exists

Marketing Cloud Next deployments can include data activation and other flows that reference CMS content, such as an email. Moving the Flow alone may leave the referenced content missing in the target.

**In the deployment scenario that prompted this helper, missing CMS content caused `INTERNAL_ERROR` instead of a clear missing-dependency message.** This is a practical troubleshooting lesson, not a claim that every `INTERNAL_ERROR` has the same cause.

The helper reads your downloaded Flow files and lists the CMS content references you should review and include in your deployment planning.

## What it does (and does not do)

- Scans one Flow metadata file or a folder of Flow metadata files, including subfolders.
- Finds `inputParameters` named `contentId` with a literal `stringValue`.
- Converts a reference such as:

  ```text
  marketing--Default_Content_Workspace.sfdc_cms__email--MC123
  ```

  into a manifest entry:

  ```xml
  <members>marketing/Default_Content_Workspace.sfdc_cms__email/MC123</members>
  ```

- Sorts the entries, removes duplicates, and optionally writes them to a new text file.
- Does not log in, change Flow files, retrieve content, or deploy anything.

It does not resolve variables, formulas, references built at runtime, or every possible CMS dependency. It also does not check whether the content already exists in the target or find all content nested inside an email.

## 1. Scan your local Flow files

Use **PowerShell 7 or later**. No Salesforce login is required for the scan.

Retrieve the relevant flows into your Salesforce project first. Then run:

```powershell
& "C:\Tools\data360_devops\scripts\find-flow-cms-dependencies.ps1" -ProjectPath "C:\Projects\Example"
```

Replace both example paths with your own. By default, the script scans `force-app\main\default\flows` inside your project.

For just one flow:

```powershell
& "C:\Tools\data360_devops\scripts\find-flow-cms-dependencies.ps1" -ProjectPath "C:\Projects\Example" -FlowPath "force-app\main\default\flows\Example_Activation.flow-meta.xml"
```

## 2. Save the list if useful

```powershell
& "C:\Tools\data360_devops\scripts\find-flow-cms-dependencies.ps1" -ProjectPath "C:\Projects\Example" -OutputPath "manifest\cms-content-members.xml"
```

| Option | Meaning |
| --- | --- |
| `-ProjectPath` | Base folder for relative paths; defaults to the current terminal folder. |
| `-FlowPath` | Optional single `.flow-meta.xml` file or folder to scan. Relative paths start at `ProjectPath`. Use this for a different package structure. |
| `-OutputPath` | Optional new file for the generated entries. Relative paths start at `ProjectPath`. Existing files are refused to avoid overwriting a manifest or Flow. |

The output is **only a list of `<members>` lines, not a complete manifest**. Do not pass that output file directly to `sf project retrieve start --manifest`.

## 3. Include the entries in your deployment preparation

Have the person managing the deployment review the results:

1. Add the generated entries inside a `<types>` section named `DigitalExperience` in the relevant retrieval/deployment manifest. Merge into an existing section if there is one.
2. Keep the manifest's existing `<version>` and other metadata sections.
3. Retrieve the listed content from the source org using that complete manifest.
4. Review the retrieved content and any additional workspace, bundle, channel, asset, or other dependencies needed in your target.
5. Ensure the content is available in the target before the flow requires it, either through a supported combined deployment or the required dependency order.
6. Validate the full deployment in a sandbox and check the content references afterward.

For the example above, the section would look like:

```xml
<types>
    <members>marketing/Default_Content_Workspace.sfdc_cms__email/MC123</members>
    <name>DigitalExperience</name>
</types>
```

This example shows the member format used by the original helper. Your org's supported metadata, API version, workspace setup, and content lifecycle requirements still apply. The generated list is not a complete CMS migration plan.

## If something looks wrong

- **No Flow files:** check that you retrieved them and selected the right folder. The script stops rather than returning an apparently successful empty scan.
- **No supported references:** the script warns. Check for dynamic references or other dependency formats manually.
- **Invalid content ID:** the script warns and excludes that value. Review the named Flow before treating the output as complete.
- **Output file already exists:** choose a new file name; the helper will not overwrite it.
- **Deployment still returns `INTERNAL_ERROR`:** check whether every referenced CMS item and its prerequisites are present, then investigate other causes. Keep the deployment ID and error details in your private project notes.

## Official background

- [Salesforce CMS developer guide](https://developer.salesforce.com/docs/platform/cms/guide/cms-developer-guide)
- [Salesforce Metadata API developer guide](https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/)

The specific `INTERNAL_ERROR` lesson above comes from deployment experience, not a general Salesforce error guarantee.
