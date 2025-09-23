"""Minimal Locust test plan used for module validation and demos.

The test issues a GET request against ``/health`` on the configured host to
exercise the HTTP client path without needing a complex backend. Adjust or
extend the tasks when integrating with a real API.
"""

from locust import HttpUser, between, task


class DemoUser(HttpUser):
    wait_time = between(1, 3)

    @task
    def hit_health_endpoint(self) -> None:
        self.client.get("/health")
