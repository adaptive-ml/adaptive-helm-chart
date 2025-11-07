#!/bin/bash

# Script to generate/update Table of Contents for all markdown files
# Uses doctoc (https://github.com/thlorenz/doctoc)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Installing doctoc..."
npm install -g doctoc

echo -e "\n${GREEN}Finding all markdown files...${NC}"
MARKDOWN_FILES=$(find . -type f -name "*.md" -not -path "./node_modules/*" -not -path "./.git/*")

echo -e "${GREEN}Generating TOC for markdown files...${NC}\n"

for file in $MARKDOWN_FILES; do
    echo "Processing: $file"

    # Generate TOC with options:
    # --github: optimize for GitHub rendering
    # --maxlevel: limit TOC depth to 3 levels for cleaner appearance
    # --notitle: don't add "Table of Contents" title (we have our own)
    doctoc --notitle --github --maxlevel 3 "$file"

    echo -e "  ${GREEN}✓${NC} TOC updated"
done

echo -e "\n${GREEN}✓ All TOCs generated successfully!${NC}"
