from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from planpals.auth.infrastructure.models import Friendship, User
from planpals.plans.application.publications import publish_completed_plan
from planpals.plans.infrastructure.models import Plan, PlanPublication
from planpals.shared.paginators import StandardResultsPagination


class PublicationInputSerializer(serializers.Serializer):
    destination = serializers.CharField(max_length=120, trim_whitespace=True)
    summary = serializers.CharField(max_length=500, trim_whitespace=True)
    highlight_ids = serializers.ListField(
        child=serializers.UUIDField(), max_length=5, required=False, default=list
    )

    def validate_highlight_ids(self, value):
        if len(value) != len(set(value)):
            raise serializers.ValidationError('Choose each highlight only once.')
        return value


def publication_payload(publication):
    plan = publication.plan
    return {
        'id': str(publication.id),
        'plan_id': str(plan.id),
        'owner_id': str(plan.creator_id),
        'title': plan.title,
        'destination': publication.destination,
        'summary': publication.summary,
        'highlights': [
            {'title': item.get('title', ''), 'place': item.get('place', '')}
            for item in publication.highlights
        ],
        'published_at': publication.published_at.isoformat(),
    }


class PublishedProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        owner = get_object_or_404(User, id=user_id, is_active=True)
        if Friendship.is_blocked(request.user, owner):
            return Response(status=status.HTTP_404_NOT_FOUND)
        publications = PlanPublication.objects.filter(
            plan__creator=owner,
            plan__plan_type='personal',
            plan__status='completed',
            is_active=True,
        ).select_related('plan').order_by('-published_at', '-id')
        paginator = StandardResultsPagination()
        page = paginator.paginate_queryset(publications, request)
        return Response({
            'user': {
                'id': str(owner.id),
                'username': owner.username,
                'full_name': owner.get_full_name() or owner.username,
                'bio': owner.bio,
                'avatar_url': owner.avatar_url,
            },
            'publications': [publication_payload(item) for item in page],
            'next': paginator.get_next_link(),
            'count': paginator.page.paginator.count,
        })


class PlanPublicationView(APIView):
    permission_classes = [IsAuthenticated]

    def _owned_plan(self, request, plan_id):
        return get_object_or_404(Plan, id=plan_id, creator=request.user)

    def get(self, request, plan_id):
        plan = self._owned_plan(request, plan_id)
        publication = PlanPublication.objects.filter(plan=plan, is_active=True).first()
        if publication is None:
            return Response(None)
        payload = publication_payload(publication)
        payload['highlight_ids'] = [
            item['source_id'] for item in publication.highlights
            if item.get('source_id')
        ]
        return Response(payload)

    def put(self, request, plan_id):
        plan = self._owned_plan(request, plan_id)
        serializer = PublicationInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            publication, created = publish_completed_plan(
                plan,
                destination=serializer.validated_data['destination'],
                summary=serializer.validated_data['summary'],
                highlight_ids=serializer.validated_data['highlight_ids'],
            )
        except ValueError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(
            publication_payload(publication),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    def delete(self, request, plan_id):
        plan = self._owned_plan(request, plan_id)
        PlanPublication.objects.filter(plan=plan).update(is_active=False)
        return Response(status=status.HTTP_204_NO_CONTENT)


class PublicationPreviewView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, publication_id):
        publication = get_object_or_404(
            PlanPublication.objects.select_related('plan'),
            id=publication_id,
            is_active=True,
            plan__plan_type='personal',
            plan__status='completed',
        )
        if Friendship.is_blocked(request.user, publication.plan.creator):
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(publication_payload(publication))
