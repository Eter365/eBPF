# 程序名称
TARGET = loader
BPF_OBJ = hello.bpf.o
BPF_SKEL = hello.skel.h
BPF_PIN_PATH = /sys/fs/bpf/hello_world

# 编译器定义
CLANG = clang
INCLUDES = -I/usr/include -I/usr/include/bpf

# 编译选项
BPF_CFLAGS = -target bpf -g -O0 $(INCLUDES)
CFLAGS = -g -O2 -Wall $(INCLUDES)
LIBS = -lbpf -lelf -lz

.PHONY: all clean run load unload test show ls

all: $(TARGET)

$(BPF_OBJ): hello.bpf.c
	$(CLANG) $(BPF_CFLAGS) -c $< -o $@

$(BPF_SKEL): $(BPF_OBJ)
	bpftool gen skeleton $< > $@

$(TARGET): loader.c $(BPF_SKEL)
	$(CLANG) $(CFLAGS) $< $(LIBS) -o $@

# --- 核心功能 ---
# 修改后的 load: 明确创建链接 (Link)
load: $(BPF_OBJ)
	@# 1. 如果已存在，先清理
	-$(MAKE) unload
	@# 2. 加载程序并获取返回的程序 ID
	@echo "正在加载并挂载程序..."
	sudo bpftool prog load $(BPF_OBJ) $(BPF_PIN_PATH)
	@# 3. 关键步骤：手动创建 link。这步不执行，test 就没内容。
	#@PROG_ID=$$(sudo bpftool prog show name hello_world | awk -F: '{print $$1}' | head -n 1); \
	#sudo bpftool link create prog id $$PROG_ID type tracepoint name sys_enter_execve
	@echo "BPF 程序已成功挂载到 sys_enter_execve。"

# 修改后的 unload: 彻底断开链接
unload:
	@echo "--- 正在清理 BPF 对象 ---"
	@# 1. 查找并断开所有与 hello_world 相关的 link
	@for link_id in $$(sudo bpftool link show | grep -B 3 "hello_world" | grep "id:" | awk '{print $$2}'); do \
		echo "正在断开 Link ID: $$link_id"; \
		sudo bpftool link detach id $$link_id; \
	done
	@# 2. 查找并断开所有指向 tracepoint 的匿名链接 (作为兜底)
	@for link_id in $$(sudo bpftool link show | grep "tracepoint sys_enter_execve" | awk '{print $$1}' | tr -d ':'); do \
		echo "正在断开匿名 Link ID: $$link_id"; \
		sudo bpftool link detach id $$link_id; \
	done
	@# 3. 删除固定点文件
	-sudo rm -f $(BPF_PIN_PATH)
	@echo "清理完成。"


test:
	@echo "正在读取内核追踪管道 (trace_pipe)... 按 Ctrl+C 停止"
	sudo cat /sys/kernel/debug/tracing/trace_pipe

# --- 新增：调试选项 ---

# 1. 查看内核中程序的具体状态（ID, Tag, 指令数等）
show:
	@echo "--- 内核 BPF 程序状态 ---"
	sudo bpftool prog show name hello_world

# 2. 查看 BPF 文件系统中的固定对象
ls:
	@echo "--- /sys/fs/bpf 目录内容 ---"
	sudo ls -l /sys/fs/bpf

# --- 其他 ---

run: all
	@echo "启动前台加载器模式..."
	sudo ./$(TARGET)

clean: unload
	rm -f $(BPF_OBJ) $(BPF_SKEL) $(TARGET)
