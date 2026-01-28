#!/bin/bash
# Fast restart script for TF2
echo "Killing Transport Fever 2..."
pkill -9 -f "TransportFever2"
pkill -9 "Transport Fever 2"

echo "Launching via Steam..."
open "steam://run/1066780"
sleep 15
echo "Waiting for menu interaction..."
/usr/local/bin/python click_menu.py

echo "Waiting for game to load (20s)..."
sleep 15

echo "Done. Game should be loading."
