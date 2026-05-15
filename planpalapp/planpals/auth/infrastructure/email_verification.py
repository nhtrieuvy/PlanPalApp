import logging
import secrets
from base64 import b64decode, b64encode
from dataclasses import dataclass
from io import BytesIO
from typing import Optional
from urllib.parse import urlencode

import cloudinary.uploader
from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.contrib.auth.tokens import PasswordResetTokenGenerator
from django.core.cache import cache
from django.core.mail import send_mail
from django.db import IntegrityError, transaction
from django.utils import timezone
from django.utils.crypto import constant_time_compare, salted_hmac
from django.utils.encoding import force_str
from django.utils.http import urlsafe_base64_decode, urlsafe_base64_encode
from django.utils.encoding import force_bytes

from planpals.shared.cache import CacheKeys


logger = logging.getLogger(__name__)
User = get_user_model()


class EmailVerificationTokenGenerator(PasswordResetTokenGenerator):
    def _make_hash_value(self, user, timestamp):
        verified_at = getattr(user, 'email_verified_at', None)
        return (
            f'{user.pk}{user.password}{user.email}{user.is_active}'
            f'{verified_at}{timestamp}'
        )


email_verification_token_generator = EmailVerificationTokenGenerator()


@dataclass(frozen=True)
class EmailVerificationResult:
    success: bool
    message: str
    user: Optional[object] = None
    error_code: Optional[str] = None


