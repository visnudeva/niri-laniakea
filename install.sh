#!/bin/bash

set -e
set -u

# --- Color Output ---
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# --- Logging ---
LOG_FILE="$HOME/niri-laniakea_$(date +%Y%m%d_%H%M%S).log"
log() {
    echo -e "${YELLOW}$@${NC}" | tee -a "$LOG_FILE"
}
log_success() {
    echo -e "${GREEN}$@${NC}" | tee -a "$LOG_FILE"
}
log_error() {
    echo -e "${RED}$@${NC}" | tee -a "$LOG_FILE"
}
log_info() {
    echo -e "${BLUE}$@${NC}" | tee -a "$LOG_FILE"
}

# --- Variables ---
REPO_URL="https://github.com/visnudeva/niri-laniakea"
CLONE_DIR="${HOME}/niri-laniakea"
CONFIG_SOURCE="${CLONE_DIR}/config"
CONFIG_TARGET="${HOME}/.config"
WALLPAPER_NAME="Laniakea.png"
WALLPAPER_SOURCE="${CLONE_DIR}/backgrounds/${WALLPAPER_NAME}"
WALLPAPER_DEST="${HOME}/.config/backgrounds/${WALLPAPER_NAME}"
BACKUP_DIR="${HOME}/.config_backup_$(date +%Y%m%d_%H%M%S)"
# SDDM theme and config paths
SDDM_THEME_SOURCE="${CLONE_DIR}/sddm/laniakea"
SDDM_THEME_DEST="/usr/share/sddm/themes/Laniakea"
SDDM_CONF_SOURCE="${CLONE_DIR}/sddm/sddm.conf"
SDDM_CONF_DEST="/etc/sddm.conf"
DRYRUN=0
FORCE=0
UNATTENDED=0
RESTORE=""
UNINSTALL=0
SUDO=""

PACKAGES=(
    acpi blueman bluez bluez-utils brightnessctl capitaine-cursors 
    fish geany gvfs kitty kvantum kvantum-qt5 libnotify mako 
    network-manager-applet networkmanager nm-connection-editor 
    niri nwg-look pamixer pavucontrol pipewire pipewire-alsa 
    pipewire-audio pipewire-jack pipewire-pulse polkit-gnome 
    qt5-graphicaleffects qt6-5compat qt6-wayland satty swww 
    swayidle swaylock thunar thunar-archive-plugin 
    thunar-media-tags-plugin thunar-volman udiskie waybar 
    wl-clipboard wireplumber xdg-desktop-portal-hyprland yay
)
AUR_PACKAGES=(
    ttf-nerd-fonts-symbols
)
REQUIRED_CMDS=(git rsync pacman diff meld)

DRYRUN_SUMMARY=()

# --- Trap for cleanup on errors ---
cleanup() {
    log_error "[!] Script failed or exited unexpectedly. Performing cleanup."
    # Add cleanup logic here if needed, e.g., removing temp files
}
trap cleanup EXIT

# --- Functions ---
usage() {
    echo "Usage: $0 [--force] [--dry-run] [--unattended] [--restore <backup_dir>] [--uninstall]"
    echo "  --force       Remove existing clone directory without prompt"
    echo "  --dry-run     Only display actions, do not perform them"
    echo "  --unattended  Skip all interactive prompts"
    echo "  --restore     Restore from backup directory"
    echo "  --uninstall   Undo all changes made by install.sh"
    exit 1
}

handle_sudo() {
    if [[ $(id -u) -ne 0 ]]; then
        SUDO="sudo"
        if ! command -v sudo &>/dev/null; then
            log_error "[!] sudo is required but not installed."
            exit 1
        fi
    fi
}

