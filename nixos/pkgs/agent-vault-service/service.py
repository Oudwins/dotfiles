"""Credential endpoint and unattended provisioning for Agent Vault."""

import argparse
import asyncio
import base64
import contextlib
import hmac
import json
import logging
import os
from pathlib import Path
import secrets
import signal
import shlex
from string import Template
import sys
import time

import aiohttp
from aiohttp import web
from yarl import URL


STATE = Path.home() / ".agent-vault"
VAULT = "dotfiles"
OWNER = "tmx@agent-vault.local"


def private_file(path, content):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return path.read_text().strip()
    with os.fdopen(descriptor, "w") as file:
        file.write(content)
    return content


def load_config(path):
    config = json.loads(Template(Path(path).read_text()).substitute(os.environ))
    for entry in config["services"].values():
        target = URL(entry["target"])
        if target.scheme not in {"http", "https"} or not target.host or target.user or target.fragment:
            raise ValueError("Service targets must be HTTP URLs without credentials or fragments")
    return config


def start_server(config):
    password = STATE / "master-password"
    private_file(password, secrets.token_urlsafe(48))
    with password.open() as file:
        os.dup2(file.fileno(), 0)
    os.execvp("agent-vault", [
        "agent-vault", "server", "--password-stdin", "--host", "127.0.0.1",
        "--port", str(config["serverPort"]), "--mitm-port", str(config["proxyPort"]),
    ])


