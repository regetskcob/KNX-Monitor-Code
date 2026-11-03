# Contributing

Thanks for wanting to help. Bug reports, ideas and votes go to the issues in
[regetskcob/KNX-Monitor](https://github.com/regetskcob/KNX-Monitor/issues).
Security problems go through
[private vulnerability reporting](https://github.com/regetskcob/KNX-Monitor/security/advisories/new),
never into a public issue.

## Before you write code

Open an issue first and describe what you want to change. KNX Monitor is a
one-person project that runs on live installations, so larger changes need to
fit its direction before they are worth your time.

## Pull requests

- Run `tool/release.sh verify` before you push. It runs the same checks as
  the CI: layout, format, analysis, tests, web build, add-on server.
- Keep one topic per pull request.
- Anything that sends telegrams to the bus needs a test, and it must respect
  the read-only switch (`READ_ONLY` / add-on option `read_only`).
- Texts the user sees exist in German and English (`lib/l10n/`).

## Licence of your contribution

KNX Monitor is licensed under the GNU General Public License v3.0. The
official builds are also distributed through the App Store and Google Play,
whose terms are not compatible with the GPL for code from third parties.
That is why every contribution needs the agreement below in addition to the
GPL.

### Contributor licence agreement

By submitting a contribution (code, documentation, graphics or translations)
to this repository, you agree to the following:

1. You wrote the contribution yourself, or you have the right to submit it
   under these terms, and it does not knowingly infringe anyone's rights.
2. Your contribution is licensed under the GNU General Public License v3.0,
   like the rest of the project.
3. In addition, you grant Daniel Bocksteger (regetskcob) a perpetual,
   worldwide, non-exclusive, royalty-free and irrevocable licence to use,
   copy, modify and distribute your contribution, and to sublicense it,
   under other terms as well, including in the official builds in app
   stores.
4. You keep the copyright in your contribution and may use it in any other
   way you like.

Confirm this by adding a `Signed-off-by` line to each commit
(`git commit -s`) and by ticking the box in the pull request template. Pull
requests without both cannot be merged.
