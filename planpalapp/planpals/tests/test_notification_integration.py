"""
Integration tests for the enhanced push notification system
"""
import pytest
from unittest.mock import Mock, patch, MagicMock
from django.test import TestCase, override_settings
from django.contrib.auth.models import User
from django.core.cache import cache
from django.utils import timezone

from ..integrations.notification_service import NotificationService
from ..models import Plan, Activity, Group
from ..services import PlanPalService
from ..events import EventType, RealtimeEvent


class NotificationIntegrationTest(TestCase):
    """Test the complete notification flow with performance optimizations"""

    def setUp(self):
        """Setup test data"""
        self.service = PlanPalService()
        self.notification_service = NotificationService()
        
        # Create test users
        self.user1 = User.objects.create_user(
            username='user1', 
            email='user1@test.com',
            password='testpass123'
        )
        self.user1.fcm_token = 'token_user1'
        self.user1.save()
        
        self.user2 = User.objects.create_user(
            username='user2',
            email='user2@test.com', 
            password='testpass123'
        )
        self.user2.fcm_token = 'token_user2'
        self.user2.save()
        
        # Create test group
        self.group = Group.objects.create(
            name='Test Group',
            description='Test group for notifications'
        )
        self.group.members.add(self.user1, self.user2)
        
        # Create test plan
        self.plan = Plan.objects.create(
            name='Test Plan',
            description='Test plan for notifications',
            created_by=self.user1,
            group=self.group,
            start_date=timezone.now().date(),
            end_date=timezone.now().date()
        )
        self.plan.members.add(self.user1, self.user2)
        
        # Clear cache before each test
        cache.clear()

    @override_settings(FCM_SERVER_KEY='test_key')
    @patch('requests.post')
    def test_notification_service_batching(self, mock_post):
        """Test that notifications are properly batched for performance"""
        # Mock successful FCM response
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'success': 2,
            'failure': 0,
            'results': [
                {'message_id': 'msg1'},
                {'message_id': 'msg2'}
            ]
        }
        mock_post.return_value = mock_response
        
        # Send notification to multiple users
        tokens = ['token1', 'token2', 'token3']
        success_count, total_count = self.notification_service.send_push_notification_batch(
            tokens, 'Test Title', 'Test Body', {'test': 'data'}
        )
        
        # Verify batching worked
        self.assertEqual(success_count, 2)  # Based on mock response
        self.assertEqual(total_count, 3)
        
        # Verify FCM was called with multicast payload
        mock_post.assert_called_once()
        call_args = mock_post.call_args
        self.assertIn('registration_ids', call_args[1]['data'])

    def test_rate_limiting(self):
        """Test that rate limiting prevents spam"""
        user_id = str(self.user1.id)
        
        # First notification should succeed
        self.assertTrue(self.notification_service.check_rate_limit(user_id))
        
        # Set rate limit to 1 for testing
        self.notification_service.max_notifications_per_hour = 1
        
        # Manually set cache to max limit
        cache_key = f"fcm_rate_limit:{user_id}"
        cache.set(cache_key, 1, 3600)
        
        # Second notification should be rate limited
        self.assertFalse(self.notification_service.check_rate_limit(user_id))

    @override_settings(FCM_SERVER_KEY='test_key')
    @patch('requests.post')
    def test_activity_notification_flow(self, mock_post):
        """Test complete flow from activity creation to notification"""
        # Mock successful FCM response
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'success': 1, 'failure': 0}
        mock_post.return_value = mock_response
        
        # Create an activity - this should trigger notifications
        with patch('planpals.realtime_publisher.RealtimeEventPublisher.publish_event') as mock_publish:
            activity_data = {
                'title': 'Test Activity',
                'description': 'Test activity for notifications',
                'start_time': timezone.now(),
                'location_name': 'Test Location'
            }
            
            activity = self.service.add_activity_to_plan(
                plan_id=self.plan.id,
                activity_data=activity_data,
                user_id=self.user1.id
            )
            
            # Verify event was published
            mock_publish.assert_called()
            call_args = mock_publish.call_args[0][0]
            self.assertEqual(call_args.event_type, EventType.ACTIVITY_CREATED)
            self.assertEqual(call_args.data['activity_title'], 'Test Activity')

    @override_settings(FCM_SERVER_KEY='test_key')
    @patch('requests.post')
    def test_plan_status_notification(self, mock_post):
        """Test plan status change notifications"""
        # Mock successful FCM response
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'success': 1, 'failure': 0}
        mock_post.return_value = mock_response
        
        # Start trip - should trigger notification
        with patch('planpals.realtime_publisher.RealtimeEventPublisher.publish_event') as mock_publish:
            result = self.service.start_trip(self.plan.id, self.user1.id)
            
            # Verify event was published with proper data
            mock_publish.assert_called()
            call_args = mock_publish.call_args[0][0]
            self.assertEqual(call_args.event_type, EventType.PLAN_STARTED)
            self.assertIn('started_by_name', call_args.data)

    def test_notification_statistics(self):
        """Test notification service statistics and monitoring"""
        stats = self.notification_service.get_statistics()
        
        # Verify required fields are present
        self.assertIn('rate_limit_window_hours', stats)
        self.assertIn('max_notifications_per_hour', stats)
        self.assertIn('batch_size', stats)
        self.assertIn('fcm_configured', stats)
        self.assertIn('timestamp', stats)
        self.assertIn('health_status', stats)

    @override_settings(FCM_SERVER_KEY='test_key')
    @patch('requests.post')
    def test_invalid_token_handling(self, mock_post):
        """Test handling of invalid FCM tokens"""
        # Mock FCM response with invalid token error
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'success': 0,
            'failure': 1,
            'results': [
                {'error': 'NotRegistered'}
            ]
        }
        mock_post.return_value = mock_response
        
        # Send notification with invalid token
        success_count, total_count = self.notification_service.send_push_notification_batch(
            ['invalid_token'], 'Test Title', 'Test Body'
        )
        
        # Should handle gracefully without crashing
        self.assertEqual(success_count, 0)
        self.assertEqual(total_count, 1)

    @override_settings(FCM_SERVER_KEY='test_key')
    def test_group_notification_targeting(self):
        """Test that group notifications properly target members"""
        # Create additional users for the group
        user3 = User.objects.create_user(
            username='user3',
            email='user3@test.com',
            password='testpass123'
        )
        user3.fcm_token = 'token_user3'
        user3.save()
        
        self.group.members.add(user3)
        
        with patch.object(self.notification_service, 'send_push_notification_batch') as mock_batch:
            mock_batch.return_value = (2, 2)  # success_count, total_count
            
            # Send group notification excluding user1
            result = self.notification_service.send_group_notification(
                str(self.group.id),
                'Test Group Message',
                'Test notification body',
                exclude_user_id=str(self.user1.id)
            )
            
            # Should succeed
            self.assertTrue(result)
            
            # Verify correct tokens were used (user2 and user3, excluding user1)
            mock_batch.assert_called_once()
            call_args = mock_batch.call_args
            tokens_used = call_args[0][0]  # First argument is token list
            
            # Should have 2 tokens (user2 and user3)
            self.assertEqual(len(tokens_used), 2)
            self.assertIn('token_user2', tokens_used)
            self.assertIn('token_user3', tokens_used)
            self.assertNotIn('token_user1', tokens_used)

    def test_configuration_validation(self):
        """Test notification service configuration validation"""
        # Test with no FCM key
        service = NotificationService()
        service.fcm_server_key = None
        self.assertFalse(service.validate_config())
        
        # Test with FCM key
        service.fcm_server_key = 'test_key'
        self.assertTrue(service.validate_config())

    @patch('planpals.integrations.notification_service.logger')
    def test_error_logging(self, mock_logger):
        """Test that errors are properly logged"""
        # Test with invalid plan ID
        result = self.notification_service.send_plan_notification(
            '99999',  # Non-existent plan
            'Test Title',
            'Test Body'
        )
        
        # Should fail gracefully and log error
        self.assertFalse(result)
        mock_logger.error.assert_called()


@pytest.mark.django_db
class NotificationPerformanceTest:
    """Performance tests for notification system"""
    
    def test_large_batch_handling(self):
        """Test handling of large notification batches"""
        service = NotificationService()
        
        # Generate large token list
        large_token_list = [f'token_{i}' for i in range(1000)]
        
        with patch('requests.post') as mock_post:
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {'success': 500, 'failure': 0}
            mock_post.return_value = mock_response
            
            # Should handle large batches by splitting them
            success_count, total_count = service.send_push_notification_batch(
                large_token_list, 'Test', 'Test body'
            )
            
            # Verify multiple requests were made for batching
            assert mock_post.call_count >= 2  # Should split into multiple batches
            assert total_count == 1000

    def test_concurrent_rate_limiting(self):
        """Test rate limiting under concurrent access"""
        service = NotificationService()
        service.max_notifications_per_hour = 10
        
        user_id = 'test_user'
        
        # Simulate concurrent requests
        results = []
        for i in range(15):
            result = service.check_rate_limit(user_id)
            results.append(result)
        
        # First 10 should succeed, rest should be rate limited
        successful = sum(results)
        assert successful <= 10  # Should not exceed rate limit