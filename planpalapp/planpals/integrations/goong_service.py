# ============================================================================
# GOONG MAP API SERVICE - VIETNAM LOCATION SERVICE
# ============================================================================

import requests
import os
from typing import List, Dict, Optional
from django.conf import settings

class GoongMapService:
    """Goong Map API service for Vietnam location-based features"""
    
    def __init__(self):
        self.api_key = os.getenv('GOONG_API_KEY')
        self.base_url = 'https://rsapi.goong.io'
        
        if self.api_key and self.api_key != 'your-goong-api-key':
            self.enabled = True
            print("✅ Goong Map API initialized successfully")
        else:
            self.enabled = False
            print("⚠️ Goong Map API key not configured")
    
    def is_available(self):
        """Check if Goong API is available"""
        return self.enabled
    
    def search_places(self, query: str, location: tuple = None, radius: int = 5000, 
                     more_compound: bool = True) -> List[Dict]:
        """
        Search for places using Goong Place API
        
        Args:
            query: Search query (e.g., "restaurant Ho Chi Minh City")
            location: Tuple of (lat, lng) to bias results
            radius: Search radius in meters
            more_compound: Return more detailed compound info
        """
        if not self.enabled:
            print("❌ Goong Map API not available")
            return []
        
        try:
            url = f"{self.base_url}/Place/Text"
            params = {
                'input': query,
                'api_key': self.api_key,
                'more_compound': more_compound
            }
            
            if location:
                params['location'] = f"{location[0]},{location[1]}"
                params['radius'] = radius
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            places = []
            for prediction in data.get('predictions', []):
                places.append(self._format_place_data(prediction))
            
            print(f"✅ Found {len(places)} places for query: {query}")
            return places
            
        except Exception as e:
            print(f"❌ Error searching places: {e}")
            return []
    
    def get_place_details(self, place_id: str) -> Optional[Dict]:
        """
        Get detailed information about a specific place
        
        Args:
            place_id: Goong place ID
        """
        if not self.enabled:
            return None
        
        try:
            url = f"{self.base_url}/Place/Detail"
            params = {
                'place_id': place_id,
                'api_key': self.api_key
            }
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            result = data.get('result', {})
            if result:
                return {
                    'place_id': place_id,
                    'name': result.get('name'),
                    'address': result.get('formatted_address'),
                    'phone': result.get('formatted_phone_number'),
                    'website': result.get('website'),
                    'rating': result.get('rating'),
                    'user_ratings_total': result.get('user_ratings_total'),
                    'geometry': result.get('geometry', {}),
                    'types': result.get('types', []),
                    'opening_hours': result.get('opening_hours', {}),
                    'photos': self._extract_photos(result.get('photos', [])),
                    'business_status': result.get('business_status')
                }
            
            return None
            
        except Exception as e:
            print(f"❌ Error getting place details: {e}")
            return None
    
    def autocomplete(self, input_text: str, location: tuple = None, 
                    radius: int = 5000, more_compound: bool = True) -> List[Dict]:
        """
        Get place suggestions for autocomplete
        
        Args:
            input_text: User input text
            location: Tuple of (lat, lng) to bias results
            radius: Bias radius in meters
            more_compound: Return more detailed compound info
        """
        if not self.enabled:
            return []
        
        try:
            url = f"{self.base_url}/Place/AutoComplete"
            params = {
                'input': input_text,
                'api_key': self.api_key,
                'more_compound': more_compound,
                'limit': 10  # Limit suggestions
            }
            
            if location:
                params['location'] = f"{location[0]},{location[1]}"
                params['radius'] = radius
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            suggestions = []
            for prediction in data.get('predictions', []):
                suggestions.append({
                    'place_id': prediction.get('place_id'),
                    'description': prediction.get('description'),
                    'main_text': prediction.get('structured_formatting', {}).get('main_text'),
                    'secondary_text': prediction.get('structured_formatting', {}).get('secondary_text'),
                    'compound': prediction.get('compound', {}),
                    'types': prediction.get('types', [])
                })
            
            print(f"✅ Found {len(suggestions)} autocomplete suggestions")
            return suggestions
            
        except Exception as e:
            print(f"❌ Error in autocomplete: {e}")
            return []
    
    def geocode(self, address: str) -> Optional[Dict]:
        """
        Convert address to coordinates using Goong Geocoding
        
        Args:
            address: Address string to geocode
        """
        if not self.enabled:
            return None
        
        try:
            url = f"{self.base_url}/Geocode"
            params = {
                'address': address,
                'api_key': self.api_key
            }
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            results = data.get('results', [])
            if results:
                result = results[0]
                location = result['geometry']['location']
                
                return {
                    'latitude': location['lat'],
                    'longitude': location['lng'],
                    'formatted_address': result['formatted_address'],
                    'place_id': result.get('place_id'),
                    'address_components': result.get('address_components', []),
                    'compound': result.get('compound', {})
                }
            
            return None
            
        except Exception as e:
            print(f"❌ Error geocoding address: {e}")
            return None
    
    def reverse_geocode(self, latitude: float, longitude: float) -> Optional[Dict]:
        """
        Convert coordinates to address using Goong Reverse Geocoding
        
        Args:
            latitude: Latitude coordinate
            longitude: Longitude coordinate
        """
        if not self.enabled:
            return None
        
        try:
            url = f"{self.base_url}/Geocode"
            params = {
                'latlng': f"{latitude},{longitude}",
                'api_key': self.api_key
            }
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            results = data.get('results', [])
            if results:
                result = results[0]
                
                return {
                    'formatted_address': result['formatted_address'],
                    'place_id': result.get('place_id'),
                    'address_components': result.get('address_components', []),
                    'compound': result.get('compound', {}),
                    'latitude': latitude,
                    'longitude': longitude
                }
            
            return None
            
        except Exception as e:
            print(f"❌ Error reverse geocoding: {e}")
            return None
    
    def nearby_search(self, latitude: float, longitude: float, 
                     radius: int = 1500, type_filter: str = None) -> List[Dict]:
        """
        Find nearby places by coordinates using Goong Places Nearby
        
        Args:
            latitude: Latitude coordinate
            longitude: Longitude coordinate
            radius: Search radius in meters
            type_filter: Type of place to filter by
        """
        if not self.enabled:
            return []
        
        try:
            url = f"{self.base_url}/Place/Nearby"
            params = {
                'location': f"{latitude},{longitude}",
                'radius': radius,
                'api_key': self.api_key
            }
            
            if type_filter:
                params['type'] = type_filter
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            places = []
            for place in data.get('results', []):
                places.append(self._format_nearby_place_data(place))
            
            print(f"✅ Found {len(places)} nearby places")
            return places
            
        except Exception as e:
            print(f"❌ Error finding nearby places: {e}")
            return []
    
    def get_directions(self, origin: str, destination: str, 
                      vehicle: str = 'car') -> Optional[Dict]:
        """
        Get directions between two points
        
        Args:
            origin: Origin address or lat,lng
            destination: Destination address or lat,lng  
            vehicle: Transport mode (car, bike, taxi, truck)
        """
        if not self.enabled:
            return None
        
        try:
            url = f"{self.base_url}/Direction"
            params = {
                'origin': origin,
                'destination': destination,
                'vehicle': vehicle,
                'api_key': self.api_key
            }
            
            response = requests.get(url, params=params, timeout=15)
            response.raise_for_status()
            data = response.json()
            
            if data.get('routes'):
                route = data['routes'][0]
                leg = route['legs'][0]
                
                return {
                    'distance': leg['distance'],
                    'duration': leg['duration'],
                    'start_address': leg['start_address'],
                    'end_address': leg['end_address'],
                    'overview_polyline': route['overview_polyline'],
                    'steps': leg['steps']
                }
            
            return None
            
        except Exception as e:
            print(f"❌ Error getting directions: {e}")
            return None
    
    def _format_place_data(self, place: Dict) -> Dict:
        """Format place data from autocomplete/search to standard structure"""
        geometry = place.get('geometry', {})
        location = geometry.get('location', {})
        
        return {
            'place_id': place.get('place_id'),
            'name': place.get('structured_formatting', {}).get('main_text', place.get('description')),
            'address': place.get('description'),
            'latitude': location.get('lat'),
            'longitude': location.get('lng'),
            'compound': place.get('compound', {}),
            'types': place.get('types', []),
            'geometry': geometry
        }
    
    def _format_nearby_place_data(self, place: Dict) -> Dict:
        """Format place data from nearby search"""
        geometry = place.get('geometry', {})
        location = geometry.get('location', {})
        
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
            'geometry': geometry
        }
    
    def _extract_photos(self, photos: List[Dict]) -> List[str]:
        """Extract photo URLs from place photos"""
        if not self.api_key or not photos:
            return []
        
        photo_urls = []
        for photo in photos[:3]:  # Limit to 3 photos
            photo_reference = photo.get('photo_reference')
            if photo_reference:
                photo_url = f"{self.base_url}/Place/Photo?maxwidth=400&photoreference={photo_reference}&api_key={self.api_key}"
                photo_urls.append(photo_url)
        
        return photo_urls

