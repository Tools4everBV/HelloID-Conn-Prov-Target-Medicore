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
    - [Name field logic](#name-field-logic)
    - [Update comparison logic](#update-comparison-logic)
    - [Delete behavior](#delete-behavior)
    - [Location permissions](#location-permissions)
    - [Import limitations](#import-limitations)
    - [API version](#api-version)
    - [Field update limitations](#field-update-limitations)
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
| Entitlement Import: Accounts          | ✅⚠️        | Limited fields available. No enabled status (hardcoded to false). Archived accounts (`_zz` prefix) excluded. [Read more](#import-limitations) |
| Entitlement Import: Permissions       | ✅⚠️        | Requires individual calls per employee. Archived accounts (`_zz` prefix) excluded. [Read more](#import-limitations)                           |
| Governance Reconciliation Resolutions | ✅⚠️        | Delete and Disable actions supported. [Read more](#governance-reconciliation-resolutions)                                                     |

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

| Setting                | Description                                                                                      | Mandatory | Example                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------ | --------- | -------------------------------------------------------------------------------------------- |
| UserName               | The username for OAuth2 password grant authentication. Provided by Medicore.                     | Yes       | `hello_id_integration`                                                                       |
| Password               | The password for the API username. Provided by Medicore.                                         | Yes       | `(secret)`                                                                                   |
| client_id              | The OAuth2 client ID for API authentication. Provided by Medicore.                               | Yes       | `api_hello_id`                                                                               |
| client_secret          | The OAuth2 client secret for API authentication. Provided by Medicore.                           | Yes       | `(secret)`                                                                                   |
| OcpApimSubscriptionKey | The Medicore API subscription key (Ocp-Apim-Subscription-Key header). Provided by Medicore.         | Yes    | `(secret)`                                                                                   |
| BaseUrl                | The base URL for Medicore API v1 endpoints. Must use `/hrintegration/v1` path.                  | Yes       | `https://{api-gateway}.azure-api.net/hrintegration/v1`                                       |
| TokenUrl               | The OAuth2 token endpoint URL for obtaining access tokens. Provided by Medicore.                 | Yes       | `https://{identity-server}/auth/realms/{realm}/protocol/openid-connect/token`               |

> [!TIP]
> The Medicore API uses OAuth2 **password grant flow**, requiring both username/password credentials AND client_id/client_secret.

**URL Format:**
- **BaseUrl:** Always ends with `/hrintegration/v1` (API version 1). The hostname will be provided by Medicore.
- **TokenUrl:** Format is `https://{identity-server}/auth/realms/{realm}/protocol/openid-connect/token` where `{realm}` is your environment-specific realm name provided by Medicore

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

- `gender` - converted to integer (1 = Male, 2 = Female)
- `templateId` - converted to integer
- `isAttendingPhysician` - converted to boolean
- `isPatientBound` - converted to boolean

These conversions are required by the Medicore API to accept the data correctly.

> [!NOTE]
> The `abbreviation` field is typically populated with the employee's personnel number (hrNumber) rather than a name abbreviation, as this provides a more unique and stable identifier.

### Name field logic

Medicore uses four separate name fields to support full name display:

- **lastName** + **lastNamePrefix**: The surname displayed in the system
- **partnerName** + **partnerNamePrefix**: The partner's name displayed before lastName

**Display logic:**  
The Medicore UI always displays names as: `[partnerName] [lastName]`

When a `partnerName` is provided, it will **always be displayed first**, followed by the `lastName`.

**Name convention mapping:**

| Convention | Meaning           | Desired display    | lastName            | partnerName         | Medicore Display       |
|-----------|-------------------|--------------------|--------------------|---------------------|------------------------|
| B         | Birth name        | "Jansen"           | Jansen (birth)     | *(empty)*           | "Jansen"               |
| P         | Partner name      | "de Vries"         | de Vries (partner) | *(empty)*           | "de Vries"             |
| BP        | Birth-Partner     | "Jansen-de Vries"  | de Vries (partner) | Jansen (birth)      | "Jansen de Vries"      |
| PB        | Partner-Birth     | "de Vries-Jansen"  | Jansen (birth)     | de Vries (partner)  | "de Vries Jansen"      |

**Key points:**
- For conventions **B** and **P**: Leave `partnerName` and `partnerNamePrefix` empty
- For conventions **BP** and **PB**: Swap the birth and partner names between `lastName` and `partnerName` to achieve the correct display order
- The prefix (tussenvoegsel) always follows its corresponding surname

### Update comparison logic

The update, enable, disable, and delete scripts use a normalized comparison approach to detect actual changes:

- **Null and empty string equivalence**: Both `null` and `""` (empty string) are treated as equivalent to prevent false change detections
- **Type normalization**: All values are converted to strings before comparison to handle type differences (e.g., `1` vs `"1"`)
- **Comparison method**: Uses PowerShell's `Compare-Object` on normalized properties to detect differences

This approach ensures that only genuine content changes trigger updates, preventing unnecessary API calls when field mapping returns empty strings for null values or when type representations differ.

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
- The `username` field is **not included** in the bulk endpoint response - individual GET calls would be required
- No enabled/disabled status is available in the import data - the `Enabled` property is hardcoded to `false` for all imported accounts
- If more fields are needed, individual GET calls for each employee would be required
- This approach is not recommended as it significantly increases runtime, especially with large numbers of accounts
- Preferably, the Medicore API should be updated to include required fields in the bulk endpoint
- Archived accounts (names ending with `_zz`) are automatically excluded from import

**Permissions Import:**
- All employees must be retrieved first, then individual GET calls are made for each employee to retrieve their location assignments
- This is required because there is no endpoint to retrieve assigned locations per location

### API version

This connector uses Medicore API **v1** endpoints:
- `/hrintegration/v1/employees` - Used for account management
- `/hrintegration/v1/employees/{id}/clinics` - Used for location permissions

> [!WARNING]
> Medicore API v2 endpoints return 404 errors and are not functional. Ensure all integrations use v1 endpoints.

### Field update limitations

**Known API issues:**
- `username` - PUT requests to update this field do not return errors but the value is not actually updated in Medicore
- This appears to be a Medicore API limitation

**UI restrictions:**
- `hrNumber` (HRM reference) is not manually editable in the Medicore UI, only via API

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
