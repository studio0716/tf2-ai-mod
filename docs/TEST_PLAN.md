# TF2 Ralphy - Live Game Test Plan

## Overview
This document outlines the test plan for verifying `tf2_Ralphy` agents against a live Transport Fever 2 game instance. The goal is to ensure that agents can correctly query game state, execute commands, and observe changes in the game world.

## Prerequisites
1.  **Game Running**: Transport Fever 2 must be running.
2.  **Mod Loaded**: `AI_Optimizer_1` mod (symlinked to `local_ai_builder`) must be enabled in the active save game/new game.
3.  **IPC Connection**: The game must be polling `/tmp/tf2_llm_command.json`.

## Test Scenarios

### 1. Connectivity & State Monitoring (Surveyor)
*   **Objective**: Verify Surveyor can connect and read state.
*   **Steps**:
    1.  Start Surveyor agent.
    2.  Send `query_game_state`.
    3.  **Assert**: Response contains valid `year`, `money` (strings).
    4.  Send `query_towns`.
    5.  **Assert**: Response is a list of towns with names and populations.

### 2. Line Management (Builder)
*   **Objective**: Verify Builder can create and manage lines.
*   **Steps**:
    1.  Identify two stations (from `query_stations` or created via `build_station` if available). *Fallback: Use existing stations in a save.*
    2.  Send `create_line` command (Road, Passenger) between Station A and Station B.
    3.  **Assert**: Response contains `line_id`.
    4.  Send `query_lines`.
    5.  **Assert**: New line appears in the list.
    6.  Send `delete_line`.
    7.  **Assert**: Line disappears from `query_lines`.

### 3. Financial Integration (Accountant)
*   **Objective**: Verify Accountant receives financial data.
*   **Steps**:
    1.  Start Surveyor and Accountant.
    2.  Wait for Surveyor to broadcast `state_delta`.
    3.  **Assert**: Accountant processes the delta and updates its internal ledger (verify via logs or internal state dump).

### 4. Full Orchestration (Planner)
*   **Objective**: Verify the "Brain" can direct the "Hands".
*   **Steps**:
    1.  Start all agents via `orchestrator.py`.
    2.  Inject a "Low Cash" scenario (simulated or real if possible).
    3.  **Assert**: Planner enters "Emergency Mode" (check logs).
    4.  Inject a "Profitable Opportunity" (via mock Strategist message or manually trigger).
    5.  **Assert**: Planner creates a Task.
    6.  **Assert**: Builder picks up the Task.

## Execution Strategy
We will use a custom `live_test_runner.py` script that acts as an external controller, sending commands via `IPCClient` and asserting results. This bypasses the full agent loop for isolated testing, then runs the full orchestrator for system testing.

## Recovery
If tests fail (timeout/hang):
1.  Kill game process.
2.  Run `restart_tf2.sh`.
3.  Wait for load.
4.  Retry.
