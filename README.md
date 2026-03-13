# Certora Run GitHub Action

This repository contains a Certora Run GitHub Action that allows you to run Certora Prover
on your contracts in parallel, receive the results as a comment on the pull request.

## Usage

To use this action, install the [Certora Run Application] on the repository and add
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
        uses: actions/checkout@v6
      - name: Submit verification jobs to Certora Prover
        uses: Certora/certora-run-action@v2
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
statuses as either `success` or `failure`, and comment on the pull request with the
results.

Both solidity compilers and `certora-cli` dependencies are cached between runs.

Example:

```yaml
name: Certora Prover Submission Workflow
description: |-
  This workflow submits Certora Prover jobs on the specified configurations. Once all
  jobs are successfully submitted, it will add a pending commit status to the commit.
  This status will be periodically updated with verification results of the jobs, along
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
        uses: actions/checkout@v6
        with:
          submodules: recursive

      # (Optional) Add installation steps for your project
      - name: Setup Node.js
        uses: actions/setup-node@v6
      - name: Install dependencies
        run: npm install

      # (Optional) Run Certora munge script
      - name: Certora munge
        run: ./certora/scripts/munge.sh

      # Submit verification jobs to Certora Prover
      - name: Submit verification jobs to Certora Prover
        uses: Certora/certora-run-action@v2
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
        uses: Certora/certora-run-action@v2
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

      # Submit verification jobs to Certora Sui Prover
      - name: Submit verification jobs to Certora Sui Prover
        uses: Certora/certora-run-action@v2
        with:
          working-directory: tests/sui
          # Specify sui ecosystem
          ecosystem: sui
          configurations: |-
            Default.conf
          job-name: "Verified Sui Rules"
          certora-key: ${{ secrets.CERTORAKEY }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      # Submit verification jobs to Certora Soroban Prover
      - name: Submit verification jobs to Certora Soroban Prover
        uses: Certora/certora-run-action@v2
        with:
          working-directory: tests/soroban
          # Specify Soroban ecosystem
          ecosystem: soroban
          configurations: |-
            Default.conf
          job-name: "Verified Soroban Rules"
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

The best practice is to specify permissions at the job level in your workflow file, as
shown in the example above. This way, you can ensure that the permissions are only
granted to the specific job that requires them.

### Inputs

General inputs for:

- `configurations` - List of configuration files to run.
- `cli-version` - Version of the `certora-cli` to use (optional). By default, the latest version is used. This action is compatible with versions `7.9.0` and above.
- `cli-release` - Release type of the `certora-cli` to use (optional). Default is `stable`.
  Options are `stable`, `alpha`, `beta`, or a custom branch name. Everything other than
  `stable` should only be used for testing purposes and is not recommended for production use.
- `ecosystem` - Name of the CLI ecosystem, the options are `evm`, `solana`, `soroban`, and `sui`. `evm` is the default ecosystem.
- `server` - Server to run the tests on (optional). Default is `production`.
- `job-name` - Name of the job (optional).
- `install-java` - Install Java for type checking (optional). Default is `true`.
- `compilation-steps-only` - Compile the spec and the code without sending a
  verification request to the cloud (optional). Default is `false`.
- `comment-fail-only` - Add a report comment to the pr only when the job fails (optional). Default is `true`.
- `certora-key` - API key for Certora Prover.
- `working-directory` - Working directory to run the action in (optional). Default is the root of the repository.
- `use-hard-links` - Whether to use hard links when copying files (optional). If you expect to modify the files in the run directory during `certoraRun` execution, you should set this to `false`.
- `debug-level` - Debug level for the action (optional). Default is `0`. Possible values are `0`, `1`, `2`, and `3`. Higher values will produce more debug output.
- `gh-review` - When to add a review comment to the PR. Options are `always`, `failure`, and `never`. Default is `always`.
- `gh-review-jobs` - Which jobs to include in the GitHub review comment. Options are `all`, `failed`. Default is `all`.

EVM specific inputs (`ecosystem: evm`):

- `solc-versions` - List of Solidity versions to download. The first version in the list
  will also be available as `solc` in the environment. Each version will be available as
  both `solc<version>` and `solc-<version>` in the environment.
- `solc-remove-version-prefix` - Prefix to remove from the Solidity version (optional).
- `vyper-version` - The version of Vyper to install. Can be `latest`, or a specific
  version like `0.3.3`. If not specified, Vyper will not be installed.

Solana specific inputs (`ecosystem: solana`):

- `rust-version` - The version of Rust to install. If not specified, the latest stable version will be used. The minimum supported version is `1.82.0`.
- `rust-additional-versions` - Additional versions of Rust to install, separated by spaces. Example: `1.75 1.79`.
- `certora-sbf-version` - The version of `cargo-certora-sbf` to install. If not specified, the latest version will be used.
- `certora-sbf-options` - Additional options to pass to the `cargo certora-sbf` command. This can be used to specify additional flags or configurations for the Certora SBF tool.
- `rust-setup` - Whether to set up Rust for Solana. The default is `true`. If you need more control over the Solana installation or options, you could use the
  [Certora Rust Setup Action](https://github.com/Certora/rust-setup-action) directly in your workflow.

### 🧩 Note: Installing the Sui CLI

This action does not automatically install the Sui CLI.
If your workflow requires running Sui commands, make sure the CLI is installed beforehand.
You can install it manually using the following commands:

```bash
curl -sSfL https://raw.githubusercontent.com/MystenLabs/suiup/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
suiup install -y sui@testnet
```

### 🧩 Note: Installing the Soroban Environment

Specifying the Soroban ecosystem **does not** automatically install the Rust toolchain required for building Soroban WASM from source.
If you plan to compile Soroban contracts in your workflow, ensure that all dependencies are available.

You typically need:

- **`just` and the Rust toolchain**. These can be installed via GitHub Actions:
  - `actions-rust-lang/setup-rust-toolchain@v1`
  - `extractions/setup-just@v3`

- **The WASM compilation target** required by Soroban:

  ```sh
  rustup target add wasm32-unknown-unknown
  ```

- **A Cargo lockfile.**
  If you do not want to commit it in your repository, you can generate it from the action
  by running, for example:

  ```sh
  cargo update -p cvlr-soroban
  ```

## Certora API Integration

You can also use this action to call Certora API commands such as cancelling or
refreshing jobs in a group. To do so, you can create a workflow like this:

```yml
name: Certora API
on:
  workflow_dispatch:
    inputs:
      command:
        required: true
        description: |
          The Certora API command to execute. Options are:
          - `cancel <group_id>`: Cancel all jobs in the specified group.
          - `refresh <group_id>`: Refresh the status of all jobs in the specified group.
      server:
        required: true
        type: choice
        description: |
          The Certora server to use. Either production, staging, or vaas-dev.
          Default is production.
        default: production
        options:
          - production
          - staging
          - vaas-dev

