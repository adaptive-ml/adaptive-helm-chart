<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Scripts](#scripts)
  - [Table of Contents Generation](#table-of-contents-generation)
    - [generate-toc.sh](#generate-tocsh)
  - [Internal JWT Key Generation](#internal-jwt-key-generation)
    - [generate-internal-jwt-key.sh](#generate-internal-jwt-keysh)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Scripts

<!-- toc -->

- [generate-toc.sh](#generate-tocsh)
- [generate-internal-jwt-key.sh](#generate-internal-jwt-keysh)

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

## Internal JWT Key Generation

### generate-internal-jwt-key.sh

This script generates the PASETO V4 (Ed25519) keypair required by the Control Plane for signing internal API JWTs. The base64-encoded private key must be provided as `secrets.auth.internalJwtPrivateKeyV4Base64` (or as the `internalJwtPrivateKeyV4Base64` key of the existing control plane secret).

**Usage:**

```bash
./scripts/generate-internal-jwt-key.sh
```

**Output:**

```
Generating PASETO V4 key...
Private key (Base64): <64-byte base64 value>
Public key (Base64):  <32-byte base64 value>
```

Only the private key is needed by the chart. Store it in your secret manager — it must be the same on all servers of a cluster, and rotating it invalidates all in-flight internal JWTs.

**Requirements:**

- OpenSSL 3.x with Ed25519 support.
  - On macOS the system `openssl` is LibreSSL and does not support Ed25519. Install OpenSSL 3 with `brew install openssl@3`; the script auto-detects Homebrew installations. Set `OPENSSL=/path/to/openssl` to override the lookup.
  - On Linux distributions shipping OpenSSL >= 1.1.1, the bundled `openssl` already works.

**Generating the key without the script:**

The script is equivalent to the following OpenSSL invocation — clients that cannot run the script (e.g. on Windows) can reproduce it manually:

```bash
# 1. Generate an Ed25519 private key
openssl genpkey -algorithm ED25519 -out private.pem

# 2. Extract the 32-byte raw seed (last 32 bytes of the PKCS#8 DER encoding)
openssl pkey -in private.pem -outform DER | tail -c 32 > seed.bin

# 3. Extract the 32-byte raw public key (last 32 bytes of the SubjectPublicKeyInfo DER encoding)
openssl pkey -in private.pem -pubout -outform DER | tail -c 32 > public.bin

# 4. PASETO V4 secret key = seed || public (64 bytes), base64-encoded
cat seed.bin public.bin | base64 | tr -d '\n'
```
