import pytest
import asyncio
import pytest_asyncio
from fastapi.testclient import TestClient
from httpx import AsyncClient
from unittest.mock import patch, Mock
from celery.result import AsyncResult
from main import app, celery

# Base URL for integration tests (Minikube)
BASE_URL = "http://192.168.49.2:31345"


@pytest.fixture
def client():
    """Fixture for FastAPI TestClient."""
    return TestClient(app)


@pytest_asyncio.fixture
async def async_client():
    """Fixture for Async HTTPX client."""
    client = AsyncClient(base_url=BASE_URL)
    yield client
    await client.aclose()


@pytest.fixture
def mock_celery_result():
    """Fixture to mock Celery AsyncResult for status checks."""
    with patch("celery.result.AsyncResult") as mock_result:
        yield mock_result


# Unit Tests
@pytest.mark.asyncio
async def test_trigger_task(client):
    """Test the /task/{device_token} endpoint."""
    response = client.get("/task/test_device")

    assert response.status_code == 200
    json_response = response.json()
    assert "task_id" in json_response
    assert json_response["message"] == "Task queued"
    assert isinstance(json_response["task_id"], str)


@pytest.mark.asyncio
async def test_check_task_status_success(client, mock_celery_result):
    """Test the /task/status/{task_id} endpoint with SUCCESS status."""
    mock_task = Mock()
    mock_task.status = "SUCCESS"
    mock_task.result = "Task completed for test_device"
    mock_celery_result.return_value = mock_task

    response = client.get("/task/status/test-task-id")

    assert response.status_code == 200
    assert response.json() == {
        "task_id": "test-task-id",
        "status": "SUCCESS",
        "result": "Task completed for test_device",
    }


@pytest.mark.asyncio
async def test_check_task_status_pending(client, mock_celery_result):
    """Test the /task/status/{task_id} endpoint with PENDING status."""
    mock_task = Mock()
    mock_task.status = "PENDING"
    mock_task.result = None
    mock_celery_result.return_value = mock_task

    response = client.get("/task/status/test-task-id")

    assert response.status_code == 200
    assert response.json() == {
        "task_id": "test-task-id",
        "status": "PENDING",
        "result": None,
    }


@pytest.mark.asyncio
async def test_check_task_status_invalid_task_id(client, mock_celery_result):
    """Test the /task/status/{task_id} endpoint with an invalid task ID."""
    mock_task = Mock()
    mock_task.status = "PENDING"
    mock_task.result = None
    mock_celery_result.return_value = mock_task

    response = client.get("/task/status/invalid-task-id")

    assert response.status_code == 200
    assert response.json() == {
        "task_id": "invalid-task-id",
        "status": "PENDING",
        "result": None,
    }


# Integration Tests
@pytest.mark.asyncio
async def test_trigger_task_integration(async_client):
    """Integration test for /task/{device_token} against running service."""
    response = await async_client.get("/task/test_device")

    assert response.status_code == 200
    json_response = response.json()
    assert "task_id" in json_response
    assert json_response["message"] == "Task queued"
    assert isinstance(json_response["task_id"], str)


@pytest.mark.asyncio
async def test_check_task_status_integration(async_client):
    """Integration test for /task/status/{task_id} against running service."""
    trigger_response = await async_client.get("/task/test_device")
    task_id = trigger_response.json()["task_id"]

    await asyncio.sleep(6)  # Wait for task to complete (5 seconds)

    response = await async_client.get(f"/task/status/{task_id}")

    assert response.status_code == 200
    json_response = response.json()
    assert json_response["task_id"] == task_id
    assert json_response["status"] == "SUCCESS"
    assert json_response["result"] == "Task completed for test_device"
