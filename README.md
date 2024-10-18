# SPSWeather

![Latest release date](https://img.shields.io/github/release-date/luigilink/SPSWeather.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/SPSWeather/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/SPSWeather.svg?style=flat)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

## Description

SPSWeather is a PowerShell script tool designed to provide the status of your SharePoint Environment.

It's compatible with all supported versions for SharePoint OnPremises (2016 to Subscription Edition).

[Download the latest release, Click here!](https://github.com/luigilink/SPSWeather/releases/latest)

## Requirements

### Windows Management Framework 5.0

Required because this module now implements class-based resources.
Class-based resources can only work on computers with Windows
Management Framework 5.0 or above.
The preferred version is PowerShell 5.1 or higher, which ships with Windows 10 or Windows Server 2016.
This is discussed further on the [SPSWeather Wiki Getting-Started](https://github.com/luigilink/SPSWeather/wiki/Getting-Started)

## CredSSP

Impersonation is handled using the `Invoke-Command` cmdlet in PowerShell, together with the creation of a "remote" session via `New-PSSession`. In the SPSWeather script, we authenticate as the InstallAccount and specify CredSSP as the authentication mechanism. This is explained further in the [SPSWeather Wiki Getting-Started](https://github.com/luigilink/SPSWeather/wiki/Getting-Started)

## Documentation

For detailed usage, configuration, and getting started information, visit the [SPSWeather Wiki](https://github.com/luigilink/SPSWeather/wiki)

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
