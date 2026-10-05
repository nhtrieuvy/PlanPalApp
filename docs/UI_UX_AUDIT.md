# PlanPal Mobile UI/UX Audit

## Scope

This audit covers the shared Flutter presentation system and the highest-use
flows: authentication, groups, plans, activities, profile, location, chat and
live location. Business rules, API contracts, routing and persistence remain
unchanged.

## Findings and resolution

| Priority | Finding | Resolution |
| --- | --- | --- |
| P0 | Google Static Maps embedded an API key in source and map views depended on Google SDK configuration. | Replaced all runtime maps with `PlanPalMap`, backed by MapLibre and Goong vector styles. Removed the iOS Google SDK bootstrap and Android Google Maps metadata. |
| P1 | Native dropdown overlays obscured page content and differed across forms. | Standardized selection on `AppSelectField`, which uses a constrained, scrollable bottom sheet with an explicit selected state. |
| P1 | Similar actions used inconsistent heights, radius, hierarchy and visual weight. | Centralized Filled, Elevated, Outlined, Text and Icon button themes with a 48 px control height and 44 px minimum touch target. |
| P1 | Dark surfaces, borders and text contrast varied by screen. | Defined light/dark semantic surfaces through `ColorScheme`, theme-level inputs, cards, sheets, snackbars, tabs and navigation. |
| P2 | Cards relied on mixed shadows and arbitrary padding. | `AppCard` now uses a 16 px radius, semantic outline and the 4/8 px spacing scale; elevation is opt-in. |
| P2 | Map screens had provider-specific UI and controls. | Added adaptive Goong light/dark styles, PlanPal marker treatment, attribution badge, consistent floating controls and bottom information surfaces. |
| P2 | Navigation, chips and tabs inherited inconsistent defaults. | Added app-level Material 3 themes for navigation bars, tabs, chips and progress indicators. |
| P3 | Spacing values were repeated without a shared vocabulary. | Added `AppSpacing`, `AppRadius` and `AppSize` tokens for new and refactored components. |

## Design system rules

- Page horizontal padding: 16 px; section spacing: 24 or 32 px.
- Controls: 48 px high, 12 px radius, one primary action per context.
- Cards: 16 px radius, subtle border, no shadow unless the surface floats.
- Touch targets: minimum 44 x 44 px.
- Primary color communicates action or selection, not decoration.
- Error, warning and success colors remain semantic and are paired with text or
  icons.
- Long option lists open as bottom sheets rather than overlay dropdown menus.
- All map presentation goes through `PlanPalMap`; feature screens never import a
  provider SDK directly.
- New copy must be added to the Vietnamese and English localization maps.

## Remaining migration rule

Older screens may still contain local semantic colors for domain statuses. New
work should use theme colors and shared components first. Local overrides are
acceptable only for destructive actions, status semantics or data
visualization, and must retain WCAG AA contrast in both themes.