check_for_update() {
    if [[ -f "$CLONE_DIR/install.sh" ]]; then
        log_info "[+] Checking for newer install.sh..."
        local latest_script
        latest_script=$(mktemp)
        curl -sL "$REPO_URL/raw/main/install.sh" -o "$latest_script"
        if ! diff "$latest_script" "$CLONE_DIR/install.sh" &>/dev/null; then
            log_info "[!] A newer version of install.sh is available."
            if (( UNATTENDED )) || (( FORCE )); then
                cp "$latest_script" "$CLONE_DIR/install.sh"
                log_success "[+] Updated install.sh to latest."
            else
                read -p "[?] Update install.sh to latest? [y/N]: " REPLY
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cp "$latest_script" "$CLONE_DIR/install.sh"
                    log_success "[+] Updated install.sh to latest."
                fi
            fi
        else
            log_info "[+] install.sh is up to date."
        fi
        rm "$latest_script"
    fi
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            arch|manjaro|cachyos)
                log_info "[+] Running on supported distro: $ID"
                ;;
            *)
                log_error "[!] Unsupported distro: $ID. Only supports Arch Linux and derivatives."
                exit 2
                ;;
        esac
    else
        log_error "[!] Could not detect OS. Aborting."
        exit 2
    fi
}

check_dependencies() {
    local missing=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} )); then
        log_error "[!] Missing dependencies: ${missing[*]}"
        exit 3
    fi
}

update_system() {
    log_info "[+] Updating Arch Linux system..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would run: $SUDO pacman -Syu --noconfirm")
    else
        $SUDO pacman -Syu --noconfirm || log_error "[!] System update failed."
    fi
}

backup_config() {
    if [[ -d "$CONFIG_TARGET" ]]; then
        log_info "[+] Backing up existing .config to $BACKUP_DIR"
        if (( DRYRUN )); then
            DRYRUN_SUMMARY+=("Would backup $CONFIG_TARGET to $BACKUP_DIR")
        else
            cp -r "$CONFIG_TARGET" "$BACKUP_DIR"
        fi
    fi
}

restore_backup() {
    if [[ -z "$RESTORE" ]]; then
        log_error "[!] No backup directory provided for restore."
        exit 1
    fi
    if [[ ! -d "$RESTORE" ]]; then
        log_error "[!] Backup directory $RESTORE does not exist."
        exit 1
    fi
    log_info "[+] Restoring config from $RESTORE to $CONFIG_TARGET"
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would restore config from $RESTORE to $CONFIG_TARGET")
    else
        rm -rf "$CONFIG_TARGET"
        cp -r "$RESTORE" "$CONFIG_TARGET"
        log_success "[+] Restore complete."
    fi
    exit 0
}

remove_clone_dir() {
    if [[ -d "$CLONE_DIR" ]]; then
        if (( FORCE )) || (( UNATTENDED )); then
            log_info "[+] Removing existing $CLONE_DIR (--force or --unattended)."
            (( DRYRUN )) && DRYRUN_SUMMARY+=("Would remove $CLONE_DIR") || rm -rf "$CLONE_DIR"
        else
            read -p "[?] $CLONE_DIR exists. Remove and reclone? [y/N]: " REPLY
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "[+] Removing existing $CLONE_DIR."
                (( DRYRUN )) && DRYRUN_SUMMARY+=("Would remove $CLONE_DIR") || rm -rf "$CLONE_DIR"
            else
                log_error "[!] Aborting due to existing directory."
                exit 4
            fi
        fi
    fi
}

clone_repo() {
    log_info "[+] Cloning repo..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would run: git clone \"$REPO_URL\" \"$CLONE_DIR\"")
    else
        git clone "$REPO_URL" "$CLONE_DIR"
    fi
}

install_packages() {
    log_info "[+] Installing packages with pacman..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would run: pacman -Syu --needed --noconfirm ${PACKAGES[*]}")
    else
        # Force a database sync and update before installing
        $SUDO pacman -Syu --needed --noconfirm "${PACKAGES[@]}" || log_error "[!] pacman package installation failed."

        # Check if each package was successfully installed
        log_info "[+] Verifying package installation..."
        for pkg in "${PACKAGES[@]}"; do
            if pacman -Q "$pkg" &>/dev/null; then
                log_success "[+] Package '$pkg' installed successfully."
            else
                log_error "[!] Package '$pkg' failed to install."
            fi
        done
    fi
}

