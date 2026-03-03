import time
from intern_crypto import encrypt, decrypt

# test basic
key = "mysecret"
message = "hello world"
encrypted = encrypt(message, key)
decrypted = decrypt(encrypted, key)
if decrypted == message:
    print("PASS: basic test")
else:
    print("FAIL: basic test")

# test empty string
try:
    encrypted2 = encrypt("", key)
    decrypted2 = decrypt(encrypted2, key)
    if decrypted2 == "":
        print("PASS: empty string")
    else:
        print("FAIL: empty string")
except:
    print("FAIL: empty string crashed")

# test long string
long_message = "a" * 10000
encrypted3 = encrypt(long_message, key)
decrypted3 = decrypt(encrypted3, key)
if decrypted3 == long_message:
    print("PASS: long string")
else:
    print("FAIL: long string")

# test special characters
special = "hello!@#$%^&*()_+-=[]{}|;':\",./<>?"
encrypted4 = encrypt(special, key)
decrypted4 = decrypt(encrypted4, key)
if decrypted4 == special:
    print("PASS: special characters")
else:
    print("FAIL: special characters")

# test numbers in string
encrypted5 = encrypt("12345", key)
decrypted5 = decrypt(encrypted5, key)
if decrypted5 == "12345":
    print("PASS: numbers")
else:
    print("FAIL: numbers")

# test empty key
try:
    encrypt("hello", "")
    print("FAIL: empty key should fail")
except:
    print("PASS: empty key fails")

# test unicode
try:
    encrypted6 = encrypt("こんにちは", key)
    decrypted6 = decrypt(encrypted6, key)
    if decrypted6 == "こんにちは":
        print("PASS: unicode")
    else:
        print("FAIL: unicode")
except:
    print("FAIL: unicode crashed")

# performance test
print("\n--- Performance ---")
start = time.time()
for i in range(10000):
    encrypted = encrypt("hello world this is a test message", key)
    decrypted = decrypt(encrypted, key)
end = time.time()
print(f"10000 encrypt+decrypt cycles: {end - start:.3f} seconds")

# test with bigger data
start = time.time()
big_data = "x" * 1000000
encrypted = encrypt(big_data, key)
decrypted = decrypt(encrypted, key)
end = time.time()
print(f"1MB encrypt+decrypt: {end - start:.3f} seconds")
