#!/bin/bash

echo "Starting Jenkins build..."
sleep 1

echo "[INFO] Checking out repository..."
sleep 2
echo "[INFO] Repository checkout successful."
sleep 1

echo "[INFO] Running unit tests..."
sleep 3
echo "[INFO] Tests completed: 45 passed, 0 failed."
sleep 1

echo "[INFO] Building the project..."
sleep 2
echo "[INFO] Build step 1 completed."
sleep 1
echo "[INFO] Build step 2 completed."
sleep 1
echo "[INFO] Running final packaging step..."
sleep 2

# Simulate a failure
echo "[ERROR] Packaging failed: Missing dependency xyz.jar"
sleep 1

echo "Build failed. See logs for details."
exit 1
