import Foundation

func applicationsForDisplay(
    _ applications: [ProtectedApplication],
    search: String,
    isSelected: (ProtectedApplication) -> Bool
) -> [ProtectedApplication] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let configurableApplications = applications.filter { !$0.isSystemApplication }
    let matchingApplications = query.isEmpty
        ? configurableApplications
        : configurableApplications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
        }

    return matchingApplications.sorted { lhs, rhs in
        let lhsIsSelected = isSelected(lhs)
        let rhsIsSelected = isSelected(rhs)
        if lhsIsSelected != rhsIsSelected {
            return lhsIsSelected
        }

        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }
}
