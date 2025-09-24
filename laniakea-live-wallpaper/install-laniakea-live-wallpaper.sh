#!/bin/bash

# Laniakea Live Wallpaper Installation Script for Arch Linux
# This script installs and configures the Laniakea live wallpaper system using Playwright for faster execution with exact visuals

set -e  # Exit on any error

echo "=== Laniakea Live Wallpaper Installation Script (Playwright Version) ==="
echo "This script will install and configure the Laniakea live wallpaper on Arch Linux using Playwright for faster execution with exact visuals"
echo

# Check if running on Arch Linux
if ! grep -q "Arch Linux" /etc/os-release 2>/dev/null; then
    echo "Warning: This script is designed for Arch Linux. You may need to modify it for your distribution."
    echo "Continuing anyway..."
fi

# Check if running as root (some operations might need sudo)
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a regular user, not as root."
    exit 1
fi

# Install required packages
echo "Installing required packages..."
# Update package databases first
sudo pacman -Sy --noconfirm
# Install only the required packages (no system upgrade) - removed firefox/geckodriver since we don't need them anymore
sudo pacman -S --noconfirm --needed \
    python \
    python-pip \
    swww \
    wget \
    curl \
    xorg-xrandr  # Added xrandr to detect screen resolution

# Create necessary directories
echo "Creating directories..."
mkdir -p ~/.config/systemd/user
mkdir -p ~/Pictures/Wallpapers

# Create the HTML file for direct viewing (kept for legacy use)
echo "Installing HTML files..."

cat > ~/Pictures/Wallpapers/index.html << 'INDEX_HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Laniakea Still</title>
  <style>
    body, html {
      margin: 0;
      padding: 0;
      overflow: hidden;
      background: black;
      width: 100%;
      height: 100%;
    }
    canvas {
      display: block;
    }
  </style>
  <script src="https://cdn.jsdelivr.net/npm/p5@1.6.0/lib/p5.min.js"></script>
</head>
<body>

<script>
  // Global variables
  let points = [];
  let mult = 0.005;

  let r1, r2, g1, g2, b1, b2;

  // Limit for how many frames to draw before saving
  let frameCountLimit = 500;

  function setup() {
    createCanvas(windowWidth, windowHeight);
    background(20);
    angleMode(DEGREES);
    noiseDetail(1);

    points = [];
    let density = 50;
    let space = height / density;

    for (let x = 0; x < width; x += space / 2) {
      for (let y = 0; y < height; y += space * 2) {
        let p = createVector(x + random(-100, 100), y + random(-100, 100));
        points.push(p);
      }
    }

    r1 = random(255);
    r2 = random(255);
    g1 = random(255);
    g2 = random(255);
    b1 = random(255);
    b2 = random(255);

    mult = random(0.002, 0.01);
  }

  function draw() {
    noStroke();
    for (let i = 0; i < points.length; i++) {
      let r = map(points[i].x, 0, width, r1, r2);
      let g = map(points[i].x, 0, height, g1, g2);
      let b = map(points[i].x, 0, width, b1, b2);

      let alpha = map(dist(width / 2, height / 2, points[i].x, points[i].y), 0, height / 2, 255, 0);
      fill(r, g, b, alpha);

      let angle = map(noise(points[i].x * mult, points[i].y * mult), 0, 1, 0, 720);
      points[i].add(createVector(cos(angle), sin(angle)));

      const centralAreaDivisor = window.innerWidth > 768 ? 3 : 4.5;
      if (dist(width / 2, height / 2, points[i].x, points[i].y) < height / centralAreaDivisor) {
        ellipse(points[i].x, points[i].y, 0.5);
      }
    }

    // After enough frames, save and stop
    if (frameCount > frameCountLimit) {
      saveCanvas("Laniakea", "png");
      noLoop();
      // Exit after a short delay so the PNG is written properly
      setTimeout(() => {
        window.close();
      }, 500);
    }
  }

  function windowResized() {
    resizeCanvas(windowWidth, windowHeight);
  }
</script>

</body>
</html>
INDEX_HTML_EOF

