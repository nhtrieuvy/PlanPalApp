# PlanPal UX/UI Audit and Redesign Direction

## Audit summary

The original product was functionally complete but visually communicated a
generic productivity dashboard. Home prioritized quick-action tiles instead
of the next journey, mobile repeated destinations in both a drawer and bottom
navigation, and several group and plan pages exposed unrelated concepts at the
same visual level. Desktop often displayed a centered mobile column instead of
using the available width. Cards, dark teal fills, mixed icon styles and local
spacing values weakened hierarchy.

Highest-impact findings:

- P1: duplicated mobile navigation and too many equal top-level destinations.
- P1: Group Detail mixed plans, polls, availability, members, audit and admin
  controls in one continuous mobile page.
- P1: Messages did not use desktop master-detail composition.
- P2: Home behaved like a dashboard rather than answering what needs attention
  next.
- P2: trip cards resembled generic task cards and lacked a journey signature.
- P2: Profile exposed database-like rows and legacy GetWidget components.
- P2: desktop list pages underused wide layouts.
- P3: inconsistent typography, radius, elevation, empty states and motion.

## Research synthesis

The redesign uses product patterns rather than visual copies:

- Wanderlog and TripIt: trip-first organization and itinerary scanning.
- Airbnb and Google Maps: place-forward hierarchy and contextual map detail.
- Splitwise: plain-language balances and one dominant financial action.
- Notion and Linear: restrained surfaces, fast scanning and contextual detail.
- Modern collaborative planners: visible people, participation and decisions.

## Design direction

The visual language is **PlanPal Journey System**, with **Journey Together** as
its motif. A route thread and destination stops appear only where they explain
progress, sequence or spatial relationships. Ocean Teal remains the brand
anchor; Sunset Coral highlights selective discovery moments; Sky Blue supports
maps and realtime states; Sand and Deep Ocean provide warm light and immersive
dark canvases.

Hierarchy is built in this order: position, typography, whitespace, alignment,
divider, surface, then color. A mobile screen should normally contain no more
than three dominant surfaces and one primary action.

## Platform strategy

Mobile focuses on one or two jobs per screen. It uses bottom navigation,
contextual sheets, sticky actions and full-screen drill-down. Group Detail is
split into Overview, Trips, Decisions and Members. Messages use list-to-detail
navigation.

Desktop exposes useful context simultaneously. Trips use master-detail,
Messages use conversation-list plus active-chat, and wide group/plan screens
use deliberate columns. Utility destinations do not compete with product
destinations in the sidebar.

## Implemented coverage

- Shared color, typography, spacing, radius, elevation and motion tokens.
- Shared Journey surfaces, headers, metrics, route markers and route progress.
- Responsive mobile, rail and desktop application shell.
- Travel-first Home with next-adventure hero and contextual content.
- Travel-specific Trips list with desktop master-detail preview.
- Group Detail contextual sections on mobile and two-column desktop layout.
- Desktop Messages master-detail while preserving mobile routes.
- Profile identity hero, metrics, preferences, theme/language controls and
  account action hierarchy.
- Responsive Groups collection with flatter object surfaces.
- Existing itinerary, map, budget, poll and form work aligned to shared tokens.

## Second-pass system audit

The second pass reviewed every presentation page and the shared widgets again
at compact, medium and expanded composition boundaries. It also scanned for
legacy GetWidget components, off-system typography, hard-coded generic
microcopy and pages that still stretched a compact layout across desktop.

