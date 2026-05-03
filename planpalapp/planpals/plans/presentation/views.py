from django.contrib.auth import get_user_model
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from django.utils.dateparse import parse_date
from django.db import models, transaction
from django.core.exceptions import ValidationError
from datetime import datetime
import logging
from rest_framework.exceptions import ValidationError as DRFValidationError

from rest_framework import viewsets, status, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from planpals.plans.infrastructure.models import Plan, PlanActivity
from planpals.plans.presentation.serializers import (
    PlanDetailSerializer, PlanCreateSerializer, PlanSummarySerializer,
    PlanActivitySerializer, PlanActivitySummarySerializer,
    PlanActivityCreateSerializer, PlanActivityUpdateSerializer,
)
from planpals.plans.presentation.permissions import (
    PlanPermission, PlanActivityPermission,
    CanJoinPlan, CanAccessPlan, CanModifyPlan
)
from planpals.plans.application.services import PlanService
from planpals.auth.presentation.serializers import UserSerializer
from planpals.shared.paginators import StandardResultsPagination, ActivityCursorPagination
from planpals.shared.domain_exceptions import ActivityNotFoundException

User = get_user_model()
logger = logging.getLogger(__name__)


class PlanViewSet(viewsets.ModelViewSet):
    serializer_class = PlanDetailSerializer
    permission_classes = [IsAuthenticated, PlanPermission]

    pagination_class = StandardResultsPagination
    
    def get_serializer_class(self):
        if self.action == 'create':
            return PlanCreateSerializer
        elif self.action in ('list', 'my_plans', 'joined', 'public'):
            return PlanSummarySerializer
        return self.serializer_class
    
    def get_queryset(self):
        user = self.request.user
        base_qs = Plan.objects.filter(
            models.Q(group__members=user) |
            models.Q(creator=user)
        ).select_related(
            'creator', 'group'
        ).with_stats().distinct().order_by('-created_at')

        # Only prefetch activities + group members for detail views.
        # List endpoints use PlanSummarySerializer which never touches activities.
        if self.action in ('retrieve', 'activities_by_date', 'schedule',
                           'summary', 'collaborators', 'update',
                           'partial_update', 'cancel'):
            base_qs = base_qs.prefetch_related(
                'group__members',
                'activities',
            )

        return base_qs
    
    def perform_create(self, serializer):
        data = serializer.validated_data
        
        group = data.get('group')
        
        plan = PlanService.create_plan(
            creator=self.request.user,
            title=data['title'],
            description=data.get('description', ''),
            plan_type=data.get('plan_type', 'personal'),
            group=group,
            start_date=data.get('start_date'),
            end_date=data.get('end_date'),
            is_public=data.get('is_public', False)
        )
        
        serializer.instance = plan

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        instance = serializer.instance
        headers = self.get_success_headers({'id': str(instance.id)})
        response_serializer = PlanDetailSerializer(
            instance,
            context={'request': request},
        )
        return Response(
            response_serializer.data,
            status=status.HTTP_201_CREATED,
            headers=headers,
        )

    def perform_update(self, serializer):
        instance = self.get_object()

        data = serializer.validated_data

        try:
            updated = PlanService.update_plan(instance, data, user=self.request.user)
        except ValidationError as e:
            raise DRFValidationError(str(e))

        serializer.instance = updated

    def perform_destroy(self, instance):
        PlanService.delete_plan(instance, user=self.request.user)
    
    
    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated])
    def my_plans(self, request):
        queryset = self.get_queryset()
        plan_type = request.query_params.get('type', 'all')
        
        if plan_type == 'personal':
            queryset = queryset.filter(group__isnull=True)
        elif plan_type == 'group':
            queryset = queryset.filter(group__isnull=False)
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
    
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, CanAccessPlan])
    def activities_by_date(self, request, pk=None):
        plan = self.get_object()

        date_value = request.query_params.get('date')
        if not date_value:
            return Response(
                {'error': 'date query parameter is required (YYYY-MM-DD)'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        target_date = parse_date(date_value)
        if target_date is None:
            return Response(
                {'error': 'Invalid date format. Use YYYY-MM-DD.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        activities = plan.get_activities_by_date(target_date)
        serializer = PlanActivitySerializer(
            activities, many=True, context={'request': request}
        )

        return Response({
            'date': target_date.isoformat(),
            'plan_id': str(plan.id),
            'activities': serializer.data,
            'count': len(serializer.data),
        })
        
    
    #API lấy người tham gia kế hoạch
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, CanAccessPlan])
    def collaborators(self, request, pk=None):
        """Get plan collaborators - OPTIMIZED using property"""
        plan = self.get_object()
        collaborators = plan.collaborators
        
        serializer = UserSerializer(collaborators, many=True, context={'request': request})
        
        return Response({
            'collaborators': serializer.data,
            'count': len(collaborators),
            'plan_type': plan.plan_type
        })
        
    
    #API lấy tóm tắt kế hoạch
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, CanAccessPlan])
    def summary(self, request, pk=None):
        """Get plan summary - delegate to service"""
        plan = self.get_object()
        
        summary = PlanService.get_plan_statistics(plan)
        return Response(summary)
    
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, CanAccessPlan])
    def schedule(self, request, pk=None):
        plan = self.get_object()
        
        schedule_data = PlanService.get_plan_schedule(plan, request.user)
        return Response(schedule_data)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, CanModifyPlan])
    def cancel(self, request, pk=None):
        """Cancel an upcoming plan without deleting historical data."""
        plan = self.get_object()
        reason = request.data.get('reason') if hasattr(request.data, 'get') else None

        try:
            cancelled_plan = PlanService.cancel_trip(
                plan,
                user=request.user,
                reason=reason,
            )
        except ValueError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        serializer = PlanDetailSerializer(
            cancelled_plan,
            context={'request': request},
        )
        return Response(serializer.data, status=status.HTTP_200_OK)
    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, CanModifyPlan])
    def create_activity(self, request, pk=None):
        plan = self.get_object()
        
        try:
            activity = PlanService.add_activity_to_plan(plan, request.user, request.data)
            return Response(
                PlanActivitySerializer(activity, context={'request': request}).data,
                status=status.HTTP_201_CREATED
            )
        except ValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    
    
    @action(detail=True, methods=['put', 'patch'], url_path='activities/(?P<activity_id>[^/.]+)', 
            permission_classes=[IsAuthenticated, CanModifyPlan])
    def update_activity(self, request, pk=None, activity_id=None):
        plan = self.get_object()

        try:
            activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist as exc:
            raise ActivityNotFoundException() from exc

        serializer = PlanActivityUpdateSerializer(
            data=request.data,
            context={'request': request, 'activity': activity},
            partial=request.method.lower() == 'patch',
        )
        serializer.is_valid(raise_exception=True)

        updated_activity = PlanService.update_activity(
            plan,
            activity_id,
            request.user,
            serializer.validated_data,
        )
        return Response({
            'message': 'Activity updated successfully',
            'activity': PlanActivitySerializer(
                updated_activity,
                context={'request': request},
            ).data,
            'meta': {
                'version': updated_activity.version,
                'updated_at': updated_activity.updated_at.isoformat(),
            },
        })
    
    @action(detail=True, methods=['delete'], url_path='activities/(?P<activity_id>[^/.]+)',
            permission_classes=[IsAuthenticated, CanModifyPlan])
    def remove_activity(self, request, pk=None, activity_id=None):
        plan = self.get_object()
        PlanService.remove_activity(plan, activity_id, request.user)
        return Response({'message': 'Activity removed from plan'})
    
    @action(detail=True, methods=['post'], url_path='activities/(?P<activity_id>[^/.]+)/complete',
            permission_classes=[IsAuthenticated, CanModifyPlan])
    def toggle_activity_completion(self, request, pk=None, activity_id=None):
        plan = self.get_object()
        
        success, message, activity = PlanService.toggle_activity_completion(plan, activity_id, request.user)
        
        if not success:
            status_code = status.HTTP_403_FORBIDDEN if "permission" in message else status.HTTP_404_NOT_FOUND
            return Response({'error': message}, status=status_code)
        
        return Response({
            'message': message,
            'activity': PlanActivitySerializer(activity).data
        })

    @action(detail=False, methods=['get'])
    def joined(self, request):
        search = request.query_params.get('search', None)
        group_plans = PlanService.get_joined_plans(request.user, search)
        
        serializer = PlanSummarySerializer(group_plans, many=True, context={'request': request})
        return Response({
            'results': serializer.data,
            'count': group_plans.count()
        })
    
    @action(detail=False, methods=['get'])
    def public(self, request):
        search = request.query_params.get('search', None)
        public_plans = PlanService.get_public_plans(request.user, search)
        
        serializer = PlanSummarySerializer(public_plans, many=True, context={'request': request})
        return Response({
            'results': serializer.data,
            'count': public_plans.count()
        })


    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, CanJoinPlan])
    def join(self, request, pk=None):
        plan = self.get_object()
        user = request.user
        
        success, message = PlanService.join_plan(plan, user)
        
        if not success:
            return Response(
                {'error': message}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        return Response(PlanDetailSerializer(plan, context={'request': request}).data)


class PlanActivityViewSet(viewsets.GenericViewSet,
                          mixins.CreateModelMixin,
                          mixins.RetrieveModelMixin,
                          mixins.UpdateModelMixin,
                          mixins.DestroyModelMixin):
    serializer_class = PlanActivitySerializer
    permission_classes = [IsAuthenticated, PlanActivityPermission]
    pagination_class = ActivityCursorPagination
    
    def get_serializer_class(self):
        if self.action == 'create':
            return PlanActivityCreateSerializer
        if self.action in {'update', 'partial_update'}:
            return PlanActivityUpdateSerializer
        return PlanActivitySerializer
    
    def get_queryset(self):
        return PlanActivity.objects.filter(
            models.Q(plan__group__members=self.request.user) |
            models.Q(plan__creator=self.request.user)
        ).select_related('plan', 'plan__group', 'plan__creator').distinct()
    
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        plan = serializer.validated_data['plan']
        activity = PlanService.add_activity_to_plan(
            plan,
            request.user,
            serializer.validated_data,
        )
        response_serializer = PlanActivitySerializer(
            activity,
            context={'request': request},
        )
        return Response(response_serializer.data, status=status.HTTP_201_CREATED)
    
    def retrieve(self, request, *args, **kwargs):
        """
        Get full activity details - returns complete PlanActivitySerializer data
        This is called when user opens activity detail dialog
        """
        return super().retrieve(request, *args, **kwargs)

    def update(self, request, *args, **kwargs):
        activity = self.get_object()
        serializer = self.get_serializer(
            data=request.data,
            context={'request': request, 'activity': activity},
        )
        serializer.is_valid(raise_exception=True)
        updated_activity = PlanService.update_activity(
            activity.plan,
            str(activity.id),
            request.user,
            serializer.validated_data,
        )
        response_serializer = PlanActivitySerializer(
            updated_activity,
            context={'request': request},
        )
        return Response({
            'message': 'Activity updated successfully',
            'activity': response_serializer.data,
            'meta': {
                'version': updated_activity.version,
                'updated_at': updated_activity.updated_at.isoformat(),
            },
        })

    def partial_update(self, request, *args, **kwargs):
        activity = self.get_object()
        serializer = self.get_serializer(
            data=request.data,
            context={'request': request, 'activity': activity},
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        updated_activity = PlanService.update_activity(
            activity.plan,
            str(activity.id),
            request.user,
            serializer.validated_data,
        )
        response_serializer = PlanActivitySerializer(
            updated_activity,
            context={'request': request},
        )
        return Response({
            'message': 'Activity updated successfully',
            'activity': response_serializer.data,
            'meta': {
                'version': updated_activity.version,
                'updated_at': updated_activity.updated_at.isoformat(),
            },
        })

    def destroy(self, request, *args, **kwargs):
        activity = self.get_object()
        PlanService.remove_activity(activity.plan, str(activity.id), request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)
    
    
    #API lấy hoạt động theo kế hoạch - OPTIMIZED
    @action(detail=False, methods=['get'])
    def by_plan(self, request):
        plan_id = request.query_params.get('plan_id')
        
        if not plan_id:
            return Response(
                {'error': 'plan_id parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            plan = Plan.objects.filter(
                models.Q(id=plan_id) & (
                    models.Q(group__members=request.user) | 
                    models.Q(creator=request.user)
                )
            ).first()
            
            if not plan:
                raise Plan.DoesNotExist()
            
            # Get activities with optimized query
            activities = self.get_queryset().filter(
                plan=plan
            ).order_by('start_time')
            
            serializer = self.get_serializer(activities, many=True)
            return Response({
                'activities': serializer.data,
                'plan_id': plan_id,
                'plan_title': plan.title,
                'count': len(activities)
            })
            
        except Plan.DoesNotExist:
            return Response(
                {'error': 'Plan not found or access denied'}, 
                status=status.HTTP_404_NOT_FOUND
            )
    
    #API lấy hoạt động theo khoảng thời gian - NEW
    @action(detail=False, methods=['get'])
    def by_date_range(self, request):
        start_date = request.query_params.get('start_date')
        end_date = request.query_params.get('end_date')
        
        if not start_date or not end_date:
            return Response(
                {'error': 'start_date and end_date parameters required (YYYY-MM-DD)'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            start_date = datetime.strptime(start_date, '%Y-%m-%d').date()
            end_date = datetime.strptime(end_date, '%Y-%m-%d').date()
            
            activities = self.get_queryset().filter(
                start_time__date__range=[start_date, end_date]
            ).select_related('plan').order_by('start_time')
            
            serializer = self.get_serializer(activities, many=True)
            return Response({
                'activities': serializer.data,
                'date_range': {
                    'start': start_date.isoformat(),
                    'end': end_date.isoformat()
                },
                'count': len(activities)
            })
            
        except ValueError:
            return Response(
                {'error': 'Invalid date format. Use YYYY-MM-DD'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
    
    #API lấy hoạt động sắp tới - NEW
    @action(detail=False, methods=['get'])
    def upcoming(self, request):
        limit = min(int(request.query_params.get('limit', 20)), 50)  # Max 50
        
        now = timezone.now()
        activities = self.get_queryset().filter(
            start_time__gt=now
        ).select_related('plan').order_by('start_time')[:limit]
        
        serializer = self.get_serializer(activities, many=True)
        return Response({
            'activities': serializer.data,
            'count': len(activities),
            'timestamp': now.isoformat()
        })
    
    #API tìm kiếm hoạt động - NEW
    @action(detail=False, methods=['get'])
    def search(self, request):
        query = request.query_params.get('q')
        plan_id = request.query_params.get('plan_id')
        
        if not query:
            return Response(
                {'error': 'Search query (q) parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Base queryset - only user's activities
        queryset = self.get_queryset().filter(
            models.Q(title__icontains=query) |
            models.Q(description__icontains=query) |
            models.Q(location_name__icontains=query)
        ).select_related('plan')
        
        # Filter by specific plan if provided
        if plan_id:
            try:
                Plan.objects.filter(
                    models.Q(id=plan_id) & (
                        models.Q(group__members=request.user) | 
                        models.Q(creator=request.user)
                    )
                ).get()  # Validate access
                queryset = queryset.filter(plan_id=plan_id)
            except Plan.DoesNotExist:
                return Response(
                    {'error': 'Plan not found or access denied'}, 
                    status=status.HTTP_404_NOT_FOUND
                )
        
        # Apply pagination to activities
        page = self.paginate_queryset(queryset.order_by('-created_at'))
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset.order_by('-created_at'), many=True)
        
        return Response({
            'activities': serializer.data,
            'count': queryset.count(),
            'query': query
        })


class EnhancedPlanViewSet(PlanViewSet):    
    @action(detail=True, methods=['post'])
    def add_activity_with_place(self, request, pk=None):
        plan = self.get_object()
        
        title = request.data.get('title')
        start_time = request.data.get('start_time')
        end_time = request.data.get('end_time')
        place_id = request.data.get('place_id')
        
        if not all([title, start_time, end_time]):
            return Response(
                {'error': 'title, start_time, and end_time are required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            # Parse datetime with timezone awareness
            # DRF's ISO 8601 parser handles timezone correctly
            start_time_str = start_time.replace('Z', '+00:00') if isinstance(start_time, str) else start_time
            end_time_str = end_time.replace('Z', '+00:00') if isinstance(end_time, str) else end_time
            
            start_time = parse_datetime(start_time_str)
            end_time = parse_datetime(end_time_str)
            
            if not start_time or not end_time:
                raise ValueError("Invalid datetime format")
            
            # Ensure timezone-aware datetimes
            if timezone.is_naive(start_time):
                start_time = timezone.make_aware(start_time)
            if timezone.is_naive(end_time):
                end_time = timezone.make_aware(end_time)
            
            # Extract extra fields
            extra_fields = {k: v for k, v in request.data.items() 
                           if k not in ['title', 'start_time', 'end_time', 'place_id']}
            
            # Use service layer for activity creation
            activity = PlanService.add_activity_with_place(
                plan=plan,
                title=title,
                start_time=start_time,
                end_time=end_time,
                place_id=place_id,
                **extra_fields
            )
            return Response(
                PlanActivitySerializer(activity).data, 
                status=status.HTTP_201_CREATED
            )
            
        except ValueError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_400_BAD_REQUEST
            )
