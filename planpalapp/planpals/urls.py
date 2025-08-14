# ============================================================================
# PLANPAL API URLs - OAuth2 Authentication
# ============================================================================

from django.urls import path, include
from rest_framework.routers import DefaultRouter

from .views import (
    OAuth2LogoutView, UserViewSet, GroupViewSet,
    PlanViewSet, ChatMessageViewSet, PlanActivityViewSet,
    # Friendship views (class-based, not ViewSet)
    FriendRequestView, FriendRequestListView, FriendRequestActionView, FriendsListView,
    # Location/Places API views (using Goong Map API)
    PlacesSearchView, PlaceDetailsView, NearbyPlacesView, 
    PlaceAutocompleteView, GeocodeView, SendNotificationView
)

# Router cho ViewSets
router = DefaultRouter()

# ✅ FIXED: Add basename for all ViewSets without queryset attribute
router.register(r'users', UserViewSet, basename='user')
router.register(r'groups', GroupViewSet, basename='group')
router.register(r'plans', PlanViewSet, basename='plan')  # FIXED - ModelViewSet also needs basename!
router.register(r'messages', ChatMessageViewSet, basename='chatmessage')
router.register(r'activities', PlanActivityViewSet, basename='planactivity')

urlpatterns = [
    # OAuth2 Authentication endpoints
    path('auth/logout/', OAuth2LogoutView.as_view(), name='oauth2_logout'),
    
    # Friendship endpoints (class-based views)
    path('friends/request/', FriendRequestView.as_view(), name='friend_request'),
    path('friends/requests/', FriendRequestListView.as_view(), name='friend_requests'),
    path('friends/requests/<int:request_id>/action/', FriendRequestActionView.as_view(), name='friend_request_action'),
    path('friends/', FriendsListView.as_view(), name='friends_list'),
    
    # Location/Places API endpoints (using Goong Map API)
    path('places/search/', PlacesSearchView.as_view(), name='places_search'),
    path('places/<str:place_id>/details/', PlaceDetailsView.as_view(), name='place_details'),
    path('places/nearby/', NearbyPlacesView.as_view(), name='nearby_places'),
    path('places/autocomplete/', PlaceAutocompleteView.as_view(), name='place_autocomplete'),
    path('geocode/', GeocodeView.as_view(), name='geocode'),
    path('notifications/send/', SendNotificationView.as_view(), name='send_notification'),
    
    # API routes
    path('', include(router.urls)),
]
