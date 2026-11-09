import base64
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

import service


class CredentialTests(unittest.IsolatedAsyncioTestCase):
    async def test_file_credential_and_private_state_survive_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "token"
            self.assertEqual(service.private_file(path, "saved-token"), "saved-token")
            self.assertEqual(service.private_file(path, "replacement"), "saved-token")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual((await service.credential_response({"file": str(path)}))["access_token"], "saved-token")

    async def test_identity_token_uses_its_actual_expiry(self):
        payload = base64.urlsafe_b64encode(json.dumps({"exp": int(time.time()) + 1800}).encode()).decode().rstrip("=")
        token = f"header.{payload}.signature"
        result = await service.credential_response({"command": [sys.executable, "-c", f"print({token!r})"]})
        self.assertEqual(result["access_token"], token)
        self.assertTrue(1790 <= result["expires_in"] <= 1800)

    async def test_expired_or_failed_generators_cannot_supply_credentials(self):
        payload = base64.urlsafe_b64encode(b'{"exp": 1}').decode().rstrip("=")
        with self.assertRaises(ValueError):
            await service.credential_response({"command": [sys.executable, "-c", f"print('header.{payload}.signature')"]})
        with self.assertRaises(RuntimeError):
            await service.credential_response({"command": [sys.executable, "-c", "raise SystemExit(1)"]})


class HelperTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.state = Path(directory.name)
        state = patch.object(service, "STATE", self.state)
        state.start()
        self.addCleanup(state.stop)
        self.config = {
            "serverPort": 14321, "proxyPort": 14322, "credentialPort": 14323,
            "noProxy": ["127.0.0.1", "::1", "llmproxy.tristanmayo.com"],
            "credentials": {"TOKEN": {"file": str(self.state / "upstream-token")}},
            "services": {"executor": {"target": "http://executor.localhost:4788/mcp", "headers": {}}},
        }
        self.helper = service.CredentialHelper(self.config)
        app = web.Application(middlewares=[service.local_request])
        app.router.add_post("/token", self.helper.token)
        app.router.add_get("/health", self.helper.health)
        self.client = TestClient(TestServer(app))
        await self.client.start_server()
        self.addAsyncCleanup(self.client.close)

    async def test_credential_endpoint_requires_its_capability_and_fixed_key(self):
        for key, token in [("TOKEN", "wrong"), ("ARBITRARY_COMMAND", self.helper.refresh_token)]:
            response = await self.client.post("/token", data={"grant_type": "refresh_token", "client_id": key, "refresh_token": token})
            self.assertEqual(response.status, 401)
        response = await self.client.post("/token", data={
            "grant_type": "refresh_token", "client_id": "TOKEN", "refresh_token": self.helper.refresh_token,
        })
        result = await response.json()
        self.assertEqual(result["expires_in"], 1)
        self.assertEqual(result["access_token"], "pending-initialization")
        (self.state / "upstream-token").write_text("real-file-token")
        self.helper.bootstrapping = False
        response = await self.client.post("/token", data={
            "grant_type": "refresh_token", "client_id": "TOKEN", "refresh_token": self.helper.refresh_token,
        })
        self.assertEqual((await response.json())["access_token"], "real-file-token")
        self.assertEqual(response.headers["Cache-Control"], "no-store")

    async def test_helper_has_no_mcp_forwarding_endpoint(self):
        for path, headers, status in [
            ("/token", {"Origin": "https://example.com"}, 403),
            ("/token", {"Host": "attacker.example"}, 403),
            ("/executor", {}, 404),
            ("/payload-production", {}, 404),
        ]:
            response = await self.client.post(path, headers=headers)
            self.assertEqual(response.status, status)
            await response.read()

    async def test_health_only_reports_ready_after_provisioning(self):
        self.assertEqual((await self.client.get("/health")).status, 503)
        self.helper.ready = True
        self.assertEqual((await self.client.get("/health")).status, 200)

    async def test_network_proxy_environment_and_ca_are_private_and_exclude_model_proxy(self):
        environment = service.client_environment(self.config, "test-capability", self.state / "ca.pem")
        self.assertEqual(environment["HTTP_PROXY"], "http://test-capability:dotfiles@127.0.0.1:14322")
        self.assertEqual(environment["HTTPS_PROXY"], environment["HTTP_PROXY"])
        self.assertEqual(environment["http_proxy"], environment["HTTP_PROXY"])
        self.assertEqual(environment["no_proxy"], environment["NO_PROXY"])
        self.assertNotIn("localhost", environment["NO_PROXY"].split(","))
        self.assertIn("llmproxy.tristanmayo.com", environment["NO_PROXY"].split(","))
        self.assertEqual(environment["CODEX_CA_CERTIFICATE"], str(self.state / "ca.pem"))
        self.assertNotIn("EXECUTOR_MCP_URL", environment)
        self.assertNotIn("CODEX_EXECUTOR_CONFIG", environment)
        service.publish_environment(environment)
        path = self.state / "proxy.env"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertFalse((self.state / "proxy.env.tmp").exists())

    async def test_helper_restart_preserves_the_existing_proxy_token(self):
        (self.state / "proxy-token").write_text("existing-client-token")
        self.config["services"]["executor"]["headers"] = {"Authorization": "Bearer {{ TOKEN }}"}
        self.config["services"]["public-mcp"] = {"target": "https://public.example/mcp"}
        async def api(method, path, *args, **kwargs):
            if path == "/v1/status":
                return {"initialized": True}
            if path == "/v1/auth/login":
                return {"token": "owner-test-token"}
            if path == "/v1/auth/me":
                return {"agent_name": "coding-agents"}
            return {}
        self.helper.api = AsyncMock(side_effect=api)
        response = MagicMock()
        response.text = AsyncMock(return_value="test-ca-certificate")
        context = MagicMock()
        context.__aenter__ = AsyncMock(return_value=response)
        context.__aexit__ = AsyncMock(return_value=None)
        self.helper.client = MagicMock()
        self.helper.client.get.return_value = context
        await self.helper.bootstrap()
        self.assertEqual((self.state / "proxy-token").read_text(), "existing-client-token")
        paths = [call.args[1] for call in self.helper.api.call_args_list]
        self.assertNotIn("/v1/agents", paths)
        self.assertFalse(any("/rotate" in path for path in paths))
        self.assertTrue(self.helper.ready)
        self.assertIn("existing-client-token", (self.state / "proxy.env").read_text())
        services = next(call.args[2]["services"] for call in self.helper.api.call_args_list if call.args[1].endswith("/services"))
        self.assertEqual(services[0]["auth"], {"type": "custom", "headers": {"Authorization": "Bearer {{ TOKEN }}"}})
        self.assertEqual(services[1]["auth"], {"type": "passthrough"})


if __name__ == "__main__":
    unittest.main()
