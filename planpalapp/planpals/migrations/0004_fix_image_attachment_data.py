# Migration to fix image attachment data
# Move image URLs from content field to attachment field

from django.db import migrations


def fix_image_attachments(apps, schema_editor):
    """Move image URLs from content to attachment field"""
    ChatMessage = apps.get_model('planpals', 'ChatMessage')
    
    # Find all image messages where content contains URLs but attachment is empty
    image_messages = ChatMessage.objects.filter(
        message_type='image',
        attachment__isnull=True
    ).exclude(content='')
    
    updated_count = 0
    for message in image_messages:
        # Check if content looks like a URL (contains specific patterns)
        content = message.content.strip()
        if (content.startswith('http://') or 
            content.startswith('https://') or
            content.startswith('res.cloudinary.com') or
            'scaled_' in content):
            
            # Move URL to attachment field
            message.attachment = content
            message.attachment_name = content.split('/')[-1] if '/' in content else content
            
            # Set content to filename or generic message
            if '/' in content:
                filename = content.split('/')[-1]
                message.content = filename
            else:
                message.content = "Image"
            
            message.save(update_fields=['attachment', 'attachment_name', 'content'])
            updated_count += 1
    
    print(f"Fixed {updated_count} image messages")


def reverse_image_attachments(apps, schema_editor):
    """Reverse the migration by moving URLs back to content"""
    ChatMessage = apps.get_model('planpals', 'ChatMessage')
    
    # Find image messages with attachments
    image_messages = ChatMessage.objects.filter(
        message_type='image',
        attachment__isnull=False
    )
    
    for message in image_messages:
        if message.attachment:
            # Move URL back to content
            message.content = str(message.attachment)
            message.attachment = None
            message.attachment_name = ""
            message.save(update_fields=['content', 'attachment', 'attachment_name'])


class Migration(migrations.Migration):

    dependencies = [
        ('planpals', '0003_add_conversation_field_chatmessage'),
    ]

    operations = [
        migrations.RunPython(
            fix_image_attachments,
            reverse_image_attachments,
        ),
    ]