| Product area | Mobile | Web | Result |
| --- | --- | --- | --- |
| App shell and navigation | Bottom navigation with one contextual Create action | Rail/sidebar with utility destinations separated | Complete |
| Authentication and OTP | Focused, keyboard-safe single-column flow | Branded split composition with constrained form | Complete |
| Home and Trips | Next journey and immediate actions first | Wider contextual overview and trip master-detail | Complete |
| Itinerary and activity | Timeline-first reading, secondary actions disclosed contextually | Readable constrained detail and wider schedule context | Complete |
| Groups, invites and decisions | Segmented detail; join/invite actions remain contextual | Two-column detail and width-constrained invite management | Complete |
| Availability and polls | Vote-first controls and visible best overlap | Wider comparison view without stretching controls | Complete |
| Messages and chat | List-to-detail navigation, thumb-reachable composer | Conversation master-detail with shared typography | Complete |
| Budget and expenses | One financial action per view and plain-language balances | Overview columns plus constrained ledger/detail/list views | Complete |
| Friends and public profile | Identity and relationship actions first | Responsive list grid and constrained profile detail | Complete |
| Notifications | Today/earlier grouping and clear unread state | Constrained feed and settings form | Complete |
| Search | One search task and direct result navigation | Constrained readable result column | Complete |
| Map and live location | Full-bleed map with contextual controls | Full-bleed spatial canvas by design | Complete |
| Admin analytics | Not part of consumer navigation | Retains its operational dashboard density | Intentionally isolated |

### Issues closed in the second pass

- Replaced the remaining legacy GetWidget action with the shared Material
  button hierarchy.
- Standardized chat, message composer and search typography on Manrope.
- Corrected status-chip contrast and removed unrelated purple/pink category
  colors from activity detail.
- Added responsive content bounds to balances, expense list/detail, global
  search, invite management and notification preferences.
- Reworked login, registration and OTP into one consistent auth family;
  registration now uses progressive disclosure and submits only at completion.
- Grouped notifications by time and made availability overlap visually
  comparable instead of exposing only vote counts.
- Localized remaining friend-search and new auth/collaboration copy in English
  and Vietnamese.

### Verification boundary

Static analysis and source-level consistency checks are clean. Final visual QA
must still be performed on representative viewports (`360x800`, `768x1024`,
`1024x768`, `1440x900`) and with text scaling, keyboard opening, dark mode and
reduced motion. This device/browser pass is required before release because it
cannot be fully proven by static analysis alone.

## Guardrails

Business services, repositories, DTOs, API contracts, permissions and routing
paths remain unchanged. Presentation code may select a different composition
at `<600`, `600-1024` and `>1024`, but it consumes the same Riverpod state and
invokes the same mutations.

## Authenticated product pass

The authenticated product was reviewed once more against the Journey System,
with Trip treated as the emotional and information center rather than a generic
project record. This pass closed the remaining high-impact gaps:

- Home now uses a compact branded app bar so the next journey, not a decorative
  header, owns the first content position.
- Desktop navigation adds Explore as a product destination while mobile keeps
  exactly `Home / Trips / Create / Groups / Me`.
- Expanded itinerary uses a synchronized timeline and Goong map; compact and
  medium layouts preserve the existing vertical timeline behavior.
- Profile leads with identity and recent journeys. Private account fields move
  into a secondary account-details sheet.
- Poll creation includes travel-specific question starters. Availability uses
  a desktop comparison matrix while retaining the existing mobile voting cards.
- Map pins use Journey Green and Discovery Coral instead of off-system purple.

All changes are presentation-only. Existing route paths, provider ownership,
repository calls, permissions and request/response contracts are unchanged.

## Final authenticated quality pass

The final pass rechecked the product against every section of the authenticated
redesign brief instead of treating the previous pass as complete. It found and
closed four remaining gaps:

- Trip Detail was still a mobile mega-page. It now uses focused Overview,
  Itinerary, Decisions and More sections while retaining every budget,
  collaboration, audit and management capability.
- Home now surfaces unread trip/group updates next to the next journey on web
  and directly below it on mobile, using the existing unread provider.
- Poll results now expose participant avatars, and expanded availability uses
  an actual traveler-by-date matrix with accessible icons and editable personal
  responses. Mobile keeps the stacked date-first interaction.
- Core navigation now uses the established Phosphor family, while remaining
  hard-coded status colors were migrated to semantic PlanPal colors for reliable
  light/dark contrast.

Availability and poll responses gained additive participant-summary fields.
Existing fields, endpoints and request bodies remain unchanged, and repository
prefetching prevents the new presentation data from creating N+1 queries.
