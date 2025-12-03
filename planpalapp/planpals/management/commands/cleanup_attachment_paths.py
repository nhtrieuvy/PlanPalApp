from django.core.management.base import BaseCommand
from django.db.models import Q
from planpals.models import ChatMessage
from planpals.services import is_local_path
import re


class Command(BaseCommand):
    help = 'Find and optionally clean up chat messages with local file paths in attachment field'

    def add_arguments(self, parser):
        parser.add_argument(
            '--fix',
            action='store_true',
            help='Actually delete messages with local paths (default: dry run)',
        )
        parser.add_argument(
            '--limit',
            type=int,
            default=100,
            help='Limit number of messages to check (default: 100)',
        )

    def handle(self, *args, **options):
        self.stdout.write('🔍 Scanning for messages with local file paths...')
        
        # Query messages with image/file types that have attachment values
        messages_with_attachments = ChatMessage.objects.filter(
            message_type__in=['image', 'file'],
            attachment__isnull=False,
            is_deleted=False
        ).exclude(attachment='')[:options['limit']]
        
        problematic_messages = []
        
        for message in messages_with_attachments:
            attachment_value = str(message.attachment)
            if is_local_path(attachment_value):
                problematic_messages.append(message)
                self.stdout.write(
                    f'❌ Message {message.id} ({message.message_type}): {attachment_value[:100]}'
                )
        
        if not problematic_messages:
            self.stdout.write(self.style.SUCCESS('✅ No messages with local file paths found!'))
            return
        
        self.stdout.write(f'\n📊 Found {len(problematic_messages)} problematic messages')
        
        if options['fix']:
            self.stdout.write('🔧 Fixing problematic messages...')
            
            for message in problematic_messages:
                # Option 1: Delete the messages entirely
                # message.delete()
                
                # Option 2: Mark as deleted (soft delete)
                message.is_deleted = True
                message.save(update_fields=['is_deleted'])
                
                self.stdout.write(f'✅ Marked message {message.id} as deleted')
            
            self.stdout.write(
                self.style.SUCCESS(f'✅ Fixed {len(problematic_messages)} messages')
            )
        else:
            self.stdout.write(
                self.style.WARNING(
                    '⚠️  This was a dry run. Use --fix to actually mark these messages as deleted.'
                )
            )
            self.stdout.write('Example problematic paths found:')
            for msg in problematic_messages[:5]:  # Show first 5 examples
                self.stdout.write(f'  • {str(msg.attachment)[:80]}...')