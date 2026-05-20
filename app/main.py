import time
from typing import Dict, Any, List
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import psutil
import httpx
import asyncio

app = FastAPI(
    title="PulseCheck Microservice",
    description="Automated system and API health monitoring microservice.",
    version="1.0.0"
)

# Mount static and templates directories
app.mount("/static", StaticFiles(directory="app/static"), name="static")
templates = Jinja2Templates(directory="app/templates")

START_TIME = time.time()

# Pre-defined external health check targets
DEFAULT_TARGETS = [
    {"name": "GitHub API", "url": "https://api.github.com", "critical": True},
    {"name": "HTTPBin Tester", "url": "https://httpbin.org/status/200", "critical": False},
    {"name": "Cloudflare DNS", "url": "https://1.1.1.1", "critical": True}
]

async def check_service(client: httpx.AsyncClient, service: Dict[str, Any]) -> Dict[str, Any]:
    name = service["name"]
    url = service["url"]
    critical = service["critical"]
    
    start = time.perf_counter()
    try:
        # Perform request with 3-second timeout
        response = await client.get(url, timeout=3.0)
        latency = round((time.perf_counter() - start) * 1000, 2)
        
        is_healthy = 200 <= response.status_code < 400
        return {
            "name": name,
            "url": url,
            "status": "healthy" if is_healthy else "unhealthy",
            "status_code": response.status_code,
            "latency_ms": latency,
            "critical": critical,
            "error": None
        }
    except httpx.RequestError as e:
        latency = round((time.perf_counter() - start) * 1000, 2)
        return {
            "name": name,
            "url": url,
            "status": "unhealthy",
            "status_code": None,
            "latency_ms": latency,
            "critical": critical,
            "error": str(type(e).__name__)
        }

@app.get("/", response_class=HTMLResponse)
async def get_dashboard(request: Request):
    """
    Renders the PulseCheck premium dashboard.
    """
    return templates.TemplateResponse(request=request, name="index.html")

@app.get("/health")
async def get_health() -> Dict[str, Any]:
    """
    Detailed JSON health endpoint containing system metrics and downstream API check statuses.
    """
    # Fetch system metrics
    cpu_percent = psutil.cpu_percent(interval=None)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    uptime = round(time.time() - START_TIME, 2)
    
    system_metrics = {
        "cpu_usage_percent": cpu_percent,
        "memory": {
            "total_bytes": memory.total,
            "available_bytes": memory.available,
            "percent_used": memory.percent
        },
        "disk": {
            "total_bytes": disk.total,
            "free_bytes": disk.free,
            "percent_used": disk.percent
        },
        "uptime_seconds": uptime
    }
    
    # Check services concurrently
    services_status = []
    overall_healthy = True
    
    async with httpx.AsyncClient(follow_redirects=True) as client:
        tasks = [check_service(client, target) for target in DEFAULT_TARGETS]
        results = await asyncio.gather(*tasks)
        
        for res in results:
            services_status.append(res)
            # If a critical dependency is down, the microservice itself is considered unhealthy
            if res["critical"] and res["status"] != "healthy":
                overall_healthy = False

    return {
        "status": "healthy" if overall_healthy else "unhealthy",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "system": system_metrics,
        "services": services_status
    }
