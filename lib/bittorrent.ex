defmodule Bittorrent.CLI do
  def main(argv) do
    case argv do
      ["decode" | [encoded_str | _]] ->
        {decoded_str, _} = Bencode.decode(encoded_str)
        IO.puts(Jason.encode!(decoded_str))

      [command | _] ->
        IO.puts("Unknown command: #{command}")
        System.halt(1)

      [] ->
        IO.puts("Usage: your_bittorrent.sh <command> <args>")
        System.halt(1)
    end
  end
end

defmodule Bencode do
  def decode(<<"l"::binary, rest::binary>>) do
    decode_list(rest)
  end

  def decode(<<"i"::binary, rest::binary>>) do
    binary_data = :binary.bin_to_list(rest)
    {head, tail} = binary_data |> Enum.split_while(fn char -> char != ?e end)

    {decoded, _} = head |> List.to_string() |> Integer.parse()

    rest =
      tail |> Enum.slice(1..-1) |> List.to_string()

    {decoded, rest}
  end

  def decode(encoded_value) when is_binary(encoded_value) do
    binary_data = :binary.bin_to_list(encoded_value)
    {head, tail} = binary_data |> Enum.split_while(fn char -> char != ?: end)

    {size, _} = head |> List.to_string() |> Integer.parse()

    decoded =
      tail
      |> Enum.slice(1..size)
      |> List.to_string()

    rest =
      tail |> Enum.slice((size + 1)..length(tail)) |> List.to_string()

    {decoded, rest}
  end

  def decode(_), do: "Invalid encoded value: not binary"

  # DECODE COLLECTIONS
  defp decode_list(encoded_items, result \\ [])

  defp decode_list(<<"e"::binary, rest::binary>>, result),
    do: {result |> Enum.reverse(), rest}

  defp decode_list(encoded_items, result) do
    {decoded_item, rest} = decode(encoded_items)
    decode_list(rest, [decoded_item | result])
  end
end
