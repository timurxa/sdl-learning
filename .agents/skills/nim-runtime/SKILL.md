---
name: nim-runtime
description: Use this skill whenever running, compiling, benchmarking, or testing Nim code. Prefer optimized release/LTO builds for normal execution and ensure every launched task has a bounded lifetime and is finished or terminated.
---

# Nim Runtime Workflow

Use optimized Nim builds by default, while keeping development and diagnostic exceptions explicit. Never leave a compiler, test, benchmark, server, or other child process running indefinitely.

## Build and run defaults

For normal runs, include both defines:

```sh
nim c -d:release -d:lto path/to/program.nim
```

Use the same flags with `nim r`, `nim c -r`, tests, and benchmarks when supported. Omit them only when debugging, investigating a release-only issue, or when a tool explicitly requires another build mode; state the reason.

## Task lifetime

Every command that may run for a while must have a clear completion condition and a timeout appropriate to the task. Prefer bounded invocations, for example:

```sh
timeout 120s nim c -r -d:release -d:lto path/to/program.nim
```

When the task completes, stop any server or background process it started. If it hangs, reaches its timeout, or the user cancels it, terminate the process and its children, then verify that it exited. Do not leave watchers, servers, or test runners alive after handing back control.

For interactive or intentionally persistent programs, keep the process only while actively needed, record how to stop it, and kill it before finishing the task unless the user explicitly requests that it remain running.
