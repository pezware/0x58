"""
Authenticated symmetric encryption.

Uses AES-256-GCM via the cryptography library. The caller manages key
lifecycle; this module handles nonce generation, serialization, and
constant-time verification. Wire format:

    [12-byte nonce][16-byte tag][ciphertext...]
"""

from __future__ import annotations

import os
import struct

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

_NONCE_LEN = 12
_TAG_LEN = 16
_KEY_LEN = 32  # AES-256
_HEADER = struct.Struct(f"!{_NONCE_LEN}s")


def derive_key(passphrase: bytes, salt: bytes | None = None) -> tuple[bytes, bytes]:
    from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

    salt = salt or os.urandom(16)
    kdf = Scrypt(salt=salt, length=_KEY_LEN, n=2**17, r=8, p=1)
    return kdf.derive(passphrase), salt


def encrypt(plaintext: bytes, key: bytes, aad: bytes | None = None) -> bytes:
    if len(key) != _KEY_LEN:
        raise ValueError(f"key must be {_KEY_LEN} bytes, got {len(key)}")

    nonce = os.urandom(_NONCE_LEN)
    ct = AESGCM(key).encrypt(nonce, plaintext, aad)  # ct includes tag
    return nonce + ct


def decrypt(blob: bytes, key: bytes, aad: bytes | None = None) -> bytes:
    if len(blob) < _NONCE_LEN + _TAG_LEN:
        raise ValueError("ciphertext too short")

    nonce, ct = blob[:_NONCE_LEN], blob[_NONCE_LEN:]
    return AESGCM(key).decrypt(nonce, ct, aad)
