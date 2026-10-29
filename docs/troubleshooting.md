# Troubleshooting

[Back to the reference index](../README.md)

| Problem | What to check first |
| --- | --- |
| `sf` is not recognized | Install Salesforce CLI, reopen PowerShell, and run `sf --version`. |
| PowerShell refuses to run a script | Ask your IT team or project owner about approved execution policies. Do not disable organization security settings to work around it. |
| A helper reports a missing .NET method | Confirm you are using PowerShell 7 rather than Windows PowerShell 5.1. |
| Login is expired or org is disconnected | Sign in again and check `sf org list`. |
| The script uses the wrong source | The retrieval helper uses the default org. Check the username it prints before continuing; set the intended default from the project folder. |
| Data Kit is not found | Check the source org, Developer Name, permissions, and whether the kit exists there. |
| API returns unauthorized / HTTP 401 | Check login and the helper's authorization implementation. The reviewed scripts contain placeholder headers. Do not hardcode tokens. |
| A command cannot find the project or manifest | Run it from the Salesforce project folder containing `sfdx-project.json`, and check the manifest path. |
| Retrieval reports a conflict | Save and compare your local changes before deciding whether to overwrite them. |
| Validation mentions missing dependencies | Check that the manifest includes required configuration and that target prerequisites exist. |
| Validation rejects `isSqlDmo` or Key Qualifier metadata | See the targeted preparation notes in [Retrieve and prepare](retrieve-and-prepare.md); do not delete unrelated configuration. |
| Lookup fields disappear after cleanup | The helper removes Lookup fields without matching local relationship metadata. Restore from your saved copy and check whether retrieval was complete. |
| Files were retrieved to another folder but cleanup seems wrong | The reviewed helper does not apply its output-directory setting to cleanup or validation. Stop and check which project files changed. |
| Metadata succeeds but components are missing | Check the separate Data Kit installation/component setup step and unsupported component types. |
| The CLI or helper times out | Check server-side job status before retrying. The operation may still be running. |
| Runtime deployment fails | Review component deployment errors, target data space, connector configuration, namespaces, and supported types. |

## When asking for help

Provide:

- The step you were attempting.
- The tool version.
- The command, with sensitive values removed.
- The error message and job ID through an approved private channel.
- Whether anything had already changed in the target.

Never attach access tokens, authentication files, full org authentication output, customer metadata, or unreviewed logs to a public issue.

## Keep these notes useful

When adding a lesson learned, include the symptom, the cause, the solution, and any limits on where it applies. Use generic example names and link to official documentation where possible.
