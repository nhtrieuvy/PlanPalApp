from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from planpals.experience.application.factories import get_experience_service
from planpals.experience.presentation.serializers import (
    GlobalSearchQuerySerializer,
    GroupPollCreateSerializer,
    GroupPollSerializer,
    GroupPollVoteSerializer,
    LiveLocationSerializer,
    LiveLocationStartSerializer,
    LiveLocationUpdateSerializer,
)


class GroupPollListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, group_id):
        polls = get_experience_service().list_group_polls(group_id, request.user.id)
        return Response([
            GroupPollSerializer.from_model(poll, request.user.id) for poll in polls
        ])

    def post(self, request, group_id):
        serializer = GroupPollCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        poll = get_experience_service().create_group_poll(
            group_id,
            request.user.id,
            dict(serializer.validated_data),
            client_mutation_id=request.headers.get('X-Client-Mutation-ID'),
        )
        return Response(
            GroupPollSerializer.from_model(poll, request.user.id),
            status=status.HTTP_201_CREATED,
        )


class GroupPollVoteView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, poll_id):
        serializer = GroupPollVoteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        poll = get_experience_service().vote_group_poll(
            poll_id, request.user.id, serializer.validated_data['option_ids']
        )
        return Response(GroupPollSerializer.from_model(poll, request.user.id))


class GroupPollCloseView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, poll_id):
        poll = get_experience_service().close_group_poll(poll_id, request.user.id)
        return Response(GroupPollSerializer.from_model(poll, request.user.id))


class ConversationLiveLocationListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, conversation_id):
        shares = get_experience_service().list_live_locations(
            conversation_id, request.user.id
        )
        return Response([LiveLocationSerializer.from_model(item) for item in shares])

    def post(self, request, conversation_id):
        serializer = LiveLocationStartSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        share = get_experience_service().start_live_location(
            conversation_id,
            request.user.id,
            dict(serializer.validated_data),
            client_mutation_id=request.headers.get('X-Client-Mutation-ID'),
        )
        return Response(
            LiveLocationSerializer.from_model(share), status=status.HTTP_201_CREATED
        )


class LiveLocationDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, share_id):
        serializer = LiveLocationUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        share = get_experience_service().update_live_location(
            share_id, request.user.id, dict(serializer.validated_data)
        )
        return Response(LiveLocationSerializer.from_model(share))

    def delete(self, request, share_id):
        get_experience_service().stop_live_location(share_id, request.user.id)
        return Response(status=status.HTTP_204_NO_CONTENT)


class GlobalSearchView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = GlobalSearchQuerySerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        result = get_experience_service().global_search(
            request.user.id,
            serializer.validated_data['q'],
            types=serializer.parsed_types(),
            limit=serializer.validated_data['limit'],
        )
        return Response({'query': serializer.validated_data['q'], **result})
