# SPSWeather Wiki

**SPSWeather** is a PowerShell tool that produces a health-check report of a SharePoint Server farm and emails it to administrators. It is compatible with all supported on-premises versions of SharePoint Server (2016 to Subscription Edition).

SPSWeather connects to each farm server over **CredSSP remoting**, collects SharePoint, Search, system/IIS and SQL signals, renders a single **HTML report optimized for email**, and raises an **ALERT** when something needs attention.

## Key features

- Configurable farm health checks (SharePoint, Search, IIS, system, SQL)
- HTML report optimized for email, delivered over SMTP
- Configuration as a PowerShell data file (`config.psd1`)
- Service credential stored as a DPAPI-encrypted `secrets.psd1` — no third-party module
- Windows Event Log instrumentation (dedicated `SPSWeather` log)
- Self-contained `SPSWeather.Common` PowerShell module (manifest-driven version)

## Architecture overview

```
        SPSWeather.ps1  (entry point, scheduled task)
               │  imports
               ▼
        SPSWeather.Common  (PowerShell module: Public/ + Private/)
               │  CredSSP remoting (Invoke-Command / New-PSSession)
               ▼
   Each SharePoint farm server  ──►  HTML report  ──►  SMTP mailbox
```

The credential used for remoting is read from `Config\secrets.psd1` (DPAPI), and every run writes lifecycle entries to the `SPSWeather` Windows Event Log.

## Pages

- [Getting Started](Getting-Started) — prerequisites, installation, first run
- [Configuration](Configuration) — `config.psd1` and `secrets.psd1` explained
- [Usage](Usage) — parameters, scheduling, output and the event log
- [Release Process](Release-Process) — for maintainers: how to ship a new version

## Project links

- [Source repository](https://github.com/luigilink/SPSWeather)
- [Latest release](https://github.com/luigilink/SPSWeather/releases/latest)
- [Issues](https://github.com/luigilink/SPSWeather/issues)
- [Changelog](https://github.com/luigilink/SPSWeather/blob/main/CHANGELOG.md)
