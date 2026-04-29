# YourTurn -- Technical Analysis

**A lightweight cross-platform notifier for AI agent signals**

Date: 2026-03-03

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Area 1: Lightest-Weight Approach](#area-1-lightest-weight-approach)
3. [Area 2: Signal Delivery Architecture](#area-2-signal-delivery-architecture)
4. [Area 3: Auth and Expandability](#area-3-auth-and-expandability)
5. [Area 4: Pitfalls and Gotchas](#area-4-pitfalls-and-gotchas)
6. [Area 5: Development Lifecycle](#area-5-development-lifecycle)
7. [Recommended Architecture](#recommended-architecture)
8. [Sources](#sources)

---

## Executive Summary

YourTurn is a notification-relay app: AI agents (Claude Code CLI, Claude online, Codex, etc.) POST signals to a backend, which fans them out to the user's device as push notifications with distinct visual/sound/haptic patterns per signal type. The app itself is thin -- its job is to display state ("agent working"), alert on action-required ("review this plan", "approve this command"), and let the user manage which agents are connected.

The recommended path is **Expo (React Native)** for the client, **Cloudflare Workers + D1** for the backend, and **FCM/APNs push notifications** (not WebSockets) for signal delivery. This combination yields a sub-5 MB app, a near-zero-cost backend at MVP scale, and the fastest path to both App Store and Play Store.

---

## Area 1: Lightest-Weight Approach

### Framework Comparison

| Criterion | PWA | Expo (React Native) | Flutter | Native (Swift + Kotlin) |
|---|---|---|---|---|
| **Min app size** | 0 MB (web) | ~3-4 MB download | ~7-10 MB download | ~2-3 MB download |
| **Push notifications** | Limited on iOS | Full FCM/APNs | Full FCM/APNs | Full FCM/APNs |
| **Custom sounds** | No | Yes (with caveats) | Yes | Full control |
| **Haptic feedback** | No | Via expo-haptics | Yes | Full control |
| **Background execution** | Very limited | Standard iOS/Android APIs | Standard APIs | Full control |
| **Development speed** | Fastest | Fast | Fast | Slowest (2x codebases) |
| **Store presence** | No store listing | Yes | Yes | Yes |
| **Maintenance burden** | Lowest | Low | Low | High (2 codebases) |

### PWA: Tempting but Disqualifying

A PWA would be the lightest option, but it fails the requirements:

- **iOS push notifications require Home Screen install**: Users must manually "Add to Home Screen" from Safari before push works. This is a terrible onboarding experience for a notification app whose core value is receiving notifications.
- **No custom sounds or haptics**: Web Push on iOS only plays the default system sound. You cannot bundle custom audio or trigger haptic patterns. For a "metronome with visual/sound effects" this is a non-starter.
- **No background execution**: A PWA cannot maintain any persistent state or run code when not in the foreground. Service workers can handle push events, but cannot play custom audio or run animations.
- **No App Store presence**: Discoverability is worse, and there is no native install flow.

**Verdict**: PWA is ruled out for YourTurn's requirements.

### Flutter: Capable but Heavier

Flutter produces fully native binaries and has excellent push notification support. However:

- Minimum app size starts at 7-10 MB due to the bundled Skia rendering engine.
- Memory overhead is ~25 MB higher than React Native equivalents (145 MB vs 120 MB baseline).
- For an app that is mostly a notification listener with a simple settings UI, bundling an entire custom rendering engine is overkill.

**Verdict**: Valid choice, but unnecessarily heavy for a notification-centric app.

### Native (Swift + Kotlin): Maximum Control, Maximum Cost

Going fully native gives the most control over custom sounds, haptics, and background behavior. But:

- Two completely separate codebases, two CI pipelines, two sets of platform-specific bugs.
- For a "slim" app, the development and maintenance cost is 2x with no proportional user benefit.
- The notification and haptic APIs available through Expo cover what YourTurn needs.

**Verdict**: Only justified if the app evolves into something with heavy platform-specific needs. Overkill for MVP and likely for V2 as well.

### Expo (React Native): The Sweet Spot

Expo is the recommendation. Here is why:

- **~3-4 MB download size** on stores. The `expo` package itself adds only ~1 MB. This is as slim as it gets for a cross-platform framework.
- **expo-notifications** provides a unified API for FCM and APNs, including local notification scheduling, notification channels (Android), and custom sounds (with caveats -- see Area 4).
- **expo-haptics** provides access to iOS Core Haptics and Android vibration APIs.
- **EAS Build** handles native compilation and code signing without needing Xcode/Android Studio locally for CI.
- **Single codebase, single deployment pipeline** for both platforms.
- **Escape hatch**: If a native module is ever needed, Expo supports custom dev clients and bare workflow. You are not locked in.

**Minimum viable Expo dependencies for YourTurn:**

```
expo
expo-notifications
expo-haptics
expo-device
expo-constants
expo-secure-store (for API tokens)
react-native-reanimated (for metronome animation)
```

This is a thin dependency tree. No navigation library is strictly needed at MVP (a single-screen app with a modal for settings).

---

## Area 2: Signal Delivery Architecture

### Signal Types and Their Delivery Requirements

| Signal | Latency Requirement | Delivery Guarantee | User Interruption Level |
|---|---|---|---|
| `agent_processing` | Low priority, 5-30s OK | Best effort | Passive (visual indicator only) |
| `agent_needs_review` | Moderate, <5s ideal | Must deliver | Active (sound + haptic + visual) |
| `agent_needs_approval` | High, <3s ideal | Must deliver | Urgent (persistent sound + haptic) |

### Delivery Mechanism Comparison

| Mechanism | Latency | Battery Impact | Works in Background | Reliability |
|---|---|---|---|---|
| **FCM/APNs Push** | 0.5-3s typical | Minimal (system-managed) | Yes | High (99%+ on stock Android, lower on OEM-modified devices) |
| **WebSockets** | <100ms | High (1%/hr) | Fragile (OS kills connections) | Low in background |
| **Server-Sent Events** | <200ms | Moderate (0.3-0.5%/hr) | Does not work in background | Low in background |
| **Polling** | Depends on interval | Proportional to frequency | Via background fetch (unreliable) | Inconsistent |

**Decision: FCM/APNs push notifications as the primary delivery channel.**

Rationale:
- YourTurn's signals are event-driven and infrequent (a developer might get 5-50 per day, not 5 per second).
- Push notifications are the only mechanism that reliably works when the app is backgrounded or killed, which is the default state for a notifier app.
- Battery drain is negligible because the OS maintains a single shared connection for all apps.
- WebSockets would be needed only if the app required sub-100ms latency or streaming data. Neither applies here.

### When the App IS in Foreground

When the user has YourTurn open, there is value in showing real-time state (a pulsing "metronome" animation while the agent is processing). Two options:

1. **Short polling (every 5s)**: Simple. Works. Adds trivial load at YourTurn's scale.
2. **WebSocket while foregrounded**: Lower latency, but adds complexity. The connection opens when the app foregrounds and closes when it backgrounds.

Recommendation: Start with short polling for the foreground state display. It is simpler, and at <50 active users per agent, the load is negligible. Upgrade to WebSockets only if users report the 5s delay as noticeable.

### Backend Architecture

#### Option A: Build on ntfy.sh (Evaluated and Rejected for Primary Use)

ntfy.sh is an excellent open-source push notification relay with a simple HTTP API. However:

- **iOS reliability problems**: Multiple open GitHub issues document iOS push notifications not arriving reliably. The ntfy iOS app relies on polling with a forwarding workaround through the central ntfy.sh server, which is fragile.
- **No custom sound control**: ntfy delivers notifications through its own app. YourTurn needs custom sounds and haptic patterns per signal type, which requires being the notification-presenting app.
- **Multi-hop architecture**: Agent -> your backend -> ntfy -> ntfy app -> (no way to get to YourTurn app). You would need ntfy as an intermediate push relay, adding a dependency and failure point.

ntfy.sh is worth considering as a **fallback or developer-mode channel** (e.g., "also send to ntfy topic X") but should not be the primary delivery path.

#### Option B: Cloudflare Workers + D1 (Recommended)

```
Agent (Claude Code CLI, etc.)
  |
  | HTTPS POST /v1/signal  (API key in header)
  v
Cloudflare Worker (edge, <50ms cold start)
  |
  |-- Validate API key (D1 lookup, cached)
  |-- Store signal in D1 (for history/state)
  |-- Fan out: send push via FCM HTTP v1 API + APNs HTTP/2
  v
User's device receives push notification
  |
  v
YourTurn app presents notification with correct sound/haptic/visual
```

**Why Cloudflare Workers:**

- **Cold start < 50ms** (vs 200-500ms for AWS Lambda). For a notification relay, fast cold start matters.
- **Free tier**: 100,000 requests/day, 10ms CPU time per request. A signal relay doing auth + store + push-send fits easily within 10ms CPU.
- **D1 free tier**: 5M reads/day, 100K writes/day, 5 GB storage. More than enough for signal metadata and user/agent registrations.
- **Global edge**: The worker runs close to wherever the agent is, minimizing the first hop latency.
- **No server to manage**: Zero ops burden.

**Cost at scale (Workers Paid plan, $5/month):**

| Resource | Free Tier | Paid Tier | YourTurn MVP Usage (est.) |
|---|---|---|---|
| Worker requests | 100K/day | 10M/month included | ~10K/month |
| D1 reads | 5M/day | 25B/month included | ~50K/month |
| D1 writes | 100K/day | 50M/month included | ~10K/month |
| D1 storage | 5 GB | 5 GB included | ~10 MB |

YourTurn's MVP comfortably fits within the **free tier**. Even at 1,000 active users with 50 signals/day each, you are at ~1.5M requests/month, still within the $5/month paid plan.

### How Agents Send Signals

```bash
# Agent sends a signal -- this is what Claude Code CLI (or any agent) would call
curl -X POST https://api.yourturn.app/v1/signal \
  -H "Authorization: Bearer ytn_abc123def456" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "agent_needs_review",
    "agent_name": "claude-code",
    "title": "Implementation plan ready",
    "body": "Created IMPLEMENTATION_PLAN.md with 4 stages",
    "metadata": {
      "file": "IMPLEMENTATION_PLAN.md",
      "session_id": "abc-123"
    }
  }'
```

The API contract is intentionally simple: a single endpoint, a bearer token, and a JSON body. Any agent that can make an HTTP POST can integrate in minutes.

### Signal Types Mapping to Notification Presentation

| Signal Type | iOS Category | Android Channel | Sound | Haptic | Persistence |
|---|---|---|---|---|---|
| `agent_processing` | Silent/update | Low priority channel | None | None | Clears on next signal |
| `agent_needs_review` | Default | Default channel | Custom chime | Medium impact | Stays until tapped |
| `agent_needs_approval` | Time Sensitive | High priority channel | Distinct alert tone | Heavy impact, repeated | Stays until actioned |

---

## Area 3: Auth and Expandability

### User Authentication

For a lightweight notifier app, authentication should be frictionless. Here is the tiered approach:

#### Recommended: Magic Link Email

1. User enters email address.
2. Backend sends a one-time link to that email.
3. User taps link, which deep-links into the app (via universal links / app links).
4. App receives a session token, stores it in expo-secure-store.

**Why magic link over alternatives:**

| Method | Pros | Cons |
|---|---|---|
| Magic link | No password to remember, simple UX, no OAuth dependency | Requires email delivery, deep link setup |
| OAuth (Google/GitHub) | One-tap for existing users | Dependency on provider, more complex setup, privacy concerns |
| Username/password | Familiar | Worst UX, password management burden, security liability |
| API token only (no account) | Simplest | No way to recover if token lost, no multi-device |

Magic links strike the right balance: no password friction, email serves as identity verification, and the implementation is straightforward (send a JWT-signed link, verify on callback).

**Implementation note**: For the deep link to work on iOS, you need an `apple-app-site-association` file served from your domain. On Android, you need `assetlinks.json`. Both are one-time setup.

### Agent Registration and API Keys

Each user can register multiple agents. Each agent gets a unique API key.

**Data model:**

```
User
  id: uuid
  email: string
  created_at: timestamp

Agent
  id: uuid
  user_id: uuid (FK -> User)
  name: string ("Claude Code - Work Laptop", "Codex - CI Pipeline")
  api_key: string (ytn_ prefixed, 32 random bytes, base62 encoded)
  created_at: timestamp
  last_signal_at: timestamp
  is_active: boolean

DeviceToken
  id: uuid
  user_id: uuid (FK -> User)
  platform: enum (ios, android)
  push_token: string (FCM token or APNs device token)
  created_at: timestamp
  updated_at: timestamp
```

**Agent registration flow:**

1. User opens YourTurn app, taps "Add Agent".
2. App calls `POST /v1/agents` with session token.
3. Backend creates agent record, generates API key.
4. App displays the API key with a "Copy" button and instructions.
5. User pastes the API key into their agent's configuration (e.g., Claude Code CLI config, a CI environment variable, etc.).

**API key design:**

- Prefix: `ytn_` (makes keys greppable in logs, identifiable if leaked).
- Length: 32 bytes of randomness, base62 encoded (~43 characters).
- Example: `ytn_7kH2mN9pQ4rS1tV6wX8yZ0aB3cD5eF`
- Stored as an argon2 hash in D1. The plaintext is shown exactly once at creation time.

### Multi-Tenancy

At the Cloudflare Workers + D1 level, multi-tenancy is straightforward:

- All data lives in a single D1 database. Tenant isolation is enforced at the query level (every query includes `WHERE user_id = ?`).
- API keys are scoped to a user. An agent's key can only send signals that route to that user's devices.
- There is no cross-tenant data access path in the API.

This is adequate for the scale YourTurn will operate at. If the app grows to tens of thousands of users, D1's single-database model still works (it is SQLite-backed with read replicas at the edge). Sharding would only be needed at a scale that is far beyond the initial target.

### Expandability: Custom Agent Integration

The API is designed so that any system capable of HTTP POST can be an agent:

- **CLI tools** (Claude Code, Codex): Add a post-hook or plugin that fires HTTP requests.
- **CI/CD pipelines** (GitHub Actions, GitLab CI): Add a step that curls the API.
- **Browser extensions**: A Chrome extension could detect when Claude web outputs a plan and fire a signal.
- **Webhooks from other services**: Zapier, n8n, or Make.com can forward events as YourTurn signals.
- **Custom scripts**: A 3-line shell function wrapping `curl`.

The key insight: YourTurn does not need to know anything about the agent's internals. It just receives typed signals and delivers them. The agent taxonomy is the user's to define.

---

## Area 4: Pitfalls and Gotchas

### 4.1 iOS Background Execution Limitations

**The core constraint**: iOS suspends apps within seconds of backgrounding. There is no way to keep a persistent connection alive or run periodic code reliably.

**Implications for YourTurn:**

- The "agent_processing" pulsing animation cannot run in the background. It only works when the app is foregrounded. This is fine -- the animation is a nice-to-have, not the core value.
- Push notifications (via APNs) are the only reliable way to reach a backgrounded iOS app.
- Silent push notifications (content-available) can wake the app briefly (~30 seconds of execution time), but iOS throttles these aggressively. Do not rely on silent pushes for user-facing state updates.
- If the user force-quits the app, silent pushes will not be delivered at all. Visible push notifications still work.

**Mitigation**: Design the app so that push notifications are the primary delivery mechanism, and the in-app real-time view is a bonus when the user actively opens the app.

### 4.2 Push Notification Reliability

**FCM on modified Android OEMs**: Manufacturers like Xiaomi, OPPO, Vivo, and Huawei aggressively restrict background processes. This can cause 20-40% notification delivery failures on affected devices.

**Mitigations:**
- Detect the device manufacturer at registration time.
- For affected OEMs, show an in-app prompt guiding the user to disable battery optimization for YourTurn (link to dontkillmyapp.com for device-specific instructions).
- Implement delivery confirmation: when the app opens or receives a notification, it pings the backend. If a high-priority signal has not been confirmed within N seconds, the backend can retry.

**APNs reliability**: Generally high (99%+) on stock iOS. The main failure mode is expired or invalid device tokens. Implement token refresh on every app launch and handle APNs error responses to prune stale tokens.

### 4.3 Battery Drain

**Push notifications**: Negligible battery impact. The OS maintains a single persistent connection shared across all apps. YourTurn adds zero battery overhead beyond what the OS already uses for push.

**WebSockets (if used for foreground updates)**: ~1% battery per hour due to keepalive packets. This is acceptable since the connection would only be open while the user is actively looking at the app.

**Recommendation**: Never maintain a persistent connection in the background. Push-only architecture means YourTurn's battery impact is effectively zero.

### 4.4 App Store / Play Store Review Gotchas

**Apple App Store:**
- Push notifications must not be required for the app to function. YourTurn must have a usable state even if the user declines notification permissions (e.g., show signal history in-app).
- Push notifications must not be used for advertising or direct marketing. YourTurn's notifications are purely functional, so this is not an issue.
- The app must provide clear value beyond just forwarding notifications. Include the agent management UI, signal history, and status dashboard to demonstrate standalone value.
- Privacy nutrition labels must accurately declare data collection (email, device tokens).
- Requires a paid Apple Developer account ($99/year).

**Google Play Store:**
- Target SDK must be current (Android 15 / API level 35 as of 2025). Expo's EAS Build handles this automatically.
- Notification permission must be requested at runtime (Android 13+). Expo-notifications handles this, but the app must gracefully handle denial.
- Privacy policy is mandatory for apps that request notification permissions.
- Data safety section must declare push token collection and email storage.
- Requires a one-time $25 registration fee.

**Key risk for both stores**: If the app is perceived as "too simple" or not providing enough standalone value, it could be rejected as a thin client. Mitigation: include signal history, agent management, and notification customization as core features visible during review.

### 4.5 Rate Limiting and Abuse Prevention

**Threat model:**
- A leaked API key could be used to spam a user with notifications.
- A buggy agent could fire thousands of signals in a loop.
- An attacker could enumerate or brute-force API keys.

**Mitigations:**

| Layer | Mechanism | Limits |
|---|---|---|
| Cloudflare WAF | IP-based rate limiting | 100 req/s per IP |
| Worker level | Per-API-key rate limiting | 60 signals/minute per key, 1000/day per key |
| Worker level | Per-user aggregate | 200 signals/minute across all agents |
| API key validation | Timing-safe comparison | Prevents timing attacks |
| Brute force | API key entropy | 32 bytes = 2^256 possible keys, infeasible to guess |
| Key rotation | User can revoke and regenerate | Instant invalidation via D1 |

**Implementation**: Use Cloudflare's Rate Limiting rules (available on free plan, 1 rule) combined with in-Worker logic using D1 or Workers KV for counters.

### 4.6 Sound and Haptic Customization Limitations

**Custom notification sounds:**

- **iOS**: Custom sounds must be bundled with the app binary (in the app's main bundle or Library/Sounds). They must be under 30 seconds and in aiff, wav, or caf format. You specify the sound filename in the APNs payload. This works for remote push notifications.
- **Android**: Custom sounds are set per notification channel. The sound file must be in `res/raw`. Once a channel is created, its sound cannot be changed -- you must create a new channel. Users can override channel sounds in system settings.
- **Expo limitation**: expo-notifications supports custom sounds for local notifications, but for remote push notifications through Expo's push service, only the default sound plays. **To use custom sounds with remote pushes, you must send pushes directly via FCM/APNs rather than through Expo's push relay.**

This is a critical architectural decision: either use Expo's push service (simpler, but default sounds only) or send pushes directly to FCM/APNs (more work, but full sound control). Given that distinct sounds per signal type are a core feature of YourTurn, **direct FCM/APNs integration is necessary**.

**Haptic feedback:**

- Haptics can only be triggered when the app is in the foreground. There is no API to trigger custom haptics from a push notification on either platform.
- iOS notification categories support "critical alerts" (requires Apple entitlement approval) that bypass Do Not Disturb, but these are reserved for health/safety apps.
- The workaround: when a notification is tapped and the app opens, immediately trigger the appropriate haptic pattern. For foreground notifications, trigger haptics immediately.

---

## Area 5: Development Lifecycle

### Tools and Services Needed

| Category | Tool/Service | Purpose | Cost |
|---|---|---|---|
| **IDE** | VS Code / Cursor | Development | Free |
| **Runtime** | Node.js 20+ | Expo/React Native dev | Free |
| **Framework** | Expo SDK 52+ | Cross-platform app | Free |
| **Build** | EAS Build | Native compilation | Free tier: 30 builds/month |
| **Backend** | Cloudflare Workers | Signal relay API | Free tier sufficient for MVP |
| **Database** | Cloudflare D1 | User/agent/signal storage | Free tier sufficient for MVP |
| **Push (iOS)** | APNs HTTP/2 API | iOS push delivery | Free (requires Apple Dev account) |
| **Push (Android)** | FCM HTTP v1 API | Android push delivery | Free |
| **Auth emails** | Resend or AWS SES | Magic link delivery | Free tier: 100 emails/day (Resend), 200/day (SES) |
| **Source control** | GitHub | Code hosting | Free |
| **CI/CD** | GitHub Actions + EAS | Build and deploy | Free tier sufficient |
| **Monitoring** | Sentry (Expo plugin) | Error tracking | Free tier: 5K events/month |
| **Apple Dev** | Apple Developer Program | iOS distribution | $99/year |
| **Google Dev** | Google Play Console | Android distribution | $25 one-time |

**Total ongoing cost for MVP**: ~$99/year (Apple Developer Program) + $25 one-time (Google Play). Everything else fits within free tiers.

### MVP Scope and Complexity Estimate

**MVP features (Phase 1):**

1. User registration (magic link auth)
2. Add/remove agents (generate API keys)
3. Receive push notifications with 3 distinct sounds for 3 signal types
4. Signal history screen (last 50 signals)
5. Agent status indicator (last seen)
6. Backend: signal ingestion endpoint, push fanout, auth

**Complexity estimate:**

| Component | Effort | Notes |
|---|---|---|
| Expo app scaffold + navigation | 2 days | Single tab navigator, 3 screens |
| Auth flow (magic link) | 3 days | Including deep link setup, token storage |
| Push notification setup (FCM + APNs) | 3 days | Direct integration, not Expo push service |
| Agent management UI | 2 days | List, add, revoke, copy key |
| Signal history UI | 1 day | FlatList with signal type indicators |
| Notification presentation (sounds, categories) | 2 days | Custom sounds, notification channels |
| Foreground state display ("metronome" animation) | 2 days | Reanimated pulse animation |
| Cloudflare Worker backend | 3 days | Auth, signal endpoint, push fanout |
| D1 schema and migrations | 1 day | Users, agents, device tokens, signals |
| Rate limiting and security | 1 day | Cloudflare rules + in-worker limits |
| Testing and debugging on devices | 3 days | Physical device testing required |
| App Store / Play Store submission | 2 days | Screenshots, descriptions, review prep |
| **Total** | **~25 days** | **For a single experienced developer** |

This is roughly **5-6 weeks of solo development**, or **3 weeks with two developers** (one frontend, one backend).

### Phase 2 Features (Post-MVP)

- Notification grouping and threading
- Quick actions from notifications (approve/reject without opening app)
- Agent health monitoring (alert if agent hasn't pinged in N minutes)
- Team/org support (shared agents across team members)
- Webhook forwarding (forward signals to Slack, Discord, etc.)
- Widget (iOS/Android home screen widget showing agent status)
- ntfy.sh integration as alternate delivery channel

### Deployment Pipeline

```
Developer pushes to main
  |
  v
GitHub Actions
  |-- Run TypeScript checks + ESLint
  |-- Run Jest unit tests
  |-- Run Cloudflare Worker tests (miniflare)
  |
  |-- [on tag/release]
  |   |-- EAS Build (iOS + Android)
  |   |-- EAS Submit (TestFlight + Google Play Internal Track)
  |   |-- Cloudflare Worker deploy (wrangler)
  |
  v
Manual promotion: TestFlight -> App Store, Internal -> Production
```

### Testing Strategy for Push Notifications

Push notifications cannot be tested in simulators/emulators. This requires a specific strategy:

1. **Unit tests** (Jest): Test signal processing logic, API key validation, rate limiting logic, notification payload construction. These do not require devices.

2. **Integration tests** (miniflare): Test the Cloudflare Worker locally. Mock FCM/APNs responses. Verify correct payloads are constructed for each signal type.

3. **Device testing** (manual, physical devices):
   - Minimum: 1 iPhone (iOS 16+), 1 Android phone (API 33+).
   - Use EAS development builds for fast iteration.
   - Expo's push notification tool can send test pushes to verify token registration.
   - For direct FCM/APNs testing, use Firebase console and APNs testing tools.

4. **End-to-end testing**:
   - Script that sends a signal via curl, then verifies (via backend logs) that the push was dispatched.
   - On-device verification is manual: confirm the notification appears with correct sound and content.

5. **Staging environment**:
   - Separate Cloudflare Worker + D1 instance with a different domain (e.g., `staging-api.yourturn.app`).
   - Separate FCM project and APNs environment (sandbox).
   - TestFlight and Google Play Internal Track for distribution to testers.

---

## Recommended Architecture

### System Diagram

```
+------------------+     +------------------+     +------------------+
|  Claude Code CLI |     |   Codex Agent    |     |  Custom Agent    |
|  (or any agent)  |     |                  |     |  (user-defined)  |
+--------+---------+     +--------+---------+     +--------+---------+
         |                         |                        |
         |  HTTPS POST            |  HTTPS POST            |  HTTPS POST
         |  /v1/signal            |  /v1/signal            |  /v1/signal
         v                         v                        v
+--------+-------------------------+------------------------+---------+
|                    Cloudflare Worker (Edge)                          |
|                                                                     |
|  1. Validate API key (D1 lookup, cached in Worker memory)           |
|  2. Rate limit check (Workers KV counter)                           |
|  3. Store signal in D1                                              |
|  4. Lookup user's device tokens (D1)                                |
|  5. Send push notification:                                         |
|     - iOS: APNs HTTP/2 API                                         |
|     - Android: FCM HTTP v1 API                                     |
+---------------------------------------------------------------------+
         |                                      |
         | APNs push                            | FCM push
         v                                      v
+------------------+                   +------------------+
|   iPhone         |                   |   Android        |
|   YourTurn app   |                   |   YourTurn app   |
|                  |                   |                  |
|  - Notification  |                   |  - Notification  |
|    with custom   |                   |    with custom   |
|    sound/haptic  |                   |    sound/channel |
|  - In-app state  |                   |  - In-app state  |
|    display       |                   |    display       |
+------------------+                   +------------------+
```

### Technology Stack Summary

| Layer | Technology | Rationale |
|---|---|---|
| Mobile app | Expo (React Native) | Lightest cross-platform option with full push support |
| Backend API | Cloudflare Workers | Sub-50ms cold start, free tier, zero ops |
| Database | Cloudflare D1 | Co-located with Workers, SQLite simplicity, free tier |
| Rate limiting | Workers KV | Fast counter reads/writes at the edge |
| iOS push | APNs HTTP/2 (direct) | Custom sound support, no intermediary |
| Android push | FCM HTTP v1 (direct) | Custom sound support via channels |
| Auth emails | Resend | Simple API, generous free tier, good deliverability |
| Monitoring | Sentry + Cloudflare analytics | Error tracking + request metrics |

### API Surface

```
POST   /v1/auth/magic-link      -- Request magic link email
POST   /v1/auth/verify           -- Verify magic link token, return session
POST   /v1/auth/refresh          -- Refresh session token

GET    /v1/agents                -- List user's agents
POST   /v1/agents                -- Create agent, returns API key
DELETE /v1/agents/:id            -- Revoke agent and its API key

POST   /v1/devices               -- Register device push token
DELETE /v1/devices/:id           -- Unregister device

POST   /v1/signal                -- Agent sends a signal (API key auth)

GET    /v1/signals               -- User fetches signal history (session auth)
GET    /v1/signals/latest        -- Latest signal per agent (for foreground polling)
```

Total: 9 endpoints. This is a small API surface, implementable in a single Cloudflare Worker file (or a few modules).

---

## Sources

### PWA and iOS Limitations
- [Progressive Web Apps on iOS - Complete Guide 2026](https://www.mobiloud.com/blog/progressive-web-apps-ios)
- [PWA on iOS - Current Status and Limitations 2025](https://brainhub.eu/library/pwa-on-ios)
- [PWA iOS Limitations and Safari Support](https://www.magicbell.com/blog/pwa-ios-limitations-safari-support-complete-guide)
- [Apple Developer - Web Push in Web Apps](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers)

### Framework Comparison
- [Flutter vs React Native 2026 Benchmarks](https://adevs.com/blog/react-native-vs-flutter/)
- [Flutter vs React Native Comparison Guide 2025](https://www.thedroidsonroids.com/blog/flutter-vs-react-native-comparison)
- [Cross-Platform Development Comparison 2025](https://dev.to/sajan_kumarsingh_b556129/cross-platform-mobile-development-react-native-vs-flutter-vs-progressive-web-apps-in-2025-50am)
- [Expo for React Native in 2025](https://hashrocket.com/blog/posts/expo-for-react-native-in-2025-a-perspective)
- [Understanding Expo App Size](https://docs.expo.dev/distribution/app-size/)

### Push Notifications and Delivery
- [Why Mobile Push Notification Architecture Fails](https://www.netguru.com/blog/why-mobile-push-notification-architecture-fails)
- [Push Notifications Deep Dive: APNs and FCM](https://www.spritle.com/blog/push-notifications-deep-dive-the-ultimate-technical-guide-to-apns-fcm/)
- [Why Push Notifications Go Undelivered on Android](https://clevertap.com/blog/why-push-notifications-go-undelivered-and-what-to-do-about-it/)
- [Mobile Push Notifications vs WebSockets](https://www.curiosum.com/blog/mobile-push-notifications-description-and-comparison-with-web-sockets)

### ntfy.sh
- [ntfy.sh Official](https://ntfy.sh/)
- [ntfy GitHub](https://github.com/binwiederhier/ntfy)
- [ntfy iOS Push Issues (GitHub Issue #1191)](https://github.com/binwiederhier/ntfy/issues/1191)
- [Self-Hosted Push Notifications with ntfy on iOS](https://noted.lol/ntfy/)
- [ntfy vs Pushover Comparison (HN)](https://news.ycombinator.com/item?id=44975650)
- [Gotify, Pushover and ntfy Comparison](https://debian.ninja/post/2025/09/23/gotify-pushover-and-ntfy-real-time-notifications/)

### Cloudflare Workers and D1
- [Cloudflare Durable Objects](https://workers.cloudflare.com/product/durable-objects/)
- [Cloudflare Workers Pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [Cloudflare D1 Pricing](https://developers.cloudflare.com/d1/platform/pricing/)
- [WebSocket on Cloudflare Workers](https://developers.cloudflare.com/workers/runtime-apis/websockets/)

### iOS Background Execution
- [iOS Background Execution Limits (Apple Forums)](https://developer.apple.com/forums/thread/685525)
- [Silent Push Notifications - Opportunities Not Guarantees](https://mohsinkhan845.medium.com/silent-push-notifications-in-ios-opportunities-not-guarantees-2f18f645b5d5)
- [iOS 26 Background APIs - BGContinuedProcessingTask](https://dev.to/arshtechpro/wwdc-2025-ios-26-background-apis-explained-bgcontinuedprocessingtask-changes-everything-9b5)

### Battery and Performance
- [WebSocket Battery vs Push Notification](https://www.curiosum.com/blog/mobile-push-notifications-description-and-comparison-with-web-sockets)
- [ntfy WebSocket Battery Issue](https://github.com/binwiederhier/ntfy/issues/190)
- [WebSocket Testing for Mobile - Battery Optimization](https://yrkan.com/blog/websocket-mobile-testing/)

### App Store Guidelines
- [Apple App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Store Review Guidelines 2025 Checklist](https://nextnative.dev/blog/app-store-review-guidelines)
- [Apple App Store Rejection Reasons 2025](https://twinr.dev/blogs/apple-app-store-rejection-reasons-2025/)
- [Common Google Play Store Rejections](https://onemobile.ai/common-google-play-store-rejections/)

### Sound and Haptics
- [Haptic Feedback in iOS - Comprehensive Guide](https://dev.to/maxnxi/haptic-feedback-in-ios-a-comprehensive-guide-39fb)
- [Core Haptics (Apple Developer)](https://developer.apple.com/documentation/corehaptics/)
- [Expo Notifications - Custom Sound Issues](https://github.com/expo/expo/issues/16447)

### Authentication
- [Magic Link Authentication Guide (Clerk)](https://clerk.com/blog/magic-links)
- [OTP vs Magic Link Comparison](https://www.scalekit.com/blog/otp-vs-magic-links-passwordless-authentication)
- [Magic Links UX and Security for SaaS](https://www.baytechconsulting.com/blog/magic-links-ux-security-and-growth-impacts-for-saas-platforms-2025)

### Rate Limiting and Security
- [API Rate Limiting and Abuse Prevention Guide](https://kokil.com.np/blog/a-practical-guide-to-api-rate-limiting-and-abuse-prevention-in-modern-web-apps)
- [Webhook Security Best Practices](https://www.webhookdebugger.com/blog/webhook-security-best-practices)
- [Cloudflare Rate Limiting Best Practices](https://developers.cloudflare.com/waf/rate-limiting-rules/best-practices/)

### Expo and Testing
- [Expo Push Notifications Setup](https://docs.expo.dev/push-notifications/push-notifications-setup/)
- [Expo Notifications SDK](https://docs.expo.dev/versions/latest/sdk/notifications/)
- [Expo Push Notification Tool](https://expo.dev/notifications)
