import googlemaps
from typing import Dict, List, Optional, Any
from django.conf import settings
from decimal import Decimal
from .base_service import BaseService

class GooglePlacesService(BaseService):
    """Service để tích hợp với Google Places API"""
    
    def __init__(self):
        super().__init__()
        self.client = None
        if self.validate_config():
            self.client = googlemaps.Client(key=settings.GOOGLE_PLACES_API_KEY)
    
    def validate_config(self) -> bool:
        """Kiểm tra API key"""
        api_key = getattr(settings, 'GOOGLE_PLACES_API_KEY', None)
        if not api_key:
            self.log_error("Google Places API key không được cấu hình")
            return False
        return True
    
    def search_places(self, query: str, location: Optional[tuple] = None, 
                     radius: int = 5000, place_type: str = None) -> List[Dict[str, Any]]:
        """
        Tìm kiếm địa điểm theo từ khóa
        
        Args:
            query: Từ khóa tìm kiếm
            location: Tọa độ (lat, lng) để tìm kiếm xung quanh
            radius: Bán kính tìm kiếm (mét)
            place_type: Loại địa điểm (restaurant, tourist_attraction, etc.)
        """
        if not self.client:
            self.log_error("Google Places client chưa được khởi tạo")
            return []
        
        try:
            if location:
                # Text search với vị trí, Dựa theo document của google
                result = self.client.places_nearby(
                    location=location,
                    radius=radius,
                    keyword=query,
                    type=place_type
                )
            else:
                # Text search không có vị trí cụ thể
                result = self.client.places(query=query)
            
            places = []
            for place in result.get('results', []):
                places.append(self._format_place_data(place))
            
            self.log_info(f"Tìm được {len(places)} địa điểm cho '{query}'")
            return places
            
        except Exception as e:
            self.log_error("Lỗi khi tìm kiếm địa điểm", e)
            return []
    
    def get_place_details(self, place_id: str, 
                         fields: Optional[List[str]] = None) -> Optional[Dict[str, Any]]:
        """
        Lấy thông tin chi tiết của một địa điểm
        
        Args:
            place_id: ID của địa điểm từ Google Places
            fields: Các trường thông tin cần lấy
        """
        if not self.client:
            self.log_error("Google Places client chưa được khởi tạo")
            return None
        
        if not fields:
            fields = [
                'place_id', 'name', 'formatted_address', 'rating', 
                'reviews', 'photos', 'opening_hours', 'formatted_phone_number',
                'website', 'price_level', 'geometry', 'types'
            ]
        
        try:
            result = self.client.place(
                place_id=place_id,
                fields=fields
            )
            
            if result.get('result'):
                return self._format_place_details(result['result'])
            
            return None
            
        except Exception as e:
            self.log_error(f"Lỗi khi lấy chi tiết địa điểm {place_id}", e)
            return None
    
    def get_nearby_places(self, lat: float, lng: float, radius: int = 1000,
                         place_type: str = None) -> List[Dict[str, Any]]:
        """
        Lấy danh sách địa điểm xung quanh một tọa độ
        
        Args:
            lat: Vĩ độ
            lng: Kinh độ  
            radius: Bán kính (mét)
            place_type: Loại địa điểm
        """
        if not self.client:
            self.log_error("Google Places client chưa được khởi tạo")
            return []
        
        try:
            result = self.client.places_nearby(
                location=(lat, lng),
                radius=radius,
                type=place_type
            )
            
            places = []
            for place in result.get('results', []):
                places.append(self._format_place_data(place))
            
            self.log_info(f"Tìm được {len(places)} địa điểm xung quanh ({lat}, {lng})")
            return places
            
        except Exception as e:
            self.log_error("Lỗi khi lấy địa điểm xung quanh", e)
            return []
    
    def get_place_photos(self, photo_references: List[str], 
                        max_width: int = 400) -> List[str]:
        """
        Lấy URL của ảnh địa điểm
        
        Args:
            photo_references: Danh sách photo reference từ Google Places
            max_width: Chiều rộng tối đa của ảnh
        """
        if not self.client:
            return []
        
        photo_urls = []
        for photo_ref in photo_references:
            try:
                photo_url = f"https://maps.googleapis.com/maps/api/place/photo?maxwidth={max_width}&photoreference={photo_ref}&key={settings.GOOGLE_PLACES_API_KEY}"
                photo_urls.append(photo_url)
            except Exception as e:
                self.log_error(f"Lỗi khi tạo URL ảnh {photo_ref}", e)
        
        return photo_urls
    
    def _format_place_data(self, place: Dict[str, Any]) -> Dict[str, Any]:
        """Format dữ liệu địa điểm từ Google Places API"""
        geometry = place.get('geometry', {})
        location = geometry.get('location', {})
        
        # Lấy photo URLs nếu có
        photo_urls = []
        if place.get('photos'):
            photo_refs = [photo.get('photo_reference') for photo in place['photos'][:3]]
            photo_urls = self.get_place_photos(photo_refs)
        
        return {
            'place_id': place.get('place_id'),
            'name': place.get('name'),
            'address': place.get('vicinity') or place.get('formatted_address'),
            'latitude': location.get('lat'),
            'longitude': location.get('lng'),
            'rating': place.get('rating'),
            'user_ratings_total': place.get('user_ratings_total'),
            'price_level': place.get('price_level'),
            'types': place.get('types', []),
            'photos': photo_urls,
            'opening_hours': place.get('opening_hours'),
            'permanently_closed': place.get('permanently_closed', False)
        }
    
    def _format_place_details(self, place: Dict[str, Any]) -> Dict[str, Any]:
        """Format dữ liệu chi tiết địa điểm"""
        geometry = place.get('geometry', {})
        location = geometry.get('location', {})
        
        # Format reviews
        reviews = []
        for review in place.get('reviews', [])[:5]:  # Lấy tối đa 5 review
            reviews.append({
                'author_name': review.get('author_name'),
                'rating': review.get('rating'),
                'text': review.get('text'),
                'time': review.get('time'),
                'relative_time_description': review.get('relative_time_description')
            })
        
        # Format photos
        photo_urls = []
        if place.get('photos'):
            photo_refs = [photo.get('photo_reference') for photo in place['photos']]
            photo_urls = self.get_place_photos(photo_refs)
        
        return {
            'place_id': place.get('place_id'),
            'name': place.get('name'),
            'formatted_address': place.get('formatted_address'),
            'latitude': location.get('lat'),
            'longitude': location.get('lng'),
            'rating': place.get('rating'),
            'user_ratings_total': place.get('user_ratings_total'),
            'price_level': place.get('price_level'),
            'types': place.get('types', []),
            'photos': photo_urls,
            'opening_hours': place.get('opening_hours'),
            'formatted_phone_number': place.get('formatted_phone_number'),
            'website': place.get('website'),
            'reviews': reviews
        }
