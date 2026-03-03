import base64

def encrypt(text, key):
    result = ""
    for i in range(len(text)):
        char = text[i]
        key_char = key[i % len(key)]
        encrypted_char = chr(ord(char) + ord(key_char))
        result = result + encrypted_char
    encrypted_bytes = base64.b64encode(result.encode())
    return encrypted_bytes

def decrypt(text, key):
    decoded = base64.b64decode(text).decode()
    result = ""
    for i in range(len(decoded)):
        char = decoded[i]
        key_char = key[i % len(key)]
        decrypted_char = chr(ord(char) - ord(key_char))
        result = result + decrypted_char
    return result

# test
key = "mysecret"
message = "hello world"
print("original: " + message)
encrypted = encrypt(message, key)
print("encrypted: " + str(encrypted))
decrypted = decrypt(encrypted, key)
print("decrypted: " + decrypted)
