from collections.abc import Callable

from django.db import DatabaseError, connection
from django.http import (
    HttpRequest,
    HttpResponse,
    HttpResponseNotAllowed,
    JsonResponse,
)


class HealthCheckMiddleware:
    def __init__(
        self,
        get_response: Callable[[HttpRequest], HttpResponse],
    ) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        if request.path not in {"/health/live/", "/health/ready/"}:
            return self.get_response(request)

        if request.method not in {"GET", "HEAD"}:
            response = HttpResponseNotAllowed(["GET", "HEAD"])
        elif request.path == "/health/live/":
            response = JsonResponse({"status": "alive"})
        else:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT 1")
                    cursor.fetchone()
            except DatabaseError:
                response = JsonResponse(
                    {"status": "not_ready"},
                    status=503,
                )
            else:
                response = JsonResponse({"status": "ready"})

        response["Cache-Control"] = "no-store"
        return response
