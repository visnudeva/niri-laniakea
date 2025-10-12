#!/bin/bash

echo "Creating the wallpaper generation script..."

# Create a wrapper script that ensures the wallpaper is properly generated
cat > ~/Pictures/Wallpapers/wallpaper_generator.sh << 'GENERATOR_EOF'
#!/bin/bash

# Wallpaper generator that handles timing issues on slower systems

WALLPAPER_PATH="/tmp/Laniakea.png"
PYTHON_SCRIPT="$HOME/Pictures/Wallpapers/laniakea_env/bin/python"
WALLPAPER_GENERATOR="$HOME/Pictures/Wallpapers/playwright_capture_wallpaper.py"

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

# Generate the wallpaper
echo "Generating wallpaper..."
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
    
    # Set the wallpaper if it was generated
    if [ -f "$WALLPAPER_PATH" ] && [ -s "$WALLPAPER_PATH" ]; then
        echo "Setting wallpaper..."
        # Wait a bit more to ensure swww is ready
        sleep 1
        swww img "$WALLPAPER_PATH" --transition-fps 60 --transition-duration 1 --transition-type grow
        echo "Wallpaper set successfully."
    else
        echo "ERROR: Wallpaper file was not generated properly."
        exit 1
    fi
else
    echo "ERROR: Wallpaper generator script not found at $WALLPAPER_GENERATOR"
    exit 1
fi
GENERATOR_EOF

chmod +x ~/Pictures/Wallpapers/robust_wallpaper_generator.sh

echo "Updated wallpaper.service"

# Update the wallpaper service to use the robust script
cat > ~/.config/systemd/user/wallpaper.service << 'SERVICE_EOF'
[Unit]
Description=Generate random wallpaper with Playwright (faster execution, same visuals) and set via swww
After=graphical-session.target swww-daemon.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5

# Use the robust wallpaper generator script
ExecStart=%h/Pictures/Wallpapers/robust_wallpaper_generator.sh

[Install]
WantedBy=graphical-session.target
SERVICE_EOF

# Reload systemd configuration
systemctl --user daemon-reload

echo "Services have been reloaded."
