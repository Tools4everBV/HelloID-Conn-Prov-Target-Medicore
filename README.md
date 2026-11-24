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
    - [Username](#username)
    - [Error code MG21](#error-code-mg21)
    - [API concurrency](#api-concurrency)
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
| Entitlement Import: Accounts          | ✅⚠️        | Limited fields available. No enabled status (hardcoded to false). Accounts without `hrNumber` excluded. Archived accounts (`_zz`) optionally excluded. [Read more](#import-limitations) |
| Entitlement Import: Permissions       | ✅⚠️        | Requires individual calls per employee. Accounts without `hrNumber` excluded. Archived accounts (`_zz`) optionally excluded. [Read more](#import-limitations)                           |
| Governance Reconciliation Resolutions | ✅⚠️        | Delete and Disable actions supported. [Read more](#governance-reconciliation-resolutions)                                                     |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Medicore/refs/heads/main/Icon.png
```

### Requirements

Before implementing this connector, ensure the following requirements are met:

**API Access from Medicore:**
The client must request API access from Medicore. The API must be made available by Medicore as **API version 1** (`/hrintegration/v1`), as the v2 endpoints are not functional. Medicore will provide the following credentials and endpoints:
- **UserName** - OAuth2 username for password grant authentication
- **Password** - Password for the API user
- **client_id** - OAuth2 client ID for API authentication  
- **client_secret** - OAuth2 client secret for API authentication
- **Ocp-Apim-Subscription-Key** - Medicore API subscription key (required header)
- **BaseUrl** - Base URL for Medicore API v1 endpoints (must end with `/hrintegration/v1`)
- **TokenUrl** - OAuth2 token endpoint URL for obtaining access tokens

**Medicore System Requirements:**
- All Medicore accounts that must be managed by HelloID need a populated `hrNumber` field (shown as HRM reference in Medicore). This field is **required** and is the only supported correlation field. **The connector cannot be implemented without this field.** If hrNumber is not (correctly) populated in Medicore, it must be (correctly) populated before implementation can proceed.
  - Accounts without `hrNumber` cannot be correlated or managed. They are excluded from the account and permission imports, and a create for a matching person would try to create a new account instead of correlating to the existing one.
  - `hrNumber` is not editable in the Medicore UI. Ask Medicore support to fill it for the existing accounts with a one-time load through the API, for example from the external id field or based on the email address.
- Every employee needs a date of birth in Medicore, otherwise the API blocks updates with the generic error [MG21](#error-code-mg21).

**Source System Requirements:**
- The `agbCode` field must be available from the source system (e.g., HR system) and must be exactly 8 characters long. This field is **required** for account management in Medicore. **The connector cannot be implemented without this field.** If agbCode is not available from the source system, it must be made available before implementation can proceed.
- The `templateId` must be determined for each account. This is a **required** field when creating accounts in Medicore. Organizations with a single template can use a fixed value in the field mapping. Organizations with multiple templates must establish logic to determine which persons receive which template ID.

**Technical Requirements:**
- **Concurrent actions of the target system in HelloID must be set to 1.** The Medicore API accepts only one concurrent action. HelloID runs actions in parallel by default, so with a higher setting requests overlap and exceed this limit. See [API concurrency](#api-concurrency).

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

> [!IMPORTANT]
> Correlation **must** use the `hrNumber` field. This is the only supported correlation field because the Medicore API is built around hrNumber - all GET operations for individual employees use `/employees/{hrnumber}`. Correlation on any other field is not supported by the API.

> [!NOTE]
> Medicore accounts without `hrNumber` are not correlated and not managed. Fill the `hrNumber` for these accounts first (see [Requirements](#requirements)). The `username` and `email` cannot be used for correlation: the GET employee endpoint only accepts the `hrNumber`, and the list endpoint does not return the `username`.

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
> The `abbreviation` field has a maximum length of 6 characters. It is typically populated with the employee's personnel number (hrNumber) rather than a name abbreviation, as this provides a more unique and stable identifier. If the personnel number can be longer than 6 characters, use another unique source value.

> [!IMPORTANT]
> The `agbCode` field is **required** for account management in Medicore. Without an agbCode, accounts cannot be managed. This field must be available from the source system.

### Name field logic

Medicore has no field for name usage (the HelloID name convention). The name of an employee is determined by the combination of four fields:

- **lastName** + **lastNamePrefix**: the surname with prefix (tussenvoegsel), for example "van den Boele"
- **partnerName** + **partnerNamePrefix**: the partner name with prefix, for example "de Vries"

**Display logic:**  
The Medicore UI always displays names as: `[partnerNamePrefix] [partnerName] [lastNamePrefix] [lastName]`

When `partnerName` is filled, it is **always displayed first**, followed by the surname. The four fields must therefore be filled conditionally, based on the name convention of the person (`Person.Name.Convention`).

**Name convention mapping:**

| Convention | Meaning       | Desired display          | lastName (+ prefix)   | partnerName (+ prefix) | Medicore display         |
| ---------- | ------------- | ------------------------ | --------------------- | ---------------------- | ------------------------ |
| B          | Birth name    | "van den Boele"          | van den Boele (birth) | *(empty)*              | "van den Boele"          |
| P          | Partner name  | "de Vries"               | de Vries (partner)    | *(empty)*              | "de Vries"               |
| BP         | Birth-Partner | "van den Boele-de Vries" | de Vries (partner)    | van den Boele (birth)  | "van den Boele de Vries" |
| PB         | Partner-Birth | "de Vries-van den Boele" | van den Boele (birth) | de Vries (partner)     | "de Vries van den Boele" |

**Key points:**
- For conventions **B** and **P**: leave `partnerName` and `partnerNamePrefix` empty, as only one name is displayed.
- For conventions **BP** and **PB**: the birth and partner names are swapped between `lastName` and `partnerName`, so the display order is correct.
- Each prefix belongs to its own name: `lastNamePrefix` to `lastName`, `partnerNamePrefix` to `partnerName`.
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
- `username` - set to empty string, but the Medicore API ignores this (see [Username](#username))

This approach allows archived employees to be recognized in the system while releasing the email address for reuse. The username cannot be released through the API.

> [!IMPORTANT]
> Archived accounts (with `_zz` prefix in firstName) are **not** filtered out of the account and permission imports by default, so they can be correlated and put under management during the initial implementation. After go-live, when Governance Reconciliation is used, enable the optional archived account filter. See [Archived accounts](#archived-accounts).

> [!WARNING]
> The delete action does not change `dateOutOfService`. An archived account stays active in Medicore when it was not disabled first, so the disable must run before the delete (for example in the Business Rule).

> [!WARNING]
> Because delete is implemented as an update operation, the account remains in Medicore but with modified field values. This is not a true deletion.

### Username

- Medicore requires a unique `username` when an account is created. When Medicore uses SSO the `username` has no function, the email address is leading for logging in.
- The `username` can only be set on create. PUT requests to update it do not return an error but the value is not updated, so the username cannot be cleaned up when an employee leaves.
- Map a value that is unique and stable, for example the object id of the Entra ID account. A username that can be generated again for a future employee with the same name causes a conflict when the account is created. Accounts that were created before the integration can contain a legacy username that Medicore support can clean up once.
- The `username` is not returned by the GET all employees endpoint. It is available in the GET employee endpoint (`/employees/{hrNumber}`) as `user.name`.
- The `email` can be updated, and is cleared by the delete action.

### Error code MG21

MG21 is a generic Medicore error code for an unexpected error, comparable to an HTTP 404. A known cause is an employee without a date of birth: Medicore validates this in the background and blocks changes through the API. Fill the date of birth in Medicore (and in the source system) to resolve the error.

### API concurrency

The Medicore API has a concurrent action limit of 1: it handles one action at a time. HelloID runs multiple actions in parallel by default, which would exceed this limit, so the concurrent actions setting of the target system in HelloID **must be 1**. As a result actions are processed one after another and large bulk runs (for example the first enforcement or an import) take a while.

### Location permissions

- Location permissions use the `/clinics` endpoint (clinics and locations are the same in Medicore)
- Each person can be assigned to multiple locations

### Import limitations

The import action has significant limitations:

**Account Import:**
- Only the fields `id`, `name`, `hrNumber`, and `isInternalAccount` are returned by the GET all employees endpoint
- The `username` field is **not included** in the bulk endpoint response - individual GET calls would be required
- Accounts without `hrNumber` are excluded from the import, as accounts can only be managed by `hrNumber`
- No enabled/disabled status is available in the import data - the `Enabled` property is hardcoded to `false` for all imported accounts
- If more fields are needed, individual GET calls for each employee would be required
- This approach is not recommended as it significantly increases runtime, especially with large numbers of accounts
- Preferably, the Medicore API should be updated to include required fields in the bulk endpoint
- Archived accounts can optionally be excluded from the import, see [Archived accounts](#archived-accounts)

**Permissions Import:**
- All employees must be retrieved first, then individual GET calls are made for each employee to retrieve their location assignments
- This is required because there is no endpoint to retrieve assigned locations per location
- Accounts without `hrNumber` are excluded, as the `hrNumber` is required to retrieve the employee and is used as the account reference
- Archived accounts can optionally be excluded from the import, see [Archived accounts](#archived-accounts)

#### Archived accounts

The delete action archives an account in Medicore (see [Delete behavior](#delete-behavior)). The import scripts (`import.ps1` and `permissions/locations/importPermissions.ps1`) contain a filter for archived accounts that is **commented out by default**.

| Phase                                                  | Filter       | Why                                                                                                                                                                                                                       |
| ------------------------------------------------------ | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Initial implementation                                 | Disabled     | Archived accounts are imported, so they can be correlated and put under management.                                                                                                                                         |
| After go-live, when Governance Reconciliation is used  | **Enabled**  | HelloID treats archived accounts as deleted. Without the filter they are imported as accounts without an owner and keep returning in every reconciliation report.                                                          |

To enable the filter, remove the comment characters from the three lines below the comment `Optional: filter out 'archived' accounts` in both import scripts.

> [!WARNING]
> The filter checks the `name` returned by the GET all employees endpoint for the `_zz` marker. Verify how the `name` is composed for an archived account (the delete action prefixes the `firstName`) before enabling the filter, and adjust the check when needed.

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
| Delete  | `firstName`, `email`, `username` | Prefix firstName with `_zz`, clear email/username (the API ignores the username, see [Username](#username)) |
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
| /employees/{id} | GET, PUT   | Get and update specific employee     |
| /clinics        | GET        | Retrieve location/clinic information |

## Getting help

> [!TIP]
> For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
