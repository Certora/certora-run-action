# Certora Run GitHub Action

This repository contains Certora Run GitHub Action that allows you to run Certora Prover
on your contracts in parallel, receive the results as a comment on the pull request.

## Usage

To use this action, add the [Certora Run Application] to the repository and add
the following to your GitHub Actions workflow:

```yaml
jobs:
  certora_run_submission:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      statuses: write
      pull-requests: write
      id-token: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      - name: Submit verification jobs to Certora Prover
        uses: Certora/certora-run-action@v1
        with:
          # Add your configurations as lines, each line is separated.
          # Specify additional options for each configuration by adding them after the configuration.
          configurations: |-
            tests/evm/conf-verified.conf
            tests/evm/conf-verified.conf --rule monotone --method "counter()"
            tests/evm/conf-verified.conf --rule invertible
            tests/evm/conf-verified.conf --method "counter()"
          solc-versions: 0.7.6 0.8.1
          job-name: "Verified Rules"
          certora-key: ${{ secrets.CERTORAKEY }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

This action will download all the specified Solidity versions, start `certora-cli` on
every configuration file, and run the tests asynchronously. If one of the configurations
fails to start, the action will be marked as failed, and all other jobs will continue to run.

Once all the tests are finished, `Certora Run GitHub Application` will mark the commit
statuses as either `success` or `failure` and comment on the pull request with the
results.

Both solidity compilers and `certora-cli` dependencies are cached between runs.

Example:

```yaml
name: Certora Prover Submission Workflow
description: |-
  This workflow submits Certora Prover jobs on the specified configurations. Once all
  jobs are successfully submitted, it will add a pending commit status to the commit.
  This status will be periodically updated with verification results of the jobs along
  with the verification summary comment on the pull request.

  For more information, please visit https://github.com/certora/certora-run-action.

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main
  workflow_dispatch:

jobs:
  certora_run_submission:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      statuses: write
      pull-requests: write
      id-token: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          submodules: recursive

      # (Optional) Add installation steps for your project
      - name: Setup Node.js
        uses: actions/setup-node@v4
      - name: Install dependencies
        run: npm install

      # (Optional) Run Certora munge script
      - name: Certora munge
        run: ./certora/scripts/munge.sh

      # Submit verification jobs to Certora Prover
      - name: Submit verification jobs to Certora Prover
        uses: Certora/certora-run-action@v1
        with:
          # Add your configurations as lines, each line is separated.
          # Specify additional options for each configuration by adding them after the configuration.
          configurations: |-
            tests/evm/conf-verified.conf
            tests/evm/conf-verified.conf --rule monotone --method "counter()"
            tests/evm/conf-verified.conf --rule invertible
            tests/evm/conf-verified.conf --method "counter()"
          solc-versions: 0.7.6 0.8.1
          job-name: "Verified Rules"
          certora-key: ${{ secrets.CERTORAKEY }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      # Submit verification jobs to Certora Solana Prover
      - name: Submit verification jobs to Certora Solana Prover
        uses: Certora/certora-run-action@v1
        with:
          working-directory: tests/solana
          # Specify solana ecosystem
          ecosystem: solana
          configurations: |-
            Default.conf
          job-name: "Verified Solana Rules"
          certora-key: ${{ secrets.CERTORAKEY }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Permissions

This action requires the following permissions:

- `contents: read` - Clone the repository and read the configuration files.
- `statuses: write` - Write the status of the run to the GitHub UI.
- `pull-requests: write` - Write the run status & comment on the pull request.
- `id-token: write` - enables GitHub to request a signed OIDC token.

besides the permissions, the action requires the following secrets:

- `CERTORAKEY` - API key for Certora Prover.

### Inputs

General inputs for:

- `configurations` - List of configuration files to run.
- `cli-version` - Version of the `certora-cli` to use (optional). By default, the latest version is used. This action is compatible with versions `7.9.0` and above.
- `ecosystem` - Name of the cli ecosystem, the options are `evm` or `solana`. `evm` is the default ecosystem.
- `use-alpha` - Use the alpha version of the `certora-cli` (optional).
- `use-beta` - Use the beta version of the `certora-cli` (optional).
- `server` - Server to run the tests on (optional). Default is `production`.
- `job-name` - Name of the job (optional).
- `install-java` - Install Java for type checking (optional). Default is `true`.
- `compilation-steps-only` - Compile the spec and the code without sending a
  verification request to the cloud (optional). Default is `false`.
- `comment-fail-only` - Add a report comment to the pr only when the job fail (optional). Default it `true`.
- `certora-key` - API key for Certora Prover.
- `working-directory` - Working directory to run the action in (optional). Default is the root of the repository.
- `debug-level` - Debug level for the action (optional). Default is `0`. Possible values are `0`, `1`, `2`, and `3`. Higher values will produce more debug output.

EVM specific inputs (`ecosystem: evm`):

- `solc-versions` - List of Solidity versions to download. The first version in the list
  will also be available as `solc` in the environment. Each version will be available as
  both `solc<version>` and `solc-<version>` in the environment.
- `solc-remove-version-prefix` - Prefix to remove from the Solidity version (optional).

Solana specific inputs (`ecosystem: solana`):

- `rust-version` - The version of Rust to install. If not specified, the latest stable version will be used. The minimum supported version is `1.82.0`.
- `rust-additional-versions` - Additional versions of Rust to install, separated by spaces. Example: `1.75 1.79`.
- `certora-sbf-version` - The version of `cargo-certora-sbf` to install. If not specified, the latest version will be used.
- `certora-sbf-options` - Additional options to pass to the `cargo certora-sbf` command. This can be used to specify additional flags or configurations for the Certora SBF tool.
- `rust-setup` - Whether to set up Rust for Solana. Default is `true`. If you need more control over the Solana installation or options, you could use the
  [Certora Rust Setup Action](https://github.com/Certora/rust-setup-action) directly in your workflow.

### Comments on the Pull Request

First, it will add a comment with details about runs:

![GitHub PR Comments](/static/comments.png?raw=true "GitHub PR Comments")

Then you can see the live status of the runs:

![GitHub PR Status](/static/status.png?raw=true "GitHub PR Status")

And finally, once the first job finishes, GH App will add and update a review with the results:

![GitHub PR Review](/static/reviews.png?raw=true "GitHub PR Review")

## Development Setup

For local development, you can use the [act] tool to run
the action locally. The easiest way to set up everything is through combination of
[nix] and [direnv].

In order to set up the environment, follow these steps:

```bash
direnv allow
```

Then, you can run the action with the following command:

```bash
act workflow_dispatch \
    -s GITHUB_TOKEN="$(gh auth token)" \
    -s CERTORAKEY="$CERTORAKEY" \
    -W .github/workflows/main.yml \
    --container-architecture=linux/amd64
```

For testing, please create a PR using [Certora Action Test] repository. The PR should
start several workflows on all of our environments.

[act]: https://github.com/nektos/act
[nix]: https://nixos.org/
[direnv]: https://github.com/direnv/direnv
[Certora Run Application]: https://github.com/apps/certora-run
[Certora Action Test]: https://github.com/Certora/certora-run-action-test
