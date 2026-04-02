# Nix

- Nix is the preferred meta package manager on all systems — assume it is available even on non-NixOS Linux
- Always prefer a project-level `flake.nix` as the canonical way to define dev environments, build systems, and scripts
- Dev environments go in `devShells`, project scripts/tools go in `packages` or as `apps` within the flake
- Never suggest `apt`, `brew`, `pip install --user`, `npm install -g`, or other imperative global installs — reach for `nix shell`, `nix run`, or the project devshell instead
- Prefer `nix run` for one-off tool invocations and `nix develop` (or `direnv` + `use flake`) for persistent dev shells
- Binaries and tools introduced to a project should be pinned and run through Nix, not assumed to be on `$PATH` from the host
- Flakes are the preferred interface — avoid legacy `nix-env` or channel-based patterns
