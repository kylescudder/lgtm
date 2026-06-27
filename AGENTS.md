# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) and other agents when working with code in this repository.

LGTM is a native Apple app (macOS + iOS) for reviewing and approving Azure DevOps pull requests, signed in with Microsoft Entra ID, plus a push backend.

## Layout & build status

Three layers, each with its own build system and a different verification story:

| Path | What it is | Toolchain | Verified how |
|------|-----------|-----------|--------------|
| `Packages/LGTMKit/` | Pure-Swift core: models, `ADOClient`, push client, shared `PushLogic` | SwiftPM, **Swift 6** (strict concurrency) | `swift build` + `swift run DevVerify` on plain Command Line Tools |
| `App/` | SwiftUI app — macOS (MenuBarExtra) + iOS (NavigationStack) shells | Xcode project generated from `project.yml`, **Swift 5** | Builds in Xcode with MSAL |
| `Backend/` | _(under review — to be documented)_ | | |

The Swift-version split is deliberate: the core package stays Swift 6, but the app targets are pinned to Swift 5 (`project.yml`) to avoid strict-concurrency errors against the Objective-C MSAL dependency.

## Commands

### Core package (LGTMKit) — the canonical, always-buildable piece
```bash
cd Packages/LGTMKit
swift build
swift run DevVerify        # 19 runtime checks (decoding, request building, retries, webhook selection)
swift test                 # Swift Testing suite — the canonical tests
swift test --filter <name> # run a single test
```
**`swift test` caveat:** on *Command Line Tools only*, the bundled Swift Testing runner does not discover tests reliably — `swift test` is the source of truth under full Xcode / CI. `DevVerify` exists to give equivalent runtime verification without Xcode and mirrors the test harness (see `Sources/DevVerify/main.swift`). When changing core logic, update both.

### App (macOS + iOS)
```bash
brew install xcodegen      # one-off
xcodegen generate          # (re)creates lgtm.xcodeproj from project.yml
open lgtm.xcodeproj
```
`lgtm.xcodeproj` is **generated and git-ignored** — never hand-edit it; change `project.yml` and re-run `xcodegen generate`. Two targets (`lgtm-iOS`, `lgtm-macOS`) consume the local `LGTMKit` package and MSAL (pinned `from: 2.13.0`).

### Backend
```bash
cd Backend
# env: APNS_P8, APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC, WEBHOOK_SECRET
swift run LGTMBackend
```

## Architecture

```
macOS app (MenuBarExtra + window)   iOS app (NavigationStack)
            └──────────────┬──────────────┘
                       LGTMKit
            ADOClient · Models · PushService · PushLogic
        │ Bearer (ADO scope)            │ Bearer (backend scope)
        ▼                                ▼
  Azure DevOps REST (7.1)         push backend ──APNs──► devices
                                        ▲ service hook: PR created / updated
```

**Two-token model.** One MSAL sign-in acquires *two* tokens: the Azure DevOps token (for REST calls) and a backend-scope token. The backend trusts the caller's Entra `oid` from its own token without ever seeing the ADO token. The fixed Azure DevOps resource GUID `499b84ac-1321-427f-aa17-267ca6975798` (`azureDevOpsResourceID`) scopes the ADO token.

**Multi-tenant, runtime org selection.** Any Entra org's users can sign in; the same Entra token works across every Azure DevOps org a user can access — no re-auth to switch. There is no hardcoded org: `AppServices.selectOrg(_:)` rebuilds the `ADOClient` bound to the chosen org. Org/profile discovery (`profile()`, `accounts(memberId:)`) goes to the org-agnostic vssps host; everything else targets `dev.azure.com/{org}`.

**`ADOClient` (`Packages/LGTMKit/.../Networking/ADOClient.swift`)** is the single REST surface. It re-fetches a bearer token from the injected `TokenProvider` before *every* request (so silent refresh is transparent), and retries 429/5xx with `Retry-After`-aware exponential backoff. `connectionData` must use api-version `7.1-preview` — the plain `7.1` is rejected for that preview resource. Use `connectionData().authenticatedUser.id` (org-local identity GUID) as the `reviewerId`/`creatorId` for PR searches — **not** the Entra object id.

**`PushLogic.reviewerIdsToNotify(for:)` is shared, not duplicated.** Both the app and the backend import it from LGTMKit. The Vapor webhook handler (`Backend/Sources/LGTMBackend/routes.swift`) calls the same verified rule to decide who is newly blocking a PR — keep this the one source of truth for notification logic.

**App composition.** `AppSession` (lazy: `signIn()` builds services + triggers the MSAL interactive flow on demand, so the app launches before any config exists) → `AppServices` (composition root: wires `MSALTokenProvider` into `ADOClient` + `PushService`) → `CacheStore` (disk-persisted per-org cache of projects + resolved user id, so the PR list renders instantly while a background refresh runs). View models (`PRListViewModel`, `PRDetailViewModel`) are `@MainActor` `ObservableObject`s.

**Backend.** `EntraAuthMiddleware` validates the bearer token and attaches the caller's `oid`; `/devices` registers an APNs token against that `oid`; `/webhooks/azuredevops` verifies the `X-Webhook-Secret` header, then fans out APNs alerts. Device storage is currently `InMemoryDeviceStore`.

## Configuration

`App/Auth/AppConfiguration.swift` holds the non-secret public-client values (client ID, multi-tenant `/organizations` authority, backend scope/URL, keychain group). It is safe to commit (public client, no secret). `isConfigured` gates real sign-in: until the client ID is filled, the app launches into a "configuration needed" state rather than crashing. The required Phase 0 registrations (Entra client + backend API, Azure DevOps consent, Apple Push key, Azure DevOps service hook) are documented in `README.md`.
