# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [2.0.0] - 2026-08-05

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
- Import actions now exclude archived accounts (firstName ending with `_zz`) from both account and permission imports
- Updated README documentation with clearer sections and better organization
- Enhanced type conversion comments for better code readability

### Fixed

- Boolean conversion for `isAttendingPhysician` and `isPatientBound` fields now correctly parses string "true"/"false" values using `[System.Convert]::ToBoolean()` instead of `[bool]` cast (which incorrectly converted all non-empty strings to `$true`)

### Removed

- CSV mapping files from Assets folder (LocationMapping.csv, TemplateMapping.csv)
- `Get-MedicoreLocationIdsFromMapping` function
- CSV import logic from create.ps1 and update.ps1

## [1.0.0] - 06-06-2024

This is the first official release of _HelloID-Conn-Prov-Target-Medicore_. This release is based on template version _1.2.0_.

### Added

### Changed

### Deprecated

### Removed