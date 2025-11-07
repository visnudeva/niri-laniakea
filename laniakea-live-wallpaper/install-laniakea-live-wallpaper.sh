#!/bin/bash

# Wallpaper generator that handles timing issues on slower systems
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

# First, try to set the cached wallpaper for a smoother user experience
if [ -f "$CACHED_WALLPAPER" ] && [ -s "$CACHED_WALLPAPER" ]; then
    echo "Setting cached wallpaper: $CACHED_WALLPAPER"
    swww img "$CACHED_WALLPAPER" --transition-fps 60 --transition-duration 1 --transition-type grow
    echo "Cached wallpaper set with transition."
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
