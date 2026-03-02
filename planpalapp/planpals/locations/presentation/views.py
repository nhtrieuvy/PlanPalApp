from rest_framework import status
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from planpals.locations.infrastructure.goong_service import GoongMapService


class PlacesSearchView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        query = request.query_params.get('query')
        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')
        radius = int(request.query_params.get('radius', 5000))
        place_type = request.query_params.get('type')

        if not query:
            return Response(
                {'error': 'query parameter required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        location = None
        if lat and lng:
            try:
                location = (float(lat), float(lng))
            except ValueError:
                return Response(
                    {'error': 'Invalid lat/lng format'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        places = GoongMapService.search_places(
            query=query,
            location=location,
            radius=radius
        )

        return Response({'places': places})


class PlaceDetailsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, place_id):
        place_details = GoongMapService.get_place_details(place_id)

        if place_details:
            return Response({'place': place_details})
        else:
            return Response(
                {'error': 'Place not found'},
                status=status.HTTP_404_NOT_FOUND
            )


class NearbyPlacesView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')
        radius = int(request.query_params.get('radius', 1000))
        place_type = request.query_params.get('type')

        if not lat or not lng:
            return Response(
                {'error': 'lat and lng parameters required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            lat = float(lat)
            lng = float(lng)
        except ValueError:
            return Response(
                {'error': 'Invalid lat/lng format'},
                status=status.HTTP_400_BAD_REQUEST
            )

        places = GoongMapService.nearby_search(
            latitude=lat,
            longitude=lng,
            radius=radius,
            type_filter=place_type
        )

        return Response({'places': places})


class PlaceAutocompleteView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        input_text = request.query_params.get('input')
        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')
        radius = int(request.query_params.get('radius', 5000))

        if not input_text:
            return Response(
                {'error': 'input parameter required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Convert lat/lng to tuple if provided for location bias
        location = None
        if lat and lng:
            try:
                location = (float(lat), float(lng))
            except ValueError:
                return Response(
                    {'error': 'Invalid lat/lng format'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        suggestions = GoongMapService.autocomplete(
            input_text=input_text,
            location=location,
            radius=radius
        )

        return Response({'suggestions': suggestions})


class GeocodeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        address = request.query_params.get('address')
        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')

        if address:
            # Forward geocoding: address to coordinates
            result = GoongMapService.geocode(address)
            if result:
                return Response({'result': result})
            else:
                return Response(
                    {'error': 'Address not found'},
                    status=status.HTTP_404_NOT_FOUND
                )

        elif lat and lng:
            # Reverse geocoding: coordinates to address
            try:
                lat = float(lat)
                lng = float(lng)
                result = GoongMapService.reverse_geocode(lat, lng)
                if result:
                    return Response({'result': result})
                else:
                    return Response(
                        {'error': 'Location not found'},
                        status=status.HTTP_404_NOT_FOUND
                    )
            except ValueError:
                return Response(
                    {'error': 'Invalid lat/lng format'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        else:
            return Response(
                {'error': 'Either address or lat/lng parameters required'},
                status=status.HTTP_400_BAD_REQUEST
            )


class LocationReverseGeocodeView(APIView):

    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            latitude = request.data.get('latitude')
            longitude = request.data.get('longitude')

            if latitude is None or longitude is None:
                return Response(
                    {'error': 'Latitude and longitude are required'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Convert to float and validate
            try:
                lat = float(latitude)
                lng = float(longitude)

                if not (-90 <= lat <= 90):
                    return Response(
                        {'error': 'Latitude must be between -90 and 90'},
                        status=status.HTTP_400_BAD_REQUEST
                    )

                if not (-180 <= lng <= 180):
                    return Response(
                        {'error': 'Longitude must be between -180 and 180'},
                        status=status.HTTP_400_BAD_REQUEST
                    )

            except (ValueError, TypeError):
                return Response(
                    {'error': 'Invalid latitude or longitude format'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Use Goong service for reverse geocoding
            goong_service = GoongMapService()

            if goong_service.is_available():
                result = goong_service.reverse_geocode(lat, lng)

                if result:
                    return Response({
                        'formatted_address': result.get('formatted_address', ''),
                        'location_name': result.get('formatted_address', 'Vị trí đã chọn'),
                        'latitude': lat,
                        'longitude': lng,
                        'place_id': result.get('place_id'),
                        'address_components': result.get('address_components', []),
                        'compound': result.get('compound', {})
                    })

            # Fallback response if Goong service is not available
            return Response({
                'formatted_address': f'{lat:.6f}, {lng:.6f}',
                'location_name': 'Vị trí đã chọn',
                'latitude': lat,
                'longitude': lng,
                'place_id': None,
                'address_components': [],
                'compound': {}
            })

        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LocationSearchView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            query = request.query_params.get('q', '').strip()

            if not query:
                return Response(
                    {'error': 'Search query is required'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if len(query) < 2:
                return Response(
                    {'error': 'Search query must be at least 2 characters'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Use Goong service for place search
            goong_service = GoongMapService()

            if goong_service.is_available():
                results = goong_service.search_places(query)
                return Response({'results': results})
            else:
                return Response({
                    'results': [],
                    'message': 'Location search service is not available'
                })

        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LocationAutocompleteView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            input_text = request.query_params.get('input', '').strip()

            if not input_text:
                return Response({'predictions': []})

            if len(input_text) < 2:
                return Response({'predictions': []})

            # Use Goong service for autocomplete
            goong_service = GoongMapService()

            if goong_service.is_available():
                suggestions = goong_service.autocomplete(input_text)

                predictions = []
                for suggestion in suggestions:
                    predictions.append({
                        'place_id': suggestion.get('place_id'),
                        'description': suggestion.get('description', ''),
                        'structured_formatting': suggestion.get('structured_formatting', {}),
                        'types': suggestion.get('types', []),
                        'latitude': None,
                        'longitude': None,
                    })

                return Response({'predictions': predictions})
            else:
                return Response({
                    'predictions': [],
                    'message': 'Autocomplete service is not available'
                })

        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LocationPlaceDetailsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            place_id = request.query_params.get('place_id', '').strip()

            if not place_id:
                return Response(
                    {'error': 'place_id is required'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Use Goong service for place details
            goong_service = GoongMapService()

            if goong_service.is_available():
                details = goong_service.get_place_details(place_id)

                if details:
                    return Response(details)
                else:
                    return Response(
                        {'error': 'Place not found'},
                        status=status.HTTP_404_NOT_FOUND
                    )
            else:
                return Response(
                    {'error': 'Place details service is not available'},
                    status=status.HTTP_503_SERVICE_UNAVAILABLE
                )

        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
