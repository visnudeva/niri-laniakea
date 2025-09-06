#!/bin/bash

action=$(echo -e "  Lock\n󰍃  Logout\n  Reboot\n  Shutdown\n󰤄  Suspend" | fuzzel --dmenu -p "")

case "$action" in
  *Lock*)
    swaylock || hyprlock || echo "No lock utility found"
    ;;
  *Logout*)
    loginctl kill-session "$XDG_SESSION_ID" --signal=SIGTERM
    ;;
  *Reboot*)
    systemctl reboot
    ;;
  *Shutdown*)
    systemctl poweroff
    ;;
  *Suspend*)
    systemctl suspend
    ;;
esac
