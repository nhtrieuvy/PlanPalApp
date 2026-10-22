from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIRequestFactory, force_authenticate

from planpals.auth.infrastructure.websocket_ticket import WebSocketTicketService
from planpals.auth.presentation.views import WebSocketTicketView


@override_settings(
    CACHES={
        'default': {
            'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
            'LOCATION': 'websocket-ticket-tests',
        }
    },
    WEBSOCKET_TICKET_TTL_SECONDS=30,
)
class WebSocketTicketTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = get_user_model().objects.create_user(
            username='ws-ticket-user',
            email='ws-ticket@example.com',
            password='test-password',
        )

    def test_ticket_is_single_use(self):
        ticket = WebSocketTicketService.issue(self.user.id)

        first = WebSocketTicketService.consume(ticket)
        replay = WebSocketTicketService.consume(ticket)

        self.assertEqual(first['user_id'], str(self.user.id))
        self.assertIsNone(replay)

    def test_authenticated_endpoint_issues_ticket(self):
        request = APIRequestFactory().post('/api/v1/auth/websocket-ticket/')
        force_authenticate(request, user=self.user)

        response = WebSocketTicketView.as_view()(request)

        self.assertEqual(response.status_code, 200)
        self.assertIn('ticket', response.data)
        self.assertEqual(response.data['expires_in'], 30)

    def test_endpoint_rejects_anonymous_user(self):
        request = APIRequestFactory().post('/api/v1/auth/websocket-ticket/')

        response = WebSocketTicketView.as_view()(request)

        self.assertIn(response.status_code, (401, 403))
