#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
if [ -z "$GITHUB_ORG" ]; then
    echo -e "${RED}Error: GITHUB_ORG environment variable is not set${NC}"
    exit 1
fi
if [ -z "$GITHUB_REPO" ]; then
    echo -e "${RED}Error: GITHUB_REPO environment variable is not set${NC}"
    exit 1
fi
if [ -z "$OCI_REGISTRY" ]; then
    echo -e "${RED}Error: OCI_REGISTRY environment variable is not set${NC}"
    exit 1
fi

OCI_REPO="${OCI_REGISTRY}/${GITHUB_ORG}"

# Temporary directory for downloads
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo -e "${GREEN}=== Helm Chart Migration to OCI Registry ===${NC}"
echo "This script will migrate existing charts from GitHub Releases to ${OCI_REPO}"
echo "and sign them with cosign for enhanced security."
echo ""
echo -e "${YELLOW}Note: This script requires write permissions to the organization's packages.${NC}"
echo -e "${YELLOW}For organization packages at ghcr.io/${GITHUB_ORG}:${NC}"
echo -e "${YELLOW}  1. Repository must have 'packages: write' permission in the workflow${NC}"
echo -e "${YELLOW}  2. Organization must allow package creation from this repository${NC}"
echo -e "${YELLOW}  3. First-time package creation may require organization admin approval${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is not installed${NC}"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}Error: curl is not installed${NC}"; exit 1; }
command -v cosign >/dev/null 2>&1 || { echo -e "${RED}Error: cosign is not installed${NC}"; exit 1; }

# Check Helm version
HELM_VERSION=$(helm version --short | grep -oE 'v[0-9]+\.[0-9]+' | sed 's/v//')
readonly HELM_VERSION
HELM_MAJOR=$(echo $HELM_VERSION | cut -d. -f1)
readonly HELM_MAJOR
HELM_MINOR=$(echo $HELM_VERSION | cut -d. -f2)
readonly HELM_MINOR

echo -e "${YELLOW}Checking Helm version...${NC}"
echo "Helm version: $HELM_VERSION"
echo "Helm major: $HELM_MAJOR"
echo "Helm minor: $HELM_MINOR"
echo ""

echo -e "${YELLOW}Checking cosign version...${NC}"
echo "Cosign version: $(cosign version)"
echo ""

if [ "$HELM_MAJOR" -lt 3 ] || ([ "$HELM_MAJOR" -eq 3 ] && [ "$HELM_MINOR" -lt 8 ]); then
    echo -e "${RED}Error: Helm 3.8.0 or higher is required for OCI support${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"
echo ""

# Login to OCI registry
echo -e "${YELLOW}Logging in to ${OCI_REGISTRY}...${NC}"
if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}Error: GITHUB_TOKEN environment variable is not set${NC}"
    echo "Please set it with: export GITHUB_TOKEN=<your_github_token>"
    echo ""
    echo "For organization packages, the token needs 'write:packages' scope."
    echo "Alternatively, run this script via GitHub Actions workflow."
    exit 1
fi

# Detect username - use GITHUB_ACTOR if in GitHub Actions, otherwise require GITHUB_USERNAME
if [ -n "$GITHUB_ACTOR" ]; then
    GITHUB_USERNAME="$GITHUB_ACTOR"
elif [ -z "$GITHUB_USERNAME" ]; then
    echo -e "${RED}Error: GITHUB_USERNAME environment variable is not set${NC}"
    echo "Please set it with: export GITHUB_USERNAME=<your_github_username>"
    exit 1
fi

echo "$GITHUB_TOKEN" | helm registry login "$OCI_REGISTRY" -u "$GITHUB_USERNAME" --password-stdin
echo -e "${GREEN}✓ Logged in to ${OCI_REGISTRY} as ${GITHUB_USERNAME}${NC}"
echo ""

# Also login with cosign for signing
echo -e "${YELLOW}Logging in to ${OCI_REGISTRY} for cosign...${NC}"
echo "$GITHUB_TOKEN" | cosign login "$OCI_REGISTRY" -u "$GITHUB_USERNAME" --password-stdin
echo -e "${GREEN}✓ Logged in for cosign${NC}"
echo ""

