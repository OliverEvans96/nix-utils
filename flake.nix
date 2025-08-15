{
  description = "Minimal uv2nix flake for Python/uv project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
    let
      inherit (nixpkgs) lib;

      # Helper to load workspace and overlays
      mkWorkspace = { dir, overrides ? (_final: _prev: { }) }: let
        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = dir; };
        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };
        pyprojectOverrides = overrides;
      in {
        inherit workspace overlay pyprojectOverrides;
      };

      # Helper to get pkgs and python
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      python = pkgs.python312;

      # Non-editable environment
      mkUvEnv = { dir, venvName, workspaceOverrides ? (_final: _prev: { }) }: let
        ws = mkWorkspace { inherit dir; overrides = workspaceOverrides; };
        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope
            (
              lib.composeManyExtensions [
                pyproject-build-systems.overlays.default
                ws.overlay
                ws.pyprojectOverrides
              ]
            );
        virtualenv = pythonSet.mkVirtualEnv venvName ws.workspace.deps.all;
      in
        virtualenv;

      # Editable (dev) environment
      mkUvDevShell = { dir, venvName, workspaceOverrides ? (_final: _prev: { }), overlays ? [], extraPackages ? [], ignoreCollisions ? false }: let
        ws = mkWorkspace { inherit dir; overrides = workspaceOverrides; };
        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope
            (
              lib.composeManyExtensions (
                [
                  pyproject-build-systems.overlays.default
                  ws.overlay
                  ws.pyprojectOverrides
                ] ++ overlays
              )
            );
        editableOverlay = ws.workspace.mkEditablePyprojectOverlay {
          root = "$REPO_ROOT";
        };
        editablePythonSet = pythonSet.overrideScope (
          lib.composeManyExtensions [
            editableOverlay
          ]
        );
        virtualenv = editablePythonSet.mkVirtualEnv venvName (ws.workspace.deps.all // { inherit ignoreCollisions; });
      in
        pkgs.mkShell {
          packages = [
            virtualenv
            pkgs.uv
          ];
          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = python.interpreter;
            UV_PYTHON_DOWNLOADS = "never";
          };
          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT=$(git rev-parse --show-toplevel)
          '';
        };

    in
    {
      inherit mkUvEnv mkUvDevShell;
    };
}

