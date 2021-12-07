{
  description = "An opentelemetry example";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    naersk = {
      url = "github:nmattia/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , pre-commit-hooks
    , naersk
    , fenix
    }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      rustToolchain = fenix.packages.${system}.latest.withComponents [
        "clippy"
        "rust-analysis"
        "rust-analyzer-preview"
        "rust-src"
        "rust-std"
        "rustfmt"
        "cargo"
        "rustc"
      ];
      naersk-lib = naersk.lib.${system}.override {
        cargo = rustToolchain;
        rustc = rustToolchain;
      };
      inherit (pkgs.lib) mkForce;
    in
    rec {
      packages.opentelemetry-example = naersk-lib.buildPackage {
        pname = "opentelemetry-example";
        src = ./.;
        dontPatchELF = true;
        doCheck = true;
      };

      defaultPackage = packages.opentelemetry-example;

      apps.opentelemetry-example = flake-utils.lib.mkApp {
        drv = packages.opentelemetry-example;
      };
      defaultApp = apps.opentelemetry-example;

      packages.opentelemetry-example-image = pkgs.dockerTools.buildLayeredImage {
        name = "opentelemetry-example";
        config = {
          Entrypoint = [ "${packages.opentelemetry-example}/bin/opentelemetry-example" ];
        };
      };

      checks = {
        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nix-linter = {
              enable = true;
              entry = mkForce "${pkgs.nix-linter}/bin/nix-linter";
              excludes = [ "nix/sources.nix" ];
            };

            nixpkgs-fmt = {
              enable = true;
              entry = mkForce "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check";
            };

            shellcheck = {
              enable = true;
              entry = mkForce "${pkgs.shellcheck}/bin/shellcheck";
              files = "\\.sh$";
              types_or = mkForce [ ];
            };

            shfmt = {
              enable = true;
              entry = mkForce "${pkgs.shfmt}/bin/shfmt -i 2 -sr -d -s -l";
              files = "\\.sh$";
            };

            rustfmt = {
              enable = true;
              entry = mkForce "${rustToolchain}/bin/cargo fmt -- --check --color=always";
            };

            clippy = {
              enable = true;
              entry = mkForce "${rustToolchain}/bin/cargo clippy";
            };

            cargo-check = {
              enable = true;
              entry = mkForce "${rustToolchain}/bin/cargo check";
            };
          };

        };
      };

      devShell = pkgs.mkShell {
        nativeBuildInputs = (with pkgs; [
          cacert
          cargo-bloat
          cargo-edit
          cargo-udeps
          commitizen
          docker-compose
          grpc
          protobuf
          jq
          util-linux
          yj
        ]) ++ [
          rustToolchain
        ];
        PROTOC = "${pkgs.protobuf}/bin/protoc";
        shellHook = ''
          ${self.checks.${system}.pre-commit-check.shellHook}
        '';
      };
    });
}
