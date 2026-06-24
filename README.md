# LGTM — native Azure DevOps PR approvals for macOS & iOS

A native Apple app for reviewing and approving Azure DevOps pull requests, signed
in with Microsoft Entra ID.

> **v1 scope:** Pull Requests only — list PRs awaiting your review, view diffs &
> comments, vote (approve / approve-with-suggestions / wait / reject), comment,
> complete/abandon. Real push notifications when a PR needs your approval.

> **Auth model:** **multi-tenant** — any Microsoft Entra organization's users can
> sign in, then pick which Azure DevOps **organization** to view (one Entra token
> works across every org a user can access; no re-auth to switch). The client ID
> is the app's own identity (baked in, not secret); the tenant is not pinned.

## Status

| Layer | State | Verified here? |
|-------|-------|----------------|
| `Packages/LGTMKit` — models, REST client, rate limiting, push client, shared webhook logic | **Implemented** | ✅ `swift build` + `swift run DevVerify` (19 checks) |
| `App/` — MSAL auth, SwiftUI views, macOS + iOS shells | Scaffolded | ❌ needs Xcode + MSAL + Phase 0 |
| `Backend/` — Vapor webhook receiver + APNs sender | Scaffolded | ❌ needs Vapor toolchain + Phase 0 |

The core package is fully buildable and tested on plain Command Line Tools. The
app and backend are real, idiomatic scaffolding that compile once you open them
in Xcode (with the MSAL/Vapor dependencies) and complete the Phase 0 registrations.

## Layout

```
lgtm/
├── Packages/LGTMKit/      ← core library (pure Swift, tested)
│   ├── Sources/LGTMKit/   ← Models, Networking (ADOClient), Push, shared PushLogic
│   ├── Sources/DevVerify/        ← `swift run DevVerify` runtime checks (CLT-friendly)
│   └── Tests/                    ← Swift Testing suite (runs under full Xcode/CI)
├── App/
│   ├── Auth/                     ← MSALTokenProvider, AppConfiguration
│   ├── SharedUI/                 ← AppServices, PR list/detail view models + SwiftUI views
│   ├── macOS/                    ← MenuBarExtra + window entry point
│   └── iOS/                      ← NavigationStack entry point + APNs registration
└── Backend/                      ← Vapor push backend (webhook → APNs)
```

## Verify the core package now

```bash
cd Packages/LGTMKit
swift build
swift run DevVerify        # 19 runtime checks: decoding, request building, retries, webhook selection
```

> **Note on `swift test`:** the Swift Testing suite is the canonical test set and
> runs under full Xcode / CI. On *Command Line Tools only*, the bundled Swift
> Testing runner does not discover tests reliably, so `DevVerify` exists to give
> equivalent runtime verification without Xcode.

## Phase 0 — registrations (do before assembling the app)

1. **Entra app registration (client)** — public client, **multi-tenant**
   ("Accounts in any organizational directory"), no secret. Add an **iOS/macOS**
   platform with redirect URI `msauth.<bundle-id>://auth` for each bundle id.
   External organizations may require their own admin to consent on first sign-in.
2. **Entra app registration (backend API)** — expose a scope (e.g. `access_as_user`)
   and grant the client app permission to it.
3. **Azure DevOps consent** — the resource GUID `499b84ac-1321-427f-aa17-267ca6975798`
   is fixed; have a tenant admin grant consent once to avoid per-user prompts.
4. **Apple Developer Program** — App IDs for both targets with **Push Notifications**
   and **Keychain Sharing** capabilities; create a token-based **APNs key (.p8)**.
5. **Azure DevOps Service Hook** — "Pull request created" + "Pull request updated"
   → `POST https://<backend>/webhooks/azuredevops`, with an `X-Webhook-Secret` header.

Fill the results into `App/Auth/AppConfiguration.swift` (client id, tenant id,
org, backend scope, backend URL).

## The app project (generated)

The Xcode project is **generated from `project.yml`** with [XcodeGen](https://github.com/yonaskolb/XcodeGen),
so it's reproducible and the `.xcodeproj` need not be hand-edited. Two app targets
(`lgtm-iOS`, `lgtm-macOS`) consume the local `LGTMKit`
package and **MSAL** (pinned `from: 2.13.0`).

```bash
brew install xcodegen          # one-off
cd lgtm
xcodegen generate              # (re)creates lgtm.xcodeproj
open lgtm.xcodeproj
```

Both targets **compile today** and the app launches into a sign-in / "configuration
needed" screen even before Phase 0 — so you can ⌘R immediately. To actually sign in:

1. Select your **Development Team** under *Signing & Capabilities* for each target.
2. Fill in `App/Auth/AppConfiguration.swift` — for multi-tenant you only need the
   **client ID** (the authority is already `/organizations`; the DevOps org is
   chosen at runtime). Set the backend scope/URL when you stand up the push backend.
3. Add the capabilities the entitlements comments call out: **Keychain Sharing**
   (`com.microsoft.adalcache` on iOS, `com.microsoft.identity.universalstorage` on
   macOS) for MSAL SSO, and **Push Notifications** for APNs.

The `msauth.<bundle-id>` URL scheme and the `msauthv2`/`msauthv3` query schemes are
already wired into the `Info.plist` files.

> Verified: `lgtm-macOS` and `lgtm-iOS` both build clean against
> Xcode (Swift 5 language mode for the app targets; the core package stays Swift 6).

## Run the backend

```bash
cd Backend
# Set: APNS_P8, APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC, WEBHOOK_SECRET
swift run LGTMBackend
```

Deploy into the Kyle Scudder Azure subscription (App Service / container). The
backend reuses `LGTMKit.PushLogic.reviewerIdsToNotify` — the same
verified rule used in the checks — to decide who is newly blocking a PR.

## Architecture

```
macOS app (MenuBarExtra + window)   iOS app (NavigationStack)
            │                                 │
            └──────► LGTMKit ◄──────────┘
                     • AuthService = MSALTokenProvider (app layer)
                     • ADOClient (REST, async/await, retry/backoff)
                     • PushService (device registration)
                     • PushLogic (shared with backend)
        │ Bearer (ADO scope)            │ Bearer (backend scope)
        ▼                                ▼
  Azure DevOps REST (api 7.1)     Vapor backend ──APNs──► devices
                                        ▲
                                  service hook: PR created / updated
```

One MSAL sign-in acquires **two** tokens: the Azure DevOps token (REST calls) and
a backend-scope token (so the backend can trust the caller's `oid` without ever
seeing the Azure DevOps token).
