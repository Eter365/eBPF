#ifndef __TARGET_ARCH_arm64
#define __TARGET_ARCH_arm64
#endif

#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

struct user_pt_regs {
    unsigned long regs[31];
    unsigned long sp;
    unsigned long pc;
    unsigned long pstate;
};

// 存储事务 ID
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, __u32);
    __type(value, __u32);
} xid_map SEC(".maps");

// 存储 SQL 开始时间戳 (纳秒)
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, __u32);
    __type(value, __u64);
} start_map SEC(".maps");

char LICENSE[] SEC("license") = "GPL";

// 1. SQL 进入时：记录时间戳和 SQL 内容
SEC("uprobe//usr/local/pgsql/bin/postgres:exec_simple_query")
int handle_query_entry(struct user_pt_regs *ctx) {
    __u32 pid = bpf_get_current_pid_tgid() >> 32;
    __u64 ts = bpf_ktime_get_ns();

    // 记录开始时间
    bpf_map_update_elem(&start_map, &pid, &ts, BPF_ANY);
    
    return 0;
}

// 2. 事务 ID 获取 (保持原样)
SEC("uretprobe//usr/local/pgsql/bin/postgres:GetTopTransactionId")
int handle_get_xid_exit(struct user_pt_regs *ctx) {
    __u32 pid = bpf_get_current_pid_tgid() >> 32;
    __u32 xid = (__u32)ctx->regs[0]; 

    if (xid != 0) {
        bpf_map_update_elem(&xid_map, &pid, &xid, BPF_ANY);
    }
    return 0;
}

// 3. 核心：在提交时计算耗时并过滤
SEC("uprobe//usr/local/pgsql/bin/postgres:CommitTransaction")
int handle_commit(struct user_pt_regs *ctx) {
    __u32 pid = bpf_get_current_pid_tgid() >> 32;
    __u64 end_ts = bpf_ktime_get_ns();
    __u64 *start_ts = bpf_map_lookup_elem(&start_map, &pid);

    if (start_ts) {
        __u64 duration_ns = end_ts - *start_ts;
        
        // --- 谓词过滤：10ms = 10,000,000 ns ---
        if (duration_ns > 10000000) {
            __u32 *xid = bpf_map_lookup_elem(&xid_map, &pid);
            
            // 只有超过 10ms 才会触发 printk 输出
            // 注意：在实际生产中，建议通过 Ring Buffer 把结果传给用户态，printk 仅供调试
            bpf_printk("SLOW_PG [PID:%u] [XID:%u] Latency:%llu ms\n", 
                        pid, xid ? *xid : 0, duration_ns / 1000000);
        }
    }

    // 清理 Map，防止内存泄漏
    bpf_map_delete_elem(&start_map, &pid);
    bpf_map_delete_elem(&xid_map, &pid);
    return 0;
}
