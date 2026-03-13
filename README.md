# Actions

Composite GitHub Actions for downloading, caching, and adding CLI tools to `$PATH`.

## Available Actions

### setup-jira

Download, cache, and add `jira-cli` to PATH.

```yaml
- uses: endgame-build/actions/setup-jira@v1
  with:
    token: ${{ secrets.JIRA_CLI_PAT }}
    # version: '1.2.3'  # optional, defaults to latest
```

#### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `token` | Yes | — | GitHub PAT with read access to `endgame-build/jira-cli` releases |
| `version` | No | `latest` | Jira CLI version (without `v` prefix) or `"latest"` |

#### Notes

- The token needs `repo` read access to the private `endgame-build/jira-cli` repository.
- Binaries are cached by OS, architecture, and version tag — subsequent runs hit cache.
- Supported platforms: Linux and macOS (amd64, arm64).
- For issues, visit the [main repository](https://github.com/endgame-build/jira-cli).
