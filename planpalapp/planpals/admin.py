from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.utils.html import format_html
from django.urls import reverse
from django.utils.safestring import mark_safe
from django.db import models
from django.forms import Textarea

from .models import (
    User, Group, GroupMembership, Plan, PlanActivity, 
    ChatMessage, Friendship, FriendshipRejection, MessageReadStatus
)

# ============================================================================
# USER ADMIN
# ============================================================================

@admin.register(User)
class UserAdmin(BaseUserAdmin):
    # List display
    list_display = [
        'username', 'email', 'get_full_name', 'is_online', 
        'last_seen', 'phone_number', 'is_staff', 'date_joined'
    ]
    
    list_filter = [
        'is_staff', 'is_superuser', 'is_active', 'is_online',
        'date_joined', 'last_login'
    ]
    
    search_fields = ['username', 'first_name', 'last_name', 'email', 'phone_number']
    
    ordering = ['-date_joined']
    
    readonly_fields = [
        'id', 'date_joined', 'last_login', 'created_at', 'updated_at',
        'avatar_preview'
    ]
    
    # Custom fieldsets
    fieldsets = (
        ('Thông tin đăng nhập', {
            'fields': ('id', 'username', 'password')
        }),
        ('Thông tin cá nhân', {
            'fields': ('first_name', 'last_name', 'email', 'phone_number', 'date_of_birth', 'bio')
        }),
        ('Hình ảnh', {
            'fields': ('avatar_preview', 'avatar'),
            'classes': ('collapse',)
        }),
        ('Trạng thái', {
            'fields': ('is_online', 'last_seen', 'fcm_token')
        }),
        ('Quyền hạn', {
            'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions'),
            'classes': ('collapse',)
        }),
        ('Thời gian', {
            'fields': ('date_joined', 'last_login', 'created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    add_fieldsets = (
        ('Tạo tài khoản mới', {
            'classes': ('wide',),
            'fields': ('username', 'email', 'password1', 'password2'),
        }),
    )
    
    def avatar_preview(self, obj):
        if obj.avatar:
            # Cloudinary URL với transformation
            avatar_url = obj.avatar.build_url(
                width=100, height=100, crop='fill', gravity='face'
            ) if hasattr(obj.avatar, 'build_url') else obj.avatar.url
            
            return format_html(
                '<img src="{}" width="100" height="100" style="border-radius: 50%; object-fit: cover;" />',
                avatar_url
            )
        return "Chưa có avatar"
    avatar_preview.short_description = "Preview Avatar"

# ============================================================================
# FRIENDSHIP ADMIN  
# ============================================================================

@admin.register(Friendship)
class FriendshipAdmin(admin.ModelAdmin):
    list_display = ['get_friendship_display', 'initiator', 'status', 'created_at']
    list_filter = ['status', 'created_at']
    search_fields = ['user_a__username', 'user_b__username', 'initiator__username']
    readonly_fields = ['id', 'created_at', 'updated_at', 'canonical_display']
    
    fieldsets = (
        ('Friendship Details', {
            'fields': ('id', 'canonical_display', 'user_a', 'user_b', 'initiator', 'status')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    def get_friendship_display(self, obj):
        """Display friendship with direction indicator"""
        direction = "→" if obj.initiator == obj.user_a else "←"
        return f"{obj.user_a.username} {direction} {obj.user_b.username}"
    get_friendship_display.short_description = "Friendship"
    get_friendship_display.admin_order_field = 'user_a__username'
    
    def canonical_display(self, obj):
        """Show canonical ordering explanation"""
        return f"Canonical: {obj.user_a.username} < {obj.user_b.username}"
    canonical_display.short_description = "Canonical Order"
    
    # Custom actions
    actions = ['accept_friendships', 'reject_friendships']
    
    def accept_friendships(self, request, queryset):
        updated = queryset.filter(status='pending').update(status='accepted')
        self.message_user(request, f'Đã chấp nhận {updated} lời mời kết bạn.')
    accept_friendships.short_description = "Chấp nhận các lời mời kết bạn đã chọn"
    
    def reject_friendships(self, request, queryset):
        updated = queryset.filter(status='pending').update(status='rejected')
        self.message_user(request, f'Đã từ chối {updated} lời mời kết bạn.')
    reject_friendships.short_description = "Từ chối các lời mời kết bạn đã chọn"


@admin.register(FriendshipRejection)
class FriendshipRejectionAdmin(admin.ModelAdmin):
    list_display = ['get_friendship_display', 'rejected_by']
    list_filter = ['created_at']
    search_fields = [
        'friendship__user_a__username', 
        'friendship__user_b__username', 
        'rejected_by__username'
    ]
    readonly_fields = ['id', 'created_at', 'updated_at']
    
    fieldsets = (
        ('Rejection Details', {
            'fields': ('id', 'friendship', 'rejected_by')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    def get_friendship_display(self, obj):
        """Display the friendship being rejected"""
        friendship = obj.friendship
        direction = "→" if friendship.initiator == friendship.user_a else "←"
        return f"{friendship.user_a.username} {direction} {friendship.user_b.username}"
    get_friendship_display.short_description = "Friendship"
    get_friendship_display.admin_order_field = 'friendship__user_a__username'
    
    def has_add_permission(self, request):
        """Prevent manual creation - rejections should be created through model logic"""
        return False

# ============================================================================
# GROUP ADMIN
# ============================================================================

class GroupMembershipInline(admin.TabularInline):
    model = GroupMembership
    extra = 1
    fields = ['user', 'role']
    readonly_fields = ['created_at', 'updated_at']
    
    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "user":
            kwargs["queryset"] = User.objects.filter(is_active=True)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

@admin.register(Group)
class GroupAdmin(admin.ModelAdmin):
    list_display = [
        'name', 'admin', 'member_count', 'plan_count', 
        'is_active', 'created_at'
    ]
    list_filter = ['is_active', 'created_at']
    search_fields = ['name', 'description', 'admin__username']
    readonly_fields = ['id', 'created_at', 'updated_at', 'cover_preview']
    
    inlines = [GroupMembershipInline]
    
    fieldsets = (
        ('Thông tin cơ bản', {
            'fields': ('name', 'description', 'admin')
        }),
        ('Hình ảnh', {
            'fields': ('cover_preview', 'cover_image'),
            'classes': ('collapse',)
        }),
        ('Trạng thái', {
            'fields': ('is_active',)
        }),
        ('Thời gian', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    def cover_preview(self, obj):
        if obj.cover_image:
            # Cloudinary URL với transformation
            cover_url = obj.cover_image.build_url(
                width=200, height=100, crop='fill', gravity='center'
            ) if hasattr(obj.cover_image, 'build_url') else obj.cover_image.url
            
            return format_html(
                '<img src="{}" width="200" height="100" style="object-fit: cover;" />',
                cover_url
            )
        return "Chưa có ảnh bìa"
    cover_preview.short_description = "Preview Cover"
    
    def member_count(self, obj):
        count = obj.members.count()
        url = reverse('admin:planpals_groupmembership_changelist') + f'?group__id__exact={obj.id}'
        return format_html('<a href="{}">{} thành viên</a>', url, count)
    member_count.short_description = 'Số thành viên'
    
    def plan_count(self, obj):
        count = obj.plans.count()
        url = reverse('admin:planpals_plan_changelist') + f'?group__id__exact={obj.id}'
        return format_html('<a href="{}">{} kế hoạch</a>', url, count)
    plan_count.short_description = 'Số kế hoạch'

@admin.register(GroupMembership)
class GroupMembershipAdmin(admin.ModelAdmin):
    list_display = ['user', 'group', 'role']
    list_filter = ['role']
    search_fields = ['user__username', 'group__name']
    readonly_fields = ['id', 'created_at', 'updated_at']

# ============================================================================
# PLAN ADMIN
# ============================================================================

class PlanActivityInline(admin.TabularInline):
    model = PlanActivity
    extra = 1
    fields = ['title', 'activity_type', 'start_time', 'end_time', 'estimated_cost', 'order']
    ordering = ['start_time', 'order']

@admin.register(Plan)
class PlanAdmin(admin.ModelAdmin):
    list_display = [
        'title', 'creator', 'group', 'plan_type', 'status', 
        'duration_days', 'activities_count', 'total_cost', 'created_at'
    ]
    list_filter = ['plan_type', 'status', 'is_public', 'created_at']
    search_fields = ['title', 'description', 'creator__username', 'group__name']
    readonly_fields = ['id', 'created_at', 'updated_at']
    
    inlines = [PlanActivityInline]
    
    fieldsets = (
        ('Thông tin cơ bản', {
            'fields': ('title', 'description', 'creator', 'group', 'plan_type')
        }),
        ('Thời gian & Ngân sách', {
            'fields': ('start_date', 'end_date', 'budget')
        }),
        ('Trạng thái', {
            'fields': ('status', 'is_public')
        }),
        ('Thời gian tạo', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    def duration_days(self, obj):
        return f"{obj.duration_days} ngày"
    duration_days.short_description = 'Thời lượng'
    
    def activities_count(self, obj):
        count = obj.activities.count()
        url = reverse('admin:planpals_planactivity_changelist') + f'?plan__id__exact={obj.id}'
        return format_html('<a href="{}">{} hoạt động</a>', url, count)
    activities_count.short_description = 'Số hoạt động'
    
    def total_cost(self, obj):
        total = obj.total_estimated_cost
        if total:
            return f"{total:,.0f} VND"
        return "Chưa ước tính"
    total_cost.short_description = 'Tổng chi phí'

# ============================================================================
# PLAN ACTIVITY ADMIN
# ============================================================================

@admin.register(PlanActivity)
class PlanActivityAdmin(admin.ModelAdmin):
    list_display = [
        'title', 'plan', 'activity_type', 'start_time', 
        'duration_hours', 'estimated_cost', 'has_location'
    ]
    list_filter = ['activity_type', 'start_time', 'created_at']
    search_fields = ['title', 'description', 'location_name', 'plan__title']
    readonly_fields = ['id', 'created_at', 'updated_at']
    
    fieldsets = (
        ('Thông tin cơ bản', {
            'fields': ('plan', 'title', 'description', 'activity_type')
        }),
        ('Thời gian', {
            'fields': ('start_time', 'end_time', 'order')
        }),
        ('Địa điểm', {
            'fields': ('location_name', 'location_address', 'latitude', 'longitude', 'goong_place_id'),
            'classes': ('collapse',)
        }),
        ('Chi phí & Ghi chú', {
            'fields': ('estimated_cost', 'notes')
        }),
        ('Metadata', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    def duration_hours(self, obj):
        if obj.duration_hours:
            return f"{obj.duration_hours:.1f}h"
        return "-"
    duration_hours.short_description = 'Thời lượng'
    
    def has_location(self, obj):
        return "✓" if obj.has_location() else "✗"
    has_location.short_description = 'GPS'
    has_location.boolean = True

# ============================================================================
# CHAT MESSAGE ADMIN
# ============================================================================

@admin.register(ChatMessage)
class ChatMessageAdmin(admin.ModelAdmin):
    list_display = [
        'group', 'sender', 'message_type', 'content_preview', 
        'has_attachment', 'is_deleted', 'created_at'
    ]
    list_filter = ['message_type', 'is_deleted', 'created_at']
    search_fields = ['content', 'group__name', 'sender__username']
    readonly_fields = ['id', 'created_at', 'updated_at', 'attachment_preview']
    
    fieldsets = (
        ('Thông tin cơ bản', {
            'fields': ('group', 'sender', 'message_type', 'content')
        }),
        ('File đính kèm', {
            'fields': ('attachment_preview', 'attachment', 'attachment_name', 'attachment_size'),
            'classes': ('collapse',)
        }),
        ('Vị trí', {
            'fields': ('latitude', 'longitude', 'location_name'),
            'classes': ('collapse',)
        }),
        ('Reply & Status', {
            'fields': ('reply_to', 'is_edited', 'is_deleted')
        }),
        ('Thời gian', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    # Custom widget for content field
    formfield_overrides = {
        models.TextField: {'widget': Textarea(attrs={'rows': 4, 'cols': 80})},
    }
    
    def content_preview(self, obj):
        if obj.is_deleted:
            return "[Tin nhắn đã bị xóa]"
        return obj.content[:100] + '...' if len(obj.content) > 100 else obj.content
    content_preview.short_description = 'Nội dung'
    
    def has_attachment(self, obj):
        return "✓" if obj.has_attachment else "✗"
    has_attachment.short_description = 'File'
    has_attachment.boolean = True
    
    def attachment_preview(self, obj):
        if obj.attachment:
            if obj.message_type == 'image':
                # Cloudinary URL với transformation
                attachment_url = obj.attachment.build_url(
                    width=200, height=150, crop='fill', gravity='center'
                ) if hasattr(obj.attachment, 'build_url') else obj.attachment.url
                
                return format_html(
                    '<img src="{}" width="200" height="150" style="object-fit: cover;" />',
                    attachment_url
                )
            else:
                # Cho file không phải image
                file_url = obj.attachment.build_url() if hasattr(obj.attachment, 'build_url') else obj.attachment.url
                
                return format_html(
                    '<a href="{}" target="_blank">{}</a> ({})',
                    file_url,
                    obj.attachment_name or 'File',
                    obj.get_attachment_size_display() or 'Unknown size'
                )
        return "Không có file"
    attachment_preview.short_description = "Preview File"

@admin.register(MessageReadStatus)
class MessageReadStatusAdmin(admin.ModelAdmin):
    list_display = ['message', 'user', 'read_at']
    list_filter = ['read_at']
    search_fields = ['user__username', 'message__content']
    readonly_fields = ['id', 'created_at', 'updated_at']

# ============================================================================
# ADMIN SITE CUSTOMIZATION
# ============================================================================

# Custom admin site configuration


# Add custom CSS
class PlanPalAdminSite(admin.AdminSite):
    admin.site.site_header = "PlanPal Administration"
    admin.site.site_title = "PlanPal Admin"
    admin.site.index_title = "Welcome to PlanPal Administration"
    
    def each_context(self, request):
        context = super().each_context(request)
        context['custom_style'] = True
        return context

# Replace default admin site if needed
# admin_site = PlanPalAdminSite(name='planpal_admin')
