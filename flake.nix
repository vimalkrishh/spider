{
  inputs = {
    systems.url = "github:nix-systems/default";
    flake-parts.url = "github:hercules-ci/flake-parts";
    haskell-flake.url = "github:srid/haskell-flake";

    # Match euler-nix-common's nixpkgs pin so that `ghc98` == 9.8.4, the migrated
    # dependency versions line up, and the patched GHC derivation matches euler's
    # cached build (cache.nixos.asia/juspay).
    nixpkgs.url = "github:nixos/nixpkgs/89c2b2330e733d6cdb5eae7b899326930c2c0648";

    # streamly is only used for its `core` sub-package. Input name kept as
    # `streamly` so downstream can `inputs.streamly.follows = "common/streamly-core"`.
    streamly.url = "github:composewell/streamly/12d85026291d9305f93f573d284d0d35abf40968";
    streamly.flake = false;

    # ghc 9.8.4 (already-migrated) forks, pinned to the exact revs used by
    # euler-nix-common. Input names are kept stable so downstream repos can
    # `follows` them onto the common set.
    classyplate.url = "github:infinitumkiran/classyplate/71022deb4163c39ef278e30c2c1d3e56a3137812";
    classyplate.flake = false;

    references.url = "github:infinitumkiran/references/663c62cddf86d84f5f91568f5504e65e92cf7461";
    references.flake = false;

    # Dependency of `references`; the nixpkgs Hackage version is marked broken.
    instance-control.url = "github:infinitumkiran/instance-control/7a0ab66ffa44f8634857440701b8451a20436756";
    instance-control.flake = false;

    # eswar2001 large-anon 0.2 ported to GHC 9.8.4 (branch ghc984-port). Only
    # `large-anon` is sourced from here; the rest of the family stays on the
    # common (Hackage) set — matching euler-api-txns.
    large-records.url = "github:infinitumkiran/large-records/35005b63a183ca8da3d05b22cefbf41d6a1ba3cf";
    large-records.flake = false;

    ghc-hasfield-plugin.url = "github:eswar2001/ghc-hasfield-plugin/13887ab3f0d26bc724300521c012bf335e1945c6";
    ghc-hasfield-plugin.flake = false;

    record-dot-preprocessor.url = "github:AyushChaturvedi-7/record-dot-preprocessor/2b126423423fba113547f3a01bc66ef0cf38b263";
    record-dot-preprocessor.flake = false;
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ withSystem, ... }: {
      systems = import inputs.systems;
      imports = [ inputs.haskell-flake.flakeModule ];
      perSystem = { self', pkgs, system, ... }:
        let
          # Patched GHC 9.8.4 that adds the `desugarResultAction` plugin hook
          # (used by the `warner` plugin). Applies the exact same patch set, in
          # the same order, as euler-nix-common's `ghc98-perf-events`, so the
          # resulting GHC derivation is substitutable from the juspay cache.
          ghc-desugar-plugin-overlay = final: prev: {
            haskell = prev.haskell // {
              compiler = prev.haskell.compiler // {
                ghc98-desugar-plugin = prev.haskell.compiler.ghc98.overrideAttrs (drv: {
                  patches = (drv.patches or [ ]) ++ [
                    ./ghc-patches/0001-Add-a-primop-to-get-the-thread-statistics.patch
                    ./ghc-patches/added-support-for-desugar-plugin.patch
                  ];
                });
              };
              packages = prev.haskell.packages // {
                ghc98-desugar-plugin = prev.haskell.packages.ghc98.override {
                  buildHaskellPackages = final.buildPackages.haskell.packages.ghc98-desugar-plugin;
                  ghc = final.buildPackages.haskell.compiler.ghc98-desugar-plugin;
                  # Same all-cabal-hashes pin as euler-nix-common so that Hackage
                  # version resolution (e.g. ghc-tcplugin-api) matches the
                  # already-migrated set.
                  all-cabal-hashes = builtins.fetchurl {
                    url = "https://github.com/commercialhaskell/all-cabal-hashes/archive/0c3c1e49cb6c1ba8419d11e259eb72f2e89e76ca.tar.gz";
                    sha256 = "1qs0cxvzjpsysnp5fm5i6b8p9vb2rsdw9pcyqaf8gi8nv6ppv40k";
                  };
                };
              };
            };
          };
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            overlays = [ ghc-desugar-plugin-overlay ];
            inherit system;
          };

          haskellProjects.default = {
            projectFlakeName = "spider";
            # NOTE: `warner` requires `ghc98-desugar-plugin` (the patched GHC that
            # adds the `desugarResultAction` hook), so it is the project-wide base.
            # The patch set/order matches euler-nix-common's `ghc98-perf-events`
            # exactly (see ./ghc-patches), so the compiler derivation is identical
            # to euler's and resolves from cache rather than a source build; the
            # patch is purely additive (adds one hook) so the other packages build
            # against it unchanged. Downstream repos build spider against euler's
            # own patched GHC + cache, so this choice only governs spider's
            # standalone build.
            basePackages = pkgs.haskell.packages.ghc98-desugar-plugin;

            packages = {
              streamly-core.source = inputs.streamly + /core;
              classyplate.source = inputs.classyplate;
              references.source = inputs.references;
              instance-control.source = inputs.instance-control;
              # Only large-anon is taken from the ghc984-port fork; the rest of
              # the large-records family comes from the common (Hackage) set.
              large-anon.source = inputs.large-records + /large-anon;
              ghc-hasfield-plugin.source = inputs.ghc-hasfield-plugin;
              record-dot-preprocessor.source = inputs.record-dot-preprocessor;
              ghc-tcplugin-api.source = "0.16.1.0";
            };

            settings = {
              # Mirrors the already-migrated settings from euler-nix-common.
              classyplate = {
                jailbreak = true;
                broken = false;
              };
              large-anon = {
                broken = false;
                check = false;
                jailbreak = true;
              };
              large-records = {
                broken = false;
                jailbreak = true;
              };
              large-generics.broken = false;
              typelet = {
                broken = false;
                jailbreak = true;
              };
              record-dot-preprocessor.jailbreak = true;

              # Local plugin packages: skip their test-suites (they self-apply
              # the plugin, which requires a running collector / extra setup).
              sheriff.check = false;
              fdep.check = false;
              api-contract.check = false;
              fieldInspector.check = false;
              warner.check = false;
              paymentFlow.check = false;
              endpoints.check = false;
              dc.check = false;
              keyLookupTracker.check = false;
              coresyn2chart.check = false;
            };

            devShell = {
              mkShellArgs = {
                name = "spider-ghc98";
              };
              # HLS 2.12 fails to configure against this GHC and isn't needed for
              # the build loop.
              tools = hp: {
                haskell-language-server = null;
              };
              hlsCheck.enable = false;
            };
          };

          packages.default = self'.packages.fdep;
        };

      flake.haskellFlakeProjectModules = {
        # Consumed by downstream repos: `inputs.spider.haskellFlakeProjectModules.output`
        output = { pkgs, lib, ... }: withSystem pkgs.system ({ config, ... }:
          config.haskellProjects."default".defaults.projectModules.output
        );
      };
    });
}
