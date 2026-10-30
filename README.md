# Data360 DevOps Notes

A small reference library for moving Salesforce Data Cloud (Data 360) configuration between environments.

This is a place to keep practical steps, useful commands, lessons learned, and a few optional PowerShell helpers. There are no GitHub workflows or release pipelines.

## Start here

| Guide | What it helps you do |
| --- | --- |
| [Getting started](docs/getting-started.md) | Understand the terms, check your tools, and sign in |
| [Retrieve and prepare a Data Kit](docs/retrieve-and-prepare.md) | Download configuration and review it before deployment |
| [Validate and deploy](docs/validate-and-deploy.md) | Check the target, deploy metadata, and complete Data Kit setup |
| [Troubleshooting](docs/troubleshooting.md) | Recognize common problems and decide what to check |
| [Script guides](docs/scripts.md) | Use the included retrieval, runtime deployment, and comparison helpers |
| [Flow CMS dependencies](docs/flow-cms-dependencies.md) | Find CMS references needed for Marketing Cloud Next flow deployments |

## The basic process

1. Retrieve configuration from the **source** environment.
2. Review and prepare the downloaded files.
3. Validate them against the **target** environment.
4. Deploy the metadata.
5. Complete any required Data Kit component setup.
6. Check the result in Salesforce.

**A successful metadata deployment does not necessarily mean your Data Cloud setup is ready to use.** Connections, component creation, permissions, and other environment-specific steps may still be needed.

## What belongs here

- Generic instructions and commands with example names.
- Lessons learned, with their limitations explained.
- Links to official documentation.
- Generic helper scripts, with usage guides and limitations.

Keep customer metadata, customer names, org URLs, passwords, access tokens, authentication files, and raw deployment logs in the appropriate private project, not here.

## Using the examples

Commands use Windows PowerShell. Replace example org aliases and file names with your own values. Run project commands from your **Salesforce project**, not from this reference repository.

Try the process in a sandbox first. Follow your team's approval process before changing production.

## Official reference

- [Salesforce CLI command reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [Salesforce Data Cloud developer documentation](https://developer.salesforce.com/docs/data/data-cloud-dev/guide/)

Command behavior and supported metadata can change. Check the current documentation when your installed version behaves differently.