from django.apps import AppConfig


class PlanpalsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'planpals'

    def ready(self):
        # Chat signals kept — no domain event handler for chat realtime yet
        import planpals.chat.infrastructure.signals  # noqa: F401

        # Register domain event handlers (Clean Architecture event wiring)
        # These replace the old signals for plans, groups, and auth
        from planpals.plans.infrastructure.event_handlers import register_plan_event_handlers
        from planpals.groups.infrastructure.event_handlers import register_group_event_handlers
        from planpals.auth.infrastructure.event_handlers import register_auth_event_handlers

        register_plan_event_handlers()
        register_group_event_handlers()
        register_auth_event_handlers()
