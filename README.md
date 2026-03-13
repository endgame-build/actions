# Actions

Composite GitHub Actions for downloading, caching, and adding CLI tools to `$PATH`.

## Available Actions

### setup-jira

Download, cache, and add `jira-cli` to PATH.

```yaml
- uses: actions/create-github-app-token@v1
  id: app-token
  with:
    app-id: ${{ secrets.JIRA_CLI_APP_ID }}
    private-key: ${{ secrets.JIRA_CLI_APP_PRIVATE_KEY }}
    owner: endgame-build

- uses: endgame-build/actions/setup-jira@v1
  with:
    token: ${{ steps.app-token.outputs.token }}
    # version: '1.2.3'  # optional, defaults to latest
```

#### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `token` | Yes | — | GitHub token with read access to `endgame-build/jira-cli` releases |
| `version` | No | `latest` | Jira CLI version (without `v` prefix) or `"latest"` |

#### Authentication

The recommended approach is a [GitHub App](https://docs.github.com/en/apps) installed on `endgame-build/jira-cli` with **Contents: Read-only** permission. Each consuming repo needs two secrets:

| Secret | Description |
|--------|-------------|
| `JIRA_CLI_APP_ID` | GitHub App ID |
| `JIRA_CLI_APP_PRIVATE_KEY` | GitHub App private key (`.pem`) |

#### Notes

- The GitHub App must be installed on the `endgame-build/jira-cli` repository.
- Binaries are cached by OS, architecture, and version tag — subsequent runs hit cache.
- Supported platforms: Linux and macOS (amd64, arm64).
- For issues, visit the [main repository](https://github.com/endgame-build/jira-cli).
