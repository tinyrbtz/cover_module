# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0

Initial release. A drop-in fork of Elixir's `Mix.Tasks.Test.Coverage` with
quieter HTML generation (silences `:cover` notices from Mimic-restored modules),
a summary table that hides fully-covered modules, and a public
`with_silenced_io/1,2` helper. Extracted from internal Tiny Robots use.
