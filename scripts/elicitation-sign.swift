// Élicitation signée mag — enroll / sign (P-256 + Touch ID).
// Usage :
//   swift scripts/elicitation-sign.swift enroll <public.der path>
//   swift scripts/elicitation-sign.swift sign '<canonical-json>'
// Exit : 0 ok, 1 refus/erreur, 2 biométrie / keychain indisponible
//
// Ordre d'enrôlement :
//   1) Secure Enclave + ACL biométrie
//   2) Keychain logiciel + ACL biométrie
//   3) Keychain logiciel (privateKeyUsage seul)
//   4) Fichier private.p256 à côté de public.der + Touch ID à chaque sign
//      (nécessaire : scripts `swift` non signés → errSecMissingEntitlement -34018)
import Foundation
import CryptoKit
import LocalAuthentication
import Security

let keyTag = "com.mag.elicitation.v1".data(using: .utf8)!
let privateFileName = "private.p256"

func die(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

func elicitationDir(fromPublic path: String? = nil) -> URL {
    if let path, !path.isEmpty {
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }
    if let env = ProcessInfo.processInfo.environment["GWSA_ELICITATION_DIR"], !env.isEmpty {
        return URL(fileURLWithPath: env)
    }
    if let root = ProcessInfo.processInfo.environment["GWSA_ROOT"], !root.isEmpty {
        return URL(fileURLWithPath: root).appendingPathComponent(".elicitation")
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".config/gws-accounts/.elicitation")
}

func privateFileURL(dir: URL) -> URL {
    dir.appendingPathComponent(privateFileName)
}

func accessControl(biometry: Bool) -> SecAccessControl? {
    var err: Unmanaged<CFError>?
    var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
    if biometry {
        flags.insert(.biometryCurrentSet)
    }
    return SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        flags,
        &err
    )
}

func loadKeychainPrivateKey() -> SecKey? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: keyTag,
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let ref = item else { return nil }
    return (ref as! SecKey)
}

func exportPublicDER(_ pub: SecKey) -> Data {
    var err: Unmanaged<CFError>?
    guard let ext = SecKeyCopyExternalRepresentation(pub, &err) else {
        die("export clé publique : \(err.debugDescription)")
    }
    let raw = ext as Data
    // SPKI P-256 (RFC 5480)
    let header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]
    return Data(header) + raw
}

func exportPublicDER(from cryptoPub: P256.Signing.PublicKey) -> Data {
    let raw = cryptoPub.x963Representation
    let header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]
    return Data(header) + raw
}

func writePublic(_ data: Data, to path: String) {
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! data.write(to: url)
    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
}

@discardableResult
func tryCreateKeychainKey(secureEnclave: Bool, biometry: Bool) -> SecKey? {
    guard let ac = accessControl(biometry: biometry) else { return nil }
    var attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecPrivateKeyAttrs as String: [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrAccessControl as String: ac,
        ] as [String: Any],
    ]
    if secureEnclave {
        attrs[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
    }
    var err: Unmanaged<CFError>?
    return SecKeyCreateRandomKey(attrs as CFDictionary, &err)
}

func enrollFileBased(to path: String) {
    let dir = elicitationDir(fromPublic: path)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let priv = P256.Signing.PrivateKey()
    let privURL = privateFileURL(dir: dir)
    try! priv.rawRepresentation.write(to: privURL)
    try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privURL.path)
    writePublic(exportPublicDER(from: priv.publicKey), to: path)
    print("{\"ok\":true,\"secure_enclave\":false,\"storage\":\"file\",\"note\":\"Keychain/SE inaccessible — clé fichier + Touch ID à chaque signature\"}")
}

func enroll(to path: String) {
    if let priv = loadKeychainPrivateKey() {
        guard let pub = SecKeyCopyPublicKey(priv) else { die("clé publique introuvable") }
        writePublic(exportPublicDER(pub), to: path)
        // Nettoyer un éventuel ancien fichier privé
        let privURL = privateFileURL(dir: elicitationDir(fromPublic: path))
        try? FileManager.default.removeItem(at: privURL)
        print("{\"ok\":true,\"reused\":true,\"storage\":\"keychain\"}")
        return
    }
    let filePriv = privateFileURL(dir: elicitationDir(fromPublic: path))
    if FileManager.default.fileExists(atPath: filePriv.path),
       let raw = try? Data(contentsOf: filePriv),
       let existing = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
        writePublic(exportPublicDER(from: existing.publicKey), to: path)
        print("{\"ok\":true,\"reused\":true,\"storage\":\"file\"}")
        return
    }

    // 1) SE + biometrie
    if let priv = tryCreateKeychainKey(secureEnclave: true, biometry: true) {
        guard let pub = SecKeyCopyPublicKey(priv) else { die("clé publique") }
        writePublic(exportPublicDER(pub), to: path)
        print("{\"ok\":true,\"secure_enclave\":true,\"storage\":\"keychain\"}")
        return
    }
    // 2) Keychain logiciel + biometrie
    if let priv = tryCreateKeychainKey(secureEnclave: false, biometry: true) {
        guard let pub = SecKeyCopyPublicKey(priv) else { die("clé publique") }
        writePublic(exportPublicDER(pub), to: path)
        print("{\"ok\":true,\"secure_enclave\":false,\"storage\":\"keychain\"}")
        return
    }
    // 3) Keychain sans ACL biométrie (Touch ID demandé à part au sign)
    if let priv = tryCreateKeychainKey(secureEnclave: false, biometry: false) {
        guard let pub = SecKeyCopyPublicKey(priv) else { die("clé publique") }
        writePublic(exportPublicDER(pub), to: path)
        print("{\"ok\":true,\"secure_enclave\":false,\"storage\":\"keychain\",\"biometry_acl\":false}")
        return
    }
    // 4) Fichier — seul chemin fiable pour `swift script.swift` non signé (-34018)
    enrollFileBased(to: path)
}

