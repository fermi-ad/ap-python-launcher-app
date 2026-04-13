from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
import requests

from ap_launcher.discovery import HarborClient, HarborRepo


def _make_response(data, status_code=200, raise_http_error=False):
    """Build a mock requests.Response."""
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = data
    if raise_http_error:
        resp.raise_for_status.side_effect = requests.HTTPError("HTTP error")
    else:
        resp.raise_for_status.return_value = None
    return resp


@pytest.fixture
def client_no_auth():
    return HarborClient("https://harbor.example.com", "myproject", None, None)


@pytest.fixture
def client_with_auth():
    return HarborClient("https://harbor.example.com", "myproject", "user", "pass")


# --- Constructor / session setup ---


def test_no_auth_session_has_no_auth(client_no_auth):
    assert client_no_auth.session.auth is None


def test_auth_credentials_set_on_session(client_with_auth):
    assert client_with_auth.session.auth == ("user", "pass")


def test_trailing_slash_stripped_from_base_url():
    c = HarborClient("https://harbor.example.com/", "proj", None, None)
    assert c.base_url == "https://harbor.example.com"


# --- list_repositories ---


def test_list_repositories_single_page(mocker, client_no_auth):
    items = [{"name": "myproject/app1"}, {"name": "myproject/app2"}]
    mocker.patch.object(
        client_no_auth.session, "get", return_value=_make_response(items)
    )
    result = client_no_auth.list_repositories()
    assert result == ["myproject/app1", "myproject/app2"]
    client_no_auth.session.get.assert_called_once()


def test_list_repositories_paginates_when_full_page_returned(mocker, client_no_auth):
    full_page = [{"name": f"myproject/app{i}"} for i in range(100)]
    empty_page = []
    mocker.patch.object(
        client_no_auth.session,
        "get",
        side_effect=[_make_response(full_page), _make_response(empty_page)],
    )
    result = client_no_auth.list_repositories()
    assert len(result) == 100
    assert client_no_auth.session.get.call_count == 2


def test_list_repositories_raises_on_http_error(mocker, client_no_auth):
    mocker.patch.object(
        client_no_auth.session,
        "get",
        return_value=_make_response([], raise_http_error=True),
    )
    with pytest.raises(requests.HTTPError):
        client_no_auth.list_repositories()


def test_list_repositories_raises_on_non_list_response(mocker, client_no_auth):
    mocker.patch.object(
        client_no_auth.session,
        "get",
        return_value=_make_response({"error": "something"}),
    )
    with pytest.raises(
        RuntimeError, match="Unexpected Harbor response for repositories"
    ):
        client_no_auth.list_repositories()


def test_list_repositories_skips_items_without_name_key(mocker, client_no_auth):
    items = [{"name": "myproject/ok"}, {"no_name_key": True}]
    mocker.patch.object(
        client_no_auth.session, "get", return_value=_make_response(items)
    )
    result = client_no_auth.list_repositories()
    assert result == ["myproject/ok"]


# --- list_artifacts ---


def test_list_artifacts_strips_project_prefix(mocker, client_no_auth):
    mocker.patch.object(client_no_auth.session, "get", return_value=_make_response([]))
    client_no_auth.list_artifacts("myproject/myrepo")
    call_url = client_no_auth.session.get.call_args[0][0]
    assert "/repositories/myrepo/artifacts" in call_url
    assert "myproject/myrepo" not in call_url


def test_list_artifacts_passes_with_tag_param(mocker, client_no_auth):
    mocker.patch.object(client_no_auth.session, "get", return_value=_make_response([]))
    client_no_auth.list_artifacts("myproject/myrepo", with_tag=True)
    call_params = client_no_auth.session.get.call_args[1]["params"]
    assert call_params["with_tag"] == "true"


def test_list_artifacts_single_page(mocker, client_no_auth):
    items = [{"digest": "sha256:abc", "tags": [{"name": "latest"}]}]
    mocker.patch.object(
        client_no_auth.session, "get", return_value=_make_response(items)
    )
    result = client_no_auth.list_artifacts("myproject/myrepo")
    assert len(result) == 1


