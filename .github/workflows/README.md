# GitHub Actions Workflows

This directory contains GitHub Actions workflows for SQLSketch.jl.

## Workflows

### CI.yml - Continuous Integration

**Triggers:**
- Push to `main` branch (excluding docs and markdown files)
- Pull requests (excluding docs and markdown files)

**Jobs:**
1. **Test** - Run tests on Julia 1.9 and 1.12
2. **Lint** - Run JET static analysis
3. **Format Check** - Verify code formatting with JuliaFormatter

**Skipped when:**
- Only `docs/**` files changed
- Only `*.md` files changed
- Only `LICENSE` changed

### Documentation.yml - Documentation Build & Deploy

**Triggers:**
- Push to `main` branch (only when docs/src/Project.toml changed)
- Tags
- Pull requests (only when docs/src/Project.toml changed)

**Jobs:**
1. **Build** - Build documentation with Documenter.jl
2. **Deploy** - Deploy to GitHub Pages (only on main branch)

**Runs when:**
- `docs/**` files changed
- `src/**` files changed (API changes)
- `Project.toml` changed
- Workflow file changed

## Local Development

Run the same checks locally:

```bash
# Run all checks
make all

# Individual checks
make test          # Run tests
make lint          # Run JET analysis
make format-check  # Check formatting
make format        # Auto-format code
make docs          # Build documentation
```

## Setup Requirements

### For Documentation Deployment

1. Generate SSH deploy key:
   ```bash
   julia --project=. -e 'using DocumenterTools; DocumenterTools.genkeys(user="daikichiba9511", repo="SQLSketch.jl")'
   ```

2. Add Deploy Key to GitHub:
   - Go to: https://github.com/daikichiba9511/SQLSketch.jl/settings/keys
   - Add public key with write access

3. Add Secret to GitHub:
   - Go to: https://github.com/daikichiba9511/SQLSketch.jl/settings/secrets/actions
   - Name: `DOCUMENTER_KEY`
   - Value: Private key (base64 string)

See `tmp/docs/SETUP_GITHUB_PAGES.md` for detailed instructions.

## Workflow Optimization

- **Parallel execution**: Test, Lint, and Format-check run in parallel
- **Path filtering**: Workflows only run when relevant files change
- **Caching**: Julia packages cached via `julia-actions/cache@v2`
- **Matrix strategy**: Tests run on multiple Julia versions
