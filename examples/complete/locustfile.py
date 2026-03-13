from __future__ import annotations

import uuid
from typing import Any

from faker import Faker
from locust import HttpUser
from locust import between
from locust import task

fake = Faker()
ALLOWED_GENDERS = ("Male", "Female", "Other")


class PersonaChatUser(HttpUser):
    """
    Locust user that exercises the end-to-end persona chat journey:
    register -> login -> create persona -> send chat message -> fetch chat instance.
    """

    wait_time = between(1, 2)

    def _post(
        self,
        path: str,
        *,
        name: str,
        json: dict[str, Any],
        headers: dict[str, str] | None = None,
    ) -> dict[str, Any] | None:
        request_headers = {"Content-Type": "application/json"}
        if headers:
            request_headers.update(headers)

        with self.client.post(
            path,
            json=json,
            headers=request_headers,
            name=name,
            catch_response=True,
        ) as response:
            if response.status_code >= 400:
                response.failure(f"{response.status_code}: {response.text}")
                return None
            try:
                data = response.json()
            except ValueError:
                response.failure("Response was not valid JSON")
                return None
            response.success()
            return data

    def _get(
        self,
        path: str,
        *,
        name: str,
        headers: dict[str, str],
    ) -> dict[str, Any] | None:
        with self.client.get(
            path,
            headers=headers,
            name=name,
            catch_response=True,
        ) as response:
            if response.status_code >= 400:
                response.failure(f"{response.status_code}: {response.text}")
                return None
            try:
                data = response.json()
            except ValueError:
                response.failure("Response was not valid JSON")
                return None
            response.success()
            return data

    def _generate_credentials(self) -> tuple[str, str, str]:
        username = fake.user_name()
        email = f"{username}.{uuid.uuid4().hex[:8]}@example.com"
        password = fake.password(length=12)
        return username, email, password

    def _register_user(self) -> tuple[str, str, dict[str, Any]] | None:
        username, email, password = self._generate_credentials()
        payload = {"username": username, "email": email, "password": password}
        data = self._post(
            "/api/v1/auth/signup",
            name="auth:signup",
            json=payload,
        )
        if data is None:
            return None
        return email, password, data

    def _login(self, email: str, password: str) -> str | None:
        payload = {"email": email, "password": password}
        data = self._post(
            "/api/v1/auth/login",
            name="auth:login",
            json=payload,
        )
        if not data:
            return None
        token = data.get("access_token")
        if not token:
            return None
        return token

    def _create_persona(self, auth_headers: dict[str, str]) -> dict[str, Any] | None:
        payload = {
            "name": fake.name(),
            "age": fake.random_int(min=18, max=85),
            "gender": fake.random_element(elements=ALLOWED_GENDERS),
            "status": fake.job(),
            "tech": fake.catch_phrase(),
            "character": fake.paragraph(nb_sentences=1),
            "goals": fake.sentence(nb_words=8),
            "motivations": fake.sentence(nb_words=6),
            "pain_points": fake.sentence(nb_words=7),
            "postcode": fake.postcode(),
        }
        return self._post(
            "/api/v1/personas/",
            name="personas:create",
            json=payload,
            headers=auth_headers,
        )

    def _send_chat_message(
        self,
        auth_headers: dict[str, str],
        persona_id: int,
        *,
        chat_instance_id: int | None = None,
        user_query: str | None = None,
    ) -> dict[str, Any] | None:
        payload = {
            "persona_id": persona_id,
            "user_query": user_query or fake.sentence(nb_words=12),
        }
        if chat_instance_id is not None:
            payload["chat_instance_id"] = chat_instance_id
        return self._post(
            "/api/v1/chat/message",
            name="chat:message",
            json=payload,
            headers=auth_headers,
        )

    def _fetch_chat_instance(
        self,
        auth_headers: dict[str, str],
        chat_instance_id: int,
    ) -> dict[str, Any] | None:
        return self._get(
            f"/api/v1/chat/instances/{chat_instance_id}",
            name="chat:instance:get",
            headers=auth_headers,
        )

    @task
    def persona_chat_flow(self) -> None:
        user = self._register_user()
        if user is None:
            return

        email, password, _user_payload = user
        token = self._login(email, password)
        if not token:
            return

        auth_headers = {"Authorization": f"Bearer {token}"}

        persona = self._create_persona(auth_headers)
        if not persona:
            return

        persona_id = persona.get("id")
        if not isinstance(persona_id, int):
            return

        chat_response = self._send_chat_message(
            auth_headers,
            persona_id,
            user_query=fake.sentence(nb_words=10),
        )
        if not chat_response:
            return

        chat_instance_id = chat_response.get("chat_instance_id")
        if not isinstance(chat_instance_id, int):
            return

        follow_up = self._send_chat_message(
            auth_headers,
            persona_id,
            chat_instance_id=chat_instance_id,
            user_query=fake.sentence(nb_words=14),
        )
        if not follow_up:
            return

        self._fetch_chat_instance(auth_headers, chat_instance_id)
