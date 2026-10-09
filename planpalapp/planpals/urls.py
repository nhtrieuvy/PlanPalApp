# ============================================================================
# PLANPAL API URLs - OAuth2 Authentication
# ============================================================================

from django.urls import path, include
from rest_framework.routers import DefaultRouter

from planpals.auth.presentation.views import (
    OAuth2LogoutView, WebSocketTicketView, UserViewSet,
    FriendRequestView, FriendRequestListView, FriendRequestActionView, FriendsListView,
)
from planpals.audit.presentation.views import AuditLogViewSet
from planpals.plans.presentation.views import PlanViewSet, PlanActivityViewSet
from planpals.plans.presentation.publications import (
    PublishedProfileView, PlanPublicationView, PublicationPreviewView,
)
from planpals.auth.presentation.friend_trips import (
    FriendTripListCreateView, FriendTripDecisionView,
)
from planpals.groups.presentation.views import (
    GroupInviteListCreateView,
    GroupInviteRevokeView,
    GroupJoinRequestApproveView,
    GroupJoinRequestListView,
    GroupJoinRequestRejectView,
    GroupViewSet,
    JoinGroupByInviteCodeView,
    JoinGroupViaInviteView,
)
from planpals.chat.presentation.views import ChatMessageViewSet, ConversationViewSet
from planpals.notifications.presentation.views import NotificationViewSet
from planpals.analytics.presentation.views import AnalyticsViewSet
from planpals.budgets.presentation.views import (
    PlanBalancesView,
    PlanBudgetView,
    PlanExpenseListCreateView,
    PlanExpenseCorrectionView,
    PlanExpenseDetailView,
    PlanFinanceInsightsView,
    PlanRecurringExpenseListView,
    PlanRecurringExpenseStatusView,
    SettlementCreateView,
    SettlementActionView,
)
from planpals.locations.presentation.views import (
    LocationReverseGeocodeView, LocationSearchView, LocationAutocompleteView, LocationPlaceDetailsView,
)
from planpals.experience.presentation.views import (
    ConversationLiveLocationListCreateView,
    GlobalSearchView,
    GroupPollCloseView,
    GroupPollListCreateView,
    GroupPollVoteView,
    LiveLocationDetailView,
)
from planpals.collaboration.presentation.views import (
    AvailabilityVoteView,
    CommentPinView,
    CommentReactionView,
    GroupAvailabilityPollListCreateView,
    PlanCalendarLinksView,
    PlanCloneView,
    PlanCommentDetailView,
    PlanCommentListCreateView,
    PlanICSExportView,
    PlanWorkItemDetailView,
    PlanWorkItemListCreateView,
)

# Router cho ViewSets
router = DefaultRouter()

# ✅ FIXED: Add basename for all ViewSets without queryset attribute
router.register(r'users', UserViewSet, basename='user')
router.register(r'groups', GroupViewSet, basename='group')
router.register(r'plans', PlanViewSet, basename='plan')  # FIXED - ModelViewSet also needs basename!
router.register(r'messages', ChatMessageViewSet, basename='chatmessage')
router.register(r'conversations', ConversationViewSet, basename='conversation')
router.register(r'activities', PlanActivityViewSet, basename='planactivity')
router.register(r'audit-logs', AuditLogViewSet, basename='audit-log')
router.register(r'notifications', NotificationViewSet, basename='notification')
router.register(r'analytics', AnalyticsViewSet, basename='analytics')

