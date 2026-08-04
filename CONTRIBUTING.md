# Contributing to FocusMode

Thanks for helping make FocusMode better. Bug fixes, accessibility improvements, translations, documentation, and focused feature proposals are all welcome.

## Before You Start

- Search existing issues and pull requests to avoid duplicates.
- Use a discussion or feature request before investing in a large behavioral change.
- Keep changes narrow. FocusMode intentionally has no third-party dependencies or background service.
- Follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Local Development

You need macOS 14+ and Xcode 16+ or a Swift 6 toolchain.

```zsh
cd FocusMode
swift build
swift run FocusMode
```

Create the release-style app bundle with:

```zsh
zsh build-app.sh
```

## Pull Requests

1. Fork the repository and create a branch from `main`.
2. Make the smallest complete change that solves the issue.
3. Run `swift build` and manually exercise affected menu-bar flows.
4. Update documentation and localized strings when user-visible behavior changes.
5. Open a pull request using the provided template and link its issue.

Keep commit messages short and imperative, for example `Fix session restoration after cancelled quit`.

## Maintainer Releases

Create and push a Semantic Versioning tag to run the release workflow:

```zsh
git tag v1.0.0
git push origin v1.0.0
```

Tags matching `v*` publish an automatically generated GitHub Release. Update `CHANGELOG.md` before tagging.

## Translations

Localized strings live under `Sources/FocusMode/Resources/<language>.lproj/Localizable.strings`. Keep keys aligned with the English source and preserve format placeholders such as `%ld` and `%@`.

## Reporting Bugs

Use the bug report form and include your macOS version, FocusMode version or commit, reproduction steps, and expected behavior. Do not include sensitive documents, app data, or security reports in public issues.

## License

By contributing, you agree that your contributions will be licensed under the repository's [MIT License](LICENSE).
