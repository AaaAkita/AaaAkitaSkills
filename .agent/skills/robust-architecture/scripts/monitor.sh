#!/bin/bash

# --- Robust Architecture Monitor Script ---
# 检查核心服务状态、磁盘空间和内存占用

echo "[$(date)] Starting health check..."

# 1. 检查磁盘空间 (阈值 90%)
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
  echo "WARNING: Disk usage is high: ${DISK_USAGE}%"
else
  echo "Disk status: OK (${DISK_USAGE}%)"
fi

# 2. 检查内存占用 (阈值 90%)
MEM_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
if [ "$MEM_USAGE" -gt 90 ]; then
  echo "WARNING: Memory usage is high: ${MEM_USAGE}%"
else
  echo "Memory status: OK (${MEM_USAGE}%)"
fi

# 3. 检查进程 (示例: 检查是否有名为 'node' 或 'python' 的进程)
# pgrep -x "node" > /dev/null && echo "Process 'node' is running" || echo "ERROR: 'node' process not found"

echo "[$(date)] Health check completed."
