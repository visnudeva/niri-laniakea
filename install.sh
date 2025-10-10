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
    qt5-graphicaleffects qt6-5compat qt6-wayland satty sddm 
    swww swayidle swaylock thunar thunar-archive-plugin 
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
        log_info "[+] Existing config found. You can review and merge differences before overwrite."
        if (( DRYRUN )); then
            DRYRUN_SUMMARY+=("Would compare and optionally merge $CONFIG_SOURCE with $CONFIG_TARGET")
        else
            read -p "[?] Open config comparison with meld? [Y/n] (Press Enter for Yes, 'n' to skip): " REPLY
            if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
                if command -v meld &>/dev/null; then
                    meld "$CONFIG_TARGET" "$CONFIG_SOURCE"
                    log_info "[+] Review complete. Proceeding with overwrite."
                else
                    log_info "[+] meld not found, skipping comparison."
                fi
            else
                log_info "[+] Skipping config comparison."
            fi
        fi
    else
        log_info "[+] No existing config found. Proceeding with installation."
    fi
}

copy_dotfiles() {
    log_info "[+] Copying dotfiles to ~/.config..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would run: rsync -avh --exclude='.git' \"$CONFIG_SOURCE/\" \"$CONFIG_TARGET/\"")
        DRYRUN_SUMMARY+=("Would run: chmod +x \"$CONFIG_TARGET/fuzzel/fuzzel-logout.sh\"")
    else
        rsync -avh --exclude='.git' "$CONFIG_SOURCE/" "$CONFIG_TARGET/"
        chmod +x "$CONFIG_TARGET/fuzzel/fuzzel-logout.sh"
    fi
}

setup_theming() {
    log_info "[+] Applying theme and icons..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would apply Laniakea-Cybersakura theme via nwg-look")
        DRYRUN_SUMMARY+=("Would apply Tela-circle-dracula icon theme via qt6ct")
        DRYRUN_SUMMARY+=("Would apply Laniakea-Cybersakura theme in Kvantum")
    else
        # Set GTK theme using nwg-look
        gsettings set org.gnome.desktop.interface gtk-theme "Laniakea-Cybersakura"
        gsettings set org.gnome.desktop.interface icon-theme "Tela-circle-dracula"
        log_success "[+] Applied GTK theme and icon theme via nwg-look."

        # Set Qt theme via qt6ct
        mkdir -p "$HOME/.config/qt6ct"
        echo -e "[Qt]\nstyle=kvantum" > "$HOME/.config/qt6ct/qt6ct.conf"
        echo -e "[Icons]\ntheme=Tela-circle-dracula" >> "$HOME/.config/qt6ct/qt6ct.conf"
        log_success "[+] Applied Qt theme and icons via qt6ct."

        # Apply Kvantum theme
        local kvantum_config="$HOME/.config/Kvantum/kvantum.kvconfig"
        local kvantum_theme="Laniakea-Cybersakura-Kvantum"
        if [[ -f "$kvantum_config" ]]; then
            sed -i "s/^theme=.*/theme=$kvantum_theme/" "$kvantum_config"
            log_success "[+] Applied Kvantum theme '$kvantum_theme'."
        else
            log_error "[!] Kvantum config file not found at '$kvantum_config'. Skipping Kvantum theme setup."
        fi
    fi
}

setup_wallpaper() {
    # This function is kept for backward compatibility but will be skipped
    # since we're now using the laniakea-live-wallpaper
    log_info "[+] Skipping static wallpaper setup (using live wallpaper instead)..."
}

install_gtk_kvantum_themes() {
    log_info "[+] Installing GTK-Kvantum themes..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would install GTK-Kvantum themes to ~/.themes and ~/.config/Kvantum")
        DRYRUN_SUMMARY+=("Would run: cp -r \"$CLONE_DIR/GTK-kvantum/\"* \"\$HOME/.themes/\"")
    else
        # Create themes directory
        mkdir -p "$HOME/.themes"
        
        # Copy all GTK-Kvantum themes to ~/.themes
        cp -r "$CLONE_DIR/GTK-kvantum/"* "$HOME/.themes/"
        log_success "[+] GTK-Kvantum themes installed to ~/.themes"
    fi
}

install_laniakea_live_wallpaper() {
    log_info "[+] Installing Laniakea Live Wallpaper..."
    if (( DRYRUN )); then
        DRYRUN_SUMMARY+=("Would run: bash \"$CLONE_DIR/laniakea-live-wallpaper/install-laniakea-live-wallpaper.sh\"")
    else
        # Execute the live wallpaper installation script
        if [[ -f "$CLONE_DIR/laniakea-live-wallpaper/install-laniakea-live-wallpaper.sh" ]]; then
            bash "$CLONE_DIR/laniakea-live-wallpaper/install-laniakea-live-wallpaper.sh"
            log_success "[+] Laniakea Live Wallpaper installed."
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
    [[ -f "$WALLPAPER_DEST" ]] && log_success "Wallpaper at $WALLPAPER_DEST." || log_error "Wallpaper missing!"
    [[ -d "$HOME/.themes/Laniakea-Cybersakura-Gtk" ]] && log_success "GTK-Kvantum themes installed." || log_error "GTK-Kvantum themes missing!"
    [[ -f "$HOME/Pictures/Wallpapers/index.html" ]] && log_success "Laniakea Live Wallpaper installed." || log_error "Laniakea Live Wallpaper missing!"
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
        $SUDO pacman -Rs --noconfirm "${PACKAGES[@]}"
        # Remove AUR packages
        for aur_pkg in "${AUR_PACKAGES[@]}"; do
            $SUDO pacman -Rs --noconfirm "$aur_pkg"
        done
        # Remove wallpaper
        rm -f "$WALLPAPER_DEST"
        # Remove GTK-Kvantum themes
        rm -rf "$HOME/.themes/Laniakea-Cybersakura"*
        # Remove Laniakea Live Wallpaper files
        rm -rf "$HOME/Pictures/Wallpapers"
        rm -f "$HOME/.config/systemd/user/swww-daemon.service"
        rm -f "$HOME/.config/systemd/user/wallpaper.service"
        rm -f "$HOME/.config/systemd/user/wallpaper.timer"
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
    setup_theming
    setup_wallpaper
    install_gtk_kvantum_themes
    install_laniakea_live_wallpaper
    setup_sddm
    post_install_checks
    dryrun_summary

    log_success "\nAll done! niri-laniakea setup is complete, you now have a fresh Niri installation with its dotfiles and a beautiful wallpaper. Enjoy your new sleek system!\n"
}

main

trap - EXIT
