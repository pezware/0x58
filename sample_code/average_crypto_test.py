"""Tests and benchmarks for average_crypto module."""

import timeit
import unittest

from average_crypto import decrypt, encrypt


class TestEncryptDecrypt(unittest.TestCase):
    """Round-trip and edge-case tests."""

    def test_round_trip(self):
        ct = encrypt("hello world", "secret")
        self.assertEqual(decrypt(ct, "secret"), "hello world")

    def test_empty_plaintext(self):
        ct = encrypt("", "key")
        self.assertEqual(decrypt(ct, "key"), "")

    def test_empty_key_raises(self):
        with self.assertRaises(ValueError):
            encrypt("hello", "")

    def test_empty_key_decrypt_raises(self):
        with self.assertRaises(ValueError):
            decrypt("aGVsbG8=", "")

    def test_unicode(self):
        msg = "日本語テスト 🎉"
        ct = encrypt(msg, "key")
        self.assertEqual(decrypt(ct, "key"), msg)

    def test_special_characters(self):
        msg = "!@#$%^&*()_+-=[]{}|;':\",./<>?\n\t"
        ct = encrypt(msg, "key123")
        self.assertEqual(decrypt(ct, "key123"), msg)

    def test_long_message(self):
        msg = "a" * 100_000
        ct = encrypt(msg, "k")
        self.assertEqual(decrypt(ct, "k"), msg)

    def test_key_longer_than_message(self):
        ct = encrypt("hi", "a_very_long_key_that_exceeds_message")
        self.assertEqual(decrypt(ct, "a_very_long_key_that_exceeds_message"), "hi")

    def test_single_char_key(self):
        ct = encrypt("test message", "x")
        self.assertEqual(decrypt(ct, "x"), "test message")

    def test_wrong_key_fails(self):
        ct = encrypt("secret data", "right_key")
        result = decrypt(ct, "wrong_key")
        self.assertNotEqual(result, "secret data")

    def test_invalid_base64_raises(self):
        with self.assertRaises(Exception):
            decrypt("not-valid-base64!!!", "key")

    def test_binary_like_content(self):
        msg = "".join(chr(i) for i in range(1, 128))
        ct = encrypt(msg, "key")
        self.assertEqual(decrypt(ct, "key"), msg)


class TestPerformance(unittest.TestCase):
    """Basic throughput benchmarks."""

    def _throughput(self, size: int, iterations: int) -> float:
        msg = "x" * size
        key = "benchmarkkey"

        def run():
            decrypt(encrypt(msg, key), key)

        total = timeit.timeit(run, number=iterations)
        ops_per_sec = iterations / total
        return ops_per_sec

    def test_small_message_throughput(self):
        ops = self._throughput(64, 10_000)
        print(f"\n  64B messages: {ops:,.0f} ops/sec")
        self.assertGreater(ops, 100, "Unreasonably slow for 64B")

    def test_medium_message_throughput(self):
        ops = self._throughput(4096, 5_000)
        print(f"\n  4KB messages: {ops:,.0f} ops/sec")
        self.assertGreater(ops, 50, "Unreasonably slow for 4KB")

    def test_large_message_throughput(self):
        ops = self._throughput(1_000_000, 10)
        print(f"\n  1MB messages: {ops:,.0f} ops/sec")
        self.assertGreater(ops, 1, "Unreasonably slow for 1MB")


if __name__ == "__main__":
    unittest.main(verbosity=2)
