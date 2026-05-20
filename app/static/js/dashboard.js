// Global configurations & state
let pollInterval = null;
const POLL_RATE_MS = 5000;

document.addEventListener("DOMContentLoaded", () => {
    // Initial fetch
    fetchDiagnostics();

    // Setup interactive handlers
    setupEventListeners();

    // Start auto polling if toggle is checked
    toggleAutoPoll(document.getElementById("auto-refresh-toggle").checked);
});

function setupEventListeners() {
    // Manual diagnostic trigger
    const manualBtn = document.getElementById("manual-refresh-btn");
    manualBtn.addEventListener("click", () => {
        fetchDiagnostics(true);
    });

    // Auto-refresh switch
    const autoToggle = document.getElementById("auto-refresh-toggle");
    autoToggle.addEventListener("change", (e) => {
        toggleAutoPoll(e.target.checked);
    });

    // Collapsible JSON inspector
    const jsonToggle = document.getElementById("json-toggle");
    const jsonBody = document.getElementById("json-body");
    const jsonArrow = document.getElementById("inspector-arrow");

    jsonToggle.addEventListener("click", () => {
        jsonBody.classList.toggle("collapsed");
        jsonArrow.classList.toggle("open");
    });

    // Copy JSON to clipboard
    const copyBtn = document.getElementById("copy-json-btn");
    copyBtn.addEventListener("click", (e) => {
        e.stopPropagation(); // Prevent toggling the accordion
        const rawJson = document.getElementById("json-preview").textContent;
        navigator.clipboard.writeText(rawJson)
            .then(() => {
                const icon = copyBtn.querySelector("i");
                icon.className = "fa-solid fa-check";
                icon.style.color = "var(--accent-green)";
                setTimeout(() => {
                    icon.className = "fa-regular fa-copy";
                    icon.style.color = "";
                }, 2000);
            })
            .catch(err => {
                console.error("Failed to copy JSON:", err);
            });
    });
}

function toggleAutoPoll(enable) {
    if (enable) {
        if (!pollInterval) {
            pollInterval = setInterval(() => fetchDiagnostics(), POLL_RATE_MS);
        }
    } else {
        if (pollInterval) {
            clearInterval(pollInterval);
            pollInterval = null;
        }
    }
}

async function fetchDiagnostics(isManual = false) {
    const refreshIcon = document.getElementById("refresh-icon");
    const manualBtn = document.getElementById("manual-refresh-btn");
    
    // UI Loading state indication
    if (isManual) {
        refreshIcon.classList.add("fa-spin");
        manualBtn.disabled = true;
    }

    try {
        const response = await fetch("/health");
        const data = await response.json();
        
        updateDashboard(data);
    } catch (error) {
        console.error("PulseCheck API Fetch Error: ", error);
        showConnectionError();
    } finally {
        if (isManual) {
            refreshIcon.classList.remove("fa-spin");
            manualBtn.disabled = false;
        }
    }
}

