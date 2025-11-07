#!/bin/bash

# Script to generate/update Table of Contents for all markdown files
# Uses markdown-toc (https://github.com/jonschlinkert/markdown-toc)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Installing markdown-toc..."
npm install -g markdown-toc

echo -e "\n${GREEN}Finding all markdown files...${NC}"
MARKDOWN_FILES=$(find . -type f -name "*.md" -not -path "./node_modules/*" -not -path "./.git/*")

echo -e "${GREEN}Generating TOC for markdown files...${NC}\n"

for file in $MARKDOWN_FILES; do
    echo "Processing: $file"

    # Generate TOC with options:
    # --bullets: use - for bullets
    # --maxdepth: limit TOC depth to 3 levels
    # --no-firsth1: don't include the first h1 in TOC
    markdown-toc -i --bullets "-" --maxdepth 3 --no-firsth1 "$file"

    echo -e "  ${GREEN}✓${NC} TOC updated"
done

echo -e "\n${GREEN}✓ All TOCs generated successfully!${NC}"
