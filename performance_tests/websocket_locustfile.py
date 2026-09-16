"""Locust WebSocket ping/pong benchmark for PlanPal chat."""

from __future__ import annotations

import json
import os
import time
from urllib.parse import urlparse

from locust import HttpUser, between, events, task
from locust.exception import StopUser
from websocket import WebSocket, WebSocketException, create_connection


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


class PlanPalWebSocketUser(HttpUser):
    wait_time = between(0.5, 1.5)

    token: str
    conversation_id: str
    socket: WebSocket | None = None
    successful_pings: int = 0
    reconnect_every: int = 20

    def on_start(self) -> None:
        try:
            self.reconnect_every = max(
                int(_env("PLANPAL_WS_FORCE_RECONNECT_EVERY", "20")),
                0,
            )
        except ValueError:
            self.reconnect_every = 20
        self.token = _env("PLANPAL_ACCESS_TOKEN") or self._login()
        self.conversation_id = (
            _env("PLANPAL_WS_CONVERSATION_ID") or self._first_conversation_id()
        )
        if not self.conversation_id:
            raise StopUser(
                "WebSocket test needs an accessible conversation. Set "
                "PLANPAL_WS_CONVERSATION_ID or create a conversation for the test user."
            )
        self._connect_socket()

    def on_stop(self) -> None:
        self._close_socket()

    def _login(self) -> str:
        username = _env("PLANPAL_USERNAME")
        password = _env("PLANPAL_PASSWORD")
        client_id = _env("PLANPAL_CLIENT_ID")
        if not all((username, password, client_id)):
            raise StopUser(
                "Set PLANPAL_ACCESS_TOKEN or PLANPAL_USERNAME, "
                "PLANPAL_PASSWORD and PLANPAL_CLIENT_ID."
            )
        payload = {
            "grant_type": "password",
            "username": username,
            "password": password,
            "client_id": client_id,
        }
        client_secret = _env("PLANPAL_CLIENT_SECRET")
        if client_secret:
            payload["client_secret"] = client_secret
        response = self.client.post("/o/token/", json=payload, name="AUTH /o/token/")
        if response.status_code != 200 or not response.json().get("access_token"):
            raise StopUser("OAuth login failed for WebSocket load test.")
        return str(response.json()["access_token"])

    def _first_conversation_id(self) -> str:
        response = self.client.get(
            "/api/v1/conversations/",
            headers={"Authorization": f"Bearer {self.token}"},
            name="SETUP /api/v1/conversations/",
        )
        if response.status_code != 200:
            raise StopUser("Could not load conversations for WebSocket test.")
        items = response.json().get("conversations", [])
        return str(items[0]["id"]) if items else ""

    def _socket_url(self) -> str:
        parsed = urlparse(self.host)
        scheme = "wss" if parsed.scheme == "https" else "ws"
        return (
            f"{scheme}://{parsed.netloc}/ws/chat/{self.conversation_id}/"
            f"?token={self.token}"
        )

    def _connect_socket(self) -> None:
        started = time.perf_counter()
        try:
            self.socket = create_connection(self._socket_url(), timeout=10)
            events.request.fire(
                request_type="WS",
                name="connect /ws/chat/{conversation_id}/",
                response_time=(time.perf_counter() - started) * 1000,
                response_length=0,
                exception=None,
            )
        except Exception as exc:
            events.request.fire(
                request_type="WS",
                name="connect /ws/chat/{conversation_id}/",
                response_time=(time.perf_counter() - started) * 1000,
                response_length=0,
                exception=exc,
            )
            self.socket = None
            raise StopUser("WebSocket connection failed.") from exc

    def _close_socket(self) -> None:
        if self.socket is not None:
            try:
                self.socket.close()
            except WebSocketException:
                pass
        self.socket = None

    @task
    def ping_pong_latency(self) -> None:
        if self.socket is None or not self.socket.connected:
            self._connect_socket()

        started = time.perf_counter()
        response_length = 0
        try:
            self.socket.send(json.dumps({"type": "ping", "data": {}}))
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                raw = self.socket.recv()
                response_length += len(raw or "")
                payload = json.loads(raw)
                if payload.get("type") == "pong":
                    break
            else:
                raise TimeoutError("No pong received within 5 seconds")

            events.request.fire(
                request_type="WS",
                name="ping/pong chat latency",
                response_time=(time.perf_counter() - started) * 1000,
                response_length=response_length,
                exception=None,
            )
            self.successful_pings += 1
            if (
                self.reconnect_every > 0
                and self.successful_pings % self.reconnect_every == 0
            ):
                # The next task iteration must establish a fresh authenticated
                # socket, exercising reconnect behavior during the load test.
                self._close_socket()
        except Exception as exc:
            events.request.fire(
                request_type="WS",
                name="ping/pong chat latency",
                response_time=(time.perf_counter() - started) * 1000,
                response_length=response_length,
                exception=exc,
            )
            self._close_socket()
