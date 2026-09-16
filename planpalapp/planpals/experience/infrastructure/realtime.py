import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from planpals.shared.events import ChannelGroups


logger = logging.getLogger(__name__)


class ExperienceRealtimePublisher:
    def publish_group(self, group_id, event, data):
        self._publish(ChannelGroups.group(group_id), event, data)

    def publish_conversation(self, conversation_id, event, data):
        self._publish(ChannelGroups.conversation(conversation_id), event, data)

    @staticmethod
    def _publish(group_name, event, data):
        channel_layer = get_channel_layer()
        if channel_layer is None:
            return
        try:
            async_to_sync(channel_layer.group_send)(
                group_name,
                {
                    'type': 'event_message',
                    'data': {'type': event, 'data': data},
                },
            )
        except Exception:
            logger.exception(
                'Unable to publish experience event %s to %s',
                event,
                group_name,
            )
