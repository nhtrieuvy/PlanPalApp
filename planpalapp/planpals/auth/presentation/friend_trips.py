from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from planpals.auth.application.friend_trips import (
    decide_invitation, invitation_payload, send_invitation,
)
from planpals.auth.infrastructure.models import FriendTripInvitation, User


class InvitationInputSerializer(serializers.Serializer):
    friend_id = serializers.UUIDField()
    name = serializers.CharField(max_length=120, trim_whitespace=True)


class FriendTripListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        invitations = FriendTripInvitation.objects.filter(
            Q(sender=request.user) | Q(recipient=request.user)
        ).select_related('sender', 'recipient').order_by('-created_at')[:100]
        return Response([invitation_payload(item) for item in invitations])

    def post(self, request):
        serializer = InvitationInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        recipient = get_object_or_404(User, id=serializer.validated_data['friend_id'])
        invitation = send_invitation(
            request.user, recipient, serializer.validated_data['name']
        )
        return Response(invitation_payload(invitation), status=status.HTTP_201_CREATED)


class FriendTripDecisionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, invitation_id):
        decision = request.data.get('decision')
        if decision not in {'accept', 'decline', 'cancel'}:
            return Response(
                {'decision': ['Choose accept, decline or cancel.']},
                status=status.HTTP_400_BAD_REQUEST,
            )
        invitation = decide_invitation(invitation_id, request.user, decision)
        return Response(invitation_payload(invitation))