install_aur_packages() {
    local aur_helper=""
    for helper in yay paru trizen aura; do
        if command -v "$helper" &>/dev/null; then
            aur_helper="$helper"
            break
        fi
    done
    if [[ -n "$aur_helper" ]]; then
        log_info "[+] Installing AUR packages with $aur_helper..."
        if (( DRYRUN )); then
            DRYRUN_SUMMARY+=("Would run: $aur_helper -S --noconfirm ${AUR_PACKAGES[*]}")
        else
            "$aur_helper" -S --noconfirm "${AUR_PACKAGES[@]}" || log_error "[!] $aur_helper AUR package installation failed."
        fi
    else
        log_error "[!] No AUR helper found. Skipping AUR package installation."
    fi
}

merge_or_diff_dotfiles() {
    if [[ -d "$CONFIG_TARGET" ]]; then
        log_info "[+] Existing config directory found. Overwriting with new configs."
    else
        log_info "[+] No existing config found. Proceeding with installation."
    fi
}

copy_dotfiles() {
    log_info "[+] Copying dotfiles to ~/.config..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would run: rsync -avh --exclude='.git' \"$CONFIG_SOURCE/\" \"$CONFIG_TARGET/\"")
    else
        rsync -avh --exclude='.git' "$CONFIG_SOURCE/" "$CONFIG_TARGET/"
    fi
}

setup_theming() {
    log_info "[+] Applying theme and icons..."
    
    # Find the first available Laniakea GTK theme
    local gtk_theme=""
    for theme_dir in "$HOME/.themes/Laniakea-"*"-Gtk"; do
        if [[ -d "$theme_dir" ]]; then
            gtk_theme=$(basename "$theme_dir")
            break
        fi
    done
    
    # Find the first available Laniakea Kvantum theme
    local kvantum_theme=""
    for theme_dir in "$HOME/.config/Kvantum/Laniakea-"*"-Kvantum"; do
        if [[ -d "$theme_dir" ]]; then
            kvantum_theme=$(basename "$theme_dir")
            break
        fi
    done
    
    if (( DRYRUN )); then
        if [[ -n "$gtk_theme" ]]; then
            DRYRUN_SUMMARY+=("Would apply $gtk_theme theme via gsettings")
        else
            DRYRUN_SUMMARY+=("Would attempt to apply GTK theme, but no Laniakea GTK theme found")
        fi
        DRYRUN_SUMMARY+=("Would apply Tela-circle-dracula icon theme via qt6ct")
        if [[ -n "$kvantum_theme" ]]; then
            DRYRUN_SUMMARY+=("Would apply $kvantum_theme theme in Kvantum")
        else
            DRYRUN_SUMMARY+=("Would attempt to apply Kvantum theme, but no Laniakea Kvantum theme found")
        fi
    else
        # Set GTK theme using gsettings - finding the first available Laniakea theme
        if [[ -n "$gtk_theme" ]] && command -v gsettings &>/dev/null; then
            gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
            gsettings set org.gnome.desktop.interface icon-theme "Tela-circle-dracula"
            log_success "[+] Applied GTK theme '$gtk_theme' and icon theme via gsettings."
        else
            if [[ -z "$gtk_theme" ]]; then
                log_error "[!] No Laniakea GTK theme found to apply."
            fi
            if ! command -v gsettings &>/dev/null; then
                log_error "[!] gsettings command not found, skipping GTK theme application."
            fi
        fi

        # Set Qt theme via qt6ct
        mkdir -p "$HOME/.config/qt6ct"
        cat > "$HOME/.config/qt6ct/qt6ct.conf" << 'QT6CT_EOF'
[Appearance]
custom_palette=false
standard_dialogs=default
style=kvantum

[Fonts]
fixed="Sans Serif,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
general="Sans Serif,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"

[Interface]
activate_item_on_single_click=1
buttonbox_layout=0
cursor_flash_time=1000
dialog_buttons_have_icons=1
double_click_interval=400
gui_effects=@Invalid()
keyboard_scheme=2
menus_have_icons=true
show_shortcuts_in_context_menus=true
stylesheets=@Invalid()
toolbutton_style=4
underline_shortcut=1
wheel_scroll_lines=3

[SettingsWindow]
geometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\0\0\x5\0\0\0\0\0\0\0\b\xb3\0\0\x4\x6\0\0\x5\0\0\0\0\0\0\0\b\xb3\0\0\x4\x6\0\0\0\0\0\0\0\0\a\x80\0\0\x5\0\0\0\0\0\0\0\b\xb3\0\0\x4\x6)

