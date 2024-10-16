# Configuration

To customize the script for your environment, you need to prepare a JSON configuration file. Below is a sample structure for the file:

```json
{
  "$schema": "http://json-schema.org/schema#",
  "contentVersion": "1.0.0.0",
  "ConfigurationName": "PROD",
  "ApplicationName": "contoso",
  "Domain": "contoso.com",
  "SMTPToAddress": ["admin-farm@contoso.com", "admin-setup@contoso.com"],
  "SMTPFromAddress": "noreply@contoso.com",
  "SMTPServer": "smtp.contoso.com",
  "StoredCredential": "PROD-ADM",
  "ExclusionRules": [
    "SPSiteHttpStatus",
    "EvtViewerStatus",
    "IISW3WPStatus",
    "WSPStatus"
  ],
  "Farms": [
    {
      "Name": "SEARCH",
      "Server": "srvcontososearch"
    },
    {
      "Name": "SERVICES",
      "Server": "srvcontososervices"
    },
    {
      "Name": "CONTENT",
      "Server": "srvcontosocontent"
    }
  ]
}
```

## Configuration and Application

`ConfigurationName` is used to populate the content of `Environment` PowerShell Variable.
`ApplicationName` is used to populate the content of `Application` PowerShell Variable.

## SMTP settings

Use `SMTPToAddress`, `SMTPFromAddress` and `SMTPServer` parameters to configure your SMTP settings in your environment

## Credential Manager

`StoredCredential` is refered to the target of your credential that you used during the installation processus.

## ExclusionRules

The `ExclusionRules` parameter can be used to exclude some check during the script execution. The default values are `SPSiteHttpStatus`, `EvtViewerStatus`, `IISW3WPStatus` and `WSPStatus`.

The authorized values are : `None`, `APIHttpStatus`, `SPSiteHttpStatus`, `EvtViewerStatus`, `IISW3WPStatus`, `HealthStatus`, `WSPStatus` and `FailedTimerJob`

## Farms settings

In the context of trusted farm you can check the health of each farm.

> [!IMPORTANT]
> You need to use the same service account to use the farms parameter

## Next Step

For the next steps, go to the [Usage](./Usage) page.
