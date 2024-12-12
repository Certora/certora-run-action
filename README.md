# Certora Run GitHub Action

This repostory contains a reusable GitHub Action workflow for running Certora Prover
in your GitHub Actions workflows.

Test.

## Usage

To use this action, add the following to your GitHub Actions workflow:

```yaml
jobs:
  certora_run:
    permissions:
      contents: read
      statuses: write
      pull-requests: write
    uses: Certora/certora-run-action/.github/workflows/certora_run.yml@main
    secrets:
      CERTORAKEY: ${{ secrets.CERTORAKEY }}
    with:
      configurations: |-
        tests/conf-good.conf
        tests/conf-good1.conf
        tests/conf-good2.conf
      solc-versions: 0.7.6 0.8.1
      job-name: "Passing Test"
```

This action will download all the specified Solidity versions, start `certora-cli` on
every configuration file and run the tests asynchronously. If one of the configurations
fails to start, the action will be marked as failed all other jobs will continue to run.

Once all the test are finished `Certora Run GitHub Application` will mark commit
statuses as either `success` or `failure` and comment on the pull request with the
results.

Both solidity compilers and `certora-cli` dependencies are cached between runs.

### Permissions

This action requires the following permissions:

- `contents: read` - Clone the repository and read the configuration files.
- `statuses: write` - Write the status of the run to the GitHub UI.
- `pull-requests: write` - Write the status of the run & comment to the pull request.

besides the permissions, the action requires the following secrets:

- `CERTORAKEY` - API key for Certora Prover.

### Inputs

- `configurations` - List of configuration files to run.
- `solc-versions` - List of Solidity versions to download.
- `cli-version` - Version of the `certora-cli` to use (optional). By default, the latest version is used.
- `use-alpha` - Use the alpha version of the `certora-cli` (optional).
- `use-beta` - Use the beta version of the `certora-cli` (optional).
- `server` - Server to run the tests on (optional). Default is `production`.
- `solc-remove-version-prefix` - Prefix to remove from the Solidity version (optional).
- `job-name` - Name of the job (optional).

### Comments on the Pull Request

![GitHub PR Comments](/static/comments.png?raw=true "GitHub PR Comments")
![GitHub PR Status](/static/status.png?raw=true "GitHub PR Status")

## FAQ

Why do we have this action in `.github/workflows`?

- Unfortunately, GitHub Actions does not support relative paths outside this folder [https://github.com/orgs/community/discussions/9050]

## Development Setup

For local development, you can use the [act] tool to run
the action locally. The easiest way to set up everything is through combination of
[nix] and [direnv].

In order to set up the environment, follow these steps:

```bash
direnv allow
```

Then you can run the action with the following command:

```bash
act workflow_dispatch \
    -s GITHUB_TOKEN="$(gh auth token)" \
    -s CERTORAKEY="$CERTORAKEY" \
    -W .github/workflows/main.yml \
    --container-architecture=linux/amd64
```

[act]: https://github.com/nektos/act
[nix]: https://nixos.org/
[direnv]: https://github.com/direnv/direnv
