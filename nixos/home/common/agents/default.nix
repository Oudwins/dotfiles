{ config, pkgs, lib, ... }@args: {
  imports = [ ];
  # We don't install opencode, claude code or codex here because these packages are updated a lot so would prefer to just install manually


  home.packages = with pkgs; [
    jq
    bun
    btca
    beads
    jsonc2json
    # Opencode for code linting
    typescript-language-server
  ];

  # Local AI
  # ollama
  # ollama run qwen3:8b
  ''
    ram  model
    8–16GB qwen3:4b
    16–24GB qwen3:8b
    32–36GB qwen3:14b or qwen3:32b

    ---
    Setup
    -----
    OLLAMA_CONTEXT_LENGTH=32768 ollama serve
    ollama run qwen3:8b # only first time. To pull the model. You can also do ollama pull {model}
    ollama run qwen3-coder:30b
  '';
}
