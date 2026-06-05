# The Decoupled Engine & OCI Storage Architecture 📦

> **A Reference Guide to Docker Engine Components, Content Addressable Storage, and OCI Specs.**

## Table of Contents
1. [The Decoupled Engine Hierarchy](#1-the-decoupled-engine-hierarchy)
2. [The Open Container Initiative (OCI)](#2-the-open-container-initiative-oci)
3. [The Rigid Dichotomy: Image vs. Container](#3-the-rigid-dichotomy-image-vs-container)
4. [Content Addressable Storage (CAS) & Immutability](#4-content-addressable-storage-cas--immutability)
5. [The DAG & Deduplication Magic](#5-the-dag--deduplication-magic)
6. [Image Anatomy: Manifests & Configs](#6-image-anatomy-manifests--configs)

---

## 1. The Decoupled Engine Hierarchy
Docker is not a single monolithic program. It is a strictly separated chain of command, ensuring stability and modularity.

* **`docker` (The Client):** A lightweight CLI tool. It does no heavy lifting; it merely translates your terminal commands into REST API calls and sends them to the daemon.
* **`dockerd` (The Daemon):** The high-level manager. It handles network routing, volume creation, and image builds. When it needs to run a container, it delegates the task downwards.
* **`containerd` (The Supervisor):** The middle-manager. It pulls images from registries, manages the container lifecycle (start/stop/pause), and prepares the `config.json` for the runtime.
* **`runc` (The Surgeon / OCI Runtime):** A low-level, transient binary. Its sole job is to take the `config.json`, interface directly with the Linux Kernel to create Namespaces and Cgroups, spawn the container process, and immediately exit.
* **`containerd-shim` (The Lifeguard):** A tiny daemon attached to every running container. Because `runc` exits, the `shim` stays behind to keep the container's `stdin/stdout` open and report the exit status back to `containerd`. This allows the main `dockerd` to crash or update without killing the running containers (**Daemonless Architecture**).

---

## 2. The Open Container Initiative (OCI)
To prevent vendor lock-in, Docker handed over its core standards to the OCI. This ensures containers are universal.

* **The Image Spec (Storage):** Dictates how to serialize a filesystem into a stack of compressed `.tar` layers and JSON metadata.
* **The Distribution Spec (Network):** Standardizes the HTTP API (`/v2/<name>/manifests/...`) so you can push/pull images from *any* registry (Docker Hub, AWS ECR, Harbor) using the exact same protocol.
* **The Runtime Spec (Execution):** Dictates the structure of the `config.json` and how tools like `runc` must interact with the kernel to unpack layers and enforce isolation.

---

## 3. The Rigid Dichotomy: Image vs. Container
These two concepts represent fundamentally different states of computing data.

* **The Image (The Blueprint):** A static, immutable, cryptographically signed, build-time artifact. It is essentially dead code residing on the disk.
* **The Container (The Instance):** A dynamic, mutable, ephemeral, run-time environment. It is the active Linux process running in RAM (spawned via `execve`).

---

## 4. Content Addressable Storage (CAS) & Immutability
Docker does not retrieve files by their arbitrary names (e.g., `script.py`). It retrieves them by the mathematical hash of their contents.

* **The Mechanism:** When a file/layer is ingested, the Engine calculates its `SHA256` hash. This hash becomes the physical address on the disk (e.g., `/var/lib/docker/overlay2/sha256:a1b2...`).
* **Strict Immutability:** Because the address *is* the content, changing a single bit of code generates a completely new SHA256 hash. Therefore, you cannot "edit" an existing Docker Image layer; you can only generate a new one.

---

## 5. The DAG & Deduplication Magic
To prevent paralyzing the host's disk space with duplicated OS files, Docker treats storage as a graph theory problem.

* **The DAG (Directed Acyclic Graph):** An image is a strict hierarchy of layers. Layer 3 points to Layer 2, which points to Layer 1. The relationship is unidirectional.
* **Deduplication:** If ten distinct images (e.g., PHP, Node, Python) all start with `FROM debian`, the Engine hashes the Debian layer only once. All ten images will simply point to the exact same physical SHA256 blob on the host disk. This reduces gigabytes of wasted space into mere kilobytes of pointers.

---

## 6. Image Anatomy: Manifests & Configs
An image on disk is not a `.iso` file. It is a logical construct assembled from distinct pieces.

* **The Manifest (`manifest.json`):** The entry point or "packing slip". It contains an ordered list of layer hashes, telling `containerd` exactly which blobs to download and in what order to stack them.
* **The Layers (`layer.tar`):** The actual compressed archives containing the filesystem diffs for that specific step.
* **The Image Config (JSON):** The immutable DNA generated at build time (from the `Dockerfile`). It contains default variables like `ENTRYPOINT`, `ENV`, and `EXPOSE`.

### The Golden Rule of Configs
Do not confuse the **Image Config** with the **Runtime Config**.
When you run a container, `containerd` reads the *Image Config*, merges it with your CLI arguments (e.g., `--memory 500m`), and generates a completely new, temporary **Runtime Config** (`config.json`). This temporary file is what `runc` actually uses to command the kernel.
