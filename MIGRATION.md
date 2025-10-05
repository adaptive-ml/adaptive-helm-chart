# Migration Guide: GitHub Pages to OCI Registry

This guide explains how to migrate your Helm charts from GitHub Pages/Releases to GitHub Container Registry (OCI).

## Prerequisites

- Organization admin or maintainer access to `adaptive-ml` organization
- Access to run GitHub Actions workflows

## Migration Options

### Option 1: Via GitHub Actions (Recommended)

This is the easiest method as it uses the built-in `GITHUB_TOKEN` with proper permissions.

1. Go to your repository on GitHub
2. Navigate to **Actions** tab
3. Select **Migrate Charts to OCI Registry** workflow
4. Click **Run workflow** → **Run workflow**
5. Wait for the workflow to complete
6. Check the workflow summary for migration results

After completion, make packages public:
- Visit https://github.com/orgs/adaptive-ml/packages
- For each package (adaptive, monitoring), click on it
- Go to **Package settings** → **Danger Zone**
- Click **Change visibility** → **Public**

### Option 2: Local Execution (Requires Org Admin)

If you have organization admin/maintainer permissions:

1. Create a GitHub Personal Access Token with `write:packages` scope:
   - Go to https://github.com/settings/tokens
   - Click **Generate new token (classic)**
   - Select scope: `write:packages`
   - Generate and copy the token

2. Set environment variables:
   ```bash
   export GITHUB_TOKEN=ghp_your_token_here
   export GITHUB_USERNAME=your_github_username
   ```

3. Run the migration script:
   ```bash
   ./migrate-to-oci.sh
   ```

## What Gets Migrated

The migration script will:

1. **Download old versions** from GitHub Releases:
   - adaptive-0.0.1
   - adaptive-0.0.2

2. **Package current versions** from source:
   - adaptive-0.6.2 (current)
   - monitoring-0.1.5 (current)

3. **Push all versions** to `oci://ghcr.io/adaptive-ml/`

## Post-Migration

After successful migration:

1. **Make packages public** (see Option 1 above)

2. **Test the migration**:
   ```bash
   # List available versions
   helm show chart oci://ghcr.io/adaptive-ml/adaptive --version 0.6.2
   
   # Install a chart
   helm install adaptive oci://ghcr.io/adaptive-ml/adaptive --version 0.6.2
   ```

3. **Update CI/CD**: The `publish.yml` workflow is already configured to publish new versions automatically

4. **Deprecate old method**: Add a deprecation notice to the old GitHub Pages site if still active

## Troubleshooting

### Permission Denied
- Ensure you have `write:packages` permission for the organization
- Verify your token hasn't expired
- For GitHub Actions, ensure the workflow has `packages: write` permission

### Chart Already Exists
- The script will fail if a chart version already exists in the registry
- To force re-push, manually delete the package version first from GitHub Packages UI

### Download Failed
- Check that the GitHub Release URLs are correct
- Ensure the release artifacts are still available

## Rollback

If you need to rollback to the old method:

1. The original charts in GitHub Releases remain untouched
2. Simply revert the changes to `publish.yml` workflow
3. Charts in OCI registry can coexist with the old method

## Support

For issues or questions:
- Check workflow logs in GitHub Actions
- Review script output for error messages
- Contact organization administrators

