# ============================================================================
# PLANPAL MANAGEMENT COMMAND - OAuth2 Token Cleanup
# ============================================================================

from django.core.management.base import BaseCommand
from planpals.oauth2_utils import OAuth2TokenManager


class Command(BaseCommand):
    help = 'Clean up expired OAuth2 tokens'
    
    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be deleted without actually deleting',
        )
        
        parser.add_argument(
            '--verbose',
            action='store_true', 
            help='Show detailed output',
        )
    
    def handle(self, *args, **options):
        self.stdout.write(
            self.style.SUCCESS('Starting OAuth2 token cleanup...')
        )
        
        if options['dry_run']:
            self.stdout.write(
                self.style.WARNING('DRY RUN: No tokens will be actually deleted')
            )
        
        try:
            if options['dry_run']:
                # For dry run, we need to implement count logic
                from django.utils import timezone
                from oauth2_provider.models import AccessToken, RefreshToken
                
                now = timezone.now()
                expired_access_count = AccessToken.objects.filter(expires__lt=now).count()
                expired_refresh_count = RefreshToken.objects.filter(expires__lt=now).count()
                
                result = {
                    'expired_access_tokens': expired_access_count,
                    'expired_refresh_tokens': expired_refresh_count
                }
            else:
                result = OAuth2TokenManager.cleanup_expired_tokens()
            
            if options['verbose']:
                self.stdout.write(f"Expired access tokens: {result['expired_access_tokens']}")
                self.stdout.write(f"Expired refresh tokens: {result['expired_refresh_tokens']}")
            
            if result['expired_access_tokens'] > 0 or result['expired_refresh_tokens'] > 0:
                self.stdout.write(
                    self.style.SUCCESS(
                        f"{'Would clean up' if options['dry_run'] else 'Cleaned up'} "
                        f"{result['expired_access_tokens']} access tokens and "
                        f"{result['expired_refresh_tokens']} refresh tokens"
                    )
                )
            else:
                self.stdout.write(
                    self.style.SUCCESS('No expired tokens found')
                )
                
        except Exception as e:
            self.stdout.write(
                self.style.ERROR(f'Error during cleanup: {str(e)}')
            )
            raise
