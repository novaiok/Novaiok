import AppKit
import RepoBarCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    private var showOnlyMyRepos: Bool {
        guard let username = self.currentUsername() else { return false }
        return self.session.settings.repoList.ownerFilter.contains(username.lowercased())
    }

    private func currentUsername() -> String? {
        if case let .loggedIn(user) = self.session.account {
            return user.username
        }
        return nil
    }

    private func toggleShowOnlyMyRepos(_ enabled: Bool) {
        guard let username = self.currentUsername() else { return }
        let normalizedUsername = username.lowercased()

        if enabled {
            if !self.session.settings.repoList.ownerFilter.contains(normalizedUsername) {
                self.session.settings.repoList.ownerFilter = [normalizedUsername]
            }
        } else {
            self.session.settings.repoList.ownerFilter.removeAll { $0.lowercased() == normalizedUsername }
        }

        self.appState.persistSettings()
        self.appState.requestRefresh(cancelInFlight: true)
    }

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section {
                    Toggle("Launch at login", isOn: self.$session.settings.launchAtLogin)
                        .onChange(of: self.session.settings.launchAtLogin) { _, value in
                            LaunchAtLoginHelper.set(enabled: value)
                            self.appState.persistSettings()
                        }
                } footer: {
                    Text("Automatically opens RepoBar when you start your Mac.")
                }

                Section {
                    Toggle("Show contribution header", isOn: self.$session.settings.appearance.showContributionHeader)
                        .onChange(of: self.session.settings.appearance.showContributionHeader) { _, _ in
                            self.appState.persistSettings()
                        }
                    Picker("Activity feed", selection: self.$session.settings.appearance.activityScope) {
                        ForEach(GlobalActivityScope.allCases, id: \.self) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .onChange(of: self.session.settings.appearance.activityScope) { _, _ in
                        self.appState.persistSettings()
                        self.appState.requestRefresh()
                    }
                    Picker("Repository heatmap", selection: self.$session.settings.heatmap.display) {
                        ForEach(HeatmapDisplay.allCases, id: \.self) { display in
                            Text(display.label).tag(display)
                        }
                    }
                    .onChange(of: self.session.settings.heatmap.display) { _, _ in
                        self.appState.persistSettings()
                    }
                    Picker("Heatmap window", selection: self.$session.settings.heatmap.span) {
                        ForEach(HeatmapSpan.allCases, id: \.self) { span in
                            Text(span.label).tag(span)
                        }
                    }
                    .onChange(of: self.session.settings.heatmap.span) { _, _ in
                        self.appState.persistSettings()
                        self.appState.updateHeatmapRange(now: Date())
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Repository heatmaps show recent commit activity for each repository.")
                }

                Section {
                    Picker("Repositories shown", selection: self.$session.settings.repoList.displayLimit) {
                        ForEach([3, 6, 9, 12], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Menu sort", selection: self.$session.settings.repoList.menuSortKey) {
                        ForEach(RepositorySortKey.settingsCases, id: \.self) { sortKey in
                            Text(sortKey.settingsLabel).tag(sortKey)
                        }
                    }
                    .onChange(of: self.session.settings.repoList.menuSortKey) { _, _ in
                        self.appState.persistSettings()
                    }
                    Toggle("Include forked repositories", isOn: self.$session.settings.repoList.showForks)
                        .onChange(of: self.session.settings.repoList.showForks) { _, _ in
                            self.appState.persistSettings()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                    Toggle("Include archived repositories", isOn: self.$session.settings.repoList.showArchived)
                        .onChange(of: self.session.settings.repoList.showArchived) { _, _ in
                            self.appState.persistSettings()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                    Toggle("Show only my repositories", isOn: Binding(
                        get: { self.showOnlyMyRepos },
                        set: { self.toggleShowOnlyMyRepos($0) }
                    ))
                } header: {
                    Text("Repositories")
                } footer: {
                    Text("Filters apply to repo lists and search. 'Show only my repositories' hides repos from organizations.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Quit RepoBar") { NSApp.terminate(nil) }
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