[Troubleshooting]
force_raster_widgets=1
ignored_applications=@Invalid()

[Qt]
style=kvantum
QT6CT_EOF
        log_success "[+] Applied Qt theme and icons via qt6ct."
        
        # Create XDG config directories if they don't exist and ensure permissions
        mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
        chmod 755 "$HOME/.config" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" 2>/dev/null || true

        # Find the first available Laniakea Kvantum theme
        local kvantum_theme=""
        for theme_dir in "$HOME/.config/Kvantum/Laniakea-"*"-Kvantum"; do
            if [[ -d "$theme_dir" ]]; then
                kvantum_theme=$(basename "$theme_dir")
                break
            fi
        done
        
        # Apply Kvantum theme with verification
        local kvantum_config="$HOME/.config/Kvantum/kvantum.kvconfig"
        
        if [[ -n "$kvantum_theme" ]]; then
            # Create Kvantum config directory if it doesn't exist
            mkdir -p "$HOME/.config/Kvantum"
            
            if [[ -f "$kvantum_config" ]]; then
                sed -i "s/^theme=.*/theme=$kvantum_theme/" "$kvantum_config"
                log_success "[+] Applied Kvantum theme '$kvantum_theme' to existing config."
            else
                # Create the config file with the theme setting
                echo "[General]" > "$kvantum_config"
                echo "theme=$kvantum_theme" >> "$kvantum_config"
                log_success "[+] Created Kvantum config with theme '$kvantum_theme'."
            fi
            
            # Apply the theme using kvantummanager to ensure it's properly activated
            if command -v kvantummanager &>/dev/null; then
                # Wait a bit for the config to be written
                sleep 1
                if kvantummanager --set "$kvantum_theme" 2>/dev/null; then
                    log_success "[+] Kvantum theme '$kvantum_theme' successfully applied via kvantummanager."
                else
                    log_error "[!] Failed to apply Kvantum theme via kvantummanager."
                fi
            else
                log_error "[!] kvantummanager not found, but theme config was set."
            fi
        else
            log_error "[!] No Laniakea Kvantum theme found to apply."
        fi
        
        # Note: nwg-look is available but we'll rely on gsettings and config files
        # as they are more reliable for theme persistence
        if command -v nwg-look &>/dev/null; then
            log_info "[+] nwg-look is available, but relying on gsettings and config files for theme application."
        fi
        
        # Set GTK theme using XDG config files as another fallback method
        local config_dir="$HOME/.config"
        mkdir -p "$config_dir"
        
        # Update settings.ini file
        local settings_file="$config_dir/gtk-3.0/settings.ini"
        mkdir -p "$(dirname "$settings_file")"
        
        # Create or update the settings.ini file to set the theme
        {
            echo "[Settings]"
            echo "gtk-theme-name=$gtk_theme"
            echo "gtk-icon-theme-name=Tela-circle-dracula"
            echo "gtk-cursor-theme-name=capitaine-cursors"
            echo "gtk-cursor-theme-size=24"
            echo "gtk-application-prefer-dark-theme=1"
        } > "$settings_file"
        
        # Also create gtkrc file for GTK-2 applications
        local gtkrc_file="$HOME/.gtkrc-2.0"
        {
            echo "gtk-theme-name=\"$gtk_theme\""
            echo "gtk-icon-theme-name=\"Tela-circle-dracula\""
            echo "gtk-cursor-theme-name=\"capitaine-cursors\""
        } > "$gtkrc_file"
        
        # Create gtk-4 config directory if it doesn't exist and link to gtk-3 config
        mkdir -p "$config_dir/gtk-4.0"
        if [[ ! -f "$config_dir/gtk-4.0/settings.ini" ]]; then
            cp "$settings_file" "$config_dir/gtk-4.0/settings.ini" 2>/dev/null || true
        fi
        
        log_success "[+] GTK config files updated for GTK-3, GTK-4 and GTK-2 compatibility."
        
        # Set environment variables to ensure theme persistence across sessions
        local profile_file="$HOME/.profile"
        
        # Remove old theme settings if they exist
        sed -i '/# Niri-Laniakea Theme Settings/d' "$profile_file" 2>/dev/null || true
        sed -i '/export GTK_THEME/d' "$profile_file" 2>/dev/null || true
        sed -i '/export GTK2_RC_FILES/d' "$profile_file" 2>/dev/null || true
        
        # Add new theme settings to profile
        {
            echo ""
            echo "# Niri-Laniakea Theme Settings"
            echo "export GTK_THEME=$gtk_theme"
            echo "export GTK2_RC_FILES=$HOME/.gtkrc-2.0"
            echo "# Ensure gsettings is run after desktop environment loads"
            echo "(sleep 5 && gsettings set org.gnome.desktop.interface gtk-theme '$gtk_theme' 2>/dev/null) &"
            echo ""
        } >> "$profile_file"
        
        # Also add to .bashrc for terminal sessions
        local bashrc_file="$HOME/.bashrc"
        if [[ -f "$bashrc_file" ]]; then
            sed -i '/# Niri-Laniakea Theme Settings/d' "$bashrc_file" 2>/dev/null || true
            sed -i '/export GTK_THEME/d' "$bashrc_file" 2>/dev/null || true
            sed -i '/export GTK2_RC_FILES/d' "$bashrc_file" 2>/dev/null || true
            
            {
                echo ""
                echo "# Niri-Laniakea Theme Settings"
                echo "export GTK_THEME=$gtk_theme"
                echo "export GTK2_RC_FILES=$HOME/.gtkrc-2.0"
                echo ""
            } >> "$bashrc_file"
        fi
        
        log_success "[+] Added theme settings to user profile for session persistence."
    fi
}

