{ lib }:

{ length, trailingNewline, ... }:

let
  inherit (lib) optionalString;

  # https://owasp.org/www-community/password-special-characters
  alphabet = "'A-Za-z0-9!\"#$%&'\\''()*+,-./:;<=>?@[\\]^_`{|}~'";
in
''
  (LC_ALL=C; 2>/dev/null tr -dc ${alphabet} </dev/urandom | head -c ${toString length} ${optionalString trailingNewline "; echo"})
''
