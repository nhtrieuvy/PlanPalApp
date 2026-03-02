from rest_framework import status
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from django.contrib.auth import get_user_model

from planpals.integrations.notification_service import NotificationService

User = get_user_model()


class SendNotificationView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        recipient_id = request.data.get('recipient_id')
        title = request.data.get('title')
        body = request.data.get('body')
        data = request.data.get('data', {})

        if not all([recipient_id, title, body]):
            return Response(
                {'error': 'recipient_id, title, and body are required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            recipient = User.objects.get(id=recipient_id)
            if hasattr(recipient, 'fcm_token') and recipient.fcm_token:
                success = NotificationService.send_push_notification(
                    fcm_tokens=[recipient.fcm_token],
                    title=title,
                    body=body,
                    data=data
                )

                if success:
                    return Response({'message': 'Notification sent successfully'})
                else:
                    return Response(
                        {'error': 'Failed to send notification'},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR
                    )
            else:
                return Response(
                    {'error': 'Recipient has no FCM token'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        except User.DoesNotExist:
            return Response(
                {'error': 'Recipient not found'},
                status=status.HTTP_404_NOT_FOUND
            )
