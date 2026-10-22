# PlanPal Journey System

The full identity rationale, logo usage and asset inventory are documented in
[`BRAND_FOUNDATION.md`](BRAND_FOUNDATION.md).

## Product direction

PlanPal uses a travel-first visual language called **PlanPal Journey System**.
Its signature idea is **Journey Together**: routes, stops, destinations and
people moving through places as one group. The UI
should feel calm enough for long planning sessions and energetic enough to
support discovery. Hierarchy comes from alignment, typography and whitespace
before containers, color or elevation.

The two recurring motifs are:

- **Route thread**: a continuous line and destination dots for itinerary,
  activity feeds and branded hero areas.
- **Travel stamp**: a compact icon container used for page and section
  identity. It is functional, not decorative.

## Product architecture

Trip is the central product object. It owns itinerary, map, places, budget,
decisions, members and trip chat. Group is the collaboration workspace;
messages are communication; notifications and profile are utilities.

Mobile navigation is `Home / Trips / Create / Groups / Me`. The centered
Create action opens a contextual sheet and never duplicates the navigation in
a drawer. Messages remain reachable from the Home header and group context.

Desktop navigation is `Home / Trips / Explore / Groups / Messages`, with
notifications and profile separated as utilities. Expanded layouts use
master-detail and split views rather than stretching the mobile composition.

## Foundations

### Color

- Journey Green `#0B6B62`: primary actions, selected state and navigation.
- Horizon Blue `#287E9A`: maps, realtime and informational content.
- Discovery Coral `#F47A5A`: discovery moments and selective emphasis.
- Sand Canvas `#F7F6F1`: light background.
- Night Forest `#0D1D1B`: dark background.
- Semantic colors are reserved for success, warning, error and information.

New code reads semantic roles from `PlanPalSemanticColors` through
`context.semanticColors`. Physical palette values remain in `AppColors` only
for theme construction and backwards compatibility. This prevents a feature
from choosing a different teal, surface or muted-text color locally.

Use colors through `Theme.of(context).colorScheme` or `AppColors`. Never add a
feature-specific primary color directly in a page.

### Typography

Manrope is the UI/body typeface. Space Grotesk is the display and major-title
typeface. Both explicitly support Vietnamese. The supported hierarchy is:

- `headlineLarge`: exceptional hero content only.
- `headlineSmall`: page title.
- `titleLarge`: major section.
- `titleMedium`: card/object title.
- `bodyLarge` and `bodyMedium`: primary reading text.
- `bodySmall` and labels: metadata.

Use weight 800 sparingly for page and section anchors. Metadata uses
`onSurfaceVariant`; it must remain readable in both themes.

### Spacing and geometry

- Spacing follows the 4/8 scale in `AppSpacing`.
- Page horizontal padding: 16px compact, 24px medium/expanded.
- Control height: at least 48px; touch target: at least 44x44px.
- Control radius: 12px; card radius: 16px; sheet radius: 24px.
- Cards default to a one-pixel semantic outline and no shadow.
- Elevation is reserved for hover, modal, dropdown and map overlays.

### Motion

- Quick feedback: 140ms.
- Standard state transition: 220ms.
- Emphasized spatial transition: 300ms.
- Respect platform reduced-motion behavior and never delay an action for
  decoration.

## Components

- `JourneyPageHeader`: page identity and optional single contextual action.
- `JourneySectionHeader`: section title, optional subtitle and tertiary action.
- `JourneySurface`: interactive object container with hover and selected state.
- `JourneyMetricStrip`: compact responsive metrics without dashboard cards.
- `JourneyRouteMarker`: itinerary and activity-feed route thread.
- `JourneyPathBackdrop`: low-contrast branded hero background.
- `JourneyLine`, `JourneyPath`, `JourneyStop`, `JourneyProgress`: sequence and
  travel-progress primitives with horizontal/vertical composition.
- `PlanPalLogo`, `PlanPalMark`: scalable in-app brand rendering.
- `JourneyIllustration`: shared cartographic empty/onboarding/success visual.
- `AppCard`, `InfoCard`, `StatCard`: compatibility primitives that share the
  same semantic surface, radius and border rules.

All inputs, buttons, chips, dialogs, sheets, tabs and navigation inherit their
states from `AppTheme`. A page should not locally recreate these states unless
the interaction genuinely differs.

Phosphor is the product-navigation icon family. Core destinations and global
actions use regular weight and switch to fill for selected state. Material
icons remain acceptable for established domain/status symbols where replacing
them would reduce recognition, but a single component must not mix icon styles.

## Interaction rules

- Each screen exposes one primary action. Secondary actions belong in an
  outlined/tertiary control, contextual menu or bottom sheet.
- Mobile screens focus on one or two jobs and use bottom sheets for supporting
  choices.
- Desktop uses contextual side panels, master-detail or split views; it does
  not stretch a compact form across the viewport.
- Forms remain between 640px and 720px wide and keep draft state until the
  final submit.
- Loading preserves layout with skeletons. Empty and error states always offer
  the next useful action.
- Color is never the only status signal. Icons, labels and semantics accompany
  important states.

## Responsive behavior

- `<600px`: bottom navigation, single-column content and thumb-reachable main
  actions.
- `600-1024px`: navigation rail and centered, width-constrained content.
- `>1024px`: persistent sidebar plus split or contextual layouts where useful.

Map detail is a bottom sheet on mobile and a right-side inspector on desktop.
Group detail and budget overview use two-column information architecture on
expanded screens while preserving the mobile reading order.

Authenticated Home uses the next relevant journey as its emotional anchor;
the app bar carries identity and utilities without competing with that story.
Itinerary stays a vertical route on compact screens and becomes a synchronized
timeline plus Goong map on expanded screens when activities contain locations.
Availability stays a thumb-friendly stack on mobile and becomes a comparison
matrix on wider screens. Poll creation offers optional travel-question starters
without changing the stored poll contract.

Trip Detail uses contextual `Overview / Itinerary / Decisions / More` sections
on compact and medium screens. Expanded screens expose the complete workspace;
the dedicated itinerary view provides the synchronized timeline and Goong map.
Administrative actions remain in More instead of competing with journey tasks.

## Review checklist

- Is the page purpose clear in five seconds?
- Is there exactly one visually dominant action?
- Can secondary content be hidden until needed?
- Are spacing, type, color and icons sourced from shared tokens?
- Does the screen work at compact, medium and expanded widths?
- Are hover, focus, pressed, loading, disabled, empty and error states present?
- Can a screen reader identify icon-only controls?
- Does the page preserve all existing permissions and business behavior?
