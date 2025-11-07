# Scripts

<!-- toc -->

- [generate-toc.sh](#generate-tocsh)

<!-- tocstop -->

## Table of Contents Generation

### generate-toc.sh

This script automatically generates and updates Table of Contents for all markdown files in the repository.

**Usage:**

```bash
./scripts/generate-toc.sh
```

**What it does:**

1. Installs `markdown-toc` globally via npm
2. Finds all `.md` files in the repository (excluding `node_modules` and `.git`)
3. Generates/updates TOC for each file based on HTML comment markers

**Adding TOC to new markdown files:**

To add automatic TOC generation to a new markdown file, add two HTML comment markers where you want the TOC to appear:
- Opening marker starts with `<!--` followed by space, `toc`, space, and `-->`
- Closing marker starts with `<!--` followed by space, `tocstop`, space, and `-->`

Example placement in a file (add the actual markers between these lines):
```
# My Document Title
[Place opening marker here]
[Place closing marker here]
## First Section
```

Then run `./scripts/generate-toc.sh` to populate the TOC.

**CI Integration:**

The CI pipeline automatically checks that all TOCs are up-to-date on every pull request. If you modify headers in any markdown file, make sure to run `./scripts/generate-toc.sh` before committing your changes.