# Function to download and push a chart version
migrate_chart() {
    local chart_name=$1
    local version=$2
    local download_url=$3
    
    echo -e "${YELLOW}Migrating ${chart_name}:${version}...${NC}"
    
    # Download the chart
    local chart_file="${chart_name}-${version}.tgz"
    curl -L -s -o "${TEMP_DIR}/${chart_file}" "$download_url"
    
    if [ ! -f "${TEMP_DIR}/${chart_file}" ]; then
        echo -e "${RED}✗ Failed to download ${chart_file}${NC}"
        return 1
    fi
    
    # Check if package version already exists
    echo -e "${YELLOW}Checking if ${chart_name}:${version} already exists...${NC}"
    if helm pull "oci://${OCI_REPO}/${chart_name}" --version "${version}" --destination "${TEMP_DIR}" 2>/dev/null; then
        echo -e "${YELLOW}⚠ ${chart_name}:${version} already exists in OCI registry, skipping...${NC}"
        echo ""
        return 0
    fi
    
    # Push to OCI registry
    echo -e "${YELLOW}Pushing to oci://${OCI_REPO}...${NC}"
    if helm push "${TEMP_DIR}/${chart_file}" "oci://${OCI_REPO}" 2>&1 | tee "${TEMP_DIR}/helm_push.log"; then
        echo -e "${GREEN}✓ Successfully pushed ${chart_name}:${version} to OCI registry${NC}"
        
        # Extract digest from helm push output
        local digest=$(grep -oE 'Digest: sha256:[a-f0-9]{64}' "${TEMP_DIR}/helm_push.log" | cut -d' ' -f2)
        
        if [ -z "$digest" ]; then
            echo -e "${YELLOW}⚠ Could not extract digest from helm push output, using tag for signing${NC}"
            local image_ref="${OCI_REPO}/${chart_name}:${version}"
        else
            echo -e "${GREEN}✓ Extracted digest: ${digest}${NC}"
            local image_ref="${OCI_REPO}/${chart_name}@${digest}"
        fi
        
        # Sign the chart with cosign using digest
        echo -e "${YELLOW}Signing ${chart_name}:${version} with cosign...${NC}"
        echo -e "${YELLOW}Using image reference: ${image_ref}${NC}"
        if cosign sign --yes "${image_ref}" 2>&1; then
            echo -e "${GREEN}✓ Successfully signed ${chart_name}:${version}${NC}"
            
            # Verify the signature
            echo -e "${YELLOW}Verifying signature for ${chart_name}:${version}...${NC}"
            if cosign verify "${image_ref}" --certificate-identity-regexp=".*" --certificate-oidc-issuer=https://token.actions.githubusercontent.com 2>&1; then
                echo -e "${GREEN}✓ Successfully verified signature for ${chart_name}:${version}${NC}"
            else
                echo -e "${RED}✗ Failed to verify signature for ${chart_name}:${version}${NC}"
                echo -e "${YELLOW}Note: Chart was signed but verification failed.${NC}"
            fi
        else
            echo -e "${RED}✗ Failed to sign ${chart_name}:${version}${NC}"
            echo -e "${YELLOW}Note: Chart was pushed but signing failed. You can sign it later.${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to push ${chart_name}:${version}${NC}"
        echo -e "${RED}Error details:${NC}"
        cat "${TEMP_DIR}/helm_push.log"
        return 1
    fi
    
    echo ""
}

# Fetch all tags from GitHub repository
echo -e "${GREEN}=== Fetching tags from GitHub repository ===${NC}"
echo ""

TAGS_JSON=$(curl -s "https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/tags")
TAG_NAMES=$(echo "$TAGS_JSON" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)

if [ -z "$TAG_NAMES" ]; then
    echo -e "${RED}Error: No tags found in repository${NC}"
    exit 1
fi

echo -e "${GREEN}Found the following tags:${NC}"
echo "$TAG_NAMES"
echo ""

# Migrate chart versions from GitHub Releases
echo -e "${GREEN}=== Migrating chart versions from GitHub Releases ===${NC}"
echo ""

while IFS= read -r tag; do
    # Skip empty lines
    [ -z "$tag" ] && continue
    
    # Parse tag name to extract chart name and version
    # Expected format: adaptive-{version} or monitoring-{version}
    if [[ $tag =~ ^(adaptive|monitoring)-(.+)$ ]]; then
        chart_name="${BASH_REMATCH[1]}"
        version="${BASH_REMATCH[2]}"
        download_url="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/download/${tag}/${chart_name}-${version}.tgz"
        
        migrate_chart "$chart_name" "$version" "$download_url"
    else
        echo -e "${YELLOW}⚠ Skipping tag '${tag}' - doesn't match expected format (chartname-version)${NC}"
        echo ""
    fi
done <<< "$TAG_NAMES"

# Logout
echo -e "${YELLOW}Logging out from ${OCI_REGISTRY}...${NC}"
helm registry logout "$OCI_REGISTRY"
echo -e "${GREEN}✓ Logged out${NC}"
echo ""

# Summary
echo -e "${GREEN}=== Migration Complete ===${NC}"
echo ""