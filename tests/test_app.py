import random
from collections.abc import Iterator

import pytest
from flask.testing import FlaskClient

import app as app_module


@pytest.fixture
def client() -> Iterator[FlaskClient]:
    app_module.app.config["TESTING"] = True
    app_module.count = 0  # the counter is module-level state, reset it per test
    with app_module.app.test_client() as test_client:
        yield test_client


def test_default_returns_message_and_pod(client: FlaskClient) -> None:
    response = client.get("/")
    assert response.status_code == 200
    data = response.get_json()
    assert data["message"] == "Hello from GKE! v2!"
    assert isinstance(data["pod"], str) and data["pod"]


def test_health_returns_ok(client: FlaskClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


@pytest.mark.parametrize(
    ("db_healthy", "cache_healthy", "expected"),
    [
        (True, True, "healthy"),
        (True, False, "unhealthy"),
        (False, True, "unhealthy"),
        (False, False, "unhealthy"),
    ],
)
def test_random_combines_component_status(
    client: FlaskClient,
    monkeypatch: pytest.MonkeyPatch,
    db_healthy: bool,
    cache_healthy: bool,
    expected: str,
) -> None:
    # /random calls random.choice twice: first for db, then for cache
    answers = iter([db_healthy, cache_healthy])
    monkeypatch.setattr(random, "choice", lambda _seq: next(answers))

    response = client.get("/random")
    assert response.status_code == 200
    data = response.get_json()
    assert data["database"] == ("healthy" if db_healthy else "unhealthy")
    assert data["cache"] == ("healthy" if cache_healthy else "unhealthy")
    assert data["status"] == expected


def test_count_increments_per_request(client: FlaskClient) -> None:
    first = client.get("/count").get_json()
    second = client.get("/count").get_json()
    assert first == {"Counted per pod:": 1}
    assert second == {"Counted per pod:": 2}


def test_unknown_route_returns_404(client: FlaskClient) -> None:
    assert client.get("/does-not-exist").status_code == 404


def test_post_not_allowed_on_health(client: FlaskClient) -> None:
    assert client.post("/health").status_code == 405
