import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var feedLink = Credentials.redditFeedURL ?? ""
    @State private var feedLinkChanged = false
    @State private var signedIn: Set<Service> = []
    @State private var signingIn: Service?

    var body: some View {
        Form {
            Section {
                TextField("Feed link", text: $feedLink, prompt: Text("https://www.reddit.com/user/…/saved.json?feed=…"))
                    .onChange(of: feedLink) {
                        Credentials.redditFeedURL = feedLink.trimmingCharacters(in: .whitespacesAndNewlines)
                        feedLinkChanged = true
                    }
                    .onSubmit(applyFeedLink)
                if !feedLink.isEmpty, !feedLink.contains("feed=") {
                    Text("This doesn't look like a private feed link; it should contain “feed=”.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Link("Get your feed link on old.reddit.com/prefs/feeds", destination: URL(string: "https://old.reddit.com/prefs/feeds/")!)
                account(.reddit)
            } header: {
                Text("Reddit")
            } footer: {
                Text("On the feeds page, copy the JSON link next to your saved links. No API key needed. Without a feed link, SavedFeeds uses your reddit.com sign-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                account(.instagram)
            } header: {
                Text("Instagram")
            } footer: {
                Text("Instagram has no API for saved posts. SavedFeeds reads them through your instagram.com session the way the website does. That's unofficial and may stop working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .task { await loadAccounts() }
        .onDisappear(perform: applyFeedLink)
        .sheet(item: $signingIn) { service in
            SignInSheet(service: service) {
                Task {
                    await loadAccounts()
                    await app.feed(for: service).refresh()
                }
            }
        }
    }

    private func account(_ service: Service) -> some View {
        LabeledContent("\(service.cookieDomain) session") {
            if signedIn.contains(service) {
                HStack {
                    Text("Signed in")
                        .foregroundStyle(.secondary)
                    Button("Sign Out") {
                        Task {
                            await app.signOut(service)
                            await loadAccounts()
                        }
                    }
                }
            } else {
                Button("Sign In…") { signingIn = service }
            }
        }
    }

    private func loadAccounts() async {
        var accounts = Set<Service>()
        for service in Service.allCases where await service.isSignedIn() {
            accounts.insert(service)
        }
        signedIn = accounts
    }

    private func applyFeedLink() {
        guard feedLinkChanged else { return }
        feedLinkChanged = false
        Task { await app.reddit.refresh() }
    }
}
