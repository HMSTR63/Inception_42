# Low-Level Container Architecture: The Kernel Illusion 🐋

> **A Deep Reference Guide to OS Containerization, Kernel Primitives, and OverlayFS.**

## Table of Contents

1. [The Core Philosophy](#1-the-core-philosophy)
2. [Namespaces: The Walls of Isolation](#2-namespaces-the-walls-of-isolation)
3. [Control Groups (Cgroups): The Resource Brakes](#3-control-groups-cgroups-the-resource-brakes)
4. [The OOM Killer & The Zombie Problem](#4-the-oom-killer--the-zombie-problem)
5. [Linux Capabilities: The Castrated Root](#5-linux-capabilities-the-castrated-root)
6. [The Spark of Life: execve](#6-the-spark-of-life-execve)
7. [Storage: OverlayFS and UnionFS](#7-storage-overlayfs-and-unionfs)
8. [The workdir & Atomic Operations](#8-the-workdir--atomic-operations)

---

## 1. The Core Philosophy

A container is **not** a Virtual Machine. A VM pretends to be a full computer — it has a fake CPU, fake RAM, a fake hard drive, and its own copy of a complete operating system. When you boot a VM, you are booting a whole new OS on top of fake hardware. This is powerful but very heavy and slow to start.

A container is something much simpler and much lighter. It is just a **normal Linux process** — the same kind of process as when you open a browser or run a script. The difference is that this process has been put into a kind of "box" by the Linux kernel. From inside the box, the process thinks it owns the whole machine. From outside the box, the host can see it is just another process with a regular PID.

This "box" is not a physical thing. It is not a separate piece of software. It is a set of rules that the kernel enforces. The kernel creates the illusion. Your application believes it has its own filesystem, its own list of processes, its own network card, its own hostname. None of this is real. It is all an illusion built out of three kernel primitives:

- **Namespaces** — control what the process can _see_
- **Cgroups** — control what the process can _use_
- **Capabilities** — control what the process can _do_

The runtime engine (Docker, containerd, runc) is just a helper. Its job is to set up these three things correctly and then get out of the way. Once it calls `execve()`, the runtime is gone and your application is alive inside the illusion.

---

## 2. Namespaces: The Walls of Isolation

A namespace wraps one type of global resource and gives the process inside it a private copy. The process inside can do whatever it wants with its private copy — the host does not care and is not affected.

Linux has **8 different namespace types**. Each one isolates a different part of the system. Docker uses most of them by default.

---

### 2.1 PID Namespace — Hiding the Real Process IDs

Every process on Linux has a Process ID (PID). PID numbers are global — if you have 500 processes running, each one has a unique number from 1 to some big number. PID 1 is always the first process the kernel starts (`init` or `systemd`) and it is special — it is the parent of all other processes.

When the runtime creates a **PID namespace**, the kernel creates a fresh, empty process ID space just for the container. The first process that starts inside the container gets PID 1 in that private namespace. To the container, it is the king of the machine. To the host, this same process has a completely different, high-numbered PID like `3452`.

```
Host sees:        PID 3452  (runc + your app)
Container sees:   PID 1     (your app)
```

This double identity is real and you can inspect it from the host:

```bash
cat /proc/3452/status | grep NSpid
# NSpid:  3452    1
#          ^host   ^inside container
```

**Why PID 1 is dangerous if you get it wrong**

PID 1 has a very special behaviour in Linux: **it is immune to any signal it does not explicitly handle**. If you send `SIGTERM` (the polite "please shut down" signal) to a normal process, it will die. If you send `SIGTERM` to PID 1 and PID 1 does not have a handler for it, the kernel silently throws the signal away.

This means if your container's PID 1 is just a raw application like `node server.js` or `python app.py`, and you run `docker stop`, Docker sends `SIGTERM` to PID 1, nothing happens, Docker waits 10 seconds, and then sends `SIGKILL` (signal 9, which cannot be caught or ignored). Your app is killed forcefully with no chance to save data, close connections, or flush buffers. This is a very common source of data corruption and slow container shutdowns.

---

### 2.2 Mount Namespace — The Private Filesystem

Every process on Linux sees a filesystem starting from `/`. The mount namespace lets a container have its **own completely different filesystem tree**. When the container opens `/etc/nginx/nginx.conf`, it is looking at a completely different file than the host's `/etc/nginx/nginx.conf`. They share nothing.

To make this work, the runtime uses a syscall called `pivot_root`. This is more secure than the older `chroot` command. Here is what happens step by step:

**Step 1:** The runtime unpacks the Docker image (all its layers) into a directory on the host. Let's call it `/var/lib/docker/overlay2/abc123/merged`. This directory looks like a complete Linux filesystem with `/bin`, `/etc`, `/usr`, etc.

**Step 2:** The runtime calls `pivot_root(new_root, put_old)`. This syscall tells the kernel: "for this process, make `new_root` the new `/`. Put the old `/` temporarily at `put_old`."

**Step 3:** The runtime immediately unmounts `put_old`. Now the container has zero path back to the real host filesystem. It is fully caged.

`chroot` is weaker because a root process can escape it with a series of `chdir("..")` calls if the filesystem is set up carelessly. `pivot_root` changes the actual mount point at the kernel level — there is no directory to climb out of.

---

### 2.3 Network Namespace — The Private Network Card

A network namespace gives the container its own **completely isolated network stack**. This means:

- Its own network interfaces (like a private `eth0`)
- Its own IP addresses
- Its own routing table (the list of "where should I send this packet?")
- Its own firewall rules (`iptables`)
- Its own ports — the container can listen on port 80 even if the host already has something on port 80

**How the container talks to the outside world**

The kernel can create a **virtual ethernet pair** (`veth`). Think of it as a pipe made of two ends. One end lives inside the container's network namespace (named `eth0` inside). The other end lives on the host (named something like `veth3f1a92b`). Anything you put in one end comes out the other.

The host end is attached to a software bridge called `docker0`. The bridge is like a virtual network switch. All containers are plugged into this switch. The host uses `iptables` rules to do NAT (Network Address Translation) — it rewrites the container's outbound packets so they look like they came from the host's real IP address, then rewrites the incoming reply packets back.

```
[Container eth0: 172.17.0.2] <--veth pair--> [docker0 bridge: 172.17.0.1] <--NAT--> [Internet]
```

**Port publishing** (`-p 8080:80`) is also just an iptables rule:

```bash
# Docker adds this rule when you use -p 8080:80
iptables -t nat -A DOCKER -p tcp --dport 8080 \
  -j DNAT --to-destination 172.17.0.2:80
```

Any packet arriving at the host on port 8080 gets its destination address rewritten to the container's private IP and port 80, then is forwarded across the bridge.

---

### 2.4 UTS Namespace — The Private Hostname

UTS stands for "UNIX Time-sharing System" — it is the namespace that isolates the hostname and NIS domain name. When a container sets its hostname to `webserver-prod`, the host's hostname is completely unaffected. The `uname -n` command inside the container returns the container's own hostname.

---

### 2.5 IPC Namespace — The Private Message Queues

IPC stands for "Inter-Process Communication". Linux provides shared memory segments, semaphores, and message queues that processes can use to talk to each other. The IPC namespace makes these resources private. A process inside the container cannot access IPC objects created by the host or by other containers. This prevents accidental (or malicious) communication across container boundaries.

---

### 2.6 User Namespace — Fake Root

The User namespace is the most powerful and most complex. It maps user IDs and group IDs between inside and outside the container.

The most important use: **UID 0 inside the container maps to an unprivileged UID outside**.

For example, when you run a rootless container, the "root" user inside the container is actually mapped to UID 100000 on the host. If the container is compromised and an attacker escapes the container boundary, they land on the host as UID 100000 — a completely powerless, unprivileged user. They cannot read root's files, cannot kill other processes, cannot modify the system.

The mapping is defined in `/etc/subuid` on the host:

```
youruser:100000:65536
# means: UID 0 in container = UID 100000 on host
#        UID 1 in container = UID 100001 on host
#        ... and so on for 65536 UIDs
```

---

## 3. Control Groups (Cgroups): The Resource Brakes

Namespaces control what you can see. Cgroups (Control Groups) control **how much you can use**. Without cgroups, a single container running a bad process — or just a very heavy workload — could eat all the RAM, all the CPU, all the disk I/O on the host, and crash every other container running there. Cgroups are the reason multi-tenant container platforms work.

---

### 3.1 How Cgroups Work: Everything is a File

Cgroups are exposed to the system through a **Virtual File System (VFS)**. A virtual filesystem looks like a real directory on disk, but it is not. When you read a file in it, the kernel runs code to generate the content on the fly. When you write to a file in it, the kernel runs code to apply the value.

Cgroups live at `/sys/fs/cgroup`. Every container gets a directory (called a "cgroup") inside there. Inside that directory, there are files for every resource you can limit.

```bash
ls /sys/fs/cgroup/system.slice/docker-abc123.scope/
# cpu.max  memory.max  memory.current  io.max  pids.max  cpu.stat ...
```

To set a limit, you literally just write a number to a file:

```bash
# Set 256MB memory limit (cgroups v2 syntax):
echo "268435456" > /sys/fs/cgroup/…/memory.max

# This is exactly what Docker does under the hood when you run:
docker run --memory=256m myapp
```

The kernel watches these files. The moment a process in the cgroup tries to allocate memory beyond `memory.max`, the kernel refuses the allocation and triggers the OOM Killer.

---

### 3.2 Memory Limits: The --memory-swap Trap

This is one of the most misunderstood parts of Docker. The `--memory-swap` flag does **not** set how much swap space the container gets. It sets the **total combined budget of RAM + swap**.

| What you type                      | RAM limit | Swap space          | Total budget     |
| ---------------------------------- | --------- | ------------------- | ---------------- |
| `--memory=256m` only               | 256 MB    | 256 MB (default)    | 512 MB           |
| `--memory=256m --memory-swap=512m` | 256 MB    | 256 MB of swap      | 512 MB total     |
| `--memory=256m --memory-swap=256m` | 256 MB    | **0 MB (disabled)** | 256 MB hard wall |
| `--memory=256m --memory-swap=-1`   | 256 MB    | Unlimited           | No swap cap      |

The third row is the one you usually want in production: both values are the same, so the math (total - RAM = 0) means the container gets zero swap. The moment it hits 256 MB of RAM, the OOM Killer fires. This is predictable and fast.

The first row (most common mistake) means the container can actually use 512 MB total before dying — it will just start swapping to disk silently, making your app slow with no obvious reason why.

---

### 3.3 CPU Limits: Three Different Knobs

**`--cpus` — hard quota**

This sets a hard ceiling on CPU time. `--cpus=1.5` means the container can use at most 1.5 CPU-seconds worth of CPU time every second, no matter how many cores the host has. Under the hood this sets two files in the cgroup:

```bash
# cpu.max contains "quota period"
cat /sys/fs/cgroup/…/cpu.max
# 150000 100000
# meaning: 150,000 microseconds of CPU per 100,000 microsecond period = 1.5 CPUs
```

**`--cpu-shares` — relative weight**

This is not a hard limit. It is a **relative priority**. The default value is 1024. If container A has shares=1024 and container B has shares=2048, and the host is at 100% CPU load, container B gets twice as much CPU time as A. But if the host has idle CPU, both get as much as they want — shares only matter when there is competition.

**`--cpuset-cpus` — pin to specific cores**

This tells the kernel: only schedule this container's processes on these specific CPU cores. `--cpuset-cpus="0,2"` means cores 0 and 2 only. This is used in performance-critical applications where you want to avoid the overhead of the scheduler moving your process between cores (which can invalidate CPU cache).

---

### 3.4 Dynamic Updates: Changing Limits Without Restarting

Because cgroups are just files, you can change limits on a **running container**. Docker exposes this with `docker update`. The kernel applies the new limit immediately — no restart needed, no downtime.

```bash
# Double the memory limit of a running container, live:
docker update --memory=512m --memory-swap=512m my-container
```

Under the hood Docker just writes the new value to `memory.max`. The kernel picks it up immediately. This is why cgroup-based limits are so powerful — they are live, hot-reloadable resource controls.

---

## 4. The OOM Killer & The Zombie Problem

### 4.1 The OOM Killer: How It Picks a Victim

When a container hits its memory limit and there is no more memory to reclaim (no old cache pages to evict), the kernel is in a crisis. A process is asking for memory and the kernel cannot give it. If the kernel just returns "out of memory" to the process, most programs will crash in undefined ways. So the kernel makes a hard choice: **kill something**.

The Out-Of-Memory (OOM) Killer picks a process and kills it with `SIGKILL` (signal 9 — cannot be caught, cannot be blocked, cannot be ignored). The process dies instantly.

But which process does it kill? The kernel calculates an `oom_score` for every process in the cgroup. The score is roughly:

```
oom_score = (how much RAM this process uses / total RAM) × 1000
```

The higher the score, the more RAM the process is using, and the more "worthwhile" it is to kill it (freeing the most memory). The process with the highest score gets killed.

You can read any process's current score and even adjust it:

```bash
cat /proc/1234/oom_score      # read current score (0–1000)
cat /proc/1234/oom_score_adj  # read the manual adjustment (-1000 to +1000)

# Protect a critical process from ever being killed:
echo -500 > /proc/$(pgrep redis-server)/oom_score_adj
```

Setting `oom_score_adj` to `-1000` makes the process completely immune to the OOM Killer. Setting it to `+1000` makes it the first to die under memory pressure.

---

### 4.2 Exit Code 137: What It Means

When Docker reports `Exit Code 137`, this means the container's PID 1 was killed by `SIGKILL`. The math is: 128 (base for "killed by signal") + 9 (SIGKILL number) = 137.

But `SIGKILL` has two possible senders:

1. The **OOM Killer** — because the container ran out of memory
2. **Docker itself** — when you run `docker stop`, Docker sends `SIGTERM` to PID 1 first, waits 10 seconds for graceful shutdown, and if PID 1 is still running, escalates to `SIGKILL`

To know which one happened, check the inspect output:

```bash
docker inspect my-container | grep OOMKilled
# "OOMKilled": true    ← memory was the problem
# "OOMKilled": false   ← something else killed it (probably SIGKILL timeout)
```

---

### 4.3 The Survivor Scenario: Container Stays Up After OOM

Here is a subtle scenario that trips people up. Imagine your container runs PID 1 (`bash`) and a child process (`python worker.py`). The worker is using a lot of RAM. The OOM Killer calculates scores and decides to kill the worker — not PID 1.

The worker dies. `bash` (PID 1) is still alive. **The container keeps running.** From Docker's perspective, the container is healthy. Your application is silently broken.

This is why proper monitoring matters — you should watch for `oom_score` events in the system journal (`journalctl -k | grep oom`) and alert on them, not just on container exit.

---

### 4.4 Zombie Processes: The Reaping Problem

When a process dies in Linux, it does not disappear immediately. It moves to a special state called **Zombie** (shown as `Z` or `<defunct>` in `ps aux`). The zombie is not using CPU, not using memory. It is just a record in the process table that says "this process died and its exit status has not been read yet."

The exit status stays there until the **parent process** calls `wait()` or `waitpid()`. This is called "reaping" the zombie. Once the parent reads the exit status, the kernel removes the zombie from the table completely.

This is normally fine. But here is the problem inside a container:

- Normal Unix: if a parent dies before reaping its children, the orphaned children are adopted by **PID 1** (the real init system), which runs an infinite loop calling `waitpid()` to reap them constantly.
- Inside a container: PID 1 is usually your app — `nginx`, `node`, a Python script. **These programs do not run `waitpid()` in a loop**. They were not written to be an init system.

The result: every time a child process dies inside your container, it becomes a zombie. It stays in the process table forever. Over time they accumulate. Eventually the container hits the kernel's process table limit and cannot spawn any new processes — even simple things like `ls` fail with "cannot fork". The container appears healthy but is completely broken.

**The fix: use a real init as PID 1**

Tools like `tini` and `dumb-init` are tiny programs whose entire purpose is:

1. Start your real application as a child process
2. Forward all signals (like SIGTERM) to that child
3. Loop forever calling `waitpid()` to reap any zombies

```bash
# Option 1: Docker's built-in flag (uses tini internally)
docker run --init myapp

# Option 2: Add tini to your Dockerfile explicitly
FROM debian:bookworm-slim
RUN apt-get install -y tini
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]
```

The `--` separator in the `ENTRYPOINT` array tells tini "everything after this is the command to run as your child". Tini becomes PID 1. Your app runs as PID 2 (or higher). Tini reaps zombies and forwards signals. Problem solved.

---

## 5. Linux Capabilities: The Castrated Root

### 5.1 The Problem with Binary Root

Traditional Unix had a simple rule: either you are root (UID 0) and you can do **everything**, or you are not root and you can do almost nothing privileged. There was no middle ground.

This is a security disaster for containers. A web server inside a container needs to do exactly one privileged thing: bind to port 80. That is it. But under the old model, to bind to port 80 it must run as root — and if it runs as root, it also has the power to load kernel modules, mount filesystems, manipulate hardware, and escape the container entirely if it finds a bug.

Linux Capabilities solve this by **splitting root's powers into about 40 individual units**. You can grant a process exactly the capabilities it needs and nothing else.

---

### 5.2 The Three Capability Sets

Every process has three sets of capabilities, stored as bitmasks:

**Permitted** — the hard ceiling. This is the maximum set of capabilities the process is ever allowed to have. Even if the process tries to gain more capabilities, it cannot go beyond what is in the Permitted set. This is set at container start and cannot be increased without a new container.

**Effective** — what is actually active right now. The kernel checks this set for every privileged operation. A capability can be in the Permitted set but not the Effective set — meaning the process holds it but is not using it. The process can move capabilities from Permitted to Effective and back, but cannot add anything that is not in Permitted.

**Inheritable** — what gets passed to child processes when the process calls `execve()`. Combined with file capability bits (metadata stored on the executable file itself) to determine what a freshly exec'd program gets.

---

### 5.3 Docker's Default Whitelist

Docker does not give containers root's full power. It uses a whitelist — only these capabilities are on by default:

| Capability                  | What it allows                                   | Why it is on by default                              |
| --------------------------- | ------------------------------------------------ | ---------------------------------------------------- |
| `CAP_CHOWN`                 | Change file ownership (UID/GID)                  | Package managers and build steps need this           |
| `CAP_DAC_OVERRIDE`          | Bypass file read/write/execute permissions       | Many daemons need to read files owned by other users |
| `CAP_NET_BIND_SERVICE`      | Bind to ports below 1024 (80, 443)               | Web servers and databases need standard ports        |
| `CAP_SETUID` / `CAP_SETGID` | Change the process's own UID/GID                 | Servers that drop privileges after startup           |
| `CAP_KILL`                  | Send signals to processes of other users         | Process supervisors and service managers             |
| `CAP_NET_RAW`               | Use raw and packet sockets                       | The `ping` command needs this                        |
| `CAP_FOWNER`                | Bypass permission checks for files you don't own | Some installation scripts need this                  |

---

### 5.4 The Dangerous Blacklist (Always Stripped)

These capabilities are always removed and should never be restored unless you know exactly what you are doing:

| Capability       | What it allows                                                       | Why it is dangerous                                                                                                    |
| ---------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `CAP_SYS_ADMIN`  | Mount filesystems, create namespaces, set sysctls, many other things | So powerful it is sometimes called "the new root". Granting this largely defeats the entire point of containerization. |
| `CAP_SYS_MODULE` | Load and unload kernel modules                                       | Arbitrary code in the kernel. The most dangerous capability that exists.                                               |
| `CAP_SYS_PTRACE` | Trace and read the memory of other processes                         | Can read secrets from other containers on the same host.                                                               |
| `CAP_NET_ADMIN`  | Configure network interfaces, add routes, modify iptables            | Can intercept all network traffic on the host.                                                                         |
| `CAP_SYS_RAWIO`  | Access raw I/O ports and physical memory                             | Can read/write any memory location on the machine.                                                                     |

---

### 5.5 Principle of Least Privilege in Practice

In production, the best practice is to **drop all capabilities and add back only what you need**:

```bash
# Most web servers only need NET_BIND_SERVICE
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE nginx

# Inspect what a running container actually has:
docker inspect my-container | grep -A5 CapAdd

# Decode the bitmask from inside the container:
cat /proc/self/status | grep CapEff
# CapEff: 00000000a80425fb
capsh --decode=00000000a80425fb
# = cap_chown, cap_dac_override, cap_net_bind_service, ...
```

---

## 6. The Spark of Life: `execve`

### 6.1 What execve Actually Does

`execve()` is the Linux syscall that starts a new program. But it does not create a new process — it **replaces** the current process entirely. Everything about the current process — its code, its heap, its stack, all its variables, all its data — is wiped out and replaced with the new program.

What survives across `execve`:

- The PID (process ID stays the same)
- The namespace memberships (the process is still inside the same namespaces)
- The cgroup assignment (still subject to the same resource limits)
- The capability sets (Permitted/Effective/Inheritable as set up before the call)
- Open file descriptors (unless they have `FD_CLOEXEC` set)

What is destroyed:

- All code (the runtime engine's executable is gone)
- All heap memory
- All stack memory
- All global variables

This is the moment of no return. The runtime engine sets up the perfect container environment — namespaces, cgroups, capabilities, rootfs — and then calls `execve("/app/server", ...)`. The runtime engine ceases to exist. Your application wakes up in its place, inheriting all the restrictions that were configured, believing it is PID 1 on an empty machine.

---

### 6.2 The Internal Steps of execve

When the kernel receives the `execve()` call, it does this internally:

1. **Open the target binary file** and check the first few bytes (the "magic bytes"). For ELF executables, these are `\x7fELF`. For shell scripts, it looks for `#!` (the shebang line).

2. **Load the ELF segments** into the new virtual address space. The `.text` segment (code) is mapped as read-only and executable. The `.data` segment is mapped as read-write. The `.bss` segment (uninitialized data) is zeroed.

3. **Load the dynamic linker** (`/lib/x86_64-linux-gnu/ld.so.2` or similar). The kernel maps this into the address space too. The entry point is set to the dynamic linker, not your `main()` function.

4. **Set up the stack** with the argument list (`argv`) and environment variables (`envp`).

5. **Jump to the dynamic linker**. It resolves all shared library dependencies (`libc.so`, `libssl.so`, etc.), maps them into the address space, and then transfers control to your program's `main()` function.

---

### 6.3 Shell Form vs Exec Form in Dockerfiles

Understanding `execve` explains one of the most practical Dockerfile decisions: should you use exec form or shell form for `ENTRYPOINT` and `CMD`?

**Shell form** — this is what happens when you do NOT use brackets:

```dockerfile
# Shell form — wraps your command in /bin/sh -c "..."
ENTRYPOINT "node server.js"
CMD "python app.py"
```

The shell form becomes `execve("/bin/sh", ["/bin/sh", "-c", "node server.js"])`. So `/bin/sh` is PID 1. Your actual application (`node`) is a **child process** of sh. This has two bad consequences:

1. `SIGTERM` sent to PID 1 goes to `sh`. `sh` does not forward signals to its children. Your `node` process never receives the signal. Docker waits 10 seconds and force-kills everything.
2. When `sh` exits, any grandchild processes become zombies because there is no reaper.

**Exec form** — this is what happens when you use brackets (a JSON array):

```dockerfile
# Exec form — directly execves your binary
ENTRYPOINT ["node", "server.js"]
CMD ["python", "app.py"]
```

With exec form, Docker calls `execve("/usr/local/bin/node", ["node", "server.js"])` directly. `node` is PID 1. It receives all signals directly. It can handle SIGTERM gracefully, close database connections, flush write buffers, and exit cleanly.

**The rule**: always use exec form (brackets) in production Dockerfiles. Shell form is a trap.

---

## 7. Storage: OverlayFS and UnionFS

### 7.1 The Problem OverlayFS Solves

Imagine you have 50 containers all running from the same base image (say, `debian:bookworm-slim`, which is about 100 MB). Without a smart storage system, each container would need its own 100 MB copy of all those files. That is 5 GB just for the base OS files across 50 containers.

OverlayFS solves this by using a **layered, copy-on-write filesystem**. All 50 containers share the exact same read-only copy of the base image on disk. Each container only gets its own small write layer where it stores changes. A container that has not modified many files might only use a few KB of its own disk space.

---

### 7.2 The Four Directories of Overlay2

Docker's `overlay2` storage driver uses four directories for every container:

**LowerDir (read-only)**

This is where the image layers live. It is a colon-separated list of directories, stacked from top to bottom. The first path in the list is the topmost (most recent) layer; the last path is the oldest base layer. These directories are **shared across all containers using the same image**. They are completely immutable — the kernel guarantees no write ever reaches them.

```
LowerDir = /var/lib/docker/overlay2/top-layer/diff:
           /var/lib/docker/overlay2/middle-layer/diff:
           /var/lib/docker/overlay2/base-layer/diff
```

**UpperDir (read-write)**

This is the container's private sandbox. Every write operation (creating a file, modifying a file, deleting a file) ends up here. This directory is created fresh when the container is created. **It is completely deleted when the container is removed.** Anything stored only in UpperDir is gone forever when the container dies. This is why databases must use Docker Volumes — to store data outside the UpperDir.

**WorkDir (hidden staging area)**

This is a hidden directory required by the OverlayFS specification in the Linux kernel. The container application never sees it or knows it exists. It is the staging area where the kernel prepares files before atomically moving them to UpperDir. It must live on the same filesystem as UpperDir (this is a hard kernel requirement for atomic rename operations).

**MergedDir (the unified view)**

This is what the container actually sees. It is not a real directory on disk — it exists only in the kernel's VFS layer as a virtual view that merges all the layers below it. When the container opens a file, the kernel looks it up in this order: UpperDir first, then LowerDirs from top to bottom. The first match wins.

---

### 7.3 Copy-on-Write: How Modifying a File Works

When the container tries to write to a file that exists only in LowerDir (a read-only image layer), the kernel cannot just write to it — LowerDir is read-only. Instead, OverlayFS intercepts the write and performs a **Copy-on-Write (CoW)** operation:

**Step 1: Detection**

The VFS layer intercepts the `write()` syscall. It checks: does this path exist in UpperDir? No. Does it exist in LowerDir? Yes. So we need to do a copy-up.

**Step 2: Copy to WorkDir**

The kernel copies the entire original file from LowerDir into WorkDir. This is a full byte-for-byte copy. For a large file, this can take time and cause write latency — this is the main reason why OverlayFS is bad for database workloads. A database that constantly writes to large files (like a 10 GB PostgreSQL data file) would trigger copy-up operations that could stall the database for seconds.

**Step 3: Apply the write to the WorkDir copy**

The container's actual write data is applied to the copied file sitting in WorkDir.

**Step 4: Atomic rename to UpperDir**

The kernel calls `rename(workdir/filename, upperdir/filename)`. This is atomic — it either completes fully or not at all (more on this in section 8). Instantly, the file now lives in UpperDir.

**Step 5: Masking**

OverlayFS's lookup rule means the container now finds the UpperDir copy first when accessing this file. The original in LowerDir is still there, completely unchanged — but invisible to the container, "masked" by the UpperDir copy. The image is unaffected. All other containers sharing this image still see the original.

---

### 7.4 How Deletion Works: Whiteout Files

You cannot delete a file from LowerDir because LowerDir is read-only. So how does a container delete a file? It uses a **whiteout file**.

A whiteout file is a special marker created in UpperDir. It is a character device file with major device number 0 and minor device number 0. It has the same name as the file you want to delete. When OverlayFS sees a whiteout file in UpperDir, it stops searching lower layers and returns "file not found" — as if the file never existed.

```bash
# This is what OverlayFS creates in UpperDir when you delete /etc/hosts inside a container:
ls -la /var/lib/docker/overlay2/xyz/diff/etc/
# c--------- 1 root root 0, 0 May 20 10:30 hosts
# ^ character device, major=0, minor=0 → this is the whiteout marker
```

For deleting an entire directory, OverlayFS uses an "opaque directory" — a regular directory with a special extended attribute `trusted.overlay.opaque=y` set on it, which tells OverlayFS to ignore the directory in all lower layers.

---

### 7.5 Why Databases Must Use Volumes

Two reasons:

**Reason 1: Data loss.** All data written to UpperDir is deleted when the container is removed. A database that stores its data files in the container's filesystem loses everything on `docker rm`. A Docker Volume stores data outside the container on the host filesystem — it persists after the container dies.

**Reason 2: I/O performance.** The copy-up operation (copying a file from LowerDir to UpperDir before the first write) adds significant latency. A database that writes to a 10 GB data file for the first time would trigger a 10 GB copy-up operation. With a Volume, the data file lives directly on the host filesystem — there are no overlay layers, no copy-up, just direct I/O. Volumes bypass OverlayFS entirely.

```bash
# Correct: database data in a Volume, not in the container
docker run -v /host/path/data:/var/lib/postgresql/data postgres
```

---

## 8. The workdir & Atomic Operations

### 8.1 The Problem: Normal Writes are Not Safe

A standard `write()` syscall is **not atomic**. It does not guarantee all-or-nothing. When the kernel writes a large file, it does it in small chunks over time. If the system loses power or crashes when the file is 50% written, you are left with a corrupt half-written file on disk. You cannot tell from the file itself whether it is complete or not.

For OverlayFS, this is a serious danger. When a container modifies a large file, OverlayFS must copy the entire original from LowerDir to UpperDir before allowing the modification. If the system crashes in the middle of this copy, the container wakes up to a half-written, corrupted version of what was a perfectly good file.

The WorkDir exists specifically to prevent this.

---

### 8.2 The Atomic Solution: rename()

Linux provides one syscall that is **truly atomic** with respect to the filesystem: `rename(oldpath, newpath)`.

`rename()` does not move data. It does not copy bytes. It updates a single record in the directory's inode table — changing which inode number a filename points to. This record update is logged as a single journal transaction by the filesystem (ext4, XFS, btrfs all do this). The journal either commits the transaction completely or rolls it back completely. There is no in-between state.

Because the update is a single small record, it takes a fraction of a microsecond regardless of how large the file is. A 1 GB file renamed is just as fast as a 1 KB file renamed.

---

### 8.3 How OverlayFS Uses WorkDir and rename() Together

Here is the full sequence for a safe copy-up operation:

**Step 1: Copy the file into WorkDir**

The kernel copies the file from LowerDir into WorkDir (not UpperDir). WorkDir is a staging area. If the system crashes here, UpperDir is untouched. The container would restart and find the original clean file in LowerDir.

```
LowerDir/etc/nginx.conf  → (full copy) →  WorkDir/etc/nginx.conf
```

**Step 2: Apply the container's writes to the WorkDir copy**

The container's actual modifications are applied to the file sitting in WorkDir. If the system crashes here, same result — UpperDir is still clean, the container restarts safely.

```
WorkDir/etc/nginx.conf (modified with new content)
```

**Step 3: Atomic rename to UpperDir**

Once the file in WorkDir is complete and ready:

```
rename("WorkDir/etc/nginx.conf", "UpperDir/etc/nginx.conf")
```

The kernel executes this as a single atomic journal transaction. The inode table entry for `WorkDir/etc/nginx.conf` is removed and `UpperDir/etc/nginx.conf` is created pointing to the same inode — the same physical disk blocks.

```
Before rename:
  WorkDir/etc/nginx.conf  → inode 88421 (complete modified file)
  UpperDir/etc/           → (no nginx.conf entry)

After rename:
  WorkDir/etc/            → (nginx.conf entry removed)
  UpperDir/etc/nginx.conf → inode 88421 (same physical data, no copying)
```

**The result**: at every point in time, the container sees either the complete old file (from LowerDir) or the complete new file (from UpperDir). It never sees a partial, corrupted file. The WorkDir is the guarantor of this safety.

---

### 8.4 Why WorkDir Must Be on the Same Filesystem as UpperDir

The atomicity of `rename()` only works if the source and destination are on the **same filesystem**. This is because the rename is a metadata update inside a single filesystem's journal. If you tried to rename across two different filesystems, the kernel would reject it with the error `EXDEV` (cross-device link).

OverlayFS enforces this as a mount-time requirement. If you try to specify a WorkDir on a different filesystem than UpperDir, the kernel will refuse to mount the OverlayFS with an error. This is not an arbitrary restriction — it is what makes the whole crash-safety guarantee possible.

---

### 8.5 The Danger of CoW for Large Files: A Practical Example

Consider a container running PostgreSQL without a Volume (wrong way):

1. PostgreSQL starts and creates a 500 MB data file in `/var/lib/postgresql/data/`. This file goes to UpperDir immediately (it is a new file, not in LowerDir). Fine so far.

2. PostgreSQL grows the database to 10 GB. All writes go directly to UpperDir. Fine.

3. Now something tries to read a config file from `/etc/postgresql/postgresql.conf` — which is part of the image (in LowerDir) — and write to it. Copy-up triggers: the kernel copies the entire config file to WorkDir, then renames to UpperDir. Config files are small — this is fast.

4. **But what if PostgreSQL writes to a temp file that overlaps with an image file path?** Then OverlayFS triggers copy-up for whatever the overlap is. This adds unexpected I/O.

5. When you `docker stop` and `docker rm` the container, the entire UpperDir is deleted. All 10 GB of database data is gone permanently.

**Correct approach:**

```bash
docker run \
  -v pgdata:/var/lib/postgresql/data \  # Volume for data
  postgres:16
```

With a Volume, `/var/lib/postgresql/data` inside the container is a bind-mount pointing directly to the host filesystem. OverlayFS is not involved for that path at all. No copy-up, no CoW overhead, and the data survives container removal.