urlpatterns = [
    path('friends/trip-invitations/', FriendTripListCreateView.as_view()),
    path('friends/trip-invitations/<uuid:invitation_id>/decision/', FriendTripDecisionView.as_view()),
    path('users/<uuid:user_id>/published-profile/', PublishedProfileView.as_view()),
    path('plans/<uuid:plan_id>/publication/', PlanPublicationView.as_view()),
    path('publications/<uuid:publication_id>/', PublicationPreviewView.as_view()),
    # OAuth2 Authentication endpoints
    path('auth/logout/', OAuth2LogoutView.as_view(), name='oauth2_logout'),
    path(
        'auth/websocket-ticket/',
        WebSocketTicketView.as_view(),
        name='websocket-ticket',
    ),
    
    # Friendship endpoints (class-based views)
    path('friends/request/', FriendRequestView.as_view(), name='friend_request'),
    path('friends/requests/', FriendRequestListView.as_view(), name='friend_requests'),
    path('friends/requests/<uuid:request_id>/action/', FriendRequestActionView.as_view(), name='friend_request_action'),
    path('friends/', FriendsListView.as_view(), name='friends_list'),
    
    # Enhanced location API endpoints for minimap
    path('location/reverse-geocode/', LocationReverseGeocodeView.as_view(), name='location_reverse_geocode'),
    path('location/search/', LocationSearchView.as_view(), name='location_search'),
    path('location/autocomplete/', LocationAutocompleteView.as_view(), name='location_autocomplete'),
    path('location/place-details/', LocationPlaceDetailsView.as_view(), name='location_place_details'),
    path('plans/<uuid:plan_id>/budget/', PlanBudgetView.as_view(), name='plan-budget'),
    path('plans/<uuid:plan_id>/expenses/', PlanExpenseListCreateView.as_view(), name='plan-expenses'),
    path('plans/<uuid:plan_id>/expenses/<uuid:expense_id>/', PlanExpenseDetailView.as_view(), name='plan-expense-detail'),
    path('plans/<uuid:plan_id>/balances/', PlanBalancesView.as_view(), name='plan-balances'),
    path('plans/<uuid:plan_id>/finance-insights/', PlanFinanceInsightsView.as_view(), name='plan-finance-insights'),
    path('plans/<uuid:plan_id>/recurring-expenses/', PlanRecurringExpenseListView.as_view(), name='plan-recurring-expenses'),
    path('plans/<uuid:plan_id>/recurring-expenses/<uuid:recurring_id>/', PlanRecurringExpenseStatusView.as_view(), name='plan-recurring-expense-status'),
    path('plans/<uuid:plan_id>/expenses/<uuid:expense_id>/corrections/', PlanExpenseCorrectionView.as_view(), name='plan-expense-corrections'),
    path('settlements/', SettlementCreateView.as_view(), name='settlements'),
    path('settlements/<uuid:settlement_id>/<str:action>/', SettlementActionView.as_view(), name='settlement-action'),
    path('search/', GlobalSearchView.as_view(), name='global-search'),
    path('groups/<uuid:group_id>/polls/', GroupPollListCreateView.as_view(), name='group-polls'),
    path('group-polls/<uuid:poll_id>/vote/', GroupPollVoteView.as_view(), name='group-poll-vote'),
    path('group-polls/<uuid:poll_id>/close/', GroupPollCloseView.as_view(), name='group-poll-close'),
    path('conversations/<uuid:conversation_id>/live-locations/', ConversationLiveLocationListCreateView.as_view(), name='conversation-live-locations'),
    path('live-locations/<uuid:share_id>/', LiveLocationDetailView.as_view(), name='live-location-detail'),
    path('groups/<uuid:group_id>/availability-polls/', GroupAvailabilityPollListCreateView.as_view(), name='group-availability-polls'),
    path('availability-polls/<uuid:poll_id>/vote/', AvailabilityVoteView.as_view(), name='availability-poll-vote'),
    path('plans/<uuid:plan_id>/work-items/', PlanWorkItemListCreateView.as_view(), name='plan-work-items'),
    path('plan-work-items/<uuid:item_id>/', PlanWorkItemDetailView.as_view(), name='plan-work-item-detail'),
    path('plans/<uuid:plan_id>/comments/', PlanCommentListCreateView.as_view(), name='plan-comments'),
    path('plan-comments/<uuid:comment_id>/', PlanCommentDetailView.as_view(), name='plan-comment-detail'),
    path('plan-comments/<uuid:comment_id>/react/', CommentReactionView.as_view(), name='plan-comment-react'),
    path('plan-comments/<uuid:comment_id>/pin/', CommentPinView.as_view(), name='plan-comment-pin'),
    path('plans/<uuid:plan_id>/clone/', PlanCloneView.as_view(), name='plan-clone'),
    path('plans/<uuid:plan_id>/export.ics', PlanICSExportView.as_view(), name='plan-export-ics'),
    path('plans/<uuid:plan_id>/calendar-links/', PlanCalendarLinksView.as_view(), name='plan-calendar-links'),
    path('groups/<uuid:group_id>/invites/', GroupInviteListCreateView.as_view(), name='group-invites'),
    path('groups/<uuid:group_id>/join-requests/', GroupJoinRequestListView.as_view(), name='group-join-requests'),
    path('groups/invites/<uuid:invite_id>/', GroupInviteRevokeView.as_view(), name='group-invite-revoke'),
    path('groups/join-requests/<uuid:request_id>/approve/', GroupJoinRequestApproveView.as_view(), name='group-join-request-approve'),
    path('groups/join-requests/<uuid:request_id>/reject/', GroupJoinRequestRejectView.as_view(), name='group-join-request-reject'),
    path('groups/join-code/', JoinGroupByInviteCodeView.as_view(), name='group-join-code'),
    path('groups/join/<str:token>/', JoinGroupViaInviteView.as_view(), name='group-join-invite'),
    
    # API routes
    path('', include(router.urls)),
]
