#!/bin/bash

# More robust wallpaper service script that handles timing issues on slower systems

echo "Creating a more robust wallpaper generation script..."

# Create a wrapper script that ensures the wallpaper is properly generated
cat > ~/Pictures/Wallpapers/robust_wallpaper_generator.sh << 'GENERATOR_EOF'
#!/bin/bash

# Robust wallpaper generator that handles timing issues on slower systems

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

echo "Updated wallpaper.service to use the robust generator..."

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

echo "Wallpaper service updated with robust generator script."

echo
echo "The wallpaper system has been updated with a more robust generator that:"
echo "1. Waits for swww daemon to be running"
echo "2. Ensures the wallpaper file is properly generated"
echo "3. Waits for the file to be fully written"
echo "4. Sets the wallpaper after verifying all conditions"
echo
echo "Services have been reloaded. To test the new setup, run:"
echo "  systemctl --user restart wallpaper.service"
