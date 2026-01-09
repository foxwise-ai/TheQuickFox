#!/bin/bash

# Code signing configuration for TheQuickFox
# 
# To use:
# 1. Update SIGNING_IDENTITY with your certificate name
# 2. Source this file in your build scripts

# Set your signing identity here
# Examples:
# - "Apple Development: John Doe (ABC123DEF)"
# - "Developer ID Application: John Doe (ABC123DEF)"
# - "-" for ad-hoc signing (default)

SIGNING_IDENTITY="-"

# Uncomment and update with your certificate name:
# SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)"

export SIGNING_IDENTITY