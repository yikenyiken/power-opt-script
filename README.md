# Linux Power Optimization Script

Automated Bash utility for Linux (laptops especially) that dynamically detects background resource drainers, and applies system-wide optimizations to extend battery life and reduce thermal output.

---

## ⚠️ Important Warnings & Precautions

Before executing this script on your machine, please read the following:

* **Requires Root Privileges:** The script modifies systemd services and kernel tuneables via `/sys`, so it must be run with `sudo`.
* **Disables Active Services Immediately:** The script automatically stops and disables running background daemons (such as Docker, database servers, web servers, printing services, etc.) if they are actively running when the script is executed.
* **Impact on Development Environments:** If you rely on background services (e.g., Docker containers, PostgreSQL, Apache) for active local development, you will need to start them manually after running this script (`sudo systemctl start <service>`).

---

## 🤖 AI Assistance Transparency & Development Effort

In the spirit of open-source transparency, here is how this project was created:

* **AI Assistance:** This script and its accompanying documentation were drafted, structured, and refined with the assistance of **Gemini** (an AI language model by Google).
* **Development & Iteration Time:** ~15–20 minutes of prompt engineering, architectural refinement (transitioning from hardcoded service targets to dynamic systemd checks), and parameter validation.
* **Human Oversight:** The underlying logic, service candidate pools, and fallback metrics were reviewed to ensure safe execution on standard Linux distributions (Debian/Ubuntu, Arch, Fedora).

---

## 🚀 Features

* **Deterministic Power Savings:** Stops unused, high-overhead background daemons (containers, databases, web servers) to guarantee reduced idle CPU wakeups and RAM consumption.
* **Dynamic Service Detection:** Scans `systemctl` for active daemons on the host machine rather than blindly changing system configuration.
* **Kernel & Hardware Tuning:** Leverages `powertop --auto-tune` for PCIe/USB power management and sets CPU scaling governors to `powersave`.
* **Zero-Telemetry Overhead:** Focuses on actionable system state changes without relying on noisy or unreliable real-time battery sensors.

---

## 📋 Prerequisites

* Linux Operating System (Systemd-based)
* Laptop hardware running on battery power (for live wattage metrics)
* Bash shell environment
* `sudo` / root access

---

## 🔧 Installation & Usage

1. **Clone or download the repository:**
   ```bash
   git clone https://github.com/yikenyiken/power-opt-script.git
   cd power-opt-script

```

2. **Make the script executable:**
```bash
chmod +x optimize_power.sh

```


3. **Run with root permissions (unplug AC adapter for wattage reading):**
```bash
sudo ./optimize_power.sh

```



---

## 🛠️ Restoring Services

If the script stopped a background service you need (e.g., Docker or PostgreSQL), you can quickly restore it with:

```bash
sudo systemctl enable --now <service-name>

```

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