def test_list_artifacts_paginates_multiple_pages(mocker, client_no_auth):
    full_page = [{"digest": f"sha256:{i}"} for i in range(100)]
    last_page = [{"digest": "sha256:final"}]
    mocker.patch.object(
        client_no_auth.session,
        "get",
        side_effect=[_make_response(full_page), _make_response(last_page)],
    )
    result = client_no_auth.list_artifacts("myproject/myrepo")
    assert len(result) == 101


def test_list_artifacts_raises_on_non_list_response(mocker, client_no_auth):
    mocker.patch.object(
        client_no_auth.session, "get", return_value=_make_response("not a list")
    )
    with pytest.raises(RuntimeError, match="Unexpected Harbor response for artifacts"):
        client_no_auth.list_artifacts("myproject/myrepo")


# --- list_latest_apps ---


def _repos_response(names):
    return _make_response([{"name": n} for n in names])


def _artifacts_with_latest(extra_tags: list[str] | None = None):
    """Artifact tagged 'latest', optionally with additional version tags."""
    tag_list = [{"name": t} for t in (extra_tags or [])] + [{"name": "latest"}]
    return _make_response([{"tags": tag_list}])


def _artifacts_without_latest():
    return _make_response([{"tags": [{"name": "v1.0"}]}])


def test_list_latest_apps_returns_repos_with_latest_tag_only(mocker, client_no_auth):
    side_effects = [
        _repos_response(["proj/app-a", "proj/app-b"]),
        _artifacts_with_latest(),  # app-a has latest (only tag)
        _artifacts_without_latest(),  # app-b does not
    ]
    mocker.patch.object(client_no_auth.session, "get", side_effect=side_effects)
    result = client_no_auth.list_latest_apps()
    # Only 'latest' tag present → resolved tag falls back to 'latest'
    assert result == [HarborRepo(repo="proj/app-a", tag="latest", all_tags=("latest",))]


def test_list_latest_apps_resolves_version_tag_when_present(mocker, client_no_auth):
    side_effects = [
        _repos_response(["proj/app-a"]),
        _artifacts_with_latest(extra_tags=["v1.2.3"]),
    ]
    mocker.patch.object(client_no_auth.session, "get", side_effect=side_effects)
    result = client_no_auth.list_latest_apps()
    assert len(result) == 1
    assert result[0].tag == "v1.2.3"
    assert set(result[0].all_tags) == {"v1.2.3", "latest"}


def test_list_latest_apps_result_is_sorted_by_repo_name(mocker, client_no_auth):
    side_effects = [
        _repos_response(["proj/z-app", "proj/a-app"]),
        _artifacts_with_latest(extra_tags=["v1.0"]),
        _artifacts_with_latest(extra_tags=["v2.0"]),
    ]
    mocker.patch.object(client_no_auth.session, "get", side_effect=side_effects)
    result = client_no_auth.list_latest_apps()
    assert result[0].repo == "proj/a-app"
    assert result[1].repo == "proj/z-app"


def test_list_latest_apps_skips_repo_on_http_error(mocker, client_no_auth):
    side_effects = [
        _repos_response(["proj/a", "proj/b"]),
        _make_response([], raise_http_error=True),  # proj/a errors
        _artifacts_with_latest(),  # proj/b succeeds
    ]
    mocker.patch.object(client_no_auth.session, "get", side_effect=side_effects)
    result = client_no_auth.list_latest_apps()
    assert len(result) == 1
    assert result[0].repo == "proj/b"


def test_list_latest_apps_skips_artifact_without_tags_list(mocker, client_no_auth):
    side_effects = [
        _repos_response(["proj/app"]),
        _make_response([{"tags": None}]),  # tags is None, not a list
    ]
    mocker.patch.object(client_no_auth.session, "get", side_effect=side_effects)
    result = client_no_auth.list_latest_apps()
    assert result == []


def test_list_latest_apps_only_one_entry_per_repo(mocker, client_no_auth):
    # Two artifacts both tagged "latest" — should only produce one HarborRepo
    side_effects = [
        _repos_response(["proj/app"]),
        _make_response(
            [
                {"tags": [{"name": "latest"}]},
                {"tags": [{"name": "latest"}]},
            ]
        ),
    ]
    mocker.patch.object(client_no_auth.session, "get", side_effect=side_effects)
    result = client_no_auth.list_latest_apps()
    assert len(result) == 1
