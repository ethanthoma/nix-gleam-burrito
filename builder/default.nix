{
  stdenv,
  lib,
  fetchFromGitHub,
  gleam,
  erlang,
  elixir,
  git,
  rebar3,
  beamPackages,
  zig,
  p7zip,
  fetchHex,
  writeText,
  runCommand,
}:

let
  inherit (builtins) fromTOML readFile;

  systemToBurrito = {
    "x86_64-darwin" = {
      target = "macos";
      os = "darwin";
      cpu = "x86_64";
    };
    "aarch64-darwin" = {
      target = "macos";
      os = "darwin";
      cpu = "aarch64";
    };
    "x86_64-linux" = {
      target = "linux";
      os = "linux";
      cpu = "x86_64";
    };
    "aarch64-linux" = {
      target = "linux";
      os = "linux";
      cpu = "aarch64";
    };
  };

  defaultTarget = systemToBurrito.${stdenv.system};

  mixGleam = fetchFromGitHub {
    owner = "gleam-lang";
    repo = "mix_gleam";
    tag = "v0.6.2";
    sha256 = "sha256-m7fJvMxfGn+kQObZscmNLITLtv9yStUT2nKRKXqCzrs=";
  };

  makeErtsPackage =
    {
      os,
      cpu,
      erlang,
      ...
    }:
    let
      version = erlang.version;
    in
    runCommand "otp-${version}-${os}-${cpu}.tar.gz" { } ''
      mkdir -p otp-${version}-${os}-${cpu}
      cd otp-${version}-${os}-${cpu}

      cp -r ${erlang}/lib/erlang/erts* erts-${version}
      cp -r ${erlang}/lib/erlang/releases releases
      cp -r ${erlang}/lib/erlang/lib lib
      cp -r ${erlang}/lib/erlang/misc misc
      cp -r ${erlang}/lib/erlang/usr usr
      touch Install

      cd ..
      tar czf $out otp-${version}-${os}-${cpu}
    '';
