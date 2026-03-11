from rest_framework.permissions import BasePermission, SAFE_METHODS
from django.contrib.auth import get_user_model

from planpals.models import Plan, Group
from planpals.groups.application.services import GroupService
from planpals.plans.application.services import PlanService

User = get_user_model()


class PlanPermission(BasePermission):
    def has_permission(self, request, view):
        if request.method == 'POST':
            plan_type = request.data.get('plan_type', 'personal')
            group_id = request.data.get('group_id')
            
            if plan_type == 'group' and group_id:
                try:
                    group = Group.objects.get(id=group_id)
                    return GroupService.can_edit_group(group, request.user)
                except Group.DoesNotExist:
                    return False
            return True
        return True 
    
    def has_object_permission(self, request, view, obj):
        user = request.user
                
        if obj.creator == user:
            return True
        
        if request.method in SAFE_METHODS:
            return PlanService.can_view_plan(obj, user)
        else:
            return PlanService.can_edit_plan(obj, user)


class PlanActivityPermission(BasePermission):
    def has_permission(self, request, view):
        if request.method == 'POST':
            plan_id = request.data.get('plan')
            if plan_id:
                try:
                    plan = Plan.objects.select_related('group').get(id=plan_id)
                    if plan.is_group_plan():
                        return plan.group.is_admin(request.user)
                    else:
                        return plan.creator == request.user
                except Plan.DoesNotExist:
                    return False
        return True  
    
    def has_object_permission(self, request, view, obj):
        user = request.user
        plan = obj.plan
        
        if not self._can_access_plan(user, plan):
            return False
        
        if request.method in SAFE_METHODS:
            return True
        elif request.method in ['PUT', 'PATCH', 'DELETE']:
            return self._can_modify_activity(user, plan)
        
        return False
    
    def _can_access_plan(self, user, plan):
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_member(user)
        
        return False
    
    def _can_modify_activity(self, user, plan):
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_admin(user)
        
        return False


class CanJoinPlan(BasePermission):
    """Allow joining a plan only if it is public or the group is public."""
    
    def has_object_permission(self, request, view, obj):
        plan = obj
        user = request.user
        
        # Creator cannot "join" their own plan
        if plan.creator == user:
            return False
        
        if plan.plan_type == 'group' and plan.group:
            # Already a member — cannot join again
            if plan.group.members.filter(id=user.id).exists():
                return False
            # Only allow joining public groups
            return getattr(plan.group, 'is_public', False)
        
        return plan.is_public


class CanAccessPlan(BasePermission):
    
    def has_object_permission(self, request, view, obj):
        plan = obj
        user = request.user
        
        if plan.creator == user:
            return True
        
        if plan.plan_type == 'group' and plan.group:
            return plan.group.is_member(user)
        
        return False


class CanModifyPlan(BasePermission):
    """Only plan creator or group admin can modify a plan."""
    
    def has_object_permission(self, request, view, obj):
        plan = obj
        user = request.user
        
        if plan.creator == user:
            return True
        
        if plan.plan_type == 'group' and plan.group:
            return plan.group.is_admin(user)
        
        return False


