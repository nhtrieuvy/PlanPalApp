# ============================================================================
# PLANPAL API URLs - OAuth2 Authentication
# ============================================================================

from django.urls import path, include
from rest_framework.routers import DefaultRouter

from planpals.auth.presentation.views import (
    OAuth2LogoutView, UserViewSet,
    FriendRequestView, FriendRequestListView, FriendRequestActionView, FriendsListView,
)
from planpals.audit.presentation.views import AuditLogViewSet
from planpals.plans.presentation.views import PlanViewSet, PlanActivityViewSet
from planpals.groups.presentation.views import GroupViewSet
from planpals.chat.presentation.views import ChatMessageViewSet, ConversationViewSet
from planpals.notifications.presentation.views import NotificationViewSet
from planpals.analytics.presentation.views import AnalyticsViewSet
from planpals.budgets.presentation.views import PlanBudgetView, PlanExpenseListCreateView
from planpals.locations.presentation.views import (
    LocationReverseGeocodeView, LocationSearchView, LocationAutocompleteView, LocationPlaceDetailsView,
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
    # OAuth2 Authentication endpoints
    path('auth/logout/', OAuth2LogoutView.as_view(), name='oauth2_logout'),
    
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
    
    # API routes
    path('', include(router.urls)),
]
