# Crypto Alternatives

Freechains needs three primitives:

| Primitive | Kotlin original | What for |
|---|---|---|
| Symmetric encryption | NaCl SecretBox (XSalsa20-Poly1305) | Shared/private chains (`$name`) |
| Asymmetric encryption | NaCl SealedBox (X25519+XSalsa20-Poly1305) | Identity chains (`@pub`), DMs |
| Digital signature | Ed25519 | Block authorship, reputation identity |

---

## Alternatives

| Tool | Symmetric | Asymmetric | Signing | Deps | Language | Notes |
|---|---|---|---|---|---|---|
| **openssl** | AES-256-CBC | X25519 + AES-256-CBC | Ed25519 (`-rawin`) | none (system) | CLI | Current choice. Requires OpenSSL 3.0+ for Ed25519/X25519. Fixed IV is a simplification — production should use random IV. |
| **luasodium** | `crypto_secretbox` | `crypto_box_seal` | `crypto_sign` | libsodium + Lua binding | Lua | Closest to Kotlin original. NaCl API, nonce handling built in. Best choice once Lua is the main language. |
| **age** | ✅ (passphrase mode) | ✅ (X25519) | ❌ | `age` binary | CLI | Modern, simple. No signing — would need a second tool. |
| **minisign** | ❌ | ❌ | ✅ (Ed25519) | `minisign` binary | CLI | Signing only. Would need openssl or age for encryption. |
| **gpg** | ✅ | ✅ | ✅ | GnuPG | CLI | Heavyweight, complex keyring management. Overkill. |
| **libsodium CLI** | ✅ | ✅ | ✅ | libsodium | C | Would need a small C wrapper or use `sodium` CLI tools (not standard). |
| **tweetnacl-lua** | `crypto_secretbox` | `crypto_box` | `crypto_sign` | pure Lua | Lua | Pure Lua NaCl implementation. No C deps but slower. Educational. |

---

## Current implementation: openssl

Wrapper: `tst/fc-crypto.sh`

| Command | What it does | OpenSSL operation |
|---|---|---|
| `keygen <dir>` | Generate Ed25519 + X25519 keypairs | `genpkey -algorithm ed25519`, `genpkey -algorithm X25519` |
| `pubkey <dir>` | Extract raw 32-byte Ed25519 public key (hex) | `pkey -pubin -outform DER \| tail -c 32` |
| `sign <dir>` | Sign stdin with Ed25519, output base64 | `pkeyutl -sign -rawin` |
| `verify <dir> <sig>` | Verify Ed25519 signature | `pkeyutl -verify -pubin -rawin` |
| `shared-key <pass>` | Derive 256-bit key from passphrase | `dgst -sha256` |
| `shared-encrypt <key>` | AES-256-CBC encrypt stdin to base64 | `enc -aes-256-cbc -nosalt -base64` |
| `shared-decrypt <key>` | AES-256-CBC decrypt base64 to stdout | `enc -d -aes-256-cbc -nosalt -base64` |
| `seal-encrypt <pub> <eph>` | X25519 key exchange + AES-256-CBC | `pkeyutl -derive` + `enc -aes-256-cbc` |
| `seal-decrypt <pvt> <eph>` | X25519 key exchange + AES-256-CBC decrypt | `pkeyutl -derive` + `enc -d -aes-256-cbc` |

### Limitations

- Fixed IV (`0000...`) — all encryptions with the same key reuse the IV. Fine for testing, not for production.
- No AEAD — AES-CBC has no authentication. Ciphertext can be silently corrupted.
- Separate keypairs — Ed25519 for signing, X25519 for encryption (can't reuse).
- Shell-level only — not embeddable in Lua without `io.popen`.

---

## Recommended path

1. **Now**: openssl CLI for tests — zero dependencies, validates the protocol
2. **Next**: luasodium for the Lua implementation — NaCl API matches Kotlin original exactly
3. **Optional**: tweetnacl-lua if zero-C-dependency Lua is needed
