defmodule Rbtz.CoverModule do
  @moduledoc """
  A drop-in replacement for Elixir's built-in `Mix.Tasks.Test.Coverage` that
  silences the noisy `:cover` output generated during HTML report creation —
  particularly when used alongside tools like
  [Mimic](https://hex.pm/packages/mimic), which restore modules between tests
  and cause `:cover` to print a large number of `Redefining module ...` /
  `Restoring module ...` notices.

  All upstream options (`summary`, `threshold`, `ignore_modules`, `output`,
  `export`, `local_only`) behave identically. Switching is a one-line change
  in your `mix.exs` `test_coverage:` config:

      test_coverage: [
        tool: Rbtz.CoverModule,
        summary: [threshold: 100],
        ignore_modules: [
          MyApp.Application,
          MyApp.Release,
          ~r/^MyApp\\.Generated\\./
        ]
      ]

  See the README for a full list of additions over the upstream tool.
  """
  @compile {:no_warn_undefined, :cover}

  @default_threshold 90

  @doc false
  def start(compile_path, opts) do
    Mix.shell().info("Cover compiling modules ...")
    Mix.ensure_application!(:tools)

    if Keyword.get(opts, :local_only, true) do
      :cover.local_only()
    end

    cover_compile([compile_path])

    if name = opts[:export] do
      fn ->
        Mix.shell().info("\nExporting cover results ...\n")
        export_cover_results(name, opts)
      end
    else
      fn ->
        Mix.shell().info("\nGenerating cover results ...\n")
        generate_cover_results(opts)
      end
    end
  end

  @doc false
  def generate_cover_results(opts) do
    {:result, ok, _fail} = :cover.analyse(:coverage, :line)
    ignore = opts[:ignore_modules] || []
    modules = Enum.reject(:cover.modules(), &ignored?(&1, ignore))

    if summary_opts = Keyword.get(opts, :summary, true) do
      summary(ok, modules, summary_opts)
    end

    html(modules, opts)
  end

  @doc false
  def summary_results(results, keep) do
    {module_results, totals} = gather_coverage(results, keep)

    {module_results |> Enum.reject(fn {coverage, _module} -> coverage >= 100.0 end), totals}
  end

  @doc """
  Runs `fun` with the current process's group leader redirected to a silent
  `StringIO`, so any output written to stdout during the call is suppressed.
  Group leaders are restored afterwards regardless of how `fun` returns.

  Pass a list of additional pids as the first argument to silence them too —
  useful for long-lived processes (like `:cover_server`) that write through
  their own group leader.

      Rbtz.CoverModule.with_silenced_io(fn ->
        noisy_function()
      end)

      Rbtz.CoverModule.with_silenced_io([Process.whereis(:cover_server)], fn ->
        :cover.async_analyse_to_file(...)
      end)
  """
  def with_silenced_io(fun), do: [] |> with_silenced_io(fun)

  @doc false
  def with_silenced_io(extra_pids, fun) do
    pids = [self() | extra_pids] |> Enum.reject(&is_nil/1) |> Enum.uniq()
    {:ok, silenced_io} = StringIO.open("")

    original_group_leaders =
      for pid <- pids do
        {:group_leader, group_leader} = Process.info(pid, :group_leader)
        {pid, group_leader}
      end

    # :cover writes these notices through the long-lived cover server, while
    # async_analyse_to_file/3 also spawns worker processes. Redirecting both the
    # caller and the cover server keeps the suppression scoped to HTML output.
    Enum.each(pids, &Process.group_leader(&1, silenced_io))

    try do
      fun.()
    after
      Enum.each(original_group_leaders, fn {pid, group_leader} ->
        Process.group_leader(pid, group_leader)
      end)
    end
  end

  defp cover_compile(compile_paths) do
    _ = :cover.stop()
    {:ok, _pid} = :cover.start()

    for compile_path <- compile_paths do
      case compile_path |> beams() |> :cover.compile_beam() do
        results when is_list(results) ->
          :ok

        {:error, reason} ->
          Mix.raise(
            "Failed to cover compile directory #{inspect(Path.relative_to_cwd(compile_path))} " <>
              "with reason: #{inspect(reason)}"
          )
      end
    end
  end

  # Pick beams from the compile_path but if by any chance it is a protocol,
  # gets its path from the code server (which will most likely point to
  # the consolidation directory as long as it is enabled).
  defp beams(dir) do
    consolidation_dir = Mix.Project.consolidation_path()

    consolidated =
      case File.ls(consolidation_dir) do
        {:ok, files} -> files
        _ -> []
      end

    # spell-checker:disable-next-line
    for file <- File.ls!(dir), Path.extname(file) == ".beam" do
      with true <- file in consolidated,
           [_ | _] = path <- file |> Path.rootname() |> String.to_atom() |> :code.which() do
        path
      else
        _ -> dir |> Path.join(file) |> String.to_charlist()
      end
    end
  end

  defp export_cover_results(name, opts) do
    output = Keyword.get(opts, :output, "cover")
    File.mkdir_p!(output)

    case :cover.export(~c"#{output}/#{name}.coverdata") do
      :ok ->
        Mix.shell().info("Run \"mix test.coverage\" once all exports complete")

      {:error, reason} ->
        Mix.shell().error("Export failed with reason: #{inspect(reason)}")
    end
  end

  defp ignored?(mod, ignores) do
    Enum.any?(ignores, &ignored_any?(mod, &1))
  end

  defp ignored_any?(mod, %Regex{} = re), do: Regex.match?(re, inspect(mod))
  defp ignored_any?(mod, other), do: mod == other

  defp html(modules, opts) do
    output = Keyword.get(opts, :output, "cover")
    File.mkdir_p!(output)
    cover_server = Process.whereis(:cover_server)

    # The default :cover HTML generation prints extra noise for Mimic-restored
    # coverdata. We only silence this phase, including the cover server itself,
    # so the summary and final status still go to the normal terminal output.
    [cover_server]
    |> with_silenced_io(fn ->
      modules
      |> Enum.map(fn mod ->
        pid = :cover.async_analyse_to_file(mod, ~c"#{output}/#{mod}.html", [:html])
        Process.monitor(pid)
      end)
      |> Enum.each(fn ref ->
        receive do
          {:DOWN, ^ref, :process, _pid, _reason} ->
            :ok
        end
      end)
    end)

    Mix.shell().info("Generated HTML coverage results in #{inspect(output)} directory")
  end

  defp summary(results, keep, summary_opts) do
    {module_results, totals} = results |> summary_results(keep)
    module_results = Enum.sort(module_results, :desc)
    print_summary(module_results, totals, summary_opts)

    if totals < get_threshold(summary_opts) do
      print_failed_threshold(totals, get_threshold(summary_opts))
      System.at_exit(fn _ -> exit({:shutdown, 3}) end)
    end

    :ok
  end

  defp gather_coverage(results, keep) do
    keep_set = MapSet.new(keep)

    # When gathering coverage results, we need to skip any
    # entry with line equal to 0 as those are generated code.
    #
    # We may also have multiple entries on the same line.
    # Each line is only considered once.
    #
    # We use ETS for performance, to avoid working with nested maps.
    table = :ets.new(__MODULE__, [:set, :private])

    try do
      for {{module, line}, cov} <- results, module in keep_set, line != 0 do
        case cov do
          {1, 0} -> :ets.insert(table, {{module, line}, true})
          {0, 1} -> :ets.insert_new(table, {{module, line}, false})
        end
      end

      module_results = for module <- keep, do: {read_cover_results(table, module), module}
      {module_results, read_cover_results(table, :_)}
    after
      :ets.delete(table)
    end
  end

  defp read_cover_results(table, module) do
    covered = :ets.select_count(table, [{{{module, :_}, true}, [], [true]}])
    not_covered = :ets.select_count(table, [{{{module, :_}, false}, [], [true]}])
    percentage(covered, not_covered)
  end

  defp percentage(0, 0), do: 100.0
  defp percentage(covered, not_covered), do: covered / (covered + not_covered) * 100

  defp print_summary(results, totals, true), do: print_summary(results, totals, [])

  defp print_summary(results, totals, opts) when is_list(opts) do
    threshold = get_threshold(opts)

    results =
      results |> Enum.sort() |> Enum.map(fn {coverage, module} -> {coverage, inspect(module)} end)

    name_max_length =
      case results do
        [] ->
          10

        _ ->
          results
          |> Enum.map(&(elem(&1, 1) |> String.length()))
          |> Enum.max()
          |> max(10)
      end

    name_separator = String.duplicate("-", name_max_length)

    Mix.shell().info("| Percentage | #{String.pad_trailing("Module", name_max_length)} |")
    Mix.shell().info("|------------|-#{name_separator}-|")
    Enum.each(results, &display(&1, threshold, name_max_length))
    Mix.shell().info("|------------|-#{name_separator}-|")
    display({totals, "Total"}, threshold, name_max_length)
    Mix.shell().info("")
  end

  defp print_failed_threshold(totals, threshold) do
    Mix.shell().info("Coverage test failed, threshold not met:\n")
    Mix.shell().info("    Coverage:  #{format_number(totals, 6)}%")
    Mix.shell().info("    Threshold: #{format_number(threshold, 6)}%")
    Mix.shell().info("")
  end

  defp display({percentage, name}, threshold, pad_length) do
    Mix.shell().info([
      "| ",
      color(percentage, threshold),
      format_number(percentage, 9),
      "%",
      :reset,
      " | ",
      String.pad_trailing(name, pad_length),
      " |"
    ])
  end

  defp color(percentage, true), do: color(percentage, @default_threshold)
  defp color(_, false), do: ""
  defp color(percentage, threshold) when percentage >= threshold, do: :green
  defp color(_, _), do: :red

  defp format_number(number, length) when is_integer(number),
    do: format_number(number / 1, length)

  defp format_number(number, length), do: :io_lib.format("~#{length}.2f", [number])

  defp get_threshold(true), do: @default_threshold
  defp get_threshold(opts), do: Keyword.get(opts, :threshold, @default_threshold)
end
