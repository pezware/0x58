"""Simple symmetric encryption using XOR cipher with base64 encoding."""

import base64
from typing import Union


def encrypt(plaintext: str, key: str) -> str:
    """Encrypt plaintext using repeating-key XOR."""
    if not key:
        raise ValueError("Key must not be empty")

    key_bytes = key.encode("utf-8")
    plain_bytes = plaintext.encode("utf-8")

    cipher_bytes = bytes(
        pb ^ key_bytes[i % len(key_bytes)]
        for i, pb in enumerate(plain_bytes)
    )
    return base64.b64encode(cipher_bytes).decode("ascii")


def decrypt(ciphertext: str, key: str) -> str:
    """Decrypt base64-encoded XOR ciphertext."""
    if not key:
        raise ValueError("Key must not be empty")

    key_bytes = key.encode("utf-8")
    cipher_bytes = base64.b64decode(ciphertext)

    plain_bytes = bytes(
        cb ^ key_bytes[i % len(key_bytes)]
        for i, cb in enumerate(cipher_bytes)
    )
    return plain_bytes.decode("utf-8")


if __name__ == "__main__":
    key = "mysecretkey"
    message = "hello world"

    encrypted = encrypt(message, key)
    print(f"Encrypted: {encrypted}")

    decrypted = decrypt(encrypted, key)
    print(f"Decrypted: {decrypted}")

    assert decrypted == message, "Round-trip failed"