setup_wallpaper() {
    # This function is kept as a placeholder to maintain script structure
    # but does nothing since static wallpaper is no longer supported
    :
}

install_gtk_kvantum_themes() {
    log_info "[+] Installing GTK-Kvantum themes..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would install GTK-Kvantum themes to ~/.themes and ~/.config/Kvantum")
        DRYRUN_SUMMARY+=("Would run: cp -r \"$CLONE_DIR/GTK-kvantum/\"* \"\$HOME/.themes/\"")
    else
        # Create themes directories
        mkdir -p "$HOME/.themes"
        mkdir -p "$HOME/.icons"  # Create icons directory for icon themes
        
        # Find and copy all theme subdirectories (like Laniakea-XXX-Gtk and Laniakea-XXX-Kvantum) to ~/.themes
        for theme_dir in "$CLONE_DIR/GTK-kvantum"/*/; do
            if [[ -d "$theme_dir" ]]; then
                # Copy each subtheme directory (like Laniakea-XXX-Gtk and Laniakea-XXX-Kvantum)
                for subtheme in "$theme_dir"*/; do
                    if [[ -d "$subtheme" ]]; then
                        theme_name=$(basename "$subtheme")
                        if [[ "$theme_name" == *"-Gtk"* ]]; then
                            # Copy GTK theme to ~/.themes
                            cp -r "$subtheme" "$HOME/.themes/"
                            log_info "[+] Installed GTK theme: $theme_name"
                        elif [[ "$theme_name" == *"-Kvantum"* ]]; then
                            # Copy Kvantum theme to ~/.config/Kvantum
                            cp -r "$subtheme" "$HOME/.config/Kvantum/"
                            log_info "[+] Installed Kvantum theme: $theme_name"
                        fi
                    fi
                done
            fi
        done
        log_success "[+] GTK-Kvantum themes installed to ~/.themes and ~/.config/Kvantum"
        
        # Also copy any icon themes if they exist in the theme directories
        find "$CLONE_DIR/GTK-kvantum" -name "*icon*" -type d -exec cp -r {} "$HOME/.icons/" \; 2>/dev/null || true
    fi
}

