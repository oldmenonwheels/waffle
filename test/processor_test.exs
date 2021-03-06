defmodule WaffleTest.Processor do
  use ExUnit.Case, async: false
  @img "test/support/image.png"
  @img2 "test/support/image two.png"

  defmodule DummyDefinition do
    use Waffle.Actions.Store
    use Waffle.Definition.Storage

    def validate({file, _}), do: String.ends_with?(file.file_name, ".png")
    def transform(:original, _), do: :noaction
    def transform(:thumb, _), do: {:convert, "-strip -thumbnail 10x10"}

    def transform(:med, _),
      do: {:convert, fn input, output -> " #{input} -strip -thumbnail 10x10 #{output}" end, :jpg}

    def transform(:small, _),
      do:
        {:convert, fn input, output -> [input, "-strip", "-thumbnail", "10x10", output] end, :jpg}

    def transform(:new_format, _), do: {:convert, "-quality 40", :webp}

    def transform(:skipped, _), do: :skip

    def __versions, do: [:original, :thumb]
  end

  defmodule BrokenDefinition do
    use Waffle.Actions.Store
    use Waffle.Definition.Storage

    def validate({file, _}), do: String.ends_with?(file.file_name, ".png")
    def transform(:original, _), do: :noaction
    def transform(:thumb, _), do: {:convert, "-strip -invalidTransformation 10x10"}
    def __versions, do: [:original, :thumb]
  end

  defmodule MissingExecutableDefinition do
    use Waffle.Definition

    def transform(:original, _), do: {:blah, ""}
  end

  test "returns the original path for :noaction transformations" do
    {:ok, file} =
      Waffle.Processor.process(DummyDefinition, :original, {Waffle.File.new(@img), nil})

    assert file.path == @img
  end

  test "returns nil for :skip transformations" do
    assert {:ok, nil} =
             Waffle.Processor.process(DummyDefinition, :skipped, {Waffle.File.new(@img), nil})
  end

  test "transforms a copied version of file according to the specified transformation" do
    {:ok, new_file} =
      Waffle.Processor.process(DummyDefinition, :thumb, {Waffle.File.new(@img), nil})

    assert new_file.path != @img
    # original file untouched
    assert "128x128" == geometry(@img)
    assert "10x10" == geometry(new_file.path)
    cleanup(new_file.path)
  end

  test "transforms a copied version of file according to a function transformation that returns a string" do
    {:ok, new_file} =
      Waffle.Processor.process(DummyDefinition, :med, {Waffle.File.new(@img), nil})

    assert new_file.path != @img
    # original file untouched
    assert "128x128" == geometry(@img)
    assert "10x10" == geometry(new_file.path)
    cleanup(new_file.path)
  end

  test "transforms a copied version of file according to a function transformation that returns a list" do
    {:ok, new_file} =
      Waffle.Processor.process(DummyDefinition, :small, {Waffle.File.new(@img), nil})

    assert new_file.path != @img
    # original file untouched
    assert "128x128" == geometry(@img)
    assert "10x10" == geometry(new_file.path)
    cleanup(new_file.path)
  end

  test "transforms a file given as a binary" do
    img_binary = File.read!(@img)

    {:ok, new_file} =
      Waffle.Processor.process(
        DummyDefinition,
        :small,
        {Waffle.File.new(%{binary: img_binary, filename: "image.png"}), nil}
      )

    assert new_file.path != @img
    # original file untouched
    assert "128x128" == geometry(@img)
    assert "10x10" == geometry(new_file.path)
    cleanup(new_file.path)
  end

  test "file names with spaces" do
    {:ok, new_file} =
      Waffle.Processor.process(DummyDefinition, :thumb, {Waffle.File.new(@img2), nil})

    assert new_file.path != @img2
    # original file untouched
    assert "128x128" == geometry(@img2)
    assert "10x10" == geometry(new_file.path)
    cleanup(new_file.path)
  end

  test "converts file to correct format" do
    {:ok, new_file} =
      Waffle.Processor.process(DummyDefinition, :new_format, {Waffle.File.new(@img), nil})

    # new tmp file has correct extension
    assert Path.extname(new_file.path) == ".webp"

    cleanup(new_file.path)
  end

  test "converts file to correct format via function transfomations" do
    {:ok, new_file} =
      Waffle.Processor.process(DummyDefinition, :small, {Waffle.File.new(@img), nil})

    # new tmp file has correct extension
    assert Path.extname(new_file.path) == ".jpg"

    cleanup(new_file.path)
  end

  test "returns tuple in an invalid transformation" do
    assert {:error, _} =
             Waffle.Processor.process(BrokenDefinition, :thumb, {Waffle.File.new(@img), nil})
  end

  test "raises an error if the given transformation executable cannot be found" do
    assert_raise Waffle.MissingExecutableError, ~r"blah", fn ->
      Waffle.Processor.process(
        MissingExecutableDefinition,
        :original,
        {Waffle.File.new(@img), nil}
      )
    end
  end

  defp geometry(path) do
    {identify, 0} = System.cmd("identify", ["-verbose", path], stderr_to_stdout: true)
    Enum.at(Regex.run(~r/Geometry: ([^+]*)/, identify), 1)
  end

  defp cleanup(path) do
    File.rm(path)
  end
end
