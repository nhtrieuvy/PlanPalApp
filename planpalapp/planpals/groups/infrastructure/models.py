"""
Groups Infrastructure — Django ORM Models

These are Django ORM model definitions (persistence concern).
They live in the infrastructure layer because they depend on Django's ORM.

The domain layer (entities.py, repositories.py, events.py) is pure Python.
"""
from uuid import UUID
from typing import Dict, Optional, Any, Union

from django.db import models
from django.db.models import Q, Count, QuerySet
from django.conf import settings
from django.core.exceptions import ValidationError

from cloudinary.models import CloudinaryField
from cloudinary import CloudinaryImage

from planpals.shared.base_models import BaseModel


class GroupQuerySet(models.QuerySet['Group']):
    
    def with_member_count(self) -> 'GroupQuerySet':
        return self.annotate(
            admin_count_annotated=Count(
                'memberships',
                distinct=True
            )
        )
    
    def with_admin_count(self) -> 'GroupQuerySet':
        return self.annotate(
            admin_count_annotated=Count(
                'memberships', 
                filter=Q(memberships__role=GroupMembership.ADMIN),
                distinct=True
            )
        )
    
    def with_plans_count(self) -> 'GroupQuerySet':
        return self.annotate(
            plans_count_annotated=Count('plans', distinct=True),
            active_plans_count_annotated=Count(
                'plans',
                filter=~Q(plans__status__in=['cancelled', 'completed']),
                distinct=True
            )
        )
    
    def with_full_stats(self) -> 'GroupQuerySet':
        return self.with_member_count().with_admin_count().with_plans_count()
    
    def active(self) -> 'GroupQuerySet':
        return self.filter(is_active=True)
    
    def for_user(self, user) -> 'GroupQuerySet':
        return self.filter(members=user)
    
    def administered_by(self, user) -> 'GroupQuerySet':
        return self.filter(
            memberships__user=user,
            memberships__role=GroupMembership.ADMIN
        )


class Group(BaseModel):

    name = models.CharField(
        max_length=100,
        help_text="Group name"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Group description"
    )
    
    avatar = CloudinaryField(
        'image',
        blank=True, 
        null=True,
        folder='planpal/groups/avatars',
        transformation={
            'width': 300,
            'height': 300,
            'crop': 'fill',
            'gravity': 'face',
            'quality': 'auto:good'
        },
        help_text="Group avatar"
    )
    
    cover_image = CloudinaryField(
        'image',
        blank=True, 
        null=True,
        folder='planpal/groups/covers',
        transformation={
            'width': 1200,
            'height': 400,
            'crop': 'fill',
            'gravity': 'center',
            'quality': 'auto:good'
        },
        help_text="Group cover image"
    )

    
    admin = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='administered_groups',
        help_text="Group admin"
    )
    
    members = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        through='GroupMembership',
        related_name='joined_groups',
        help_text="Group members"
    )
    
    objects = GroupQuerySet.as_manager()

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_groups'
        
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['admin', 'is_active']),
            models.Index(fields=['is_active', 'created_at']),
        ]

    def __str__(self) -> str:
        return f"{self.name} (Admin: {self.admin.username})"

    def save(self, *args: Any, **kwargs: Any) -> None:
        # Cờ kiểm tra nếu là nhóm mới
        is_new = self._state.adding
        
        super().save(*args, **kwargs)
        
        if is_new and self.admin:
            GroupMembership.objects.get_or_create(
                group=self,
                user=self.admin,
                defaults={'role': GroupMembership.ADMIN}
            )
            
            # Create group conversation - avoid circular import by using direct model approach
            try:
                from planpals.models import Conversation
                self.conversation
            except Exception:
                from planpals.models import Conversation
                Conversation.objects.create(
                    conversation_type='group',
                    group=self
                )

    @property
    def has_avatar(self) -> bool: 
        return bool(self.avatar)

    @property
    def avatar_url(self) -> Optional[str]:
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=300, height=300, crop='fill', gravity='face', secure=True)

    @property
    def avatar_thumb(self) -> Optional[str]:
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=100, height=100, crop='fill', gravity='face', secure=True)

    @property
    def has_cover_image(self) -> bool:
        return bool(self.cover_image)

    @property
    def cover_image_url(self) -> Optional[str]:
        if not self.cover_image:
            return None
        cloudinary_image = CloudinaryImage(str(self.cover_image))
        return cloudinary_image.build_url(width=1200, height=600, crop='fill', gravity='center', secure=True)

    @property
    def member_count(self) -> int:
        if hasattr(self, 'member_count_annotated'):
            return self.member_count_annotated
        return self.memberships.count()

    @property
    def admin_count(self) -> int:
        if hasattr(self, 'admin_count_annotated'):
            return self.admin_count_annotated
        return self.get_admin_count()

    @property
    def plans_count(self) -> int:
        if hasattr(self, 'plans_count_annotated'):
            return self.plans_count_annotated
        return self.plans.count()

    @property
    def active_plans_count(self) -> int:
        if hasattr(self, 'active_plans_count_annotated'):
            return self.active_plans_count_annotated
        return self.plans.exclude(status__in=['cancelled', 'completed']).count()
    


    def is_member(self, user) -> bool:
        return GroupMembership.objects.filter(
            group=self,
            user=user
        ).exists()

    def is_admin(self, user) -> bool:
        return GroupMembership.objects.filter(
            group=self,
            user=user,
            role=GroupMembership.ADMIN
        ).exists()

    def get_admins(self) -> QuerySet:
        from django.contrib.auth import get_user_model
        User = get_user_model()
        return User.objects.filter(
            groupmembership__group=self,
            groupmembership__role=GroupMembership.ADMIN
        )
    
    def get_admin_count(self) -> int:
        if hasattr(self, 'admin_count_annotated'):
            return self.admin_count_annotated
        
        return GroupMembership.objects.filter(
            group=self,
            role=GroupMembership.ADMIN
        ).count()


    def get_user_membership(self, user) -> Optional['GroupMembership']:
        try:
            return GroupMembership.objects.select_related('user').get(
                group=self,
                user=user
            )
        except GroupMembership.DoesNotExist:
            return None
    
    def get_user_role(self, user) -> Optional[str]:
        """Get the role of a user in this group"""
        membership = self.get_user_membership(user)
        return membership.role if membership else None
    


    def get_member_roles(self) -> Dict[UUID, str]:
        return dict(
            GroupMembership.objects.filter(group=self)
            .values_list('user_id', 'role')
        )

    def get_recent_messages(self, limit: int = 50) -> QuerySet:
        return self.messages.active().select_related('sender').order_by('-created_at')


