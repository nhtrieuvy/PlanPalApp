from django.http import HttpResponse
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from planpals.collaboration.application.factories import get_collaboration_service
from planpals.collaboration.domain.exceptions import (
    CollaborationConflict,
    CollaborationError,
    CollaborationNotFound,
    CollaborationPermissionDenied,
)
from planpals.collaboration.presentation.serializers import (
    AvailabilityPollCreateSerializer,
    AvailabilityPollSerializer,
    AvailabilityVoteInputSerializer,
    ClonePlanSerializer,
    CommentInputSerializer,
    CommentUpdateSerializer,
    PlanCommentSerializer,
    PlanWorkItemSerializer,
    ReactionInputSerializer,
    WorkItemInputSerializer,
)
from planpals.plans.presentation.serializers import PlanDetailSerializer


class CollaborationAPIView(APIView):
    permission_classes = [IsAuthenticated]

    @property
    def service(self):
        return get_collaboration_service()

    def error_response(self, exc: CollaborationError):
        response_status = status.HTTP_400_BAD_REQUEST
        if isinstance(exc, CollaborationPermissionDenied):
            response_status = status.HTTP_403_FORBIDDEN
        elif isinstance(exc, CollaborationNotFound):
            response_status = status.HTTP_404_NOT_FOUND
        elif isinstance(exc, CollaborationConflict):
            response_status = status.HTTP_409_CONFLICT
        return Response(
            {'code': exc.code, 'message': exc.message, 'details': {}},
            status=response_status,
        )


class GroupAvailabilityPollListCreateView(CollaborationAPIView):
    def get(self, request, group_id):
        try:
            polls = self.service.list_polls(group_id, request.user.id)
            return Response(AvailabilityPollSerializer(
                polls, many=True, context={'user_id': request.user.id}
            ).data)
        except CollaborationError as exc:
            return self.error_response(exc)

    def post(self, request, group_id):
        serializer = AvailabilityPollCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            poll = self.service.create_poll(
                group_id,
                request.user.id,
                title=serializer.validated_data['title'],
                closes_at=serializer.validated_data.get('closes_at'),
                options=serializer.validated_data['options'],
            )
            return Response(AvailabilityPollSerializer(
                poll, context={'user_id': request.user.id}
            ).data, status=status.HTTP_201_CREATED)
        except CollaborationError as exc:
            return self.error_response(exc)


class AvailabilityVoteView(CollaborationAPIView):
    def post(self, request, poll_id):
        serializer = AvailabilityVoteInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            self.service.vote(poll_id, user_id=request.user.id, **serializer.validated_data)
            return Response({'message': 'Availability response saved.'})
        except CollaborationError as exc:
            return self.error_response(exc)


class PlanWorkItemListCreateView(CollaborationAPIView):
    def get(self, request, plan_id):
        try:
            items = self.service.list_work_items(plan_id, request.user.id)
            return Response(PlanWorkItemSerializer(items, many=True).data)
        except CollaborationError as exc:
            return self.error_response(exc)

    def post(self, request, plan_id):
        serializer = WorkItemInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            item = self.service.create_work_item(
                plan_id, request.user.id, serializer.validated_data
            )
            return Response(PlanWorkItemSerializer(item).data, status=status.HTTP_201_CREATED)
        except CollaborationError as exc:
            return self.error_response(exc)


class PlanWorkItemDetailView(CollaborationAPIView):
    def patch(self, request, item_id):
        serializer = WorkItemInputSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        try:
            item = self.service.update_work_item(
                item_id, request.user.id, serializer.validated_data
            )
            return Response(PlanWorkItemSerializer(item).data)
        except CollaborationError as exc:
            return self.error_response(exc)

    def delete(self, request, item_id):
        try:
            self.service.delete_work_item(item_id, request.user.id)
            return Response(status=status.HTTP_204_NO_CONTENT)
        except CollaborationError as exc:
            return self.error_response(exc)


class PlanCommentListCreateView(CollaborationAPIView):
    def get(self, request, plan_id):
        try:
            comments = self.service.list_comments(
                plan_id, request.user.id, request.query_params.get('activity_id')
            )
            return Response(PlanCommentSerializer(
                comments, many=True, context={'user_id': request.user.id}
            ).data)
        except CollaborationError as exc:
            return self.error_response(exc)

    def post(self, request, plan_id):
        serializer = CommentInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            comment = self.service.create_comment(
                plan_id, request.user.id, serializer.validated_data
            )
            return Response(PlanCommentSerializer(
                comment, context={'user_id': request.user.id}
            ).data, status=status.HTTP_201_CREATED)
        except CollaborationError as exc:
            return self.error_response(exc)


class PlanCommentDetailView(CollaborationAPIView):
    def patch(self, request, comment_id):
        serializer = CommentUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            comment = self.service.update_comment(
                comment_id, request.user.id, serializer.validated_data['body']
            )
            return Response(PlanCommentSerializer(
                comment, context={'user_id': request.user.id}
            ).data)
        except CollaborationError as exc:
            return self.error_response(exc)

    def delete(self, request, comment_id):
        try:
            self.service.delete_comment(comment_id, request.user.id)
            return Response(status=status.HTTP_204_NO_CONTENT)
        except CollaborationError as exc:
            return self.error_response(exc)


class CommentReactionView(CollaborationAPIView):
    def post(self, request, comment_id):
        serializer = ReactionInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            self.service.react(
                comment_id, request.user.id, serializer.validated_data.get('reaction')
            )
            return Response({'message': 'Reaction updated.'})
        except CollaborationError as exc:
            return self.error_response(exc)


class CommentPinView(CollaborationAPIView):
    def post(self, request, comment_id):
        try:
            comment = self.service.toggle_pin(comment_id, request.user.id)
            return Response(PlanCommentSerializer(
                comment, context={'user_id': request.user.id}
            ).data)
        except CollaborationError as exc:
            return self.error_response(exc)


class PlanCloneView(CollaborationAPIView):
    def post(self, request, plan_id):
        serializer = ClonePlanSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            plan = self.service.clone_plan(plan_id, request.user.id, serializer.validated_data)
            return Response(PlanDetailSerializer(
                plan, context={'request': request}
            ).data, status=status.HTTP_201_CREATED)
        except CollaborationError as exc:
            return self.error_response(exc)


class PlanICSExportView(CollaborationAPIView):
    def get(self, request, plan_id):
        try:
            content = self.service.export_ics(plan_id, request.user.id)
            response = HttpResponse(content, content_type='text/calendar; charset=utf-8')
            response['Content-Disposition'] = f'attachment; filename="plan-{plan_id}.ics"'
            return response
        except CollaborationError as exc:
            return self.error_response(exc)


class PlanCalendarLinksView(CollaborationAPIView):
    def get(self, request, plan_id):
        try:
            return Response({'results': self.service.google_calendar_links(
                plan_id, request.user.id
            )})
        except CollaborationError as exc:
            return self.error_response(exc)