async def credential_response(spec):
    if "file" in spec:
        token = Path(spec["file"]).expanduser().read_text().strip()
        lifetime = 3600
    else:
        process = await asyncio.create_subprocess_exec(
            *spec["command"], stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            stdout, _ = await asyncio.wait_for(process.communicate(), timeout=25)
        except (TimeoutError, asyncio.CancelledError):
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            await process.wait()
            raise
        if process.returncode:
            raise RuntimeError("Credential command failed; check gcloud authentication")
        token = stdout.decode().strip()
        claims = json.loads(base64.urlsafe_b64decode(token.split(".")[1] + "=="))
        lifetime = int(claims["exp"] - time.time())
    if not token or any(character.isspace() for character in token) or lifetime <= 300:
        raise ValueError("Credential is empty, invalid, or expires too soon")
    return {"access_token": token, "token_type": "Bearer", "expires_in": lifetime}


@web.middleware
async def local_request(request, handler):
    if request.url.host not in {"127.0.0.1", "localhost"} or "Origin" in request.headers:
        raise web.HTTPForbidden()
    return await handler(request)


def client_environment(config, token, certificate):
    proxy = URL(f"http://127.0.0.1:{config['proxyPort']}").with_user(token).with_password(VAULT)
    environment = {
        "HTTP_PROXY": str(proxy), "HTTPS_PROXY": str(proxy),
        "NO_PROXY": ",".join(config["noProxy"]),
        "NODE_USE_ENV_PROXY": "1",
    }
    for name in ["HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY"]:
        environment[name.lower()] = environment[name]
    for name in ["SSL_CERT_FILE", "CODEX_CA_CERTIFICATE", "NODE_EXTRA_CA_CERTS", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "GIT_SSL_CAINFO", "DENO_CERT"]:
        environment[name] = str(certificate)
    return environment


def publish_environment(environment):
    destination = STATE / "proxy.env"
    temporary = STATE / "proxy.env.tmp"
    with temporary.open("w") as file:
        os.chmod(temporary, 0o600)
        file.write("".join(f"export {name}={shlex.quote(value)}\n" for name, value in environment.items()))
    temporary.replace(destination)


class CredentialHelper:
    def __init__(self, config):
        self.config = config
        self.address = f"http://127.0.0.1:{config['serverPort']}"
        self.password = private_file(STATE / "owner-password", secrets.token_urlsafe(48))
        self.refresh_token = private_file(STATE / "credential-token", secrets.token_urlsafe(48))
        self.bootstrapping = True
        self.ready = False

    async def api(self, method, path, payload=None, token=None, allowed=(200, 201)):
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        async with self.client.request(
            method, self.address + path, json=payload, headers=headers,
            timeout=aiohttp.ClientTimeout(total=30),
        ) as response:
            if response.status not in allowed:
                raise RuntimeError(f"Agent Vault {method} {path} returned HTTP {response.status}")
            return await response.json()

    async def token(self, request):
        form = await request.post()
        key = form.get("client_id", "")
        if form.get("grant_type") != "refresh_token" or not hmac.compare_digest(
            form.get("refresh_token", ""), self.refresh_token,
        ) or key not in self.config["credentials"]:
            raise web.HTTPUnauthorized()
        # Provision refresh metadata without requiring gcloud or SOPS at startup.
        # The one-second expiry forces a real refresh before the first request.
        if self.bootstrapping:
            return web.json_response({"access_token": "pending-initialization", "expires_in": 1})
        try:
            result = await credential_response(self.config["credentials"][key])
        except Exception:
            logging.error("Credential generation failed for %s", key)
            raise web.HTTPBadGateway(text="Credential generation failed; check service logs and gcloud authentication")
        return web.json_response(result, headers={"Cache-Control": "no-store"})

    async def bootstrap(self):
        deadline = time.monotonic() + 60
        while True:
            try:
                status = await self.api("GET", "/v1/status")
                break
            except (aiohttp.ClientError, TimeoutError):
                if time.monotonic() >= deadline:
                    raise RuntimeError("Agent Vault did not become ready")
                await asyncio.sleep(1)
        credentials = {"email": OWNER, "password": self.password, "device_label": "dotfiles-service"}
        login = await self.api("POST", "/v1/auth/login" if status["initialized"] else "/v1/auth/register", credentials)
        owner = login["token"]
        await self.api("PUT", "/v1/admin/settings", {"invite_only": True}, owner)
        await self.api("POST", "/v1/vaults", {"name": VAULT}, owner, allowed=(201, 409))
        await self.api("PATCH", f"/v1/vaults/{VAULT}/settings", {"unmatched_host_policy": "passthrough"}, owner)
        for key in self.config["credentials"]:
            await self.api("POST", "/v1/credentials/oauth/tokens", {
                "vault": VAULT, "key": key, "client_id": key,
                "token_url": f"http://127.0.0.1:{self.config['credentialPort']}/token",
                "refresh_token": self.refresh_token,
            }, owner)
        services = [{
            "name": name,
            "host": str(URL(route["target"]).origin()).split("://", 1)[1],
            "path": URL(route["target"]).path.rstrip("/") + "*",
            "auth": {"type": "custom", "headers": route["headers"]} if route.get("headers") else {"type": "passthrough"},
        } for name, route in self.config["services"].items()]
        await self.api("PUT", f"/v1/vaults/{VAULT}/services", {"services": services}, owner)
        token_path = STATE / "proxy-token"
        token = token_path.read_text().strip() if token_path.exists() else None
        if token:
            identity = await self.api("GET", "/v1/auth/me", token=token, allowed=(200, 401))
            if identity.get("agent_name") != "coding-agents":
                token = None
        if not token:
            agent = await self.api("POST", "/v1/agents", {
                "name": "coding-agents", "vaults": [{"vault_name": VAULT, "vault_role": "proxy"}],
            }, owner, allowed=(201, 409))
            if "av_agent_token" not in agent:
                agent = await self.api("POST", "/v1/agents/coding-agents/rotate", {}, owner)
            token = agent["av_agent_token"]
            token_path.write_text(token)
            token_path.chmod(0o600)
        async with self.client.get(self.address + "/v1/mitm/ca.pem") as response:
            response.raise_for_status()
            certificate = await response.text()
        certificate_path = STATE / "ca.pem"
        certificate_path.write_text(certificate)
        publish_environment(client_environment(self.config, token, certificate_path))
        self.bootstrapping = False
        self.ready = True
        logging.info("Agent Vault configured for direct network proxy use with %d services", len(services))

    async def health(self, request):
        return web.json_response({"ready": self.ready}, status=200 if self.ready else 503)

    async def run(self):
        async with aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=None, connect=10),
            auto_decompress=False, trust_env=False,
        ) as self.client:
            provider = web.Application(middlewares=[local_request])
            provider.router.add_post("/token", self.token)
            provider.router.add_get("/health", self.health)
            provider_runner = web.AppRunner(provider, access_log=None)
            await provider_runner.setup()
            await web.TCPSite(provider_runner, "127.0.0.1", self.config["credentialPort"]).start()
            try:
                await self.bootstrap()
                stopped = asyncio.Event()
                for signum in (signal.SIGINT, signal.SIGTERM):
                    asyncio.get_running_loop().add_signal_handler(signum, stopped.set)
                await stopped.wait()
            finally:
                await provider_runner.cleanup()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["server", "credentials"])
    parser.add_argument("--config", default=str(Path.home() / ".config/agent-vault/config.json"))
    args = parser.parse_args()
    os.umask(0o077)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    config = load_config(args.config)
    if args.mode == "server":
        start_server(config)
    else:
        asyncio.run(CredentialHelper(config).run())


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        logging.error("%s: %s", type(error).__name__, error)
        sys.exit(1)
