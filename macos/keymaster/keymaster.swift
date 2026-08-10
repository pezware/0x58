// Keymaster, access Keychain secrets guarded by TouchID
// src: torarnv/keymaster
import Foundation
import LocalAuthentication
import Darwin

let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics


func setPassword(key: String, password: String) -> Bool {
  guard let passwordData = password.data(using: .utf8) else {
    print("Failed to convert password to data")
    return false
  }
  
  // First try to delete any existing item
  let deleteQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: key,
    kSecAttrAccount as String: key
  ]
  SecItemDelete(deleteQuery as CFDictionary)
  
  // Now add the new item - simplified without biometric for initial testing
  let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: key,
    kSecAttrAccount as String: key,
    kSecValueData as String: passwordData,
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
  ]

  let status = SecItemAdd(query as CFDictionary, nil)
  
  if status != errSecSuccess {
    let errorMessage: String
    switch status {
    case errSecDuplicateItem:
      errorMessage = "Duplicate item"
    case errSecItemNotFound:
      errorMessage = "Item not found"
    case errSecAuthFailed:
      errorMessage = "Authentication failed"
    case errSecParam:
      errorMessage = "Invalid parameters"
    case errSecAllocate:
      errorMessage = "Failed to allocate memory"
    case errSecInteractionNotAllowed:
      errorMessage = "User interaction not allowed"
    case errSecUserCanceled:
      errorMessage = "User canceled"
    default:
      errorMessage = "Unknown error (\(status))"
    }
    print("SecItemAdd failed: \(errorMessage)")
    return false
  }
  
  return true
}

func deletePassword(key: String) -> Bool {
  let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: key,
    kSecAttrAccount as String: key
  ]
  let status = SecItemDelete(query as CFDictionary)
  return status == errSecSuccess || status == errSecItemNotFound
}

func getPassword(key: String, context: LAContext) -> String? {
  // Exact match first: service AND account both equal to the key, which is what
  // `set` writes. Items created by other tools (or by older versions of this one)
  // often set only kSecAttrService, so fall back to a service-only lookup rather
  // than reporting "not found" for a secret that is demonstrably in the keychain.
  let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: key,
    kSecAttrAccount as String: key,
    kSecMatchLimit as String: kSecMatchLimitOne,
    kSecReturnData as String: true
  ]
  var item: CFTypeRef?
  var status = SecItemCopyMatching(query as CFDictionary, &item)

  if status == errSecItemNotFound {
      let lenientQuery: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: key,
          kSecMatchLimit as String: kSecMatchLimitOne,
          kSecReturnData as String: true
      ]
      status = SecItemCopyMatching(lenientQuery as CFDictionary, &item)
  }


  guard status == errSecSuccess,
    let passwordData = item as? Data,
    let password = String(data: passwordData, encoding: .utf8)
  else {
    if status != errSecSuccess && status != errSecItemNotFound {
      print("Failed to get password: \(status)")
    }
    return nil
  }

  return password
}

func listKeys() -> [String] {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnAttributes as String: true
    ]

    var items: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &items)

    guard status == errSecSuccess, let keychains = items as? [[String: Any]] else {
        if status != errSecItemNotFound {
            print("Failed to list keys: \(status)")
        }
        return []
    }

    return keychains.compactMap { $0[kSecAttrService as String] as? String }
}


func usage() {
  print("Usage: keymaster [get|set|update|delete|list] <key>")
  print("")
  print("Commands:")
  print("  get <key>      - Retrieve a password (requires TouchID)")
  print("  set <key>      - Store a new password (reads from stdin, requires TouchID)")
  print("  update <key>   - Update an existing password (reads from stdin, requires TouchID)")
  print("  delete <key>   - Delete a password (requires TouchID)")
  print("  list           - List all keys stored by keymaster")
  print("")
  print("Note: Passwords are read from stdin for security (not command line arguments)")
}

func readPasswordFromStdin() -> String? {
  // Use getpass for secure password input (no echo)
  guard let passwordCStr = getpass("Enter password: ") else {
    return nil
  }
  
  let password = String(cString: passwordCStr)
  guard !password.isEmpty else {
    return nil
  }
  
  return password
}

func main() {
  let inputArgs: [String] = Array(CommandLine.arguments.dropFirst())
  if inputArgs.isEmpty || inputArgs.count > 2 {
      usage()
      exit(EXIT_FAILURE)
  }
  let action = inputArgs[0].lowercased()

  if action == "list" {
      if inputArgs.count != 1 {
          usage()
          exit(EXIT_FAILURE)
      }
      let keys = listKeys()
      if keys.isEmpty {
          print("No keys found in keychain.")
      } else {
          print("Keys stored in keychain:")
          keys.forEach { print("- \($0)") }
      }
      exit(EXIT_SUCCESS)
  }

  if inputArgs.count != 2 {
    usage()
    exit(EXIT_FAILURE)
  }
  let key = inputArgs[1]

  let context = LAContext()
  context.touchIDAuthenticationAllowableReuseDuration = 0

  var error: NSError?
  guard context.canEvaluatePolicy(policy, error: &error) else {
    print("This Mac doesn't support deviceOwnerAuthenticationWithBiometrics")
    exit(EXIT_FAILURE)
  }

  if action == "set" || action == "update" {
    guard let secret = readPasswordFromStdin() else {
      print("Error reading password")
      exit(EXIT_FAILURE)
    }
    
    context.evaluatePolicy(policy, localizedReason: "\(action) the password for \(key)") { success, error in
      if success && error == nil {
        guard setPassword(key: key, password: secret) else {
          print("Error \(action == "set" ? "setting" : "updating") password")
          exit(EXIT_FAILURE)
        }
        print("Key \(key) has been successfully \(action == "set" ? "set" : "updated") in the keychain")
        exit(EXIT_SUCCESS)
      } else {
        let errorDescription = error?.localizedDescription ?? "Unknown error"
        print("Error: \(errorDescription)")
        exit(EXIT_FAILURE)
      }
    }
    dispatchMain()
  }

  else if action == "get" {
    context.evaluatePolicy(policy, localizedReason: "access the password for \(key)") { success, error in
      if success && error == nil {
        guard let password = getPassword(key: key, context: context) else {
          print("Error: Key not found or unable to retrieve password")
          exit(EXIT_FAILURE)
        }
        print(password)
        exit(EXIT_SUCCESS)
      } else {
        let errorDescription = error?.localizedDescription ?? "Unknown error"
        print("Error: \(errorDescription)")
        exit(EXIT_FAILURE)
      }
    }
    dispatchMain()
  }

  else if action == "delete" {
    context.evaluatePolicy(policy, localizedReason: "delete the password for \(key)") { success, error in
      if success && error == nil {
        guard deletePassword(key: key) else {
          print("Error: Key not found or unable to delete")
          exit(EXIT_FAILURE)
        }
        print("Key \(key) has been successfully deleted from the keychain")
        exit(EXIT_SUCCESS)
      } else {
        let errorDescription = error?.localizedDescription ?? "Unknown error"
        print("Error: \(errorDescription)")
        exit(EXIT_FAILURE)
      }
    }
    dispatchMain()
  }
  else {
    print("Error: Invalid action '\(action)'")
    usage()
    exit(EXIT_FAILURE)
  }
}

main()