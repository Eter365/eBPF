#!/bin/bash

# 配置项
PG_BIN="/usr/local/pgsql/bin/postgres"
DB_NAME="eter"
DURATION=30
CLIENTS=16
LOADER_BIN="./loader" # 假设你的 C 加载器编译后的二进制文件名

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function run_pgbench() {
    local label=$1
    local output_file=$2
    echo -e "${GREEN}正在运行场景: $label...${NC}"
    pgbench -c $CLIENTS -T $DURATION -P 5 $DB_NAME > "$output_file" 2>&1
}

# 预热数据库
echo "预热中..."
pgbench -i -s 10 $DB_NAME > /dev/null

# --- 场景 1: Baseline ---
run_pgbench "Baseline (No Tracing)" "baseline.log"

# --- 场景 2: Full Tracing (无过滤，使用 bpftrace 模拟高频触发) ---
echo -e "${RED}启动全量追踪 (无过滤)...${NC}"
sudo bpftrace -e 'usdt:'$PG_BIN':transaction__start { @start[tid] = nsecs; } 
                  usdt:'$PG_BIN':transaction__commit /@start[tid]/ { delete(@start[tid]); @count++; }' > /dev/null 2>&1 &
BPF_PID=$!
sleep 2
run_pgbench "Full Tracing" "full_trace.log"
sudo kill $BPF_PID

# --- 场景 3: Smart Tracing (内核态过滤 > 10ms) ---
echo -e "${GREEN}启动定向追踪 (谓词过滤 > 10ms)...${NC}"
# 启动你的 C 语言加载器
sudo $LOADER_BIN > /dev/null 2>&1 &
LOADER_PID=$!
sleep 2
run_pgbench "Filtered Tracing (>10ms)" "filtered_trace.log"
sudo kill $LOADER_PID

# --- 结果分析 ---
echo -e "\n========================================"
echo -e "         PostgreSQL 性能压测报告"
echo -e "========================================"
printf "%-25s | %-15s | %-10s\n" "场景" "TPS" "平均延迟(ms)"
echo "--------------------------------------------------------"

for log in baseline.log full_trace.log filtered_trace.log; do
    tps=$(grep "tps =" $log | awk '{print $3}')
    lat=$(grep "latency average =" $log | awk '{print $4}')
    label=$(echo $log | cut -d'.' -f1)
    printf "%-25s | %-15s | %-10s\n" "$label" "$tps" "$lat"
done
