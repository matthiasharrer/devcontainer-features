# Atuin Shell History (`atuin`)

Installs [Atuin](https://atuin.sh) and enables its shell integration for bash and zsh (up-arrow binding disabled). The host's Atuin config and data are bind-mounted into the container, so the container shares the host's history database. Sync is disabled inside the container (`ATUIN_AUTO_SYNC=false`); the host handles syncing.

```jsonc
"features": {
    "ghcr.io/matthiasharrer/devcontainer-features/atuin:1": {}
}
```

## Options

| Option | Default | Description |
|---|---|---|
| `version` | `latest` | Atuin version to install (`latest` or e.g. `18.24.4`). Keep it the same as the host's Atuin version if you use the host daemon (see below). |
| `debug` | `false` | Trace `install.sh` (`set -x`) to diagnose install failures. |

## Mounts

| Host | Container |
|---|---|
| `~/.config/atuin` | `/home/vscode/.config/atuin` |
| `~/.local/share/atuin` | `/home/vscode/.local/share/atuin` |

Both host directories must exist before the container starts.

## Atuin daemon

The container **never runs a daemon of its own**: two daemons on the same database are not wanted. It uses the **host's** daemon when it can reach it, and otherwise writes history directly to the database.

### Using the host daemon (Linux hosts)

By default, the host daemon listens on `/tmp/atuin-$UID/atuin.sock`, which is not visible in the container. Put the socket into the mounted data directory instead, in the host's `~/.config/atuin/config.toml`:

```toml
[daemon]
enabled = true
autostart = true
socket_path = "~/.local/share/atuin/atuin.sock"
```

Then restart the host daemon so it moves its socket (on the host):

```bash
atuin daemon restart
```

Rebuild the container, or open a new terminal in it. `atuin threads list`, `atuin resume`, `atuin mcp` and shell history then go through the host daemon.

### How it works

The feature sets these container environment variables (Atuin reads `ATUIN_<SECTION>__<KEY>` as overrides of `config.toml`):

| Variable | Value | Why |
|---|---|---|
| `ATUIN_DAEMON__AUTOSTART` | `false` | Never start a daemon in the container. |
| `ATUIN_DAEMON__SOCKET_PATH` | `/home/vscode/.local/share/atuin/atuin.sock` | The host socket, seen through the data-dir mount. |
| `ATUIN_DAEMON__PIDFILE_PATH` | `/tmp/atuin-devcontainer/atuin-daemon.pid` | Container-local and never created, see below. |

The host daemon's pidfile (`~/.local/share/atuin/atuin-daemon.pid`) is in the mounted data directory. It records the socket path as an absolute host path (`/home/<host-user>/...`), and Atuin clients prefer that recorded path over `socket_path`. That path doesn't exist in the container. And because the host daemon holds a lock on the pidfile, a client in the container with daemon autostart would wait for the "running" daemon and then fail (`a daemon still holds its pidfile ... after 4000ms`). Pointing the container at its own (non-existent) pidfile makes clients use `ATUIN_DAEMON__SOCKET_PATH` instead.

The shell integration checks at shell start whether that socket exists. If not, it sets `ATUIN_DAEMON__ENABLED=false` for the shell, so commands write history directly and don't print a "failed to start history via the daemon" warning each time. This is the case when:

- the host daemon is disabled or not running,
- the host daemon still uses its default socket in `/tmp/atuin-$UID`,
- the host is Windows (Docker Desktop/WSL2), where a host Unix socket can't be shared into the container.

`atuin threads`, `atuin resume` and `atuin mcp` need the daemon, so they are unavailable in the container in these cases. Set `ATUIN_DAEMON__ENABLED` yourself (e.g. via `remoteEnv`) to override the check.

Notes:

- If the host daemon starts after the container shell was opened, open a new terminal.
- Keep the container's Atuin version equal to the host's: a client refuses a daemon of a different build, and the container can't restart the host daemon.
- Don't run `atuin daemon start` inside the container.
- On Docker Desktop for Mac, a socket on a shared folder can exist but not accept connections; set `ATUIN_DAEMON__ENABLED=false` in `remoteEnv` there.

### Checking it in the container

```bash
atuin daemon status
```

```bash
atuin threads list
```

```bash
env | grep ATUIN_DAEMON
```