# Copy the Playwright-based wallpaper generation scripts (faster than original but exact same visuals)
echo "Installing Playwright-based wallpaper generation scripts..."
cp /home/visnudeva/Desktop/qwen/laniakea-live-wallpaper/playwright_capture_wallpaper.py ~/Pictures/Wallpapers/
chmod +x ~/Pictures/Wallpapers/playwright_capture_wallpaper.py

# Make the Python scripts executable
chmod +x ~/Pictures/Wallpapers/fast_capture_wallpaper.py
chmod +x ~/Pictures/Wallpapers/fast_generate_wallpaper.py

# Install required Python packages using a virtual environment to comply with PEP 668
python -m venv ~/Pictures/Wallpapers/laniakea_env
source ~/Pictures/Wallpapers/laniakea_env/bin/activate
pip install numpy Pillow playwright
playwright install chromium
deactivate

# Create systemd service files
echo "Creating systemd service files..."

# swww daemon service
cat > ~/.config/systemd/user/swww-daemon.service << 'SWWW_SERVICE_EOF'
[Unit]
Description=Wayland wallpaper daemon (swww)
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/swww-daemon
Restart=always

[Install]
WantedBy=graphical-session.target
SWWW_SERVICE_EOF

# Wallpaper generation service
cat > ~/.config/systemd/user/wallpaper.service << 'WALLPAPER_SERVICE_EOF'
[Unit]
Description=Generate random wallpaper with Playwright (faster execution, same visuals) and set via swww
After=graphical-session.target swww-daemon.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 1

# Generate a new wallpaper PNG with the Playwright script (faster than original Firefox but same visuals)
ExecStart=%h/Pictures/Wallpapers/laniakea_env/bin/python %h/Pictures/Wallpapers/playwright_capture_wallpaper.py /tmp/Laniakea.png

# Set it as wallpaper
ExecStartPost=/usr/bin/swww img /tmp/Laniakea.png

[Install]
WantedBy=graphical-session.target
WALLPAPER_SERVICE_EOF

# Create timer to generate wallpaper at boot (runs once at boot)
cat > ~/.config/systemd/user/wallpaper.timer << 'WALLPAPER_TIMER_EOF'
[Unit]
Description=Timer to generate wallpaper at boot
Requires=wallpaper.service

[Timer]
Unit=wallpaper.service
OnBootSec=3s
AccuracySec=1s

[Install]
WantedBy=timers.target
WALLPAPER_TIMER_EOF

# Enable and start services
echo "Enabling and starting services..."

# Reload systemd configuration
systemctl --user daemon-reload

# Enable services
systemctl --user enable swww-daemon.service
systemctl --user enable wallpaper.timer

# Start services
systemctl --user start swww-daemon.service
# Only start the timer (which runs once at boot), not the service directly
systemctl --user start wallpaper.timer

# Generate initial wallpaper
echo "Generating initial wallpaper..."
systemctl --user start wallpaper.service

echo
echo "=== Installation Complete (Fast Version) ==="
echo
echo "The Laniakea live wallpaper system has been installed and configured with a faster method!"
echo
echo "Services installed:"
echo "  - swww-daemon.service: Manages the wallpaper daemon"
echo "  - wallpaper.service: Generates and sets the wallpaper"
echo "  - wallpaper.timer: Generates wallpaper once at boot"
echo
echo "Files installed:"
echo "  - ~/Pictures/Wallpapers/index.html: Main HTML file for direct viewing"
echo "  - ~/Pictures/Wallpapers/playwright_capture_wallpaper.py: Fast browser-based wallpaper generator"
echo "  - ~/Pictures/Wallpapers/laniakea_env: Virtual environment with required packages"
echo "  - ~/.config/systemd/user/swww-daemon.service"
echo "  - ~/.config/systemd/user/wallpaper.service"
echo "  - ~/.config/systemd/user/wallpaper.timer"
echo
echo "To manually update the wallpaper at any time, run:"
echo "  systemctl --user start wallpaper.service"
echo
echo "The wallpaper will automatically update once at boot after 3 seconds."
echo "To disable automatic boot updates, run:"
echo "  systemctl --user stop wallpaper.timer"
echo "  systemctl --user disable wallpaper.timer"
echo
echo "Enjoy your organic, root-like Laniakea live wallpaper with faster loading!"
