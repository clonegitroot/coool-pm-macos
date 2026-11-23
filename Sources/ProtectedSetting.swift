import SwiftUI

protocol ProtectedSettingValue {
    init?(protectedData: Data)
    var protectedData: Data { get }
}
extension String: ProtectedSettingValue {
    init?(protectedData: Data) { self.init(data: protectedData, encoding: .utf8) }
    var protectedData: Data { Data(utf8) }
}
extension Data: ProtectedSettingValue {
    init?(protectedData: Data) { self = protectedData }
    var protectedData: Data { self }
}

/// SwiftUI still observes preference changes, but only the authenticated ciphertext reaches the plist.
@propertyWrapper
struct ProtectedSetting<Value: ProtectedSettingValue>: DynamicProperty {
    @AppStorage private var stored: Data?
    let name: String
    let fallback: Value

    init(wrappedValue: Value, _ name: String) {
        self.name = name
        fallback = wrappedValue
        _stored = AppStorage<Data?>(name)
    }
    var wrappedValue: Value {
        get {
            guard let stored, let data = try? VaultSession.shared.key().open(stored, purpose: "preference/" + name),
                  let value = Value(protectedData: data) else { return fallback }
            return value
        }
        nonmutating set {
            do { stored = try VaultSession.shared.key().seal(newValue.protectedData, purpose: "preference/" + name) }
            catch { Task { @MainActor in NSApp.presentError(error) } }
        }
    }
    var projectedValue: Binding<Value> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
}
