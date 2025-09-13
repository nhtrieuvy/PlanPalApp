from rest_framework.pagination import PageNumberPagination, CursorPagination
from rest_framework.response import Response
from collections import OrderedDict
from typing import Dict, Any, Optional
import urllib.parse as urlparse
from django.core.paginator import InvalidPage
from rest_framework.exceptions import NotFound

class StandardResultsPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = 'page_size'
    max_page_size = 100
    page_query_param = 'page'
    
    def get_paginated_response(self, data):
        return Response(OrderedDict([
            ('count', self.page.paginator.count),
            ('total_pages', self.page.paginator.num_pages),
            ('current_page', self.page.number),
            ('page_size', self.get_page_size(self.request)),
            ('next', self.get_next_link()),
            ('previous', self.get_previous_link()),
            ('results', data)
        ]))
    
    def get_paginated_response_schema(self, schema):
        return {
            'type': 'object',
            'properties': {
                'count': {
                    'type': 'integer',
                    'example': 123,
                },
                'total_pages': {
                    'type': 'integer',
                    'example': 7,
                },
                'current_page': {
                    'type': 'integer',
                    'example': 2,
                },
                'page_size': {
                    'type': 'integer',
                    'example': 20,
                },
                'next': {
                    'type': 'string',
                    'nullable': True,
                    'format': 'uri',
                    'example': 'http://api.example.org/accounts/?page=3'
                },
                'previous': {
                    'type': 'string',
                    'nullable': True,
                    'format': 'uri',
                    'example': 'http://api.example.org/accounts/?page=1'
                },
                'results': schema,
            },
        }


# ============================================================================
# CURSOR PAGINATION FOR REAL-TIME DATA
# ============================================================================

class ChatMessageCursorPagination(CursorPagination):
    """
    Cursor-based pagination optimized for chat messages
    Good for: real-time data where items are frequently added/removed
    """
    page_size = 50
    page_size_query_param = 'limit'
    max_page_size = 100
    ordering = '-created_at'  # Newest first
    cursor_query_param = 'cursor'
    cursor_query_description = 'The pagination cursor value.'
    
    def get_paginated_response(self, data):
        return Response(OrderedDict([
            ('next', self.get_next_link()),
            ('previous', self.get_previous_link()),
            ('has_more', self.has_next),
            ('has_previous', self.has_previous),
            ('results', data)
        ]))


class ActivityCursorPagination(CursorPagination):
    """
    Cursor-based pagination for user activities and plan activities
    Ordered by start_time for chronological browsing
    """
    page_size = 25
    page_size_query_param = 'limit'
    max_page_size = 50
    ordering = '-start_time'  # Most recent activities first
    cursor_query_param = 'cursor'
    
    def get_paginated_response(self, data):
        return Response(OrderedDict([
            ('next', self.get_next_link()),
            ('previous', self.get_previous_link()),
            ('has_more', self.has_next),
            ('has_previous', self.has_previous),
            ('count', len(data)),
            ('results', data)
        ]))


# ============================================================================
# CUSTOM CURSOR PAGINATION FOR SEARCH RESULTS
# ============================================================================

class SearchResultsPagination(PageNumberPagination):
    """
    Pagination for search results with relevance scoring
    Smaller page size for better UX in search interfaces
    """
    page_size = 15
    page_size_query_param = 'limit'
    max_page_size = 50
    page_query_param = 'page'
    
    def get_paginated_response(self, data):
        return Response(OrderedDict([
            ('count', self.page.paginator.count),
            ('total_pages', self.page.paginator.num_pages),
            ('current_page', self.page.number),
            ('page_size', self.get_page_size(self.request)),
            ('next', self.get_next_link()),
            ('previous', self.get_previous_link()),
            ('results', data),
            ('search_query', getattr(self, 'search_query', '')),
        ]))
    
    def set_search_query(self, query: str):
        """Set search query for response metadata"""
        self.search_query = query


# ============================================================================
# LIGHTWEIGHT PAGINATION FOR MOBILE
# ============================================================================

class MobilePagination(PageNumberPagination):
    """
    Optimized pagination for mobile apps with smaller page sizes
    Reduces payload size and improves performance on slower connections
    """
    page_size = 10
    page_size_query_param = 'limit'
    max_page_size = 25
    page_query_param = 'page'
    
    def get_paginated_response(self, data):
        # Simplified response for mobile
        return Response(OrderedDict([
            ('count', self.page.paginator.count),
            ('has_next', self.page.has_next()),
            ('has_previous', self.page.has_previous()),
            ('page', self.page.number),
            ('results', data)
        ]))


