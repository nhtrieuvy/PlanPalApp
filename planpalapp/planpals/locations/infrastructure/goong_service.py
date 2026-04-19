from __future__ import annotations

import logging
from typing import Any

import requests
from django.conf import settings


logger = logging.getLogger(__name__)


class GoongMapService:
    """Thin infrastructure wrapper around Goong Map APIs."""

    base_url = 'https://rsapi.goong.io'

    def __init__(self) -> None:
        self.api_key = getattr(settings, 'GOONG_API_KEY', None)
        self.enabled = bool(self.api_key and self.api_key != 'your-goong-api-key')

        if self.enabled:
            self._session = requests.Session()
        else:
            self._session = None

    def is_available(self) -> bool:
        return self.enabled

    def search_places(
        self,
        query: str,
        location: tuple[float, float] | None = None,
        radius: int = 5000,
        more_compound: bool = True,
    ) -> list[dict[str, Any]]:
        if not self.enabled:
            return []

        params: dict[str, Any] = {
            'input': query,
            'api_key': self.api_key,
            'more_compound': more_compound,
        }
        if location:
            params['location'] = f'{location[0]},{location[1]}'
            params['radius'] = radius

        data = self._get_json('/Place/Text', params)
        if not data:
            return []

        return [self._format_place_data(prediction) for prediction in data.get('predictions', [])]

    def get_place_details(self, place_id: str) -> dict[str, Any] | None:
        if not self.enabled:
            return None

        data = self._get_json(
            '/Place/Detail',
            {
                'place_id': place_id,
                'api_key': self.api_key,
            },
        )
        if not data:
            return None

        result = data.get('result') or {}
        if not result:
            return None

        geometry = result.get('geometry') or {}
        location = geometry.get('location') or {}
        lat = location.get('lat')
        lng = location.get('lng')

        place_details = {
            'place_id': place_id,
            'name': result.get('name'),
            'address': result.get('formatted_address'),
            'formatted_address': result.get('formatted_address'),
            'phone': result.get('formatted_phone_number'),
            'website': result.get('website'),
            'rating': result.get('rating'),
            'user_ratings_total': result.get('user_ratings_total'),
            'geometry': geometry,
            'types': result.get('types', []),
            'opening_hours': result.get('opening_hours', {}),
            'photos': self._extract_photos(result.get('photos', [])),
            'business_status': result.get('business_status'),
        }
        if lat is not None and lng is not None:
            place_details['latitude'] = lat
            place_details['longitude'] = lng
        return place_details

    def autocomplete(
        self,
        input_text: str,
        location: tuple[float, float] | None = None,
        radius: int = 5000,
        more_compound: bool = True,
    ) -> list[dict[str, Any]]:
        if not self.enabled:
            return []

        params: dict[str, Any] = {
            'input': input_text,
            'api_key': self.api_key,
            'more_compound': more_compound,
            'limit': 10,
        }
        if location:
            params['location'] = f'{location[0]},{location[1]}'
            params['radius'] = radius

        data = self._get_json('/Place/AutoComplete', params)
        if not data:
            return []

        return [
            {
                'place_id': prediction.get('place_id'),
                'description': prediction.get('description'),
                'main_text': (prediction.get('structured_formatting') or {}).get('main_text'),
                'secondary_text': (
                    prediction.get('structured_formatting') or {}
                ).get('secondary_text'),
                'compound': prediction.get('compound', {}),
                'types': prediction.get('types', []),
            }
            for prediction in data.get('predictions', [])
        ]

    def geocode(self, address: str) -> dict[str, Any] | None:
        if not self.enabled:
            return None

        data = self._get_json(
            '/Geocode',
            {
                'address': address,
                'api_key': self.api_key,
            },
        )
        if not data:
            return None

        results = data.get('results') or []
        if not results:
            return None

        result = results[0]
        location = (result.get('geometry') or {}).get('location') or {}
        return {
            'latitude': location.get('lat'),
            'longitude': location.get('lng'),
            'formatted_address': result.get('formatted_address'),
            'place_id': result.get('place_id'),
            'address_components': result.get('address_components', []),
            'compound': result.get('compound', {}),
        }

    def reverse_geocode(self, latitude: float, longitude: float) -> dict[str, Any] | None:
        if not self.enabled:
            return None

        data = self._get_json(
            '/Geocode',
            {
                'latlng': f'{latitude},{longitude}',
                'api_key': self.api_key,
            },
        )
        if not data:
            return None

        results = data.get('results') or []
        if not results:
            return None

        result = results[0]
        return {
            'formatted_address': result.get('formatted_address'),
            'place_id': result.get('place_id'),
            'address_components': result.get('address_components', []),
            'compound': result.get('compound', {}),
            'latitude': latitude,
            'longitude': longitude,
        }

    def nearby_search(
        self,
        latitude: float,
        longitude: float,
        radius: int = 1500,
        type_filter: str | None = None,
    ) -> list[dict[str, Any]]:
        if not self.enabled:
            return []

        params: dict[str, Any] = {
            'location': f'{latitude},{longitude}',
            'radius': radius,
            'api_key': self.api_key,
        }
        if type_filter:
            params['type'] = type_filter

        data = self._get_json('/Place/Nearby', params)
        if not data:
            return []

        return [self._format_nearby_place_data(place) for place in data.get('results', [])]

    def get_directions(
        self,
        origin: str,
        destination: str,
        vehicle: str = 'car',
    ) -> dict[str, Any] | None:
        if not self.enabled:
            return None

        data = self._get_json(
            '/Direction',
            {
                'origin': origin,
                'destination': destination,
                'vehicle': vehicle,
                'api_key': self.api_key,
            },
            timeout=15,
        )
        if not data or not data.get('routes'):
            return None

        route = data['routes'][0]
        leg = route['legs'][0]
        return {
            'distance': leg.get('distance'),
            'duration': leg.get('duration'),
            'start_address': leg.get('start_address'),
            'end_address': leg.get('end_address'),
            'overview_polyline': route.get('overview_polyline'),
            'steps': leg.get('steps', []),
        }

    def _get_json(
        self,
        path: str,
        params: dict[str, Any],
        *,
        timeout: int = 10,
    ) -> dict[str, Any] | None:
        if not self._session:
            return None

        try:
            response = self._session.get(
                f'{self.base_url}{path}',
                params=params,
                timeout=timeout,
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException:
            logger.exception('Goong request failed for path %s', path)
            return None
        except ValueError:
            logger.exception('Goong returned invalid JSON for path %s', path)
            return None

    def _format_place_data(self, place: dict[str, Any]) -> dict[str, Any]:
        geometry = place.get('geometry') or {}
        location = geometry.get('location') or {}
        structured_formatting = place.get('structured_formatting') or {}

        return {
            'place_id': place.get('place_id'),
            'name': structured_formatting.get('main_text') or place.get('description'),
            'address': place.get('description'),
            'latitude': location.get('lat'),
            'longitude': location.get('lng'),
            'compound': place.get('compound', {}),
            'types': place.get('types', []),
            'geometry': geometry,
        }

    def _format_nearby_place_data(self, place: dict[str, Any]) -> dict[str, Any]:
        geometry = place.get('geometry') or {}
        location = geometry.get('location') or {}

        return {
            'place_id': place.get('place_id'),
            'name': place.get('name'),
            'address': place.get('vicinity'),
            'latitude': location.get('lat'),
            'longitude': location.get('lng'),
            'rating': place.get('rating'),
            'user_ratings_total': place.get('user_ratings_total'),
            'types': place.get('types', []),
            'photos': self._extract_photos(place.get('photos', [])),
            'price_level': place.get('price_level'),
            'opening_hours': place.get('opening_hours', {}),
            'business_status': place.get('business_status'),
            'geometry': geometry,
        }

    def _extract_photos(self, photos: list[dict[str, Any]]) -> list[str]:
        if not self.api_key or not photos:
            return []

        photo_urls: list[str] = []
        for photo in photos[:3]:
            photo_reference = photo.get('photo_reference')
            if not photo_reference:
                continue
            photo_urls.append(
                f'{self.base_url}/Place/Photo?maxwidth=400&photoreference={photo_reference}&api_key={self.api_key}'
            )
        return photo_urls