permissions:
  contents: read
  id-token: write

jobs:
  certora_api_command:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: Certora/certora-run-action/api@v2
        with:
          certora-command: ${{ github.event.inputs.command }}
          server: ${{ github.event.inputs.server }}
```

Then, you can trigger this workflow manually from the GitHub Actions UI, providing the
command and the server as inputs.

### Comments on the Pull Request

First, it will add a comment with details about runs:

![GitHub PR Comments](/static/comments.png?raw=true "GitHub PR Comments")

Then you can see the live status of the runs:

![GitHub PR Status](/static/status.png?raw=true "GitHub PR Status")

And finally, once the first job finishes, GH App will add and update a review with the results:

![GitHub PR Review](/static/reviews.png?raw=true "GitHub PR Review")

## Troubleshooting

In case of any troubleshooting we recommend checking the logs of the workflow and using
`debug-level: 3` input to get more detailed logs from the action. Also make sure to
verify that all parameters are set correctly in the `with` block of the action
in your workflow file as GitHub does not validate the input or raise any errors on
additional or misspelled parameters.

### Permissions Errors

If you encounter permissions errors, make sure that you have set the required
[permissions](#permissions) in your workflow file for this specific job.

### GitHub Application is not Available Error

If you encounter this error, make sure that you have installed the [Certora Run Application]
and it's available for this repository.

### CERTORAKEY is Missing Error

The most common reasons for this issue are:

1. The secret is not set in the repository settings. Make sure to add the `CERTORAKEY`
   secret in your repository settings. If you're using environment secrets, make sure to
   add it there and that the environment is selected in the workflow ([GitHub Actions Environment]).
2. The secret is not passed to the action. Make sure to specify the `certora-key` input
   in your workflow file and set it to `${{ secrets.CERTORAKEY }}`.
3. The secret is not accessible due to repository permissions. Ensure that the workflow
   has access to the secret, especially if it's in a forked repository. In case of forks,
   secrets are not available by default for security reasons. There is an option to use
   a different action trigger like `pull_request_target`, but it should be used with
   caution as it can pose security risks ([Pull Request Target Security]). Other options
   include using different triggers and separate workflows.

### Workflow Fails with "Failed to start all jobs" Error

This error indicates that one or more Certora Prover jobs failed to start. In order to
identify the root cause of the issue, review the logs of the workflow that are included
in the GitHub Actions UI as workflow artifacts and in the PR comment.

Common reasons for this error include:

- Missing configuration files or incorrect paths specified in the `configurations`
  input.
- Missing dependencies or munge steps required for the verification process.

### Workflow Does Not Start

In case that the workflow does not start at all:

1. Make sure that the GitHub Actions are enabled for the repository.
2. Make sure that the workflow already exists in the default branch of the repository
   and that the trigger is correct.
3. Make sure that the workflow file is valid and does not contain any syntax errors. You can use
   GitHub's workflow editor to validate the syntax of your workflow file or
   [GitHub Actions Linter](https://rhysd.github.io/actionlint/).

## Migration from v1 to v2

If you are migrating from v1 to v2, you need to update the action reference in your workflow file:

- **Permissions**: In order to provide verification using [GitHub OIDC], we need to
  enable `id-token: write` permission. This way we can authenticate to Certora
  and verify that [Certora Run Application] was installed on the repository.
  Update your workflow file to include the `id-token: write` permission:

```diff
permissions:
  contents: read
  statuses: write
  pull-requests: write
