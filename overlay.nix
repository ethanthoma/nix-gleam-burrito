final: prev:
let
  callPackage = final.darwin.apple_sdk_11_0.callPackage or final.callPackage;
in
{
  inherit (callPackage ./builder { }) buildGleamBurrito;
}
