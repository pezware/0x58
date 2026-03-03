"""
Tests for elite_crypto: correctness, edge cases, adversarial inputs,
and performance characterization.

Correctness uses hypothesis for property-based testing.
Performance uses statistical analysis over multiple samples to detect
regressions rather than asserting absolute thresholds (which break
across hardware).
"""

from __future__ import annotations

import os
import statistics
import time
import unittest

from hypothesis import given, settings, assume
from hypothesis.strategies import binary, integers

from elite_crypto import _KEY_LEN, _NONCE_LEN, _TAG_LEN, decrypt, derive_key, encrypt


# ── Helpers ──────────────────────────────────────────────────────────

def _random_key() -> bytes:
    return os.urandom(_KEY_LEN)


def _time_op(fn, *, rounds: int = 100) -> list[float]:
    """Return per-call durations in seconds."""
    times = []
    for _ in range(rounds):
        start = time.perf_counter()
        fn()
        times.append(time.perf_counter() - start)
    return times


# ── Correctness ──────────────────────────────────────────────────────

class TestRoundTrip(unittest.TestCase):

    @given(data=binary(min_size=0, max_size=64 * 1024))
    @settings(max_examples=200, deadline=None)
    def test_arbitrary_plaintext(self, data: bytes):
        key = _random_key()
        assert decrypt(encrypt(data, key), key) == data

    @given(data=binary(min_size=0, max_size=1024), aad=binary(min_size=1, max_size=64))
    @settings(max_examples=100, deadline=None)
    def test_with_aad(self, data: bytes, aad: bytes):
        key = _random_key()
        ct = encrypt(data, key, aad=aad)
        assert decrypt(ct, key, aad=aad) == data

    def test_empty_plaintext(self):
        key = _random_key()
        ct = encrypt(b"", key)
        assert decrypt(ct, key) == b""


class TestKeyDerivation(unittest.TestCase):

    def test_deterministic_with_same_salt(self):
        salt = os.urandom(16)
        k1, _ = derive_key(b"passphrase", salt)
        k2, _ = derive_key(b"passphrase", salt)
        assert k1 == k2

    def test_different_salt_different_key(self):
        k1, _ = derive_key(b"passphrase", os.urandom(16))
        k2, _ = derive_key(b"passphrase", os.urandom(16))
        assert k1 != k2

    def test_output_length(self):
        key, salt = derive_key(b"pw")
        assert len(key) == _KEY_LEN
        assert len(salt) == 16


# ── Adversarial / edge cases ────────────────────────────────────────

class TestAdversarial(unittest.TestCase):

    def test_wrong_key_rejects(self):
        ct = encrypt(b"secret", _random_key())
        with self.assertRaises(Exception):
            decrypt(ct, _random_key())

    def test_tampered_ciphertext_rejects(self):
        key = _random_key()
        ct = bytearray(encrypt(b"data", key))
        ct[-1] ^= 0xFF  # flip last byte
        with self.assertRaises(Exception):
            decrypt(bytes(ct), key)

    def test_tampered_nonce_rejects(self):
        key = _random_key()
        ct = bytearray(encrypt(b"data", key))
        ct[0] ^= 0xFF  # flip first nonce byte
        with self.assertRaises(Exception):
            decrypt(bytes(ct), key)

    def test_truncated_blob_rejects(self):
        key = _random_key()
        ct = encrypt(b"data", key)
        with self.assertRaises(ValueError):
            decrypt(ct[:_NONCE_LEN], key)

    def test_empty_blob_rejects(self):
        with self.assertRaises(ValueError):
            decrypt(b"", _random_key())

    def test_wrong_aad_rejects(self):
        key = _random_key()
        ct = encrypt(b"data", key, aad=b"context-a")
        with self.assertRaises(Exception):
            decrypt(ct, key, aad=b"context-b")

    def test_missing_aad_rejects(self):
        key = _random_key()
        ct = encrypt(b"data", key, aad=b"required")
        with self.assertRaises(Exception):
            decrypt(ct, key)  # no aad

    def test_bad_key_length(self):
        with self.assertRaises(ValueError):
            encrypt(b"data", b"short")

    @given(n=integers(min_value=1, max_value=27))
    def test_short_blobs_rejected(self, n: int):
        """Anything shorter than nonce+tag must be rejected."""
        assume(n < _NONCE_LEN + _TAG_LEN)
        with self.assertRaises((ValueError, Exception)):
            decrypt(os.urandom(n), _random_key())

    def test_nonce_uniqueness(self):
        """Two encryptions of same plaintext must produce different blobs."""
        key = _random_key()
        ct1 = encrypt(b"same", key)
        ct2 = encrypt(b"same", key)
        assert ct1 != ct2


# ── Performance characterization ────────────────────────────────────

class TestPerformance(unittest.TestCase):
    """
    Characterize throughput across message sizes. Reports median and p95
    rather than asserting thresholds — run on CI with benchmark tracking
    to detect regressions over time.
    """

    SIZES = [
        ("64B",   64),
        ("4KB",   4 * 1024),
        ("1MB",   1024 * 1024),
    ]

    def test_throughput_table(self):
        key = _random_key()
        print("\n  ┌─────────┬──────────────┬──────────────┬──────────────┐")
        print("  │  Size   │  Median (μs) │  P95 (μs)    │  MB/sec      │")
        print("  ├─────────┼──────────────┼──────────────┼──────────────┤")

        for label, size in self.SIZES:
            data = os.urandom(size)
            rounds = 1000 if size < 100_000 else 50

            durations = _time_op(lambda: decrypt(encrypt(data, key), key), rounds=rounds)
            med = statistics.median(durations)
            p95 = sorted(durations)[int(len(durations) * 0.95)]
            mbps = (size / med) / (1024 * 1024) if med > 0 else float("inf")

            print(f"  │ {label:<7} │ {med*1e6:>10,.0f}   │ {p95*1e6:>10,.0f}   │ {mbps:>10,.1f}   │")

        print("  └─────────┴──────────────┴──────────────┴──────────────┘")

    def test_key_derivation_cost(self):
        """Key derivation should be intentionally slow (scrypt)."""
        durations = _time_op(lambda: derive_key(b"password"), rounds=3)
        med = statistics.median(durations)
        print(f"\n  Key derivation (scrypt): {med*1000:,.0f} ms")
        # scrypt with n=2^17 should take at least 50ms on modern hardware
        self.assertGreater(med, 0.01, "Key derivation suspiciously fast")


if __name__ == "__main__":
    unittest.main(verbosity=2)