install_laniakea_live_wallpaper() {
    log_info "[+] Installing Laniakea Live Wallpaper..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would run: bash \"$CLONE_DIR/laniakea-live-wallpaper/install-laniakea-live-wallpaper.sh\"")
        DRYRUN_SUMMARY+=("Would run: systemctl --user daemon-reload")
        DRYRUN_SUMMARY+=("Would run: systemctl --user enable wallpaper.service")
        DRYRUN_SUMMARY+=("Would run: systemctl --user start wallpaper.service")
    else
        # Execute the live wallpaper installation script
        if [[ -f "$CLONE_DIR/laniakea-live-wallpaper/install-laniakea-live-wallpaper.sh" ]]; then
            bash "$CLONE_DIR/laniakea-live-wallpaper/install-laniakea-live-wallpaper.sh"
            log_success "[+] Laniakea Live Wallpaper installed."
            
            # Wait a bit for the installation to complete before starting services
            sleep 2
            
            # Reload and enable the wallpaper service (no timer - just sets wallpaper once)
            systemctl --user daemon-reload
            systemctl --user enable swww-daemon.service
            systemctl --user enable wallpaper.service  # Enable the service to run on session start
            
            # Start swww daemon first and wait for it to be ready
            systemctl --user start swww-daemon.service
            
            # Wait for swww daemon to be fully running
            local max_wait=10
            local count=0
            while [ $count -lt $max_wait ]; do
                if pgrep -f "swww-daemon" > /dev/null; then
                    log_info "[+] swww daemon is running."
                    break
                else
                    log_info "[+] Waiting for swww daemon... ($count/$max_wait)"
                    sleep 1
                    ((count++))
                fi
            done
            
            if [ $count -eq $max_wait ]; then
                log_error "[!] swww daemon did not start properly."
            else
                # Start the wallpaper service once to set the wallpaper
                systemctl --user start wallpaper.service
                log_success "[+] Laniakea Live Wallpaper services enabled and started."
            fi
        else
            log_error "[!] Laniakea Live Wallpaper installation script not found. Skipping."
        fi
    fi
}

setup_sddm() {
    log_info "[+] Setting up SDDM theme and configuration..."
    if command -v sddm &>/dev/null; then
        if (( DRYRUN )); then
            DRYRUN_SUMMARY+=("Would run: sudo cp -r \"$SDDM_THEME_SOURCE\" \"$SDDM_THEME_DEST\"")
            DRYRUN_SUMMARY+=("Would run: sudo cp \"$SDDM_CONF_SOURCE\" \"$SDDM_CONF_DEST\"")
        else
            if [[ ! -d "$SDDM_THEME_SOURCE" ]]; then
                log_error "[!] SDDM theme source directory not found at $SDDM_THEME_SOURCE. Aborting SDDM setup."
                return 1
            fi
            if [[ ! -f "$SDDM_CONF_SOURCE" ]]; then
                log_error "[!] SDDM config file not found at $SDDM_CONF_SOURCE. Aborting SDDM setup."
                return 1
            fi

            # Copy the theme folder
            $SUDO cp -r "$SDDM_THEME_SOURCE" "$SDDM_THEME_DEST"
            log_success "[+] SDDM theme copied to $SDDM_THEME_DEST."
            
            # Copy the sddm.conf file
            $SUDO cp "$SDDM_CONF_SOURCE" "$SDDM_CONF_DEST"
            log_success "[+] SDDM config copied to $SDDM_CONF_DEST."
        fi
    else
        log_error "[!] SDDM not detected. Skipping SDDM theme and config setup."
    fi
}

enable_lingering() {
    if $SUDO loginctl show-user "$USER" --property=Linger &>/dev/null; then
        log_info "[+] Enabling lingering for $USER..."
        if (( DRYRUN )); then
            DRYRUN_SUMMARY+=("Would run: $SUDO loginctl enable-linger \"$USER\"")
        else
            $SUDO loginctl enable-linger "$USER"
        fi
    else
        log_error "[!] loginctl not available or insufficient permissions. Skipping lingering enable."
    fi
}

