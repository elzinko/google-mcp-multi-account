// Authentification forte locale pour gwsa (élicitation) : Touch ID, Apple Watch
// ou mot de passe de session macOS en secours (.deviceOwnerAuthentication).
// Exit 0 = authentifié, 1 = refusé/échec, 2 = indisponible.
// Usage : swift scripts/touchid.swift "raison affichée dans la boîte système"
import Foundation
import LocalAuthentication

let reason = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "autoriser cette action gwsa"

let ctx = LAContext()
var err: NSError?
guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
    FileHandle.standardError.write(
        "touchid : indisponible (\(err?.localizedDescription ?? "?"))\n".data(using: .utf8)!)
    exit(2)
}

let sem = DispatchSemaphore(value: 0)
var ok = false
ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
    ok = success
    sem.signal()
}
sem.wait()
exit(ok ? 0 : 1)
