from __future__ import annotations

import logging

from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from planpals.locations.application.services import LocationService


logger = logging.getLogger(__name__)


class BaseLocationView(APIView):
    permission_classes = [IsAuthenticated]

    @property
    def service(self) -> LocationService:
        return LocationService()


class LocationReverseGeocodeView(BaseLocationView):
    def post(self, request):
        latitude = request.data.get('latitude')
        longitude = request.data.get('longitude')

        if latitude is None or longitude is None:
            return Response(
                {'error': 'Latitude and longitude are required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            lat = float(latitude)
            lng = float(longitude)
        except (TypeError, ValueError):
            return Response(
                {'error': 'Invalid latitude or longitude format'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not (-90 <= lat <= 90):
            return Response(
                {'error': 'Latitude must be between -90 and 90'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not (-180 <= lng <= 180):
            return Response(
                {'error': 'Longitude must be between -180 and 180'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            return Response(self.service.reverse_geocode(lat, lng))
        except Exception:
            logger.exception('Reverse geocode failed for coordinates (%s, %s)', lat, lng)
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class LocationSearchView(BaseLocationView):
    def get(self, request):
        query = request.query_params.get('q', '').strip()

        if len(query) < 2:
            return Response(
                {'error': 'Search query must be at least 2 characters'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            return Response(self.service.search(query))
        except Exception:
            logger.exception('Place search failed for query "%s"', query)
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class LocationAutocompleteView(BaseLocationView):
    def get(self, request):
        input_text = request.query_params.get('input', '').strip()

        if len(input_text) < 2:
            return Response({'predictions': []})

        try:
            return Response(self.service.autocomplete(input_text))
        except Exception:
            logger.exception('Place autocomplete failed for input "%s"', input_text)
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class LocationPlaceDetailsView(BaseLocationView):
    def get(self, request):
        place_id = request.query_params.get('place_id', '').strip()

        if not place_id:
            return Response(
                {'error': 'place_id is required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            details = self.service.get_place_details(place_id)
        except Exception:
            logger.exception('Place details lookup failed for place_id "%s"', place_id)
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        if not details:
            return Response(
                {'error': 'Place not found'},
                status=status.HTTP_404_NOT_FOUND,
            )

        return Response(details)
