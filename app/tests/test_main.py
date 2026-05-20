import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_read_root():
    """
    Ensure the root UI is rendered with appropriate HTML components.
    """
    response = client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "PULSE" in response.text
    assert "CHECK" in response.text

def test_read_health():
    """
    Ensure health status output has system and downstream details.
    """
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    
    # Assert top-level structure
    assert "status" in data
    assert "timestamp" in data
    assert "system" in data
    assert "services" in data
    
    assert data["status"] in ["healthy", "unhealthy"]
    
    # Assert system stats structure
    sys = data["system"]
    assert "cpu_usage_percent" in sys
    assert "memory" in sys
    assert "disk" in sys
    assert "uptime_seconds" in sys
    
    # Assert services array structure
    services = data["services"]
    assert len(services) > 0
    for svc in services:
        assert "name" in svc
        assert "url" in svc
        assert "status" in svc
        assert "latency_ms" in svc
        assert "critical" in svc
