#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <bpf/libbpf.h>
#include "hello.skel.h"

static volatile int stop = 0;
void handle_sig(int sig) { stop = 1; }

int main() {
    struct hello_bpf *skel;
    
    // 1. 打开并加载
    skel = hello_bpf__open_and_load();
    if (!skel) {
        fprintf(stderr, "加载 BPF 失败\n");
        return 1;
    }

    // 2. 关键：自动附加到 tracepoint
    // 这步相当于执行了 bpftool link create，但在 C 代码里更稳定
    int err = hello_bpf__attach(skel);
    if (err) {
        fprintf(stderr, "附加 BPF 失败\n");
        hello_bpf__destroy(skel);
        return 1;
    }

    signal(SIGINT, handle_sig);
    printf("BPF 程序已启动并挂载！请保持此窗口开启...\n");

    while (!stop) {
        sleep(1); 
    }

    printf("\n正在清理并退出...\n");
    hello_bpf__destroy(skel);
    return 0;
}