function updateDashboard(data) {
    // 1. Overall Health Banner
    const banner = document.getElementById("status-banner");
    const statusText = document.getElementById("overall-status-text");
    const shieldIcon = document.getElementById("status-shield");
    
    banner.className = "status-banner-card"; // Reset
    if (data.status === "healthy") {
        banner.classList.add("healthy");
        statusText.textContent = "ENVIRONMENT HEALTHY & STABLE";
        shieldIcon.className = "fa-solid fa-shield-halved";
    } else {
        banner.classList.add("unhealthy");
        statusText.textContent = "ENVIRONMENT ACTION REQUIRED";
        shieldIcon.className = "fa-solid fa-triangle-exclamation";
    }

    // Update scan timestamp
    document.getElementById("last-update-time").textContent = new Date().toLocaleTimeString();

    // 2. Host Performance Metrics
    const sys = data.system;
    
    // CPU Utilization (Radial Gauge)
    const cpuVal = Math.round(sys.cpu_usage_percent);
    document.getElementById("cpu-value").textContent = `${cpuVal}%`;
    const cpuGauge = document.getElementById("cpu-gauge-fill");
    // Circumference = 2 * PI * r = 2 * 3.14159 * 40 = 251.2
    const circumference = 251.2;
    const cpuOffset = circumference - (cpuVal / 100) * circumference;
    cpuGauge.style.strokeDashoffset = cpuOffset;

    // RAM Utilization
    const ramPercent = Math.round(sys.memory.percent_used);
    document.getElementById("ram-value").textContent = `${ramPercent}%`;
    document.getElementById("ram-bar-fill").style.width = `${ramPercent}%`;
    
    const ramUsedGb = (sys.memory.total_bytes - sys.memory.available_bytes) / (1024 ** 3);
    const ramTotalGb = sys.memory.total_bytes / (1024 ** 3);
    document.getElementById("ram-used-bytes").textContent = `${ramUsedGb.toFixed(1)} GB`;
    document.getElementById("ram-total-bytes").textContent = `${ramTotalGb.toFixed(1)} GB`;

    // Disk Volume
    const diskPercent = Math.round(sys.disk.percent_used);
    document.getElementById("disk-value").textContent = `${diskPercent}%`;
    document.getElementById("disk-bar-fill").style.width = `${diskPercent}%`;
    
    const diskFreeGb = sys.disk.free_bytes / (1024 ** 3);
    const diskTotalGb = sys.disk.total_bytes / (1024 ** 3);
    document.getElementById("disk-free-bytes").textContent = `${diskFreeGb.toFixed(1)} GB`;
    document.getElementById("disk-total-bytes").textContent = `${diskTotalGb.toFixed(1)} GB`;

    // System Uptime
    document.getElementById("uptime-value").textContent = formatUptime(sys.uptime_seconds);

    // 3. Dependency Services
    const servicesContainer = document.getElementById("services-container");
    servicesContainer.innerHTML = ""; // Clear loader/previous data
    
    data.services.forEach(svc => {
        const row = document.createElement("div");
        row.className = "service-row";
        
        const isHealthy = svc.status === "healthy";
        const badgeClass = isHealthy ? "ok" : "err";
        const badgeText = isHealthy ? `HTTP ${svc.status_code || 200}` : (svc.status_code ? `HTTP ${svc.status_code}` : "DOWN");
        
        row.innerHTML = `
            <div class="service-meta">
                <div class="service-led ${isHealthy ? 'healthy' : 'unhealthy'}" title="${isHealthy ? 'Online' : 'Offline'}"></div>
                <div>
                    <div class="service-name">${svc.name} ${svc.critical ? '<span style="color: var(--accent-red); font-size: 0.65rem; margin-left:4px; vertical-align: middle;">[CRITICAL]</span>' : ''}</div>
                    <div class="service-url">${svc.url}</div>
                </div>
            </div>
            <div class="service-details-right">
                <span class="service-badge ${badgeClass}">${badgeText}</span>
                <span class="service-latency">
                    <i class="fa-solid fa-gauge-high latency-icon"></i>
                    ${svc.latency_ms} ms
                </span>
            </div>
        `;
        servicesContainer.appendChild(row);
    });

    // 4. Update JSON preview
    document.getElementById("json-preview").textContent = JSON.stringify(data, null, 2);
}

function showConnectionError() {
    const banner = document.getElementById("status-banner");
    const statusText = document.getElementById("overall-status-text");
    const shieldIcon = document.getElementById("status-shield");
    
    banner.className = "status-banner-card unhealthy";
    statusText.textContent = "DIAGNOSTICS OFFLINE - CHECK SERVICE";
    shieldIcon.className = "fa-solid fa-plug-circle-xmark";
    
    const servicesContainer = document.getElementById("services-container");
    servicesContainer.innerHTML = `
        <div class="loading-state" style="color: var(--accent-red)">
            <i class="fa-solid fa-triangle-exclamation" style="font-size: 2.5rem;"></i>
            <p style="font-weight: 600">Failed to connect to PulseCheck health endpoint.</p>
            <p style="font-size: 0.8rem; color: var(--text-muted)">Verify the FastAPI service is running locally.</p>
        </div>
    `;
}

function formatUptime(seconds) {
    const d = Math.floor(seconds / (3600 * 24));
    const h = Math.floor((seconds % (3600 * 24)) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    
    const dDisplay = d > 0 ? `${d}d ` : "";
    const hDisplay = h > 0 ? `${h}h ` : "0h ";
    const mDisplay = m > 0 ? `${m}m ` : "0m ";
    const sDisplay = `${s}s`;
    
    return dDisplay + hDisplay + mDisplay + sDisplay;
}