in
{
  buildGleamBurrito =
    {
      src,
      nativeBuildInputs ? [ ],
      localPackages ? [ ],
      erlangPackage ? erlang,
      rebar3Package ? rebar3,
      target ? defaultTarget.target, # Can be "macos", "linux", or "windows"
      targetCpu ? defaultTarget.cpu, # Can be "x86_64" or "aarch64"
      ...
    }@attrs:
    let
      gleamToml = fromTOML (readFile (src + "/gleam.toml"));
      manifestToml = fromTOML (readFile (src + "/manifest.toml"));

      currentTarget =
        let
          os =
            if target == "macos" then
              "darwin"
            else if target == "windows" then
              "windows"
            else
              "linux";
        in
        {
          inherit target os;
          cpu = defaultTarget.cpu;
        };

      ertsPackage = makeErtsPackage (
        currentTarget
        // {
          erlang = erlangPackage;
        }
      );

      mixDeps = import ./deps.nix {
        inherit lib beamPackages;
      };

      gleamDeps = builtins.listToAttrs (
        map (pkg: {
          name = pkg.name;
          value = fetchHex {
            pkg = pkg.name;
            version = pkg.version;
            sha256 = pkg.outer_checksum;
          };
        }) manifestToml.packages
      );

      gleamDepsString = builtins.concatStringsSep "\n      " (
        builtins.attrValues (
          builtins.mapAttrs (name: path: ''{:${name}, path: "deps/${name}", override: true},'') gleamDeps
        )
      );

      mixDepsString = builtins.concatStringsSep "\n      " (
        builtins.attrValues (
          builtins.mapAttrs (name: drv: ''{:${name}, path: "${drv}/", override: true},'') mixDeps
        )
      );

      mixEntry =
        pname:
        writeText "${pname}.ex" ''
          defmodule ${lib.toUpper pname}.Application do
            use Application

            @impl true
            def start(_type, _args) do
              :${pname}.main()
              
              System.halt(0)
            end
          end
        '';

      mixConfig =
        name: version: currentTarget: ertsPackage:
        writeText "mix.exs" ''
          defmodule ${lib.toUpper name}.MixProject do
            use Mix.Project

            def project do
              [
                app: :${name},
                version: "${version}",
                elixir: "~> 1.18",
                start_permanent: Mix.env() == :prod,
                deps: deps(),
                releases: releases(),
                archives: [mix_gleam: "~> 0.6"],
                compilers: [:gleam | Mix.compilers()],
                erlc_paths: [
                  "build/dev/erlang/${name}/_gleam_artefacts",
                  "lib",
                ],
                erlc_include_path: "build/dev/erlang/${name}/include",
                prune_code_paths: false,
              ]
            end

            def releases do
              [
                ${name}: [
                  include_executables_for: [:unix, :windows],
                  steps: [:assemble, &Burrito.wrap/1],
                  burrito: [
                    targets: [
                      ${currentTarget.target}: [
                        os: :${currentTarget.os}, 
                        cpu: :${currentTarget.cpu}, 
                        custom_erts: "${ertsPackage}"
                      ],
                      ${lib.optionalString (currentTarget.target == "windows") ''
                        windows: [
                          os: :windows,
                          cpu: :${currentTarget.cpu},
                          custom_erts: "${ertsPackage}"
                        ],
                      ''}
                    ]
                  ],
                  applications: [
                    inets: :permanent,
                    ssl: :permanent
                  ],
                  debug: Mix.env() != :prod,
                  no_clean: false
                ]
              ]
            end

            def application do
              [ 
                mod: {${lib.toUpper name}.Application, []},
                extra_applications: [:inets, :ssl]
              ]
            end

            defp deps do
              [
                ${gleamDepsString}
                ${mixDepsString}
              ]
            end
          end
        '';

      defaultNativeBuildInputs = [
        gleam
        beamPackages.hex
        elixir
        erlangPackage
        rebar3Package
        zig
        p7zip
      ] ++ nativeBuildInputs;
    in
    stdenv.mkDerivation (
      attrs
      // rec {
        pname = attrs.pname or gleamToml.name;
        version = attrs.version or gleamToml.version;

        inherit src;

        nativeBuildInputs = defaultNativeBuildInputs;

        env = {
          MIX_ENV = "prod";
          HEX_OFFLINE = 1;
          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";
          MIX_PATH = "${beamPackages.hex}/lib/erlang/lib/hex/ebin";
          MIX_REBAR3 = "${beamPackages.rebar3}/bin/rebar3";
          BURRITO_TARGET = target;
        };

        configurePhase = ''
          export HOME=$(mktemp -d)
          mkdir -p $HOME/.mix/archives
          export MIX_HOME=$HOME/.mix

          echo "Adding mix config..."
          cp ${mixConfig pname version currentTarget ertsPackage} mix.exs

          echo "Adding mix entry point..."
          mkdir -p lib
          cp ${mixEntry pname} lib/${pname}.ex

          echo "Installing mix_gleam..."
          tmpdir=$(mktemp -d)
          cp -r ${mixGleam}/* $tmpdir/
          cd $tmpdir
          mix do archive.build, archive.install --force
          cd -

          echo "Installing rebar3..."
          mix local.rebar rebar3 ${rebar3Package}/bin/rebar3 --force

          echo "Installing compiled mix deps..."
          ${builtins.concatStringsSep "\n" (
            builtins.attrValues (
              builtins.mapAttrs (name: drv: ''
                mkdir -p _build/prod/lib/${name}/ebin
                cp -r ${drv}/lib/erlang/lib/${name}-${drv.version}/ebin/* _build/prod/lib/${name}/ebin/
                chmod -R +w _build/prod/lib/${name}
              '') mixDeps
            )
          )}

          echo "Adding burrito..."
          cp -r ${mixDeps.burrito}/src /build/burrito-${mixDeps.burrito.version}
          chmod -R +w /build/burrito-${mixDeps.burrito.version}

          echo "Installing gleam deps..."
          mkdir -p deps

          ${builtins.concatStringsSep "\n" (
            builtins.attrValues (
              builtins.mapAttrs (name: path: ''
                cp -r ${path} deps/${name}
                chmod -R +w deps/${name}
              '') gleamDeps
            )
          )}
          mix gleam.deps.get
        '';

        buildPhase = ''
          mix compile
          mix release
        '';

        installPhase = ''
          mkdir -p $out/bin
          cp burrito_out/* $out/bin/${pname}
        '';
      }
    );
}
