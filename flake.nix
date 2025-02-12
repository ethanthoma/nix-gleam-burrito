{
  description = "nix-gleam-burrito: A nix builder for packaging gleam apps to executables";

  outputs =
    {
      self,
    }:
    {
      overlays.default = import ./overlay.nix;
    };
}
