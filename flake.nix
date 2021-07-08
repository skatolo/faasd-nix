{
  description = "A lightweight & portable faas engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
    utils.url = "github:numtide/flake-utils";
    faasd-src = {
      url = "https://github.com/openfaas/faasd/archive/refs/tags/0.11.4.tar.gz";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, utils, faasd-src }:
    let
      faasdVersion = "0.11.4";
      faasdRev = "dca036ee51a7275389bf45c7839d22d437663a8e";

      supportedSystems = [
        "x86_64-linux"
      ];
    in
    {
      overlay = final: prev:

        with final;

        let
          faasdBuild = buildGoModule rec {
            pname = "faasd-build";
            version = "${faasdVersion}";
            commit = "${faasdRev}";

            src = "${faasd-src}";

            vendorSha256 = null;

            CGO_ENABLED = 0;
            buildFlagsArray = [
              ''
                -ldflags=
                -s -w
                -X main.Version=${version}
                -X main.GitCommit=${commit}
              ''
              "-a"
            ];
          };
        in
        {
          containerd = prev.containerd.overrideAttrs (oldAttrs: {
            version = "1.3.5";
            src = fetchFromGitHub {
              owner = "containerd";
              repo = "containerd";
              rev = "9b6f3ec0307a825c38617b93ad55162b5bb94234";
              sha256 = "sha256-M1+DSNkV+Ly0vUf4nOWlXNDhTiFG3Sztg0hDpzfTw10=";
            };

            nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ pkg-config ];

            buildInputs = oldAttrs.buildInputs ++ [ libseccomp ];

            installPhase = ''
              install -Dm555 bin/* -t $out/bin
              installManPage man/*.[1-9]
            '';
          });

          faasd = stdenv.mkDerivation rec {
            inherit faasdBuild;

            pname = "faasd";
            version = "${faasdVersion}";

            faasdRuntimeDeps = [
              iptables
            ];

            buildInputs = [
              makeWrapper
            ] ++ faasdRuntimeDeps;

            unpackPhase = "true";

            installPhase = ''
              mkdir -p "$out/bin"
               makeWrapper ${faasdBuild}/bin/faasd "$out/bin/faasd" \
                --prefix PATH : ${lib.makeBinPath faasdRuntimeDeps}

              mkdir -p $out/installation
              cp ${faasd-src}/docker-compose.yaml $out/installation/docker-compose.yaml
              cp ${faasd-src}/prometheus.yml $out/installation/prometheus.yml
              cp ${faasd-src}/resolv.conf $out/installation/resolv.conf
            '';
          };
        };

      nixosModules.faasd = {
        imports = [ ./faasd-module.nix ];
        nixpkgs.overlays = [ self.overlay ];
      };
    } // utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
        };
      in
      {
        defaultPackage = pkgs.faasd;

        evShell = pkgs.mkShell {
          buildInputs = [
            pkgs.nixpkgs-fmt
          ];
        };
      });
}
