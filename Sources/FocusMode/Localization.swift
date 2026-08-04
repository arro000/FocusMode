import Foundation

enum L10n {
    static func string(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: .module,
            value: defaultValue,
            comment: ""
        )
    }

    static func format(_ key: String, defaultValue: String, _ argument: CVarArg) -> String {
        String.localizedStringWithFormat(string(key, defaultValue: defaultValue), argument)
    }
}
