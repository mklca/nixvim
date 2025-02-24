{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  pluginWithConfigType = types.submodule {
    options = {
      config = mkOption {
        type = types.lines;
        description = "vimscript for this plugin to be placed in init.vim";
        default = "";
      };

      optional =
        mkEnableOption "optional"
        // {
          description = "Don't load by default (load with :packadd)";
        };

      plugin = mkOption {
        type = types.package;
        description = "vim plugin";
      };
    };
  };
in {
  options = {
    viAlias = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Symlink <command>vi</command> to <command>nvim</command> binary.
      '';
    };

    vimAlias = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Symlink <command>vim</command> to <command>nvim</command> binary.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.neovim-unwrapped;
      description = "Neovim to use for nixvim";
    };

    wrapRc = mkOption {
      type = types.bool;
      description = "Should the config be included in the wrapper script";
      default = false;
    };

    finalPackage = mkOption {
      type = types.package;
      description = "Wrapped neovim";
      readOnly = true;
    };

    initContent = mkOption {
      type = types.str;
      description = "The content of the init.lua file";
      readOnly = true;
      visible = false;
    };
  };

  config = let
    defaultPlugin = {
      plugin = null;
      config = "";
      optional = false;
    };

    normalizedPlugins = map (x:
      defaultPlugin
      // (
        if x ? plugin
        then x
        else {plugin = x;}
      ))
    config.extraPlugins;

    neovimConfig = pkgs.neovimUtils.makeNeovimConfig ({
        inherit (config) viAlias vimAlias;
        # inherit customRC;
        plugins = normalizedPlugins;
      }
      # Necessary to make sure the runtime path is set properly in NixOS 22.05,
      # or more generally before the commit:
      # cda1f8ae468 - neovim: pass packpath via the wrapper
      // optionalAttrs (functionArgs pkgs.neovimUtils.makeNeovimConfig ? configure) {
        configure.packages = {
          nixvim = {
            start = map (x: x.plugin) normalizedPlugins;
            opt = [];
          };
        };
      });

    customRC =
      ''
        vim.cmd([[
          ${neovimConfig.neovimRcContent}
        ]])
      ''
      + config.content;

    extraWrapperArgs = builtins.concatStringsSep " " (
      (optional (config.extraPackages != [])
        ''--prefix PATH : "${makeBinPath config.extraPackages}"'')
      ++ (optional (config.wrapRc)
        ''--add-flags -u --add-flags "${pkgs.writeText "init.lua" customRC}"'')
    );

    wrappedNeovim = pkgs.wrapNeovimUnstable config.package (neovimConfig
      // {
        wrapperArgs = lib.escapeShellArgs neovimConfig.wrapperArgs + " " + extraWrapperArgs;
        wrapRc = false;
      });
  in {
    type = lib.mkForce "lua";
    finalPackage = wrappedNeovim;
    initContent = customRC;
    extraPlugins =
      if config.wrapRc
      then [config.filesPlugin]
      else [];
  };
}
