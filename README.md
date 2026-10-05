# ida.nix

Wrappers for a manually installed IDA Pro on NixOS. Relies on
[nix-ld](https://github.com/nix-community/nix-ld) — no FHS env, no patchelf,
so the install and its plugins stay untouched.

Everything runs under `bwrap --dev-bind / / --unshare-net`: no network, so no
Lumina, update checks or cloud decompilers.

## Commands

| Command        | What it does                                                                                        |
| -------------- | --------------------------------------------------------------------------------------------------- |
| `ida`          | Runs IDA with the runtime libraries and the flake's Python (3.14) for IDAPython.                     |
| `ida-env CMD`  | Runs `CMD` in IDA's runtime environment, e.g. `ida-env python script.py` for idalib. Uses your own python/venv. |
| `ida-pyswitch` | No args: points IDAPython at the flake's Python. With args: passes them through to `idapyswitch`.   |

## Setup

```nix
# flake.nix
inputs.ida.url = "git+ssh://forgejo@10.66.0.2/gweej/ida.nix.git";

# configuration.nix
programs.nix-ld.enable = true;
environment.systemPackages = [ inputs.ida.packages.x86_64-linux.default ];
```

Then run `ida-pyswitch` once.

To use idalib, add `idapro` to your project's venv (e.g. `uv add` from
`$IDADIR/idalib/python`) and run scripts through `ida-env python ...`.

## Configuration

Override the package:

```nix
inputs.ida.packages.x86_64-linux.default.override {
  idaDir = "/opt/ida-pro-9.2";                  # default: auto-detect
  idaPython = pkgs.python313;                   # default: python314
  extraPythonPackages = ps: [ ps.capstone ];    # for IDAPython plugins
  extraLibs = [ pkgs.libsecret ];               # missing .so files
}
```

Environment variables:

- `IDADIR`: IDA install directory. If unset, the newest `~/ida-pro-*`,
  `~/idapro-*`, `~/ida-*` or `/opt/...` directory containing an `ida` binary is used.
- `IDA_ALLOW_NET=1`: skip the network sandbox, e.g. `IDA_ALLOW_NET=1 ida-env uv sync`.
- `IDA_QPA_PLATFORM`: Qt platform plugin (default `xcb`).

## Troubleshooting

- **Missing libraries:** run `ida-env ldd "$IDADIR/ida" | grep 'not found'` and add what it lists to `extraLibs`.
- **IDAPython doesn't load:** your IDA version may not support Python 3.14. Set `idaPython = pkgs.python313` and rerun `ida-pyswitch`.
- **Floating licenses:** these need the license server, which the sandbox blocks. Use `IDA_ALLOW_NET=1`.
