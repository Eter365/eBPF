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

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, __u32);
    __type(value, __u32);
} xid_map SEC(".maps");

char LICENSE[] SEC("license") = "GPL";

// 1. SQL 进入时
SEC("uprobe//usr/local/pgsql/bin/postgres:exec_simple_query")
int handle_query_entry(struct user_pt_regs *ctx) {
    __u32 pid = bpf_get_current_pid_tgid() >> 32;
    char query[128];
    bpf_probe_read_user_str(&query, sizeof(query), (void *)ctx->regs[0]);

    __u32 *xid = bpf_map_lookup_elem(&xid_map, &pid);
    bpf_printk("PG_SQL [PID:%u] [XID:%u] SQL:%s\n", pid, xid ? *xid : 0, query);
    return 0;
}

// 2. 核心：Hook 事务 ID 获取函数的返回处
// 如果 GetTopTransactionId 也没有，请尝试 GetCurrentTransactionId
SEC("uretprobe//usr/local/pgsql/bin/postgres:GetTopTransactionId")
int handle_get_xid_exit(struct user_pt_regs *ctx) {
    __u32 pid = bpf_get_current_pid_tgid() >> 32;
    __u32 xid = (__u32)ctx->regs[0]; // ARM64 返回值在 x0

    if (xid != 0) {
        bpf_map_update_elem(&xid_map, &pid, &xid, BPF_ANY);
        bpf_printk("PG_XID_ASSIGNED [PID:%u] [XID:%u]\n", pid, xid);
    }
    return 0;
}

// 3. 事务结束清理
SEC("uprobe//usr/local/pgsql/bin/postgres:CommitTransaction")
int handle_commit(struct user_pt_regs *ctx) {
    __u32 pid = bpf_get_current_pid_tgid() >> 32;
    bpf_map_delete_elem(&xid_map, &pid);
    return 0;
}