func promptText(from obj: [String: Any]) -> String {
    let action = obj["action"] as? String ?? ""
    let alias = obj["alias"] as? String ?? ""
    let email = obj["email"] as? String ?? ""
    let target = obj["target"] as? String ?? ""
    let sid = obj["session_id"] as? String ?? ""
    let minutes = obj["minutes"] as? Int ?? 0
    let hours = obj["hours"] as? Int ?? 0
    // Nommer le compte à l'instant d'autoriser (fiche 0047) — aligné sur
    // gateway/elicitation.py:prompt_from_payload. Repli alias seul si inconnu.
    let who = email.isEmpty ? "« \(alias) »" : "« \(alias) » (\(email))"
    let acct = email.isEmpty ? alias : "\(alias) · \(email)"
    switch action {
    case "session_unlock":
        return "mag : déverrouiller \(who) pour la session \(sid) (\(minutes) min)"
    case "unlock":
        if target == "off" { return "mag : retirer le verrou permanent sur \(who)" }
        return "mag : déverrouiller \(who) (\(minutes > 0 ? String(minutes) : target) min, poste entier)"
    case "session_grant":
        return "mag : zone session \(sid) — « \(target) » (\(acct), \(hours) h)"
    case "grant":
        return "mag : autoriser l'écriture Drive « \(target) » (\(acct), \(hours) h)"
    case "project_sign":
        return "mag : signer le manifeste projet (.mag/)"
    case "add_account":
        return "mag : connecter le compte Google « \(alias) » (\(target))"
    case "revoke_descendants":
        return "mag : révoquer les sous-sessions de \(sid.isEmpty ? target : sid)"
    case "strongauth_off":
        return "mag : désactiver l'authentification forte"
    default:
        return "mag : \(action) — \(alias) \(target)"
    }
}

func requireTouchID(reason: String) {
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
        die(
            "biométrie indisponible (\(err?.localizedDescription ?? "?"))",
            code: 2
        )
    }
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
        ok = success
        sem.signal()
    }
    sem.wait()
    if !ok {
        die("refusé par l'utilisateur", code: 1)
    }
}

func signWithSecKey(_ priv: SecKey, data: Data, reason: String) -> Data {
    // ACL biométrie → prompt système via SecKey ; sinon on a déjà fait Touch ID.
    var err: Unmanaged<CFError>?
    guard let sig = SecKeyCreateSignature(
        priv,
        .ecdsaSignatureMessageX962SHA256,
        data as CFData,
        &err
    ) else {
        let msg = (err?.takeRetainedValue() as Error?)?.localizedDescription ?? "signature refusée"
        if msg.lowercased().contains("cancel") || msg.lowercased().contains("user") {
            die("refusé par l'utilisateur", code: 1)
        }
        die(msg, code: 2)
    }
    _ = reason
    return sig as Data
}

func signWithFileKey(data: Data, reason: String) -> Data {
    let privURL = privateFileURL(dir: elicitationDir())
    guard let raw = try? Data(contentsOf: privURL),
          let priv = try? P256.Signing.PrivateKey(rawRepresentation: raw) else {
        die("clé fichier absente — mag elicitation enroll", code: 2)
    }
    requireTouchID(reason: reason)
    do {
        let sig = try priv.signature(for: data)
        return sig.derRepresentation
    } catch {
        die("signature fichier : \(error)", code: 2)
    }
}

func signPayload(_ json: String) {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        die("payload JSON invalide")
    }
    let reason = promptText(from: obj)
    let sigData: Data
    if let priv = loadKeychainPrivateKey() {
        // Sans ACL biométrie sur la clé, forcer Touch ID avant signature.
        // Avec ACL, SecKeyCreateSignature redemandera — on évite le double prompt
        // en ne pré-appelant Touch ID que si le fichier privé n'existe pas… :
        // Heuristique : toujours pré-authentifier (deviceOwnerAuthentication) pour
        // un prompt unique avec le texte métier ; SecKey réutilise le contexte
        // si possible. En pratique sur keychain sans ACL, c'est obligatoire.
        requireTouchID(reason: reason)
        sigData = signWithSecKey(priv, data: data, reason: reason)
    } else if FileManager.default.fileExists(atPath: privateFileURL(dir: elicitationDir()).path) {
        sigData = signWithFileKey(data: data, reason: reason)
    } else {
        die("clé non enrôlée — mag elicitation enroll", code: 2)
    }
    let b64 = sigData.base64EncodedString()
    let out: [String: Any] = [
        "signature": "p256:" + b64,
        "prompt": reason,
        "payload_hash": SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined(),
    ]
    let outData = try! JSONSerialization.data(withJSONObject: out)
    FileHandle.standardOutput.write(outData)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

guard CommandLine.arguments.count >= 2 else {
    die("usage : enroll <pub.der> | sign <json>")
}
let cmd = CommandLine.arguments[1]
switch cmd {
case "enroll":
    guard CommandLine.arguments.count >= 3 else { die("usage : enroll <public.der>") }
    enroll(to: CommandLine.arguments[2])
case "sign":
    guard CommandLine.arguments.count >= 3 else { die("usage : sign <json>") }
    signPayload(CommandLine.arguments[2])
default:
    die("commande inconnue : \(cmd)")
}
