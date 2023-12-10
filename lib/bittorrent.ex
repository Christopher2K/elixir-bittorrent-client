defmodule Bittorrent.CLI do
  def main(argv) do
    case argv do
      ["decode" | [encoded_str | _]] ->
        {decoded_str, _} = Bencode.decode(encoded_str)
        IO.puts(Jason.encode!(decoded_str))

      ["info" | [filename | _]] ->
        binary = filename |> File.read!() |> IO.iodata_to_binary()
        {decoded_str, _} = Bencode.decode(binary)
        data = Jason.encode!(decoded_str) |> Jason.decode!()

        info_map = data["info"]
        bencoded_info_map = Bencode.encode(info_map)

        hex_digest =
          :crypto.hash(:sha, <<bencoded_info_map::binary>>)
          |> Base.encode16(case: :lower)

        piece_length = data["info"]["piece length"]

        IO.puts("Tracker URL: #{data["announce"]}")
        IO.puts("Length: #{data["info"]["length"]}")
        IO.puts("Info Hash: #{hex_digest}")
        IO.puts("Piece Length: #{piece_length}")
        IO.puts("Piece Hashes:")
        piece_hashes = data["info"]["pieces"] |> Bittorrent.Utils.get_piece_hashes()

        for hash <- piece_hashes do
          IO.puts(hash)
        end

      [command | _] ->
        IO.puts("Unknown command: #{command}")
        System.halt(1)

      [] ->
        IO.puts("Usage: your_bittorrent.sh <command> <args>")
        System.halt(1)
    end
  end
end

defmodule Bittorrent.Utils do
  def get_piece_hashes(pieces) do
    {:ok, binary} = pieces |> Base.decode16(case: :lower)
    do_get_piece_hashes(binary)
  end

  defp do_get_piece_hashes(pieces, result \\ [])
  defp do_get_piece_hashes(<<>>, result), do: Enum.reverse(result)

  defp do_get_piece_hashes(pieces, result) do
    <<piece::binary-size(20), rest::binary>> = pieces
    encoded_piece = piece |> Base.encode16(case: :lower)
    do_get_piece_hashes(rest, [encoded_piece | result])
  end
end

defmodule Bencode do
  @doc """
  Bencode a map, a list, a number or a string
  This function returns a binary since nothing guarantees that the context will be UTF-8 friendly
  For strings, it does accept UTF-8 string or Hex representation for non UTF-8 chars
  """
  def encode(map) when is_map(map) do
    encoded_map_entries =
      map
      |> Enum.flat_map(fn {k, v} -> [encode(k), encode(v)] end)
      |> Enum.reduce(<<>>, fn item, acc -> <<acc::binary, item::binary>> end)

    <<"d"::binary, encoded_map_entries::binary, "e"::binary>>
  end

  def encode(list) when is_list(list) do
    encoded_list_items = list |> Enum.map(&encode/1) |> Enum.join()
    <<"l"::binary, encoded_list_items::binary, "e"::binary>>
  end

  def encode(data) when is_integer(data),
    do: <<"i"::binary, "#{Integer.to_string(data)}"::binary, "e"::binary>>

  def encode(data) when is_binary(data) do
    case Base.decode16(data, case: :lower) do
      {:ok, binary} ->
        size = Integer.floor_div(String.length(data), 2)
        <<"#{size}:"::binary, binary::binary>>

      :error ->
        <<"#{String.length(data)}:#{data}"::binary>>
    end
  end

  ## DECODE
  def decode(<<"d"::binary, rest::binary>>) do
    decode_object(rest)
  end

  def decode(<<"l"::binary, rest::binary>>), do: decode_list(rest)

  def decode(<<"i"::binary, rest::binary>>) do
    binary_data = :binary.bin_to_list(rest)
    {head, tail} = binary_data |> Enum.split_while(fn char -> char != ?e end)

    {decoded, _} = head |> List.to_string() |> Integer.parse()

    rest =
      tail |> Enum.slice(1..-1) |> :binary.list_to_bin()

    {decoded, rest}
  end

  def decode(encoded_value) when is_binary(encoded_value) do
    binary_data = :binary.bin_to_list(encoded_value)
    {head, tail} = binary_data |> Enum.split_while(fn char -> char != ?: end)

    {size, _} = head |> List.to_string() |> Integer.parse()

    decoded_bin =
      tail
      |> Enum.slice(1..size)
      |> :binary.list_to_bin()

    case String.valid?(decoded_bin) do
      true ->
        decoded = decoded_bin

        rest =
          tail |> Enum.slice((size + 1)..length(tail)) |> :binary.list_to_bin()

        {decoded, rest}

      false ->
        # Non UTF-8 values are converted to Base16 so we can count how many char
        # we have to skip
        base16_tail = tail |> :binary.list_to_bin() |> Base.encode16(case: :lower)
        # Since this is hex, size of 1 = 2bytes
        decoded = base16_tail |> String.slice(2..(size * 2 + 1))
        rest = base16_tail |> String.slice((size * 2 + 2)..-1) |> Base.decode16!(case: :lower)
        {decoded, rest}
    end
  end

  def decode(_), do: {"Invalid encoded value: not binary", ""}

  # DECODE COLLECTIONS
  defp decode_list(encoded_items, result \\ [])

  defp decode_list(<<"e"::binary, rest::binary>>, result),
    do: {result |> Enum.reverse(), rest}

  defp decode_list(encoded_items, result) do
    {decoded_item, rest} = decode(encoded_items)
    decode_list(rest, [decoded_item | result])
  end

  defp decode_object(encoded_items, key \\ nil, result \\ %{})

  defp decode_object(<<"e"::binary, rest::binary>>, nil, result), do: {result, rest}

  defp decode_object(encoded_items, nil, result) do
    {decoded_key, rest} = decode(encoded_items)
    decode_object(rest, decoded_key, result)
  end

  defp decode_object(encoded_items, key, result) do
    {decoded_value, rest} = decode(encoded_items)
    decode_object(rest, nil, Map.put(result, key, decoded_value))
  end
end
