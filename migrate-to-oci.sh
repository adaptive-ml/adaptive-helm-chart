#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GITHUB_ORG="adaptive-ml"
GITHUB_REPO="adaptive-helm-chart"
OCI_REGISTRY="ghcr.io"
OCI_REPO="${OCI_REGISTRY}/${GITHUB_ORG}"

# Temporary directory for downloads
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo -e "${GREEN}=== Helm Chart Migration to OCI Registry ===${NC}"
echo "This script will migrate existing charts from GitHub Releases to ${OCI_REPO}"
echo ""
echo -e "${YELLOW}Note: This script requires write permissions to the organization's packages.${NC}"
echo -e "${YELLOW}Run this via GitHub Actions or as an org admin/maintainer.${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is not installed${NC}"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}Error: curl is not installed${NC}"; exit 1; }

# Check Helm version
HELM_VERSION=$(helm version --short | grep -oE 'v[0-9]+\.[0-9]+' | sed 's/v//')
readonly HELM_VERSION
HELM_MAJOR=$(echo $HELM_VERSION | cut -d. -f1)
readonly HELM_MAJOR
HELM_MINOR=$(echo $HELM_VERSION | cut -d. -f2)
readonly HELM_MINOR

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
    
    # Push to OCI registry
    if helm push "${TEMP_DIR}/${chart_file}" "oci://${OCI_REPO}"; then
        echo -e "${GREEN}✓ Successfully pushed ${chart_name}:${version} to OCI registry${NC}"
    else
        echo -e "${RED}✗ Failed to push ${chart_name}:${version}${NC}"
        return 1
    fi
    
    echo ""
}

# Migrate old adaptive chart versions from GitHub Releases
echo -e "${GREEN}=== Migrating old chart versions from GitHub Releases ===${NC}"
echo ""

migrate_chart "adaptive" "0.0.1" "https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/download/adaptive-0.0.1/adaptive-0.0.1.tgz"
migrate_chart "adaptive" "0.0.2" "https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/download/adaptive-0.0.2/adaptive-0.0.2.tgz"

# Package and push current chart versions
echo -e "${GREEN}=== Packaging and pushing current chart versions ===${NC}"
echo ""

cd "$(dirname "$0")/charts"

# Package and push adaptive chart
echo -e "${YELLOW}Packaging adaptive chart...${NC}"
helm dependency update adaptive
helm package adaptive -d "${TEMP_DIR}"
ADAPTIVE_VERSION=$(grep '^version:' adaptive/Chart.yaml | awk '{print $2}')
echo -e "${GREEN}✓ Packaged adaptive:${ADAPTIVE_VERSION}${NC}"

echo -e "${YELLOW}Pushing adaptive:${ADAPTIVE_VERSION} to OCI registry...${NC}"
helm push "${TEMP_DIR}/adaptive-${ADAPTIVE_VERSION}.tgz" "oci://${OCI_REPO}"
echo -e "${GREEN}✓ Successfully pushed adaptive:${ADAPTIVE_VERSION}${NC}"
echo ""

# Package and push monitoring chart
echo -e "${YELLOW}Packaging monitoring chart...${NC}"
helm package monitoring -d "${TEMP_DIR}"
MONITORING_VERSION=$(grep '^version:' monitoring/Chart.yaml | awk '{print $2}')
echo -e "${GREEN}✓ Packaged monitoring:${MONITORING_VERSION}${NC}"

echo -e "${YELLOW}Pushing monitoring:${MONITORING_VERSION} to OCI registry...${NC}"
helm push "${TEMP_DIR}/monitoring-${MONITORING_VERSION}.tgz" "oci://${OCI_REPO}"
echo -e "${GREEN}✓ Successfully pushed monitoring:${MONITORING_VERSION}${NC}"
echo ""

# Logout
echo -e "${YELLOW}Logging out from ${OCI_REGISTRY}...${NC}"
helm registry logout "$OCI_REGISTRY"
echo -e "${GREEN}✓ Logged out${NC}"
echo ""

# Summary
echo -e "${GREEN}=== Migration Complete ===${NC}"
echo ""
echo "Charts successfully migrated to ${OCI_REPO}:"
echo "  • adaptive:0.0.1"
echo "  • adaptive:0.0.2"
echo "  • adaptive:${ADAPTIVE_VERSION}"
echo "  • monitoring:${MONITORING_VERSION}"
echo ""
echo "Users can now install charts with:"
echo "  helm install adaptive oci://${OCI_REPO}/adaptive --version ${ADAPTIVE_VERSION}"
echo "  helm install monitoring oci://${OCI_REPO}/monitoring --version ${MONITORING_VERSION}"
echo ""
echo -e "${YELLOW}Note: Make sure to make the packages public in GitHub repository settings${NC}"
echo "Visit: https://github.com/orgs/${GITHUB_ORG}/packages"

