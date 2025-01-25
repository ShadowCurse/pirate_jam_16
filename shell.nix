{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  SDL2_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [pkgs.SDL2]}";
  EM_CACHE="/home/antaraz/.emscripten_cache";

  buildInputs = with pkgs; [
    SDL2
    pkg-config
    emscripten
    zip
  ];
}
