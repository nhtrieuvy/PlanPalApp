# ============================================================================
# PLANPAL API URLs - OAuth2 Authentication
# ============================================================================

from django.urls import path, include
from rest_framework.routers import DefaultRouter

from .views import (
    OAuth2LoginView, OAuth2LogoutView, UserViewSet, GroupViewSet,
    PlanViewSet, FriendshipViewSet, ChatMessageViewSet, 
    PlanActivityViewSet,
    # Service-based views
    PlacesSearchView, PlaceDetailsView, NearbyPlacesView, 
    SendNotificationView, EnhancedGroupViewSet, EnhancedPlanViewSet
)

# Router cho ViewSets
router = DefaultRouter()
router.register(r'users', UserViewSet)
router.register(r'groups', GroupViewSet)
router.register(r'plans', PlanViewSet)
router.register(r'friendships', FriendshipViewSet)
router.register(r'messages', ChatMessageViewSet)
router.register(r'activities', PlanActivityViewSet)

# Enhanced routers with services
router.register(r'enhanced-groups', EnhancedGroupViewSet, basename='enhancedgroup')
router.register(r'enhanced-plans', EnhancedPlanViewSet, basename='enhancedplan')

urlpatterns = [
    # OAuth2 Authentication endpoints
    path('auth/login/', OAuth2LoginView.as_view(), name='oauth2_login'),
    path('auth/logout/', OAuth2LogoutView.as_view(), name='oauth2_logout'),
    
    # External API endpoints
    path('places/search/', PlacesSearchView.as_view(), name='places_search'),
    path('places/<str:place_id>/details/', PlaceDetailsView.as_view(), name='place_details'),
    path('places/nearby/', NearbyPlacesView.as_view(), name='nearby_places'),
    path('notifications/send/', SendNotificationView.as_view(), name='send_notification'),
    
    # API routes
    path('', include(router.urls)),
]