class GroupMembershipQuerySet(models.QuerySet['GroupMembership']):
    def admins(self) -> 'GroupMembershipQuerySet':
        return self.filter(role=GroupMembership.ADMIN)
    
    def members(self) -> 'GroupMembershipQuerySet':
        return self.filter(role=GroupMembership.MEMBER)
    
    def for_group(self, group) -> 'GroupMembershipQuerySet':
        return self.filter(group=group)
    
    def for_user(self, user) -> 'GroupMembershipQuerySet':
        return self.filter(user=user)


class GroupMembership(BaseModel):
    ADMIN = 'admin'
    MEMBER = 'member'
    
    ROLE_CHOICES = [
        (ADMIN, 'Quản trị viên'),
        (MEMBER, 'Thành viên'),
    ]
    
    
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        help_text="Member user"
    )
    
    group = models.ForeignKey(
        Group,
        on_delete=models.CASCADE,
        related_name='memberships',
        help_text="Group"
    )
    
    role = models.CharField(
        max_length=20,
        choices=ROLE_CHOICES,
        default=MEMBER,
        db_index=True,
        help_text="Role"
    )
    
    objects = GroupMembershipQuerySet.as_manager()

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_group_memberships'
        # Đảm bảo user chỉ có 1 membership trong 1 group
        unique_together = ('user', 'group')
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho query members của group
            models.Index(fields=['group', 'role']),
            # Index cho query groups của user
            models.Index(fields=['user', 'role']),
        ]
        

    def __str__(self) -> str:
        return f"{self.user.username} in {self.group.name} ({self.get_role_display()})"

    def clean(self) -> None:
        super().clean()
        
        if self.pk and self.role == self.MEMBER:
            admin_count = GroupMembership.objects.filter(
                group=self.group,
                role=self.ADMIN
            ).exclude(pk=self.pk).count()
            
            if admin_count == 0:
                raise ValidationError("Group must have at least one admin")

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.pk and self.role == self.MEMBER:
            admin_count = GroupMembership.objects.filter(
                group=self.group,
                role=self.ADMIN
            ).exclude(pk=self.pk).count()
            
            if admin_count == 0:
                raise ValueError("Group must have at least one admin")

        self.clean()
        super().save(*args, **kwargs)
