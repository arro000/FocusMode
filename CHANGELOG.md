# Changelog

All notable changes to FocusMode will be documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Protected applications are now entirely user-defined. FocusMode no longer ships built-in third-party defaults, and macOS system apps remain protected automatically.
- Removed outdated screenshots from the README.

## [1.1.0] - 2026-08-04

### Added

- Added a complete open-source project presentation and contribution workflow.
- Added XCTest coverage for application ordering, profiles, protections, localization, and persistence.

### Changed

- Rebranded the application and package as FocusMode.
- Selected applications are grouped at the top of profile and global protection lists.
- Added a visual separator and localized label for selected applications.
- CI now runs the test suite with code coverage enabled.

### Fixed

- Prevented SwiftUI checklist rows from retaining a stale checked state when an application moves between selected and unselected groups.

## [1.0.0] - 2026-08-04

### Added

- Restorable focus sessions using polite macOS quit requests.
- One-shot cleanup without session retention.
- Configurable exclusion profiles.
- Localizations for nine languages.
- User-configurable protection for applications that should stay open.
