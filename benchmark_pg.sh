#!/bin/bash
# benchmark_pg.sh - 验证 bpftrace 对 PG 性能的影响

DB_NAME="eter"
DURATION=30
CLIENTS=10

echo "开始压测对比..."

# 1. 基准测试 (Baseline)
echo "--- 场景 1: Baseline (无追踪) ---"
pgbench -c $CLIENTS -T $DURATION -P 5 $DB_NAME > baseline.log 2>&1

# 2. 轻量追踪 (追踪事务开始)
echo "--- 场景 2: Light Tracing (追踪事务) ---"
# 在后台运行 bpftrace
sudo bpftrace -e 'usdt:/usr/local/pgsql/bin/postgres:transaction__start { @count = count(); }' > /dev/null 2>&1 &
BPF_PID=$!
sleep 2
pgbench -c $CLIENTS -T $DURATION -P 5 $DB_NAME > light.log 2>&1
sudo kill $BPF_PID

# 3. 重量追踪 (追踪 Buffer 读取)
echo "--- 场景 3: Heavy Tracing (追踪 Buffer) ---"
sudo bpftrace -e 'usdt:/usr/local/pgsql/bin/postgres:buffer__read__start { @count = count(); }' > /dev/null 2>&1 &
BPF_PID=$!
sleep 2
pgbench -c $CLIENTS -T $DURATION -P 5 $DB_NAME > heavy.log 2>&1
sudo kill $BPF_PID

# 汇总结果
echo "=== 压测结果汇总 ==="
echo "基准 TPS: $(grep 'tps =' baseline.log | awk '{print $3}')"
echo "轻量追踪 TPS: $(grep 'tps =' light.log | awk '{print $3}')"
echo "重量追踪 TPS: $(grep 'tps =' heavy.log | awk '{print $3}')"
