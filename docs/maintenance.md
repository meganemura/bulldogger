# Maintenance

## How releases work

GitHub Actions publishes bulldogger through RubyGems.org Trusted
Publishing. The release workflow holds no RubyGems.org API key. It signs
in with a short-lived OIDC token that RubyGems.org accepts only from this
repository, this workflow file, and this environment.

`.github/workflows/release.yml` runs when a `v*` tag reaches GitHub. It
checks that the tag version matches `Bulldogger::VERSION`, runs the
default task and the coverage gate, builds the gem, pushes it, and
attaches the built gem to a GitHub release.

## Before the first release

Two things live outside this repository, and a release fails without
either one.

### Register the pending trusted publisher

RubyGems.org accepts a publisher for a gem name that does not exist yet.
Open the [pending trusted publishers
page](https://rubygems.org/profile/oidc/pending_trusted_publishers) and
create one with these values:

| Field | Value |
| --- | --- |
| Gem name | `bulldogger` |
| Repository owner | `meganemura` |
| Repository name | `bulldogger` |
| Workflow filename | `release.yml` |
| Environment | `release` |
| Workflow repository owner | Leave this field blank. |
| Workflow repository name | Leave this field blank. |

Leave both workflow repository fields blank. Those fields name a
reusable workflow in a different repository, and this workflow lives
beside the gem.

RubyGems.org converts the pending publisher after the first successful
push, and adds the profile account as an owner of the new gem.

For a gem that already exists, open the gem page, select **Trusted
publishers**, select **Create**, and enter the same values.

### Create the GitHub environment

The workflow names `release` as its environment. Create that environment
in the repository settings and add a required reviewer.

RubyGems.org matches this name exactly. The workflow, the environment in
the repository settings, and the trusted publisher must all use the same
name, or the push step fails to authenticate.

Without a required reviewer the environment still satisfies
RubyGems.org, and the release proceeds with no human confirmation.
Publishing a version cannot be undone: yanking a version does not free
its number, and the number can never be reused. The reviewer is what
turns a pushed tag into a decision.

## Make a release

1. Update the version in `lib/bulldogger/version.rb`.
2. Complete the normal review process for the version change.
3. Create a `vVERSION` tag, using the exact version from
   `version.rb`. Version `0.1.0` takes the tag `v0.1.0`.
4. Push the tag.
5. Approve the waiting release in the GitHub Actions run.
6. Confirm that the workflow succeeds.
7. Confirm that RubyGems.org shows the new version.

The workflow refuses a tag whose version disagrees with `version.rb`, so
a mistyped tag stops before anything is published.

Re-running a release that already pushed its gem succeeds. The push step
treats "Repushing of gem versions is not allowed" as success, so a
failure in a later step can be retried without the earlier step blocking
it.

## Releasing a version whose tag already exists

A tag that is already on GitHub does not start a workflow by existing.
Deleting the tag and pushing it again does:

```sh
git push origin :refs/tags/vVERSION
git push origin vVERSION
```

Confirm the tag points at the commit intended for release before pushing
it back.
