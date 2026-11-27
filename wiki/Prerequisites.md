# Prerequisites

SPSWeather runs from a single host (a SharePoint server, or a dedicated
orchestration / PULL server) and reaches every farm over a CredSSP PSSession.

## Host requirements

- **Windows** with PowerShell 5.1 (or PowerShell 7+).
- **Local administrator**: SPSWeather must run elevated. The entry script enforces
  this and stops otherwise. It is required to write the scheduled task, the event-log
  source, and the CredSSP client configuration.
- The `SPSWeather.Common` module shipped in `src\Modules\` (no external module needed;
  the former CredentialManager dependency was dropped in 3.0.0).

## The service account

One account runs the scheduled task and opens every remote session, so it needs the rights of the layers that SPSWeather reads. **I use the SharePoint farm account**, and I suggest it: it already holds most of what the table below asks for. **Check the table against your own farm**, because SharePoint does not grant all of it by itself. Microsoft's description of the [farm service account](https://learn.microsoft.com/en-us/sharepoint/install/initial-deployment-administrative-and-service-accounts-in-sharepoint-server) says that SharePoint gives it additional permissions on the farm servers and a SQL Server login with the `dbcreator` and `securityadmin` server roles and `db_owner` on the SharePoint databases. Membership of the local Administrators group is asked of the *farm administrator* account that runs Setup, and `VIEW SERVER STATE` is not in that list. On my farms the account is also a local administrator, which is why nothing had to be added. Another account works if it has the rights of the table.

| Layer | What SPSWeather needs from the account |
|---|---|
| The run server | Member of the local Administrators (the script runs elevated and stops otherwise); the task is registered with its password and runs with the highest privileges |
| Each farm server | A remote session over CredSSP, and the rights to run the SharePoint cmdlets (`SharePointServer` module), to read IIS and to read the system information of the server |
| SQL Server | Windows authentication (integrated security): at least `VIEW SERVER STATE` and read access to `master` and `msdb`. A SQL instance that cannot be queried is reported as a failed `Query failed` row, and the other instances are still checked |
| The dashboard folder or share | Write access, if `Dashboard.OutputPath` is set |

Use the **same account for every farm** of a configuration. The credential is stored in `Config\secrets.psd1` (see [Configuration](Configuration)), encrypted with DPAPI for that account on that machine.

## What the script changes on the run server

SPSWeather is not read-only on the machine that runs it. Every run that starts elevated:

- sets the Windows **power plan to High Performance** (`powercfg /s`). I do it in all my scripts because the servers are always-on virtual machines. It applies to every action, including `-Action Install` and `-Action Uninstall`;
- creates the `SPSWeather` **Windows Event Log** source on first use.

`-Action Install` also registers the **scheduled task**, stores the secret in `Config\secrets.psd1` and configures the **CredSSP client** (see below). `-Action Uninstall` removes the task and the secret and leaves the CredSSP client configuration in place. Nothing is changed on the farm servers, in IIS or in SQL Server: the checks only read.

## CredSSP

SPSWeather uses CredSSP to perform the double hop (the health-check host → each farm
server → SQL). CredSSP has **two sides**:

| Side | Where | Managed by |
|---|---|---|
| **Client** | the host that runs SPSWeather | **SPSWeather** (`-Action Install`) |
| **Server** | each SharePoint farm server | **your DSC** on the farms |

### Client side (handled by SPSWeather)

Running `-Action Install` calls `Set-SPSCredSSPClient`, which:

- enables CredSSP **client** authentication (WSMan), and
- allows fresh-credentials delegation to the **precise farm FQDNs** derived from
  `Farms[].Server` + `Domain` in your config (e.g. `WSMAN/app1.contoso.com`).

It is idempotent and supports `-WhatIf`. When those settings are controlled by a
Group Policy it warns and leaves the GPO in charge instead of fighting it.

> Re-run `-Action Install` after adding a farm so the new server FQDN is delegated.
> `-Action Uninstall` leaves the CredSSP client configuration in place (other tools
> on the host may rely on it).

This is why SPSWeather can run from a host that is **not** a SharePoint server: it no
longer depends on a DSC resource to configure the client side.

### Server side (handled by your DSC)

Each SharePoint farm server must have the CredSSP **server** role enabled
(`Enable-WSManCredSSP -Role Server`). This is part of the farm's own configuration and
stays owned by your DSC — SPSWeather does not change it.

## Looking ahead: a CredSSP-free path

CredSSP is convenient but delegates the caller's credentials to the target. A future,
more secure option for the double hop is **Kerberos resource-based constrained
delegation (RBCD)**, which does not delegate the password and is scoped per target.
It is tracked as a backlog item; CredSSP remains the supported path today.
