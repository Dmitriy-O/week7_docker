import os
from copy import deepcopy

from django.core.exceptions import ImproperlyConfigured

from . import settings as _base
from .settings import *  # noqa: F403

DEBUG = False

MIDDLEWARE = [
    "hc.health.HealthCheckMiddleware",
    *_base.MIDDLEWARE,
]

DATABASES = deepcopy(_base.DATABASES)

if DATABASES["default"]["ENGINE"] != "django.db.backends.postgresql":
    raise ImproperlyConfigured(
        "Kubernetes settings require PostgreSQL. Set DB=postgres."
    )

DATABASES["default"]["OPTIONS"]["connect_timeout"] = int(
    os.getenv("DB_CONNECT_TIMEOUT", "3")
)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "plain": {
            "format": "{asctime} {levelname} {name} {message}",
            "style": "{",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "stream": "ext://sys.stderr",
            "formatter": "plain",
        },
    },
    "root": {
        "handlers": ["console"],
        "level": "INFO",
    },
    "loggers": {
        "django": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": False,
        },
        "hc": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": False,
        },
    },
}