class EmailVerificationService:
    resend_cooldown_seconds = 60
    code_ttl_seconds = 10 * 60
    max_code_attempts = 5
    pending_registration_ttl_seconds = 10 * 60
    max_pending_avatar_bytes = 3 * 1024 * 1024

    @classmethod
    def _code_cache_key(cls, user_id) -> str:
        return f'email_verification_code:{user_id}'

    @classmethod
    def _attempts_cache_key(cls, user_id) -> str:
        return f'email_verification_attempts:{user_id}'

    @classmethod
    def _resend_cache_key(cls, user_id) -> str:
        return f'email_verification_resend:{user_id}'

    @classmethod
    def _pending_registration_key(cls, email: str) -> str:
        return f'email_verification_pending_registration:{email.strip().lower()}'

    @classmethod
    def _pending_username_key(cls, username: str) -> str:
        return f'email_verification_pending_username:{username.strip().lower()}'

    @classmethod
    def _pending_email_code_key(cls, email: str) -> str:
        return f'email_verification_pending_code:{email.strip().lower()}'

    @classmethod
    def _pending_email_attempts_key(cls, email: str) -> str:
        return f'email_verification_pending_attempts:{email.strip().lower()}'

    @classmethod
    def _pending_email_resend_key(cls, email: str) -> str:
        return f'email_verification_pending_resend:{email.strip().lower()}'

    @classmethod
    def _generate_code(cls) -> str:
        return f'{secrets.randbelow(1_000_000):06d}'

    @classmethod
    def _hash_code(cls, user_id, code: str) -> str:
        return salted_hmac(
            'planpal.auth.email_verification',
            f'{user_id}:{code}',
        ).hexdigest()

    @classmethod
    def _hash_email_code(cls, email: str, code: str) -> str:
        return salted_hmac(
            'planpal.auth.pending_email_verification',
            f'{email.strip().lower()}:{code}',
        ).hexdigest()

    @classmethod
    def _store_code(cls, user, code: str) -> None:
        cache.set(
            cls._code_cache_key(user.id),
            cls._hash_code(user.id, code),
            timeout=cls.code_ttl_seconds,
        )
        cache.delete(cls._attempts_cache_key(user.id))

    @classmethod
    def _store_pending_code(cls, email: str, code: str) -> None:
        normalized_email = email.strip().lower()
        cache.set(
            cls._pending_email_code_key(normalized_email),
            cls._hash_email_code(normalized_email, code),
            timeout=cls.code_ttl_seconds,
        )
        cache.delete(cls._pending_email_attempts_key(normalized_email))

    @classmethod
    def _send_code_email(cls, *, email: str, display_name: str, code: str) -> bool:
        subject = 'Your PlanPal verification code'
        message = (
            f'Hi {display_name},\n\n'
            f'Your PlanPal verification code is: {code}\n\n'
            f'This code expires in {cls.code_ttl_seconds // 60} minutes. '
            'Enter it in the PlanPal app to activate your account.\n\n'
            'If you did not create this account, you can ignore this email.'
        )

        try:
            send_mail(
                subject=subject,
                message=message,
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[email],
                fail_silently=False,
            )
            return True
        except Exception:
            logger.exception('Failed to send email verification code to %s', email)
            return False

    @classmethod
    def start_pending_registration(cls, validated_data: dict) -> EmailVerificationResult:
        data = dict(validated_data)
        data.pop('password_confirm', None)

        email = (data.get('email') or '').strip().lower()
        username = (data.get('username') or '').strip()
        if not email or not username:
            return EmailVerificationResult(
                success=False,
                message='Email and username are required.',
                error_code='invalid_registration_payload',
            )

        if User.objects.filter(email__iexact=email).exists():
            return EmailVerificationResult(
                success=False,
                message='Email is already in use.',
                error_code='email_exists',
            )
        if User.objects.filter(username__iexact=username).exists():
            return EmailVerificationResult(
                success=False,
                message='Username already exists.',
                error_code='username_exists',
            )

        pending_username_key = cls._pending_username_key(username)
        reserved_email = cache.get(pending_username_key)
        if reserved_email and reserved_email != email:
            return EmailVerificationResult(
                success=False,
                message='Username is waiting for email verification.',
                error_code='username_pending_verification',
            )

        avatar_payload = None
        avatar = data.pop('avatar', None)
        if avatar is not None:
            avatar.seek(0)
            avatar_bytes = avatar.read()
            if len(avatar_bytes) > cls.max_pending_avatar_bytes:
                return EmailVerificationResult(
                    success=False,
                    message='Avatar is too large for pending registration.',
                    error_code='avatar_too_large',
                )
            avatar_payload = {
                'name': getattr(avatar, 'name', 'avatar.jpg'),
                'content_type': getattr(avatar, 'content_type', 'image/jpeg'),
                'content': b64encode(avatar_bytes).decode('ascii'),
            }

        data['email'] = email
        data['password'] = make_password(data['password'])
        data['avatar_payload'] = avatar_payload

        cache.set(
            cls._pending_registration_key(email),
            data,
            timeout=cls.pending_registration_ttl_seconds,
        )
        cache.set(
            pending_username_key,
            email,
            timeout=cls.pending_registration_ttl_seconds,
        )

        code = cls._generate_code()
        cls._store_pending_code(email, code)
        sent = cls._send_code_email(
            email=email,
            display_name=data.get('first_name') or username,
            code=code,
        )
        if not sent:
            cls._clear_pending_registration(email=email, username=username)
            return EmailVerificationResult(
                success=False,
                message='Could not send verification code. Please try again later.',
                error_code='email_send_failed',
            )

        logger.info('Started pending registration for email %s', email)
        return EmailVerificationResult(
            success=True,
            message='Verification code sent. Complete email verification to create your account.',
        )

    @classmethod
    def _clear_pending_registration(cls, *, email: str, username: Optional[str] = None) -> None:
        normalized_email = email.strip().lower()
        pending = cache.get(cls._pending_registration_key(normalized_email))
        reserved_username = username or (pending or {}).get('username')
        cache.delete(cls._pending_registration_key(normalized_email))
        cache.delete(cls._pending_email_code_key(normalized_email))
        cache.delete(cls._pending_email_attempts_key(normalized_email))
        cache.delete(cls._pending_email_resend_key(normalized_email))
        if reserved_username:
            cache.delete(cls._pending_username_key(reserved_username))

    @classmethod
    def is_pending_identifier(cls, identifier: str) -> bool:
        normalized = (identifier or '').strip().lower()
        if not normalized:
            return False
        if '@' in normalized:
            return bool(cache.get(cls._pending_registration_key(normalized)))
        return bool(cache.get(cls._pending_username_key(normalized)))

    @classmethod
    def send_verification_email(cls, user, request=None) -> bool:
        if user.is_email_verified:
            return True

        code = cls._generate_code()
        cls._store_code(user, code)

        if cls._send_code_email(
            email=user.email,
            display_name=user.get_full_name() or user.username,
            code=code,
        ):
            logger.info('Sent email verification code to user %s', user.id)
            return True
        return False

    @classmethod
    def build_verification_url(cls, user, request=None) -> str:
        uid = urlsafe_base64_encode(force_bytes(user.pk))
        token = email_verification_token_generator.make_token(user)
        query = urlencode({'uid': uid, 'token': token})

        frontend_url = getattr(settings, 'EMAIL_VERIFICATION_FRONTEND_URL', '')
        if frontend_url:
            separator = '&' if '?' in frontend_url else '?'
            return f'{frontend_url}{separator}{query}'

        path = f'/api/v1/users/verify-email/?{query}'
        if request is not None:
            return request.build_absolute_uri(path)

        base_url = getattr(settings, 'BACKEND_PUBLIC_URL', '').rstrip('/')
        return f'{base_url}{path}' if base_url else path

    @classmethod
    def verify(
        cls,
        *,
        email: Optional[str] = None,
        code: Optional[str] = None,
        uid: Optional[str] = None,
        token: Optional[str] = None,
    ) -> EmailVerificationResult:
        if email is not None or code is not None:
            return cls._verify_code(email=email or '', code=code or '')
        return cls._verify_token(uid=uid or '', token=token or '')

    @classmethod
    def _verify_token(cls, uid: str, token: str) -> EmailVerificationResult:
        if not uid or not token:
            return EmailVerificationResult(
                success=False,
                message='Verification link is missing required parameters.',
                error_code='missing_token',
            )

        try:
            user_id = force_str(urlsafe_base64_decode(uid))
            user = User.objects.get(pk=user_id)
        except (TypeError, ValueError, OverflowError, User.DoesNotExist):
            return EmailVerificationResult(
                success=False,
                message='Verification link is invalid.',
                error_code='invalid_token',
            )

        if user.is_email_verified:
            return EmailVerificationResult(
                success=True,
                message='Email is already verified.',
                user=user,
            )

        if not email_verification_token_generator.check_token(user, token):
            return EmailVerificationResult(
                success=False,
                message='Verification link is invalid or expired.',
                user=user,
                error_code='invalid_or_expired_token',
            )

        user.mark_email_verified()
        cache.delete(CacheKeys.user_profile(user.id))
        return EmailVerificationResult(
            success=True,
            message='Email verified successfully. You can now sign in.',
            user=user,
        )

    @classmethod
    def _verify_code(cls, email: str, code: str) -> EmailVerificationResult:
        normalized_email = (email or '').strip().lower()
        normalized_code = (code or '').strip()
        if not normalized_email or not normalized_code:
            return EmailVerificationResult(
                success=False,
                message='Email and verification code are required.',
                error_code='missing_code',
            )

        if not normalized_code.isdigit() or len(normalized_code) != 6:
            return EmailVerificationResult(
                success=False,
                message='Verification code must be 6 digits.',
                error_code='invalid_code_format',
            )

        try:
            user = User.objects.get(email__iexact=normalized_email)
        except User.DoesNotExist:
            return cls._verify_pending_registration(
                email=normalized_email,
                code=normalized_code,
            )

        if user.is_email_verified:
            return EmailVerificationResult(
                success=True,
                message='Email is already verified.',
                user=user,
            )

        attempts_key = cls._attempts_cache_key(user.id)
        attempts = int(cache.get(attempts_key) or 0)
        if attempts >= cls.max_code_attempts:
            return EmailVerificationResult(
                success=False,
                message='Too many incorrect attempts. Please request a new code.',
                user=user,
                error_code='too_many_attempts',
            )

        expected_hash = cache.get(cls._code_cache_key(user.id))
        if not expected_hash:
            return EmailVerificationResult(
                success=False,
                message='Verification code is invalid or expired.',
                user=user,
                error_code='invalid_or_expired_code',
            )

        submitted_hash = cls._hash_code(user.id, normalized_code)
        if not constant_time_compare(expected_hash, submitted_hash):
            cache.set(
                attempts_key,
                attempts + 1,
                timeout=cls.code_ttl_seconds,
            )
            return EmailVerificationResult(
                success=False,
                message='Verification code is invalid or expired.',
                user=user,
                error_code='invalid_or_expired_code',
            )

        user.mark_email_verified()
        cache.delete(cls._code_cache_key(user.id))
        cache.delete(attempts_key)
        cache.delete(cls._resend_cache_key(user.id))
        cache.delete(CacheKeys.user_profile(user.id))
        return EmailVerificationResult(
            success=True,
            message='Email verified successfully. You can now sign in.',
            user=user,
        )

    @classmethod
    def _verify_pending_registration(cls, email: str, code: str) -> EmailVerificationResult:
        pending = cache.get(cls._pending_registration_key(email))
        if not pending:
            return EmailVerificationResult(
                success=False,
                message='Verification code is invalid or expired.',
                error_code='invalid_or_expired_code',
            )

        attempts_key = cls._pending_email_attempts_key(email)
        attempts = int(cache.get(attempts_key) or 0)
        if attempts >= cls.max_code_attempts:
            return EmailVerificationResult(
                success=False,
                message='Too many incorrect attempts. Please request a new code.',
                error_code='too_many_attempts',
            )

        expected_hash = cache.get(cls._pending_email_code_key(email))
        if not expected_hash:
            return EmailVerificationResult(
                success=False,
                message='Verification code is invalid or expired.',
                error_code='invalid_or_expired_code',
            )

        submitted_hash = cls._hash_email_code(email, code)
        if not constant_time_compare(expected_hash, submitted_hash):
            cache.set(
                attempts_key,
                attempts + 1,
                timeout=cls.code_ttl_seconds,
            )
            return EmailVerificationResult(
                success=False,
                message='Verification code is invalid or expired.',
                error_code='invalid_or_expired_code',
            )

        username = pending.get('username')
        if User.objects.filter(email__iexact=email).exists():
            cls._clear_pending_registration(email=email, username=username)
            return EmailVerificationResult(
                success=False,
                message='Email is already in use.',
                error_code='email_exists',
            )
        if User.objects.filter(username__iexact=username).exists():
            cls._clear_pending_registration(email=email, username=username)
            return EmailVerificationResult(
                success=False,
                message='Username already exists.',
                error_code='username_exists',
            )

        avatar_payload = pending.pop('avatar_payload', None)
        pending['is_active'] = True
        pending['email_verified_at'] = timezone.now()

        try:
            with transaction.atomic():
                user = User.objects.create(**pending)
        except IntegrityError:
            cls._clear_pending_registration(email=email, username=username)
            return EmailVerificationResult(
                success=False,
                message='Account could not be created. Please register again.',
                error_code='account_create_failed',
            )
        except Exception:
            logger.exception('Unexpected error while creating verified user for %s', email)
            return EmailVerificationResult(
                success=False,
                message='Account could not be created. Please try again later.',
                error_code='account_create_failed',
            )

        if avatar_payload:
            cls._save_pending_avatar(user=user, avatar_payload=avatar_payload)

        cls._clear_pending_registration(email=email, username=username)
        cache.delete(CacheKeys.user_profile(user.id))
        return EmailVerificationResult(
            success=True,
            message='Email verified successfully. You can now sign in.',
            user=user,
        )

    @classmethod
    def _save_pending_avatar(cls, *, user, avatar_payload: dict) -> None:
        try:
            avatar_bytes = b64decode(avatar_payload['content'])
            avatar_stream = BytesIO(avatar_bytes)
            avatar_stream.name = avatar_payload.get('name') or 'avatar.jpg'
            upload_result = cloudinary.uploader.upload(
                avatar_stream,
                folder='planpal/avatars',
                resource_type='image',
                use_filename=True,
                unique_filename=True,
                overwrite=False,
            )
            public_id = upload_result.get('public_id')
            if public_id:
                user.avatar = public_id
                user.save(update_fields=['avatar', 'updated_at'])
        except Exception as exc:
            logger.warning(
                'Verified user %s was created, but avatar upload was skipped: %s',
                user.id,
                exc,
            )

    @classmethod
    def resend(cls, email: str, request=None) -> EmailVerificationResult:
        normalized_email = (email or '').strip().lower()
        if not normalized_email:
            return EmailVerificationResult(
                success=False,
                message='Email is required.',
                error_code='email_required',
            )

        try:
            user = User.objects.get(email__iexact=normalized_email)
        except User.DoesNotExist:
            pending = cache.get(cls._pending_registration_key(normalized_email))
            if pending:
                cache_key = cls._pending_email_resend_key(normalized_email)
                if cache.get(cache_key):
                    return EmailVerificationResult(
                        success=True,
                        message='A verification code was sent recently. Please check your inbox.',
                    )
                code = cls._generate_code()
                cls._store_pending_code(normalized_email, code)
                sent = cls._send_code_email(
                    email=normalized_email,
                    display_name=pending.get('first_name') or pending.get('username') or 'there',
                    code=code,
                )
                if sent:
                    cache.set(cache_key, True, timeout=cls.resend_cooldown_seconds)
                return EmailVerificationResult(
                    success=sent,
                    message=(
                        'If the email exists and is not verified, a verification code has been sent.'
                        if sent
                        else 'Could not send verification code. Please try again later.'
                    ),
                    error_code=None if sent else 'email_send_failed',
                )
            return EmailVerificationResult(
                success=True,
                message='If the email exists and is not verified, a verification code has been sent.',
            )

        if user.is_email_verified:
            return EmailVerificationResult(
                success=True,
                message='Email is already verified.',
                user=user,
            )

        cache_key = cls._resend_cache_key(user.id)
        if cache.get(cache_key):
            return EmailVerificationResult(
                success=True,
                message='A verification code was sent recently. Please check your inbox.',
                user=user,
            )

        sent = cls.send_verification_email(user, request=request)
        if sent:
            cache.set(cache_key, True, timeout=cls.resend_cooldown_seconds)
        return EmailVerificationResult(
            success=sent,
            message=(
                'If the email exists and is not verified, a verification code has been sent.'
                if sent
                else 'Could not send verification code. Please try again later.'
            ),
            user=user,
            error_code=None if sent else 'email_send_failed',
        )
