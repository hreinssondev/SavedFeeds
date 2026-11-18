import SwiftUI

/// One feed at a time, Instagram first; the top bar's Reddit and Instagram switch between them.
struct PhoneRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = Service.instagram
    @State private var signedIn: Set<Service> = []

    var body: some View {
        @Bindable var app = app
        ZStack {
            // Both stay alive, so each keeps its scroll position.
            ForEach(Service.allCases) { service in
                PhoneFeedView(feed: app.feed(for: service))
                    .opacity(selection == service ? 1 : 0)
                    .allowsHitTesting(selection == service)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .background(HiddenSitePages())
        .task {
            await app.importMacSessions()
            await app.refreshAll()
            await loadAccounts()
        }
        .onChange(of: scenePhase) { _, phase in
            // The Mac may have shared a new sign-in while the app was away.
            if phase == .active {
                Task {
                    await app.syncMacSessions()
                    await loadAccounts()
                }
            }
        }
        .sheet(item: $app.signingIn) { service in
            NavigationStack {
                SignInSheet(service: service) {
                    Task {
                        await app.feed(for: service).refresh()
                        await loadAccounts()
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 28) {
            ForEach([Service.reddit, .instagram]) { service in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = service }
                } label: {
                    HStack(spacing: 6) {
                        ServiceBadge(service: service)
                        Text(service.name)
                            .font(.headline)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if selection == service {
                            Capsule()
                                .fill(service.tint)
                                .frame(height: 3)
                        }
                    }
                    .opacity(selection == service ? 1 : 0.45)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { menu }
        .padding(.horizontal)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Signing in here is the backup; normally the Mac's sign-ins arrive through iCloud Keychain.
    private var menu: some View {
        Menu {
            ForEach(Service.allCases) { service in
                Section(service.name) {
                    if signedIn.contains(service) {
                        Button("Sign Out of \(service.name)", role: .destructive) {
                            Task {
                                await app.signOut(service)
                                await loadAccounts()
                            }
                        }
                    } else {
                        Button("Sign In to \(service.name) Here…") { app.signingIn = service }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }

    private func loadAccounts() async {
        var accounts = Set<Service>()
        for service in Service.allCases where await service.isSignedIn() {
            accounts.insert(service)
        }
        signedIn = accounts
    }
}