reload_user_services() {
    log_info "[+] Reloading user systemd services..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would run: systemctl --user daemon-reload")
    else
        systemctl --user daemon-reload
        # Wait a bit for the reload to complete
        sleep 1
    fi
}

check_in_clone_dir() {
    if [[ "$PWD" == "$CLONE_DIR"* ]]; then
        log_error "[!] You are currently in the directory you're about to delete. Moving to home directory."
        if (( DRYRUN )); then
            DRYRUN_SUMMARY+=("Would run: cd ~")
        else
            cd ~
        fi
    fi
}

post_install_checks() {
    log_info "[+] Running post-install checks..."
    if (( DRYRUN )); then
        log_info "[+] Skipping post-install checks in dry-run mode."
        return
    fi
    for pkg in "${PACKAGES[@]}"; do
        pacman -Q "$pkg" &>/dev/null && log_success "Package $pkg installed." || log_error "Package $pkg NOT installed!"
    done
    [[ -d "$CONFIG_TARGET" ]] && log_success "$CONFIG_TARGET exists." || log_error "$CONFIG_TARGET missing!"
    # Static wallpaper is no longer used; live wallpaper is used instead, checked separately below
    
    # Check for any of the expected Laniakea GTK themes
    if [[ -d "$HOME/.themes/Laniakea-Cybersakura-Gtk" ]] || [[ -d "$HOME/.themes/Laniakea-Bluemoon-Gtk" ]] || [[ -d "$HOME/.themes/Laniakea-Dreamvapor-Gtk" ]] || [[ -d "$HOME/.themes/Laniakea-Duskrose-Gtk" ]] || [[ -d "$HOME/.themes/Laniakea-Shadowfern-Gtk" ]]; then
        log_success "GTK-Kvantum themes installed."
    else
        log_error "GTK-Kvantum themes missing!"
    fi
    
    # Check for Kvantum themes
    if [[ -d "$HOME/.config/Kvantum/Laniakea-Cybersakura-Kvantum" ]] || [[ -d "$HOME/.config/Kvantum/Laniakea-Bluemoon-Kvantum" ]] || [[ -d "$HOME/.config/Kvantum/Laniakea-Dreamvapor-Kvantum" ]] || [[ -d "$HOME/.config/Kvantum/Laniakea-Duskrose-Kvantum" ]] || [[ -d "$HOME/.config/Kvantum/Laniakea-Shadowfern-Kvantum" ]]; then
        log_success "Kvantum themes installed."
    else
        log_error "Kvantum themes missing!"
    fi
    
    [[ -f "$HOME/.config/laniakea-live-wallpaper/playwright_capture_wallpaper.py" ]] && log_success "Laniakea Live Wallpaper installed." || log_error "Laniakea Live Wallpaper missing!"
    
    # Check if icon theme is set correctly
    local current_icon_theme
    current_icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo "(command not available)")
    if [[ "$current_icon_theme" == *Tela-circle* ]]; then
        log_success "Icon theme properly set to: $current_icon_theme"
    else
        log_error "Icon theme not set correctly. Current: $current_icon_theme"
    fi
    
    # Check if GTK theme is set correctly (try gsettings first, then config files)
    local current_gtk_theme
    current_gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "(command not available)")
    if [[ "$current_gtk_theme" == *Laniakea*-Gtk* ]]; then
        log_success "GTK theme properly set to: $current_gtk_theme"
    else
        # If gsettings doesn't show the theme, check the config file
        local config_theme=""
        if [[ -f "$HOME/.config/gtk-3.0/settings.ini" ]]; then
            config_theme=$(grep "gtk-theme-name" "$HOME/.config/gtk-3.0/settings.ini" | cut -d'=' -f2 | tr -d '"' | xargs)
        elif [[ -f "$HOME/.gtkrc-2.0" ]]; then
            config_theme=$(grep "gtk-theme-name" "$HOME/.gtkrc-2.0" | cut -d'"' -f2)
        fi
        
        if [[ -n "$config_theme" && "$config_theme" == *Laniakea*-Gtk* ]]; then
            log_success "GTK theme properly configured in config files: $config_theme"
        else
            log_error "GTK theme not set correctly. Current (gsettings): $current_gtk_theme, Current (config): $config_theme"
        fi
    fi
}

