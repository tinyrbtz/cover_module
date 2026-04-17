# Tiny Robots Cover Module

[![CI](https://github.com/tinyrbtz/cover_module/actions/workflows/ci.yml/badge.svg)](https://github.com/tinyrbtz/cover_module/actions/workflows/ci.yml)
[![Hex version](https://img.shields.io/hexpm/v/rbtz_cover_module.svg "Hex version")](https://hex.pm/packages/rbtz_cover_module)
[![Hex downloads](https://img.shields.io/hexpm/dt/rbtz_cover_module.svg "Hex downloads")](https://hex.pm/packages/rbtz_cover_module)
[![License](http://img.shields.io/:license-mit-blue.svg)](http://doge.mit-license.org)

A Mix test coverage tool used by [Tiny Robots](https://github.com/tinyrbtz).

`Rbtz.CoverModule` is a fork of Elixir's built-in `Mix.Tasks.Test.Coverage` with a few additional features layered on top. It is a **drop-in replacement** — all upstream options (`summary`, `threshold`, `ignore_modules`, `output`, `export`, `local_only`) behave identically, so switching is just a one-line `tool:` change in your `mix.exs`.

## Hides fully-covered modules from the summary table

Only modules below 100% appear in the per-module breakdown — the total line still reflects the full project. Keeps the summary focused on what needs attention as coverage grows.

## Quieter HTML generation

When used with [Mimic](https://hex.pm/packages/mimic) (or anything else that restores modules between tests), `:cover`'s HTML phase floods stdout with `Redefining module ...` / `Restoring module ...` notices. `Rbtz.CoverModule` redirects the `:cover_server` group leader during HTML generation only, suppressing that noise while leaving the summary table, threshold result, and regular test output untouched.

## Installation

Add `rbtz_cover_module` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:rbtz_cover_module, "~> 0.1", only: [:test], runtime: false}
  ]
end
```

Run `mix deps.get`.

## Usage

Set it as the `tool:` in your `test_coverage:` config:

```elixir
def project do
  [
    # ...
    test_coverage: [
      tool: Rbtz.CoverModule,
      summary: [threshold: 100],
      ignore_modules: [
        MyApp.Application,
        MyApp.Release,
        ~r/^MyApp\.Generated\./
      ]
    ]
  ]
end
```

Then run as usual:

```
mix test --cover                         # inline summary + HTML in cover/
mix test --cover --export-coverage unit  # export coverdata for later merge
mix test.coverage                        # merge exported coverdata
```

## Configuration

`Rbtz.CoverModule` accepts the same options as Elixir's built-in coverage tool. See the upstream [`Mix.Tasks.Test.Coverage`](https://hexdocs.pm/mix/Mix.Tasks.Test.Coverage.html) docs for the full option list (`summary`, `threshold`, `ignore_modules`, `output`, `export`, `local_only`). Just set `tool: Rbtz.CoverModule`.

## Credits

Forked from Elixir's `Mix.Tasks.Test.Coverage`. Used in production across Tiny Robots projects.

## License

MIT. See [LICENSE](LICENSE).
