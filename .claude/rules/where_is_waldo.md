# Working in where_is_waldo

- This repo is PUBLIC. No internal hostnames, IP addresses, fleet topology or
  private notes in any file here — including this one. Judge changes as a library
  maintainer would: any consumer could hit the problem, so "our apps don't do
  that" is not a reason to leave a bug.
- Publishes are immutable and npm renders the README from the published tarball,
  refreshing it only on the NEXT version. So a README that lags the code stays
  wrong on npm until the following release. Update every doc BEFORE building or
  publishing, never after.
- Before cutting a version, check for a release PR already prepared as that
  version — `gh pr list`. Merge it rather than cutting a fresh one from master;
  cutting past a prepared PR has burned a version number here before.
- Build the gem with `bundle exec rake build`, which puts it in `pkg/`. NOT
  `gem build`, which drops it at the repo root and breaks the push command.
- The npm package must be published to BOTH public npm and GitHub Packages.
  Consumers resolve `@byscott-io` from GitHub Packages and cannot see a release
  that only reached public npm.
- Pushing the gem to RubyGems is Scott's step, not an automated one. Hand him the
  built file from `pkg/`.
- A version number appearing in production does not prove a release works.
  Exercise the actual code path and assert on a real payload value.
