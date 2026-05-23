{ config, pkgs, lib, ... }:

# SOLEM SMART HOME — Home Assistant + Zigbee2MQTT + Mosquitto self-host.
#
# Single responsibility: SOLO orchestrare hub IoT + broker MQTT + zigbee
# coordinator. Niente integrazione GAVIO (lo fa l'utente via API HASS).

let
  cfg = config.solem.smartHome;
in {
  options.solem.smartHome = {
    homeAssistant = {
      enable = lib.mkEnableOption "Home Assistant (IoT hub)";
      port = lib.mkOption { type = lib.types.port; default = 8123; };
    };

    mosquitto = {
      enable = lib.mkEnableOption "Mosquitto MQTT broker";
      port = lib.mkOption { type = lib.types.port; default = 1883; };
    };

    zigbee2mqtt = {
      enable = lib.mkEnableOption "Zigbee2MQTT (controller Zigbee senza vendor lock-in)";
      device = lib.mkOption {
        type = lib.types.str;
        default = "/dev/ttyUSB0";
        description = "Path USB del coordinator Zigbee (Sonoff dongle, etc.)";
      };
    };

    nodeRed = lib.mkEnableOption "Node-RED (flow-based automation visual)";
  };

  config = lib.mkMerge [
    # Home Assistant
    (lib.mkIf cfg.homeAssistant.enable {
      services.home-assistant = {
        enable = true;
        config = {
          homeassistant = {
            name = "SOLEM Home";
            unit_system = "metric";
            time_zone = "Europe/Rome";
            country = "IT";
          };
          http = {
            server_port = cfg.homeAssistant.port;
            use_x_forwarded_for = true;
            trusted_proxies = [ "127.0.0.1" "::1" ];
          };
          default_config = {};
          mqtt = lib.mkIf cfg.mosquitto.enable {
            broker = "127.0.0.1";
            port = cfg.mosquitto.port;
          };
        };
        extraComponents = [
          "esphome" "mqtt" "zha" "zwave_js"
          "philips_hue" "shelly" "tuya"
          # Niente integrazioni servizi a pagamento (Spotify/Netflix/Sonos) di
          # default. L'utente le aggiunge a runtime se ha un account.
        ];
      };
    })

    # Mosquitto
    (lib.mkIf cfg.mosquitto.enable {
      services.mosquitto = {
        enable = true;
        listeners = [{
          address = "0.0.0.0";
          port = cfg.mosquitto.port;
          settings.allow_anonymous = false;
        }];
      };
    })

    # Zigbee2MQTT
    (lib.mkIf cfg.zigbee2mqtt.enable {
      services.zigbee2mqtt = {
        enable = true;
        settings = {
          serial.port = cfg.zigbee2mqtt.device;
          mqtt = {
            base_topic = "zigbee2mqtt";
            server = "mqtt://127.0.0.1:${toString cfg.mosquitto.port}";
          };
          frontend = {
            port = 8081;
          };
          permit_join = false;
          advanced = {
            log_level = "info";
            channel = 11;
          };
        };
      };
    })

    # Node-RED
    (lib.mkIf cfg.nodeRed {
      services.node-red = {
        enable = true;
        openFirewall = false;
      };
    })
  ];
}
