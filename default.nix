{
  poetry2nix,
  python3,
}:
poetry2nix.mkPoetryApplication {
  projectDir = ./.;
  python = python3;
  overrides =
    poetry2nix.defaultPoetryOverrides.extend (final: prev: {
    });
}
