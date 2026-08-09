import Foundation
import VercelAnalyticsCore

struct ProjectSelection: Equatable, Sendable {
    static let empty = ProjectSelection(selectedProjectIDs: [], currentProjectID: nil)

    let selectedProjectIDs: Set<String>
    let currentProjectID: String?
}

struct ProjectCatalog: Equatable, Sendable {
    private(set) var projects: [VercelProject]
    private(set) var selection: ProjectSelection

    init(selection: ProjectSelection = .empty) {
        projects = []
        self.selection = selection
    }

    var selectedProjectIDs: Set<String> {
        selection.selectedProjectIDs
    }

    var currentProjectID: String? {
        selection.currentProjectID
    }

    var currentProject: VercelProject? {
        guard let currentProjectID else {
            return projects.first { selectedProjectIDs.contains($0.id) }
        }
        return projects.first {
            $0.id == currentProjectID && selectedProjectIDs.contains($0.id)
        } ?? projects.first { selectedProjectIDs.contains($0.id) }
    }

    mutating func restore(_ selection: ProjectSelection) {
        self.selection = selection
    }

    mutating func reconcile(with projects: [VercelProject]) {
        self.projects = VercelProject.sorted(projects)

        let availableProjectIDs = Set(self.projects.map(\.id))
        var selectedProjectIDs = selection.selectedProjectIDs.intersection(availableProjectIDs)
        if selectedProjectIDs.isEmpty, let firstProject = self.projects.first {
            selectedProjectIDs = [firstProject.id]
        }

        let retainedCurrentProjectID = selection.currentProjectID.flatMap { projectID in
            selectedProjectIDs.contains(projectID) ? projectID : nil
        }
        let currentProjectID = retainedCurrentProjectID ?? selectedProjectIDs.sorted().first

        selection = ProjectSelection(
            selectedProjectIDs: selectedProjectIDs,
            currentProjectID: currentProjectID
        )
    }

    @discardableResult
    mutating func setProject(_ projectID: String, selected: Bool) -> Bool {
        guard projects.contains(where: { $0.id == projectID }) else { return false }

        var selectedProjectIDs = selection.selectedProjectIDs
        if selected {
            guard selectedProjectIDs.insert(projectID).inserted else { return false }
        } else {
            guard selectedProjectIDs.contains(projectID), selectedProjectIDs.count > 1 else { return false }
            selectedProjectIDs.remove(projectID)
        }

        let currentProjectID = if selected {
            selection.currentProjectID ?? projectID
        } else if selection.currentProjectID == projectID {
            selectedProjectIDs.sorted().first
        } else {
            selection.currentProjectID
        }

        selection = ProjectSelection(
            selectedProjectIDs: selectedProjectIDs,
            currentProjectID: currentProjectID
        )
        return true
    }

    @discardableResult
    mutating func selectCurrentProject(_ projectID: String) -> Bool {
        guard projectID != selection.currentProjectID,
              selection.selectedProjectIDs.contains(projectID),
              projects.contains(where: { $0.id == projectID })
        else {
            return false
        }

        selection = ProjectSelection(
            selectedProjectIDs: selection.selectedProjectIDs,
            currentProjectID: projectID
        )
        return true
    }

    func projects(matching searchQuery: String) -> [VercelProject] {
        let query = normalized(searchQuery)
        guard !query.isEmpty else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || (project.teamName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func selectedProjects(matching searchQuery: String) -> [VercelProject] {
        let selectedProjects = projects.filter { selectedProjectIDs.contains($0.id) }
        let query = normalized(searchQuery)
        guard !query.isEmpty else { return selectedProjects }
        return selectedProjects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func teamMetadata(for project: VercelProject) -> String? {
        guard projects.count(where: { $0.name == project.name }) > 1 else { return nil }
        return project.teamName ?? "Personal account"
    }

    private func normalized(_ searchQuery: String) -> String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