# ============================================================================
# MANUAL CURSOR PAGINATION HELPER
# ============================================================================

class ManualCursorPaginator:
    """
    Manual cursor pagination for complex queries that can't use DRF's CursorPagination
    Used in services for custom pagination logic like ChatService.get_group_messages
    """
    
    @staticmethod
    def paginate_by_id(queryset, before_id: Optional[str] = None, 
                      limit: int = 50, ordering: str = '-id') -> Dict[str, Any]:
        """
        Manual cursor pagination based on ID field
        
        Args:
            queryset: Django QuerySet to paginate
            before_id: ID to paginate before (for newer -> older)
            limit: Number of items per page
            ordering: Ordering field (default: '-id' for newest first)
            
        Returns:
            Dict with 'items', 'has_more', 'next_cursor'
        """
        # Apply cursor filter
        if before_id:
            if ordering.startswith('-'):
                # Descending order: get items with ID less than before_id
                field_name = ordering[1:]  # Remove the '-'
                filter_kwargs = {f'{field_name}__lt': before_id}
            else:
                # Ascending order: get items with ID greater than before_id
                filter_kwargs = {f'{ordering}__gt': before_id}
            
            queryset = queryset.filter(**filter_kwargs)
        
        # Get one extra item to check if there are more
        items = list(queryset.order_by(ordering)[:limit + 1])
        
        # Check if there are more items
        has_more = len(items) > limit
        
        # Remove the extra item if it exists
        if has_more:
            items = items[:limit]
        
        # Generate next cursor (ID of last item)
        next_cursor = None
        if items and has_more:
            if ordering.startswith('-'):
                next_cursor = str(getattr(items[-1], ordering[1:]))
            else:
                next_cursor = str(getattr(items[-1], ordering))
        
        return {
            'items': items,
            'has_more': has_more,
            'next_cursor': next_cursor,
            'count': len(items)
        }
    
    @staticmethod
    def paginate_by_datetime(queryset, before_datetime: Optional[str] = None,
                           limit: int = 50, ordering: str = '-created_at') -> Dict[str, Any]:
        """
        Manual cursor pagination based on datetime field
        Useful for time-ordered data like messages, activities
        """
        # Apply cursor filter
        if before_datetime:
            if ordering.startswith('-'):
                # Descending order: get items before the datetime
                field_name = ordering[1:]
                filter_kwargs = {f'{field_name}__lt': before_datetime}
            else:
                # Ascending order: get items after the datetime
                filter_kwargs = {f'{ordering}__gt': before_datetime}
            
            queryset = queryset.filter(**filter_kwargs)
        
        # Get one extra item to check if there are more
        items = list(queryset.order_by(ordering)[:limit + 1])
        
        # Check if there are more items
        has_more = len(items) > limit
        
        # Remove the extra item if it exists
        if has_more:
            items = items[:limit]
        
        # Generate next cursor (datetime of last item)
        next_cursor = None
        if items and has_more:
            field_name = ordering[1:] if ordering.startswith('-') else ordering
            last_datetime = getattr(items[-1], field_name)
            next_cursor = last_datetime.isoformat() if last_datetime else None
        
        return {
            'items': items,
            'has_more': has_more,
            'next_cursor': next_cursor,
            'count': len(items)
        }


# ============================================================================
# PAGINATOR FACTORY
# ============================================================================

def get_paginator_class(pagination_type: str = 'standard'):
    """
    Factory function to get appropriate paginator class
    
    Args:
        pagination_type: Type of pagination needed
            - 'standard': StandardResultsPagination (default)
            - 'cursor': ChatMessageCursorPagination
            - 'activity': ActivityCursorPagination  
            - 'search': SearchResultsPagination
            - 'mobile': MobilePagination
    """
    paginators = {
        'standard': StandardResultsPagination,
        'cursor': ChatMessageCursorPagination,
        'activity': ActivityCursorPagination,
        'search': SearchResultsPagination,
        'mobile': MobilePagination,
    }
    
    return paginators.get(pagination_type, StandardResultsPagination)
