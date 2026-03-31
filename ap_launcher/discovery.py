from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import requests


@dataclass(frozen=True)
class HarborRepo:
    repo: str
    tag: str


class HarborClient:
    """Minimal Harbor v2 API client (project-scoped)."""

    def __init__(
        self, base_url: str, project: str, username: str | None, password: str | None
    ):
        self.base_url = base_url.rstrip("/")
        self.project = project
        self.session = requests.Session()
        if username and password:
            self.session.auth = (username, password)

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def list_repositories(self) -> list[str]:
        # GET /api/v2.0/projects/{project_name}/repositories
        url = self._url(f"/api/v2.0/projects/{self.project}/repositories")
        repos: list[str] = []
        page = 1
        page_size = 100

        while True:
            resp = self.session.get(
                url, params={"page": page, "page_size": page_size}, timeout=15
            )
            resp.raise_for_status()
            data = resp.json()
            if not isinstance(data, list):
                raise RuntimeError(
                    f"Unexpected Harbor response for repositories: {type(data)}"
                )

            for item in data:
                name = item.get("name")
                if isinstance(name, str):
                    # Harbor returns '<project>/<repo>'
                    repos.append(name)

            if len(data) < page_size:
                break
            page += 1

        return repos

    def list_artifacts(
        self, repository: str, *, with_tag: bool = True
    ) -> list[dict[str, Any]]:
        # GET /api/v2.0/projects/{project}/repositories/{repository_name}/artifacts
        # repository_name is the repository without the '<project>/' prefix.
        repo_short = repository
        prefix = f"{self.project}/"
        if repo_short.startswith(prefix):
            repo_short = repo_short[len(prefix) :]

        url = self._url(
            f"/api/v2.0/projects/{self.project}/repositories/{repo_short}/artifacts"
        )

        artifacts: list[dict[str, Any]] = []
        page = 1
        page_size = 100

        while True:
            resp = self.session.get(
                url,
                params={
                    "page": page,
                    "page_size": page_size,
                    "with_tag": str(with_tag).lower(),
                },
                timeout=15,
            )
            resp.raise_for_status()
            data = resp.json()
            if not isinstance(data, list):
                raise RuntimeError(
                    f"Unexpected Harbor response for artifacts: {type(data)}"
                )

            for item in data:
                if isinstance(item, dict):
                    artifacts.append(item)

            if len(data) < page_size:
                break
            page += 1

        return artifacts

    def list_latest_apps(self) -> list[HarborRepo]:
        """Return one entry per repo for tag 'latest' if present."""
        apps: list[HarborRepo] = []
        for repo in self.list_repositories():
            try:
                artifacts = self.list_artifacts(repo, with_tag=True)
            except requests.HTTPError:
                # Skip repos we cannot read
                continue

            for art in artifacts:
                tags = art.get("tags")
                if not isinstance(tags, list):
                    continue
                if any(isinstance(t, dict) and t.get("name") == "latest" for t in tags):
                    apps.append(HarborRepo(repo=repo, tag="latest"))
                    break

        apps.sort(key=lambda a: a.repo)
        return apps
