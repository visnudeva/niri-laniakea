#!/usr/bin/env python3

import os
import sys
import asyncio
from playwright.async_api import async_playwright

# Define cache directory
CACHE_DIR = os.path.expanduser("~/.cache/laniakea-live-wallpaper")

async def generate_wallpaper_with_playwright(output_path, width=1920, height=1080):
    """Generate wallpaper using Playwright which is much faster than Selenium/Firefox"""
    
    async with async_playwright() as p:
        # Use Chromium which is faster to initialize than Firefox
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        
        # Set viewport
        await page.set_viewport_size({"width": width, "height": height})
        
        # HTML content (using the exact headless-index.html content)
        html_content = '''<!DOCTYPE html>
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
      background: rgb(20, 20, 20);
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
    
    // Render the complete pattern immediately for headless mode
    renderCompletePatternForHeadless();
    
    // Stop the animation loop since we're done
    noLoop();
  }

  function renderCompletePatternForHeadless() {
    noStroke();
    
    // For each point, simulate the full animation path and draw dots along it
    for (let i = 0; i < points.length; i++) {
      // Create a copy of the point to track its path
      let currentPoint = points[i].copy();
      
      // Get the color for this point
      let r = map(points[i].x, 0, width, r1, r2);
      let g = map(points[i].x, 0, height, g1, g2);
      let b = map(points[i].x, 0, width, b1, b2);
      
      // Simulate the animation by moving the point and drawing dots along its path
      for (let step = 0; step < 300; step++) {
        let angle = map(noise(currentPoint.x * mult, currentPoint.y * mult), 0, 1, 0, 720);
        currentPoint.add(createVector(cos(angle), sin(angle)));
        
        // Draw a dot at this position if it's in the central area
        const centralAreaDivisor = window.innerWidth > 768 ? 3 : 4.5;
        if (dist(width / 2, height / 2, currentPoint.x, currentPoint.y) < height / centralAreaDivisor) {
          let alpha = map(dist(width / 2, height / 2, currentPoint.x, currentPoint.y), 0, height / 2, 255, 0);
          fill(r, g, b, alpha);
          ellipse(currentPoint.x, currentPoint.y, 0.5);
        }
      }
    }
  }

  function draw() {
    // This will never be called because we call noLoop() in setup()
  }

  function windowResized() {
    resizeCanvas(windowWidth, windowHeight);
  }
</script>

</body>
</html>'''
        
        # Enable JavaScript console logging
        page.on("console", lambda msg: print(f"JS Console: {msg.type}: {msg.text}"))
        page.on("pageerror", lambda err: print(f"JS Error: {err}"))
        
        await page.set_content(html_content)
        
        # Wait a bit to allow the page to load and drawing to complete
        await page.wait_for_timeout(5000)
        
        # Take screenshot
        await page.screenshot(path=output_path, type='png')
        
        print(f"Wallpaper captured and saved to {output_path}")
        
        # Also save to cache for future use
        cache_path = os.path.join(CACHE_DIR, "cached_wallpaper.png")
        os.makedirs(CACHE_DIR, exist_ok=True)
        await page.screenshot(path=cache_path, type='png')
        print(f"Wallpaper also cached to {cache_path}")
        
        await browser.close()

def capture_wallpaper(output_path):
    width, height = 1920, 1080
    
    try:
        # Try to get actual screen resolution
        import subprocess
        result = subprocess.run(['xrandr'], stdout=subprocess.PIPE, text=True, timeout=5, check=False)
        for line in result.stdout.split('\n'):
            if '*' in line:  # Current resolution has an asterisk
                parts = line.split()
                for part in parts:
                    if 'x' in part and part[0].isdigit():
                        res = part.split('x')
                        if len(res) == 2:
                            width, height = int(res[0]), int(res[1])
                            break
                break
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        # If xrandr fails or is not available, fall back to default resolution
        pass
    
    # Run the async function
    asyncio.run(generate_wallpaper_with_playwright(output_path, width, height))

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 playwright_capture_wallpaper.py <output_path>")
        sys.exit(1)
    
    output_path = sys.argv[1]
    capture_wallpaper(output_path)
