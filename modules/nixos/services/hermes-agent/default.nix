{ config, configLib, pkgs, lib, ... }:

let
  # provider = "openai-api";
  # big_model = "gpt-5.5";
  # small_model = "gpt.5.4-mini";
  # nano_model = small_model;
  # base_url = "https://api.openai.com/v1";
  provider = "opencode-go";
  big_model = "deepseek-v4.1-flash";
  small_model = "deepseek-v4.1-flash";
  nano_model = small_model;
  base_url = "https://opencode.ai/zen/go/v1";
  elevenlabsScribeStt = pkgs.writeShellApplication {
    name = "elevenlabs-scribe-stt";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      set -euo pipefail

      input_path=""
      language=""

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --language)
            language="''${2:-}"
            shift 2
            ;;
          *)
            input_path="$1"
            shift
            ;;
        esac
      done

      if [ -z "''${ELEVENLABS_API_KEY:-}" ]; then
        echo "ELEVENLABS_API_KEY is not set" >&2
        exit 1
      fi

      if [ -z "$input_path" ]; then
        echo "missing input audio path" >&2
        exit 1
      fi

      curl_args=(
        -fsS
        -X POST
        "https://api.elevenlabs.io/v1/speech-to-text"
        -H "xi-api-key: $ELEVENLABS_API_KEY"
        -F "model_id=scribe_v2"
        -F "file=@$input_path"
        -F "tag_audio_events=false"
        -F "diarize=false"
        -F "timestamps_granularity=none"
      )

      if [ -n "$language" ] && [ "$language" != "auto" ]; then
        curl_args+=(-F "language_code=$language")
      fi

      curl "''${curl_args[@]}" | jq -r '.text // empty'
    '';
  };
  executorHost =
    "${config.my.services.executor.subdomain}.${config.my.server.location}.${config.my.domain}";
in {
  imports = [ ./matrix.nix ];
  sops.secrets."hermes-env" = { format = "yaml"; };
  users.groups.hermes = { };
  users.users.hermes = {
    isSystemUser = true;
    group = "hermes";
    home = "/home/hermes";
    createHome = true;
    shell = pkgs.bashInteractive;
  };

  services.hermes-agent = {
    enable = true;
    createUser = false;
    container.enable = true;
    container.hostUsers = [ "hermes" ];
    container.extraOptions = [
      "--dns=100.100.100.100"
      "--env-file=${config.sops.secrets."hermes-env".path}"
    ];
    # ... rest of config is identical
    environmentFiles = [ config.sops.secrets."hermes-env".path ];
    addToSystemPackages = true;
    extraDependencyGroups = [ "anthropic" "messaging" "tts-premium" ];
    mcpServers.executor = {
      url = "https://${executorHost}/mcp";
      headers.Authorization = "Bearer \${EXECUTOR_MCP_TOKEN}";
    };

    # config
    settings = {
      model = {
        inherit provider base_url;
        default = big_model;
      };
      toolsets = [ "all" ];
      tool_output = {
        max_bytes = 75000;
        max_lines = 5000;
        max_line_length = 5000;
      };
      max_turns = 100;

      approvals = {
        mode = "off"; # skip all!
      };
      # SUB AGENTS
      delegation = {
        # n subagents
        max_concurrent_children = 6;
        # subagent spawn depth
        max_spawn_depth = 3;
        subagent_auto_approve = true;
      };
      terminal = {
        backend = "local";
        cwd = ".";
        timeout = 180;
      };
      compression = {
        enabled = true;
        threshold = 0.85;
        # how much of the conv is not compressed at the end. So you end up with summary + last few bits
        # target_ratio = 0.2;
      };

      auxiliary = {
        title_generation = {
          inherit provider;
          model = nano_model;
          inherit base_url;
        };
        compression = {
          model = small_model;
          inherit provider;
          inherit base_url;
        };
      };

      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
      worktree = true;
      display = {
        compact = false;
        personality = "concise";
      };
      agent = {
        max_turns = 60;
        verbose = false;
      };

      tts = {
        provider = "elevenlabs";
        elevenlabs = {
          voice_id = "pNInz6obpgDQGcFmaJgB";
          model_id = "eleven_multilingual_v2";
        };
      };

      stt = {
        provider = "elevenlabs-scribe";
        providers.elevenlabs-scribe = {
          type = "command";
          command = "${
              lib.getExe elevenlabsScribeStt
            } {input_path} --language {language}";
          format = "txt";
          language = "en";
          model = "scribe_v2";
          timeout = 300;
        };
      };
    };

  };
}
