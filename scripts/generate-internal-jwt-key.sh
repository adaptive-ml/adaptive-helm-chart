#!/usr/bin/env bash
# Generate a PASETO V4 public-key keypair (Ed25519), base64-encoded.
# The private key is meant to be set as `secrets.auth.internalJwtPrivateKeyV4Base64`
# (or the `internalJwtPrivateKeyV4Base64` key of an existing control plane secret).
set -euo pipefail

# macOS ships LibreSSL as /usr/bin/openssl, which lacks Ed25519. Prefer a real
# OpenSSL (e.g. from Homebrew) if one is on PATH or installed in the common
# Homebrew locations.
find_openssl() {
    for candidate in \
        "${OPENSSL:-}" \
        /opt/homebrew/opt/openssl@3/bin/openssl \
        /opt/homebrew/opt/openssl/bin/openssl \
        /usr/local/opt/openssl@3/bin/openssl \
        /usr/local/opt/openssl/bin/openssl \
        openssl; do
        [ -z "$candidate" ] && continue
        if "$candidate" list -public-key-algorithms 2>/dev/null | grep -qi ed25519; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

OPENSSL_BIN=$(find_openssl) || {
    echo "error: could not find an OpenSSL binary with Ed25519 support" >&2
    echo "install OpenSSL 3.x (e.g. 'brew install openssl@3') or set OPENSSL=/path/to/openssl" >&2
    exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$OPENSSL_BIN" genpkey -algorithm ED25519 -out "$tmp/private.pem"

# Last 32 bytes of Ed25519 PKCS#8 DER == raw seed / raw public key
"$OPENSSL_BIN" pkey -in "$tmp/private.pem" -outform DER | tail -c 32 >"$tmp/seed.bin"
"$OPENSSL_BIN" pkey -in "$tmp/private.pem" -pubout -outform DER | tail -c 32 >"$tmp/public.bin"

# PASETO V4 secret key = seed || public (64 bytes)
cat "$tmp/seed.bin" "$tmp/public.bin" >"$tmp/secret.bin"

private_b64=$(base64 <"$tmp/secret.bin" | tr -d '\n')
public_b64=$(base64 <"$tmp/public.bin" | tr -d '\n')

echo "Generating PASETO V4 key..."
echo "Private key (Base64): $private_b64"
echo "Public key (Base64): $public_b64"
