{ config, lib, pkgs, utils, ... }:

with lib;
let
  cfg = config.declared-secrets;

  inherit (utils.systemdUtils.lib) mkPathSafeName shellEscape;
  safeName = name: replaceChars [ "/" ] [ "--" ] (mkPathSafeName (shellEscape name));

  supportedTypes =
    let
      atomicReplace = script: path: { base64, group, regenerate, ... }@args': ''
        set -u
        atomicReplace () {
          local group="$1"
          local path="$2"
          local basedir

          umask 077

          basedir="$(dirname -- "$path")"
          name="$(basename -- "$path")"
          tmppath="$basedir/.''${name}.$RANDOM"
          mkdir -p "$basedir"

          touch "$tmppath"
          chmod 600 "$tmppath"
          chown 0:0 "$tmppath"

          cat ${optionalString base64 "| base64 -w0"} > "$tmppath"
          chmod 440 "$tmppath"
          chown 0:"$group" "$tmppath"

          mv "$tmppath" "$path"
        }
      '' + optionalString (!regenerate) ''

        if [ -f "${path}" ]; then
          exit 0
        fi
      '' + ''
        mkdir -p ${cfg.directory}
        chown 0:0 ${cfg.directory}
        chmod 755 ${cfg.directory}

        {
          ${script args'}
        } | atomicReplace "${group}" "${path}"
      '';
    in
    {
      password = atomicReplace ({ length, trailingNewline, ... }:
        let
          # https://owasp.org/www-community/password-special-characters
          alphabet = "'A-Za-z0-9!\"#$%&'\\''()*+,-./:;<=>?@[\\]^_`{|}~'";
        in
        ''
          (LC_ALL=C; 2>/dev/null tr -dc ${alphabet} </dev/urandom | head -c ${toString length} ${optionalString trailingNewline "; echo"})
        '');

      uuid = atomicReplace ({ trailingNewline, ... }: ''
        (echo ${optionalString (!trailingNewline) "-n"} "$(< /proc/sys/kernel/random/uuid)")
      '');
    };
in
{
  options = {
    declared-secrets = {
      directory = mkOption {
        type = types.str;
        default = "/run/declared-secrets";
        description = "Directory where to store the declared keys";
      };

      secrets =
        let
          module = types.submodule ({ name, ... }@args: {
            options = {
              type = mkOption {
                type = types.enum (builtins.attrNames supportedTypes);
                default = "password";
                description = "Secret type";
              };

              length = mkOption {
                type = types.nullOr types.int;
                default = 31;
                description = "Generated password length";
              };

              trailingNewline = mkOption {
                type = types.bool;
                default = true;
                description = "Whether to add a trailing newline or not";
              };

              regenerate = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to regenerate this secret on next system boot";
              };

              group = mkOption {
                type = types.str;
                default = "keys";
                description = "Group who can read the keys";
              };

              base64 = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to encode secrets to base64";
              };

              __toString = mkOption {
                default = _: "${cfg.directory}/${name}";
                readOnly = true;
              };
            };
          });
        in
        mkOption {
          type = types.attrsOf module;
          default = { };
        };
    };
  };

  config =
    let
      createSecretUnit = name: secret:
        let
          path = "${cfg.directory}/${name}";
          unitName = "declared-secret-${safeName path}";
        in
        nameValuePair unitName {
          description = "Declared secret - ${path}";
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [ coreutils ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          script = supportedTypes.${secret.type} path secret;
        };
    in
    {
      systemd.services = mkMerge ([ (mapAttrs' createSecretUnit cfg.secrets) ]);
      users.groups.keys.gid = mkDefault 3001;
    };
}
