{
  description = "Module to declare secrets";

  outputs = { self }: {
    nixosModules.declaredSecrets = import ./module.nix;
    nixosModule = self.nixosModules.declaredSecrets;
  };
}
