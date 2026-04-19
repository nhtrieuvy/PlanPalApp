from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from planpals.locations.infrastructure.goong_service import GoongMapService


DEFAULT_LOCATION_NAME = 'Vị trí đã chọn'


@dataclass(slots=True)
class LocationService:
    provider: GoongMapService

    def __init__(self, provider: GoongMapService | None = None) -> None:
        self.provider = provider or GoongMapService()

    def search(self, query: str) -> dict[str, Any]:
        return {'results': self.provider.search_places(query)}

    def autocomplete(self, input_text: str) -> dict[str, Any]:
        suggestions = self.provider.autocomplete(input_text)
        predictions = [
            {
                'place_id': suggestion.get('place_id'),
                'description': suggestion.get('description', ''),
                'structured_formatting': {
                    'main_text': suggestion.get('main_text') or suggestion.get('description', ''),
                    'secondary_text': suggestion.get('secondary_text') or '',
                },
                'types': suggestion.get('types', []),
                'latitude': suggestion.get('latitude'),
                'longitude': suggestion.get('longitude'),
            }
            for suggestion in suggestions
        ]
        return {'predictions': predictions}

    def get_place_details(self, place_id: str) -> dict[str, Any] | None:
        return self.provider.get_place_details(place_id)

    def reverse_geocode(self, latitude: float, longitude: float) -> dict[str, Any]:
        result = self.provider.reverse_geocode(latitude, longitude)
        if result:
            formatted_address = result.get('formatted_address') or self._format_coordinates(
                latitude,
                longitude,
            )
            return {
                'formatted_address': formatted_address,
                'location_name': formatted_address,
                'latitude': latitude,
                'longitude': longitude,
                'place_id': result.get('place_id'),
                'address_components': result.get('address_components', []),
                'compound': result.get('compound', {}),
            }

        formatted_address = self._format_coordinates(latitude, longitude)
        return {
            'formatted_address': formatted_address,
            'location_name': DEFAULT_LOCATION_NAME,
            'latitude': latitude,
            'longitude': longitude,
            'place_id': None,
            'address_components': [],
            'compound': {},
        }

    @staticmethod
    def _format_coordinates(latitude: float, longitude: float) -> str:
        return f'{latitude:.6f}, {longitude:.6f}'