+  id-token: write
```

- **CLI Release**: The `use-beta`/`use-alpha` inputs have been replaced with `cli-release`. The
  default value is `stable`, so if you want to use the beta version, you need to
  specify it explicitly:

```diff
      - name: Submit verification jobs to Certora Prover
-       uses: Certora/certora-run-action@v1
+       uses: Certora/certora-run-action@v2
        with:
          configurations: |-
            tests/evm/conf-verified.conf
          solc-versions: 0.7.6 0.8.1
-         use-beta: true
+         cli-release: beta
```

## Development Setup

For local development, you can use the [act] tool to run
the action locally. The easiest way to set up everything is through a combination of
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

For testing, please create a PR using the [Certora Action Test] repository. The PR should
start several workflows on all of our environments.

[act]: https://github.com/nektos/act
[nix]: https://nixos.org/
[direnv]: https://github.com/direnv/direnv
[Certora Run Application]: https://github.com/apps/certora-run
[Certora Action Test]: https://github.com/Certora/certora-run-action-test
[GitHub OIDC]: https://docs.github.com/en/actions/concepts/security/about-security-hardening-with-openid-connect#adding-permissions-settings
[GitHub Actions Environment]: https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/deploy-to-environment
[Pull Request Target Security]: https://securitylab.github.com/resources/github-actions-preventing-pwn-requests/
