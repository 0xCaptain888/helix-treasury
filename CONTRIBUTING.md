# Contributing to Helix

Helix is the treasury infrastructure for the programmable economy. We welcome contributors who share that vision and are willing to operate to the standards that come with building infrastructure that holds real money.

## Ground Rules

1. **Read the security model first.** Every contribution starts with [docs/05-security-model.md](./docs/05-security-model.md). If your change might affect any of the listed invariants, label your PR `security-review` and expect a deeper review cycle.

2. **No undocumented changes to contract storage layouts.** Storage layout changes require a migration plan and are blocked from merging without one.

3. **No LLM-generated code that has not been read line-by-line by a human.** We use AI tools, but we own every line we commit. PRs that contain "vibes-coded" sections will be rejected.

4. **Tests are not optional.** New code paths require new tests. New invariants require new property tests. PR description must state which tests cover the change.

## Development Setup

See [docs/06-deployment.md](./docs/06-deployment.md) for the full toolchain.

```bash
git clone https://github.com/YOUR_ORG/helix.git
cd helix
pnpm install
forge install
cd contracts/stylus && cargo build && cd ../..
```

## Branch Strategy

- `main` — production-bound. Only audited or test-only changes land here.
- `develop` — integration branch. Most PRs target this.
- `feature/<short-name>` — feature branches.
- `audit/<finding-id>` — branches addressing audit findings; require special review.

## Pull Request Checklist

Before opening a PR:

- [ ] `pnpm test` passes locally
- [ ] `forge test -vvv` passes
- [ ] `forge fmt --check` passes
- [ ] PR description references the issue or design discussion that motivated the change
- [ ] Storage layout unchanged OR migration plan included
- [ ] Threat-model implications stated explicitly (even if "none")
- [ ] Documentation updated where relevant

## Areas We Want Help With

- **Adapter implementations** — new protocol adapters following the `IAdapter` interface
- **Hard constraint library** — useful constraints for specific jurisdictions and risk profiles
- **Policy templates** — well-tested `.hxp` policies for common treasury patterns
- **Testing** — additional property-based and invariant tests, especially for cross-adapter interactions
- **SDK & dashboard examples** — example dashboards, alert configurations, integration patterns
- **Documentation** — clarity improvements, additional examples

## Areas Where We Need Caution

- Changes to `PolicyEngine` are reviewed by at least two maintainers
- Changes to `TreasuryVault` are reviewed by all core maintainers
- New `Adapter` implementations require a threat-model statement

## Security Issues

**Do not** open public issues for security vulnerabilities. Email `security@helix-treasury.xyz` (TBD post-buildathon) with a detailed report. See [docs/05-security-model.md §9](./docs/05-security-model.md#9-disclosure-policy) for the full disclosure policy.

## Code of Conduct

We follow the [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).
