#!/bin/bash

echo "Creating the wallpaper generation script..."

# Create the directory if it doesn't exist
mkdir -p ~/.config/laniakea-live-wallpaper

# Copy the Python script to the new location
cp "$(dirname "$0")/playwright_capture_wallpaper.py" ~/.config/laniakea-live-wallpaper/

# Create a Python virtual environment and install required packages
if [ ! -d ~/.config/laniakea-live-wallpaper/laniakea_env ]; then
    echo "Creating Python virtual environment and installing required packages..."
    python3 -m venv ~/.config/laniakea-live-wallpaper/laniakea_env
    source ~/.config/laniakea-live-wallpaper/laniakea_env/bin/activate
    pip install --upgrade pip
    pip install playwright
    playwright install chromium
    deactivate
else
    echo "Virtual environment already exists."
fi

# Create a wrapper script that ensures the wallpaper is properly generated
cat > ~/.config/laniakea-live-wallpaper/wallpaper_generator.sh << 'GENERATOR_EOF'
#!/bin/bash

# Wallpaper generator that handles timing issues on slower systems
# Set environment variables for X11 if running under systemd
if [ -z "$DISPLAY" ]; then
    if [ -n "$XDG_RUNTIME_DIR" ]; then
        export DISPLAY=":0"
    fi
fi

if [ -z "$XAUTHORITY" ]; then
    if [ -f "$HOME/.Xauthority" ]; then
        export XAUTHORITY="$HOME/.Xauthority"
    fi
fi

# First sets the cached wallpaper for immediate display, then generates a new one

WALLPAPER_PATH="/tmp/Laniakea.png"
PYTHON_SCRIPT="$HOME/.config/laniakea-live-wallpaper/laniakea_env/bin/python"
WALLPAPER_GENERATOR="$HOME/.config/laniakea-live-wallpaper/playwright_capture_wallpaper.py"
CACHED_WALLPAPER="$HOME/.cache/laniakea-live-wallpaper/cached_wallpaper.png"

# Wait for the swww daemon to be running
echo "Waiting for swww daemon to be ready..."
for i in {1..20}; do
    if pgrep -f "swww-daemon" > /dev/null; then
        echo "swww daemon is running."
        break
    else
        echo "Waiting for swww daemon... ($i/20)"
        sleep 1
    fi
done

# First, try to set the cached wallpaper immediately for a better user experience
if [ -f "$CACHED_WALLPAPER" ] && [ -s "$CACHED_WALLPAPER" ]; then
    echo "Setting cached wallpaper immediately: $CACHED_WALLPAPER"
    swww img "$CACHED_WALLPAPER" --transition-fps 60 --transition-duration 0 --transition-type none
    echo "Cached wallpaper set immediately."
else
    echo "No cached wallpaper found at $CACHED_WALLPAPER, will generate new wallpaper first."
fi

# Generate the new wallpaper
echo "Generating new wallpaper..."
if [ -f "$WALLPAPER_GENERATOR" ]; then
    $PYTHON_SCRIPT "$WALLPAPER_GENERATOR" "$WALLPAPER_PATH"
    
    # Wait for the file to be fully written
    echo "Waiting for wallpaper file to be fully written..."
    for i in {1..10}; do
        if [ -f "$WALLPAPER_PATH" ] && [ -s "$WALLPAPER_PATH" ]; then
            echo "Wallpaper generated successfully at $WALLPAPER_PATH"
            break
        else
            echo "Waiting for wallpaper file... ($i/10)"
            sleep 1
        fi
    done
    
    # Set the new wallpaper if it was generated
    if [ -f "$WALLPAPER_PATH" ] && [ -s "$WALLPAPER_PATH" ]; then
        echo "Setting new wallpaper..."
        # Wait a bit more to ensure swww is ready
        sleep 1
        swww img "$WALLPAPER_PATH" --transition-fps 60 --transition-duration 1 --transition-type grow
        echo "New wallpaper set successfully."
    else
        echo "ERROR: New wallpaper file was not generated properly."
        
        # If we have a cached wallpaper but failed to generate a new one, keep showing the cached one
        if [ -f "$CACHED_WALLPAPER" ] && [ -s "$CACHED_WALLPAPER" ]; then
            echo "Reverting to cached wallpaper..."
            swww img "$CACHED_WALLPAPER" --transition-fps 60 --transition-duration 1 --transition-type grow
            echo "Reverted to cached wallpaper."
        else
            exit 1
        fi
    fi
else
    echo "ERROR: Wallpaper generator script not found at $WALLPAPER_GENERATOR"
    exit 1
fi
GENERATOR_EOF

chmod +x ~/.config/laniakea-live-wallpaper/wallpaper_generator.sh

echo "Updated wallpaper.service"

# Update the wallpaper service to use the script
cat > ~/.config/systemd/user/wallpaper.service << 'SERVICE_EOF'
[Unit]
Description=Generate random wallpaper with Playwright (faster execution, same visuals) and set via swww
After=graphical-session.target swww-daemon.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
    Environment=DISPLAY=:0
    Environment=XAUTHORITY=%h/.Xauthority


# Use the wallpaper generator script
ExecStart=%h/.config/laniakea-live-wallpaper/wallpaper_generator.sh

[Install]
WantedBy=graphical-session.target
SERVICE_EOF

# Reload systemd configuration
systemctl --user daemon-reload

echo "Services have been reloaded."
