import SafariServices
import SwiftUI

/// One feed at a time, Instagram first, running to the top of the screen. The glass bar at the bottom switches feeds
/// (as does a swipe sideways); the ⋯ button at the top right has search, the layout and the accounts. Tapping a post
/// opens it.
struct PhoneRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = Service.instagram
    @State private var path: [PostRoute] = []
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var browsing: Browsed?
    @State private var signedIn: Set<Service> = []
    @State private var toTop: [Service: Int] = [:]
    @AppStorage("phoneLayout.reddit") private var redditLayout = PhoneLayout.full
    @AppStorage("phoneLayout.instagram") private var instagramLayout = PhoneLayout.full
    @Namespace private var zoom
    @Namespace private var switcherSelection

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $path) {
            // The feeds side by side, Reddit then Instagram, swiped between like pages.
            TabView(selection: $selection) {
                ForEach(Service.allCases) { service in
                    FeedScreen(
                        feed: app.feed(for: service),
                        query: query,
                        layout: layout(for: service),
                        namespace: zoom,
                        toTop: toTop[service, default: 0]
                    ) { route in
                        path.append(route)
                    }
                    .tag(service)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaBar(edge: .top) {
                if searching { searchBar }
            }
            .safeAreaBar(edge: .bottom) { switcher }
            .overlay(alignment: .topTrailing) {
                if !searching { menu }
            }
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

    private func layout(for service: Service) -> PhoneLayout {
        (service == .reddit ? redditLayout : instagramLayout).resolved(for: service)
    }

    // MARK: Switcher

    /// Reddit and Instagram on a glass bar floating over the feeds; the one you're on is lit.
    private var switcher: some View {
        HStack(spacing: 2) {
            ForEach(Service.allCases) { service in
                let isSelected = selection == service
                Button {
                    choose(service)
                } label: {
                    HStack(spacing: 8) {
                        ServiceLogo(service: service, size: 24)
                        Text(service.name)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 16)
                    .frame(height: 46)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.primary.opacity(0.1))
                                .matchedGeometryEffect(id: "selection", in: switcherSelection)
                        }
                    }
                    .opacity(isSelected ? 1 : 0.55)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(service.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("switcher.\(service.rawValue)")
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.snappy(duration: 0.25), value: selection)
        .padding(.bottom, 6)
    }

    private func choose(_ service: Service) {
        if selection == service {
            // The feed you're on: back to it from a post, or to its top.
            if path.isEmpty { toTop[service, default: 0] += 1 } else { path.removeAll() }
        }
        withAnimation(.snappy(duration: 0.3)) { selection = service }
    }

    // MARK: Menu and search

    private var menu: some View {
        Menu {
            Button("Search", systemImage: "magnifyingglass", action: startSearch)
            Picker("View", selection: Binding(
                get: { layout(for: selection) },
                set: { if selection == .reddit { redditLayout = $0 } else { instagramLayout = $0 } }
            )) {
                ForEach(PhoneLayout.options(for: selection)) { layout in
                    Label(layout.name(for: selection), systemImage: layout.symbol).tag(layout)
                }
            }
            .pickerStyle(.inline)
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
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("More")
        .accessibilityIdentifier("menu")
        .padding(.trailing, 16)
        .padding(.top, 2)
    }

    /// A glass search field across the top, with a button to put it away.
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search saved \(selection.name) posts", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("search.field")
                    .onAppear { searchFocused = true }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .glassEffect(.regular.interactive(), in: .capsule)
            Button(action: endSearch) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Done Searching")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func startSearch() {
        withAnimation(.snappy(duration: 0.25)) { searching = true }
    }

    private func endSearch() {
        searchFocused = false
        query = ""
        withAnimation(.snappy(duration: 0.25)) { searching = false }
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
    /// For screenshots in the Simulator (with `-demoData`): `-demoService reddit`, `-demoLayout grid`,
    /// `-demoQuery <words>` (opens search), `-demoPost <post id>` (with `-demoComments YES` to start at its comments,
    /// or `-demoPicture <index>` for the photo viewer), `-demoLoadPages YES` (a real page in the hidden web views).
    private func openDemoScreen() {
        let defaults = UserDefaults.standard
        if let service = defaults.string(forKey: "demoService").flatMap(Service.init(rawValue:)) { selection = service }
        if let layout = defaults.string(forKey: "demoLayout").flatMap(PhoneLayout.init(rawValue:)) {
            if selection == .reddit { redditLayout = layout } else { instagramLayout = layout }
        }
        if let words = defaults.string(forKey: "demoQuery") {
            query = words
            searching = true
        }
        if defaults.bool(forKey: "demoLoadPages") {
            for page in [SitePage.reddit, .instagram] {
                page.hostedView.load(URLRequest(url: URL(string: "https://example.com")!))
            }
        }
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
