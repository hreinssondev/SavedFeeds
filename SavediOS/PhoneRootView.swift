import SafariServices
import SwiftUI

/// One feed at a time, Instagram first: the Reddit and Instagram in the navigation bar switch between them, the ⋯ menu
/// picks how posts are laid out, and tapping a post opens it.
struct PhoneRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = Service.instagram
    @State private var path: [PostRoute] = []
    @State private var query = ""
    @State private var browsing: Browsed?
    @State private var signedIn: Set<Service> = []
    @State private var toTop: [Service: Int] = [:]
    @AppStorage("phoneLayout.reddit") private var redditLayout = PhoneLayout.full
    @AppStorage("phoneLayout.instagram") private var instagramLayout = PhoneLayout.full
    @Namespace private var zoom

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $path) {
            ZStack {
                // Both stay alive, so each keeps its place.
                ForEach(Service.allCases) { service in
                    FeedScreen(
                        feed: app.feed(for: service),
                        query: selection == service ? query : "",
                        layout: service == .reddit ? redditLayout : instagramLayout,
                        namespace: zoom,
                        toTop: toTop[service, default: 0]
                    ) { route in
                        path.append(route)
                    }
                    .opacity(selection == service ? 1 : 0)
                    .allowsHitTesting(selection == service)
                    .accessibilityHidden(selection != service)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { switcher }
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .searchable(text: $query, prompt: "Search saved \(selection.name) posts")
            .navigationDestination(for: PostRoute.self) { route in
                PostDetailView(route: route)
                    .navigationTransition(.zoom(sourceID: route.post.id, in: zoom))
            }
        }
        // The hidden reddit.com and instagram.com pages the feeds are fetched through, out of sight behind it all.
        .background(alignment: .topLeading) {
            HiddenSitePages()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .environment(\.openURL, OpenURLAction(handler: route))
        .fullScreenCover(item: $browsing) { page in
            SafariView(url: page.url)
                .ignoresSafeArea()
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
        .sensoryFeedback(.selection, trigger: selection)
        .task {
            #if DEBUG
            openDemoScreen()
            #endif
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
    }

    // MARK: Bar

    private var switcher: some View {
        HStack(spacing: 22) {
            ForEach([Service.reddit, .instagram]) { service in
                Button {
                    if selection == service {
                        // Tapping the feed you're on takes you back to it, or to its top.
                        if path.isEmpty { toTop[service, default: 0] += 1 } else { path.removeAll() }
                    }
                    withAnimation(.snappy(duration: 0.2)) { selection = service }
                } label: {
                    HStack(spacing: 6) {
                        ServiceBadge(service: service)
                        Text(service.name)
                            .font(.subheadline.weight(selection == service ? .bold : .medium))
                    }
                    .opacity(selection == service ? 1 : 0.4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == service ? .isSelected : [])
            }
        }
    }

    private var menu: some View {
        Menu {
            Picker("View", selection: selection == .reddit ? $redditLayout : $instagramLayout) {
                ForEach([PhoneLayout.full, .compact], id: \.self) { layout in
                    Label(layout.name(for: selection), systemImage: layout.symbol(for: selection))
                        .tag(layout)
                }
            }
            // Signing in here is the backup; the Mac's sign-ins arrive through iCloud Keychain.
            ForEach(Service.allCases) { service in
                Section(service.name) {
                    if signedIn.contains(service) {
                        Button("Sign Out of \(service.name)", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task {
                                await app.signOut(service)
                                await loadAccounts()
                            }
                        }
                    } else {
                        Button("Sign In to \(service.name) Here…", systemImage: "person.crop.circle.badge.plus") {
                            app.signingIn = service
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    // MARK: Links

    /// Reddit and Instagram links open their apps (or Safari without them); others open in the app's own browser.
    private func route(_ url: URL) -> OpenURLAction.Result {
        let host = url.host()?.lowercased() ?? ""
        let ownApps = ["reddit.com", "redd.it", "instagram.com"].contains { host == $0 || host.hasSuffix("." + $0) }
        guard !ownApps, ["http", "https"].contains(url.scheme?.lowercased()) else { return .systemAction }
        browsing = Browsed(url: url)
        return .handled
    }

    #if DEBUG
    /// For screenshots in the Simulator (with `-demoData`): `-demoService reddit`, `-demoLayout compact`,
    /// `-demoQuery <words>`, `-demoPost <post id>` (with `-demoComments YES` to start at its comments, or
    /// `-demoPicture <index>` for the photo viewer).
    private func openDemoScreen() {
        let defaults = UserDefaults.standard
        if let service = defaults.string(forKey: "demoService").flatMap(Service.init(rawValue:)) { selection = service }
        if let layout = defaults.string(forKey: "demoLayout").flatMap(PhoneLayout.init(rawValue:)) {
            if selection == .reddit { redditLayout = layout } else { instagramLayout = layout }
        }
        if let words = defaults.string(forKey: "demoQuery") { query = words }
        if let id = defaults.string(forKey: "demoPost"), let post = app.feed(for: selection).posts.first(where: { $0.id == id }) {
            path = [PostRoute(post: post, toComments: defaults.bool(forKey: "demoComments"))]
        }
    }
    #endif

    private func loadAccounts() async {
        var accounts = Set<Service>()
        for service in Service.allCases where await service.isSignedIn() {
            accounts.insert(service)
        }
        signedIn = accounts
    }
}

private struct Browsed: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Safari inside the app, for links out of posts.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
