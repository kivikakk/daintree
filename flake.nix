{
  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      formatter = pkgs.alejandra;

      devShells.default = pkgs.mkShell {
        name = "daintree";
        buildInputs = [
          pkgs.qemu
          pkgs.dtc
        ];
      };
    });
}
