# GitHub Self-Hosted Runner Troubleshooting

## How to Check the Status of Self-Hosted GitHub Runners on Ubuntu

### 1. Check Runner Service Status

```bash
# Check if the runner service is running
sudo systemctl status actions.runner.*.service

# Or if you know the specific service name:
sudo systemctl status actions.runner.your-org-your-repo.your-runner-name.service
```

### 2. Check Runner Process

```bash
# List all runner processes
ps aux | grep Runner.Listener

# Or check if runsvc.sh is running
ps aux | grep runsvc.sh
```

### 3. Check Runner Logs

```bash
# Navigate to the runner directory (typically where you installed it)
cd /path/to/your/runner

# View the most recent runner log
tail -f _diag/Runner_*.log

# Or view worker logs
tail -f _diag/Worker_*.log
```

### 4. Using GitHub CLI

```bash
# List all runners for a repository
gh api repos/OWNER/REPO/actions/runners

# List runners for an organization
gh api orgs/ORG/actions/runners

# Check specific runner status
gh api repos/OWNER/REPO/actions/runners/RUNNER_ID
```

### 5. Check via GitHub Web Interface

Navigate to:
- **For repository runners**: `https://github.com/OWNER/REPO/settings/actions/runners`
- **For organization runners**: `https://github.com/organizations/ORG/settings/actions/runners`

The status will show as:
- **Idle** (green) - Runner is online and waiting for jobs
- **Active** (blue) - Runner is currently executing a job
- **Offline** (gray) - Runner is not connected

### 6. Quick Health Check Script

```bash
#!/bin/bash
# Save as check-runner.sh

RUNNER_DIR="/path/to/your/runner"

echo "=== GitHub Runner Status ==="
echo ""
echo "Service Status:"
systemctl status actions.runner.*.service | grep "Active:"
echo ""
echo "Runner Process:"
ps aux | grep "Runner.Listener" | grep -v grep
echo ""
echo "Recent Logs:"
tail -n 20 "$RUNNER_DIR/_diag/Runner_"*.log 2>/dev/null | tail -20
```

The most reliable method is checking the **systemctl status** combined with viewing the GitHub web interface to see if the runner appears online there.

---

## How to Find and Start All Local Runners

### 1. Find All Runner Installations

```bash
# Find all runner directories (runners typically contain run.sh and config.sh)
sudo find / -name "run.sh" -path "*/actions-runner/*" 2>/dev/null

# Or search for runner services
sudo systemctl list-units --all | grep actions.runner

# Find runner configuration files
sudo find / -name ".runner" -type f 2>/dev/null
```

### 2. Start All Runner Services

```bash
# Start all runner services at once
sudo systemctl start actions.runner.*.service

# Or start them individually if you know the names
sudo systemctl start actions.runner.your-org-your-repo.runner-name.service
```

### 3. Enable Auto-Start on Boot

```bash
# Enable all runners to start automatically on system boot
sudo systemctl enable actions.runner.*.service
```

### 4. Verify All Runners are Running

```bash
# Check status of all runner services
sudo systemctl status actions.runner.*.service

# List all active runner services
sudo systemctl list-units --type=service --state=running | grep actions.runner
```

### 5. Complete Script to Find and Start All Runners

```bash
#!/bin/bash
# Save as start-all-runners.sh

echo "=== Finding all GitHub Runner services ==="
SERVICES=$(sudo systemctl list-units --all | grep actions.runner | awk '{print $1}')

if [ -z "$SERVICES" ]; then
    echo "No runner services found."
    echo ""
    echo "Searching for runner directories..."
    RUNNER_DIRS=$(sudo find / -name "run.sh" -path "*/actions-runner/*" 2>/dev/null)

    if [ -z "$RUNNER_DIRS" ]; then
        echo "No runner installations found."
        exit 1
    else
        echo "Found runner installations:"
        echo "$RUNNER_DIRS"
        echo ""
        echo "These runners are not installed as services."
        echo "You can start them manually with: cd /path/to/runner && ./run.sh"
    fi
else
    echo "Found runner services:"
    echo "$SERVICES"
    echo ""

    echo "=== Starting all runner services ==="
    for service in $SERVICES; do
        echo "Starting $service..."
        sudo systemctl start "$service"
    done

    echo ""
    echo "=== Verifying runner status ==="
    sudo systemctl status actions.runner.*.service | grep -E "●|Active:"
fi
```

Make it executable and run:
```bash
chmod +x start-all-runners.sh
sudo ./start-all-runners.sh
```

### 6. Manual Start (if not installed as service)

