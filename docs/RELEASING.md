# Releasing New Versions

This document describes the release process for `mollie_pay`.

## Overview

We follow [Semantic Versioning](https://semver.org/):
- **MAJOR** (X.0.0): Breaking changes requiring host app modifications
- **MINOR** (0.X.0): New features, backward compatible
- **PATCH** (0.0.X): Bug fixes, backward compatible

## Pre-Release Checklist

Before cutting a release, ensure:

1. **All tests pass**: `bin/rails test`
2. **Linting passes**: `bundle exec rubocop`
3. **CHANGELOG.md updated** with all changes since last release
4. **Version bumped** in `lib/mollie_pay/version.rb`
5. **Migration notes added** to CHANGELOG if schema changes
6. **README.md updated** with any new features or API changes

## Step-by-Step Release Process

### 1. Update CHANGELOG.md

Add a new section at the top following [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Now removed features

### Fixed
- Bug fixes

### Security
- Security improvements
```

**Important:** If the release requires database migrations, add a "Migration Required" section:

```markdown
### Migration Required
- Run `rails mollie_pay:install:migrations && rails db:migrate` for the new index on `mollie_pay_subscriptions.name`
```

### 2. Bump Version

Edit `lib/mollie_pay/version.rb`:

```ruby
module MolliePay
  VERSION = "X.Y.Z"
end
```

### 3. Create Release Commit

Commit both files with a conventional commit message:

```bash
git add lib/mollie_pay/version.rb CHANGELOG.md
git commit -m "chore: Bump version to X.Y.Z"
```

### 4. Tag the Release

Create an annotated tag matching the version:

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

### 5. Push to GitHub

```bash
git push origin master
git push origin vX.Y.Z
```

### 6. Create GitHub Release

Navigate to [GitHub Releases](https://github.com/peterberkenbosch/mollie_pay/releases) and click "Draft a new release".

**Release details:**
- **Tag version**: `vX.Y.Z` (select existing tag)
- **Release title**: `vX.Y.Z`
- **Description**: Copy the relevant CHANGELOG section (without the version header)

Example release body:

```markdown
### Added
- Named subscriptions: `name` column on subscriptions (default: `"default"`)
  enables multiple concurrent subscriptions per customer
- `name:` keyword argument on `mollie_subscribe`, `mollie_cancel_subscription`,
  `mollie_subscribed?`, and `mollie_subscription` (default: `"default"`)

### Migration Required
- Run `rails mollie_pay:install:migrations && rails db:migrate` for the
  `name` column and partial unique index on subscriptions
```

### 7. Publish Gem (Optional)

If publishing to RubyGems.org:

1. Update `mollie_pay.gemspec` to remove or update the `allowed_push_host` restriction
2. Build the gem: `gem build mollie_pay.gemspec`
3. Push to RubyGems: `gem push mollie_pay-X.Y.Z.gem`

Currently, the gemspec has `allowed_push_host` set to prevent accidental pushes:
```ruby
spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
```

## Fixing a Release Tag

If you need to add a missed commit to a tagged release (e.g. forgot to include
`Gemfile.lock`), follow these steps:

### 1. Commit the fix

```bash
git add Gemfile.lock
git commit -m "chore: Update Gemfile.lock for vX.Y.Z"
git push origin master
```

### 2. Move the tag

Delete the old tag locally, recreate it on the new commit:

```bash
git tag -d vX.Y.Z
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

### 3. Update the remote tag

GitHub rejects tag updates via `--force-with-lease`. Delete the remote tag first,
then push the new one:

```bash
git push origin :refs/tags/vX.Y.Z
git push origin vX.Y.Z
```

### 4. Re-publish the GitHub Release

Replacing a tag puts the GitHub Release into **draft** mode. Delete the draft and
recreate it:

```bash
gh release delete vX.Y.Z --yes
gh release create vX.Y.Z --title "vX.Y.Z" --notes "..."
```

Verify the release is public at
`https://github.com/peterberkenbosch/mollie_pay/releases/tag/vX.Y.Z`.

## Post-Release

1. Verify the GitHub release is public
2. Test installation from the new tag: `gem 'mollie_pay', github: 'peterberkenbosch/mollie_pay', tag: 'vX.Y.Z'`
3. Update any deployment documentation referencing the new version

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| v0.3.0 | 2026-03-17 | Named subscriptions support |
| v0.2.0 | 2026-03-17 | Through associations, idempotency guards, metadata |
| v0.1.0 | 2026-03-01 | Initial release |

## Questions?

See the [GitHub repository](https://github.com/peterberkenbosch/mollie_pay) for issues and discussions.
