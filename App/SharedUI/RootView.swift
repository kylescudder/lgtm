import SwiftUI
import LGTMKit

/// Top-level routing: sign-in → organization picker → pull request list.
struct RootView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        Group {
            if let services = session.services {
                SignedInRootView(services: services)
            } else {
                SignInView(session: session)
            }
        }
        // Restore a cached session silently on launch — skips the sign-in screen
        // entirely for returning users when MSAL has a valid cached token.
        .task { await session.resume() }
    }
}

/// Shown once signed in: pick an organization, then show its pull requests.
private struct SignedInRootView: View {
    @ObservedObject var services: AppServices

    var body: some View {
        if services.currentOrg == nil {
            OrgPickerView(services: services)
        } else {
            PRListView(services: services)
                .environmentObject(services)
        }
    }
}

/// Lets the user choose among the Azure DevOps organizations they can access.
struct OrgPickerView: View {
    @ObservedObject var services: AppServices
    @State private var orgs: [Account] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose an organization").font(.title2).bold()
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Retry") { Task { await load() } }
            } else if orgs.isEmpty {
                Text("No Azure DevOps organizations found for this account.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                List(orgs) { org in
                    Button {
                        services.selectOrg(org)
                    } label: {
                        HStack {
                            Image(systemName: "building.2")
                            Text(org.accountName)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 320)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            orgs = try await services.availableOrgs()
            // Auto-select when there is exactly one.
            if orgs.count == 1, let only = orgs.first { services.selectOrg(only) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Sign-in / configuration screen. Shared by both platforms.
struct SignInView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
            Text("lgtm").font(.largeTitle).bold()

            if AppConfiguration.isConfigured {
                Text("Sign in with your Microsoft account to review and approve pull requests.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await session.signIn() }
                } label: {
                    Text(session.isSigningIn ? "Signing in…" : "Sign in with Microsoft")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isSigningIn)
            } else {
                configurationNeeded
            }

            if let error = session.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: 460)
    }

    private var configurationNeeded: some View {
        VStack(spacing: 8) {
            Label("Configuration needed", systemImage: "gearshape")
                .font(.headline)
            Text("""
            Complete the Phase 0 registrations and fill in \
            App/Auth/AppConfiguration.swift (the client ID), then rebuild. \
            See the project README.
            """)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
