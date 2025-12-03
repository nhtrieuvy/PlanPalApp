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
            ('results', data)
        ]))
    


class ChatMessageCursorPagination(CursorPagination):
    page_size = 20
    page_size_query_param = 'limit'
    max_page_size = 50
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
    page_size = 5
    page_size_query_param = 'limit'
    max_page_size = 20
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



class SearchResultsPagination(PageNumberPagination):
    page_size = 15
    page_size_query_param = 'limit'
    max_page_size = 30
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
        self.search_query = query


# ============================================================================
# LIGHTWEIGHT PAGINATION FOR MOBILE
# ============================================================================

class MobilePagination(PageNumberPagination):
    page_size = 5
    page_size_query_param = 'limit'
    max_page_size = 15
    page_query_param = 'page'
    
    def get_paginated_response(self, data):
        return Response(OrderedDict([
            ('count', self.page.paginator.count),
            ('has_next', self.page.has_next()),
            ('has_previous', self.page.has_previous()),
            ('page', self.page.number),
            ('results', data)
        ]))

class ManualCursorPaginator:
    """
    Manual cursor pagination for complex queries that can't use DRF's CursorPagination
    Used in services for custom pagination logic like ChatService.get_group_messages
    """
    
    @staticmethod
    def paginate_by_id(queryset, before_id: Optional[str] = None, 
                      limit: int = 50, ordering: str = '-id') -> Dict[str, Any]:
      
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

    paginators = {
        'standard': StandardResultsPagination,
        'cursor': ChatMessageCursorPagination,
        'activity': ActivityCursorPagination,
        'search': SearchResultsPagination,
        'mobile': MobilePagination,
    }
    
    return paginators.get(pagination_type, StandardResultsPagination)
