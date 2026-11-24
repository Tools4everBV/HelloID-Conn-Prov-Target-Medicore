# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [2.0.0] - 2026-11-24

### Added

- Governance Reconciliation Resolutions support for Delete and Disable lifecycle actions
- Permissions subfolder structure (`/permissions/locations/`) for location management with dedicated scripts (grantPermission, revokePermission, permissions, importPermissions)
- Comprehensive README documentation with modern template structure including:
  - Supported features table with detailed notes
  - HelloID Icon URL section
  - Detailed remarks sections (Type conversions, Delete behavior, Location permissions, Import limitations, Governance reconciliation)
  - API endpoints reference table

### Changed

- **BREAKING**: Replaced CSV mapping files (LocationMapping.csv, TemplateMapping.csv) with field mapping in create.ps1 and update.ps1
- **BREAKING**: Removed `Get-MedicoreLocationIdsFromMapping` function and CSV-based template/location lookups
- **BREAKING**: Location functionality moved from lifecycle scripts to dedicated permissions subfolder
- Delete action now performs soft-delete (updates firstName with `_zz` prefix, clears email/username) instead of hard delete
- Account import now excludes accounts without `hrNumber`, as accounts can only be managed by `hrNumber`
- The filter for archived accounts (`_zz`) in the account and permission imports is optional and disabled by default, so archived accounts can be correlated during the initial implementation. Enable it after go-live when Governance Reconciliation is used, so deleted accounts no longer return in reconciliation reports (see README)
- Field mapping uses a `MicrosoftEntraID` placeholder instead of a customer-specific `Person.Accounts` GUID for `email` and `username`, and the `agbCode`, `dateOfBirth`, `email` and `username` descriptions document their requirements
- README documents the `hrNumber` requirement and cleanup, the username behavior with SSO, error code MG21 (missing date of birth), the API concurrency requirement (concurrent actions must be 1) and the delete behavior for `username`
- Updated README documentation with clearer sections and better organization
- Enhanced type conversion comments for better code readability
- Improved update comparison logic in update.ps1, enable.ps1, disable.ps1, and delete.ps1 to normalize null and empty string values, preventing false change detections
- Enhanced configuration.json with descriptive placeholders and improved field descriptions

### Fixed

- Location permission import log in permissions.ps1 showed an empty `groupGuid`, it now shows the location id
- Description of `lastName` in the field mapping now matches the mapping for name convention PB (own name)
- README name field logic now describes the full display order including the prefixes and that Medicore has no field for name usage
- Documented the maximum length of 6 characters of `abbreviation` in the field mapping description and the README
- `phoneMobile` is now mapped to `Person.Contact.Business.Phone.Mobile` instead of the fixed business phone number. Existing implementations that rely on the fixed number should keep their own mapping, as an update changes the phone number of existing accounts
- `isAttendingPhysician` and `isPatientBound` are now mapped for Create only, so values changed manually in Medicore are no longer reset by an update
- Correlation audit log in create.ps1 shows the email of the correlated account instead of the empty username, and the employee uri no longer contains a redundant sub-expression
- Boolean conversion for `isAttendingPhysician` and `isPatientBound` fields now correctly parses string "true"/"false" values using `[System.Convert]::ToBoolean()` instead of `[bool]` cast (which incorrectly converted all non-empty strings to `$true`)
- Corrected field update limitations documentation: only `username` field cannot be updated (API limitation), all other fields including `dateOfBirth`, `dateInService`, and `templateId` can be updated

### Removed

- Commented-out code from enable.ps1, update.ps1, disable.ps1 and delete.ps1
- CSV mapping files from Assets folder (LocationMapping.csv, TemplateMapping.csv)
- `Get-MedicoreLocationIdsFromMapping` function
- CSV import logic from create.ps1 and update.ps1

## [1.0.0] - 06-06-2024

This is the first official release of _HelloID-Conn-Prov-Target-Medicore_. This release is based on template version _1.2.0_.

### Added

### Changed

### Deprecated

### Removed