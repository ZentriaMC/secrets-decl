{ lib }:

{ trailingNewline, ... }:

let
  inherit (lib) optionalString;
in
''
  (echo ${optionalString (!trailingNewline) "-n"} "$(< /proc/sys/kernel/random/uuid)")
''
