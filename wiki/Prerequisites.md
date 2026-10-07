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