If runners are not installed as services:

```bash
# Find runner directories
RUNNER_DIRS=$(sudo find / -name "run.sh" -path "*/actions-runner/*" 2>/dev/null)

# Start each runner manually
for dir in $RUNNER_DIRS; do
    RUNNER_PATH=$(dirname "$dir")
    echo "Starting runner in $RUNNER_PATH"
    cd "$RUNNER_PATH"
    nohup ./run.sh > runner.log 2>&1 &
done
```

### 7. Common Runner Locations

Runners are typically installed in:
- `/home/username/actions-runner/`
- `/opt/actions-runner/`
- `/var/lib/actions-runner/`
- User home directories: `~/actions-runner/`

The **systemctl approach** is the most reliable if runners were installed as services. If they weren't, you'll need to navigate to each runner directory and execute `./run.sh` manually or in the background.

---

## Fixing Expired Token Issues

When a GitHub self-hosted runner token expires, you need to re-register the runner.

### 1. Remove the Old Runner Configuration

```bash
# Navigate to your runner directory
cd /path/to/your/runner

# Stop the runner service if it's running
sudo ./svc.sh stop

# Uninstall the service
sudo ./svc.sh uninstall

# Remove the old configuration
./config.sh remove --token YOUR_REMOVAL_TOKEN
```

**Note**: If you don't have a removal token or the above fails, you can force remove:

```bash
# Force remove without token
sudo rm .runner
sudo rm .credentials
sudo rm .credentials_rsaparams
```

### 2. Get a New Registration Token

You need to generate a new token from GitHub:

#### For Repository Runners:
1. Go to: `https://github.com/OWNER/REPO/settings/actions/runners`
2. Click **"New self-hosted runner"**
3. Select **Linux** and copy the token from the configuration command

#### For Organization Runners:
1. Go to: `https://github.com/organizations/ORG/settings/actions/runners`
2. Click **"New runner"**
3. Select **Linux** and copy the token

#### Using GitHub CLI:
```bash
# For repository
gh api --method POST repos/OWNER/REPO/actions/runners/registration-token | jq -r .token

# For organization
gh api --method POST orgs/ORG/actions/runners/registration-token | jq -r .token
```

### 3. Re-register the Runner

```bash
# Navigate to runner directory
cd /path/to/your/runner

# Configure with new token
./config.sh --url https://github.com/OWNER/REPO --token YOUR_NEW_TOKEN

# Or for organization:
./config.sh --url https://github.com/ORGANIZATION --token YOUR_NEW_TOKEN

# Optional: Add labels and name
./config.sh --url https://github.com/OWNER/REPO --token YOUR_NEW_TOKEN --name my-runner --labels ubuntu,self-hosted
```

### 4. Install and Start as Service

```bash
# Install as service
sudo ./svc.sh install

# Start the service
sudo ./svc.sh start

# Check status
sudo ./svc.sh status
```

### 5. Complete Script to Re-register Runner

```bash
#!/bin/bash
# Save as reregister-runner.sh

RUNNER_DIR="/path/to/your/runner"
GITHUB_URL="https://github.com/OWNER/REPO"  # Change this
NEW_TOKEN="YOUR_NEW_TOKEN"  # Get from GitHub

cd "$RUNNER_DIR"

echo "=== Stopping and removing old configuration ==="
sudo ./svc.sh stop 2>/dev/null
sudo ./svc.sh uninstall 2>/dev/null

# Force remove old credentials
sudo rm -f .runner .credentials .credentials_rsaparams

echo ""
echo "=== Re-registering runner with new token ==="
./config.sh --url "$GITHUB_URL" --token "$NEW_TOKEN"

if [ $? -eq 0 ]; then
    echo ""
    echo "=== Installing and starting service ==="
    sudo ./svc.sh install
    sudo ./svc.sh start

    echo ""
    echo "=== Checking status ==="
    sudo ./svc.sh status
else
    echo "Failed to register runner. Please check the token and URL."
    exit 1
fi
```

### 6. Alternative: Remove Old Runner from GitHub First

If the runner appears offline in GitHub settings:

1. Go to GitHub: `Settings → Actions → Runners`
2. Find your offline runner
3. Click the **three dots** (⋯) next to it
4. Select **"Remove"**
5. Then follow steps 2-4 above to re-register

### Important Notes

- **Registration tokens expire after 1 hour** - use them quickly after generation
- **Removal tokens** are different from registration tokens
- If you have **multiple runners**, you'll need to repeat this process for each one
- Consider using **GitHub Apps** or **PAT tokens** for automated runner management in production environments
