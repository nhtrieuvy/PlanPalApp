from enum import Enum


class AvailabilityStatus(str, Enum):
    AVAILABLE = 'available'
    MAYBE = 'maybe'
    UNAVAILABLE = 'unavailable'

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(item.value for item in cls)


class WorkItemType(str, Enum):
    TASK = 'task'
    CHECKLIST = 'checklist'

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(item.value for item in cls)


class WorkItemStatus(str, Enum):
    TODO = 'todo'
    IN_PROGRESS = 'in_progress'
    DONE = 'done'

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(item.value for item in cls)


ALLOWED_REACTIONS = ('like', 'love', 'celebrate', 'helpful')
