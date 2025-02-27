{ lib
, config
, pkgs
, ...
} @ args:
let
  cfg = config.programs.plasma;
  hasWidget = widgetName: builtins.any (panel: builtins.any (widget: widget.name == widgetName) panel.widgets) cfg.panels;

  # An attrset keeping track of the packages which should be added when a
  # widget is present in the config.
  additionalWidgetPackages = with pkgs; {
    "com.github.antroids.application-title-bar" = [ application-title-bar ];
    plasmusic-toolbar = [ plasmusic-toolbar ];
    "org.kde.windowbuttons" = [ kdePackages.applet-window-buttons6 ];
  };
  # An attrset of service-names and widgets/conditions. If any of the
  # conditions (given in cond) evaluate to true for any of the widgets with the
  # name given in the widget attribute, the service is marked for restart in
  # the panel-script.
  serviceRestarts = {
    "plasma-plasmashell" = [
      {
        widget = "org.kde.plasma.systemmonitor";
        cond = widget: ((builtins.hasAttr "org.kde.ksysguard.piechart/General" widget.config) && (builtins.hasAttr "showLegend" widget.config."org.kde.ksysguard.piechart/General"));
      }
    ];
  };
  widgetsOfName = name: (lib.filter (w: w.name == name) (lib.flatten (map (panel: panel.widgets) cfg.panels)));
  shouldRestart = service:
    (
      let candidates = serviceRestarts."${service}";
      in (builtins.any (x: x) (map (v: (builtins.any v.cond (widgetsOfName v.widget))) candidates))
    );

  widgets = import ./widgets args;

  panelType = lib.types.submodule ({ config, ... }: {
    options = {
      height = lib.mkOption {
        type = lib.types.int;
        default = 44;
        description = "The height of the panel.";
      };
      offset = lib.mkOption {
        type = with lib.types; nullOr int;
        default = null;
        example = 100;
        description = "The offset of the panel from the anchor-point.";
      };
      minLength = lib.mkOption {
        type = with lib.types; nullOr int;
        default = null;
        example = 1000;
        description = "The minimum required length/width of the panel.";
      };
      maxLength = lib.mkOption {
        type = with lib.types; nullOr int;
        default = null;
        example = 1600;
        description = "The maximum allowed length/width of the panel.";
      };
      lengthMode = lib.mkOption {
        type = with lib.types; nullOr (enum [ "fit" "fill" "custom" ]);
        default =
          if config.minLength != null || config.maxLength != null then
            "custom"
          else
            null;
        example = "fit";
        description = "The length mode of the panel. Defaults to `custom` if either `minLength` or `maxLength` is set.";
      };
      location = lib.mkOption {
        type = with lib.types; nullOr (enum [ "top" "bottom" "left" "right" "floating" ]);
        default = "bottom";
        example = "left";
        description = "The location of the panel.";
      };
      alignment = lib.mkOption {
        type = with lib.types; nullOr (enum [ "left" "center" "right" ]);
        default = "center";
        example = "right";
        description = "The alignment of the panel.";
      };
      hiding = lib.mkOption {
        type = with lib.types; nullOr (enum [
          "none"
          "autohide"
          # Plasma 5 only
          "windowscover"
          "windowsbelow"
          # Plasma 6 only
          "dodgewindows"
          "normalpanel"
          "windowsgobelow"
        ]);
        default = null;
        example = "autohide";
        description = ''
          The hiding mode of the panel. Here windowscover and windowsbelow are
          plasma 5 only, while dodgewindows, windowsgobelow and normalpanel are
          plasma 6 only.
        '';
      };
      floating = lib.mkEnableOption "Enable or disable floating style.";
      widgets = lib.mkOption {
        type = lib.types.listOf widgets.type;
        default = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.pager"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
        example = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.digitalclock"
        ];
        description = ''
          The widgets to use in the panel. To get the names, it may be useful
          to look in the share/plasma/plasmoids folder of the nix-package the
          widget/plasmoid is from. Some packages which include some
          widgets/plasmoids are for example plasma-desktop and
          plasma-workspace.
        '';
        apply = map widgets.convert;
      };
      screen = lib.mkOption {
        type = with lib.types; nullOr (oneOf [ ints.unsigned (listOf ints.unsigned) (enum [ "all" ]) ]);
        default = null;
        description = ''
          The screen the panel should appear on. Can be an int, or a list of ints,
          starting from 0, representing the ID of the screen the panel should
          appear on. Alternatively it can be set to "any" if the panel should
          appear on all the screens.
        '';
      };
      extraSettings = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          Extra lines to add to the layout.js. See
          https://develop.kde.org/docs/plasma/scripting/ for inspiration.
        '';
      };
    };
  });

  anyPanelOrWallpaperSet = ((cfg.workspace.wallpaper != null) ||
    (cfg.workspace.wallpaperSlideShow != null) ||
    (cfg.workspace.wallpaperPictureOfTheDay != null) ||
    (cfg.workspace.wallpaperPlainColor != null) ||
    ((builtins.length cfg.panels) > 0));
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "programs" "plasma" "extraWidgets" ] "Place the widget packages in home.packages or environment.systemPackages instead.")
  ];

  options.programs.plasma.panels = lib.mkOption {
    type = lib.types.listOf panelType;
    default = [ ];
  };

  # Wallpaper and panels are in the same script since the resetting of the
  # panels in the panels-script also has a tendency to reset the wallpaper, so
  # these should run at the same time.
  config = (lib.mkIf cfg.enable {
    home.packages = (lib.flatten (lib.filter (x: x != null)
      (lib.mapAttrsToList
        (widgetName: packages: if (hasWidget widgetName) then packages else null)
        additionalWidgetPackages)));

    programs.plasma.startup.desktopScript."panels_and_wallpaper" = (lib.mkIf anyPanelOrWallpaperSet
      (
        let
          anyPanels = ((builtins.length cfg.panels) > 0);
          anyNonDefaultScreens = ((builtins.any (panel: panel.screen != null)) cfg.panels);
          panelPreCMD = (if anyPanels then ''
            # We delete plasma-org.kde.plasma.desktop-appletsrc to hinder it
            # growing indefinitely. See:
            # https://github.com/nix-community/plasma-manager/issues/76
            [ -f ${config.xdg.configHome}/plasma-org.kde.plasma.desktop-appletsrc ] && rm ${config.xdg.configHome}/plasma-org.kde.plasma.desktop-appletsrc
          '' else "");
          panelLayoutStr = (if anyPanels then (import ../lib/panel.nix { inherit lib; inherit config; }) else "");
          panelPostCMD = (if anyNonDefaultScreens then ''
            sed -i 's/^lastScreen\\x5b$i\\x5d=/lastScreen[$i]=/' ${config.xdg.configHome}/plasma-org.kde.plasma.desktop-appletsrc
          '' else "");
          # This meaningless comment inserts the URL into the desktop-script
          # which means that when the wallpaper is updated, the sha256 hash
          # changes and the script will be re-run.
          wallpaperDesktopScript = (if (cfg.workspace.wallpaper != null) then ''
            // Wallpaper to set later: ${cfg.workspace.wallpaper}
          '' else "");
          wallpaperPostCMD = (if (cfg.workspace.wallpaper != null) then ''
            plasma-apply-wallpaperimage ${cfg.workspace.wallpaper}
          '' else "");
          wallpaperSlideShow = (if (cfg.workspace.wallpaperSlideShow != null) then ''
            // Wallpaper slideshow
            let allDesktops = desktops();
            for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex++) {
                var desktop = allDesktops[desktopIndex];
                desktop.wallpaperPlugin = "org.kde.slideshow";
                desktop.currentConfigGroup = Array("Wallpaper", "org.kde.slideshow", "General");
                desktop.writeConfig("SlidePaths", ${with cfg.workspace.wallpaperSlideShow; if ((builtins.isPath path) || (builtins.isString path)) then
                  "\"" + (builtins.toString path) + "\"" else
                  "[" + (builtins.concatStringsSep "," (map (s: "\"" + s + "\"") path)) + "]"});
                desktop.writeConfig("SlideInterval", "${builtins.toString cfg.workspace.wallpaperSlideShow.interval}");
            }
          '' else "");
          wallpaperPOTD = (if (cfg.workspace.wallpaperPictureOfTheDay != null) then ''
            // Wallpaper POTD
            let allDesktops = desktops();
            for (const desktop of allDesktops) {
                desktop.wallpaperPlugin = "org.kde.potd";
                desktop.currentConfigGroup = ["Wallpaper", "org.kde.potd", "General"];
                desktop.writeConfig("Provider", "${cfg.workspace.wallpaperPictureOfTheDay.provider}");
                desktop.writeConfig("UpdateOverMeteredConnection", "${if (cfg.workspace.wallpaperPictureOfTheDay.updateOverMeteredConnection) then "1" else "0"}");
              }
          '' else "");
          wallpaperPlainColor = (if (cfg.workspace.wallpaperPlainColor != null) then ''
            // Wallpaper plain color
            let allDesktops = desktops();
            for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex++) {
                var desktop = allDesktops[desktopIndex];
                desktop.wallpaperPlugin = "org.kde.color";
                desktop.currentConfigGroup = Array("Wallpaper", "org.kde.color", "General");
                desktop.writeConfig("Color", "${cfg.workspace.wallpaperPlainColor}");
            }
          '' else ""
          );
        in
        {
          preCommands = panelPreCMD;
          text = panelLayoutStr + wallpaperDesktopScript + wallpaperSlideShow + wallpaperPOTD + wallpaperPlainColor;
          postCommands = panelPostCMD + wallpaperPostCMD;
          restartServices =
            (lib.unique (if anyNonDefaultScreens then [ "plasma-plasmashell" ] else [ ])
              ++ (lib.filter (service: shouldRestart service) (builtins.attrNames serviceRestarts)));
          priority = 2;
        }
      ));
  });
}
