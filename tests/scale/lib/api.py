"""Forgejo API client. Tokens stay in files. List calls are paged.

Forgejo returns at most 50 items per page. Follow pages until a short page,
or until the item is found.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from collections.abc import Callable
from typing import Any

from paths import PAGE_LIMIT, base_url, read_secret
from proc import scrub


class ApiError(RuntimeError):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code


Transport = Callable[[str, str, dict[str, str], bytes | None], tuple[int, bytes]]


def urllib_transport(method: str, url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except urllib.error.URLError as exc:
        raise ApiError(0, "host unreachable") from exc


class Client:
    def __init__(
        self,
        token_file,
        *,
        url: str | None = None,
        transport: Transport | None = None,
        secrets: list[str] | None = None,
    ) -> None:
        self.token_file = token_file
        self.url = (url or base_url()).rstrip("/")
        self.transport = transport or urllib_transport
        self.secrets = list(secrets or [])

    def _token(self) -> str:
        token = read_secret(self.token_file)
        if token and token not in self.secrets:
            self.secrets.append(token)
        return token

    def request(self, method: str, path: str, body: dict[str, Any] | None = None) -> tuple[int, Any]:
        token = self._token()
        headers = {
            "Authorization": "token " + token,
            "Accept": "application/json",
        }
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        code, raw = self.transport(method, self.url + path, headers, data)
        if not raw:
            return code, None
        text = raw.decode("utf-8", errors="replace")
        try:
            return code, json.loads(text)
        except json.JSONDecodeError:
            return code, {"message": scrub(text, self.secrets)[:200]}

    def message(self, payload: Any) -> str:
        if isinstance(payload, dict):
            return scrub(str(payload.get("message") or ""), self.secrets)
        return ""

    def list_all(self, path: str, *, limit: int = PAGE_LIMIT) -> list[dict[str, Any]]:
        """Follow pages until a short page. Never ask for more than one page at a time."""
        if limit < 1 or limit > PAGE_LIMIT:
            raise ValueError("page size must be 1 to 50")
        found: list[dict[str, Any]] = []
        page = 1
        while page <= 400:
            code, payload = self.request("GET", self._paged(path, limit, page))
            if code != 200 or not isinstance(payload, list):
                raise ApiError(code, "list failed")
            found.extend(item for item in payload if isinstance(item, dict))
            if len(payload) < limit:
                return found
            page += 1
        raise ApiError(0, "too many pages")

    def find(self, path: str, match: Callable[[dict[str, Any]], bool], *, limit: int = PAGE_LIMIT) -> dict[str, Any] | None:
        """Follow pages until the item is found or a short page ends the list."""
        if limit < 1 or limit > PAGE_LIMIT:
            raise ValueError("page size must be 1 to 50")
        page = 1
        while page <= 400:
            code, payload = self.request("GET", self._paged(path, limit, page))
            if code != 200 or not isinstance(payload, list):
                raise ApiError(code, "list failed")
            for item in payload:
                if isinstance(item, dict) and match(item):
                    return item
            if len(payload) < limit:
                return None
            page += 1
        raise ApiError(0, "too many pages")

    @staticmethod
    def _paged(path: str, limit: int, page: int) -> str:
        join = "&" if "?" in path else "?"
        return f"{path}{join}limit={limit}&page={page}"
