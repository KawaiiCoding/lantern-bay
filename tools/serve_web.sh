#!/bin/sh
# Serves the web build locally at http://localhost:8070
cd "$(dirname "$0")/../build/web" && python3 -m http.server 8070
