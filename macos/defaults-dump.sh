#!/usr/bin/env bash
# macOS defaults — curated customizations only
# Run: ./defaults.sh (applies these) or ./defaults.sh --dry-run (preview)
set -euo pipefail

# --- Dock ---
defaults write com.apple.dock "autohide" -bool true
defaults write com.apple.dock "launchanim" -bool false
defaults write com.apple.dock "mru-spaces" -bool false
defaults write com.apple.dock "orientation" -string "right"
defaults write com.apple.dock "show-recents" -bool false

# --- Finder ---
defaults write com.apple.finder "AppleShowAllExtensions" -bool true
defaults write com.apple.finder "FXEnableExtensionChangeWarning" -bool false
defaults write com.apple.finder "ShowPathbar" -bool true
defaults write com.apple.finder "ShowStatusBar" -bool true
defaults write com.apple.finder "_FXSortFoldersFirst" -bool true

# --- Global ---
defaults write NSGlobalDomain "AppleShowAllExtensions" -bool true
defaults write NSGlobalDomain "NSAutomaticSpellingCorrectionEnabled" -bool false
defaults write NSGlobalDomain "NSAutomaticCapitalizationEnabled" -bool false
defaults write NSGlobalDomain "NSAutomaticDashSubstitutionEnabled" -bool false
defaults write NSGlobalDomain "NSAutomaticPeriodSubstitutionEnabled" -bool false
defaults write NSGlobalDomain "NSAutomaticQuoteSubstitutionEnabled" -bool false
defaults write NSGlobalDomain "AppleInterfaceStyle" -string "Dark"
defaults write NSGlobalDomain "InitialKeyRepeat" -int 15
defaults write NSGlobalDomain "KeyRepeat" -int 2

# --- Manual steps (cannot be set via defaults) ---
# Caps Lock → Control: System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys
# Display scaling: System Settings → Displays → choose scaling

# Restart affected services
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
