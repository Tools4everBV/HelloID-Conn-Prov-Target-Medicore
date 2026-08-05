# HelloID-Conn-Prov-Target-Medicore

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Medicore/blob/main/Logo.png?raw=true">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Medicore](#helloid-conn-prov-target-medicore)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account reference](#account-reference)
  - [Remarks](#remarks)
    - [Type conversions](#type-conversions)
    - [Delete behavior](#delete-behavior)
    - [Location permissions](#location-permissions)
    - [Import limitations](#import-limitations)
    - [Governance reconciliation resolutions](#governance-reconciliation-resolutions)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

HelloID-Conn-Prov-Target-Medicore is a target connector. Medicore provides a set of REST APIs that allow you to programmatically interact with its data. This connector manages user accounts in Medicore and their location assignments.

## Supported features

The following features are available:

| Feature                               | Supported | Notes                                                                                                                                         |
| ------------------------------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Account Lifecycle                     | ✅         | Create, Update, Enable, Disable. Delete is a soft-delete (updates fields instead of removing account). [Read more](#type-conversions)         |
| Permissions                           | ✅         | Locations managed via clinics endpoint. [Read more](#location-permissions)                                                                    |
| Resources                             | ❌         | Not applicable                                                                                                                                |
| Entitlement Import: Accounts          | ✅         | Limited fields available. No enabled status (hardcoded to false). Archived accounts (`_zz` prefix) excluded. [Read more](#import-limitations) |
| Entitlement Import: Permissions       | ✅         | Requires individual calls per employee. Archived accounts (`_zz` prefix) excluded. [Read more](#import-limitations)                           |
| Governance Reconciliation Resolutions | ✅         | Delete and Disable actions supported. [Read more](#governance-reconciliation-resolutions)                                                     |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Medicore/refs/heads/main/Icon.png
```

### Requirements

- Valid Medicore API credentials (username, password, client_id, client_secret)
- Medicore API subscription key (Ocp-Apim-Subscription-Key)
- API base URL and token URL
- OAuth2 password grant flow support

### Connection settings

The following settings are required to connect to the API.

| Setting                | Description                                | Mandatory |
| ---------------------- | ------------------------------------------ | --------- |
| UserName               | The UserName to connect to the API         | Yes       |
| Password               | The Password to connect to the API         | Yes       |
| client_id              | The client ID to connect to the API        | Yes       |
| client_secret          | The client secret to connect to the API    | Yes       |
| OcpApimSubscriptionKey | The subscription key to connect to the API | Yes       |
| BaseUrl                | The URL to the API                         | Yes       |
| TokenUrl               | The URL to generate the bearer token       | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within Medicore to a person in HelloID.

| Setting                   | Value                           |
| ------------------------- | ------------------------------- |
| Enable correlation        | True                            |
| Person correlation field  | PersonContext.Person.ExternalId |
| Account correlation field | hrNumber                        |

> [!TIP]
> For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages.

### Field mapping

The field mapping can be imported by using the `fieldMapping.json` file.

### Account reference

The account reference is populated with the `hrNumber` property from Medicore.

## Remarks

### Type conversions

Due to the limitations of the field mapping, which can only return strings or an array of strings, type conversions are performed in the lifecycle scripts for the following properties:

- `gender` - converted to integer
- `isAttendingPhysician` - converted to boolean
- `isPatientBound` - converted to boolean

These conversions are required by the Medicore API to accept the data correctly.

### Delete behavior

The delete action does **not** perform a hard delete. Instead, it performs a soft-delete by updating specific account fields:

- `firstName` - prefixed with `_zz` to mark archived employees (e.g., `_zzJohn`)
- `email` - set to empty string to free up unique values for reuse
- `username` - set to empty string to free up unique values for reuse

This approach allows archived employees to be recognized in the system while releasing their unique identifiers (email and username) for potential reassignment to new employees.

> [!IMPORTANT]
> Archived accounts (with `_zz` prefix in firstName) are automatically filtered out during both account and permission imports. This ensures deleted employees are not imported back into HelloID.

> [!WARNING]
> Because delete is implemented as an update operation, the account remains in Medicore but with modified field values. This is not a true deletion.

### Location permissions

- Location permissions use the `/clinics` endpoint (clinics and locations are the same in Medicore)
- Each person can be assigned to multiple locations

### Import limitations

The import action has significant limitations:

**Account Import:**
- Only the fields `id`, `name`, `hrNumber`, and `isInternalAccount` are returned by the GET all employees endpoint
- No enabled/disabled status is available in the import data - the `Enabled` property is hardcoded to `false` for all imported accounts
- If more fields are needed, individual GET calls for each employee would be required
- This approach is not recommended as it significantly increases runtime, especially with large numbers of accounts
- Preferably, the Medicore API should be updated to include required fields in the bulk endpoint
- Archived accounts (names ending with `_zz`) are automatically excluded from import

**Permissions Import:**
- All employees must be retrieved first, then individual GET calls are made for each employee to retrieve their location assignments
- This is required because there is no endpoint to retrieve assigned locations per location
- This may impact performance with large numbers of accounts
- Archived accounts (names ending with `_zz`) are automatically excluded from import

> [!NOTE]
> We do not advise fetching individual employee details due to performance concerns. Consider requesting API enhancements from Medicore for optimal import performance.

### Governance reconciliation resolutions

The connector supports Governance Reconciliation Resolutions for **Delete** and **Disable** actions. These actions can be triggered from governance workflows where no person context is available.

**Enforcement vs Reconciliation Mode:**

- **Enforcement mode**: Triggered by normal workflows. Uses field mapping with full person context available.
- **Reconciliation mode**: Triggered by governance resolutions. Uses hardcoded values because no person context is available.

**Hardcoded values for reconciliation:**

| Action  | Field(s) Updated                 | Values                                            |
| ------- | -------------------------------- | ------------------------------------------------- |
| Delete  | `firstName`, `email`, `username` | Prefix firstName with `_zz`, clear email/username |
| Disable | `dateOutOfService`               | Set to current date (YYYY-MM-DD)                  |

> [!IMPORTANT]
> Reconciliation mode applies hardcoded field values to ensure accounts can be managed through governance workflows without requiring person context. These values differ from enforcement mode which uses the full field mapping.

## Development resources

### API endpoints

The following endpoints are used by the connector:

| Endpoint        | Method     | Description                          |
| --------------- | ---------- | ------------------------------------ |
| /oauth2/token   | POST       | Retrieve access token                |
| /employees      | GET, POST  | Retrieve and create employee records |
| /employees/{id} | GET, PATCH | Get and update specific employee     |
| /clinics        | GET        | Retrieve location/clinic information |

## Getting help

> [!TIP]
> For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
