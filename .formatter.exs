[
  inputs: ["mix.exs", "config/*.exs", "{lib,test}/**/*.sface"],
  subdirectories: ["apps/*"],
  plugins: [Surface.Formatter.Plugin]
]
