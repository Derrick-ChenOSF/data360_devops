# Getting started

[Back to the reference index](../README.md)

## A few useful terms

| Term | Plain-language meaning |
| --- | --- |
| Org | A Salesforce environment, such as a sandbox or production |
| Source | The environment you are copying configuration from |
| Target | The environment you are copying configuration to |
| Alias | A short name you assign to an org, such as `source-sandbox` |
| Metadata | Configuration files, rather than the business records stored in Salesforce |
| Data Kit | A collection of Data Cloud configuration intended for reuse or deployment |
| Manifest | An XML file listing the metadata you want to retrieve or deploy |
| Validation / dry run | A deployment check that does not save the proposed metadata changes |

Retrieving a Data Kit is not a backup or transfer of all customer data.

## What you need

- Access to the source and target orgs, with permissions for the work you need to do.
- Salesforce CLI installed on your computer.
- PowerShell. If using the existing helper scripts, use PowerShell 7; some use newer .NET functions.
- A Salesforce project folder containing `sfdx-project.json`.
- The Data Kit's Developer Name, also called its API name.
- Any required target Data Cloud connections and data spaces identified with your administrator.

If these are not already set up, ask the project owner to help. This reference repository does not include a Salesforce project or customer metadata.

## Check Salesforce CLI

Open PowerShell and run:

```powershell
sf --version
```

If the command is not recognized, use the [Salesforce CLI installation instructions](https://developer.salesforce.com/tools/salesforcecli) and reopen your terminal.

## Sign in to your orgs

These examples open a browser for login. Use your own login details.

For a sandbox:

```powershell
sf org login web --alias source-sandbox --instance-url https://test.salesforce.com
```

For another sandbox that will receive the configuration:

```powershell
sf org login web --alias target-sandbox --instance-url https://test.salesforce.com
```

Your organization may require a specific My Domain login URL instead. Ask your administrator if the standard login does not work.

List your connections:

```powershell
sf org list
```

Check the alias, username, and environment before proceeding. An alias is just a name; calling an org `target-sandbox` does not prove it is a sandbox.

Do not share authentication output, access tokens, or saved login files.

## Open your project folder

```powershell
Set-Location "C:\Projects\YourSalesforceProject"
```

Replace this path with your project location. Confirm that `sfdx-project.json` is present.

Save or back up existing work before retrieving metadata. Retrieval can change local files.

Next: [Retrieve and prepare a Data Kit](retrieve-and-prepare.md).
