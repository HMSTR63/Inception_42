# Low-Level Container Architecture: The Kernel Illusion 🐋

> **A Reference Guide to OS Containerization, Kernel Primitives, and OverlayFS.**

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

A container is not a physical object, nor is it a Virtual Machine. It is a standard **Linux process subjected to strict isolation** through native kernel primitives. The operating system creates a controlled "illusion" where the process believes it has full control over a dedicated machine.

---

## 2. Namespaces: The Walls of Isolation

Namespaces restrict what a process can _see_. They provide the fundamental isolation for different system resources.

- **PID Namespace:** Isolates the process ID number space. The first process spawned inside the container is assigned **PID 1** (the "King"). To the host machine, this same process has a standard, high-number PID (e.g., `3452`).
- **Mount Namespace & `pivot_root`:** Isolates the filesystem mount points. The `pivot_root` syscall changes the root directory of the container, securely caging it within a specific directory (the image rootfs) so it cannot traverse back to the host's physical `/`.
- **Network Namespace:** Provides an isolated network stack (interfaces, routing tables, iptables). A virtual ethernet pair (`veth`) connects the container's isolated network to the host's bridge (e.g., `docker0`).

---

## 3. Control Groups (Cgroups): The Resource Brakes

While Namespaces limit visibility, Cgroups limit **resource usage** (Memory, CPU, I/O) to prevent a single container from exhausting the host machine.

- **The VFS Mechanism:** Cgroups are managed via a Virtual File System (VFS) in the host's memory, typically mounted at `/sys/fs/cgroup`. Limits are enforced by writing values to specific files (e.g., `memory.max`).
- **Swap Math:** By default, Docker allocates memory-swap equal to double the memory limit. The command `--memory-swap` defines the **total** (Memory + Swap), not just the swap. To enforce a hard memory limit with zero swap, both `--memory` and `--memory-swap` must be set to the identical value.
- **Dynamic Updates:** Cgroups allow on-the-fly resource adjustments (e.g., `docker update`), modifying the kernel structures without restarting the container.

---

## 4. The OOM Killer & The Zombie Problem

When a process hits its Cgroup memory limit, the kernel triggers the Out-Of-Memory (OOM) Killer.

- **Targeting (The Sniper):** The OOM Killer evaluates all processes within the specific Cgroup and calculates an `oom_score`. It terminates the highest-scoring process (often a child worker process) with a `SIGKILL` (Signal 9).
- **The PID 1 Survival:** If a child process is killed but PID 1 (e.g., `bash`) survives, the container remains running. If PID 1 is starved and killed, the entire container crashes with **Exit Code 137**.
- **Defunct Processes (Zombies):** When a child process is killed by the OOM Killer, its exit status remains in the process table (as a `<defunct>` or `Z` state) until its parent reaps it. Since standard shells (`bash`, `sh`) acting as PID 1 are not designed to reap orphaned children, these zombies accumulate.
- **The Solution (`init`):** Robust containers use lightweight init systems like `tini` or `dumb-init` as PID 1. Their sole job is to spawn the main application and immediately reap any zombie processes that die.

---

## 5. Linux Capabilities: The Castrated Root

To prevent privilege escalation, the absolute power of UID 0 (root) is shattered into distinct units called Capabilities.

- **The Concept:** Running as root inside a container grants the identity of root, but not the authority. The runtime engine strips away dangerous capabilities before execution.
- **The Lists:** The kernel manages capabilities using bitmasks across lists: `Permitted` (the absolute ceiling), `Effective` (currently active), and `Inheritable` (passed to children).
- **Default Whitelist:** Containers keep safe capabilities like `CAP_NET_BIND_SERVICE` (to open ports like 80/443) and `CAP_CHOWN`.
- **The Blacklist:** Dangerous capabilities like `CAP_SYS_ADMIN` (mounting filesystems) or `CAP_SYS_MODULE` (loading kernel drivers) are stripped away, securing the host even if the container is compromised.

---

## 6. The Spark of Life: `execve`

After the runtime engine sets up Namespaces, Cgroups, and Capabilities, it calls the `execve()` syscall.

- **The Shape-Shift:** `execve` does not spawn a new process; it replaces the current runtime engine's memory space entirely with the target application's code (e.g., `nginx`).
- This is the point of no return. The setup engine vanishes from memory, and the container application awakens as PID 1.

---

## 7. Storage: OverlayFS and UnionFS

To avoid duplicating base OS files for every container, Docker utilizes a layered, stackable Virtual File System (Overlay2).

- **LowerDir (Read-Only):** The immutable base image layers (e.g., Debian binaries). Shared safely across all containers using the same image.
- **UpperDir (Read-Write):** A thin, ephemeral directory created specifically for a running container. It is the only layer where the container is permitted to write.
- **MergedDir (The View):** The unified perspective provided by the kernel. The container sees a single, cohesive filesystem.

### Copy-on-Write (CoW) and Masking

- **Writing New Files:** Written directly to the `UpperDir`.
- **Modifying Existing Files:** If a container modifies a system file located in the `LowerDir`, the kernel intercepts the operation. It copies the file up to the `UpperDir`, allows the modification on the copy, and "masks" the original. The container only sees the modified version, while the original remains untouched below.
- **The Danger:** Because the `UpperDir` is deleted entirely when a container is removed, databases must bypass this mechanism using **Volumes** to prevent complete data loss and avoid heavy I/O latency from CoW operations.

---

## 8. The `workdir` & Atomic Operations

Data corruption is a massive risk when moving large, modified files from the underlying layers to the `UpperDir`. The kernel prevents this using the `workdir` and atomic operations.

### The Problem with Direct Writes

Standard `write()` syscalls are not atomic. If the kernel copies a 1GB file into the `UpperDir` and the system crashes at 50%, the container wakes up to a corrupted, half-written file.

### The Atomic Solution

An atomic operation guarantees that a process either completes fully (100%) or does not happen at all (0%). In Linux, the `rename(oldpath, newpath)` syscall is strictly atomic.

**How it works at the Inode level:**

1. **Preparation:** The kernel intercepts the CoW request and copies the file from `LowerDir` into the `workdir` (a hidden preparation directory).
2. **Modification:** The container's writes are applied to this file inside the `workdir`.
3. **The Atomic Swap:** Once the file is 100% complete, the kernel executes `rename`. It does _not_ move the physical data on the disk. Instead, it updates the directory index table, replacing the file's path pointer from `/workdir/file` to `/upperdir/file` while keeping the exact same **Inode**.
4. **The Result:** Because changing a path pointer takes a fraction of a microsecond, the operation is practically instantaneous and atomic. The container instantly sees the fully formed file in the `MergedDir` with zero risk of observing corrupted data.

