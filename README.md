# nix-gleam-burrito

A builder that allows gleam projects to be easily wrapped via [burrito](https://github.com/burrito-elixir/burrito).

This builder is inspired by [nix-gleam](https://github.com/arnarg/nix-gleam).

> [!IMPORTANT]
> This only works for the erlang target of gleam as burrito is for elixir apps.

## buildGleamBurrito

The builder is in the overlay. You can import it and use it like so in your `flake.nix`:

```nix
{
    description = "My gleam burrito~";

    inputs = {
        inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        inputs.flake-utils.url = "github:numtide/flake-utils";
        inputs.nix-gleam-burrito.url = "github:ethanthoma/nix-gleam-burrito";
    };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-gleam-burrito,
    }:
    {
      overlays = {
        default = nixpkgs.lib.composeManyExtensions [
          nix-gleam.overlays.default
          nix-gleam-burrito.overlays.default
        ];
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;

        default = pkgs.buildGleamBurrito {
          # The pname and version will be read from your `gleam.toml`
          src = ./.;
          # The default burrito target is linux, you can override it with
          # target = "macos";
        };
      in 
      {
        packages = {
          inherit default;
        };
      }
    );
}
````