dryrun_summary() {
    if (( DRYRUN )); then
        echo -e "${BLUE}\nDry-Run Summary:${NC}"
        for action in "${DRYRUN_SUMMARY[@]}"; do
            echo -e "${YELLOW}- $action${NC}"
        done
        echo -e "${BLUE}End of dry-run summary.${NC}"
    fi
}

uninstall() {
    log_info "[+] Uninstalling niri-laniakea setup..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would uninstall niri-laniakea-theme, restore backup, remove all installed packages and dotfiles")
    else
        # Remove dotfiles
        rm -rf "$CONFIG_TARGET"
        # Restore backup if exists
        local latest_backup
        latest_backup=$(ls -td "$HOME"/.config_backup_* 2>/dev/null | head -n 1)
        if [[ -n "$latest_backup" ]]; then
            cp -r "$latest_backup" "$CONFIG_TARGET"
            log_success "[+] Restored original config from $latest_backup"
        fi
        # Remove packages
        $SUDO pacman -Rs --noconfirm "${PACKAGES[@]}" 2>/dev/null || log_info "Some packages may not have been installed to begin with."
        # Remove AUR packages
        for aur_pkg in "${AUR_PACKAGES[@]}"; do
            $SUDO pacman -Rs --noconfirm "$aur_pkg" 2>/dev/null || log_info "AUR package $aur_pkg may not have been installed to begin with."
        done
        # Remove wallpaper
        rm -f "$WALLPAPER_DEST"
        # Remove GTK-Kvantum themes
        rm -rf "$HOME/.themes/Laniakea-*"
        # Remove Kvantum themes
        rm -rf "$HOME/.config/Kvantum/Laniakea-*"
        # Remove Laniakea Live Wallpaper files
        rm -rf "$HOME/Pictures/Wallpapers"
        rm -rf "$HOME/.config/laniakea-live-wallpaper"
        rm -f "$HOME/.config/systemd/user/swww-daemon.service"
        rm -f "$HOME/.config/systemd/user/wallpaper.service"
        log_success "[+] Uninstall complete."
    fi
    dryrun_summary
    exit 0
}

# --- Parse options ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        --dry-run)
            DRYRUN=1
            shift
            ;;
        --unattended)
            UNATTENDED=1
            shift
            ;;
        --restore)
            RESTORE="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL=1
            shift
            ;;
        *)
            usage
            ;;
    esac
done

main() {
    handle_sudo
    detect_distro
    check_dependencies
    update_system

    if (( UNINSTALL )); then
        uninstall
    fi

    if [[ -n "$RESTORE" ]]; then
        restore_backup
    fi

    check_for_update
    enable_lingering
    reload_user_services

    if [[ -d "$CLONE_DIR" && ! -d "$CLONE_DIR/.git" ]]; then
        log_error "[!] $CLONE_DIR exists but is not a valid git repo. Removing it."
        (( DRYRUN )) && DRYRUN_SUMMARY+=("Would remove invalid $CLONE_DIR") || rm -rf "$CLONE_DIR"
    fi

    check_in_clone_dir
    remove_clone_dir
    clone_repo
    install_packages
    install_aur_packages
    backup_config
    merge_or_diff_dotfiles
    copy_dotfiles
    install_gtk_kvantum_themes
    setup_theming
    setup_wallpaper
    install_laniakea_live_wallpaper
    setup_sddm
    post_install_checks
    dryrun_summary

    log_success "\nAll done! Enjoy the fresh Niri-laniakea setup with a beautiful live wallpaper which will be generated at every boot after a few seconds or with Mod+L\n"
}

main

trap - EXIT
